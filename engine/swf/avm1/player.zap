# A movie played with its ActionScript, frame by frame as Flash Player runs AVM1 (Ruffle's
# core/src/player.rs and display_object/movie_clip.rs): at load the init actions (DoInitAction)
# run first, then the first frame's clips are made, their classes (Object.registerClass)
# constructed and their code run. Each frame then queues every clip's enterFrame handlers and
# moves the playing ones on a frame, which makes and removes clips and queues the frames' code;
# the queue runs init actions first, then constructors, then the rest in order. setInterval's
# timers fire by the movie's clock. The game calls in by `invoke` (a method by its path from
# _root) and by ExternalInterface's callbacks, and reads what the movie asked of it in
# `m.external`.

import engine
import engine.swf

# a movie and its machine
pub type Player:
	prog Program
	m Machine

# the movie's code decoded: every block once, by where it runs
pub fn newProgram(move scene swf.Scene) Program:
	prog = Program(scene, version = 0)
	prog.version = prog.scene.movie.version
	for a in prog.scene.movie.initActions:
		prog.initBlocks.push(prog.addBlock(a.code, a.library))
	prog.addTimeline(0)
	for id in prog.scene.movie.sprites.keys().sorted():
		prog.addTimeline(id)
	for id in prog.scene.movie.buttons.keys().sorted():
		actions = prog.scene.movie.buttons[id].actions.copy()
		library = prog.scene.movie.libraryOf.get(id) ?? 0
		handlers = actions.map(ClipHandler(events = .conditions, key = 0,
			block = prog.addBlock(it.code, library)))
		if not handlers.isEmpty: prog.buttonBlocks[id] = handlers
	prog

fn addBlock(mut prog Program, code u8[], library i64):
	prog.blocks.push(decodeBlock(code))
	prog.libraries.push(library)
	prog.blocks.len - 1

fn addTimeline(mut prog Program, character i64):
	frames = (prog.scene.timelineOf(character) ?? return).frames.copy()
	library = prog.scene.movie.libraryOf.get(character) ?? 0
	for k, f in frames:
		for code in f.actions:
			b = prog.addBlock(code, library)
			key = (character << 24) | k
			if prog.frameBlocks.getMut(key) is list: list.push(b)
			else: prog.frameBlocks[key] = [b]
		for c in f.commands:
			if c is Place(p):
				for action in p.clipActions:
					handler = ClipHandler(events = action.events, key = action.key,
						block = prog.addBlock(action.code, library))
					key = clipKey(character, k, p.depth)
					if prog.clipBlocks.getMut(key) is list: list.push(handler)
					else: prog.clipBlocks[key] = [handler]

# the movie loaded and its first frame run, in a window of the viewport's size
pub fn newPlayer(move scene swf.Scene, viewport Viewport) Player:
	startPlayer(newProgram(scene), viewport)

# the program's movie loaded and its first frame run
pub fn startPlayer(move prog Program, viewport Viewport) Player:
	m = newMachine(prog.scene.newStage(), viewport)
	m.installBuiltins()
	prog.start(m)
	Player(prog, m)

fn start(prog Program, mut m Machine):
	for b in prog.initBlocks:
		m.initJobs.push(.Run(m.stage.root, b))
	prog.runJobs(m)
	prog.takeStageChanges(m, none) ?? m.fault("{error}")
	prog.runJobs(m)

# The changes of the stage taken: an object for each new node, its onClipEvent(initialize) and
# onClipEvent(construct) handlers (where a component's parameters are set) and its class's
# constructor queued, in that order (run now for `immediate`, a clip a script made), its load
# handlers (a clip's after its children's, as Flash loads a clip once what it holds has loaded)
# and the code of each frame shown queued.
pub fn takeStageChanges(prog Program, mut m Machine, immediate Handle<swf.Node>?) () ? Thrown:
	created = m.stage.created.copy()
	m.stage.created.clear()
	loads = []
	for n in created:
		if n not in m.stage.nodes: continue
		prog.translateField(m, n)
		id = m.objectOfNode(prog, n)
		for b in prog.handlersOf(m, n, constructEvents):
			if immediate == n: try prog.runBlock(m, b, n)
			else: m.constructJobs.push(.Run(n, b))
		if prog.classOf(m, m.stage.nodes[n].placed.character) is ctor:
			if immediate == n:
				try prog.callValue(m, .Obj(ctor), .Obj(id), [], m.prototypeOf(ctor))
			else:
				m.constructJobs.push(.Construct(n, ctor))
		loads.push(n)
	entered = m.stage.entered.copy()
	m.stage.entered.clear()
	for e in entered:
		if e.node not in m.stage.nodes: continue
		character = m.stage.nodes[e.node].placed.character
		blocks = prog.frameBlocks.get((character << 24) | e.frame) ?? continue
		for b in blocks:
			m.jobs.push(.Run(e.node, b))
	for n in loads.sortedBy(-m.stage.depthOf(it)):
		prog.queueEvent(m, n, 1, "onLoad")
	prog.takeRemoved(m)

