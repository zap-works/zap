# zaplink: the command line of the daemon's world (README.md). The board's cards, and the agents,
# loops and goals the daemon runs (asked of it over HTTP, so an agent may start another one: the
# daemon decides when, under the machine's limit and the plan's pace).
#
#   zaplink board check | next | take <id>... [--branch name] [--by session]
#   zaplink agents | spawn [--card id] [--model m] [--effort e] [prompt...]
#   zaplink say <agent> <text...> | kill <agent> | resume <agent>      (an agent by its id's start or name)
#   zaplink loop <name> [--every minutes] [--model m] <prompt...> | goal <name> --check "cmd" [--budget dollars] <aim...>
#   zaplink plans | pause|resume|delete <loop or goal> | done <goal> | set <key>=<value>...
#   zaplink adopt <session> [--now]      (a Claude Code window's session, taken over by the daemon)

import agents
import cards
import daemon
import fs
import json

args.options([
	ArgOption(name = "--branch", takesValue = true, help = "the branch that takes the cards (the first id's name)"),
	ArgOption(name = "--by", takesValue = true, help = "the agent's session id (Claude Code's own by default)"),
	ArgOption(name = "--card", takesValue = true, help = "the card an agent works on"),
	ArgOption(name = "--model", takesValue = true, help = "haiku, sonnet or opus (the settings' when left out)"),
	ArgOption(name = "--effort", takesValue = true, help = "low, medium, high, xhigh or max (the settings' when left out)"),
	ArgOption(name = "--every", takesValue = true, help = "a loop's minutes between runs (0: again at once)"),
	ArgOption(name = "--check", takesValue = true, help = "a goal's command, met when it exits with 0"),
	ArgOption(name = "--budget", takesValue = true, help = "a goal's dollars as Claude Code counts them"),
	ArgOption(name = "--now", takesValue = false, help = "adopt a session that is busy")
])
words = args.positional()
here = currentDir().replace("\\", "/")
config = daemon.loadConfig()
command = words[0] if not words.isEmpty else ""
rest = words[1..].join(" ") if words.len > 1 else ""

# the daemon's answer, or the program stopped with why there is none
fn asked(method str, path str, body str):
	config.askDaemon(method, path, body) ?? exit(1, "zaplinkd does not answer on {config.host}:{config.port}: {error}")

# the agents, loops and goals as the daemon holds them
fn state():
	json.parse(asked("GET", "/agents.json", "")) ?? exit(1, "zaplinkd's answer is not JSON")

# the full id of the agent whose id starts with, or whose name is, `which`
fn agentId(which str) str:
	doc = state()
	list = doc.get(doc.root, "agents") ?? exit(1, "no agents")
	for k in 0..doc.count(list):
		a = doc.at(list, k)
		id = doc.textOf(a, "id")
		if id.startsWith(which) or doc.textOf(a, "name") == which: return id.copy()
	exit(1, "no agent {which}")

fn board():
	sub = words[1] if words.len > 1 else ""
	if sub == "check":
		problems = cards.checkCards(here)
		for line in problems:
			print(line)
		if not problems.isEmpty: exit(1, "{problems.len} problems")
		found, _ = cards.loadCards(here)
		print("{found.len} cards, well formed")
	elif sub == "next":
		texts {str: str} = {}
		b = cards.readBoard(here, texts)
		ready = b.placed.find(.lane == .Ready) ?? exit(1, "no card is ready")
		print("{ready.card.id}  {ready.card.title}  ({ready.card.size})  {ready.card.path}")
	elif sub == "take" and words.len > 2:
		ids = words[2..]
		branch = args.option("--branch") ?? ids[0]
		by = args.option("--by") ?? (env.get("CLAUDE_CODE_SESSION_ID") ?? "")
		tree = cards.takeCards(cards.mainCheckout(here), ids, branch, by) ?? exit(1, error.why)
		print("{ids.join(", ")} taken by {branch}: {tree}")
	else:
		exit(2, "usage: zaplink board check | next | take <id>... [--branch name] [--by session]")

fn listAgents():
	doc = state()
	list = doc.get(doc.root, "agents") ?? return
	for k in 0..doc.count(list):
		a = doc.at(list, k)
		cost = doc.number(a, "cost") ?? 0.0
		state = doc.get(a, "state") ?? a
		print("{doc.textOf(a, "id")[..8]}  {doc.textOf(a, "name")}  {doc.textOf(a, "model")}  {doc[state].text}  ${cost:.2}  {doc.textOf(a, "card")}")

