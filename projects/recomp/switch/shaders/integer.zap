# The integer, logic and predicate instructions translated (fields as yuzu's integer_*.cpp,
# logic_operation*.cpp and predicate_*.cpp read them): IADD, IADD3, ISCADD, XMAD, SHL, SHR, SHF,
# LOP, LOP3, BFE, BFI, POPC, FLO, I2I, ISETP, ISET, ICMP, IMNMX, SEL, MOV, PSETP, PSET, P2R, R2P.
# A register is u32: a sum wraps as the hardware's does, a signed test reads it as i32.

# condition codes (CC writes, X reads) are not translated: what sets them is noted
fn usesFlags(mut e Emitter, i Instr, cc bool, x bool):
	if not cc and not x: return false
	e.lack(i, "condition codes", [i.rd])
	true

fn neg(v str, n bool):
	"(0 - {v})" if n else v

pub fn emitIadd(mut e Emitter, i Instr):
	imm32 = i.form == .Imm32
	if e.usesFlags(i, i.flag(52 if imm32 else 47), i.flag(53 if imm32 else 43)): return
	if i.flag(54 if imm32 else 50):
		e.lack(i, "IADD.SAT", [i.rd])
		return
	po = i.field(55 if imm32 else 48, 2) == 3
	a = neg(e.x(i.ra), not po and i.flag(56 if imm32 else 49))
	b = neg(e.bits(i.b), not po and not imm32 and i.flag(48))
	e.set(i.rd, "{a} + {b} + 1" if po else "{a} + {b}")

# IADD3: A + B (shifted by 16 left or right, the reg form's 37-38) + C, each negated as asked;
# the reg form's halves (31-36) pick 16 bits of each
pub fn emitIadd3(mut e Emitter, i Instr):
	if e.usesFlags(i, i.flag(47), i.flag(48)): return
	isReg = i.form == .Reg
	parts = [e.x(i.ra), e.bits(i.b), e.x(i.c.reg)]
	if isReg:
		for k, at in [35, 33, 31]:
			h = i.field(at, 2)
			if h != 0: parts[k] = "maxwell.half({parts[k]}, {h == 2}, false)"
	a = neg(parts[0], i.flag(51))
	b = neg(parts[1], i.flag(50))
	c = neg(parts[2], i.flag(49))
	shift = i.field(37, 2) if isReg else 0
	if shift == 1:
		e.lack(i, "IADD3.RS", [i.rd])
		return
	e.set(i.rd, "(({a} + {b}) << 16) + {c}" if shift == 2 else "{a} + {b} + {c}")

pub fn emitIscadd(mut e Emitter, i Instr):
	imm32 = i.form == .Imm32
	if e.usesFlags(i, i.flag(52 if imm32 else 47), false): return
	scale = i.field(53, 5) if imm32 else i.field(39, 5)
	a = neg(e.x(i.ra), not imm32 and i.flag(49))
	b = neg(e.bits(i.b), not imm32 and i.flag(48))
	e.set(i.rd, "({a} << {scale}) + {b}")

# XMAD: a 16x16 product of halves plus C (or a half of C, or B << 16 + C); PSL shifts the product,
# MRG puts B's low half in the result's high one
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
	if e.usesFlags(i, i.flag(47), x): return
	if mode > 4 or mode == 3:
		e.lack(i, "XMAD select mode {mode}", [i.rd])
		return
	a = "maxwell.half({e.x(i.ra)}, {i.flag(53)}, {i.flag(48)})"
	product = "{a} * maxwell.half({b}, {highB}, {i.flag(49)})"
	if psl: product = "({product}) << 16"
	addend = [
		c,
		"maxwell.half({c}, false, false)",
		"maxwell.half({c}, true, false)",
		"",
		"({b} << 16) + {c}"
	][mode]
	sum = "{product} + {addend}"
	e.set(i.rd, "maxwell.insertBits({sum}, {b}, 16, 16)" if mrg else sum)

