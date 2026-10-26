# The interface's movies read from the player's install; skipped quietly without it.

import engine.swf
import engine.swf.avm1
import fs
import game.sim
import image
import interface
import papyrus
import reference
import save
import skyrim
import skyrim.esm

# the install, none without it
fn opened() skyrim.Install?:
	if not fs.exists(skyrim.defaultInstall): return none
	skyrim.openInstall(skyrim.defaultInstall) ?? fail

test "every movie of the interface reads whole: no tag cut short, the unknown ones only counted":
	install = opened() ?? return
	keys = install.movieKeys()
	expect keys.len > 50
	for key in keys:
		movie = install.openMovie(key) ?? fail
		expect movie.problems.isEmpty
		expect movie.stageSize().x > 0.0 and movie.tagCounts.len > 1
		if key.endsWith(".gfx"): expect movie.signature == "CFX" or movie.signature == "GFX"

test "hudmenu.swf has the HUD's named instances, and its bitmaps decode":
	install = opened() ?? return
	p = install.openHud(1280, 720) ?? fail
	for path in [
		"HUDMovieBaseInstance",
		"HUDMovieBaseInstance.CompassShoutMeterHolder",
		"HUDMovieBaseInstance.CompassShoutMeterHolder.Compass.DirectionRect",
		"HUDMovieBaseInstance.CompassShoutMeterHolder.ShoutMeterInstance",
		"HUDMovieBaseInstance.Health.HealthMeter_mc",
		"HUDMovieBaseInstance.Magica.MagickaMeter_mc",
		"HUDMovieBaseInstance.Stamina.StaminaMeter_mc",
		"HUDMovieBaseInstance.Crosshair"
	]:
		expect p.m.stage.nodeAt(path) != none
	movie = ref p.prog.scene.movie
	expect movie.bitmaps.len > 100
	for id in movie.bitmaps.keys():
		img = movie.bitmaps[id].decodeBitmap(movie.jpegTables) ?? fail
		expect img.width > 0 and img.height > 0
	expect p.prog.scene.libraries.len == 3 and "$EverywhereMediumFont" in p.prog.scene.fontMap

test "the JPEG bitmaps of sharedcomponents.swf decode with the movie's tables":
	install = opened() ?? return
	movie = install.openMovie("interface/sharedcomponents.swf") ?? fail
	jpegs = 0
	for id in movie.bitmaps.keys():
		b = movie.bitmaps[id]
		if b.tag != 6: continue
		img = b.decodeBitmap(movie.jpegTables) ?? fail
		expect img.width > 0 and img.height > 0
		jpegs += 1
	expect jpegs == 2

# a node's bounds in the window's pixels
fn windowBounds(p avm1.Player, path str):
	n = p.m.stage.nodeAt(path) ?? fail("no {path}")
	matrix = p.prog.toScreen(p.m).times(p.m.stage.stageMatrix(n))
	p.prog.scene.boundsOf(p.m.stage, n, matrix) ?? fail("{path} has no bounds")

test "the text fields of containermenu.swf carry the game's drop shadow: black, 2 pixels away at 45 degrees":
	install = opened() ?? return
	movie = install.openMovie("interface/containermenu.swf") ?? fail
	shadows = []
	for id in movie.sprites.keys().sorted():
		for frame in movie.sprites[id].timeline.frames:
			for c in frame.commands:
				if c is Place(p) and p.filters is list: shadows.extend(list)
	expect shadows.len >= 4 and shadows.all(.kind == 0)
	expect shadows.all((.distance - 2.0).abs() < 0.01 and (.angle - 0.7854).abs() < 0.01)
	expect shadows.all(.color == Vec4(0.0, 0.0, 0.0, 1.0) and .blurX == 2.0)

noSaves save.Listed[] = []

# the journal's frames run
fn runJournal(mut p avm1.Player, frames i64):
	loop frames:
		p.advance()