# the removed nodes forgotten (their unload handlers are not run: the node is gone)
fn takeRemoved(prog Program, mut m Machine):
	m.stage.removed.clear()

# the class registered for a character's symbol, in the library it came from
pub fn classOf(prog Program, m Machine, character i64) Handle<Obj>?:
	movie = ref prog.scene.movie
	name = try movie.linkages.get(character)
	key = "{movie.libraryOf.get(character) ?? 0}|{name}"
	if key not in m.classes: return none
	m.classes[key]

# ClipEventFlags' initialize (0x200) and construct (0x4_0000)
constructEvents = 0x4_0200

# the blocks of the clip's onClipEvent handlers of any of these events
fn handlersOf(prog Program, m Machine, n Handle<swf.Node>, events i64):
	node = m.stage.nodes.get(n) ?? return []
	if node.owner < 0: return []
	key = clipKey(node.owner, node.placed.placedAt, node.placed.depth)
	handlers = prog.clipBlocks.get(key) ?? return []
	handlers.filter((.events & events) != 0).map(.block)

# a clip event queued: the clip's handlers of it (onClipEvent) and its method of that name
pub fn queueEvent(prog Program, mut m Machine, n Handle<swf.Node>, event i64, method str):
	for b in prog.handlersOf(m, n, event):
		m.jobs.push(.Run(n, b))
	m.jobs.push(.Method(n, method.copy()))

# the queue run until it is empty: init actions first, then constructors, then the rest
pub fn runJobs(prog Program, mut m Machine):
	m.steps = 0
	loop 1_000_000:
		job Job? = none
		if not m.initJobs.isEmpty: job = m.initJobs.remove(0)
		elif not m.constructJobs.isEmpty: job = m.constructJobs.remove(0)
		elif not m.jobs.isEmpty: job = m.jobs.remove(0)
		j = job ?? return
		match prog.runJob(m, j):
			error: m.fault("uncaught {prog.describe(m, error.value)}")
			_: pass

fn runJob(prog Program, mut m Machine, job Job) bool ? Thrown:
	match job:
		Run(n, b):
			try prog.runBlock(m, b, n)
		Construct(n, ctor):
			if n not in m.stage.nodes: return false
			id = m.objectOfNode(prog, n)
			try prog.callValue(m, .Obj(ctor), .Obj(id), [], m.prototypeOf(ctor))
		Method(n, name):
			if n not in m.stage.nodes: return false
			me = Value.Obj(m.objectOfNode(prog, n))
			found = try prog.methodOf(m, me, name)
			if found.function is Obj: try prog.callValue(m, found.function, me, [], found.home)
	true

# a value thrown, as the log shows it
pub fn describe(prog Program, mut m Machine, v Value) str:
	prog.toText(m, v) ?? "a value"

# one frame of the movie: the clock moved by a frame, enterFrame handlers queued and the playing
# clips moved on, the queue run, the timers that are due fired
pub fn advance(mut p Player):
	p.prog.advanceFrame(p.m)

fn advanceFrame(prog Program, mut m Machine):
	m.time += 1000.0 / f64(prog.scene.movie.frameRate.max(1.0))
	for n in m.stage.playOrder():
		if n not in m.stage.nodes: continue
		character = m.stage.nodes[n].placed.character
		if character == -1 or prog.scene.timelineOf(character) != none:
			prog.queueEvent(m, n, 2, "onEnterFrame")
		if m.stage.nodes[n].playing: m.stage.stepFrame(prog.scene, n)
	prog.takeStageChanges(m, none) ?? m.fault("{error}")
	prog.runJobs(m)
	prog.fireIntervals(m)
	prog.runJobs(m)
	if i64(m.heap.len) > 2 * m.liveAfterCollect + 4096: m.collect()