# SHL: W wraps the shift to its low 5 bits, else a shift past 31 gives 0
pub fn emitShl(mut e Emitter, i Instr):
	if e.usesFlags(i, i.flag(47), i.flag(43)): return
	a = e.x(i.ra)
	if i.b.kind == .Imm:
		n = i.shiftOf()
		e.set(i.rd, "{a} << {n}" if n < 32 else "0")
		return
	s = e.bits(i.b)
	e.set(i.rd, "{a} << ({s} & 31)" if i.flag(39) else "0 if {s} > 31 else {a} << {s}")

# an immediate shift, wrapped when W
fn shiftOf(i Instr):
	n = i.b.imm & 0xFFFF_FFFF
	n & 31 if i.flag(39) else n

# SHR: signed or not, W as SHL's, BREV reversing A first
pub fn emitShr(mut e Emitter, i Instr):
	if e.usesFlags(i, i.flag(47), i.flag(43)): return
	a = "maxwell.reverseBits({e.x(i.ra)})" if i.flag(40) else e.x(i.ra)
	signed = i.flag(48)
	if i.b.kind == .Imm:
		n = i.shiftOf()
		if signed:
			e.set(i.rd, "u32(i32({a}) >> {n.min(31)})")
		else:
			e.set(i.rd, "{a} >> {n}" if n < 32 else "0")
		return
	s = e.bits(i.b)
	amount = "({s} & 31)" if i.flag(39) else "{s}.min(31)"
	if signed:
		e.set(i.rd, "u32(i32({a}) >> {amount})")
	elif i.flag(39):
		e.set(i.rd, "{a} >> {amount}")
	else:
		e.set(i.rd, "0 if {s} > 31 else {a} >> {s}")

# SHF: the 64 bits C:A shifted by B, the high (left) or low (right) word kept
pub fn emitShf(mut e Emitter, i Instr):
	if e.usesFlags(i, i.flag(47), i.field(48, 2) != 0): return
	maxShift = i.field(37, 2)
	if maxShift == 1:
		e.lack(i, "SHF of an undefined width", [i.rd])
		return
	s = e.bits(i.b)
	limit = 32 if maxShift == 0 else 63
	amount = "({s} & {limit - 1})" if i.flag(50) else "{s}.min({limit})"
	right = i.op == .ShfR
	e.set(
		i.rd,
		"maxwell.funnelShift({e.x(i.ra)}, {e.x(i.c.reg)}, {amount}, {right}, {maxShift == 3})"
	)

# AND, OR, XOR, PASS_B
fn logic(a str, b str, op i64):
	["{a} & {b}", "{a} | {b}", "{a} ^ {b}", b.copy()][op]

# a predicate set from a logic result: false, true, zero, non-zero
fn predicateOp(v str, op i64):
	["false", "true", "{v} == 0", "{v} != 0"][op]

pub fn emitLop(mut e Emitter, i Instr):
	imm32 = i.form == .Imm32
	if e.usesFlags(i, i.flag(52 if imm32 else 47), i.flag(57 if imm32 else 43)): return
	a = e.x(i.ra)
	if i.flag(55 if imm32 else 39): a = "~{a}"
	b = e.bits(i.b)
	if i.flag(56 if imm32 else 40): b = "~{b}"
	op = i.field(53, 2) if imm32 else i.field(41, 2)
	e.set(i.rd, logic(a, b, op))
	if not imm32 and i.field(48, 3) != pt:
		e.setP(i.field(48, 3), predicateOp(e.x(i.rd), i.field(44, 2)))

pub fn emitLop3(mut e Emitter, i Instr):
	isReg = i.form == .Reg
	if e.usesFlags(i, i.flag(47), i.flag(38) if isReg else false): return
	table = i.field(28, 8) if isReg else i.field(48, 8)
	e.set(i.rd, "maxwell.lop3({e.x(i.ra)}, {e.bits(i.b)}, {e.x(i.c.reg)}, {table})")
	if isReg and i.field(48, 3) != pt:
		e.setP(i.field(48, 3), predicateOp(e.x(i.rd), i.field(36, 2)))

