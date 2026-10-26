# Two turns of a loop nest at once (unroll and jam, spec 14.3): a `for i in lo..hi` whose body is
# lets and one loop, whose body is lets and one loop..., the innermost `for j in 0..s` assigning
# elements L[i * s + j] of lists, everything else pure arithmetic and elements read, runs i and
# i + 1 together: each loop of the nest once for both, the innermost one's statements for i then
# for i + 1, so what the inner loops read (a row of another list) is read once for two rows of L.
# Two turns write two rows of L that do not meet (j stays below s), and nothing else is written,
# so only the order of independent stores changes: every element's value is computed as written.
# A guard before the loop bounds every index and every integer the nest computes over the
# counters' ranges; when one could leave its list or overflow, the loop runs as written (it then
# stops where it would), else the two turns at once run without a check, the last odd turn as
# written.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# the jammed loop of s's body and the next i's name in it
type JamPlan:
	body NodeId
	next str

# where the loop s (for i in lo..hi, by one) goes on after its turns two at a time: lo when the
# guard finds a check that could fail; none when its body is not such a nest
fn irJammed(mut g Gen, mut lw IrLower, s NodeId, lo i64, hi i64) i64?:
	plan = try g.jamPlan(lw, s)
	rest = lw.f.irVreg(irInt)
	plain = lw.f.irBlock()
	join = lw.f.irBlock()
	env {str: (i64, i64)} = {}
	g.jamSmall(lw, lo, 61, plain)
	g.jamSmall(lw, hi, 61, plain)
	last = lw.irDef(irInt, IrInst(op = irSub, a = hi, b = lw.irConstOf(irInt, 1)))
	env[nodes[s].text.copy()] = (lo, last)
	g.jamGuardBlock(lw, env, nodes[s].sub()[0], plain)
	counter = lw.irDef(irInt, IrInst(op = irCopy, a = lo))
	irCountedLoop(
		g,
		lw,
		s,
		counter,
		last,
		lw.irConstOf(irInt, 2),
		false,
		[counter],
		-1,
		none,
		[],
		body = plan.body,
		next = plan.next
	)
	lw.irPut(IrInst(op = irCopy, dst = rest, a = counter))
	lw.f.irJumpTo(join)
	lw.f.irEnter(plain)
	lw.irPut(IrInst(op = irCopy, dst = rest, a = lo))
	lw.f.irJumpTo(join)
	lw.f.irEnter(join)
	rest

# ---------- the nest ----------

# s's plan, or none when its body is not a nest the two turns may run at once
fn jamPlan(mut g Gen, lw IrLower, s NodeId) JamPlan?:
	i = nodes[s].text
	body = nodes[s].sub()[0]
	bound = [i.copy()]
	inner = try g.jamLoopOf(body, bound)
	if not g.jamRows(body, inner, i, bound): return none
	next = "{i}$next"
	renames {str: str} = {}
	renames[i.copy()] = next.copy()
	for name in bound[1..]:
		if not g.jamIsCounter(body, name):
			renames[name.copy()] = "{name}$next"
	mine = cloneTree(nodes, kidIds, body)
	other = cloneTree(nodes, kidIds, body)
	g.jamUnchecked(mine)
	g.jamUnchecked(other)
	g.jamRename(other, renames)
	JamPlan(body = g.jamJoin(mine, other), next)

# the innermost loop of the nest block starts: lets that compute and stop at nothing, then one
# loop over a range its counters do not change; the names they bind added to bound
fn jamLoopOf(mut g Gen, block NodeId, mut bound str[]) NodeId?:
	if nodes[block].kind != nBlock or nodes[block].kids(kidIds).isEmpty: return none
	last = nodes[block].kids(kidIds)[nodes[block].kids(kidIds).len - 1]
	for st in nodes[block].kids(kidIds)[..nodes[block].kids(kidIds).len - 1]:
		if not g.jamLet(st, bound): return none
	if nodes[last].kind != nFor or not g.jamRange(nodes[last].kids(kidIds)[0], bound): return none
	bound.push(nodes[last].text.copy())
	body = nodes[last].sub()[0]
	if nodes[body].kind != nBlock or nodes[body].kids(kidIds).isEmpty: return none
	if nodes[nodes[body].kids(kidIds)[nodes[body].kids(kidIds).len - 1]].kind == nFor:
		return g.jamLoopOf(body, bound)
	for st in nodes[body].kids(kidIds):
		if nodes[st].kind == nAssign:
			target = nodes[st].kids(kidIds)[0]
			if nodes[st].kids(kidIds).len != 2 or nodes[target].kind != nIndex or
				g.jamList(target) == "" or not g.jamInt(nodes[target].kids(kidIds)[1]) or
				not g.jamValue(nodes[st].kids(kidIds)[1]):
				return none
		elif not g.jamLet(st, bound):
			return none
	last

