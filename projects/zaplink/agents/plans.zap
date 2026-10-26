# Loops and goals: work the fleet keeps going by itself. A loop runs its prompt in a fresh agent
# every few minutes, or again as soon as the last run ends, never two at once. A goal is an aim
# with the command that says it is met: its agent works toward it, and each time it stops the
# check runs; while the check fails and the budget lasts, the agent is told the check's output
# and goes on.

import fs
import json
import win

pub type Loop:
	name str
	prompt str
	model str = ""   # the settings' model when ""
	effort str = ""   # the settings' effort when ""
	every i64 = 0   # minutes between runs, 0 for again as soon as the last one ends
	paused bool = false
	last str = ""   # the last run's agent
	lastAt i64 = 0   # when it started, unix seconds

pub type Goal:
	name str
	aim str
	check str   # a command line run in the repository whose exit code 0 says the goal is met
	model str = ""
	effort str = ""
	budget f64 = 5.0   # dollars as Claude Code counts the turns
	paused bool = false
	met bool = false
	agent str = ""   # the agent pursuing it
	checks i64 = 0   # how many times the check ran

# a goal's check running beside the daemon's loop, what it wrote gathered
pub type CheckRun:
	goal str
	process win.Piped
	out str

# what a goal's agent is first told
fn goalPrompt(g Goal):
	"Your goal: {g.aim}\n\nIt is met when this command exits with 0 in the repository: `{g.check}`. Work toward it in commits on a branch of your own (`zap branch new`), never in main. When you believe it is met, say so and stop; the daemon then runs the check and tells you its output if it fails."

# the plans kept beside the agents
pub fn loadPlans(dir str) (Loop[], Goal[]):
	loops = Loop[].fromJson(fs.readFile("{dir}/loops.json") ?? "[]") ?? []
	goals = Goal[].fromJson(fs.readFile("{dir}/goals.json") ?? "[]") ?? []
	(loops, goals)

# the loops' runs started when due, the goals' agents asked for and their checks run as they stop
pub fn advancePlans(mut fleet Fleet, repo str):
	now = unixSeconds()
	for k in 0..fleet.loops.len:
		l = fleet.loops[k]
		if l.paused: continue
		if fleet.find(l.last) is a:
			if fleet.agents[a].state == .Idle: fleet.kill(l.last)
			if fleet.agents[a].state != .Stopped: continue
		if l.every > 0 and now - l.lastAt < l.every * 60: continue
		model = l.model if l.model != "" else fleet.settings.model
		effort = l.effort if l.effort != "" else fleet.settings.effort
		fleet.loops[k].last = fleet.ask(repo, model, effort, l.prompt, "", "loop {l.name}")
		fleet.loops[k].lastAt = now
		fleet.savePlans()
	for k in 0..fleet.goals.len:
		g = fleet.goals[k]
		if g.paused or g.met: continue
		if fleet.checking.any(.goal == g.name): continue
		if fleet.find(g.agent) is a:
			agent = fleet.agents[a]
			if agent.state == .Idle or agent.state == .Stopped: fleet.startCheck(k, repo)
			continue
		model = g.model if g.model != "" else fleet.settings.model
		effort = g.effort if g.effort != "" else fleet.settings.effort
		fleet.goals[k].agent = fleet.ask(repo, model, effort, g.goalPrompt(), "", "goal {g.name}")
		fleet.savePlans()

# the goal's check started without waiting for it
fn startCheck(mut fleet Fleet, k i64, repo str):
	g = fleet.goals[k]
	match win.startPiped("cmd /c {g.check}", repo):
		process: fleet.checking.push(CheckRun(goal = g.name.copy(), process, out = ""))
		error: fleet.note(g.agent, Step(kind = "note", title = "the check could not start", text = "system error {error.code}"))
	fleet.goals[k].checks += 1
	fleet.note(g.agent, Step(kind = "note", title = "checking the goal", text = g.check.copy()))
	fleet.savePlans()

# the goals' checks read as they run; an ended one meets its goal or sends its agent back to work
pub fn readChecks(mut fleet Fleet):
	c = 0
	while c < fleet.checking.len:
		fleet.checking[c].out = "{fleet.checking[c].out}{str(fleet.checking[c].process.read())}"
		if not fleet.checking[c].process.hasEnded():
			c += 1
			continue
		goal = fleet.checking[c].goal.copy()
		passed = fleet.checking[c].process.code == 0
		out = fleet.checking[c].out.copy()
		fleet.checking.remove(c)
		k = fleet.goals.indexOf(fleet.goals.find(.name == goal) ?? continue) ?? continue
		fleet.checkEnded(k, passed, out)

fn checkEnded(mut fleet Fleet, k i64, passed bool, out str):
	g = fleet.goals[k]
	tail = out[(out.len - 3_000).max(0)..].copy()
	if passed:
		fleet.goals[k].met = true
		fleet.note(g.agent, Step(kind = "done", title = "goal met", text = g.check.copy()))
		fleet.kill(g.agent)
	elif (fleet.find(g.agent) ?? -1) >= 0 and fleet.agents[fleet.find(g.agent) ?? 0].cost < g.budget:
		fleet.message(g.agent, "The goal's check failed (`{g.check}`). Its output's end:\n\n{tail}\n\nKeep working toward the goal.")
	else:
		fleet.goals[k].paused = true
		fleet.note(g.agent, Step(kind = "note", title = "goal paused: its budget is spent", text = tail))
	fleet.savePlans()

# a loop as a JSON object names it, any key but name and prompt left out
pub fn loopOf(body str) Loop?:
	doc = json.parse(body) ?? return none
	r = doc.root
	if doc.textOf(r, "name") == "" or doc.textOf(r, "prompt") == "": return none
	Loop(
		name = doc.textOf(r, "name").copy(),
		prompt = doc.textOf(r, "prompt").copy(),
		model = doc.textOf(r, "model").copy(),
		effort = doc.textOf(r, "effort").copy(),
		every = i64(doc.number(r, "every") ?? 0.0)
	)

# a goal as a JSON object names it, any key but name, aim and check left out
pub fn goalOf(body str) Goal?:
	doc = json.parse(body) ?? return none
	r = doc.root
	if doc.textOf(r, "name") == "" or doc.textOf(r, "aim") == "" or doc.textOf(r, "check") == "": return none
	Goal(
		name = doc.textOf(r, "name").copy(),
		aim = doc.textOf(r, "aim").copy(),
		check = doc.textOf(r, "check").copy(),
		model = doc.textOf(r, "model").copy(),
		effort = doc.textOf(r, "effort").copy(),
		budget = doc.number(r, "budget") ?? 5.0
	)

# a loop or a goal paused, resumed or deleted; a goal said done has its check run at once
pub fn actOnPlan(mut fleet Fleet, kind str, name str, act str, repo str):
	if kind == "loops":
		k = i64(fleet.loops.indexOf(fleet.loops.find(.name == name) ?? return) ?? return)
		if act == "pause": fleet.loops[k].paused = true
		elif act == "resume": fleet.loops[k].paused = false
		elif act == "delete": fleet.loops.remove(k)
	else:
		k = i64(fleet.goals.indexOf(fleet.goals.find(.name == name) ?? return) ?? return)
		if act == "pause": fleet.goals[k].paused = true
		elif act == "resume": fleet.goals[k].paused = false
		elif act == "delete": fleet.goals.remove(k)
		elif act == "done" and not fleet.checking.any(.goal == name): fleet.startCheck(k, repo)
	fleet.savePlans()
