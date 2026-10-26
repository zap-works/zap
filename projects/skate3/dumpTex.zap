# Saves textures of a district's streams as PNG files, to look at them and check the decoding
# (projects/skate3/assets/check/, which is not committed). Run from the repository root:
#
#   zap run projects/skate3/dumpTex.zap Tex 0 20             the first 20 textures of the Tex stream
#   zap run projects/skate3/dumpTex.zap Pres 100 10 --district DIST_MegaPark

import ea
import image
import rw4
import skate
import fs

_, district, big = skate.openToolDistrict()
args.options([skate.isoOption, skate.districtOption])
a = args.positional()
name = a[0] if not a.isEmpty else "Tex"
first = (i64.parse(a[1]) ?? 0) if a.len > 1 else 0
count = (i64.parse(a[2]) ?? 10) if a.len > 2 else 10
s = big.openStream(district, name) ?? fail
dir = "projects/skate3/assets/check"
_ = fs.createDir(dir)
mut done = 0
mut index = first
while done < count and index < s.assets.len:
	asset = s.assets[index]
	index += 1
	if asset.kind != skate.assetTexture: continue
	file = big.readBigEntry(big.entries.items[asset.entry]) ?? fail
	bytes = skate.assetBytes(file, asset) ?? fail
	arena = rw4.openArena(bytes) ?? fail
	for t in arena.arenaTextures():
		f = t.fetch
		label = "{name} {index - 1}: {t.name} {f.width}x{f.height} format 0x{f.format:02X} endian {f.endian} tiled {f.tiled} pitch {f.pitch} dim {f.dimension} packed {f.packedMips}"
		match t.image:
			img:
				path = "{dir}/{name}_{index - 1}_{ea.hex64(t.id)}.png"
				_ = img.savePng(path)
				print("{label} -> {path}")
			none: print("{label}: format not read")
	done += 1