# BFE: B's low byte the offset, its second the count; BREV reverses A first
pub fn emitBfe(mut e Emitter, i Instr):
	if e.usesFlags(i, i.flag(47), false): return
	a = "maxwell.reverseBits({e.x(i.ra)})" if i.flag(40) else e.x(i.ra)
	b = e.bits(i.b)
	e.set(i.rd, "maxwell.extractBits({a}, {b} & 0xFF, ({b} >> 8) & 0xFF, {i.flag(48)})")

# BFI: A's low bits put into C at B's offset and count
pub fn emitBfi(mut e Emitter, i Instr):
	if e.usesFlags(i, i.flag(47), false): return
	b = e.bits(i.b)
	c = e.bits(i.c)
	e.set(i.rd, "maxwell.insertBits({c}, {e.x(i.ra)}, {b} & 0xFF, ({b} >> 8) & 0xFF)")

pub fn emitPopc(mut e Emitter, i Instr):
	b = "~{e.bits(i.b)}" if i.flag(40) else e.bits(i.b)
	e.set(i.rd, "maxwell.countBits({b})")

# FLO: the highest bit set's index (SH: counted from the top)
pub fn emitFlo(mut e Emitter, i Instr):
	if e.usesFlags(i, i.flag(47), false): return
	b = "~{e.bits(i.b)}" if i.flag(40) else e.bits(i.b)
	found = "maxwell.highestBit({b}, {i.flag(48)})"
	if i.flag(41):
		e.line("found = {found}")
		e.set(i.rd, "found ^ 31 if found != 0xFFFF_FFFF else found")
	else:
		e.set(i.rd, found)

# I2I of 8, 16 and 32-bit integers (the byte `selector` picks), saturated, negated, abs
pub fn emitI2i(mut e Emitter, i Instr):
	if e.usesFlags(i, i.flag(47), false): return
	srcWidth = [8, 16, 32, 0][i.field(10, 2)]
	dstWidth = [8, 16, 32, 0][i.field(8, 2)]
	if srcWidth == 0 or dstWidth == 0 or i.flag(50):
		e.lack(i, "I2I of width {i.field(10, 2)} to {i.field(8, 2)}, or saturated", [i.rd])
		return
	srcSigned = i.flag(13)
	v = "maxwell.extractBits({e.bits(i.b)}, {i.field(41, 2) * 8}, {srcWidth}, {srcSigned})"
	if i.flag(49) and srcSigned: v = "maxwell.absSigned({v})"
	if i.flag(45): v = "(0 - {v})"
	e.set(i.rd, "maxwell.extractBits({v}, 0, {dstWidth}, {i.flag(12)})" if dstWidth < 32 else v)

# Maxwell's integer comparison `op` (0 F, LT, EQ, LE, GT, NE, GE, 7 T), signed or not (i32.wrap:
# `i32(v) < 0` is refused, a language card)
pub fn intCompare(a str, b str, op i64, signed bool) str:
	l = "i32.wrap({a})" if signed else a
	r = "i32.wrap({b})" if signed and b != "0" else b
	[
		"false",
		"{l} < {r}",
		"{a} == {b}",
		"{l} <= {r}",
		"{l} > {r}",
		"{a} != {b}",
		"{l} >= {r}",
		"true"
	][op]

pub fn emitIsetp(mut e Emitter, i Instr):
	if e.usesFlags(i, false, i.flag(43)): return
	test = intCompare(e.x(i.ra), e.bits(i.b), i.field(49, 3), i.flag(48))
	e.setPredicates(i, test, e.pred(i.field(39, 3), i.flag(42)), i.field(45, 2))