test "the journal's system page shows the game's version, and its help list the topics of the plugin with their texts":
	vm, texts = innWorld() ?? return
	install = opened() ?? return
	p = install.openJournal(
		texts,
		vm.rt.world,
		noSaves,
		install.openPrefs(""),
		1280,
		960
	) ??
		fail
	page = "QuestJournalFader.Menu_mc.SystemFader.Page_mc"
	p.runJournal(30)
	expect p.read("{page}.VersionText.text").primitiveText() == "1.7.104.0"
	loop 10:
		if p.read("{page}.CategoryList.selectedEntry.text").primitiveText() == "$HELP": break
		p.press(.Down)
		p.runJournal(8)
	expect p.read("{page}.CategoryList.selectedEntry.text").primitiveText() == "$HELP"
	p.press(.Enter)
	p.runJournal(30)
	list = "{page}.HelpList.entryList"
	count = p.numberIn("{list}.length")
	expect count > 20
	first = p.read("{list}.0.text").primitiveText()
	expect first == "Alchemy" or first == "Alchemy Lab"
	p.press(.Enter)
	p.runJournal(30)
	expect p.read("{page}.HelpTitleText.text").primitiveText() == first
	expect p.read("{page}.HelpText.textField.text").primitiveText().len > 100

test "the HUD runs 60 frames of its ActionScript, its meters at the percent the game sets":
	install = opened() ?? return
	p = install.openHud(1280, 960) ?? fail
	state = interface.HudState(health = 40.0, magicka = 70.0, stamina = 100.0)
	loop 60:
		p.updateHud(state)
		p.advance()
	expect p.m.errors == 0 and p.m.unimplemented.isEmpty
	base = "HUDMovieBaseInstance"
	for (meter, want) in [
		("HealthMeterLeft", 40.0),
		("MagickaMeter", 70.0),
		("StaminaMeter", 100.0)
	]:
		got = p.read("{base}.{meter}.CurrentPercent")
		expect got is Num(x) and x.isClose(want, 0.5)

test "at 4:3 the HUD's three meters sit apart along the bottom of the window":
	install = opened() ?? return
	p = install.openHud(1280, 960) ?? fail
	loop 10:
		p.updateHud(interface.HudState())
		p.advance()
	boxes = ["Magica.MagickaMeter_mc", "Health.HealthMeter_mc", "Stamina.StaminaMeter_mc"].map(
		p.windowBounds("HUDMovieBaseInstance.{it}"))
	for k in 0..boxes.len:
		expect boxes[k].xmin >= 0.0 and boxes[k].xmax <= 1280.0 and boxes[k].ymax <= 960.0
		expect boxes[k].ymin > 800.0
		if k > 0: expect boxes[k - 1].xmax < boxes[k].xmin

test "the message box shows the text and the buttons the game gives it":
	install = opened() ?? return
	p = install.openPlayer("interface/messagebox.swf", 1280, 720) ?? fail
	p.delegateText("setMessageText('Wait here?', false)")
	p.delegateText("setButtons(0, 'Yes', 'No')")
	p.advance()
	field = p.m.stage.nodeAt("MessageMenu.MessageText") ?? fail("no MessageText")
	expect p.m.stage.nodes[field].text == "Wait here?" and p.m.errors == 0
	expect p.read("MessageMenu.MessageButtons.length") == .Num(2.0)

test "every menu's code uses only actions the machine runs, and runs without an error":
	install = opened() ?? return
	for name in ["hudmenu", "dialoguemenu", "inventorymenu", "containermenu", "bartermenu",
		"messagebox", "sleepwaitmenu", "cursormenu", "fadermenu"]:
		key = "interface/{name}.swf"
		movie = install.openMovie(key) ?? fail
		expect movie.unknownActions().isEmpty
		p = install.openPlayer(key, 1280, 720) ?? fail
		loop 5:
			p.advance()
		expect p.m.errors == 0 and p.m.unimplemented.isEmpty

# the rows of the capture where the health meter's red fill is, around the stage's middle
fn redRows(img image.Image):
	first = -1
	last = -1
	for y in img.height / 2..img.height:
		p = img[img.width / 2, y]
		if p.r > 150 and p.g < 60 and p.b < 60:
			if first < 0: first = y
			last = y
	(first, last)

test "the HUD's health meter stands where the game's own capture at 1280x960 shows it":
	reference = "projects/skyrim/assets/reference/hud.png"
	install = opened() ?? return
	if not fs.exists(reference): return
	first, last = image.loadPng(reference).redRows()
	expect first > 0
	p = install.openHud(1280, 960) ?? fail
	loop 10:
		p.updateHud(interface.HudState(health = 70.0, magicka = 70.0, stamina = 70.0))
		p.advance()
	fill = p.windowBounds("HUDMovieBaseInstance.Health.HealthMeter_mc")
	middle = f32(first + last + 1) * 0.5
	expect ((fill.ymin + fill.ymax) * 0.5 - middle).abs() < 3.0