# a let of a pure value (its name added to bound)
fn jamLet(mut g Gen, st NodeId, mut bound str[]):
	if nodes[st].kind != nLet or nodes[st].hasFlag(flagMut) or nodes[st].hasFlag(flagCompound) or
		nodes[st].kids(kidIds).len != 1 or not g.jamValue(nodes[st].kids(kidIds)[0]):
		return false
	bound.push(nodes[st].text.copy())
	true

# a range by one or a positive literal step whose ends name nothing the nest binds
fn jamRange(mut g Gen, r NodeId, bound str[]):
	if nodes[r].kind != nRange or nodes[r].kids(kidIds).len < 2 or nodes[r].kids(kidIds).len > 3:
		return false
	if nodes[r].kids(kidIds).len == 3:
		step = nodes[r].kids(kidIds)[2]
		if nodes[step].kind != nInt or g.intLitValue(step) <= 0: return false
	(0..2).all(
		g.jamInt(nodes[r].kids(kidIds)[it]) and
			not mentionsAny(nodes, kidIds, nodes[r].kids(kidIds)[it], bound)
	)

# whether name is one of the nest's loop counters (shared by the two turns, not renamed)
fn jamIsCounter(g Gen, e NodeId, name str) bool:
	nodes[e].kind == nFor and nodes[e].text == name or
		nodes[e].kids(kidIds).any(g.jamIsCounter(it, name)) or
		nodes[e].sub().any(g.jamIsCounter(it, name))

# the list an element e = L[x] is of ("" when L is not a list named directly)
fn jamList(mut g Gen, e NodeId):
	if nodes[e].kind != nIndex or nodes[e].hasFlag(flagComma): return ""
	base = nodes[e].kids(kidIds)[0]
	list = nodes[base].kids(kidIds)[0] if nodes[base].kind == nDeref else base
	if nodes[list].kind != nIdent: return ""
	lt = g.c.derefType(g.ty(list))
	nodes[list].text if g.tyK(lt) == tList else ""

# whether e is a signed 64-bit integer computed by + - * of names, literals, min and max
fn jamInt(mut g Gen, e0 NodeId) bool:
	e = g.c.unwidened(e0)
	t = g.c.derefType(g.ty(e))
	if g.tyK(t) != tInt or not tys[t].isSigned or tys[t].bits != 64: return false
	k = nodes[e].kind
	if k == nInt or k == nIdent: return true
	if k == nBinary:
		return (nodes[e].ival in [binAdd, binSub, binMul]) and
			nodes[e].kids(kidIds).all(g.jamInt(it))
	k == nCall and g.jamMinMax(e) and g.jamInt(nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0]) and
		g.jamInt(nodes[e].kids(kidIds)[1])

# whether e is x.min(y) or x.max(y)
fn jamMinMax(g Gen, e NodeId):
	callee = nodes[e].kids(kidIds)[0]
	nodes[e].kids(kidIds).len == 2 and nodes[callee].kind == nField and
		nodes[callee].kids(kidIds).len == 1 and
		(nodes[callee].text == "min" or nodes[callee].text == "max")

