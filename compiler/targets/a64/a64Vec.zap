# The intermediate form's vectors on AArch64: an irVec vreg the allocator gives register r lives
# in two NEON registers, its low 16 bytes in vr and its high ones in a64VecHighRegs[r] (a 16-byte
# vector in the first alone, its upper half zero); one it gives none
# lives in its 32-byte frame slot. An operation works on 16 bytes at a time, q0..q2 its scratch.
# irVecOp names the AVX instruction x64 runs (irVecCode); a64VecOps gives the NEON one that does
# the same lane by lane. The forms beyond the table (a fused multiply-add, a blend, a shuffle, a
# comparison with a predicate, a horizontal add, a square root, a conversion, a permute across
# the halves) are a64EmitVecForm's.

# the register of the high 16 bytes of each register a vector of 32 bytes may take (irArmPools: none
# of them a float's in a function with such a vector, all of them lost by calls: a vector never
# lives across one), -1 for the others
a64VecHighRegs = [
	-1, -1, -1, -1, -1, -1, -1, -1, 26, 27, 28, 29, 30, 31, 3, 4,
	22, 23, 24, 25, 5, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
]

# the function's 16-byte vectors (irNarrowVectors), set by a64EmitWhole
mut a64Narrows bool[] = []

# AVX's map, prefix and opcode, and the NEON instruction of 16 bytes with the same lanes
a64VecOps = [
	[1, 1, 0xDB, 0x4E20_1C00],   # pand: and
	[1, 1, 0xEB, 0x4EA0_1C00],   # por: orr
	[1, 1, 0xEF, 0x6E20_1C00],   # pxor: eor
	[1, 1, 0x57, 0x6E20_1C00],   # xorpd: eor
	[1, 1, 0xFC, 0x4E20_8400],   # paddb: add .16b
	[1, 1, 0xF8, 0x6E20_8400],   # psubb: sub .16b
	[1, 1, 0xDA, 0x6E20_6C00],   # pminub: umin .16b
	[1, 1, 0xDE, 0x6E20_6400],   # pmaxub: umax .16b
	[1, 1, 0x74, 0x6E20_8C00],   # pcmpeqb: cmeq .16b
	[1, 1, 0x64, 0x4E20_3400],   # pcmpgtb: cmgt .16b
	[1, 1, 0xFE, 0x4EA0_8400],   # paddd: add .4s
	[1, 1, 0xFA, 0x6EA0_8400],   # psubd: sub .4s
	[1, 1, 0x76, 0x6EA0_8C00],   # pcmpeqd: cmeq .4s
	[1, 1, 0x66, 0x4EA0_3400],   # pcmpgtd: cmgt .4s
	[2, 1, 0x40, 0x4EA0_9C00],   # pmulld: mul .4s
	[2, 1, 0x39, 0x4EA0_6C00],   # pminsd: smin .4s
	[2, 1, 0x3D, 0x4EA0_6400],   # pmaxsd: smax .4s
	[1, 1, 0xD4, 0x4EE0_8400],   # paddq: add .2d
	[1, 1, 0xFB, 0x6EE0_8400],   # psubq: sub .2d
	[2, 1, 0x29, 0x6EE0_8C00],   # pcmpeqq: cmeq .2d
	[2, 1, 0x37, 0x4EE0_3400],   # pcmpgtq: cmgt .2d
	[1, 1, 0x58, 0x4E60_D400],   # addpd: fadd .2d
	[1, 1, 0x5C, 0x4EE0_D400],   # subpd: fsub .2d
	[1, 1, 0x59, 0x6E60_DC00],   # mulpd: fmul .2d
	[1, 1, 0x5E, 0x6E60_FC00],   # divpd: fdiv .2d
	[1, 1, 0x5D, 0x4EE0_F400],   # minpd: fmin .2d
	[1, 1, 0x5F, 0x4E60_F400],   # maxpd: fmax .2d
	[1, 0, 0x58, 0x4E20_D400],   # addps: fadd .4s
	[1, 0, 0x5C, 0x4EA0_D400],   # subps: fsub .4s
	[1, 0, 0x59, 0x6E20_DC00],   # mulps: fmul .4s
	[1, 0, 0x5E, 0x6E20_FC00],   # divps: fdiv .4s
	[1, 0, 0x5D, 0x4EA0_F400],   # minps: fmin .4s
	[1, 0, 0x5F, 0x4E20_F400]]   # maxps: fmax .4s

