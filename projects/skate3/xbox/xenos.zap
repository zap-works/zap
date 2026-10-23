# Textures of the Xbox 360's GPU (Xenos), as a game hands them to it: a texture fetch constant of
# six words (its format, byte order, size, tiling, dimension, where its mips are) and the texels.
# Tiled textures are laid out in 32x32-element macro tiles with the elements of each shuffled
# (XGAddress2DTiledOffset; an element is a texel, or a 4x4 block of a compressed format), and each
# element's bytes are swapped by its endian mode (8 in 16, 8 in 32, 16 in 32). The formats
# decoded here are the ones Skate 3 uses: DXT1, DXT3, DXT5, DXN (two channels, normal maps), CTX1
# (two channels in a DXT1-like block), 8888, 565, 8 and 88. Texels come out as RGBA rows from the
# top, as engine.Image holds them.

import image

pub fmt8 = 0x02
pub fmt565 = 0x04
pub fmt8888 = 0x06
pub fmt88 = 0x0A
pub fmtDxt1 = 0x12
pub fmtDxt3 = 0x13
pub fmtDxt5 = 0x14
pub fmtDxn = 0x31
pub fmtDxt5a = 0x3B
pub fmtCtx1 = 0x3C

pub dimension2d = 1
pub dimensionCube = 3

# what a fetch constant says of a texture
pub type TextureFetch:
	format i64
	endian i64   # 0 none, 1 8-in-16, 2 8-in-32, 3 16-in-32
	tiled bool
	width i64
	height i64
	pitch i64   # texels a row holds in memory (a multiple of 32)
	dimension i64   # 1 2D, 3 cube
	packedMips bool

# The fetch constant of six big-endian words at `at`, read.
pub fn readFetch(d u8[], at i64) TextureFetch:
	w0 = i64(d.u32be(at))
	w1 = i64(d.u32be(at + 4))
	w2 = i64(d.u32be(at + 8))
	w5 = i64(d.u32be(at + 20))
	TextureFetch(
		format = w1 & 63,
		endian = w1.bits(6, 2),
		tiled = w0.bits(31, 1) == 1,
		width = (w2 & 0x1FFF) + 1,
		height = w2.bits(13, 13) + 1,
		pitch = w0.bits(22, 9) * 32, dimension = w5.bits(9, 2), packedMips = w5.bits(11, 1) ==
			1)

# the size of a format's element in bytes, and the texels an element spans across (4 for blocks)
pub fn elementBytes(format i64) i64:
	match format:
		0x02: 1
		0x04, 0x0A: 2
		0x06: 4
		0x12, 0x3B, 0x3C: 8
		_: 16

pub fn isBlock(format i64) bool:
	format in [fmtDxt1, fmtDxt3, fmtDxt5, fmtDxn, fmtDxt5a, fmtCtx1]

pub fn isKnownFormat(format i64) bool:
	isBlock(format) or format == fmt8 or format == fmt565 or format == fmt8888 or format == fmt88

# The element (x, y) of a tiled surface `widthElements` wide (aligned to 32), as an element index
# in memory, for elements of `bytes` bytes.
pub fn tiledIndex(x i64, y i64, widthElements i64, bytes i64) i64:
	aligned = widthElements.alignUp(32)
	logBpp = (bytes >> 2) + ((bytes >> 1) >> (bytes >> 2))
	macro = ((x >> 5) + (y >> 5) * (aligned >> 5)) << (logBpp + 7)
	micro = ((x & 7) + ((y & 6) << 2)) << logBpp
	offset = macro + ((micro & -16) << 1) + (micro & 15) + ((y & 8) << (3 + logBpp)) +
		((y & 1) << 4)
	(
		((offset & -512) << 3) + ((offset & 448) << 2) + (offset & 63) + ((y & 16) << 7) +
			(((((y & 8) >> 2) + (x >> 3)) & 3) << 6)
	) >> logBpp

