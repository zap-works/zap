# The lowering of pipelines that gather: sorting, reducing, finding, zipping and collecting (irLower.zap).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# the keys of xs's elements under the lambda, pushed onto a list (a temporary): the list's
# address, the keys', and the key type (a str key as a header that owns nothing); a range's
# values are pushed onto a list of their own (a temporary) beside their keys. Given k (a sort's
# first k), only the k first keys stay, `at` their elements' indices, and m.keys() or m.values()
# walk the map's cells in place (map the map's word, at the cells' numbers)
type IrKeys:
	list i64
	keys i64
	kt TypeId
	at i64 = -1
	map i64 = -1

fn irKeysOf(mut g Gen, mut lw IrLower, obj NodeId, lam NodeId, k i64 = 0) IrKeys?:
	body = nodes[lam].kids(kidIds)[0] if nodes[lam].sub(kidIds).isEmpty
		else nodes[
			nodes[nodes[lam].sub(kidIds)[0]].kids(kidIds)[
				nodes[nodes[lam].sub(kidIds)[0]].kids(kidIds).len - 1
			]
		].kids(kidIds)[0]
	kt = rangeBase(tys, g.ty(body))   # a range's keys: its base's
	windowKeys = g.isTextWindow(kt)
	if g.tyK(kt) == tRef and g.tyK(tys[kt].inner) == tStr:
		kt = tyStr
	strKeys = g.tyK(kt) == tStr
	if not strKeys and not g.irTakes(kt) and not g.irOwnedByAddress(kt):
		lw.irFail("sort keys of {typeStr(tys, kt)}")
		return none
	keys = g.irTemporary(lw, tyList(tys, kt))
	lw.irZeroBytes(keys, 24)
	at = -1
	if k > 0:
		at = g.irTemporary(lw, tyList(tys, tyInt(64, true)))
		lw.irZeroBytes(at, 24)
	cells = g.irMapCellsOf(obj) if k > 0 else none
	range = cells == none and (nodes[obj].kind == nRange or g.irGathersSteps(obj))   # gathered here
	elem = g.irStepsElem(obj)
	list = -1
	m = -1
	if cells is mapNode:
		word = g.irValue(lw, mapNode)
		if word.len != 1:
			lw.irFail("a map's word")
			return none
		m = word[0]
	elif range:
		list = g.irTemporary(lw, tyList(tys, elem))
		lw.irZeroBytes(list, 24)
	else:
		list = g.irListAddr(lw, obj)
	# steps walked again over their source, their values a list made apart: an element's index in
	# that list is the count of those met before it, not the source's counter
	counted = k > 0 and not range and m < 0 and g.irFusedStep(obj) != none
	seen = lw.irDef(irInt, IrInst(op = irConst, imm = 0)) if counted else -1
	each = g.irStepsBegin(lw, obj) if m < 0 else g.irMapWalkBegin(lw, cells ?? obj, m)
	if not lw.ok: return none
	owned = lw.owned.len
	mark = lw.names.len
	value = g.irMapWalkValue(lw, obj, m, each.counter) if cells != none else g.irEachValue(lw, each)
	if range:
		g.irPush(lw, list, elem, value)
	lw.keying += 1   # a key: compared, never kept (an element's str copied into it is read)
	outer = lw.borrowedKey
	if not range and nodes[lam].sub(kidIds).isEmpty and nodes[body].kind == nStructLit and
		g.irKeyBorrows(body):
		lw.borrowedKey = body
	key = g.irLambdaValue(lw, lam, value, true)
	lw.borrowedKey = outer
	lw.keying -= 1
	if not lw.ok: return none
	if strKeys:
		if key.len != 1:
			lw.irFail("a sort key")
			return none
	if strKeys and not lw.owned.any(.slot == key[0] and .name < 0):
		# a borrowed text (an element's, a field's): a header of its bytes that owns nothing (room 0),
		# so the keys list drops nothing; a temporary's text is pushed whole below (moved) instead
		header = lw.irWindowAsStr(key[0]) if windowKeys else lw.irBorrowedStr(key[0])
		lw.literals.push(header)   # pushed as it is: the keys list drops nothing of it
		key = [header]
	g.irPush(lw, keys, kt, key)
	if k > 0:
		i = lw.irDef(
			irInt,
			IrInst(op = irSub, a = lw.irHeader(list, 8), b = lw.irConstOf(irInt, 1))
		)
			if range else seen if counted else each.counter
		g.irRtInstanceValues(lw, "firstKeysKeep", [kt], [keys, at, i, lw.irConstOf(irInt, k)])
		if counted:
			lw.irPut(IrInst(op = irAdd, dst = seen, a = seen, b = lw.irConstOf(irInt, 1)))
	g.irScopeEnd(lw, mark)
	g.irDropTemporaries(lw, owned)
	g.irEachEnd(lw, each)
	IrKeys(list, keys, kt, at, map = m)

