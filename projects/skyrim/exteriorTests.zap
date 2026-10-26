# The exterior around Riverwood (game/travel.zap, esm/area.zap): the loaded grid, the area as a
# cell, the load doors between the inn and the town (the physics across cells and the shot are
# exteriorPhysicsTests.zap and exteriorShotTests.zap, a process each: they hold the whole town).

import skyrim
import skyrim.esm
import game
import game.sim
import interface

inn = "RiverwoodSleepingGiantInn"
tamriel = 0x3C
frontDoor = 0x1_3419   # the inn's, leading out
outsideDoor = 0x1_3424   # Riverwood's, leading in
# the cell outside the inn's door, and the area the game loads around it
riverwood = esm.Area(tamriel, 5, -11)

test "the loaded grid is uGridsToLoad squared around the cell, at least 5 and odd":
	expect esm.gridSide(5) == 5 and esm.gridSide(3) == 5 and esm.gridSide(6) == 7
	grid = esm.loadedGrid(4, -3, 5)
	expect grid.len == 25 and (grid.first ?? (0, 0)) == (2, -5) and (grid.last ?? (0, 0)) == (6, -1)
	expect (4, -3) in grid and (7, -3) not in grid

test "an area's id round-trips and an interior's is none":
	a = esm.Area(tamriel, 4, -3)
	expect esm.areaOf(a.areaId()) == a
	expect esm.areaOf(inn) == none

test "the area around Riverwood is its centre's cell and the 5 x 5 grid's references, the door in":
	install = skyrim.openInstall(skyrim.defaultInstall) ?? return
	plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? return
	cell = plugin.findCell(riverwood.areaId()) ?? fail("no area")
	expect cell.exterior and cell.editorId == riverwood.areaId() and cell.refs.len > 1500
	expect cell.refs.any(.formId == outsideDoor and .persistent)
	grid = esm.loadedGrid(riverwood.x, riverwood.y, 5)
	inside = cell.refs.count(.position.gridOf() in grid)
	expect inside * 100 >= cell.refs.len * 97
	# a cell of the grid is the area's too: its own references are among those of the area
	next = esm.Area(tamriel, riverwood.x + 1, riverwood.y)
	expect plugin.hasCellAt(next) and not plugin.hasCellAt(esm.Area(tamriel, 400, 400))
	records = plugin.cellRecords(riverwood.areaId()) ?? fail("no records")
	expect records.count(.kind == "REFR") > 1500 and records.any(.kind == "NAVM")

test "the loaded grid follows the player: it is made again only past the middle ring":
	here = esm.Area(tamriel, 5, -11)
	middle = Vec3(5.5 * esm.cellSize, -10.5 * esm.cellSize, 0.0)
	expect here.recentered(middle, 0.0) == none
	beside = Vec3(6.5 * esm.cellSize, -10.5 * esm.cellSize, 0.0)
	expect here.recentered(beside, 0.0) == none
	past = Vec3(7.5 * esm.cellSize, -10.5 * esm.cellSize, 0.0)
	moved = here.recentered(past, 1.0) ?? fail("not moved")
	expect moved.place == esm.Area(tamriel, 7, -11).areaId() and moved.feet == past and
		not moved.fades

test "the grid follows the player cell by cell: a step enters and leaves one row or column, and the loaded cells are always those around him":
	here = esm.Area(tamriel, 5, -11)
	step = here.gridShift(esm.Area(tamriel, 6, -11), 5)
	expect step.entering.len == 5 and step.leaving.len == 5
	expect esm.GridPlace(8, -13) in step.entering and esm.GridPlace(8, -9) in step.entering
	expect esm.GridPlace(3, -11) in step.leaving
	diagonal = here.gridShift(esm.Area(tamriel, 6, -10), 5)
	expect diagonal.entering.len == 9 and diagonal.leaving.len == 9
	expect here.gridShift(here, 5).entering.isEmpty
	# a walk of ten cells north east: each step keeps what stays loaded and brings what enters
	loaded = here.loadedPlaces(5)
	at = here
	loop 10:
		next = esm.Area(tamriel, at.x + 1, at.y + (1 if at.x % 2 == 0 else 0))
		shift = at.gridShift(next, 5)
		expect shift.leaving.all(it in loaded) and shift.entering.all(it not in loaded)
		loaded = loaded.filter(it not in shift.leaving)
		loaded.extend(shift.entering)
		at = next
		expect loaded.len == 25
		expect loaded.all(it in at.loadedPlaces(5))

test "the inn's front door leads out to Riverwood, the door outside back into the inn":
	install, plugin = skyrim.installAndPlugin() ?? return
	names = install.readNames("Skyrim.esm") ?? fail("no names")
	inside = install.worldOfCell(plugin, names, inn) ?? fail("no inn")
	out = inside.arrivalThrough(frontDoor) ?? fail("no arrival")
	expect out.place == riverwood.areaId() and out.fades
	t = inside.forms[frontDoor].teleport ?? fail("no teleport")
	expect t.placeName == "Riverwood" and t.door == outsideDoor
	# the player appears where the XTEL puts him, in the cell outside, facing as it says
	expect out.feet == t.position and out.heading == t.rotation.z
	expect out.feet.gridOf() == (riverwood.x, riverwood.y)
	town = install.worldOfCell(plugin, names, riverwood.areaId()) ?? fail("no town")
	expect town.cell == (plugin.findCell(riverwood.areaId()) ?? fail("no area")).formId
	back = town.arrivalThrough(outsideDoor) ?? fail("no way back")
	expect back.place == inn and back.fades
	b = town.forms[outsideDoor].teleport ?? fail("no teleport")
	expect b.placeName == "Sleeping Giant Inn" and b.door == frontDoor and b.world == 0
	expect town.arrivalThrough(0x14) == none

test "the load door's HUD text names the place it leads to":
	install, plugin = skyrim.installAndPlugin() ?? return
	names = install.readNames("Skyrim.esm") ?? fail("no names")
	inside = install.worldOfCell(plugin, names, inn) ?? fail("no inn")
	town = install.worldOfCell(plugin, names, riverwood.areaId()) ?? fail("no town")
	texts = install.openTexts(inside.settings) ?? return
	open = texts.setting("sOpen")
	expect texts.targetText(inside, frontDoor)?.text == "{open}\nRiverwood"
	expect texts.targetText(town, outsideDoor)?.text == "{open}\nSleeping Giant Inn"

test "what the player carries goes through the door, and a cell left is as he left it":
	install, plugin = skyrim.installAndPlugin() ?? return
	names = install.readNames("Skyrim.esm") ?? fail("no names")
	inside = install.worldOfCell(plugin, names, inn) ?? fail("no inn")
	inside.giveItem(inside.player, 0xF, 55, 0)
	inside.globals[0x1234] = 3.0
	inside.daysPassed = 2.5
	left = inside.leaving()
	town = install.worldOfCell(plugin, names, riverwood.areaId()) ?? fail("no town")
	inside.carryOver(town)
	expect town.inventories[town.player].countOf(0xF) ==
		inside.inventories[inside.player].countOf(0xF)
	expect town.globals[0x1234] == 3.0 and town.daysPassed == 2.5
	again = install.worldOfCell(plugin, names, inn) ?? fail("no inn")
	expect again.forms[frontDoor].open == false
	inside.forms[frontDoor].open = true
	again.returning(inside.leaving())
	expect again.forms[frontDoor].open and again.player == inside.player
	expect left.forms.len == inside.forms.len
