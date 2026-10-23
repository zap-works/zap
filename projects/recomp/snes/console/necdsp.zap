# The NEC uPD77C25 (DSP-1 to DSP-4) and uPD96050 (ST010, ST011) a cartridge carries, run from
# the chip's own firmware (the player's dump: dsp1b.rom and the like, its program's 24-bit words
# then its data's 16-bit ones, as Mesen 2 reads them) as Mesen 2 runs it: lazily, each access of
# the 65816 first running the chip up to the master clock at its clock rate; a wait for the CPU
# to read or write (RQM) skipped until it does.

import fs
import recomp.snes.cartridge

pub mut necMapped = false
mut necRegisterMask = 0x4000
mut necSt01x = false
mut necRate = 7_600_000.0
mut necProgram u32[] = []
mut necData u16[] = []
mut necRam u16[] = []
mut necStack u16[] = zeros(8)
mut necStackMask = 3

# its registers: the accumulators and their flags (carry, zero, sign 0 and 1, overflow 0 and 1
# as bits 0-5), the multiplier's K, L and its result M, N, the pointers, the transfer registers
mut nA = 0
mut nB = 0
mut nFlagsA = 0
mut nFlagsB = 0
mut nK = 0
mut nL = 0
mut nM = 0
mut nN = 0
mut nPC = 0
mut nRP = 0
mut nDP = 0
mut nSP = 0
mut nDR = 0
mut nSR = 0
mut nTR = 0
mut nTRB = 0
mut nSerialOut = 0
mut nCycles i64 = 0
mut nOp = 0
mut nInRqmLoop = false

flagCarry = 1
flagZero = 2
flagSign0 = 4
flagSign1 = 8
flagOverflow0 = 16
flagOverflow1 = 32

srRqm = 0x8000          # request for master: DR ready for the 65816
srDrs = 0x1000          # the 16-bit transfer's first byte done
srDrc = 0x0400          # 8-bit transfers
srSoc = 0x0800
srSic = 0x0200

# The chip the cartridge carries, its firmware found beside the cartridge's dump (where
# tools/gather.zap puts both), beside a released program, or in --firmware's dir. The DSP-1 runs
# its rewrite (dsp1.zap), its firmware needed only by the test that holds the rewrite to it;
# another DSP without its firmware stops the program.
fn startChip(romPath str):
	chip = cartridgeHeader.chip.copy()
	if not (chip in ["dsp1", "dsp1b", "dsp2", "dsp3", "dsp4", "st010", "st011"]): return
	if chip.startsWith("dsp1"):
		rewriteNec(chip)
		return
	file = firmwareFile("{chip}.rom", romPath) ??
		fail("{cartridgeHeader.title} carries a {chip}: its firmware {chip}.rom is needed (--firmware <dir>)")
	loadNec(chip, file)

# The chip `chip` ("dsp1b", "st010"...) ready to run its firmware from `file`, mapped where the
# cartridge's map (cartridge.hirom) puts it.
# the chip's RAM, stack and registers (its program and data are the firmware's)
fn necFields(mut f StateFile):
	f.wordList(necRam)
	f.wordList(necStack)
	nA = f.int(nA)
	nB = f.int(nB)
	nFlagsA = f.int(nFlagsA)
	nFlagsB = f.int(nFlagsB)
	nK = f.int(nK)
	nL = f.int(nL)
	nM = f.int(nM)
	nN = f.int(nN)
	nPC = f.int(nPC)
	nRP = f.int(nRP)
	nDP = f.int(nDP)
	nSP = f.int(nSP)
	nDR = f.int(nDR)
	nSR = f.int(nSR)
	nTR = f.int(nTR)
	nTRB = f.int(nTRB)
	nSerialOut = f.int(nSerialOut)
	nCycles = f.int(nCycles)
	nOp = f.int(nOp)
	nInRqmLoop = f.isSet(nInRqmLoop)

