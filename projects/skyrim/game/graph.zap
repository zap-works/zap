# An actor animated by the game's own behavior graph (skyrim/hkx/graph.zap): the events the game
# sends (moveStart, turnLeft, IdleChairFrontEnter...) and the variables it sets (Speed, Direction,
# iSyncIdleLocomotion...) drive the graph's state machines, and each frame it gives the clips
# playing and their weights, which the pose code samples. What the graph does as Havok does it:
# an event goes down the active tree and each state machine takes the first transition of its
# state (then its wildcards) whose event and condition hold, blending over the transition's
# length, the state machine inside the new state starting at the state the transition names; the
# states' enter and exit events are sent in their turn; a clip sends the events its triggers
# name (a clip's end is how a way in turns into its loop); a blender's weights come from its
# children's, or, parametric, from where its blend parameter falls among them (round a circle
# when cyclic); a node is reset when the frame did not reach it. A blender's child that moves only some bones is
# laid over the others by its bone weights (`Layer.bones`). Left out: the modifiers other than
# expressions, the sync points.

import engine
import math
import skyrim
import skyrim.actor
import skyrim.hkx

maxEvents = 96   # events handled a frame: a loop of events ends here
eventGap f32 = 0.1   # seconds between events sent in turn
weightKept f32 = 0.002   # the weight below which a child is not played
noParameter f32 = -1.0e9

# a clip playing: how long it has played (looped by its length when `looping`) and its weight
pub type Layer:
	clip str
	time f32
	weight f32
	looping bool
	bones f32[] = []   # what share of its weight each bone of the skeleton takes, none: all of them

# an event a clip sent as it played: the clip, and the time in it (seconds at its speed 1) of the
# trigger that sent it, which is when its annotation lies in the animation
pub type Fired:
	event str
	clip str
	at f32

# an event the game sends some seconds from now
type Delayed:
	event str
	left f32
# what the graph keeps of one actor: the variables, where each state machine is, the clips' times
pub type Animator:
	vars {str: f32}
	states {i64: i64}   # a state machine's current state (an index of its states)
	was {i64: i64}   # the state it blends away from
	blend {i64: f32}   # seconds of that blend left
	span {i64: f32}   # and its length
	nested {i64: i64}   # the state a state machine enters by when it is next reached
	times {i64: f32}   # a clip's seconds played
	active {i64: bool}   # the nodes the last frame reached
	reached {i64: bool}   # the nodes this one has
	edges {i64: bool}   # an expression that raises an event: whether it held
	took {i64: bool}   # the machines that took the event being handled (a machine takes it once)
	queue str[] = []
	entered str[] = []   # the events the states sent this frame (the game reads IdleChairSitting)
	fired Fired[] = []   # the events the clips sent this frame
	later Delayed[] = []
	layers Layer[] = []
	mask f32[] = []   # the bones' share of the pose the visit is in (a blender's masked child)

# the graph's variables at their starting values
pub fn newAnimator(g hkx.Graph) Animator:
	vars {str: f32} = {}
	for v in g.variables:
		vars[v.name.copy()] = v.value
	Animator(
		vars,
		states = {},
		was = {},
		blend = {},
		span = {},
		nested = {},
		times = {},
		active = {},
		reached = {}, edges = {}, took = {})

pub fn setVariable(mut a Animator, name str, value f32):
	a.vars[name.copy()] = value

pub fn variableOf(a Animator, name str) f32:
	a.vars.get(name) ?? 0.0

# an event the graph is to take next frame
pub fn sendEvent(mut a Animator, name str):
	a.queue.push(name.copy())

# an event the graph is to take after `seconds`
pub fn sendEventAfter(mut a Animator, name str, seconds f32):
	a.later.push(Delayed(event = name.copy(), left = seconds))

# events sent one after the other, a short while apart (the graph enters what an event brings on the
# next frame, which the following event may need)
pub fn sendEventsInTurn(mut a Animator, names str[]):
	for i, name in names:
		a.sendEventAfter(name, f32(i) * eventGap)

# a clip trigger's event, queued and told
fn raise(mut a Animator, event str, clip str, at f32):
	a.queue.push(event.copy())
	a.fired.push(Fired(event = event.copy(), clip = clip.copy(), at))

