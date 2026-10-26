# Reads a Skyrim model (NIF) and prints its blocks and the parts a renderer draws. Run from the
# repository root:
#
#   zap run projects/skyrim/nifInfo.zap meshes/clutter/barrel01.nif      a model of the archives
#   zap run projects/skyrim/nifInfo.zap out.nif --obj out.obj             a file, written as OBJ
#   zap run projects/skyrim/nifInfo.zap barrel01.nif --collision          its colliders too
#   zap run projects/skyrim/nifInfo.zap x.nif --collision-obj out.obj      the collision beside it
#   zap run projects/skyrim/nifInfo.zap x.nif --shaders     every shader block's fields and flags
#   zap run projects/skyrim/nifInfo.zap --all-inn                         every model of the inn,
#                                                                         collision against parts

import fs
import math
import skyrim
import skyrim.esm
import skyrim.nif

inn = "RiverwoodSleepingGiantInn"

fn showVec(v Vec3):
	"({v.x:.1} {v.y:.1} {v.z:.1})"

fn showAlpha(a nif.Alpha):
	if a.blend: return "blend {a.source}/{a.destination}"
	if a.test: return "test {a.testFunction} > {a.threshold}"
	"opaque"

fn showBounds(points Vec3[]):
	lo, hi = points.boundsOf()
	"bounds {lo.showVec()} .. {hi.showVec()}, size {(hi - lo).showVec()}"

fn printEffect(e nif.Effect):
	print("  effect palette {e.palette} ({e.paletteColor} {e.paletteAlpha}) color {e.baseColor} scale {e.scale:.2} falloff {e.falloff} vertex alpha {e.vertexAlpha} uv {e.uvOffset} {e.uvScale}")
	for t in e.tracks:
		print("    track {t.variable} {t.timing} value {t.value} keys {t.keys}")

fn printParticles(systems nif.Particles[]):
	for p in systems:
		print("particles {p.name}: {p.diffuse}, {p.alpha.showAlpha()}, at most {p.maxCount}, cells {p.subtextures}")
		if p.effect is e: e.printEffect()
		for m in p.modifiers:
			print("  {m.modifier.name} {m.modifier.active}: {m.modifier.kind}")
			print("    object at {m.object.applyPoint(Vec3(0.0, 0.0, 0.0)).showVec()}, {m.points.len} points, rate {m.rate}, running {m.running}")

fn printModel(n nif.Nif, parts nif.Part[]):
	h = n.header
	print("version 0x{h.version:08X} user {h.userVersion} bs {h.bsVersion}: {n.blocks.len} blocks, {n.strings.len} strings")
	for i in 0..n.blocks.len:
		print("{i:>3} {n.blockKind(i)} {n.blockName(i)}")
	for p in parts:
		print("part {p.name}: {p.positions.len} vertices, {p.colors.len} colors, {p.indices.len / 3} triangles, {p.alpha.showAlpha()}{" two-sided" if p.twoSided else ""}{" skinned" if p.skinned else ""}, gloss {p.glossiness:.0} specular {p.specularStrength:.2}")
		print("  diffuse {p.diffuse} normal {p.normal}")
		if p.shading.external or (p.effect?.external ?? false): print("  external emittance")
		if p.billboard is b:
			toNode = b.pivot.inverseAffine()
			print("  billboard mode {b.mode}: {showBounds(p.positions.map(toNode.applyPoint(it)))}")
		if p.effect is e: e.printEffect()
	print(showBounds(nif.partPositions(parts)))

fn printFlags(flags1 i64, flags2 i64):
	print("  SLSF1 0x{flags1:08X}: {nif.flagNames(flags1, nif.flags1Names).join(" ")}")
	print("  SLSF2 0x{flags2:08X}: {nif.flagNames(flags2, nif.flags2Names).join(" ")}")

