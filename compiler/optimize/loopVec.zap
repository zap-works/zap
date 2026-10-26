# Plain loops vectorized (spec 14.3): a `for v in lo..hi` whose body is element-wise arithmetic on
# lists of one number type (f64, f32, i64, u64, i32, u32, u8), at indexes `inv + v`, runs 32
# bytes of lanes a step in AVX2, the rest one by one in the loop as written. Every element the
# vector steps touch is checked before them, at the first and the last index each list is reached
# at. Two lists of different names never overlap (a list written in the loop is lent `mut`, so no
# other name reaches it), so the only overlap to rule out is a list read at another index than
# the one it is written at, which keeps the loop scalar. A signed sum or difference checks every
# lane for an overflow, the scalar code's check (the same elements overflow). A sum `s += x` keeps
# lane sums combined into `s` at the end: of floats only under `use fusedMultiplyAdd` (the order
# of the additions changes), of unsigned integers always (they wrap: any order gives the same),
# and `&`, `|`, `^` always; a signed sum stays scalar (a lane's partial sum may overflow where no
# sum of the scalar order does). An f32 multiply-add stays scalar: its lanes would round once in
# single precision where the scalar code rounds the f64 result.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# what a loop's vector steps read and write
type LanePlan:
	elem TypeId   # the lists' element
	lanes i64
	row i64   # its row of vecGen.zap's table
	size i64   # its bytes
	float bool
	signed bool
	accesses NodeId[] = []   # the elements read or written, L[inv + v]
	invariants NodeId[] = []   # the floats over names the body never changes: one splat each
	temps str[] = []   # the names the body binds, a vector each
	sums str[] = []   # the outer numbers the body adds to (or ands, ors, xors)
	sumOps i64[] = []   # each one's operator: binAdd (for - too), binBand, binBor, binBxor
	written str[] = []   # the lists the body assigns elements of

# the vregs of the vector steps being emitted
type LaneState:
	plan LanePlan
	counter i64
	bases i64[] = []   # per access: the address its element at the counter's 0 would have
	invVals i64[] = []   # per invariant: its splat
	names str[] = []   # temps and sums: their vectors
	vals i64[] = []
	negZero i64 = -1   # -0.0 in every lane: a negation flips the sign bits

fn laneSize(plan LanePlan):
	plan.size

# the plan's lanes of the number type t, or none when the steps take no list of it
fn laneShape(mut g Gen, t TypeId) LanePlan?:
	k = g.tyK(t)
	if isDefined(tys, t) or k != tFloat and k != tInt or tys[t].ranged: return none
	size = g.sizeOf(t)
	float = k == tFloat
	signed = k == tInt and tys[t].isSigned
	row = vecRowF64 if float and size == 8
		else 0 if float and size == 4
		else 1 if size == 4
		else 2 if size == 8
		else vecRowU8 if size == 1 and not signed
		else -1
	if row < 0: return none
	LanePlan(elem = t, lanes = 32 / size, row, size, float, signed)

# the splat kind of the plan's lanes
fn laneKind(plan LanePlan):
	irLaneF64 if plan.row == vecRowF64
		else irLaneF32 if plan.row == 0
		else irLaneI32 if plan.row == 1
		else irLaneI64 if plan.row == 2
		else irLaneU8

# whether the lanes take operator op lane by lane: + - * / of floats; + - & | ^ of integers, * of
# u32 (a signed product would need its overflow told lane by lane)
fn laneOp(plan LanePlan, op i64):
	if plan.float: return op in [binAdd, binSub, binMul, binDiv]
	op in [binAdd, binSub, binBand, binBor, binBxor] or
		op == binMul and plan.row == 1 and not plan.signed

