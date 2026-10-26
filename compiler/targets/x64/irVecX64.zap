# The machine code of the intermediate form's vectors (irVec vregs, irVecOp, irVecSplat,
# irVecMask): AVX on x/ymm registers, xmm0 and xmm1 the scratch ones, a spilled vector in a
# 32-byte slot. An operation's last operand may be read from memory: a spilled vreg's slot, a
# float constant's data.

# the encoding of an instruction for irVecOp: its opcode map (1 0F, 2 0F38, 3 0F3A), prefix (pp: 0
# none, 1 66, 2 F3, 3 F2), VEX.W, length (l 0: 128 bits, 1: 256), opcode and immediate (-1: none)
fn irVecCode(map i64, pp i64, w i64, l i64, op i64, imm8 i64):
	map | pp << 2 | w << 4 | l << 5 | op << 8 | (imm8 + 1) << 16

# the code of a table's instruction (vecGen.zap's vecOp: [map, pp, opcode]) at l
fn irVecTableCode(ins i64[], l i64, imm8 i64):
	irVecCode(ins[0], ins[1], 0, l, ins[2], imm8)

# the prefix of a VEX instruction of any length: C5 R.vvvv.L.pp, two bytes, for map 0F without
# W and with no register of the r/m operand above 7; else C4 RXB.map W.vvvv.L.pp
fn irVexL(mut g Gen, map i64, pp i64, w i64, l i64, reg i64, vvvv i64, index i64, base i64):
	tail = (15 - (vvvv & 15)) << 3 | l << 2 | pp
	r = 0x80 if reg < 8 else 0
	if map == 1 and w == 0 and index < 8 and base < 8:
		g.a.em2(0xC5, r | tail)
	else:
		b1 = map | r
		if index < 8:
			b1 |= 0x40
		if base < 8:
			b1 |= 0x20
		g.a.em3(0xC4, b1, (w << 7) | tail)
	if l == 1:
		g.usesAvx()   # the epilogue clears the upper halves

# the instruction of code on register reg, register vvvv and the r/m operand v (its register, its
# slot, or its float constant in the data)
fn irVecInsn(mut g Gen, em IrEmit, code i64, reg i64, vvvv i64, v i64):
	map = code & 3
	pp = (code >> 2) & 3
	w = (code >> 4) & 1
	l = (code >> 5) & 1
	op = (code >> 8) & 255
	if em.rs.isConst[v] and em.f.classes[v] == irFloat:
		g.irVexL(map, pp, w, l, reg, vvvv, -1, -1)
		g.a.em2(op, 0x05 | (reg & 7) << 3)
		g.a.asmDisp32Data(g.floatConst(em.rs.constVal[v]))
	elif em.rs.spilled[v] and not g.irHeld(em, v):
		g.irVexL(map, pp, w, l, reg, vvvv, -1, 4)
		g.a.em1(op)
		g.irModRm(reg, 4, -1, 1, g.irSlot(em, v))
	else:
		rm = g.irVecZero(1) if em.f.classes[v] == irVec and em.rs.isConst[v]
			else 0 if em.rs.spilled[v] else em.rs.reg[v]
		g.irVexL(map, pp, w, l, reg, vvvv, -1, rm)
		g.a.em2(op, 0xC0 | (reg & 7) << 3 | (rm & 7))
	g.irVecImm(code)
	if reg == 0:
		g.xmm0Held = -1

# the same on three registers
fn irVecInsnRR(mut g Gen, code i64, reg i64, vvvv i64, rm i64):
	g.irVexL(code & 3, (code >> 2) & 3, (code >> 4) & 1, (code >> 5) & 1, reg, vvvv, -1, rm)
	g.a.em2((code >> 8) & 255, 0xC0 | (reg & 7) << 3 | (rm & 7))
	g.irVecImm(code)
	if reg == 0:
		g.xmm0Held = -1

