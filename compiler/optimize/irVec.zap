# The vectors in the intermediate form: Simd<4, f64>, Simd<16, u8> and vecs.zap's SimdN<T>. A vector
# is one leaf of class irVec (an aggregate of one leaf: lent by address, returned through a slot,
# 32 bytes in memory); its operations are the AVX instructions of vecGen.zap's table (irVecOp),
# a broadcast (irVecSplat) and a lane mask (irVecMask). Lanes are read through a frame slot.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

fn irIsVector(g Gen, maybeT TypeId?):
	t = maybeT ?? return false
	tys[t].kind in [tSimd, tBytes, tVec]

# a vector type's row of the table (vecGen.zap) and its length bit (0: 128 bits, 1: 256)
fn irVecRow(mut g Gen, t TypeId) i64:
	k = tys[t].kind
	vecRowF64 if k == tSimd else vecRowU8 if k == tBytes else g.vecRow(t)

fn irVecL(g Gen, t TypeId):
	0 if tys[t].kind == tBytes else 1

# a vector type's lanes, and their type
fn irVecLanes(g Gen, t TypeId):
	k = tys[t].kind
	4 if k == tSimd else 16 if k == tBytes else tys[t].bits

fn irVecElem(g Gen, t TypeId):
	k = tys[t].kind
	tyFloat(64) if k == tSimd else tyInt(8, false) if k == tBytes else innerOf(tys, t)

fn irVecOpOf(mut lw IrLower, code i64, a i64, b i64) i64:
	lw.irDef(irVec, IrInst(op = irVecOp, a, b, imm = code))

# a fused multiply and add (dst = c + a op b, rounded once): opcode the 231 form's (vfmadd231,
# vfmsub231, vfnmadd231), l 1 for 32 bytes
fn irVecFma(mut lw IrLower, class i64, opcode i64, l i64, a i64, b i64, c i64) i64:
	lw.irDef(
		class,
		IrInst(op = irVecOp, a, b, c, cond = 1, imm = irVecCode(2, 1, 1, l, opcode, -1))
	)

# a op b lane by lane, the operator one of the table's
fn irVecBinary(mut g Gen, mut lw IrLower, e NodeId):
	t = g.ty(e)
	ins = vecOp(g.irVecRow(t), vecOpName(nodes[e].ival))
	if ins.isEmpty: return lw.irRefused("a vector operation of {typeStr(tys, t)}")
	a = g.irExpr(lw, nodes[e].kids(kidIds)[0])
	b = g.irExpr(lw, nodes[e].kids(kidIds)[1])
	if not lw.ok: return []
	[lw.irVecOpOf(irVecTableCode(ins, g.irVecL(t), -1), a, b)]

# whether e is a call the vectors' code lowers: a vector's lanes, a splat, a list's loadN or
# storeN of a vector, any method of a vector, a float's fused multiply-add
fn irIsVecCall(mut g Gen, e NodeId):
	if nodes[e].hasFlag(flagVecLit): return true
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind != nField: return false
	m = nodes[callee].text
	rt = g.ty(nodes[callee].kids(kidIds)[0])
	if g.irIsVector(rt): return true
	if g.irIsVector(g.ty(e)) and (m.startsWith("splat") or m.startsWith("load")): return true
	args = nodes[e].kids(kidIds).len - 1
	if m.startsWith("store") and args == 2 and g.irIsVector(g.ty(nodes[e].kids(kidIds)[2])):
		return true
	m == "mulAdd" and args == 2 and g.tyK(rt) == tFloat

