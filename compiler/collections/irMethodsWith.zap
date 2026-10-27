# The lowering of stores, pushes, call arguments, boxes and method calls (irLower.zap).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# a value of type t stored at items + idx * stride (idx -1: at items), leaf by leaf
fn irStoreValue(mut g Gen, mut lw IrLower, t TypeId, items i64, idx i64, stride i64, value i64[]):
	scaled = idx < 0 or scaleBitsOf(stride) >= 0
	irStoreLeaves(
		g,
		lw,
		t,
		items,
		idx if scaled else lw.irScaled(idx, stride),
		stride if scaled else 1,
		0,
		value
	)

# a value of type t stored leaf by leaf at a + index * scale + base (index -1: none), the bytes
# between its leaves zeroed: memory holds the value's bytes alone, so comparing the bytes of
# two equal values finds them equal
fn irStoreLeaves(
	mut g Gen,
	mut lw IrLower,
	t TypeId,
	a i64,
	index i64,
	scale i64,
	base i64,
	value i64[]
):
	leaves = g.irLeaves(t, base)
	if leaves.len != value.len:
		lw.irFail("a store of {value.len} leaves where {leaves.len} are wanted")
		return
	for i, leaf in leaves:
		if g.irIsNicheTag(leaf.t): continue   # kept in the value's word, next
		word = value[i]
		if i > 0 and g.irIsNicheTag(leaves[i - 1].t):
			word = g.irNicheWord(lw, innerOf(tys, leaves[i - 1].t), value[i - 1], value[i])
		irPut(
			lw,
			IrInst(
				op = irStore,
				a,
				b = index,
				c = word,
				scale = u8(scale),
				imm = leaf.off,
				size = u8(g.c.typeSize(leaf.t))
			)
		)
	zero = lw.irConstOf(irInt, 0)
	at = base
	end = base + g.c.typeSize(t)
	for leaf in leaves.sortedBy(.off):
		lw.irZeroGap(a, index, scale, at, leaf.off, zero)
		at = at.max(leaf.off + g.c.typeSize(leaf.t))
	lw.irZeroGap(a, index, scale, at, end, zero)

# the first bytes at at zeroed
fn irZeroBytes(mut lw IrLower, at i64, bytes i64):
	if bytes > irZeroStores * 8:
		zero = lw.irConstOf(irInt, 0)
		lw.irPut(IrInst(op = irMemSet, a = at, b = zero, c = lw.irConstOf(irInt, bytes)))
		return
	lw.irZeroGap(at, -1, 1, 0, bytes, lw.irConstOf(irInt, 0))

irZeroStores = 16   # the most words zeroed by stores of their own, more by one setting of bytes

# the frame slot of a value of type t zeroed
fn irZeroSlot(mut g Gen, mut lw IrLower, slot i64, t TypeId):
	lw.irZeroBytes(slot, g.sizeOf(t).alignUp(8))

# zeros stored over [from, to): 8, 4, 2, 1 bytes at a time
fn irZeroGap(mut lw IrLower, a i64, index i64, scale i64, from i64, to i64, zero i64):
	at = from
	while at < to:
		size = 8
		while at + size > to:
			size /= 2
		lw.irPut(IrInst(op = irStore, a, b = index, c = zero, scale = u8(scale), imm = at, size))
		at += size

# xs.push(v) of a plain value: stored after the last element when there is room, the room
# grown first by the runtime (listGrowRaw) when there is none; the new element's index
fn irPush(mut g Gen, mut lw IrLower, list i64, elem TypeId, value i64[]):
	if not lw.ok: return -1
	n = lw.irHeader(list, 8)
	room = lw.irHeader(list, 16)
	growB = lw.f.irBlock()
	storeB = lw.f.irBlock()
	lw.irBranchIf(n, irLt, room, storeB, growB)
	lw.f.irEnter(growB)
	lw.f.blocks[growB].cold = true
	stride = g.c.elemStride(elem)
	need = lw.irDef(irInt, IrInst(op = irAdd, a = n, b = lw.irConstOf(irInt, 1)))
	g.irGrowCall(lw, "listGrowRaw", list, need, stride)
	lw.f.irJoin(storeB)
	g.irPutAt(lw, list, elem, n, value)
	n