# whether xmm0 holds the spilled vector v, stored from there by the instruction before
fn irHeld(g Gen, em IrEmit, v i64):
	v == g.xmm0Held and em.f.classes[v] == irVec

fn irVecImm(mut g Gen, code i64):
	imm8 = (code >> 16) - 1
	if imm8 >= 0:
		g.a.em1(imm8)

# x = a vector of zeros (the only vector constant)
fn irVecZero(mut g Gen, x i64):
	if x == 0:
		g.xmm0Held = -1
	if x == 0 and g.xmm0Zero: return x
	g.irVecInsnRR(irVecCode(1, 0, 0, 1, 0x57, -1), x, x, x)   # vxorps ymm x, x, x
	g.xmm0Zero = x == 0 or g.xmm0Zero
	x

# the register holding v, a vector or a float: its own, or scratch loaded with it
fn irXmmIn(mut g Gen, em IrEmit, v i64, scratch i64):
	if em.f.classes[v] == irFloat:
		if scratch == 0:
			g.xmm0Held = -1
		return g.irFloatIn(em, v, scratch)
	if em.rs.isConst[v]: return g.irVecZero(scratch)
	if em.rs.spilled[v]:
		if scratch == 0 and g.irHeld(em, v): return 0
		g.irVexL(1, 0, 0, 1, scratch, 0, -1, 4)
		g.a.em1(0x10)   # vmovups ymm scratch, [rsp+slot]
		g.irModRm(scratch, 4, -1, 1, g.irSlot(em, v))
		if scratch == 0:
			g.xmm0Held = v
		return scratch
	em.rs.reg[v]

# v's value, computed in register x, put where v lives
fn irXmmDone(mut g Gen, em IrEmit, v i64, x i64):
	if em.f.classes[v] == irFloat:
		if x == 0:
			g.xmm0Held = -1
		g.irFloatDone(em, v, x)
		return
	if em.rs.spilled[v]:
		g.irVexL(1, 0, 0, 1, x, 0, -1, 4)
		g.a.em1(0x11)   # vmovups [rsp+slot], ymm x
		g.irModRm(x, 4, -1, 1, g.irSlot(em, v))
		g.xmm0Held = v if x == 0 else -1 if g.xmm0Held == v else g.xmm0Held
	elif em.rs.reg[v] >= 0 and em.rs.reg[v] != x:
		g.irVecInsnRR(irVecCode(1, 0, 0, 1, 0x28, -1), em.rs.reg[v], 0, x)   # vmovaps ymm

# the register an instruction computes v into (xmm0 when v lives in a slot)
fn irXmmOut(em IrEmit, v i64):
	em.rs.reg[v] if em.rs.reg[v] >= 0 else 0

# irVecOp: dst = a op b (or op a), dst = c + a op b (an FMA's accumulator), or a and b blended by c
fn irEmitVecOp(mut g Gen, em IrEmit, inst IrInst):
	out = em.irXmmOut(inst.dst)
	if inst.cond == 1:
		g.irEmitVecFma(em, inst, none)
		return
	if inst.cond == 2:
		ra = g.irXmmIn(em, inst.a, 0)
		mask = g.irXmmIn(em, inst.c, 1)
		g.irVecInsn(em, inst.imm | (((mask << 4) + 1) << 16), out, ra, inst.b)   # vpblendvb: the mask's register in the immediate
		g.irXmmDone(em, inst.dst, out)
		return
	if inst.b < 0:
		g.irVecInsn(em, inst.imm, out, 0, inst.a)
	elif irCommutes(inst.imm) and em.rs.spilled[inst.a] and not g.irHeld(em, inst.a) and
		em.irInReg(inst.b):
		g.irVecInsn(em, inst.imm, out, em.rs.reg[inst.b], inst.a)   # the slot read as the r/m operand
	else:
		g.irVecInsn(em, inst.imm, out, g.irXmmIn(em, inst.a, 0), inst.b)
	g.irXmmDone(em, inst.dst, out)

