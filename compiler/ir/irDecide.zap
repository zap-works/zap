# What the lowering decides of a function from its body as written, before lowering it: a lambda
# lent to a call (a read parameter, a pipeline's step) or only called by its name dies with the
# call, so it borrows what it captures (flagBorrowLambda); a kept one copies the shared values it
# captures (text2: "|name|"); a statement of an `arena:` block that stores outside it allocates
# from the heap (flagArenaPause): it changes a place bound before the block, returns, gives a
# lambda that is kept, may give back an error (`?`) or calls a function that changes a module
# variable.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

type IrDecide:
	names str[] = []   # the names bound where the walk is, the latest last
	depths i64[] = []   # each one's open arena blocks
	plain bool[] = []   # and whether it is plain data
	starts i64[] = []   # per open block: where its names start
	arenas i64 = 0   # the arena blocks open
	lambdaArenas i64 = 0   # those open where the innermost lambda begins: its return leaves none

fn irDecide(mut g Gen, fnd NodeId, implType TypeId?):
	if nodes[fnd].sub(kidIds).isEmpty or nodes[fnd].mod(kidIds) == "rt": return
	g.c.readBody(fnd)
	g.irForgetDecisions(nodes[fnd].sub(kidIds)[0])
	d = IrDecide()
	if implType is t:
		d.irBound("self", g.c.isPlainType(t))
		if g.c.tKind(t) == tStruct:
			for fAt in 0..nodes[declOf(tys, t)].kids(kidIds).len:
				f = nodes[declOf(tys, t)].kids(kidIds)[fAt]
				d.irBound(
					nodes[f].text,
					g.c.isPlainType(g.c.resolveType(nodes[f].types(kidIds)[0]))
				)
	for pAt in 0..nodes[fnd].kids(kidIds).len:
		p = nodes[fnd].kids(kidIds)[pAt]
		d.irBound(nodes[p].text, g.c.isPlainType(g.c.resolveType(nodes[p].types(kidIds)[0])))
	g.irDecideBlock(d, nodes[fnd].sub(kidIds)[0])

fn irBound(mut d IrDecide, name str, plain bool):
	d.names.push(name.copy())
	d.depths.push(d.arenas)
	d.plain.push(plain)

# the flags a lowering of another instance decided, taken off
fn irForgetDecisions(mut g Gen, e NodeId):
	if nodes[e].kind == nLambda:
		g.irUnmark(e, flagBorrowLambda | flagLocalLambda)
		g.irSetShares(e, "")
	g.irUnmark(e, flagArenaPause)
	for kAt in 0..nodes[e].kids(kidIds).len:
		k = nodes[e].kids(kidIds)[kAt]
		g.irForgetDecisions(k)
	for bAt in 0..nodes[e].sub(kidIds).len:
		b = nodes[e].sub(kidIds)[bAt]
		g.irForgetDecisions(b)

fn irDecideBlock(mut g Gen, mut d IrDecide, b NodeId):
	d.starts.push(d.names.len)
	kids = nodes[b].kids(kidIds).copy()
	for i, s in kids:
		g.irDecideStmt(d, s, kids[i + 1..])   # (its lambdas' flags first)
		if d.arenas > 0 and nodes[s].kind != nIf and g.irStoresOutside(d, s):
			g.irMark(s, flagArenaPause)
	start = d.starts.pop() ?? 0
	d.names.truncate(start)
	d.depths.truncate(start)
	d.plain.truncate(start)

