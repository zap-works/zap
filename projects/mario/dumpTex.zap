# Saves a texture of segment 2 as PNG to look at it: offset, width, height, format, size.
#   zap run projects/mario/dumpTex.zap 0x11C58 32 32 0 2 build/marioscan/water.png

import image
import n64

_, lv = n64.readCastleGrounds()
a = args
at = i64.parse(a[0]) ?? 0
w = i64.parse(a[1]) ?? 32
h = i64.parse(a[2]) ?? 32
fmt = i64.parse(a[3]) ?? 0
siz = i64.parse(a[4]) ?? 2
texels = n64.decodeTexels(lv.segments.banks[2], at, w, h, fmt, siz, [], 0)
_ = texels.savePng(a[5])