# the inn's world as a new game has it and the texts its menus read, none without the install
fn innWorld() (papyrus.Vm, interface.GameTexts)?:
	install = try opened()
	plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
	names = install.readNames("Skyrim.esm") ?? fail
	vm = papyrus.cellVm(install, plugin, names, "RiverwoodSleepingGiantInn") ?? fail
	texts = interface.openTexts(opened() ?? fail("no install"), vm.rt.world.settings) ?? fail
	(vm, texts)

# a row of an item menu's list as the movie holds it
type Row:
	text str
	count i64
	equipState i64
	filterFlag i64

fn numberIn(mut p avm1.Player, path str) i64:
	i64(p.read(path).primitiveNumber())

# the menu's frames run until it has drawn, without an error
fn settle(mut p avm1.Player):
	loop 20:
		p.advance()
	expect p.m.errors == 0

# the rows of the menu's item list
fn rowsOf(mut p avm1.Player):
	list = "Menu_mc.InventoryLists_mc.ItemsList.entryList"
	out = []
	for k in 0..p.numberIn("{list}.length"):
		out.push(Row(text = p.read("{list}.{k}.text").primitiveText(),
			count = p.numberIn("{list}.{k}.count"),
			equipState = p.numberIn("{list}.{k}.equipState"),
			filterFlag = p.numberIn("{list}.{k}.filterFlag")))
	out

# the filter bits of the category the list names so, 0 for none
fn categoryFlag(mut p avm1.Player, name str):
	list = "Menu_mc.InventoryLists_mc.CategoriesList.entryList"
	for k in 0..p.numberIn("{list}.length"):
		if p.read("{list}.{k}.text").primitiveText() == name: return p.numberIn("{list}.{k}.flag")
	0

test "the inventory menu fed from a new game shows the Roughspun Tunic and Footwraps worn, under Apparel":
	vm, texts = innWorld() ?? return
	install = opened() ?? return
	menu = install.openInventory(texts, vm.rt.world, 1280, 960) ?? fail
	menu.p.settle()
	apparel = menu.p.categoryFlag("APPAREL")
	expect apparel != 0
	rows = menu.p.rowsOf()
	for name in ["Roughspun Tunic", "Footwraps"]:
		expect rows.any(.text == name and .equipState == 1 and (.filterFlag & apparel) != 0)
	expect rows[0].text == "Footwraps"

test "the inventory menu's own PlaySound calls reach the world's sound queue as the movie asks them":
	vm, texts = innWorld() ?? return
	install = opened() ?? return
	menu = install.openInventory(texts, vm.rt.world, 1280, 960) ?? fail
	menu.p.settle()
	menu.answer(texts, vm.rt.world)
	expect vm.rt.world.takeSoundAsks().map(.name.copy()) == ["UIMenuBladeOpenSD"]
	menu.p.press(.Down)
	menu.p.settle()
	menu.answer(texts, vm.rt.world)
	expect vm.rt.world.takeSoundAsks().map(.name.copy()) == ["UIMenuFocus"]
	menu.p.press(.Right)
	menu.p.settle()
	menu.answer(texts, vm.rt.world)
	expect vm.rt.world.takeSoundAsks().map(.name.copy()) == ["UIMenuBladeOpenSD"]

test "the container menu of the food barrel by the bar shows its five cabbages, taking them a theft":
	vm, texts = innWorld() ?? return
	install = opened() ?? return
	menu = install.openContainer(texts, vm.rt.world, 0x3_6C37, 1280, 960) ?? fail
	loop 20:
		menu.p.advance()
	rows = menu.p.rowsOf()
	expect rows.any(.text == "Cabbage" and .count == 5)
	stealing = menu.p.read("Menu_mc.InventoryLists_mc.ItemsList.entryList.0.isStealing")
	expect stealing == .Bool(true)
	menu.p.press(.Right)
	loop 10:
		menu.p.advance()
	menu.p.press(.Enter)
	menu.answer(texts, vm.rt.world)
	expect vm.rt.world.inventories[vm.rt.world.player].countOf(0x6_4B3F) == 5
	expect vm.rt.world.crimes.len == 1