# whether e computes without a call, a store or a stop the guard cannot rule out: numbers, names
# of numbers, elements of lists at integer indexes, + - * / of floats, comparisons, a choice
fn jamValue(mut g Gen, e0 NodeId) bool:
	e = g.c.unwidened(e0)
	k = nodes[e].kind
	t = g.c.derefType(g.ty(e))
	if g.tyK(t) == tInt: return g.jamInt(e)
	if k == nFloat or k == nBool: return true
	if k == nIdent: return g.tyK(t) == tFloat or g.tyK(t) == tBool
	if k == nDeref: return g.jamValue(nodes[e].kids(kidIds)[0])
	if k == nIndex: return g.jamList(e) != "" and g.jamInt(nodes[e].kids(kidIds)[1])
	if k == nUnary:
		return (nodes[e].ival == unNeg and g.tyK(t) == tFloat or nodes[e].ival == unNot) and
			g.jamValue(nodes[e].kids(kidIds)[0])
	if k == nBinary:
		op = nodes[e].ival
		float = g.tyK(g.c.derefType(g.ty(nodes[e].kids(kidIds)[0]))) == tFloat
		ok = isCompareOp(op) or op == binAnd or op == binOr or
			float and (op in [binAdd, binSub, binMul, binDiv])
		return ok and nodes[e].kids(kidIds).all(g.jamValue(it))
	if k == nMatch: return g.jamChoice(e)
	if k != nCall or g.tyK(t) != tFloat: return false
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind != nField or nodes[callee].kids(kidIds).len != 1: return false
	m = nodes[callee].text
	args = nodes[e].kids(kidIds).len - 1
	ok = m == "sqrt" and args == 0 or m == "mulAdd" and args == 2 or
		(m == "min" or m == "max") and args == 1
	ok and g.jamValue(nodes[callee].kids(kidIds)[0]) and
		nodes[e].kidsFrom(kidIds, 1).all(g.jamValue(it))

# whether e is `a if c else b` of pure parts
fn jamChoice(mut g Gen, e NodeId):
	if nodes[e].kids(kidIds).len != 3: return false
	yes = nodes[e].kids(kidIds)[1]
	no = nodes[e].kids(kidIds)[2]
	g.jamValue(nodes[e].kids(kidIds)[0]) and nodes[yes].kids(kidIds).len == 2 and
		nodes[no].kids(kidIds).len == 2 and
		nodes[nodes[yes].kids(kidIds)[0]].ival == patLit and
		nodes[nodes[no].kids(kidIds)[0]].ival == patWildcard and
		g.jamValue(nodes[yes].kids(kidIds)[1]) and g.jamValue(nodes[no].kids(kidIds)[1])

# whether every list the innermost loop writes is reached, in the whole nest, at one index only:
# i * s + j (in any order), j the innermost counter over 0..s, s a name the nest does not bind
fn jamRows(mut g Gen, body NodeId, inner NodeId, i str, bound str[]):
	r = nodes[inner].kids(kidIds)[0]
	if nodes[r].kids(kidIds).len != 2 or nodes[nodes[r].kids(kidIds)[0]].kind != nInt or
		g.intLitValue(nodes[r].kids(kidIds)[0]) != 0 or
		nodes[nodes[r].kids(kidIds)[1]].kind != nIdent:
		return false
	s = nodes[nodes[r].kids(kidIds)[1]].text
	j = nodes[inner].text
	for st in nodes[nodes[inner].sub()[0]].kids(kidIds):
		if nodes[st].kind != nAssign: continue
		target = nodes[st].kids(kidIds)[0]
		list = g.jamList(target)
		if list in bound or not g.jamRow(nodes[target].kids(kidIds)[1], i, s, j): return false
		if g.jamStray(body, list, nodes[target].kids(kidIds)[1]) != 0: return false
	true

# whether e is i * s + j in any order
fn jamRow(mut g Gen, e0 NodeId, i str, s str, j str):
	e = g.c.unwidened(e0)
	if nodes[e].kind != nBinary or nodes[e].ival != binAdd: return false
	a = g.c.unwidened(nodes[e].kids(kidIds)[0])
	b = g.c.unwidened(nodes[e].kids(kidIds)[1])
	g.jamNamed(b, j) and g.jamProduct(a, i, s) or g.jamNamed(a, j) and g.jamProduct(b, i, s)

fn jamProduct(mut g Gen, e NodeId, i str, s str):
	if nodes[e].kind != nBinary or nodes[e].ival != binMul: return false
	a = g.c.unwidened(nodes[e].kids(kidIds)[0])
	b = g.c.unwidened(nodes[e].kids(kidIds)[1])
	g.jamNamed(a, i) and g.jamNamed(b, s) or g.jamNamed(a, s) and g.jamNamed(b, i)

