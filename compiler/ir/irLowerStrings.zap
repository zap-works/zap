# The lowering of text, lists, elements and the choice between values (irLower.zap).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# the address of a value reached by address: a place, or a temporary the expression makes
fn irAddressOf(mut g Gen, mut lw IrLower, e NodeId):
	if g.irIsAggregate(g.ty(e)) and nodes[e].kind == nIdent and
		lw.irInScopeNo(nameOf(nodes, e)):
		return g.irLentCopy(lw, g.ty(e), g.irValue(lw, e))   # numbers in registers: a slot of their own
	# a module variable kept in registers (stdout) is lent from a slot below, as a local is
	moduleWord = nodes[e].kind == nIdent and not lw.irInScopeNo(nameOf(nodes, e)) and
		g.irTakes(g.ty(e)) and not g.irByAddress(g.ty(e))
	if not moduleWord and
		(
			g.irIsPlaceNode(e) or
				(nodes[e].kind == nDeref and g.irIsPlaceNode(nodes[e].kids(kidIds)[0]))
		):
		return g.irListAddr(lw, e)
	v = g.irValue(lw, e)
	if not lw.ok: return -1
	if v.len != 1 or (g.irTakes(g.ty(e)) and not g.irByAddress(g.ty(e))):
		if g.irTakes(g.ty(e)): return g.irLentCopy(lw, g.ty(e), v)   # numbers: a slot of their own
		lw.irFail("an address of {typeStr(tys, g.ty(e))}")
		return -1
	v[0]

# a list literal lent to a read parameter: its elements in a frame slot,
# a header { those, length, room 0 } (room 0: it owns nothing) in another; the header's address
fn irStackList(mut g Gen, mut lw IrLower, e NodeId):
	elem = innerOf(tys, g.ty(e))
	stride = g.c.elemStride(elem)
	values = nodes[e].kids(kidIds).copy().map(g.irValue(lw, it))
	n = values.len
	items = lw.irNewSlot(n * stride)
	for i in 0..n:
		if g.irTakes(elem):
			g.irStoreLeaves(lw, elem, items, -1, 1, i * stride, values[i])
		else:
			g.irPutValue(lw, lw.irElementAddr(items, -1, stride, i * stride), elem, values[i])   # its bytes
	header = lw.irNewSlot(24)
	lw.irPut(IrInst(op = irStore, a = header, c = items, header = true))
	lw.irPut(IrInst(op = irStore, a = header, c = lw.irConstOf(irInt, n), imm = 8, header = true))
	header

# a str literal: { its bytes in the program's data, its length, room 0 } (room 0: it owns
# nothing) in a frame slot; the slot's address
fn irStrLiteral(mut g Gen, mut lw IrLower, text str):
	bytes = lw.irDef(irInt, IrInst(op = irDataAddr, imm = g.strLit(text)))
	slot = lw.irNewSlot(24)
	lw.irPut(IrInst(op = irStore, a = slot, c = bytes, header = true))
	length = lw.irConstOf(irInt, text.len)
	lw.irPut(IrInst(op = irStore, a = slot, c = length, imm = 8, header = true))
	lw.literals.push(slot)
	lw.literalWords.push(IrLiteralWords(slot, bytes, length))
	slot

# a runtime function rt__name called with values (scalars, addresses); its result's leaves
fn irCallRt(mut g Gen, mut lw IrLower, name str, vs i64[]) i64[]:
	g.irCallValues(lw, g.rtDecl(name), "rt__{name}", vs)

# the bytes of the frame's buffer an interpolation is built in, when its expected length is at
# most twice that
interpBuffer = 32

# "a{x}b{y}": a block with room for the literal bytes and the values,
# each part appended (an integer formatted straight into it, a bool or a float formatted first),
# the block then the str
fn irInterpolation(mut g Gen, mut lw IrLower, e NodeId) i64[]:
	parts = g.irInterpParts(lw, e)
	if not lw.ok: return []
	room = nodes[e].kids(kidIds).sum(nodes[it].text.len if nodes[it].kind == nStr else 16)
	out = []
	if room <= interpBuffer * 2:
		# built in a buffer of the frame: a short result needs no block (strBuildEnd)
		buf = lw.f.irVreg(irInt)
		lw.irPut(IrInst(op = irFrameSlot, dst = buf, imm = interpBuffer))
		out = g.irCallRt(lw, "strBuildIn", [buf, lw.irConstOf(irInt, interpBuffer)])
	else:
		out = g.irCallRt(lw, "strBuildStart", [lw.irConstOf(irInt, room)])
	if not lw.ok: return []
	g.irAppendParts(lw, out[0], parts)
	if not lw.ok: return []
	g.irCallRt(lw, "strBuildEnd", out)