fn listPlans():
	doc = state()
	for kind in ["loops", "goals"]:
		list = doc.get(doc.root, kind) ?? continue
		for k in 0..doc.count(list):
			p = doc.at(list, k)
			paused = " (paused)" if (doc.number(p, "paused") ?? 0.0) != 0.0 else ""
			print("{kind[..kind.len - 1]} {doc.textOf(p, "name")}{paused}: {doc.textOf(p, "prompt")}{doc.textOf(p, "aim")}")

# the Claude Code session of that name, opened by hand, taken over by the daemon: its window's
# process ended once it is idle, its conversation going on as the daemon's agent
fn adopt(name str):
	s = cards.sessionsRunning().find(.name == name and .kind == "interactive") ?? exit(1, "no session {name} open by hand")
	if s.status != "idle" and not args.hasFlag("--now"): exit(1, "{name} is {s.status}: wait until it is idle, or give --now")
	Process.output(["taskkill", "/PID", "{s.pid}", "/F"])
	print(asked("POST", "/adopt", "\{\"id\":{s.sessionId.toJson()},\"name\":{s.name.toJson()},\"dir\":{s.cwd.toJson()}}"))

# "loops" or "goals" for the plan of that name, "" for none
fn planKind(name str):
	doc = state()
	for kind in ["loops", "goals"]:
		list = doc.get(doc.root, kind) ?? continue
		for k in 0..doc.count(list):
			if doc.textOf(doc.at(list, k), "name") == name: return kind.copy()
	""

# `key=value` words as a JSON object: numbers as numbers, true and false as 1 and 0, the rest as text
fn settingsJson(pairs str[]):
	fields = []
	for pair in pairs:
		at = pair.indexOf("=") ?? exit(2, "{pair}: not key=value")
		key = pair[..at]
		value = pair[at + 1..]
		shown = "1" if value == "true" else ("0" if value == "false" else value.copy())
		fields.push("{key.toJson()}:{shown if f64.parse(shown) != none else value.toJson()}")
	"\{{fields.join(",")}}"

if command == "host" and words.len == 2: agents.runHost(fs.join(daemon.stateDir(), "agents"), words[1])
elif command == "board": board()
elif command == "agents": listAgents()
elif command == "plans": listPlans()
elif command == "spawn":
	ask = "\{\"card\":{(args.option("--card") ?? "").toJson()},\"model\":{(args.option("--model") ?? "").toJson()},\"effort\":{(args.option("--effort") ?? "").toJson()},\"parent\":{(env.get("CLAUDE_CODE_SESSION_ID") ?? "").toJson()},\"prompt\":{rest.toJson()}}"
	print(asked("POST", "/agents", ask))
elif command == "say" and words.len > 2: print(asked("POST", "/agents/{agentId(words[1])}/message", words[2..].join(" ")))
elif command == "kill" and words.len == 2: print(asked("POST", "/agents/{agentId(words[1])}/kill", ""))
elif command == "resume" and words.len == 2 and planKind(words[1]) == "":
	print(asked("POST", "/agents/{agentId(words[1])}/resume", ""))
elif command == "loop" and words.len > 2:
	print(asked("POST", "/loops", "\{\"name\":{words[1].toJson()},\"every\":{args.option("--every") ?? "0"},\"model\":{(args.option("--model") ?? "").toJson()},\"prompt\":{words[2..].join(" ").toJson()}}"))
elif command == "goal" and words.len > 2:
	check = args.option("--check") ?? exit(2, "a goal needs --check \"command\"")
	print(asked("POST", "/goals", "\{\"name\":{words[1].toJson()},\"check\":{check.toJson()},\"budget\":{args.option("--budget") ?? "5"},\"model\":{(args.option("--model") ?? "").toJson()},\"aim\":{words[2..].join(" ").toJson()}}"))
elif (command in ["pause", "resume", "delete", "done"]) and words.len == 2:
	kind = planKind(words[1])
	if kind == "": exit(1, "no loop or goal {words[1]}")
	print(asked("POST", "/{kind}/{words[1]}/{command}", ""))
elif command == "adopt" and words.len == 2: adopt(words[1])
elif command == "set" and words.len > 1: print(asked("POST", "/settings", settingsJson(words[1..])))
else:
	exit(2, "usage: zaplink board ... | agents | spawn | say | kill | resume | loop | goal | plans | pause | resume | delete | done | set\n{args.usage()}")
