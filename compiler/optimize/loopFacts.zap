# Facts about a loop's body: what it assigns or disturbs, the indexes rising with its counter,
# whether a statement leaves early.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# whether e assigns, rebinds, lends mutably or hands to a call the local v
fn assignsName(g Gen, e NodeId, v str) bool:
	k = nodes[e].kind
	if k == nAssign:
		target = nodes[e].kids(kidIds)[0]
		if nodes[target].kind == nIdent and nodes[target].text == v: return true
	if k == nLet and nodes[e].text == v: return true
	if k == nUnary and (nodes[e].ival == unMutRef or nodes[e].ival == unRef):
		kid = nodes[e].kids(kidIds)[0]
		if nodes[kid].kind == nIdent and nodes[kid].text == v: return true
	if k == nCall:
		for i in 1..g.c.nodes[e].kids(g.c.kidIds).len:
			a = nodes[e].kids(kidIds)[i]
			if nodes[a].kind == nIdent and nodes[a].text == v:
				return true   # a bare argument may be a mut parameter
	nodes[e].kids(kidIds).any(g.assignsName(it, v)) or
		nodes[e].sub(kidIds).any(g.assignsName(it, v))

# whether L[i] (list variable lv, index variable iv) is proven within bounds
fn proven(g Gen, lv i64, iv i64):
	if lv < 0 or iv < 0: return false
	(0..g.provenL.len).any(g.provenL[it] == lv and g.provenV[it] == iv)

# the locals a loop body names that rising indexes may use: lists (and strs) indexed, integers
# as terms. Each backend says which names are its locals; the analysis is shared.
type LoopLocals:
	lists str[]
	ints str[]

# the name nodes under e
pub fn identsIn(g Gen, e NodeId, mut out NodeId[]):
	if nodes[e].kind == nIdent:
		out.push(e)
	for k in nodes[e].kids(kidIds):
		g.identsIn(k, out)
	for k in nodes[e].sub(kidIds):
		g.identsIn(k, out)

# the elements the statement surely reaches (outside conditions, choices, loops and lambdas) at
# an index rising with v or staying: of local lists the body does not resize, and of fixed arrays
# (a local, a field of one, or a layer of one at an index that stays)
fn risingIndexes(mut g Gen, e NodeId, v str, body NodeId, names LoopLocals, mut found NodeId[]):
	k = nodes[e].kind
	if k == nIf:
		g.risingIndexes(nodes[e].kids(kidIds)[0], v, body, names, found)   # the condition always runs
		return
	if k in [nMatch, nWhile, nFor, nLambda]: return
	if k == nBinary and (nodes[e].ival in [binAnd, binOr, binCoalesce]):
		g.risingIndexes(nodes[e].kids(kidIds)[0], v, body, names, found)
		return   # the right side may not run
	if k == nIndex:
		base = nodes[e].kids(kidIds)[0]
		rise = g.indexRise(nodes[e].kids(kidIds)[1], v, body, names)
		if rise >= 0 and nodes[base].kind == nIdent and nodes[base].text in names.lists and
			not g.bodyDisturbs(body, nodes[base].text, v) or
			rise >= 0 and g.steadyArray(base, v, body, names):
			found.push(e)
	for kid in nodes[e].kids(kidIds):
		g.risingIndexes(kid, v, body, names, found)

# whether e or a part of it binds the name v: an array bound in a loop's body is not there before
# it, to be checked ahead
fn bindsIn(g Gen, e NodeId, v str) bool:
	nodes[e].kind == nLet and nodes[e].text == v or nodes[e].kids(kidIds).any(g.bindsIn(it, v)) or
		nodes[e].sub(kidIds).any(g.bindsIn(it, v))

# whether e is a fixed array the loop reaches the same way at each step (its length is its type's)
fn steadyArray(mut g Gen, e NodeId, v str, body NodeId, names LoopLocals) bool:
	t = g.ty(e)
	if g.tyK(tys[t].inner if g.tyK(t) == tRef else t) != tArray: return false
	k = nodes[e].kind
	if k == nIndex:
		return g.indexRise(nodes[e].kids(kidIds)[1], v, body, names) == 0 and
			g.steadyArray(nodes[e].kids(kidIds)[0], v, body, names)
	root = e
	while nodes[root].kind == nField or nodes[root].kind == nDeref:
		root = nodes[root].kids(kidIds)[0]
	nodes[root].kind == nIdent and not g.bindsIn(body, nodes[root].text)

