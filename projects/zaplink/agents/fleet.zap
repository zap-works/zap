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
	settings Settings
	agents Agent[]
	runs Run[]
	steps {str: Step[]}   # each agent's steps, read from its log
	windows {str: Window} = {}   # the plan's windows, by name (five_hour, seven_day)
	machine Machine = Machine()
	changed bool = true   # what the page shows changed since it was last made
	repo str = ""   # the main checkout, lower case with slashes: the windows on it count as work
	loops Loop[] = []
	goals Goal[] = []
	checking CheckRun[] = []   # the goals' checks running now

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

	# a message of the user to the agent: shown and kept in its log
	mut fn said(id str, text str):
		self.note(id, Step(kind = "you", title = "", text = text.copy()))
		_ = fs.appendFile(self.logOf(id), userLine(text))

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

	# the agent's process started: its session made, or taken up again
	fn start(k i64):
		a = agents[k]
		gb = 1_073_741_824.0
		match win.startPiped(a.commandOf(), a.dir, i64(settings.agentMemory * gb), settings.agentCpu):
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
				agents[k].turnStart = unixSeconds() if first != "" else 0
				agents[k].turnTokens = 0
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
			agents[k].turnStart = unixSeconds()
			agents[k].turnTokens = 0
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
		# what follows the last line break is a line not yet ended
		cut = text.lastIndexOf("\n") ?? -1
		runs[r].partial = text[cut + 1..].copy()
		if cut < 0: return
		id = runs[r].id.copy()
		for line in text[..cut].lines():
			for value in jsonValues(line):
				_ = fs.appendFile(self.logOf(id), "{value}\n")
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
		if read.turnEnded and self.find(id) is k:
			agents[k].state = .Idle
			agents[k].turnStart = 0
			agents[k].cost += read.cost
			agents[k].turns += 1
			self.save()
			changed = true

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
			out[r.id.copy()] = r.process.usage()
		out

	# the queued agents started, oldest first, while the machine and the plan have room
	mut fn schedule():
		while self.whyWait() == "":
			next = -1
			for k, a in agents:
				if a.state == .Queued and (next == -1 or a.asked < agents[next].asked): next = k
			if next == -1: return
			self.start(next)

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
		# a turn the daemon's stop cut short goes on: the agent is told so as it starts again
		if fleet.agents[k].state == .Working and fleet.agents[k].waiting == "":
			fleet.agents[k].waiting = "zaplinkd restarted during your turn and stopped it; go on from where you were."
		if fleet.agents[k].isRunning(): fleet.agents[k].state = .Queued
		id = fleet.agents[k].id.copy()
		fleet.steps[id.copy()] = []
		for value in jsonValues(fs.readFile(fleet.logOf(id)) ?? ""):
			got = readLine(value)
			if got.turnEnded and got.answer != "" and not fleet.saidSince(id):
				fleet.steps[id].push(Step(kind = "text", title = "", text = got.answer.copy()))
			fleet.steps[id].extend(got.steps)
	fleet
