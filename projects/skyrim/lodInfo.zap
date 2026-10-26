# Prints the distant LOD files of a world: a block's models (BTR terrain, BTO objects) with their
# shaders, its tree list (BTT with the LST). Run from the repository root:
#
#   zap run projects/skyrim/lodInfo.zap --block 4,-12        the level 4 block with cell (4, -12) at its corner
#   zap run projects/skyrim/lodInfo.zap --block 4,-12 --level 8

import skyrim
import skyrim.nif

args.options([skyrim.installOption, ArgOption("--block", true, "the block's south west cell: x,y"),
	ArgOption("--level", true, "the block's size in cells (4)")])
install = skyrim.openInstall(args.option("--install") ?? skyrim.defaultInstall) ?? fail
level = i64.parse(args.option("--level") ?? "") ?? 4
cell = (args.option("--block") ?? "4,-12").split(",")
x = i64.parse(cell[0]) ?? 4
y = i64.parse(cell[1]) ?? -12
for key in [
	"meshes/terrain/tamriel/tamriel.{level}.{x}.{y}.btr",
	"meshes/terrain/tamriel/objects/tamriel.{level}.{x}.{y}.bto"
]:
	bytes = install.installRead(key) ?? continue
	n = nif.readNif(bytes) ?? fail("{key}: {error}")
	print("{key}: {bytes.len} bytes")
	for i, b in n.blocks:
		if b is LightingBlock(s):
			print("  shader {i}: type {s.shaderType} flags {s.flags1:X} {s.flags2:X} gloss {s.glossiness} spec {s.specularStrength} emissive {s.emissiveMultiple}")
	for p in n.drawParts():
		print("  part {p.name}: {p.positions.len} vertices, {p.normals.len} normals, {p.colors.len} colors, {p.indices.len / 3} triangles, uv {p.uvs.len}, diffuse {p.diffuse}, normal {p.normal}")
		if not p.positions.isEmpty:
			print("    first {p.positions[0]} uv {p.uvs[0] if not p.uvs.isEmpty else Vec2(0.0, 0.0)} normal {p.normals[0] if not p.normals.isEmpty else Vec3(0.0, 0.0, 0.0)}")