# the value of a node's member bound to a variable (of its child `slot`, -1 its own), else `otherwise`
fn boundOf(a Animator, n hkx.Node, slot i64, member str, otherwise f32):
	for b in n.bindings:
		if b.slot == slot and b.member == member: return a.vars.get(b.variable) ?? otherwise
	otherwise

fn isBound(n hkx.Node, slot i64, member str):
	n.bindings.any(.slot == slot and .member == member)

fn stateIndexOf(n hkx.Node, id i64):
	n.states.findIndex(.id == id) ?? -1

# the state machine inside the generator at `at` (through the nodes that only pass it on)
fn machineWithin(g hkx.Graph, at i64) i64:
	if at < 0: return -1
	n = g.nodes[at]
	if n.kind == .Machine: return at
	if n.kind == .Pass and not n.children.isEmpty: return g.machineWithin(n.children[0])
	-1

fn sendAll(mut a Animator, events str[]):
	for e in events:
		if e.isEmpty: continue
		a.queue.push(e.copy())
		a.entered.push(e.copy())

# the machine reached for the first time (or again): in its start state, or the one a transition
# named, the state's enter events sent
fn startMachine(mut a Animator, g hkx.Graph, at i64):
	n = g.nodes[at]
	id = i64(a.boundOf(n, -1, "startStateId", f32(n.start)))
	index = n.stateIndexOf(id)
	if a.nested.get(at) is forced:
		index = n.stateIndexOf(forced)
		a.nested.remove(at)
	if index < 0: index = 0
	if n.states.isEmpty: return
	a.states[at] = index
	a.blend[at] = 0.0
	a.sendAll(n.states[index].enter)

# a clip played `dt` seconds, its triggers' events sent; its layer added. `again`: reached before
# this frame, where it already moved on
fn playClip(
	mut a Animator,
	n hkx.Node,
	at i64,
	weight f32,
	durations {str: f32},
	dt f32,
	again bool
):
	length = durations.get(n.clip) ?? 0.0
	speed = n.speed * a.boundOf(n, -1, "playbackSpeed", 1.0)
	before = a.times.get(at) ?? 0.0
	if a.active.get(at) == none and not again: before = 0.0
	after = before + dt * speed
	if length > 0.0:
		for t in n.triggers:
			time = length + t.time if t.fromEnd else t.time
			if n.looping:
				crossed = (before % length < time and after % length >= time) or
					(after >= length and before < length and time <= after % length)
				if crossed and dt > 0.0: a.raise(t.event, n.clip, time)
			elif before < time and after >= time:
				a.raise(t.event, n.clip, time)
		if not n.looping: after = after.min(length)
	a.times[at] = after
	if weight > weightKept:
		a.layers.push(
			Layer(
				clip = n.clip.copy(),
				time = after,
				weight,
				looping = n.looping,
				bones = a.mask.copy()
			)
		)

# the weights of a blender's children
fn blendWeights(a Animator, n hkx.Node, cyclicParameter f32):
	count = n.children.len
	out f32[] = []
	loop count: out.push(0.0)
	if count == 0: return out
	if not n.parametric:
		total = 0.0
		for i in 0..count:
			if n.partial[i]: continue
			out[i] = a.boundOf(n, i, "weight", n.positions[i]).max(0.0)
			total += out[i]
		if total <= 0.0:
			out[0] = 1.0
			return out
		return out.map(it / total)
	parameter = a.boundOf(n, -1, "blendParameter", n.parameter)
	if cyclicParameter > noParameter: parameter = cyclicParameter
	places = (0..count).map(a.boundOf(n, it, "weight", n.positions[it]))
	order = (0..count).filter(not n.partial[it]).sortedBy(places[it])
	if order.isEmpty: return out
	if n.cyclic:
		width = (n.high - n.low).max(1.0e-6)
		parameter = n.low + (((parameter - n.low) % width) + width) % width
		for k in 0..order.len:
			at = places[order[k]]
			next = places[order[(k + 1) % len]] + (width if k + 1 == order.len else 0.0)
			parameter2 = parameter if parameter >= at else parameter + width
			if parameter2 >= at and parameter2 <= next:
				share = (parameter2 - at) / (next - at).max(1.0e-6)
				out[order[k]] += 1.0 - share
				out[order[(k + 1) % len]] += share
				return out
		out[order[0]] = 1.0
		return out
	first = order[0]
	if parameter <= places[first]:
		out[first] = 1.0
		return out
	for k in 0..order.len - 1:
		lower = places[order[k]]
		upper = places[order[k + 1]]
		if parameter <= upper:
			share = (parameter - lower) / (upper - lower).max(1.0e-6)
			out[order[k]] = 1.0 - share
			out[order[k + 1]] = share
			return out
	out[order[len - 1]] = 1.0
	out

