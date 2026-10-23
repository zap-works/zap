# A64's encodings (Arm ARM C4.1) decoded into Instr: the integer, branch, system and memory
# groups. A word the decoder does not know is Op.Unknown, which the interpreter stops at with its
# address and bits.

# `width` bits of w from bit `at`
pub fn bits(w i64, at i64, width i64) i64:
	(w >> at) & ((1 << width) - 1)

pub fn hasBit(w i64, at i64) bool:
	(w >> at) & 1 != 0

# the value of `width` bits from `at` read as a signed number
pub fn signedBits(w i64, at i64, width i64) i64:
	v = bits(w, at, width)
	v - (1 << width) if v >> (width - 1) != 0 else v

# a register field where 31 is the stack pointer
fn orSp(r i64):
	sp if r == 31 else r

# The instruction at pc whose bits are w.
pub fn decode(w i64, pc i64) Instr:
	op0 = bits(w, 25, 4)
	if op0 & 0b1110 == 0b1000: return dataImmediate(w, pc)
	if op0 & 0b1110 == 0b1010: return branchSystem(w, pc)
	if op0 & 0b0101 == 0b0100: return loadStore(w, pc)
	if op0 & 0b0111 == 0b0101: return dataRegister(w)
	if op0 & 0b0111 == 0b0111:
		return floatScalar(w) if hasBit(w, 28) and not hasBit(w, 30) else advancedSimd(w)
	Instr()

fn dataImmediate(w i64, pc i64):
	sf = hasBit(w, 31)
	rd = bits(w, 0, 5)
	rn = bits(w, 5, 5)
	match bits(w, 23, 3):
		0, 1:
			lo = bits(w, 29, 2)
			hi = signedBits(w, 5, 19)
			if hasBit(w, 31):
				return Instr(op = .Adr, rd, imm = (pc & ~0xFFF) + ((hi << 2 | lo) << 12))
			Instr(op = .Adr, rd, imm = pc + (hi << 2 | lo))
		2:
			imm = bits(w, 10, 12) << (12 if hasBit(w, 22) else 0)
			setFlags = hasBit(w, 29)
			Instr(
				op = .AddImm,
				rd = rd if setFlags else orSp(rd),
				rn = orSp(rn),
				imm,
				sf,
				setFlags,
				subtract = hasBit(w, 30)
			)
		4:
			mask = bitMask(hasBit(w, 22), bits(w, 16, 6), bits(w, 10, 6), sf) ?? return Instr()
			opc = bits(w, 29, 2)
			Instr(op = .LogicImm, rd = rd if opc == 3 else orSp(rd), rn, imm = mask, opc, sf)
		5:
			opc = bits(w, 29, 2)
			if opc == 1 or (not sf and hasBit(w, 22)): return Instr()
			Instr(op = .MoveWide, rd, imm = bits(w, 5, 16), shift = bits(w, 21, 2) * 16, opc, sf)
		6:
			if hasBit(w, 22) != sf or bits(w, 29, 2) == 3 or
				(not sf and (hasBit(w, 21) or hasBit(w, 15))):
				return Instr()
			Instr(
				op = .Bitfield,
				rd,
				rn,
				imm = bits(w, 16, 6),
				imm2 = bits(w, 10, 6),
				opc = bits(w, 29, 2),
				sf
			)
		3: Instr()   # add/sub with tags: not in v8.0
		_:
			if hasBit(w, 22) != sf or bits(w, 29, 2) != 0 or hasBit(w, 21) or
				(not sf and hasBit(w, 15)):
				return Instr()
			Instr(op = .Extract, rd, rn, rm = bits(w, 16, 5), imm = bits(w, 10, 6), sf)

# The mask a logical immediate's N:immr:imms stands for, none for a reserved one.
pub fn bitMask(n bool, immr i64, imms i64, sf bool) i64?:
	wmask, _ = try bitMasks(n, immr, imms, sf, true)
	wmask

