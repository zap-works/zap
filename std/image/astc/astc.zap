# ASTC textures (Adaptive Scalable Texture Compression), LDR, decoded to RGBA8 and encoded from it.
# A block is 16 bytes covering a 2D footprint of 4x4 to 12x12 texels; `decode` turns the blocks of
# a texture into an image, `encodeAstc` an image into blocks (encode.zap), and `readAstc` and
# `writeAstc` read and write the .astc file the reference encoder writes (a 16-byte header, then
# the blocks). Left out: 3D footprints, and the HDR endpoint modes and void extents, which an LDR
# decode gives the error color (magenta). Colors come out as stored; `srgb` only picks how the
# endpoints widen (Khronos Data Format Specification, chapter "ASTC").

import image
import fs

parts ise, header, endpoints, partition, block, encode, fit

footprintMin = 4
footprintMax = 12
headerBytes = 16
blockBytes = 16

# A texture: its footprint, its size in texels and its blocks, row after row.
pub type Astc:
	blockX i64
	blockY i64
	width i64
	height i64
	blocks u8[]

# The texture of an .astc file, or why it cannot be read.
pub fn readAstc(bytes u8[]) Astc ? str:
	if bytes.len < headerBytes: return "too short for an ASTC header"
	if bytes.u32le(0) != 0x5CA1_AB13: return "no ASTC magic"
	if bytes[6] != 1 or size3(bytes, 13) != 1: return "a 3D ASTC is not read"
	bx = i64(bytes[4])
	by = i64(bytes[5])
	if bx < footprintMin or by < footprintMin or bx > footprintMax or by > footprintMax:
		return "a {bx}x{by} ASTC footprint is not read"
	width = size3(bytes, 7)
	height = size3(bytes, 10)
	needed = blocksFor(width, bx) * blocksFor(height, by) * blockBytes
	if width < 1 or height < 1 or bytes.len < headerBytes + needed: return "the ASTC data is short"
	Astc(bx, by, width, height, bytes[headerBytes..headerBytes + needed].copy())

fn size3(bytes u8[], at i64):
	i64(bytes[at]) | (i64(bytes[at + 1]) << 8) | (i64(bytes[at + 2]) << 16)

fn blocksFor(texels i64, footprint i64):
	(texels + footprint - 1) / footprint

# The texture as an image; `srgb` for an sRGB-encoded one.
pub fn decode(a Astc, srgb bool) image.Image:
	decodeBlocks(a.blocks, a.width, a.height, a.blockX, a.blockY, srgb)

# The width by height texels of blocks (16 bytes each, row after row) of bx by by texels.
pub fn decodeBlocks(blocks u8[], width i64, height i64, bx i64, by i64, srgb bool) image.Image:
	img = image.Image(width, height, fill = image.Rgba8(0, 0, 0, 255))
	across = blocksFor(width, bx)
	px image.Rgba8[144]
	for row in 0..blocksFor(height, by):
		for col in 0..across:
			decodeBlock(blocks, (row * across + col) * blockBytes, bx, by, srgb, px)
			for y in 0..by.min(height - row * by):
				for x in 0..bx.min(width - col * bx):
					img[col * bx + x, row * by + y] = px[y * bx + x]
	img

# the oracle decodes the files were checked against, as a sum and a running hash of the RGBA bytes
fn digest(img image.Image):
	sum = 0
	h = 0
	for b in img.cells.bytes():
		sum += b
		h = (h * 31 + i64(b)) % 1_000_000_007
	"{img.width}x{img.height} {sum} {h}"

fn load(name str):
	readAstc(fs.readBytes("std/image/astc/tests/{name}.astc") ?? []) ?? fail