# each shader property, texture set and alpha block: every field, the flags by name and raw
fn printShaders(n nif.Nif):
	for i in 0..n.blocks.len:
		match n.blocks[i]:
			LightingBlock(shader):
				print("{i:>3} BSLightingShaderProperty {shader}")
				printFlags(shader.flags1, shader.flags2)
			EffectBlock(shader):
				print("{i:>3} BSEffectShaderProperty {shader}")
				printFlags(shader.flags1, shader.flags2)
			TextureSetBlock(paths): print("{i:>3} BSShaderTextureSet {paths}")
			AlphaBlock(alpha): print("{i:>3} NiAlphaProperty {alpha}")
			_: continue

fn printColliders(colliders nif.Collider[]):
	for c in colliders:
		layer = nif.layerNames[c.layer] if c.layer < nif.layerNames.len else "layer {c.layer}"
		print("collider {c.node}: {layer}, {c.motion}, mass {c.mass:.1}, friction {c.friction:.2}, restitution {c.restitution:.2}, {c.kinds.join(" ")}, {c.indices.len / 3} triangles")
		print("  {showBounds(c.positions)}")

# each model's collision box against its drawn parts', and the farthest
fn compareCollision(keys str[], models nif.Nif[]):
	worst = nif.BoundsFit(ratio = 1.0, offset = 0.0, overflow = 0.0)
	worstOffset = ""
	worstOverflow = ""
	for i in 0..keys.len:
		colliders = models[i].collisionShapes()
		if colliders.isEmpty: continue
		parts = models[i].drawParts()
		fit = nif.collisionFit(colliders, parts)
		print("{keys[i]}: {colliders.len} colliders ({colliders.flatMap(.kinds.copy()).join(" ")}), size ratio {fit.ratio:.2}, offset {fit.offset * 100.0:.1}%, past the drawn box {fit.overflow * 100.0:.1}%")
		print("  drawn {showBounds(nif.partPositions(parts))}")
		print("  solid {showBounds(nif.colliderPositions(colliders))}")
		if fit.offset > worst.offset:
			worst.offset = fit.offset
			worstOffset = keys[i].copy()
		if fit.overflow > worst.overflow:
			worst.overflow = fit.overflow
			worstOverflow = keys[i].copy()
	print("farthest centers {worst.offset * 100.0:.1}%: {worstOffset}")
	print("farthest past the drawn box {worst.overflow * 100.0:.1}%: {worstOverflow}")

fn allInn(install skyrim.Install):
	plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
	cell = plugin.findCell(inn) ?? fail("no {inn} in {install.data}")
	keys = plugin.cellModels(cell)
	kinds {str: i64} = {}
	parts = 0
	triangles = 0
	failed = 0
	read = []
	models = []
	for key in keys:
		match install.readModel(key):
			n:
				read.push(key.copy())
				models.push(n)
				for i in 0..n.blocks.len:
					kinds.add(n.blockKind(i), 1)
				for p in n.drawParts():
					parts += 1
					triangles += p.indices.len / 3
			error:
				failed += 1
				print("FAIL {error}")
	for k in kinds.keys().sorted():
		print("{k}: {kinds.get(k) ?? 0}")
	compareCollision(read, models)
	print("{keys.len} models, {failed} failed, {parts} parts, {triangles} triangles")

install = skyrim.openInstall(args.option("--install") ?? skyrim.defaultInstall) ?? fail
if "--all-inn" in args:
	install.allInn()
	return
args.options(
	[
		skyrim.installOption,
		ArgOption("--obj", true, "the .obj file to write"),
		ArgOption("--collision-obj", true, "the collision's .obj file to write")
	]
)
rest = args.positional()
if rest.isEmpty: fail("give a model's archive key or a .nif file")
given = rest[0]
modelBytes = fs.readBytes(given) ??
	(install.installRead(given) ?? fail("{given} is no file and in no archive"))
model = nif.readNif(modelBytes) ?? fail("{given}: {error}")
if "--shaders" in args:
	model.printShaders()
	return
modelParts = model.drawParts()
model.printModel(modelParts)
printParticles(model.drawModel().systems)
colliders = model.collisionShapes()
if "--collision" in args: printColliders(colliders)
for option in ["--obj", "--collision-obj"]:
	path = args.option(option) ?? continue
	solid = colliders if option == "--collision-obj" else []
	fs.writeFile(path, nif.objText(modelParts, solid)) ?? fail("cannot write {path}")
	print("wrote {path}")