fn jamNamed(g Gen, e NodeId, name str):
	nodes[e].kind == nIdent and nodes[e].text == name

# how many times e names list other than as its element at index
fn jamStray(mut g Gen, e NodeId, list str, index NodeId) i64:
	n = 1 if nodes[e].kind == nIdent and nodes[e].text == list else 0
	if nodes[e].kind == nIndex and g.jamList(e) == list and
		isSameTree(nodes, kidIds, nodes[e].kids(kidIds)[1], index):
		n -= 1   # its base names the list once
	for k in nodes[e].kids(kidIds):
		n += g.jamStray(k, list, index)
	for k in nodes[e].sub():
		n += g.jamStray(k, list, index)
	n

# ---------- the jammed copy ----------

# the copy's elements and integer arithmetic marked inside (the guard bounds them)
fn jamUnchecked(mut g Gen, e NodeId):
	k = nodes[e].kind
	if k == nIndex or k == nBinary and (nodes[e].ival in [binAdd, binSub, binMul]):
		nodes[e].flags |= flagInBounds
	for i in 0..nodes[e].kids(kidIds).len:
		g.jamUnchecked(nodes[e].kids(kidIds)[i])
	for i in 0..nodes[e].sub().len:
		g.jamUnchecked(nodes[e].sub()[i])

# the copy's names renamed: the next i's, and the lets' own
fn jamRename(mut g Gen, e NodeId, renames {str: str}):
	k = nodes[e].kind
	if (k == nIdent or k == nLet) and renames.get(nodes[e].text) is to:
		nodes[e].text = to.copy()
	for i in 0..nodes[e].kids(kidIds).len:
		g.jamRename(nodes[e].kids(kidIds)[i], renames)
	for i in 0..nodes[e].sub().len:
		g.jamRename(nodes[e].sub()[i], renames)

# blocks a and b (copies of one nest) as one: a's lets, b's lets, then their loop once with its
# bodies joined; the innermost a's statements, then b's (that loop marked flagJammed)
fn jamJoin(mut g Gen, a NodeId, b NodeId) NodeId:
	ka = nodes[a].kids(kidIds).copy()
	kb = nodes[b].kids(kidIds).copy()
	last = ka[len - 1]
	kids = []
	if nodes[last].kind == nFor:
		kids.extend(ka[..len - 1])
		kids.extend(kb[..len - 1])
		inner = g.jamJoin(nodes[last].sub()[0], nodes[kb[len - 1]].sub()[0])
		joined = nodes[last].copy()
		joined.nodePart().sub = [inner]
		innermost = nodes[inner].kids(kidIds).all(nodes[it].kind != nFor)
		if innermost:
			joined.flags |= flagJammed
		nodes.push(joined)
		kids.push(NodeId(nodes.len - 1))
	else:
		kids.extend(ka)
		kids.extend(kb)
	block = nodes[a].copy()
	block.setKids(kidIds, kids)
	nodes.push(block)
	NodeId(nodes.len - 1)

# ---------- the guard ----------

# the nest's block bounded: each loop's counter between its ends, each integer let's value, each
# element inside its list and each integer computed inside 2^62; fail where one may not be
fn jamGuardBlock(mut g Gen, mut lw IrLower, mut env {str: (i64, i64)}, block NodeId, fail i64):
	for st in nodes[block].kids(kidIds).copy():
		k = nodes[st].kind
		if k == nLet:
			value = nodes[st].kids(kidIds)[0]
			if g.tyK(g.c.derefType(g.ty(value))) == tInt:
				env[nodes[st].text.copy()] = g.jamSpan(lw, env, value, fail)
			else:
				g.jamGuardValue(lw, env, value, fail)
		elif k == nFor:
			r = nodes[st].kids(kidIds)[0]
			from, _ = g.jamSpan(lw, env, nodes[r].kids(kidIds)[0], fail)
			_, to = g.jamSpan(lw, env, nodes[r].kids(kidIds)[1], fail)
			g.jamSmall(lw, to, 61, fail)
			last = lw.irDef(irInt, IrInst(op = irSub, a = to, b = lw.irConstOf(irInt, 1)))
			env[nodes[st].text.copy()] = (from, last)
			g.jamGuardBlock(lw, env, nodes[st].sub()[0], fail)
		else:
			g.jamGuardValue(lw, env, nodes[st].kids(kidIds)[0], fail)
			g.jamGuardValue(lw, env, nodes[st].kids(kidIds)[1], fail)

