# The GPU's front end fed pushbuffers written here: methods, subchannels, semaphores,
# syncpoints and the copies, on a guest memory of a few pages.

import recomp.switch.cpu
import recomp.switch.maxwell

base = 0x10_0000
gpuBase = 0x2000_0000

# a GPU with one channel whose address space maps 0x10000 bytes of guest memory at gpuBase
fn newGpu():
	cpu.memory = cpu.Memory(bytes = zeros(0x1_0000), base = base)
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
