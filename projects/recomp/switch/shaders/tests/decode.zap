# Maxwell words decoded into their fields, each word one deko3d's compiler wrote (the examples'
# shaders) and each field as yuzu's decoder (maxwell.inc, impl/*.cpp) and Ryujinx's InstTable
# place it.

import recomp.switch.shaders

# a word written as the hardware's bits
fn word(w u64) i64:
	i64.wrap(w)

# the instruction at byte address `at`: its operation, form, guard and operands
fn said(t shaders.OpTable, w u64, at i64):
	i = t.decodeAt(word(w), at)
	guard = "" if i.pred == shaders.pt and not i.predNot
		else "@{"!" if i.predNot else ""}P{i.pred} "
	"{guard}{i.op} {i.form} d{i.rd} a{i.ra} {i.b.operand()} {i.c.operand()}"

fn operand(o shaders.Operand):
	match o.kind:
		Reg: "r{o.reg}"
		Cbuf: "c[{o.bank}][0x{o.offset:x}]"
		Imm: "#0x{o.imm:x}"
		None: "-"

test "the ALU's forms: B a register, a constant buffer's word, an immediate; C a register or a constant":
	t = shaders.newTable()
	print(t.said(0x4C68_1008_0007_0002, 0x10))   # FMUL R2, R0, c[0x2][0x0]
	print(t.said(0x49A0_0108_0047_0102, 0x38))   # FFMA R2, R1, c[0x2][0x10], R2
	print(t.said(0x59A0_0380_0057_0507, 0xF0))   # FFMA R7, R5, R5, R7
	print(t.said(0x3858_103F_8007_0200, 0x308))   # FADD R0, R2, 1.0
	print(t.said(0x0103_F800_0007_F003, 0x2F8))   # MOV32I R3, 0x3f800000
	print(t.said(0x3818_0280_0107_0000, 0xD0))   # ISCADD R0, R0, 0x10, 0x5
	prints """
		Fmul Cbuf d2 a0 c[2][0x0] r32
		Ffma Cr d2 a1 c[2][0x10] r2
		Ffma Reg d7 a5 r5 r7
		Fadd Imm d0 a2 #0x3f800 r32
		Mov Imm32 d3 a240 #0x3f800000 r240
		Iscadd Imm d0 a0 #0x10 r5
		"""

test "a float immediate's 19 bits and sign are a float's top 20":
	t = shaders.newTable()
	i = t.decodeAt(word(0x3858_103F_8007_0200), 0x308)
	expect (i.b.imm & 0xF_FFFF) << 12 == 0x3F80_0000

test "the guard predicate, and a branch's target past the next instruction":
	t = shaders.newTable()
	bra = t.decodeAt(word(0xE240_0000_0988_000F), 0x98)
	print(t.said(0xE240_0000_0988_000F, 0x98))
	print("0x{bra.branchTarget():x}")
	# SSY's target falls on a scheduling word: the instruction after it
	ssy = t.decodeAt(word(0xE290_0000_0D00_0000), 0x88)
	print("0x{ssy.branchTarget():x}")
	print(t.said(0xE300_0000_0007_000F, 0x368))
	prints """
		@!P0 Bra None d15 a0 - -
		0x138
		0x168
		Exit None d15 a0 - -
		"""

fn field(w u64, at i64, width i64):
	(word(w) >> at) & ((1 << width) - 1)

test "the fields one operation reads from the word":
	t = shaders.newTable()
	ald u64 = 0xEFD8_FF80_0807_FF00   # ALD R0, a[0x80] (2 words: generic 0's x and y)
	ipa u64 = 0xE003_FF87_CFF7_FF00   # IPA.PASS R0, a[0x7c] (position w)
	ldc u64 = 0xEF94_0010_0307_0700   # LDC R0, c[0x1][R7+0x30]
	fsetp u64 = 0x4BBD_8388_0037_FF07   # FSETP.NEU P0, PT, RZ, c[0x2][0xc], PT
	tlds u64 = 0xDA50_1A40_2077_0600   # TLDS.LZ R0, R2, R6, R7, 0x1a4, 2D, RGBA
	s2r u64 = 0xF0C8_0000_0257_0000   # S2R R0, SR_CTAID.X
	mufu u64 = 0x5080_0000_0047_0000   # MUFU.RCP R0, R0
	fields = [
		field(ald, 20, 10),
		field(ald, 47, 2),
		field(ipa, 30, 8),
		field(ipa, 54, 2),
		field(ldc, 36, 5),
		field(ldc, 20, 16), field(ldc, 48, 3), field(fsetp, 48, 4), field(fsetp, 3, 3),
		field(fsetp, 0, 3), field(tlds, 36, 13), field(tlds, 53, 4), field(tlds, 50, 3),
		field(tlds, 28, 8), field(s2r, 20, 8), field(mufu, 20, 4)
	]
	print(fields.map("{it}").join(" "))
	print([ald, ipa, ldc, fsetp, tlds, s2r, mufu].map("{t.decodeAt(word(it), 8).op}").join(" "))
	prints """
		128 1 31 0 1 48 4 13 0 7 420 2 4 2 37 4
		Ald Ipa Ldc Fsetp Tlds S2r Mufu
		"""

test "the most specific pattern wins, and a word no pattern takes is unknown":
	t = shaders.newTable()
	# 1110 1110 1111: ATOM (cas) over ATOMS (cas)'s 1110 1110
	print(t.decodeAt(word(0xEEF0_0000_0000_0000), 8).op)
	print(t.decodeAt(word(0xEE00_0000_0000_0000), 8).op)
	print(t.decodeAt(0, 8).op)
	prints """
		AtomCas
		AtomsCas
		Unknown
		"""

test "an instruction's address counts the scheduling word of each group of three":
	print((0..6).map("0x{shaders.addressOf(it):x}").join(" "))
	print((0..6).map("{shaders.indexOf(shaders.addressOf(it))}").join(" "))
	prints """
		0x8 0x10 0x18 0x28 0x30 0x38
		0 1 2 3 4 5
		"""