fn fireIntervals(prog Program, mut m Machine):
	for k in 0..m.intervals.len:
		if k >= m.intervals.len or m.intervals[k].next > m.time: continue
		t = m.intervals[k].copy()
		m.intervals[k].next = m.time + t.every
		if t.once: m.intervals = m.intervals.filter(.id != t.id)
		f = t.function.copy()
		me = t.me.copy()
		if t.function is Str(name): f = prog.getMember(m, t.me, name) ?? .Undefined
		prog.callValue(m, f, me, t.args, none) ??
			m.fault("in a timer: {prog.describe(m, error.value)}")

# The method at a path from _root ("HUDMovieBaseInstance.SetHealthMeterPercent") called with the
# arguments, as Scaleform's Invoke does; what it returns, undefined when the path names nothing.
pub fn invoke(mut p Player, path str, args Value[]) Value:
	p.prog.invokePath(p.m, path, args)

# a path from _root ("_root.A.b" or "A.b") as its members' names
fn pathParts(path str):
	(path[6..] if path.startsWith("_root.") else path[..]).split(".")

fn invokePath(prog Program, mut m Machine, path str, args Value[]) Value:
	parts = pathParts(path)
	object = prog.memberAt(m, parts[..parts.len - 1])
	found = prog.methodOf(m, object, parts[len - 1]) ?? Found(function = .Undefined)
	if not found.function.isObject():
		m.fault("invoke {path}: no such function")
		return .Undefined
	result = Value.Undefined
	match prog.callValue(m, found.function, object, args, found.home):
		v: result = v
		error: m.fault("invoke {path}: {prog.describe(m, error.value)}")
	prog.takeStageChanges(m, none) ?? m.fault("{error}")
	prog.runJobs(m)
	result

# the value at a path of members from _root ("HUDMovieBaseInstance.HealthMeterLeft.CurrentPercent")
pub fn read(mut p Player, path str) Value:
	p.prog.memberAt(p.m, pathParts(path))

# an object's member, as the game reads one through GFx (a getter the class defines runs)
pub fn member(mut p Player, object Value, name str) Value:
	p.prog.getMember(p.m, object, name) ?? .Undefined

# A value set at a path of members from _root ("Menu_mc.ItemCard_mc.itemInfo"), as the game sets
# one through GFx: a setter the class defines runs, and what it changes on the stage is taken.
pub fn write(mut p Player, path str, v Value):
	parts = pathParts(path)
	object = p.prog.memberAt(p.m, parts[..parts.len - 1])
	if p.prog.setMember(p.m, object, parts[len - 1], v) is error:
		p.m.fault("write {path}: {p.prog.describe(p.m, error.value)}")
	p.prog.takeStageChanges(p.m, none) ?? p.m.fault("{error}")
	p.prog.runJobs(p.m)

# An object's member set, as the game sets one through GFx (a setter the class defines runs, and
# what it changes on the stage is taken).
pub fn setProperty(mut p Player, object Value, name str, v Value):
	if p.prog.setMember(p.m, object, name, v) is error:
		p.m.fault("set {name}: {p.prog.describe(p.m, error.value)}")
	p.prog.takeStageChanges(p.m, none) ?? p.m.fault("{error}")
	p.prog.runJobs(p.m)

# a new object with these members, as the game makes one with GFx's CreateObject and SetMember
pub fn newRecord(mut p Player, fields (str, Value)[]) Value:
	id = p.m.newObject(p.m.protos.object)
	for (name, v) in fields:
		p.m.setOwn(id, name, v.copy())
	.Obj(id)

# a new array of these values, as the game makes one with GFx's CreateArray
pub fn newList(mut p Player, move items Value[]) Value:
	.Obj(p.m.newArray(items))

# the array's elements replaced by these, as the game refills a list the movie handed it
pub fn refill(mut p Player, array Value, move items Value[]):
	id = array.objectId() ?? return
	if p.m.isArray(id): p.m.heap[id].items = items

