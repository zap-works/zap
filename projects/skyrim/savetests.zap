# Saving and loading in the inn (save/): the .ess container read and written, the change forms
# against a new game's entries, and the whole game saved, changed and loaded back, compared
# field by field. Real saves of the player's, when there are any, check the layout read.
# The fight in progress, the dead's ragdolls, the clutter's poses and the play time are saved too.
#   limit: 1500 s (each game test copies the inn's world and talk, and the fight ones play frames)

import save
import engine
import engine.physics
import engine.swf.avm1
import fs
import interface
import skyrim
import game
import game.combat
import game.dialogue
import game.sim
import papyrus
import skyrim.esm
import world

fn entry(kind i64, refId i64, part i64, text str):
	save.Entry(kind, refId, part, data = text.bytes().cStringAt(0, 1000).toBytes())

# why a read failed, "" when it did not
fn failure<T>(r T ? str) str:
	match r:
		error: error
		_: ""

# the distinct numbers, in order
fn distinct(xs i64[]):
	seen {i64: bool} = {}
	for x in xs:
		seen[x] = true
	seen.keys().sorted()

fn sampleEss():
	save.Ess(
		header = save.Header(
			saveNumber = 7,
			name = "Лена",
			level = 3,
			location = "Sleeping Giant Inn",
			playTime = "000.01.30",
			race = "NordRace",
			female = true,
			filetime = 134_370_000_000_000_000,
			shotWidth = 2, shotHeight = 1),
		shot = [1, 2, 3, 255, 4, 5, 6, 255],
		plugins = ["Skyrim.esm", "Update.esm"],
		blocks = [save.Block(kind = 3, data = [1, 2]), save.Block(kind = 1001, data = [9, 9, 9]),
			save.Block(kind = 2001, data = [])],
		changes = [
			entry(save.typeAchr, 0x14, save.partForm, "player"),
			entry(save.typeAchr, 0x14, save.partInventory, "gold"),
			entry(save.typeRefr, 0x0009_A2B3, save.partForm, "a mug"),
			entry(save.typeRefr, 0x0100_0042, save.partForm, "past the default ids"),
			entry(save.typeRefr, 0xFF00_0801, save.partForm, "made in play"),
			save.Entry(kind = save.typeInfo, refId = 0x0001_0203, part = save.partSaid, data = [], gone = true),
			entry(save.typeQust, 0x0004_0000, save.partStage, "stage")
		],
		visited = [0x3C, 0x1B]
	)

test "a save written reads back: header, screenshot, plugins, global data, change forms and the ids their RefIDs name":
	e = sampleEss()
	back = save.readEss(e.writeEss()) ?? fail("the file does not read back")
	expect back.header.toBytes() == e.header.toBytes()
	expect back.shot == e.shot and back.plugins == e.plugins and back.visited == e.visited
	expect back.blocks.toBytes() == e.blocks.toBytes()
	expect back.changes.len == e.changes.len
	for k, c in e.changes:
		expect back.changes[k].toBytes() == c.toBytes()

test "the container is UESP's: magic, header size, screenshot, then the body's lengths and an LZ4 block":
	bytes = sampleEss().writeEss()
	expect bytes.startsWith("TESV_SAVEGAME")
	c = save.containerOf(bytes) ?? fail("no container")
	expect c.header.shotWidth == 2 and c.shot.len == 8 and
		c.base == bytes.len - 8 - bytes.u32le(c.base + 4)
	head = c.headOf() ?? fail("no head")
	l = head.locations
	expect l.globals1 > c.base and l.globals1 < l.globals2 and l.globals2 <= l.changeForms
	expect l.changeForms < l.globals3 and l.globals3 < l.formIds and l.formIds < l.unknownTable
	expect l.count1 == 1 and l.count2 == 0 and l.count3 == 2 and l.countForms == 6
	raw = c.changeFormsFrom(l) ?? fail("no change forms")
	expect raw.map(.refId) ==
		[0x14, 0x0009_A2B3, 0x0100_0042, 0xFF00_0801, 0x0001_0203, 0x0004_0000]
	expect raw.map(.kind) == [1, 0, 0, 0, 7, 8] and raw.all(.version == 78)

test "a save that is not one, or is cut short, is refused with a reason":
	expect not failure(save.readEss([1, 2, 3])).isEmpty
	whole = sampleEss().writeEss()
	expect not failure(save.readEss(whole[..whole.len - 3])).isEmpty
	expect not failure(save.readEss(whole[..20])).isEmpty

# the newest save of the game's own folder, none without one
fn realSave() u8[]?:
	dir = "{skyrim.iniDir() ?? return none}/Saves"
	names = (fs.list(dir) ?? []).filter(fs.extension(it) == ".ess").sorted()
	fs.readBytes("{dir}/{names.last ?? return none}") ?? none