# the map whose cells m.keys() or m.values() (obj, the checker's call of rt__mapKeys or
# rt__mapValues) walks, or none
fn irMapCellsOf(mut g Gen, obj NodeId) NodeId?:
	if nodes[obj].kind != nCall or nodes[obj].kids(kidIds).len != 2: return none
	callee = nodes[obj].kids(kidIds)[0]
	if nodes[callee].kind != nIdent or not (nodes[callee].text in ["rt__mapKeys", "rt__mapValues"]):
		return none
	m = nodes[obj].kids(kidIds)[1]
	m if g.tyK(g.ty(m)) == tMap else none

# a loop over the cells of map m (its word), its counter the cell's number, the body entered
# only for a live cell
fn irMapWalkBegin(mut g Gen, mut lw IrLower, mapNode NodeId, m i64):
	mt = g.ty(mapNode)
	types = [innerOf(tys, mt), valOf(tys, mt)]
	n = g.irRtInstanceValues(lw, "mapEntryCount", types, [m])
	each = IrEach(
		shell = IrShell(pre = -1, body = -1, cont = -1, end = -1),
		counter = lw.f.irVreg(irInt),
		n = n[0] if n.len == 1 else -1,
		ptr = -1,
		elem = tyInt(64, true)
	)
	if not lw.ok: return each
	lw.irPut(IrInst(op = irConst, dst = each.counter, imm = 0))
	each.shell = lw.f.irShell()
	lw.irBranchIf(each.counter, irLt, each.n, each.shell.body, each.shell.end)
	lw.f.irEnterBody(each.shell)
	alive = g.irRtInstanceValues(lw, "mapEntryAlive", types, [m, each.counter])
	if not lw.ok or alive.len != 1: return each
	live = lw.f.irBlock()
	lw.irBranchNZ(alive[0], live, each.shell.cont)
	lw.f.irEnter(live)
	each

# the element of m.keys() or m.values() (obj) in the map's cell i, borrowed: a window key made
# again, else read where the cell keeps it
fn irMapWalkValue(mut g Gen, mut lw IrLower, obj NodeId, m i64, i i64) i64[]:
	mt = g.ty(nodes[obj].kids(kidIds)[1])
	types = [innerOf(tys, mt), valOf(tys, mt)]
	keys = nodes[nodes[obj].kids(kidIds)[0]].text == "rt__mapKeys"
	t = types[0] if keys else types[1]
	if keys and g.isTextWindow(t): return g.irRtInstanceValues(lw, "textKeyAt", types, [m, i])
	place = g.irRtInstanceValues(lw, "mapKeyPlace" if keys else "mapValPlace", types, [m, i])
	if not lw.ok or place.len != 1: return []
	g.irLoadValue(lw, t, place[0], -1, 0)

# The parts of the key lambda lam that sortBy makes again at each comparison instead of keeping
# a list of keys (listSortByParts): its tuple's fields (up to three) or its value, each a number
# or a str, and each cheap: no work outside, no allocation, no loop, borrowing only what
# outlives the sort (irKeyBorrows), calling only the program's functions; none when one is not
fn irKeyParts(mut g Gen, lam NodeId):
	if nodes[lam].kind != nLambda or not nodes[lam].sub(kidIds).isEmpty or
		nodes[lam].names(kidIds).len != 1 or
		"self" in nodes[lam].names2(kidIds):
		return []
	body = nodes[lam].kids(kidIds)[0]
	tuple = g.c.isTupleLiteral(body)
	if nodes[body].kind == nStructLit and not tuple: return []
	parts = nodes[body].kids(kidIds).copy() if tuple else [body]
	if parts.len > 3 or
		not parts.all(g.irKeyPartType(it) != none and g.irKeyBorrows(it) and g.irCheapPart(it)):
		return []
	parts

# the type a key part is compared as: a number's, or str for a text (borrowed); none for others
fn irKeyPartType(mut g Gen, part NodeId) TypeId?:
	t = rangeBase(tys, g.ty(part))
	if g.tyK(t) == tInt or g.tyK(t) == tFloat: return t
	if g.tyK(t) == tStr or g.tyK(t) == tRef and g.tyK(tys[t].inner) == tStr: return tyStr
	none

# what a key part may not do, made at every comparison
costlyDoings = doesImpure | doesAllocate | doesWait | doesEndless | doesPrint | doesReadProgram

