# The emulated processor: the 16 general registers, rip, the flags the integer instructions set
# (each a bool), the 16 XMM registers (two 64-bit halves each), the fs and gs bases, over the
# memory of memory.zap; the operand reads and writes the instructions share. MXCSR stays at its
# default (round to nearest, no flush to zero, exceptions masked), as the game runs.

import engine.memorymap

pub type Stub:
	Returns(rax u64, xmm0 u64)   # returns these at once
	Pause   # stops the run (`Stop.Paused`) for the caller to answer and resume
	Crt(name str)   # a C runtime function the platform computes (stubs.zap)

pub type Machine:
	mem Memory
	regs u64[] = zeros(16)
	xmm u64[] = zeros(32)   # register k's low half at 2k, high at 2k + 1
	rip u64 = 0
	cf bool = false
	pf bool = false
	af bool = false
	zf bool = false
	sf bool = false
	of bool = false
	df bool = false
	fsBase u64 = 0
	gsBase u64 = 0
	stubs {u64: Stub} = {}
	budget i64 = 1_000_000   # instructions a run may take
	steps i64 = 0
	trace bool = false
	branched bool = true   # rip was set by a jump: look for a stub there
	cacheAt {u64: i64} = {}
	cache Instr[] = []

	# general register r's low `size` bytes; a byte register without REX from 4 on is ah..bh
	fn reg(r i64, size i64, rex i64):
		v = regs[r]
		match size:
			8: v
			4: v & 0xFFFF_FFFF
			2: v & 0xFFFF
			_: (regs[r - 4] >> 8) & 0xFF if rex == 0 and r >= 4 and r < 8 else v & 0xFF

	# a write of `size` bytes to register r: 4 bytes clear the upper half, 1 and 2 keep the rest
	fn setReg(r i64, size i64, rex i64, v u64):
		match size:
			8: regs[r] = v
			4: regs[r] = v & 0xFFFF_FFFF
			2: regs[r] = (regs[r] & ~u64(0xFFFF)) | (v & 0xFFFF)
			_:
				if rex == 0 and r >= 4 and r < 8:
					regs[r - 4] = (regs[r - 4] & ~u64(0xFF00)) | (v & 0xFF) << 8
				else:
					regs[r] = (regs[r] & ~u64(0xFF)) | (v & 0xFF)

	# the address of the memory operand
	fn ea(d Instr):
		a u64 = u64.wrap(d.disp)
		if d.base == 16: a += d.at + u64(d.len)
		elif d.base >= 0: a += regs[d.base]
		if d.index >= 0: a += regs[d.index] * u64(d.scale)
		if d.seg == 0x64: a += fsBase
		if d.seg == 0x65: a += gsBase
		a

	mut fn readE(d Instr, size i64):
		if d.mem: return mem.read(ea(d), size)
		reg(d.rm, size, d.rex)

	mut fn writeE(d Instr, size i64, v u64):
		if d.mem: mem.write(ea(d), size, v)
		else: setReg(d.rm, size, d.rex, v)

	fn readG(d Instr, size i64):
		reg(d.reg, size, d.rex)

	mut fn writeG(d Instr, size i64, v u64):
		setReg(d.reg, size, d.rex, v)

	# the two halves of XMM register r
	fn lo(r i64):
		xmm[2 * r]

	fn hi(r i64):
		xmm[2 * r + 1]

	fn setXmm(r i64, low u64, high u64):
		xmm[2 * r] = low
		xmm[2 * r + 1] = high

	# the XMM-or-memory operand as two halves: from memory its `bytes` (4, 8 or 16), the rest zero
	mut fn readW(d Instr, bytes i64):
		if not d.mem: return (lo(d.rm), hi(d.rm))
		at = ea(d)
		match bytes:
			16: (mem.read(at, 8), mem.read(at + 8, 8))
			_: (mem.read(at, bytes), 0)

	fn push(v u64):
		regs[4] -= 8
		mem.write(regs[4], 8, v)

	fn pop():
		v = mem.read(regs[4], 8)
		regs[4] += 8
		v

	fn jump(to u64):
		rip = to
		branched = true

	# condition code c (the low nibble of jcc, setcc, cmovcc)
	fn holds(c i64):
		r = match c >> 1:
			0: of
			1: cf
			2: zf
			3: cf or zf
			4: sf
			5: pf
			6: sf != of
			_: zf or sf != of
		r != (c & 1 == 1)

# A machine over the image: its stack, its scratch memory and its thread block open, each import
# a stub of the C runtime.
pub fn machineFor(move image Image) Machine:
	stubs {u64: Stub} = {}
	for imp in image.imports:
		stubs[imp.stub] = .Crt(imp.name.copy())
	m = Machine(mem = Memory(image), stubs)
	m.mem.open(stackTop - u64(stackSize), stackSize)
	m.mem.open(scratchBase, scratchSize)
	m.mem.open(tebBase, 0x1_0000)
	m.gsBase = tebBase
	m.mem.write(tebBase + 0x30, 8, tebBase)
	m.mem.write(tebBase + 0x58, 8, tebBase + 0x1000)
	for k in 0..64:
		m.mem.write(tebBase + 0x1000 + u64(8 * k), 8, tebBase + 0x4000)
	m

# the stack, below the image's usual base; scratch memory a caller fills (a struct an argument
# points to); the thread's environment block gs points to, its TLS array at +0x1000, every slot
# the block of zeros at +0x4000
pub stackTop u64 = 0x10_0000_0000
pub stackSize n64 = 0x10_0000
pub scratchBase u64 = 0x20_0000_0000
pub scratchSize n64 = 0x100_0000
pub tebBase u64 = 0x30_0000_0000