pub fn emitIset(mut e Emitter, i Instr):
	if e.usesFlags(i, i.flag(47), i.flag(43)): return
	test = intCompare(e.x(i.ra), e.bits(i.b), i.field(49, 3), i.flag(48))
	test = combined(test, i.field(45, 2), e.pred(i.field(39, 3), i.flag(42)))
	e.set(i.rd, "{"0x3F80_0000" if i.flag(44) else "0xFFFF_FFFF"} if {test} else 0")

# ICMP: rd = A when C compares with 0 as asked, else B
pub fn emitIcmp(mut e Emitter, i Instr):
	test = intCompare(e.bits(i.c), "0", i.field(49, 3), i.flag(48))
	e.set(i.rd, "{e.x(i.ra)} if {test} else {e.bits(i.b)}")

pub fn emitImnmx(mut e Emitter, i Instr):
	if e.usesFlags(i, i.flag(47), false): return
	if i.field(43, 2) != 0:
		e.lack(i, "IMNMX extended mode", [i.rd])
		return
	choice = e.pred(i.field(39, 3), i.flag(42))
	a = e.x(i.ra)
	b = e.bits(i.b)
	if i.flag(48):
		e.set(i.rd, "u32(i32({a}).min(i32({b})) if {choice} else i32({a}).max(i32({b})))")
	else:
		e.set(i.rd, "{a}.min({b}) if {choice} else {a}.max({b})")

pub fn emitSel(mut e Emitter, i Instr):
	e.set(i.rd, "{e.x(i.ra)} if {e.pred(i.field(39, 3), i.flag(42))} else {e.bits(i.b)}")

pub fn emitMov(mut e Emitter, i Instr):
	e.set(i.rd, e.bits(i.b))
	if i.rd == rz: return
	if i.b.kind == .Imm: e.known[i.rd] = Known(value = i.b.imm & 0xFFFF_FFFF)
	if i.b.kind == .Cbuf: e.known[i.rd] = Known(bank = i.b.bank, word = i.b.offset / 4)

# the three predicates combined: (A op1 B) op2 C, A at 12, B at 29, C at 39
fn predicateSet(mut e Emitter, i Instr, negated bool):
	ab = combined(
		e.pred(i.field(12, 3), i.flag(15)),
		i.field(24, 2),
		e.pred(i.field(29, 3), i.flag(32))
	)
	combined("not ({ab})" if negated else ab, i.field(45, 2), e.pred(i.field(39, 3), i.flag(42)))

pub fn emitPsetp(mut e Emitter, i Instr):
	e.line("test = {e.predicateSet(i, false)}")
	e.setP(i.field(3, 3), "test")
	e.setP(i.field(0, 3), e.predicateSet(i, true))

pub fn emitPset(mut e Emitter, i Instr):
	if e.usesFlags(i, i.flag(47), false): return
	e.set(
		i.rd,
		"{"0x3F80_0000" if i.flag(44) else "0xFFFF_FFFF"} if {e.predicateSet(i, false)} else 0"
	)

# P2R: the predicates the mask names (B's low 7 bits) into A's byte `selector`
pub fn emitP2r(mut e Emitter, i Instr):
	if i.flag(40) or i.b.kind != .Imm:
		e.lack(i, "P2R of the condition codes or a mask not immediate", [i.rd])
		return
	mask = i.b.imm & 0x7F
	at = i.field(41, 2) * 8
	value = "({e.x(i.ra)} & {~(mask << at) & 0xFFFF_FFFF})"
	for p in 0..7:
		if (mask >> p) & 1 != 0:
			value = "{value} | ({1 << (p + at)} if {e.pred(p, false)} else 0)"
	e.set(i.rd, value)

# R2P: the predicates the mask names set from A's byte `selector`
pub fn emitR2p(mut e Emitter, i Instr):
	if i.flag(40) or i.b.kind != .Imm:
		e.lack(i, "R2P to the condition codes or a mask not immediate", [])
		return
	at = i.field(41, 2) * 8
	for p in 0..7:
		if (i.b.imm >> p) & 1 != 0:
			e.setP(p, "({e.x(i.ra)} >> {p + at}) & 1 != 0")