test "the barter menu of Orgnar lists his stock and the player's items, Enter buying the stack of ales with the gold at the formula's price":
	vm, texts = innWorld() ?? return
	install = opened() ?? return
	orgnar = 0x1_3486
	menu = install.openBarter(texts, vm.rt.world, orgnar, 1280, 960) ?? fail
	menu.p.settle()
	rows = menu.p.rowsOf()
	expect rows[0].text == "Ale" and rows[0].count == 7
	expect rows.any(.count == 10 and .filterFlag == 1024) and not rows.any(.text == "Gold")
	expect menu.p.read("Menu_mc.InventoryLists_mc.ItemsList.entryList.0.enabled") == .Bool(true)
	player = vm.rt.world.player
	gold = vm.rt.world.inventories[player].countOf(0xF)
	price = vm.rt.world.askingPrice(orgnar, vm.rt.world.items[0x3_4C5E])
	menu.p.press(.Enter)
	loop 10:
		menu.p.advance()
	menu.p.press(.Enter)
	menu.answer(texts, vm.rt.world)
	expect vm.rt.world.inventories[player].countOf(0x3_4C5E) == 7
	expect vm.rt.world.inventories[player].countOf(0xF) == gold - 7 * price
	expect vm.rt.world.inventories[0x7_8C0F].countOf(0x3_4C5E) == 0

test "the magic menu fed from a new game lists Flames under Destruction, Healing under Restoration, the Nord's battle cry under Powers":
	vm, texts = innWorld() ?? return
	install = opened() ?? return
	menu = install.openMagic(texts, vm.rt.world, 1280, 960) ?? fail
	menu.p.settle()
	rows = menu.p.rowsOf()
	expect rows.map(.text) == ["Battle Cry", "Flames", "Healing", "Resist Frost"]
	active = menu.p.categoryFlag("Active Effects")
	expect active != 0 and menu.p.categoryFlag("SHOUTS") != 0
	expect rows.any(.text == "Resist Frost" and .filterFlag == active)
	expect rows.all(.filterFlag != active or .text == "Resist Frost")
	effect = "Menu_mc.InventoryLists_mc.ItemsList.entryList.3.card"
	expect menu.p.read("{effect}.name").primitiveText() == "Resist Frost" and
		menu.p.read("{effect}.timeRemaining") == .Num(0.0)
	for (name, category) in [("Flames", "DESTRUCTION"), ("Healing", "RESTORATION"),
		("Battle Cry", "POWERS")]:
		flag = menu.p.categoryFlag(category)
		expect flag != 0 and rows.any(.text == name and (.filterFlag & flag) != 0)
	card = "Menu_mc.InventoryLists_mc.ItemsList.entryList.1.card"
	expect menu.p.read("{card}.spellCost") == .Num(14.0) and
		menu.p.read("{card}.castTime") == .Num(0.0)
	expect menu.p.read("{card}.castLevel").primitiveText() == "Novice"

test "the magic menu lists a potion the player drank under Active Effects with the seconds it has left":
	vm, texts = innWorld() ?? return
	install = opened() ?? return
	w = vm.rt.world
	fire = w.items.keys().find(w.items[it].name == "Potion of Resist Fire") ?? fail("no potion")
	w.consume(w.player, fire) ?? fail
	w.tickEffects(15.0)
	menu = install.openMagic(texts, w, 1280, 960) ?? fail
	menu.p.settle()
	rows = menu.p.rowsOf()
	active = menu.p.categoryFlag("Active Effects")
	expect rows.any(.text == "Resist Fire" and .filterFlag == active)
	card = "Menu_mc.InventoryLists_mc.ItemsList.entryList.{rows.len - 1}.card"
	expect menu.p.read("{card}.name").primitiveText() == "Resist Fire" and
		menu.p.read("{card}.timeRemaining") == .Num(45.0)

test "Enter in the magic menu puts the spell in the right hand, the left slot in the left, the same again takes it out":
	vm, texts = innWorld() ?? return
	install = opened() ?? return
	menu = install.openMagic(texts, vm.rt.world, 1280, 960) ?? fail
	player = vm.rt.world.player
	loop 20:
		menu.p.advance()
	menu.p.press(.Left)
	loop 10:
		menu.p.advance()
	menu.p.press(.Down)
	loop 10:
		menu.p.advance()
	menu.p.press(.Enter)
	menu.answer(texts, vm.rt.world)
	expect vm.rt.world.spellIn(player, false) == 0x1_2FCD
	menu.p.press(.Down)
	loop 10:
		menu.p.advance()
	menu.equipSelectedLeft(texts, vm.rt.world)
	expect vm.rt.world.spellIn(player, true) == 0x1_2FCC and
		vm.rt.world.spellIn(player, false) == 0x1_2FCD
	loop 10:
		menu.p.advance()
	expect menu.p.rowsOf().any(.text == "Flames" and .equipState == 3)
	menu.equipSelectedLeft(texts, vm.rt.world)
	expect vm.rt.world.spellIn(player, true) == 0

