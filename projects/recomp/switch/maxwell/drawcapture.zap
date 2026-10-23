# The draws of a frame kept as DrawCalls, and the programs they used written out. A draw is the
# END method (the BEGIN before it names the topology and whether it is one more instance of the
# last draw), or one of the methods that begin, draw and end in one word.

import digest
import fs
import recomp.switch.shaders

maxDrawsAFrame = 512

# the byte count a program is searched for: grown from the first up to the last
firstProgramBytes = 0x400
mostProgramBytes = 0x4_0000

# the bits of BEGIN: the topology, then whether the draw is one more instance of the last
beginTopologyMask = 0xFFFF
beginSubsequentBit = 26

# a draw of the engine's registers kept for the frame; `subsequent` makes it one more instance of
# the last draw kept
fn keepDraw(
	mut g Gpu,
	c i64,
	sub i64,
	topology i64,
	subsequent bool,
	indexed bool,
	first i64,
	count i64
):
	g.stats.draws += 1
	g.stats.drawsThisFrame += 1
	if subsequent and not g.draws.isEmpty:
		g.draws[len - 1].instances += 1
		return
	if g.draws.len >= maxDrawsAFrame:
		return g.note("more than {maxDrawsAFrame} draws in a frame, the rest not kept")
	draw = g.channels[c].engines[sub].drawOf(topology, indexed, first, count)
	if not g.recordDir.isEmpty:
		for p in draw.programs:
			g.recordProgram(c, p.address)
	g.draws.push(draw)

# END: the draw BEGIN began, an indexed one when the index count was written since or indices
# came inline
fn drawEnded(mut g Gpu, c i64, sub i64):
	e = g.channels[c].engines[sub]
	begin = e.regs[reg3dDrawBegin]
	inline = e.inlineIndices.len
	indexed = e.drawIndexed or inline > 0
	first = e.regs[reg3dIndexBuffer + 5] if indexed else e.regs[reg3dVertexArrayFirst]
	count = inline if inline > 0
		else e.regs[reg3dIndexBufferCount] if indexed
		else e.regs[reg3dVertexArrayFirst + 1]
	g.keepDraw(
		c,
		sub,
		begin & beginTopologyMask,
		(begin >> beginSubsequentBit) & 1 == 1,
		indexed,
		first,
		count
	)
	g.channels[c].engines[sub].inlineIndices.clear()
	g.channels[c].engines[sub].drawIndexed = false

# a method that draws: bits 0-15 the first, 16-27 the count, 28-31 the topology
fn drawBeginEnd(mut g Gpu, c i64, sub i64, method i64, arg i64):
	indexed = method >= reg3dIndexBeginEnd
	subsequent = method == reg3dVertexArrayBeginEnd + 1 or method >= reg3dIndexBeginEnd + 3
	g.keepDraw(c, sub, (arg >> 28) & 0xF, subsequent, indexed, arg & 0xFFFF, (arg >> 16) & 0xFFF)

fn isDrawBeginEnd(method i64):
	method == reg3dVertexArrayBeginEnd or method == reg3dVertexArrayBeginEnd + 1 or
		(method >= reg3dIndexBeginEnd and method < reg3dIndexBeginEnd + 6)

# indices sent as method data: four bytes, two shorts or one word
fn pushInlineIndices(mut g Gpu, c i64, sub i64, method i64, arg i64):
	width = 8 if method == reg3dInlineIndexU8 else 16 if method == reg3dInlineIndexU16 else 32
	for k in 0..32 / width:
		if g.channels[c].engines[sub].inlineIndices.len < maxInlineIndices:
			g.channels[c].engines[sub].inlineIndices.push((arg >> (k * width)) & ((1 << width) - 1))

fn isInlineIndex(method i64):
	method in [reg3dInlineIndexU8, reg3dInlineIndexU16, reg3dInlineIndexU32]

fn isConstantBind(method i64):
	method >= reg3dConstantBind and method < reg3dConstantBind + constantStages * 8 and
		(method - reg3dConstantBind) % 8 == 0

# A stage's bind of the constant buffer window (the address and size set before) to a slot, or the
# slot's release.
fn bindConstantBuffer(mut g Gpu, c i64, sub i64, method i64, arg i64):
	slot = (arg >> 4) & 0x1F
	if slot >= constantSlots: return g.note("constant buffer slot {slot}")
	e = g.channels[c].engines[sub]
	at = ((method - reg3dConstantBind) / 8 * constantSlots + slot) * 3
	size = e.regs[reg3dConstantWindow]
	address = addressAt(e.regs, reg3dConstantWindow + 1)
	g.channels[c].engines[sub].bound[at] = arg & 1
	g.channels[c].engines[sub].bound[at + 1] = address
	g.channels[c].engines[sub].bound[at + 2] = size

# A program's bytes (its header and code to the branch that ends it) at a GPU address: none when
# no end lies within reach.
fn programBytes(mut g Gpu, c i64, address i64) u8[]?:
	s = g.spaceOf(c)
	if s < 0: return none
	size = firstProgramBytes
	while size <= mostProgramBytes:
		code = g.spaces[s].read(address, size)
		end = shaders.programEnd(code, 0)
		if end != none: return code[..end ?? 0].copy()
		size *= 2
	none

# The program at `address` written to the recording dir the first time its bytes are met, named by
# their hash (what tools/shaders.zap reads back).
fn recordProgram(mut g Gpu, c i64, address i64):
	code = g.programBytes(c, address) ?? return g.note("no end to the program at {address:x}")
	name = "{digest.crc32(code):08x}{digest.fnv1a(code):08x}"
	if name in g.recorded: return
	g.recorded.push(name.copy())
	fs.createDir(g.recordDir) ?? return g.note("cannot make {g.recordDir}: {error}")
	fs.writeBytes(fs.join(g.recordDir, "{name}.bin"), code) ??
		g.note("cannot write the program {name}: {error}")
