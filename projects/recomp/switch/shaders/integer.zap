# The integer, logic and predicate instructions translated (fields as yuzu's integer_*.cpp,
# logic_operation*.cpp and predicate_*.cpp read them): SHL, SHR, SHF, LOP, LOP3, BFE, BFI, POPC,
# FLO, I2I, ISETP, ISET, ICMP, IMNMX, SEL, MOV, PSETP, PSET, P2R, R2P (sums: sums.zap). A register
# is u32: a sum wraps as the hardware's does, a signed test reads it as i32. CC sets the zero and
# sign codes of the result (Ryujinx's SetZnFlags), X keeps zero only when the words below were zero.

# X of a shift or a funnel shift (no reference reads it) is noted
fn shiftsCarry(mut e Emitter, i Instr, x bool):
	if not x: return false
	e.lack(i, "{i.op}.X", [i.rd])
	true

# SHL: W wraps the shift to its low 5 bits, else a shift past 31 gives 0
pub fn emitShl(mut e Emitter, i Instr):
	if e.shiftsCarry(i, i.flag(43)): return
	a = e.x(i.ra)
	cc = i.flag(47)
	if i.b.kind == .Imm:
		n = i.shiftOf()
		e.setCoded(i.rd, "{a} << {n}" if n < 32 else "0", cc, false)
		return
	s = e.bits(i.b)
	value = "{a} << ({s} & 31)" if i.flag(39) else "0 if {s} > 31 else {a} << {s}"
	e.setCoded(i.rd, value, cc, false)

# an immediate shift, wrapped when W
fn shiftOf(i Instr):
	n = i.b.imm & 0xFFFF_FFFF
	n & 31 if i.flag(39) else n

# SHR: signed or not, W as SHL's, BREV reversing A first
pub fn emitShr(mut e Emitter, i Instr):
	if e.shiftsCarry(i, i.flag(43)): return
	e.setCoded(i.rd, e.shiftedRight(i), i.flag(47), false)

fn shiftedRight(mut e Emitter, i Instr):
	a = "maxwell.reverseBits({e.x(i.ra)})" if i.flag(40) else e.x(i.ra)
	signed = i.flag(48)
	if i.b.kind == .Imm:
		n = i.shiftOf()
		if signed: return "u32(i32({a}) >> {n.min(31)})"
		return "{a} >> {n}" if n < 32 else "0"
	s = e.bits(i.b)
	amount = "({s} & 31)" if i.flag(39) else "{s}.min(31)"
	if signed: return "u32(i32({a}) >> {amount})"
	if i.flag(39): return "{a} >> {amount}"
	"0 if {s} > 31 else {a} >> {s}"

# SHF: the 64 bits C:A shifted by B, the high (left) or low (right) word kept
pub fn emitShf(mut e Emitter, i Instr):
	if e.shiftsCarry(i, i.field(48, 2) != 0): return
	maxShift = i.field(37, 2)
	if maxShift == 1:
		e.lack(i, "SHF of an undefined width", [i.rd])
		return
	s = e.bits(i.b)
	limit = 32 if maxShift == 0 else 63
	amount = "({s} & {limit - 1})" if i.flag(50) else "{s}.min({limit})"
	right = i.op == .ShfR
	value = "maxwell.funnelShift({e.x(i.ra)}, {e.x(i.c.reg)}, {amount}, {right}, {maxShift == 3})"
	e.setCoded(i.rd, value, i.flag(47), false)

# AND, OR, XOR, PASS_B
fn logic(a str, b str, op i64):
	["{a} & {b}", "{a} | {b}", "{a} ^ {b}", b.copy()][op]

# a predicate set from a logic result: false, true, zero, non-zero
fn predicateOp(v str, op i64):
	["false", "true", "{v} == 0", "{v} != 0"][op]

pub fn emitLop(mut e Emitter, i Instr):
	imm32 = i.form == .Imm32
	a = e.x(i.ra)
	if i.flag(55 if imm32 else 39): a = "~{a}"
	b = e.bits(i.b)
	if i.flag(56 if imm32 else 40): b = "~{b}"
	op = i.field(53, 2) if imm32 else i.field(41, 2)
	e.setCoded(i.rd, logic(a, b, op), i.flag(52 if imm32 else 47), i.flag(57 if imm32 else 43))
	if not imm32 and i.field(48, 3) != pt:
		e.setP(i.field(48, 3), predicateOp(e.x(i.rd), i.field(44, 2)))

