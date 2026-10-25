# Texture reads past 2D samples from hand-written compute programs (fields as yuzu's texture_*.cpp
# and surface_*.cpp read them): texel fetches (TLD, TLDS) of 2D textures, arrays and 3D textures
# with their levels and offsets, 3D textures and cubes sampled (TEX, TEXS), shadow maps compared at
# a level and with a bias, textures the TIC says hold integers read as numbers, and surfaces
# loaded, stored and changed by atomics (SULD, SUST, SUATOM, SURED); their module builds.

import fs
import recomp.switch.shaders

exit u64 = 0xE300_0000_0007_000F

# a TEX-family word: the opcode's top bits at `top` and up, then the fields from the low ones
# (the predicate PT at 16)
fn textureWord(op u64, top i64, fields (i64, i64)[]):
	w = i64.wrap(op << top) | (7 << 16)
	for (at, value) in fields:
		w |= value << at
	w

# TEXS (TLDS when `load`) of an encoding, f32 results (bit 59), swizzle 0 (r: into rd), handle h, A and B
fn swizzled(load bool, encoding i64, h i64, a i64, b i64):
	textureWord(
		0x1B,
		59,
		[(57, 1 if load else 0), (53, encoding), (36, h), (28, 0xFF), (20, b), (8, a), (0, 0)]
	)

# TEX of a type, blod, handle h, coordinates from A, meta from B (aoffi, depth compare), into r0
fn tex(dim i64, blod i64, h i64, a i64, b i64, aoffi bool = false, compared bool = false):
	textureWord(
		0x18,
		59,
		[(55, blod), (54, 1 if aoffi else 0), (51, 7), (50, 1 if compared else 0), (36, h), (31, 1),
			(28, dim), (20, b), (8, a)]
	)

# TLD of a type, handle h, from A, meta from B (lod, aoffi), into r0
fn tld(dim i64, h i64, a i64, b i64, lod bool = false, aoffi bool = false):
	textureWord(
		0xDC,
		56,
		[(55, 1 if lod else 0), (51, 7), (36, h), (35, 1 if aoffi else 0), (31, 1), (28, dim),
			(20, b), (8, a)]
	)

# SULD.D (SUST.D when `store`) of a 32-bit number of the bound 2D surface h at A, into (from) rd
fn surfaceAccess(store bool, h i64, a i64, d i64):
	textureWord(
		0xEB,
		56,
		[(53, 1 if store else 0), (52, 1), (51, 1), (36, h), (33, 3), (20, 4), (8, a), (0, d)]
	)

# SUATOM of an operation (U32) on the bound 2D surface h at A by B, what the texel held into rd
fn suatom(op i64, h i64, a i64, b i64, d i64):
	textureWord(0xEA, 56, [(36, h), (33, 3), (29, op), (20, b), (8, a), (0, d)])

# SURED of an operation (U32) on the bound 2D surface h at A by rd's number
fn sured(op i64, h i64, a i64, d i64):
	textureWord(0xEB, 56, [(53, 2), (51, 1), (36, h), (33, 3), (24, op), (8, a), (0, d)])

fn program(code i64[]):
	words = code.copy()
	words.push(i64.wrap(exit))
	shaders.Program(stage = .Compute, header = none, words, start = 0)

# whether the text holds the part
fn mentions(text str, part str):
	(text.indexOf(part) ?? -1) >= 0

# whether the program's translation holds each part, nothing left out
fn translates(words i64[], parts str[], integers {i64: bool} = {}) bool:
	s = shaders.newTable().translateProgram(program(words), "T", [], [1, 1, 1], integers) ?? fail
	if not s.missing.isEmpty: print(s.missing.join("\n"))
	parts.all(mentions(s.text, it))

# TLD and TLDS of 2D textures, arrays and 3D textures, at levels and by offsets
fn fetches() i64[]:
	[
		swizzled(true, 2, 4, 0, 1),
		swizzled(true, 12, 5, 2, 4),
		swizzled(true, 7, 6, 8, 10),
		swizzled(true, 8, 7, 12, 14),
		tld(3, 8, 16, 20, lod = true, aoffi = true),
		tld(4, 9, 24, 28)
	]

# TEX and TEXS of 3D textures and cubes at levels and by an offset; compares at a level, by a bias
fn samples() i64[]:
	[
		0x0100_0000_0007_F000 | (0x1F2 << 20) | 7,   # MOV32I R7, 0x1f2: the offset (2, -1, 1)
		tex(4, 3, 4, 0, 6, aoffi = true),
		tex(7, 0, 5, 8, 12),
		swizzled(false, 13, 6, 16, 18),
		swizzled(false, 10, 7, 20, 22),
		tex(2, 3, 8, 24, 26, compared = true),
		tex(3, 2, 9, 28, 30, compared = true),
		swizzled(false, 5, 10, 32, 34)
	]

# TLD, TLDS and TEX of the textures of integers 15 (unsigned) and 16 (signed)
fn integerReads() i64[]:
	[tld(2, 15, 0, 2), swizzled(true, 2, 16, 4, 5), tex(2, 0, 15, 6, 8)]

# SULD, SUST, SUATOM and SURED of the surfaces 3 and 4
fn surfaces() i64[]:
	[
		surfaceAccess(false, 3, 2, 0),
		surfaceAccess(true, 3, 4, 1),
		suatom(0, 3, 8, 7, 6),
		sured(6, 4, 10, 12)
	]

test "texel fetches, 3D textures, cubes, compares, textures of integers and surfaces translate (textures.expected)":
	expected = (
		fs.readFile("projects/recomp/switch/shaders/tests/textures.expected") ?? fail
	).lines()
	plain {i64: bool} = {}
	cases = [
		("fetches", fetches(), plain.copy()),
		("samples", samples(), plain.copy()),
		("integerReads", integerReads(), {15: false, 16: true}),
		("surfaces", surfaces(), plain.copy())
	]
	for (name, words, integers) in cases:
		parts = expected.filter(.startsWith("{name}: ")).map(it[name.len + 2..].copy())
		expect not parts.isEmpty and words.translates(parts, integers)

test "the reads' module builds":
	words = fetches()
	for part in [samples(), integerReads(), surfaces()]:
		words.extend(part)
	source = shaders.Source(
		name = "Reads",
		program = program(words),
		group = [1, 1, 1],
		integers = {15: false, 16: true}
	)
	out = "projects/recomp/switch/out/tests/texelreads"
	done, said = shaders.writeBuilt([source], out) ?? fail
	expect done.shaders.all(.missing.isEmpty)
	if said != "": print(said)
	expect said == ""