fn a64LoadQ(mut a Asm, q i64, base i64, off i64):
	a.a64Access(0x3DC0_0000, 16, q, base, off, accessFloat)

fn a64StoreQ(mut a Asm, q i64, base i64, off i64):
	a.a64Access(0x3D80_0000, 16, q, base, off, accessFloat)

# mov vd.16b, vn.16b
fn a64VecMov(mut a Asm, d i64, n i64):
	if d != n:
		a.a64(0x4EA0_1C00 | n << 16 | n << 5 | d)   # orr vd, vn, vn

# the register holding half h of vector vreg v, -1 when it lives in its slot (or is the zero
# constant)
fn a64VecReg(em IrEmit, v i64, h i64):
	if em.rs.spilled[v] or em.rs.reg[v] < 0: return -1
	em.rs.reg[v] if h == 0 else a64VecHighRegs[em.rs.reg[v]]

# whether v's upper half is no register's: a 16-byte vector in a register, its upper half zero
fn a64VecLowOnly(em IrEmit, v i64):
	a64Narrows[v] and em.a64VecReg(v, 0) >= 0

# the register holding half h of v: its own, or q loaded with it (zeros for the constant and a
# 16-byte vector's upper half)
fn a64VecIn(mut g Gen, em IrEmit, v i64, h i64, q i64):
	if em.rs.isConst[v] or h == 1 and em.a64VecLowOnly(v):
		g.a.a64(0x6F00_E400 | q)   # movi q, 0
		return q
	r = em.a64VecReg(v, h)
	if r >= 0: return r
	g.a.a64LoadQ(q, a64Fp, em.slots[v] + 16 * h)
	q

# the register whose lane 0 holds v's: a float's d register, or a vector's low half
fn a64LowLaneIn(mut g Gen, em IrEmit, v i64, q i64) i64:
	if em.f.classes[v] == irFloat: return g.a64FloatIn(em, v, q)
	g.a64VecIn(em, v, 0, q)

# half h of v copied into q
fn a64VecInto(mut g Gen, em IrEmit, v i64, h i64, q i64):
	g.a.a64VecMov(q, g.a64VecIn(em, v, h, q))

# the register an operation computes half h of v into: its own, or q0 when v lives in its slot
fn a64VecOut(em IrEmit, v i64, h i64):
	r = em.a64VecReg(v, h)
	r if r >= 0 else 0

# half h of v, computed into q, put where v lives
fn a64VecDone(mut g Gen, em IrEmit, v i64, h i64, q i64):
	if h == 1 and em.a64VecLowOnly(v): return
	r = em.a64VecReg(v, h)
	if r < 0:
		g.a.a64StoreQ(q, a64Fp, em.slots[v] + 16 * h)
	else:
		g.a.a64VecMov(r, q)

# half h of v zeroed
fn a64VecZero(mut g Gen, em IrEmit, v i64, h i64):
	if h == 1 and em.a64VecLowOnly(v): return
	q = em.a64VecOut(v, h)
	g.a.a64(0x6F00_E400 | q)   # movi q, 0
	g.a64VecDone(em, v, h, q)