fn irDecideStmt(mut g Gen, mut d IrDecide, s NodeId, after NodeId[]):
	k = nodes[s].kind
	if k == nIf and nodes[s].hasFlag(flagArena):
		d.arenas += 1
		g.irDecideBlock(d, nodes[s].sub(kidIds)[0])
		d.arenas -= 1
		return
	if k == nIf:
		if d.arenas > 0 and g.irStoresOutside(d, nodes[s].kids(kidIds)[0]):
			g.irMark(s, flagArenaPause)
		g.irDecideExpr(d, nodes[s].kids(kidIds)[0])
		for bAt in 0..nodes[s].sub(kidIds).len:
			b = nodes[s].sub(kidIds)[bAt]
			g.irDecideBlock(d, b)
		return
	if k == nFor:
		g.irDecideExpr(d, nodes[s].kids(kidIds)[0])
		d.starts.push(d.names.len)
		d.irBound(nodes[s].text, false)
		for nm in nodes[s].names(kidIds).copy():
			d.irBound(nm, false)
		g.irDecideBlock(d, nodes[s].sub(kidIds)[0])
		start = d.starts.pop() ?? 0
		d.names.truncate(start)
		d.depths.truncate(start)
		d.plain.truncate(start)
		return
	if k == nWhile:
		g.irDecideExpr(d, nodes[s].kids(kidIds)[0])
		g.irDecideBlock(d, nodes[s].sub(kidIds)[0])
		return
	if k == nLet and not nodes[s].kids(kidIds).isEmpty:
		value = nodes[s].kids(kidIds)[0]
		fresh = d.irDepthOf(nodes[s].text) < 0 or not nodes[s].canAssign(kidIds)
		if fresh and not nodes[s].hasFlag(flagMut) and nodes[value].kind == nLambda and
			after.all(g.irUsesOnlyAsCallee(it, nodes[s].text, false)):
			g.irMark(value, flagBorrowLambda | flagLocalLambda)
		g.irDecideExpr(d, value)
		if fresh:
			d.irBound(nodes[s].text, g.c.isPlainType(typeOf(nodes, value)))
		return
	for kidAt in 0..nodes[s].kids(kidIds).len:
		kid = nodes[s].kids(kidIds)[kidAt]
		g.irDecideExpr(d, kid)
	for bAt in 0..nodes[s].sub(kidIds).len:
		b = nodes[s].sub(kidIds)[bAt]
		g.irDecideBlock(d, b)

fn irDecideExpr(mut g Gen, mut d IrDecide, e NodeId):
	k = nodes[e].kind
	if k == nCall:
		for a in g.irLentLambdas(e):
			g.irMark(a, flagBorrowLambda)
		if g.c.isParallelStream(e) and nodes[g.c.argAt(e, 1)].kind == nLambda:
			g.irMark(g.c.argAt(e, 1), flagBorrowLambda)   # the loop's own stream ends with the loop
		if g.c.runsAsJob(e) and nodes[g.c.argAt(e, 0)].kind == nLambda:
			g.irMark(g.c.argAt(e, 0), flagOnce)   # a job runs once
	if k == nLambda:
		if not g.irFlagged(e, flagBorrowLambda):
			g.irSharedCaptures(e)
		d.starts.push(d.names.len)
		for nm in nodes[e].names(kidIds).copy():
			d.irBound(nm, false)
		outer = d.lambdaArenas
		d.lambdaArenas = d.arenas
		if not nodes[e].sub(kidIds).isEmpty:
			g.irDecideBlock(d, nodes[e].sub(kidIds)[0])
		else:
			g.irDecideExpr(d, nodes[e].kids(kidIds)[0])
		d.lambdaArenas = outer
		start = d.starts.pop() ?? 0
		d.names.truncate(start)
		d.depths.truncate(start)
		d.plain.truncate(start)
		return
	if k == nMatch:
		g.irDecideExpr(d, nodes[e].kids(kidIds)[0])
		for arm in g.c.matchArms(e):
			d.starts.push(d.names.len)
			bound = []
			g.c.patternNames(g.c.armPattern(arm), bound)
			pat = g.c.armPattern(arm)
			if nodes[pat].ival == patBind:
				bound.push(nodes[pat].text.copy())
			for nm in bound:
				d.irBound(nm, false)
			if g.c.armGuard(arm) is guard:
				g.irDecideExpr(d, guard)
			if g.c.armBlock(arm) is blk:
				g.irDecideBlock(d, blk)
			else:
				g.irDecideExpr(d, g.c.armBody(arm))
			start = d.starts.pop() ?? 0
			d.names.truncate(start)
			d.depths.truncate(start)
			d.plain.truncate(start)
		return
	for kidAt in 0..nodes[e].kids(kidIds).len:
		kid = nodes[e].kids(kidIds)[kidAt]
		g.irDecideExpr(d, kid)
	for bAt in 0..nodes[e].sub(kidIds).len:
		b = nodes[e].sub(kidIds)[bAt]
		g.irDecideBlock(d, b)