# DecodeBitMasks: the element of imms+1 ones rotated right by immr, repeated over the width
# (wmask), and the element of (imms-immr)+1 ones repeated (tmask, a bitfield's); none for a
# reserved field. `immediate` refuses an element of all ones, as a logical immediate must.
pub fn bitMasks(n bool, immr i64, imms i64, sf bool, immediate bool) (i64, i64)?:
	combined = (64 if n else 0) | (~imms & 0x3F)
	if combined == 0: return none
	len = 63 - u64(combined).leadingZeros()
	size = 1 << len
	levels = size - 1
	s = imms & levels
	r = immr & levels
	if immediate and s == levels: return none
	if not sf and n: return none
	elemMask = (1 << size) - 1 if size < 64 else -1
	welem = ones(s + 1)
	if r != 0: welem = ((welem >> r) & (elemMask >> r)) | ((welem << (size - r)) & elemMask)
	telem = ones(((s - r) & levels) + 1)
	(replicated(welem, size, sf), replicated(telem, size, sf))

# n ones in the low bits
fn ones(n i64) i64:
	i64(u64(-1) >> (64 - n))

# an element of `size` bits repeated over 64 bits, then cut to 32 when not sf
fn replicated(elem i64, size i64, sf bool):
	out = elem
	width = size
	while width < 64:
		out |= out << width
		width *= 2
	out if sf else out & 0xFFFF_FFFF

fn branchSystem(w i64, pc i64):
	if bits(w, 26, 5) == 0b0_0101:
		return Instr(
			op = .BranchLink if hasBit(w, 31) else .Branch,
			imm = pc + signedBits(w, 0, 26) * 4
		)
	if bits(w, 25, 6) == 0b01_1010:
		return Instr(
			op = .CompareBranch,
			rd = bits(w, 0, 5),
			imm = pc + signedBits(w, 5, 19) * 4,
			opc = bits(w, 24, 1),
			sf = hasBit(w, 31)
		)
	if bits(w, 25, 6) == 0b01_1011:
		return Instr(
			op = .TestBranch,
			rd = bits(w, 0, 5),
			imm = pc + signedBits(w, 5, 14) * 4,
			imm2 = bits(w, 31, 1) << 5 | bits(w, 19, 5),
			opc = bits(w, 24, 1)
		)
	if w & 0xFF00_0010 == 0x5400_0000:
		return Instr(op = .BranchCond, imm = pc + signedBits(w, 5, 19) * 4, cond = bits(w, 0, 4))
	if w & 0xFF00_0000 == 0xD400_0000:
		match (bits(w, 21, 3), bits(w, 0, 5)):
			(0, 1): return Instr(op = .Svc, imm = bits(w, 5, 16))
			(1, 0): return Instr(op = .Brk, imm = bits(w, 5, 16))
			_: return Instr()
	if w & 0xFE1F_FC1F == 0xD61F_0000:
		rn = bits(w, 5, 5)
		match bits(w, 21, 4):
			0: return Instr(op = .BranchReg, rn)
			1: return Instr(op = .BranchLinkReg, rn)
			2: return Instr(op = .Return, rn)
			_: return Instr()
	if w & 0xFFC0_0000 == 0xD500_0000: return system(w)
	Instr()

fn system(w i64):
	rt = bits(w, 0, 5)
	if w & 0xFFFF_F01F == 0xD503_201F: return Instr(op = .Hint, imm = bits(w, 5, 7))
	if w & 0xFFFF_F0FF == 0xD503_305F: return Instr(op = .ClearExclusive)
	if w & 0xFFFF_F09F == 0xD503_309F: return Instr(op = .Barrier, opc = bits(w, 5, 3))
	if w & 0xFFF8_F01F == 0xD500_401F:
		return Instr(
			op = .WriteState,
			imm = bits(w, 8, 4),
			imm2 = bits(w, 16, 3) << 3 | bits(w, 5, 3)
		)
	if w & 0xFFF8_0000 == 0xD508_0000: return Instr(op = .System, rd = rt, imm = bits(w, 5, 14))
	if w & 0xFFF0_0000 == 0xD530_0000: return Instr(op = .ReadSystem, rd = rt, imm = bits(w, 5, 15))
	if w & 0xFFF0_0000 == 0xD510_0000:
		return Instr(op = .WriteSystem, rd = rt, imm = bits(w, 5, 15))
	Instr()

