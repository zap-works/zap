# The operands of emitted instructions: registers, moves, VEX and ALU forms, comparisons (irX64.zap).

# the integer register holding v: its own, or scratch loaded with it
fn irIntIn(mut g Gen, em IrEmit, v i64, scratch i64):
	if em.rs.isFrame[v]:
		g.a.memOp(true, 0x8D, -1, scratch, 4, -1, g.irDisp(em.rs.constVal[v]))   # lea scratch, [rsp+disp]
		return scratch
	if em.rs.isConst[v]:
		g.irMovImm(scratch, em.rs.constVal[v])
		return scratch
	if em.rs.isData[v]:
		g.a.memOp(true, 0x8D, -1, scratch, ripBase, -1, em.rs.constVal[v])   # lea scratch, [rip + data]
		return scratch
	if em.rs.spilled[v]:
		g.a.memOp(true, 0x8B, -1, scratch, 4, -1, g.irSlot(em, v))
		return scratch
	em.rs.reg[v]

# the integer register an instruction computes v into (rax when v lives in a slot)
fn irIntOut(em IrEmit, v i64):
	em.rs.reg[v] if em.rs.reg[v] >= 0 else 0

# v's value, computed into register r, put where v lives
fn irIntDone(mut g Gen, em IrEmit, v i64, r i64):
	if em.rs.spilled[v]:
		g.a.memOp(true, 0x89, -1, r, 4, -1, g.irSlot(em, v))
	elif em.rs.reg[v] >= 0:
		g.irMov(em.rs.reg[v], r)

fn irFloatIn(mut g Gen, em IrEmit, v i64, scratch i64):
	if em.rs.isConst[v]:
		g.irFloatConst(scratch, em.rs.constVal[v])
		return scratch
	if em.rs.spilled[v]:
		g.irVexRM(3, 0, 0x10, scratch, 0, 4, -1, 1, g.irSlot(em, v))   # vmovsd
		return scratch
	em.rs.reg[v]

# x = the f64 of these bits: 0 by a vxorps, any other from the data
fn irFloatConst(mut g Gen, x i64, bits i64):
	if bits == 0:
		if x == 0 and g.xmm0Zero: return
		g.irVexRR(0, 0, 0x57, x, x, x)
		if x == 0:
			g.xmm0Zero = true
	else:
		if x == 0:
			g.xmm0Zero = false
		g.irVexData(3, 0x10, x, 0, g.floatConst(bits))

fn irFloatOut(em IrEmit, v i64):
	em.rs.reg[v] if em.rs.reg[v] >= 0 else 0

fn irFloatDone(mut g Gen, em IrEmit, v i64, x i64):
	if em.rs.spilled[v]:
		g.irVexRM(3, 0, 0x11, x, 0, 4, -1, 1, g.irSlot(em, v))
	elif em.rs.reg[v] >= 0 and em.rs.reg[v] != x:
		g.irMovapd(em.rs.reg[v], x)

# ---------- instructions ----------

fn irMov(mut g Gen, dst i64, src i64):
	if dst != src:
		g.regOp(true, 0x89, -1, src, dst)

fn irMovImm(mut g Gen, r i64, v i64):
	if v >= 0 and v <= 4_294_967_295:
		if r >= 8: g.a.em1(0x41)
		g.a.em1(0xB8 | (r & 7))   # mov r32, imm32 (zero-extended)
		g.a.emit32(v)
	elif fitsImm32(v):
		g.regOp(true, 0xC7, -1, 0, r)
		g.a.emit32(v)
	else:
		g.a.em1(0x49 if r >= 8 else 0x48)
		g.a.em1(0xB8 | (r & 7))
		g.a.emit64(v)

fn irMovapd(mut g Gen, dst i64, src i64):
	if dst != src:
		g.irVexRR(1, 0, 0x28, dst, 0, src)

fn irMovqToXmm(mut g Gen, x i64, r i64):
	g.irVexRR(1, 1, 0x6E, x, 0, r)

fn irMovqFromXmm(mut g Gen, r i64, x i64):
	g.irVexRR(1, 1, 0x7E, x, 0, r)

# ---------- VEX ----------

# the VEX prefix (irVexL) of a 128-bit instruction of map 0F on register reg, register vvvv (0
# when it takes none) and an r/m operand of index and base registers (-1: none); pp 0 none, 1
# 66, 2 F3, 3 F2
fn irVex(mut g Gen, pp i64, w i64, reg i64, vvvv i64, index i64, base i64):
	g.irVexMap(1, pp, w, reg, vvvv, index, base)

# the same prefix for an opcode map (1 0F, 2 0F38, 3 0F3A)
fn irVexMap(mut g Gen, map i64, pp i64, w i64, reg i64, vvvv i64, index i64, base i64):
	g.irVexL(map, pp, w, 0, reg, vvvv, index, base)

# op reg, vvvv, rm
fn irVexRR(mut g Gen, pp i64, w i64, op i64, reg i64, vvvv i64, rm i64):
	g.irVex(pp, w, reg, vvvv, -1, rm)
	g.a.em2(op, 0xC0 | (reg & 7) << 3 | (rm & 7))

# op reg, vvvv, [base + index * scale + disp]
fn irVexRM(
	mut g Gen,
	pp i64,
	w i64,
	op i64,
	reg i64,
	vvvv i64,
	base i64,
	index i64,
	scale i64,
	disp i64
):
	g.irVex(pp, w, reg, vvvv, index, base)
	g.a.em1(op)
	g.irModRm(reg, base, index, scale, disp)

