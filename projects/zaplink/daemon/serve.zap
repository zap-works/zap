# The daemon's web server: a job answers the browser at once from the pages last made and passes
# its orders on, while the daemon's own loop runs the agents and reads the board again.

import agents
import cards
import fs
import json
import net
import web
import win

# what the daemon's loop tells the job that answers the browser
pub type Update:
	Board(html str, version i64)
	Agents(html str, json str, version i64)   # the page's part and the agents, loops and goals as JSON
	Steps(id str, html str[])   # the agent's steps made since the last ones sent

# what the browser asks of the daemon's loop
pub type Order:
	Spawn(ask SpawnAsk)
	Message(id str, text str)
	Kill(id str)
	Resume(id str)
	Settings(json str)   # the knobs a JSON object names, changed
	AddLoop(added agents.Loop)
	AddGoal(added agents.Goal)
	Plan(kind str, name str, act str)   # a loop's or a goal's pause, resume, delete; a goal's done

# an agent asked for from the page or the command line: a card, else a prompt
pub type SpawnAsk:
	card str = ""
	prompt str = ""
	effort str = ""   # the settings' effort when ""
	model str = ""   # the settings' model when ""

# whether the connection is still open once what arrived is read
fn received(mut conn net.TcpConn):
	conn.fill(wait = false) ?? return false
	true

# whether a whole request's head has arrived
fn holdsRequest(conn net.TcpConn):
	conn.stop > conn.start and str(conn.buf[conn.start..conn.stop]).indexOf("\r\n\r\n") != none

# what the job answers from: the pages last made
type Views:
	board str = ""
	boardVersion i64 = 0
	agents str = ""
	agentsJson str = "\{}"
	agentsVersion i64 = 0
	steps {str: str[]} = {}

	fn apply(update Update):
		match update:
			Board(html, version):
				board = html.copy()
				boardVersion = version
			Agents(html, json, version):
				agents = html.copy()
				agentsJson = json.copy()
				agentsVersion = version
			Steps(id, html):
				if id not in steps: steps[id.copy()] = []
				steps[id].extend(html.copy())

# the answer to a GET: the page, a part of it, or an agent's steps after the n the page has
fn got(views Views, path str, query str):
	if path == "/":
		return (
			"text/html; charset=utf-8",
			web.pageText(views.board, "{views.boardVersion}.{views.agentsVersion}")
		)
	if path == "/board": return ("text/html; charset=utf-8", views.board.copy())
	if path == "/agents": return ("text/html; charset=utf-8", views.agents.copy())
	if path == "/agents.json": return ("application/json", views.agentsJson.copy())
	if path == "/version": return ("text/plain", "{views.boardVersion}.{views.agentsVersion}")
	if path.startsWith("/agents/") and path.endsWith("/steps"):
		id = path[8..path.len - 6].copy()
		after = i64.parse(query.replace("after=", "")) ?? 0
		all = views.steps.get(id) ?? []
		return ("text/html; charset=utf-8", "{all.len}\n{all[after.min(all.len)..].join("")}")
	("", "")

# the ask in a JSON object, any of its keys left out
fn spawnAskOf(body str) SpawnAsk?:
	doc = json.parse(body) ?? return none
	model = doc.textOf(doc.root, "model")
	SpawnAsk(
		effort = doc.textOf(doc.root, "effort").copy(),
		card = doc.textOf(doc.root, "card").trimmed().copy(),
		prompt = doc.textOf(doc.root, "prompt").copy(),
		model = model.copy()
	)

# the order a POST gives: /agents with a SpawnAsk's JSON, /agents/<id>/message with the text,
# /agents/<id>/kill and /agents/<id>/resume
fn orderOf(path str, body str) Order?:
	if path == "/agents":
		ask = try spawnAskOf(body)
		return .Spawn(ask)
	parts = path.split("/")
	if path == "/settings": return .Settings(body.copy())
	if path == "/loops":
		added = try agents.loopOf(body)
		return .AddLoop(added)
	if path == "/goals":
		added = try agents.goalOf(body)
		return .AddGoal(added)
	if parts.len == 4 and (parts[1] == "loops" or parts[1] == "goals"):
		return .Plan(parts[1].copy(), parts[2].copy(), parts[3].copy())
	if parts.len != 4 or parts[1] != "agents": return none
	id = parts[2].copy()
	if parts[3] == "message": return .Message(id, body.copy())
	if parts[3] == "kill": return .Kill(id)
	if parts[3] == "resume": return .Resume(id)
	none

# answers the browser on a thread of its own: GETs from the views, POSTs passed on as orders
fn answer(move listener net.TcpListener, updates Channel<Update>, orders Channel<Order>):
	feed = updates
	out = orders
	views = Views()
	conns = []
	loop:
		busy = false
		while feed.tryReceive() is update:
			views.apply(update)
		if listener.poll() is conn:
			conns.push(conn)
			busy = true
		k = 0
		while k < conns.len:
			if not conns[k].received():
				conns.remove(k)
				continue
			if conns[k].holdsRequest():
				request = conns[k].nextRequest() ?? return
				if request.method == "POST":
					if orderOf(request.path(), str(request.body)) is order:
						out.send(order)
						conns[k].queueResponse(200, "text/plain", "ok".bytes())
					else:
						conns[k].queueResponse(400, "text/plain", "no such order".bytes())
				else:
					kind, text = views.got(request.path(), request.query())
					if kind == "": conns[k].queueResponse(404, "text/plain", "no such page".bytes())
					else: conns[k].queueResponse(200, kind, text.bytes())
				_ = conns[k].flush()
				busy = true
			k += 1
		if not busy: sleepMs(5)

