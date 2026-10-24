# Each instruction that is no jump as Zap statements over the cpu module's registers and flags and
# the console's memory, in the widths it was read in: an 8-bit register is the low byte of its
# 16 (u8.wrap of it), an 8-bit index register's high byte always 0. A flag is written only where
# a later instruction reads it (flags.zap).

# the register an instruction's name ends in, and whether it is 16 bits wide in the widths
fn registerOf(i Instr):
	r = i.name[2..3]
	match r:
		"x", "y": (r.copy(), not i.widths.x)
		_: ("a", not i.widths.m)

fn typeOf(wide bool):
	"u16" if wide else "u8"

fn signBit(wide bool):
	"0x8000" if wide else "0x80"

pub fn readReg(r str, wide bool) str:
	"cpu.{r}" if wide else "u8.wrap(cpu.{r})"

fn writeReg(mut ft FnText, depth i64, r str, wide bool, value str):
	if wide:
		ft.put(depth, "cpu.{r} = {value}")
	elif r == "a":
		ft.put(depth, "cpu.a = (cpu.a & 0xFF00) | u16({value})")
	else:
		ft.put(depth, "cpu.{r} = u16({value})")

# n and z from a value, those live
fn setNz(mut ft FnText, depth i64, live i64, value str, wide bool):
	if live & flagN != 0: ft.put(depth, "cpu.n = {value} & {signBit(wide)} != 0")
	if live & flagZ != 0: ft.put(depth, "cpu.z = {value} == 0")

# a value bound to a temporary of the width when flags read it, else the value itself
fn bound(mut ft FnText, depth i64, value str, wide bool, needed bool):
	if not needed: return value.copy()
	t = ft.temp("v")
	ft.put(depth, "{t} {typeOf(wide)} = {value}")
	t

# the register given a value, its flags set
fn load(mut ft FnText, depth i64, r str, wide bool, value str, live i64):
	v = ft.bound(depth, value, wide, live & (flagN | flagZ) != 0)
	ft.writeReg(depth, r, wide, v)
	ft.setNz(depth, live, v, wide)

pub fn operation(mut ft FnText, depth i64, i Instr, live i64):
	match i.name:
		"lda", "ldx", "ldy":
			r, wide = i.registerOf()
			ft.load(depth, r, wide, ft.operandValue(depth, i, wide), live)
		"sta", "stx", "sty", "stz":
			r, wide = i.registerOf()
			value = "0" if i.name == "stz" else readReg(r, wide)
			ft.store(depth, i, wide, value)
		"and", "ora", "eor":
			wide = not i.widths.m
			op = match i.name:
				"and": "&"
				"ora": "|"
				_: "^"
			value = "{readReg("a", wide)} {op} {ft.operandValue(depth, i, wide)}"
			ft.load(depth, "a", wide, value, live)
		"adc", "sbc":
			wide = not i.widths.m
			ft.put(
				depth,
				"cpu.{i.name}{"16" if wide else "8"}({ft.operandValue(depth, i, wide)})"
			)
		"cmp", "cpx", "cpy":
			r, wide = i.registerOf()
			value = ft.operandValue(depth, i, wide)
			if live & (flagN | flagZ | flagC) != 0:
				ft.put(depth, "cpu.compare{"16" if wide else "8"}({readReg(r, wide)}, {value})")
			elif not isImmediate(i.mode):
				ft.put(depth, "_ = {value}")
		"bit": ft.bit(depth, i, live)
		_: ft.otherOperation(depth, i, live)