# whether the key part e costs about as little as reading a kept key: names, fields, numbers'
# operators, indexes of lists and texts, conversions and the program's functions that do none of
# costlyDoings
fn irCheapPart(mut g Gen, e NodeId) bool:
	k = nodes[e].kind
	if nodes[e].hasFlag(flagClosure) or k == nIdent and nodes[e].hasFlag(flagModuleVar):
		return false
	if k == nCall:
		callee = nodes[e].kids(kidIds)[0]
		if nodes[callee].kind != nIdent: return false
		if primType(nodes[callee].text) == none:   # not a conversion: the program's function
			fnd = g.c.findFunc(nodes[callee].text, nameOf(nodes, callee)) ?? return false
			if nodes[fnd].mod(kidIds) == "rt" or g.c.fnDoes(fnd) & costlyDoings != 0: return false
	elif k == nIndex:
		if not (g.tyK(g.c.derefType(g.ty(nodes[e].kids(kidIds)[0]))) in [tList, tStr, tArray]):
			return false
	elif k == nBinary:
		# numbers' operators (no text's or list's comparison, no membership)
		if nodes[e].ival in [binIn, binMatmul, binCoalesce] or
			nodes[e].kids(kidIds).any(g.irClassOf(g.ty(it)) < 0):
			return false
	elif k == nUnary:
		if nodes[e].ival in [unMove, unMutRef, unOut]: return false
	elif not (
		k in [nInt, nFloat, nBool, nStr, nIdent, nField, nStructLit, nRange, nDeref, nNamedArg]
	):
		return false
	nodes[e].kids(kidIds).all(g.irCheapPart(it)) and nodes[e].sub(kidIds).all(g.irCheapPart(it))

# whether making the key part e may stop the program (a failed check, an overflow)
fn irPartMayStop(mut g Gen, e NodeId) bool:
	if g.c.walkingRuntime() or g.c.stopFact(e) != "": return true
	if nodes[e].kind == nCall and primType(nodes[nodes[e].kids(kidIds)[0]].text) == none:
		fnd = g.c.findFunc(nodes[nodes[e].kids(kidIds)[0]].text) ?? return true
		if g.c.fnDoes(fnd) & doesStop != 0: return true
	nodes[e].kids(kidIds).any(g.irPartMayStop(it)) or nodes[e].sub(kidIds).any(g.irPartMayStop(it))

# a key part's value where a comparison reads it: a number's leaves, or a str's header that
# owns nothing (the bytes it borrows)
fn irKeyPartValue(mut g Gen, mut lw IrLower, part NodeId):
	at = lw.owned.len
	lw.keyParts += 1
	value = g.irValue(lw, part)
	lw.keyParts -= 1
	if not lw.ok: return []
	t = g.ty(part)
	if g.irKeyPartType(part) != tyStr or value.len != 1:
		g.irDropTemporaries(lw, at)
		return value
	header = lw.irWindowAsStr(value[0]) if g.isTextWindow(t) else lw.irBorrowedStr(value[0])
	lw.literals.push(header)   # given as it is: nothing of it is dropped
	g.irDropTemporaries(lw, at)
	[header]

# the names of this code lam's parts read, noted as its captures (a key lambda's check lists
# none: it runs where it is written) and lent by pointer, the lambda now given to the sort;
# false when a part reads a name this code does not hold (a field of self named bare)
fn irNoteKeyCaptures(mut g Gen, lw IrLower, lam NodeId, parts NodeId[]):
	g.irMark(lam, flagBorrowLambda)
	if not nodes[lam].names2(kidIds).isEmpty: return true   # (noted by a lowering before)
	if parts.all(g.irNoteNamesRead(lw, lam, it)): return true
	nodes[lam].nodeMore(kidIds).names2.clear()
	nodes[lam].nodeMore(kidIds).ints.clear()
	false

fn irNoteNamesRead(mut g Gen, lw IrLower, lam NodeId, e NodeId) bool:
	k = nodes[e].kind
	if k == nIdent and not nodes[e].hasFlag(flagFnRef) and
		nodes[e].text != nodes[lam].names(kidIds)[0] and
		not (nodes[e].text in nodes[lam].names2(kidIds)):
		if not lw.irInScopeNo(nameOf(nodes, e)): return false
		nodes[lam].nodeMore(kidIds).names2.push(nodes[e].text.copy())
		nodes[lam].nodeMore(kidIds).ints.push(g.ty(e))
	kids = nodes[e].kidsFrom(kidIds, 1).copy() if k == nCall else nodes[e].kids(kidIds).copy()   # (a callee is a function)
	kids.all(g.irNoteNamesRead(lw, lam, it)) and
		nodes[e].sub(kidIds).copy().all(g.irNoteNamesRead(lw, lam, it))

