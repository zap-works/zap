# DDS files (DirectDraw Surface), read: the magic "DDS ", a 124-byte header (height, width, pitch,
# mip count, the pixel format with its flags and fourCC) and, for fourCC "DX10", a 20-byte header
# with the DXGI format; then the levels, largest first, each as the block math sizes it. Read are
# BC1 to BC5 and BC7 (the GPU's block formats) and 8-bit RGBA and BGRA; decodeLevel (blocks.zap)
# turns a level into an image. Cube maps and arrays keep their first surface's levels, and `face`
# reads a cube map's others.

import image

parts blocks, bc7, bc7Tables

pub type Format:
	Bc1
	Bc2
	Bc3
	Bc4
	Bc5
	Bc7
	Rgba8
	Bgra8

# A texture: its format, whether the color is sRGB, the size of level 0, the number of levels and
# the bytes of all of them; levelBytes(d, i) is level i's window.
pub type Dds:
	format Format
	srgb bool
	width i64
	height i64
	levels i64
	bytes u8[]
	starts i64[]

headerSize = 128
dx10Size = 20
fourCcAt = 84
flagFourCc = 4
flagRgb = 64
maskRedRgba = 0xFF
maskRedBgra = 0xFF_0000

# what the pixel format says: the format, its color space and where the levels start
type Layout:
	format Format
	srgb bool
	dataAt i64

# The texture a DDS file holds, or why it cannot be read.
pub fn readDds(bytes u8[]) Dds ? str:
	if bytes.len < headerSize: return "too short for a DDS header"
	if str(bytes[..4]) != "DDS ": return "no DDS magic"
	if bytes.u32le(4) != 124: return "the DDS header is not 124 bytes"
	height = i64(bytes.u32le(12))
	width = i64(bytes.u32le(16))
	if width < 1 or height < 1 or width > 65_536 or height > 65_536: return "a {width}x{height} DDS"
	levels = i64(bytes.u32le(28)).clamp(1, 32)
	layout = try layoutOf(bytes)
	data = bytes[layout.dataAt..].copy()
	starts = [0]
	for level in 0..levels:
		size = layout.format.levelSize(levelDim(width, level), levelDim(height, level))
		if starts[level] + size > data.len:
			if level == 0: return "the DDS data is short"
			return Dds(layout.format, layout.srgb, width, height, level, data, starts)
		starts.push(starts[level] + size)
	Dds(layout.format, layout.srgb, width, height, levels, data, starts)

# the pixel format of the header at its place in the file
fn layoutOf(bytes u8[]) Layout ? str:
	flags = i64(bytes.u32le(80))
	cc = str(bytes[fourCcAt..fourCcAt + 4])
	if flags & flagFourCc != 0:
		if cc == "DX10":
			if bytes.len < headerSize + dx10Size: return "the DX10 header is cut short"
			code = i64(bytes.u32le(headerSize))
			match dxgiFormat(code):
				format: return Layout(format, dxgiSrgb(code), headerSize + dx10Size)
				none: return "the DXGI format {code} is not read"
		match fourCcFormat(cc):
			format: return Layout(format, false, headerSize)
			none: return "the fourCC {cc} is not read"
	if flags & flagRgb != 0 and bytes.u32le(88) == 32:
		red = i64(bytes.u32le(92))
		if red == maskRedRgba: return Layout(.Rgba8, false, headerSize)
		if red == maskRedBgra: return Layout(.Bgra8, false, headerSize)
	"a DDS pixel format that is not read"

fn fourCcFormat(cc str) Format?:
	match cc:
		"DXT1": .Bc1
		"DXT3": .Bc2
		"DXT5": .Bc3
		"ATI1", "BC4U": .Bc4
		"ATI2", "BC5U": .Bc5
		_: none

# DXGI_FORMAT numbers: the unorm one and its sRGB twin of each format
fn dxgiFormat(code i64) Format?:
	match code:
		71, 72: .Bc1
		74, 75: .Bc2
		77, 78: .Bc3
		80: .Bc4
		83: .Bc5
		98, 99: .Bc7
		28, 29: .Rgba8
		87, 91: .Bgra8
		_: none

