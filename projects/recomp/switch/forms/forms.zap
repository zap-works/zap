# What the common instructions do, written once as Zap text: the translation writes an
# instruction's form with its fields as numbers (`c.x[3] = c.x[1] + u64(16)`), and the interpreter's
# functions for the same operations are written from the same forms with the fields read from the
# decoded instruction (`c.x[i.rd]`), every value of the attributes that shape the text (sf, the
# flags, an access's size and mode) one branch (interpreter.zap, written into cpu/forms.zap). The
# oracle checks the interpreter, and so the forms.

import recomp.switch.arm64

# the text of an instruction's fields: numbers when the translation knows them, the decoded
# instruction's fields when the interpreter reads them; `t` names the form's temporaries apart
pub type Fields:
	known bool
	rd str
	rn str
	rm str
	ra str
	imm str
	imm2 str
	shift str
	amount str
	size str
	opc str
	cond str
	t str
	m str   # what names core's functions where the form is written

# the fields of i at pc, as the translation writes them
pub fn knownFields(i arm64.Instr, pc i64) Fields:
	Fields(
		known = true,
		rd = "{i.rd}",
		rn = "{i.rn}",
		rm = "{i.rm}",
		ra = "{i.ra}",
		imm = "{i.imm}",
		imm2 = "{i.imm2}",
		shift = "{i.shift}",
		amount = "{i.amount}",
		size = "{i.size}",
		opc = "{i.opc}",
		cond = "{i.cond}",
		t = "t{pc:x}",
		m = "core."
	)

# the fields as the interpreter reads them from the decoded instruction `i`
pub fn readFields() Fields:
	Fields(
		known = false,
		rd = "i.rd",
		rn = "i.rn",
		rm = "i.rm",
		ra = "i.ra",
		imm = "i.imm",
		imm2 = "i.imm2",
		shift = "i.shift",
		amount = "i.amount",
		size = "i.size",
		opc = "i.opc",
		cond = "i.cond",
		t = "t",
		m = "core."
	)

# register r read, its low 32 bits when not sf (zr known as zero)
fn read(f Fields, r str, sf bool):
	if f.known and r == "{arm64.zr}": return "u64(0)"
	"c.x[{r}]" if sf else "(c.x[{r}] & 0xFFFF_FFFF)"

# register r set to value (cut to 32 bits when not sf); a write to zr dropped
fn write(f Fields, r str, value str, sf bool):
	if f.known and r == "{arm64.zr}": return []
	lines = ["c.x[{r}] = {value if sf else "({value}) & 0xFFFF_FFFF"}"]
	if not f.known: lines.push("c.x[{arm64.zr}] = 0")
	lines

# rd = x + y or x - y, with the flags when setFlags (AddWithCarry)
fn addLines(f Fields, x str, y str, sf bool, setFlags bool, subtract bool):
	if not setFlags: return f.write(f.rd, "{x} {"-" if subtract else "+"} {y}", sf)
	kept = f.write(f.rd, "{f.t}r", sf)
	result = "_" if kept.isEmpty else "{f.t}r"   # a compare's result dropped
	lines = [
		"{result}, {f.t}f = {f.m}addWithCarry({x}, {"~" if subtract else ""}{y}, {subtract}, {sf})",
		"c.setNzcv({f.t}f)"
	]
	lines.extend(kept)
	lines

# rm shifted as the instruction says (shifted's lsl, lsr, asr, ror), plain when known unshifted
fn shiftedRm(f Fields, sf bool):
	if f.known and f.amount == "0": return f.read(f.rm, sf)
	"{f.m}shifted({f.read(f.rm, sf)}, {f.shift}, {f.amount}, {sf})"

# rd = x op y for and, orr, eor, ands (opc), ands also setting N and Z
fn logicLines(f Fields, x str, y str, opc i64, sf bool):
	op = ["&", "|", "^", "&"][opc]
	if opc != 3: return f.write(f.rd, "{x} {op} {y}", sf)
	mask = "u64(-1)" if sf else "u64(0xFFFF_FFFF)"
	lines = ["{f.t}r = ({x} {op} {y}) & {mask}", "c.setNzcv({f.m}flagBit({f.m}isNegative({f.t}r, {sf})) << 3 | {f.m}flagBit({f.t}r == 0) << 2)"]
	lines.extend(f.write(f.rd, "{f.t}r", sf))
	lines

