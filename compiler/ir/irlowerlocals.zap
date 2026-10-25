# The lowering of names bound in place, assignments, stores and if (irlower.zap).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

fn irBindNameAt(mut g Gen, mut lw IrLower, s NodeId, name str, valueNode NodeId, value i64[]):
	bare = nodes[s].canAssign()
	if bare and g.irFind(lw, name.copy()) is existing:
		g.irAssignValue(lw, existing, g.ty(valueNode), value)
		return
	if bare and g.irStoreThisField(lw, name.copy(), value): return
	if nodes[s].hasFlag(flagMut):
		lw.mutNames.push(lw.names.len)
	t = g.ty(valueNode)
	if (g.irIsWindow(t) or g.tyK(t) == tRef) and value.len == 1:
		lw.irDeclare(name, value.copy())   # a window: its two words where they are; a reference: the address
		return
	if g.irIsOption(t) and g.irIsOwnedWord(tys[t].inner) and value.len == 2 and
		value[1] not in lw.raw:
		# an optional map (or box): the local owns the table (a temporary's taken, a place's copied)
		oi = lw.irOwnedWordAt(value[1])
		if oi >= 0 and lw.owned[oi].name < 0:
			lw.irNameOwned(oi, lw.names.len, name)
			lw.irDeclare(name, value.copy())
			return
		w = g.irWordTaken(lw, innerOf(tys, t), value[1])
		g.irOwnedWord(lw, innerOf(tys, t), w)
		lw.irNameOwned(lw.owned.len - 1, lw.names.len, name)
		lw.irDeclare(name, [value[0], w])
		return
	if g.tyK(t) == tRef:
		t = innerOf(tys, t)
	if g.irBindNameAtBorrow(lw, s, name, valueNode, value, t): return
	g.irBindNameAtOwn(lw, s, name, valueNode, value, t)

fn irBindNameAtBorrow(
	mut g Gen,
	mut lw IrLower,
	s NodeId,
	name str,
	valueNode NodeId,
	value i64[],
	t TypeId
):
	if g.irByAddress(t) and g.isOwningType(t) and value.len == 1 and
		nodes[s].hasFlag(flagMut) and value[0] in lw.literals:
		# a literal a local will change: its header in a slot the local owns (its room 0: owning
		# nothing until changed, its drop frees nothing)
		slot = lw.irNewSlot(g.sizeOf(t))
		lw.irOwnBegin(IrOwned(slot, t, name = lw.names.len, key = name.copy()))
		lw.irPut(IrInst(op = irMemCopy, a = slot, b = value[0], imm = g.sizeOf(t)))
		lw.irDeclare(name, [slot])
		return true
	if value.len == 1 and g.irLetBorrows(lw, s, valueNode) and
		(g.irByAddress(t) or g.irIsOwnedWord(t)) and
		not lw.owned.any((.slot == value[0] or .word == value[0]) and .name < 0):
		lw.irDeclare(name, value.copy())   # the ownership pass's borrow: another name for the place's value
		return true
	if g.irByAddress(t) and g.isOwningType(t) and value.len == 1 and
		lw.owned.any(.slot == value[0] and .name >= 0):
		# another local's value moved in: a slot of its own, the old name left empty (its drop at
		# its last use frees nothing)
		slot = lw.irNewSlot(g.sizeOf(t))
		lw.irOwnBegin(IrOwned(slot, t, name = lw.names.len, key = name.copy()))
		g.irMoveTo(lw, slot, value[0], t)   # from a local: no temporary given up
		lw.irDeclare(name, [slot])
		return true
	if g.irByAddress(t) and value.len == 1 and
		lw.owned.findIndex(.slot == value[0] and .name < 0) is ti:
		# a temporary the statement made: it becomes the local (its slot, no copy), still the
		# region's blocks alone when nothing can change it
		region = lw.owned[ti].region and not nodes[s].hasFlag(flagMut)
		lw.irNameOwned(ti, lw.names.len, name)
		lw.owned[ti].region = region
		lw.irDeclare(name, value.copy())
		return true
	if g.irByAddress(t) and not g.isOwningType(t) and value.len == 1 and
		g.irIsPlaceNode(valueNode):
		# plain data read from a place: a copy of its own, as an assignment makes
		slot = lw.irNewSlot(g.sizeOf(t))
		lw.irPut(IrInst(op = irMemCopy, a = slot, b = value[0], imm = g.sizeOf(t)))
		lw.irDeclare(name, [slot])
		return true
	if not lw.irInRuntimeCode() and g.irByAddress(t) and value.len == 1 and
		value[0] in lw.literals and g.isOwningType(t) and
		not g.irIsPlaceNode(valueNode) and not lw.irOwns(value[0]):
		# a literal: the local's (its drop frees nothing), so giving it away is seen
		lw.irOwnBegin(IrOwned(slot = value[0], t, name = lw.names.len, key = name.copy()))
		lw.irDeclare(name, value.copy())
		return true
	if g.irByAddress(t) and value.len == 1 and not nodes[s].hasFlag(flagMut) and
		nodes[valueNode].kind == nMatch and g.irMatchLends(lw, valueNode) and
		not lw.irOwns(value[0]):
		lw.irDeclare(name, value.copy())   # a choice of places: a borrow of the one it picks
		return true
	false