# the lambdas call e lends: those given to a read parameter of a function or method, and a
# pipeline step's (it runs inline)
fn irLentLambdas(mut g Gen, e NodeId):
	out = []
	if nodes[e].hasFlag(flagClosure) or nodes[e].kids(kidIds).isEmpty: return out
	callee = nodes[e].kids(kidIds)[0]
	n = g.c.argCount(e)
	decl NodeId? = none
	if nodes[callee].kind == nIdent:
		decl = g.c.findFunc(nodes[callee].text, nameOf(nodes, callee))
	elif nodes[callee].kind == nField and not nodes[callee].kids(kidIds).isEmpty:
		ot = nodes[nodes[callee].kids(kidIds)[0]].ty
		otk = g.c.tKind(ot)
		if (otk == tStruct or otk == tEnum) and ot is t:
			decl = g.c.findMethod(tys[t].name, nodes[callee].text)
		if decl == none and ot != none and nodes[callee].text in pipelineSteps:
			for i in 0..n:
				if nodes[g.c.argAt(e, i)].kind == nLambda:
					out.push(g.c.argAt(e, i))
			return out
	fnd = decl ?? return out
	for i in 0..n:
		a = g.c.argAt(e, i)
		mode = nodes[nodes[fnd].kids(kidIds)[i]].ival if i < nodes[fnd].kids(kidIds).len
			else modeRead
		if nodes[a].kind == nLambda and mode != modeMove and mode != modeMut:
			out.push(a)
	out

# a kept lambda's captures that copy freely and are not plain data (shared values): the closure
# holds one more owner of each
fn irSharedCaptures(mut g Gen, lam NodeId):
	marks = ""
	for i in 0..nodes[lam].names2(kidIds).len:
		if i >= nodes[lam].ints(kidIds).len: break
		t = nodes[lam].ints(kidIds)[i]
		if g.c.copiesFreely(t) and not g.c.isPlainType(t):
			marks = "{marks}|{nodes[lam].names2(kidIds)[i]}|"
	g.irSetShares(lam, marks)

# how many arena blocks were open where name was bound (-1: not bound here; a module variable
# 0)
fn irDepthOf(d IrDecide, name str):
	i = d.names.len - 1
	while i >= 0:
		if d.names[i] == name: return d.depths[i]
		i -= 1
	-1

# whether the place rooted at name is outside the innermost arena block and owns memory
fn irOutsidePlace(mut g Gen, d IrDecide, name str):
	i = d.names.len - 1
	while i >= 0:
		if d.names[i] == name: return not d.plain[i] and d.depths[i] < d.arenas
		i -= 1
	cd = g.c.findDeclByGlobalName(nConstDecl, name) ?? return false
	nodes[cd].hasFlag(flagMut) and not g.c.isPlainType(g.c.constTypeOf(cd))

# Whether statement (or expression) e, in an arena block, stores outside it (the blocks under it
# are statements of their own, a lambda's body is the lambda's).
fn irStoresOutside(mut g Gen, d IrDecide, e NodeId) bool:
	k = nodes[e].kind
	if k == nReturn or k == nTry: return d.arenas > d.lambdaArenas   # (a lambda's own arenas only)
	if k == nLambda: return not g.irFlagged(e, flagBorrowLambda) or
		nodes[e].bounds(kidIds).copy().any(g.irOutsidePlace(d, it))
	if k == nAssign:
		if g.irChangesOutside(d, nodes[e].kids(kidIds)[0]): return true
	if k == nLet and nodes[e].canAssign(kidIds) and d.irDepthOf(nodes[e].text) >= 0 and
		g.irOutsidePlace(d, nodes[e].text.copy()):
		return true
	if k == nUnary and nodes[e].ival == unMutRef and
		g.irChangesOutside(d, nodes[e].kids(kidIds)[0]):
		return true
	if k == nCall and g.irCallStoresOutside(d, e): return true
	if k in [nIf, nFor, nWhile]: return g.irStoresOutside(d, nodes[e].kids(kidIds)[0])
	nodes[e].kids(kidIds).copy().any(g.irStoresOutside(d, it))

# whether the place e changes is rooted outside the innermost arena block
fn irChangesOutside(mut g Gen, d IrDecide, e NodeId) bool:
	root, _ = g.c.placePath(e)
	r = root ?? return false
	g.irOutsidePlace(d, nodes[r].text.copy())