fn irVecCall(mut g Gen, mut lw IrLower, e NodeId):
	if nodes[e].hasFlag(flagVecLit): return g.irVecLiteral(lw, e)
	callee = nodes[e].kids(kidIds)[0]
	m = nodes[callee].text.copy()
	recv = nodes[callee].kids(kidIds)[0]
	args = nodes[e].kidsFrom(kidIds, 1).copy()
	t = g.ty(e)
	rt = g.ty(recv)
	if m == "mulAdd" and not g.irIsVector(rt):
		# x.mulAdd(y, z): x * y + z rounded once (vfmadd231sd)
		x = g.irExpr(lw, recv)
		y = g.irExpr(lw, args[0])
		z = g.irExpr(lw, args[1])
		if not lw.ok: return []
		v = lw.irVecFma(irFloat, 0xB9, 0, x, y, z)
		return [g.irRounded(lw, v, t)]   # an f32's: the exact f64 result rounded to single
	if m.startsWith("splat"): return [g.irVecSplatOf(lw, t, g.irExpr(lw, recv))]
	if m.startsWith("load"):
		at = g.irLanesAddr(lw, recv, args[0], g.irVecLanes(t), g.sizeOf(g.irVecElem(t)))
		if not lw.ok: return []
		v = lw.f.irVreg(irVec)
		irPut(
			lw,
			IrInst(
				op = irLoad,
				dst = v,
				a = at,
				size = g.irVecLanes(t) * g.sizeOf(g.irVecElem(t))
			)
		)
		return [v]
	if m.startsWith("store"):
		vt = g.ty(args[1])
		v = g.irExpr(lw, args[1])   # the value first, as written
		at = g.irLanesAddr(lw, recv, args[0], g.irVecLanes(vt), g.sizeOf(g.irVecElem(vt)))
		if not lw.ok: return []
		irPut(
			lw,
			IrInst(
				op = irStore,
				a = at,
				c = v,
				size = g.irVecLanes(vt) * g.sizeOf(g.irVecElem(vt))
			)
		)
		return []
	a = g.irExpr(lw, recv)
	if not lw.ok: return []
	if m == "lane":
		return [g.irVecLaneConst(lw, rt, a, args[0]) ?? return g.irVecLane(lw, rt, a, args[0])]
	if m == "sum": return [g.irVecSum(lw, rt, a)]
	if m.endsWith("Mask"): return [g.irVecMaskOf(lw, rt, m, a, g.irExpr(lw, args[0]))]
	if m == "min" or m == "max":
		return [g.irVecMinMax(lw, rt, m == "min", a, g.irExpr(lw, args[0]))]
	row = g.irVecRow(rt)
	l = g.irVecL(rt)
	if m == "sqrt": return [lw.irVecOpOf(irVecCode(1, 1, 0, 1, 0x51, -1), a, -1)]   # vsqrtpd
	if m == "rsqrtEstimate":
		# the hardware's 12-bit 1/sqrt estimate, through single precision
		narrow = lw.irVecOpOf(irVecCode(1, 1, 0, 1, 0x5A, -1), a, -1)   # vcvtpd2ps xmm, ymm
		est = lw.irVecOpOf(irVecCode(1, 0, 0, 0, 0x52, -1), narrow, -1)   # vrsqrtps
		return [lw.irVecOpOf(irVecCode(1, 0, 0, 1, 0x5A, -1), est, -1)]   # vcvtps2pd ymm, xmm
	if m == "spread": return [g.irVecSpread(lw, rt, a, args[0])]
	if m == "sums4":
		hadd = vecOp(row, "hadd")
		ab = lw.irVecOpOf(irVecTableCode(hadd, 1, -1), a, g.irExpr(lw, args[0]))
		cd = irVecOpOf(
			lw,
			irVecTableCode(hadd, 1, -1),
			g.irExpr(lw, args[1]),
			g.irExpr(lw, args[2])
		)
		swap = lw.irVecOpOf(irVecCode(3, 1, 0, 1, 0x06, 0x21), ab, cd)   # vperm2f128: ab's high half, cd's low
		blend = lw.irVecOpOf(irVecCode(3, 1, 0, 1, 0x0D, 12), ab, cd)   # vblendpd: ab's low half, cd's high
		return [lw.irVecOpOf(irVecTableCode(vecOp(row, "add"), 1, -1), blend, swap)]
	if m in ["mulAdd", "mulSub", "subMul"]:
		x = g.irExpr(lw, args[0])
		y = g.irExpr(lw, args[1])
		if not lw.ok: return []
		# acc + a*b (vfmadd231pd), a*b - acc (vfmsub231pd), acc - a*b (vfnmadd231pd)
		if m == "mulAdd": return [lw.irVecFma(irVec, 0xB8, 1, a, x, y)]
		if m == "mulSub": return [lw.irVecFma(irVec, 0xBA, 1, a, x, y)]
		return [lw.irVecFma(irVec, 0xBC, 1, x, y, a)]
	if m == "shuffle" or m == "eqBytes":
		return [
			irVecOpOf(
				lw,
				irVecTableCode(vecOp(row, "shuffle" if m == "shuffle" else "eq"), l, -1),
				a,
				g.irExpr(lw, args[0])
			)
		]
	if m == "blend":
		w = g.irExpr(lw, args[0])
		mask = g.irExpr(lw, args[1])
		if not lw.ok: return []
		return [lw.irVecBlend(l, a, w, mask)]
	lw.irFail("{typeStr(tys, rt)}.{m}")
	[]