# an expression modifier's assignments of the frame: a variable set, an event raised when its
# expression turns true
fn assign(mut a Animator, n hkx.Node, at i64):
	for k, m in n.modifiers:
		value = engine.evaluate(m.expression, a.vars)
		if not m.variable.isEmpty:
			a.vars[m.variable.copy()] = value
		elif not m.event.isEmpty:
			key = at * 64 + k
			held = value != 0.0
			if held and (a.edges.get(key) ?? false) == false: a.queue.push(m.event.copy())
			a.edges[key] = held

# the node and what it plays, `weight` of the pose; `cyclic` the blend parameter a cyclic blend
# transition above it gives its blender
fn visit(mut a Animator, g hkx.Graph, durations {str: f32}, at i64, weight f32, cyclic f32, dt f32):
	if at < 0 or weight <= weightKept: return
	n = g.nodes[at]
	# a node reached again this frame (under a masked child and a whole one) does not move on twice
	again = a.reached.get(at) != none
	step f32 = 0.0 if again else dt
	a.reached[at] = true
	match n.kind:
		Clip: a.playClip(n, at, weight, durations, step, again)
		Pass:
			a.assign(n, at)
			parameter = cyclic
			if n.bindings.find(.member == "fBlendParameter") is b:
				parameter = a.vars.get(b.variable) ?? noParameter
			if not n.children.isEmpty: a.visit(g, durations, n.children[0], weight, parameter, step)
		Selector:
			index = i64(a.boundOf(n, -1, "selectedGeneratorIndex", f32(n.selected)))
			if index >= 0 and index < n.children.len:
				a.visit(g, durations, n.children[index], weight, cyclic, step)
		Blender: a.visitBlender(g, durations, n, weight, cyclic, step)
		Machine: a.visitMachine(g, durations, at, weight, step)
		_: pass

# the share each bone gives the pose of masked child i: its weight times its bone weights
fn shareOf(a Animator, n hkx.Node, i i64):
	w = a.boundOf(n, i, "weight", n.positions[i]).clamp(0.0, 1.0)
	n.bones[i].weights.map(it * w)

# the inner share of each bone inside the outer's (an empty one: all of it)
fn within(outer f32[], inner f32[]):
	if outer.isEmpty: return inner.copy()
	(0..inner.len).map(inner[it] * (outer[it] if it < outer.len else 1.0))

# The bones' share of the pose under each child of a blender. A child that moves only some bones
# (its hkbBoneWeightArray) is laid over the children before it: it takes its share of each bone
# and the children after it that are masked take theirs off it; the whole-body children keep what
# no masked child takes.
fn visitBlender(
	mut a Animator,
	g hkx.Graph,
	durations {str: f32},
	n hkx.Node,
	weight f32,
	cyclic f32,
	dt f32
):
	weights = a.blendWeights(n, cyclic)
	outer = a.mask.copy()
	masked = []
	if not n.parametric:
		for i in 0..n.children.len:
			if n.partial[i] and not a.shareOf(n, i).all(it <= weightKept): masked.push(i)
	left f32[] = []
	width = 0
	for i in masked: width = width.max(n.bones[i].weights.len)
	loop width: left.push(1.0)
	taken {i64: f32[]} = {}
	for k in 0..masked.len:
		i = masked[len - 1 - k]
		share = a.shareOf(n, i)
		taken[i] = (0..share.len).map(share[it] * left[it])
		for b in 0..share.len: left[b] *= 1.0 - share[b]
	for i in 0..n.children.len:
		if n.partial[i] and not n.parametric:
			own = taken.get(i) ?? continue
			a.mask = outer.within(own)
			a.visit(g, durations, n.children[i], weight, noParameter, dt)
		else:
			a.mask = outer.within(left) if not masked.isEmpty else outer.copy()
			a.visit(g, durations, n.children[i], weight * weights[i], noParameter, dt)
	a.mask = outer

