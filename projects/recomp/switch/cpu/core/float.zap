# What A64's scalar floating-point instructions do (arm64/float.zap decodes them) and the
# operations they are made of (Arm ARM, J1: FPAdd, FPMul, FPMulAdd, FPToFixed...). An operation
# takes the format and the operands' bits and returns the result's bits, raising its flags in
# FPSR; the rounding mode, flush-to-zero and default-NaN choices are FPCR's. The Advanced SIMD
# operations on lanes call the same ones.

import recomp.switch.arm64

# how a compares to b, neither a NaN: -1, 0 or 1
pub fn compareValues(a Unpacked, b Unpacked) i64:
	negA = a.sign and a.kind != .Zero
	negB = b.sign and b.kind != .Zero
	if negA != negB: return -1 if negA else 1
	order = a.compareMagnitudes(b)
	-order if negA else order

fn compareMagnitudes(a Unpacked, b Unpacked):
	if a.kind == .Number and b.kind == .Number:
		topA = a.e + 63 - a.m.leadingZeros()
		topB = b.e + 63 - b.m.leadingZeros()
		if topA != topB: return -1 if topA < topB else 1
		ma = a.m << a.m.leadingZeros()
		mb = b.m << b.m.leadingZeros()
		if ma == mb: return 0
		return -1 if ma < mb else 1
	rankA = a.kind.kindRank()
	rankB = b.kind.kindRank()
	if rankA == rankB: return 0
	-1 if rankA < rankB else 1

fn kindRank(k Kind):
	match k:
		Zero: 0
		Number: 1
		_: 2

# a + b, or a - b
pub fn fpAdd(mut c Cpu, f Fmt, a u64, b u64, subtract bool) u64:
	x = c.unpack(f, a)
	y = c.unpack(f, b)
	if hasNan([x, y]): return c.nanResult(f, [x, y])
	if subtract: y.sign = not y.sign
	if x.kind == .Infinity or y.kind == .Infinity:
		if x.kind == .Infinity and y.kind == .Infinity and x.sign != y.sign:
			c.raise(flagInvalid)
			return f.defaultNan()
		return f.infinityOf(x.sign if x.kind == .Infinity else y.sign)
	if x.kind == .Zero and y.kind == .Zero and x.sign == y.sign: return f.zeroOf(x.sign)
	sum = x.exactOf().addExact(y.exactOf())
	mode = c.rounding()
	if sum.w.isZero(): return f.zeroOf(mode == roundMinusInfinity)
	c.roundExact(f, sum, mode)

pub fn fpMul(mut c Cpu, f Fmt, a u64, b u64) u64:
	c.fpMulDiv(f, a, b, false)

pub fn fpDiv(mut c Cpu, f Fmt, a u64, b u64) u64:
	c.fpMulDiv(f, a, b, true)

# a * b, or a / b: zero and infinity decide the result before any rounding
fn fpMulDiv(mut c Cpu, f Fmt, a u64, b u64, divide bool) u64:
	x = c.unpack(f, a)
	y = c.unpack(f, b)
	if hasNan([x, y]): return c.nanResult(f, [x, y])
	sign = x.sign != y.sign
	special = x.kind != .Number and y.kind != .Number
	if special and (x.kind == y.kind) == divide:
		c.raise(flagInvalid)
		return f.defaultNan()
	if x.kind == .Infinity or y.kind == (.Zero if divide else .Infinity):
		if divide and y.kind == .Zero and x.kind != .Infinity: c.raise(flagDivideByZero)
		return f.infinityOf(sign)
	if x.kind == .Zero or y.kind == (.Infinity if divide else .Zero): return f.zeroOf(sign)
	c.roundExact(f, x.divExact(y) if divide else x.mulExact(y), c.rounding())

pub fn fpSqrt(mut c Cpu, f Fmt, a u64) u64:
	x = c.unpack(f, a)
	if x.isNan(): return c.nanResult(f, [x])
	if x.kind == .Zero: return f.zeroOf(x.sign)
	if x.sign:
		c.raise(flagInvalid)
		return f.defaultNan()
	if x.kind == .Infinity: return f.infinityOf(false)
	c.roundExact(f, x.sqrtExact(), c.rounding())

# addend + n * m rounded once
pub fn fpMulAdd(mut c Cpu, f Fmt, addend u64, n u64, m u64) u64:
	c.fpMulAddScaled(f, addend, n, m, false)