# xs.sortBy(f) by the parts of its key made at each comparison (listSortByParts<T, K...>(xs,
# part..., made), each part the lambda given in place), when irKeyParts finds them; none when not
fn irSortByParts(mut g Gen, mut lw IrLower, obj NodeId, lam NodeId) i64[]?:
	parts = g.irKeyParts(lam)
	if parts.isEmpty or g.irMentions(lam, g.irRootName(obj)):
		return none   # (a key that reads the list would read it while its elements move)
	if not g.irNoteKeyCaptures(lw, lam, parts): return none
	held = g.irHeldOf(lw, lam)
	caps i64[,] = []
	for ci in 0..nodes[lam].names2(kidIds).len:
		caps.push(
			[] if held.any(.at == ci) else lw.irLookup(nodes[lam].names2(kidIds)[ci]) ?? return none
		)
	name = "listSortByParts"
	targs = [innerOf(tys, g.irListType(obj))]
	for i in 0..3:
		targs.push(try g.irKeyPartType(parts[i if i < len else 0]))
	mangle = g.rtMangle(name, targs)
	ii = try g.c.findInstance(g.rtDecl(name), mangle)
	decl = g.c.instances[ii].decl
	givens = []
	for i in 0..3:
		part = i if i < parts.len else 0
		givens.push(
			IrGiven(
				at = 1 + i,
				node = lam,
				site = lw.site.copy(),
				held = held.copy(),
				caps = caps.copy(),
				part
			)
		)
	made = parts.any(g.irPartMayStop(it))
	vs = [g.irListAddr(lw, obj)]
	for given in givens:
		vs.push(g.irGivenClosureWord(lw, given))
	vs.push(lw.irConstOf(irInt, parts.len))
	vs.push(lw.irConstOf(irInt, 1 if made else 0))
	sav = move g.c.subst
	g.c.subst = g.c.instances[ii].sub.copy()
	out = []
	if g.irCallable(decl, true):
		out = g.irCallValuesWith(
			lw,
			decl,
			g.irGivenKey("rt__{name}_{mangle}", decl, givens, none, none),
			-1,
			vs
		)
	else:
		lw.irFail("generic call of {name}")
	g.c.subst = sav
	out

# whether the key e owns nothing it makes: what owns memory in it is a name (the element, a
# capture), a field of one, or a borrow of such values, all outliving the sort, so the strs of a
# key's struct literal can borrow their bytes instead of copying them (the elements stay put
# while the keys are compared)
fn irKeyBorrows(mut g Gen, e NodeId) bool:
	k = nodes[e].kind
	if k == nIdent: return true
	if k == nLambda: return false
	if k != nNamedArg and g.irClassOf(g.ty(e)) >= 0: return true   # a number holds no borrow
	if k in [nStructLit, nField, nDeref, nNamedArg] or g.tyK(g.ty(e)) == tRef:
		return nodes[e].kids(kidIds).all(g.irKeyBorrows(it)) and
			nodes[e].sub(kidIds).all(g.irKeyBorrows(it))
	false

# xs.sortedBy(f): the keys, then the runtime's listSortByKeys<T, K>(xs, move keys) makes the
# sorted copy; `.slice(0, k)` fused by the checker (flagFirstK, k in ival) keeps the first k as
# the keys come (a map's keys or values picked from its cells), a `.parallel()` sorts in parts
fn irSortedBy(mut g Gen, mut lw IrLower, e NodeId, obj NodeId, lam NodeId) i64[]:
	if nodes[e].hasFlag(flagFirstK):
		first = nodes[e].ival
		f = g.irKeysOf(lw, obj, lam, first) ?? return []
		count = lw.irConstOf(irInt, first)
		if f.map >= 0:
			mt = g.ty(nodes[obj].kids(kidIds)[1])
			keys = nodes[nodes[obj].kids(kidIds)[0]].text == "rt__mapKeys"
			picker = "mapKeysPicked" if keys else "mapValuesPicked"
			mtypes = [innerOf(tys, mt), valOf(tys, mt), f.kt]
			return g.irRtInstanceValues(lw, picker, mtypes, [f.map, f.keys, f.at, count])
		ftypes = [g.irSourceElem(obj), f.kt]
		return g.irRtInstanceValues(lw, "firstKeysPicked", ftypes, [f.list, f.keys, f.at, count])
	k = g.irKeysOf(lw, obj, lam) ?? return []
	types = [g.irSourceElem(obj), k.kt]
	if g.irGathersSteps(obj) and not nodes[e].hasFlag(flagParallelSort):
		# the steps' values were gathered into a list of the statement's: sorted in place, it is
		# the result
		g.irRtInstanceValues(lw, "listSortBy", types, [k.list, k.keys])
		return [k.list]
	irRtInstanceValues(
		g,
		lw,
		"listSortByKeysParallel" if nodes[e].hasFlag(flagParallelSort) else "listSortByKeys",
		types,
		[k.list, k.keys]
	)

# xs.maxBy(f), xs.minBy(f): the keys, the runtime's index of the extreme one (-1 of no element),
# the element's address as an optional reference (a range's: the value, an optional)
fn irExtremeBy(mut g Gen, mut lw IrLower, max bool, et TypeId, obj NodeId, lam NodeId):
	k = g.irKeysOf(lw, obj, lam) ?? return []
	idx = g.irRtInstanceValues(lw, "keysMaxIndex" if max else "keysMinIndex", [k.kt], [k.keys])
	if not lw.ok or idx.len != 1: return []
	tag = lw.irDef(irInt, IrInst(op = irSet, a = idx[0], b = lw.irConstOf(irInt, 0), cond = irGe))
	elem = g.irSourceElem(obj)
	items = lw.irHeader(k.list, 0)
	if nodes[obj].kind == nRange:
		# the value read only when there is one: an empty list has no items
		v = lw.irDef(irInt, IrInst(op = irConst, imm = 0))
		way = lw.irSplitNZ(tag, false)
		read = g.irLoadValue(lw, elem, items, idx[0], g.c.elemStride(elem))
		lw.irPut(IrInst(op = irCopy, dst = v, a = read[0]))
		lw.f.irJoin(way.end)
		return g.irOptionOf(lw, et, tag, v)
	at = lw.irElementAddr(items, idx[0], g.c.elemStride(elem), 0)
	if g.irIsLeafOption(et): return g.irOptionOf(lw, et, tag, at)
	# a window to the element (ref str): the optional in a slot, the window's words copied in
	# when there is one
	ot = et
	slot = g.irZeroedSlot(lw, ot)
	way = lw.irSplitNZ(tag, false)
	g.irStoreWindowOf(lw, g.irSomeAt(lw, ot, slot), elem, at)
	lw.f.irJoin(way.end)
	[slot]

