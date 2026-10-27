# Handles known to name a value of their pool, so `pool[h]` reads its place with no check of its
# count (Pool's indexLive) and `pool.get(h)` gives it as some (getLive):
# - the handle of a walk over `pool.handles()` whose body removes nothing from the pool, which
#   steps over the pool's places itself when the body adds nothing either;
# - a handle `pool[h]` found in an earlier statement of the block, with nothing between that may
#   remove from the pool.
# What may remove is judged by what the code says: the pool named only to read, add or index it,
# no other name for it or for what holds it, no call of a function value, and in a method whose
# pool is the receiver's, no bare call of another method.

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# the methods of a pool that leave every value in it
poolReads = [
	"get",
	"getMut",
	"getLive",
	"getLiveMut",
	"index",
	"indexMut",
	"indexLive",
	"indexLiveMut",
	"contains",
	"handles",
	"placeCount",
	"liveAt",
	"handleAt",
	"add",
	"len",
	"isEmpty"
]

# a pool and a handle that names a value of it: pool[h] of them needs no check
type LiveHandle:
	pool str   # the pool's place as written, a field named bare spelled through self
	root i64   # the variable the place starts at (Checker.vars)
	handle i64   # the handle's variable (Checker.vars)
	scope i64   # the scope it was found in (Checker.scopeStarts.len): it ends with it

# the place of `for h in place.handles():` while its iterable is not checked yet, else none
fn walkedPool(mut c Checker, s NodeId) NodeId?:
	iter = nodes[s].kids(kidIds)[0]
	if nodes[iter].kind != nCall or nodes[iter].kids(kidIds).len != 1: return none
	callee = nodes[iter].kids(kidIds)[0]
	if nodes[callee].kind != nField or nodes[callee].text != "handles" or
		nodes[callee].kids(kidIds).len != 1:
		return none
	place = nodes[callee].kids(kidIds)[0]
	place if c.fieldChain(place) else none

# whether a bare name is a field of the receiver (a method's body names its fields bare)
fn isBareField(c Checker, name str):
	c.implType != none and c.vars.any(.isField and .name == name)

# a place's text with a field named bare spelled through self (`mobs` is `self.mobs`)
fn walkPlace(c Checker, e NodeId):
	text = exprText(nodes, kidIds, e)
	root = c.placeRootNode(e)
	"self.{text}" if nodes[root].kind == nIdent and c.isBareField(nodes[root].text) else text

# the variable a place starts at (self for a field named bare), else -1
fn walkRoot(mut c Checker, e NodeId) i64:
	root = c.placeRootNode(e)
	if nodes[root].kind != nIdent or nodes[root].hasFlag(flagModuleVar): return -1
	if c.isBareField(nodes[root].text): return c.lookupVar("self")
	c.lookupVarNo(nameOf(nodes, root))

fn isPool(mut c Checker, maybeT TypeId?):
	t = maybeT ?? return false
	c.tKind(t) == tStruct and nodes[declOf(tys, t)].text2().startsWith("Pool<") and
		c.findMethod(tys[t].name, "indexLive") != none

# whether a mut ref other than root's variable is held: another name that may change the pool
fn otherMutRef(mut c Checker, root i64):
	(0..c.vars.len).any(
		it != root and c.tKind(c.vars[it].ty) == tRef and tys[c.vars[it].ty].bits == 1
	)

# The pool at place (a local's, as a module variable changes in any call) known to keep the value
# of the handle variable handle while the code that follows does what it says.
fn noteLive(mut c Checker, place NodeId, handle i64):
	if handle < 0 or not c.isPool(c.derefType(typeOf(nodes, place))): return false
	root = c.walkRoot(place)
	if root < 0 or c.otherMutRef(root): return false
	pool = c.walkPlace(place)
	if c.liveHandles.any(.handle == handle and .root == root and .pool == pool): return true
	c.liveHandles.push(LiveHandle(pool, root, handle, c.scopeStarts.len))
	true

# the handles found in the scope that ends now are forgotten
fn forgetScope(mut c Checker):
	i = 0
	while i < c.liveHandles.len:
		if c.liveHandles[i].scope >= c.scopeStarts.len:
			c.liveHandles.remove(i)
		else:
			i += 1

# The live handles hidden while a body checked apart is checked (a lambda's, which runs when it is
# called; a function's): the caller gives them back after it.
fn hideLiveHandles(mut c Checker):
	hidden = move c.liveHandles
	c.liveHandles = []
	hidden