# fpMulAdd, or (addend + n * m) / 2 rounded once when `halve` (frsqrts)
fn fpMulAddScaled(mut c Cpu, f Fmt, addend u64, n u64, m u64, halve bool) u64:
	a = c.unpack(f, addend)
	x = c.unpack(f, n)
	y = c.unpack(f, m)
	badProduct = (x.kind == .Infinity and y.kind == .Zero) or
		(x.kind == .Zero and y.kind == .Infinity)
	if a.kind == .QuietNan and badProduct:
		c.raise(flagInvalid)
		return f.defaultNan()
	if hasNan([a, x, y]): return c.nanResult(f, [a, x, y])
	productSign = x.sign != y.sign
	productInfinite = x.kind == .Infinity or y.kind == .Infinity
	if badProduct or (a.kind == .Infinity and productInfinite and a.sign != productSign):
		c.raise(flagInvalid)
		return f.defaultNan()
	if a.kind == .Infinity: return f.infinityOf(a.sign)
	if productInfinite: return f.infinityOf(productSign)
	productZero = x.kind == .Zero or y.kind == .Zero
	if a.kind == .Zero and productZero and a.sign == productSign: return f.zeroOf(a.sign)
	product = Exact(sign = productSign, e = 0, w = Wide())
	if not productZero: product = x.mulExact(y)
	sum = a.exactOf().addExact(product)
	mode = c.rounding()
	if sum.w.isZero(): return f.zeroOf(mode == roundMinusInfinity)
	if halve: sum = Exact(..sum, e = sum.e - 1)
	c.roundExact(f, sum, mode)

# the arithmetic FloatOp `op` on two operands (the scalar and the vector forms share it)
pub fn fpArith(mut c Cpu, f Fmt, op arm64.FloatOp, a u64, b u64) u64:
	match op:
		Add: c.fpAdd(f, a, b, false)
		Sub: c.fpAdd(f, a, b, true)
		Mul: c.fpMul(f, a, b)
		Div: c.fpDiv(f, a, b)
		Max: c.fpMax(f, a, b, false, false)
		Min: c.fpMax(f, a, b, true, false)
		MaxNum: c.fpMax(f, a, b, false, true)
		_: c.fpMax(f, a, b, true, true)

# whether a * b is infinity times zero (neither a NaN)
fn infinityTimesZero(x Unpacked, y Unpacked):
	(x.kind == .Infinity and y.kind == .Zero) or (x.kind == .Zero and y.kind == .Infinity)

# fmulx: a * b, but infinity times zero is 2.0
pub fn fpMulX(mut c Cpu, f Fmt, a u64, b u64) u64:
	x = c.unpack(f, a)
	y = c.unpack(f, b)
	if x.infinityTimesZero(y): return f.twoOf(x.sign != y.sign)
	c.fpMul(f, a, b)

# frecps (2 - a * b) and frsqrts ((3 - a * b) / 2), fused; infinity times zero gives 2.0 and 1.5
fn fpStep(mut c Cpu, f Fmt, a u64, b u64, rsqrt bool) u64:
	negated = a ^ f.signBit()
	if c.unpack(f, negated).infinityTimesZero(c.unpack(f, b)):
		return f.onePointFive() if rsqrt else f.twoOf(false)
	c.fpMulAddScaled(f, f.twoOf(false) if not rsqrt else f.threeOf(), negated, b, rsqrt)

pub fn fpRecipStep(mut c Cpu, f Fmt, a u64, b u64) u64:
	c.fpStep(f, a, b, false)

pub fn fpRsqrtStep(mut c Cpu, f Fmt, a u64, b u64) u64:
	c.fpStep(f, a, b, true)

# the 9-bit estimate (256-511) of 1 / x for x in [0.5, 1) given as 256-511
fn recipEstimateOf(scaled i64):
	(((1 << 19) / (scaled * 2 + 1)) + 1) / 2

# the 9-bit estimate (256-511) of 1 / sqrt(x) for x given as 128-511 (128-255 for [0.25, 0.5))
fn rsqrtEstimateOf(scaled i64):
	a = scaled * 2 + 1 if scaled < 256 else (((scaled >> 1) << 1) + 1) * 2
	b = 512
	while a * (b + 1) * (b + 1) < 1 << 28:
		b += 1
	(b + 1) / 2