test "the favorites menu lists the favorite spells, Enter putting the chosen one in the right hand":
	vm, texts = innWorld() ?? return
	install = opened() ?? return
	player = vm.rt.world.player
	vm.rt.world.setFavoriteSpell(player, 0x1_2FCD, true)
	menu = install.openFavorites(texts, vm.rt.world, 1280, 960) ?? fail
	menu.p.settle()
	list = "MenuHolder.Menu_mc.List_mc.entryList"
	expect menu.p.numberIn("{list}.length") == 1
	expect menu.p.read("{list}.0.text").primitiveText() == "Flames"
	menu.p.press(.Enter)
	menu.answer(texts, vm.rt.world)
	expect vm.rt.world.spellIn(player, false) == 0x1_2FCD and not menu.open

test "a number key in the favorites menu puts the selected favorite on that hotkey, the same key again takes it off, the key outside the menu uses it":
	vm, texts = innWorld() ?? return
	install = opened() ?? return
	player = vm.rt.world.player
	vm.rt.world.setFavoriteSpell(player, 0x1_2FCD, true)
	vm.rt.world.setFavoriteSpell(player, 0x1_2FCC, true)
	menu = install.openFavorites(texts, vm.rt.world, 1280, 960) ?? fail
	menu.p.settle()
	list = "MenuHolder.Menu_mc.List_mc.entryList"
	keys = install.openInputMap("")
	expect keys.commandOf(.Char('3')) == "Hotkey3" and keys.commandOf(.Char('9')) == ""
	expect keys.commandOf(.Char('Q')) == "Favorites" and keys.commandOf(.Escape) == "Pause"
	menu.assignHotkey(texts, vm.rt.world, 2)
	loop 10:
		menu.p.advance()
	flames = menu.p.read("{list}.0.text").primitiveText()
	healing = menu.p.read("{list}.1.text").primitiveText()
	expect flames == "Flames" and healing == "Healing"
	expect vm.rt.world.hotkeyOf(player, 0x1_2FCD) == 2 and
		vm.rt.world.hotkeyOf(player, 0x1_2FCC) == -1
	expect menu.p.numberIn("{list}.0.hotkey") == 2
	menu.assignHotkey(texts, vm.rt.world, 0)
	expect vm.rt.world.hotkeyOf(player, 0x1_2FCD) == 0
	menu.assignHotkey(texts, vm.rt.world, 0)
	expect vm.rt.world.hotkeyOf(player, 0x1_2FCD) == -1
	menu.assignHotkey(texts, vm.rt.world, 5)
	expect vm.rt.world.useHotkey(player, 5) == none and
		vm.rt.world.spellIn(player, false) == 0x1_2FCD
	expect vm.rt.world.useHotkey(player, 5) == none and vm.rt.world.spellIn(player, false) == 0
	vm.rt.world.setFavoriteForm(player, 0x1_2FCD, false)
	expect vm.rt.world.hotkeyOf(player, 0x1_2FCD) == -1

# how close a menu came to the game's capture of it: the share of pixels within 8 (percent) and the
# largest mean difference of red, green and blue
type Floor:
	within f32
	mean f32

# long: one line a menu
menuFloors = {
	"inventory-open": Floor(within = 77.5, mean = 9.0),
	"inventory": Floor(within = 79.5, mean = 10.0),
	"container": Floor(within = 81.0, mean = 8.5),
	"system": Floor(within = 51.0, mean = 12.5),
	"sleepwait": Floor(within = 25.5, mean = 35.0),
	"messagebox": Floor(within = 78.5, mean = 29.0),
	"activate": Floor(within = 40.5, mean = 19.0),
	"tween": Floor(within = 23.5, mean = 31.5)
}

