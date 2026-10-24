# The GPU's front end fed pushbuffers written here: methods, subchannels, semaphores,
# syncpoints and the copies, on a guest memory of a few pages.

import fs
import recomp.switch.cpu.core
import recomp.switch.maxwell
import recomp.switch.textures

base = 0x10_0000
gpuBase = 0x2000_0000

# a GPU with one channel whose address space maps 0x10000 bytes of guest memory at gpuBase
fn newGpu():
	core.memory = core.committedMemory(base, 0x1_0000)
	g = maxwell.Gpu()
	s = g.newSpace()
	g.spaces[s].map(gpuBase, 0x1_0000, base, 0)
	c = g.newChannel()
	g.channels[c].space = s
	g

# a method header: operation, subchannel, method and count
fn header(op i64, sub i64, method i64, count i64):
	op << 29 | count << 16 | sub << 13 | method

# the words laid at gpuBase + at and a submission of one entry naming them
fn submitWords(mut g maxwell.Gpu, at i64, words i64[]):
	bytes = []
	for w in words:
		bytes.pushU32le(w)
	g.spaces[0].write(gpuBase + at, bytes)
	entry = []
	entry.pushU32le(gpuBase + at)
	entry.pushU32le(words.len << 10)
	g.submit(0, entry)

test "an object is bound to a subchannel and its methods fill the registers":
	g = newGpu()
	g.submitWords(0, [header(1, 0, 0, 1), maxwell.classThreeD, header(1, 0, 0x100, 3), 7, 8, 9])
	expect g.channels[0].engines[0].class == maxwell.classThreeD
	expect g.channels[0].engines[0].regs[0x100] == 7
	expect g.channels[0].engines[0].regs[0x102] == 9
	expect g.notes.isEmpty

test "a non-incrementing burst writes one register, an increment-once burst two":
	g = newGpu()
	g.submitWords(0, [header(1, 1, 0, 1), maxwell.classTwoD, header(3, 1, 0x200, 2), 1, 2])
	g.submitWords(0x100, [header(5, 1, 0x300, 3), 4, 5, 6, header(4, 1, 0x400, 77)])
	regs = g.channels[0].engines[1].regs
	expect regs[0x200] == 2
	expect regs[0x300] == 4 and regs[0x301] == 6
	expect regs[0x400] == 77

test "a semaphore release writes its payload, with a timestamp when it is four words":
	g = newGpu()
	g.timestamp = 1234
	g.submitWords(0, [header(1, 0, 4, 4), 0, 0x2000_0200, 0xAB, 2])
	expect g.spaces[0].readWord(gpuBase + 0x200) == 0xAB
	g.submitWords(0, [header(1, 0, 4, 4), 0, 0x2000_0300, 0xCD, 2])
	bytes = g.spaces[0].read(gpuBase + 0x300, 16)
	expect bytes.u64le(0) == 0xCD and bytes.u64le(8) == 1234
	expect g.stats.semaphores == 2

test "a syncpoint operation increments, and an acquire that fails is noted":
	g = newGpu()
	words = [header(1, 0, 0x1D, 1), 1 << 16 | 11, header(1, 0, 0x1D, 1), 1 << 16 | 11]
	g.submitWords(0, words)
	expect g.syncpoints[11] == 2
	expect g.hasReachedSyncpoint(11, 2) and not g.hasReachedSyncpoint(11, 3)

test "an inline upload and a DMA copy move bytes":
	g = newGpu()
	submitWords(
		g,
		0,
		[
			header(1, 2, 0, 1),
			maxwell.classInline,
			header(1, 2, 0x60, 4),
			8,
			1,
			0,
			0x2000_0400,
			header(1, 2, 0x6C, 1),
			1,
			header(3, 2, 0x6D, 2),
			0x0403_0201,
			0x0807_0605
		]
	)
	expect g.spaces[0].read(gpuBase + 0x400, 8) == [1, 2, 3, 4, 5, 6, 7, 8]
	expect g.stats.inlineUploads == 1
	submitWords(
		g,
		0x100,
		[
			header(1, 3, 0, 1),
			maxwell.classCopy,
			header(1, 3, 0x100, 8),
			0,
			0x2000_0400,
			0,
			0x2000_0500,
			0,
			0,
			8,
			1,
			header(1, 3, 0xC0, 1),
			1 | 1 << 7 | 1 << 8
		]
	)
	expect g.spaces[0].read(gpuBase + 0x500, 8) == [1, 2, 3, 4, 5, 6, 7, 8]
	expect g.stats.copies == 1

test "draws end a frame's count":
	g = newGpu()
	submitWords(
		g,
		0,
		[
			header(1, 0, 0, 1),
			maxwell.classThreeD,
			header(1, 0, 0x585, 1),
			0,
			header(1, 0, 0x585, 1),
			0
		]
	)
	g.endFrame()
	expect g.stats.frameDraws == [2]
	expect g.stats.draws == 2

