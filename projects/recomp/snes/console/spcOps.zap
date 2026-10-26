# The SPC700's instructions, each a sequence of bus cycles in the order Mesen 2 and fullsnes give:
# the opcode's fetch, its operands', the reads and writes of its data, its internal cycles (idle)
# and the dummy reads it makes. The ALU's six operations share their eleven address modes
# (aluInstruction); the rest is a table of one line an opcode. Three kinds of step take no bus
# cycle (a branch not taken, [dp]+Y's index, DIV's tenth): `zeroStepAt` keeps where, for the ports.

type AluOp:
	Or
	And
	Eor
	Cmp
	Adc
	Sbc

# the operation of each pair of rows of the opcode table, 0-B
aluOps AluOp[] = [.Or, .And, .Eor, .Cmp, .Adc, .Sbc]

fn runInstruction():
	op = spcFetch()
	lo = op & 0x0F
	hi = op >> 4
	match lo:
		1: tcall(hi)
		2: setBit(hi >> 1, hi & 1 == 0)
		3: branchOnBit(hi >> 1, hi & 1 == 0)
		_:
			if lo >= 4 and lo <= 9 and hi < 0xC: aluOps[hi >> 1].aluInstruction(op & 0x1F)
			else: otherInstruction(op)

fn spcFetch():
	v = spcRead(spc.pc)
	spc.pc = (spc.pc + 1) & 0xFFFF
	v

fn dummyRead():
	spcRead(spc.pc)

fn direct(offset i64):
	(offset & 0xFF) | (0x100 if spc.psw.p else 0)

fn signed(v i64):
	(v ^ 0x80) - 0x80

# ---------- address modes: their bus cycles, then the address ----------

fn dpAddr():
	direct(spcFetch())

fn dpIndexed(index i64):
	at = direct(spcFetch() + index)
	spcIdle()
	at

fn absAddr():
	lo = spcFetch()
	lo | (spcFetch() << 8)

fn absIndexed(index i64):
	at = absAddr()
	spcIdle()
	(at + index) & 0xFFFF

fn xAddr():
	dummyRead()
	direct(spc.x)

# [dp+X]: the pointer at dp+X
fn dpXIndirect():
	at = dpIndexed(spc.x)
	lo = spcRead(at)
	lo | (spcRead(direct(at + 1)) << 8)

# [dp]+Y: the pointer at dp, plus Y
fn dpIndirectY():
	at = dpAddr()
	lo = spcRead(at)
	hi = spcRead(direct(at + 1))
	spc.zeroStepAt = spc.tick
	spcIdle()
	((lo | (hi << 8)) + spc.y) & 0xFFFF

# ---------- flags ----------

fn setNZ(v i64):
	spc.psw.n = v & 0x80 != 0
	spc.psw.z = v & 0xFF == 0

fn setNZ16(v i64):
	spc.psw.n = v & 0x8000 != 0
	spc.psw.z = v & 0xFFFF == 0

fn carry():
	1 if spc.psw.c else 0

# ---------- the ALU ----------

fn add(l i64, r i64):
	sum = l + r + carry()
	spc.psw.v = ~(l ^ r) & (l ^ sum) & 0x80 != 0
	spc.psw.h = (l ^ r ^ sum) & 0x10 != 0
	spc.psw.c = sum > 0xFF
	setNZ(sum)
	sum & 0xFF

fn compare(l i64, r i64):
	spc.psw.c = l >= r
	setNZ(l - r)

# the operation's result on l and r (CMP's: l, its flags set)
fn alu(kind AluOp, l i64, r i64):
	match kind:
		Or: logic(l | r)
		And: logic(l & r)
		Eor: logic(l ^ r)
		Cmp:
			compare(l, r)
			l
		Adc: add(l, r)
		Sbc: add(l, r ^ 0xFF)

fn logic(v i64):
	setNZ(v)
	v

