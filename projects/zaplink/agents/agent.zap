# An agent: Claude Code without a window (`claude -p`), driven over stream-json (one JSON message
# a line both ways) in a dir; its session's id is its name for Claude Code, so a stopped agent
# goes on from where it was (`--resume`). Every line it writes is kept in its log, the state
# dir's agents/<id>.jsonl, which a restart of the daemon reads again.

import json
import win

pub type AgentState:
	Queued   # asked, waiting for a place under the machine's limit
	Working   # its process runs and a turn is under way
	Idle   # its process runs, waiting for a message
	Stopped   # killed or ended; resuming starts it again from its session

pub type Agent:
	id str
	name str
	dir str
	model str
	effort str = ""   # Claude Code's --effort: low, medium, high, xhigh or max
	role str = ""   # the loop or the goal it runs for, "" for none
	parent str = ""   # the session of the agent that started it, "" when the user did
	prompt str   # the first message, sent when it starts
	card str = ""   # the card it works on, "" for none
	state AgentState = .Queued
	asked i64 = 0   # unix seconds
	started bool = false   # whether its session exists, so a start resumes it
	waiting str = ""   # a message for it once it starts again
	cost f64 = 0.0   # dollars as Claude Code counts the turns
	turnStart i64 = 0   # when the turn under way began, unix seconds; 0 between turns
	idleSince i64 = 0   # when its last turn ended, unix seconds; 0 while one runs
	startHead str = ""   # the commit its worktree was at when it started, to tell whether it committed
	turnTokens i64 = 0   # the tokens the turn under way has made so far, as Claude Code estimates them
	turns i64 = 0
	standing bool = false   # on a standing card: at hand for the user, never stopped for idleness

	# its state as the page writes it
	fn stateText():
		match state:
			Queued: "queued"
			Working: "working"
			Idle: "idle"
			Stopped: "stopped"

	# whether its process runs
	fn isRunning():
		state == .Working or state == .Idle

# a new session's id: a version 4 UUID
pub fn newSessionId() str:
	b = win.secureRandom(16)
	b[6] = (b[6] & 0x0F) | 0x40
	b[8] = (b[8] & 0x3F) | 0x80
	hex = b.map("{it:02x}").join("")
	"{hex[..8]}-{hex[8..12]}-{hex[12..16]}-{hex[16..20]}-{hex[20..]}"

# the command line that runs the agent: its session made, or taken up again
pub fn commandOf(a Agent) str:
	session = "--resume {a.id}" if a.started else "--session-id {a.id}"
	model = " --model {a.model}" if a.model != "" else ""
	effort = " --effort {a.effort}" if a.effort != "" else ""
	"claude -p --input-format stream-json --output-format stream-json --verbose --permission-mode bypassPermissions{model}{effort} {session}"

# a message from the user as a line of stream-json
pub fn userLine(text str) str:
	"\{\"type\":\"user\",\"message\":\{\"role\":\"user\",\"content\":{text.toJson()}}}\n"

# the agents a JSON list holds, each key an agent of an older shape lacks at its default
pub fn agentsOf(text str) Agent[]:
	doc = json.parse(text) ?? return []
	out = []
	for k in 0..doc.count(doc.root):
		a = doc.at(doc.root, k)
		state = doc.textOf(doc.get(a, "state") ?? a, "$tag")
		out.push(
			Agent(
				id = doc.textOf(a, "id").copy(),
				name = doc.textOf(a, "name").copy(),
				dir = doc.textOf(a, "dir").copy(),
				model = doc.textOf(a, "model").copy(),
				effort = doc.textOf(a, "effort").copy(),
				role = doc.textOf(a, "role").copy(),
				parent = doc.textOf(a, "parent").copy(),
				prompt = doc.textOf(a, "prompt").copy(),
				card = doc.textOf(a, "card").copy(),
				state = .Stopped if state == "Stopped" else (.Queued if state == "Queued" else (.Working if state == "Working" else .Idle)),
				asked = i64(doc.number(a, "asked") ?? 0.0),
				started = (doc.number(a, "started") ?? 0.0) != 0.0,
				waiting = doc.textOf(a, "waiting").copy(),
				cost = doc.number(a, "cost") ?? 0.0,
				turns = i64(doc.number(a, "turns") ?? 0.0),
				idleSince = i64(doc.number(a, "idleSince") ?? 0.0),
				startHead = doc.textOf(a, "startHead").copy(),
				standing = (doc.number(a, "standing") ?? 0.0) != 0.0
			)
		)
	out
