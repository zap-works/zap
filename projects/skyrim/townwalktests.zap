# Riverwood's people outdoors (game/townfolk.zap, game/transit.zap): the residents of the exterior
# area at chosen hours, and the ones who come out of a house's or the inn's door into the town.

import fs
import engine.physics
import skyrim
import skyrim.esm
import game
import world

riverwood = esm.Area(0x3C, 5, -11)
outside = riverwood.areaId()
light = game.Load(textures = false, graph = false, sound = false)
frame f32 = 1.0 / 60.0
innDoor = 0x1_3419   # the inn's, leading out
alvorsDoor = 0x1_33FB   # Alvor's house's, leading out

type Outside:
	cell game.PreparedCell
	town game.Town

# the town and its prepared exterior, none without the install
fn readOutside() Outside?:
	if not fs.exists(esm.defaultEsm()):
		eprint("skipped: no {esm.defaultEsm()}")
		return none
	install = skyrim.openInstall(skyrim.defaultInstall) ?? fail
	plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
	Outside(cell = game.openOrPrepare(outside, light), town = plugin.townAround(riverwood))

town = readOutside()

# the exterior's residents at an hour of a new game, living in the town
fn residentsAt(o Outside, hour f32):
	cast = o.cell.head.cast
	rs = cast.newResidents(cast.skeletons.map(.skeletonRig()), cast.skeletons.map(.speeds.copy()),
		hour, light)
	rs.joinTown(o.town.copy(), outside)
	rs

fn residentNamed(o Outside, rs game.Residents, editorId str):
	cast = o.cell.head.cast
	rs.all.findIndex(cast.npcs[.npc].editorId == editorId) ?? fail("no {editorId}")

# the frames run for `seconds` at the hour
fn run(mut o Outside, mut rs game.Residents, hour f32, seconds f32):
	cast = o.cell.head.cast
	evaluate {i64: bool} = {}
	loop i64(seconds / frame):
		rs.stepResidents(cast, hour, 20.0, evaluate, cast.start, o.cell.physics.world, frame)
		o.cell.physics.world.step(frame)

fn distanceToPlace(o Outside, rs game.Residents, k i64):
	cast = o.cell.head.cast
	r = rs.all[k]
	(r.body.feetOf() - cast.npcs[r.npc].plans[r.plan].center).length()

test "at 10 Alvor works outside, Sigrid is at the garden or the forge, the guards stand watch; at 22 Alvor is away, in the inn":
	o = town ?? return
	cast = o.cell.head.cast
	rs = o.residentsAt(10.0)
	for name in ["Alvor", "Sigrid"]:
		k = o.residentNamed(rs, name)
		plan = cast.npcs[rs.all[k].npc].plans[rs.all[k].plan]
		expect rs.all[k].present and o.distanceToPlace(rs, k) <= plan.radius.max(64.0)
	expect rs.all[o.residentNamed(rs, "GuardRiverwoodImperial01")].present
	late = o.residentsAt(22.0)
	alvor = o.residentNamed(late, "Alvor")
	expect not late.all[alvor].present
	expect late.all[o.residentNamed(late, "GuardRiverwoodImperial01")].present

test "Alvor, at home until 8, comes out of his house's door when his work begins and walks to his place":
	o = town ?? return
	rs = o.residentsAt(7.5)
	k = o.residentNamed(rs, "Alvor")
	expect not rs.all[k].present
	o.run(rs, 8.0, 0.5)
	expect not rs.all[k].present and rs.all[k].arrival != none
	waits = rs.all[k].arriveIn
	expect waits > 0.0 and waits < 120.0
	o.run(rs, 8.0, waits + 1.0)
	expect rs.all[k].present
	door = o.town.doors.find(.refId == alvorsDoor) ?? fail("no door")
	expect (rs.all[k].body.feetOf() - door.arrival.at).length() < 400.0
	o.run(rs, 8.0, 90.0)
	expect o.distanceToPlace(rs, k) < 600.0

test "Embry, leaving the inn at 8, comes out of the inn's front door into Riverwood":
	o = town ?? return
	rs = o.residentsAt(7.5)
	k = o.residentNamed(rs, "Embry")
	expect not rs.all[k].present
	o.run(rs, 8.0, 0.5)
	expect rs.all[k].arrival != none
	o.run(rs, 8.0, rs.all[k].arriveIn + 1.0)
	expect rs.all[k].present
	door = o.town.doors.find(.refId == innDoor) ?? fail("no door")
	expect (rs.all[k].body.feetOf() - door.arrival.at).length() < 300.0