# The ALU's operations in their modes: rows 0-B, columns 4-9 (an odd row the indexed modes).
fn aluInstruction(kind AluOp, mode i64):
	match mode:
		0x04: spc.a = kind.alu(spc.a, spcRead(dpAddr()))
		0x05: spc.a = kind.alu(spc.a, spcRead(absAddr()))
		0x06: spc.a = kind.alu(spc.a, spcRead(xAddr()))
		0x07: spc.a = kind.alu(spc.a, spcRead(dpXIndirect()))
		0x08: spc.a = kind.alu(spc.a, spcFetch())
		0x09:
			v = spcRead(dpAddr())
			kind.aluToMemory(v, dpAddr())
		0x14: spc.a = kind.alu(spc.a, spcRead(dpIndexed(spc.x)))
		0x15: spc.a = kind.alu(spc.a, spcRead(absIndexed(spc.x)))
		0x16: spc.a = kind.alu(spc.a, spcRead(absIndexed(spc.y)))
		0x17: spc.a = kind.alu(spc.a, spcRead(dpIndirectY()))
		0x18:
			v = spcFetch()
			kind.aluToMemory(v, dpAddr())
		_:
			dummyRead()
			v = spcRead(direct(spc.y))
			kind.aluToMemory(v, direct(spc.x))

# dp, dp / dp, #imm / (X), (Y): the destination read, then written (CMP: an internal cycle)
fn aluToMemory(kind AluOp, v i64, at i64):
	r = kind.alu(spcRead(at), v)
	if kind == .Cmp: spcIdle() else: spcWrite(at, r)

# ---------- loads, stores, read-modify-writes ----------

fn load(v i64):
	setNZ(v)
	v

# a store reads its address first
fn store(at i64, v i64):
	spcRead(at)
	spcWrite(at, v)

fn shift(kind i64, v i64):
	match kind:
		0:
			spc.psw.c = v & 0x80 != 0
			load((v << 1) & 0xFF)
		1:
			r = ((v << 1) | carry()) & 0xFF
			spc.psw.c = v & 0x80 != 0
			load(r)
		2:
			spc.psw.c = v & 1 != 0
			load(v >> 1)
		3:
			r = (v >> 1) | (carry() << 7)
			spc.psw.c = v & 1 != 0
			load(r)
		4: load((v - 1) & 0xFF)
		_: load((v + 1) & 0xFF)

# ASL ROL LSR ROR DEC INC (kinds 0-5) on memory: read, write
fn modify(kind i64, at i64):
	spcWrite(at, shift(kind, spcRead(at)))

fn modifyA(kind i64):
	dummyRead()
	spc.a = shift(kind, spc.a)

fn transfer(v i64):
	dummyRead()
	load(v)

# ---------- 16-bit ----------

fn readWord(at i64):
	lo = spcRead(at)
	spcIdle()
	lo | (spcRead(direct(at + 1)) << 8)

fn ya():
	(spc.y << 8) | spc.a

fn setYa(v i64):
	spc.a = v & 0xFF
	spc.y = (v >> 8) & 0xFF

fn stepWord(at i64, delta i64):
	lo = spcRead(at)
	spcWrite(at, (lo + delta) & 0xFF)
	hiAt = direct(at + 1)
	v = (((spcRead(hiAt) << 8) | lo) + delta) & 0xFFFF
	spcWrite(hiAt, v >> 8)
	setNZ16(v)

fn addWord(w i64):
	l = ya()
	sum = l + w
	spc.psw.c = sum > 0xFFFF
	spc.psw.v = ~(l ^ w) & (l ^ sum) & 0x8000 != 0
	spc.psw.h = (l ^ w ^ sum) & 0x1000 != 0
	setNZ16(sum)
	setYa(sum)

fn subtractWord(w i64):
	l = ya()
	diff = l - w
	spc.psw.c = diff >= 0
	spc.psw.v = (l ^ w) & (l ^ diff) & 0x8000 != 0
	spc.psw.h = (l ^ w ^ diff) & 0x1000 == 0
	setNZ16(diff)
	setYa(diff)

fn compareWord(at i64):
	lo = spcRead(at)
	w = lo | (spcRead(direct(at + 1)) << 8)
	spc.psw.c = ya() >= w
	setNZ16(ya() - w)

fn storeWord(at i64):
	spcRead(at)
	spcWrite(at, spc.a)
	spcWrite(direct(at + 1), spc.y)

fn multiply():
	dummyRead()
	loop 7:
		spcIdle()
	setYa(spc.y * spc.a)
	setNZ(spc.y)

# the quotient of YA by X in A, the remainder in Y, as the hardware gives it past 9 bits too
fn divide():
	dummyRead()
	loop 9:
		spcIdle()
	spc.zeroStepAt = spc.tick
	spcIdle()
	n = ya()
	x = spc.x
	spc.psw.h = (spc.y & 15) >= (x & 15)
	spc.psw.v = spc.y >= x
	if spc.y < x << 1:
		spc.a = (n / x) & 0xFF
		spc.y = n % x
	else:
		spc.a = (255 - (n - (x << 9)) / (256 - x)) & 0xFF
		spc.y = (x + (n - (x << 9)) % (256 - x)) & 0xFF
	setNZ(spc.a)