# the elements and the integers under e bounded
fn jamGuardValue(mut g Gen, mut lw IrLower, env {str: (i64, i64)}, e0 NodeId, fail i64):
	e = g.c.unwidened(e0)
	if g.tyK(g.c.derefType(g.ty(e))) == tInt:
		g.jamSpan(lw, env, e, fail)
		return
	if nodes[e].kind == nIndex:
		low, high = g.jamSpan(lw, env, nodes[e].kids(kidIds)[1], fail)
		n = lw.irHeader(g.irListAddr(lw, nodes[e].kids(kidIds)[0]), 8)
		g.jamFailIf(lw, low, irLt, lw.irConstOf(irInt, 0), fail)
		g.jamFailIf(lw, high, irGe, n, fail)
		return
	for k in nodes[e].kids(kidIds).copy():
		g.jamGuardValue(lw, env, k, fail)

# the least and the greatest values the integer e takes while the counters stay in their spans
fn jamSpan(mut g Gen, mut lw IrLower, env {str: (i64, i64)}, e0 NodeId, fail i64) (i64, i64):
	e = g.c.unwidened(e0)
	k = nodes[e].kind
	if k == nIdent and env.get(nodes[e].text) is span: return span
	if k == nInt or k == nIdent:
		v = g.irExpr(lw, e)
		return (v, v)
	if k == nCall:
		alo, ahi = g.jamSpan(lw, env, nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0], fail)
		blo, bhi = g.jamSpan(lw, env, nodes[e].kids(kidIds)[1], fail)
		cond = irLt if nodes[nodes[e].kids(kidIds)[0]].text == "min" else irGt
		return (lw.jamPick(alo, cond, blo), lw.jamPick(ahi, cond, bhi))
	alo, ahi = g.jamSpan(lw, env, nodes[e].kids(kidIds)[0], fail)
	blo, bhi = g.jamSpan(lw, env, nodes[e].kids(kidIds)[1], fail)
	op = nodes[e].ival
	bits = 31 if op == binMul else 61
	for v in [alo, ahi, blo, bhi]:
		g.jamSmall(lw, v, bits, fail)
	if op == binAdd: return (lw.jamOp(irAdd, alo, blo), lw.jamOp(irAdd, ahi, bhi))
	if op == binSub: return (lw.jamOp(irSub, alo, bhi), lw.jamOp(irSub, ahi, blo))
	p = [lw.jamOp(irMul, alo, blo), lw.jamOp(irMul, alo, bhi), lw.jamOp(irMul, ahi, blo),
		lw.jamOp(irMul, ahi, bhi)]
	low = lw.jamPick(lw.jamPick(p[0], irLt, p[1]), irLt, lw.jamPick(p[2], irLt, p[3]))
	high = lw.jamPick(lw.jamPick(p[0], irGt, p[1]), irGt, lw.jamPick(p[2], irGt, p[3]))
	(low, high)

fn jamOp(mut lw IrLower, op i64, a i64, b i64) i64:
	lw.irDef(irInt, IrInst(op, a, b))

# a if a cond b, else b
fn jamPick(mut lw IrLower, a i64, cond i64, b i64) i64:
	lw.irDef(irInt, IrInst(op = irSelect, a, b, cond, c = a, d = b))

# to fail unless -2^bits < v < 2^bits
fn jamSmall(mut g Gen, mut lw IrLower, v i64, bits i64, fail i64):
	shifted = lw.irDef(irInt, IrInst(op = irAdd, a = v, b = lw.irConstOf(irInt, 1 << bits)))
	ok = lw.f.irBlock()
	lw.irBranchIf(shifted, irGe, lw.irConstOf(irInt, 2 << bits), fail, ok, uns = true)
	lw.f.irEnter(ok)

# to fail when a cond b
fn jamFailIf(mut g Gen, mut lw IrLower, a i64, cond i64, b i64, fail i64):
	ok = lw.f.irBlock()
	lw.irBranchIf(a, cond, b, fail, ok)
	lw.f.irEnter(ok)