# where the mask's byte has its high bit, b's byte, else a's (vpblendvb)
fn irVecBlend(mut lw IrLower, l i64, a i64, b i64, mask i64):
	v = lw.f.irVreg(irVec)
	irPut(
		lw,
		IrInst(
			op = irVecOp,
			dst = v,
			a,
			b,
			c = mask,
			cond = 2,
			imm = irVecCode(3, 1, 0, l, 0x4C, -1)
		)
	)
	v

# the scalar x in every lane of a vector of type t
fn irVecSplatOf(mut g Gen, mut lw IrLower, t TypeId, x i64):
	if not lw.ok: return -1
	row = g.irVecRow(t)
	kind = irLaneF64 if row == vecRowF64
		else irLaneF32 if row == 0
		else irLaneI32 if row == 1
		else irLaneI64 if row == 2
		else irLaneU8
	s = x
	if (kind == irLaneF64 or kind == irLaneF32) and lw.f.classes[x] == irInt:
		s = lw.irDef(irFloat, IrInst(op = irIntToFloat, a = x))
	v = lw.f.irVreg(irVec)
	irPut(
		lw,
		IrInst(
			op = irVecSplat,
			dst = v,
			a = s,
			imm = kind,
			size = 32 if g.irVecL(t) == 1 else 16
		)
	)
	v

# the address of xs[i], the `lanes` elements from it checked within the list
fn irLanesAddr(mut g Gen, mut lw IrLower, xs NodeId, idx NodeId, lanes i64, size i64) i64:
	i = g.irExpr(lw, idx)
	items, n = g.irItemsAndLength(lw, xs)
	if not lw.ok: return -1
	last = lw.irDef(irInt, IrInst(op = irAdd, a = i, b = lw.irConstOf(irInt, lanes - 1)))
	lw.irPut(IrInst(op = irFailIf, a = i, b = n, cond = irGe, uns = true, imm = g.failBounds))
	lw.irPut(IrInst(op = irFailIf, a = last, b = n, cond = irGe, uns = true, imm = g.failBounds))
	lw.irDef(irInt, IrInst(op = irAdd, a = items, b = lw.irScaled(i, size)))

# the vector a in a frame slot of its own, for reading its lanes
fn irVecSlot(mut lw IrLower, a i64):
	slot = lw.irNewSlot(32)
	lw.irPut(IrInst(op = irStore, a = slot, c = a, size = 32))
	slot

# lane i of the vector a of type t, the index checked
fn irVecLane(mut g Gen, mut lw IrLower, t TypeId, a i64, idx NodeId) i64[]:
	slot = lw.irVecSlot(a)
	i = g.irExpr(lw, idx)
	if not lw.ok: return []
	irPut(
		lw,
		IrInst(
			op = irFailIf,
			a = i,
			b = lw.irConstOf(irInt, g.irVecLanes(t)),
			cond = irGe,
			uns = true,
			imm = g.failBounds
		)
	)
	elem = g.irVecElem(t)
	g.irLoadValue(lw, elem, slot, i, g.sizeOf(elem))