# the calls the movie made to the game since the last time they were taken
pub fn takeExternal(mut p Player) ExternalCall[]:
	calls = p.m.external.copy()
	p.m.external.clear()
	calls

# the value at a path of members from _root, or from _global when the path starts with it
# The value at a path of members; its first name is looked up as a variable is, on _root and then
# on _global (GFx's Invoke reaches "BookMenu.BookMenuInstance.TurnPage", a class's static).
fn memberAt(prog Program, mut m Machine, parts str[]):
	global = not parts.isEmpty and parts[0] == "_global"
	object = Value.Obj(m.globals if global else m.objectOfNode(prog, m.stage.root))
	first = 1 if global else 0
	for k in first..parts.len:
		found = prog.getMember(m, object, parts[k]) ?? Value.Undefined
		if k == 0 and found == .Undefined:
			found = prog.getMember(m, .Obj(m.globals), parts[k]) ?? .Undefined
		object = found
	object

# a call written as text, "Path.Method(1, 'a', [2])", invoked
pub fn invokeText(mut p Player, text str) Value:
	path, args = p.m.parseCall(text)
	p.invoke(path, args)

# A call of GameDelegate's written as text, "setMessageText('Hello', false)": the game's call into
# the movie by ExternalInterface's "call" callback, which GameDelegate.receiveCall gives to the
# function registered for that name (GameDelegate.addCallBack).
pub fn delegateText(mut p Player, text str) Value:
	name, args = p.m.parseCall(text)
	p.delegate(name, args)

# the function GameDelegate registered for this name called with the arguments, as the game does
pub fn delegate(mut p Player, name str, args Value[]) Value:
	all Value[] = [.Str(name.copy())]
	all.extend(args.copy())
	p.callBack("call", all)

# a callback the movie registered with ExternalInterface.addCallback, called by the game
pub fn callBack(mut p Player, name str, args Value[]) Value:
	c = (p.m.callbacks.get(name) ?? return .Undefined).copy()
	result = p.prog.callValue(p.m, c.function, c.me, args, none) ?? Value.Undefined
	p.prog.runJobs(p.m)
	result

# a key pressed or let go (Flash's key codes): Key's listeners told, onKeyDown or onKeyUp
pub fn key(mut p Player, code i64, down bool):
	p.prog.keyEvent(p.m, code, down)

fn keyEvent(prog Program, mut m Machine, code i64, down bool):
	if down:
		m.lastKey = code
		if code not in m.keysDown: m.keysDown.push(code)
	else:
		m.keysDown = m.keysDown.filter(it != code)
	for who in m.heap[m.keyListeners].items.copy():
		found = prog.methodOf(m, who, "onKeyDown" if down else "onKeyUp") ?? continue
		if prog.callValue(m, found.function, who, [], found.home) is error:
			m.fault("in a key handler: {prog.describe(m, error.value)}")
	prog.runJobs(m)

# the stage's twips to the window's pixels, as the viewport's scale mode fits it
pub fn toScreen(prog Program, m Machine) swf.Affine:
	v = m.viewport
	prog.scene.movie.viewTransform(v.width, v.height, v.scaleMode, v.align)

# what the window shows of the stage, in the stage's pixels: x, y, width, height
pub fn visibleRect(prog Program, m Machine) Vec4:
	from = prog.toScreen(m).inverse()
	low = from.apply(Vec2(0.0, 0.0)) / 20.0
	high = from.apply(Vec2(f32(m.viewport.width), f32(m.viewport.height))) / 20.0
	Vec4(low.x, low.y, high.x - low.x, high.y - low.y)

# the stage drawn into the window
pub fn draw(p Player, mut cache swf.DrawCache, mut r engine.Renderer):
	p.prog.scene.drawStage(p.m.stage, cache, r, p.prog.toScreen(p.m))

# the stage drawn whole into the window's rectangle at x, y of w by h pixels, its proportions kept
pub fn drawInto(
	p Player,
	mut cache swf.DrawCache,
	mut r engine.Renderer,
	x f32,
	y f32,
	w f32,
	h f32
):
	t = p.prog.scene.movie.viewTransform(f64(w), f64(h), "showAll", "")
	t.tx += x
	t.ty += y
	p.prog.scene.drawStage(p.m.stage, cache, r, t)