test "the menus drawn over the inn stay as close to the game's captures as they came":
	if opened() == none: return
	if not fs.exists("{reference.referenceDir}/menus/menus.json"): return
	for m in reference.menusIn("{reference.referenceDir}/menus/menus.json"):
		floor = menuFloors.get(m.name) ?? continue
		got = m.compareMenu()
		expect got.within >= floor.within
		expect got.mean.x <= floor.mean and got.mean.y <= floor.mean and got.mean.z <= floor.mean

test "a field made by createTextField takes a font and its text scrolls by scroll and maxscroll":
	install = opened() ?? return
	p = install.openHud(1280, 720) ?? fail
	p.invoke("_root.createTextField", [.Str("scrolled"), .Num(500.0), .Num(10.0), .Num(20.0),
		.Num(200.0), .Num(60.0)])
	expect p.read("scrolled").isObject()
	p.invoke("scrolled.setTextFormat", [p.newRecord([("font", .Str("$EverywhereFont")),
		("size", .Num(20.0))])])
	p.write("scrolled.text", .Str("a\rb\rc\rd\re\rf"))
	expect p.numberIn("scrolled.numLines") == 6
	maxscroll = p.numberIn("scrolled.maxscroll")
	expect maxscroll > 2 and maxscroll < 6
	expect p.numberIn("scrolled.scroll") == 1
	expect p.numberIn("scrolled.bottomScroll") == 7 - maxscroll
	p.write("scrolled.scroll", .Num(99.0))
	expect p.numberIn("scrolled.scroll") == maxscroll
	expect p.numberIn("scrolled.bottomScroll") == 6
	p.write("scrolled.scroll", .Num(2.0))
	expect p.numberIn("scrolled.scroll") == 2

# an empty folder for a test's own files
fn ownDirOf(name str):
	dir = "{testDir()}{name}"
	fs.deleteTree(dir) ?? fail
	dir

test "the settings pages' choices apply to the settings and save into the game's own folder":
	install = opened() ?? return
	dir = ownDirOf("prefs")
	prefs = interface.prefsOf(skyrim.IniSettings(values = {}), dir, install.openInputMap(""))
	p = install.openHud(1280, 720) ?? fail
	expect prefs.difficulty() == 2 and prefs.isOn("bShowCrosshair:Interface")
	# the display page's Crosshair (its place in the page) off, the gameplay page's Difficulty on Legendary
	ok = prefs.answerOptionCall(p, avm1.ExternalCall(name = "OptionChange",
		args = [.Num(0.0), .Num(102.0), .Num(0.0)]))
	expect ok and not prefs.isOn("bShowCrosshair:Interface") and prefs.revision == 1
	prefs.answerOptionCall(p, avm1.ExternalCall(name = "OptionChange",
		args = [.Num(0.0), .Num(3.0), .Num(5.0)]))
	expect prefs.difficulty() == 5
	prefs.answerOptionCall(p, avm1.ExternalCall(name = "OptionChange",
		args = [.Num(0.0), .Num(200.0), .Num(0.25)]))
	expect prefs.volumes()["audiocategorymaster"] == 0.25
	prefs.answerOptionCall(p, avm1.ExternalCall(name = "SaveSettings", args = [.Num(0.0)]))
	text = fs.readFile("{dir}/SkyrimPrefs.ini") ?? fail
	expect text.indexOf("bShowCrosshair=0") != none and text.indexOf("[Interface]") != none
	expect text.indexOf("iDifficulty=5") != none and
		text.indexOf("fAudioMasterVolume=0.2500") != none
	expect prefs.changed.isEmpty

test "difficulty multiplies a fight by the fDiffMult game settings":
	empty {str: f64} = {}
	expect empty.difficultyMultipliers(0).byPlayer == 2.0 and
		empty.difficultyMultipliers(0).toPlayer == 0.5
	expect empty.difficultyMultipliers(2).byPlayer == 1.0
	expect empty.difficultyMultipliers(5).toPlayer == 2.5 and
		empty.difficultyMultipliers(5).byPlayer == 0.25