test "a save of the real game reads: its header, its tables at the offsets the location table gives, its change forms":
	bytes = realSave() ?? return
	c = save.containerOf(bytes) ?? fail("a real save does not unpack")
	expect c.header.shotWidth * c.header.shotHeight * 4 == c.shot.len
	head = c.headOf() ?? fail("a real save's head does not read")
	l = head.locations
	expect (head.plugins.first ?? "") == "Skyrim.esm" and head.plugins.len > 1
	first = c.blocksFrom(l.globals1, l.count1) ?? fail("table 1")
	second = c.blocksFrom(l.globals2, l.count2) ?? fail("table 2")
	third = c.blocksFrom(l.globals3, l.count3) ?? fail("table 3")
	expect (first.map(.kind).first ?? -1) == 0 and first.map(.kind).all(it < 100)
	expect second.map(.kind).all(it >= 100 and it < 1000) and (third.map(.kind).first ?? -1) == 1000
	expect third.any(.kind == 1001)
	forms = c.changeFormsFrom(l) ?? fail("the change forms")
	expect forms.len == l.countForms
	expect l.changeForms < l.globals3 and l.globals3 < l.formIds and l.formIds < l.unknownTable
	expect forms.all(.version == 78 or .version < 100)

test "what the reader takes from a real save's header and location table the writer writes back to the same bytes":
	bytes = realSave() ?? return
	c = save.containerOf(bytes) ?? fail("a real save does not unpack")
	headerSize = i64(bytes.u32le(13))
	expect c.header.headerBytes() == bytes[17..17 + headerSize]
	head = c.headOf() ?? fail("real head")
	written u8[] = []
	written.pushLocations(head.locations)
	expect written == c.body[head.tableAt..head.tableAt + 100]

inn = "RiverwoodSleepingGiantInn"
light = game.Load(textures = false, graph = false, sound = false, dialogue = false)

# the inn's dialogue over the archives and its prepared cell, read for each test
fn archivesTalk():
	dialogue.talkOfArchives(inn)

fn readInnCell() game.PreparedCell?:
	if not fs.exists(esm.defaultEsm()): return none
	game.openOrPrepare(inn, light)

fn innCell():
	readInnCell()

# the inn's residents at the game hour
fn residentsAt(cell game.PreparedCell, hour f32):
	cast = cell.head.cast
	rigs = cast.skeletons.map(.skeletonRig())
	speeds = cast.skeletons.map(.speeds.copy())
	cast.newResidents(rigs, speeds, hour, light)

# a new game of the inn: its cell, dialogue and VM, residents at 8 and the player at the door
fn startedGame() (game.PreparedCell, dialogue.Talk, game.Residents, game.Player)?:
	cell = try innCell()
	t = try archivesTalk()
	rs = cell.residentsAt(8.0)
	p = cell.head.cast.start.newPlayer(cell.head.cast.heading, rs.gaits[0])
	(cell, t, rs, p)

# a folder of the test's own for the saves
fn freshDir(name str):
	dir = "{fs.cacheDir("skyrimsavetests")}/{name}"
	fs.deleteTree(dir) ?? fail("{dir} cannot be cleared")
	dir

fn residentNamed(rs game.Residents, cast world.CastHead, editorId str):
	rs.all.findIndex(cast.npcs[.npc].editorId == editorId) ?? fail("no {editorId}")

# the first form of the world that satisfies the test, 0 for none
fn firstForm(w sim.GameWorld, kind str, inCell bool):
	for id in w.forms.keys().sorted():
		f = w.forms[id]
		if f.baseKind == kind and f.enabled and (f.cell == w.cell or not inCell): return id
	0