# integer register r = the size-byte lane of v at byte at, zero- or sign-extended (umov, smov)
fn a64VecLane(mut g Gen, em IrEmit, v i64, at i64, size i64, uns bool, r i64):
	if em.rs.isConst[v]:
		g.a.a64MovImm(r, 0)
		return
	if em.a64VecReg(v, 0) < 0:
		g.a.a64Load(r, a64Fp, em.slots[v] + at, size, uns)
		return
	q = g.a64VecIn(em, v, at / 16, 0)
	k = at % 16 / size
	word = 0x4E08_3C00 | k << 20 if size == 8
		else (0x0E04_3C00 if uns else 0x4E04_2C00) | k << 19 if size == 4
		else (0x0E02_3C00 if uns else 0x4E02_2C00) | k << 18 if size == 2
		else (0x0E01_3C00 if uns else 0x4E01_2C00) | k << 17
	g.a.a64(word | q << 5 | r)

# the vector instructions: an irVecOp, a splat, a mask, a lane, a copy, a load or a store
fn a64EmitVec(mut g Gen, em IrEmit, inst IrInst):
	op = inst.op
	if op == irVecOp:
		g.a64EmitVecOp(em, inst)
	elif op == irVecSplat:
		g.a64EmitVecSplat(em, inst)
	elif op == irVecMask:
		g.a64EmitVecMask(em, inst)
	elif op == irVecLaneOf:
		r = em.a64IntOut(inst.dst)
		g.a64VecLane(em, inst.a, inst.imm * inst.size, inst.size, inst.uns, r)
		g.a64IntDone(em, inst.dst, r)
	elif op == irConst or op == irCopy:
		if op == irConst and em.rs.isConst[inst.dst]: return
		for h in 0..2:
			if op == irConst:
				g.a64VecZero(em, inst.dst, h)
			elif h == 0 or not em.a64VecLowOnly(inst.dst):
				q = em.a64VecOut(inst.dst, h)
				g.a64VecDone(em, inst.dst, h, g.a64VecIn(em, inst.a, h, q))
	elif op == irLoad or op == irStore:
		load = op == irLoad
		at = g.a64Address(em, inst, 0)
		base = at.base
		off = at.off
		for h in 0..inst.size / 16:
			if load:
				q = em.a64VecOut(inst.dst, h)
				g.a.a64LoadQ(q, base, off + 16 * h)
				g.a64VecDone(em, inst.dst, h, q)
			else:
				g.a.a64StoreQ(g.a64VecIn(em, inst.c, h, 0), base, off + 16 * h)
		if load and inst.size == 16:
			g.a64VecZero(em, inst.dst, 1)   # (the upper half zero, as VEX's)
	else:
		g.a64Refuse(inst)

# dst = a op b lane by lane, a half at a time (a 128-bit instruction's upper half zero)
fn a64EmitVecOp(mut g Gen, em IrEmit, inst IrInst):
	code = inst.imm
	map = code & 3
	pp = (code >> 2) & 3
	opcode = (code >> 8) & 255
	if g.a64EmitVecForm(em, inst): return
	row = a64VecOps.find(it[0] == map and it[1] == pp and it[2] == opcode) ?? []
	if row.isEmpty or inst.cond != 0 or inst.b < 0:
		g.a64Refuse(inst)
		return
	neon = row[3]
	halves = 2 if (code >> 5) & 1 == 1 else 1
	for h in 0..2:
		if h < halves:
			a = g.a64VecIn(em, inst.a, h, 0)
			b = g.a64VecIn(em, inst.b, h, 1)
			q = em.a64VecOut(inst.dst, h)
			g.a.a64Op3(neon, q, a, b)
			g.a64VecDone(em, inst.dst, h, q)
		else:
			g.a64VecZero(em, inst.dst, h)

# dst = the scalar a in every lane of both halves (imm the lane's kind)
fn a64EmitVecSplat(mut g Gen, em IrEmit, inst IrInst):
	k = inst.imm
	q = em.a64VecOut(inst.dst, 0)
	if k == irLaneF64 or k == irLaneF32:
		x = g.a64FloatIn(em, inst.a, 1)
		if k == irLaneF32:
			g.a.a64Op2(a64FcvtDS, 1, x)
		g.a.a64Op2(0x4E08_0400 if k == irLaneF64 else 0x4E04_0400, q, 1 if k == irLaneF32 else x)   # dup .2d / .4s
	else:
		imm5 = 1 if k == irLaneU8 else 4 if k == irLaneI32 else 8
		g.a.a64Op2(0x4E00_0C00 | imm5 << 16, q, g.a64IntIn(em, inst.a, a64T0))   # dup from a register
	for h in 0..2:
		g.a64VecDone(em, inst.dst, h, q)

