# The daemon's agents: started under one limit for the machine (its own agents and the Claude
# Code sessions opened by hand count alike) and while the plan's window has room, what they write
# read as it comes into their logs and steps, messages sent to them, and the queue of those asked
# that wait for a place.

import cards
import fs
import win

# an agent at work in its host: how far its log is read, and what does not end a line yet
type Run:
	id str
	offset i64
	partial str
	at i64 = 0   # when its host was started, unix seconds; 0 for a host found running

pub type Fleet:
	dir str   # the state dir's agents/: agents.json and each agent's log
	settings Settings
	agents Agent[]
	runs Run[]
	steps {str: Step[]}   # each agent's steps, read from its log
	windows {str: Window} = {}   # the plan's windows, by name (five_hour, seven_day)
	machine Machine = Machine()
	changed bool = true   # what the page shows changed since it was last made
	repo str = ""   # the main checkout, lower case with slashes: the windows on it count as work
	home str = ""   # the main checkout as given: where the hosts are started from
	loops Loop[] = []
	goals Goal[] = []
	checking CheckRun[] = []   # the goals' checks running now
	tasks {str: str[]} = {}   # each agent's tasks still running (commands in the background, subagents)

	fn save():
		_ = fs.createDir(dir)
		_ = fs.writeFile("{dir}/agents.json", agents.toJson())

	fn savePlans():
		_ = fs.createDir(dir)
		_ = fs.writeFile("{dir}/loops.json", loops.toJson())
		_ = fs.writeFile("{dir}/goals.json", goals.toJson())
		changed = true

	fn logOf(id str):
		"{dir}/{id}.jsonl"

	# an agent asked for: queued, started when a place frees; its id
	# a Claude Code session opened by hand taken over: its conversation goes on as an agent of the
	# fleet, under the session's name, its model and effort its own
	fn adopt(id str, name str, workDir str):
		if self.find(id) != none: return
		agents.push(
			Agent(
				id = id.copy(),
				name = name.copy(),
				dir = workDir.copy(),
				model = "",
				prompt = "",
				asked = unixSeconds(),
				started = true
			)
		)
		steps[id.copy()] = [Step(kind = "note", title = "taken over", text = "the session {name}, opened by hand")]
		self.save()
		changed = true

	# the next name for an agent of the model: opus-3
	fn nextName(model str):
		prefix = "{model}-"
		most = 0
		for a in agents:
			if a.name.startsWith(prefix): most = most.max(i64.parse(a.name[prefix.len..]) ?? 0)
		"{prefix}{most + 1}"

	fn ask(workDir str, model str, effort str, prompt str, card str, role str):
		id = newSessionId()
		name = self.nextName(model)
		agents.push(
			Agent(
				id = id.copy(),
				name,
				dir = workDir.copy(),
				model = model.copy(),
				effort = effort.copy(),
				role = role.copy(),
				prompt = prompt.copy(),
				card = card.copy(),
				asked = unixSeconds()
			)
		)
		steps[id.copy()] = []
		self.save()
		changed = true
		id

	fn find(id str) i64?:
		for k, a in agents:
			if a.id == id: return k
		none

	fn runOf(id str) i64?:
		for k, r in runs:
			if r.id == id: return k
		none

	# a message of the user to the agent: put in its inbox, which its host sends on and logs
	fn said(id str, text str):
		_ = fs.appendFile(hostFile(dir, id, "inbox"), userLine(text))

	# whether the agent wrote text since the user's last message
	fn saidSince(id str):
		all = steps.get(id) ?? return false
		for k in 0..all.len:
			kind = all[all.len - 1 - k].kind
			if kind == "text": return true
			if kind == "you": return false
		false

	# the step added to the agent's steps, and the page told
	fn note(id str, step Step):
		if id not in steps: steps[id.copy()] = []
		steps[id].push(step.copy())
		changed = true

	# the agent's host started, which starts its Claude Code (its session made, or taken up again)
	# and outlives the daemon
	fn start(k i64):
		a = agents[k]
		gb = 1_073_741_824.0
		begin = HostStart(cmd = a.commandOf(), workDir = a.dir.copy(), memoryCap = i64(settings.agentMemory * gb), cpuCap = settings.agentCpu)
		_ = fs.writeFile(hostFile(dir, a.id, "start"), begin.toJson())
		_ = fs.writeFile(hostFile(dir, a.id, "inbox"), "")
		_ = fs.deleteFile(hostFile(dir, a.id, "kill"))
		_ = fs.deleteFile(hostFile(dir, a.id, "pid"))
		first = a.waiting if a.started else a.prompt
		if first != "": self.said(a.id, first)
		# the host built once by the daemon at its start: hosts started together never build it at once
		host = "\"{home}/build/zaplinkhost.exe\" {a.id}"
		match win.startDetached(host, home):
			_:
				size = sizeOf(self.logOf(a.id))
				runs.push(Run(id = a.id.copy(), offset = size, partial = "", at = unixSeconds()))
				self.note(a.id, Step(kind = "note", title = "started", text = "{a.model} in {a.dir}"))
				agents[k].state = .Working if first != "" else .Idle
				agents[k].turnStart = unixSeconds() if first != "" else 0
				agents[k].turnTokens = 0
				agents[k].waiting = ""
				agents[k].startHead = headOf(a.dir)
			error:
				agents[k].state = .Stopped
				self.note(a.id, Step(kind = "note", title = "could not start", text = "system error {error.code}"))
		self.save()
		changed = true

	# a message sent to the agent; a stopped one is queued to start again and gets it then
	fn message(id str, text str):
		k = self.find(id) ?? return
		if self.runOf(id) != none:
			self.said(id, text)
			agents[k].state = .Working
			agents[k].turnStart = unixSeconds()
			agents[k].turnTokens = 0
		else:
			agents[k].waiting = text.copy()
			agents[k].state = .Queued
		self.save()

	# the agent stopped, its process and what it started ended; resumable
	fn kill(id str):
		if self.runOf(id) is r:
			_ = fs.writeFile(hostFile(dir, id, "kill"), "")
			runs.remove(r)
		if self.find(id) is k: agents[k].state = .Stopped
		self.save()
		changed = true

	# a stopped agent queued to start again from its session
	fn resume(id str):
		k = self.find(id) ?? return
		if agents[k].state == .Stopped: agents[k].state = .Queued
		self.save()
		changed = true

	# the agents running now, the daemon's and the sessions opened by hand
	# the agents at work now: the daemon's in a turn, and the windows opened by hand on this
	# repository that are busy (an idle agent or window spends no tokens)
	fn working():
		ours = agents.filter(.state == .Working).len
		by = cards.sessionsRunning().filter(
			self.find(.sessionId) == none and .status == "busy" and .cwd.lower().replace("\\", "/").startsWith(repo.lower())
		)
		ours + by.len


	# what every running agent wrote, read; the ended ones stopped; the queued ones started while
	# there is room; whether anything changed
	fn pump():
		r = 0
		while r < runs.len:
			self.readRun(r)
			if fs.exists(hostFile(dir, runs[r].id, "ended")):
				if self.find(runs[r].id) is k: agents[k].state = .Stopped
				runs.remove(r)
				changed = true
				self.save()
			elif not self.hostAlive(r):
				# a host gone without its end (killed, its window closed): started again, a turn it cut
				# short told to go on
				if self.find(runs[r].id) is k:
					if agents[k].state == .Working and agents[k].waiting == "":
						agents[k].waiting = "Your host stopped during your turn; go on from where you were."
					agents[k].state = .Queued
				runs.remove(r)
				changed = true
				self.save()
			else:
				r += 1
		self.schedule()

	# whether the agent's host runs: its pid's process alive (a host just started counts until it
	# writes its pid)
	fn hostAlive(r i64):
		# a host that wrote no pid a minute after its start never ran
		young = runs[r].at == 0 or unixSeconds() - runs[r].at < 60
		text = fs.readFile(hostFile(dir, runs[r].id, "pid")) ?? return young
		pid = i64.parse(text.trimmed()) ?? return young
		win.processAlive(pid)

	# what the agent's host logged since the last read
	fn readRun(r i64):
		file = fs.open(self.logOf(runs[r].id)) ?? return
		size = file.len
		if size <= runs[r].offset: return
		got = file.readAt(runs[r].offset, size - runs[r].offset) ?? return
		runs[r].offset = size
		text = "{runs[r].partial}{str(got)}"
		# what follows the last line break is a line not yet ended
		cut = text.lastIndexOf("\n") ?? -1
		runs[r].partial = text[cut + 1..].copy()
		if cut < 0: return
		id = runs[r].id.copy()
		for line in text[..cut].lines():
			for value in jsonValues(line):
				self.take(id, value)

	# a line of the agent's stream: its steps kept, the turn's end and the plan's use noted
	fn take(id str, line str):
		read = readLine(line)
		if self.find(id) is a and read.tokens > 0:
			agents[a].turnTokens = agents[a].turnTokens.max(read.tokens)
			changed = true
		if read.turnEnded and read.answer != "" and not self.saidSince(id):
			self.note(id, Step(kind = "text", title = "", text = read.answer.copy()))
		for step in read.steps:
			self.note(id, step)
		if read.planUse >= 0.0:
			before = windows.get(read.planWindow) ?? Window(use = 0.0, resetsAt = 0)
			windows[read.planWindow.copy()] = before.readAgain(read.planUse, read.resetsAt, unixSeconds())
			changed = true
		for plan in read.plans:
			before = windows.get(plan.window) ?? Window(use = 0.0, resetsAt = 0)
			windows[plan.window.copy()] = before.readAgain(plan.use, plan.resetsAt, unixSeconds())
			changed = true
		self.noteTask(id, read)
		if read.began and self.find(id) is k: agents[k].started = true
		# a session to resume that does not exist (its first run never began): the next start makes it
		# anew from the prompt (its card's next agent, or a resume)
		if read.resumeFailed and self.find(id) is k and agents[k].turns == 0:
			agents[k].started = false
			self.note(id, Step(kind = "note", title = "no session to resume", text = "its next start begins from its prompt"))
		if read.turnEnded and self.find(id) is k:
			# a turn that left a task running goes on by itself when the task ends
			agents[k].state = .Working if self.hasTasks(id) else .Idle
			agents[k].turnStart = 0
			agents[k].idleSince = unixSeconds()
			agents[k].cost += read.cost
			agents[k].turns += 1
			self.save()
			changed = true

	# the agent of a worktree: the last one that worked in it, else the session named by (a card's
	# `by`) when the fleet has it, else ""
	fn agentOf(tree str, by str):
		for k in 0..agents.len:
			a = agents[agents.len - 1 - k]
			if a.dir == tree: return a.id.copy()
		if self.find(by) != none: return by.copy()
		""

	# whether the agent has a task still running
	fn hasTasks(id str):
		id in tasks and not tasks[id].isEmpty

	# a task's start or end the line tells, kept; a host's start forgets the tasks before it
	fn noteTask(id str, read Read):
		if read.hostStarted or id not in tasks: tasks[id.copy()] = []
		# the list Claude Code gives is the truth (a task stopped tells no end of its own)
		if read.listed: tasks[id.copy()] = read.tasks.copy()
		if read.taskStarted != "": tasks[id].push(read.taskStarted.copy())
		if read.taskEnded != "": tasks[id.copy()] = tasks[id].filter(it != read.taskEnded)

	# why no agent may start now ("" when one may): the machine's limit, the plan's pace or ceiling,
	# the processors or the memory
	fn whyWait():
		if self.working() >= settings.limit: return "{settings.limit} agents at work"
		now = unixSeconds()
		for name in windows.keys():
			w = windows[name]
			cap = w.allowed(name, settings.pace, now).min(settings.planCeiling)
			if w.use >= cap: return "the plan's {name} window at {w.use * 100.0:.0}%, {cap * 100.0:.0}% allowed now"
		if machine.cpu > settings.cpuCeiling: return "processors {machine.cpu * 100.0:.0}% busy"
		freeGb = machine.memory.free / 1_073_741_824.0
		if machine.memory.total > 0 and freeGb < settings.memoryFloor: return "{freeGb:.1} GB free"
		""

	# each running agent's processor seconds and most memory held, by id
	fn usage():
		out {str: (f64, i64)} = {}
		for r in runs:
			words = (fs.readFile(hostFile(dir, r.id, "usage")) ?? "").words()
			if words.len == 2: out[r.id.copy()] = (f64.parse(words[0]) ?? 0.0, i64.parse(words[1]) ?? 0)
		out

	# the queued agents started, oldest first, while the machine and the plan have room
	mut fn schedule():
		# an agent queued with nothing to say starts idle and spends nothing, so it waits for no room
		idle = []
		for k, a in agents:
			if a.state == .Queued and a.started and a.waiting == "": idle.push(k)
		for k in idle:
			self.start(k)
		while self.whyWait() == "":
			next = -1
			for k, a in agents:
				if a.state == .Queued and (next == -1 or a.asked < agents[next].asked): next = k
			if next == -1: return
			self.start(next)