# The files in tests/ are 14 footprints of random blocks (some a void extent, most an error or a
# partitioned, dual-plane or quint/trit block) and four images encoded by ARM's astcenc; the
# digests are of astcenc's own decode (-dl linear, -ds sRGB), so every texel matches it.
test "astc blocks decode to the reference encoder's texels":
	want = {
		"grad10x6.cl": "80x64 2747562 884079761",
		"grad10x6.cs": "80x64 2747921 682842207",
		"gray12x12.cl": "53x47 1449255 438138459",
		"gray12x12.cs": "53x47 1449471 759761865",
		"r10x10.cl": "59x38 1712340 913812598",
		"r10x10.cs": "59x38 1712340 913812598",
		"r10x5.cl": "59x18 792462 705084349",
		"r10x5.cs": "59x18 792472 413383987",
		"r10x6.cl": "59x22 926571 997749283",
		"r10x6.cs": "59x22 926652 315680181",
		"r10x8.cl": "59x30 1308921 296632273",
		"r10x8.cs": "59x30 1308931 480956423",
		"r12x10.cl": "71x38 1994875 369189100",
		"r12x10.cs": "71x38 1994808 58600466",
		"r12x12.cl": "71x46 2244779 632864231",
		"r12x12.cs": "71x46 2244970 532678434",
		"r4x4.cl": "23x14 241422 858764515",
		"r4x4.cs": "23x14 241422 858764515",
		"r5x4.cl": "29x14 293568 15798896",
		"r5x4.cs": "29x14 293588 138561839",
		"r5x5.cl": "29x18 381644 887771424",
		"r5x5.cs": "29x18 381667 702809894",
		"r6x5.cl": "35x18 476565 558226062",
		"r6x5.cs": "35x18 476575 374744545",
		"r6x6.cl": "35x22 563296 522884816",
		"r6x6.cs": "35x22 563318 823148461",
		"r8x5.cl": "47x18 615450 666488666",
		"r8x5.cs": "47x18 615501 807846983",
		"r8x6.cl": "47x22 766471 927547993",
		"r8x6.cs": "47x22 766477 912649736",
		"r8x8.cl": "47x30 987684 691778485",
		"r8x8.cs": "47x30 987775 606024115",
		"shape8x8.cl": "70x50 2113833 793868059",
		"shape8x8.cs": "70x50 2113846 901583250",
		"smooth4x4.cl": "61x45 1729524 636339871",
		"smooth4x4.cs": "61x45 1729765 17881413"
	}
	for key, digest in want:
		stem = key[..key.len - 3]
		got = load(stem).decode(key.endsWith(".cs"))
		expect got.digest() == digest

# why a file is refused
fn refusal(bytes u8[]):
	match readAstc(bytes):
		error: error
		a: "read {a.width}x{a.height}"

test "a damaged ASTC is refused":
	bytes = fs.readBytes("std/image/astc/tests/r4x4.astc") ?? []
	expect refusal(bytes[..3]) == "too short for an ASTC header"
	expect refusal(bytes[..40]) == "the ASTC data is short"
	bad = bytes
	bad[0] = 0
	expect refusal(bad) == "no ASTC magic"


# The test images encoded at 4x4 and 6x6, as linear and as sRGB textures: each decoded back to the
# digest kept (ARM's astcenc decodes these encodes to the same texels: astcenc -dl, -ds) and within
# the PSNR kept of its source.
test "astc encodes and decodes back near the source":
	want = {
		"smooth4x4.4x4": ("61x45 1728742 94990347", 38.0),
		"smooth4x4.4x4.s": ("61x45 1729030 133335580", 38.0),
		"smooth4x4.6x6": ("61x45 1729334 104202349", 33.6),
		"smooth4x4.6x6.s": ("61x45 1729662 93841780", 33.6),
		"shape8x8.4x4": ("70x50 2113095 240616742", 35.8),
		"shape8x8.4x4.s": ("70x50 2113077 647846774", 35.8),
		"shape8x8.6x6": ("70x50 2113698 690658443", 34.6),
		"shape8x8.6x6.s": ("70x50 2113810 551005671", 34.6),
		"grad10x6.4x4": ("80x64 2746551 377569023", 41.5),
		"grad10x6.4x4.s": ("80x64 2746593 387849033", 41.5),
		"grad10x6.6x6": ("80x64 2747556 273119060", 38.9),
		"grad10x6.6x6.s": ("80x64 2747495 399570767", 38.9),
		"gray12x12.4x4": ("53x47 1448913 132050300", 53.0),
		"gray12x12.4x4.s": ("53x47 1448923 146162625", 53.2),
		"gray12x12.6x6": ("53x47 1449159 847006841", 43.3),
		"gray12x12.6x6.s": ("53x47 1449021 903221985", 43.3)
	}
	for stem in ["smooth4x4", "shape8x8", "grad10x6", "gray12x12"]:
		src = load(stem).decode(false)
		for bx in [4, 6]:
			for srgb in [false, true]:
				digest, least = want["{stem}.{bx}x{bx}{".s" if srgb else ""}"]
				back = src.encodeAstc(bx, bx, srgb).decode(srgb)
				expect back.digest() == digest
				expect src.psnr(back) >= least

test "a texture of one color encodes to void extents":
	img = image.Image(9, 5, fill = image.Rgba8(10, 200, 30, 128))
	a = img.encodeAstc(4, 4)
	expect a.blocks.len == 3 * 2 * blockBytes
	expect a.blocks[..8] == [0xFC, 0xFD, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
	expect a.decode(false).cells == img.cells
	expect (readAstc(a.writeAstc()) ?? fail).blocks == a.blocks
