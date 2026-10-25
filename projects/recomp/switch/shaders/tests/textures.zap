# Texture reads past 2D samples from hand-written compute programs (fields as yuzu's texture_*.cpp
# read them): texel fetches (TLD, TLDS) of 2D textures, arrays and 3D textures with their levels
# and offsets, 3D textures and cubes sampled (TEX, TEXS), shadow maps compared at a level and with
# a bias, and textures the TIC says hold integers read as numbers; their module builds.

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

fn program(code i64[]):
	words = code.copy()
	words.push(i64.wrap(exit))
	shaders.Program(stage = .Compute, header = none, words, start = 0)

# whether the text holds the part
fn mentions(text str, part str):
	(text.indexOf(part) ?? -1) >= 0

# the program's translation, nothing left out
fn translated(words i64[], integers {i64: bool} = {}):
	s = shaders.newTable().translateProgram(program(words), "T", [], [1, 1, 1], integers) ?? fail
	if not s.missing.isEmpty: print(s.missing.join("\n"))
	s.text

test "TLD and TLDS fetch texels of 2D textures, arrays and 3D textures, at levels, by offsets":
	text = translated([
		swizzled(true, 2, 4, 0, 1),
		swizzled(true, 12, 5, 2, 4),
		swizzled(true, 7, 6, 8, 10),
		swizzled(true, 8, 7, 12, 14),
		tld(3, 8, 16, 20, lod = true, aoffi = true),
		tld(4, 9, 24, 28)
	])
	expect [
		"p.textures[0].fetch(IVec2(i32(r0), i32(r1)), 0)",
		"p.textures[1].fetch(IVec2(i32(r2) + maxwell.texelOffset(r5, 0), i32(r3) + maxwell.texelOffset(r5, 4)), i32(r4))",
		"p.volumes[0].fetch(IVec3(i32(r8), i32(r9), i32(r10)), 0)",
		"p.layers[0].fetch(IVec2(i32(r14), i32(r15)), i32(r12 & 0xFFFF), 0)",
		"p.layers[1].fetch(IVec2(i32(r17) + maxwell.texelOffset(r21, 0), i32(r18) + maxwell.texelOffset(r21, 4)), i32(r16 & 0xFFFF), i32(r20))",
		"p.volumes[1].fetch(IVec3(i32(r24), i32(r25), i32(r26)), 0)"
	].all(mentions(text, it))

test "3D textures and cubes sampled at levels and by offsets, shadow maps compared at a level and with a bias":
	text = translated([
		0x0100_0000_0007_F000 | (0x1F2 << 20) | 7,   # MOV32I R7, 0x1f2: the offset (2, -1, 1)
		tex(4, 3, 4, 0, 6, aoffi = true),
		tex(7, 0, 5, 8, 12),
		swizzled(false, 13, 6, 16, 18),
		swizzled(false, 10, 7, 20, 22),
		tex(2, 3, 8, 24, 26, compared = true),
		tex(3, 2, 9, 28, 30, compared = true),
		swizzled(false, 5, 10, 32, 34)
	])
	expect [
		"p.volumes[0].sampleLevel(Vec3(f32.fromBits(r0), f32.fromBits(r1), f32.fromBits(r2)), f32.fromBits(r6), IVec3(2, -1, 1))",
		"p.cubeLayers[0].sample(Vec3(f32.fromBits(r9), f32.fromBits(r10), f32.fromBits(r11)), f32(r8 & 0xFFFF))",
		"p.cubes[0].sampleLevel(Vec3(f32.fromBits(r16), f32.fromBits(r17), f32.fromBits(r18)), f32.fromBits(r19))",
		"p.volumes[1].sample(Vec3(f32.fromBits(r20), f32.fromBits(r21), f32.fromBits(r22)))",
		"p.shadows[0].compareLevel(Vec2(f32.fromBits(r24), f32.fromBits(r25)), f32.fromBits(r27), f32.fromBits(r26))",
		"p.shadowLayers[0].compareBias(Vec2(f32.fromBits(r29), f32.fromBits(r30)), f32(r28 & 0xFFFF), f32.fromBits(r31), f32.fromBits(r30))",
		"p.shadows[1].compareLevel(Vec2(f32.fromBits(r32), f32.fromBits(r33)), f32.fromBits(r35), f32.fromBits(r34))"
	].all(mentions(text, it))

test "a texture the TIC says holds integers: its texels fetched and sampled as numbers":
	text = translated(
		[tld(2, 4, 0, 2), swizzled(true, 2, 5, 4, 5), tex(2, 0, 4, 6, 8)],
		{4: false, 5: true}
	)
	expect [
		"intTexel = p.integers[0].fetch(IVec2(i32(r0), i32(r1)), 0)",
		"r0 = intTexel.x",
		"signedTexel = p.signedIntegers[0].fetch(IVec2(i32(r4), i32(r5)), 0)",
		"u32(signedTexel.x)",
		"size = p.integers[0].size(0)"
	].all(mentions(text, it))

test "the reads' module builds":
	words = [
		0x0100_0000_0007_F000 | (0x1F2 << 20) | 7,
		swizzled(true, 2, 4, 0, 1),
		swizzled(true, 12, 5, 2, 4),
		swizzled(true, 7, 6, 8, 10),
		swizzled(true, 8, 7, 12, 14),
		tld(3, 8, 16, 20, lod = true, aoffi = true),
		tex(4, 3, 9, 0, 6, aoffi = true),
		tex(7, 0, 10, 8, 12),
		swizzled(false, 13, 11, 16, 18),
		tex(2, 3, 12, 24, 26, compared = true),
		tex(3, 2, 13, 28, 30, compared = true),
		swizzled(false, 5, 14, 32, 34),
		tld(2, 15, 36, 38),
		tex(2, 0, 16, 40, 42)
	]
	source = shaders.Source(
		name = "Reads",
		program = program(words),
		group = [1, 1, 1],
		integers = {15: false, 16: true}
	)
	out = "projects/recomp/switch/out/tests/texelreads"
	done = shaders.writeModule([source], out) ?? fail
	expect done.shaders.all(.missing.isEmpty)
	fs.writeFile("{out}/programs.zap", shaders.namingProgram(done.shaders, [])) ?? fail("{error}")
	built = Process.output("{zapPath()} build {out}/programs.zap")
	if built.code != 0: print(built.out)
	expect built.code == 0
