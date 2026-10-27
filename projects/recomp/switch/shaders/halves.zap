# The half float instructions translated (fields as yuzu's half_floating_point_*.cpp read them):
# HADD2, HMUL2, HFMA2, HSET2, HSETP2. A register holds two halves (the low one first); each operand
# gives two values by its swizzle (both halves, the low or the high one twice, or the register as
# one f32), each computed in f32 (the runtime's halfValue) and rounded to a half when stored
# (halfBits): an f32 sum or product of halves rounds to the half of the exact one.

import recomp.switch.arm64

pub type Swizzle:
	Halves
	Single   # the register's bits an f32, both values
	Low
	High

swizzles = [Swizzle.Halves, Swizzle.Single, Swizzle.Low, Swizzle.High]

fn swizzleAt(i Instr, at i64):
	swizzles[i.field(at, 2)]

# an operand's two values (low, high) by its swizzle, abs and negation applied
fn valuesOf(v str, s Swizzle, abs bool, neg bool):
	low = absNeg("halfValue({v})", abs, neg)
	high = absNeg("halfValue({v} >> 16)", abs, neg)
	single = absNeg("f32.fromBits({v})", abs, neg)
	match s:
		Halves: (low, high)
		Single: (single.copy(), single)
		Low: (low.copy(), low)
		High: (high.copy(), high)

# the immediate of the Imm form: two halves of 9 bits (the top of each) and their signs
fn halvesImmediate(i Instr):
	w = i.word
	v = arm64.bits(w, 20, 9) << 6 | arm64.bits(w, 29, 1) << 15 | arm64.bits(w, 30, 9) << 22 |
		arm64.bits(w, 56, 1) << 31
	"{v}"

# operand B's swizzle: a register's at `at`, a constant buffer's word an f32, an immediate halves
fn swizzleOfB(i Instr, at i64) Swizzle:
	match i.form:
		Reg, Rc: i.swizzleAt(at)
		Cbuf, Cr: .Single
		_: .Halves

# Operand B's values: a register (at 20, or HFMA2.RC's at 39), a constant buffer's word, the Imm
# form's halves, the 32I form's word
fn halvesOfB(mut e Emitter, i Instr, s Swizzle, abs bool, neg bool):
	v = match i.form:
		Reg, Rc: e.x(i.b.reg)
		Cbuf, Cr: e.bits(i.b)
		Imm: i.halvesImmediate()
		_: "{i.b.imm & 0xFFFF_FFFF}"
	valuesOf(v, s, abs, neg)

# rd from the values `lo` and `hi` by merge 0 (two halves), 1 (lo an f32: through a half when an
# operand was halves), 2 (lo into the low half, rd's high kept) or 3 (hi into the high half)
fn writeHalves(mut e Emitter, i Instr, merge i64, throughHalf bool):
	single = "halfValue(halfBits(lo))" if throughHalf else "lo"
	value = match merge:
		0: "halfBits(lo) | halfBits(hi) << 16"
		1: "({single}).toBits()"
		2: "({e.x(i.rd)} & 0xFFFF_0000) | halfBits(lo)"
		_: "({e.x(i.rd)} & 0xFFFF) | halfBits(hi) << 16"
	e.set(i.rd, value)

# the locals lo and hi, clamped to 0..1 when sat
fn computeHalves(mut e Emitter, low str, high str, sat bool):
	e.line("lo = {saturated(low, sat)}")
	e.line("hi = {saturated(high, sat)}")

fn isHalves(s Swizzle):
	s != .Single

# a product by precision 2 (FMZ): zero when either factor is
fn halfProduct(a str, b str, precision i64):
	"maxwell.mulZero({a}, {b})" if precision == 2 else "{a} * {b}"

pub fn emitHadd2(mut e Emitter, i Instr):
	imm32 = i.form == .Imm32
	isReg = i.form == .Reg
	swizzleA = i.swizzleAt(53 if imm32 else 47)
	a0, a1 = valuesOf(e.x(i.ra), swizzleA, not imm32 and i.flag(44), i.flag(56 if imm32 else 43))
	swizzleB = i.swizzleOfB(28)
	absB = i.flag(30) if isReg else i.form == .Cbuf and i.flag(54)
	negB = i.flag(31) if isReg else i.form == .Cbuf and i.flag(56)
	b0, b1 = e.halvesOfB(i, swizzleB, absB, negB)
	e.computeHalves("{a0} + {b0}", "{a1} + {b1}", i.flag(32 if isReg else 52))
	e.writeHalves(i, 0 if imm32 else i.field(49, 2), swizzleA.isHalves() or swizzleB.isHalves())

