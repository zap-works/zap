# What an agent's stream-json lines say, as steps to read: its text, each tool it calls with what
# it asked, what the tool gave back, the turn's end with its cost, and the plan's use.

import json

# a step of an agent's work, as the page shows it
pub type Step:
	kind str   # "text", "tool", "output", "you", "done" or "note"
	title str
	text str

# what one line of the stream holds: its steps, and what it tells of the agent and the plan
# a window of the plan and its use, as a line tells it
pub type PlanUse:
	window str
	use f64   # 0 to 1
	resetsAt i64   # unix seconds

pub type Read:
	steps Step[]
	turnEnded bool   # a result: the agent waits for a message
	cost f64   # the turn's cost, at its end
	planUse f64   # the plan's use of its window (0 to 1), -1 when the line does not say
	planWindow str
	resetsAt i64   # when the plan's window resets, unix seconds
	answer str   # the turn's last text, given with its end
	tokens i64   # the turn's tokens so far, when the line tells them
	taskStarted str = ""   # a task (a command in the background, a subagent) started: its id
	taskEnded str = ""   # a task that ended: its id
	hostStarted bool = false   # the host's mark that it started: the tasks of a Claude Code before are gone
	began bool = false   # Claude Code's session runs (its init line): from now on it is resumed, not made
	plans PlanUse[] = []   # each window of the plan the line tells
	listed bool = false   # the line lists the tasks running in the background (tasks then holds them)
	tasks str[] = []
	resumeFailed bool = false   # a turn that failed before it began: a session to resume that does not exist

# a tool's input, short: the command, the file or the pattern it names, else its JSON
fn toolInput(doc json.Doc, input json.Node):
	for key in ["command", "file_path", "pattern", "url", "prompt", "description"]:
		text = doc.textOf(input, key)
		if text != "": return text.copy()
	out = []
	doc.write(input, out)
	str(out)

# a tool result's text: a string, or the texts of a list of parts
fn resultText(doc json.Doc, content json.Node):
	if doc[content].kind == .Text: return doc[content].text.copy()
	parts = []
	for k in 0..doc.count(content):
		parts.push(doc.textOf(doc.at(content, k), "text").copy())
	parts.join("\n")

# at most n bytes of the text, a note of what was left out after them
fn clipped(text str, n i64):
	if text.len <= n: return text.copy()
	"{text[..n]}\n... ({text.len - n} bytes more)"

fn contentSteps(doc json.Doc, content json.Node, fromUser bool):
	out = []
	if doc[content].kind == .Text:
		out.push(Step(kind = "you", title = "", text = doc[content].text.copy()))
		return out
	for k in 0..doc.count(content):
		part = doc.at(content, k)
		kind = doc.textOf(part, "type")
		if kind == "text":
			out.push(
				Step(
					kind = "you" if fromUser else "text",
					title = "",
					text = doc.textOf(part, "text").copy()
				)
			)
		elif kind == "tool_use":
			input = doc.get(part, "input") ?? continue
			out.push(
				Step(
					kind = "tool",
					title = doc.textOf(part, "name").copy(),
					text = clipped(doc.toolInput(input), 2_000)
				)
			)
		elif kind == "tool_result":
			body = doc.get(part, "content") ?? continue
			out.push(
				Step(kind = "output", title = "", text = clipped(doc.resultText(body), 4_000))
			)
	out

# what the line says; nothing for the lines a reader needs not see (thinking, the commands list)
pub fn readLine(line str) Read:
	read = Read(steps = [], turnEnded = false, cost = 0.0, planUse = -1.0, planWindow = "", resetsAt = 0, answer = "", tokens = 0)
	doc = json.parse(line) ?? return read
	root = doc.root
	kind = doc.textOf(root, "type")
	if kind == "assistant" or kind == "user":
		message = doc.get(root, "message") ?? return read
		content = doc.get(message, "content") ?? return read
		read.steps = doc.contentSteps(content, kind == "user")
	elif kind == "result":
		read.turnEnded = true
		read.answer = doc.textOf(root, "result").copy()
		read.cost = doc.number(root, "total_cost_usd") ?? 0.0
		read.resumeFailed = doc.textOf(root, "subtype") == "error_during_execution" and (doc.number(root, "num_turns") ?? 1.0) == 0.0
		seconds = (doc.number(root, "duration_ms") ?? 0.0) / 1000.0
		read.steps.push(
			Step(kind = "done", title = "turn ended", text = "{seconds:.0} s")
		)
	elif kind == "system":
		subtype = doc.textOf(root, "subtype")
		if subtype == "thinking_tokens": read.tokens = i64(doc.number(root, "estimated_tokens") ?? 0.0)
		elif subtype == "task_started": read.taskStarted = doc.textOf(root, "task_id").copy()
		elif subtype == "task_notification": read.taskEnded = doc.textOf(root, "task_id").copy()
		elif subtype == "init": read.began = true
		elif subtype == "background_tasks_changed":
			read.listed = true
			if doc.get(root, "tasks") is list:
				for k in 0..doc.count(list):
					read.tasks.push(doc.textOf(doc.at(list, k), "task_id").copy())
	elif kind == "host":
		read.hostStarted = true
	elif kind == "rate_limit_event":
		info = doc.get(root, "rate_limit_info") ?? return read
		read.planUse = doc.number(info, "utilization") ?? -1.0
		read.planWindow = doc.textOf(info, "rateLimitType").copy()
		read.resetsAt = i64(doc.number(info, "resetsAt") ?? 0.0)
		# each window apart (five_hour, seven_day), as Claude Code tells them now
		if doc.get(info, "unifiedWindows") is windows:
			for name in ["five_hour", "seven_day"]:
				w = doc.get(windows, name) ?? continue
				use = doc.number(w, "utilization") ?? continue
				read.plans.push(PlanUse(window = name, use, resetsAt = i64(doc.number(w, "resetsAt") ?? 0.0)))
	read

# the JSON values a text holds one after another, a line each or run together
pub fn jsonValues(text str) str[]:
	out = []
	at = 0
	while at < text.len:
		while at < text.len and (text[at] == ' ' or text[at] == '\n' or text[at] == '\r' or text[at] == '\t'):
			at += 1
		if at >= text.len: break
		end = json.valueEnd(text, at) ?? break
		out.push(text[at..end].copy())
		at = end
	out