fn otherOperation(mut ft FnText, depth i64, i Instr, live i64):
	match i.name:
		"inc", "dec", "asl", "lsr", "rol", "ror", "tsb", "trb": ft.modify(depth, i, live)
		"inx", "iny", "dex", "dey":
			r = i.name[2..3]
			wide = not i.widths.x
			ft.load(
				depth,
				r,
				wide,
				"{readReg(r, wide)} {"+" if i.name[1] == 'n' else "-"} 1",
				live
			)
		"tax", "tay", "txa", "tya", "txy", "tyx", "tsx", "txs", "tcs", "tsc", "tcd", "tdc", "xba":
			ft.transfer(depth, i, live)
		"clc", "sec", "cli", "sei", "cld", "sed", "clv", "rep", "sep", "xce": ft.flagOperation(
			depth,
			i
		)
		"wai": ft.put(
			depth,
			"if cpu.wait({i.nextText()}, {i.widths.statusWidths()}): {ft.returnText}"
		)
		"brk", "cop":
			call = "cpu.softwareInterrupt({i.atText()}, {i.name == "cop"}, {i.widths.statusWidths()})"
			ft.put(depth, "if {call}: {ft.returnText}")
			# the code after it is no part of the flow: the translated function goes on through the dispatcher
			if not i.symbolic:
				ft.put(depth, "cpu.go({i.nextText()}, {i.widths.widthBits()})")
				ft.put(depth, "return")
		"stp": ft.put(depth, "cpu.unsupported({i.atText()}, \"{i.name}\")")
		"mvn", "mvp":
			step = 1 if i.name == "mvn" else -1
			ft.put(
				depth,
				"if cpu.moveBlock({i.blockBank(true)}, {i.blockBank(false)}, {step}, {i.widths.statusWidths()}, {i.atText()}): {ft.returnText}"
			)
		"nop", "wdm": pass
		_: ft.stackOperation(depth, i, live)

# bit: z from the accumulator and the operand; from memory n and v from the operand's top bits
fn bit(mut ft FnText, depth i64, i Instr, live i64):
	wide = not i.widths.m
	needed = live & (flagN | flagV | flagZ)
	value = ft.operandValue(depth, i, wide)
	if needed == 0:
		if not isImmediate(i.mode): ft.put(depth, "_ = {value}")
		return
	v = ft.bound(depth, value, wide, true)
	if not isImmediate(i.mode):
		if live & flagN != 0: ft.put(depth, "cpu.n = {v} & {signBit(wide)} != 0")
		if live & flagV != 0: ft.put(depth, "cpu.v = {v} & {"0x4000" if wide else "0x40"} != 0")
	if live & flagZ != 0: ft.put(depth, "cpu.z = {readReg("a", wide)} & {v} == 0")

# A read, a change and a write back, of the accumulator or of memory: inc, dec, the shifts and
# rotations, tsb and trb.
fn modify(mut ft FnText, depth i64, i Instr, live i64):
	wide = not i.widths.m
	place = ft.placeOf(depth, i, wide)
	old = ft.bound(depth, place.read, wide, true)
	top = signBit(wide)
	carryIn = "(1 if cpu.c else 0)" if i.name == "rol" else "({top} if cpu.c else 0)"
	result = match i.name:
		"inc": "{old} + 1"
		"dec": "{old} - 1"
		"asl": "{old} << 1"
		"lsr": "{old} >> 1"
		"rol": "({old} << 1) | {carryIn}"
		"ror": "({old} >> 1) | {carryIn}"
		"tsb": "{old} | {readReg("a", wide)}"
		_: "{old} & ~{readReg("a", wide)}"
	if i.name == "tsb" or i.name == "trb":
		if live & flagZ != 0: ft.put(depth, "cpu.z = {old} & {readReg("a", wide)} == 0")
		ft.writePlace(depth, place, result)
		return
	r = ft.bound(depth, result, wide, true)
	if live & flagC != 0 and i.name != "inc" and i.name != "dec":
		shiftsLeft = i.name == "asl" or i.name == "rol"
		if ft.patches.get(i.at) is Carry(_, _, text):
			ft.put(depth, "cpu.c = {text.replace("\{old}", old)}")
		else:
			ft.put(depth, "cpu.c = {old} & {top} != 0" if shiftsLeft else "cpu.c = {old} & 1 != 0")
	ft.writePlace(depth, place, r)
	ft.setNz(depth, live, r, wide)