fn irBindNameAtOwn(
	mut g Gen,
	mut lw IrLower,
	s NodeId,
	name str,
	valueNode NodeId,
	value i64[],
	t TypeId
):
	ownsPlace = nodes[s].hasFlag(flagMut) and g.irOwnedByAddress(t) and g.irIsPlaceNode(valueNode)
	if g.irByAddress(t) and value.len == 1 and not ownsPlace and
		(g.irIsPlaceNode(valueNode) or value[0] in lw.literals or value[0] in lw.made):
		lw.irDeclare(name, value.copy())   # a borrow of a place (or a literal): another name for it
		return
	if g.irIsOwnedWord(t) and value.len == 1:
		oi = lw.irOwnedWordAt(value[0])
		if oi < 0 and value[0] in lw.raw:
			lw.irDeclare(name, value.copy())   # raw: the local owns nothing either
			return
		if oi < 0 and g.c.copiesFreely(t):
			w = g.irWordCopied(lw, t, value[0])   # a shared value: one more owner
			g.irOwnedWord(lw, t, w)
			lw.irNameOwned(lw.owned.len - 1, lw.names.len, name)
			lw.irDeclare(name, [w])
			return
		if oi < 0:
			lw.irFail("a map bound, not owned here")
			return
		if lw.owned[oi].name >= 0:
			# another local's moved in: the word in a vreg of its own, so the old name's last use
			# (which drops nothing: its value went) does not find this entry
			w = lw.irDef(irInt, IrInst(op = irCopy, a = value[0]))
			lw.owned[oi].word = w
			lw.irNameOwned(oi, lw.names.len, name)
			lw.irDeclare(name, [w])
			return
		lw.irNameOwned(oi, lw.names.len, name)   # a temporary's map (or box) is the local's
		lw.irDeclare(name, value.copy())
		return
	if g.irOwnedByAddress(t) and value.len == 1:
		# a borrow (a temporary's field, a parameter's value): the local gets a copy of its own,
		# or the value is taken out of its place (the ownership check decides)
		slot = g.irTemporary(lw, t)
		place = lw.places.get(value[0]) ?? ""
		irPut(
			lw,
			IrInst(
				op = irDeepCopy,
				a = slot,
				b = value[0],
				ty = t,
				cond = 0 if lw.irInRuntimeCode() or lw.keying > 0 else 3 if name.startsWith("$tuple") else 2 if nodes[s].hasFlag(flagMut) else 1,
				key = "{name}\t{place}" if nodes[s].hasFlag(flagMut) else place.copy()
			)
		)
		lw.irNameOwned(lw.owned.len - 1, lw.names.len, name)
		lw.irDeclare(name, [slot])
		return
	if not g.irTakes(t):
		lw.irFail("let of type {typeStr(tys, t)}")
		return
	leaves = g.irNewValue(lw, t)
	lw.irCopyValue(leaves, value)
	lw.irDeclare(name, leaves)

fn irAssign(mut g Gen, mut lw IrLower, s NodeId):
	if g.irInPlaceStep(lw, nodes[s].kids(kidIds)[0], nodes[s].kids(kidIds)[1]):
		g.irNoteChange(lw, nodes[s].kids(kidIds)[0])
		return
	value = g.irValue(lw, nodes[s].kids(kidIds)[1])   # first: a call in it may move what holds the place
	g.irStoreTo(lw, nodes[s].kids(kidIds)[0], value)
	g.irNoteChange(lw, nodes[s].kids(kidIds)[0])
	target = nodes[s].kids(kidIds)[0]
	if nodes[target].kind == nIndex and
		g.c.holdsRefs(g.c.derefType(typeOf(nodes, nodes[target].kids(kidIds)[0]))):
		g.irKeepsRefs(lw, nodes[target].kids(kidIds)[0], nodes[s].kids(kidIds)[1])

