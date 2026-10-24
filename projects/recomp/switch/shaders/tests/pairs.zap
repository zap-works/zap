# A vertex and a pixel program that both read textures, translated into one module: they share
# its `Params`, so `shader` pairs them, and the module of the recorded sets builds.

import fs
import recomp.switch.shaders

pixelBase = 32

# the program header as the GPU reads it: 20 words, the stage in word 0 and two words as given
fn headerBytes(kind i64, first i64, firstWord i64, second i64, secondWord i64):
	words = fill(20, 0)
	words[first] = firstWord
	words[second] = secondWord
	words[0] = kind << 10
	out = []
	for w in words:
		for k in 0..4:
			out.push(u8.wrap((w >> (k * 8)) & 0xFF))
	out

# TEXS of encoding 1 (a 2D sample) of the texture `handle`, its x component into r0
fn texs(handle i64) u64:
	u64.wrap(
		(0xD << 60) | (1 << 59) | (1 << 53) | (handle << 36) | (0xFF << 28) | (2 << 20) | (7 << 16)
	)

exit u64 = 0xE300_0000_0007_000F

# whether the text holds the part
fn mentions(text str, part str):
	(text.indexOf(part) ?? -1) >= 0

# ALD of generic attribute 0 into r1: the vertex stage's input
vertexInput u64 = 0xEFD8_0000_0000_0000 | (128 << 20) | (255 << 8) | (7 << 16) | 1

# a vertex stage passing generic 0 on (output bit 432), reading its attribute and `handles`
fn vertexProgram(handles i64[]):
	words = [vertexInput]
	for h in handles:
		words.push(texs(h))
	words.push(exit)
	header = shaders.readHeader(headerBytes(1, 13, 1 << 16, 19, 0), 0)
	shaders.Program(
		.Vertex,
		header,
		words = words.map(i64.wrap(it)),
		start = 0
	)

# a pixel stage reading generic 0 (perspective) and `handles`, writing target 0
fn pixelProgram(handles i64[]):
	words = handles.map(texs(it))
	words.push(exit)
	header = shaders.readHeader(headerBytes(5, 6, 2, 18, 0xF), 0)
	shaders.Program(
		.Pixel,
		header,
		words = words.map(i64.wrap(it)),
		start = 0
	)

test "a vertex and a pixel program with textures pair under the shared Params and build":
	sources = [
		shaders.Source(name = "Pa", program = vertexProgram([5]), group = []),
		shaders.Source(name = "Pb", program = pixelProgram([6, 9]), group = [])
	]
	out = "projects/recomp/switch/out/tests/pairs"
	done = shaders.writeModule(sources, out) ?? fail
	expect done.shaders.len == 2
	expect done.shaders.all(.missing.isEmpty)
	types = fs.readFile("{out}/{shaders.module}/types.gpu.zap") ?? fail("{error}")
	expect mentions(types, "textures engine.Texture[]")
	vertex = done.shaders[0]
	pixel = done.shaders[1]
	expect mentions(vertex.text, "p.textures[0]")
	expect mentions(pixel.text, "p.textures[{pixelBase}]")
	expect mentions(pixel.text, "p.textures[{pixelBase + 1}]")
	sets = shaders.translatedSets(["a b", "a", "b", "b a", "a x"], done.shaders)
	expect sets.map(.key) == ["a b"]
	done.writePrograms(sets, out) ?? fail
	built = Process.output("{zapPath()} build {out}/programs.zap")
	if built.code != 0: print(built.out)
	expect built.code == 0

# a TEX-family word: the opcode's top bits at `top` and up, then the fields from the low ones
fn textureWord(op u64, top i64, fields (i64, i64)[]):
	w = i64.wrap(op << top) | (7 << 16)
	for (at, value) in fields:
		w |= value << at
	w