pub fn emitHmul2(mut e Emitter, i Instr):
	imm32 = i.form == .Imm32
	isReg = i.form == .Reg
	swizzleA = i.swizzleAt(53 if imm32 else 47)
	negA = not imm32 and not isReg and i.flag(43)
	a0, a1 = valuesOf(e.x(i.ra), swizzleA, not imm32 and i.flag(44), negA)
	swizzleB = i.swizzleOfB(28)
	absB = i.flag(30) if isReg else i.form == .Cbuf and i.flag(54)
	b0, b1 = e.halvesOfB(i, swizzleB, absB, isReg and i.flag(31))
	precision = i.field(55 if imm32 else 39, 2)
	low = halfProduct(a0, b0, precision)
	e.computeHalves(low, halfProduct(a1, b1, precision), i.flag(32 if isReg else 52))
	e.writeHalves(i, 0 if imm32 else i.field(49, 2), swizzleA.isHalves() or swizzleB.isHalves())

# HFMA2: A * B + C; the 32I form's C is rd, B its word
pub fn emitHfma2(mut e Emitter, i Instr):
	imm32 = i.form == .Imm32
	isReg = i.form == .Reg
	swizzleA = i.swizzleAt(53 if imm32 else 47)
	a0, a1 = valuesOf(e.x(i.ra), swizzleA, false, false)
	swizzleB = i.swizzleOfB(28 if isReg else 53)
	negB = i.flag(31) if isReg else i.form != .Imm and not imm32 and i.flag(56)
	b0, b1 = e.halvesOfB(i, swizzleB, false, negB)
	swizzleC = match i.form:
		Reg: i.swizzleAt(35)
		Cr, Imm: i.swizzleAt(53)
		Rc: Swizzle.Single
		_: Swizzle.Halves
	c = e.bits(i.c) if i.form == .Rc else e.x(i.rd) if imm32 else e.x(i.c.reg)
	c0, c1 = valuesOf(c, swizzleC, false, i.flag(30 if isReg else 52 if imm32 else 51))
	precision = i.field(37 if isReg else 55 if imm32 else 57, 2)
	e.computeHalves(
		"{halfProduct(a0, b0, precision)} + {c0}",
		"{halfProduct(a1, b1, precision)} + {c1}",
		not imm32 and i.flag(32 if isReg else 52)
	)
	through = swizzleA.isHalves() or swizzleB.isHalves() or swizzleC.isHalves()
	e.writeHalves(i, 0 if imm32 else i.field(49, 2), through)

# HSET2 and HSETP2's two comparisons (low, high), each combined with the predicate at 39
fn halfTests(mut e Emitter, i Instr):
	isReg = i.form == .Reg
	a0, a1 = valuesOf(e.x(i.ra), i.swizzleAt(47), i.flag(44), i.flag(43))
	absB = i.flag(30) if isReg else i.op == .Hsetp2 and i.form == .Cbuf and i.flag(54)
	negB = i.flag(31) if isReg else i.form == .Cbuf and i.flag(56)
	b0, b1 = e.halvesOfB(i, i.swizzleOfB(28), absB, negB)
	op = i.field(35 if isReg else 49, 4)
	c = e.pred(i.field(39, 3), i.flag(42))
	bop = i.field(45, 2)
	(combined(floatCompare(a0, b0, op), bop, c), combined(floatCompare(a1, b1, op), bop, c))

# HSET2: each half 1.0 (BF) or all ones where its test holds, else 0
pub fn emitHset2(mut e Emitter, i Instr):
	low, high = e.halfTests(i)
	one = 0x3C00 if i.flag(49 if i.form == .Reg else 53) else 0xFFFF
	e.set(i.rd, "({one} if {low} else 0) | ({one << 16} if {high} else 0)")

# HSETP2: the predicates at 3 and 0 the two tests, or with H_AND both tests and its negation
pub fn emitHsetp2(mut e Emitter, i Instr):
	low, high = e.halfTests(i)
	if i.flag(49 if i.form == .Reg else 53):
		e.line("test = ({low}) and ({high})")
		e.setP(i.field(3, 3), "test")
		e.setP(i.field(0, 3), "not test")
		return
	e.setP(i.field(3, 3), low)
	e.setP(i.field(0, 3), high)
