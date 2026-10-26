# The readers on the player's Skyrim.esm and archives, in place: cells, models, collision, HKX; skipped quietly without them.

import fs
import skyrim
import skyrim.esm
import skyrim.hkx
import skyrim.nif
import skyrim.actor

inn = "RiverwoodSleepingGiantInn"

test "the Sleeping Giant Inn is found, with its light and its references resolved":
	if not fs.exists(esm.defaultEsm()):
		eprint("skipped: no {esm.defaultEsm()}")
		return
	plugin = esm.openEsm(esm.defaultEsm()) ?? fail
	cell = plugin.findCell(inn.upper()) ?? fail("no {inn}")
	expect cell.editorId == inn
	expect (cell.flags & 1) == 1
	expect cell.water == none
	light = cell.lighting ?? fail("no XCLL")
	expect light.fogFar > light.fogNear and light.ambientCube.len == 6
	expect cell.refs.len > 100
	modelled = 0
	for r in cell.refs:
		b = plugin.baseRecord(r.base) ?? continue
		if b.kind == "LIGH":
			expect (b.light ?? fail("a light without DATA")).radius > 0
		if not b.model.isEmpty: modelled += 1
	expect modelled * 10 > cell.refs.len * 9
	expect plugin.findCell("NoSuchCellAnywhere") == none

# the install and the barrel's model read from it, none without the install
fn withBarrel() (skyrim.Install, nif.Nif)?:
	if not fs.exists(esm.defaultEsm()):
		eprint("skipped: no {esm.defaultEsm()}")
		return none
	install = skyrim.openInstall(skyrim.defaultInstall) ?? fail
	barrel = install.readModel("meshes/clutter/barrel01.nif") ?? fail
	(install, barrel)

test "the barrel's model reads into one textured part, and every model of the inn reads":
	install, barrel = withBarrel() ?? return
	parts = barrel.drawParts()
	expect parts.len == 1
	part = parts[0]
	expect part.indices.len / 3 == 396 and part.positions.len == 286
	expect part.uvs.len == 286 and part.normals.len == 286 and not part.skinned
	expect part.diffuse.lower().endsWith(".dds") and part.normal.lower().endsWith(".dds")
	height = part.positions.map(.z).max() ?? 0.0
	expect height > 50.0 and height < 100.0
	plugin = esm.openEsm(esm.defaultEsm()) ?? fail
	cell = plugin.findCell(inn) ?? fail("no {inn}")
	keys = plugin.cellModels(cell)
	expect keys.len > 100
	for key in keys:
		model = install.readModel(key) ?? fail
		expect model.header.bsVersion == 100

# The HKX readers: the character skeleton and the male animations.
# whether every edge of the collider's triangles is shared by two of them; `welded`: corners at
# one place (to a hundredth of a unit) are one, as a mesh's chunks repeat their shared vertices
fn isClosed(c nif.Collider, welded bool):
	corners = c.positions.map(
		"{(.x * 100.0).round()} {(.y * 100.0).round()} {(.z * 100.0).round()}"
	) if welded else (0..c.positions.len).map("{it}")
	edges {str: i64} = {}
	for t in 0..c.indices.len / 3:
		for e in 0..3:
			a = corners[c.indices[t * 3 + e]]
			b = corners[c.indices[t * 3 + (e + 1) % 3]]
			edges.add("{a}|{b}" if a < b else "{b}|{a}", 1)
	edges.values().all(it == 2)

