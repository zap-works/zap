# The cast's NPCs as the game runs them. Each takes the first of its packages whose conditions
# held at a new game and whose schedule takes in the hour, again at every new game hour and when a
# script asks (EvaluatePackage); it is in the cell while that package's place is. A package that
# travels stands it at its place; a sandbox (sandbox.zap) keeps it busy within its radius. As the
# game does when the player comes into a cell, an actor is found already where its package puts
# it and at what it does. Its head turns to the player who comes near (look.zap).

import engine
import game.sim
import engine.physics
import skyrim.actor
import skyrim.hkx
import world

# why a package is taken again: the hour changed (or a script asked), the cell has just loaded (a
# new game: the actor stands where the cell placed it), or the player waited or slept (the time
# skip: the actor is where its package puts it)
pub type PlanReason:
	Hourly
	Loading
	Skipping

pub type Doing:
	Standing
	Walking
	Entering   # the marker's way in
	Using   # its loop
	Leaving   # its way out

pub type Resident:
	npc i64   # its NpcHead in the cast
	body Player   # its capsule, the way it faces, its gait
	skeleton i64
	present bool = false
	plan i64 = -1   # its package (of its NpcHead's plans), -1 for none
	hour i64 = -1   # the game hour it took its package at
	doing Doing = .Standing
	marker i64 = -1   # the marker it goes to or uses, -1 for none
	using str = ""   # that marker's kind
	graphDriven bool = false   # the behavior graph plays its way in, loop and way out
	path Vec3[] = []   # where it walks, the last point the marker's foot on the navmesh
	along i64 = 0
	clock f32 = 0.0   # seconds into what it does
	until f32 = 0.0   # seconds it keeps on at it
	progress f32 = 0.0   # seconds it walked without coming nearer
	nearest f32 = 0.0
	look Quat = Quat(0.0, 0.0, 0.0, 1.0)   # its head's turn toward the player
	was Vec3 = Vec3(0.0, 0.0, 0.0)   # its feet the frame before
	fighting bool = false   # the fight moves it, not its package (fightScene.zap)
	crossings DoorCrossing[] = []   # the closed doors its path goes through, in order (doors.zap)
	talking bool = false   # in dialogue with the player: its package held (talk.zap)
	turnRate f32 = 0.0   # radians a second it turns to the player while talking
	exit i64 = 0   # the load door it walks to, to go on to its package's place in another cell
	arrival Spot? = none   # where it appears, coming into the cell through a door
	arriveIn f32 = 0.0   # seconds before it does: the walk through the cells before this one

# an actor that went through a load door of the cell
pub type Departure:
	npc i64   # its NpcHead's form id
	door i64   # the door's reference

# the clips of a marker's kind in one skeleton's rig, -1 for one it lacks
pub type ClipSet:
	kind str
	enter i64
	looping i64
	leave i64
	enterEvents str[] = []   # the events the graph is sent to enter the marker, one after the other
	leaveEvent str = ""   # and to leave it

pub type Residents:
	all Resident[]
	sets ClipSet[,]   # by skeleton
	gaits Gaits[]   # by skeleton
	turned i64[,]   # by skeleton: the neck's and the head's nodes
	durations f32[,]   # by skeleton, by clip
	clipNames str[,]   # by skeleton, by clip
	lengths {str: f32}[]   # by skeleton: each clip's duration by its name
	graph hkx.Graph   # the character's behavior graph
	walkers Walker[]   # by resident: its animator
	motions actor.Motion[,]   # by skeleton, by clip: where each clip carries the actor
	taken {i64: i64} = {}   # a marker's user (or one walking to it), by marker
	dice Random = Random(20)
	fallen Fallen[] = []   # the dead, their ragdolls (fallen.zap)
	doorsOpen {i64: bool} = {}   # the doors the actors opened, by reference
	doorUses DoorUse[] = []   # the doors opened since the world last took them (applyDoorUses)
	doorsToClear i64[] = []   # those whose collision has yet to leave the physics world
	town Town? = none   # the cells around this one and the doors between them (townfolk.zap)
	cellId str = ""   # this cell's id in the town
	departed Departure[] = []   # who went through a load door, for the cell it leads to

