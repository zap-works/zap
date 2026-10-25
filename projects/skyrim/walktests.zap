# The inn's actors at a new game and over time: placed at their references and walking to their
# packages' places along the navmesh, opening the doors on their way (and leaving them open), and
# taken to where their packages put them when the player waits or sleeps.

import fs
import skyrim
import skyrim.esm
import game
import engine.physics
import game.sim
import game.dialogue
import world

inn = "RiverwoodSleepingGiantInn"
light = game.Load(textures = false, graph = false, sound = false)
frame f32 = 1.0 / 60.0
frontDoor = 0x1_3419   # the inn's, leading out
roomDoor = 0xE_3A79   # FarmhouseAnimDoor02, RiverwoodInnDelphineRoomDoor
otherDoor = 0xE_3A7B

type Inn:
	cell game.PreparedCell
	rs game.Residents
	t dialogue.Talk
	opened i64[]   # the doors that opened, in the order they did

# the inn at an hour of a new game; none without the install
fn readInn(hour f32) Inn?:
	if not fs.exists(esm.defaultEsm()): return none
	cell = game.openOrPrepare(inn, light)
	cast = cell.head.cast
	rs = cast.newResidents(cast.skeletons.map(.skeletonRig()), cast.skeletons.map(.speeds.copy()),
		hour, light)
	install = skyrim.openInstall(skyrim.defaultInstall) ?? fail
	plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
	rs.joinTown(plugin.townAround(esm.Area(0x3C, 5, -11)), inn)
	t = dialogue.talkInCell(install, plugin, inn) ?? fail
	t.vm.rt.world.daysPassed = f64(hour) / 24.0
	Inn(cell, rs, t, opened = [])

fn openedInn():
	readInn(8.0)
fn morningInn():
	readInn(7.5)

fn residentNamed(g Inn, editorId str):
	cast = g.cell.head.cast
	g.rs.all.findIndex(cast.npcs[.npc].editorId == editorId) ?? fail("no {editorId}")

# the frames run for `seconds` with the player at the door, the world taking the actors' doors
fn run(mut g Inn, hour f32, seconds f32):
	cast = g.cell.head.cast
	evaluate {i64: bool} = {}
	loop i64(seconds / frame):
		g.rs.stepResidents(cast, hour, 20.0, evaluate, cast.start, g.cell.physics.world, frame)
		g.cell.physics.world.step(frame)
		for o in g.rs.placeInWorld(cast, g.t.vm.rt.world):
			g.opened.push(o.refId)

fn distanceTo(g Inn, k i64, p Vec3):
	(g.rs.all[k].body.feetOf() - p).length()

fn packageCenter(g Inn, k i64):
	cast = g.cell.head.cast
	r = g.rs.all[k]
	cast.npcs[r.npc].plans[r.plan].center

test "the inn's navmesh knows the load door's triangle and no other, the cell has its doors":
	g = openedInn() ?? return
	cast = g.cell.head.cast
	expect cast.navmesh.doors.map(.door) == [0x1_3419]
	expect cast.doors.any(.refId == roomDoor) and cast.doors.any(.refId == otherDoor)
	expect cast.doors.filter(.teleports).map(.refId) == [0x1_3419]

test "Delphine starts in the hall where the cell places her and walks to her room, opening its door and leaving it open":
	g = openedInn() ?? return
	cast = g.cell.head.cast
	k = g.residentNamed("Delphine")
	placed = cast.npcs[g.rs.all[k].npc].start
	expect g.distanceTo(k, placed) < 1.0 and (placed - g.packageCenter(k)).length() > 400.0
	expect g.t.vm.rt.world.forms[roomDoor].open == false
	g.run(8.0, 3.0)
	expect g.distanceTo(k, placed) > 20.0 and g.opened.isEmpty
	g.run(8.0, 40.0)
	expect g.distanceTo(k, g.packageCenter(k)) < 120.0
	expect g.opened == [roomDoor]
	expect g.t.vm.rt.world.forms[roomDoor].open
	expect not g.t.vm.rt.world.forms[otherDoor].open
	g.run(8.0, 20.0)
	expect g.t.vm.rt.world.forms[roomDoor].open and g.opened == [roomDoor]