# an access's address and the lines before it (a pre- or post-index's write-back)
fn accessAddress(f Fields, mode arm64.Mode) (str[], str):
	base = "i64(c.x[{f.rn}])"
	match mode:
		Offset: ([], "{base} + {f.imm}")
		PreIndex: (["{f.t}a = {base} + {f.imm}", "c.x[{f.rn}] = u64({f.t}a)"], "{f.t}a")
		PostIndex: (["{f.t}a = {base}", "c.x[{f.rn}] = u64({f.t}a + {f.imm})"], "{f.t}a")
		RegisterOffset: (
			[],
			"{base} + i64({f.m}extended(c.x[{f.rm}], {f.shift}, {f.amount}, true))"
		)

# a call of core's function `name` on the thread: its method form in the interpreter, qualified in
# the game's code
fn onCpu(f Fields, name str, args str):
	"{f.m}{name}(c, {args})" if f.known else "c.{name}({args})"

# a load or a store of one register, general or vector, in any of the four modes
fn accessLines(i arm64.Instr, f Fields):
	lines = []
	if i.op == .Store and not i.vector: lines.push("{f.t}v = {f.read(f.rd, true)}")
	before, at = f.accessAddress(i.mode)
	lines.extend(before)
	if i.vector:
		lines.push(
			f.onCpu("loadVector" if i.op == .Load else "storeVector", "{f.rd}, {at}, {f.size}")
		)
	elif i.op == .Store:
		lines.push("{f.m}memory.store({at}, {f.size}, {f.t}v)")
	else:
		value = "{f.m}memory.load({at}, {f.size})"
		lines.extend(
			f.write(f.rd, "{f.m}signExtend({value}, {f.size}, {i.sf})" if i.signed else value, true)
		)
	lines

# lines as a block's body: `pass` when there are none
fn block(lines str[]):
	(lines if not lines.isEmpty else ["pass"]).map("	{it}")

# movn, movz, movk: the 16 bits at their place, inverted, alone or kept among the others
fn moveWideLines(i arm64.Instr, f Fields):
	v = "(u64({f.imm}) << {f.shift})"
	match i.opc:
		0: f.write(f.rd, "~{v}", i.sf)
		2: f.write(f.rd, v, i.sf)
		_: f.write(f.rd, "(c.x[{f.rd}] & ~(u64(0xFFFF) << {f.shift})) | {v}", i.sf)

# csel, csinc, csinv, csneg: rn when the condition holds, else rm as the operation leaves it
fn condSelectLines(i arm64.Instr, f Fields):
	y = f.read(f.rm, i.sf)
	other = [y, "{y} + 1", "~{y}", "0 - {y}"][i.opc]
	lines = ["if c.holds({f.cond}):"]
	lines.extend(block(f.write(f.rd, f.read(f.rn, i.sf), i.sf)))
	lines.push("else:")
	lines.extend(block(f.write(f.rd, other, i.sf)))
	lines

# a pair's element loaded from `at`, sign-extended when signed (ldpsw)
fn pairElement(f Fields, at str, signed bool):
	value = "{f.m}memory.load({at}, {f.size})"
	"{f.m}signExtend({value}, {f.size}, true)" if signed else value

# a pair of loads or stores, general or vector: the second element `1 << size` bytes on
fn pairLines(i arm64.Instr, f Fields):
	lines = []
	load = i.op == .LoadPair
	if not load and not i.vector:
		lines.push("{f.t}v = {f.read(f.rd, true)}")
		lines.push("{f.t}w = {f.read(f.ra, true)}")
	before, at = f.accessAddress(i.mode)
	lines.extend(before)
	second = "{at} + (1 << {f.size})"
	if i.vector:
		call = "loadVector" if load else "storeVector"
		lines.push(f.onCpu(call, "{f.rd}, {at}, {f.size}"))
		lines.push(f.onCpu(call, "{f.ra}, {second}, {f.size}"))
	elif not load:
		lines.push("{f.m}memory.store({at}, {f.size}, {f.t}v)")
		lines.push("{f.m}memory.store({second}, {f.size}, {f.t}w)")
	else:
		lines.push("{f.t}v = {f.pairElement(at, i.signed)}")
		lines.push("{f.t}w = {f.pairElement(second, i.signed)}")
		lines.extend(f.write(f.rd, "{f.t}v", true))
		lines.extend(f.write(f.ra, "{f.t}w", true))
	lines