# bytes.extend("a{x}".bytes()): the parts appended to the list, no str between
fn irInterpolationOnto(mut g Gen, mut lw IrLower, e NodeId, obj NodeId):
	parts = g.irInterpParts(lw, e)
	if not lw.ok: return []
	g.irAppendParts(lw, g.irListAddr(lw, obj), parts)
	irNoLeaves()

# the interpolation of "a{x}".bytes() (its window read through), or none
fn irBytesOfInterpolation(g Gen, at NodeId) NodeId?:
	e = nodes[at].kids(kidIds)[0] if nodes[at].kind == nDeref and nodes[at].kids(kidIds).len == 1
		else at
	if nodes[e].kind != nCall or nodes[e].kids(kidIds).len != 1: return none
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind != nField or nodes[callee].text != "bytes" or
		nodes[callee].kids(kidIds).isEmpty:
		return none
	inner = nodes[callee].kids(kidIds)[0]
	if nodes[inner].kind != nInterp: return none
	inner

# each part of an interpolation first (one may leave the function: nothing is built yet): an
# integer's value (0 unsigned, 1 signed), its text's address (2), or nothing (3: an empty literal)
# a text read where it lies (a place) is read after the parts that call, which could move it
# (a place in a list a call grows): the order of what happens stays the order written
fn irInterpParts(mut g Gen, mut lw IrLower, e NodeId):
	kids = nodes[e].kids(kidIds).copy()
	parts = fill(kids.len, (-1, 0))
	for sweep in 0..2:
		for i, p in kids:
			t = g.ty(p)
			late = g.irIsStr(t) and g.irIsPlaceNode(p) and not g.exprHasCall(p) and
				kids[i + 1..].any(g.exprHasCall(it))
			if late != (sweep == 1): continue
			if nodes[p].kind == nStr and nodes[p].text.isEmpty:
				parts[i] = -1, 3   # nothing to append
			elif nodes[p].kind == nNone:
				parts[i] = g.irStrLiteral(lw, "none"), 2
			elif g.tyK(t) == tInt:
				parts[i] = g.irExpr(lw, p), 1 if tys[t].isSigned else 0
			else:
				parts[i] = g.irToStr(lw, p), 2
			if not lw.ok: return parts
	parts

# the parts (irInterpParts's) appended to the bytes at out
fn irAppendParts(mut g Gen, mut lw IrLower, out i64, parts (i64, i64)[]):
	for (v, kind) in parts:
		if kind == 3: continue
		irCallRt(
			g,
			lw,
			"strBuildAdd" if kind == 2 else "pushInt" if kind == 1 else "pushUint",
			[out, v]
		)
		if not lw.ok: return

# the str form of p: a str itself, a number or a bool formatted by the
# runtime, anything else by the printing function the compiler wrote for its type; its address
fn irToStr(mut g Gen, mut lw IrLower, p NodeId):
	t = g.ty(p)
	k = g.tyK(t)
	if g.irIsStr(t): return g.irStrAddr(lw, p)
	if k == tInt:
		return irCallRt(
			g,
			lw,
			"fmtInt" if tys[t].isSigned else "fmtUint",
			[g.irExpr(lw, p)]
		).first ??
			-1
	if k == tBool or k == tFloat:
		v = g.irExpr(lw, p)
		if k == tFloat:
			bits = lw.irDef(irInt, IrInst(op = irFloatBits, a = v))   # the f64 of the value, its width told apart
			v = bits
		text = g.irCallRt(lw, "fmtBool", [v]) if k == tBool
			else g.irCallRt(lw, "fmtFloat", [v, lw.irConstOf(irInt, tys[t].bits)])
		return text.first ?? -1
	fnd = g.derivedFn("str", t)
	if fnd is f and g.irCallable(f, false):
		return g.irCallTo(lw, f, nodes[f].text.copy(), [p]).first ?? -1
	lw.irFail("the str form of {typeStr(tys, t)}")
	-1