# the order carried out on the fleet; an agent on a card works in the card's worktree, taken in its
# name
fn obey(mut fleet agents.Fleet, order Order, mut config Config):
	repo = config.repo.copy()
	match order:
		Spawn(asked):
			ask = asked.copy()
			if ask.model == "": ask.model = fleet.settings.model.copy()
			if ask.effort == "": ask.effort = fleet.settings.effort.copy()
			if ask.card == "":
				fleet.ask(repo, ask.model, ask.effort, ask.prompt, "", "")
				return
			id = fleet.ask(repo, ask.model, ask.effort, cards.briefing(repo, ask.card, ask.prompt), ask.card, "")
			k = fleet.find(id) ?? return
			match cards.takeCards(repo, [ask.card.copy()], ask.card, id):
				tree:
					fleet.agents[k].dir = tree.copy()
					shareMemory(tree, repo)
				error:
					fleet.agents[k].state = .Stopped
					fleet.note(
						id,
						agents.Step(
							kind = "note",
							title = "could not take {ask.card}",
							text = error.why
						)
					)
		Message(id, text): fleet.message(id, text)
		Kill(id): fleet.kill(id)
		Resume(id): fleet.resume(id)
		AddLoop(added):
			fleet.loops = fleet.loops.filter(.name != added.name)
			fleet.loops.push(added.copy())
			fleet.savePlans()
		AddGoal(added):
			fleet.goals = fleet.goals.filter(.name != added.name)
			fleet.goals.push(added.copy())
			fleet.savePlans()
		Plan(kind, name, act): fleet.actOnPlan(kind, name, act, repo)
		Settings(body):
			config.settings = config.settings.changedBy(body)
			fleet.settings = config.settings.copy()
			config.save()
			fleet.changed = true

# the next Ready card asked for when the fleet has room and nothing waits, AGENTS.md's rule kept
# (two agents at most on the compiler, the board's Doing cards counted); an XL card on opus
fn autoQueue(mut fleet agents.Fleet, b cards.Board, mut config Config):
	if fleet.whyWait() != "" or fleet.agents.any(.state == .Queued): return
	compiling = b.placed.filter(.lane == .Doing and .card.area == "compiler").len
	for p in b.placed:
		if p.lane != .Ready or fleet.agents.any(.card == p.card.id and .state != .Stopped): continue
		if p.card.area == "compiler" and compiling >= 2: continue
		model = "opus" if p.card.size == "XL" else ""
		fleet.obey(.Spawn(SpawnAsk(card = p.card.id.copy(), prompt = "", model)), config)
		return

# a path as Claude Code names its project dir: every ':', '' and '/' a '-'
fn projectKey(path str):
	path.replace(":", "-").replace("\\", "-").replace("/", "-")

# the worktree's Claude Code project memory made the repository's (a junction), so every agent
# reads and writes one memory
fn shareMemory(tree str, repo str):
	projects = "{fs.userDir()}/.claude/projects"
	mainKey = projectKey(repo).lower()
	main = (fs.list(projects) ?? []).find(.lower() == mainKey) ?? return
	link = "{projects}/{projectKey(tree)}/memory"
	if fs.exists(link): return
	_ = fs.createDir("{projects}/{projectKey(tree)}")
	target = "{projects}/{main}/memory"
	_ = Process.output(["cmd", "/c", "mklink", "/J", link.replace("/", "\\"), target.replace("/", "\\")])

# the page at http://host:port/: a job answers at once from the pages last made; this loop runs
# the agents, reads the board again every 1.5 s and sends what changed
pub fn serve(mut config Config):
	listener = net.tcpListen(config.port, config.host) ??
		exit(1, "cannot listen on {config.host}:{config.port}: {error}")
	print("zaplinkd on http://{config.host}:{config.port}/, the board of {config.repo}")
	win.unsetVariable("ANTHROPIC_API_KEY")
	updates = Channel<Update>()
	orders = Channel<Order>()
	server = background((): answer(listener, updates, orders))
	fleet = agents.loadFleet(fs.join(stateDir(), "agents"), config.settings)
	lookAt = 0
	plansAt = 0
	gpuAt = 0
	texts {str: str} = {}
	lastBoard = ""
	boardVersion = 0
	agentsVersion = 0
	sent {str: i64} = {}
	boardAt = clockMs() - 10_000
	feed = updates
	pending = orders
	while not server.isDone:
		while pending.tryReceive() is order:
			fleet.obey(order, config)
		if clockMs() - lookAt > 2_000:
			lookAt = clockMs()
			fleet.machine = fleet.machine.looked()
			if clockMs() - gpuAt > 10_000:
				gpuAt = clockMs()
				fleet.machine.gpu = agents.gpuUse()
			fleet.changed = true
		fleet.pump()
		fleet.readChecks()
		if clockMs() - plansAt > 5_000:
			plansAt = clockMs()
			fleet.advancePlans(config.repo)
		if fleet.changed:
			fleet.changed = false
			agentsVersion += 1
			for a in fleet.agents:
				all = fleet.steps.get(a.id) ?? []
				from = sent.get(a.id) ?? 0
				if all.len > from:
					feed.send(.Steps(a.id.copy(), all[from..].map(.stepText())))
					sent[a.id.copy()] = all.len
			feed.send(.Agents(fleet.agentsText(), "\{\"agents\":{fleet.agents.toJson()},\"loops\":{fleet.loops.toJson()},\"goals\":{fleet.goals.toJson()}}", agentsVersion))
		if clockMs() - boardAt > 1_500:
			boardAt = clockMs()
			b = cards.readBoard(config.repo, texts)
			if config.settings.autoQueue: fleet.autoQueue(b, config)
			html = b.boardText()
			if html != lastBoard:
				boardVersion += 1
				lastBoard = html.copy()
				feed.send(.Board(html, boardVersion))
		sleepMs(50)