# The bytes of a surface's elements in memory order put in rows (`width` x `height` elements of
# `bytes` bytes) with each element's byte order made little-endian; `pitch` elements a row in
# memory when not tiled. Elements past the data read as zeros.
fn linearElements(
	data u8[],
	from i64,
	width i64,
	height i64,
	pitch i64,
	bytes i64,
	tiled bool,
	endian i64
):
	zero u8 = 0
	out = fill(width * height * bytes, zero)
	for y in 0..height:
		for x in 0..width:
			index = tiledIndex(x, y, pitch, bytes) if tiled else y * pitch + x
			src = from + index * bytes
			dst = (y * width + x) * bytes
			if src + bytes > data.len: continue
			if endian == 1:
				k = 0
				while k < bytes:
					out[dst + k] = data[src + k + 1]
					out[dst + k + 1] = data[src + k]
					k += 2
			elif endian == 2:
				k = 0
				while k < bytes:
					out[dst + k] = data[src + k + 3]
					out[dst + k + 1] = data[src + k + 2]
					out[dst + k + 2] = data[src + k + 1]
					out[dst + k + 3] = data[src + k]
					k += 4
			elif endian == 3:
				k = 0
				while k < bytes:
					out[dst + k] = data[src + k + 2]
					out[dst + k + 1] = data[src + k + 3]
					out[dst + k + 2] = data[src + k]
					out[dst + k + 3] = data[src + k + 1]
					k += 4
			else:
				for k in 0..bytes:
					out[dst + k] = data[src + k]
	out

# The base level of the texture whose texels start at `from` in `data`, as an RGBA image; a cube
# gives its six faces one under the other. None when its format is not one read here.
pub fn decodeTexture(f TextureFetch, data u8[], from i64) image.Image?:
	if not isKnownFormat(f.format): return none
	block = isBlock(f.format)
	bytes = elementBytes(f.format)
	wide = (f.width + 3) / 4 if block else f.width
	high = (f.height + 3) / 4 if block else f.height
	pitch = ((f.pitch.max(f.width) + 3) / 4).alignUp(32) if block
		else f.pitch .max(f.width) .alignUp(32)
	faces = 6 if f.dimension == dimensionCube else 1
	# a face is a whole number of 4 KB pages of 32x32-element tiles
	faceBytes = (pitch * high.alignUp(32) * bytes).alignUp(4096)
	sheet = image.Image(f.width, f.height * faces, fill = image.Rgba8(0, 0, 0, 0))
	for face in 0..faces:
		elements = linearElements(
			data,
			from + face * faceBytes,
			wide,
			high,
			pitch,
			bytes,
			f.tiled,
			f.endian
		)
		surface = decodeBlocks(elements, f.format, f.width, f.height) if block
			else decodeTexels(elements, f.format, f.width, f.height)
		sheet.paste(surface, 0, face * f.height)
	sheet

# ---------- block formats ----------

# a 565 color as 8-bit r, g, b
fn expand565(c i64):
	(c.bits(11, 5) * 255 / 31, c.bits(5, 6) * 255 / 63, (c & 31) * 255 / 31)

# the 16 values of a BC4 block (DXT5's alpha) at `at`
fn bc4Values(e u8[], at i64, mut out i64[]):
	a0 = i64(e[at])
	a1 = i64(e[at + 1])
	table i64[8]
	table[0] = a0
	table[1] = a1
	if a0 > a1:
		for i in 1..7:
			table[i + 1] = ((7 - i) * a0 + i * a1) / 7
	else:
		for i in 1..5:
			table[i + 1] = ((5 - i) * a0 + i * a1) / 5
		table[6] = 0
		table[7] = 255
	bits = e.u32le(at + 2) | i64(e.u16le(at + 6)) << 32
	for p in 0..16:
		out[p] = table[(bits >> (3 * p)) & 7]

# the 16 colors of a BC1 block at `at` into rgba (64 bytes); `punch`: the 3-color mode makes
# index 3 transparent
fn bc1Colors(e u8[], at i64, punch bool, mut rgba u8[]):
	c0 = e.u16le(at)
	c1 = e.u16le(at + 2)
	r0, g0, b0 = expand565(c0)
	r1, g1, b1 = expand565(c1)
	pr i64[4]
	pg i64[4]
	pb i64[4]
	pa i64[4]
	pr[0] = r0
	pg[0] = g0
	pb[0] = b0
	pr[1] = r1
	pg[1] = g1
	pb[1] = b1
	pa[0] = 255
	pa[1] = 255
	pa[2] = 255
	pa[3] = 255
	if c0 > c1 or not punch:
		pr[2] = (2 * r0 + r1) / 3
		pg[2] = (2 * g0 + g1) / 3
		pb[2] = (2 * b0 + b1) / 3
		pr[3] = (r0 + 2 * r1) / 3
		pg[3] = (g0 + 2 * g1) / 3
		pb[3] = (b0 + 2 * b1) / 3
	else:
		pr[2] = (r0 + r1) / 2
		pg[2] = (g0 + g1) / 2
		pb[2] = (b0 + b1) / 2
		pr[3] = 0
		pg[3] = 0
		pb[3] = 0
		pa[3] = 0
	indices = i64(e.u32le(at + 4))
	for p in 0..16:
		k = (indices >> (2 * p)) & 3
		rgba[p * 4] = u8(pr[k])
		rgba[p * 4 + 1] = u8(pg[k])
		rgba[p * 4 + 2] = u8(pb[k])
		rgba[p * 4 + 3] = u8(pa[k])