# s.m(args) of a str (or a window): a copy, indexOf's three runtime
# functions (a str, from a start, a byte), the rest strMethodRt's
fn irStrMethod(mut g Gen, mut lw IrLower, e NodeId, m str, obj NodeId, args NodeId[]) i64[]:
	if m == "copy" and args.isEmpty:
		from = g.irStrAddr(lw, obj)
		slot = g.irTemporary(lw, tyStr)
		lw.irPut(IrInst(op = irDeepCopy, a = slot, b = from, ty = tyStr))
		return [slot]
	name = strMethodRt(m)
	if name == "": return lw.irRefused("method {m} of str")
	vs = [g.irStrAddr(lw, obj)]
	for a in args:
		vs.push(g.irStrAddr(lw, a) if g.irByAddress(g.ty(a)) else g.irExpr(lw, a))
	g.irCallRt(lw, name, vs)

# how many leaves a value of type t has
fn irLeafCount(mut g Gen, t TypeId):
	g.irLeaves(t, 0).len

# the runtime's function of that name, or none
fn rtDeclOrNone(g Gen, name str):
	g.c.findFunc("rt__{name}")

# whether t is a str, or a reference to one
fn irIsStr(g Gen, maybeT TypeId?):
	t = maybeT ?? return false
	tys[t].kind == tStr or (tys[t].kind == tRef and tys[innerOf(tys, t)].kind == tStr)

# the text window e reads through: e itself when it is a `ref str`, its target when it
# dereferences one
fn irTextWindowOf(mut g Gen, e NodeId) NodeId?:
	if g.isTextWindow(g.ty(e)): return e
	if nodes[e].kind == nDeref and g.isTextWindow(g.ty(nodes[e].kids(kidIds)[0])):
		return nodes[e].kids(kidIds)[0]
	none

# the bytes' address and length of the text e: a window's two words, a str's (irStrWords)
fn irTextWords(mut g Gen, mut lw IrLower, e NodeId) (i64, i64):
	if g.irTextWindowOf(e) is w:
		v = g.irValue(lw, w)
		if not lw.ok or v.len != 1:
			lw.irFail("a window of {v.len} leaves")
			return (-1, -1)
		return (lw.irHeader(v[0], 0), lw.irHeader(v[0], 8))
	lw.irStrWords(g.irListAddr(lw, e))

# the address of a str holding the text e, which a function taking a str reads: a window's two
# words copied into one
fn irStrAddr(mut g Gen, mut lw IrLower, e NodeId) i64:
	if not g.isTextWindow(g.ty(e)): return g.irAddressOf(lw, e)
	v = g.irValue(lw, e)
	if not lw.ok or v.len != 1:
		lw.irFail("a window of {v.len} leaves")
		return -1
	lw.irWindowAsStr(v[0])

# the window over the text of type t at a (a str's bytes wherever they are, or a window's words)
# stored at `to`
fn irStoreWindowOf(mut g Gen, mut lw IrLower, to i64, t TypeId, a i64):
	ptr = -1
	n = -1
	if g.tyK(t) == tStr:
		ptr, n = lw.irStrWords(a)
	else:
		ptr = lw.irHeader(a, 0)
		n = lw.irHeader(a, 8)
	lw.irPut(IrInst(op = irStore, a = to, c = ptr))
	lw.irPut(IrInst(op = irStore, a = to, c = n, imm = 8))

# the str at a seen through a window (a `ref str` made of it)
fn irStrAsWindow(mut lw IrLower, a i64) i64:
	ptr, n = lw.irStrWords(a)
	lw.irWindowSlot(ptr, n)

# the items' address and the length of the list, str or window e
fn irItemsAndLength(mut g Gen, mut lw IrLower, e NodeId):
	if g.tyK(g.irListType(e)) == tStr: return g.irTextWords(lw, e)
	list = g.irReadListAddr(lw, e)
	(lw.irHeader(list, 0), lw.irHeader(list, 8))

