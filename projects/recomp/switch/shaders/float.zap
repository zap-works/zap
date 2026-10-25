# The float instructions translated (fields as yuzu's floating_point_*.cpp and Ryujinx's
# InstEmitFArith read them): FADD, FMUL, FFMA, FMNMX, MUFU, RRO, FSETP, FSET, FCMP, F2I, I2F, F2F,
# and of f64 (double.zap's register pairs) DMNMX, DSET, DSETP, the conversions and MUFU's RCP64H
# and RSQ64H.

import recomp.switch.arm64

fn flag(i Instr, at i64):
	arm64.hasBit(i.word, at)

fn field(i Instr, at i64, width i64):
	arm64.bits(i.word, at, width)

# a value with Maxwell's abs and negation applied
fn absNeg(v str, abs bool, neg bool):
	a = "{v}.abs()" if abs else v
	"-{a}" if neg else a

fn saturated(v str, sat bool):
	"({v}).clamp(0.0, 1.0)" if sat else v

# A conversion's rounding modes but the nearest even are not translated. Arithmetic (FADD, FMUL,
# FFMA) rounds to the nearest whatever it asks, as yuzu's GLSL and SPIR-V backends do: the
# results differ in the last bit at most.
fn roundsNearest(mut e Emitter, i Instr, rounding i64):
	if rounding == 0: return true
	e.lack(i, "rounding mode {rounding}", [i.rd])
	false

fn product(a str, b str, fmz bool):
	"maxwell.mulZero({a}, {b})" if fmz else "{a} * {b}"

pub fn emitFadd(mut e Emitter, i Instr):
	if i.form == .Imm32:
		a = absNeg(e.f(i.ra), i.flag(54), i.flag(56))
		e.setF(i.rd, "{a} + {absNeg(e.float(i.b), i.flag(57), i.flag(53))}")
		return
	a = absNeg(e.f(i.ra), i.flag(46), i.flag(48))
	b = absNeg(e.float(i.b), i.flag(49), i.flag(45))
	e.setF(i.rd, saturated("{a} + {b}", i.flag(50)))

# FMUL's scale of a (Ryujinx's FPMultiplyScale): none, /2, /4, /8, *8, *4, *2
scales = ["", " * 0.5", " * 0.25", " * 0.125", " * 8.0", " * 4.0", " * 2.0", ""]

pub fn emitFmul(mut e Emitter, i Instr):
	if i.form == .Imm32:
		e.setF(i.rd, saturated(product(e.f(i.ra), e.float(i.b), i.field(53, 2) == 2), i.flag(55)))
		return
	b = absNeg(e.float(i.b), false, i.flag(48))
	a = "({e.f(i.ra)}{scales[i.field(41, 3)]})" if i.field(41, 3) != 0 else e.f(i.ra)
	e.setF(i.rd, saturated(product(a, b, i.field(44, 2) == 2), i.flag(50)))

# FFMA's C is the destination in FFMA32I
pub fn emitFfma(mut e Emitter, i Instr):
	if i.form == .Imm32:
		a = absNeg(e.f(i.ra), false, i.flag(56))
		c = absNeg(e.f(i.rd), false, i.flag(57))
		sum = "{product(a, e.float(i.b), i.field(53, 2) == 2)} + {c}"
		e.setF(i.rd, saturated(sum, i.flag(55)))
		return
	b = absNeg(e.float(i.b), false, i.flag(48))
	c = absNeg(e.float(i.c), false, i.flag(49))
	sum = "{product(e.f(i.ra), b, i.field(53, 2) == 2)} + {c}"
	e.setF(i.rd, saturated(sum, i.flag(50)))

# A and B of a float operation, register pairs' f64s when `wide` (DMNMX, DSET, DSETP: their
# fields are FMNMX's, FSET's and FSETP's)
fn operandA(mut e Emitter, i Instr, wide bool) str:
	e.d(i.ra) if wide else e.f(i.ra)

