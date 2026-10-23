# A64's scalar floating-point group (Arm ARM C4.1.6, op0 x0x1): data processing of one, two and
# three sources, compares, conditional selects and compares, immediates, and the conversions
# between floats and integers. `size` is the type field (0 single, 1 double, 3 half, which only
# fcvt takes in v8.0); rd, rn, rm and ra are scalar registers, except a conversion's general side.

pub type FloatOp:
	None
	Move   # fmov
	Abs
	Neg
	Sqrt
	Convert   # fcvt from size to the type in opc
	Round   # frint*: opc 0 n, 1 p, 2 m, 3 z, 4 a, 5 x, 6 i
	Add
	Sub
	Mul
	NegMul
	Div
	Max
	Min
	MaxNum
	MinNum
	MulAdd   # opc is o1:o0: fmadd, fmsub, fnmadd, fnmsub (rd = ra + rn * rm, negated as said)
	Compare   # fcmp, fcmpe (setFlags: signals on a quiet NaN); pair: against zero
	CondCompare   # fccmp, fccmpe; imm the flags when the condition fails
	Select
	Immediate   # imm the value's bits
	ToGeneral   # fmov to a general register; index 1 the high half of a vector
	FromGeneral
	ToInt   # fcvt[nmpaz][su]: opc the mode as frint's, signed; imm2 the fraction bits
	FromInt   # scvtf, ucvtf
	MulX   # the vector forms: fmulx, which gives 2.0 for infinity times zero
	Abd   # |a - b|
	MulAcc   # fmla: rd = rd + rn * rm
	MulSub   # fmls
	RecipStep   # frecps
	RsqrtStep   # frsqrts
	CompareEq   # a lane of ones where the comparison holds (also against zero)
	CompareGe
	CompareGt
	CompareLe   # against zero only
	CompareLt
	AbsGe   # facge, facgt
	AbsGt
	RecipEstimate   # frecpe
	RsqrtEstimate   # frsqrte
	RecipExponent   # frecpx
	Widen   # fcvtl: half to single or single to double
	Narrow   # fcvtn
	NarrowOdd   # fcvtxn: double to single, round to odd
	UnsignedRecipEstimate   # urecpe, ursqrte: the integer estimates of 32-bit lanes
	UnsignedRsqrtEstimate

fn floatInstr(op FloatOp, w i64):
	Instr(
		op = .Float,
		fop = op,
		rd = bits(w, 0, 5),
		rn = bits(w, 5, 5),
		rm = bits(w, 16, 5),
		size = bits(w, 22, 2)
	)

# The scalar FP instruction w, Op.Unknown when it is none the decoder knows.
fn floatScalar(w i64):
	if hasBit(w, 29): return Instr()
	ftype = bits(w, 22, 2)
	if hasBit(w, 24):
		if hasBit(w, 31) or ftype > 1: return Instr()
		i = floatInstr(.MulAdd, w)
		i.ra = bits(w, 10, 5)
		i.opc = bits(w, 21, 1) << 1 | bits(w, 15, 1)
		return i
	if not hasBit(w, 21) or bits(w, 10, 6) == 0: return floatConversion(w)
	if hasBit(w, 31): return Instr()
	if bits(w, 10, 5) == 0b1_0000: return floatOneSource(w)
	if ftype > 1: return Instr()
	if bits(w, 10, 4) == 0b1000: return floatCompare(w)
	if bits(w, 10, 3) == 0b100: return floatImmediate(w)
	floatTwoSource(w)

fn floatTwoSource(w i64):
	kind = bits(w, 10, 2)
	if kind == 0: return Instr()
	if kind == 1:
		i = floatInstr(.CondCompare, w)
		i.cond = bits(w, 12, 4)
		i.imm = bits(w, 0, 4)
		i.setFlags = hasBit(w, 4)
		i.rd = 0
		return i
	if kind == 3:
		i = floatInstr(.Select, w)
		i.cond = bits(w, 12, 4)
		return i
	op = match bits(w, 12, 4):
		0: FloatOp.Mul
		1: FloatOp.Div
		2: FloatOp.Add
		3: FloatOp.Sub
		4: FloatOp.Max
		5: FloatOp.Min
		6: FloatOp.MaxNum
		7: FloatOp.MinNum
		8: FloatOp.NegMul
		_: FloatOp.None
	if op == .None: return Instr()
	op.floatInstr(w)

# fmov, fabs, fneg, fsqrt, fcvt and frint*: opcode (bits 20:15)
fn floatOneSource(w i64):
	opcode = bits(w, 15, 6)
	ftype = bits(w, 22, 2)
	if opcode >> 2 == 1:
		to = opcode & 3
		if ftype == 2 or to == 2 or to == ftype: return Instr()
		i = floatInstr(.Convert, w)
		i.opc = to
		return i
	if ftype > 1: return Instr()
	op = match opcode:
		0: FloatOp.Move
		1: FloatOp.Abs
		2: FloatOp.Neg
		3: FloatOp.Sqrt
		8, 9, 10, 11, 12, 14, 15: FloatOp.Round
		_: FloatOp.None
	if op == .None: return Instr()
	i = op.floatInstr(w)
	if op == .Round: i.opc = {14: 5, 15: 6}.get(opcode) ?? opcode - 8
	i

fn floatCompare(w i64):
	if bits(w, 14, 2) != 0 or bits(w, 0, 3) != 0: return Instr()
	i = floatInstr(.Compare, w)
	i.rd = 0
	i.setFlags = hasBit(w, 4)
	i.pair = hasBit(w, 3)
	i

# imm the 8-bit immediate, which cpu/float.zap expands in the type's format
fn floatImmediate(w i64):
	if bits(w, 5, 5) != 0: return Instr()
	i = floatInstr(.Immediate, w)
	i.imm = bits(w, 13, 8)
	i

# the conversions between a float and an integer or fixed-point, and fmov to and from a general
# register: sf, rmode (bits 20:19), opcode (18:16), and the scale of a fixed-point one
fn floatConversion(w i64):
	sf = hasBit(w, 31)
	rmode = bits(w, 19, 2)
	opcode = bits(w, 16, 3)
	fixed = not hasBit(w, 21)
	if fixed and not sf and not hasBit(w, 15): return Instr()
	i = floatInstr(.ToInt, w)
	i.sf = sf
	i.signed = opcode & 1 == 0
	if fixed: i.imm2 = 64 - bits(w, 10, 6)
	if opcode >= 6: return i.floatMove(rmode, opcode & 1 == 1) if not fixed else Instr()
	if i.size > 1: return Instr()
	match opcode >> 1:
		0:
			if fixed and rmode != 3: return Instr()
			i.opc = rmode
		1:
			if rmode != 0: return Instr()
			i.fop = .FromInt
		_:
			if rmode != 0 or fixed: return Instr()
			i.opc = 4
	i

# fmov between a general register and the scalar of the sf's width, or a vector's high half
fn floatMove(source Instr, rmode i64, fromGeneral bool):
	i = source
	i.fop = .FromGeneral if fromGeneral else .ToGeneral
	if rmode == 0 and i.size == (1 if i.sf else 0): return i
	if rmode == 1 and i.size == 2 and i.sf:
		i.size = 1
		i.index = 1
		return i
	Instr()