# [a, b, ...] of plain elements: a new list (a temporary) with room for them all, each stored
fn irListLiteral(mut g Gen, mut lw IrLower, e NodeId):
	t = g.ty(e)
	elem = innerOf(tys, t)
	owned = g.irOwnedByAddress(elem)   # each element moved in from what owns it
	if not owned and not g.irIsOwnedWord(elem) and
		(g.isOwningType(elem) or not (g.irTakes(elem) or g.irByAddress(elem))):
		lw.irFail("a list literal of {typeStr(tys, elem)}")
		return -1
	recycle = lw.recycleInto
	lw.recycleInto = -1   # (not for the elements)
	values = nodes[e].kids(kidIds).copy().map(g.irValue(lw, it))
	slot = g.irTemporary(lw, t)
	lw.recycleInto = recycle
	lw.irTakeKept(slot, t)
	n = values.len
	if n == 0: return slot   # the zeroed slot is the empty list
	stride = g.c.elemStride(elem)
	grow = g.c.findFunc("rt__listGrowRaw")
	irPut(
		lw,
		IrInst(
			op = irCall,
			args = [slot, lw.irConstOf(irInt, n), lw.irConstOf(irInt, stride)],
			key = "rt__listGrowRaw",
			regArgs = g.takesRegArgs(grow, false)
		)
	)
	items = lw.irDef(irInt, IrInst(op = irLoad, a = slot, header = true))
	for i in 0..n:
		if owned:
			irPutOwned(
				g,
				lw,
				lw.irElementAddr(items, -1, stride, i * stride),
				elem,
				values[i],
				false
			)
		elif g.irByAddress(elem) or g.irIsOwnedWord(elem):
			g.irPutValue(lw, lw.irElementAddr(items, -1, stride, i * stride), elem, values[i])   # its bytes, or a word given
		else:
			g.irStoreLeaves(lw, elem, items, -1, 1, i * stride, values[i])
	lw.irPut(IrInst(op = irStore, a = slot, c = lw.irConstOf(irInt, n), imm = 8, header = true))
	slot

# the address of the list e that is only read: a literal of elements that own nothing built in
# the frame (no heap block, nothing to drop), else irListAddr's
fn irReadListAddr(mut g Gen, mut lw IrLower, e NodeId) i64:
	if g.stackListOk(e): return g.irStackList(lw, e)
	g.irListAddr(lw, e)

# the address of the list (or place struct) e names: a name, or a field of a place struct
fn irListAddr(mut g Gen, mut lw IrLower, e NodeId):
	at = e
	if nodes[at].kind == nDeref:
		at = nodes[at].kids(kidIds)[0]
		if g.isTextWindow(g.ty(at)):
			w = g.irValue(lw, at)
			return lw.irWindowAsStr(w[0]) if lw.ok and w.len == 1 else -1   # read as a str
	if not g.irPointsAway(g.ty(at)) and g.irGlobal(lw, at) is global:
		return global   # a constant list read where it is kept
	v = g.irValue(lw, at)   # a place, or a temporary the expression makes
	if v.len == 1:
		if g.irSteadyList(lw, at) and v[0] not in lw.steady: lw.steady.push(v[0])
		return v[0]
	lw.irFail("an address of {typeStr(tys, g.ty(e))}")
	-1

# whether e is a list a read parameter of the function lowered holds, itself or as a field of
# fields held in place (no box, no reference on the way: a shared value's fields change under
# other threads): the caller lent it for reading, so no call made while the function runs changes
# its length or items (not inside an inlined body, whose parameters are the caller's places)
fn irSteadyList(mut g Gen, lw IrLower, e NodeId):
	if not lw.rets.isEmpty or not g.irIsList(g.ty(e)): return false
	fnd = lw.fnd ?? return false
	at = e
	while nodes[at].kind == nField:
		at = nodes[at].kids(kidIds)[0]
		if g.tyK(g.ty(at)) != tStruct: return false
	nodes[at].kind == nIdent and
		nodes[fnd]
			.kids(kidIds)
			.any(nodes[it].kind == nParam and nodes[it].text == nodes[at].text and
					nodes[it].ival == modeRead)

# whether a value of type t is indexed by lane: a vector, or a struct of numbers of one type (Vec3)
fn irHasLanes(mut g Gen, maybeT TypeId?):
	if g.irIsVector(maybeT): return true
	t = maybeT ?? return false
	if tys[t].kind != tStruct or not g.irIsAggregate(t): return false
	fts = g.c.fieldTypesOf(declOf(tys, t))
	not fts.isEmpty and g.irClassOf(fts[0]) >= 0 and fts.all(isSameType(tys, it, fts[0]))

# a lane-indexed value's element type and how many lanes it has
fn irLaneShape(mut g Gen, t TypeId):
	if g.irIsVector(t): return (g.irVecElem(t), g.irVecLanes(t))
	(g.c.structFieldTypeAt(declOf(tys, t), 0), nodes[declOf(tys, t)].kids(kidIds).len)