# dst = the top bit of each byte of a's size bytes, a bit each (imm 2; vpmovmskb); of each 4-byte
# or 8-byte lane (imm 0, 1: movmskps, movmskpd) its sign, lane by lane; cond 1 or 2, a nibble mask
# of 16 compared bytes (a64Masks.zap): four bits a byte, or the nibble's lowest alone
fn a64EmitVecMask(mut g Gen, em IrEmit, inst IrInst):
	r = em.a64IntOut(inst.dst)
	if inst.cond != 0:
		g.a.a64(0x0F0C_8400 | g.a64VecIn(em, inst.a, 0, 0) << 5)   # shrn v0.8b, a.8h, 4
		g.a.a64Op2(a64FmovXD, r, 0)
		if inst.cond == 2:
			g.a.a64LogicalImm(a64And, r, r, 0x1111_1111_1111_1111, true)
		g.a64IntDone(em, inst.dst, r)
		return
	if inst.imm != 2 or em.rs.isConst[inst.a]:
		lane = 4 if inst.imm == 0 else 8 if inst.imm == 1 else 1
		g.a.a64MovImm(7, 0)
		for k in 0..(0 if em.rs.isConst[inst.a] else inst.size / lane):
			g.a64VecLane(em, inst.a, lane * k, lane, true, 6)
			g.a.a64ShiftImm(1, 6, 6, 8 * lane - 1, true)   # its sign bit alone
			g.a.a64(a64Orr | 6 << 16 | k << 10 | 7 << 5 | 7)   # orr x7, x7, x6, lsl k
		g.a.a64Mov(r, 7)
		g.a64IntDone(em, inst.dst, r)
		return
	# each byte's top bit weighed by its place in its eight (1, 2, 4..128: 0x8040_2010_0804_0201),
	# the eight weights added
	g.a.a64AdrData(a64T0, g.floatConst(-9_205_322_385_119_247_871))
	g.a.a64LoadF(1, a64T0, 0, 8)
	if inst.size == 8:
		g.a.a64(0x2F09_0400 | g.a64VecIn(em, inst.a, 0, 0) << 5)   # ushr v0.8b, a.8b, 7
		g.a.a64(0x0E21_9C00)   # mul v0.8b, v0.8b, v1.8b
		g.a.a64(0x0E31_B800)   # addv b0, v0.8b
		g.a.a64Op2(a64FmovWS, r, 0)
		g.a64IntDone(em, inst.dst, r)
		return
	g.a.a64(0x4E08_0421)   # dup v1.2d, v1.d[0]
	halves = inst.size / 16
	for h in 0..halves:
		q = 2 * h   # the low half's in v0, the high's in v2
		g.a.a64(0x4E20_A800 | g.a64VecIn(em, inst.a, h, q) << 5 | q)   # cmlt q.16b, a.16b, 0: a byte's top bit as its whole byte
		g.a.a64(0x4E21_1C00 | q << 5 | q)   # and q.16b, q.16b, v1.16b
	# lanes added in pairs, the halves' side by side first, so the 16 or 32 end as two or four bytes
	g.a.a64(0x4E20_BC00 | (2 if halves == 2 else 0) << 16)   # addp v0.16b, v0.16b, v0 or v2
	loop 2:
		g.a.a64(0x4E20_BC00)   # addp v0.16b, v0.16b, v0.16b
	g.a.a64Op2(0x0E04_3C00 if halves == 2 else 0x0E02_3C00, r, 0)   # umov r, v0.s[0] or v0.h[0]
	g.a64IntDone(em, inst.dst, r)

