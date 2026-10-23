# The floating-point formats and what A64 does at their edges (Arm ARM, J1: FPUnpack, FPRound,
# FPProcessException, FPProcessNaN): the operations in float.zap and the vector ones build on
# these. A value is handled as its bits (u64, the low width of them) and the flags it raises
# are ORed into FPSR.

# FPSR's cumulative exception bits
pub flagInvalid u64 = 1
pub flagDivideByZero u64 = 2
pub flagOverflow u64 = 4
pub flagUnderflow u64 = 8
pub flagInexact u64 = 16
pub flagInputDenormal u64 = 128

# FPCR's rounding modes (its RMode field, plus the tie-away mode only conversions use)
pub roundNearestEven = 0
pub roundPlusInfinity = 1
pub roundMinusInfinity = 2
pub roundZero = 3
pub roundTieAway = 4

pub type Fmt:
	expBits i64
	fracBits i64

	fn bias():
		(1 << (expBits - 1)) - 1

	fn width():
		1 + expBits + fracBits

	fn expMax():
		(u64(1) << expBits) - 1

	fn fracMask():
		(u64(1) << fracBits) - 1

	fn signBit():
		u64(1) << (expBits + fracBits)

	# the format's bits, the low width of a register's word
	fn mask():
		u64(-1) if width() == 64 else (u64(1) << width()) - 1

	# the top fraction bit, set in a quiet NaN
	fn quiet():
		u64(1) << (fracBits - 1)

pub fmtHalf = Fmt(expBits = 5, fracBits = 10)
pub fmtSingle = Fmt(expBits = 8, fracBits = 23)
pub fmtDouble = Fmt(expBits = 11, fracBits = 52)

# the format of an instruction's type field (0 single, 1 double, 3 half)
pub fn fmtOf(ftype i64) Fmt:
	match ftype:
		0: fmtSingle
		1: fmtDouble
		_: fmtHalf

pub type Kind:
	Zero
	Number
	Infinity
	QuietNan
	SignalingNan

# An operand taken apart: a number is m * 2^e with the sign apart, and `bits` are the operand's
# own (a NaN is returned as they were).
pub type Unpacked:
	kind Kind = .Zero
	sign bool = false
	e i64 = 0
	m u64 = 0
	bits u64 = 0

	fn isNan():
		kind == .QuietNan or kind == .SignalingNan

# an exact value, w * 2^e and a bit more than that when `sticky`, to be rounded once
pub type Exact:
	sign bool
	e i64
	w Wide
	sticky bool = false

pub fn raise(mut c Cpu, flags u64):
	c.fpsr |= flags

# the rounding mode FPCR chooses
pub fn rounding(c Cpu) i64:
	(c.fpcr >> 22) & 3

# whether FPCR says a NaN becomes the default one
pub fn hasDefaultNan(c Cpu) bool:
	(c.fpcr >> 25) & 1 != 0

# whether denormal operands and results are flushed to zero (FPCR.FZ; not for half precision)
fn flushes(c Cpu, f Fmt):
	(c.fpcr >> 24) & 1 != 0 and f.fracBits != fmtHalf.fracBits

pub fn zeroOf(f Fmt, sign bool) u64:
	f.signBit() if sign else 0

pub fn infinityOf(f Fmt, sign bool) u64:
	(f.expMax() << f.fracBits) | f.zeroOf(sign)

fn maxNormalOf(f Fmt, sign bool):
	((f.expMax() - 1) << f.fracBits) | f.fracMask() | f.zeroOf(sign)

pub fn defaultNan(f Fmt) u64:
	(f.expMax() << f.fracBits) | f.quiet()

# the operand taken apart; a denormal one is flushed to zero when FPCR says so (and IDC is set)
pub fn unpack(mut c Cpu, f Fmt, bits u64) Unpacked:
	sign = bits & f.signBit() != 0
	exp = (bits >> f.fracBits) & f.expMax()
	frac = bits & f.fracMask()
	if exp == f.expMax():
		kind = Kind.Infinity
		if frac != 0: kind = .QuietNan if frac & f.quiet() != 0 else .SignalingNan
		return Unpacked(kind, sign, bits)
	if exp == 0:
		if frac == 0: return Unpacked(kind = .Zero, sign, bits)
		if c.flushes(f):
			c.raise(flagInputDenormal)
			return Unpacked(kind = .Zero, sign, bits)
		return Unpacked(kind = .Number, sign, e = 1 - f.bias() - f.fracBits, m = frac, bits)
	Unpacked(
		kind = .Number,
		sign,
		e = i64(exp) - f.bias() - f.fracBits,
		m = frac | (u64(1) << f.fracBits),
		bits
	)

# a NaN made the result: quiet, or the default one when FPCR says so; a signaling one is invalid
pub fn processNan(mut c Cpu, f Fmt, u Unpacked) u64:
	if u.kind == .SignalingNan: c.raise(flagInvalid)
	if c.hasDefaultNan(): return f.defaultNan()
	u.bits | f.quiet()

# whether any operand is a NaN
pub fn hasNan(operands Unpacked[]) bool:
	operands.any(.isNan())

# the NaN the operands give (one of them is a NaN): the first signaling one, else the first quiet
# one
pub fn nanResult(mut c Cpu, f Fmt, operands Unpacked[]) u64:
	for u in operands:
		if u.kind == .SignalingNan: return c.processNan(f, u)
	for u in operands:
		if u.kind == .QuietNan: return c.processNan(f, u)
	f.defaultNan()

# whether a rounding to the mode adds one to the kept bits, given what lies below them
pub fn roundsUp(mode i64, sign bool, odd bool, guard bool, rest bool) bool:
	match mode:
		0: guard and (rest or odd)
		1: (guard or rest) and not sign
		2: (guard or rest) and sign
		3: false
		_: guard

# FPRound: the exact value in the format, by the mode; flushed to zero when FPCR says so before
# rounding (the exponent too small), else raising underflow, overflow and inexact as they occur
pub fn roundExact(mut c Cpu, f Fmt, x Exact, mode i64) u64:
	lead = x.w.leadingZeros()
	exponent = x.e + 127 - lead
	minExponent = 1 - f.bias()
	tiny = exponent < minExponent
	if tiny and c.flushes(f):
		c.raise(flagUnderflow)
		return f.zeroOf(x.sign)
	keep = f.fracBits + 1 - (minExponent - exponent if tiny else 0)
	q, guard, below = x.w.shl(lead).splitAt(128 - keep)
	rest = below or x.sticky
	inexact = guard or rest
	packed = q.lo + (1 if roundsUp(mode, x.sign, q.lo & 1 != 0, guard, rest) else 0)
	if not tiny: packed += u64(exponent + f.bias() - 1) << f.fracBits
	if tiny and inexact: c.raise(flagUnderflow)
	if packed >> f.fracBits >= f.expMax():
		c.raise(flagOverflow | flagInexact)
		toInfinity = match mode:
			0: true
			1: not x.sign
			2: x.sign
			_: false
		return f.infinityOf(x.sign) if toInfinity else f.maxNormalOf(x.sign)
	if inexact: c.raise(flagInexact)
	packed | f.zeroOf(x.sign)