# The loop s from lo to hi vectorized when its body allows it: the vector steps run while four
# or eight elements remain, and the scalar loop goes on from the vreg returned (lo when the body
# is not element-wise)
fn irVectorLoop(mut g Gen, mut lw IrLower, s NodeId, lo i64, hi i64):
	plan = g.lanePlan(lw, s) ?? return lo
	w = plan.lanes
	size = plan.laneSize()
	v = nodes[s].text.copy()
	start = lw.irDef(irInt, IrInst(op = irCopy, a = lo))
	span = lw.irDef(irInt, IrInst(op = irSub, a = hi, b = lo))
	someB = lw.f.irBlock()
	runB = lw.f.irBlock()
	scalarB = lw.f.irBlock()
	lw.irBranchIf(lo, irLt, hi, someB, scalarB)
	lw.f.irEnter(someB)
	lw.irBranchIf(span, irGe, lw.irConstOf(irInt, w), runB, scalarB, uns = true)
	lw.f.irEnter(runB)
	whole = lw.irDef(irInt, IrInst(op = irAnd, a = span, b = lw.irConstOf(irInt, -w)))
	end = lw.irDef(irInt, IrInst(op = irAdd, a = lo, b = whole))
	last = lw.irDef(irInt, IrInst(op = irSub, a = end, b = lw.irConstOf(irInt, 1)))
	st = LaneState(plan = plan.copy(), counter = lw.f.irVreg(irInt))
	for e in plan.invariants:
		st.invVals.push(g.irLaneSplat(lw, plan, g.irExpr(lw, e)))
	for e in plan.accesses:
		st.bases.push(g.irLaneBase(lw, e, v, lo, last, size))
	for i, name in plan.sums:
		st.names.push(name.copy())
		zero = lw.irConstOf(irVec, 0)
		st.vals.push(
			lw.irVecOpOf(irVecTableCode(vecOp(1, "eq"), 1, -1), zero, zero) if plan.sumOps[i] ==
				binBand
			else zero
		)   # each lane starts at the operator's identity: all ones for &, else zero
	if not lw.ok: return lo
	lw.irPut(IrInst(op = irCopy, dst = st.counter, a = lo))
	l = lw.f.irShell()
	lw.f.irJumpTo(l.body)
	lw.f.irEnterBody(l)
	for stmt in nodes[nodes[s].sub()[0]].kids(kidIds).copy():
		g.irLaneStatement(lw, st, stmt)
	lw.f.irJoin(l.cont)
	lw.irPut(IrInst(op = irAdd, dst = st.counter, a = st.counter, b = lw.irConstOf(irInt, w)))
	lw.irBranchIf(st.counter, irLt, end, l.body, l.end)
	lw.irLoopDone(l)
	for i, name in plan.sums:
		g.irLaneSumInto(lw, st, name, plan.sumOps[i])
	lw.irPut(IrInst(op = irCopy, dst = start, a = end))
	lw.f.irJoin(scalarB)
	start

# the scalar x of the plan's element in every lane
fn irLaneSplat(mut g Gen, mut lw IrLower, plan LanePlan, x i64):
	if not lw.ok: return -1
	v = lw.f.irVreg(irVec)
	irPut(
		lw,
		IrInst(
			op = irVecSplat,
			dst = v,
			a = x,
			imm = plan.laneKind(),
			size = 32
		)
	)
	v

# the element e = L[inv + v] checked at the vector steps' first and last index, and the address
# its element at index v would have when v is 0 (the steps read it at that plus v * size)
fn irLaneBase(mut g Gen, mut lw IrLower, e NodeId, v str, lo i64, last i64, size i64) i64:
	list = g.irListAddr(lw, nodes[e].kids(kidIds)[0])
	if not lw.ok: return -1
	n = lw.irHeader(list, 8)
	first = -1
	for at in [lo, last]:
		mark = lw.names.len
		lw.irDeclare(v, [at])
		i = g.irExpr(lw, nodes[e].kids(kidIds)[1])
		g.irScopeEnd(lw, mark)
		if not lw.ok: return -1
		lw.irPut(IrInst(op = irFailIf, a = i, b = n, cond = irGe, uns = true, imm = g.failBounds))
		if first < 0:
			first = i
	offset = lw.irDef(irInt, IrInst(op = irSub, a = first, b = lo))
	lw.irDef(irInt, IrInst(op = irAdd, a = lw.irHeader(list, 0), b = lw.irScaled(offset, size)))

