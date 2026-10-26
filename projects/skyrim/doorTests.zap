# The doors as the game animates them: the Open and Close sequences of a door's model, read from
# its NiControllerManager, posing the door's node; skipped quietly without the install.

import fs
import skyrim
import skyrim.esm
import skyrim.nif
import game
import world

inn = "RiverwoodSleepingGiantInn"
roomDoor = 0xE_3A79   # FarmhouseAnimDoor02, RiverwoodInnDelphineRoomDoor
otherDoor = 0xE_3A7B

doorModel = "meshes/architecture/farmhouse/farmhouseanimdoor02.nif"

fn readDoor() nif.Nif?:
	if not fs.exists(esm.defaultEsm()):
		eprint("skipped: no {esm.defaultEsm()}")
		return none
	install = skyrim.openInstall(skyrim.defaultInstall) ?? fail
	install.readModel(doorModel) ?? fail

test "a farmhouse door's model has an Open and a Close sequence of one second, each moving its Door02 node":
	door = readDoor() ?? return
	sequences = door.sequencesOf()
	expect sequences.map(.name) == ["Open", "Close"]
	for q in sequences:
		expect q.start == 0.0 and q.stop == 1.0 and q.cycle == 2
		expect q.tracks.map(.node) == ["Door02"]

test "the Open sequence turns the door a quarter turn about z and the Close sequence turns it back":
	door = readDoor() ?? return
	sequences = door.sequencesOf()
	open = sequences[0]
	close = sequences[1]
	rest = Mat4(1.0)
	closed = open.tracks[0].localAt(rest, 0.0)
	opened = open.tracks[0].localAt(rest, open.stop)
	# the hinge turns the door's x onto y
	expect (closed.applyDirection(Vec3(1.0, 0.0, 0.0)) - Vec3(1.0, 0.0, 0.0)).length() < 0.001
	along = opened.applyDirection(Vec3(1.0, 0.0, 0.0))
	expect along.y > 0.99 and along.x.abs() < 0.04
	back = close.tracks[0].localAt(rest, close.stop)
	expect (back.applyDirection(Vec3(1.0, 0.0, 0.0)) - Vec3(1.0, 0.0, 0.0)).length() < 0.001
	# the clock clamps past the end
	expect open.clockOf(5.0) == 1.0 and open.clockOf(0.5) == 0.5

# the prepared inn's head, none without the install
fn preparedInn() world.CellHead?:
	if not fs.exists(esm.defaultEsm()):
		eprint("skipped: no {esm.defaultEsm()}")
		return none
	load = game.Load(textures = false, graph = false, sound = false)
	if game.openPrepared(inn, load) == none: game.prepareCell(skyrim.defaultInstall, inn)
	(game.openPrepared(inn, load) ?? fail("the prepared inn cannot be read")).head

# how far the movable's vertices, in the door's own axes (x across when closed, y through it),
# reach as the state poses them
fn extentOf(head world.CellHead, refId i64, s world.MovableState):
	m = head.movables.find(.refId == refId) ?? fail("no movable {refId}")
	door = head.cast.doors.find(.refId == refId) ?? fail("no door {refId}")
	solid = []
	both = []
	blended = []
	added = []
	m.fillMovable(s, solid, both, blended, added)
	back = game.yUp.inverseAffine()
	across = Vec3(door.heading.cos(), -door.heading.sin(), 0.0)
	through = Vec3(door.heading.sin(), door.heading.cos(), 0.0)
	low = Vec2(1.0e9, 1.0e9)
	high = Vec2(-1.0e9, -1.0e9)
	for v in solid:
		p = back.applyPoint(v.position) - door.position
		low = Vec2(low.x.min(p @ across), low.y.min(p @ through))
		high = Vec2(high.x.max(p @ across), high.y.max(p @ through))
	Vec2(high.x - low.x, high.y - low.y)

test "the inn's two farmhouse doors are movables, each a closed leaf of 96 by 18 units":
	head = preparedInn() ?? return
	expect head.movables.any(.refId == roomDoor) and
		head.movables.any(.refId == otherDoor)
	closed = head.extentOf(roomDoor, world.MovableState(known = true))
	expect (closed.x - 96.0).abs() < 1.0 and (closed.y - 18.0).abs() < 1.0
	expect ((head.cast.doors.find(.refId == roomDoor) ?? fail("no door")).halfWidth - 48.0).abs() <
		0.01

test "an opened door stands turned a quarter turn, and it swings in the one second of its Open sequence":
	head = preparedInn() ?? return
	m = head.movables.find(.refId == roomDoor) ?? fail("no movable")
	open = head.extentOf(roomDoor, world.MovableState(open = true, known = true))
	expect open.x < 30.0 and open.y > 90.0
	state = world.MovableState(open = true, known = true, playing = true)
	half = m.stepped(state, 0.5)
	expect half.playing and half.clock == 0.5
	swinging = head.extentOf(roomDoor, half)
	expect swinging.x < 96.0 - 5.0 and swinging.x > open.x
	done = m.stepped(half, 0.5)
	expect not done.playing