fn dataRegister(w i64):
	sf = hasBit(w, 31)
	rd = bits(w, 0, 5)
	rn = bits(w, 5, 5)
	rm = bits(w, 16, 5)
	if not hasBit(w, 28):
		if not sf and hasBit(w, 15) and not (hasBit(w, 24) and hasBit(w, 21)): return Instr()
		if not hasBit(w, 24):
			return Instr(
				op = .LogicShifted,
				rd,
				rn,
				rm,
				opc = bits(w, 29, 2),
				subtract = hasBit(w, 21),   # the second operand inverted
				shift = bits(w, 22, 2),
				amount = bits(w, 10, 6),
				sf
			)
		setFlags = hasBit(w, 29)
		if not hasBit(w, 21):
			if bits(w, 22, 2) == 3: return Instr()
			return Instr(
				op = .AddShifted,
				rd,
				rn,
				rm,
				shift = bits(w, 22, 2),
				amount = bits(w, 10, 6),
				sf,
				setFlags,
				subtract = hasBit(w, 30)
			)
		if bits(w, 10, 3) > 4 or bits(w, 22, 2) != 0: return Instr()
		return Instr(
			op = .AddExtended,
			rd = rd if setFlags else orSp(rd),
			rn = orSp(rn),
			rm,
			shift = bits(w, 13, 3),
			amount = bits(w, 10, 3),
			sf,
			setFlags,
			subtract = hasBit(w, 30)
		)
	match bits(w, 21, 4):
		0b0000:
			Instr(
				op = .AddCarry,
				rd,
				rn,
				rm,
				sf,
				setFlags = hasBit(w, 29),
				subtract = hasBit(w, 30)
			)
		0b0010:
			if not hasBit(w, 29) or hasBit(w, 10) or hasBit(w, 4): return Instr()
			Instr(
				op = .CondCompare,
				rn,
				rm,
				imm = bits(w, 0, 4),
				cond = bits(w, 12, 4),
				pair = hasBit(w, 11),   # rm is an immediate
				sf,
				subtract = hasBit(w, 30)
			)
		0b0100:
			if hasBit(w, 29) or hasBit(w, 11): return Instr()
			Instr(
				op = .CondSelect,
				rd,
				rn,
				rm,
				cond = bits(w, 12, 4),
				opc = bits(w, 30, 1) << 1 | bits(w, 10, 1),
				sf
			)
		0b0110:
			opc = bits(w, 10, 6)
			if hasBit(w, 29): return Instr()
			if hasBit(w, 30):
				if bits(w, 16, 5) != 0 or opc > 5 or (opc == 3 and not sf): return Instr()
				return Instr(op = .OneSource, rd, rn, opc, sf)
			crcWide = opc == 19 or opc == 23
			known = opc == 2 or opc == 3 or (opc >= 8 and opc <= 11) or
				(opc >= 16 and opc <= 23 and crcWide == sf)
			if not known: return Instr()
			Instr(op = .TwoSource, rd, rn, rm, opc, sf)
		_:
			opc = bits(w, 21, 3) << 1 | bits(w, 15, 1)
			if not hasBit(w, 24) or bits(w, 29, 2) != 0: return Instr()
			if not (opc in [0, 1] or (sf and opc in [2, 3, 4, 10, 11, 12])): return Instr()
			Instr(
				op = .ThreeSource,
				rd,
				rn,
				rm,
				ra = bits(w, 10, 5),
				opc = bits(w, 21, 3) << 1 | bits(w, 15, 1),
				sf
			)