# sbfm, bfm, ubfm: cpu's bitfieldOf over masks the translation computes now and the interpreter at
# each run
fn bitfieldLines(i arm64.Instr, f Fields):
	dst = f.read(f.rd, i.sf) if i.opc == 1 else "0"
	lines = []
	masks = "{f.t}w, {f.t}m"
	if f.known:
		w, t = arm64.bitMasks(i.sf, i.imm, i.imm2, i.sf, false) ?? (0, 0)
		width = u64(-1) if i.sf else u64(0xFFFF_FFFF)
		masks = "0x{u64(w) & width:x}, 0x{u64(t) & width:x}"   # where u64s are asked for
	else:
		lines.push("{masks} = {f.m}bitfieldMasks({f.imm}, {f.imm2}, {i.sf})")
	value = "{f.m}bitfieldOf({f.read(f.rn, i.sf)}, {dst}, {f.imm}, {f.imm2}, {masks}, {i.opc}, {i.sf})"
	lines.extend(f.write(f.rd, value, i.sf))
	lines

# madd, msub, smaddl, smsubl, smulh, umaddl, umsubl, umulh (opc as the decoder numbers them)
fn multiplyLines(i arm64.Instr, f Fields):
	a = f.read(f.ra, true)
	n = f.read(f.rn, true)
	m = f.read(f.rm, true)
	match i.opc:
		0: f.write(f.rd, "{a} + {n} * {m}", i.sf)
		1: f.write(f.rd, "{a} - {n} * {m}", i.sf)
		2: f.write(f.rd, "{a} + {f.m}mulSignedWords({n}, {m})", true)
		3: f.write(f.rd, "{a} - {f.m}mulSignedWords({n}, {m})", true)
		4: f.write(f.rd, "{f.m}mulHighSigned({n}, {m})", true)
		10: f.write(f.rd, "{a} + ({n} & 0xFFFF_FFFF) * ({m} & 0xFFFF_FFFF)", true)
		11: f.write(f.rd, "{a} - ({n} & 0xFFFF_FFFF) * ({m} & 0xFFFF_FFFF)", true)
		_: f.write(f.rd, "{f.m}mulHigh({n}, {m})", true)

# ccmp, ccmn (an immediate in rm when pair): the comparison's flags when the condition holds, else
# the instruction's own
fn condCompareLines(i arm64.Instr, f Fields):
	y = "u64({f.rm})" if i.pair else f.read(f.rm, i.sf)
	[
		"if c.holds({f.cond}):",
		"	_, {f.t}f = {f.m}addWithCarry({f.read(f.rn, i.sf)}, {"~" if i.subtract else ""}{y}, {i.subtract}, {i.sf})",
		"	c.setNzcv({f.t}f)",
		"else:",
		"	c.setNzcv(u64({f.imm}))"
	]

# adc, sbc (adcs, sbcs): the carry flag the carry in
fn addCarryLines(i arm64.Instr, f Fields):
	y = f.read(f.rm, i.sf)
	kept = f.write(f.rd, "{f.t}r", i.sf)
	result = "_" if kept.isEmpty else "{f.t}r"
	lines = ["{result}, {f.t}f = {f.m}addWithCarry({f.read(f.rn, i.sf)}, {"~" if i.subtract else ""}{y}, c.flagC, {i.sf})"]
	if i.setFlags: lines.push("c.setNzcv({f.t}f)")
	else: lines[0] = lines[0].replace("{f.t}f =", "_ =")
	lines.extend(kept)
	lines