# the commit a worktree is at, "" when it is gone
pub fn headOf(tree str) str:
	if not fs.exists(tree): return ""
	ran = Process.output(["git", "-C", tree.copy(), "rev-parse", "HEAD"])
	ran.out.trimmed().copy() if ran.code == 0 else ""

# a file's size in bytes, 0 when there is none
fn sizeOf(path str):
	match fs.open(path):
		file: file.len
		error: 0

# the fleet kept in the dir: its agents and their steps read again; those that were running when
# the daemon stopped are queued to go on from their sessions
pub fn loadFleet(dir str, settings Settings) Fleet:
	fleet = Fleet(dir = dir.copy(), settings = settings.copy(), agents = [], runs = [], steps = {})
	loops, goals = loadPlans(dir)
	fleet.loops = loops
	fleet.goals = goals
	text = fs.readFile("{dir}/agents.json") ?? return fleet
	fleet.agents = agentsOf(text)
	for k in 0..fleet.agents.len:
		# an agent whose host still runs goes on as it was: the new daemon reads its log from here
		pid = i64.parse((fs.readFile(hostFile(dir, fleet.agents[k].id, "pid")) ?? "").trimmed()) ?? 0
		if fleet.agents[k].isRunning() and pid > 0 and win.processAlive(pid):
			size = sizeOf(fleet.logOf(fleet.agents[k].id))
			fleet.runs.push(Run(id = fleet.agents[k].id.copy(), offset = size, partial = ""))
		# a turn the daemon's stop cut short goes on: the agent is told so as it starts again
		elif fleet.agents[k].state == .Working and fleet.agents[k].waiting == "":
			fleet.agents[k].waiting = "zaplinkd restarted during your turn and stopped it; go on from where you were."
		if fleet.agents[k].isRunning() and fleet.runOf(fleet.agents[k].id) == none:
			fleet.agents[k].state = .Queued
		id = fleet.agents[k].id.copy()
		fleet.steps[id.copy()] = []
		# whether the log's last turn ended after the last message sent: what a host picked up again
		# is doing is read from its log, not from the state saved before
		ended = false
		for value in jsonValues(fs.readFile(fleet.logOf(id)) ?? ""):
			got = readLine(value)
			if got.turnEnded and got.answer != "" and not fleet.saidSince(id):
				fleet.steps[id].push(Step(kind = "text", title = "", text = got.answer.copy()))
			fleet.noteTask(id, got)
			for plan in got.plans:
				before = fleet.windows.get(plan.window) ?? Window(use = 0.0, resetsAt = 0)
				fleet.windows[plan.window.copy()] = before.readAgain(plan.use, plan.resetsAt, unixSeconds())
			if got.turnEnded: ended = true
			if got.steps.any(.kind == "you"): ended = false
			fleet.steps[id].extend(got.steps)
		if fleet.runOf(id) != none:
			fleet.agents[k].state = .Idle if ended and not fleet.hasTasks(id) else .Working
			if fleet.agents[k].state == .Working and fleet.agents[k].turnStart == 0: fleet.agents[k].turnStart = unixSeconds()
			if fleet.agents[k].state == .Idle and fleet.agents[k].idleSince == 0: fleet.agents[k].idleSince = unixSeconds()
	fleet