# What the tests change in a running game, in every part a save keeps: the player's body, values,
# inventory, equipment, favorites and hotkeys; actors dead and moved; a container emptied and an
# item taken; a thing made; the quests, the dialogue, the books, the furniture, the crimes; the
# VM's variables, a waiting thread and an update; the clock; a resident's package.
fn changeThings(
	mut t dialogue.Talk,
	mut rs game.Residents,
	cast world.CastHead,
	mut p game.Player,
	shift f32
):
	w = mut ref t.vm.rt.world
	me = w.player
	p.placeBody(save.SavedBody(
		feet = Vec3(-900.0 + shift, -120.0, 0.0),
		falling = 0.0,
		onFloor = true,
		heading = 1.0 + shift / 100.0,
		gait = 1.0,
		cycle = 0.25,
		idleTime = 2.0
	))
	w.actors[me].damageValue("health", 20.0 + shift)
	w.actors[me].modValue("stamina", 15.0)
	w.inventories[me].addItem(0xF, 77)
	w.inventories[me].unequip(0x3_C9FE)
	fire = w.items.keys().find(w.items[it].name == "Potion of Resist Fire") ?? fail("no potion")
	w.consume(me, fire) ?? fail
	w.tickEffects(5.0 + shift)
	w.setHotkey(me, 0x1_D4EC, 2)
	w.setHotkey(me, 0x1_3790, 5)
	orgnar = 0x1_3486
	w.actors[orgnar].kill()
	w.forms[orgnar].x += 50.0 + shift
	w.inventories[0x1_3485].addItem(0xF, 9)
	chest = w.firstForm("CONT", true)
	w.ensureInventory(chest)
	w.inventories[chest].addItem(0xA, 3)
	loose = w.firstForm("MISC", true)
	w.forms[loose].enabled = false
	w.inventories[me].addItem(w.forms[loose].base, 1)
	made = w.placeNew(0xF, Vec3(10.0, 20.0, 30.0), 12)
	w.setStage(w.stages.keys().sorted()[0], 40 + i64(shift))
	w.setStage(0x0A_0000 + i64(shift), 10)
	t.said[t.dialogue.infos.keys().sorted()[0]] = 2.5 + f64(shift)
	t.talkedTo[orgnar] = true
	w.booksRead[0x1234] = true
	base = w.furniture.keys().sorted()[0]
	w.furniture[base].active = 3
	fact = w.crimeValues.keys().sorted()[0]
	w.crimeValues[fact].murder += 7
	w.daysPassed += 0.25
	w.stealth.sneaking = true
	w.stealth.clock += 4.0 + shift
	w.stealth.action = 100
	w.progress.xp += 7.0 + shift
	w.progress.skillXp[3] += 2.0 + shift
	w.progress.perkPoints += 1
	w.stealth.detections[orgnar] = sim.Detection(level = 12 + i64(shift), inCone = true, at = 3.5)
	w.events.push("changed {made:X}")
	t.vm.rt.objects[1].vars["savetest"] = .Int(42)
	k = t.vm.lib.scriptIndex(t.vm.rt.objects[1].script) ?? 0
	t.vm.rt.threads.push(papyrus.Thread(
		frames = [papyrus.Frame(code = papyrus.CodeRef(script = k, state = 0, index = 0,
			setter = false), pc = 1, locals = {"x": .Int(5)}, me = 1, resultTo = "")],
		wakeAt = 1.0e9,
		result = .None,
		label = "savetest"
	))
	t.vm.rt.updates.push(papyrus.Update(object = 1, at = 1.0e9, interval = 0.0, gameTime = false))
	r = rs.residentNamed(cast, "Delphine")
	rs.all[r].plan += 1
	rs.all[r].clock += 12.5 + shift
	rs.all[r].marker = 3
	rs.all[r].body.placeBody(save.SavedBody(feet = Vec3(-1000.0 + shift, 600.0, 0.0), falling = 0.0,
		onFloor = true, heading = 0.5, gait = 0.0, cycle = 0.0, idleTime = 1.0))

# the names of the snapshot's fields that differ (as JSON, which writes a map's keys in order: its
# bytes follow the order it was filled in)
fn differing(a save.Snapshot, b save.Snapshot):
	out = []
	if a.forms.toJson() != b.forms.toJson(): out.push("forms")
	if a.actors.toJson() != b.actors.toJson(): out.push("actors")
	if a.inventories.toJson() != b.inventories.toJson(): out.push("inventories")
	if a.residents.toJson() != b.residents.toJson(): out.push("residents")
	if a.player.toJson() != b.player.toJson(): out.push("player")
	if a.stages.toJson() != b.stages.toJson(): out.push("stages")
	if a.stagesDone.toJson() != b.stagesDone.toJson(): out.push("stagesDone")
	if a.running.toJson() != b.running.toJson(): out.push("running")
	if a.globals.toJson() != b.globals.toJson(): out.push("globals")
	if a.furniture.toJson() != b.furniture.toJson(): out.push("furniture")
	if a.said.toJson() != b.said.toJson(): out.push("said")
	if a.talkedTo.toJson() != b.talkedTo.toJson(): out.push("talkedTo")
	if a.relations.toJson() != b.relations.toJson(): out.push("relations")
	if a.fills.toJson() != b.fills.toJson(): out.push("fills")
	if a.booksRead.toJson() != b.booksRead.toJson(): out.push("booksRead")
	if a.crimeValues.toJson() != b.crimeValues.toJson(): out.push("crimeValues")
	if a.crimeFactions.toJson() != b.crimeFactions.toJson(): out.push("crimeFactions")
	if a.misc.toJson() != b.misc.toJson(): out.push("misc")
	if a.vm.toJson() != b.vm.toJson(): out.push("vm")
	if a.walker.toJson() != b.walker.toJson(): out.push("walker")
	if a.clutter.toJson() != b.clutter.toJson(): out.push("clutter")
	if a.fallen.toJson() != b.fallen.toJson(): out.push("fallen")
	if a.fighters.toJson() != b.fighters.toJson(): out.push("fighters")
	if a.fight.toJson() != b.fight.toJson(): out.push("fight")
	if a.havok.toJson() != b.havok.toJson(): out.push("havok")
	out

