# Reads a movie of Skyrim's interface (a Scaleform SWF or GFX of "Skyrim - Interface.bsa") and
# prints what swfdump would: its header, its tags counted, its characters by id, its exports and
# imports, its main timeline and the tree of instances of its first frame. Run from the
# repository root:
#
#   zap run projects/skyrim/menuInfo.zap interface/hudmenu.swf          the whole dump
#   zap run projects/skyrim/menuInfo.zap interface/hudmenu.swf --tree 4 the instance tree alone,
#                                                                       4 levels deep
#   zap run projects/skyrim/menuInfo.zap interface/hudmenu.swf --sprite 767   a sprite's timeline
#   zap run projects/skyrim/menuInfo.zap interface/hudmenu.swf --actions   its ActionScript, each
#                                                       block disassembled
#   zap run projects/skyrim/menuInfo.zap --run interface/hudmenu.swf --frames 60 --shot hud.png
#       the menu played with its ActionScript for 60 frames in a window of 1280x960 (--size WxH)
#       and drawn; --invoke "Path.Method(1, 'text'); Other()" calls into it after it loads, as the
#       game does, and --call "setMessageText('Hello', false)" through GameDelegate; the HUD gets
#       --meters health,magicka,stamina (percent, 100 each by default) and the game's own calls and state each frame. Prints the movie's
#       traces, script errors, natives it lacks and what it asked of the game.
#       --keys "20:down;25:enter" presses the game's keys at their frames in a --run too
#   zap run projects/skyrim/menuInfo.zap --feed inventory --keys "20:right;25:down" --frames 40 --shot inv.png
#       the inventory menu filled from the inn's world as a new game has it (--feed 36C37: that
#       container's menu), the game's keys pressed at their frames, what it asks answered; --read
#       "Menu_mc.bFadedIn;..." prints the values at those paths
#   zap run projects/skyrim/menuInfo.zap --all                          every movie: tags not
#                                                                       known and problems

import engine
import image
import engine.swf
import engine.swf.avm1
import interface
import papyrus
import save
import skyrim
import skyrim.esm

# the window's size given by --size WxH, 1280x960 by default
fn windowSize():
	size = (args.option("--size") ?? "1280x960").split("x")
	(i64.parse(size[0]) ?? 1280, i64.parse(size[len - 1]) ?? 960)

# the menu played for some frames, its log printed and its last frame saved when `shot` is given
fn runMenu(install skyrim.Install, key str, out str?):
	width, height = windowSize()
	frames = i64.parse(args.option("--frames") ?? "1") ?? 1
	hud = key == "interface/hudmenu.swf"
	opened = install.openHud(width, height) if hud else install.openPlayer(key, width, height)
	p = opened ?? fail
	for call in (args.option("--invoke") ?? "").split(";"):
		if not call.trimmed().isEmpty: p.invokeText(call.trimmed())
	for call in (args.option("--call") ?? "").split(";"):
		if not call.trimmed().isEmpty: p.delegateText(call.trimmed())
	meters = args.optionNumbers("--meters")
	state = interface.HudState()
	if meters.len == 3:
		state = interface.HudState(health = meters[0], magicka = meters[1], stamina = meters[2])
	for k in 0..frames:
		p.pressKeysAt(k)
		if hud: p.updateHud(state)
		p.advance()
	p.readPaths()
	p.report(key, frames)
	p.shoot(key, out)

# The inventory menu (`what` "inventory"), the journal ("journal"), the magic menu ("magic"), the favorites menu ("favorites") or a container's (`what` its reference in hex) filled
# from the inn's world as a new game has it and played for --frames, the keys of --keys pressed at
# their frames ("20:right;25:down": the game's keys, engine.Key names or letters).
fn runFed(install skyrim.Install, what str, out str?):
	width, height = windowSize()
	frames = i64.parse(args.option("--frames") ?? "1") ?? 1
	plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
	names = install.readNames("Skyrim.esm") ?? fail
	scripts = skyrim.openInstall(dir) ?? fail
	vm = papyrus.cellVm(scripts, plugin, names, inn) ?? fail
	t = install.openTexts(vm.rt.world.settings) ?? fail
	if what == "journal":
		p = install.openJournal(
			t,
			vm.rt.world,
			save.listSaves(save.savesDir() ?? ""),
			install.openPrefs(""),
			width,
			height
		) ??
			fail
		for k in 0..frames:
			p.pressKeysAt(k)
			p.advance()
		p.readPaths()
		p.report(what, frames)
		p.shoot(what, out)
		return
	container = i64.parse("0x{what}") ?? 0
	opened = match what:
		"inventory": install.openInventory(t, vm.rt.world, width, height)
		"magic": install.openMagic(t, vm.rt.world, width, height)
		"favorites": install.openFavorites(t, vm.rt.world, width, height)
		_: install.openContainer(t, vm.rt.world, container, width, height)
	menu = opened ?? fail
	for k in 0..frames:
		menu.p.pressKeysAt(k)
		menu.answer(t, vm.rt.world)
		menu.p.advance()
	menu.p.readPaths()
	menu.p.report(what, frames)
	menu.p.shoot(what, out)