# `xs = xs.filter(p)`, `xs = xs.map(f)` and `xs = xs.sortedBy(k)` of a list the lambda does not
# read: the old list is the place's own and dies here, so the step works in it, nothing allocated
# (Perceus's reuse): a filter keeps its elements moved down and drops the others, a map writes
# each value over the element it was made from, a sort sorts the list where it is
fn irInPlaceStep(mut g Gen, mut lw IrLower, target NodeId, call NodeId):
	if g.irReplaceInPlace(lw, target, call): return true
	if nodes[call].kind != nCall or nodes[call].kids(kidIds).len != 2: return false
	callee = nodes[call].kids(kidIds)[0]
	lam = nodes[call].kids(kidIds)[1]
	m = nodes[callee].text.copy()
	if nodes[callee].kind != nField or nodes[callee].kids(kidIds).len != 1 or
		not (m in ["filter", "map", "sortedBy"]) or nodes[lam].kind != nLambda or
		nodes[lam].names().len != 1 or nodes[call].hasFlag(flagFirstK) or
		nodes[call].hasFlag(flagParallelSort) or nodes[lam].hasFlag(flagKeyLambda) and m == "map":
		return false
	lt = g.ty(target)
	if not g.irIsList(lt) or not isSameType(tys, lt, g.ty(call)) or g.c.holdsDrop(innerOf(tys, lt)):
		return false   # (a drop function sees its values dropped in the order written)
	root = g.irSamePlace(target, nodes[callee].kids(kidIds)[0]) ?? return false
	name = nodes[root].text.copy()
	if mentions(nodes, kidIds, lam, true, name): return false
	# a module variable, or this's field, a call in the lambda could read
	if (name == "self" or lw.irLookup(name) == none) and g.irCallsProgram(lam): return false
	elem = innerOf(tys, lt)
	if m == "sortedBy":
		if g.irSortByParts(lw, target, lam) != none: return true
		k = g.irKeysOf(lw, target, lam) ?? return true
		g.irRtInstanceValues(lw, "listSortBy", [elem, k.kt], [k.list, k.keys])
		return true
	list = g.irListAddr(lw, target)
	if not lw.ok: return true
	stride = g.c.elemStride(elem)
	kept = lw.f.irVreg(irInt)
	lw.irPut(IrInst(op = irConst, dst = kept, imm = 0))
	items = lw.irHeader(list, 0)
	each = g.irEachBegin(lw, target)
	if not lw.ok: return true
	at = lw.owned.len
	mark = lw.names.len
	element = g.irEachValue(lw, each)
	value = g.irLambdaValue(lw, lam, element, true)
	if not lw.ok: return true
	if m == "map":
		if g.irOwnedByAddress(elem):
			g.irPutOwned(lw, each.ptr, elem, value, true)   # the new value made, the old dropped, the new moved in
		else:
			g.irPutValue(lw, each.ptr, elem, value)
	else:
		yesB = lw.f.irBlock()
		noB = lw.f.irBlock()
		joinB = lw.f.irBlock()
		irPut(
			lw,
			IrInst(
				op = irBranch,
				a = value[0],
				b = lw.irConstOf(irInt, 0),
				cond = irNe,
				target = yesB,
				other = noB
			)
		)
		lw.f.irEnter(yesB)
		lw.irPut(
			IrInst(
				op = irMemCopy,
				a = lw.irElementAddr(items, kept, stride, 0),
				b = each.ptr,
				imm = stride
			)
		)
		lw.irPut(IrInst(op = irAdd, dst = kept, a = kept, b = lw.irConstOf(irInt, 1)))
		lw.f.irJumpTo(joinB)
		lw.f.irEnter(noB)
		if g.isOwningType(elem):
			lw.irPut(IrInst(op = irDrop, a = each.ptr, ty = elem))
		lw.f.irJumpTo(joinB)
		lw.f.irEnter(joinB)
	g.irScopeEnd(lw, mark)
	g.irDropTemporaries(lw, at)
	g.irEachEnd(lw, each)
	if m == "filter":
		lw.irPut(IrInst(op = irStore, a = list, c = kept, imm = 8, header = true))
	true

