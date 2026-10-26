# The character's behavior graph as the game ships it, read from the player's install (skipped
# without it): its state machines, and the clips it plays as events and variables drive it.

import fs
import skyrim
import skyrim.esm
import skyrim.hkx
import skyrim.actor
import game

# the graph and the clips' lengths; none without the install
type Loaded:
	graph hkx.Graph
	lengths {str: f32}

fn withGraph() Loaded?:
	if not fs.exists(esm.defaultEsm()): return none
	install = skyrim.openInstall(skyrim.defaultInstall) ?? fail
	g = install.readCharacterGraph() ?? fail
	Loaded(lengths = install.clipDurations(g.clipNamesOf()), graph = g)

fn run(mut a game.Animator, l Loaded, seconds f32):
	loop i64(seconds * 30.0): a.stepAnimator(l.graph, l.lengths, 1.0 / 30.0)

# the clip that weighs most in the frame
fn playing(a game.Animator):
	a.layers[0].clip if not a.layers.isEmpty else ""

fn thirdPerson(l Loaded):
	l.graph.newWalker(true).animator

test "the master graph and the behaviors it refers to are one graph of state machines":
	l = withGraph() ?? return
	machines = l.graph.nodes.filter(.kind == .Machine)
	states = machines.map(.states.len).sum()
	print("{machines.len > 400} {states > 1500} {l.graph.nodes[l.graph.root].name}")
	prints "true true Master_Behavior"
	expect l.graph.variables.any(.name == "Speed") and
		l.graph.variables.any(.name == "iSyncIdleLocomotion")

test "moveStart then moveStop goes idle, walk, idle; the speed picks the run":
	l = withGraph() ?? return
	a = l.thirdPerson()
	a.run(l, 1.0)
	expect a.playing() == "mt_idle"
	a.sendEvent("moveStart")
	a.setVariable("Speed", 82.45)
	a.setVariable("SpeedSampled", 82.45)
	a.run(l, 1.0)
	expect a.playing() == "mt_walkforward"
	a.setVariable("Speed", 351.0)
	a.setVariable("SpeedSampled", 351.0)
	a.run(l, 1.0)
	expect a.playing() == "mt_runforward"
	a.setVariable("Direction", 0.125)
	a.run(l, 0.5)
	expect a.playing() == "mt_runforwardright"
	a.sendEvent("moveStop")
	a.setVariable("Speed", 0.0)
	a.setVariable("SpeedSampled", 0.0)
	a.setVariable("Direction", 0.0)
	a.run(l, 1.0)
	expect a.playing() == "mt_idle"

test "turning in place plays the turn clip and stopping the turn goes back to the idle":
	l = withGraph() ?? return
	a = l.thirdPerson()
	a.run(l, 1.0)
	a.sendEvent("turnRight")
	a.run(l, 0.5)
	expect a.playing() == "mt_turnright60"
	a.sendEvent("turnStop")
	a.run(l, 1.0)
	expect a.playing() == "mt_idle"

test "sitting on a chair enters, then loops the sit idle, and leaving goes back to standing":
	l = withGraph() ?? return
	a = l.thirdPerson()
	a.run(l, 1.0)
	a.sendEvent("IdleChairFrontEnter")
	a.run(l, 0.5)
	expect a.playing() == "chair_frontentervar1"
	a.run(l, l.lengths.get("chair_frontentervar1") ?? 0.0)
	a.run(l, 1.0)
	expect a.playing() == "chair_idlebasevar1"
	a.run(l, 20.0)
	expect a.playing() == "chair_idlebasevar1"
	a.sendEvent("IdleChairFrontExit")
	a.run(l, 0.5)
	expect a.playing() == "chair_frontexit"
	a.run(l, 3.0)
	expect a.playing() == "mt_idle"