# xs.reduce(init, (acc, x) => ...) over values of leaves: the accumulator's leaves assigned the
# lambda's value each turn
fn irReduce(mut g Gen, mut lw IrLower, e NodeId, obj NodeId, init NodeId, lam NodeId):
	acc = g.irNewValue(lw, g.ty(e))
	lw.irCopyValue(acc, g.irAs(lw, g.irValue(lw, init), g.ty(e)))
	each = g.irStepsBegin(lw, obj)   # maps and filters before it in its loop
	if not lw.ok: return []
	at = lw.owned.len
	mark = lw.names.len
	lw.irDeclare(nodes[lam].names(kidIds)[0], acc.copy())
	lw.irDeclare(nodes[lam].names(kidIds)[1], g.irEachValue(lw, each))
	value = g.irLambdaBody(lw, lam, true)
	if not lw.ok: return []
	lw.irCopyValue(acc, g.irAs(lw, value, g.ty(e)))
	g.irScopeEnd(lw, mark)
	g.irDropTemporaries(lw, at)
	g.irEachEnd(lw, each)
	acc

# a one-parameter lambda's test of value: to yesB when it holds, else to noB
fn irLambdaTest(mut g Gen, mut lw IrLower, lam NodeId, value i64[], yesB i64, noB i64):
	mark = lw.names.len
	if nodes[lam].kind != nLambda:
		c = g.irLambdaValue(lw, lam, value, true)   # a function by name or as a value
		if not lw.ok: return
		lw.irBranchNZ(c[0], yesB, noB)
		return
	lw.irDeclare(nodes[lam].names(kidIds)[0], value.copy())
	if nodes[lam].sub(kidIds).isEmpty:
		# a condition of its own, even inside another's: what it makes is dropped every turn
		conditions = lw.conditions
		lw.conditions = 0
		g.irCond(lw, nodes[lam].kids(kidIds)[0], yesB, noB)
		lw.conditions = conditions
	else:
		c = g.irLambdaBody(lw, lam, true)
		if c.len != 1:
			lw.irFail("a lambda's value")
			return
		lw.irBranchNZ(c[0], yesB, noB)
	g.irScopeEnd(lw, mark)

# xs.find(p) (a reference to the first element p holds for, or of a range the number) and
# xs.findIndex(p) of a list: a loop that stops at the first; an optional's tag and value
fn irFindEach(mut g Gen, mut lw IrLower, m str, e NodeId, obj NodeId, lam NodeId):
	tag = lw.f.irVreg(irInt)
	found = lw.f.irVreg(irInt)
	lw.irPut(IrInst(op = irConst, dst = tag, imm = 0))
	lw.irPut(IrInst(op = irConst, dst = found, imm = 0))
	each = g.irEachBegin(lw, obj)
	if not lw.ok: return []
	element = g.irEachValue(lw, each)
	yesB = lw.f.irBlock()
	g.irLambdaTest(lw, lam, element, yesB, each.shell.cont)
	lw.f.irEnter(yesB)
	lw.irPut(IrInst(op = irConst, dst = tag, imm = 1))
	held = each.counter if m == "findIndex" or each.ptr < 0
		else each.ptr if g.tyK(tys[g.ty(e)].inner) == tRef
		else element[0]
	lw.irPut(IrInst(op = irCopy, dst = found, a = held))
	lw.f.irJumpTo(each.shell.end)
	g.irEachEnd(lw, each)
	if g.c.isNicheOption(g.ty(e)): return [found]   # the element's address, 0 when none matched
	[tag, found]

# xs.find(p) of elements by address whose result is an optional window (ref str? of a str[]):
# a tagged optional in a slot of the statement, the found element's first two words its window
fn irFindWindow(mut g Gen, mut lw IrLower, e NodeId, obj NodeId, lam NodeId):
	t = g.ty(e)
	slot = g.irZeroedSlot(lw, t)
	g.irMarkNone(lw, t, slot)
	each = g.irEachBegin(lw, obj)
	if not lw.ok: return []
	element = g.irEachValue(lw, each)
	yesB = lw.f.irBlock()
	g.irLambdaTest(lw, lam, element, yesB, each.shell.cont)
	lw.f.irEnter(yesB)
	g.irStoreWindowOf(lw, g.irSomeAt(lw, t, slot), g.irSourceElem(obj), element[0])
	lw.f.irJumpTo(each.shell.end)
	g.irEachEnd(lw, each)
	[slot]