# the value v of type t in a frame slot, for reading or writing one lane
fn irLaneSlot(mut g Gen, mut lw IrLower, t TypeId, v i64[]) i64:
	lw.irVecSlot(v[0]) if g.irIsVector(t) else g.irLentCopy(lw, t, v)

# v[i] of a lane-indexed value: the value in a slot, the index checked, the lane read there
fn irLaneRead(mut g Gen, mut lw IrLower, e NodeId) i64[]:
	vt = g.ty(nodes[e].kids(kidIds)[0])
	v = g.irValue(lw, nodes[e].kids(kidIds)[0])
	i = g.irExpr(lw, nodes[e].kids(kidIds)[1])
	if not lw.ok: return []
	elem, lanes = g.irLaneShape(vt)
	irPut(
		lw,
		IrInst(
			op = irFailIf,
			a = i,
			b = lw.irConstOf(irInt, lanes),
			cond = irGe,
			uns = true,
			imm = g.failBounds
		)
	)
	g.irLoadValue(lw, elem, g.irLaneSlot(lw, vt, v), i, g.sizeOf(elem))

# v[i] = x on a lane-indexed value: the value in a slot, the lane written there (the index
# checked), the value read back whole and stored where it came from
fn irStoreLane(mut g Gen, mut lw IrLower, at NodeId, value i64[]):
	vec = nodes[at].kids(kidIds)[0]
	vt = g.ty(vec)
	v = g.irValue(lw, vec)
	i = g.irExpr(lw, nodes[at].kids(kidIds)[1])
	if not lw.ok: return
	elem, lanes = g.irLaneShape(vt)
	irPut(
		lw,
		IrInst(
			op = irFailIf,
			a = i,
			b = lw.irConstOf(irInt, lanes),
			cond = irGe,
			uns = true,
			imm = g.failBounds
		)
	)
	slot = g.irLaneSlot(lw, vt, v)
	g.irStoreLeaves(lw, elem, slot, i, g.sizeOf(elem), 0, value)
	whole = g.irLoadValue(lw, vt, slot, -1, 0)
	if g.irIsVector(vt):
		whole = [lw.f.irVreg(irVec)]
		lw.irPut(IrInst(op = irLoad, dst = whole[0], a = slot, size = 32))
	g.irStoreTo(lw, vec, whole)

# xs[lo..hi] of a list, a str or a window: a window over [lo, hi), stopping unless
# 0 <= lo <= hi <= xs.len (two unsigned checks, which the optimizer drops where they pass)
fn irSlice(mut g Gen, mut lw IrLower, e NodeId, obj NodeId, lo NodeId, hi NodeId) i64:
	lt = g.irListType(obj)
	text = g.tyK(lt) == tStr
	list = -1
	items = -1
	n = -1
	if text:
		items, n = g.irTextWords(lw, obj)   # a str's words do not change
	else:
		list = g.irListAddr(lw, obj)
	from = g.irExpr(lw, lo)
	to = g.irExpr(lw, hi)
	if not lw.ok: return -1
	if not nodes[e].hasFlag(flagInBounds):   # proven inside (lengths.zap)
		if not text:
			n = lw.irHeader(list, 8)
		lw.irPut(IrInst(op = irFailIf, a = to, b = n, cond = irGt, uns = true, imm = g.failBounds))
		lw.irPut(
			IrInst(op = irFailIf, a = from, b = to, cond = irGt, uns = true, imm = g.failBounds)
		)
	stride = 1 if text else g.c.elemStride(innerOf(tys, lt))
	lw.irPatWindow(items if text else lw.irHeader(list, 0), from, to, stride)