# for h in pool.handles(): the body checked with the walk's handle live when it removes nothing,
# and made a walk over the places when it adds nothing either
fn checkPoolWalk(mut c Checker, s NodeId, place NodeId, varT TypeId):
	body = nodes[s].sub()[0]
	pool = c.walkPlace(place)
	root = c.walkRoot(place)
	live = c.isPool(c.derefType(typeOf(nodes, place))) and root >= 0 and not c.otherMutRef(root) and
		not c.mayRemove(body, pool, true)
	if live and nodes[s].names().isEmpty and not c.mayRemove(body, pool, false):
		c.walkPlaces(s, place)
		return
	c.enterScope()
	h = c.addVar(nodes[s].text, varT, false, false, nodes[s].line, nodes[s].col)
	if live:
		c.noteLive(place, h)
	c.checkLoopBody(body)
	c.exitScope()
	c.proveLoopIndexes(s)

# `for h in pool.handles():` made `for $i in 0..pool.placeCount():` whose body starts with
# `if not pool.liveAt($i): continue` and `h = pool.handleAt($i)` (the let a live handle: noteLet),
# then checked: no list of the handles is built. The body adds nothing and removes nothing, so the
# places walked are those the list would give.
fn walkPlaces(mut c Checker, s NodeId, place NodeId):
	line = nodes[s].line
	col = nodes[s].col
	idx = "$i{s}"
	count = newNode(
		nodes,
		kidIds,
		nField,
		line,
		col,
		text = "placeCount",
		kids = [cloneTree(nodes, kidIds, place)]
	)
	zero = newNode(nodes, kidIds, nInt, line, col, text = "0")
	upper = newNode(nodes, kidIds, nCall, line, col, kids = [count])
	r = newNode(nodes, kidIds, nRange, line, col, kids = [zero, upper])
	live = c.placeCall(place, "liveAt", idx, line, col)
	unlive = newNode(nodes, kidIds, nUnary, line, col, kids = [live])
	nodes[unlive].ival = unNot
	skip = newNode(nodes, kidIds, nIf, line, col, kids = [unlive])
	nodes[skip].nodePart().sub = [
		newNode(
			nodes,
			kidIds,
			nBlock,
			line,
			col,
			kids = [newNode(nodes, kidIds, nContinue, line, col)]
		)
	]
	bind = newNode(
		nodes,
		kidIds,
		nLet,
		line,
		col,
		kids = [c.placeCall(place, "handleAt", idx, line, col)]
	)
	nodes[bind].setText(nodes[s].takeText())   # the loop's name moves to the binding
	c.walkLets.push(bind)
	body = nodes[s].sub()[0]
	nodes[body].insertKid(kidIds, 0, bind)
	nodes[body].insertKid(kidIds, 0, skip)
	nodes[s].setText(idx)
	nodes[s].setKids(kidIds, [r])
	c.checkFor(s)

# place.method(i), i the variable named idx
fn placeCall(mut c Checker, place NodeId, method str, idx str, line i64, col i64) NodeId:
	f = newNode(
		nodes,
		kidIds,
		nField,
		line,
		col,
		text = method.copy(),
		kids = [cloneTree(nodes, kidIds, place)]
	)
	i = newNode(nodes, kidIds, nIdent, line, col, text = idx.copy())
	newNode(nodes, kidIds, nCall, line, col, kids = [f, i])

# The statement s about to be checked: the live handles of the pools it may remove from are
# forgotten. What it indexes it gives back: the pool[h] it always evaluates (the place, h a
# variable then), to note after it with noteIndexed.
fn beforeStmt(mut c Checker, s NodeId):
	i = 0
	while i < c.liveHandles.len:
		if c.mayRemove(s, c.liveHandles[i].pool, true):
			c.liveHandles.remove(i)
		else:
			i += 1
	found = []
	for e in nodes[s].kids(kidIds):
		c.indexedAlways(e, found)
	kept = []
	for (place, h) in found:
		if h >= 0 and not c.vars[h].isMut and c.tKind(c.vars[h].ty) == tStruct and
			not c.mayRemove(s, c.walkPlace(place), true):
			kept.push((place, h))
	kept

# The statement s checked: each pool[h] it always evaluated found a value, which stays while
# nothing removes from the pool; the let of a walk over the places binds a live handle.
fn afterStmt(mut c Checker, s NodeId, indexed (NodeId, i64)[]):
	for (place, h) in indexed:
		c.noteLive(place, h)
	if nodes[s].kind == nLet and s in c.walkLets:
		callee = c.writtenCallee(nodes[s].kids(kidIds)[0])
		c.noteLive(nodes[callee].kids(kidIds)[0], c.lookupVarNo(nameOf(nodes, s)))