test "a wait of 11 hours in the morning puts Embry, Camilla and Hod where their packages place them and Delphine, walking, in her room":
	g = openedInn() ?? return
	cast = g.cell.head.cast
	g.run(8.0, 3.0)
	delphine = g.residentNamed("Delphine")
	expect g.distanceTo(delphine, g.packageCenter(delphine)) > 300.0
	embry = g.residentNamed("Embry")
	expect not g.rs.all[embry].present
	g.t.vm.rt.world.startSleepWait(11, false)
	while not g.t.vm.rt.world.stepSleepWait(): pass
	hour = game.hourOf(g.t.vm.rt.world.daysPassed)
	expect (hour - 19.0).abs() < 0.01
	g.rs.skipTime(cast, hour, 11.0 * 3600.0)
	for name in ["Embry", "CamillaValerius", "Hod"]:
		k = g.residentNamed(name)
		plan = cast.npcs[g.rs.all[k].npc].plans[g.rs.all[k].plan]
		expect g.rs.all[k].present
		expect g.distanceTo(k, plan.center) <= plan.radius.max(64.0)
	expect g.distanceTo(delphine, g.packageCenter(delphine)) < 64.0
	# on her way the closed door of her room opened, and stays open
	expect g.rs.doorUses.any(cast.doors[.door].refId == roomDoor)

test "Delphine's path from the hall goes through her room's door and no other, and the door opens when she reaches it":
	g = openedInn() ?? return
	cast = g.cell.head.cast
	k = g.residentNamed("Delphine")
	g.run(8.0, 0.5)
	crossing = g.rs.all[k].crossings
	expect crossing.map(cast.doors[.door].refId) == [roomDoor]
	reach = crossing[0].at
	until = 0
	while g.opened.isEmpty and until < 3000:
		g.run(8.0, 0.1)
		until += 1
	expect g.opened == [roomDoor]
	# she was at the door, not yet through it
	expect g.rs.all[k].crossings.isEmpty
	expect g.distanceTo(k, reach) < 60.0

test "Embry, eating in the inn before 8, walks to the front door when her package takes her outside, and goes through it":
	g = morningInn() ?? return
	k = g.residentNamed("Embry")
	expect g.rs.all[k].present and g.rs.departed.isEmpty
	g.run(7.5, 2.0)
	expect g.rs.all[k].present and g.rs.all[k].exit == 0
	g.run(8.0, 1.0)
	expect g.rs.all[k].exit == frontDoor
	until = 0
	while g.rs.departed.isEmpty and until < 120:
		g.run(8.0, 1.0)
		until += 1
	expect g.rs.departed.map(.door) == [frontDoor]
	expect g.rs.departed.map(.npc) == [g.cell.head.cast.npcs[g.rs.all[k].npc].formId]
	expect not g.rs.all[k].present
	expect g.rs.all[k].exit == 0

test "Hod, at the sawmill until 19, comes in through the front door after his walk and goes on to his place":
	g = openedInn() ?? return
	cast = g.cell.head.cast
	k = g.residentNamed("Hod")
	g.run(18.5, 1.0)
	expect not g.rs.all[k].present
	g.run(19.0, 1.0)
	expect not g.rs.all[k].present and g.rs.all[k].arrival != none
	waits = g.rs.all[k].arriveIn
	expect waits > 5.0
	g.run(19.0, waits + 1.0)
	expect g.rs.all[k].present
	door = cast.doors.find(.refId == frontDoor) ?? fail("no door")
	expect g.distanceTo(k, door.position) < 400.0
	g.run(19.0, 60.0)
	expect g.distanceTo(k, g.packageCenter(k)) < 150.0