# the function a call's callee names, or the method of its struct or enum receiver; none for
# another callee
fn irCalleeDecl(g Gen, callee NodeId):
	if nodes[callee].kind == nIdent: return g.c.findFunc(nodes[callee].text, nameOf(nodes, callee))
	if nodes[callee].kind != nField or nodes[callee].kids(kidIds).isEmpty: return none
	ot = nodes[nodes[callee].kids(kidIds)[0]].ty
	otk = g.c.tKind(ot)
	if (otk == tStruct or otk == tEnum) and ot is t:
		return g.c.findMethod(tys[t].name, nodes[callee].text)
	none

# a call that changes a place outside the arena block (its receiver or a mut argument), takes
# one out of it, or calls a function that changes a module variable owning memory
fn irCallStoresOutside(mut g Gen, d IrDecide, e NodeId):
	callee = nodes[e].kids(kidIds)[0]
	n = g.c.argCount(e)
	decl = g.irCalleeDecl(callee)
	if nodes[callee].kind == nField and not nodes[callee].kids(kidIds).isEmpty:
		obj = nodes[callee].kids(kidIds)[0]
		ot = nodes[obj].ty
		otk = g.c.tKind(ot)
		m = nodes[callee].text
		if (otk == tStruct or otk == tEnum) and ot != none:
			if decl is md and nodes[md].hasFlag(flagMut) and g.irChangesOutside(d, obj):
				return true
		elif g.c.methodIsMutating(m) and (otk == tList or otk == tMap or m == "take" or
				m == "intoStr") and g.irChangesOutside(d, obj):
			return true
		if nodes[e].hasFlag(flagTaken) and g.irChangesOutside(d, obj): return true
	fnd = decl ?? return false
	for i in 0..n:
		if i < nodes[fnd].kids(kidIds).len and nodes[nodes[fnd].kids(kidIds)[i]].ival == modeMut and
			g.irChangesOutside(d, g.c.argAt(e, i)):
			return true
	if g.c.opaqueFunction(fnd): return false
	g.c.effects.changesModuleVariable(fnd)

fn irUsesOnlyAsCallee(g Gen, e NodeId, name str, inLambda bool) bool:
	k = nodes[e].kind
	if k == nIdent: return nodes[e].text != name
	if k == nLet and nodes[e].text == name: return false
	if k == nCall and not inLambda and nodes[nodes[e].kids(kidIds)[0]].kind == nIdent and
		nodes[nodes[e].kids(kidIds)[0]].text == name:
		return (1..g.c.nodes[e].kids(g.c.kidIds).len).all(i:
			g.irUsesOnlyAsCallee(nodes[e].kids(kidIds)[i], name, inLambda)
		)
	nested = inLambda or k == nLambda
	nodes[e].kids(kidIds).all(g.irUsesOnlyAsCallee(it, name, nested)) and
		nodes[e].sub(kidIds).all(g.irUsesOnlyAsCallee(it, name, nested))

# ---------- what a binding or a choice borrows, decided where it is lowered ----------

# whether e names a place: a local, a field of the receiver, a module variable, a field or an
# element of one, an element of a constant list (kept in the data area), the value behind a
# reference
fn irNamesPlace(mut g Gen, lw IrLower, e NodeId) bool:
	k = nodes[e].kind
	if k == nIdent:
		if nodes[e].hasFlag(flagFnRef): return false
		name = nodes[e].text.copy()
		if lw.irLookupAt(name) >= 0 or g.irFieldOfThis(lw, name): return true
		cd = g.c.findDeclByGlobalName(nConstDecl, name) ?? return false
		return nodes[cd].hasFlag(flagMut)
	if k == nField:
		obj = nodes[e].kids(kidIds)[0]
		return not nodes[e].hasFlag(flagSafe) and nodes[obj].ty != none and g.irNamesPlace(lw, obj)
	if k == nIndex:
		base = nodes[e].kids(kidIds)[0]
		if g.irNamesPlace(lw, base): return true
		return nodes[base].kind == nIdent and lw.irLookupAtNo(nameOf(nodes, base)) < 0 and
			g.c.storedConstant(nodes[base].text.copy())
	k == nDeref

# whether e names a local that owns its value
fn irNamesOwnedLocal(g Gen, lw IrLower, e NodeId):
	if nodes[e].kind != nIdent: return false
	i = lw.irLookupAtNo(nameOf(nodes, e))
	i >= 0 and lw.owned.any(.name == i)