# value pushed onto the list at list, whose room holds it (made before: irEachBegin's room)
fn irPushInRoom(mut g Gen, mut lw IrLower, list i64, elem TypeId, value i64[]):
	if not lw.ok: return
	g.irPutAt(lw, list, elem, lw.irHeader(list, 8), value)

# value stored at index n of the list at list, inside its room, and the length made n + 1
fn irPutAt(mut g Gen, mut lw IrLower, list i64, elem TypeId, n i64, value i64[]):
	stride = g.c.elemStride(elem)
	items = lw.irHeader(list, 0)
	if g.irOwnedByAddress(elem):
		g.irPutOwned(lw, lw.irElementAddr(items, n, stride, 0), elem, value, false)
	elif g.irByAddress(elem):
		g.irPutValue(lw, lw.irElementAddr(items, n, stride, 0), elem, value)
	else:
		g.irStoreValue(lw, elem, items, n, stride, value)
	more = lw.irDef(irInt, IrInst(op = irAdd, a = n, b = lw.irConstOf(irInt, 1)))
	lw.irPut(IrInst(op = irStore, a = list, c = more, imm = 8, header = true))

# the runtime's grow functions: a list's room made larger in place, its header's words rewritten
irGrowKeys = ["rt__listGrowRaw", "rt__listGrowExact"]

# a call of the runtime's grow function name (listGrowRaw, listGrowExact) making the list at list
# hold need elements of stride bytes, the headers kept in registers written before and read after
fn irGrowCall(mut g Gen, mut lw IrLower, name str, list i64, need i64, stride i64):
	g.irSyncHeaders(lw, true)
	irPut(
		lw,
		IrInst(
			op = irCall,
			regArgs = g.takesRegArgs(g.c.findFunc("rt__{name}"), false),
			part = instPartOf([list, need, lw.irConstOf(irInt, stride)], "rt__{name}")
		)
	)
	g.irSyncHeaders(lw, false)

# a call of fnd under key (its parameters' types resolved as they are now): the arguments read,
# an address for a list or a place struct
fn irCallTo(mut g Gen, mut lw IrLower, fnd NodeId, key str, args NodeId[]) i64[]:
	g.irCallWith(lw, fnd, key, none, -1, args)