# xs[i]'s place: the items' address, the index checked against the length, the element's type
fn irElement(mut g Gen, mut lw IrLower, e NodeId):
	lt = g.irListType(nodes[e].kids(kidIds)[0])   # a window's list as the list
	if g.tyK(lt) == tArray:
		# an array's elements where it is, the index checked against its fixed length
		at = g.irListAddr(lw, nodes[e].kids(kidIds)[0])
		i = g.irExpr(lw, nodes[e].kids(kidIds)[1])
		if not lw.ok: return (-1, -1, tyError)
		if g.c.spanInside(nodes[e].kids(kidIds)[1], 0, tys[lt].bits - 1) or e in lw.checked:   # its range lies inside, or checked ahead
			return (at, i, innerOf(tys, lt))
		irPut(
			lw,
			IrInst(
				op = irFailIf,
				a = i,
				b = lw.irConstOf(irInt, tys[lt].bits),
				cond = irGe,
				uns = true,
				imm = g.failBounds
			)
		)
		return (at, i, innerOf(tys, lt))
	if not g.irIsList(lt) and g.tyK(lt) != tStr:
		lw.irFail("index of {typeStr(tys, lt)}")
		return (-1, -1, tyError)
	elem = g.ty(e) if g.tyK(lt) == tStr else innerOf(tys, lt)   # a str: its bytes, laid out as a list's
	if g.tyK(lt) == tStr:
		bytes, length = g.irTextWords(lw, nodes[e].kids(kidIds)[0])
		at = g.irExpr(lw, nodes[e].kids(kidIds)[1])
		if not lw.ok: return (-1, -1, tyError)
		if not (
			e in lw.checked or nodes[e].hasFlag(flagInBounds) and nodes[e].hasFlag(flagInternal)
		):
			lw.irPut(
				IrInst(
					op = irFailIf,
					a = at,
					b = length,
					cond = irGe,
					uns = true,
					imm = g.failBounds
				)
			)
		return (bytes, at, elem)
	list = g.irListAddr(lw, nodes[e].kids(kidIds)[0])
	idx = g.irExpr(lw, nodes[e].kids(kidIds)[1])
	if not lw.ok: return (-1, -1, tyError)
	if lw.proven.find(.list == list and .index == idx) is p: return (p.addr, -1, elem)
	if e in lw.checked or nodes[e].hasFlag(flagInBounds):   # proven inside (stops.zap, lengths.zap)
		items = lw.irHeader(list, 0)
		return (items, idx, elem)
	n = lw.irHeader(list, 8)
	lw.irPut(IrInst(op = irFailIf, a = idx, b = n, cond = irGe, uns = true, imm = g.failBounds))
	items = lw.irHeader(list, 0)
	(items, idx, elem)

# a value of type t at items + idx * stride (idx -1: at items), leaf by leaf; for a type reached
# by address, that address
fn irLoadValue(mut g Gen, mut lw IrLower, t TypeId, items i64, idx i64, stride i64):
	if g.irByAddress(t):
		if idx < 0: return [items]
		a = lw.f.irVreg(irInt)
		lw.irPut(IrInst(op = irAdd, dst = a, a = items, b = lw.irScaled(idx, stride)))
		return [a]
	if not g.irTakes(t): return lw.irRefused("a value of {typeStr(tys, t)}")
	leaves = g.irLeaves(t, 0)
	scaled = idx < 0 or scaleBitsOf(stride) >= 0
	index = idx if scaled else lw.irScaled(idx, stride)
	out = []
	for i, leaf in leaves:
		v = g.irLeafVreg(lw, leaf.t)
		out.push(v)
		if g.irIsNicheTag(leaf.t): continue   # read from the value's word, next
		irPut(
			lw,
			IrInst(
				op = irLoad,
				dst = v,
				a = items,
				b = index,
				scale = u8(stride if scaled else 1),
				imm = leaf.off,
				size = i32(g.irLoadBytes(leaf.t)),
				uns = not g.irSigned(leaf.t)
			)
		)
		if i > 0 and g.irIsNicheTag(leaves[i - 1].t):
			g.irNicheTagOf(lw, innerOf(tys, leaves[i - 1].t), v, out[i - 1])
	out

# the bytes a load of a leaf of type t reads: a vector's own (a u8x16's 16, though its slot holds
# 32: what lies past it may be another's, or no memory)
fn irLoadBytes(mut g Gen, t TypeId) i64:
	g.irVecLanes(t) * g.sizeOf(g.irVecElem(t)) if g.irIsVector(t) else g.c.typeSize(t)

# idx times stride: a shift when stride is a power of two
fn irScaled(mut lw IrLower, idx i64, stride i64):
	v = lw.f.irVreg(irInt)
	if stride & (stride - 1) == 0:
		irPut(
			lw,
			IrInst(op = irShl, dst = v, a = idx, b = lw.irConstOf(irInt, stride.trailingZeros()))
		)
	else:
		lw.irPut(IrInst(op = irMul, dst = v, a = idx, b = lw.irConstOf(irInt, stride)))
	v