test "a body that starts walking and stops is seen by the graph as moveStart and moveStop":
	l = withGraph() ?? return
	w = l.graph.newWalker(false)
	feet = Vec3(0.0, 0.0, 0.0)
	seen str[] = []
	for frame in 0..90:
		if frame >= 30 and frame < 60: feet.y += 90.0 / 30.0
		w.stepWalker(l.graph, l.lengths, feet, 0.0, true, 1.0 / 30.0)
		clip = w.animator.playing()
		if seen.isEmpty or seen[len - 1] != clip: seen.push(clip)
	print(seen)
	prints "[\"mt_idle\", \"mt_walkforward\", \"mt_idle\"]"

test "the events of the IDLE records take the graph through the clips of every marker's kind":
	l = withGraph() ?? return
	_, plugin = skyrim.installAndPlugin() ?? return
	seen = []
	kinds = l.graph.markerClipsOf(plugin, l.lengths, seen)
	by = kinds.map(.kind)
	for kind in ["chair", "chair behind", "bed", "leantable", "counter", "sweep"]:
		expect kind in by
	lean = kinds.find(.kind == "leantable") ?? fail("no leantable")
	expect lean.enterEvents == ["IdleLeanTableEnter"] and lean.leaveEvent == "IdleChairExitStart"
	expect lean.enter == "idleleantable_enter" and lean.looping == "idleleantable" and
		lean.leave == "idleleantable_exit"
	counter = kinds.find(.kind == "counter") ?? fail("no counter")
	expect counter.enterEvents == ["IdleCounterStart"]
	expect counter.enter == "animobjectcounterenter" and
		counter.looping == "animobjectcounteridleloopright" and
		counter.leave == "animobjectcounterexit"
	sweep = kinds.find(.kind == "sweep") ?? fail("no sweep")
	expect sweep.enterEvents == ["idleLooseSweepingStart"] and sweep.leaveEvent == "IdleStop"
	expect sweep.enter == "animobjectsweepingidlestart" and
		sweep.looping == "animobjectsweepingidlebase"
	chair = kinds.find(.kind == "chair") ?? fail("no chair")
	expect chair.enterEvents == ["IdleChairFrontEnter"] and chair.leaveEvent == "IdleChairFrontExit"
	expect chair.enter == "chair_frontentervar1" and chair.looping == "chair_idlebasevar1" and
		chair.leave == "chair_frontexit"

test "a seat entered from behind sits at once and is left backwards, as the graph plays it":
	l = withGraph() ?? return
	_, plugin = skyrim.installAndPlugin() ?? return
	seen = []
	kinds = l.graph.markerClipsOf(plugin, l.lengths, seen)
	behind = kinds.find(.kind == game.chairBehind) ?? fail("no seat from behind")
	expect behind.enterEvents == ["IdleChairFrontEnter", "IdleChairEnterInstant"]
	expect behind.enter == "" and behind.looping == "chair_idlebasevar1" and
		behind.leave == "tablebackexit"
	bed = kinds.find(.kind == "bed") ?? fail("no bed")
	expect bed.enterEvents == ["IdleBedLeftEnterStart"] and bed.leaveEvent == "IdleBedExitStart"

test "a blender's child that moves only some bones lays its clip over the others by its bone weights":
	l = withGraph() ?? return
	a = l.thirdPerson()
	a.takeStance(0, 0, true)
	a.sendEvent("WeapEquip")
	a.run(l, 3.0)
	a.setVariable("Speed", 200.0)
	a.sendEvent("moveStart")
	a.run(l, 1.0)
	masked = a.layers.filter(not .bones.isEmpty)
	expect masked.len == 2 and
		masked.map(.clip).sorted() == ["1hm_walkforward", "h2h_locomotionpose"]
	for m in masked:
		expect m.bones.all(it >= 0.0 and it <= 1.0)
		expect m.bones.any(it > 0.0) and m.bones.any(it < 1.0)
	bones = masked.map(.bones.len).min() ?? 0
	uncovered = 0
	for bone in 0..bones:
		share = f32(0.0)
		for m in masked: share += m.weight * m.bones[bone]
		expect share <= 1.01
		if share < 0.99: uncovered += 1
	expect uncovered <= 3
	names = a.playingClips()
	pose = a.poseOfLayers(names, names.map(l.lengths.get(it) ?? 1.0))
	expect pose.mixed.len == names.len and pose.mixed.all(not .bones.isEmpty)
