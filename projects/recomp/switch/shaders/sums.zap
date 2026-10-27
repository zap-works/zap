# The integer sums and products translated (fields as Ryujinx's InstDecoders and
# InstEmitIntegerArithmetic read them): IADD, IADD3, ISCADD, LEA, IMAD, IMUL, XMAD. A sum adds as
# the hardware's adder does: a negated operand is ~v and a one more, X adds the carry, CC sets
# zero, sign, carry and overflow (Ryujinx's SetIaddFlags, the zero of an X sum kept only when the
# words below were zero), SAT clamps to the signed range on an overflow.

# ~v of a u32 value, an immediate's computed
fn inverted(v str):
	if i64.parse(v) is n: return "{~n & 0xFFFF_FFFF}"
	"~{v}"

# Sum options: `negation` 0 none, 1 B negated, 2 A negated, 3 a one more (AvgMode); `plus` a u32
# expression added too ("" none).
type SumMode:
	negation i64 = 0
	plus str = ""
	x bool = false
	cc bool = false
	sat bool = false

# the expression of a + b as the mode asks, its codes set when cc (through the locals ca, cb, cr)
fn sumOf(mut e Emitter, a str, b str, m SumMode):
	left = inverted(a) if m.negation == 2 else a
	right = inverted(b) if m.negation == 1 else b
	tail = ""
	if m.negation != 0: tail = " + 1"
	if m.plus != "": tail = "{tail} + {m.plus}"
	if m.x: tail = "{tail} + maxwell.bit({e.cc(2)})"
	if not m.cc and not m.sat: return "{left}{tail}" if right == "0" else "{left} + {right}{tail}"
	e.usesSum = true
	e.line("ca = {left}")
	e.line("cb = {right}")
	e.line("cr = ca + cb{tail}")
	overflow = "((ca ^ cr) & (cb ^ cr)) >> 31 != 0"
	if m.cc:
		e.setFlag(2, "maxwell.carriesOut(ca, cb, {tail[3..] if tail != "" else "0"})")
		e.setFlag(3, overflow)
		e.setZeroSign("cr", m.x)
	if m.sat: e.line("cr = 0x7FFF_FFFF + (ca >> 31) if {overflow} else cr")
	"cr"

pub fn emitIadd(mut e Emitter, i Instr):
	imm32 = i.form == .Imm32
	m = SumMode(
		negation = i.field(55 if imm32 else 48, 2),
		x = i.flag(53 if imm32 else 43),
		cc = i.flag(52 if imm32 else 47),
		sat = i.flag(54 if imm32 else 50)
	)
	e.set(i.rd, e.sumOf(e.x(i.ra), e.bits(i.b), m))

fn neg(v str, n bool):
	"(0 - {v})" if n else v

# IADD3: A + B (shifted by 16 left or right, the reg form's 37-38) + C, each negated as asked;
# the reg form's halves (31-36) pick 16 bits of each. CC and X apply to the last addition, of C.
pub fn emitIadd3(mut e Emitter, i Instr):
	isReg = i.form == .Reg
	parts = [e.x(i.ra), e.bits(i.b), e.x(i.c.reg)]
	if isReg:
		for k, at in [35, 33, 31]:
			h = i.field(at, 2)
			if h != 0: parts[k] = "maxwell.half({parts[k]}, {h == 2}, false)"
	ab = "{neg(parts[0], i.flag(51))} + {neg(parts[1], i.flag(50))}"
	shift = i.field(37, 2) if isReg else 0
	if shift == 1: ab = "(({ab}) >> 16)"
	if shift == 2: ab = "(({ab}) << 16)"
	m = SumMode(negation = 1 if i.flag(49) else 0, x = i.flag(48), cc = i.flag(47))
	e.set(i.rd, e.sumOf(ab, parts[2], m))

# ISCADD: (A << shift) + B, each negated as asked (the 32I form negates neither)
pub fn emitIscadd(mut e Emitter, i Instr):
	imm32 = i.form == .Imm32
	scale = i.field(53, 5) if imm32 else i.field(39, 5)
	m = SumMode(negation = 0 if imm32 else i.field(48, 2), cc = i.flag(52 if imm32 else 47))
	e.set(i.rd, e.sumOf("({e.x(i.ra)} << {scale})", e.bits(i.b), m))