fn dxgiSrgb(code i64):
	code in [72, 75, 78, 99, 29, 91]

# the size of a level: the base's halved level times, at least 1
pub fn levelDim(base i64, level i64) i64:
	(base >> level).max(1)

pub fn isBlock(f Format) bool:
	match f:
		Rgba8, Bgra8: false
		_: true

# the bytes of one 4x4 block
pub fn blockBytes(f Format) i64:
	match f:
		Bc1, Bc4: 8
		_: 16

# the bytes of a level of width by height texels
pub fn levelSize(f Format, width i64, height i64) i64:
	if not f.isBlock(): return width * height * 4
	(width + 3) / 4 * ((height + 3) / 4) * f.blockBytes()

# The face k of a cube map (+x, -x, +y, -y, +z, -z) as a texture of its own: a cube map holds its
# faces one after the other, each with all its levels. None past the file's.
pub fn face(d Dds, k i64) Dds?:
	size = d.starts[d.levels]
	if (k + 1) * size > d.bytes.len: return none
	Dds(
		d.format,
		d.srgb,
		d.width,
		d.height,
		d.levels,
		d.bytes[k * size..(k + 1) * size].copy(),
		d.starts.copy()
	)

# the bytes of a level, a window into the texture
pub fn levelBytes(d Dds, level i64) ref u8[]:
	d.bytes[d.starts[level]..d.starts[level + 1]]

# ---------- tests ----------

# 16 bytes holding the (value, width) fields from bit 0 up, the way BC7 lays a block out
fn pack(fields (i64, i64)[]):
	out u8[] = zeros(16)
	at = 0
	for (value, width) in fields:
		for b in 0..width:
			if (value >> b) & 1 == 1: out[at >> 3] |= u8.wrap(1 << (at & 7))
			at += 1
	out

fn bytesOf(xs i64[]):
	xs.map(u8.wrap(it))

# a texture of one level of the block bytes given
fn textureOf(format Format, width i64, height i64, bytes u8[]):
	Dds(format, false, width, height, 1, bytes.copy(), [0, bytes.len])

fn pixelsOf(img image.Image):
	img.cells.map("{.r},{.g},{.b},{.a}")

# whether every text of the list is `want`
fn only(texts str[], want str):
	for t in texts:
		if t != want: return false
	true

# why a file is refused
fn refusal(bytes u8[]):
	match readDds(bytes):
		error: error
		d: "read as {d.format}"

# an uncompressed header and the data after it
fn file(fourCc str, width i64, height i64, mips i64, data u8[]):
	out u8[] = zeros(128)
	out.setU32le(0, 0x2053_4444)
	out.setU32le(4, 124)
	out.setU32le(12, u32(height))
	out.setU32le(16, u32(width))
	out.setU32le(28, u32(mips))
	out.setU32le(80, 4)
	for i in 0..4:
		out[84 + i] = fourCc.bytes()[i]
	out.extend(data)
	out

test "BC1: a solid red block, the 3-color transparent index, the 4-color mixes":
	solid = textureOf(.Bc1, 4, 4, bytesOf([0, 0xF8, 0, 0, 0, 0, 0, 0]))
	expect only(solid.decodeLevel(0).pixelsOf(), "255,0,0,255")
	mixed = textureOf(.Bc1, 4, 4, bytesOf([0, 0xF8, 0x1F, 0, 0xE4, 0, 0, 0]))
	img = mixed.decodeLevel(0)
	expect img.pixelsOf()[..4] == ["255,0,0,255", "0,0,255,255", "170,0,85,255", "85,0,170,255"]
	clear = textureOf(.Bc1, 4, 4, bytesOf([0x1F, 0, 0, 0xF8, 0xE4, 0, 0, 0]))
	expect clear.decodeLevel(0).pixelsOf()[..4] ==
		["0,0,255,255", "255,0,0,255", "127,0,127,255", "0,0,0,0"]

