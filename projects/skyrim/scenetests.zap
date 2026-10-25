# The inn's world over time, read from the player's install (skipped without it): its Havok (the
# clutter, the hanging animals, a ragdoll), the player's capsule and walk, the actors at their
# packages.

import engine
import fs
import skyrim
import skyrim.esm
import skyrim.nif
import skyrim.hkx
import skyrim.actor
import game
import engine.physics
import world

inn = "RiverwoodSleepingGiantInn"

# the inn's physics world, read from the install once per file; none without it
fn readInnWorld() game.CellWorld?:
	install, plugin = try skyrim.installAndPlugin()
	cell = plugin.findCell(inn) ?? fail("no {inn}")
	models {str: nif.Collider[]} = {}
	install.cellWorld(plugin, cell, models)

innWorld = readInnWorld()

# a world of the test's own, from the one read
fn withInnWorld() game.CellWorld?:
	(try innWorld)

# Some of the inn's refs stand past their support in the plugin: a coin purse 24 units past the
# edge of the bar's lower shelf, a wine bottle whose center is past the edge of its table, a closed
# book (two bodies) set 4.5 units into a shelf's side with half of it past the shelf, which falls
# once it is pushed out. The game never settles placed clutter, so they stay there until touched;
# here they fall, and only they move that far.
test "the inn's clutter settles in 5 s: near where it was placed, asleep, none below its floor":
	cw = withInnWorld() ?? return
	expect cw.placed.len > 150 and cw.world.scene.triangleCount() > 20_000
	cw.world.step(5.0)
	moved = cw.placed.filter(cw.displacement(it) > 8.0).map(.editorId)
	expect moved.sorted() ==
		[
			"Book2CommonFallFromGlory",
			"Book2CommonFallFromGlory",
			"CoinPurseSmall",
			"FoodWineBottle02"
		]
	expect cw.placed.count(not cw.world.bodies[.body].asleep) <= 1
	expect not cw.placed.any(cw.isBelowFloor(it))

test "the player walks across the inn's main room on its floor":
	cw = withInnWorld() ?? return
	c = game.playerController(Vec3(-1100, -200, 10))
	lowest f32 = 10.0
	loop 360:
		lowest = lowest.min(c.walk(cw.world, Vec3(200, 0, 0), 1.0 / 60.0).z)
	expect c.feet.x > 0.0 and c.onFloor and c.feet.z.abs() < 1.0 and lowest > -1.0

# the player's gaits as the install's clips give them; none without it
fn withGaits() game.Gaits?:
	if not fs.exists(esm.defaultEsm()): return none
	install = skyrim.openInstall(skyrim.defaultInstall) ?? fail
	_, men = install.prepareSkeleton(false, game.playerClips)
	game.gaitsOf(men.rig.clips, men.speeds)

# the player walked for `seconds` at 60 frames a second, the keys asking for the way `heading`
# (the world stepped too); the lowest his feet went
fn walked(mut p game.Player, mut w physics.World, heading f32, seconds f32):
	ahead = game.Input(forward = 1.0, right = 0.0, run = false, look = IVec2(0, 0))
	lowest = p.feetOf().z
	loop i64(seconds * 60.0):
		p.steerPlayer(ahead, heading, w, 1.0 / 60.0)
		w.step(1.0 / 60.0)
		lowest = lowest.min(p.feetOf().z)
	lowest

# The walk's motion (93.4 units in its 1.13 s) carries the player once his gait has eased in over
# a quarter second; the inn's front wall (its load door at y -422) stops him a capsule's radius
# and a little away from it.
test "a scripted walk goes as far as the walk's motion carries it, on the floor, and a wall stops it":
	gaits = withGaits() ?? return
	cw = withInnWorld() ?? return
	expect (gaits.walkSpeed - 93.448 / 1.1333333).abs() < 0.1 and gaits.runSpeed > 300.0
	p = game.newPlayer(Vec3(-1100, -200, 0), pi / 2.0, gaits)
	lowest = p.walked(cw.world, pi / 2.0, 2.0)
	end = p.feetOf()
	expect (end.x - (-1100.0 + gaits.walkSpeed * 1.875)).abs() < 3.0 and (end.y + 200.0).abs() < 1.0
	expect p.controller.onFloor and end.z.abs() < 1.0 and lowest > -1.0
	q = game.newPlayer(Vec3(-256, -322, 0), pi, gaits)
	q.walked(cw.world, pi, 3.0)
	expect q.feetOf().y > -422.0 + 10.0 and q.feetOf().y < -380.0 and q.controller.onFloor