# the scalar FP operations with forms: each a call of cpu/float.zap's exact arithmetic on the
# registers read in the instruction's format (cpu's float runs the others)
fn floatLines(i arm64.Instr, f Fields) str[]?:
	fmt = "{f.m}fmtOf({f.size})"
	a = f.onCpu("readFp", "{f.rn}, {fmt}")
	b = f.onCpu("readFp", "{f.rm}, {fmt}")
	put = (v str): [f.onCpu("writeFp", "{f.rd}, {v}")]
	width = 64 if i.sf else 32
	match i.fop:
		Move: put(a)
		Abs: put("{a} & ~{fmt}.signBit()")
		Neg: put("{a} ^ {fmt}.signBit()")
		Sqrt: put(f.onCpu("fpSqrt", "{fmt}, {a}"))
		Add, Sub, Mul, Div, Max, Min, MaxNum, MinNum: put(
			f.onCpu("fpArith", "{fmt}, .{i.fop}, {a}, {b}")
		)
		NegMul: put("{f.onCpu("fpMul", "{fmt}, {a}, {b}")} ^ {fmt}.signBit()")
		Compare: [
			"c.setNzcv({f.onCpu("fpCompare", "{fmt}, {a}, {"0" if i.pair else b}, {i.setFlags}")})"
		]
		Select: put("{a} if c.holds({f.cond}) else {b}")
		FromInt: put(f.onCpu("fpFromInt", "{fmt}, c.x[{f.rn}], {i.signed}, {width}, {f.imm2}"))
		ToInt: f.write(
			f.rd,
			f.onCpu("fpToInt", "{fmt}, {a}, {f.imm2}, {f.opc}, {i.signed}, {width}"),
			i.sf
		)
		_: none

# Whether a conditional branch is taken, as an expression; none for any other instruction.
pub fn branchTaken(i arm64.Instr, f Fields) str?:
	match i.op:
		BranchCond: "c.holds({f.cond})"
		CompareBranch: "{f.read(f.rd, i.sf)} {"==" if i.opc == 0 else "!="} 0"
		TestBranch: "(c.x[{f.rd}] >> {f.imm2}) & 1 {"!=" if i.opc == 1 else "=="} 0"
		_: none

# The lines of i's operation from its fields' text, none when its operation has no form here.
pub fn formLines(i arm64.Instr, f Fields) str[]?:
	match i.op:
		AddImm: f.addLines(f.read(f.rn, i.sf), "u64({f.imm})", i.sf, i.setFlags, i.subtract)
		AddShifted: f.addLines(f.read(f.rn, i.sf), f.shiftedRm(i.sf), i.sf, i.setFlags, i.subtract)
		LogicImm: f.logicLines(f.read(f.rn, i.sf), "u64({f.imm})", i.opc, i.sf)
		LogicShifted:
			y = f.shiftedRm(i.sf)
			f.logicLines(f.read(f.rn, i.sf), "~{y}" if i.subtract else y, i.opc, i.sf)
		Load, Store: i.accessLines(f)
		LoadPair, StorePair: i.pairLines(f)
		MoveWide: i.moveWideLines(f)
		Adr: f.write(f.rd, "u64({f.imm})", true)
		CondSelect: i.condSelectLines(f)
		AddExtended:
			y = "{f.m}extended(c.x[{f.rm}], {f.shift}, {f.amount}, {i.sf})"
			f.addLines(f.read(f.rn, i.sf), y, i.sf, i.setFlags, i.subtract)
		AddCarry: i.addCarryLines(f)
		Bitfield: i.bitfieldLines(f)
		Extract: f.write(
			f.rd,
			"{f.m}extractOf({f.read(f.rm, i.sf)}, {f.read(f.rn, i.sf)}, {f.imm}, {i.sf})",
			i.sf
		)
		CondCompare: i.condCompareLines(f)
		ThreeSource: i.multiplyLines(f)
		Float: i.floatLines(f)
		BranchCond, CompareBranch, TestBranch:
			lines = ["if {i.branchTaken(f) ?? "false"}:"]
			lines.push("	c.pc = {f.imm}")
			lines
		_: none