test "the journal's settings page lists its options from the ini settings":
	vm, texts = innWorld() ?? return
	install = opened() ?? return
	prefs = interface.prefsOf(skyrim.IniSettings(values = {"idifficulty:gameplay": "4"}),
		ownDirOf("pagelist"), install.openInputMap(""))
	p = install.openJournal(texts, vm.rt.world, noSaves, prefs, 1280, 960) ?? fail
	page = "QuestJournalFader.Menu_mc.SystemFader.Page_mc"
	p.runJournal(30)
	loop 10:
		if p.read("{page}.CategoryList.selectedEntry.text").primitiveText() == "$SETTINGS": break
		p.press(.Down)
		p.runJournal(8)
	p.press(.Enter)
	p.runJournal(30)
	p.press(.Enter)
	p.runJournal(30)
	list = "{page}.OptionsListsPanel.OptionsLists.List_mc.entryList"
	count = p.numberIn("{list}.length")
	expect count > 5
	found = false
	for k in 0..count:
		if p.read("{list}.{k}.text").primitiveText() == "$Difficulty":
			found = true
			expect p.numberIn("{list}.{k}.value") == 4 and p.numberIn("{list}.{k}.defaultVal") == 2
	expect found

test "the controls list takes a key the player maps, and keeps it in the game's folder":
	vm, texts = innWorld() ?? return
	install = opened() ?? return
	dir = ownDirOf("controls")
	prefs = interface.prefsOf(skyrim.IniSettings(values = {}), dir, install.openInputMap(dir))
	p = install.openJournal(texts, vm.rt.world, noSaves, prefs, 1280, 960) ?? fail
	list = p.newList([])
	asked = avm1.ExternalCall(
		name = "StartRemapMode",
		args = [.Num(0.0), .Str("Jump"), list.copy()]
	)
	expect prefs.controls.answerInputCall(p, asked)
	expect prefs.controls.remapTo(p, .Char('J'))
	jump = prefs.controls.bindings.filter(.event == "Jump")[0]
	expect jump.key == 0x24
	asked = avm1.ExternalCall(
		name = "StartRemapMode",
		args = [.Num(0.0), .Str("Sprint"), list.copy()]
	)
	prefs.controls.answerInputCall(p, asked)
	prefs.controls.remapTo(p, .Escape)
	expect prefs.controls.bindings.filter(.event == "Sprint")[0].key == 0x38
	prefs.controls.answerInputCall(p, avm1.ExternalCall(name = "SaveControls", args = [.Num(0.0)]))
	again = install.openInputMap(dir)
	expect again.bindings.filter(.event == "Jump")[0].key == 0x24
	expect again.bindings.filter(.event == "Sprint")[0].key == 0x38

test "a book of the inn opens in book.swf, its pages turned two at a time and stopped at the cover":
	vm, texts = innWorld() ?? return
	install = opened() ?? return
	w = vm.rt.world
	books = w.items.keys().sorted().filter(
		(w.items[it].book?.textId ?? 0) != 0 and not (w.items[it].book?.note ?? true)
	)
	expect not books.isEmpty
	# the inn's longest book: several spreads
	book = books.maxBy((texts.descriptions.texts.get(w.items[it].book?.textId ?? 0) ?? "").len) ??
		fail("no book")
	b = install.openBook(texts, w, book, 0, 1280, 960) ?? fail
	# the movie paginates on an interval, a line at a time
	loop 120: b.p.advance()
	expect b.p.numberIn("BookMenu.BookMenuInstance.PageInfoA.length") > 4.0
	expect not b.turnPage(false)
	expect b.turnPage(true)
	expect b.p.numberIn("BookMenu.BookMenuInstance.iLeftPageNumber") == 2.0
	expect b.turnPage(false)
	expect b.p.numberIn("BookMenu.BookMenuInstance.iLeftPageNumber") == 0.0

test "a notice given to the HUD is queued and shown by its Messages":
	install = opened() ?? return
	p = install.openHud(1280, 720) ?? fail
	loop 5: p.advance()
	p.showNotice("This lock cannot be picked. It requires a key to open.")
	loop 30: p.advance()
	messages = "HUDMovieBaseInstance.MessagesInstance"
	expect p.numberIn("{messages}.MessageArray.length") +
		p.numberIn("{messages}.ShownMessageArray.length") >=
		1.0

# the stats menu's player card and the text of a field of it
statsCard = "StatsMenuBaseInstance.BottomBarInstance.BottomBarPlayerInfoInstance.PlayerInfoCardInstance"
statsTop = "StatsMenuBaseInstance.TopPlayerInfo"

# the stats menu opened and run until it has drawn: only the errors of its own loading (a clip it
# looks for before the game sets it up) are allowed
fn statsOf(mut texts interface.GameTexts, w sim.GameWorld) avm1.Player?:
	install = try opened()
	p = install.openStats(texts, w, "Dragonborn", 1280, 960) ?? fail
	loop 20:
		p.advance()
	expect p.m.errors == 8
	p