pub fn emitLop3(mut e Emitter, i Instr):
	isReg = i.form == .Reg
	table = i.field(28, 8) if isReg else i.field(48, 8)
	value = "maxwell.lop3({e.x(i.ra)}, {e.bits(i.b)}, {e.x(i.c.reg)}, {table})"
	e.setCoded(i.rd, value, i.flag(47), i.flag(38) if isReg else false)
	if isReg and i.field(48, 3) != pt:
		e.setP(i.field(48, 3), predicateOp(e.x(i.rd), i.field(36, 2)))

# BFE: B's low byte the offset, its second the count; BREV reverses A first
pub fn emitBfe(mut e Emitter, i Instr):
	a = "maxwell.reverseBits({e.x(i.ra)})" if i.flag(40) else e.x(i.ra)
	b = e.bits(i.b)
	value = "maxwell.extractBits({a}, {b} & 0xFF, ({b} >> 8) & 0xFF, {i.flag(48)})"
	e.setCoded(i.rd, value, i.flag(47), false)

# BFI: A's low bits put into C at B's offset and count
pub fn emitBfi(mut e Emitter, i Instr):
	b = e.bits(i.b)
	c = e.bits(i.c)
	value = "maxwell.insertBits({c}, {e.x(i.ra)}, {b} & 0xFF, ({b} >> 8) & 0xFF)"
	e.setCoded(i.rd, value, i.flag(47), false)

pub fn emitPopc(mut e Emitter, i Instr):
	b = "~{e.bits(i.b)}" if i.flag(40) else e.bits(i.b)
	e.set(i.rd, "maxwell.countBits({b})")

# FLO: the highest bit set's index (SH: counted from the top)
pub fn emitFlo(mut e Emitter, i Instr):
	b = "~{e.bits(i.b)}" if i.flag(40) else e.bits(i.b)
	found = "maxwell.highestBit({b}, {i.flag(48)})"
	if i.flag(41):
		e.line("found = {found}")
		found = "found ^ 31 if found != 0xFFFF_FFFF else found"
	e.setCoded(i.rd, found, i.flag(47), false)

# I2I of 8, 16 and 32-bit integers (the byte `selector` picks), negated, abs, saturated to the
# destination's range (yuzu's SaturateInteger); CC also clears carry and overflow
pub fn emitI2i(mut e Emitter, i Instr):
	srcWidth = [8, 16, 32, 0][i.field(10, 2)]
	dstWidth = [8, 16, 32, 0][i.field(8, 2)]
	if srcWidth == 0 or dstWidth == 0:
		e.lack(i, "I2I of width {i.field(10, 2)} to {i.field(8, 2)}", [i.rd])
		return
	srcSigned = i.flag(13)
	dstSigned = i.flag(12)
	v = "maxwell.extractBits({e.bits(i.b)}, {i.field(41, 2) * 8}, {srcWidth}, {srcSigned})"
	if i.flag(49) and srcSigned: v = "maxwell.absSigned({v})"
	if i.flag(45): v = "(0 - {v})"
	if i.flag(50):
		v = "maxwell.saturateInt({v}, {dstWidth}, {srcSigned}, {dstSigned})"
	elif dstWidth < 32:
		v = "maxwell.extractBits({v}, 0, {dstWidth}, {dstSigned})"
	cc = i.flag(47)
	e.setCoded(i.rd, v, cc, false)
	if cc:
		e.setFlag(2, "false")
		e.setFlag(3, "false")

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

# The comparison of X (the high words of numbers whose lower words a subtraction before compared,
# its zero and carry codes: carry when no borrow), as Ryujinx's GetIntComparisonExtended.
fn extendedCompare(mut e Emitter, a str, b str, op i64, signed bool):
	if op == 0 or op == 7: return intCompare(a, b, op, signed)
	l = "i32.wrap({a})" if signed else a
	r = "i32.wrap({b})" if signed else b
	same = "{a} == {b}"
	z = e.cc(0)
	c = e.cc(2)
	[
		"",
		"({l} < {r} or ({same} and not {c}))",
		"({same} and {z})",
		"({l} < {r} or ({same} and ({z} or not {c})))",
		"({l} > {r} or ({same} and not {z} and {c}))",
		"({a} != {b} or not {z})",
		"({l} > {r} or ({same} and {c}))"
	][op]

