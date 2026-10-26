# An agent's host: a process of its own that owns the agent's Claude Code, so the agent outlives
# the daemon (a restart to take a change stops no agent). It appends to the agent's log what Claude
# Code writes and the messages it is sent, writes the inbox's new lines to Claude Code's stdin,
# keeps its usage in a file, and ends with it; a kill file stops it. The daemon only reads and
# writes these files, and a new daemon finds the host still at work.

import fs
import win

# how the host starts its Claude Code, written by the daemon for the host to read
pub type HostStart:
	cmd str
	workDir str
	memoryCap i64
	cpuCap f64

# the file of the agent's with this ending: log (jsonl), inbox, start, pid, usage, kill, ended
pub fn hostFile(dir str, id str, ending str) str:
	"{dir}/{id}.{ending}"

# what the text holds up to its last line break appended to the log, a value a line; the rest,
# a line not yet ended
fn logged(text str, log str) str:
	cut = text.lastIndexOf("\n") ?? return text.copy()
	for line in text[..cut].lines():
		for value in jsonValues(line):
			_ = fs.appendFile(log, "{value}\n")
	text[cut + 1..].copy()

# runs the agent's Claude Code until it ends or a kill file comes
pub fn runHost(dir str, id str):
	text = fs.readFile(hostFile(dir, id, "start")) ?? exit(1, "no start for {id}")
	start = HostStart.fromJson(text) ?? exit(1, "a broken start for {id}")
	log = hostFile(dir, id, "jsonl")
	inbox = hostFile(dir, id, "inbox")
	process = win.startPiped(start.cmd, start.workDir, start.memoryCap, start.cpuCap) ??
		exit(1, "Claude Code could not start: system error {error.code}")
	_ = fs.deleteFile(hostFile(dir, id, "ended"))
	_ = fs.writeFile(hostFile(dir, id, "pid"), "{processId()}")
	sent = 0
	partial = ""
	usedAt = 0
	loop:
		got = process.read()
		if not got.isEmpty: partial = logged("{partial}{str(got)}", log)
		asked = fs.readFile(inbox) ?? ""
		if asked.len > sent:
			lines = asked[sent..].copy()
			_ = fs.appendFile(log, lines)
			_ = process.write(lines.bytes())
			sent = asked.len
		if fs.exists(hostFile(dir, id, "kill")): break
		if clockMs() - usedAt > 3_000:
			usedAt = clockMs()
			cpu, memory = process.usage()
			_ = fs.writeFile(hostFile(dir, id, "usage"), "{cpu} {memory}")
		if process.hasEnded():
			_ = logged("{partial}{str(process.read())}\n", log)
			break
		sleepMs(20)
	process.close()
	_ = fs.deleteFile(hostFile(dir, id, "kill"))
	_ = fs.deleteFile(hostFile(dir, id, "pid"))
	_ = fs.writeFile(hostFile(dir, id, "ended"), "{process.code}")