# a call of fnd with the receiver recv (its address in recvAt, -1 for none; or its leaves for the
# registers, recvAt the first) and the argument nodes
fn irCallWith(
	mut g Gen,
	mut lw IrLower,
	fnd NodeId,
	key str,
	recv NodeId?,
	recvAt i64,
	args NodeId[],
	implType TypeId? = none,
	implDecl NodeId? = none,
	recvLeaves i64[] = []
):
	into = lw.resultAt   # (taken by this call, not one its arguments make)
	lw.resultAt = -1
	# an address taken before a later argument's call could point where that call reallocates:
	# then the values come first, the addresses after (needsValuesFirst)
	first = g.needsValuesFirst(fnd, recv, args)
	givens = g.irGivens(lw, fnd, args)
	plan = g.irArgPlan(fnd, recvAt >= 0, implType)
	argsAt = 1 if recvAt >= 0 else 0   # the first argument's place in the plan
	vs = fill(args.len, -1)
	spread i64[,] = []   # a read small aggregate's leaves, for the registers
	loop args.len:
		spread.push([])
	changed = []   # a mut scalar argument and the slot it is in
	outs = []   # `out name` making a new local: its name, slot and type
	for sweep in 0..(2 if first else 1):
		for i, arg in args:
			a = arg
			mode = nodes[nodes[fnd].kids(kidIds)[i]].ival
			scalar = g.irMutScalar(g.ty(a), mode)
			out = mode == modeOut and nodes[a].kind == nUnary and nodes[a].ival == unOut   # out x: the system writes x
			lent = (g.irByAddress(g.ty(a)) and mode != modeMove) or scalar or out
			if first and lent == (sweep == 0): continue
			if givens.find(.at == i) is given:
				vs[i] = g.irGivenClosureWord(lw, given)
			elif g.tyK(g.ty(a)) == tFn and nodes[fnd].hasFlag(flagExtern) and
				nodes[a].kind == nIdent:
				v = lw.f.irVreg(irInt)
				irPut(
					lw,
					IrInst(
						op = irFnAddr,
						dst = v,
						imm = g.callbackLabel(nodes[a].text.copy(), g.ty(a))
					)
				)
				vs[i] = v
			elif out:
				x = nodes[a].kids(kidIds)[0]
				if lw.irLookupNo(nameOf(nodes, x)) != none:
					vs[i] = g.irMutScalarAddr(lw, x, changed)
				else:
					# a new local the call fills: a slot of its own, read into the local after
					pt = g.c.resolveType(nodes[nodes[fnd].kids(kidIds)[i]].sub(kidIds)[0])
					slot = lw.irNewSlot(8)
					lw.irPut(IrInst(op = irStore, a = slot, c = lw.irConstOf(irInt, 0)))
					outs.push((nodes[x].text.copy(), slot, pt))
					vs[i] = slot
			elif scalar:
				vs[i] = g.irMutScalarAddr(lw, a, changed)
			elif mode == modeRead and g.stackListOk(a):
				vs[i] = g.irStackList(lw, a)   # lent only: built in the frame, nothing allocated
			elif irSpreadIn(plan, argsAt + i):
				spread[i] = g.irAs(lw, g.irValue(lw, a), g.ty(a))
			elif g.irLentAsCopy(g.ty(a)):
				vs[i] = g.irLentCopy(lw, g.ty(a), g.irAs(lw, g.irValue(lw, a), g.ty(a)))
			elif g.isTextWindow(g.ty(a)) and g.irTakesStr(fnd, i):
				vs[i] = g.irStrAddr(lw, a)   # a window where a str is read
			else:
				vs[i] = g.irAddressOf(lw, a) if g.irByAddress(g.ty(a)) else g.irExpr(lw, a)
	lw.resultAt = into
	out = g.irCallValuesWith(
		lw,
		fnd,
		key.copy() if givens.isEmpty else g.irGivenKey(key, fnd, givens, implType, implDecl),
		recvAt,
		vs,
		implType,
		spread,
		recvLeaves
	)
	for (a, slot) in changed:
		g.irStoreTo(lw, a, g.irLoadValue(lw, g.ty(a), slot, -1, 0))   # the value the callee left
	for (name, slot, pt) in outs:
		lw.irDeclare(name, g.irLoadValue(lw, pt, slot, -1, 0))
	out

# whether parameter i of fnd is a str
fn irTakesStr(mut g Gen, fnd NodeId, i i64):
	p = nodes[fnd].kids(kidIds)[i]
	not nodes[p].types(kidIds).isEmpty and g.tyK(g.c.resolveType(nodes[p].types(kidIds)[0])) == tStr

# the address a mut struct of numbers is passed by: its place in memory, or a slot of this frame
# holding its leaves, written back after the call (a place named by locals and fields only, read
# twice)
fn irMutScalarAddr(mut g Gen, mut lw IrLower, a NodeId, mut changed (NodeId, i64)[]):
	if g.irMemPlace(lw, a) is (addr, _): return addr
	root = a
	while nodes[root].kind == nField:
		root = nodes[root].kids(kidIds)[0]
	if nodes[root].kind == nIndex: return g.irElementFieldAddr(lw, a, root)   # an element: where it is
	if nodes[root].kind == nDeref:
		# through a reference: where it points
		base = g.irValue(lw, nodes[root].kids(kidIds)[0])
		if not lw.ok or base.len != 1:
			lw.irFail("a mut argument through a reference")
			return -1
		_, off = g.irFieldPath(a, root, innerOf(tys, g.ty(nodes[root].kids(kidIds)[0])))
		return lw.irElementAddr(base[0], -1, 0, off)
	if nodes[root].kind != nIdent:
		lw.irFail("a mut argument of kind {nodes[root].kind}")
		return -1
	slot = lw.irNewSlot(g.sizeOf(g.ty(a)).alignUp(8))
	g.irStoreLeaves(lw, g.ty(a), slot, -1, 1, 0, g.irValue(lw, a))
	changed.push((a, slot))
	slot