# The residents given the town they live in, `cellId` the cell they are in: a package whose place
# is in another cell sends the actor to the door that leads there, and one coming from another
# cell appears at the door it came through, after the walk through the cells before this one.
pub fn joinTown(mut rs Residents, move town Town, cellId str):
	rs.town = town
	rs.cellId = cellId.copy()

# the game's hour (0 to 24) of a game time in days
pub fn hourOf(daysPassed f64) f32:
	f32((daysPassed * 24.0) % 24.0)

# seconds of real time a span of game hours lasts at the timescale
fn realSeconds(hours f32, timeScale f32):
	hours * 3600.0 / timeScale.max(1.0)

fn clipIndex(rig engine.Rig, name str):
	rig.clips.findIndex(.name == name) ?? -1

fn clipSetOf(rig engine.Rig, m world.MarkerClips):
	ClipSet(
		kind = m.kind.copy(),
		enter = rig.clipIndex(m.enter),
		looping = rig.clipIndex(m.looping),
		leave = rig.clipIndex(m.leave),
		enterEvents = m.enterEvents.map(.copy()),
		leaveEvent = m.leaveEvent.copy()
	)

fn setsOf(rig engine.Rig, markerClips world.MarkerClips[]):
	markerClips.map(rig.clipSetOf(it))

fn lengthsOf(rig engine.Rig):
	out {str: f32} = {}
	for c in rig.clips: out[c.name.copy()] = c.duration
	out

fn turnedOf(rig engine.Rig):
	["NPC Neck [Neck]", "NPC Head [Head]"].map(rig.names.indexOf(it) ?? -1).filter(it >= 0)

# The cast's NPCs at the game hour, each where its package puts it; `rigs` and `speeds` the
# skeletons' (world.ActorScene's), `load` says whether the character's behavior graph their
# animators run is read (without it they show the poses of their gaits and their markers' clips).
pub fn newResidents(cast world.CastHead, rigs engine.Rig[], speeds f32[,], hour f32,
	load Load) Residents:
	graph = load.characterGraph()
	gaits = (0..rigs.len).map(gaitsOf(rigs[it].clips, speeds[it]))
	all = []
	for k, n in cast.npcs:
		all.push(Resident(npc = k, body = n.start.newPlayer(n.heading, gaits[n.look.skeleton]),
			skeleton = n.look.skeleton))
	walkers = []
	loop cast.npcs.len: walkers.push(graph.newWalker(false))
	rs = Residents(
		all,
		sets = rigs.map(.setsOf(cast.markerClips)),
		gaits,
		turned = rigs.map(.turnedOf()),
		durations = rigs.map(.clips.map(.duration)),
		clipNames = rigs.map(.clips.map(.name.copy())),
		lengths = rigs.map(.lengthsOf()),
		graph = move graph,
		walkers,
		motions = cast.skeletons.map(.motions.copy())
	)
	for k in 0..rs.all.len:
		rs.takePlan(cast, k, hour, .Loading)
	rs

# the package the actor runs at the hour: the first whose conditions held and whose schedule
# takes the hour in, -1 for none
pub fn planAt(n world.NpcHead, hour f32) i64:
	n.plans.findIndex(.holds and .schedule.scheduleMatches(hour, newGameDay)) ?? -1

fn isSandbox(p world.PlanHead):
	p.template.lower().startsWith("sandbox") or p.template == "Eat" or p.template == "Sleep"

# where an actor coming to its package's place stands: where the cell placed it when that is
# within the place's radius, else at the place
fn arrivalOf(n world.NpcHead, p world.PlanHead):
	if n.refId != 0 and (n.start - p.center).length() <= p.radius.max(arrival):
		return (n.start, n.heading)
	(p.center, n.heading)

