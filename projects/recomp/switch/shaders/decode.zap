# A Maxwell instruction decoded into the fields every encoding shares (yuzu's impl.cpp, Ryujinx's
# InstDecoders): the guard predicate (bits 16-19, 7 the always-true PT, bit 19 its negation), the
# destination (bits 0-7), operand A (8-15), operand B as its form gives it and operand C (a
# register at 39-46, or B's constant in the Rc form). Register 255 is RZ: zero read, a write
# dropped. What one operation alone reads (its modifiers) the translation takes from the word.

import recomp.switch.arm64

pub rz = 255
pub pt = 7

pub type Kind:
	None
	Reg
	Cbuf
	Imm

# A source: a register, a constant buffer's word (bank, byte offset) or an immediate.
pub type Operand:
	kind Kind = .None
	reg i64 = 0
	bank i64 = 0
	offset i64 = 0
	imm i64 = 0

pub type Instr:
	op Op = .Unknown
	form Form = .None
	word i64 = 0
	at i64 = 0   # its byte address in the code, scheduling words counted
	pred i64 = pt
	predNot bool = false
	rd i64 = rz
	ra i64 = rz
	b Operand = Operand()
	c Operand = Operand()

fn regAt(w i64, at i64):
	Operand(kind = .Reg, reg = arm64.bits(w, at, 8))

# c[bank][offset]: the word at bits 20-33, the bank at 34-38
pub fn cbufOf(w i64) Operand:
	Operand(kind = .Cbuf, bank = arm64.bits(w, 34, 5), offset = arm64.bits(w, 20, 14) * 4)

# the 20-bit immediate: 19 bits at 20 and its sign at 56, as an integer (a float's top 20 bits
# for a float operation: emit.zap)
fn imm20(w i64):
	v = arm64.bits(w, 20, 19)
	Operand(kind = .Imm, imm = v - (1 << 19) if arm64.hasBit(w, 56) else v)

fn imm32(w i64):
	Operand(kind = .Imm, imm = arm64.bits(w, 20, 32))

# the byte address of the instruction `index` of a program's instructions (3 a group of 32 bytes)
pub fn addressOf(index i64) i64:
	index / 3 * 32 + (index % 3 + 1) * 8

pub fn indexOf(address i64) i64:
	address / 32 * 3 + (address % 32) / 8 - 1

# The instruction w at byte address `at`.
pub fn decodeAt(t OpTable, w i64, at i64) Instr:
	e = t.encodingOf(w)
	base = Instr(
		op = e.op,
		form = e.form,
		word = w,
		at,
		pred = arm64.bits(w, 16, 3),
		predNot = arm64.hasBit(w, 19),
		rd = arm64.bits(w, 0, 8),
		ra = arm64.bits(w, 8, 8)
	)
	match e.form:
		Reg: Instr(..base, b = regAt(w, 20), c = regAt(w, 39))
		Cbuf: Instr(..base, b = cbufOf(w), c = regAt(w, 39))
		Imm: Instr(..base, b = imm20(w), c = regAt(w, 39))
		Imm32: Instr(..base, b = imm32(w), c = regAt(w, 39))
		Rc: Instr(..base, b = regAt(w, 39), c = cbufOf(w))
		Cr: Instr(..base, b = cbufOf(w), c = regAt(w, 39))
		_: base

# A program's instructions decoded.
pub fn decodeProgram(t OpTable, words i64[]) Instr[]:
	out = []
	for i, w in words:
		out.push(t.decodeAt(w, addressOf(i)))
	out

# the target of the relative branch w at `at` (BRA, SSY, PBK, CAL, PCNT): 24 signed bits at 20
# past the next instruction, a scheduling word's address meaning the instruction after it
pub fn relativeTarget(w i64, at i64) i64:
	target = at + 8 + arm64.signedBits(w, 20, 24)
	target + 8 if target % 32 == 0 else target

pub fn branchTarget(i Instr) i64:
	relativeTarget(i.word, i.at)
