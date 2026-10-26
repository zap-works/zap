# Each instruction of the common form as Zap statements over the cpu module's registers, the
# function's flags (nf, zf, cf, vf) and gba's memory. A jump ends the statements as the
# function's shape says (`FnText.jump`).

import arm

# the text of one function as it is written
pub type FnText:
	lines str[]
	temps i64   # the temporaries named so far
	dispatched bool   # a loop over a match of its labels, else straight statements
	thumb bool
	usesEntry bool
	flagsRead i64
	flagsWritten i64

	fn put(depth i64, line str):
		lines.push("{"\t".repeat(depth)}{line}")

	fn temp(prefix str):
		temps += 1
		"{prefix}{temps}"

	fn setFlag(depth i64, flag i64, value str):
		flagsWritten |= flag
		self.put(depth, "{flagName(flag)} = {value}")

	fn readFlag(flag i64):
		flagsRead |= flag
		flagName(flag)

	pub mut fn condText(cond i64) str:
		match cond:
			0: self.readFlag(flagZ)
			1: "not {self.readFlag(flagZ)}"
			2: self.readFlag(flagC)
			3: "not {self.readFlag(flagC)}"
			4: self.readFlag(flagN)
			5: "not {self.readFlag(flagN)}"
			6: self.readFlag(flagV)
			7: "not {self.readFlag(flagV)}"
			8: "{self.readFlag(flagC)} and not {self.readFlag(flagZ)}"
			9: "not {self.readFlag(flagC)} or {self.readFlag(flagZ)}"
			10: "{self.readFlag(flagN)} == {self.readFlag(flagV)}"
			11: "{self.readFlag(flagN)} != {self.readFlag(flagV)}"
			12: "not {self.readFlag(flagZ)} and {self.readFlag(flagN)} == {self.readFlag(flagV)}"
			_: "{self.readFlag(flagZ)} or {self.readFlag(flagN)} != {self.readFlag(flagV)}"

	# the value of a second operand
	mut fn operandValue(i arm.Instr, b arm.Operand, left bool = false):
		match b:
			Imm(v, _): "u32({hex(v)})" if left else hex(v)
			Reg(m, shift, amount):
				r = i.reg(m)
				match shift:
					0: r if amount == 0 else "({r} << {amount})"
					1: "u32(0)" if amount == 32 else "({r} >> {amount})"
					2: "u32(i32({r}) >> {amount.min(31)})"
					3: "{r}.rotateRight({amount})"
					_: "(({r} >> 1) | (0x8000_0000 if {self.readFlag(flagC)} else 0))"
			RegShift(m, shift, s):
				value = "i32({i.reg(m)})" if shift == 2 else i.reg(m)
				"cpu.{shiftCalls[shift]}({value}, {i.reg(s)} & 0xFF)"

	# the carry out of a second operand that has one (shifterCarries)
	mut fn operandCarry(i arm.Instr, b arm.Operand):
		match b:
			Imm(v, _): "true" if v >> 31 == 1 else "false"
			Reg(m, shift, amount):
				r = i.reg(m)
				match shift:
					0: "({r} >> {32 - amount}) & 1 == 1"
					1, 2: "{r} >> 31 == 1" if amount == 32 else "({r} >> {amount - 1}) & 1 == 1"
					3: "({r} >> {amount - 1}) & 1 == 1"
					_: "{r} & 1 == 1"
			RegShift(m, shift, s):
				"cpu.{carryCalls[shift]}({i.reg(m)}, {i.reg(s)} & 0xFF, {self.readFlag(flagC)})"

	# A data processing instruction: the result into a temporary when flags read it, the flags from
	# the operands and the result, then the destination.
	pub mut fn alu(depth i64, i arm.Instr, live i64):
		kind, sets, d, n, b = match i.op:
			Alu(kind, sets, d, n, b): (kind, sets, d, n, b)
			_: fail("no alu")
		need = live if sets else 0
		writes = kind < arm.aluTst or kind > arm.aluCmn
		if not writes and need == 0: return
		bv = self.operandValue(i, b, left = kind in [3, 7, 13, 15])
		arithmetic = isArithmetic(kind)
		if (need & (flagC | flagV) != 0 and arithmetic or "cpu.shift" in bv) and not isPlain(bv):
			named = self.temp("b")
			self.put(depth, "{named} = {bv}")
			bv = named
		nv = i.reg(n)
		carry = "cpu.bit({self.readFlag(flagC)})" if readsCarry(kind) else ""
		result = match kind:
			0, 8: "{nv} & {bv}"
			1, 9: "{nv} ^ {bv}"
			2, 10: "{nv} - {bv}"
			3: "{bv} - {nv}"
			4, 11: "{nv} + {bv}"
			5: "{nv} + {bv} + {carry}"
			6: "{nv} - {bv} - 1 + {carry}"
			7: "{bv} - {nv} - 1 + {carry}"
			12: "{nv} | {bv}"
			13: bv.copy()
			14: "{nv} & ~{bv}"
			_: "~{bv}"
		if need == 0:
			self.writeReg(depth, i, d, result)
			return
		if not writes and need & (flagN | flagZ) == 0 and not arithmetic:
			if b.shifterCarries(): self.setFlag(depth, flagC, self.operandCarry(i, b))
			return
		if not writes and need & (flagN | flagZ | flagV) == 0 and kind != 4 and kind != 11:
			self.arithmeticFlags(depth, kind, nv, bv, carry, "", need)   # a compare's carry alone
			return
		t = self.temp("t")
		self.put(depth, "{t} = {result}")
		if need & flagN != 0: self.setFlag(depth, flagN, "{t} >> 31 == 1")
		if need & flagZ != 0: self.setFlag(depth, flagZ, "{t} == 0")
		if arithmetic:
			self.arithmeticFlags(depth, kind, nv, bv, carry, t, need)
		elif need & flagC != 0 and b.shifterCarries():
			self.setFlag(depth, flagC, self.operandCarry(i, b))
		if writes: self.writeReg(depth, i, d, t)

	# C and V of an addition or a subtraction (the reversed ones with their operands turned)
	mut fn arithmeticFlags(depth i64,
		kind i64,
		nv str,
		bv str,
		carry str,
		t str,
		need i64
	):
		reversed = kind == 3 or kind == 7
		x = bv if reversed else nv
		y = nv if reversed else bv
		adds = kind in [4, 5, arm.aluCmn]
		if need & flagC != 0:
			c = match kind:
				4, 11: "{t} < {x}"
				5: "u64({x}) + u64({y}) + u64({carry}) > 0xFFFF_FFFF"
				2, 3, 10: "true" if isZero(y) else "{x} >= {y}"
				_: "u64({x}) + u64({carry}) >= u64({y}) + 1"
			self.setFlag(depth, flagC, c)
		if need & flagV != 0:
			v = "(~({x} ^ {y}) & ({x} ^ {t})) >> 31 == 1" if adds
				else "(({x} ^ {y}) & ({x} ^ {t})) >> 31 == 1"
			self.setFlag(depth, flagV, v)

	# a register written; the program counter written is a jump
	fn writeReg(depth i64, i arm.Instr, d i64, value str):
		if d != arm.pc:
			self.put(depth, "{regTarget(d)} = {value}")
			return
		self.jump(depth, "({value}) | 1" if i.thumb else "({value}) & ~u32(1)")

	# A jump to a computed key (the address, bit 0 the state): the dispatcher takes it, a return
	# when it is where the function returns, a call of another function else.
	pub mut fn jump(depth i64, key str):
		usesEntry = true
		if dispatched:
			# a return first: where the function returns may also be one of its labels (a call of it
			# from its own code)
			self.put(depth, "pc = {key}")
			self.put(depth, "if pc | 1 == entry | 1: return")
			self.put(depth, "continue")
			return
		t = self.temp("j")
		self.put(depth, "{t} u32 = {key}")
		self.put(depth, "if {t} | 1 != entry | 1: cpu.far({t}, entry)")
		self.put(depth, "return")

	mut fn mulOf(depth i64, i arm.Instr, live i64):
		match i.op:
			Mul(sets, d, m, s, acc):
				product = "{i.reg(m)} * {i.reg(s)}"
				value = product if acc < 0 else "{product} + {i.reg(acc)}"
				need = live & (flagN | flagZ) if sets else 0
				if need == 0:
					self.writeReg(depth, i, d, value)
					return
				t = self.temp("t")
				self.put(depth, "{t} = {value}")
				if need & flagN != 0: self.setFlag(depth, flagN, "{t} >> 31 == 1")
				if need & flagZ != 0: self.setFlag(depth, flagZ, "{t} == 0")
				self.writeReg(depth, i, d, t)
			MulLong(signed, adds, sets, lo, hi, m, s):
				t = self.temp("p")
				product = "u64(i64(i32({i.reg(m)})) * i64(i32({i.reg(s)})))" if signed
					else "u64({i.reg(m)}) * u64({i.reg(s)})"
				self.put(
					depth,
					"{t} = {product} + ((u64({i.reg(hi)}) << 32) | {i.reg(lo)})" if adds
					else "{t} = {product}"
				)
				need = live & (flagN | flagZ) if sets else 0
				if need & flagN != 0: self.setFlag(depth, flagN, "{t} >> 63 == 1")
				if need & flagZ != 0: self.setFlag(depth, flagZ, "{t} == 0")
				self.put(depth, "{regTarget(lo)} = u32.wrap({t})")
				self.put(depth, "{regTarget(hi)} = u32({t} >> 32)")
			_: fail("no multiply")

fn hex(v i64):
	"0x{v:08X}"

# the register's value as instruction i reads it: the program counter is a constant
fn reg(i arm.Instr, r i64):
	if r == arm.pc: return "u32({hex(i.pcValue())})"
	"cpu.r{r}"

fn isZero(text str):
	text == "0x00000000"

fn regTarget(r i64):
	"cpu.r{r}"

flagNames = ["vf", "cf", "zf", "nf"]

fn flagName(flag i64):
	flagNames[flag.trailingZeros()].copy()

shiftCalls = ["shiftLeft", "shiftRight", "shiftArithmetic", "rotate"]
carryCalls = ["carriesLeft", "carriesRight", "carriesArithmetic", "carriesRotate"]

fn isPlain(text str):
	not (" " in text) and not ("(" in text)