# whether e is xs.map(f) or xs.filter(p) of a source, of values irGather pushes
fn irIsGather(mut g Gen, e NodeId):
	if nodes[e].kind != nCall or nodes[e].kids(kidIds).len != 2 or
		nodes[nodes[e].kids(kidIds)[0]].kind != nField:
		return false
	m = nodes[nodes[e].kids(kidIds)[0]].text
	et = g.ty(e)
	(m == "map" or m == "filter") and
		g.irIsSource(nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0]) and
		g.irIsLambda1(nodes[e].kids(kidIds)[1]) and g.tyK(et) == tList and
		(
			g.irTakes(tys[et].inner) or g.irOwnedByAddress(innerOf(tys, et)) or
				(g.irByAddress(tys[et].inner) and not g.isOwningType(innerOf(tys, et)))
		)

# the name a place starts from (xs of xs[i].f), or ""
fn irRootName(g Gen, e NodeId):
	at = e
	while (nodes[at].kind == nField or nodes[at].kind == nIndex) and
		not nodes[at].kids(kidIds).isEmpty:
		at = nodes[at].kids(kidIds)[0]
	nodes[at].text.copy() if nodes[at].kind == nIdent else ""

# whether the name appears under e ("" appears everywhere)
fn irMentions(g Gen, e NodeId, name str) bool:
	name == "" or nodes[e].kind == nIdent and nodes[e].text == name or
		nodes[e].kids(kidIds).any(g.irMentions(it, name)) or
		nodes[e].sub(kidIds).any(g.irMentions(it, name))

# xs.map(f), xs.filter(p) and xs.sum() of a source: a new list (a temporary) with room for every
# element, each lambda's value pushed (map), each element its lambda keeps (filter), or every
# element (a Seq's toList, lam -1); or the elements added up (sum). With into, the values are
# pushed onto the list at that address instead (an extend), and nothing is given.
fn irGather(
	mut g Gen,
	mut lw IrLower,
	m str,
	e NodeId,
	obj NodeId,
	lam NodeId?,
	into i64 = -1
):
	t = g.ty(e)
	if m == "sum":
		total = lw.f.irVreg(g.irClassOf(t))
		lw.irPut(IrInst(op = irConst, dst = total, imm = 0))
		each = g.irEachBegin(lw, obj)
		if not lw.ok: return []
		v = g.irEachValue(lw, each)
		irPut(
			lw,
			IrInst(
				op = irFAdd if g.irClassOf(t) == irFloat else irAdd,
				dst = total,
				a = total,
				b = v[0],
				trap = g.irClassOf(t) == irInt and g.irStopsOnOverflow(t)
			)
		)
		g.irEachEnd(lw, each)
		return [g.irFits(lw, total, t)]
	elem = innerOf(tys, t)
	out = into if into >= 0 else g.irTemporary(lw, t)
	if into < 0:
		lw.irTakeKept(out, t)
	# source.filter(p).map(f): the filter runs in the map's loop, so the mapped
	# values (windows into the elements) point into the source, not into a list that goes
	src = obj
	pred NodeId? = none
	if m == "map" and g.irFilterCallOf(obj) is (source, p):
		src = source
		pred = p
	# a map's output made to hold every element first, when each turn gives one
	room = out if m == "map" and into < 0 and pred == none and g.irKeepsEveryTurn(src) else -1
	each = g.irStepsBegin(lw, src, room, g.c.elemStride(elem))   # maps and filters before it in its loop: no list between
	if not lw.ok: return []
	at = lw.owned.len
	mark = lw.names.len
	element = g.irEachValue(lw, each)
	if m == "map":
		skipB = -1
		if pred is pred:
			keep = g.irLambdaValue(lw, pred, element, true)
			if not lw.ok or keep.len != 1: return []
			g.irDropTemporaries(lw, at)   # the predicate's own, before the paths part
			skipB = lw.irSplitNZ(keep[0], false).end
		value = g.irLambdaValue(
			lw,
			lam ?? return lw.irRefused("a map without its lambda"),
			element,
			true
		)
		if g.isTextWindow(elem) and value.len == 1 and
			nodes[lam ?? return []].hasFlag(flagKeyLambda):
			value = [lw.irStrAsWindow(value[0])]   # a str of the element, lent (`ms.map(.name)`)
		if g.irIsOwnedWord(elem) and value.len == 1:
			value = [g.irWordTaken(lw, elem, value[0])]   # a map the list owns from now on
		if room >= 0:
			g.irPushInRoom(lw, out, elem, value)
		else:
			g.irPush(lw, out, elem, value)
		if pred != none:
			g.irDropTemporaries(lw, at)   # the step's own, on the path that made them
			lw.f.irJoin(skipB)
	else:
		noB = -1
		if lam is lam:
			keep = g.irLambdaValue(lw, lam, element, true)
			if keep.len != 1: return lw.irRefused("a filter's value")
			noB = lw.irSplitNZ(keep[0], false).end
		kept = element.copy()
		if g.irOwnedByAddress(elem):
			copy = g.irTemporary(lw, elem)   # the source list keeps its own
			lw.irPut(IrInst(op = irDeepCopy, a = copy, b = element[0], ty = elem))
			kept = [copy]
		g.irPush(lw, out, elem, kept)
		if noB < 0:
			noB = lw.f.irBlock()
		lw.f.irJoin(noB)
	g.irScopeEnd(lw, mark)
	g.irDropTemporaries(lw, at)   # the step's own temporaries, every turn
	g.irEachEnd(lw, each)
	[] if into >= 0 else [out]