# the estimate's fraction (8 bits of a 256-511 estimate) and the exponent as the format keeps
# them: the bits of a normal number, or of the denormal one when the exponent is 0 or -1
fn estimateBits(f Fmt, exponent i64, estimate i64, sign bool):
	frac = u64(estimate & 0xFF) << 44
	e = exponent
	if e == 0: frac = (u64(1) << 51) | (frac >> 1)
	elif e == -1:
		frac = (u64(1) << 50) | (frac >> 2)
		e = 0
	f.zeroOf(sign) | u64(e) << f.fracBits | frac >> (52 - f.fracBits)

# frecpe: the estimate of 1 / a, accurate to 8 bits
pub fn fpRecipEstimate(mut c Cpu, f Fmt, a u64) u64:
	x = c.unpack(f, a)
	if x.isNan(): return c.nanResult(f, [x])
	if x.kind == .Infinity: return f.zeroOf(x.sign)
	if x.kind == .Zero:
		c.raise(flagDivideByZero)
		return f.infinityOf(x.sign)
	exponent = i64((a >> f.fracBits) & f.expMax())
	frac = (a & f.fracMask()) << (52 - f.fracBits)
	if exponent == 0 and frac >> 50 == 0:
		c.raise(flagOverflow | flagInexact)
		return f.infinityOf(x.sign) if overflowsToInfinity(c.rounding(), x.sign)
			else f.maxNormalOf(x.sign)
	if c.flushes(f) and exponent >= 2 * f.bias() - 1:
		c.raise(flagUnderflow)
		return f.zeroOf(x.sign)
	if exponent == 0:
		if frac >> 51 == 0:
			exponent = -1
			frac = (frac << 2) & fracMask52
		else:
			frac = (frac << 1) & fracMask52
	estimate = recipEstimateOf(256 | i64(frac >> 44) & 0xFF)
	f.estimateBits(2 * f.bias() - 1 - exponent, estimate, x.sign)

# frsqrte: the estimate of 1 / sqrt(a), accurate to 8 bits
pub fn fpRsqrtEstimate(mut c Cpu, f Fmt, a u64) u64:
	x = c.unpack(f, a)
	if x.isNan(): return c.nanResult(f, [x])
	if x.kind == .Zero:
		c.raise(flagDivideByZero)
		return f.infinityOf(x.sign)
	if x.sign:
		c.raise(flagInvalid)
		return f.defaultNan()
	if x.kind == .Infinity: return 0
	exponent = i64((a >> f.fracBits) & f.expMax())
	frac = (a & f.fracMask()) << (52 - f.fracBits)
	if exponent == 0:
		while frac >> 51 == 0:
			frac = (frac << 1) & fracMask52
			exponent -= 1
		frac = (frac << 1) & fracMask52
	scaled = 256 | i64(frac >> 44) & 0xFF if exponent & 1 == 0 else 128 | i64(frac >> 45) & 0x7F
	f.estimateBits((3 * f.bias() - 1 - exponent) / 2, rsqrtEstimateOf(scaled), false)

# urecpe and ursqrte of a 32-bit lane: all ones when the leading bits are clear, else the estimate
# of the top 9 bits as the fraction of a number in [1, 2)
pub fn unsignedRecipEstimate(x u64, rsqrt bool) u64:
	if x >> (30 if rsqrt else 31) == 0: return 0xFFFF_FFFF
	top = i64(x >> 23)
	(u64(rsqrtEstimateOf(top) if rsqrt else recipEstimateOf(top)) & 0x1FF) << 23

# frecpx: the exponent inverted and the fraction cleared
pub fn fpRecipExponent(mut c Cpu, f Fmt, a u64) u64:
	x = c.unpack(f, a)
	if x.isNan(): return c.nanResult(f, [x])
	exponent = (a >> f.fracBits) & f.expMax()
	kept = f.expMax() - 1 if exponent == 0 else ~exponent & f.expMax()
	f.zeroOf(x.sign) | kept << f.fracBits

# the last 52 bits
fracMask52 = (u64(1) << 52) - 1

