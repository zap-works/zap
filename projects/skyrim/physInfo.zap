# Builds a cell's physics from the plugin and the install and runs it without a window. Run from
# the repository root:
#
#   zap run projects/skyrim/physInfo.zap                      the inn's counts, 5 s of its clutter
#   zap run projects/skyrim/physInfo.zap --cell X --seconds 10
#   zap run projects/skyrim/physInfo.zap --drop BasicTankard01 -700,500,200    rest height, bounces
#   zap run projects/skyrim/physInfo.zap --walk -1300,0,10 200,0 4             the player walked
#   zap run projects/skyrim/physInfo.zap --hanging [--seconds 5]   the constrained clutter: each
#       body's rest under its anchor, its chain, whether it sleeps; when it came to rest

import math
import skyrim
import skyrim.esm
import skyrim.nif
import engine.physics
import game

frame f32 = 1.0 / 60.0

# the n words after the flag, none when it is not given
fn after(flag str, n i64) str[]?:
	at = try args.indexOf(flag)
	if at + n >= args.len: fail("{flag} takes {n} values")
	args[i64(at) + 1..i64(at) + 1 + n].copy()

fn numbers(text str):
	text.split(",").map(f32.parse(it) ?? fail("not a number in {text}"))

fn showVec(v Vec3):
	"({v.x:.1} {v.y:.1} {v.z:.1})"

fn printCounts(cw game.CellWorld):
	print("static shapes {cw.staticShapes}, {cw.world.scene.triangleCount()} triangles; floors at {cw.floors}")
	kinds {str: i64} = {}
	for p in cw.placed:
		kinds.add(p.shape, 1)
	print("dynamic bodies {cw.placed.len}: {kinds.keys().sorted().map("{it} {kinds.get(it) ?? 0}").join(", ")}")

fn settle(mut cw game.CellWorld, seconds f32):
	start = clockMs()
	cw.world.step(seconds)
	took = clockMs() - start
	asleep = cw.placed.count(cw.world.bodies[.body].asleep)
	below = cw.placed.count(cw.isBelowFloor(it))
	print("{seconds} s in {cw.world.steps} steps took {took} ms: {asleep} of {cw.placed.len} asleep, {below} below their floor")
	worst = cw.placed.sortedBy(-cw.displacement(it))
	print("largest displacement {cw.displacement(worst.first ?? return):.2}; the worst:")
	for p in worst[..len.min(8)]:
		b = cw.world.bodies[p.body]
		print("  {p.editorId} ({p.shape}): {cw.displacement(p):.2} from {p.at.showVec()} to {b.position.showVec()}{"" if b.asleep else " awake"}")

# a body of the base record dropped at `at` (unturned) into the cell's world
fn drop(
	mut cw game.CellWorld,
	install skyrim.Install,
	mut plugin esm.Esm,
	cell esm.Cell,
	mut models {str: nif.Collider[]},
	editorId str,
	at Vec3
):
	model = ""
	for r in cell.refs:
		b = plugin.baseRecord(r.base) ?? continue
		if b.editorId == editorId: model = b.model
	if model.isEmpty: fail("no {editorId} with a model in the cell")
	before = cw.placed.len
	key = install.loadColliders(model, models)
	cw.addModel(models.get(key) ?? [], editorId, Mat4.translation(at), false)
	if cw.placed.len == before: fail("{editorId}'s model has no dynamic body")
	i = cw.placed[before].body
	bounces = 0
	rising = false
	loop 600:
		cw.world.step(frame)
		up = cw.world.bodies[i].velocity.z > cw.world.unitsPerMeter * 0.1
		if up and not rising: bounces += 1
		rising = up
	b = cw.world.bodies[i]
	print("{editorId} dropped from {at.showVec()}: rests at {b.position.showVec()}, its lowest point at {b.lowest():.2} over the floor at {cw.floorUnder(at.z)}, {bounces} bounces{"" if b.asleep else ", awake"}")

# the constrained bodies run for `seconds`: when each chain last moved, where its bodies rest
fn printHanging(mut cw game.CellWorld, seconds f32):
	rested = fill(cw.chains.len, f32(0.0))
	loop i64(seconds / frame):
		cw.world.step(frame)
		for k, chain in cw.chains:
			if chain.bodies.any(not cw.world.bodies[it].asleep):
				rested[k] = f32(cw.world.steps) * cw.world.subStep
	for k, chain in cw.chains:
		below, far = cw.chainReach(chain)
		anchor = "free"
		if chain.anchor is a: anchor = a.showVec()
		gaps = chain.joints.map("{cw.world.joints[it].pivotGap(cw.world.bodies):.2}").join(" ")
		print("{chain.editorId}: {chain.bodies.len} bodies from {anchor}, the lowest {below:.1} below it, the farthest {far:.1} from it, at rest after {rested[k]:.2} s; pivot gaps {gaps}")
		for i in chain.bodies:
			b = cw.world.bodies[i]
			print("  body {i} rests at {b.position.showVec()}{" asleep" if b.asleep else " awake"}")

fn walk(mut cw game.CellWorld, from Vec3, velocity Vec3, seconds f32):
	c = from.playerController()
	lowest = from.z
	steadyFloor = true
	frames = i64(seconds / frame)
	for k in 0..frames:
		feet = c.walk(cw.world, velocity, frame)
		lowest = lowest.min(feet.z)
		if k > 30 and not c.onFloor: steadyFloor = false
	floor = cw.floorUnder(from.z)
	print("walked from {from.showVec()} at {velocity.showVec()} for {seconds} s: ends at {c.feet.showVec()}, {"on the floor" if c.onFloor else "in the air"}, lowest {lowest:.2} over the floor at {floor}{", stayed on it" if steadyFloor and lowest >= floor - 1.0 else ", left it"}")

install = skyrim.openInstall(args.option("--install") ?? skyrim.defaultInstall) ?? fail
plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
name = args.option("--cell") ?? "RiverwoodSleepingGiantInn"
cell = plugin.findCell(name) ?? fail("no {name} in {install.data}")
models {str: nif.Collider[]} = {}
started = clockMs()
cw = install.cellWorld(plugin, cell, models)
print("{name}: built in {clockMs() - started} ms")
cw.printCounts()
if after("--drop", 2) is d:
	v = numbers(d[1])
	cw.drop(install, plugin, cell, models, d[0], Vec3(v[0], v[1], v[2]))
elif after("--walk", 3) is w:
	at = numbers(w[0])
	by = numbers(w[1])
	cw.walk(
		Vec3(at[0], at[1], at[2]),
		Vec3(by[0], by[1], 0),
		f32.parse(w[2]) ?? fail("not seconds: {w[2]}")
	)
elif args.hasFlag("--hanging"):
	cw.printHanging(f32.parse(args.option("--seconds") ?? "5") ?? fail("not seconds"))
else:
	cw.settle(f32.parse(args.option("--seconds") ?? "5") ?? fail("not seconds"))