# `source.filter(p)` as a pipeline's source: the source and the predicate, or none
fn irFilterCallOf(mut g Gen, e NodeId) (NodeId, NodeId)?:
	if nodes[e].kind != nCall or nodes[e].kids(kidIds).len != 2: return none
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind != nField or nodes[callee].text != "filter" or
		not g.irIsLambda1(nodes[e].kids(kidIds)[1]) or
		not g.irIsSource(nodes[callee].kids(kidIds)[0]):
		return none
	(nodes[callee].kids(kidIds)[0], nodes[e].kids(kidIds)[1])

# whether e is a source, or map and filter steps over one that a consumer runs in its own loop
fn irIsSteps(mut g Gen, e NodeId):
	g.irIsSource(e) or g.irFusedStep(e) != none

# `source.filter(p)` or `source.map(f)` of numbers (a list typed, its source a step's or a
# source), which the step consuming it runs in its loop: the source, the lambda and whether it
# filters; none otherwise
fn irFusedStep(mut g Gen, e NodeId) (NodeId, NodeId, bool)?:
	step = fusableStep(nodes, kidIds, e)
	if step == "" or g.tyK(g.ty(e)) != tList: return none
	src = nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0]
	if step == "map" and g.irClassOf(tys[g.ty(e)].inner) < 0 or not g.irIsSteps(src): return none
	(src, nodes[e].kids(kidIds)[1], step == "filter")

# The walk of the steps e is (irIsSteps): its source's, each map's value and each filter's test
# made in the turn, so the element the consumer gets is the steps' (a filtered one goes on to
# the next) and no list is made between them; room as irEachBegin's (irKeepsEveryTurn)
fn irStepsBegin(mut g Gen, mut lw IrLower, e NodeId, room i64 = -1, stride i64 = 1) IrEach:
	if g.irFusedStep(e) is (src, lam, filter):
		each = g.irStepsBegin(lw, src, room, stride)
		if not lw.ok: return each
		value = g.irEachValue(lw, each)
		at = lw.owned.len
		mark = lw.names.len
		made = g.irLambdaValue(lw, lam, value, true)
		g.irScopeEnd(lw, mark)
		if not lw.ok or made.len != 1:
			lw.irFail("a step's value")
			return each
		each.given = true
		if not filter:
			each.value = made
			return each
		g.irDropTemporaries(lw, at)   # the test's own, before the paths part
		keptB = lw.f.irBlock()
		lw.irBranchNZ(made[0], keptB, each.shell.cont)
		lw.f.irEnter(keptB)
		each.value = value
		return each
	g.irEachBegin(lw, e, room, stride)

# whether the steps e give an element every turn of their source, a source whose turns are
# counted before it runs (no filter among them, no Seq)
fn irKeepsEveryTurn(mut g Gen, e NodeId) bool:
	if g.irFusedStep(e) is (src, _, filter): return not filter and g.irKeepsEveryTurn(src)
	g.tyK(g.ty(e)) != tSeq

# the type of the elements the steps e give
fn irStepsElem(mut g Gen, e NodeId):
	if nodes[e].kind == nRange: return g.ty(nodes[e].kids(kidIds)[0])
	t = g.ty(e)
	innerOf(tys, tys[t].inner if g.tyK(t) == tRef else t)

# a value passed to a runtime function by one word: an aggregate's leaves lent from a slot
fn irOneWord(mut g Gen, mut lw IrLower, t TypeId, value i64[]):
	if g.irIsAggregate(t) or g.irIsOption(t): return g.irLentCopy(lw, t, value)
	if value.len != 1:
		lw.irFail("a value of {typeStr(tys, t)} in one word")
		return -1
	value[0]

# steps.mean() of f64s: their sum over their count (NaN of none), added in their order
fn irMean(mut g Gen, mut lw IrLower, obj NodeId):
	total = lw.irDef(irFloat, IrInst(op = irConst, imm = 0))
	count = lw.irDef(irInt, IrInst(op = irConst, imm = 0))
	each = g.irStepsBegin(lw, obj)
	if not lw.ok: return []
	v = g.irEachValue(lw, each)
	lw.irPut(IrInst(op = irFAdd, dst = total, a = total, b = v[0]))
	lw.irPut(IrInst(op = irAdd, dst = count, a = count, b = lw.irConstOf(irInt, 1)))
	g.irEachEnd(lw, each)
	n = lw.irDef(irFloat, IrInst(op = irIntToFloat, a = count))
	mean = lw.irDef(irFloat, IrInst(op = irFDiv, a = total, b = n))
	[mean]