# the larger (or smaller) of a and b; with `number`, a quiet NaN gives way to a number
pub fn fpMax(mut c Cpu, f Fmt, a u64, b u64, minimum bool, number bool) u64:
	x = c.unpack(f, a)
	y = c.unpack(f, b)
	if number:
		unwanted = Unpacked(kind = .Infinity, sign = not minimum)
		if x.kind == .QuietNan and y.kind != .QuietNan: x = unwanted
		elif y.kind == .QuietNan and x.kind != .QuietNan: y = unwanted
	if hasNan([x, y]): return c.nanResult(f, [x, y])
	order = x.compareValues(y)
	picked = x if (order < 0 if minimum else order > 0) else y
	if picked.kind == .Zero: return f.zeroOf((x.sign or y.sign) if minimum else (x.sign and y.sign))
	picked.bits

# fcmp's flags (NZCV as four bits); `signalAll` raises invalid on a quiet NaN too (fcmpe)
pub fn fpCompare(mut c Cpu, f Fmt, a u64, b u64, signalAll bool) u64:
	x = c.unpack(f, a)
	y = c.unpack(f, b)
	if x.isNan() or y.isNan():
		if signalAll or x.kind == .SignalingNan or y.kind == .SignalingNan: c.raise(flagInvalid)
		return 0b0011
	order = x.compareValues(y)
	if order == 0: return 0b0110
	0b1000 if order < 0 else 0b0010

# A number's value rounded to an integer by the mode: its magnitude, whether it passed 2^64, and
# whether there was a fraction. fbits scales the number by 2^fbits first (fixed-point).
pub type Integral:
	magnitude u64 = 0
	huge bool = false
	inexact bool = false

pub fn toIntegral(u Unpacked, fbits i64, mode i64) Integral:
	e = u.e + fbits
	if e >= 0:
		if 64 - u.m.leadingZeros() + e > 64: return Integral(huge = true)
		return Integral(magnitude = u.m << e)
	q, guard, rest = splitAt(Wide(lo = u.m), -e)
	up = roundsUp(mode, u.sign, q.lo & 1 != 0, guard, rest)
	Integral(magnitude = q.lo + (1 if up else 0), inexact = guard or rest)

# fcvt[nmpaz][su], fcvtz[su] with fbits: the float as an integer of `width` bits (32 or 64),
# saturated, with invalid for a NaN or a value out of range
pub fn fpToInt(
	mut c Cpu,
	f Fmt,
	a u64,
	fbits i64,
	mode i64,
	signed bool,
	width i64
) u64:
	x = c.unpack(f, a)
	if x.isNan():
		c.raise(flagInvalid)
		return 0
	if x.kind == .Zero: return 0
	top = u64(-1) if width == 64 else (u64(1) << width) - 1
	maxPositive = top >> 1 if signed else top
	maxNegative = maxPositive + 1 if signed else 0
	got = Integral(huge = true)
	if x.kind == .Number: got = x.toIntegral(fbits, mode)
	limit = maxNegative if x.sign else maxPositive
	if got.huge or got.magnitude > limit:
		c.raise(flagInvalid)
		return (0 - maxNegative) if x.sign else maxPositive
	if got.inexact: c.raise(flagInexact)
	(0 - got.magnitude) if x.sign else got.magnitude

# scvtf, ucvtf: the integer of `width` bits divided by 2^fbits, in the format
pub fn fpFromInt(mut c Cpu, f Fmt, v u64, signed bool, width i64, fbits i64) u64:
	top = u64(-1) if width == 64 else (u64(1) << width) - 1
	value = v & top
	negative = signed and value >> (width - 1) != 0
	magnitude = (0 - value) & top if negative else value
	if magnitude == 0: return 0
	c.roundExact(f, Exact(sign = negative, e = -fbits, w = Wide(lo = magnitude)), c.rounding())

# frint*: the float rounded to an integral float by the mode; `exact` raises inexact (frintx)
pub fn fpRoundInt(mut c Cpu, f Fmt, a u64, mode i64, exact bool) u64:
	x = c.unpack(f, a)
	if x.isNan(): return c.nanResult(f, [x])
	if x.kind == .Zero: return f.zeroOf(x.sign)
	if x.kind == .Infinity or x.e >= 0: return a
	got = x.toIntegral(0, mode)
	if exact and got.inexact: c.raise(flagInexact)
	if got.magnitude == 0: return f.zeroOf(x.sign)
	c.roundExact(f, Exact(sign = x.sign, e = 0, w = Wide(lo = got.magnitude)), roundZero)

# fcvt between formats: the value rounded, a NaN's top fraction bits kept
pub fn fpConvert(mut c Cpu, from Fmt, to Fmt, a u64) u64:
	c.fpConvertBy(from, to, a, c.rounding())