# The hanging animals behind the bar (two bodies each on limited hinges, game/hanging.zap) start
# from their models' pose, swing down under their hooks and come to rest; asleep, they rest where
# they would hang: woken, they stay.
test "the inn's 17 hanging animals rest under their hooks within 2 s, none asleep before resting, none fallen":
	cw = withInnWorld() ?? return
	hung = cw.chains.filter(.anchor != none).map(.copy())
	expect hung.len == 17
	cw.world.step(2.0)
	for chain in hung:
		anchor = chain.anchor ?? fail("no anchor")
		below, far = cw.chainReach(chain)
		expect chain.bodies.all(cw.world.bodies[it].asleep)
		expect chain.bodies.all(cw.world.bodies[it].position.z < anchor.z)
		expect below > 10.0 and far < 40.0
		expect chain.joints.all(cw.world.joints[it].pivotGap(cw.world.bodies) < 0.5)
	slept = hung.flatMap(.bodies.map(cw.world.bodies[it].position))
	for chain in hung:
		for i in chain.bodies:
			cw.world.bodies[i].asleep = false
	cw.world.step(1.0)
	woken = hung.flatMap(.bodies.map(cw.world.bodies[it].position))
	expect (0..slept.len).all((woken[it] - slept[it]).length() < 1.0)

# Walked through, the capsule nudges the rabbit hung at (-1388, 183) (character.zap): it swings up
# to its hinges' limits and its swing dies down under its hook, as the game's does when pushed (the
# joints' rows as the executable solves them damp it slowly: about half of the swing is left after 20 s).
test "the player's capsule walking into a hanging rabbit swings it, and the swing dies down":
	cw = withInnWorld() ?? return
	cw.world.step(2.0)
	chain = cw.chains.find((.anchor ?? Vec3(0, 0, 0)).isClose(Vec3(-1388.0, 182.8, 138.4), 1.0)) ??
		fail("no rabbit at the bar's end")
	low = chain.bodies.last ?? fail("no body")
	start = cw.world.bodies[low].position
	c = game.playerController(Vec3(-1348.0, 182.8, 0.0))
	widest f32 = 0.0
	late = 0.0
	for f in 0..1500:
		if f < 30: c.walk(cw.world, Vec3(-200.0, 0.0, 0.0), 1.0 / 60.0)
		cw.world.step(1.0 / 60.0)
		off = (cw.world.bodies[low].position - start).length()
		widest = widest.max(off)
		if f >= 1200: late = late.max(off)
	below, far = cw.chainReach(chain)
	print("swung {widest:.1} units, {late:.1} of it left after 20 s, {below:.1} below its hook")
	expect widest > 5.0 and late < 0.6 * widest
	expect below > 20.0 and far < 40.0

# what the actors' tests read: the prepared head and physics, no textures, graph or sound
light = game.Load(textures = false, graph = false, sound = false, dialogue = false)

# the prepared inn (prepared first when it is missing), read once; none without the install
fn readInnCell() game.PreparedCell?:
	if not fs.exists(esm.defaultEsm()): return none
	game.openOrPrepare(inn, light)

fn innCell():
	readInnCell()

# the prepared inn with its actors at the game hour; none without the install
fn withResidents(hour f32) (game.PreparedCell, game.Residents)?:
	cell = try innCell()
	rigs = cell.head.cast.skeletons.map(.skeletonRig())
	speeds = cell.head.cast.skeletons.map(.speeds.copy())
	(cell, cell.head.cast.newResidents(rigs, speeds, hour, light))

fn residentNamed(rs game.Residents, cast world.CastHead, editorId str):
	(rs.all.find(cast.npcs[.npc].editorId == editorId) ?? fail("no {editorId}"))

test "at 8 of a new game Orgnar works within his sandbox's radius and Delphine stands where the cell placed her (she then walks to her room); at 19 Embry, Camilla and Hod are in":
	cell, rs = withResidents(8.0) ?? return
	cast = cell.head.cast
	orgnar = rs.residentNamed(cast, "Orgnar")
	plan = cast.npcs[orgnar.npc].plans[orgnar.plan]
	expect orgnar.present and plan.editorId == "OrgnarWorkInn0x24"
	expect (orgnar.body.feetOf() - plan.center).length() <= plan.radius
	delphine = rs.residentNamed(cast, "Delphine")
	expect delphine.present and
		cast.npcs[delphine.npc].plans[delphine.plan].editorId == "DelphineStartInRoom"
	expect (delphine.body.feetOf() - cast.npcs[delphine.npc].start).length() < 1.0
	expect not rs.residentNamed(cast, "Embry").present
	_, evening = withResidents(19.0) ?? return
	for name in ["Embry", "CamillaValerius", "Hod", "Orgnar", "Delphine"]:
		expect evening.residentNamed(cast, name).present
	expect not evening.residentNamed(cast, "Sven").present