# one statement of the body, its values a vector each
fn irLaneStatement(mut g Gen, mut lw IrLower, mut st LaneState, stmt NodeId):
	value = g.irLaneValue(lw, st, nodes[stmt].kids(kidIds)[nodes[stmt].kids(kidIds).len - 1])
	if nodes[stmt].kind == nAssign:
		at = st.plan.accesses.indexOf(nodes[stmt].kids(kidIds)[0]) ?? -1
		irPut(
			lw,
			IrInst(
				op = irStore,
				a = st.bases[at],
				b = st.counter,
				scale = st.plan.laneSize(),
				c = value,
				size = 32
			)
		)
		return
	name = nodes[stmt].text
	if st.names.indexOf(name) is i:
		lw.irPut(IrInst(op = irCopy, dst = st.vals[i], a = value))
	else:
		mine = lw.irDef(irVec, IrInst(op = irCopy, a = value))
		st.names.push(name.copy())
		st.vals.push(mine)

# an expression of the body as a vector (the plan admitted it)
fn irLaneValue(mut g Gen, mut lw IrLower, mut st LaneState, e NodeId) i64:
	if st.plan.invariants.indexOf(e) is i: return st.invVals[i]
	k = nodes[e].kind
	f64s = st.plan.row == vecRowF64
	if k == nDeref: return g.irLaneValue(lw, st, nodes[e].kids(kidIds)[0])
	if k == nIdent:
		i = st.names.indexOf(nodes[e].text) ?? -1
		return st.vals[i]
	if k == nIndex:
		at = st.plan.accesses.indexOf(e) ?? -1
		v = lw.f.irVreg(irVec)
		irPut(
			lw,
			IrInst(
				op = irLoad,
				dst = v,
				a = st.bases[at],
				b = st.counter,
				scale = st.plan.laneSize(),
				size = 32
			)
		)
		return v
	if k == nUnary:
		x = g.irLaneValue(lw, st, nodes[e].kids(kidIds)[0])
		if st.negZero < 0:
			st.negZero = g.irLaneSplat(lw, st.plan, lw.irConstOf(irFloat, 1 << 63))
		return lw.irVecOpOf(irVecTableCode(vecOp(st.plan.row, "xor"), 1, -1), x, st.negZero)
	if k == nBinary:
		a = g.irLaneValue(lw, st, nodes[e].kids(kidIds)[0])
		b = g.irLaneValue(lw, st, nodes[e].kids(kidIds)[1])
		op = nodes[e].ival
		v = lw.irVecOpOf(irVecTableCode(vecOp(st.plan.row, vecOpName(op)), 1, -1), a, b)
		if st.plan.signed and (op == binAdd or op == binSub):
			g.irLaneOverflow(lw, st.plan, op, a, b, v)
		return v
	# a call: x.sqrt() or x.mulAdd(y, z) of f64s
	callee = nodes[e].kids(kidIds)[0]
	x = g.irLaneValue(lw, st, nodes[callee].kids(kidIds)[0])
	if nodes[callee].text == "sqrt":
		return lw.irVecOpOf(irVecCode(1, 1 if f64s else 0, 0, 1, 0x51, -1), x, -1)   # vsqrtpd / ps
	y = g.irLaneValue(lw, st, nodes[e].kids(kidIds)[1])
	z = g.irLaneValue(lw, st, nodes[e].kids(kidIds)[2])
	v = lw.f.irVreg(irVec)
	irPut(
		lw,
		IrInst(
			op = irVecOp,
			dst = v,
			a = x,
			b = y,
			c = z,
			cond = 1,
			imm = irVecCode(2, 1, 1, 1, 0xB8, -1)   # vfmadd231pd: z + x * y
		)
	)
	v

# a signed lane sum or difference v = a op b: the program stops when a lane overflowed (its sign
# differs from both operands' of a sum, from the minuend's when the subtrahend's differs too)
fn irLaneOverflow(mut g Gen, mut lw IrLower, plan LanePlan, op i64, a i64, b i64, v i64):
	xor = irVecTableCode(vecOp(plan.row, "xor"), 1, -1)
	x1 = lw.irVecOpOf(xor, a, v)
	x2 = lw.irVecOpOf(xor, b, v) if op == binAdd else lw.irVecOpOf(xor, a, b)
	both = lw.irVecOpOf(irVecTableCode(vecOp(plan.row, "and"), 1, -1), x1, x2)
	bits = lw.f.irVreg(irInt)
	irPut(
		lw,
		IrInst(op = irVecMask, dst = bits, a = both, imm = 0 if plan.size == 4 else 1, size = 32)
	)
	irPut(
		lw,
		IrInst(
			op = irFailIf,
			a = bits,
			b = lw.irConstOf(irInt, 0),
			cond = irNe,
			imm = g.failOverflow
		)
	)