fn visitMachine(mut a Animator, g hkx.Graph, durations {str: f32}, at i64, weight f32, dt f32):
	n = g.nodes[at]
	if a.active.get(at) == none or a.states.get(at) == none: a.startMachine(g, at)
	index = a.states.get(at) ?? return
	left = a.blend.get(at) ?? 0.0
	if left > 0.0 and a.was.get(at) is from:
		share = (left / (a.span.get(at) ?? 1.0).max(1.0e-6)).clamp(0.0, 1.0)
		a.visit(g, durations, n.states[from].generator, weight * share, noParameter, dt)
		a.visit(g, durations, n.states[index].generator, weight * (1.0 - share), noParameter, dt)
		a.blend[at] = (left - dt).max(0.0)
	else:
		a.visit(g, durations, n.states[index].generator, weight, noParameter, dt)

# the first transition of the machine's state that the event takes
fn transitionOf(a Animator, n hkx.Node, state i64, event str) hkx.Transition?:
	for t in n.states[state].transitions:
		if t.event == event and
			(t.condition.isEmpty or engine.evaluate(t.condition, a.vars) != 0.0):
			return t.copy()
	for t in n.wildcards:
		if t.event == event and
			(t.condition.isEmpty or engine.evaluate(t.condition, a.vars) != 0.0):
			return t.copy()
	none

fn takeTransition(mut a Animator, g hkx.Graph, at i64, t hkx.Transition):
	n = g.nodes[at]
	to = n.stateIndexOf(t.toState)
	from = a.states.get(at) ?? return
	if to < 0: return
	a.sendAll(n.states[from].exit)
	a.was[at] = from
	a.blend[at] = t.blend
	a.span[at] = t.blend
	a.states[at] = to
	if t.nested > 0:
		inner = g.machineWithin(n.states[to].generator)
		if inner >= 0: a.nested[inner] = t.nested
	a.sendAll(n.states[to].enter)

# the event handed down the nodes the last frame reached, from `at`: a machine that takes it
# does not hand it further
fn handle(mut a Animator, g hkx.Graph, at i64, event str):
	if at < 0 or a.reached.get(at) == none: return
	n = g.nodes[at]
	match n.kind:
		Machine:
			index = a.states.get(at) ?? return
			if a.took.get(at) != none: return
			if a.transitionOf(n, index, event) is t:
				a.took[at] = true
				a.takeTransition(g, at, t)
				return
			a.handle(g, n.states[index].generator, event)
			if a.was.get(at) is from and (a.blend.get(at) ?? 0.0) > 0.0:
				a.handle(g, n.states[from].generator, event)
		Selector, Blender, Pass:
			for c in n.children: a.handle(g, c, event)
		_: pass

# The layers of the frame merged by clip (a clip in two places of the graph weighs both), the
# heaviest first.
fn merged(layers Layer[]):
	out Layer[] = []
	for l in layers:
		found = out.findIndex(.clip == l.clip and .bones == l.bones) ?? -1
		if found < 0:
			out.push(l.copy())
		else:
			if l.weight > out[found].weight:
				out[found].time = l.time
				out[found].looping = l.looping
			out[found].weight += l.weight
	out.sortedBy(-.weight)

# the delayed events whose time has come, queued
fn releaseDue(mut a Animator, dt f32):
	keep = []
	for d in a.later:
		if d.left - dt <= 0.0:
			a.queue.push(d.event.copy())
		else:
			keep.push(Delayed(event = d.event.copy(), left = d.left - dt))
	a.later = keep

# The graph run `dt` seconds: the nodes the active states reach played, the events they and the
# game sent handled (so that what they change shows from the next frame). `durations` the clips'
# lengths by name.
pub fn stepAnimator(mut a Animator, g hkx.Graph, durations {str: f32}, dt f32):
	a.layers = []
	a.entered = []
	a.fired = []
	a.releaseDue(dt)
	a.reached = {}
	a.visit(g, durations, g.root, 1.0, noParameter, dt)
	handled = 0
	while not a.queue.isEmpty and handled < maxEvents:
		event = a.queue.remove(0)
		handled += 1
		a.took = {}
		a.handle(g, g.root, event)
	a.active = a.reached.copy()
	a.layers = merged(a.layers)
	for at in a.states.keys():
		if a.reached.get(at) == none: a.states.remove(at)

# the clip names of the layers
pub fn playingClips(a Animator) str[]:
	a.layers.map(.clip.copy())

type Chosen:
	index i64
	time f32
	weight f32