# the values at the paths --read names ("Menu_mc.bFadedIn;...") printed
fn readPaths(mut p avm1.Player):
	for path in (args.option("--read") ?? "").split(";").filter(not .isEmpty):
		print("{path} = {p.prog.describe(p.m, p.read(path))}")

# the keys of --keys that fall on frame k pressed
fn pressKeysAt(mut p avm1.Player, k i64):
	for step in (args.option("--keys") ?? "").split(";").filter(not .trimmed().isEmpty):
		parts = step.trimmed().split(":")
		if (i64.parse(parts[0]) ?? -1) == k: p.press(keyNamed(parts[len - 1]))

# a key by the name --keys gives it
fn keyNamed(name str) engine.Key:
	match name.lower():
		"up": .Up
		"down": .Down
		"left": .Left
		"right": .Right
		"enter": .Enter
		"tab": .Tab
		"esc", "escape": .Escape
		_: .Char(name.upper()[0])

# the movie's traces, script errors, natives it lacks and what it asked of the game
fn report(p avm1.Player, what str, frames i64):
	for line in p.m.log:
		print(line)
	for name in p.m.unimplemented.keys().sorted():
		print("not implemented: {name} ({p.m.unimplemented[name]})")
	for c in p.m.external:
		print("to the game: {c.name}({c.args.map(.primitiveText()).join(", ")})")
	print("{what}: {frames} frames, {p.m.errors} script errors, {p.m.heap.len} objects")

# the movie's frame drawn into a window of its viewport's size and saved to `out`, when given
fn shoot(p avm1.Player, what str, out str?):
	path = out ?? return
	width, height = i64(p.m.viewport.width), i64(p.m.viewport.height)
	window = engine.openWindow("menuinfo {what}", width, height)
	r = engine.newRenderer()
	cache = swf.newDrawCache()
	clock = engine.newFrames()
	if not window.nextFrame(clock): fail("the window closed")
	r.beginFrame(width, height, Vec4(0.0, 0.0, 0.0, 1.0), engine.Camera())
	p.draw(cache, r)
	r.screenshot().savePng(path) ?? fail("cannot write {path}: {error}")
	for m in cache.missing:
		eprint("not drawn: {m}")
	print("{cache.triangles} triangles drawn into {path}")

inn = "RiverwoodSleepingGiantInn"
dir = args.option("--install") ?? skyrim.defaultInstall
install = skyrim.openInstall(dir) ?? fail
args.options(
	[
		skyrim.installOption,
		ArgOption("--tree", true, "how many levels of the instance tree"),
		ArgOption("--sprite", true, "the sprite whose timeline to show"),
		ArgOption("--run", true, "the menu to play"),
		ArgOption("--actions", true, "the movie whose ActionScript to show"),
		ArgOption("--frames", true, "how many frames to play"),
		ArgOption("--shot", true, "the picture to write"),
		ArgOption("--size", true, "the window's size, WxH"),
		ArgOption("--invoke", true, "calls into the movie after it loads"),
		ArgOption("--call", true, "a call through GameDelegate"),
		ArgOption("--meters", true, "the HUD's meters, in percent"),
		ArgOption("--feed", true, "the menu filled from the inn's world"),
		ArgOption("--keys", true, "the keys to press at their frames"),
		ArgOption("--read", true, "the values at these paths to print")
	]
)
rest = args.positional()
if args.option("--feed") is what:
	install.runFed(what, args.option("--shot"))
	return
if args.option("--run") is key:
	install.runMenu(key, args.option("--shot"))
	return
if args.option("--actions") is key:
	movie = install.openMovie(key) ?? fail
	for (where, code) in movie.movieBlocks():
		print("{where}:")
		for line in avm1.decodeBlock(code).blockLines("  "):
			print(line)
	return
if "--all" in args:
	for key in install.movieKeys():
		match install.openMovie(key):
			movie:
				unknown = movie.unknown.keys().map("{it}")
				print("{key}: {movie.signature}, {movie.kinds.len} characters, unknown [{unknown.join(", ")}], {movie.problems.len} problems")
			error: print("{key}: {error}")
	return
if rest.isEmpty: fail("give a movie's key, such as interface/hudmenu.swf")
movie = install.openMovie(rest[0]) ?? fail
if args.option("--tree") is levels:
	for line in movie.treeLines(movie.timeline, 0, "", i64.parse(levels) ?? 3):
		print(line)
	return
if args.option("--sprite") is text:
	id = i64.parse(text) ?? fail("--sprite takes a sprite's id")
	sprite = movie.sprites.get(id) ?? fail("no sprite {id}")
	for line in sprite.timeline.timelineLines(""):
		print(line)
	return
for line in movie.headerLines():
	print(line)
for line in movie.tagLines():
	print(line)
for line in movie.characterLines():
	print(line)
for line in movie.assetLines():
	print(line)
for line in movie.timeline.timelineLines(""):
	print(line)