fn decimalAdjust(adding bool):
	spcIdle()
	spcIdle()
	a = spc.a
	if adding:
		if spc.psw.c or a > 0x99:
			a += 0x60
			spc.psw.c = true
		if spc.psw.h or a & 0x0F > 9: a += 6
	else:
		if not spc.psw.c or a > 0x99:
			a -= 0x60
			spc.psw.c = false
		if not spc.psw.h or a & 0x0F > 9: a -= 6
	spc.a = load(a & 0xFF)

# ---------- bits ----------

fn setBit(bit i64, on bool):
	at = dpAddr()
	v = spcRead(at)
	spcWrite(at, v | (1 << bit) if on else v & ~(1 << bit))

# the address of a bit (abs.b): the low 13 bits the byte, the top 3 the bit
fn bitAddr():
	w = absAddr()
	(w & 0x1FFF, w >> 13)

# OR1 /OR1 AND1 /AND1 EOR1 MOV1 on the carry (kinds 0-5)
fn carryBit(kind i64):
	at, bit = bitAddr()
	b = (spcRead(at) >> bit) & 1
	c = carry()
	match kind:
		0: c |= b
		1: c |= b ^ 1
		2: c &= b
		3: c &= b ^ 1
		4: c ^= b
		_: c = b
	spc.psw.c = c != 0
	if kind in [0, 1, 4]: spcIdle()

fn storeCarry():
	at, bit = bitAddr()
	v = spcRead(at)
	spcIdle()
	spcWrite(at, (v & ~(1 << bit)) | (carry() << bit))

fn invertBit():
	at, bit = bitAddr()
	spcWrite(at, spcRead(at) ^ (1 << bit))

fn testBits(clear bool):
	at = absAddr()
	v = spcRead(at)
	spcRead(at)
	spcWrite(at, v & ~spc.a if clear else v | spc.a)
	setNZ(spc.a - v)

# ---------- branches, calls, the stack ----------

fn branchIf(taken bool):
	offset = spcFetch()
	if not taken:
		spc.zeroStepAt = spc.tick
		return
	spcIdle()
	spcIdle()
	spc.pc = (spc.pc + signed(offset)) & 0xFFFF

# BBS/BBC, CBNE, DBNZ: the test's data, then the offset; taken, two internal cycles
fn branchAfter(taken bool):
	offset = spcFetch()
	if not taken: return
	spcIdle()
	spcIdle()
	spc.pc = (spc.pc + signed(offset)) & 0xFFFF

fn branchOnBit(bit i64, whenSet bool):
	v = spcRead(dpAddr())
	spcIdle()
	branchAfter((v & (1 << bit) != 0) == whenSet)

fn compareBranch(at i64):
	v = spcRead(at)
	spcIdle()
	branchAfter(spc.a != v)

fn decrementBranch():
	at = dpAddr()
	v = (spcRead(at) - 1) & 0xFF
	spcWrite(at, v)
	branchAfter(v != 0)

fn decrementYBranch():
	dummyRead()
	spcIdle()
	spc.y = (spc.y - 1) & 0xFF
	branchAfter(spc.y != 0)

fn push(v i64):
	spcWrite(0x100 | spc.sp, v)
	spc.sp = (spc.sp - 1) & 0xFF

fn pop():
	spc.sp = (spc.sp + 1) & 0xFF
	spcRead(0x100 | spc.sp)

fn pushPc():
	push(spc.pc >> 8)
	push(spc.pc & 0xFF)

fn pushValue(v i64):
	dummyRead()
	push(v)
	spcIdle()

fn popValue():
	dummyRead()
	spcIdle()
	pop()

fn readVector(at i64):
	lo = spcRead(at)
	spc.pc = lo | (spcRead((at + 1) & 0xFFFF) << 8)

fn tcall(n i64):
	dummyRead()
	spcIdle()
	pushPc()
	spcIdle()
	readVector(0xFFDE - 2 * n)

fn call():
	at = absAddr()
	spcIdle()
	pushPc()
	spcIdle()
	spcIdle()
	spc.pc = at