# The pose of the frame: the heaviest two clips the rig has (`names` and `lengths` by clip),
# blended by their weights; none of them: no clip.
pub fn poseOfLayers(a Animator, names str[], lengths f32[]) engine.Pose:
	chosen = []
	for l in a.layers:
		index = names.indexOf(l.clip) ?? -1
		if index < 0: continue
		length = lengths[index].max(0.01)
		chosen.push(
			Chosen(
				index,
				time = l.time % length if l.looping else l.time.min(length),
				weight = l.weight
			)
		)
		if chosen.len == 2: break
	if chosen.isEmpty: return engine.Pose(clip = -1, time = 0.0)
	first = chosen[0]
	if a.layers.any(not .bones.isEmpty): return a.maskedPose(names, lengths)
	if chosen.len == 1: return engine.Pose(clip = first.index, time = first.time)
	second = chosen[1]
	engine.Pose(clip = first.index, time = first.time, from = second.index, fromTime = second.time,
		blend = first.weight / (first.weight + second.weight))

# the pose of layers some of which move only some bones: the clips averaged bone by bone
fn maskedPose(a Animator, names str[], lengths f32[]):
	mixed = []
	for l in a.layers:
		index = names.indexOf(l.clip) ?? -1
		if index < 0: continue
		length = lengths[index].max(0.01)
		mixed.push(
			engine.PoseLayer(
				clip = index,
				time = l.time % length if l.looping else l.time.min(length),
				weight = l.weight,
				bones = l.bones.copy()
			)
		)
	engine.Pose(clip = mixed[0].clip, time = mixed[0].time, mixed)

# the character's behavior graph of the install in `dir`
pub fn openGraph(dir str) hkx.Graph:
	install = skyrim.openInstall(dir) ?? fail
	install.readCharacterGraph() ?? fail

# an actor the graph animates from how its body moves: the game's events and variables made of
# the feet's and the heading's change
pub type Walker:
	animator Animator
	feet Vec3 = Vec3(0.0, 0.0, 0.0)
	heading f32 = 0.0
	moving bool = false
	turning i64 = 0   # -1 turning left, 1 right, 0 not
	placed bool = false   # whether feet and heading are those of a frame
	scale f32 = 1.0   # the body's scale, which its Speed is divided by

# What SkyrimSE.exe's animation graph channels feed the graph each frame (registered by 0x1406b0650,
# reference/exe/README.md, "Animation: the names"): Speed the body's speed over its scale
# (0x1407c6a10), with the action Move Start when it rises to 5 units a second and Move Stop when it
# falls under; TurnDelta its turn in degrees a second, its sign flipped (0x1407c6be0), with Turn
# Left (positive) or Turn Right (negative) when it rises to 1 degree a second and Turn Stop when it
# falls under (the actions reach the graph through the IDLE records, whose conditions keep the turns
# to a body standing); Direction the way it means to move from the way it faces, a turn's share in
# 0..1 (0x1407c6d60, from the movement controller's wanted direction, not the body's displacement):
# our bodies always walk the way they face, so it stays 0.
movingAt f32 = 5.0
turningAt f32 = 1.0
# an animator in the game's third person: `player` the player's, else an NPC's
pub fn newWalker(g hkx.Graph, player bool) Walker:
	a = g.newAnimator()
	a.setVariable("i1stPerson", 0.0)
	a.setVariable("IsPlayer", 1.0 if player else 0.0)
	a.setVariable("IsNPC", 0.0 if player else 1.0)
	Walker(animator = a)

# The walker a frame on: when `free` (the body moves by itself, not carried by a clip), its
# speed, turn and direction sent as the game's channels send them (above); the graph run `dt`
# seconds.
pub fn stepWalker(
	mut w Walker,
	g hkx.Graph,
	durations {str: f32},
	feet Vec3,
	heading f32,
	free bool,
	dt f32):
	if w.placed and free and dt > 0.0:
		moved = Vec3(feet.x - w.feet.x, feet.y - w.feet.y, 0.0)
		speed = moved.length() / dt / w.scale
		turnDelta = -math.angleBetween(w.heading, heading) / dt * (180.0 / pi)
		w.animator.setVariable("Speed", speed)
		w.animator.setVariable("SpeedSampled", speed)
		w.animator.setVariable("TurnDelta", turnDelta)
		if not w.moving and speed >= movingAt:
			w.moving = true
			w.animator.sendEvent("moveStart")
		elif w.moving and speed < movingAt:
			w.moving = false
			w.animator.sendEvent("moveStop")
		wanted = 0
		if not w.moving and turnDelta.abs() >= turningAt:
			wanted = 1 if turnDelta < 0.0 else -1
		if wanted != w.turning:
			w.animator.sendEvent(
				"turnStop" if wanted == 0 else ("turnRight" if wanted > 0 else "turnLeft")
			)
			w.turning = wanted
	w.feet = feet
	w.heading = heading
	w.placed = true
	w.animator.stepAnimator(g, durations, dt)