# LEA: (A << shift), negated as asked, + B; LEA.HI the high word of (C:A) << shift (negated as a
# 64-bit number) + B
pub fn emitLea(mut e Emitter, i Instr):
	if i.op == .LeaLo:
		m = SumMode(negation = 2 if i.flag(45) else 0, x = i.flag(46), cc = i.flag(47))
		e.set(i.rd, e.sumOf("({e.x(i.ra)} << {i.field(39, 5)})", e.bits(i.b), m))
		return
	isReg = i.form == .Reg
	shift = i.field(28 if isReg else 51, 5)
	a = e.x(i.ra)
	high = "maxwell.funnelShift({a}, {e.x(i.c.reg)}, {shift}, false, false)"
	negated = i.flag(37 if isReg else 56)
	m = SumMode(
		plus = "maxwell.bit(({a} << {shift}) == 0)" if negated else "",
		x = i.flag(38 if isReg else 57),
		cc = i.flag(47)
	)
	e.set(i.rd, e.sumOf(inverted(high) if negated else high, e.bits(i.b), m))

# A * B (its low word, or with HI the high one of the 64-bit product, each factor signed or not)
fn productOf(mut e Emitter, i Instr, signedA bool, signedB bool, high bool):
	a = e.x(i.ra)
	b = e.bits(i.b)
	if high: return "maxwell.mulHigh({a}, {b}, {signedA}, {signedB})"
	"{a} * {b}"

# IMAD: A * B + C, the product negated (mode 2) or C (mode 1) or a one added (3); IMAD32I's C is
# the destination
pub fn emitImad(mut e Emitter, i Instr):
	if i.form == .Imm32:
		product = e.productOf(i, i.flag(54), i.flag(57), i.flag(53))
		m = SumMode(negation = i.field(55, 2), cc = i.flag(52))
		e.set(i.rd, e.sumOf(product, e.x(i.rd), m))
		return
	product = e.productOf(i, i.flag(48), i.flag(53), i.flag(54))
	m = SumMode(negation = i.field(51, 2), x = i.flag(49), cc = i.flag(47), sat = i.flag(50))
	e.set(i.rd, e.sumOf(product, e.bits(i.c), m))

pub fn emitImul(mut e Emitter, i Instr):
	imm32 = i.form == .Imm32
	at = 53 if imm32 else 39   # HI, then A's sign and B's
	product = e.productOf(i, i.flag(at + 1), i.flag(at + 2), i.flag(at))
	e.set(i.rd, e.sumOf(product, "0", SumMode(cc = i.flag(52 if imm32 else 47))))

# XMAD: a 16x16 product of halves plus C (or a half of C, C less the factors' signs shifted up
# (CSFU), or B << 16 + C); PSL shifts the product, MRG puts B's low half in the result's high one
pub fn emitXmad(mut e Emitter, i Instr):
	b, c, mode, highB, psl, mrg, x = match i.form:
		Reg: (
			e.x(i.b.reg),
			e.x(i.c.reg),
			i.field(50, 3),
			i.flag(35),
			i.flag(36),
			i.flag(37),
			i.flag(38)
		)
		Imm: (
			"{i.field(20, 16)}",
			e.x(i.c.reg),
			i.field(50, 3),
			false,
			i.flag(36),
			i.flag(37),
			i.flag(38)
		)
		Rc: (e.bits(i.b), e.bits(i.c), i.field(50, 2), i.flag(52), false, false, i.flag(54))
		_: (
			e.bits(i.b),
			e.x(i.c.reg),
			i.field(50, 2),
			i.flag(52),
			i.flag(55),
			i.flag(56),
			i.flag(54)
		)
	if mode > 4:
		e.lack(i, "XMAD select mode {mode}", [i.rd])
		return
	a = "maxwell.half({e.x(i.ra)}, {i.flag(53)}, {i.flag(48)})"
	factorB = "maxwell.half({b}, {highB}, {i.flag(49)})"
	product = "{a} * {factorB}"
	if psl: product = "({product}) << 16"
	addend = [
		c,
		"maxwell.half({c}, false, false)",
		"maxwell.half({c}, true, false)",
		"{c} - ((({a} >> 31) + ({factorB} >> 31)) << 16)",
		"({b} << 16) + {c}"
	][mode]
	sum = e.sumOf(product, addend, SumMode(x, cc = i.flag(47)))
	e.set(i.rd, "maxwell.insertBits({sum}, {b}, 16, 16)" if mrg else sum)