test "after 600 frames of 16 ms at 19 every actor in the inn stands on its floor, inside the cell":
	cell, rs = withResidents(19.0) ?? return
	cast = cell.head.cast
	evaluate {i64: bool} = {}
	hour = 19.0
	loop 600:
		rs.stepResidents(cast, hour, 20.0, evaluate, cast.start, cell.physics.world, 0.016)
		cell.physics.world.step(0.016)
		hour += 0.016 * 20.0 / 3600.0
	for r in rs.all.filter(.present):
		feet = r.body.feetOf()
		_, floor = cast.navmesh.nearestPoint(feet)
		expect (feet.z - floor.z).abs() < 8.0
		p = game.yUp.applyPoint(feet)
		expect p.x >= cell.head.low.x and p.x <= cell.head.high.x
		expect p.z >= cell.head.low.z and p.z <= cell.head.high.z

# the prepared inn at 8 with Orgnar killed behind his counter after 10 frames (fallen.zap), and
# the skeletons' rigs
fn withFallenOrgnar() (game.PreparedCell, game.Residents, engine.Rig[])?:
	cell, rs = try withResidents(8.0)
	cast = cell.head.cast
	rigs = cast.skeletons.map(.skeletonRig())
	evaluate {i64: bool} = {}
	loop 10:
		rs.stepResidents(cast, 8.0, 20.0, evaluate, cast.start, cell.physics.world, frame)
		cell.physics.world.step(frame)
	expect rs.killNamed(cast, "Orgnar", rigs, cell.physics.world, frame)
	(cell, rs, rigs)

frame f32 = 1.0 / 60.0

# the frames run at 8 of the morning: the actors and the world
fn runFrames(mut cell game.PreparedCell, mut rs game.Residents, frames i64):
	evaluate {i64: bool} = {}
	loop frames:
		rs.stepResidents(cell.head.cast, 8.0, 20.0, evaluate, cell.head.cast.start,
			cell.physics.world, frame)
		cell.physics.world.step(frame)

# Killed while leaning on his counter, Orgnar slumps against it, falls to the floor and lies there:
# still from 7 s on (his bodies asleep a moment after; his limbs push each other apart as the
# executable's biped filter lets them collide, which takes him about 4 s longer), on the floor,
# each joint within its limits, and the skinned skeleton the ragdoll poses unstretched (every bone at its length from
# its parent).
test "Orgnar's ragdoll rests on the floor within 7 s, every joint within its limits, no body below the floor, no bone stretched":
	cell, rs, _ = withFallenOrgnar() ?? return
	f = rs.fallen[0]
	cell.runFrames(rs, 420)
	at = f.ragdoll.bodies.map(cell.physics.world.bodies[it].position)
	cell.runFrames(rs, 120)
	w = ref cell.physics.world
	moved = (0..at.len).map((w.bodies[f.ragdoll.bodies[it]].position - at[it]).length()).max() ??
		0.0
	floor = f.place.translation.z
	lowest = f.ragdoll.bodies.map(w.bodies[it].lowest()).min() ?? 0.0
	excess = f.ragdoll.joints.map(w.joints[it].limitExcess(w.bodies)).max() ?? 0.0
	print("moved {moved:.2} after 7 s, lowest {lowest - floor:.2} over the floor, past the limits by {excess:.3}")
	expect moved < 2.0 and w.isRagdollAsleep(f.ragdoll)
	expect lowest > floor - 1.0 and f.ragdoll.bodies.all(w.bodies[it].position.z < floor + 30.0)
	expect excess < limitSlack
	head = cell.head.cast.skeletons[rs.all[f.resident].skeleton]
	posed = head.bones.modelPose(game.bonesOfRig(rs.fallen[0].pose, f.nodes))
	bind = head.bones.modelPose(head.bones.bones.map(.pose))
	stretch = 0.0
	for i, b in head.bones.bones:
		if b.parent < 0: continue
		length = (bind[i].translation - bind[b.parent].translation).length()
		stretch = stretch.max(
			(posed[i].translation - posed[b.parent].translation).length() - length
		)
	print("the longest bone {stretch:.2} units over its length")
	expect stretch < ragdollOffset

# how far a bone may come from its parent past its length: the skeleton mapper's offsets between
# a ragdoll bone's frame and its animation bone's (the hip's and the shoulder's up to 4.8 units)
# let the joint's end swing about a pivot that is not its own
ragdollOffset f32 = 4.8

# how far (radians) a resting ragdoll's joint may stay past its limit: Havok's limits are soft (a
# limit closes tau times its factor of the error a sub-step, a twist's also by the squared half length
# of its axes' sum, so a twist the arm's weight loads rests well past its limit) and the low
# deactivation class stops the last of the correction
limitSlack f32 = 0.3