# whether the instruction of code is vaddps/pd or vmulps/pd (its operands swap)
fn irCommutes(code i64):
	op = (code >> 8) & 255
	code & 3 == 1 and (code >> 2) & 3 < 2 and (op == 0x58 or op == 0x59) and code >> 16 == 0

# irVecOp of two operands, the last read from a load's memory (irFoldedUse)
fn irEmitVecOpFrom(mut g Gen, em IrEmit, inst IrInst, load IrInst):
	at, base, index = g.irMemoryAt(em, load)
	out = em.irXmmOut(inst.dst)
	ra = g.irXmmIn(em, inst.a, 0)
	code = inst.imm
	g.irVexL(code & 3, (code >> 2) & 3, (code >> 4) & 1, (code >> 5) & 1, out, ra, index, base)
	g.a.em1((code >> 8) & 255)
	g.irModRm(out, base, index, at.scale, at.imm)
	g.irVecImm(code)
	g.irXmmDone(em, inst.dst, out)

# irVecOp of a fused multiply-add (dst = c + a op b), its operands in the three places of an FMA:
# the register written (the one of the operands already there, else the accumulator moved in),
# a register, and the r/m operand (a load's memory, a slot, a register); the form follows the
# places: 231 the accumulator written, 213 the accumulator r/m, 132 the accumulator the register
fn irEmitVecFma(mut g Gen, em IrEmit, inst IrInst, load IrInst?):
	out = em.irXmmOut(inst.dst)
	mem = -1   # the operand read from the load's memory
	if load is from:
		mem = from.dst
	ops = [inst.a, inst.b, inst.c]
	x1 = -1
	for p in [2, 0, 1]:
		if x1 < 0 and ops[p] != mem and em.irInReg(ops[p]) and em.rs.reg[ops[p]] == out:
			x1 = p
	if x1 < 0:
		x1 = 2 if ops[2] != mem else 0
		r = g.irXmmIn(em, ops[x1], out)
		if r != out:
			g.irVecInsnRR(irVecCode(1, 0, 0, 1, 0x28, -1), out, 0, r)   # vmovaps
	rest = [0, 1, 2].filter(it != x1)
	# r/m: the load, else what is not in a register (a slot before a constant, whose zero takes
	# xmm1 when it is the r/m operand)
	rm = rest[1]
	for p in rest:
		if ops[p] == mem or mem < 0 and em.rs.spilled[ops[p]]:
			rm = p
	if mem < 0 and not em.rs.spilled[ops[rm]] and em.rs.isConst[ops[rest[0]]]:
		rm = rest[0]
	vv = rest[0] if rm == rest[1] else rest[1]
	shift = 0 if x1 == 2 else 0x10 if rm == 2 else 0x20   # 231, 213, 132
	code = inst.imm - (shift << 8)
	rv = g.irXmmIn(em, ops[vv], 1 if out == 0 else 0)
	if load is from:
		at, base, index = g.irMemoryAt(em, from)
		g.irVexL(code & 3, (code >> 2) & 3, (code >> 4) & 1, (code >> 5) & 1, out, rv, index, base)
		g.a.em1((code >> 8) & 255)
		g.irModRm(out, base, index, at.scale, at.imm)
		g.irVecImm(code)
	else:
		g.irVecInsn(em, code, out, rv, ops[rm])
	g.irXmmDone(em, inst.dst, out)