# the game changed with changeThings and saved as the first save of a folder: its session, its
# state then and its file
fn playedAndSaved(
	cell game.PreparedCell,
	mut t dialogue.Talk,
	mut rs game.Residents,
	mut p game.Player,
	folder str
):
	cast = cell.head.cast
	s = save.startSession(freshDir(folder), t, rs, cast, p, none, rs.graph.newWalker(true),
		cell.physics.world)
	t.changeThings(rs, cast, p, 0.0)
	saved = t.capture(rs, cast, p, none, rs.graph.newWalker(true), cell.physics.world)
	written = s.saveGame(t, rs, cast, p, save.kindSave, none, none) ?? fail("the save failed")
	(s, saved, written)

test "a game saved, changed and loaded again is the game saved, whole, field by field":
	cell, t, rs, p = startedGame() ?? return
	cast = cell.head.cast
	s, saved, written = cell.playedAndSaved(t, rs, p, "whole")
	expect fs.exists(written.file) and written.header.saveNumber == 1
	t.changeThings(rs, cast, p, 40.0)
	expect t.capture(rs, cast, p, none, rs.graph.newWalker(true), cell.physics.world).toJson() !=
		saved.toJson()
	s.loadGame(t, rs, cast, p, written) ?? fail("the load failed")
	back = t.capture(rs, cast, p, none, rs.graph.newWalker(true), cell.physics.world)
	expect back.differing(saved).isEmpty
	expect back.toJson() == saved.toJson()

test "the save holds a change form of every type the game writes, and a new game none":
	cell, t, rs, p = startedGame() ?? return
	cast = cell.head.cast
	walker = rs.graph.newWalker(true)
	s = save.startSession(freshDir("types"), t, rs, cast, p, none, walker, cell.physics.world)
	fresh = save.readEss(s.saveBytes(t, rs, cast, p, none, walker, cell.physics.world, 1, none)) ??
		fail("a new game does not save")
	expect fresh.changes.isEmpty and fresh.blocks.len == 9
	t.changeThings(rs, cast, p, 0.0)
	changed = save.readEss(
		s.saveBytes(t, rs, cast, p, none, walker, cell.physics.world, 2, none)
	) ??
		fail("the save does not read")
	kinds = distinct(changed.changes.map(.kind))
	expect kinds == [save.typeRefr, save.typeAchr, save.typeInfo, save.typeQust, save.typeBook,
		save.typeFurn, save.typeFact]
	parts = distinct(changed.changes.map(.part))
	expect parts == (0..12).map(it)
	expect changed.changes.any(.refId == 0x14 and .part == save.partResident) == false
	expect changed.changes.any(.refId >> 24 == 0xFF)   # the thing made in play

test "a save loads into a game that has not played, VM threads and all, and the game goes on":
	cell, played, rs, p = startedGame() ?? return
	cast = cell.head.cast
	_, saved, written = cell.playedAndSaved(played, rs, p, "fresh")
	t = dialogue.talkOfArchives(inn) ?? return
	other = cell.residentsAt(8.0)
	q = cast.start.newPlayer(cast.heading, other.gaits[0])
	second = save.startSession(fs.dirOf(written.file), t, other, cast, q, none,
		other.graph.newWalker(true), cell.physics.world)
	second.loadGame(t, other, cast, q, written) ?? fail("the load failed")
	expect t.capture(other, cast, q, none, other.graph.newWalker(true), cell.physics.world)
		.differing(saved).isEmpty
	expect t.vm.rt.threads.len == 1 and t.vm.rt.threads[0].label == "savetest"
	# the test's own update, beside those the new game's quests registered
	expect t.vm.rt.updates.count(.object == 1) == 1 and
		(t.vm.rt.objects[1].vars.get("savetest") ?? .None) is Int(n) and n == 42
	t.vm.tick(0.5)
	expect t.vm.rt.threads.len == 1
	expect t.vm.rt.world.daysPassed > saved.misc.daysPassed