# the sum's lanes combined ((0 op 1) op (2 op 3) ...) and into the outer number, rounded or wrapped
# as its type is (a difference's lanes hold minus what they took: added)
fn irLaneSumInto(mut g Gen, mut lw IrLower, st LaneState, name str, op i64):
	i = st.names.indexOf(name) ?? -1
	slot = lw.irVecSlot(st.vals[i])
	plan = st.plan
	class = irFloat if plan.float else irInt
	scalar = irFAdd if plan.float
		else irAnd if op == binBand
		else irOr if op == binBor
		else irXor if op == binBxor
		else irAdd
	lanes = []
	for k in 0..plan.lanes:
		x = lw.f.irVreg(class)
		irPut(
			lw,
			IrInst(
				op = irLoad,
				dst = x,
				a = slot,
				imm = k * plan.size,
				size = plan.size,
				uns = not plan.signed
			)
		)
		lanes.push(x)
	outer = lw.irLookup(name) ?? return
	lanes.push(outer[0])   # the outer one last
	while lanes.len > 1:
		next = []
		for k in 0..lanes.len / 2:
			x = lw.irDef(class, IrInst(op = scalar, a = lanes[2 * k], b = lanes[2 * k + 1]))
			next.push(g.irLaneNumber(lw, plan, x))
		if lanes.len % 2 == 1:
			next.push(lanes[len - 1])
		lanes = next
	lw.irPut(IrInst(op = irCopy, dst = outer[0], a = lanes[0]))

# x as a value of the plan's element: an f32 rounded, an unsigned integer wrapped to its width
fn irLaneNumber(mut g Gen, mut lw IrLower, plan LanePlan, x i64) i64:
	if plan.float: return g.irRounded(lw, x, plan.elem)
	if plan.signed or plan.size == 8: return x
	lw.irDef(irInt, IrInst(op = irTrunc, a = x, imm = plan.size * 8, uns = true))

# ---------- what a body must be ----------

# the plan of loop s, or none when its body is not element-wise arithmetic the steps can run
fn lanePlan(mut g Gen, mut lw IrLower, s NodeId) LanePlan?:
	iter = nodes[s].kids(kidIds)[0]
	body = nodes[s].sub()[0]
	if nodes[iter].kind != nRange or nodes[iter].kids(kidIds).len != 2 or
		nodes[body].kind != nBlock or
		nodes[body].kids(kidIds).isEmpty:
		return none
	first = nodes[body].kids(kidIds)[0]
	elem = g.ty(nodes[first].kids(kidIds)[nodes[first].kids(kidIds).len - 1])
	plan = try g.laneShape(elem)
	v = nodes[s].text
	fused = nodes[s].hasFlag(flagFusedMath) or nodes[body].hasFlag(flagFusedMath)
	# the names the body binds are its own (a vector each) unless they name an outer float it adds to
	for stmt in nodes[body].kids(kidIds):
		k = nodes[stmt].kind
		if k == nLet:
			name = nodes[stmt].text
			if not lw.irInScope(name):
				if name not in plan.temps:
					plan.temps.push(name.copy())
			elif nodes[stmt].hasFlag(flagCompound) and name != v and name not in plan.sums and
				g.sumOperator(plan, fused, nodes[stmt].kids(kidIds)[0]) is op:
				plan.sums.push(name.copy())
				plan.sumOps.push(op)
			else:
				return none
		elif k != nAssign:
			return none
		if not isSameType(
			tys,
			g.ty(nodes[stmt].kids(kidIds)[nodes[stmt].kids(kidIds).len - 1]),
			elem
		):
			return none
	for stmt in nodes[body].kids(kidIds):
		value = nodes[stmt].kids(kidIds)[nodes[stmt].kids(kidIds).len - 1]
		if nodes[stmt].kind == nAssign:
			target = nodes[stmt].kids(kidIds)[0]
			if not g.laneElement(lw, plan, s, target): return none
			plan.accesses.push(target)
			plan.written.push(g.laneListName(target))
		elif nodes[stmt].text in plan.sums:
			name = nodes[stmt].text
			op = plan.sumOps[plan.sums.indexOf(name) ?? 0]
			if not g.sumsInto(value, name, op) or
				nodes[body]
					.kids(kidIds)
					.any(it != stmt and mentions(nodes, kidIds, it, false, name)):
				return none
		if not g.laneExpr(lw, plan, s, value): return none
	if not nodes[s].hasFlag(flagJammed) and not g.laneNoOverlap(plan): return none
	plan