# irVecSplat: the scalar a in every lane
fn irEmitVecSplat(mut g Gen, em IrEmit, inst IrInst):
	out = em.irXmmOut(inst.dst)
	g.xmm0Held = -1   # xmm0 the scalar's scratch
	l = 1 if inst.size == 32 else 0
	if inst.imm == irLaneF64:
		x = g.irFloatIn(em, inst.a, 0)
		g.irVecInsnRR(irVecCode(2, 1, 0, l, 0x19, -1), out, 0, x)   # vbroadcastsd
	elif inst.imm == irLaneF32:
		x = g.irFloatIn(em, inst.a, 0)
		g.irVecInsnRR(irVecCode(1, 3, 0, 0, 0x5A, -1), 0, x, x)   # vcvtsd2ss xmm0, x, x
		g.irVecInsnRR(irVecCode(2, 1, 0, l, 0x18, -1), out, 0, 0)   # vbroadcastss
	else:
		r = g.irIntIn(em, inst.a, 0)
		g.irVecInsnRR(irVecCode(1, 1, 1, 0, 0x6E, -1), 0, 0, r)   # vmovq xmm0, r
		op = 0x78 if inst.imm == irLaneU8 else 0x58 if inst.imm == irLaneI32 else 0x59   # vpbroadcastb, d, q
		g.irVecInsnRR(irVecCode(2, 1, 0, l, op, -1), out, 0, 0)
	g.irXmmDone(em, inst.dst, out)

# irVecLaneOf: lane imm of a, an integer of size bytes (vmovd or vmovq for lane 0, else vpextr),
# extended
fn irEmitVecLaneOf(mut g Gen, em IrEmit, inst IrInst):
	x = g.irXmmIn(em, inst.a, 0)
	r = em.irIntOut(inst.dst)
	k = inst.imm
	w = 1 if inst.size == 8 else 0
	if k == 0 and inst.size >= 4:
		g.irVecInsnRR(irVecCode(1, 1, w, 0, 0x7E, -1), x, 0, r)   # vmovd / vmovq r, x
	else:
		op = 0x14 if inst.size == 1 else 0x15 if inst.size == 2 else 0x16   # vpextrb, w, d / q
		g.irVecInsnRR(irVecCode(3, 1, w, 0, op, k), x, 0, r)
	if not inst.uns and inst.size < 8:
		g.irExtend(r, r, inst.size, false)
	g.irIntDone(em, inst.dst, r)

# irVecMask: the sign of each lane of a as a bit of dst
fn irEmitVecMask(mut g Gen, em IrEmit, inst IrInst):
	x = g.irXmmIn(em, inst.a, 0)
	r = em.irIntOut(inst.dst)
	l = 1 if inst.size == 32 else 0
	if inst.imm == 2:
		g.irVecInsnRR(irVecCode(1, 1, 0, l, 0xD7, -1), r, 0, x)   # vpmovmskb r32, x
	else:
		g.irVecInsnRR(irVecCode(1, inst.imm, 0, l, 0x50, -1), r, 0, x)   # vmovmskps / vmovmskpd
	g.irIntDone(em, inst.dst, r)

# a vector's copy, its constant (zero), a load or a store of one (16 or 32 bytes, unaligned)
fn irEmitVecMove(mut g Gen, em IrEmit, inst IrInst, base i64, index i64):
	if inst.op == irConst:
		g.irXmmDone(em, inst.dst, g.irVecZero(em.irXmmOut(inst.dst)))
	elif inst.op == irCopy:
		out = em.irXmmOut(inst.dst)
		g.irXmmDone(em, inst.dst, g.irXmmIn(em, inst.a, out))
	elif inst.op == irLoad:
		out = em.irXmmOut(inst.dst)
		g.irVexL(1, 2, 0, 1 if inst.size == 32 else 0, out, 0, index, base)
		g.a.em1(0x6F)   # vmovdqu x, [mem]
		g.irModRm(out, base, index, inst.scale, inst.imm)
		g.irXmmDone(em, inst.dst, out)
	else:
		x = g.irXmmIn(em, inst.c, 0)
		g.irVexL(1, 2, 0, 1 if inst.size == 32 else 0, x, 0, index, base)
		g.a.em1(0x7F)   # vmovdqu [mem], x
		g.irModRm(x, base, index, inst.scale, inst.imm)