# A pixel program reading by TEX at a bias with an offset MOV32I gave, TEX of a shadow array, TLD4
# of component 1 and TMML.B of the handle MOV read from c[2][0x20]; writing target 5 and its depth.
fn readingProgram():
	words = [
		0x0100_0000_0007_F000 | (0xF1 << 20) | 9,   # MOV32I R9, 0xf1: the offset (1, -1)
		textureWord(0x18, 59, [(55, 2), (54, 1), (51, 7), (36, 4), (31, 0xF), (28, 2), (20, 8)]),
		textureWord(0x18, 59, [(51, 7), (50, 1), (36, 5), (31, 1), (28, 3), (20, 12), (0, 4)]),
		textureWord(0x32, 58, [(56, 1), (51, 7), (36, 6), (31, 0xF), (28, 2), (20, 0xFF), (0, 16)]),
		textureWord(0x4C98, 48, [(39, 0xF), (34, 2), (20, 8), (0, 10)]),   # MOV R10, c[2][0x20]
		textureWord(0x1BEC, 51, [(31, 2), (28, 2), (20, 10), (0, 20)]),
		i64.wrap(exit)
	]
	header = shaders.readHeader(headerBytes(5, 18, 0xF << 20, 19, 2), 0)
	shaders.Program(.Pixel, header, words, start = 0)

test "a pixel program's reads past a sample and its target 5 and depth translate and build":
	sources = [
		shaders.Source(name = "Pa", program = vertexProgram([]), group = []),
		shaders.Source(name = "Pc", program = readingProgram(), group = [])
	]
	out = "projects/recomp/switch/out/tests/reads"
	done = shaders.writeModule(sources, out) ?? fail
	expect done.shaders.all(.missing.isEmpty)
	text = done.shaders[1].text
	expect [
		"p.textures[{pixelBase}].sampleBias(Vec2(f32.fromBits(r0), f32.fromBits(r1)), f32.fromBits(r8), IVec2(1, -1))",
		"p.shadowLayers[{pixelBase}].compare(Vec2(f32.fromBits(r1), f32.fromBits(r2)), f32(r0 & 0xFFFF), f32.fromBits(r12))",
		"p.textures[{pixelBase + 1}].gather(Vec2(f32.fromBits(r0), f32.fromBits(r1)), 1)",
		"p.textures[{pixelBase + 2}].lod(",
		"u32(level.y.max(0.0) * 256.0)",
		"target5 = Vec4(f32.fromBits(r0), f32.fromBits(r1), f32.fromBits(r2), f32.fromBits(r3)), depth = f32.fromBits(r5)"
	].all(mentions(text, it))
	expect done.shaders[1].textures.map("{.kind}:{.handle}:{.bank}") ==
		["Plain:4:-1", "LayeredShadow:5:-1", "Plain:6:-1", "Plain:8:2"]
	done.writePrograms(shaders.translatedSets(["a c"], done.shaders), out) ?? fail
	built = Process.output("{zapPath()} build {out}/programs.zap")
	if built.code != 0: print(built.out)
	expect built.code == 0

test "TXD: a sample by the gradients in B, its offset in the register after the coordinates":
	words = [
		0x0100_0000_0007_F000 | (0x0F << 36) | 2,   # MOV32I R2, 0xf0000: the offset (-1, 0)
		textureWord(0x378, 54, [(51, 7), (36, 3), (35, 1), (31, 1), (28, 2), (20, 4), (0, 8)]),
		i64.wrap(exit)
	]
	header = shaders.readHeader(headerBytes(5, 18, 0xF, 19, 0), 0)
	s = shaders
		.newTable()
		.translateProgram(shaders.Program(.Pixel, header, words, start = 0), "T", [], []) ??
		fail
	expect s.missing.isEmpty
	expect mentions(s.text, "p.textures[{pixelBase}].sampleGrad(Vec2(f32.fromBits(r0), f32.fromBits(r1)), Vec2(f32.fromBits(r4), f32.fromBits(r6)), Vec2(f32.fromBits(r5), f32.fromBits(r7)), IVec2(-1, 0))")
