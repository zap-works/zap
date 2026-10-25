# An instruction as the table reads it, with the address it sits at (bank << 16 | pc). Its text is
# the canonical assembly (`text()`), which `assemble` reads back: lowercase mnemonics, `$` and
# uppercase hex as wide as the operand's bytes (`lda #$0001`, `sta $7E0010,x`, `bne $80A8F2`).

pub type Instr:
	at i64
	opcode i64
	name str
	mode str
	value i64   # the operand's bytes, little-endian
	size i64
	widths Widths   # those it was read in
	symbolic bool = false   # any opcode's instruction, its address and operand the interpreter's (interpret.zap)

	pub fn bank() i64:
		at >> 16

	# the address after it: the program counter wraps within its bank
	pub fn next() i64:
		(at & 0xFF_0000) | ((at + size) & 0xFFFF)

	# a branch's target, in its bank
	pub fn target() i64:
		offset = signed(value, 8 * (size - 1))
		(at & 0xFF_0000) | ((at + size + offset) & 0xFFFF)

	# the operand as the mode writes it
	pub fn operandText() str:
		match mode:
			"": ""
			"A": "a"
			"r", "rl": "${self.target():06X}"
			"b,b": "${value >> 8:02X},${value & 0xFF:02X}"
			_:
				if isImmediate(mode): return "#${hexBytes(value, size - 1)}"
				k = placeholderIndex(mode) ?? fail("no operand in mode {mode}")
				"{mode[..k]}${hexBytes(value, size - 1)}{mode[k + 1..]}"

	# the canonical assembly of the instruction
	pub fn text() str:
		operand = self.operandText()
		name.copy() if operand.isEmpty else "{name} {operand}"

	# the instruction's bytes
	pub fn bytes() u8[]:
		out u8[] = [u8(opcode)]
		for k in 1..size:
			out.push(u8.wrap(value >> (8 * (k - 1))))
		out

# the value sign-extended from its width
pub fn signed(v i64, bits i64) i64:
	shift = 64 - bits
	(v << shift) >> shift

# v in hex with two digits a byte
pub fn hexBytes(v i64, bytes i64) str:
	match bytes:
		1: "{v:02X}"
		2: "{v:04X}"
		_: "{v:06X}"

# where the letter of the operand's bytes sits in a mode
pub fn placeholderIndex(mode str) i64?:
	for k, c in mode.bytes():
		if c == 'd' or c == 'w' or c == 'l': return k
	none

# The texts the translation writes for the instruction's address, the address after it, its
# bank and its operand: literals, or for the interpreter's instructions (symbolic) the variables
# `at`, `nextAt` and `operand` (u32) its functions have.
pub fn atText(i Instr) str:
	"at" if i.symbolic else hex(i.at, 6)

pub fn nextText(i Instr) str:
	"nextAt" if i.symbolic else hex(i.next(), 6)

# the program bank as a byte (phk, a long call's push)
pub fn bankByteText(i Instr) str:
	"u8.wrap(at >> 16)" if i.symbolic else hex(i.bank(), 2)

# the operand as an address part (u32)
pub fn valueText(i Instr) str:
	"operand" if i.symbolic else hex(i.value, 2 * (i.size - 1))

# the operand as a value of `type` (u8 or u16)
pub fn valueAs(i Instr, typeName str) str:
	"{typeName}.wrap(operand)" if i.symbolic else hex(i.value, 2 * (i.size - 1))

# a branch's target, in its bank
pub fn targetText(i Instr) str:
	"cpu.branchTarget(at, operand, {i.size})" if i.symbolic else hex(i.target(), 6)

# a block move's source bank (the operand's high byte) or destination bank, as a byte
pub fn blockBank(i Instr, source bool) str:
	if i.symbolic: return "u8.wrap(operand >> 8)" if source else "u8.wrap(operand)"
	hex(i.value >> 8 if source else i.value & 0xFF, 2)