test "the stats menu lists the 18 skills with the player's values, names and progress, and its card the name, level, race and attributes":
	vm, texts = innWorld() ?? return
	w = vm.rt.world
	w.useSkill("onehanded", 60.0)
	w.actors[w.player].modValue("health", 20.0)
	w.actors[w.player].modValue("smithing", -5.0)
	w.actors[w.player].damageValue("stamina", 30.0)
	p = texts.statsOf(w) ?? return
	list = "StatsMenu.SkillStatsA"
	expect p.read("{list}.length") == .Num(90.0)
	expect p.read("{list}.0") == .Num(20.0) and p.read("{list}.1").primitiveText() == "One-handed"
	xp, need = w.skillProgress("onehanded")
	expect (p.read("{list}.2").primitiveNumber() - f64(xp / need * 100.0)).abs() < 0.001
	expect p.read("{list}.3").primitiveText() == "#FFFFFF" and p.read("{list}.4") == .Num(0.0)
	names = (0..18).map(p.read("{list}.{it * 5 + 1}").primitiveText())
	expect names.len == 18 and "Illusion" in names and "Speech" in names and "Archery" in names
	smithing = sim.skillNames.indexOf("smithing") ?? 0
	expect p.read("{list}.{smithing * 5}") == .Num(15.0)
	expect p.read("{list}.{smithing * 5 + 3}").primitiveText() == "#FF0000"
	expect p.read("{statsTop}.FirstLastLabel.text").primitiveText() == "Dragonborn"
	expect p.read("{statsTop}.LevelNumberLabel.text").primitiveText() == "1"
	expect p.read("{statsTop}.RacevalueLabel.text").primitiveText() == "Nord"
	health = p.read("{statsCard}.healthValue.htmlText").primitiveText()
	expect health == "<font color='#189515'>120/120</font>"
	expect p.read("{statsCard}.magicValue.htmlText").primitiveText() ==
		"<font color='#FFFFFF'>100/100</font>"
	stamina = p.read("{statsCard}.enduranceValue.htmlText").primitiveText()
	expect stamina == "<font color='#FFFFFF'>70/100</font>"

test "choosing a perk in the stats menu takes the perk and a perk point and tells the menu how many are left":
	vm, texts = innWorld() ?? return
	install = opened() ?? return
	plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
	names = install.readNames("Skyrim.esm") ?? fail
	w = vm.rt.world
	expect w.learnSkillTree(plugin, names, "onehanded")
	armsman = plugin.formByEditorId("PERK", "Armsman00") ?? fail("no Armsman")
	node = w.skillTrees["onehanded"].nodes.find(.perk == armsman) ?? fail("no Armsman node")
	w.progress.perkPoints = 2
	p = texts.statsOf(w) ?? return
	expect p.chooseSkillPerk(w, "onehanded", node.index) == none
	expect w.hasPerk(w.player, armsman) and w.progress.perkPoints == 1
	loop 5:
		p.advance()
	expect p.m.errors == 8
	expect p.chooseSkillPerk(w, "onehanded", 99_999) == "onehanded has no node 99999"
	expect w.progress.perkPoints == 1

test "the level-up menu's choices raise the attribute and the level, the tween menu telling the way to it":
	vm, texts = innWorld() ?? return
	install = opened() ?? return
	w = vm.rt.world
	w.progress.xp = 110.0
	expect w.canLevelUp()
	tween = install.openTween(texts, w, 1280, 960) ?? fail
	loop 20:
		tween.advance()
	expect tween.m.errors == 0
	menu = install.openLevelUp(1280, 960) ?? fail
	loop 20:
		menu.advance()
	for call in menu.takeExternal():
		expect w.answerLevelUp(call) == none
	expect w.actors[w.player].level == 1
	expect w.answerLevelUp(avm1.ExternalCall(name = "addMagicka", args = [])) == "magicka"
	a = w.actors[w.player]
	expect a.level == 2 and a.valueOf("magicka") == 110.0 and a.valueOf("health") == 100.0
	expect w.progress.xp == 10.0 and not w.canLevelUp() and w.progress.perkPoints == 1
	expect w.answerLevelUp(avm1.ExternalCall(name = "addHealth", args = [])) == none
	expect w.actors[w.player].level == 2
	expect w.answerLevelUp(avm1.ExternalCall(name = "PlaySound", args = [])) == none