# a macro instruction: operation, result's use, exit, dst, src a, immediate
fn macroWord(op i64, use i64, exit i64, dst i64, srcA i64, imm i64):
	op | use << 4 | exit << 7 | dst << 8 | srcA << 11 | (imm & 0x3_FFFF) << 14

test "a macro sets its method address and sends its parameter there, a delay slot after its exit":
	g = newGpu()
	g.call(0, 0, 0, maxwell.classThreeD)
	code = [
		macroWord(1, 2, 0, 0, 0, 0x1500),   # r0 + 0x1500 made the method address: 0x500, step 1
		macroWord(1, 4, 1, 0, 1, 0),   # r1 sent, then exit
		macroWord(1, 1, 0, 0, 0, 0),   # the exit's delay slot
		macroWord(1, 4, 0, 0, 1, 0)   # never runs
	]
	g.call(0, 0, 0x45, 0)
	for w in code:
		g.call(0, 0, 0x46, w)
	g.call(0, 0, 0x47, 0)
	g.call(0, 0, 0x48, 0)
	g.call(0, 0, 0xE00, 0x1234)
	g.flushMacro(0, 0)
	expect g.channels[0].engines[0].regs[0x500] == 0x1234
	expect g.channels[0].engines[0].regs[0x501] == 0
	expect g.stats.macroCalls == 1

test "a clear color in the render target formats":
	c = Vec4(1.0, 0.5, 0.0, 1.0)
	expect (maxwell.pixelOf(0xD5, c) ?? []) == [u8(255), 128, 0, 255]
	expect (maxwell.pixelOf(0xCF, c) ?? []) == [u8(0), 128, 255, 255]
	expect (maxwell.pixelOf(0xCA, c) ?? []) == [u8(0), 0x3C, 0, 0x38, 0, 0, 0, 0x3C]
	expect (maxwell.pixelOf(0xE8, c) ?? []) == [u8(0), 0xFC]   # red 31, green 32, blue 0
	expect maxwell.pixelOf(0x12, c) == none

fn bits(v f32) i64:
	v.toBits()

# the words of a burst of `values` from `method`
fn burst(method i64, values i64[]):
	words = [header(1, 0, method, values.len)]
	words.extend(values)
	words

# a 3D engine on subchannel 0 and the state of one draw: a target, a vertex stream and attribute,
# a pixel program, a constant buffer, the pools, a viewport, depth and cull
fn setUpDraw(mut g maxwell.Gpu):
	words = [header(1, 0, 0, 1), maxwell.classThreeD]
	words.extend(burst(0x200, [1, 0x2000_0000, 1280, 720, 0xD5, 0x10]))
	words.extend(burst(0x487, [1 | 2 << 4]))
	words.extend(burst(0x458, [8 << 7 | 2 << 21 | 7 << 27]))
	words.extend(burst(0x700, [24 | 1 << 12, 0, 0x2000_0400, 0]))
	words.extend(burst(0x7C0, [0, 0x2000_0500]))
	words.extend(burst(0x646, [1, 0x901, 0x405]))
	words.extend(burst(0x4B3, [1]))
	words.extend(burst(0x4BA, [1]))
	words.extend(burst(0x4C3, [4]))
	words.extend(burst(0x582, [0, 0x2000_0000]))
	words.extend(burst(0x810, [0, 0x3000]))   # VertexB, run though its enable bit is clear
	words.extend(burst(0x850, [1, 0x1000]))
	words.extend(burst(0x8E0, [0x100, 0, 0x2000_0800]))
	words.extend(burst(0x924, [1 | 3 << 4]))
	words.extend(burst(0x557, [0, 0x2000_0900, 63]))
	words.extend(burst(0x55D, [0, 0x2000_0A00, 127]))
	words.extend(burst(0x982, [2]))
	words.extend(
		burst(0x280, [bits(640.0), bits(-360.0), bits(0.5), bits(640.0), bits(360.0), bits(0.5)])
	)
	words.extend(burst(0x300, [1280 << 16, 720 << 16, 0, bits(1.0)]))
	words.extend(burst(0x380, [1, 1280 << 16, 720 << 16]))
	g.submitWords(0, words)