test "the inn's collision: the barrel's a closed round shell as tall as it, every body read, near its mesh":
	install, barrel = withBarrel() ?? return
	colliders = barrel.collisionShapes()
	expect colliders.len == 1
	c = colliders[0]
	expect c.kinds == ["mesh"] and c.motion == .Fixed and nif.layerNames[c.layer] == "static"
	expect c.indices.len / 3 > 100 and c.isClosed(welded = true)
	drawn = nif.partPositions(barrel.drawParts())
	height = drawn.map(.z).max() ?? 0.0
	expect ((c.positions.map(.z).max() ?? 0.0) - height).abs() < height * 0.05
	widest = drawn.map(.xy.length()).max() ?? 0.0
	for p in c.positions:
		expect p.xy.length() > widest * 0.7 and p.xy.length() < widest * 1.05
	plugin = esm.openEsm(esm.defaultEsm()) ?? fail
	cell = plugin.findCell(inn) ?? fail("no {inn}")
	bodies = 0
	for key in plugin.cellModels(cell):
		model = install.readModel(key) ?? fail
		if not (0..model.blocks.len).any(model.blockKind(it) == "bhkCollisionObject"): continue
		bodies += 1
		solid = model.collisionShapes()
		expect not solid.isEmpty and solid.all(not .indices.isEmpty)
		for s in solid:
			if s.kinds.all(it != "mesh"): expect s.isClosed(welded = false)
		fit = nif.collisionFit(solid, model.drawParts())
		expect fit.overflow < 0.2 and fit.offset < 0.45
	expect bodies > 100

# The HKX readers: the character skeleton and the male animations.

# the bytes of a file of the install, none without one
fn gameFile(key str):
	if not fs.exists("{skyrim.defaultInstall}/Skyrim - Animations.bsa"): return none
	match skyrim.openInstall(skyrim.defaultInstall):
		install: return install.installRead(key)
		error: return none

fn animation(name str) hkx.Animation?:
	bytes = try gameFile("{actor.maleAnimations}{name}.hkx")
	hkx.readAnimation(bytes) ?? fail

fn isFiniteTransform(t hkx.Transform):
	p = t.translation
	q = t.rotation
	s = t.scale
	[p.x, p.y, p.z, q.x, q.y, q.z, q.w, s.x, s.y, s.z].all(hkx.isFinite)

# how far apart two turns are: 0 for the same, 1 for opposite ones
fn turnBetween(a Quat, b Quat):
	1.0 - (a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w).abs()

# the largest step of a turn and of a translation of any track between two frames in a row
fn largestSteps(a hkx.Animation):
	turn f32 = 0.0
	shift f32 = 0.0
	before = a.frame(0)
	for i in 1..a.frames:
		now = a.frame(i)
		for t in 0..now.len:
			expect now[t].isFiniteTransform()
			turn = turn.max(now[t].rotation.turnBetween(before[t].rotation))
			shift = shift.max((now[t].translation - before[t].translation).length())
		before = now
	(turn, shift)

test "the character skeleton: 99 bones from NPC Root, parents before children":
	bytes = gameFile(actor.characterSkeleton) ?? return
	s = hkx.readSkeleton(bytes) ?? fail
	expect s.bones.len == 99
	expect s.bones[0].name == "NPC Root [Root]" and s.bones[0].parent == -1
	for name in ["NPC Pelvis [Pelv]", "NPC Spine [Spn0]", "NPC Head [Head]", "NPC L Thigh [LThg]"]:
		expect s.boneNamed(name) != none
	for i in 0..s.bones.len:
		expect s.bones[i].parent < i and s.bones[i].pose.isFiniteTransform()

test "the idle: 9 seconds at 30 frames a second, smooth, its body where the skeleton stands it":
	a = animation("mt_idle") ?? return
	expect a.frames == 275 and a.trackCount() == 99
	expect a.duration.isClose(9.133333, 0.001) and (1.0 / a.frameDuration).isClose(30.0, 0.01)
	turn, shift = a.largestSteps()
	expect turn < 0.001 and shift < 0.5
	com = a.frame(a.frames / 2)[4].translation
	expect (com - Vec3(0.0, 0.0, 68.91)).length() < 5.0

test "the walk: a loop whose legs turn smoothly from frame to frame":
	a = animation("mt_walkforward") ?? return
	expect a.frames == 35
	turn, shift = a.largestSteps()
	expect turn < 0.02 and shift < 5.0
	first = a.frame(0)
	last = a.frame(a.frames - 1)
	for leg in [6, 9]:
		expect first[leg].rotation.turnBetween(last[leg].rotation) < 0.0001
		expect first[leg].rotation.turnBetween(a.frame(a.frames / 2)[leg].rotation) > 0.01

# The player's body: the worn models the plugin names, skinned to the character skeleton.
