# A texture's first level as RGBA8 pixels, from its TIC and the bytes at its address: unswizzled
# when block linear, decoded by its format (yuzu's TextureFormat codes, video_core/textures/
# texture.h) and its components' type, then swizzled as the TIC says. BC1-5 and BC7 decode with
# std's dds, ASTC with std's astc; floats are clamped to 0..1. Formats not written here give none.

import image
import image.astc
import image.dds

componentFloat = 7

# a format's block in texels (1 by 1 for plain formats) and its bytes
type Texel:
	width i64 = 1
	height i64 = 1
	bytes i64

# long: a table of the formats decoded
fn texelOf(format i64) Texel?:
	match format:
		0x01: Texel(bytes = 16)   # R32G32B32A32
		0x03: Texel(bytes = 8)   # R16G16B16A16
		0x04: Texel(bytes = 8)   # R32G32
		0x07, 0x08, 0x09, 0x0C, 0x0F, 0x21: Texel(bytes = 4)
		0x12, 0x13, 0x14, 0x15, 0x18, 0x1B: Texel(bytes = 2)
		0x1D: Texel(bytes = 1)   # R8
		0x24, 0x27: Texel(width = 4, height = 4, bytes = 8)   # BC1, BC4
		0x25, 0x26, 0x28, 0x17: Texel(width = 4, height = 4, bytes = 16)   # BC2, BC3, BC5, BC7
		0x40: Texel(width = 4, height = 4, bytes = 16)
		0x41: Texel(width = 5, height = 5, bytes = 16)
		0x42: Texel(width = 6, height = 6, bytes = 16)
		0x44: Texel(width = 8, height = 8, bytes = 16)
		0x45: Texel(width = 10, height = 10, bytes = 16)
		0x46: Texel(width = 12, height = 12, bytes = 16)
		0x50: Texel(width = 5, height = 4, bytes = 16)
		0x51: Texel(width = 6, height = 5, bytes = 16)
		0x52: Texel(width = 8, height = 6, bytes = 16)
		0x53: Texel(width = 10, height = 8, bytes = 16)
		0x54: Texel(width = 12, height = 10, bytes = 16)
		0x55: Texel(width = 8, height = 5, bytes = 16)
		0x56: Texel(width = 10, height = 5, bytes = 16)
		0x57: Texel(width = 10, height = 6, bytes = 16)
		_: none

fn isAstc(format i64):
	format >= 0x40 and format <= 0x57

# the first level's rows of blocks: their bytes each and how many
fn rowsOf(t Tic, e Texel):
	((t.width + e.width - 1) / e.width * e.bytes, (t.height + e.height - 1) / e.height)

# The bytes the first level takes at the texture's address; 0 for a format not decoded.
pub fn textureBytes(t Tic) i64:
	e = texelOf(t.format) ?? return 0
	rowBytes, rows = t.rowsOf(e)
	if not t.isBlockLinear(): return t.pitch * (rows - 1) + rowBytes
	Surface(rowBytes, rows, blockHeight = t.blockHeight).layoutBytes()

# the first level's rows of blocks packed one after another
fn packed(t Tic, e Texel, raw u8[]):
	rowBytes, rows = t.rowsOf(e)
	if t.isBlockLinear():
		return Surface(rowBytes, rows, blockHeight = t.blockHeight).unswizzle(raw, 0)
	out = []
	for y in 0..rows:
		at = y * t.pitch
		out.extend(raw[at..(at + rowBytes).min(len)])
	out

# The first level's blocks packed row after row as a GPU reads them, for a format of blocks (BC,
# ASTC); none for another.
pub fn textureBlocks(t Tic, raw u8[]) u8[]?:
	e = try texelOf(t.format)
	if e.width == 1: return none
	t.packed(e, raw)

# The texture's first level, or none for a format not decoded here.
pub fn decodeTexture(t Tic, raw u8[]) image.Image?:
	e = try texelOf(t.format)
	bytes = t.packed(e, raw)
	img = try t.decoded(e, bytes)
	t.swizzled(img)

fn decoded(t Tic, e Texel, move bytes u8[]) image.Image?:
	if isAstc(t.format):
		return astc.decodeBlocks(bytes, t.width, t.height, e.width, e.height, t.srgb)
	if e.width == 4: return t.blockImage(bytes)
	t.plainImage(e, bytes)

# BC1-5 and BC7 by std's dds
fn blockImage(t Tic, move bytes u8[]) image.Image?:
	format = match t.format:
		0x24: dds.Format.Bc1
		0x25: dds.Format.Bc2
		0x26: dds.Format.Bc3
		0x27: dds.Format.Bc4
		0x28: dds.Format.Bc5
		0x17: dds.Format.Bc7
		_: return none
	n = bytes.len
	d = dds.Dds(
		format,
		srgb = t.srgb,
		width = t.width,
		height = t.height,
		levels = 1,
		bytes,
		starts = [0, n]
	)
	d.decodeLevel(0)