pub fn loadNec(chip str, file str):
	necSt01x = chip.startsWith("st")
	programBytes = 0xC000 if necSt01x else 0x1800
	dataBytes = 0x1000 if necSt01x else 0x800
	bytes = fs.readBytes(file) ?? fail("cannot read {file}: {error}")
	if bytes.len != programBytes + dataBytes:
		fail("{file} is {bytes.len} bytes, not {programBytes + dataBytes}")
	necProgram = zeros(programBytes / 3)
	for i in 0..necProgram.len:
		necProgram[i] = bytes[3 * i] | (u32(bytes[3 * i + 1]) << 8) | (
			u32(bytes[3 * i + 2]) << 16
		)
	necData = zeros(dataBytes / 2)
	for i in 0..necData.len:
		necData[i] = bytes[programBytes + 2 * i] | (u16(bytes[programBytes + 2 * i + 1]) << 8)
	necRam = zeros(0x800 if necSt01x else 0x100)
	necStack = zeros(8 if necSt01x else 4)
	necStackMask = necStack.len - 1
	necRate = 11_000_000.0 if chip == "st010" else 22_000_000.0 if chip == "st011" else 7_600_000.0
	necRegisterMask = 0x0001 if necSt01x else 0x1000 if cartridge.hirom else 0x4000
	necMapped = true
	necRewritten = false

fn firmwareFile(name str, romPath str) str?:
	dirs = [
		(args.option("--firmware") ?? "").copy(),
		fs.dirOf(romPath).copy(),
		fs.dirOf(exePath()).copy()
	]
	for dir in dirs:
		if dir.isEmpty: continue
		path = fs.join(dir, name)
		if fs.exists(path): return path
	none

# whether the 65816's address is the chip's (its registers, an ST01x's RAM)
fn isNecAddress(bank u32, off n32):
	if necSt01x:
		return off < 0x1000 and
			(bank == 0x60 or bank == 0xE0 or bank & 0x7F >= 0x68 and bank & 0x7F <= 0x6F)
	if cartridge.hirom: return bank & 0x7F < 0x20 and off >= 0x6000 and off < 0x8000
	(bank & 0x7F >= 0x30 and bank & 0x7F < 0x40 and off >= 0x8000) or
		(bank & 0x7F >= 0x60 and bank & 0x7F < 0x70 and off < 0x8000)

fn isNecRam(addr u32):
	necSt01x and addr & 0x0F_0000 >= 0x08_0000

fn necRead(addr u32) u8:
	necRun()
	if isNecRam(addr):
		w = necRam[(addr >> 1) & u32(len - 1)]
		return u8.wrap(w >> 8) if addr & 1 != 0 else u8.wrap(w)
	if addr & u32(necRegisterMask) != 0: return u8.wrap(nSR >> 8)
	nInRqmLoop = false
	if nSR & srDrc != 0:
		nSR &= ~srRqm
		rwClearedAt = nCycles
		return u8.wrap(nDR)
	if nSR & srDrs != 0:
		nSR &= ~(srRqm | srDrs)
		rwClearedAt = nCycles
		return u8.wrap(nDR >> 8)
	nSR |= srDrs
	u8.wrap(nDR)

fn necWrite(addr u32, v u8):
	necRun()
	if isNecRam(addr):
		at = i64((addr >> 1) & u32(necRam.len - 1))
		w = i64(necRam[at])
		necRam[at] = u16.wrap(
			(w & 0xFF) | (i64(v) << 8) if addr & 1 != 0 else (w & 0xFF00) | i64(v)
		)
		return
	if addr & u32(necRegisterMask) != 0: return
	nInRqmLoop = false
	if nSR & srDrc != 0:
		nSR &= ~srRqm
		rwClearedAt = nCycles
		nDR = (nDR & 0xFF00) | i64(v)
	elif nSR & srDrs != 0:
		nSR &= ~(srRqm | srDrs)
		rwClearedAt = nCycles
		nDR = (nDR & 0xFF) | (i64(v) << 8)
	else:
		nSR |= srDrs
		nDR = (nDR & 0xFF00) | i64(v)