# value stored at target: element at of a list, or a field of it (`xs[i].p.x`)
fn irStoreElement(mut g Gen, mut lw IrLower, target NodeId, at NodeId, value i64[]):
	if target == at and g.irHasLanes(g.ty(nodes[at].kids(kidIds)[0])):
		g.irStoreLane(lw, at, value)
		return
	items, idx, elem = g.irElement(lw, at)
	if not lw.ok: return
	stride = g.c.elemStride(elem)
	t, base = g.irFieldPath(target, at, elem)
	if g.irOwnedByAddress(t):
		g.irPutOwned(lw, lw.irElementAddr(items, idx, stride, base), t, value, true)
		return
	if g.irIsOwnedWord(t) and value.len == 1:
		# a map's or box's word replaced: the old one dropped, the new one the element's
		place = lw.irElementAddr(items, idx, stride, base)
		lw.irPut(IrInst(op = irDrop, a = place, ty = t))
		given = g.irGiveWordOf(lw, t, value[0])
		if given < 0:
			lw.irFail("a {typeStr(tys, t)} stored, not owned here")
			return
		lw.irPut(IrInst(op = irStore, a = place, c = given))
		return
	if g.irByAddress(t) and not g.isOwningType(t) and value.len == 1:
		irPut(   # its bytes
			lw,
			IrInst(
				op = irMemCopy,
				a = lw.irElementAddr(items, idx, stride, base),
				b = value[0],
				imm = g.sizeOf(t)
			)
		)
		return
	if not g.irTakes(t):
		lw.irFail("a store of {typeStr(tys, t)}")   # one that owns memory: ownership's
		return
	scaled = idx < 0 or scaleBitsOf(stride) >= 0
	irStoreLeaves(
		g,
		lw,
		t,
		items,
		idx if scaled else lw.irScaled(idx, stride),
		stride if scaled else 1,
		base,
		value
	)

# the address of the element idx of items (idx -1: items is it), plus base
fn irElementAddr(mut lw IrLower, items i64, idx i64, stride i64, base i64) i64:
	at = items
	if idx >= 0:
		at = lw.f.irVreg(irInt)   # numbered before the scaled index's: the registers given stay
		lw.irPut(IrInst(op = irAdd, dst = at, a = items, b = lw.irScaled(idx, stride)))
	if base == 0: return at
	lw.irDef(irInt, IrInst(op = irAdd, a = at, b = lw.irConstOf(irInt, base)))

# x ?? y where x is an optional reference to a struct of numbers and the struct is wanted: its
# leaves read through the reference when there is one, else y's (read only then); or where x is a
# scalar's optional and y one of the same type: x when it holds a value, else y
fn irCoalesceLeaves(mut g Gen, mut lw IrLower, e NodeId, t TypeId):
	l = nodes[e].kids(kidIds)[0]
	o = g.irOptionParts(lw, l)
	if not lw.ok or o.len != 2: return lw.irRefused("optional of {typeStr(tys, g.ty(l))}")
	result = g.irNewValue(lw, t)
	way = lw.irSplitNZ(o[0])
	if isSameType(tys, t, g.ty(l)):
		lw.irCopyValue(result, o)
	elif g.c.isOptionOfRef(g.ty(l)):
		lw.irCopyValue(result, g.irLoadValue(lw, t, o[1], -1, 0))
	else:
		lw.irCopyValue(result, [o[1]])   # an enum's word: the variant's number
	lw.f.irJumpTo(way.end)
	taken = lw.owned.copy()
	lw.f.irEnter(way.no)
	alt = g.irValue(lw, nodes[e].kids(kidIds)[1])   # a return here leaves the function instead
	if not lw.ok: return []
	if not lw.f.irEnded() and not g.irNever(nodes[e].kids(kidIds)[1]):
		lw.irCopyValue(result, alt)
	lw.irFallbackLeft(taken)
	lw.f.irJoin(way.end)
	result

# whether e never gives a value: its type is unit where one is wanted (fail(...), exit(...))
fn irNever(mut g Gen, e NodeId):
	g.tyK(g.ty(e)) == tUnit