# The transfers between registers: to an index register as wide as X says, to the accumulator
# as M says (tcs, tsc, tcd, tdc and xba all 16 bits), the flags from what is written.
fn transfer(mut ft FnText, depth i64, i Instr, live i64):
	m16 = not i.widths.m
	x16 = not i.widths.x
	match i.name:
		"tax", "tay": ft.load(depth, i.name[2..3], x16, readReg("a", x16), live)
		"txa", "tya": ft.load(depth, "a", m16, readReg(i.name[1..2], m16), live)
		"txy", "tyx": ft.load(depth, i.name[2..3], x16, readReg(i.name[1..2], x16), live)
		"tsx": ft.load(depth, "x", x16, readReg("s", x16), live)
		"txs", "tcs":
			r = "x" if i.name == "txs" else "a"
			to = "0x100 | (cpu.{r} & 0xFF)" if i.widths.e else "cpu.{r}"
			ft.put(depth, "cpu.setStack({to})")
		"tsc": ft.load(depth, "a", true, "cpu.s", live)
		"tcd": ft.load(depth, "d", true, "cpu.a", live)
		"tdc": ft.load(depth, "a", true, "cpu.d", live)
		_:
			ft.put(depth, "cpu.a = (cpu.a >> 8) | (cpu.a << 8)")
			ft.setNz(depth, live, "u8.wrap(cpu.a)", false)

# The flags set and cleared; the widths rep and sep change are the translation's, an 8-bit X
# clearing the index registers' high bytes.
fn flagOperation(mut ft FnText, depth i64, i Instr):
	match i.name:
		"clc", "sec": ft.put(depth, "cpu.c = {i.name == "sec"}")
		"cli", "sei": ft.put(depth, "cpu.irqDisabled = {i.name == "sei"}")
		"cld", "sed": ft.put(depth, "cpu.decimal = {i.name == "sed"}")
		"clv": ft.put(depth, "cpu.v = false")
		"xce": ft.put(depth, "cpu.exchangeCarry()")
		_:
			set = i.name == "sep"
			for (bit, flag) in [
				(0x80, "n"),
				(0x40, "v"),
				(0x08, "decimal"),
				(0x04, "irqDisabled"),
				(0x02, "z"),
				(0x01, "c")
			]:
				if i.value & bit != 0: ft.put(depth, "cpu.{flag} = {set}")
			if set and i.value & 0x10 != 0 and not i.widths.x and not i.widths.e:
				ft.put(depth, "cpu.x &= 0xFF")
				ft.put(depth, "cpu.y &= 0xFF")

# The pushes and the pulls; plp pulls the widths the translation goes on in.
fn stackOperation(mut ft FnText, depth i64, i Instr, live i64):
	m16 = not i.widths.m
	x16 = not i.widths.x
	match i.name:
		"pha": ft.push(depth, readReg("a", m16), m16)
		"phx", "phy": ft.push(depth, readReg(i.name[2..3], x16), x16)
		"phb": ft.push(depth, "cpu.dbr", false)
		"phd": ft.push(depth, "cpu.d", true)
		"phk": ft.push(depth, i.bankByteText(), false)
		"php": ft.push(depth, "cpu.status({i.widths.statusWidths()})", false)
		"pea": ft.push(depth, i.valueAs("u16"), true)
		"pei": ft.push(depth, "cpu.readData16Bank0(cpu.direct({i.valueText()}))", true)
		"per": ft.push(
			depth,
			"u16.wrap({i.targetText()})" if i.symbolic else hex(i.target() & 0xFFFF, 4),
			true
		)
		"pla": ft.load(depth, "a", m16, pull(m16), live)
		"plx", "ply": ft.load(depth, i.name[2..3], x16, pull(x16), live)
		"plb": ft.load(depth, "dbr", true, "cpu.pull8()", live & ~(flagN | flagZ))
		"pld": ft.load(depth, "d", true, "cpu.pull16()", live)
		_: fail("no translation of {i.text()}")
	if i.name == "plb": ft.setNz(depth, live, "cpu.dbr", false)

# the status register's bits of the widths: M and X (B and 1 in emulation mode)
fn statusWidths(w Widths):
	hex((w.widthBits() << 4) & 0x30, 2)

fn push(mut ft FnText, depth i64, value str, wide bool):
	ft.put(depth, "cpu.push{"16" if wide else "8"}({value})")

fn pull(wide bool):
	"cpu.pull{"16" if wide else "8"}()"