# fnd called with values vs, one per parameter (scalars, addresses); its result's leaves. A value
# moved in is pushed whole (its words, as the callee reads them) and is the callee's: zeroed
# here
fn irCallValues(mut g Gen, mut lw IrLower, fnd NodeId, key str, values i64[]) i64[]:
	g.irCallValuesWith(lw, fnd, key, -1, values)

# the same with a receiver's address (recv, -1 for none) pushed first
# a call's result of type rt the callee wrote in slot: the slot, or its leaves (a map or box inside
# an optional this code's from now on: 0 when there is none)
fn irCallResult(mut g Gen, mut lw IrLower, rt TypeId, slot i64):
	if g.irByAddress(rt): return [slot]
	leaves = g.irLoadValue(lw, rt, slot, -1, 0)
	g.irOwnGivenWords(lw, rt, leaves)
	leaves

fn irCallValuesWith(
	mut g Gen,
	mut lw IrLower,
	fnd NodeId,
	key str,
	recv i64,
	values i64[],
	recvType TypeId? = none,
	spread i64[,] = [],
	recvLeaves i64[] = []
):
	into = lw.resultAt   # (irBox's block, for this call's result)
	lw.resultAt = -1
	if not lw.ok: return []
	if values.len != nodes[fnd].kids(kidIds).len:
		return lw.irRefused(
			"{key} given {values.len} values for {nodes[fnd].kids(kidIds).len} parameters"
		)
	plan = g.irArgPlan(fnd, recv >= 0, recvType)
	regArgs = plan != none
	first = 1 if recv >= 0 else 0   # the first parameter's place in the plan
	rt = g.c.fnRetType(fnd)
	vs = []
	stores = 0   # the arguments the callee may store into: its mut parameters
	if recv >= 0:
		if nodes[fnd].hasFlag(flagMut) and
			(recvType == none or g.irMayHoldBorrows(recvType ?? tyError)):
			stores = 1   # (a receiver that holds no borrow keeps none)
		if not recvLeaves.isEmpty:
			vs.extend(recvLeaves)
		elif irSpreadIn(plan, 0):
			vs.extend(g.irLoadValue(lw, recvType ?? tyError, recv, -1, 0))   # its leaves
		else:
			vs.push(recv)
	for i, value in values:
		p = nodes[fnd].kids(kidIds)[i]
		pt = g.c.resolveType(nodes[p].types(kidIds)[0])
		if irSpreadIn(plan, first + i):
			# its leaves in registers: given, or read from the address given
			vs.extend(spread[i] if i < spread.len and not spread[i].isEmpty
				else g.irLoadValue(lw, pt, value, -1, 0))
			continue
		if g.irGiven(pt, nodes[p].ival) or g.irMovedWords(pt, nodes[p].ival):
			v = value
			owning = g.isOwningType(pt)
			if owning and g.irByAddress(pt) and not lw.irOwns(v) and v not in lw.literals:
				v = g.irOwnedCopy(lw, pt, v)   # a place's value: the ownership check decides
			if owning and not lw.irOwns(v) and v not in lw.literals:
				return lw.irRefused("a move of {typeStr(tys, pt)} not owned here")
			words = g.sizeOf(pt).alignUp(8) / 8
			w = words - 1
			while w >= 0:
				word = lw.irDef(irInt, IrInst(op = irLoad, a = v, imm = 8 * w))
				if owning:
					lw.f.irLeafTyped(word, irMovedBytes)
				vs.push(word)   # the last word pushed first: the first at the lowest
				w -= 1
			if owning:
				if lw.owned.any(.slot == v and .name >= 0):
					lw.irConsumed(v, ownMoved)   # a local given to the call: its words are the call's
				lw.irZeroBytes(v, 8 * words)
		else:
			arg = g.irArgFor(lw, value, pt, regArgs)
			if nodes[p].ival == modeMove and g.irIsOwnedWord(pt):
				arg = g.irGivenWord(lw, pt, value)
				if arg < 0: return lw.irRefused("a move of {typeStr(tys, pt)} not owned here")
			if nodes[p].ival == modeMut and g.irMayHoldBorrows(pt):
				stores |= 1 << vs.len.min(63)   # a place the callee may keep a borrow in
			vs.push(arg)
	g.irCallStores[key.copy()] = -1 if vs.len > 63 else stores
	if regArgs and g.irResultClasses(rt) is classes:
		return g.irCallLeaves(
			lw,
			rt,
			classes,
			IrInst(op = irCall, regArgs, part = instPartOf(vs, key.copy()))
		)
	if not g.c.isScalar(rt) and g.tyK(rt) != tUnit:
		# written by the callee at the address pushed last: a slot of this frame, or the block
		# irBox made for it
		slot = into if into >= 0 else g.irResultSlot(lw, rt)
		g.irPutSynced(
			lw,
			IrInst(op = irCall, regArgs = false, c = slot, part = instPartOf(vs, key.copy()))
		)
		if into >= 0:
			lw.placed = into
			return [into]
		return g.irCallResult(lw, rt, slot)
	dst = -1 if g.tyK(rt) == tUnit else lw.f.irVreg(g.irClassOf(rt))
	if dst >= 0 and (g.tyK(rt) == tBool or not g.irOfRuntime(fnd) and not lw.irInRuntimeCode()):
		lw.f.irLeafTyped(dst, i64(rt))   # the program's own result: of its type
	pure = g.c.pureCallLevel(fnd) if recv < 0 else 0
	g.irPutSynced(
		lw,
		IrInst(op = irCall, dst, regArgs, pure = u8(pure), part = instPartOf(vs, key.copy()))
	)
	if dst >= 0 and g.irIsOwnedWord(rt):
		g.irOwnedWord(lw, rt, dst)   # the callee's map is this code's now
	[dst] if dst >= 0 else []