# what the walker shows, none when the rig (its clips' `names` and `lengths`) has none of the clips the graph plays
pub fn poseOfWalker(w Walker, names str[], lengths f32[]) engine.Pose?:
	pose = w.animator.poseOfLayers(names, lengths)
	none if pose.clip < 0 else pose

# the heaviest clip of the animator's frame
fn heaviest(a Animator):
	a.layers[0].clip.copy() if not a.layers.isEmpty else ""

fn runStep(
	mut a Animator,
	g hkx.Graph,
	durations {str: f32},
	seconds f32,
	step f32,
	mut seen str[]
):
	loop i64(seconds / step):
		a.stepAnimator(g, durations, step)
		for l in a.layers:
			if l.weight > 0.05 and l.clip not in seen: seen.push(l.clip.copy())

fn runFor(mut a Animator, g hkx.Graph, durations {str: f32}, seconds f32, mut seen str[]):
	a.runStep(g, durations, seconds, 1.0 / 15.0, seen)

# The clips a marker's graph plays: its way in (the first clip other than the one it left to weigh
# in full), its loop (the one it settles on) and its way out (the same, from the loop).
pub type Played:
	enter str
	looping str
	leave str

# the first clip but `besides` that the graph plays in full within `seconds`, else the heaviest
fn firstTaken(
	mut a Animator,
	g hkx.Graph,
	durations {str: f32},
	seconds f32,
	besides str,
	mut seen str[]
):
	loop i64(seconds * 60.0):
		a.runStep(g, durations, 1.0 / 60.0, 1.0 / 60.0, seen)
		if not a.layers.isEmpty and a.layers[0].weight > 0.9 and a.layers[0].clip != besides:
			return a.layers[0].clip.copy()
	a.heaviest()

pub fn playedBy(
	g hkx.Graph,
	durations {str: f32},
	enterEvents str[],
	exitEvent str,
	mut seen str[]
) Played:
	w = g.newWalker(false)
	a = w.animator.copy()
	a.runStep(g, durations, 1.0, 1.0 / 60.0, seen)
	before = a.heaviest()
	a.sendEventsInTurn(enterEvents)
	enter = a.firstTaken(g, durations, 4.0, before, seen)
	a.runStep(g, durations, 25.0, 1.0 / 60.0, seen)
	looping = a.heaviest()
	a.sendEvent(exitEvent)
	leave = a.firstTaken(g, durations, 4.0, looping, seen)
	a.runStep(g, durations, 4.0, 1.0 / 60.0, seen)
	Played(enter, looping, leave)

# The clips the game's locomotion plays: standing, turning either way, and walking and running
# in each direction, at speeds from a crawl to a sprint.
pub fn locomotionClips(g hkx.Graph, durations {str: f32}) str[]:
	seen = []
	w = g.newWalker(false)
	a = w.animator.copy()
	a.runStep(g, durations, 1.0, 1.0 / 60.0, seen)
	for event in ["turnLeft", "turnRight", "turnStop"]:
		a.sendEvent(event)
		a.runStep(g, durations, 1.0, 1.0 / 60.0, seen)
	a.sendEvent("moveStart")
	for direction in (0..8).map(f32(it) * 0.125):
		for speed in [f32(10.0), 50.0, 82.0, 200.0, 350.0]:
			a.setVariable("Direction", direction)
			a.setVariable("Speed", speed)
			a.setVariable("SpeedSampled", speed)
			a.runStep(g, durations, 0.5, 1.0 / 60.0, seen)
	seen

# the name of the state the machine of this name is in, "" when it is in none (not reached)
pub fn stateNameOf(a Animator, g hkx.Graph, machine str) str:
	for at, n in g.nodes:
		if n.kind != .Machine or n.name != machine: continue
		if a.states.get(at) is index: return n.states[index].name.copy()
	""