# whether the actor stands within its package's place
fn inPlace(r Resident, p world.PlanHead):
	(r.body.feetOf() - p.center).length() <= p.radius.max(arrival)

# where the actor is put as it takes the package: a new game leaves it at the reference the cell
# placed it at (it walks to the place), a time skip puts it at the place unless it is there
fn placeFor(r Resident, n world.NpcHead, p world.PlanHead, entry PlanReason):
	match entry:
		Loading: (n.start, n.heading) if n.refId != 0 else (p.center, n.heading)
		Skipping:
			if r.present and r.inPlace(p): return (r.body.feetOf(), r.body.heading)
			(p.center, n.heading)
		Hourly: n.arrivalOf(p)

# The actor's package taken again at the hour: in the cell or out of it, and when it changed (or
# the cell has just loaded, or the time skipped), placed where it goes and set at what it does
# there.
pub fn takePlan(mut rs Residents, cast world.CastHead, k i64, hour f32, entry PlanReason):
	n = cast.npcs[rs.all[k].npc]
	plan = n.planAt(hour)
	rs.all[k].hour = i64(hour)
	was_plan = rs.all[k].plan
	if plan == rs.all[k].plan and
		(entry == .Hourly or
				(entry == .Skipping and plan >= 0 and rs.all[k].inPlace(n.plans[plan]))):
		return
	rs.all[k].plan = plan
	rs.free(k)
	was = rs.all[k].present
	rs.all[k].exit = 0
	rs.all[k].arrival = none
	rs.all[k].arriveIn = 0.0
	if plan < 0 and n.refId != 0: return rs.stayPlaced(k, n, was)
	rs.all[k].present = plan >= 0 and n.plans[plan].inCell
	if entry == .Hourly and was and not rs.all[k].present:
		rs.all[k].exit = rs.exitDoorOf(n, plan)
		rs.all[k].present = rs.all[k].exit != 0
	if entry == .Hourly and not was and rs.all[k].present:
		rs.awaitArrival(n, was_plan, plan, k)
	if not rs.all[k].present: return
	p = n.plans[plan]
	if (entry != .Hourly or not was) and rs.all[k].exit == 0:
		at, heading = rs.all[k].placeFor(n, p, entry)
		if entry == .Skipping and was: rs.openAlong(cast, k, rs.all[k].body.feetOf(), at)
		rs.all[k].body.controller.feet = at
		rs.all[k].body.heading = heading
	rs.all[k].doing = .Standing
	rs.all[k].clock = 0.0
	rs.all[k].until = 0.0
	if p.isSandbox() and (entry == .Skipping or (entry == .Loading and rs.all[k].inPlace(p))):
		rs.settle(cast, k)

# An actor this cell places that no package takes is left to the game's default: it stays where it
# is, or, not yet here, where the cell placed it.
fn stayPlaced(mut rs Residents, k i64, n world.NpcHead, was bool):
	rs.all[k].present = true
	if not was:
		rs.all[k].body.controller.feet = n.start
		rs.all[k].body.heading = n.heading
	rs.all[k].doing = .Standing
	rs.all[k].clock = 0.0
	rs.all[k].until = 0.0

# The player waited or slept `seconds` of game time, ending at `hour`. The game runs the actors in
# ticks of iSecondsToSleepPerUpdate (`tick`, 900) game seconds, the clock moved on first
# (Actor::AdvanceSleepWaitTick, 0x140749560): each tick every loaded actor of the process lists is
# updated with the tick as its elapsed time (0x14067be00, Character 0x140679d50), long enough for
# its path, so it ends at its package's place at the tick's hour, the doors on the way opened;
# the actors out of the lists follow each hour (UpdateNonHighActors, 0x14077bbc0).
pub fn skipTime(mut rs Residents, cast world.CastHead, hour f32, seconds f64 = 0.0,
	tick f64 = 900.0):
	ticks = i64((seconds + tick - 1.0) / tick).max(1)
	for t in 1..=(ticks):
		back = f32((ticks - t) * tick / 3600.0)
		at = ((hour - back) % 24.0 + 24.0) % 24.0
		for k in 0..rs.all.len:
			if rs.fallenIndex(k) >= 0 or rs.all[k].fighting: continue
			rs.takePlan(cast, k, at, .Skipping)

