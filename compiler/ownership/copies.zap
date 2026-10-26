# What copies freely, what owns memory and what holds a value with a drop function; places' paths
# ("x", "x.f", "x[]") and how they overlap.

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# the way out an error on a value of a type parameter adds: the Copy bound
fn copyBoundHint(c Checker, t TypeId):
	u = t
	while c.tKind(u) in [tRef, tOption] and tys[u].param == "":
		u = innerOf(tys, u)
	si = c.standInIndex(u)
	if si < 0: return ""
	"; or, for plain data, declare <{tys[u].param} Copy> on {c.aliasFn[si]}"

# whether a copy of a value of type t (or of what a reference of type t points to) is cheap
# and owns nothing: plain data, or a shared value (copying it counts one more owner)
pub fn copiesFreely(mut c Checker, t TypeId) bool:
	k = c.tKind(t)
	if k == tRef: return c.copiesFreely(innerOf(tys, t))
	if k == tOption and tys[t].inner != none: return c.copiesFreely(innerOf(tys, t))
	if k == tBox and tys[t].counted: return true
	c.isPlainType(t)

# a binding written with `ref`: the program wants a reference, so conflicts are errors
fn explicitRef(c Checker, value NodeId):
	nodes[value].kind == nUnary and (nodes[value].ival == unRef or nodes[value].ival == unMutRef)

# Plain data: numbers, bool, unit, and structs, enums, optionals and results made only of plain
# data; a type parameter at its definition when it is Copy.
pub fn isPlainType(mut c Checker, t TypeId) bool:
	si = c.standInIndex(t)
	if si >= 0: return boundImplies(boundList(c.aliasBounds[si]), "Copy")
	k = c.tKind(t)
	if k in [tInt, tFloat, tBool, tUnit, tError, tRef, tSimd, tBytes, tVec]:
		return true   # a reference is plain data: copying it copies a pointer (its borrow is tracked apart)
	if k == tOption: return tys[t].inner == none or c.isPlainType(innerOf(tys, t))
	if k == tArray: return c.isPlainType(innerOf(tys, t))
	if k == tResult: return c.isPlainType(innerOf(tys, t)) and c.isPlainType(errOf(tys, t))
	if k != tStruct and k != tEnum or declOf(tys, t) in c.plainOpen:
		return false   # a type met again inside itself: checkRecursiveTypes reports it
	if k == tStruct and nodes[declOf(tys, t)].hasFlag(flagDrop): return false
	c.plainOpen.push(declOf(tys, t))
	plain = c.fieldsPlain(t)
	c.plainOpen.pop()
	plain

fn fieldsPlain(mut c Checker, t TypeId):
	if c.tKind(t) == tStruct:
		for fAt in 0..nodes[declOf(tys, t)].kids(kidIds).len:
			f = nodes[declOf(tys, t)].kids(kidIds)[fAt]
			if not c.isPlainType(c.resolveType(nodes[f].types()[0])): return false
		return true
	for vAt in 0..nodes[declOf(tys, t)].kids(kidIds).len:
		v = nodes[declOf(tys, t)].kids(kidIds)[vAt]
		for fAt in 0..nodes[v].kids(kidIds).len:
			f = nodes[v].kids(kidIds)[fAt]
			if not c.isPlainType(c.resolveType(nodes[f].types()[0])): return false
	true

# whether some program checked declares a drop function (holdsDrop is false at once otherwise)
mut dropTypesSeen = false

# Marks each struct with a drop function: `fn drop(mut self T)`, which the compiler calls where a
# value of T is destroyed (drops.zap), before its fields are. Such a type releases something
# (a GPU object, a handle), so it is not plain data: it moves and is never copied implicitly.
fn markDropTypes(mut c Checker):
	for d in c.decls[c.freshDecls..].copy():
		if nodes[d].kind != nImplDecl or not nodes[d].names2().isEmpty: continue
		for m in nodes[d].kids(kidIds):
			if nodes[m].text != "drop": continue
			c.enterModuleOf(d)
			sd = c.findTypeDecl(nodes[d].text)
			if not nodes[m].hasFlag(flagMut) or not nodes[m].kids(kidIds).isEmpty or
				not nodes[m].types().isEmpty or not nodes[m].names().isEmpty:
				c.errorAt(
					nodes[m].line,
					nodes[m].col,
					compileError("DropSignature", [])
				)
			elif sd is sd and nodes[sd].kind == nStructDecl and nodes[sd].names().isEmpty:
				nodes[sd].flags |= flagDrop
				c.layouts.remove(sd)   # its live word: laid out with it
				dropTypesSeen = true
			else:
				c.errorAt(
					nodes[m].line,
					nodes[m].col,
					compileError("DropGeneric", [])
				)
	c.curMod = -1
	c.curFile = ""