test "BC1: a texture of 2x2 texels keeps the block's corner":
	solid = textureOf(.Bc1, 2, 2, bytesOf([0xE0, 0x07, 0, 0, 0, 0, 0, 0]))
	img = solid.decodeLevel(0)
	expect img.width == 2 and img.height == 2
	expect only(img.pixelsOf(), "0,255,0,255")

test "BC2: explicit 4-bit alphas":
	block = bytesOf([0x10, 0xF0, 0, 0, 0, 0, 0, 0, 0, 0xF8, 0, 0xF8, 0, 0, 0, 0])
	px = textureOf(.Bc2, 4, 4, block).decodeLevel(0).pixelsOf()
	expect px[..4] == ["255,0,0,0", "255,0,0,17", "255,0,0,0", "255,0,0,255"]

test "BC3: a color block with a gradient alpha":
	block = bytesOf([200, 100, 0x88, 0xC6, 0xFA, 0, 0, 0, 0, 0xF8, 0, 0xF8, 0, 0, 0, 0])
	px = textureOf(.Bc3, 4, 4, block).decodeLevel(0).pixelsOf()
	expect px[..4] == ["255,0,0,200", "255,0,0,100", "255,0,0,185", "255,0,0,171"]

test "BC4: eight values, or six with 0 and 255; a single channel in gray":
	eight = bytesOf([255, 0, 0xD0, 0x08, 0, 0, 0, 0])
	px = textureOf(.Bc4, 4, 4, eight).decodeLevel(0).pixelsOf()
	expect px[..4] == ["255,255,255,255", "218,218,218,255", "182,182,182,255", "145,145,145,255"]
	six = bytesOf([10, 250, 190, 0, 0, 0, 0, 0])
	px6 = textureOf(.Bc4, 4, 4, six).decodeLevel(0).pixelsOf()
	expect px6[..3] == ["0,0,0,255", "255,255,255,255", "58,58,58,255"]

test "BC5: two channels in red and green, 255 in blue and alpha":
	block = bytesOf([128, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0])
	px = textureOf(.Bc5, 4, 4, block).decodeLevel(0).pixelsOf()
	expect only(px, "128,64,255,255")

test "BC7 mode 6: one color in every texel":
	block = pack(
		[
			(64, 7),
			(100, 7),
			(100, 7),
			(50, 7),
			(50, 7),
			(25, 7),
			(25, 7),
			(127, 7),
			(127, 7),
			(1, 1),
			(1, 1)
		]
	)
	px = textureOf(.Bc7, 4, 4, block).decodeLevel(0).pixelsOf()
	expect only(px, "201,101,51,255")

test "BC7 mode 0: three subsets by the partition's shape":
	fields = [(1, 1), (1, 4)]
	for channel in 0..3:
		for subset in 0..3:
			loop 2:
				fields.push((15 if channel == subset else 0, 4))
	loop 6:
		fields.push((1, 1))
	px = textureOf(.Bc7, 4, 4, pack(fields)).decodeLevel(0).pixelsOf()
	shape = partitions3[1]
	colors = ["255,8,8,255", "8,255,8,255", "8,8,255,255"]
	for i in 0..16:
		expect px[i] == colors[i64(shape[i]) - 48]

test "BC7: mode 8 and a block of zeros are transparent black":
	px = textureOf(.Bc7, 4, 4, zeros(16)).decodeLevel(0).pixelsOf()
	expect only(px, "0,0,0,0")

test "a DDS file: header, fourCC, mip chain of block sizes":
	data u8[] = zeros(64)
	d = readDds(file("DXT5", 8, 4, 3, data)) ?? fail
	expect d.format == .Bc3
	expect d.width == 8 and d.height == 4 and d.levels == 3
	expect d.levelBytes(0).len == 32
	expect d.levelBytes(1).len == 16
	expect d.levelBytes(2).len == 16

test "a damaged DDS is refused":
	expect refusal(zeros(10)) == "too short for a DDS header"
	expect refusal(file("DXT5", 8, 4, 1, zeros(4))) == "the DDS data is short"
	expect refusal(file("NOPE", 8, 4, 1, zeros(64))) == "the fourCC NOPE is not read"