# the marker the actor held let go
fn free(mut rs Residents, k i64):
	m = rs.all[k].marker
	if m >= 0 and (rs.taken.get(m) ?? -1) == k: rs.taken.remove(m)
	rs.all[k].marker = -1

# The actors' frame: each package taken again at a new game hour or when a script asked, each
# present actor at what it does for dt seconds, its head eased toward the player near it; the
# fallen posed by their ragdolls.
pub fn stepResidents(
	mut rs Residents,
	cast world.CastHead,
	hour f32,
	timeScale f32,
	mut evaluate {i64: bool},
	player Vec3,
	mut w physics.World,
	dt f32
):
	rs.clearOpened(w)
	rs.followRagdolls(cast, w)
	for k in 0..rs.all.len:
		if rs.fallenIndex(k) >= 0: continue
		rs.all[k].was = rs.all[k].body.feetOf()
		if rs.all[k].fighting: continue
		n = cast.npcs[rs.all[k].npc]
		asked = n.refId != 0 and evaluate.get(n.refId) != none
		if asked: evaluate.remove(n.refId)
		if asked or i64(hour) != rs.all[k].hour: rs.takePlan(cast, k, hour, .Hourly)
		if rs.all[k].arrival != none: rs.stepArrival(k, dt)
		if not rs.all[k].present: continue
		if rs.all[k].talking:
			rs.holdTalking(cast, k, timeScale, player, w, dt)
		else:
			rs.act(cast, k, timeScale, w, dt)
		rs.all[k].look = rs.lookToward(cast, k, player, dt)
		rs.stepGraph(k, dt)

# the actor's animator run a frame: it sees the body's speed and turn while the body moves by
# itself (standing, walking), not carried by a marker's clip
fn stepGraph(mut rs Residents, k i64, dt f32):
	r = rs.all[k]
	free = r.doing == .Standing or r.doing == .Walking or r.fighting
	rs.walkers[k].stepWalker(rs.graph, rs.lengths[r.skeleton], r.body.feetOf(), r.body.heading,
		free, dt)

# The actor's marker entered or left, as the game does it: the events the graph is given for that
# kind of marker (the IDLE records' own, markers.zap).
fn sendMarkerEvent(mut rs Residents, k i64, entering bool):
	r = rs.all[k]
	if not r.graphDriven: return
	set = rs.setOf(r)
	if entering:
		rs.walkers[k].animator.sendEventsInTurn(set.enterEvents)
	else:
		rs.walkers[k].animator.sendEvent(set.leaveEvent)

# the actor found already in its marker's loop: the graph run through the way in
pub fn runIn(mut rs Residents, k i64):
	rs.sendMarkerEvent(k, true)
	r = rs.all[k]
	seconds = rs.clipLength(r.skeleton, rs.setOf(r).enter) + 1.0
	loop i64(seconds * 60.0):
		rs.walkers[k].stepWalker(rs.graph, rs.lengths[r.skeleton], r.body.feetOf(), r.body.heading,
			false, 1.0 / 60.0)

# The present actors' bodies of the frame, the model of each the cast's (after the player's).
pub fn residentPoses(rs Residents) world.ActorPose[]:
	out = []
	for k, r in rs.all:
		if not r.present: continue
		pose = rs.poseOfResident(k)
		pose.turn = r.look
		pose.turned = rs.turned[r.skeleton].copy()
		f = rs.fallenIndex(k)
		if f >= 0: pose = engine.Pose(clip = -1, time = 0.0, locals = rs.fallen[f].pose.copy())
		out.push(world.ActorPose(model = r.npc + 1, pose, feet = yUp.applyPoint(r.body.feetOf()),
			yaw = -r.body.heading))
	out

