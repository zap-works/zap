# Describes a DDS texture and saves one of its levels as a PNG, to look at it and check the
# decoding. The texture is a file of a Skyrim install's archives, or a file of its own.
#
#   zap run projects/skyrim/dumpTex.zap [--install dir] [--level n] textures/clutter/barrel01.dds out.png
#   zap run projects/skyrim/dumpTex.zap [--level n] --file a.dds out.png

import fs
import image
import image.dds
import skyrim

# the texture of the file named, or else of the install's archives
fn textureOf(file str?, key str):
	if file != none:
		path = file ?? ""
		bytes = fs.readBytes(path) ?? fail("cannot read {path}")
		return dds.readDds(bytes) ?? fail("{path}: {error}")
	install = skyrim.openInstall(args.option("--install") ?? skyrim.defaultInstall) ?? fail
	install.installTexture(key) ?? fail

level = i64.parse(args.option("--level") ?? "0") ?? 0
file = args.option("--file")
args.options(
	[
		skyrim.installOption,
		ArgOption("--level", true, "the mip level"),
		ArgOption("--file", true, "a DDS file instead of an archive key")
	]
)
rest = args.positional()
if rest.len < (1 if file != none else 2):
	fail("usage: dumpTex.zap [--install dir] [--level n] <texture key> <out.png> | --file a.dds <out.png>")
out = rest[len - 1]
tex = textureOf(file, rest[0])
if level >= tex.levels:
	fail("the texture has {tex.levels} levels")
print(
	"{file ?? rest[0]}: {tex.format} {tex.width}x{tex.height}, {tex.levels} levels, srgb {tex.srgb}"
)
tex.decodeLevel(level).savePng(out) ?? fail("cannot write {out}")