# how an integer index changes with the counter v over the loop: 1 it rises (v appears once,
# times a literal at most), 0 it stays (literals, and locals the body never changes), -1 anything
# else
fn indexRise(mut g Gen, written NodeId, v str, body NodeId, names LoopLocals) i64:
	e = g.c.unwidened(written)   # (a ranged counter widened to i64 keeps its value)
	k = nodes[e].kind
	if k == nInt: return 0
	if k == nIdent:
		if nodes[e].text == v: return 1
		return 0 if nodes[e].text in names.ints and not g.assignsName(body, nodes[e].text) else -1
	if k != nBinary: return -1
	op = nodes[e].ival
	a = g.indexRise(nodes[e].kids(kidIds)[0], v, body, names)
	b = g.indexRise(nodes[e].kids(kidIds)[1], v, body, names)
	if a < 0 or b < 0: return -1
	if op == binAdd: return a + b if a + b <= 1 else -1
	if op == binSub: return a if b == 0 else -1
	if op == binMul:
		if a + b == 0: return 0
		lit = nodes[e].kids(kidIds)[1] if a == 1 else nodes[e].kids(kidIds)[0]
		return 1 if nodes[lit].kind == nInt and g.intLitValue(lit) >= 1 else -1
	if op == binShr or op == binDiv:
		# through a literal shift or a positive divisor: still never falls
		r = nodes[e].kids(kidIds)[1]
		return a if b == 0 and nodes[r].kind == nInt and
			g.intLitValue(r) >= (0 if op == binShr else 1)
			else -1
	-1

# the + - * of a rising index (indexRise): each lies between its values at the loop's first and
# last steps, so checked there it cannot overflow at a step between
fn indexArithmetic(g Gen, written NodeId, mut out NodeId[]):
	e = g.c.unwidened(written)
	if nodes[e].kind != nBinary: return
	if nodes[e].ival in [binAdd, binSub, binMul]:
		out.push(e)
	for k in nodes[e].kids(kidIds):
		g.indexArithmetic(k, out)

# whether the statement may end the step or the loop early (a break, continue or return in it)
fn leavesEarly(g Gen, e NodeId) bool:
	k = nodes[e].kind
	if k in [nBreak, nContinue, nReturn]: return true
	nodes[e].kids(kidIds).any(g.leavesEarly(it)) or nodes[e].sub(kidIds).any(g.leavesEarly(it))

# whether the body may resize or replace list L, or change the loop variable v
# whether the function callee names may resize the list given as its argument i: a mut or
# moved parameter its body changes (or passes on), or a callee not known
fn paramMayDisturb(g Gen, callee NodeId, i i64, depth i64):
	if nodes[callee].kind != nIdent or depth >= 2 or g.findVar(nodes[callee].text) >= 0:
		return true   # (a closure local, or too deep to follow)
	fnd = g.c.findFunc(nodes[callee].text, nameOf(nodes, callee)) ?? return true
	if i >= nodes[fnd].kids(kidIds).len or nodes[fnd].sub(kidIds).isEmpty or
		not nodes[fnd].names(kidIds).isEmpty:
		return true
	bodyRead(fnd)
	p = nodes[fnd].kids(kidIds)[i]
	mode = nodes[p].ival
	mode != modeRead and
		(
			mode != modeMut or
				g.bodyDisturbsAt(nodes[fnd].sub(kidIds)[0], nodes[p].text, "", depth + 1, none)
		)

fn bodyDisturbs(g Gen, e NodeId, l str, v str):
	g.bodyDisturbsAt(e, l, v, 0, none)

fn bodyDisturbsAt(g Gen, e NodeId, l str, v str, depth i64, skip NodeId?) bool:
	if e == skip: return false
	k = nodes[e].kind
	if k == nCall:
		callee = nodes[e].kids(kidIds)[0]
		if nodes[callee].kind == nField:
			obj = nodes[callee].kids(kidIds)[0]
			m = nodes[callee].text
			if nodes[obj].kind == nIdent and nodes[obj].text == l and
				(
					g.c.methodIsMutating(m) or m == "copy" or m == "sortedBy" or m == "sortBy" or
						m == "sorted" or
						m == "reversed"
				):
				return true
		rawElem = nodes[callee].kind == nIdent and
			(nodes[callee].text == "__at" or nodes[callee].text == "__setAt")
		for i in 1..g.c.nodes[e].kids(g.c.kidIds).len:
			a = nodes[e].kids(kidIds)[i]
			if nodes[a].kind == nIdent and nodes[a].text == l and not (rawElem and i == 1) and
				g.paramMayDisturb(callee, i - 1, depth):
				return true   # a bare list argument may be a mut parameter
	if k == nAssign:
		target = nodes[e].kids(kidIds)[0]
		if nodes[target].kind == nIdent and (nodes[target].text == l or nodes[target].text == v):
			return true
	if k == nLet and (nodes[e].text == l or nodes[e].text == v): return true
	if k == nUnary and (nodes[e].ival == unMove or nodes[e].ival == unMutRef):
		kid = nodes[e].kids(kidIds)[0]
		if nodes[kid].kind == nIdent and nodes[kid].text == l:
			return true   # moved, or lent for mutation (it may shrink)
	nodes[e].kids(kidIds).any(g.bodyDisturbsAt(it, l, v, depth, skip)) or
		nodes[e].sub(kidIds).any(g.bodyDisturbsAt(it, l, v, depth, skip))