fn operandB(mut e Emitter, i Instr, wide bool) str:
	e.double(i.b) if wide else e.float(i.b)

# FMNMX, DMNMX: the predicate at 39 (negated by 42): the less when it holds, the greater when not
pub fn emitMinMax(mut e Emitter, i Instr, wide bool):
	a = absNeg(e.operandA(i, wide), i.flag(46), i.flag(48))
	b = absNeg(e.operandB(i, wide), i.flag(49), i.flag(45))
	choice = e.pred(i.field(39, 3), i.flag(42))
	value = "({a}).min({b}) if {choice} else ({a}).max({b})"
	if choice == "true" or choice == "false":
		value = "({a}).{"min" if choice == "true" else "max"}({b})"
	e.setFloat(i.rd, value, wide)

mufus = ["cos", "sin", "exp2", "log2", "rcp", "inverseSqrt", "", "", "sqrt"]

pub fn emitMufu(mut e Emitter, i Instr):
	op = i.field(20, 4)
	if op == 6 or op == 7:
		# RCP64H, RSQ64H: the high word of what the double of high word A (its low one 0) gives
		high = e.x(i.ra)
		if op == 6:
			e.set(i.rd, "(1.0 / f64.fromWords(0, {high})).highWord()")
		else:
			e.set(i.rd, "maxwell.rsqrtHigh({high})")
		return
	name = mufus[op] if op < mufus.len else ""
	if name == "":
		e.lack(i, "MUFU operation {op}", [i.rd])
		return
	a = absNeg(e.f(i.ra), i.flag(46), i.flag(48))
	value = "1.0 / {a}" if name == "rcp" else "({a}).{name}()"
	e.setF(i.rd, saturated(value, i.flag(50)))

# RRO prepares MUFU's operand; MUFU here takes the value itself (yuzu's reading)
pub fn emitRro(mut e Emitter, i Instr):
	e.setF(i.rd, absNeg(e.float(i.b), i.flag(49), i.flag(45)))

# Maxwell's float comparison `op` (0 F, LT EQ LE GT NE GE, NUM, NAN, LTU EQU LEU GTU NEU GEU, 15
# T): the U forms hold when either is a NaN
pub fn floatCompare(a str, b str, op i64) str:
	ordered = [
		"false",
		"{a} < {b}",
		"{a} == {b}",
		"{a} <= {b}",
		"{a} > {b}",
		"({a} < {b} or {a} > {b})",
		"{a} >= {b}"
	]
	match op:
		0..7: ordered[op]
		7: "({a} == {a} and {b} == {b})"
		8: "({a} != {a} or {b} != {b})"
		15: "true"
		_: "not ({ordered[op - 8]})" if op != 13 else "{a} != {b}"

# the comparison combined with predicate c (BooleanOp: AND, OR, XOR)
pub fn combined(test str, op i64, c str) str:
	if c == "true" and op == 0: return test.copy()
	if c == "false" and op == 1: return test.copy()
	["({test}) and {c}", "({test}) or {c}", "({test}) != {c}", "false"][op]

# FSETP, DSETP
pub fn emitSetp(mut e Emitter, i Instr, wide bool):
	a = absNeg(e.operandA(i, wide), i.flag(7), i.flag(43))
	b = absNeg(e.operandB(i, wide), i.flag(44), i.flag(6))
	test = floatCompare(a, b, i.field(48, 4))
	c = e.pred(i.field(39, 3), i.flag(42))
	e.setPredicates(i, test, c, i.field(45, 2))

# a set-predicate's two results: A the test combined, B its negation combined
pub fn setPredicates(mut e Emitter, i Instr, test str, c str, op i64):
	e.line("test = {test}")
	e.setP(i.field(3, 3), combined("test", op, c))
	e.setP(i.field(0, 3), combined("not test", op, c))