# the chip run up to the master clock now, an instruction a cycle of its clock
fn necRun():
	target = i64(cycles * (necRate / masterRateNow()))   # the CPU's time at its access
	if necRewritten:
		rewriteRun(target)
		return
	if nInRqmLoop:
		nCycles = target
		return
	while nCycles < target:
		nOp = necProgram[nPC & (len - 1)]
		nPC += 1
		match nOp & 0xC0_0000:
			0x00_0000: necExec()
			0x40_0000:
				necExec()
				nSP = (nSP - 1) & necStackMask
				nPC = necStack[nSP]
			0x80_0000: necJump()
			_: necLoad(nOp & 0x0F, (nOp >> 6) & 0xFFFF)
		product = i64(i16.wrap(nK)) * i64(i16.wrap(nL))
		nM = (product >> 15) & 0xFFFF
		nN = (product << 1) & 0xFFFF
		nCycles += 1

fn necRom(at i64) i64:
	necData[at & (len - 1)]

fn necRamAt(at i64) i64:
	necRam[at & (len - 1)]

fn necExec():
	alu = (nOp >> 16) & 0x0F
	source = necSource((nOp >> 4) & 0x0F)
	if alu != 0: necAlu(alu, source)
	dest = nOp & 0x0F
	necLoad(dest, source)
	if dest != 4: necStepDp()
	if (nOp >> 8) & 1 != 0 and dest != 5: nRP = (nRP - 1) & 0xFFFF

fn necStepDp():
	dp = nDP
	match (nOp >> 13) & 3:
		1: dp = (dp & 0xF0) | ((dp + 1) & 0x0F)
		2: dp = (dp & 0xF0) | ((dp - 1) & 0x0F)
		3: dp &= 0xF0
		_: pass
	nDP = (dp ^ (((nOp >> 9) & 0x0F) << 4)) & 0xFFFF

fn accFlags(useB bool):
	nFlagsB if useB else nFlagsA

fn accValue(useB bool):
	nB if useB else nA

# the ALU's second operand, as bits 20-21 pick it: RAM at DP, the source, M or N
fn aluOperand(source i64):
	match (nOp >> 20) & 3:
		0: necRamAt(nDP)
		1: source
		2: nM
		_: nN

# the ALU's operation on the accumulator and the operand
fn aluResult(op i64, acc i64, p i64, carry i64):
	match op:
		1: acc | p
		2: acc & p
		3: acc ^ p
		4: acc - p
		5: acc + p
		6: acc - p - carry
		7: acc + p + carry
		8: acc - 1
		9: acc + 1
		10: ~acc
		11: (acc >> 1) | (acc & 0x8000)
		12: (acc << 1) | carry
		13: (acc << 2) | 3
		14: (acc << 4) | 0x0F
		15: (acc << 8) | (acc >> 8)
		_: 0

fn hasFlag(flags i64, bit i64):
	flags & bit != 0