# op reg, vvvv, [rip + the data at off]
fn irVexData(mut g Gen, pp i64, op i64, reg i64, vvvv i64, off i64):
	g.irVex(pp, 0, reg, vvvv, -1, -1)
	g.a.em2(op, 0x05 | (reg & 7) << 3)
	g.a.asmDisp32Data(off)

# op reg, vvvv, v: v's register, its frame slot, or its constant in the data
fn irVexOperand(mut g Gen, em IrEmit, pp i64, op i64, reg i64, vvvv i64, v i64):
	if em.rs.isConst[v]:
		g.irVexData(pp, op, reg, vvvv, g.floatConst(em.rs.constVal[v]))
	elif em.rs.spilled[v]:
		g.irVexRM(pp, 0, op, reg, vvvv, 4, -1, 1, g.irSlot(em, v))
	else:
		g.irVexRR(pp, 0, op, reg, vvvv, em.rs.reg[v])

# the ModRM byte (and SIB, displacement) of [base + index * scale + disp]
fn irModRm(mut g Gen, reg i64, base i64, index i64, scale i64, disp i64):
	if index < 0:
		g.a.emModRm(reg, base, -1, disp)
		return
	md = 0x80
	if disp == 0 and (base & 7) != 5:
		md = 0
	elif disp >= -128 and disp <= 127:
		md = 0x40
	g.a.em2(md | (reg & 7) << 3 | 4, scaleBitsOf(scale) << 6 | (index & 7) << 3 | (base & 7))
	if md == 0x40:
		g.a.em1(disp & 255)
	elif md == 0x80:
		g.a.emit32(disp)

# an ALU instruction on register r and v: opRR (op r/m, reg), opRM (op reg, r/m), the 0x81 digit
fn irAluOperand(
	mut g Gen,
	em IrEmit,
	opRR i64,
	opRM i64,
	digit i64,
	r i64,
	v i64,
	wide bool = true
):
	if em.rs.isConst[v] and (fitsImm32(em.rs.constVal[v]) or not wide):
		c = em.rs.constVal[v] if wide else irLow32(em.rs.constVal[v])
		if c == 0 and digit == 7:
			g.regOp(wide, 0x85, -1, r, r)   # test r, r: the same flags as cmp r, 0
		elif c >= -128 and c <= 127:
			g.regOp(wide, 0x83, -1, digit, r)
			g.a.em1(c & 255)
		else:
			g.regOp(wide, 0x81, -1, digit, r)
			g.a.emit32(c)
		return
	if em.rs.spilled[v]:
		g.a.memOp(wide, opRM, -1, r, 4, -1, g.irSlot(em, v))
		return
	g.regOp(wide, opRR, -1, g.irIntIn(em, v, 1), r)

# the low 32 bits of c as a signed 32-bit number: an operation on 32 bits reads only those
fn irLow32(c i64):
	((c & 0xFFFF_FFFF) ^ 0x8000_0000) - 0x8000_0000

# x64 condition codes (the jcc's second byte) of an integer comparison
fn irJcc(cond i64, uns bool):
	if cond == irEq: return 0x84
	if cond == irNe: return 0x85
	if cond == irLt: return 0x82 if uns else 0x8C
	if cond == irLe: return 0x86 if uns else 0x8E
	if cond == irGt: return 0x87 if uns else 0x8F
	0x83 if uns else 0x8D

# cmp a, b (integers)
fn irCompareInt(mut g Gen, em IrEmit, a i64, b i64):
	ra = g.irIntIn(em, a, 0)
	g.irAluOperand(em, 0x39, 0x3B, 7, ra, b)

# the comparison of a and b for cond, the constant side (if one) as the immediate: the condition
# the flags then answer
fn irCompareIntFor(mut g Gen, em IrEmit, a i64, b i64, cond i64):
	if em.rs.isConst[a] and not em.rs.isConst[b]:
		g.irCompareInt(em, b, a)
		return irSwappedCond(cond)
	g.irCompareInt(em, a, b)
	cond

# the condition with its sides swapped (a < b is b > a)
fn irSwappedCond(cond i64):
	irGt if cond == irLt
		else irLt if cond == irGt
		else irGe if cond == irLe
		else irLe if cond == irGe
		else cond

# vucomisd for a float comparison of a and b: the operands ordered so the condition is above
# (or above-or-equal), which a NaN never meets
fn irCompareFloat(mut g Gen, em IrEmit, cond i64, a i64, b i64):
	swap = cond == irLt or cond == irLe
	x = g.irFloatIn(em, b if swap else a, 0)
	g.irVexOperand(em, 1, 0x2E, x, 0, a if swap else b)

fn irFloatJcc(cond i64):
	0x87 if cond == irGt or cond == irLt
		else 0x84 if cond == irEq
		else 0x85 if cond == irNe
		else 0x83

# the result in rax, then to label: the epilogue, or the restore stub of a save point above; a
# return without the frame is a ret of its own
fn irEmitReturn(mut g Gen, em IrEmit, inst IrInst, label i64):
	if not inst.args.isEmpty:
		leaves = [inst.a]
		leaves.extend(inst.args)
		g.irResultIn(em, leaves)
	elif inst.a >= 0:
		if em.f.classes[inst.a] == irFloat:
			g.irMovqFromXmm(0, g.irFloatIn(em, inst.a, 0))
		else:
			g.irMov(0, g.irIntIn(em, inst.a, 0))
	if g.f.framed:
		g.a.jmpLabel(label)
	else:
		g.a.em1(0xC3)   # ret
