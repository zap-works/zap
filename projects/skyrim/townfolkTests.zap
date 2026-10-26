# Riverwood's people across its cells (game/townfolk.zap): the town's doors, where a few residents
# are by the hour in the exterior and the interiors, the route between cells through the load
# doors, and the ones in an unloaded cell advanced as the game advances them.

import fs
import skyrim
import skyrim.esm
import skyrim.actor
import game
import game.sim

riverwood = esm.Area(0x3C, 5, -11)
outside = riverwood.areaId()
inn = "RiverwoodSleepingGiantInn"
alvorsHouse = "RiverwoodAlvorsHouse"
innDoor = 0x1_3419   # the inn's, leading out
innDoorOutside = 0x1_3424
alvorsDoor = 0x1_33FB   # Alvor's house's, leading out
alvorsDoorOutside = 0x1_3420

# the town, none without the install
fn readTown() game.Town?:
	if not fs.exists(esm.defaultEsm()):
		eprint("skipped: no {esm.defaultEsm()}")
		return none
	install = skyrim.openInstall(skyrim.defaultInstall) ?? fail("missing")
	plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail("missing")
	plugin.townAround(riverwood)

town = readTown()

fn cellOf(t game.Town, name str, hour f32):
	d = t.dwellerNamed(name) ?? fail("no {name}")
	(d.spotAt(hour, 0) ?? fail("{name} is nowhere")).cell

test "the town is the exterior and the six interiors its doors lead to, a door out of each":
	t = town ?? return
	expect t.cells.len == 7 and t.cells[0] == outside
	for cell in [
		"RiverwoodRiverwoodTrader",
		"RiverwoodSvensHouse",
		inn,
		"RiverwoodGerdursHouse",
		alvorsHouse,
		"RiverwoodFaendalsHouse"
	]:
		expect t.doors.any(.spot.cell == cell and .to == outside)
		expect t.doors.any(.spot.cell == outside and .to == cell)
	door = t.doors.find(.refId == innDoor) ?? fail("no inn door")
	expect door.other == innDoorOutside and door.to == outside

test "the doors join the cells both ways, an arrival is where the door's XTEL puts who goes through":
	t = town ?? return
	for d in t.doors:
		back = t.doors.find(.refId == d.other) ?? fail("no door {d.other:08X}")
		expect back.to == d.spot.cell and back.other == d.refId
		expect d.arrival.cell == d.to

test "the route from the inn to Alvor's house is the inn's door then Alvor's, and none inside one cell":
	t = town ?? return
	expect t.route(inn, alvorsHouse).map(.refId) == [innDoor, alvorsDoorOutside]
	expect t.route(alvorsHouse, inn).map(.refId) == [alvorsDoor, innDoorOutside]
	expect t.route(inn, inn).isEmpty and t.route(inn, "nowhere").isEmpty

test "Alvor sleeps and eats at home, works outside from 8, eats at home at 20 and drinks in the inn at 22":
	t = town ?? return
	expect t.cellOf("Alvor", 3.0) == alvorsHouse and t.cellOf("Alvor", 6.5) == alvorsHouse
	expect t.cellOf("Alvor", 10.0) == outside and t.cellOf("Alvor", 19.5) == outside
	expect t.cellOf("Alvor", 20.5) == alvorsHouse and t.cellOf("Alvor", 22.0) == inn
	expect t.cellOf("Alvor", 23.5) == alvorsHouse

test "Sigrid and Dorthe, Camilla, Faendal and Orgnar are where their packages put them by the hour":
	t = town ?? return
	expect t.cellOf("Sigrid", 10.0) == outside and t.cellOf("Sigrid", 17.0) == alvorsHouse
	expect t.cellOf("Dorthe", 12.0) == alvorsHouse and t.cellOf("Dorthe", 18.0) == outside
	expect t.cellOf("CamillaValerius", 12.0) == "RiverwoodRiverwoodTrader"
	expect t.cellOf("CamillaValerius", 18.0) == inn
	expect t.cellOf("Faendal", 9.0) == outside and
		t.cellOf("Faendal", 3.0) == "RiverwoodFaendalsHouse"
	expect t.cellOf("Orgnar", 12.0) == inn and t.cellOf("Orgnar", 23.0) == inn

test "the town's guards and animals live outdoors all day":
	t = town ?? return
	for name in ["GuardRiverwoodImperial01", "GuardRiverwoodSonsOfSkyrim01", "EncChicken"]:
		expect t.cellOf(name, 3.0) == outside and t.cellOf(name, 15.0) == outside

test "the walk from Alvor's house to the inn is a leg in each cell, through each cell's door":
	t = town ?? return
	from = game.Spot(alvorsHouse, Vec3(0.0, 0.0, 0.0))
	to = game.Spot(inn, Vec3(10.0, 0.0, 0.0))
	path = t.legs(from, to)
	expect path.map(.cell.copy()) == [alvorsHouse, outside, inn]
	expect path.map(.door) == [alvorsDoor, innDoorOutside, 0]
	# the next leg begins where the door put the walker
	first = t.doors.find(.refId == alvorsDoor) ?? fail("no door")
	second = t.doors.find(.refId == innDoorOutside) ?? fail("no door")
	expect path[1].from == first.arrival.at and path[2].from == second.arrival.at
	expect path.walkSeconds() > 10.0

test "Alvor leaving home for the inn at 21 is in his house, then outside, then in the inn, as the hours pass":
	t = town ?? return
	d = t.dwellerNamed("Alvor") ?? fail("missing")
	start = t.whereAt(d, 21.0, 0, 20.0) ?? fail("missing")
	expect start.spot.cell == alvorsHouse and start.walking
	underway = t.whereAt(d, 21.03, 0, 20.0) ?? fail("missing")
	expect underway.spot.cell == outside and underway.walking
	arrived = t.whereAt(d, 21.6, 0, 20.0) ?? fail("missing")
	expect arrived.spot.cell == inn and not arrived.walking
	# a package that kept him where he was moves him nowhere
	staying = t.whereAt(d, 15.0, 0, 20.0) ?? fail("missing")
	expect staying.spot.cell == outside and not staying.walking

test "the exterior's cast is the town's people, placed or brought by their packages, and none of its animals":
	if not fs.exists(esm.defaultEsm()): return
	install = skyrim.openInstall(skyrim.defaultInstall) ?? fail
	plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
	actors = plugin.cellActors(outside) ?? fail("no area")
	names = []
	for a in actors:
		names.push((plugin.npcOf(a.npc) ?? fail("no npc")).editorId)
	for name in ["GuardRiverwoodImperial01", "Alvor", "Sigrid", "Hod", "Faendal", "Embry"]:
		expect name in names
	for name in ["EncChicken", "EncCow", "EncWolf", "LvlMudcrab"]:
		expect name not in names
	# Alvor has no reference in the area: his packages bring him
	alvor = actors.find(.npc == 0x1_3475) ?? fail("no Alvor")
	expect alvor.achr == none and not alvor.visits.isEmpty