# whether t is, or holds, a struct with a drop function (its values are never deep-copied by the
# compiler: a copy would release the same thing twice)
fn holdsDrop(mut c Checker, t TypeId):
	if not dropTypesSeen: return false
	if i64(t) < dropsHeld.len and dropsHeld[t] != 0: return dropsHeld[t] == 2
	seen = []
	held = c.holdsDropSeen(t, seen)
	if c.subst.names.isEmpty:
		while dropsHeld.len <= i64(t):
			dropsHeld.push(0)
		dropsHeld[t] = 2 if held else 1
	held

# holdsDrop's answers by type (0 not known, 1 no, 2 yes), outside generic instances (whose
# fields resolve through the substitution in force)
mut dropsHeld i64[] = []

# whether dropping a value of t does more than free memory: it holds a struct with a drop
# function or a closure (whose environment may hold one)
fn dropActs(mut c Checker, t TypeId) bool:
	seen = []
	c.holdsDropSeen(t, seen, closures = true)

# (the struct and enum declarations already looked into in seen: a type may hold itself through
# a box, and each instance of a generic one is a type of its own; closures: a closure counts)
fn holdsDropSeen(mut c Checker, maybeT TypeId?, mut seen NodeId[], closures bool = false) bool:
	t = maybeT ?? return false
	k = c.tKind(t)
	if k == tFn: return closures
	if k == tStruct or k == tEnum:
		if declOf(tys, t) in seen: return false
		seen.push(declOf(tys, t))
	if k == tStruct:
		if nodes[declOf(tys, t)].hasFlag(flagDrop): return true
		for fAt in 0..nodes[declOf(tys, t)].kids(kidIds).len:
			f = nodes[declOf(tys, t)].kids(kidIds)[fAt]
			if c.holdsDropSeen(c.resolveType(nodes[f].types()[0]), seen, closures): return true
		return false
	if k == tEnum:
		for vAt in 0..nodes[declOf(tys, t)].kids(kidIds).len:
			v = nodes[declOf(tys, t)].kids(kidIds)[vAt]
			for fAt in 0..nodes[v].kids(kidIds).len:
				f = nodes[v].kids(kidIds)[fAt]
				if c.holdsDropSeen(c.resolveType(nodes[f].types()[0]), seen, closures): return true
		return false
	if k in [tList, tOption, tArray, tBox]: return c.holdsDropSeen(tys[t].inner, seen, closures)
	if k == tResult:
		return c.holdsDropSeen(tys[t].inner, seen, closures) or
			c.holdsDropSeen(tys[t].err, seen, closures)
	if k == tMap: return c.holdsDropSeen(tys[t].val, seen, closures)
	false

fn pathHead(path str) ref str:
	i = 0
	while i < path.len:
		b = path[i]
		if b == 46 or b == 91: return path[..i]
		i += 1
	path

# two paths overlap when one is a prefix of the other ("x" and "x.f", not "x.f" and "x.g")
# the place a summary's change q names: a grown list's ("c.nodes+") is the list
fn changedPlace(q str):
	q[..len - 1].copy() if q.endsWith("+") else q.copy()

# whether the change q (changedThrough's) overlaps path. A list only grown moves its elements, not
# the lists inside them: a reader that read such a list's header once (headersKept) still has it.
fn changeOverlaps(q str, path str, headersKept bool):
	place = changedPlace(q)
	if headersKept and q.endsWith("+") and path.startsWith("{place}[]") and
		path.len > place.len + 2:
		return false
	pathsOverlap(place, path)

fn pathsOverlap(a str, b str) bool:
	if a.len <= b.len:
		if not b.startsWith(a): return false
		if a.len == b.len: return true
		nb = b[a.len]
		return nb == 46 or nb == 91
	pathsOverlap(b, a)