# whether e = L[inv + v] of a list named L of the plan's elements
fn laneElement(mut g Gen, mut lw IrLower, plan LanePlan, s NodeId, e NodeId):
	if nodes[e].kind != nIndex or nodes[e].hasFlag(flagComma): return false
	base = nodes[e].kids(kidIds)[0]
	list = nodes[base].kids(kidIds)[0] if nodes[base].kind == nDeref else base
	if nodes[list].kind != nIdent or not g.laneName(lw, nodes[list].text): return false
	lt = innerOf(tys, g.ty(list)) if g.tyK(g.ty(list)) == tRef else g.ty(list)
	g.tyK(lt) == tList and isSameType(tys, tys[lt].inner, plan.elem) and
		g.unitRise(lw, plan, s, nodes[e].kids(kidIds)[1])

# whether name is a local, or a module variable read by the program's own statements (where no
# parameter could lend one of them under another name)
fn laneName(mut g Gen, lw IrLower, name str):
	lw.irInScope(name) or lw.floor == 0 and g.irLowersEntry(lw) and g.globalOf(name) >= 0

# whether the index is v plus or minus integers the body never changes
fn unitRise(mut g Gen, mut lw IrLower, plan LanePlan, s NodeId, e0 NodeId) bool:
	e = g.c.unwidened(e0)
	k = nodes[e].kind
	if k == nIdent and nodes[e].text == nodes[s].text: return true
	if k != nBinary or g.tyK(g.ty(e)) != tInt: return false
	a = nodes[e].kids(kidIds)[0]
	b = nodes[e].kids(kidIds)[1]
	if nodes[e].ival == binAdd:
		return g.unitRise(lw, plan, s, a) and g.laneInvariant(lw, plan, s, b) or
			g.laneInvariant(lw, plan, s, a) and g.unitRise(lw, plan, s, b)
	nodes[e].ival == binSub and g.unitRise(lw, plan, s, a) and g.laneInvariant(lw, plan, s, b)

# whether e reads only literals and names the loop never changes (not its counter, nor what the
# body binds), through arithmetic and fields: a value the vector steps compute once
fn laneInvariant(mut g Gen, mut lw IrLower, plan LanePlan, s NodeId, e0 NodeId) bool:
	e = g.c.unwidened(e0)
	k = nodes[e].kind
	if k == nInt or k == nFloat: return true
	if k == nIdent:
		name = nodes[e].text
		if name == nodes[s].text or name in plan.temps or name in plan.sums: return false
		t = g.ty(e)
		if g.tyK(t) != tInt and g.tyK(t) != tFloat or isDefined(tys, t): return false
		return g.laneName(lw, name) or g.isConstName(name) != none
	if k == nDeref or k == nField: return g.laneInvariant(lw, plan, s, nodes[e].kids(kidIds)[0])
	if k == nUnary:
		return nodes[e].ival == unNeg and g.laneInvariant(lw, plan, s, nodes[e].kids(kidIds)[0])
	k == nBinary and (nodes[e].ival in [binAdd, binSub, binMul, binDiv]) and
		g.laneInvariant(lw, plan, s, nodes[e].kids(kidIds)[0]) and
		g.laneInvariant(lw, plan, s, nodes[e].kids(kidIds)[1])