# the place[h] in e, h a variable, that e evaluates whenever it is evaluated (not the right of
# `and`, `or` or `??`, a match's arms or a lambda's body)
fn indexedAlways(mut c Checker, e NodeId, mut found (NodeId, i64)[]):
	k = nodes[e].kind
	if k == nLambda: return
	if k == nMatch or k == nBinary and nodes[e].ival in [binAnd, binOr, binCoalesce]:
		c.indexedAlways(nodes[e].kids(kidIds)[0], found)
		return
	if k == nIndex and nodes[e].kids(kidIds).len == 2 and
		c.isWalkPlace(nodes[e].kids(kidIds)[0]) and
		nodes[nodes[e].kids(kidIds)[1]].kind == nIdent:
		found.push((nodes[e].kids(kidIds)[0], c.lookupVar(nodes[nodes[e].kids(kidIds)[1]].text)))
	for kid in nodes[e].kids(kidIds):
		c.indexedAlways(kid, found)

# whether e may remove from the pool at the place `pool` (or add to it, unless addOk)
fn mayRemove(mut c Checker, e NodeId, pool str, addOk bool) bool:
	k = nodes[e].kind
	if k == nCall:
		callee = nodes[e].kids(kidIds)[0]
		if nodes[callee].kind == nField and nodes[callee].kids(kidIds).len == 1 and
			c.isWalkPlace(nodes[callee].kids(kidIds)[0]) and
			c.walkPlace(nodes[callee].kids(kidIds)[0]) == pool:
			if nodes[callee].text not in poolReads or not addOk and nodes[callee].text == "add":
				return true
			return nodes[e]
				.kids(kidIds)[1..nodes[e].kids(kidIds).len]
				.any(c.mayRemove(it, pool, addOk))
		if nodes[callee].kind == nField and nodes[callee].kids(kidIds).len == 1:
			# a method of another value: its receiver may be what holds the pool
			return c.mayRemove(nodes[callee].kids(kidIds)[0], pool, addOk) or
				nodes[e]
					.kids(kidIds)[1..nodes[e].kids(kidIds).len]
					.any(c.mayRemove(it, pool, addOk))
		if nodes[callee].kind == nIdent:
			name = nodes[callee].text
			if c.vars.any(.name == name and not .isField): return true   # a function value
			if pool.startsWith("self.") and c.implType is impl and
				c.findMethod(tys[impl].name, name) != none:
				return true   # a bare call passes self on
	elif k == nIndex and c.isWalkPlace(nodes[e].kids(kidIds)[0]) and
		c.walkPlace(nodes[e].kids(kidIds)[0]) == pool:
		return nodes[e].kidsFrom(kidIds, 1).any(c.mayRemove(it, pool, addOk))
	elif k == nBinary and nodes[e].ival == binIn and nodes[e].kids(kidIds).len == 2 and
		c.isWalkPlace(nodes[e].kids(kidIds)[1]) and c.walkPlace(nodes[e].kids(kidIds)[1]) == pool:
		return c.mayRemove(nodes[e].kids(kidIds)[0], pool, addOk)
	elif k == nField and nodes[e].text in ["len", "isEmpty"] and nodes[e].kids(kidIds).len == 1 and
		c.isWalkPlace(nodes[e].kids(kidIds)[0]) and c.walkPlace(nodes[e].kids(kidIds)[0]) == pool:
		return false
	elif c.isWalkPlace(e):
		# the pool, what holds it or what it holds, named on its own: given on, changed or lent
		text = c.walkPlace(e)
		return text == pool or pool.startsWith("{text}.") or text.startsWith("{pool}.")
	nodes[e].kids(kidIds).any(c.mayRemove(it, pool, addOk)) or
		nodes[e].sub().any(c.mayRemove(it, pool, addOk))

fn isWalkPlace(mut c Checker, e NodeId):
	nodes[e].kind in [nIdent, nField] and c.fieldChain(e)

# whether pool[h] (base and index as written) is of a handle known to name a value: no check
fn isLiveHandle(mut c Checker, base NodeId, idx NodeId):
	if c.liveHandles.isEmpty or nodes[idx].kind != nIdent or not c.isWalkPlace(base): return false
	h = c.lookupVarNo(nameOf(nodes, idx))
	if h < 0: return false
	pool = c.walkPlace(base)
	root = c.walkRoot(base)
	c.liveHandles.any(.handle == h and .root == root and .pool == pool)

# pool.get(h) of a live handle: getLive, which gives the value as some with no check
fn liveGet(mut c Checker, e NodeId):
	if c.liveHandles.isEmpty or nodes[e].kids(kidIds).len != 2: return
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind == nField and nodes[callee].text == "get" and
		nodes[callee].kids(kidIds).len == 1 and
		c.isLiveHandle(nodes[callee].kids(kidIds)[0], nodes[e].kids(kidIds)[1]):
		nodes[callee].setText("getLive")