# the NEON of the AVX forms the table has not: true when inst was one of them
# long: a dispatch of one arm per AVX instruction
fn a64EmitVecForm(mut g Gen, em IrEmit, inst IrInst):
	code = inst.imm
	key = code & 3, (code >> 2) & 3, (code >> 8) & 255
	imm8 = (code >> 16) - 1
	f64 = (code >> 2) & 3 == 1
	w = (code >> 4) & 1 == 1
	if key == (2, 1, 0xB9) and em.f.classes[inst.dst] == irFloat:
		# vfmadd231sd: dst = a * b + c rounded once (fmadd d, a, b, c)
		x = em.a64FloatOut(inst.dst)
		a = g.a64FloatIn(em, inst.a, 0)
		b = g.a64FloatIn(em, inst.b, 1)
		c = g.a64FloatIn(em, inst.c, 2)
		g.a.a64(0x1F40_0000 | b << 16 | c << 10 | a << 5 | x)
		g.a64FloatDone(em, inst.dst, x)
	elif em.f.classes[inst.dst] == irFloat and (key == (3, 1, 0x05) or key == (1, 1, 0x28)):
		# vpermilpd x, v, 1 (lane 1 of a, as a scalar: dup d, v.d[1]) or vmovapd x, v (lane 0)
		x = em.a64FloatOut(inst.dst)
		a = g.a64VecIn(em, inst.a, 0, 0)
		if key[2] == 0x05:
			g.a.a64Op2(0x5E18_0400, x, a)
		else:
			g.a.a64Op2(a64Fmov, x, a)
		g.a64FloatDone(em, inst.dst, x)
	elif key == (1, 1, 0x14) or key == (1, 3, 0x12):
		# vunpcklpd [a0, b0] (zip1 .2d) or vmovddup [a0, a0] (dup .2d), of scalars or vectors' lane 0
		q = em.a64VecOut(inst.dst, 0)
		a = g.a64LowLaneIn(em, inst.a, 0)
		if key[2] == 0x14:
			g.a.a64Op3(0x4EC0_3800, q, a, g.a64LowLaneIn(em, inst.b, 1))
		else:
			g.a.a64Op2(0x4E08_0400, q, a)
		g.a64VecDone(em, inst.dst, 0, q)
		g.a64VecZero(em, inst.dst, 1)
	elif inst.cond == 1 and key[0] == 2 and key[2] in [0xB8, 0xBA, 0xBC]:
		g.a64EmitVecFused(em, inst, key[2], w)
	elif key == (1, 1, 0x7C):
		# vhaddpd: each half's [a0 + a1, b0 + b1] (faddp .2d)
		g.a64VecHalves(em, inst, [inst.a, inst.b], [0x6E60_D400 | 1 << 16], 0)
	elif key == (2, 1, 0x00):
		# vpshufb: each half's bytes of a by b's indices, 0 where an index has its top bit (tbl,
		# an index's bits 4..6 dropped first: movi, and, tbl)
		g.a64VecPerHalf(em, inst, 0)
	elif key[0] == 1 and key[2] == 0xC2 and imm8 >= 0 and imm8 <= 2:
		# vcmppd / vcmpps by predicate: eq (fcmeq), lt (fcmgt of the pair swapped), le (fcmge so)
		neon = [
			[0x4E20_E400, 0x6EA0_E400, 0x6E20_E400],
			[0x4E60_E400, 0x6EE0_E400, 0x6E60_E400]
		][1 if f64 else 0][imm8]
		word = neon | 1 << 16 if imm8 == 0 else neon | 1 << 5
		g.a64VecHalves(em, inst, [inst.a, inst.b], [word], 0)
	elif key == (3, 1, 0x4C) and inst.cond == 2:
		# vpblendvb: b's byte where c's byte has its top bit, else a's (the top bit spread by cmlt,
		# then bsl, or bit / bif where dst is a's or b's register)
		g.a64VecPerHalf(em, inst, 1)
	elif key == (1, 0, 0x52) and inst.b < 0:
		# vrsqrtps: each lane's 1/sqrt to x64's 12 bits: frsqrte's 8-bit estimate refined by one
		# Newton step (frsqrts), as the C programs' _mm_rsqrt_ps on NEON
		# frsqrte v1, v0; fmul v2, v0, v1; frsqrts v2, v2, v1; fmul v0, v1, v2
		words = [0x6EA1_D801, 0x6E21_DC02, 0x4EA1_FC42, 0x6E22_DC20]
		g.a64VecHalves(em, inst, [inst.a], words, 0)
	elif key[0] == 1 and key[2] == 0x51 and inst.b < 0:
		# vsqrtpd / vsqrtps: each lane's square root, correctly rounded (fsqrt .2d / .4s)
		g.a64VecHalves(em, inst, [inst.a], [0x6EE1_F800 if f64 else 0x6EA1_F800], 0)
	elif key[0] == 1 and key[2] == 0x5A and inst.b < 0:
		g.a64EmitVecConvert(em, inst, f64)
	elif key[0] == 3 and key[2] in [0x01, 0x0D]:
		# vpermpd a, imm (word i is a's word imm's bits 2i..2i+1) or vblendpd a, b, imm (word i
		# b's when imm's bit i is set, else a's): the four words read first, then written
		for i in 0..4:
			from = (imm8 >> (2 * i)) & 3 if key[2] == 0x01 else i
			pick = inst.b if key[2] == 0x0D and (imm8 >> i) & 1 == 1 else inst.a
			g.a64VecLane(em, pick, 8 * from, 8, true, 4 + i)
		for i in 0..4:
			g.a.a64(0x4E08_1C00 | (i % 2) << 20 | (4 + i) << 5 | i / 2)   # ins v(i/2).d[i%2], x(4+i)
		g.a64VecDone(em, inst.dst, 0, 0)
		g.a64VecDone(em, inst.dst, 1, 1)
	elif key == (3, 1, 0x06):
		# vperm2f128: each half the half imm's nibble names of a, b (0..3), or zeros (its bit 3)
		for h in 0..2:
			sel = (imm8 >> (4 * h)) & 15
			if sel & 8 != 0:
				g.a.a64(0x6F00_E400 | h)   # movi qh, 0
			else:
				g.a64VecInto(em, [inst.a, inst.b][sel >> 1], sel & 1, h)
		g.a64VecDone(em, inst.dst, 0, 0)
		g.a64VecDone(em, inst.dst, 1, 1)
	else:
		return false
	true

