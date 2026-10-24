# Names the file of the RomFS image at each hex offset (the storage reads the log shows), with
# its place and size. Run from the repository root:
#
#   zap run projects/recomp/switch/tools/romat.zap <romfs dir> <hex offset>...

import recomp.switch.package

given = args.positional()
root = given.first ?? fail("usage: romat.zap <romfs dir> <hex offset>...")
img = package.buildRomImage(root)
print("tables {img.head.len:x} bytes, {img.files.len} files, image {img.romImageSize():x} bytes")
for text in given[1..]:
	at = i64.parse("0x{text}") ?? fail("{text} is no hex offset")
	found = false
	for f in img.files:
		if f.at <= at and at < f.at + f.size:
			print("{text}: {f.path} at {f.at:x}, {f.size:x} bytes ({at - f.at:x} in)")
			found = true
	if not found: print("{text}: no file (tables or padding)")