# a call whose result of type rt comes back in registers (irResultClasses): its leaves, the first
# the call's dst, the others read right after it (irCallOut)
fn irCallLeaves(mut g Gen, mut lw IrLower, rt TypeId, classes i64[], move call IrInst):
	leaves = g.irNewValue(lw, rt)
	regs = irRegIndexes(classes)
	call.dst = leaves[0]
	g.irSyncHeaders(lw, true)
	lw.irPut(call)
	for k in 1..leaves.len:
		lw.irPut(IrInst(op = irCallOut, dst = leaves[k], imm = regs[k]))
	g.irSyncHeaders(lw, false)
	leaves

# v as the argument for a scalar parameter of type pt: a float in a register as it is, on the stack
# an f32's slot holding the single's bits
fn irArgFor(mut g Gen, mut lw IrLower, v i64, pt TypeId, regArgs bool) i64:
	if not g.irIsF32(pt) or v < 0: return v
	if not regArgs: return g.irArgBits(lw, v, pt) if lw.f.classes[v] == irFloat else v
	if lw.f.classes[v] == irFloat: return v
	lw.irDef(irFloat, IrInst(op = irBitsToF32, a = v))   # (given as its bits)

# the runtime's generic function name, for the type arguments, called with values (scalars,
# addresses, owned values to move in); its result's leaves
fn irRtInstanceValues(
	mut g Gen,
	mut lw IrLower,
	name str,
	targs TypeId[],
	values i64[]
):
	mangle = g.rtMangle(name, targs)
	key = "rt__{name}_{mangle}"
	fnd = g.rtDecl(name)
	ii = g.c.findInstance(fnd, mangle) ?? return lw.irRefused("instance of {name}")
	decl = g.c.instances[ii].decl
	sav = move g.c.subst
	g.c.subst = g.c.instances[ii].sub.copy()
	ok = g.irCallable(decl, true)
	out = []
	if ok:
		out = g.irCallValues(lw, decl, key, values)
	g.c.subst = sav
	if not ok:
		lw.irFail("generic call of {name}")
	out

# whether a map's key or value of type t goes in through mapSet: a scalar, an owned value or a
# struct by its address (the runtime copies its bytes)
fn irMapPart(mut g Gen, t TypeId):
	g.irClassOf(t) >= 0 or g.irOwnedByAddress(t) or g.irIsAggregate(t) or g.irIsOption(t) or
		(g.irByAddress(t) and not g.isOwningType(t))