# The ALU on accumulator A or B (bit 15 of the instruction) with the operand bits 20-21 pick.
fn necAlu(op i64, source i64):
	useB = (nOp >> 15) & 1 != 0
	flags = accFlags(useB)
	acc = accValue(useB)
	otherCarry = accFlags(not useB) & flagCarry
	p = aluOperand(source)
	result = aluResult(op, acc, p, otherCarry) & 0xFFFF
	f = flags & ~(flagZero | flagSign0)
	if result == 0: f |= flagZero
	if result & 0x8000 != 0: f |= flagSign0
	if not hasFlag(flags, flagOverflow1):
		f = (f & ~flagSign1) | (flagSign1 if hasFlag(f, flagSign0) else 0)
	match op:
		4, 5, 6, 7, 8, 9:
			q = 1 if op == 8 or op == 9 else p   # inc and dec add or take 1
			overflow = (acc ^ result) & (q ^ (result if op & 1 != 0 else acc))
			o0 = overflow & 0x8000 != 0
			o1 = hasFlag(f, flagOverflow1)
			if o0 and o1:
				o1 = hasFlag(f, flagSign0) == hasFlag(f, flagSign1)
			else:
				o1 = o1 or o0
			carry = (acc ^ q ^ result ^ overflow) & 0x8000 != 0
			f &= ~(flagOverflow0 | flagOverflow1 | flagCarry)
			if o0: f |= flagOverflow0
			if o1: f |= flagOverflow1
			if carry: f |= flagCarry
		11:
			f &= ~(flagOverflow0 | flagOverflow1 | flagCarry)
			if acc & 1 != 0: f |= flagCarry
		12:
			f &= ~(flagOverflow0 | flagOverflow1 | flagCarry)
			if acc & 0x8000 != 0: f |= flagCarry
		_: f &= ~(flagOverflow0 | flagOverflow1 | flagCarry)
	if useB:
		nB = result
		nFlagsB = f
	else:
		nA = result
		nFlagsA = f

fn necJump():
	bank = nOp & 3
	address = (nOp >> 2) & 0x7FF
	target = (nPC & 0x2000) | (bank << 11) | address
	kind = (nOp >> 13) & 0x1FF
	taken = false
	match kind:
		0x00: nPC = nSerialOut
		0x100: nPC = target & ~0x2000
		0x101: nPC = target | 0x2000
		0x140, 0x141:
			necStack[nSP] = u16.wrap(nPC)
			nSP = (nSP + 1) & necStackMask
			nPC = (target | 0x2000) if kind == 0x141 else target & ~0x2000
		_: taken = necCondition(kind)
	if taken:
		if nPC - 1 == target and (kind == 0xBC or kind == 0xBE): nInRqmLoop = true   # a wait on RQM
		nPC = target

# a conditional jump's test: the flags of A or B, DP's low nibble, or the status bits
fn necCondition(kind i64):
	if kind >= 0x80 and kind < 0xB0:
		flags = nFlagsB if kind & 4 != 0 else nFlagsA
		bit = match (kind - 0x80) >> 3:
			0: flagCarry
			1: flagZero
			2: flagOverflow0
			3: flagOverflow1
			4: flagSign0
			_: flagSign1
		return hasFlag(flags, bit) == (kind & 2 != 0)
	match kind:
		0xB0: nDP & 0x0F == 0
		0xB1: nDP & 0x0F != 0
		0xB2: nDP & 0x0F == 0x0F
		0xB3: nDP & 0x0F != 0x0F
		0xB4: nSR & srSic == 0
		0xB6: nSR & srSic != 0
		0xB8: nSR & srSoc == 0
		0xBA: nSR & srSoc != 0
		0xBC: nSR & srRqm == 0
		0xBE: nSR & srRqm != 0
		_: false

fn necLoad(dest i64, value i64):
	v = value & 0xFFFF
	match dest:
		1: nA = v
		2: nB = v
		3: nTR = v
		4: nDP = v
		5: nRP = v
		6:
			nDR = v
			nSR |= srRqm
		7: nSR = (nSR & 0x907C) | (v & ~0x907C & 0xFFFF)
		8, 9: nSerialOut = v
		10: nK = v
		11:
			nK = v
			nL = necRom(nRP)
		12:
			nL = v
			nK = necRamAt(nDP | 0x40)
		13: nL = v
		14: nTRB = v
		15: necRam[nDP & (len - 1)] = u16.wrap(v)
		_: pass

fn necSource(source i64):
	match source:
		0: nTRB
		1: nA
		2: nB
		3: nTR
		4: nDP
		5: nRP
		6: necRom(nRP)
		7: 0x8000 - (1 if hasFlag(nFlagsA, flagSign1) else 0)
		8:
			nSR |= srRqm
			nDR
		9: nDR
		10: nSR
		11, 12: 0   # the serial input: nothing on a cartridge
		13: nK
		14: nL
		_: necRamAt(nDP)