# a * b + c, a * b - c, c - a * b (the 231 forms, opcode 0xB8, 0xBA, 0xBC; w: f64 lanes): fmla or
# fmls into c's copy, in dst's own register when it is none of a's and b's
fn a64EmitVecFused(mut g Gen, em IrEmit, inst IrInst, opcode i64, w bool):
	fused = (0x4EE0_CC00 if w else 0x4EA0_CC00) if opcode == 0xBC
		else 0x4E60_CC00 if w else 0x4E20_CC00
	halves = 2 if (inst.imm >> 5) & 1 == 1 else 1
	for h in 0..2:
		if h >= halves:
			g.a64VecZero(em, inst.dst, h)
			continue
		a = g.a64VecIn(em, inst.a, h, 0)
		b = g.a64VecIn(em, inst.b, h, 1)
		acc = em.a64VecOut(inst.dst, h)
		if acc in [a, b, 0]:
			acc = 2
		g.a64VecInto(em, inst.c, h, acc)
		if opcode == 0xBA:
			g.a.a64((0x6EE0_F800 if w else 0x6EA0_F800) | acc << 5 | acc)   # fneg acc
		g.a.a64(fused | b << 16 | a << 5 | acc)   # fmla / fmls acc, a, b
		g.a64VecDone(em, inst.dst, h, acc)