test "the saves of the folder: numbered, the newest first, the quicksave replaced, one overwritten or deleted":
	cell, t, rs, p = startedGame() ?? return
	cast = cell.head.cast
	dir = freshDir("files")
	s = save.startSession(dir, t, rs, cast, p, none, rs.graph.newWalker(true), cell.physics.world)
	first = s.saveGame(t, rs, cast, p, save.kindSave, none, none) ?? fail("save 1")
	t.vm.rt.world.playSeconds += 8_640.0
	quick = s.quickSave(t, rs, cast, p, none) ?? fail("quicksave")
	again = s.quickSave(t, rs, cast, p, none) ?? fail("the second quicksave")
	third = s.saveGame(t, rs, cast, p, save.kindSave, none, none) ?? fail("save 3")
	listed = save.listSaves(dir)
	expect listed.map(.header.saveNumber) == [4, 3, 1] and again.header.saveNumber == 3
	expect listed.map(.kind.copy()) == [save.kindSave, save.kindQuick, save.kindSave]
	expect not fs.exists(quick.file) or quick.file == again.file
	expect first.header.name == "Dragonborn" and first.header.location == "Sleeping Giant Inn"
	expect first.header.level == 1 and first.header.race == "NordRace" and first.header.filetime > 0
	expect third.header.playTime == "000.02.24"
	over = s.saveGame(t, rs, cast, p, save.kindSave, first, none) ?? fail("overwriting")
	expect over.header.saveNumber == 1 and save.listSaves(dir).len == 3
	over.deleteSave() ?? fail("deleting")
	expect save.listSaves(dir).map(.header.saveNumber) == [4, 3]
	t.vm.rt.world.actors[0x14].damageValue("health", 10.0)
	s.quickLoad(t, rs, cast, p) ?? fail("quickload")
	expect t.vm.rt.world.actors[0x14].valueOf("health") == 100.0

test "the game is not saved in combat":
	cell, t, rs, p = startedGame() ?? return
	cast = cell.head.cast
	s = save.startSession(freshDir("combat"), t, rs, cast, p, none, rs.graph.newWalker(true),
		cell.physics.world)
	rs.all[0].fighting = true
	expect not failure(s.saveGame(t, rs, cast, p, save.kindSave, none, none)).isEmpty

# one save of the player's, as the journal lists it
fn listedSave():
	h = save.Header(saveNumber = 1, name = "Dragonborn", level = 3, location = "Sleeping Giant Inn",
		playTime = "000.01.00", race = "NordRace", female = false, filetime = 134_370_000_000_000_000)
	save.Listed(file = "Save1.ess", kind = save.kindSave, header = h)

noSaves save.Listed[] = []

# the journal opened on its system page over these saves; none without the install
fn openedJournal(saves save.Listed[]) avm1.Player?:
	t = try archivesTalk()
	install = skyrim.openInstall(skyrim.defaultInstall) ?? return none
	texts = install.openTexts(t.vm.rt.world.settings) ?? fail("no texts")
	p = install.openJournal(
		texts,
		t.vm.rt.world,
		saves,
		install.openPrefs(""),
		1280,
		960
	) ??
		fail("no journal")
	loop 30:
		p.advance()
	p

# a key pressed in the page and its frames run; what the page asked of the game, answered as the
# game answers, and the request that makes
fn pressed(mut p avm1.Player, saves save.Listed[], key engine.Key):
	p.press(key)
	asked interface.Request? = none
	loop 30:
		p.advance()
	for c in p.takeExternal():
		if p.answerSaveCall(c, saves) is request: asked = request
	loop 30:
		p.advance()
	asked

fn selectedCategory(mut p avm1.Player):
	p
		.read("QuestJournalFader.Menu_mc.SystemFader.Page_mc.CategoryList.selectedEntry.text")
		.primitiveText()

test "a file time is written as the date and time in UTC it stands for":
	expect save.filetimeText(116_444_736_000_000_000) == "1970-01-01 00:00"
	expect save.filetimeText(134_370_000_000_000_000) == "2026-10-20 20:00"
	expect save.filetimeText(132_538_518_000_000_000) == "2020-12-31 01:30"