# the texels of a surface of blocks in rows (`elements`, each block's bytes little-endian), as RGBA
fn decodeBlocks(elements u8[], format i64, width i64, height i64):
	out = image.Image(width, height, fill = image.Rgba8(0, 0, 0, 0))
	bytes = elementBytes(format)
	wide = (width + 3) / 4
	high = (height + 3) / 4
	zeroByte u8 = 0
	rgba = fill(64, zeroByte)
	alpha = zeros(16)
	second = zeros(16)
	for by in 0..high:
		for bx in 0..wide:
			at = (by * wide + bx) * bytes
			if format == fmtDxt1:
				bc1Colors(elements, at, true, rgba)
			elif format == fmtDxt3:
				bc1Colors(elements, at + 8, false, rgba)
				for p in 0..16:
					nibble = (i64(elements[at + p / 2]) >> (4 * (p & 1))) & 15
					rgba[p * 4 + 3] = nibble * 17
			elif format == fmtDxt5:
				bc1Colors(elements, at + 8, false, rgba)
				bc4Values(elements, at, alpha)
				for p in 0..16:
					rgba[p * 4 + 3] = u8(alpha[p])
			elif format == fmtDxn:
				bc4Values(elements, at, alpha)
				bc4Values(elements, at + 8, second)
				for p in 0..16:
					rgba[p * 4] = u8(alpha[p])
					rgba[p * 4 + 1] = u8(second[p])
					rgba[p * 4 + 2] = 255
					rgba[p * 4 + 3] = 255
			elif format == fmtDxt5a:
				bc4Values(elements, at, alpha)
				for p in 0..16:
					v = u8(alpha[p])
					rgba[p * 4] = v
					rgba[p * 4 + 1] = v
					rgba[p * 4 + 2] = v
					rgba[p * 4 + 3] = v
			else:
				ctx1Colors(elements, at, rgba)
			for py in 0..4:
				y = by * 4 + py
				if y >= height: break
				for px in 0..4:
					x = bx * 4 + px
					if x < width:
						p = (py * 4 + px) * 4
						out[x, y] = image.Rgba8(rgba[p], rgba[p + 1], rgba[p + 2], rgba[p + 3])
	out

# CTX1: two endpoints of 8-bit x and y, then 2-bit indices as BC1 (no 3-color mode); z is made
# from x and y as a normal's
fn ctx1Colors(e u8[], at i64, mut rgba u8[]):
	x0 = i64(e[at])
	y0 = i64(e[at + 1])
	x1 = i64(e[at + 2])
	y1 = i64(e[at + 3])
	indices = i64(e.u32le(at + 4))
	for p in 0..16:
		k = (indices >> (2 * p)) & 3
		x = x0
		y = y0
		if k == 1:
			x = x1
			y = y1
		elif k == 2:
			x = (2 * x0 + x1) / 3
			y = (2 * y0 + y1) / 3
		elif k == 3:
			x = (x0 + 2 * x1) / 3
			y = (y0 + 2 * y1) / 3
		fx = x / 127.5 - 1.0
		fy = y / 127.5 - 1.0
		z = (1.0 - fx * fx - fy * fy).max(0.0).sqrt()
		rgba[p * 4] = u8(x)
		rgba[p * 4 + 1] = u8(y)
		rgba[p * 4 + 2] = u8(i64((z * 0.5 + 0.5) * 255.0))
		rgba[p * 4 + 3] = 255

# ---------- texel formats ----------

# width x height texels in rows (each element little-endian), as an image
fn decodeTexels(elements u8[], format i64, width i64, height i64):
	out = image.Image(width, height, fill = image.Rgba8(0, 0, 0, 0))
	for i in 0..width * height:
		if format == fmt8888:
			# a little-endian ARGB word: B, G, R, A in memory
			out.cells[i] = image.Rgba8(
				elements[i * 4 + 2],
				elements[i * 4 + 1],
				elements[i * 4],
				elements[i * 4 + 3]
			)
		elif format == fmt565:
			r, g, b = expand565(elements.u16le(i * 2))
			out.cells[i] = image.Rgba8(u8(r), u8(g), u8(b), 255)
		elif format == fmt88:
			out.cells[i] = image.Rgba8(elements[i * 2 + 1], elements[i * 2], 255, 255)
		else:
			v = elements[i]
			out.cells[i] = image.Rgba8(v, v, v, v)
	out