# the else side of x ?? y, evaluated where x has no value and put into result
fn irCoalesceAlternative(mut g Gen, mut lw IrLower, e NodeId, t TypeId, result i64[], owned bool):
	alt = g.irAs(lw, g.irValue(lw, nodes[e].kids(kidIds)[1]), t)   # a plain fallback of an optional of optional
	if not lw.f.irEnded() and not g.irNever(nodes[e].kids(kidIds)[1]):
		if not g.irIsPlaceNode(nodes[e].kids(kidIds)[1]):
			g.irArmInto(lw, t, result, alt)
		elif g.irTakes(t):
			lw.irCopyValue(result, alt)   # a place's box lent, as the optional's is
		elif owned:
			irPut(   # the place keeps its own
				lw,
				IrInst(
					op = irDeepCopy,
					a = result[0],
					b = alt[0],
					ty = t,
					key = g.irPathOf(lw, nodes[e].kids(kidIds)[1])
				)
			)
		else:
			g.irArmInto(lw, t, result, alt)

# x ?? y of an optional reference to a struct the form reaches by its address (one too large to
# be an aggregate of leaves): the struct x refers to is copied when there is one, else y
fn irCoalesceRef(mut g Gen, mut lw IrLower, e NodeId, t TypeId):
	o = g.irOptionParts(lw, nodes[e].kids(kidIds)[0])
	if not lw.ok or o.len != 2:
		return lw.irRefused("optional of {typeStr(tys, g.ty(nodes[e].kids(kidIds)[0]))}")
	owned = g.isOwningType(t)
	result = g.irNewResult(lw, t)
	before = lw.owned.copy()
	way = lw.irSplitNZ(o[0])
	if owned:
		lw.irPut(IrInst(op = irDeepCopy, a = result[0], b = o[1], ty = t))   # the place keeps its own
	else:
		lw.irPut(IrInst(op = irMemCopy, a = result[0], b = o[1], imm = g.sizeOf(t)))
	lw.f.irJumpTo(way.end)
	taken = lw.owned.copy()
	lw.f.irEnter(way.no)
	lw.irFallbackEntered(before)
	g.irCoalesceAlternative(lw, e, t, result, owned)
	lw.irFallbackLeft(taken)
	lw.f.irJoin(way.end)
	result

# x ?? y of an optional in memory: x's value when it has one (moved out of a temporary that owns
# it), else y (read only then; a place keeps its value); a place's, where y never gives one, lent
# (the address of its payload, never a copy)
fn irCoalesce(mut g Gen, mut lw IrLower, e NodeId, t TypeId):
	a = g.irAddressOf(lw, nodes[e].kids(kidIds)[0])
	if not lw.ok: return []
	owned = g.isOwningType(t)
	# a temporary's value moves out; a name never is one, though an inlined parameter may stand
	# for the caller's temporary (irMatchPatterns)
	temporary = not g.irIsPlaceNode(nodes[e].kids(kidIds)[0]) and
		lw.owned.any(.slot == a and .name < 0)
	ot = g.ty(nodes[e].kids(kidIds)[0])
	lent = owned and not temporary and g.irByAddress(t) and not isSameType(tys, t, ot) and
		g.irNever(nodes[e].kids(kidIds)[1]) and g.irNamesPlace(lw, nodes[e].kids(kidIds)[0])
	result = [lw.f.irVreg(irInt)] if lent else g.irNewResult(lw, t)
	tag = g.irTagAt(lw, ot, a)
	before = lw.owned.copy()
	way = lw.irSplitNZ(tag)
	# the optional's value, or (b an optional of the same type) the optional itself
	payload = a if isSameType(tys, t, ot) else lw.irElementAddr(a, -1, 0, g.c.optionPayload(ot))
	if g.irTakes(t):
		lw.irCopyValue(result, g.irLoadValue(lw, t, payload, -1, 0))
	elif lent:
		lw.irPut(IrInst(op = irCopy, dst = result[0], a = payload))
	elif owned and temporary:
		g.irMoveTo(lw, result[0], payload, t)   # the temporary keeps an empty value
	elif owned:
		irPut(   # the place keeps its own
			lw,
			IrInst(
				op = irDeepCopy,
				a = result[0],
				b = payload,
				ty = t,
				key = g.irPathOf(lw, nodes[e].kids(kidIds)[0])
			)
		)
	else:
		lw.irPut(IrInst(op = irMemCopy, a = result[0], b = payload, imm = g.sizeOf(t)))
	lw.f.irJumpTo(way.end)
	taken = lw.owned.copy()
	lw.f.irEnter(way.no)
	lw.irFallbackEntered(before)
	g.irCoalesceAlternative(lw, e, t, result, owned)
	lw.irFallbackLeft(taken)
	lw.f.irJoin(way.end)
	result