# steps.groupBy(key) and steps.countBy(key): a new map, each element's key made in the turn and
# the element copied into its group (mapGroupAdd) or counted (mapAdd)
fn irCollectBy(mut g Gen, mut lw IrLower, m str, e NodeId, obj NodeId, lam NodeId):
	t = g.ty(e)
	kt = innerOf(tys, t)
	vt = valOf(tys, t)
	if not g.irMapPart(kt): return lw.irRefused("{m} by a key of {typeStr(tys, kt)}")
	groups = g.irRtInstanceValues(lw, "mapNew", [kt, vt], [])
	if not lw.ok or groups.len != 1: return []
	each = g.irStepsBegin(lw, obj)
	if not lw.ok: return []
	at = lw.owned.len
	mark = lw.names.len
	element = g.irEachValue(lw, each)
	lw.keying += 1
	key = g.irOneWord(lw, kt, g.irLambdaValue(lw, lam, element, true))
	lw.keying -= 1
	if not lw.ok: return []
	if m == "countBy":
		irRtInstanceValues(
			g,
			lw,
			"mapAdd",
			[kt, vt],
			[groups[0], key, lw.irConstOf(irInt, 1)]
		)
	else:
		elem = g.irStepsElem(obj)
		x = g.irOneWord(lw, elem, element)
		if not lw.ok: return []
		g.irRtInstanceValues(lw, "mapGroupAdd", [kt, elem], [groups[0], key, x])
	g.irScopeEnd(lw, mark)
	g.irDropTemporaries(lw, at)
	g.irEachEnd(lw, each)
	groups

# steps.zip(ys): a new list of the pairs of each element and ys's at its index, copied
# (listZipPush), the walk left where ys ends
fn irZip(mut g Gen, mut lw IrLower, e NodeId, obj NodeId, ysE NodeId):
	t = g.ty(e)
	out = g.irTemporary(lw, t)
	ys = g.irListAddr(lw, ysE)
	if not lw.ok: return []
	n = lw.irHeader(ys, 8)
	i = lw.irDef(irInt, IrInst(op = irConst, imm = 0))
	each = g.irStepsBegin(lw, obj)
	if not lw.ok: return []
	pairB = lw.f.irBlock()
	lw.irBranchIf(i, irLt, n, pairB, each.shell.end)
	lw.f.irEnter(pairB)
	elem = g.irStepsElem(obj)
	x = g.irOneWord(lw, elem, g.irEachValue(lw, each))
	if not lw.ok: return []
	g.irRtInstanceValues(
		lw,
		"listZipPush",
		[elem, innerOf(tys, g.irListType(ysE))],
		[out, x, ys, i]
	)
	lw.irPut(IrInst(op = irAdd, dst = i, a = i, b = lw.irConstOf(irInt, 1)))
	g.irEachEnd(lw, each)
	[out]

# source.flatMap(f): the elements of each list f makes, in order, moved into one list
fn irFlatMap(mut g Gen, mut lw IrLower, e NodeId, obj NodeId, lam NodeId):
	t = g.ty(e)
	out = g.irTemporary(lw, t)
	each = g.irEachBegin(lw, obj)
	if not lw.ok: return []
	at = lw.owned.len
	mark = lw.names.len
	part = g.irLambdaValue(lw, lam, g.irEachValue(lw, each), true)
	if not lw.ok or part.len != 1: return lw.irRefused("a flatMap's list")
	g.irRtInstanceValues(lw, "listAppend", [innerOf(tys, t)], [out, part[0]])
	g.irScopeEnd(lw, mark)
	g.irDropTemporaries(lw, at)
	g.irEachEnd(lw, each)
	[out]

# a.max(b), a.min(b): max keeps a when a >= b, min keeps a unless
# a > b (a NaN decides as the comparison does); integers by a conditional move
fn irMinMax(mut g Gen, mut lw IrLower, max bool, a i64, b i64, t TypeId):
	v = lw.f.irVreg(g.irClassOf(t))
	if g.irClassOf(t) == irInt:
		# max: a < b ? b : a; min: a > b ? b : a
		irPut(
			lw,
			IrInst(
				op = irSelect,
				dst = v,
				a,
				b,
				c = b,
				d = a,
				cond = irLt if max else irGt,
				uns = g.irUnsigned(t)
			)
		)
		return v
	keepB = lw.f.irBlock()
	takeB = lw.f.irBlock()
	endB = lw.f.irBlock()
	lw.irBranchIf(
		a,
		irGe if max else irGt,
		b,
		keepB if max else takeB,
		takeB if max else keepB
	)
	lw.f.irEnter(keepB)
	lw.irPut(IrInst(op = irCopy, dst = v, a))
	lw.f.irJumpTo(endB)
	lw.f.irEnter(takeB)
	lw.irPut(IrInst(op = irCopy, dst = v, a = b))
	lw.f.irJoin(endB)
	v

# the list type of e (through a reference)