# a vector's lane at a constant index, an integer in its first 16 bytes: read from its register
fn irVecLaneConst(mut g Gen, mut lw IrLower, t TypeId, a i64, idx NodeId) i64?:
	elem = g.irVecElem(t)
	if not g.isIntLit(idx) or g.irClassOf(elem) != irInt: return none
	k = g.intLitValue(idx)
	size = g.sizeOf(elem)
	if k < 0 or k >= g.irVecLanes(t) or (k + 1) * size > 16: return none
	lw.irDef(irInt, IrInst(op = irVecLaneOf, a, imm = k, size, uns = not g.irSigned(elem)))

# every lane a.spread(i) is: a's lane i (vpermpd for a constant, else a lane read and splat)
fn irVecSpread(mut g Gen, mut lw IrLower, t TypeId, a i64, idx NodeId) i64:
	if g.isIntLit(idx) and g.intLitValue(idx) >= 0 and g.intLitValue(idx) <= 3:
		return lw.irVecOpOf(irVecCode(3, 1, 1, 1, 0x01, g.intLitValue(idx) * 0x55), a, -1)
	lane = g.irVecLane(lw, t, a, idx)
	if lane.len != 1: return -1
	g.irVecSplatOf(lw, t, lane[0])

# the lanes of a added: f64's pairwise ((0 + 1) + (2 + 3), as vhaddpd does), the others in order in
# the element's own arithmetic (f32 rounded at each step, integers wrapping)
fn irVecSum(mut g Gen, mut lw IrLower, t TypeId, a i64):
	slot = lw.irVecSlot(a)
	elem = g.irVecElem(t)
	size = g.sizeOf(elem)
	lanes = []
	for i in 0..irVecLanes(g, t):
		lanes.push(g.irVecLaneAt(lw, elem, slot, i * size))
	float = g.tyK(elem) == tFloat
	if tys[t].kind == tSimd:
		lo = lw.f.irVreg(irFloat)
		hi = lw.f.irVreg(irFloat)
		v = lw.f.irVreg(irFloat)
		lw.irPut(IrInst(op = irFAdd, dst = lo, a = lanes[0], b = lanes[1]))
		lw.irPut(IrInst(op = irFAdd, dst = hi, a = lanes[2], b = lanes[3]))
		lw.irPut(IrInst(op = irFAdd, dst = v, a = lo, b = hi))
		return v
	acc = lanes[0]
	for i in 1..lanes.len:
		next = lw.f.irVreg(irFloat if float else irInt)
		lw.irPut(IrInst(op = irFAdd if float else irAdd, dst = next, a = acc, b = lanes[i]))
		acc = g.irRounded(lw, next, elem) if float else next
	if not float and tys[elem].bits < 64:
		w = lw.f.irVreg(irInt)
		irPut(
			lw,
			IrInst(
				op = irTrunc,
				dst = w,
				a = acc,
				imm = tys[elem].bits,
				uns = not g.irSigned(elem)
			)
		)
		acc = w
	acc

fn irVecLaneAt(mut g Gen, mut lw IrLower, elem TypeId, slot i64, off i64):
	v = lw.f.irVreg(g.irClassOf(elem))
	irPut(
		lw,
		IrInst(
			op = irLoad,
			dst = v,
			a = slot,
			imm = off,
			size = g.sizeOf(elem),
			uns = not g.irSigned(elem)
		)
	)
	v