# `s = s.replace(a, b)` of a str the arguments do not read: strReplaceOwn, which writes the text
# over the str's own block when it does not grow and gives it to the result
fn irReplaceInPlace(mut g Gen, mut lw IrLower, target NodeId, call NodeId):
	if nodes[call].kind != nCall or g.tyK(g.ty(target)) != tStr: return false
	callee = g.c.writtenCallee(call)
	n = nodes[call].kids(kidIds).len
	if nodes[callee].kind != nField or nodes[callee].text != "replace" or
		nodes[callee].kids(kidIds).isEmpty or n < 3:
		return false
	args = nodes[call].kids(kidIds)[n - 2..n].copy()
	root = g.irSamePlace(target, nodes[callee].kids(kidIds)[0]) ?? return false
	name = nodes[root].text.copy()
	if args.any(mentions(nodes, kidIds, it, true, name)) or
		(name == "self" or lw.irLookup(name) == none) and args.any(g.irCallsProgram(it)):
		return false
	at = g.irListAddr(lw, target)
	from = g.irStrAddr(lw, args[0])
	to = g.irStrAddr(lw, args[1])
	if lw.ok:
		g.irStoreTo(lw, target, g.irCallRt(lw, "strReplaceOwn", [at, from, to]))
	true

# whether e calls a function of the program (which could read a module variable or this): a
# method of a str, a list, a map or a number is the runtime's, which reads only what it is given
fn irCallsProgram(mut g Gen, e NodeId) bool:
	if nodes[e].kind == nCall:
		callee = g.c.writtenCallee(e)
		builtin = nodes[callee].kind == nField and not nodes[callee].kids(kidIds).isEmpty and
			g.tyK(
				g.c.derefType(g.ty(nodes[callee].kids(kidIds)[0]))
			) in [tStr, tList, tMap, tInt, tFloat, tBool]
		if not builtin: return true
	nodes[e].kids(kidIds).any(g.irCallsProgram(it)) or nodes[e].sub().any(g.irCallsProgram(it))

# `xs = xs.filter(p)` written as a bare binding of a local that exists: irInPlaceStep's
fn irRebindsInPlace(mut g Gen, mut lw IrLower, s NodeId):
	call = nodes[s].kids(kidIds)[0]
	if not nodes[s].types().isEmpty or nodes[s].hasFlag(flagMut) or nodes[call].kind != nCall:
		return false
	callee = g.c.writtenCallee(call)
	if nodes[callee].kind != nField or nodes[callee].kids(kidIds).isEmpty: return false
	recv = nodes[callee].kids(kidIds)[0]
	nodes[recv].kind == nIdent and nodes[recv].text == nodes[s].text and
		g.irFind(lw, nodes[s].text.copy()) != none and g.irInPlaceStep(lw, recv, call)

# the root name of a place written twice the same way (`xs`, `a.b.xs`), none when a and b differ
fn irSamePlace(g Gen, a NodeId, b NodeId) NodeId?:
	if nodes[a].kind != nodes[b].kind or nodes[a].text != nodes[b].text: return none
	if nodes[a].kind == nIdent: return a
	if nodes[a].kind != nField or nodes[a].hasFlag(flagSafe) or nodes[b].hasFlag(flagSafe):
		return none
	g.irSamePlace(nodes[a].kids(kidIds)[0], nodes[b].kids(kidIds)[0])

# a field of this named alone given value: in this's leaves, or in memory for a place struct;
# false when name is no field of this
fn irStoreThisField(mut g Gen, mut lw IrLower, name str, value i64[]):
	selfType = lw.thisType ?? return false
	fi = g.c.fieldIndexOf(declOf(tys, selfType), name)
	if fi < 0: return false
	recv = g.irFind(lw, "self") ?? []
	if recv.isEmpty: return false
	if g.irIsAggregate(selfType):
		start, n = g.irFieldSpan(selfType, fi)
		lw.irCopyValue(recv[start..start + n].copy(), value)
		return true
	ft = g.c.structFieldTypeAt(declOf(tys, selfType), fi)
	addr = g.irFieldAddr(lw, recv[0], selfType, fi)
	if g.irOwnedByAddress(ft):
		g.irPutOwned(lw, addr, ft, value, true)
	elif g.irTakes(ft):
		g.irStoreLeaves(lw, ft, addr, -1, 1, 0, value)
	else:
		lw.irFail("assignment to field {name}")
	true