fn unorm(v i64, bits i64) u8:
	u8(v * 255 / ((1 << bits) - 1))

fn floatByte(v f32) u8:
	u8((v.clamp(0.0, 1.0) * 255.0).round())

fn halfAt(b u8[], at i64):
	floatByte(halfValue(b.u16le(at)))

# a component of 16 bits, float or unorm as the TIC says
fn sixteen(t Tic, b u8[], at i64) u8:
	if t.componentTypes[0] == componentFloat: return halfAt(b, at)
	b.u16le(at) >> 8

# long: a dispatch over the plain formats
fn texel(t Tic, b u8[], at i64):
	match t.format:
		0x01:
			c = (0..4).map(floatByte(f32.fromBits(b.u32le(at + it * 4))))
			image.Rgba8(c[0], c[1], c[2], c[3])
		0x03: image.Rgba8(
			t.sixteen(b, at),
			t.sixteen(b, at + 2),
			t.sixteen(b, at + 4),
			t.sixteen(b, at + 6)
		)
		0x04:
			image.Rgba8(
				floatByte(f32.fromBits(b.u32le(at))),
				floatByte(f32.fromBits(b.u32le(at + 4))),
				0,
				255
			)
		0x07: image.Rgba8(b[at], b[at + 1], b[at + 2], 255)
		0x08: image.Rgba8(b[at], b[at + 1], b[at + 2], b[at + 3])
		0x09:
			v = i64(b.u32le(at))
			image.Rgba8(
				unorm(v & 0x3FF, 10),
				unorm((v >> 10) & 0x3FF, 10),
				unorm((v >> 20) & 0x3FF, 10),
				unorm(v >> 30, 2)
			)
		0x0C: image.Rgba8(t.sixteen(b, at), t.sixteen(b, at + 2), 0, 255)
		0x0F: image.Rgba8(floatByte(f32.fromBits(b.u32le(at))), 0, 0, 255)
		0x12:
			v = b.u16le(at)
			image.Rgba8(
				unorm(v & 15, 4),
				unorm((v >> 4) & 15, 4),
				unorm((v >> 8) & 15, 4),
				unorm(v >> 12, 4)
			)
		0x13:
			v = b.u16le(at)
			image.Rgba8(
				unorm(v & 31, 5),
				unorm((v >> 5) & 31, 5),
				unorm((v >> 10) & 31, 5),
				unorm(v >> 15, 1)
			)
		0x14:
			v = b.u16le(at)
			image.Rgba8(
				unorm((v >> 11) & 31, 5),
				unorm((v >> 6) & 31, 5),
				unorm((v >> 1) & 31, 5),
				unorm(v & 1, 1)
			)
		0x15:
			v = b.u16le(at)
			image.Rgba8(unorm(v & 31, 5), unorm((v >> 5) & 63, 6), unorm(v >> 11, 5), 255)
		0x18: image.Rgba8(b[at], b[at + 1], 0, 255)
		0x1B: image.Rgba8(t.sixteen(b, at), 0, 0, 255)
		0x1D: image.Rgba8(b[at], 0, 0, 255)
		0x21:
			v = i64(b.u32le(at))
			image.Rgba8(
				smallFloat(v & 0x7FF, 6),
				smallFloat((v >> 11) & 0x7FF, 6),
				smallFloat(v >> 22, 5),
				255
			)
		_: image.Rgba8(0, 0, 0, 255)

# an unsigned float of 5 exponent bits and `mantissa` bits (R11G11B10F's) as a byte
fn smallFloat(v i64, mantissa i64):
	halfAt([(v << (10 - mantissa)) & 0xFF, ((v << (10 - mantissa)) >> 8) & 0xFF], 0)

fn plainImage(t Tic, e Texel, bytes u8[]):
	img = image.Image(t.width, t.height, fill = image.Rgba8(0, 0, 0, 255))
	for y in 0..t.height:
		for x in 0..t.width:
			at = (y * t.width + x) * e.bytes
			if at + e.bytes <= bytes.len: img[x, y] = t.texel(bytes, at)
	img

# a component the TIC's swizzle names: 0 zero, 2 to 5 the texel's R to A, 6 and 7 one
fn source(p image.Rgba8, which i64):
	match which:
		2: p.r
		3: p.g
		4: p.b
		5: p.a
		6, 7: 255
		_: 0

fn swizzled(t Tic, move img image.Image):
	s = t.swizzle
	if s == [2, 3, 4, 5]: return img
	out = img.copy()
	for y in 0..img.height:
		for x in 0..img.width:
			p = img[x, y]
			out[x, y] = image.Rgba8(
				p.source(s[0]),
				p.source(s[1]),
				p.source(s[2]),
				p.source(s[3])
			)
	out
