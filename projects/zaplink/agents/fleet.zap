# The daemon's agents: started under one limit for the machine (its own agents and the Claude
# Code sessions opened by hand count alike) and while the plan's window has room, what they write
# read as it comes into their logs and steps, messages sent to them, and the queue of those asked
# that wait for a place.

import cards
import fs
import win

# an agent's process, with what it wrote that does not end a line yet
type Run:
	id str
	process win.Piped
	partial str

pub type Fleet:
	dir str   # the state dir's agents/: agents.json and each agent's log
	limit i64
	planCeiling f64   # no agent starts once the plan's window is used past this share
	agents Agent[]
	runs Run[]
	steps {str: Step[]}   # each agent's steps, read from its log
	planUse f64 = -1.0
	planWindow str = ""
	changed bool = true   # what the page shows changed since it was last made

	fn save():
		_ = fs.createDir(dir)
		_ = fs.writeFile("{dir}/agents.json", agents.toJson())

	fn logOf(id str):
		"{dir}/{id}.jsonl"

	# an agent asked for: queued, started when a place frees; its id
	fn ask(name str, workDir str, model str, prompt str, card str):
		id = newSessionId()
		agents.push(
			Agent(
				id = id.copy(),
				name = name.copy(),
				dir = workDir.copy(),
				model = model.copy(),
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

	# a message of the user to the agent: shown and kept in its log
	mut fn said(id str, text str):
		self.note(id, Step(kind = "you", title = "", text = text.copy()))
		_ = fs.appendFile(self.logOf(id), userLine(text))

	# the step added to the agent's steps, and the page told
	fn note(id str, step Step):
		if id not in steps: steps[id.copy()] = []
		steps[id].push(step.copy())
		changed = true

	# the agent's process started: its session made, or taken up again
	fn start(k i64):
		a = agents[k]
		match win.startPiped(a.commandOf(), a.dir):
			process:
				first = a.waiting if a.started else a.prompt
				if first != "":
					process.write(userLine(first).bytes())
					self.said(a.id, first)
				self.note(
					a.id,
					Step(kind = "note", title = "started", text = "{a.model} in {a.dir}")
				)
				runs.push(Run(id = a.id.copy(), process, partial = ""))
				agents[k].state = .Working if first != "" else .Idle
				agents[k].started = true
				agents[k].waiting = ""
			error:
				agents[k].state = .Stopped
				self.note(
					a.id,
					Step(
						kind = "note",
						title = "could not start",
						text = "system error {error.code}"
					)
				)
		self.save()
		changed = true

	# a message sent to the agent; a stopped one is queued to start again and gets it then
	fn message(id str, text str):
		k = self.find(id) ?? return
		if self.runOf(id) is r:
			self.said(id, text)
			runs[r].process.write(userLine(text).bytes())
			agents[k].state = .Working
		else:
			agents[k].waiting = text.copy()
			agents[k].state = .Queued
		self.save()

	# the agent stopped, its process and what it started ended; resumable
	fn kill(id str):
		if self.runOf(id) is r:
			runs[r].process.close()
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
	fn working():
		ours = agents.filter(.isRunning()).len
		ours + cards.sessionsRunning().filter(self.find(.sessionId) == none).len

	# what every running agent wrote, read; the ended ones stopped; the queued ones started while
	# there is room; whether anything changed
	fn pump():
		r = 0
		while r < runs.len:
			self.readRun(r)
			if runs[r].process.hasEnded() and runs[r].process.read(1).isEmpty:
				if self.find(runs[r].id) is k: agents[k].state = .Stopped
				runs.remove(r)
				changed = true
				self.save()
			else:
				r += 1
		self.schedule()

	fn readRun(r i64):
		got = runs[r].process.read()
		if got.isEmpty: return
		text = "{runs[r].partial}{str(got)}"
		lines = text.lines()
		runs[r].partial = lines[len - 1].copy()
		id = runs[r].id.copy()
		for line in lines[..lines.len - 1]:
			if line.trimmed().isEmpty: continue
			_ = fs.appendFile(self.logOf(id), "{line}\n")
			self.take(id, line)

	# a line of the agent's stream: its steps kept, the turn's end and the plan's use noted
	fn take(id str, line str):
		read = readLine(line)
		for step in read.steps:
			self.note(id, step)
		if read.planUse >= 0.0:
			planUse = read.planUse
			planWindow = read.planWindow.copy()
		if read.turnEnded and self.find(id) is k:
			agents[k].state = .Idle
			agents[k].cost += read.cost
			agents[k].turns += 1
			self.save()
			changed = true

	# the queued agents started, oldest first, while the machine and the plan have room
	mut fn schedule():
		while self.working() < limit and planUse < planCeiling:
			next = -1
			for k, a in agents:
				if a.state == .Queued and (next == -1 or a.asked < agents[next].asked): next = k
			if next == -1: return
			self.start(next)

# the fleet kept in the dir: its agents and their steps read again; those that were running when
# the daemon stopped are queued to go on from their sessions
pub fn loadFleet(dir str, limit i64, planCeiling f64) Fleet:
	fleet = Fleet(dir = dir.copy(), limit, planCeiling, agents = [], runs = [], steps = {})
	text = fs.readFile("{dir}/agents.json") ?? return fleet
	fleet.agents = Agent[].fromJson(text) ?? []
	for k in 0..fleet.agents.len:
		if fleet.agents[k].isRunning(): fleet.agents[k].state = .Queued
		id = fleet.agents[k].id.copy()
		read = []
		for line in (fs.readFile(fleet.logOf(id)) ?? "").lines():
			read.extend(readLine(line).steps)
		fleet.steps[id] = read
	fleet