# vpshufb (kind 0) or vpblendvb (kind 1) half by half, the operands read from their own registers
# (q0, q1, q2 only where one lives in its slot) and the result written to dst's own
fn a64VecPerHalf(mut g Gen, em IrEmit, inst IrInst, kind i64):
	halves = 2 if (inst.imm >> 5) & 1 == 1 else 1
	for h in 0..2:
		if h >= halves:
			g.a64VecZero(em, inst.dst, h)
			continue
		a = g.a64VecIn(em, inst.a, h, 0)
		b = g.a64VecIn(em, inst.b, h, 1)
		o = em.a64VecOut(inst.dst, h)
		if kind == 0:
			if not inst.uns:   # (uns: the indices' bits 4..6 known clear, irVecMasks.zap)
				g.a.a64(0x4F04_E5E0 | 2)   # movi v2.16b, 0x8f
				g.a.a64(0x4E20_1C00 | 2 << 16 | b << 5 | 1)   # and v1.16b, b.16b, v2.16b
				b = 1
			g.a.a64(0x4E00_0000 | b << 16 | a << 5 | o)   # tbl o.16b, {a.16b}, b.16b
		else:
			c = g.a64VecIn(em, inst.c, h, 2)   # (uns: its bytes known 0 or 0xFF, irVecMasks.zap)
			if o == a or o == b:
				mask = c if inst.uns else 2
				if not inst.uns:
					g.a.a64(0x4E20_A800 | c << 5 | 2)   # cmlt v2.16b, c.16b, #0
				if o == a:
					g.a.a64(0x6EA0_1C00 | mask << 16 | b << 5 | o)   # bit o, b, mask
				else:
					g.a.a64(0x6EE0_1C00 | mask << 16 | a << 5 | o)   # bif o, a, mask
			else:
				if not inst.uns:
					g.a.a64(0x4E20_A800 | c << 5 | o)   # cmlt o.16b, c.16b, #0
				elif o != c:
					g.a.a64(0x4EA0_1C00 | c << 16 | c << 5 | o)   # mov o.16b, c.16b
				g.a.a64(0x6E60_1C00 | a << 16 | b << 5 | o)   # bsl o, b, a
		g.a64VecDone(em, inst.dst, h, o)

# dst's halves: half h of each operand into q0, q1, q2, then the words, the result in q result; a
# 128-bit instruction's upper half zero
fn a64VecHalves(mut g Gen, em IrEmit, inst IrInst, operands i64[], words i64[], result i64):
	halves = 2 if (inst.imm >> 5) & 1 == 1 else 1
	for h in 0..2:
		if h < halves:
			for k, v in operands:
				g.a64VecInto(em, v, h, k)
			for word in words:
				g.a.a64(word)
			g.a64VecDone(em, inst.dst, h, result)
		else:
			g.a64VecZero(em, inst.dst, h)

# vcvtpd2ps (narrow: a's four f64s to four f32s in the low half, the high zero: fcvtn, fcvtn2)
# or vcvtps2pd (the low half's four f32s to four f64s: fcvtl, fcvtl2)
fn a64EmitVecConvert(mut g Gen, em IrEmit, inst IrInst, narrow bool):
	if narrow:
		g.a64VecInto(em, inst.a, 0, 1)
		g.a64VecInto(em, inst.a, 1, 2)
		g.a.a64Op2(0x0E61_6800, 0, 1)   # fcvtn v0.2s, v1.2d
		g.a.a64Op2(0x4E61_6800, 0, 2)   # fcvtn2 v0.4s, v2.2d
		g.a.a64(0x6F00_E400 | 1)   # movi q1, 0
	else:
		g.a64VecInto(em, inst.a, 0, 2)
		g.a.a64Op2(0x0E61_7800, 0, 2)   # fcvtl v0.2d, v2.2s
		g.a.a64Op2(0x4E61_7800, 1, 2)   # fcvtl2 v1.2d, v2.4s
	g.a64VecDone(em, inst.dst, 0, 0)
	g.a64VecDone(em, inst.dst, 1, 1)