test "the journal's system page: Quicksave asks for a quicksave, Save for a new save, and Load lists the saves and asks for the one chosen after its confirmation":
	saves = [listedSave()]
	p = openedJournal(saves) ?? return
	expect p.selectedCategory() == "$QUICKSAVE"
	expect p.pressed(saves, .Enter) is QuickSave
	p = openedJournal(saves) ?? return
	expect p.pressed(saves, .Down) == none
	expect p.pressed(saves, .Down) == none
	expect p.selectedCategory() == "$LOAD"
	expect p.pressed(saves, .Enter) == none
	list = "QuestJournalFader.Menu_mc.SystemFader.Page_mc.SaveLoadListHolder.List_mc.entryList"
	expect i64(p.read("{list}.length").primitiveNumber()) == 1
	expect p.read("{list}.0.text").primitiveText() == "Save 1"
	expect p.read("{list}.0.name").primitiveText() == "Dragonborn, Sleeping Giant Inn"
	expect p.read("{list}.0.dateString").primitiveText() == "2026-10-20 20:00"
	expect p.pressed(saves, .Enter) == none   # the page asks the game whether it may load
	expect p.pressed(saves, .Enter) is Load(at) and at == 0

test "the journal's Save page offers a new save first, and Quit asks before it quits":
	saves = [listedSave()]
	p = openedJournal(saves) ?? return
	expect p.pressed(saves, .Down) == none
	expect p.pressed(saves, .Enter) == none
	list = "QuestJournalFader.Menu_mc.SystemFader.Page_mc.SaveLoadListHolder.List_mc.entryList"
	expect i64(p.read("{list}.length").primitiveNumber()) == 2
	expect p.pressed(saves, .Enter) is Save(at) and at == -1
	q = openedJournal(saves) ?? return
	loop 8:
		q.press(.Down)
		loop 8:
			q.advance()
	expect q.selectedCategory() == "$QUIT"
	expect q.pressed(saves, .Enter) == none
	expect q.pressed(saves, .Down) == none
	expect q.pressed(saves, .Enter) == none   # the confirmation first
	expect q.pressed(saves, .Enter) is Quit

# a fight scene of the inn from the install: the actors as the game rates them, the player's
# fists, Orgnar a foe
fn innFightScene() game.FightScene?:
	install, plugin = try skyrim.installAndPlugin()
	names = install.readNames("Skyrim.esm") ?? fail("no names")
	w = install.worldOfCell(plugin, names, inn) ?? fail("no world")
	f = plugin.sceneFight(w, install.timingsOf() ?? fail("no timings"), 1) ?? fail("no fight")
	game.newFightScene(f)

# the inn at 8 with its fight, the skeletons' rigs and the player's animator; none without the
# install
fn fightStart() (
	game.PreparedCell,
	dialogue.Talk,
	game.Residents,
	game.Player,
	game.FightScene?,
	engine.Rig[],
	game.Walker
)?:
	cell, t, rs, p = try startedGame()
	fight game.FightScene? = try innFightScene()
	rigs = cell.head.cast.skeletons.map(.skeletonRig())
	walker = rs.graph.newWalker(true)
	(cell, t, rs, p, fight, rigs, walker)

tick f32 = 1.0 / 60.0

# the player stood a step from Orgnar, facing him
fn standBesideOrgnar(rs game.Residents, cast world.CastHead, mut p game.Player):
	orgnar = rs.all[rs.residentNamed(cast, "Orgnar")].body.feetOf()
	p.placeBody(save.SavedBody(feet = orgnar + Vec3(-60.0, 0.0, 0.0), falling = 0.0, onFloor = true,
		heading = 1.5708, gait = 0.0, cycle = 0.0, idleTime = 0.0))

# One frame of the inn at 8 with the fight: the player draws at frame 0 and swings at frame 8, and
# Delphine is killed at frame 12 (her ragdoll falls from where she stood).
fn playFrame(
	mut scene game.FightScene,
	mut cell game.PreparedCell,
	mut rs game.Residents,
	mut p game.Player,
	mut walker game.Walker,
	rigs engine.Rig[],
	count i64
):
	cast = cell.head.cast
	evaluate {i64: bool} = {}
	rs.stepResidents(cast, 8.0, 20.0, evaluate, p.feetOf(), cell.physics.world, tick)
	input = game.Input(
		forward = 0.0,
		right = 0.0,
		run = false,
		look = IVec2(0, 0),
		draw = count == 0,
		attack = count >= 5 and count < 8,
		block = false
	)
	scene.stepFight(rs, cast, p, walker, input, p.heading, rigs, cell.physics.world, tick)
	if count == 12: rs.killNamed(cast, "Delphine", rigs, cell.physics.world, tick)
	cell.physics.world.step(tick)

# the snapshot of the game as it stands, with its scene
fn captured(
	t dialogue.Talk,
	rs game.Residents,
	cast world.CastHead,
	p game.Player,
	fight game.FightScene?,
	walker game.Walker,
	cell game.PreparedCell
):
	t.capture(rs, cast, p, fight, walker, cell.physics.world)