# FSET, DSET
pub fn emitSet(mut e Emitter, i Instr, wide bool):
	a = absNeg(e.operandA(i, wide), i.flag(54), i.flag(43))
	b = absNeg(e.operandB(i, wide), i.flag(44), i.flag(53))
	test = combined(
		floatCompare(a, b, i.field(48, 4)),
		i.field(45, 2),
		e.pred(i.field(39, 3), i.flag(42))
	)
	e.set(i.rd, "{"0x3F80_0000" if i.flag(52) else "0xFFFF_FFFF"} if {test} else 0")

# rd = ra when C compares with 0 as asked, else B
pub fn emitFcmp(mut e Emitter, i Instr):
	test = floatCompare(e.float(i.c), "0.0", i.field(48, 4))
	e.set(i.rd, "{e.x(i.ra)} if {test} else {e.bits(i.b)}")

fn rounded(v str, mode i64):
	["maxwell.roundEven({v})", "({v}).floor()", "({v}).ceil()", "({v}).trunc()"][mode]

# F2I from an f32 or an f64 to 16 or 32 bits: a 16-bit result saturates to its range first
pub fn emitF2i(mut e Emitter, i Instr):
	to = i.field(8, 2)
	from = i.field(10, 2)
	if (to != 1 and to != 2) or (from != 2 and from != 3):
		e.lack(i, "F2I of formats {from} to {to} (f16, 64-bit)", [i.rd])
		return
	signed = i.flag(12)
	mode = i.field(39, 2)
	v = ""
	if from == 3:
		v = "maxwell.roundDouble({absNeg(e.double(i.b), i.flag(45), i.flag(49))}, {mode})"
	else:
		v = rounded(absNeg(e.float(i.b), i.flag(45), i.flag(49)), mode)
	if to == 1: v = "({v}).clamp({"-32768.0, 32767.0" if signed else "0.0, 65535.0"})"
	e.set(i.rd, "maxwell.{"doubleToInt" if from == 3 else "floatToInt"}({v}, {signed})")

# I2F to an f32 or an f64 (exact, whatever the rounding) of an 8-, 16- or 32-bit integer (the
# byte `selector` picks)
pub fn emitI2f(mut e Emitter, i Instr):
	to = i.field(8, 2)
	if (to != 2 and to != 3) or i.field(10, 2) == 3:
		e.lack(i, "I2F of formats {i.field(10, 2)} to {to} (f16, 64-bit)", [i.rd])
		return
	if to == 2 and not e.roundsNearest(i, i.field(39, 2)): return
	signed = i.flag(13)
	width = [8, 16, 32][i.field(10, 2)]
	source = e.bits(i.b)
	if width < 32:
		source = "maxwell.extractBits({source}, {i.field(41, 2) * 8}, {width}, {signed})"
	kind = "f64" if to == 3 else "f32"
	v = "{kind}(i32({source}))" if signed else "{kind}({source})"
	e.setFloat(i.rd, absNeg(v, i.flag(49), i.flag(45)), to == 3)

# F2F between f32 and f64: within a size a rounding to an integer, or a pass that keeps NaNs as
# the hardware does; across, the value converted (to an f32 by the nearest)
pub fn emitF2f(mut e Emitter, i Instr):
	to = i.field(8, 2)
	from = i.field(10, 2)
	if (to != 2 and to != 3) or (from != 2 and from != 3):
		e.lack(i, "F2F of formats {from} to {to} (f16)", [i.rd])
		return
	v = absNeg(e.double(i.b) if from == 3 else e.float(i.b), i.flag(49), i.flag(45))
	if to != from:
		if to == 2 and not e.roundsNearest(i, i.field(39, 2)): return
		value = saturated("{"f32" if to == 2 else "f64"}({v})", i.flag(50))
		e.setFloat(i.rd, value, to == 3)
		return
	op = i.field(39, 4)
	if op >= 8 and op <= 11:
		v = "maxwell.roundDouble({v}, {op - 8})" if to == 3 else rounded(v, op - 8)
	value = saturated("{v} + 0.0" if op < 8 else v, i.flag(50))
	e.setFloat(i.rd, value, to == 3)