test "the skeleton's ragdoll constraints are the discrete step's with their position motors off, its bodies in the low deactivation class":
	install = skyrim.openInstall(skyrim.defaultInstall) ?? return
	ragdoll = install.readRagdollOf(false) ?? fail
	js = ragdoll.joints
	expect (0..js.len).count(js[it].priority == 1 and not js[it].motorOn) == 17
	motor = js[0].motor ?? fail("no motor")
	expect motor.tau.isClose(0.8, 0.001) and motor.damping.isClose(1.0, 0.001)
	expect (0..ragdoll.bodies.len).count(ragdoll.bodies[it].deactivation == 2) == 18

test "the ragdoll's bodies take their biped parts from skeleton.nif, and collide as the executable's filter says":
	install = skyrim.openInstall(skyrim.defaultInstall) ?? return
	ragdoll = install.readRagdollOf(false) ?? fail
	parts {str: i64} = {}
	for b in ragdoll.bodies:
		parts[b.name.replace("Ragdoll_", "")] = b.part
	expect parts["NPC Head [Head]"] == 1 and parts["NPC COM [COM ]"] == 2 and
		parts["NPC Neck [Neck]"] == 0
	expect parts["NPC L Hand [LHnd]"] == 7 and parts["NPC R Foot [Rft ]"] == 16
	w = game.havokWorld()
	collide = (a i64, b i64): (w.partPairs[a] >> b) & 1 != 0
	expect collide(7, 2) and collide(2, 7)   # a hand and the body
	expect collide(8, 14) and not collide(8, 9)   # a thigh and the other, not its own calf
	expect not collide(0, 1) and not collide(1, 2)   # the neck (OTHER) nothing; the head not the body
	expect w.layersMeet(4, 4) and w.layersMeet(4, 1) and w.layersMeet(30, 4)   # clutter, statics, the player
	expect not w.layersMeet(30, game.deadBipLayer) and not w.layersMeet(8, 5)   # the player and the dead; a weapon and a biped

test "the skeleton mappers' round trip (Orgnar's pose to the ragdoll and back) gives back the bones the ragdoll drives":
	cell, rs = withResidents(8.0) ?? return
	cast = cell.head.cast
	rigs = cast.skeletons.map(.skeletonRig())
	k = rs.all.findIndex(cast.npcs[.npc].editorId == "Orgnar") ?? fail("no Orgnar")
	r = rs.all[k]
	head = cast.skeletons[r.skeleton]
	ragdoll = head.ragdoll ?? fail("no ragdoll")
	nodes = rigs[r.skeleton].nodesOf(head.bones)
	pose = rs.residentPoses().find(.model == r.npc + 1) ?? fail("Orgnar is not drawn")
	locals = game.bonesOfRig(rigs[r.skeleton].poseLocals(pose.pose), nodes)
	place = r.body.feetOf().actorPlace(r.body.heading, cast.npcs[r.npc].look.scale)
	frames = ragdoll.ragdollFrames(head.bones, locals, place)
	back = ragdoll.animationLocals(head.bones, frames, place, locals)
	before = head.bones.modelPose(locals)
	after = head.bones.modelPose(back)
	expect ragdoll.toAnimation.simple.len == 18 and ragdoll.bodies.len == 18
	for m in ragdoll.toAnimation.simple:
		expect (before[m.boneB].translation - after[m.boneB].translation).length() < 0.05
		expect before[m.boneB].rotation.isClose(after[m.boneB].rotation, 0.001) or
			before[m.boneB].rotation.isClose(-after[m.boneB].rotation, 0.001)

test "the inn's windows and dust beams take WeatherPineForest's weather light by the hour":
	if not fs.exists(esm.defaultEsm()):
		eprint("skipped: no {esm.defaultEsm()}")
		return
	plugin = esm.openEsm(esm.defaultEsm()) ?? fail
	cell = plugin.findCell("RiverwoodSleepingGiantInn") ?? fail("no inn")
	e = plugin.emittanceOf(cell)
	clear = world.capturedWeather
	# Update.esm's SkyrimClear at day, as the game's captures show it on the beams (105 114 118)
	expect (e.emittanceAt(clear, 12.0) * 255.0 - Vec3(105.0, 114.0, 118.0)).length() < 0.01
	# SkyrimClimate's sunrise from 5.5 to 10 and sunset from 16 to 20.5, widened by half an hour
	expect e.hours == Vec4(5.0, 10.0, 16.0, 21.0)
	k = e.weathers.indexOf(clear) ?? fail("no SkyrimClear in the region")
	expect (e.emittanceAt(clear, 7.5) - e.colors[k * 4]).length() < 0.0001
	expect (e.emittanceAt(clear, 1.0) - e.colors[k * 4 + 3]).length() < 0.0001
	# a new game's 8 o'clock: a fifth of the way from the sunrise's middle to the day
	expected = e.colors[k * 4] * 0.8 + e.colors[k * 4 + 1] * 0.2
	expect (e.emittanceAt(clear, 8.0) - expected).length() < 0.0001