test "a draw's end keeps the state a renderer needs":
	g = newGpu()
	g.setUpDraw()
	g.submitWords(
		0,
		[header(1, 0, 0x586, 1), 4, header(1, 0, 0x35D, 2), 0, 3, header(1, 0, 0x585, 1), 0]
	)
	expect g.draws.len == 1 and g.stats.draws == 1
	d = g.draws[0]
	expect d.topology == 4 and not d.indexed and d.first == 0 and d.count == 3 and d.instances == 1
	expect d.attributes.len == 1 and d.attributes[0].offset == 8 and d.attributes[0].size == 2
	expect d.attributes[0].kind == 7 and d.attributes[0].stream == 0 and
		not d.attributes[0].constant
	expect d.streams[0].enabled and d.streams[0].stride == 24 and
		d.streams[0].address == 0x2000_0400
	expect d.streams[0].limit == 0x2000_0500 and not d.streams[1].enabled
	expect d.programs.len == 2 and d.programs[0].slot == 1 and d.programs[0].kind == 0
	expect d.programs[0].address == 0x2000_3000
	expect d.programs[1].kind == 4 and d.programs[1].slot == 5
	expect d.programs[1].address == 0x2000_1000
	expect d.constantBuffers.len == 1 and d.constantBuffers[0].kind == 4
	expect d.constantBuffers[0].slot == 3 and d.constantBuffers[0].size == 0x100
	expect d.constantBuffers[0].address == 0x2000_0800
	expect d.samplerPool.address == 0x2000_0900 and d.samplerPool.highest == 63
	expect d.texturePool.address == 0x2000_0A00 and d.textureBufferSlot == 2
	expect d.targets[0].address == 0x1_2000_0000 and d.targets[0].width == 1280
	expect d.targets[0].format == 0xD5 and d.targetCount == 1 and d.targetMap[0] == 2
	expect d.viewports[0].scale.x == 640.0 and d.viewports[0].translate.y == 360.0
	expect d.viewports[0].width == 1280 and d.viewports[0].height == 720
	expect d.viewports[0].far == 1.0
	expect d.scissors[0].enabled and d.scissors[0].x2 == 1280 and d.scissors[0].y2 == 720
	expect d.depth.testEnabled and d.depth.writeEnabled and d.depth.function == 4
	expect d.cull.enabled and d.cull.frontFace == 0x901 and d.cull.face == 0x405
	expect not d.blend[0].enabled
	g.endFrame()
	expect g.draws.isEmpty

test "an indexed draw, an inline index draw and a one-word draw with instances":
	g = newGpu()
	g.setUpDraw()
	g.submitWords(
		0,
		[
			header(1, 0, 0x5F2, 7),
			0,
			0x2000_0600,
			0,
			0x2000_0700,
			1,
			5,
			12,
			header(1, 0, 0x586, 1),
			4,
			header(1, 0, 0x585, 1),
			0,
			header(1, 0, 0x586, 1),
			4 | 1 << 26,
			header(1, 0, 0x585, 1),
			0
		]
	)
	d = g.draws[0]
	expect g.draws.len == 1 and g.stats.draws == 2 and d.instances == 2
	expect d.indexed and d.first == 5 and d.count == 12 and d.index.address == 0x2000_0600
	expect d.index.end == 0x2000_0700 and d.index.format == 1
	g.submitWords(0, [header(3, 0, 0x57C, 2), 3 << 16 | 1, 2, header(1, 0, 0x4C1, 1), 0x0A09_0807])
	g.submitWords(0, [header(1, 0, 0x586, 1), 4, header(1, 0, 0x585, 1), 0])
	expect g.draws[1].indexed and g.draws[1].inlineIndices == [1, 3, 2, 0, 7, 8, 9, 10]
	expect g.draws[1].count == 8
	word = 5 << 28 | 6 << 16 | 2
	g.submitWords(0, [header(1, 0, 0x485, 1), word, header(1, 0, 0x486, 1), word])
	expect g.draws.len == 3 and g.draws[2].topology == 5 and g.draws[2].first == 2
	expect g.draws[2].count == 6 and g.draws[2].instances == 2 and not g.draws[2].indexed

# a texture entry made by hand: format 8 with component types 2, swizzled R G B and the float
# one, a block linear 256x128x2 image of 5 levels, block height 2 GOBs
fn textureEntry():
	e = []
	e.pushU32le(8 | 2 << 7 | 2 << 10 | 2 << 13 | 2 << 16 | 2 << 19 | 3 << 22 | 4 << 25 | 7 << 28)
	e.pushU32le(0x3456_7000)
	e.pushU32le(0x12 | 3 << 21)
	e.pushU32le(1 << 3 | 4 << 28)
	e.pushU32le(255 | 1 << 23 | 1 << 22)
	e.pushU32le(127 | 1 << 16 | 1 << 31)
	e.pushU32le(0)
	e.pushU32le(1 | 3 << 4)
	e

test "a texture image control entry":
	t = textures.decodeTic(textureEntry())
	expect t.format == 8 and t.componentTypes == [2, 2, 2, 2] and t.swizzle == [2, 3, 4, 7]
	expect t.address == 0x12_3456_7000 and t.layout == textures.layoutBlockLinear
	expect t.isBlockLinear() and t.blockHeight == 1 and t.blockWidth == 0 and t.blockDepth == 0
	expect t.width == 256 and t.height == 128 and t.depth == 2 and t.levels == 5
	expect t.target == textures.target2d and t.srgb and t.normalizedCoordinates
	expect t.baseLevel == 1 and t.maxLevel == 3