# value stored in the place target: an element (or a field of one), a field in memory, a local's
# leaves
fn irStoreTo(mut g Gen, mut lw IrLower, target NodeId, value i64[]):
	root = target
	while nodes[root].kind == nField:
		root = nodes[root].kids(kidIds)[0]
	if nodes[root].kind == nIndex:
		g.irStoreElement(lw, target, root, value)
		return
	if nodes[root].kind == nDeref:
		# the value a reference points to (m[k] += 1 through the index method's reference), or a
		# field of it: stored at its address
		base = g.irValue(lw, nodes[root].kids(kidIds)[0])
		if not lw.ok or base.len != 1:
			lw.irFail("assignment through a reference")
			return
		rt = innerOf(tys, g.ty(nodes[root].kids(kidIds)[0]))
		if target != root and not g.irIsPlaceStruct(rt) and not g.irIsAggregate(rt):
			lw.irFail("assignment through a reference to {typeStr(tys, rt)}")
			return
		t, off = g.irFieldPath(target, root, rt)
		addr = lw.irElementAddr(base[0], -1, 0, off)
		if g.irOwnedByAddress(t):
			g.irPutOwned(lw, addr, t, value, true)
		elif g.irIsOwnedWord(t):
			lw.irPut(IrInst(op = irDrop, a = addr, ty = t))
			g.irPutValue(lw, addr, t, value)
		else:
			g.irPutValue(lw, addr, t, value)
		return
	if nodes[root].kind != nIdent:
		lw.irFail("assignment to a place")
		return
	if target == root and g.irFind(lw, nodes[root].text.copy()) == none and
		g.irStoreThisField(lw, nodes[root].text.copy(), value):
		return
	if g.irMemPlace(lw, target) is mem:
		addr, t = mem
		if g.irOwnedByAddress(t):
			g.irPutOwned(lw, addr, t, value, true)
			return
		if g.irIsOwnedWord(t):
			lw.irPut(IrInst(op = irDrop, a = addr, ty = t))   # the table there
		g.irPutValue(lw, addr, t, value)
		return
	place = g.irValue(lw, target)   # a local's own leaves (or its fields'), not copies
	g.irAssignValue(lw, place, g.ty(target), value)

# a local's value replaced: leaves copied, or (owned, a local of this code) the old value dropped
# and the new one moved in from the temporary that holds it
fn irAssignValue(mut g Gen, mut lw IrLower, place i64[], t0 TypeId, value i64[]):
	t = innerOf(tys, t0) if g.tyK(t0) == tRef else t0
	if g.irIsOwnedWord(t):
		oi = lw.irOwnedWordAt(place[0]) if place.len == 1 else -1
		if oi < 0 and place.len == 1 and value.len == 1 and
			lw.vals.findIndex(.len == 1 and it[0] == place[0]) is ni:
			# a local that gave its map away (moved into a call): a slot for the one it gets now
			# (the slot it had, when it had one: the same owner again)
			fresh = lw.givenSlots.get(place[0]) ?? lw.irNewSlot(8)
			lw.irOwnBegin(
				IrOwned(slot = fresh, t, name = ni, word = place[0], key = lw.names[ni].copy())
			)
			oi = lw.owned.len - 1
		if oi < 0 or value.len != 1:
			lw.irFail("an assignment of {typeStr(tys, t)}")
			return
		slot = lw.owned[oi].slot
		lw.irPut(IrInst(op = irDrop, a = slot, ty = t))
		given = g.irGivenWord(lw, t, value[0])
		if given < 0:
			lw.irFail("a map assigned, not owned here")
			return
		lw.irPut(IrInst(op = irStore, a = slot, c = given))
		lw.irPut(IrInst(op = irCopy, dst = place[0], a = given))
		return
	if g.irIsOption(t) and g.irIsOwnedWord(tys[t].inner) and place.len == 2 and
		value.len == 2:
		inner = innerOf(tys, t)
		oi = lw.irOwnedWordAt(place[1])
		if oi < 0:
			lw.irFail("an assignment of {typeStr(tys, t)}")
			return
		lw.irPut(IrInst(op = irDrop, a = lw.owned[oi].slot, ty = inner))
		w = g.irWordTaken(lw, inner, value[1])
		lw.irPut(IrInst(op = irStore, a = lw.owned[oi].slot, c = w))
		lw.irCopyValue(place, [value[0], w])
		return
	if not g.irByAddress(t):
		lw.irCopyValue(place, value)
		return
	if place.len != 1:
		lw.irFail("an assignment of {typeStr(tys, t)}")
		return
	# a local's slot, or the address a mut parameter (a reference) names: the old value dropped,
	# the new one moved in
	g.irPutOwned(lw, place[0], t, value, true)