test "a fight in progress is saved and loaded: each fighter's state, the fight's clock and dice, the player's swing, the animators":
	cell, t, rs, p, fight, rigs, walker = fightStart() ?? return
	cast = cell.head.cast
	s = save.startSession(
		freshDir("fightround"),
		t,
		rs,
		cast,
		p,
		fight,
		walker,
		cell.physics.world
	)
	rs.standBesideOrgnar(cast, p)
	for count in 0..14:
		fight?.playFrame(cell, rs, p, walker, rigs, count)
	saved = t.captured(rs, cast, p, fight, walker, cell)
	f = fight ?? fail("no fight")
	me = f.player
	foe = f.fight.fighterNamed("Orgnar") ?? fail("no Orgnar")
	expect f.fight.fighters[me].mode == .Swing and f.fight.fighters[me].swing != none
	expect f.drawn and f.fight.time > 0.2
	expect not saved.fighters.isEmpty and saved.fight.present and saved.fight.drawn
	written = s.saveGameIn(t, rs, cast, p, fight, walker, cell.physics.world, save.kindSave, none,
		none) ?? fail("a fight in progress is not saved")
	for count in 14..60:
		fight?.playFrame(cell, rs, p, walker, rigs, count)
	expect t.captured(rs, cast, p, fight, walker, cell).fight.toJson() != saved.fight.toJson()
	snap = s.loadGameIn(t, rs, cast, p, walker, cell.physics.world, written) ??
		fail("the load failed")
	fight?.restoreFight(snap)
	back = t.captured(rs, cast, p, fight, walker, cell)
	expect back.differing(saved).isEmpty
	loaded = fight ?? fail("no fight")
	for x in [me, foe]:
		refId = loaded.fight.fighters[x].refId
		expect loaded.fight.fighters[x].toBytes() == saved.fighters[refId].toBytes()
	expect loaded.fight.time == saved.fight.time and loaded.fight.rng.state == saved.fight.rng

test "a dead actor's ragdoll is saved and laid again in a game that has not played: every body's pose and motion":
	cell, t, rs, p = startedGame() ?? return
	cast = cell.head.cast
	rigs = cast.skeletons.map(.skeletonRig())
	walker = rs.graph.newWalker(true)
	s = save.startSession(freshDir("ragdoll"), t, rs, cast, p, none, walker, cell.physics.world)
	evaluate {i64: bool} = {}
	loop 10:
		rs.stepResidents(cast, 8.0, 20.0, evaluate, cast.start, cell.physics.world, tick)
		cell.physics.world.step(tick)
	expect rs.killNamed(cast, "Orgnar", rigs, cell.physics.world, tick)
	loop 25:
		rs.stepResidents(cast, 8.0, 20.0, evaluate, cast.start, cell.physics.world, tick)
		cell.physics.world.step(tick)
	lying = rs.fallen[0].ragdoll.bodies.map(cell.physics.world.bodies[it].copy())
	expect lying.any(not .asleep) and lying.any(.velocity.length() > 1.0)
	saved = t.captured(rs, cast, p, none, walker, cell)
	expect saved.fallen.len == 1 and saved.fallen.values()[0].bodies.len == lying.len
	written = s.saveGameIn(t, rs, cast, p, none, walker, cell.physics.world, save.kindSave, none,
		none) ?? fail("the save failed")
	cell2 = readInnCell() ?? return
	t2 = dialogue.talkOfArchives(inn) ?? return
	rs2 = cell2.residentsAt(8.0)
	p2 = cast.start.newPlayer(cast.heading, rs2.gaits[0])
	walker2 = rs2.graph.newWalker(true)
	later = save.startSession(fs.dirOf(written.file), t2, rs2, cast, p2, none, walker2,
		cell2.physics.world)
	expect rs2.fallen.isEmpty
	later.loadGameIn(t2, rs2, cast, p2, walker2, cell2.physics.world, written) ??
		fail("the load failed")
	expect rs2.fallen.len == 1 and rs2.fallen[0].resident == rs.fallen[0].resident
	expect rs2.fallen[0].ragdoll.bodies == rs.fallen[0].ragdoll.bodies
	laid = rs2.fallen[0].ragdoll.bodies
	for k, body in laid:
		b = cell2.physics.world.bodies[body]
		was = lying[k]
		expect b.position == was.position and b.orientation == was.orientation and
			b.velocity == was.velocity and b.spin == was.spin and b.asleep == was.asleep
	expect t2.captured(rs2, cast, p2, none, walker2, cell2).differing(saved).isEmpty