fn pcall():
	low = spcFetch()
	spcIdle()
	pushPc()
	spcIdle()
	spc.pc = 0xFF00 | low

fn brk():
	spcIdle()
	pushPc()
	push(u8(spc.psw))
	spcIdle()
	readVector(0xFFDE)
	spc.psw.b = true
	spc.psw.i = false

fn ret(withFlags bool):
	dummyRead()
	spcIdle()
	if withFlags: spc.psw = Psw(pop())
	lo = pop()
	spc.pc = lo | (pop() << 8)

fn jumpIndexed():
	at = absAddr()
	spcIdle()
	readVector((at + spc.x) & 0xFFFF)

# an instruction that sets a flag: its bus cycles, then the value the flag takes
fn flagOp(on bool):
	dummyRead()
	on

fn interruptFlag(on bool):
	dummyRead()
	spcIdle()
	on

fn halt(op i64):
	fail("the SPC700 halted (opcode 0x{op:02X} at 0x{spc.pc - 1:04X})")

# long: the instruction table, one line an opcode
fn otherInstruction(op i64):
	match op:
		0x00: dummyRead()
		0x0A: carryBit(0)
		0x0B: modify(0, dpAddr())
		0x0C: modify(0, absAddr())
		0x0D: pushValue(u8(spc.psw))
		0x0E: testBits(false)
		0x0F: brk()
		0x10: branchIf(not spc.psw.n)
		0x1A: stepWord(dpAddr(), -1)
		0x1B: modify(0, dpIndexed(spc.x))
		0x1C: modifyA(0)
		0x1D: spc.x = transfer((spc.x - 1) & 0xFF)
		0x1E: compare(spc.x, spcRead(absAddr()))
		0x1F: jumpIndexed()
		0x20: spc.psw.p = flagOp(false)
		0x2A: carryBit(1)
		0x2B: modify(1, dpAddr())
		0x2C: modify(1, absAddr())
		0x2D: pushValue(spc.a)
		0x2E: compareBranch(dpAddr())
		0x2F: branchIf(true)
		0x30: branchIf(spc.psw.n)
		0x3A: stepWord(dpAddr(), 1)
		0x3B: modify(1, dpIndexed(spc.x))
		0x3C: modifyA(1)
		0x3D: spc.x = transfer((spc.x + 1) & 0xFF)
		0x3E: compare(spc.x, spcRead(dpAddr()))
		0x3F: call()
		0x40: spc.psw.p = flagOp(true)
		0x4A: carryBit(2)
		0x4B: modify(2, dpAddr())
		0x4C: modify(2, absAddr())
		0x4D: pushValue(spc.x)
		0x4E: testBits(true)
		0x4F: pcall()
		0x50: branchIf(not spc.psw.v)
		0x5A: compareWord(dpAddr())
		0x5B: modify(2, dpIndexed(spc.x))
		0x5C: modifyA(2)
		0x5D: spc.x = transfer(spc.a)
		0x5E: compare(spc.y, spcRead(absAddr()))
		0x5F: spc.pc = absAddr()
		0x60: spc.psw.c = flagOp(false)
		0x6A: carryBit(3)
		0x6B: modify(3, dpAddr())
		0x6C: modify(3, absAddr())
		0x6D: pushValue(spc.y)
		0x6E: decrementBranch()
		0x6F: ret(false)
		0x70: branchIf(spc.psw.v)
		0x7A: addWord(readWord(dpAddr()))
		0x7B: modify(3, dpIndexed(spc.x))
		0x7C: modifyA(3)
		0x7D: spc.a = transfer(spc.x)
		0x7E: compare(spc.y, spcRead(dpAddr()))
		0x7F: ret(true)
		0x80: spc.psw.c = flagOp(true)
		0x8A: carryBit(4)
		0x8B: modify(4, dpAddr())
		0x8C: modify(4, absAddr())
		0x8D: spc.y = load(spcFetch())
		0x8E: spc.psw = Psw(popValue())
		0x8F: moveImmediate()
		0x90: branchIf(not spc.psw.c)
		0x9A: subtractWord(readWord(dpAddr()))
		0x9B: modify(4, dpIndexed(spc.x))
		0x9C: modifyA(4)
		0x9D: spc.x = transfer(spc.sp)
		0x9E: divide()
		0x9F: exchangeNibbles()
		0xA0: spc.psw.i = interruptFlag(true)
		0xAA: carryBit(5)
		0xAB: modify(5, dpAddr())
		0xAC: modify(5, absAddr())
		0xAD: compare(spc.y, spcFetch())
		0xAE: spc.a = popValue()
		0xAF: storeIncrement()
		0xB0: branchIf(spc.psw.c)
		0xBA: loadWord(readWord(dpAddr()))
		0xBB: modify(5, dpIndexed(spc.x))
		0xBC: modifyA(5)
		0xBD: moveToSp()
		0xBE: decimalAdjust(false)
		0xBF: loadIncrement()
		0xC0: spc.psw.i = interruptFlag(false)
		0xC4: store(dpAddr(), spc.a)
		0xC5: store(absAddr(), spc.a)
		0xC6: store(xAddr(), spc.a)
		0xC7: store(dpXIndirect(), spc.a)
		0xC8: compare(spc.x, spcFetch())
		0xC9: store(absAddr(), spc.x)
		0xCA: storeCarry()
		0xCB: store(dpAddr(), spc.y)
		0xCC: store(absAddr(), spc.y)
		0xCD: spc.x = load(spcFetch())
		0xCE: spc.x = popValue()
		0xCF: multiply()
		0xD0: branchIf(not spc.psw.z)
		0xD4: store(dpIndexed(spc.x), spc.a)
		0xD5: store(absIndexed(spc.x), spc.a)
		0xD6: store(absIndexed(spc.y), spc.a)
		0xD7: store(dpIndirectY(), spc.a)
		0xD8: store(dpAddr(), spc.x)
		0xD9: store(dpIndexed(spc.y), spc.x)
		0xDA: storeWord(dpAddr())
		0xDB: store(dpIndexed(spc.x), spc.y)
		0xDC: spc.y = transfer((spc.y - 1) & 0xFF)
		0xDD: spc.a = transfer(spc.y)
		0xDE: compareBranch(dpIndexed(spc.x))
		0xDF: decimalAdjust(true)
		0xE0: clearOverflow()
		0xE4: spc.a = load(spcRead(dpAddr()))
		0xE5: spc.a = load(spcRead(absAddr()))
		0xE6: spc.a = load(spcRead(xAddr()))
		0xE7: spc.a = load(spcRead(dpXIndirect()))
		0xE8: spc.a = load(spcFetch())
		0xE9: spc.x = load(spcRead(absAddr()))
		0xEA: invertBit()
		0xEB: spc.y = load(spcRead(dpAddr()))
		0xEC: spc.y = load(spcRead(absAddr()))
		0xED: complementCarry()
		0xEE: spc.y = popValue()
		0xF0: branchIf(spc.psw.z)
		0xF4: spc.a = load(spcRead(dpIndexed(spc.x)))
		0xF5: spc.a = load(spcRead(absIndexed(spc.x)))
		0xF6: spc.a = load(spcRead(absIndexed(spc.y)))
		0xF7: spc.a = load(spcRead(dpIndirectY()))
		0xF8: spc.x = load(spcRead(dpAddr()))
		0xF9: spc.x = load(spcRead(dpIndexed(spc.y)))
		0xFA: moveDirect()
		0xFB: spc.y = load(spcRead(dpIndexed(spc.x)))
		0xFC: spc.y = transfer((spc.y + 1) & 0xFF)
		0xFD: spc.y = transfer(spc.a)
		0xFE: decrementYBranch()
		_: halt(op)

fn moveImmediate():
	v = spcFetch()
	store(dpAddr(), v)

fn moveDirect():
	v = spcRead(dpAddr())
	spcWrite(dpAddr(), v)

fn moveToSp():
	dummyRead()
	spc.sp = spc.x

fn exchangeNibbles():
	dummyRead()
	spcIdle()
	spcIdle()
	spcIdle()
	spc.a = load(((spc.a >> 4) | (spc.a << 4)) & 0xFF)

fn clearOverflow():
	dummyRead()
	spc.psw.v = false
	spc.psw.h = false

fn complementCarry():
	dummyRead()
	spcIdle()
	spc.psw.c = not spc.psw.c

fn loadWord(w i64):
	setYa(w)
	setNZ16(w)

fn storeIncrement():
	at = xAddr()
	spcIdle()
	spcWrite(at, spc.a)
	spc.x = (spc.x + 1) & 0xFF

fn loadIncrement():
	at = xAddr()
	spc.a = load(spcRead(at))
	spcIdle()
	spc.x = (spc.x + 1) & 0xFF