# an if, a statement or (want) an expression whose leaves are returned
fn irIf(mut g Gen, mut lw IrLower, s NodeId, want bool) i64[]:
	thenB = lw.f.irBlock()
	elseB = lw.f.irBlock()
	endB = lw.f.irBlock()
	hasElse = nodes[s].sub().len > 1
	# its type: the checker's, its first branch's value's, or (a body's last if, not typed) what
	# the body gives
	told = nodes[s].ty ?? g.irTailType(nodes[s].sub()[0])
	t = told ?? (tyError if not want else lw.rets[len - 1].t if not lw.rets.isEmpty else lw.rt)
	result = []
	if want:
		if not g.irTakes(t) and not g.irByAddress(t):
			return lw.irRefused("if of type {typeStr(tys, t)}")
		result = g.irNewResult(lw, t)   # before the condition: its slot made where the code runs
	g.irCond(lw, nodes[s].kids(kidIds)[0], thenB, elseB)
	before = lw.owned.copy()
	lw.f.irEnter(thenB)
	tv = g.irBlockValue(lw, nodes[s].sub()[0], want)
	if want and not lw.f.irEnded():
		g.irArmInto(lw, t, result, tv)
	thenLive = not lw.f.irEnded()
	thenOwned = lw.owned.copy()
	thenTail = lw.f.irBlock()
	lw.f.irJumpTo(thenTail)
	lw.owned = before.copy()
	lw.f.irEnter(elseB)
	if hasElse:
		ev = g.irBlockValue(lw, nodes[s].sub()[1], want)
		if want and not lw.f.irEnded():
			g.irArmInto(lw, t, result, ev)
	elseLive = not lw.f.irEnded()
	elseOwned = lw.owned.copy()
	elseTail = lw.f.irBlock()
	lw.f.irJumpTo(elseTail)
	irJoinOwned(
		g,
		lw,
		before,
		[(thenOwned, thenTail, thenLive), (elseOwned, elseTail, elseLive)],
		endB
	)
	lw.f.irEnter(endB)
	g.irArmsOwn(lw, t, result)
	result

# a branch's end: what it owns kept for irJoinOwned, then on to a tail block of its own
fn irBranchEnd(mut lw IrLower, mut arms (IrOwned[], i64, bool)[]):
	live = not lw.f.irEnded()
	tail = lw.f.irBlock()
	lw.f.irJumpTo(tail)
	arms.push((lw.owned.copy(), tail, live))

# The branches of a choice leave what the code owns as one: a value owned before it stays owned
# only if every branch that goes on still owns it; one that kept it while another gave it away
# drops it at its end (its tail block, then on to end). What a branch made and still owns (a
# temporary) stays owned after (its slot all zero on the other paths).
fn irJoinOwned(
	mut g Gen,
	mut lw IrLower,
	before IrOwned[],
	branches (IrOwned[], i64, bool)[],
	end i64
):
	same = (a IrOwned, b IrOwned): a.slot == b.slot and a.word == b.word
	final = []
	for o in before:
		kept = true
		for (owned, _, live) in branches:
			if live and not owned.any(same(it, o)): kept = false
		if kept: final.push(o.copy())
	for (owned, tail, live) in branches:
		lw.f.irEnter(tail)
		if live:
			for o in owned:
				inBefore = before.any(same(it, o))
				if inBefore and not final.any(same(it, o)):
					g.irDropSlot(lw, o)   # given away on another path: dropped here too
				elif not inBefore and not final.any(same(it, o)):
					final.push(o.copy())
		lw.f.irJumpTo(end)
	lw.owned = final

# x ?? y's fallback path entered, where x is none: what the value's path (before: what was owned
# before it) gave away is that none here, which owns nothing (stated consumed)
fn irFallbackEntered(mut lw IrLower, before IrOwned[]):
	for o in before:
		if not lw.owned.any(.slot == o.slot and .word == o.word):
			lw.irConsumed(o.slot, ownDropped)

# x ?? y's paths met: a fallback that left (a return) keeps nothing it made for after (taken: what
# the value's path owns)
fn irFallbackLeft(mut lw IrLower, move taken IrOwned[]):
	if lw.f.irEnded():
		lw.owned = taken