fn loadStore(w i64, pc i64):
	rt = bits(w, 0, 5)
	rn = orSp(bits(w, 5, 5))
	vector = hasBit(w, 26)
	if bits(w, 24, 6) == 0b00_1000 and not vector: return exclusive(w, rt, rn)
	if bits(w, 27, 3) == 0b001 and vector: return vectorStructure(w, rt, rn)
	if bits(w, 27, 3) == 0b011 and bits(w, 24, 2) == 0:
		opc = bits(w, 30, 2)
		imm = pc + signedBits(w, 5, 19) * 4
		if vector: return Instr(op = .LoadLiteral, rd = rt, imm, size = 2 + opc, vector = true)
		match opc:
			0: Instr(op = .LoadLiteral, rd = rt, imm, size = 2, sf = false)
			1: Instr(op = .LoadLiteral, rd = rt, imm, size = 3)
			2: Instr(op = .LoadLiteral, rd = rt, imm, size = 2, signed = true)
			_: Instr(op = .Prefetch)
	elif bits(w, 27, 3) == 0b101: pairAccess(w, rt, rn, vector)
	elif bits(w, 27, 3) == 0b111: singleAccess(w, rt, rn, vector)
	else: Instr()

fn exclusive(w i64, rt i64, rn i64):
	size = bits(w, 30, 2)
	load = hasBit(w, 22)
	pair = hasBit(w, 21)
	ordered = hasBit(w, 15)
	if pair and size < 2: return Instr()
	if hasBit(w, 23):
		if pair: return Instr()
		return Instr(
			op = .LoadAcquire if load else .StoreRelease,
			rd = rt,
			rn,
			size,
			sf = size == 3
		)
	op = Op.LoadExclusive if load else Op.StoreExclusive
	Instr(
		op,
		rd = rt,
		rn,
		ra = bits(w, 10, 5) if pair else bits(w, 16, 5),
		rm = bits(w, 16, 5),
		size,
		sf = size == 3,
		acquire = ordered,
		pair
	)

fn pairAccess(w i64, rt i64, rn i64, vector bool):
	opc = bits(w, 30, 2)
	load = hasBit(w, 22)
	mode = [Mode.Offset, Mode.PostIndex, Mode.Offset, Mode.PreIndex][bits(w, 23, 2)]
	size = 2 + opc if vector else 2 + (opc >> 1)
	if opc == 3 or (not vector and opc == 1 and (not load or bits(w, 23, 2) == 0)): return Instr()
	Instr(
		op = .LoadPair if load else .StorePair,
		rd = rt,
		ra = bits(w, 10, 5),
		rn,
		imm = signedBits(w, 15, 7) << size,
		size,
		signed = not vector and opc == 1,
		sf = opc != 0 or vector,
		vector,
		mode
	)

fn singleAccess(w i64, rt i64, rn i64, vector bool):
	size = bits(w, 30, 2)
	opc = bits(w, 22, 2)
	mode = Mode.Offset
	imm = 0
	rm = 0
	shift = 0
	amount = 0
	if hasBit(w, 24):
		if vector and opc >= 2: size = 4
		imm = bits(w, 10, 12) << size
	elif not hasBit(w, 21):
		imm = signedBits(w, 12, 9)
		mode = [Mode.Offset, Mode.PostIndex, Mode.Offset, Mode.PreIndex][bits(w, 10, 2)]
		if vector and opc >= 2: size = 4
	elif bits(w, 10, 2) == 2:
		mode = .RegisterOffset
		rm = bits(w, 16, 5)
		shift = bits(w, 13, 3)
		if vector and opc >= 2: size = 4
		amount = size if hasBit(w, 12) else 0
	else:
		return Instr()
	if vector:
		return Instr(
			op = .Load if opc & 1 != 0 else .Store,
			rd = rt,
			rn,
			rm,
			imm,
			size,
			vector = true,
			mode,
			shift,
			amount
		)
	if opc == 0:
		return Instr(op = .Store, rd = rt, rn, rm, imm, size, sf = size == 3, mode, shift, amount)
	if opc == 1:
		return Instr(op = .Load, rd = rt, rn, rm, imm, size, sf = size == 3, mode, shift, amount)
	if size == 3:
		unprivileged = not hasBit(w, 24) and not hasBit(w, 21) and bits(w, 10, 2) == 2
		prefetch = opc == 2 and mode != .PreIndex and mode != .PostIndex and not unprivileged
		return Instr(op = .Prefetch) if prefetch else Instr()
	if size == 2 and opc == 3: return Instr()
	Instr(op = .Load, rd = rt, rn, rm, imm, size, signed = true, sf = opc == 2, mode, shift, amount)