# {k: v, ...}: a new map, each pair set; the map a temporary
fn irMapLit(mut g Gen, mut lw IrLower, e NodeId):
	t = g.ty(e)
	kt = innerOf(tys, t)
	vt = valOf(tys, t)
	if not g.irMapPart(kt) or not g.irMapPart(vt):
		return lw.irRefused("map literal of {typeStr(tys, t)}")
	m = g.irRtInstanceValues(lw, "mapNew", [kt, vt], [])
	if not lw.ok: return []
	for i in 0..nodes[e].kids(kidIds).len:
		k = g.irOneWord(lw, kt, g.irValue(lw, nodes[e].kids(kidIds)[i]))   # a struct's words moved in from a slot
		v = g.irOneWord(lw, vt, g.irValue(lw, nodes[e].sub(kidIds)[i]))
		if not lw.ok: return []
		g.irRtInstanceValues(lw, "mapSet", [kt, vt], [m[0], k, v])
	m

# a method called (not inlined): the receiver's address first (a place struct where it is, a
# struct of numbers in a slot of its leaves, written back by a mut method), then the arguments
# Box(v): a block for the value on the heap (a shared value's count, 1, in the word before it),
# the value moved in; the box is this code's
fn irBox(mut g Gen, mut lw IrLower, bt TypeId, arg NodeId):
	inner = innerOf(tys, bt)
	counted = tys[bt].counted
	# a call of a function whose arguments call nothing: made after the block, its result written
	# in the block (when it is a call once lowered, not a body in place)
	placed = not counted and g.irByAddress(inner) and nodes[arg].kind == nCall and
		nodes[nodes[arg].kids(kidIds)[0]].kind == nIdent and
		nodes[arg].kidsFrom(kidIds, 1).all(g.irCallFree(it))
	value = []
	if not placed:
		value = g.irValue(lw, arg)
		if not lw.ok: return []
	block = g.irBlockToFill(lw, g.sizeOf(inner) + (8 if counted else 0))
	if not lw.ok: return []
	at = block
	if counted:
		lw.irPut(IrInst(op = irStore, a = at, c = lw.irConstOf(irInt, 1)))
		at = lw.irDef(irInt, IrInst(op = irAdd, a = block, b = lw.irConstOf(irInt, 8)))
	g.irOwnedWord(lw, bt, at)   # owned before it is filled: the filling is the box's own
	if placed:
		lw.resultAt = at
		lw.placed = -1
		value = g.irValue(lw, arg)
		lw.resultAt = -1
		if not lw.ok: return []
		if lw.placed == at: return [at]
	g.irPutValue(lw, at, inner, value)
	[at]

# A block of n bytes its maker fills before anything reads it: the open arena's next bytes in
# place (regionPop), rtAllocRaw's call when that gives none.
fn irBlockToFill(mut g Gen, mut lw IrLower, n i64) i64:
	size = newNode(nodes, kidIds, nInt, lw.line, lw.col, text = "{n}")
	nodes[size].ty = tyInt(64, true)
	v = lw.f.irVreg(irInt)
	quick = g.irTryInline(lw, g.rtDecl("regionPop"), none, none, [size]) ?? []
	if quick.len != 1:
		lw.ok = true
		return g.irCallRt(lw, "rtAllocRaw", [lw.irConstOf(irInt, n)]).first ?? -1
	lw.irPut(IrInst(op = irCopy, dst = v, a = quick[0]))
	way = lw.irSplitNZ(v)
	lw.f.irJumpTo(way.end)
	lw.f.irEnter(way.no)
	slow = g.irCallRt(lw, "rtAllocRaw", [lw.irConstOf(irInt, n)])
	if slow.len == 1:
		lw.irPut(IrInst(op = irCopy, dst = v, a = slow[0]))
	lw.f.irJoin(way.end)
	lw.irDef(irInt, IrInst(op = irCopy, a = v))   # (one definition: the box's word)

# the address `at` evaluates to kept as where the extern fnd (loaded when the program runs) is
fn irBindLoaded(mut g Gen, mut lw IrLower, fnd NodeId, at NodeId):
	v = g.irExpr(lw, at)
	slot = lw.irDef(irInt, IrInst(op = irDataAddr, imm = g.loadedSlot(fnd)))
	lw.irPut(IrInst(op = irStore, a = slot, c = v))