# fpConvert rounding by `mode` (fcvtxn's round to odd)
pub fn fpConvertBy(mut c Cpu, from Fmt, to Fmt, a u64, mode i64) u64:
	x = c.unpack(from, a)
	if x.isNan():
		if x.kind == .SignalingNan: c.raise(flagInvalid)
		if c.hasDefaultNan(): return to.defaultNan()
		frac = x.bits & from.fracMask()
		moved = frac
		if to.fracBits > from.fracBits: moved = frac << (to.fracBits - from.fracBits)
		else: moved = frac >> (from.fracBits - to.fracBits)
		return to.infinityOf(x.sign) | moved | to.quiet()
	match x.kind:
		Infinity: to.infinityOf(x.sign)
		Zero: to.zeroOf(x.sign)
		_: c.roundExact(to, x.exactOf(), mode)

# fmov's 8-bit immediate as a float of the format (VFPExpandImm)
pub fn expandImm(f Fmt, imm8 i64) u64:
	b6 = (imm8 >> 6) & 1
	middle = ((1 << (f.expBits - 3)) - 1) << 2 if b6 == 1 else 0
	exponent = u64((1 - b6) << (f.expBits - 1) | middle | (imm8 >> 4) & 3)
	frac = u64(imm8 & 15) << (f.fracBits - 4)
	f.zeroOf((imm8 >> 7) & 1 == 1) | exponent << f.fracBits | frac

# the scalar register r's low bits in the format
pub fn readFp(c Cpu, r i64, f Fmt) u64:
	c.q[2 * r] & f.mask()

# a scalar written: the rest of the 128-bit register is zeroed
pub fn writeFp(mut c Cpu, r i64, v u64):
	c.q[2 * r] = v
	c.q[2 * r + 1] = 0

# the scalar FP operations without forms (forms/forms.zap's floatLines write the others)
pub fn float(mut c Cpu, i arm64.Instr):
	f = fmtOf(i.size)
	a = c.readFp(i.rn, f)
	b = c.readFp(i.rm, f)
	match i.fop:
		Convert: c.writeFp(i.rd, c.fpConvert(f, fmtOf(i.opc), a))
		Round: c.floatRound(i, f, a)
		MulAdd: c.floatMulAdd(i, f)
		CondCompare:
			c.setNzcv(c.fpCompare(f, a, b, i.setFlags) if c.holds(i.cond) else u64(i.imm))
		Immediate: c.writeFp(i.rd, f.expandImm(i.imm))
		ToGeneral: c.set(i.rd, c.q[2 * i.rn + i.index] & f.mask(), i.sf)
		FromGeneral: c.floatFromGeneral(i, f)
		_: c.stop(c.pc - 4, "float")

# frint*: opc 0-4 the mode, 5 frintx (current mode, inexact), 6 frinti (current mode)
fn floatRound(mut c Cpu, i arm64.Instr, f Fmt, a u64):
	c.writeFp(i.rd, c.fpRoundBy(f, i.opc, a))

# frint* by the opcode: 0-4 the mode, 5 frintx (current mode, inexact), 6 frinti (current mode)
pub fn fpRoundBy(mut c Cpu, f Fmt, opc i64, a u64) u64:
	c.fpRoundInt(f, a, c.rounding() if opc >= 5 else opc, opc == 5)

# fmadd, fmsub, fnmadd, fnmsub (opc is o1:o0): the addend and the first factor negated as the
# opcode says, before any NaN is looked at
fn floatMulAdd(mut c Cpu, i arm64.Instr, f Fmt):
	negateAddend = i.opc >> 1 == 1
	negateFactor = (i.opc & 1) != (i.opc >> 1)
	addend = c.readFp(i.ra, f) ^ (f.signBit() if negateAddend else 0)
	factor = c.readFp(i.rn, f) ^ (f.signBit() if negateFactor else 0)
	c.writeFp(i.rd, c.fpMulAdd(f, addend, factor, c.readFp(i.rm, f)))

# fmov from a general register to a scalar, or to the high half of a vector (index 1)
fn floatFromGeneral(mut c Cpu, i arm64.Instr, f Fmt):
	if i.index == 1:
		c.q[2 * i.rd + 1] = c.x[i.rn]
		return
	c.writeFp(i.rd, c.get(i.rn, i.sf) & f.mask())