fn compared(mut e Emitter, i Instr):
	a = e.x(i.ra)
	b = e.bits(i.b)
	if i.flag(43): return e.extendedCompare(a, b, i.field(49, 3), i.flag(48))
	intCompare(a, b, i.field(49, 3), i.flag(48))

pub fn emitIsetp(mut e Emitter, i Instr):
	e.setPredicates(i, e.compared(i), e.pred(i.field(39, 3), i.flag(42)), i.field(45, 2))

pub fn emitIset(mut e Emitter, i Instr):
	test = combined(e.compared(i), i.field(45, 2), e.pred(i.field(39, 3), i.flag(42)))
	value = "{"0x3F80_0000" if i.flag(44) else "0xFFFF_FFFF"} if {test} else 0"
	e.setCoded(i.rd, value, i.flag(47), false)

# ICMP: rd = A when C compares with 0 as asked, else B
pub fn emitIcmp(mut e Emitter, i Instr):
	test = intCompare(e.bits(i.c), "0", i.field(49, 3), i.flag(48))
	e.set(i.rd, "{e.x(i.ra)} if {test} else {e.bits(i.b)}")

# IMNMX: the extended modes (XLO, XMED, XHI at 43) choose as the plain one, Ryujinx's reading (no
# reference documents them)
pub fn emitImnmx(mut e Emitter, i Instr):
	choice = e.pred(i.field(39, 3), i.flag(42))
	a = e.x(i.ra)
	b = e.bits(i.b)
	signed = "u32(i32({a}).min(i32({b})) if {choice} else i32({a}).max(i32({b})))"
	value = signed if i.flag(48) else "{a}.min({b}) if {choice} else {a}.max({b})"
	e.setCoded(i.rd, value, i.flag(47), false)

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
	value = "{"0x3F80_0000" if i.flag(44) else "0xFFFF_FFFF"} if {e.predicateSet(i, false)} else 0"
	e.setCoded(i.rd, value, i.flag(47), false)

# P2R and R2P move the predicates (or with CC at 40 the condition codes) that the mask names (B's
# low bits) to and from A's byte `selector`
fn moved(mut e Emitter, i Instr, k i64) str:
	e.cc(k) if i.flag(40) else e.pred(k, false)

fn movedCount(i Instr):
	4 if i.flag(40) else 7

pub fn emitP2r(mut e Emitter, i Instr):
	at = i.field(41, 2) * 8
	count = i.movedCount()
	if i.b.kind == .Imm:
		mask = i.b.imm & ((1 << count) - 1)
		value = "({e.x(i.ra)} & {~(mask << at) & 0xFFFF_FFFF})"
		for k in 0..count:
			if (mask >> k) & 1 != 0:
				value = "{value} | ({1 << (k + at)} if {e.moved(i, k)} else 0)"
		e.set(i.rd, value)
		return
	e.line("mask = ({e.bits(i.b)} & {(1 << count) - 1}) << {at}")
	moved = "0"
	for k in 0..count:
		moved = "{moved} | ({1 << (k + at)} if {e.moved(i, k)} else 0)"
	e.set(i.rd, "({e.x(i.ra)} & ~mask) | (({moved}) & mask)")

pub fn emitR2p(mut e Emitter, i Instr):
	at = i.field(41, 2) * 8
	known = i.b.kind == .Imm
	if not known: e.line("mask = {e.bits(i.b)}")
	for k in 0..i.movedCount():
		if known and (i.b.imm >> k) & 1 == 0: continue
		value = "({e.x(i.ra)} >> {k + at}) & 1 != 0"
		if not known: value = "{value} if (mask >> {k}) & 1 != 0 else {e.moved(i, k)}"
		if i.flag(40):
			e.setFlag(k, value)
		else:
			e.setP(k, value)

# PRMT: bytes of C:A (A the low four) picked by B (its nibbles, or a mode at 48)
pub fn emitPrmt(mut e Emitter, i Instr):
	e.set(
		i.rd,
		"maxwell.permuteBytes({e.x(i.ra)}, {e.bits(i.c)}, {e.bits(i.b)}, {i.field(48, 3)})"
	)