# the pose of resident k: what it does, or fights
pub fn poseOfResident(rs Residents, k i64) engine.Pose:
	rs.residentPose(k)

# the pose of what the actor does: the graph's when it plays it, else its gait, or a marker's
# clips eased in from what came before
fn residentPose(rs Residents, k i64):
	r = rs.all[k]
	played = r.doing == .Standing or r.doing == .Walking or r.graphDriven or r.fighting
	if played and
		rs.walkers[k].poseOfWalker(
			rs.clipNames[r.skeleton],
			rs.durations[r.skeleton]
		) is p:
		return p
	set = rs.setOf(r)
	ease = (r.clock * 4.0).min(1.0)
	idle = rs.gaits[r.skeleton].idle
	match r.doing:
		Standing, Walking: r.body.poseOf()
		Entering:
			engine.Pose(
				clip = set.enter if set.enter >= 0 else set.looping,
				time = r.clock,
				from = idle,
				fromTime = 0.0, blend = ease)
		Using:
			d = rs.durations[r.skeleton][set.looping].max(0.1) if set.looping >= 0 else 1.0
			engine.Pose(clip = set.looping, time = r.clock % d, from = set.enter,
				fromTime = rs.clipLength(r.skeleton, set.enter), blend = ease)
		Leaving:
			engine.Pose(clip = set.leave, time = r.clock, from = set.looping, fromTime = 0.0,
				blend = ease)

fn clipLength(rs Residents, skeleton i64, clip i64):
	rs.durations[skeleton][clip] if clip >= 0 else 0.0

# where a clip carries the actor (none: nowhere)
fn motionOf(rs Residents, skeleton i64, clip i64):
	rs.motions[skeleton][clip].copy() if clip >= 0 else actor.stillMotion()

# the clips of the marker the actor uses (none: its idle)
fn setOf(rs Residents, r Resident):
	idle = rs.gaits[r.skeleton].idle
	standing = ClipSet(kind = "", enter = idle, looping = idle, leave = idle)
	if r.marker < 0: return standing
	rs.sets[r.skeleton].find(.kind == r.using) ?? standing

# a line for each actor: where it is and what it does under which package, or that it is away
pub fn residentsText(rs Residents, cast world.CastHead) str[]:
	out = []
	for r in rs.all:
		n = cast.npcs[r.npc]
		plan = n.plans[r.plan].editorId if r.plan >= 0 else "no package"
		if not r.present:
			out.push("{n.name}: away ({plan})")
			continue
		f = r.body.feetOf()
		what = "{r.doing}" if r.marker < 0 else "{r.doing} {r.using}"
		out.push("{n.name}: at {f.x:.0}, {f.y:.0}, {f.z:.0}, {what} ({plan})")
	out

# the world's reference of the resident's actor: its placed one, else the one the world gives its
# base (a visitor's), 0 for none
pub fn worldRefOf(n world.NpcHead, w sim.GameWorld) i64:
	if n.refId != 0: return n.refId
	for refId, a in w.actors:
		if a.npc == n.formId: return refId
	0

# The actors' places written into the world, where the crosshair and the conditions find them: one
# present stands where it is in the cell, one away is in no cell; the doors they opened since are
# activated in it, those that opened returned.
pub fn placeInWorld(mut rs Residents, cast world.CastHead, mut w sim.GameWorld) DoorOpening[]:
	for r in rs.all:
		refId = cast.npcs[r.npc].worldRefOf(w)
		if w.forms.get(refId) == none: continue
		feet = r.body.feetOf()
		w.forms[refId].x = feet.x
		w.forms[refId].y = feet.y
		w.forms[refId].z = feet.z
		w.forms[refId].rotation = Vec3(0.0, 0.0, r.body.heading)
		w.forms[refId].cell = w.cell if r.present else 0
	rs.applyDoorUses(cast, w)