# whether a value of type t is a shared value (a channel, an atomic), maybe optional
fn isShared(c Checker, t TypeId) bool:
	k = c.tKind(t)
	if k == tOption and tys[t].inner != none: return c.isShared(innerOf(tys, t))
	k == tBox and tys[t].counted

# a block that ends by leaving: its moves do not reach the code after it
fn blockLeaves(c Checker, b NodeId):
	if c.blockTerminates(b): return true
	n = nodes[b].kids(kidIds).len
	if n == 0: return false
	lk = nodes[nodes[b].kids(kidIds)[n - 1]].kind
	lk == nBreak or lk == nContinue

# whether name is a constant list, made once and kept in the data area: its parts are places
# a borrow may point into (immutable, so they never change while borrowed)
fn storedConstant(c Checker, name str):
	d = c.findDeclByGlobalName(nConstDecl, name) ?? return false
	not nodes[d].hasFlag(flagMut) and not nodes[d].kids(kidIds).isEmpty and
		c.tKind(typeOf(nodes, nodes[d].kids(kidIds)[0])) == tList

# calls to intrinsics whose result aliases memory the program does not own
fn isAliasCall(c Checker, e NodeId):
	if nodes[e].kind != nCall: return false
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind != nIdent: return false
	intrinsicAliases(nodes[callee].text)

# whether e is `xs.map(.name)` giving strs of the elements, lent
fn isLentMap(c Checker, e NodeId):
	if nodes[e].kind != nCall or nodes[e].kids(kidIds).len != 2: return false
	callee = nodes[e].kids(kidIds)[0]
	nodes[callee].kind == nField and nodes[callee].text == "map" and
		nodes[nodes[e].kids(kidIds)[1]].hasFlag(flagKeyLambda)

# whether call e is a list's find, minBy or maxBy giving a reference to an element (of the list
# the call reads: a filter before it gives a list of its own)
fn lendsElement(mut c Checker, e NodeId):
	callee = c.writtenCallee(e)
	nodes[callee].kind == nField and nodes[callee].text in ["find", "minBy", "maxBy"] and
		c.tKind(c.derefType(typeOf(nodes, nodes[callee].kids(kidIds)[0]))) == tList and
		c.isRefLike(typeOf(nodes, e))

# the list a chain of filters over it reads, as the backend runs them (fusedStages): in the
# loop of the step that consumes them, over that list's own elements
fn fusedSource(mut c Checker, e NodeId):
	at = e
	while fusableStep(nodes, kidIds, at) == "filter":
		inner = nodes[nodes[at].kids(kidIds)[0]].kids(kidIds)[0]
		k = c.tKind(c.derefType(typeOf(nodes, inner)))
		if k != tList and k != tArray: break
		at = inner
	at

# The sequence a loop or a pipeline over e reads while it runs: e itself, or, when e is a chain
# of map and filter steps with plain lambdas, the chain's source (the steps run in the loop that
# goes over it, see genForStages, with no list made between them).
fn steppedSource(mut c Checker, e NodeId):
	at = e
	while nodes[at].kind == nCall and nodes[at].kids(kidIds).len == 2:
		callee = nodes[at].kids(kidIds)[0]
		lam = nodes[at].kids(kidIds)[1]
		if nodes[callee].kind != nField or nodes[callee].kids(kidIds).len != 1 or
			(nodes[callee].text != "map" and nodes[callee].text != "filter"):
			break
		if nodes[lam].kind != nLambda or not nodes[lam].sub().isEmpty or
			nodes[lam].names().len != 1:
			break
		if nodes[callee].text == "map" and
			not c.isPlainType(typeOf(nodes, nodes[lam].kids(kidIds)[0])):
			break   # values that own memory: a list is made
		at = nodes[callee].kids(kidIds)[0]
	at

# a struct or a fixed array: a read parameter refers to the caller's place, even of plain data
fn passedByAddress(c Checker, t TypeId):
	c.tKind(t) == tStruct or c.tKind(t) == tArray

# the pipeline consumers that read their source's header (items and length) once, before any
# lambda runs, and never its place again
headerKeepingSteps = ["all", "any", "count", "find", "findIndex"]