test "a linear entry takes its pitch in 32-byte units":
	e = textureEntry()
	e.setU32le(8, 0x12 | textures.layoutLinear << 21)
	e.setU32le(12, 40)
	t = textures.decodeTic(e)
	expect not t.isBlockLinear() and t.pitch == 1280

test "a texture sampler control entry":
	e = []
	e.pushU32le(2 | 1 << 3 | 3 << 6 | 1 << 9 | 3 << 10 | 7 << 20)
	e.pushU32le(2 | 2 << 4 | 3 << 6 | 1 << 9 | 0x1F80 << 12)
	e.pushU32le(0x200 | 0x400 << 12)
	e.pushU32le(0)
	for v in [f32(0.25), 0.5, 0.75, 1.0]:
		e.pushU32le(bits(v))
	s = textures.decodeTsc(e)
	expect s.wrapU == 2 and s.wrapV == 1 and s.wrapW == 3
	expect s.compareEnabled and s.compareFunction == 3 and s.maxAnisotropy == 16
	expect s.magFilter == 2 and s.minFilter == 2 and s.mipFilter == 3 and s.seamlessCube
	expect s.lodBias == -0.5 and s.minLod == 2.0 and s.maxLod == 4.0
	expect s.borderColor == [0.25, 0.5, 0.75, 1.0]

# a Maxwell program of a header and a group ending in the branch to itself; `tag` tells programs
# apart
fn programOf(tag i64):
	p u8[] = zeros(0x50)
	p[0] = u8(tag)
	p.pushU64le(0)
	endLoop u64 = 0xE240_0FFF_FF87_000F
	p.pushU64le(i64.wrap(endLoop))
	p.pushU64le(0)
	p.pushU64le(0)
	p

recordedDir = "projects/recomp/switch/out/test-recorded"

test "recording writes one file for each distinct program":
	_ = fs.deleteTree(recordedDir)
	g = newGpu()
	g.recordDir = recordedDir
	g.setUpDraw()
	g.spaces[0].write(gpuBase + 0x1000, programOf(1))
	g.spaces[0].write(gpuBase + 0x2000, programOf(2))
	g.spaces[0].write(gpuBase + 0x3000, programOf(3))
	g.submitWords(0, [header(1, 0, 0x586, 1), 4, header(1, 0, 0x585, 1), 0])
	g.submitWords(0, [header(1, 0, 0x585, 1), 0])
	g.submitWords(0, [header(1, 0, 0x851, 1), 0x2000, header(1, 0, 0x585, 1), 0])
	expect g.recorded.len == 3
	sets = (fs.readFile(fs.join(recordedDir, maxwell.pairsFile)) ?? "").lines()
	expect sets.len == 2 and sets.all(.split(" ").len == 2)
	names = (fs.list(recordedDir) ?? []).filter(it != maxwell.pairsFile)
	expect names.len == 3
	for name in names:
		bytes = fs.readBytes(fs.join(recordedDir, name)) ?? []
		expect bytes.len == 0x70
	_ = fs.deleteTree(recordedDir)

test "the older increasing and non-increasing headers carry bursts as the newer ones":
	g = newGpu()
	g.submitWords(0, [header(1, 0, 0, 1), maxwell.classThreeD])
	g.submitWords(0x100, [header(0, 0, 0x500, 2), 0x11, 0x22, header(2, 0, 0x510, 2), 0x33, 0x44])
	expect g.channels[0].engines[0].regs[0x500] == 0x11
	expect g.channels[0].engines[0].regs[0x501] == 0x22
	expect g.channels[0].engines[0].regs[0x510] == 0x44

test "a later mapping over part of an older one is what the GPU reads there":
	g = newGpu()
	g.spaces[0].map(gpuBase + 0x1000, 0x1000, base + 0x8000, 0)
	core.memory.write(base + 0x1000, [1])
	core.memory.write(base + 0x8000, [2])
	expect g.spaces[0].read(gpuBase + 0x1000, 1)[0] == 2
	expect g.spaces[0].read(gpuBase + 0x2000, 1)[0] == 0

test "words written to the constant data registers land in the window's buffer, one after another":
	g = newGpu()
	words = [header(1, 0, 0, 1), maxwell.classThreeD]
	words.extend(burst(0x8E0, [0x100, 0, gpuBase + 0x800, 8]))
	words.extend(burst(0x8E4, [0x11, 0x22]))
	g.submitWords(0, words)
	expect g.spaces[0].readWord(gpuBase + 0x808) == 0x11 and
		g.spaces[0].readWord(gpuBase + 0x80C) == 0x22