# a.xMask(b): bit i set when lane i of a compares true with lane i of b
fn irVecMaskOf(mut g Gen, mut lw IrLower, t TypeId, m str, a i64, b i64) i64:
	if not lw.ok: return -1
	row = g.irVecRow(t)
	l = g.irVecL(t)
	lanes = g.irVecLanes(t)
	cmp = -1
	negate = false
	if row == vecRowF64 or row == 0:
		# vcmppd / vcmpps by predicate: eq 0, lt 1, le 2; gt and ge as lt and le of the swapped pair
		pred = 0 if m == "eqMask" else 1 if m == "ltMask" or m == "gtMask" else 2
		swapped = m == "gtMask" or m == "geMask"
		code = irVecCode(1, 1 if row == vecRowF64 else 0, 0, l, 0xC2, pred)
		cmp = lw.irVecOpOf(code, b, a) if swapped else lw.irVecOpOf(code, a, b)
	else:
		eq = irVecTableCode(vecOp(row, "eq"), l, -1)
		gt = irVecTableCode(vecOp(row, "gt"), l, -1)
		if m == "eqMask":
			cmp = lw.irVecOpOf(eq, a, b)
		elif m == "gtMask":
			cmp = lw.irVecOpOf(gt, a, b)
		elif m == "ltMask":
			cmp = lw.irVecOpOf(gt, b, a)
		elif m == "leMask":
			cmp = lw.irVecOpOf(gt, a, b)   # not a > b
			negate = true
		else:
			cmp = lw.irVecOpOf(gt, b, a)   # not b > a
			negate = true
	bits = lw.f.irVreg(irInt)
	kind = 1 if row == vecRowF64 or row == 2 else 0 if row == 0 or row == 1 else 2
	irPut(
		lw,
		IrInst(op = irVecMask, dst = bits, a = cmp, imm = kind, size = 32 if l == 1 else 16)
	)
	if not negate: return bits
	lw.irDef(irInt, IrInst(op = irXor, a = bits, b = lw.irConstOf(irInt, (1 << lanes) - 1)))

# min or max lane by lane: the table's instruction, or for i64 (none in AVX2) a comparison and a blend
fn irVecMinMax(mut g Gen, mut lw IrLower, t TypeId, min bool, a i64, b i64) i64:
	if not lw.ok: return -1
	row = g.irVecRow(t)
	if row == 2:
		gt = lw.irVecOpOf(irVecTableCode(vecOp(row, "gt"), 1, -1), a, b)
		return lw.irVecBlend(1, a, b, gt) if min else lw.irVecBlend(1, b, a, gt)
	ins = vecOp(row, "min" if min else "max")
	if ins.isEmpty:
		lw.irFail("min or max of {typeStr(tys, t)}")
		return -1
	lw.irVecOpOf(irVecTableCode(ins, g.irVecL(t), -1), a, b)

# a vector from its lanes: from the data when every lane is a literal of a whole word or an
# integer, else lane by lane through a frame slot
fn irVecLiteral(mut g Gen, mut lw IrLower, e NodeId):
	t = g.ty(e)
	args = nodes[e].kidsFrom(kidIds, 1).copy()
	elem = g.irVecElem(t)
	size = g.sizeOf(elem)
	isF = g.tyK(elem) == tFloat
	v = lw.f.irVreg(irVec)
	if not (isF and size == 4) and args.all(nodes[it].kind == nInt or nodes[it].kind == nFloat):
		bytesAlign(g.a.data, 32)
		off = g.a.data.len
		for a in args:
			bits = g.floatLitBits(a) if isF else g.intLitValue(a)
			for b in 0..size:
				g.a.data.push((bits >> (8 * b)) & 255)
		at = lw.irDef(irInt, IrInst(op = irDataAddr, imm = off))
		lw.irPut(IrInst(op = irLoad, dst = v, a = at, size = 32))
		return [v]
	slot = lw.irNewSlot(32)
	for i, arg in args:
		x = g.irExpr(lw, arg)
		if not lw.ok: return []
		lw.irPut(IrInst(op = irStore, a = slot, c = x, imm = size * i, size))
	lw.irPut(IrInst(op = irLoad, dst = v, a = slot, size = 32))
	[v]