# the address a box (or a reference to one) points to
fn irBoxTarget(mut g Gen, mut lw IrLower, obj NodeId) i64:
	if nodes[obj].kind == nDeref: return g.irBoxTarget(lw, nodes[obj].kids(kidIds)[0])   # the checker's look through the box
	if g.irGlobal(lw, obj) is slot:
		# a module variable: its slot holds the box's word
		word = lw.irDef(irInt, IrInst(op = irLoad, a = slot))
		return word
	v = g.irExpr(lw, obj)
	if g.tyK(g.ty(obj)) != tRef: return v
	lw.irDef(irInt, IrInst(op = irLoad, a = v))

fn irMethodCall(
	mut g Gen,
	mut lw IrLower,
	md NodeId,
	implDecl NodeId?,
	generic bool,
	ot TypeId,
	obj NodeId,
	args NodeId[]
):
	sav = g.c.subst.copy()
	if generic and implDecl is impl:
		g.setSubstOf(impl)
	ok = g.irCallable(md, generic)
	out = []
	if ok:
		recvAt = -1
		slot = -1
		leaves = []   # a receiver spread over the registers
		if g.tyK(g.irListType(obj)) == tBox or
			(g.tyK(ot) == tStruct and nodes[declOf(tys, ot)].hasFlag(flagShared)):
			recvAt = g.irBoxTarget(lw, obj)   # a box's (a shared value's) method: on the value it points to
		elif irSpreadIn(g.irArgPlan(md, true, ot), 0):
			leaves = g.irAs(lw, g.irValue(lw, obj), ot)
			recvAt = leaves[0] if not leaves.isEmpty else -1
		elif g.irIsAggregate(ot):
			slot = g.irLentCopy(lw, ot, g.irValue(lw, obj))
			recvAt = slot
		else:
			recvAt = g.irAddressOf(lw, obj)
		if lw.ok:
			out = irCallWith(
				g,
				lw,
				md,
				"{tys[ot].name}_{nodes[md].text}",
				obj,
				recvAt,
				args,
				ot,
				implDecl if generic else none,
				leaves
			)
		if lw.ok and slot >= 0 and nodes[md].hasFlag(flagMut):
			if g.irIsPlaceNode(obj):
				g.irStoreTo(lw, obj, g.irLoadValue(lw, ot, slot, -1, 0))   # the leaves it changed
			else:
				lw.irFail("a mut method of a value that is not a place")
	g.c.subst = sav
	if not ok:
		lw.irFail("method {nodes[md].text} of {typeStr(tys, ot)}")
	out

# the method obj.name(args) the runtime's generic function name for targs is
fn irRtInstanceCall(
	mut g Gen,
	mut lw IrLower,
	name str,
	targs TypeId[],
	obj NodeId,
	args NodeId[]
) i64[]:
	mangle = g.rtMangle(name, targs)
	all = [obj]
	all.extend(args)
	g.irInstanceCall(lw, g.rtDecl(name), mangle, all)

# a call of the instance `mangle` of the generic function fnd, inlined when small
fn irInstanceCall(mut g Gen, mut lw IrLower, maybeFnd NodeId?, mangle str, args NodeId[]):
	fnd = maybeFnd ?? return lw.irRefused("generic call")
	ii = g.c.findInstance(fnd, mangle) ?? return lw.irRefused("generic call")
	if nodes[fnd].kids(kidIds).len != args.len or args.any(nodes[it].kind == nNamedArg):
		return lw.irRefused("generic call")
	decl = g.c.instances[ii].decl   # its own copy when numbers were given
	sav = move g.c.subst
	g.c.subst = g.c.instances[ii].sub.copy()
	# inlined, but not from inside another instance of the same function
	if g.irInlinesAs(lw, decl, true) and not g.curFnKey.startsWith("{nodes[fnd].text}_"):
		g.askChecked(ii)
		inlined = g.irTryInline(lw, decl, none, none, args)
		if inlined is v:
			g.c.subst = sav
			return v.copy()
	ok = g.irCallable(decl, true)
	out = []
	if ok:
		out = g.irCallTo(lw, decl, "{nodes[fnd].text}_{mangle}", args)
	g.c.subst = sav
	if not ok:
		lw.irFail("generic call of {nodes[fnd].text}")
	out
