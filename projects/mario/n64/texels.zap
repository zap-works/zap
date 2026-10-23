# The console's texel formats, decoded to an image of RGBA8 texels (rows from the top). A format is
# a kind (fmt: 0 RGBA, 2 CI, 3 IA, 4 I) and a size (siz: 0 4 bits, 1 8, 2 16, 3 32); color-indexed
# texels look up a palette of 16-bit RGBA5551 entries.

import image

pub fmtRgba = 0
pub fmtCi = 2
pub fmtIa = 3
pub fmtI = 4

# the texels a byte holds (4-bit: 2), or the bytes a texel takes, as a ratio bits / 8
pub fn bitsPerTexel(siz i64) i64:
	4 << siz

# w x h texels of the format from bytes at `at` of b (the palette's entries at `palette` of pal, when
# color-indexed), as an image
pub fn decodeTexels(
	b u8[],
	at i64,
	w i64,
	h i64,
	fmt i64,
	siz i64,
	pal u8[],
	palette i64
) image.Image:
	out = image.Image(w, h, fill = image.Rgba8(0, 0, 0, 0))
	bits = bitsPerTexel(siz)
	for i in 0..w * h:
		bitAt = i * bits
		byteAt = at + bitAt / 8
		if byteAt + (bits + 7) / 8 > b.len: break
		r = 0
		g = 0
		bl = 0
		a = 255
		if fmt == fmtRgba and siz == 2:
			c = i64(b.u16be(byteAt))
			r = (c >> 11) * 255 / 31
			g = c.bits(6, 5) * 255 / 31
			bl = c.bits(1, 5) * 255 / 31
			a = 255 if (c & 1) != 0 else 0
		elif fmt == fmtRgba and siz == 3:
			r = b[byteAt]
			g = b[byteAt + 1]
			bl = b[byteAt + 2]
			a = b[byteAt + 3]
		elif fmt == fmtIa and siz == 2:
			r = b[byteAt]
			g = r
			bl = r
			a = b[byteAt + 1]
		elif fmt == fmtIa and siz == 1:
			v = i64(b[byteAt])
			r = (v >> 4) * 0x11
			g = r
			bl = r
			a = (v & 15) * 0x11
		elif fmt == fmtIa and siz == 0:
			v = nibble(b, byteAt, bitAt)
			r = (v >> 1) * 0x24
			g = r
			bl = r
			a = 255 if (v & 1) != 0 else 0
		elif fmt == fmtI and siz == 1:
			r = b[byteAt]
			g = r
			bl = r
			a = r
		elif fmt == fmtI and siz == 0:
			r = nibble(b, byteAt, bitAt) * 0x11
			g = r
			bl = r
			a = r
		elif fmt == fmtCi:
			index = nibble(b, byteAt, bitAt) if siz == 0 else b[byteAt]
			e = palette + index * 2
			if e + 2 <= pal.len:
				c = i64(pal.u16be(e))
				r = (c >> 11) * 255 / 31
				g = c.bits(6, 5) * 255 / 31
				bl = c.bits(1, 5) * 255 / 31
				a = 255 if (c & 1) != 0 else 0
		out.cells[i] = image.Rgba8(u8(r), u8(g), u8(bl), u8(a))
	out

# the 4-bit texel at bit `bitAt` (the high nibble first)
fn nibble(b u8[], byteAt i64, bitAt i64):
	v = i64(b[byteAt])
	v >> 4 if (bitAt & 4) == 0 else v & 15