# whether the left side of a `??` is borrowed: a place, or a `??` whose own left side is
fn irCoalesceLends(mut g Gen, lw IrLower, l NodeId) bool:
	g.irNamesPlace(lw, l) or nodes[l].kind == nBinary and nodes[l].ival == binCoalesce and
		g.irCoalesceLends(lw, nodes[l].kids(kidIds)[0])

# whether e is an `if` used as a value whose branches are places (or literals, which live on):
# read, it borrows the one the condition picks
fn irPlaceChoice(mut g Gen, lw IrLower, e NodeId):
	branches = g.c.ifValueBranches(e)
	if branches.isEmpty: return false
	places = 0
	for b in branches:
		if g.irNamesPlace(lw, b):
			places += 1
		elif nodes[b].kind != nStr:
			return false
	places > 0

# Whether the immutable binding s of value borrows it rather than owning a value: a place, a
# choice of places, the value a `??` of a place picks, what `x?` holds of a place this code does
# not own. A value that copies freely is copied instead when the check finds its owner changed
# meanwhile (flagAutoCopy, irOwnMarks).
fn irLetBorrows(mut g Gen, lw IrLower, s NodeId, value NodeId) bool:
	if nodes[s].hasFlag(flagMut) or g.irFlagged(value, flagAutoCopy): return false
	vt = typeOf(nodes, value)
	if g.c.isPlainType(vt) or g.c.isRefLike(vt): return false
	if g.c.holdsRefs(vt) and not g.irNamesPlace(lw, value): return false
	k = nodes[value].kind
	if k == nBinary and nodes[value].ival == binCoalesce:
		return g.irCoalesceLends(lw, nodes[value].kids(kidIds)[0])
	if g.irPlaceChoice(lw, value): return not g.c.copiesFreely(vt)
	if k == nMatch: return g.irMatchLentWhole(lw, value)
	if k == nTry:
		inner = nodes[value].kids(kidIds)[0]
		return g.irNamesPlace(lw, inner) and not g.irNamesOwnedLocal(lw, inner) and
			not g.c.copiesFreely(vt)
	g.irNamesPlace(lw, value)

# whether a match's value borrows: one of its arms' values does
fn irMatchLends(mut g Gen, lw IrLower, e NodeId) bool:
	for arm in g.c.matchArms(e):
		v = g.c.armValue(arm) ?? continue
		if g.irArmLends(lw, v): return true
	false

# whether an arm's value is borrowed: of an owning type, not made here, not a local's own value
# (which moves out), not a literal (it fits both)
fn irArmLends(mut g Gen, lw IrLower, v NodeId) bool:
	k = nodes[v].kind
	if g.c.isPlainType(typeOf(nodes, v)) or g.irFlagged(v, flagAutoCopy) or k == nStr or
		k == nNone:
		return false
	if k == nIdent: return not g.irNamesOwnedLocal(lw, v)
	if k == nDeref: return true
	if k == nField or k == nIndex: return g.irNamesPlace(lw, v)
	if k == nMatch: return g.irMatchLends(lw, v)
	if k == nBinary and nodes[v].ival == binCoalesce:
		return g.irCoalesceLends(lw, nodes[v].kids(kidIds)[0]) or g.c.isPlainType(typeOf(nodes, v))
	g.c.isAliasCall(v) or g.irPlaceChoice(lw, v)

# whether match e's value, of a type that owns memory (by address, or a map or a box in a word),
# is only ever its place's own: the scrutinee a place, each arm's value a name or a place that
# lends (its pattern's names lend the scrutinee's parts) or none (the arm leaves). Read, it borrows the part an arm picks, as a
# choice of places does: never a copy (one with a drop function would be dropped twice).
fn irMatchLentWhole(mut g Gen, lw IrLower, e NodeId):
	t = g.ty(e)
	if not g.irOwnedByAddress(t) and not g.irIsOwnedWord(t) or
		not g.irNamesPlace(lw, nodes[e].kids(kidIds)[0]):
		return false
	lends = false
	for arm in g.c.matchArms(e):
		if g.c.armBlock(arm) != none:
			v = g.c.armValue(arm) ?? continue   # its block ends in a jump
			if not g.c.stops(v): return false
		elif g.c.stops(nodes[arm].kids(kidIds)[1]):
			continue
		elif g.irArmLends(lw, nodes[arm].kids(kidIds)[1]) and
			g.irIsPlaceNode(nodes[arm].kids(kidIds)[1]):
			lends = true
		else:
			return false
	lends