test "the Havok clutter's moved bodies are saved with their transform and velocity, and only those":
	cell, t, rs, p = startedGame() ?? return
	cast = cell.head.cast
	walker = rs.graph.newWalker(true)
	s = save.startSession(freshDir("clutter"), t, rs, cast, p, none, walker, cell.physics.world)
	w = mut ref cell.physics.world
	first = w.bodies.findIndex(.group == 0 and .invMass > 0.0) ?? fail("no clutter")
	second = (first + 1..w.bodies.len).find(
		w.bodies[it].group == 0 and w.bodies[it].invMass > 0.0
	) ??
		fail("one piece of clutter")
	w.bodies[first].position += Vec3(30.0, -12.0, 40.0)
	w.bodies[first].velocity = Vec3(1.0, 2.0, 3.0)
	w.bodies[first].asleep = false
	w.bodies[second].orientation = Quat(0.0, 0.0, 0.7071068, 0.7071068)
	w.bodies[second].spin = Vec3(0.0, 0.5, 0.0)
	position = w.bodies[first].position
	velocity = w.bodies[first].velocity
	orientation = w.bodies[second].orientation
	spin = w.bodies[second].spin
	changed = save.readEss(
		s.saveBytes(t, rs, cast, p, none, walker, cell.physics.world, 1, none)
	) ??
		fail("the save does not read")
	poses = changed.changes.filter(.part == save.partPose)
	expect poses.map(.refId).sorted() == [save.havokRefs + first, save.havokRefs + second]
	written = s.saveGameIn(t, rs, cast, p, none, walker, cell.physics.world, save.kindSave, none,
		none) ?? fail("the save failed")
	w.bodies[first].position = Vec3(0.0, 0.0, 0.0)
	w.bodies[first].velocity = Vec3(0.0, 0.0, 0.0)
	w.bodies[second].orientation = Quat(0.0, 0.0, 0.0, 1.0)
	w.bodies[second].spin = Vec3(0.0, 0.0, 0.0)
	s.loadGameIn(t, rs, cast, p, walker, w, written) ?? fail("the load failed")
	expect w.bodies[first].position == position and w.bodies[first].velocity == velocity
	expect w.bodies[second].orientation == orientation and w.bodies[second].spin == spin

test "the play time is the real seconds played, in the save's header and across a load":
	cell, t, rs, p = startedGame() ?? return
	cast = cell.head.cast
	walker = rs.graph.newWalker(true)
	s = save.startSession(freshDir("playtime"), t, rs, cast, p, none, walker, cell.physics.world)
	loop 600:
		t.vm.tick(0.25)
	expect t.vm.rt.world.playSeconds == 150.0
	written = s.saveGameIn(t, rs, cast, p, none, walker, cell.physics.world, save.kindSave, none,
		none) ?? fail("the save failed")
	expect written.header.playTime == "000.00.02"
	t.vm.rt.world.playSeconds = 90_000.0
	s.loadGameIn(t, rs, cast, p, walker, cell.physics.world, written) ??
		fail("the load failed")
	expect t.vm.rt.world.playSeconds == 150.0
	t.vm.tick(0.5)
	expect t.vm.rt.world.playSeconds == 150.5

test "a game saved mid-swing and mid-fall and loaded steps to the state the unsaved run reaches":
	cell, t, rs, p, fight, rigs, walker = fightStart() ?? return
	cast = cell.head.cast
	s = save.startSession(freshDir("midfight"), t, rs, cast, p, fight, walker, cell.physics.world)
	rs.standBesideOrgnar(cast, p)
	for count in 0..20:
		fight?.playFrame(cell, rs, p, walker, rigs, count)
	f = fight ?? fail("no fight")
	expect f.fight.fighters[f.player].mode == .Swing and rs.fallen.len == 1
	expect not rs.fallen[0].ragdoll.bodies.all(cell.physics.world.bodies[it].asleep)
	written = s.saveGameIn(t, rs, cast, p, fight, walker, cell.physics.world, save.kindSave, none,
		none) ?? fail("the save failed")
	atSave = t.captured(rs, cast, p, fight, walker, cell)
	for count in 20..50:
		fight?.playFrame(cell, rs, p, walker, rigs, count)
	unsaved = t.captured(rs, cast, p, fight, walker, cell)
	expect unsaved.differing(atSave).len >= 3
	snap = s.loadGameIn(t, rs, cast, p, walker, cell.physics.world, written) ??
		fail("the load failed")
	fight?.restoreFight(snap)
	expect t.captured(rs, cast, p, fight, walker, cell).differing(atSave).isEmpty
	for count in 20..50:
		fight?.playFrame(cell, rs, p, walker, rigs, count)
	again = t.captured(rs, cast, p, fight, walker, cell)
	expect again.differing(unsaved).isEmpty
	expect again.toJson() == unsaved.toJson()
