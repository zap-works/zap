# What the Advanced SIMD floating-point instructions do (arm64/vectorfloat.zap decodes them):
# each lane goes through the scalar operations of float.zap, so rounding, NaNs and FPSR's flags
# are the same as the scalar instructions'.

import recomp.switch.arm64

# a lane of ones when the comparison holds
fn comparisonLane(holds bool, bits i64):
	laneMask(bits) if holds else 0

# the lane operation of the instruction on x and y (acc the destination's lane, fmla's addend)
fn floatLane(mut c Cpu, i arm64.Instr, f Fmt, x u64, y u64, acc u64) u64:
	bits = f.width()
	match i.fop:
		MulX: c.fpMulX(f, x, y)
		Abd: c.fpAdd(f, x, y, true) & ~f.signBit()
		RecipStep: c.fpRecipStep(f, x, y)
		RsqrtStep: c.fpRsqrtStep(f, x, y)
		MulAcc: c.fpMulAdd(f, acc, x, y)
		MulSub: c.fpMulAdd(f, acc, x ^ f.signBit(), y)
		CompareEq: comparisonLane(c.fpCompare(f, x, y, false) == 0b0110, bits)
		CompareGe: comparisonLane(c.compareHolds(f, x, y, true), bits)
		CompareGt: comparisonLane(c.compareHolds(f, x, y, false), bits)
		CompareLe: comparisonLane(c.compareHolds(f, y, x, true), bits)
		CompareLt: comparisonLane(c.compareHolds(f, y, x, false), bits)
		AbsGe: comparisonLane(c.compareHolds(f, x & ~f.signBit(), y & ~f.signBit(), true), bits)
		AbsGt: comparisonLane(c.compareHolds(f, x & ~f.signBit(), y & ~f.signBit(), false), bits)
		_: c.fpArith(f, i.fop, x, y)

# x greater than y (or equal), a NaN raising invalid
fn compareHolds(mut c Cpu, f Fmt, x u64, y u64, orEqual bool):
	flags = c.fpCompare(f, x, y, true)
	flags == 0b0010 or (orEqual and flags == 0b0110)

# the operands of lane k of n for an operation on a and b, or on adjacent lanes when pairwise
fn operandsAt(pair bool, a Vec, b Vec, bits i64, n i64, k i64):
	if not pair: return (a.lane(bits, k), b.lane(bits, k))
	half = n / 2
	from = a if k < half else b
	j = 2 * (k % half)
	(from.lane(bits, j), from.lane(bits, j + 1))

# the lanes of a and b operated on as the instruction says, written to rd
pub fn floatLanes(mut c Cpu, i arm64.Instr, a Vec, b Vec):
	f = fmtOf(i.size)
	bits = f.width()
	n = i.laneCount(bits)
	d = c.vecRead(i.rd)
	out = Vec()
	for k in 0..n:
		x, y = operandsAt(i.pair, a, b, bits, n, k)
		out.setLane(bits, k, c.floatLane(i, f, x, y, d.lane(bits, k)))
	c.vecWrite(i.rd, out, i.q)

pub fn floatSame(mut c Cpu, i arm64.Instr):
	c.floatLanes(i, c.vecRead(i.rn), c.vecRead(i.rm))

# the by element forms: b is the lane repeated over a register
pub fn floatIndexed(mut c Cpu, i arm64.Instr):
	bits = fmtOf(i.size).width()
	b = replicated(c.vecRead(i.rm).lane(bits, i.index), bits)
	c.floatLanes(i, c.vecRead(i.rn), b)

# one lane of the single-source operations; amount the fraction bits of a fixed-point conversion
fn unaryLane(mut c Cpu, i arm64.Instr, f Fmt, x u64) u64:
	match i.fop:
		Sqrt: c.fpSqrt(f, x)
		Round: c.fpRoundBy(f, i.opc, x)
		ToInt: c.fpToInt(f, x, i.amount, i.opc, i.signed, f.width())
		FromInt: c.fpFromInt(f, x, i.signed, f.width(), i.amount)
		RecipEstimate: c.fpRecipEstimate(f, x)
		RsqrtEstimate: c.fpRsqrtEstimate(f, x)
		RecipExponent: c.fpRecipExponent(f, x)
		UnsignedRecipEstimate: unsignedRecipEstimate(x, false)
		UnsignedRsqrtEstimate: unsignedRecipEstimate(x, true)
		_: c.floatLane(i, f, x, 0, 0)

# FCVTL, FCVTL2: the lanes of one half converted to the format twice as wide
fn floatWiden(mut c Cpu, i arm64.Instr, a Vec):
	to = fmtOf(i.size)
	from = fmtOf(3 if i.size == 0 else 0)
	n = 64 / from.width()
	out = Vec()
	for k in 0..n:
		out.setLane(
			to.width(),
			k,
			c.fpConvert(from, to, a.lane(from.width(), k + (n if i.q else 0)))
		)
	c.vecWrite(i.rd, out, true)

# FCVTN, FCVTN2, FCVTXN: the lanes converted to the format half as wide, into one half of rd
fn floatNarrow(mut c Cpu, i arm64.Instr, a Vec):
	from = fmtOf(i.size)
	to = fmtOf(3 if i.size == 0 else 0)
	mode = roundOdd if i.fop == .NarrowOdd else c.rounding()
	out = Vec()
	for k in 0..1 if i.scalar else 64 / to.width():
		out.setLane(to.width(), k, c.fpConvertBy(from, to, a.lane(from.width(), k), mode))
	c.writeNarrow(i, out)

pub fn floatUnary(mut c Cpu, i arm64.Instr):
	a = c.vecRead(i.rn)
	match i.fop:
		Widen: c.floatWiden(i, a)
		Narrow, NarrowOdd: c.floatNarrow(i, a)
		_:
			f = fmtOf(i.size)
			out = Vec()
			for k in 0..laneCount(i, f.width()):
				out.setLane(f.width(), k, c.unaryLane(i, f, a.lane(f.width(), k)))
			c.vecWrite(i.rd, out, i.q)

# FMAXNMV, FMINNMV, FMAXV, FMINV, and the scalar pairwise ones: the lanes combined two by two
pub fn floatAcross(mut c Cpu, i arm64.Instr):
	f = fmtOf(i.size)
	a = c.vecRead(i.rn)
	values = (0..2 if i.scalar else 4).map(a.lane(f.width(), it))
	while values.len > 1:
		next = []
		for k in 0..values.len / 2:
			next.push(c.fpArith(f, i.fop, values[2 * k], values[2 * k + 1]))
		values = next
	c.vecWrite(i.rd, Vec(lo = values[0]), false)