# whether the body's value e runs lane by lane: the plan's elements, its names, invariant floats
# (each noted), + - * /, negation, sqrt and (f64) a multiply-add
fn laneExpr(mut g Gen, mut lw IrLower, mut plan LanePlan, s NodeId, e NodeId) bool:
	if not isSameType(tys, g.ty(e), plan.elem): return false
	if g.laneInvariant(lw, plan, s, e):
		plan.invariants.push(e)
		return true
	k = nodes[e].kind
	if k == nDeref: return g.laneExpr(lw, plan, s, nodes[e].kids(kidIds)[0])
	if k == nIdent: return nodes[e].text in plan.temps or nodes[e].text in plan.sums
	if k == nIndex:
		if not g.laneElement(lw, plan, s, e): return false
		plan.accesses.push(e)
		return true
	if k == nUnary:
		return plan.float and nodes[e].ival == unNeg and
			g.laneExpr(lw, plan, s, nodes[e].kids(kidIds)[0])
	if k == nBinary:
		return plan.laneOp(nodes[e].ival) and not nodes[e].hasFlag(flagWrap) and
			g.laneExpr(lw, plan, s, nodes[e].kids(kidIds)[0]) and
			g.laneExpr(lw, plan, s, nodes[e].kids(kidIds)[1])
	if k != nCall or not plan.float: return false
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind != nField: return false
	m = nodes[callee].text
	args = nodes[e].kids(kidIds).len - 1
	if m == "sqrt" and args == 0: return g.laneExpr(lw, plan, s, nodes[callee].kids(kidIds)[0])
	m == "mulAdd" and args == 2 and plan.row == vecRowF64 and
		g.laneExpr(lw, plan, s, nodes[callee].kids(kidIds)[0]) and
		g.laneExpr(lw, plan, s, nodes[e].kids(kidIds)[1]) and
		g.laneExpr(lw, plan, s, nodes[e].kids(kidIds)[2])

# the operator a compound assignment's value (`s = s op x`) keeps lane sums of, when its order
# may change: + of floats under fused math and of unsigned integers, & | ^ of integers; or none
fn sumOperator(mut g Gen, plan LanePlan, fused bool, value NodeId) i64?:
	if nodes[value].kind == nCall: return binAdd if plan.float and fused else none   # a fused one
	if nodes[value].kind != nBinary: return none
	op i64 = nodes[value].ival
	if (op == binAdd or op == binSub) and
		(plan.float and fused or not plan.float and not plan.signed):
		return binAdd
	if not plan.float and (op in [binBand, binBor, binBxor]): return op
	none

# whether e combines the sum named once with op: `name op x`, `x op name` (commutative), `name - x`
# of a sum, or x.mulAdd(y, name), x's and y's own not naming it
fn sumsInto(mut g Gen, e NodeId, name str, op i64) bool:
	k = nodes[e].kind
	if k == nDeref: return g.sumsInto(nodes[e].kids(kidIds)[0], name, op)
	if k == nIdent: return nodes[e].text == name
	if k == nBinary and (nodes[e].ival == op or op == binAdd and nodes[e].ival == binSub):
		a = nodes[e].kids(kidIds)[0]
		b = nodes[e].kids(kidIds)[1]
		if g.sumsInto(a, name, op) and not mentions(nodes, kidIds, b, false, name): return true
		return nodes[e].ival != binSub and g.sumsInto(b, name, op) and
			not mentions(nodes, kidIds, a, false, name)
	if k == nCall and op == binAdd and nodes[e].kids(kidIds).len == 3 and
		nodes[nodes[e].kids(kidIds)[0]].kind == nField and
		nodes[nodes[e].kids(kidIds)[0]].text == "mulAdd":
		return g.sumsInto(nodes[e].kids(kidIds)[2], name, op) and
			not mentions(
				nodes,
				kidIds,
				nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0],
				false,
				name
			) and
			not mentions(nodes, kidIds, nodes[e].kids(kidIds)[1], false, name)
	false

# whether each list the body writes is read and written at one index only, so no step reads
# what another lane writes
fn laneNoOverlap(mut g Gen, plan LanePlan):
	for a in plan.accesses:
		name = g.laneListName(a)
		if name in plan.written and
			plan.accesses.any(g.laneListName(it) == name and
					not isSameTree(
						nodes,
						kidIds,
						nodes[it].kids(kidIds)[1],
						nodes[a].kids(kidIds)[1]
			)):
			return false
	true

fn laneListName(g Gen, e NodeId):
	base = nodes[e].kids(kidIds)[0]
	(
		nodes[nodes[base].kids(kidIds)[0]].text if nodes[base].kind == nDeref else nodes[base].text
	).copy()
