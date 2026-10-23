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
