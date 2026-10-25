# The lowering of expressions: names, fields, literals, operators and conversions (irlower.zap).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# a scalar's vreg
fn irExpr(mut g Gen, mut lw IrLower, e NodeId):
	value = g.irValue(lw, e)
	if not lw.ok: return -1
	if value.len == 1 and g.tyK(g.ty(e)) == tStruct and
		nodes[declOf(tys, g.ty(e))].hasFlag(flagShared):
		return value[0]   # a shared value in memory: its address is its counted pointer
	if value.len != 1 or g.irClassOf(g.ty(e)) < 0:
		lw.irFail("scalar of type {typeStr(tys, g.ty(e))} (node kind {nodes[e].kind} '{nodes[e].text}', {value.len} leaves)")
		return -1
	value[0]

# the character vec.zap's generics take as the operator: + - * /
fn opChar(op i64):
	if op == binAdd: return 43
	if op == binSub: return 45
	if op == binMul: return 42
	47

# the number type of a math operator on lists of numbers (a vector or a matrix on either side),
# or none
fn irListMathElem(mut g Gen, e NodeId) TypeId?:
	for side in nodes[e].kids(kidIds).copy():
		st = g.ty(side)
		if g.c.numMatrixElem(st) is m: return m
		if g.c.numListElem(st) is l: return l
	none

# the math operators on lists of numbers, each a generic runtime function of the number type
# (vec.zap): @ as matMul, matVec or vecDot, the rest element by element (vecEw, matEw) or by a
# number (vecScalar, matScalar; the number after the list, both evaluated in the order written)
fn irListMath(mut g Gen, mut lw IrLower, e NodeId) i64[]:
	op = nodes[e].ival
	l = nodes[e].kids(kidIds)[0]
	r = nodes[e].kids(kidIds)[1]
	lm = g.c.numMatrixElem(g.ty(l))
	rm = g.c.numMatrixElem(g.ty(r))
	elem = g.irListMathElem(e) ?? return lw.irRefused("list math")
	if op == binMatmul:
		name = "matMul" if lm != none and rm != none else "matVec" if lm != none else "vecDot"
		a = g.irListAddr(lw, l)
		b = g.irListAddr(lw, r)
		if not lw.ok: return []
		return g.irRtInstanceValues(lw, name, [elem], [a, b])
	mat = lm != none or rm != none
	code = lw.irConstOf(irInt, opChar(op))
	lScalar = g.tyK(g.ty(l)) != tList
	rScalar = g.tyK(g.ty(r)) != tList
	if lScalar or rScalar:
		list = -1
		num = -1
		if lScalar:
			num = g.irExpr(lw, l)
			list = g.irListAddr(lw, r)
		else:
			list = g.irListAddr(lw, l)
			num = g.irExpr(lw, r)
		if not lw.ok: return []
		return irRtInstanceValues(
			g,
			lw,
			"matScalar" if mat else "vecScalar",
			[elem],
			[list, num, code]
		)
	a = g.irListAddr(lw, l)
	b = g.irListAddr(lw, r)
	if not lw.ok: return []
	g.irRtInstanceValues(lw, "matEw" if mat else "vecEw", [elem], [a, b, code])

# e's leaves
fn irValue(mut g Gen, mut lw IrLower, e NodeId):
	if not lw.ok: return []
	k = nodes[e].kind
	t = g.irMatchType(lw, e) if k == nMatch else typeOf(nodes, e)   # (a tail the checker left untyped)
	class = g.irClassOf(t)
	if g.irValueCopied(lw, e, k, t, class) is v: return v
	if g.irValueOperator(lw, e, k, t, class) is v: return v
	if g.irValueConstruct(lw, e, k, t, class) is v: return v
	if g.irValueControl(lw, e, k, t, class) is v: return v
	lw.irFail("expression kind {k}")
	[]

# implicit copies, literals, names, lambdas, references and fields, or none
fn irValueCopied(mut g Gen, mut lw IrLower, e NodeId, k i64, t TypeId, class i64) i64[]?:
	if g.irFlagged(e, flagAutoCopy) and g.tyK(t) == tBox and tys[t].counted:
		# a shared value copied: one more owner, its count (the word before it) up by one
		g.irUnmark(e, flagAutoCopy)
		word = g.irExpr(lw, e)
		g.irMark(e, flagAutoCopy)
		if not lw.ok: return irNoLeaves()
		count = lw.irDef(irInt, IrInst(op = irAdd, a = word, b = lw.irConstOf(irInt, -8)))
		lw.irDef(irInt, IrInst(op = irXadd, a = count, b = lw.irConstOf(irInt, 1)))
		copy = lw.irDef(irInt, IrInst(op = irCopy, a = word))
		if k == nIdent:
			lw.irArenaMovedName(lw.irLookupAt(nodes[e].text), t)   # one more owner of an arena's value
		g.irOwnedWord(lw, t, copy)
		return [copy]
	if g.irFlagged(e, flagAutoCopy) and g.isOwningType(t):
		return lw.irRefused("an implicit copy of {typeStr(tys, t)}")
	if k == nInt:
		if class == irFloat:
			return [lw.irConstOf(irFloat, i64(f64(i64.parse(nodes[e].text) ?? 0).toBits()))]
		return [lw.irConstOf(irInt, g.intLitValue(e))]
	if k == nFloat: return [lw.irConstOf(irFloat, g.floatLitBits(e))]
	if k == nBool: return [lw.irConstOf(irInt, nodes[e].ival)]
	if k == nIdent and nodes[e].hasFlag(flagFnRef) and g.tyK(t) == tFn and
		g.irFind(lw, nodes[e].text.copy()) == none and not g.irFieldOfThis(lw, nodes[e].text):
		return g.irFnValue(lw, e)
	if k == nIdent:
		named = g.irPlaced(lw, e, g.irName(lw, e))
		for x in named:
			lw.namedBy[x] = i64(e)
		return named
	if k == nLambda:
		if not g.irFlagged(e, flagBorrowLambda):
			g.irKeptLambda(lw, e)
		return g.irClosure(lw, e)
	if k == nDeref: return g.irPlaced(lw, e, g.irDeref(lw, nodes[e].kids(kidIds)[0]))
	if k == nUnary and (nodes[e].ival == unRef or nodes[e].ival == unMutRef):
		out = g.irReference(lw, e)
		if nodes[e].ival == unMutRef:
			g.irNoteChange(lw, nodes[e].kids(kidIds)[0])   # a mutable reference: no other use of the place
		return out
	if k == nUnary and nodes[e].ival == unMove: return g.irMoveOut(lw, nodes[e].kids(kidIds)[0])
	if k == nField and g.irVariantOf(e, t) >= 0: return g.irVariant(lw, e, t, [])
	if k == nField and nodes[e].hasFlag(flagSafe): return g.irSafeField(lw, e)
	if k == nField: return g.irPlaced(lw, e, g.irField(lw, e))
	none

# unary and binary operators, if, index and struct literals, or none
fn irValueOperator(mut g Gen, mut lw IrLower, e NodeId, k i64, t TypeId, class i64) i64[]?:
	if k == nUnary and g.tyK(t) != tStruct: return [g.irUnary(lw, e, class)]
	if k == nBinary and g.tyK(t) == tStruct and
		(nodes[e].ival in [binAdd, binSub, binMul, binDiv]):
		fnd = g.derivedFn(g.arithFamily(e), t) ?? return lw.irRefused("struct arithmetic")
		args = [nodes[e].kids(kidIds)[0], nodes[e].kids(kidIds)[1]]
		if g.irInlines(lw, fnd):
			if g.irTryInline(lw, fnd, none, none, args) is v: return v.copy()
		if not g.irCallable(fnd, false):
			return lw.irRefused("struct arithmetic by {nodes[fnd].text}")
		return g.irCallTo(lw, fnd, nodes[fnd].text.copy(), args)
	if k == nBinary and class == irVec: return g.irVecBinary(lw, e)
	if k == nBinary:
		if nodes[e].ival == binCoalesce and g.irIsTaggedOption(g.ty(nodes[e].kids(kidIds)[0])):
			return g.irCoalesce(lw, e, t)
		if nodes[e].ival == binAdd and g.irIsStr(t):
			at = lw.owned.len
			a = g.irStrAddr(lw, nodes[e].kids(kidIds)[0])
			v = g.irCallRt(lw, "strConcat", [a, g.irStrAddr(lw, nodes[e].kids(kidIds)[1])])
			g.irDropArgTemps(lw, at, t, v)   # the sides' temporaries die with the concatenation
			return v
		if nodes[e].ival == binCoalesce and g.irIsLeafOption(g.ty(nodes[e].kids(kidIds)[0])) and
			(
				g.irIsAggregate(t) or
					g.irIsOption(t) and isSameType(tys, t, g.ty(nodes[e].kids(kidIds)[0]))
			):
			return g.irCoalesceLeaves(lw, e, t)
		if nodes[e].ival == binCoalesce and g.irIsLeafOption(g.ty(nodes[e].kids(kidIds)[0])) and
			g.c.isOptionOfRef(g.ty(nodes[e].kids(kidIds)[0])) and g.irIsPlaceStruct(t):
			return g.irCoalesceRef(lw, e, t)
		if nodes[e].ival <= binMatmul and nodes[e].ival != binMod and nodes[e].ival != binPow and   # + - * / @ of lists of numbers
			g.irListMathElem(e) != none:
			return g.irListMath(lw, e)
		if class < 0: return lw.irRefused("an operation on {typeStr(tys, t)}")
		return [g.irBinary(lw, e, class)]
	none

# literals and options (some, none), or none
fn irValueConstruct(mut g Gen, mut lw IrLower, e NodeId, k i64, t TypeId, class i64) i64[]?:
	if k == nIf and nodes[e].sub().len > 1: return g.irIf(lw, e, true)
	if k == nMatch and g.irIsChoice(e): return g.irChoice(lw, e)
	if k == nIndex and g.irHasLanes(g.ty(nodes[e].kids(kidIds)[0])): return g.irLaneRead(lw, e)
	if k == nIndex:
		items, idx, elem = g.irElement(lw, e)
		if not lw.ok: return irNoLeaves()
		return g.irPlaced(lw, e, g.irLoadValue(lw, elem, items, idx, g.c.elemStride(elem)))
	if k == nStructLit: return g.irStructLit(lw, e)
	if k == nArray and g.tyK(t) == tList: return [g.irListLiteral(lw, e)]
	if k == nArray and g.tyK(t) == tArray: return [g.irArrayLiteral(lw, e, t)]
	if k == nStr: return [g.irStrLiteral(lw, nodes[e].text.copy())]
	if k == nInterp: return g.irInterpolation(lw, e)
	if k == nSome and g.irIsOption(t):
		some = [lw.irConstOf(irInt, 1)]
		some.extend(g.irValue(lw, nodes[e].kids(kidIds)[0]))
		return some
	if k == nNone and g.irIsOption(t):
		return [lw.irConstOf(irInt, 0), lw.irConstOf(g.irClassOf(tys[t].inner), 0)]
	if (k == nSome or k == nNone) and g.c.isNicheOption(t):
		if k == nSome: return g.irValue(lw, nodes[e].kids(kidIds)[0])   # the value's word
		return [g.irNoneWord(lw, t)]
	if k == nSome and g.irIsResult(t):
		return [g.irWrapResult(lw, t, nodes[e].ival == 1, g.irValue(lw, nodes[e].kids(kidIds)[0]))]
	if (k == nSome or k == nNone) and g.irIsTaggedOption(t):
		value = g.irValue(lw, nodes[e].kids(kidIds)[0]) if k == nSome else []
		if k == nSome and g.isTextWindow(innerOf(tys, t)) and
			g.tyK(g.ty(nodes[e].kids(kidIds)[0])) == tStr and
			value.len == 1:
			value = [lw.irStrAsWindow(value[0])]
		slot = g.irZeroedSlot(lw, t)
		if k == nSome:
			g.irPutValue(lw, g.irSomeAt(lw, t, slot), innerOf(tys, t), value)
		else:
			g.irMarkNone(lw, t, slot)
		return [slot]
	none

# matches, calls, maps, jumps and try, or none
fn irValueControl(mut g Gen, mut lw IrLower, e NodeId, k i64, t TypeId, class i64) i64[]?:
	if k == nMatch and g.irIsBindMatch(e): return g.irBindMatch(lw, e, g.tyK(t) != tUnit)
	if k == nMatch:
		return irMatchPatterns(
			g,
			lw,
			e,
			g.tyK(t) != tUnit and (g.irTakes(t) or g.irByAddress(t))
		)
	if k == nCall:
		at = lw.owned.len
		v = g.irCallOf(lw, e)
		g.irDropArgTemps(lw, at, t, v)   # the arguments' temporaries die with the call
		return v
	if k == nMapLit: return g.irMapLit(lw, e)
	if k in [nReturn, nBreak, nContinue]:
		g.irStmtOnly(lw, e)   # `?? continue`: it leaves, giving no value
		return irNoLeaves()
	if k == nTry: return g.irTry(lw, e)
	none

# What a reference points to: the target's address when the target is reached by address (the
# reference is that address), else its leaves read from where it points. A dereference the
# checker wrote on a generic template, in an instance where the operand is no reference, stands
# for its operand (a window is read where it is).
fn irDeref(mut g Gen, mut lw IrLower, kid NodeId) i64[]:
	rt = g.ty(kid)
	value = g.irOptionParts(lw, kid) if g.c.isOptionOfRef(rt) else g.irValue(lw, kid)
	if not lw.ok: return []
	if g.isTextWindow(rt) and value.len == 1: return [lw.irWindowAsStr(value[0])]   # read as a str
	if g.c.isOptionOfRef(rt) and g.isTextWindow(innerOf(tys, rt)) and value.len == 1:
		# an optional window read as an optional str: its tag and two words, a third word 0 (room 0)
		st = g.c.derefType(rt)
		slot = lw.f.irVreg(irInt)
		lw.irPut(IrInst(op = irFrameSlot, dst = slot, imm = g.sizeOf(st)))
		lw.irPut(IrInst(op = irMemCopy, a = slot, b = value[0], imm = g.sizeOf(rt)))
		lw.irZeroGap(slot, -1, 1, g.sizeOf(rt), g.sizeOf(st) - g.sizeOf(rt), lw.irConstOf(irInt, 0))
		return [slot]
	if g.c.isOptionOfRef(rt) and not g.c.refIsWindow(innerOf(tys, rt)) and value.len == 2:
		# an optional reference read as an optional value: the target read only when there is one
		target = innerOf(tys, tys[rt].inner)
		if g.irByAddress(target) or not g.irTakes(target):
			return lw.irRefused("an optional reference to {typeStr(tys, target)} read")
		if g.irLeafCount(target) != 1: return g.irDerefAggregateOption(lw, g.c.derefType(rt), value)
		out = lw.f.irVreg(g.irClassOf(target))
		lw.irPut(IrInst(op = irConst, dst = out, imm = 0))
		way = lw.irSplitNZ(value[0], false)
		lw.irCopyValue([out], g.irLoadValue(lw, target, value[1], -1, 0))
		lw.f.irJoin(way.end)
		return [lw.irBoolOf(value[0]), out]
	if g.tyK(rt) == tBox and value.len == 1 and not g.irByAddress(tys[rt].inner) and
		g.irTakes(tys[rt].inner):
		return g.irLoadValue(lw, innerOf(tys, rt), value[0], -1, 0)   # a box of numbers: its value read through the word
	if g.tyK(rt) != tRef or g.c.refIsWindow(rt): return value
	inner = innerOf(tys, rt)
	if g.irByAddress(inner): return value
	if value.len != 1: return lw.irRefused("a reference of {value.len} leaves")
	g.irLoadValue(lw, inner, value[0], -1, 0)

# An optional reference to a struct of numbers read as an optional value (kept in memory): the
# struct copied into the optional when the reference holds an address, else none. pointer is the
# reference's tag and address.
fn irDerefAggregateOption(mut g Gen, mut lw IrLower, opt TypeId, pointer i64[]):
	if not g.irIsTaggedOption(opt):
		return lw.irRefused("an optional reference read as {typeStr(tys, opt)}")
	target = innerOf(tys, opt)
	zero = lw.irConstOf(irInt, 0)
	slot = g.irResultSlot(lw, opt)
	lw.irZeroGap(slot, -1, 1, 0, g.sizeOf(opt).alignUp(8), zero)
	g.irMarkNone(lw, opt, slot)
	yes = lw.f.irBlock()
	end = lw.f.irBlock()
	lw.irBranchIf(pointer[0], irNe, zero, yes, end)
	lw.f.irEnter(yes)
	payload = g.irSomeAt(lw, opt, slot)
	g.irStoreLeaves(lw, target, payload, -1, 1, 0, g.irLoadValue(lw, target, pointer[1], -1, 0))
	lw.f.irJoin(end)
	[slot]

# the address of the field path from target down to the element root (xs[i].a.b): the items,
# the index checked, the field's offset in the element
fn irElementFieldAddr(mut g Gen, mut lw IrLower, target NodeId, root NodeId) i64:
	items, idx, elem = g.irElement(lw, root)
	if not lw.ok: return -1
	_, base = g.irFieldPath(target, root, elem)
	lw.irElementAddr(items, idx, g.c.elemStride(elem), base)

# a reference to a place (`ref x`): its address, which a target in memory has (a value reached by
# address, a field or an element in memory); the value itself where the reference is a window
fn irReference(mut g Gen, mut lw IrLower, e NodeId) i64[]:
	kid = nodes[e].kids(kidIds)[0]
	t = g.ty(e)
	if g.isTextWindow(t) and g.tyK(g.ty(kid)) == tStr:
		a = g.irListAddr(lw, kid)
		return [lw.irStrAsWindow(a)] if lw.ok else []
	if g.tyK(t) != tRef or g.c.refIsWindow(t) or g.irByAddress(g.ty(kid)): return g.irValue(lw, kid)
	if g.irMemPlace(lw, kid) is mem:
		addr, _ = mem
		return [addr]
	root = kid
	while nodes[root].kind == nField:
		root = nodes[root].kids(kidIds)[0]
	if nodes[root].kind == nIndex:
		at = g.irElementFieldAddr(lw, kid, root)
		return [at] if lw.ok else []
	if nodes[root].kind == nIdent and lw.thisType is selfType and g.irIsAggregate(selfType) and
		g.irFieldOfThis(lw, nodes[root].text) and lw.irLookup(nodes[root].text) == none and
		lw.mutScalars.find(.ty == selfType) is ms:
		# a field of this, a struct of numbers the method changes: the caller's struct, at the
		# address passed, brought up to date first (the leaves are written back on the way out too)
		g.irStoreLeaves(lw, selfType, ms.addr, -1, 1, 0, ms.leaves)
		sd = declOf(tys, selfType)
		fi = g.c.fieldIndexOf(sd, nodes[root].text)
		_, more = g.irFieldPath(kid, root, g.c.structFieldTypeAt(sd, fi))
		return [lw.irElementAddr(ms.addr, -1, 0, g.c.structFieldOffsets(sd)[fi] + more)]
	rt = g.ty(root)
	if nodes[root].kind == nIdent and nodes[e].ival == unRef and g.irTakes(rt) and
		not g.irIsOwnedWord(rt) and g.irFind(lw, nodes[root].text.copy()) is leaves:
		# a local of numbers read through the reference (an extern writes through it too): in a
		# slot kept in step with its leaves around calls
		if leaves.isEmpty: return lw.irRefused("a reference to {nodes[root].text}")
		_, off = g.irFieldPath(kid, root, rt)
		return [lw.irElementAddr(g.irSpillSlot(lw, leaves, rt), -1, 0, off)]
	lw.irFail("a reference to a value held in registers")
	[]

# a name: a local's leaves, a field of this named alone, or a constant
fn irName(mut g Gen, mut lw IrLower, e NodeId):
	gi = lw.irGivenAt(nodes[e].text)
	if gi >= 0: return [g.irGivenValue(lw, lw.given[gi].copy())]   # read as a value: a closure whole
	if g.irFind(lw, nodes[e].text.copy()) is v: return v
	if lw.thisType is selfType and g.c.fieldIndexOf(declOf(tys, selfType), nodes[e].text) >= 0 and
		g.irFind(lw, "self") is recv:
		return g.irFieldOf(
			lw,
			recv,
			selfType,
			g.c.fieldIndexOf(declOf(tys, selfType), nodes[e].text)
		)
	if g.irClassOf(g.ty(e)) == irInt and g.isIntLit(e):
		return [lw.irConstOf(irInt, g.intLitValue(e))]
	if g.irGlobal(lw, e) is at:
		gd = g.c.findDeclByGlobalName(nConstDecl, nodes[e].text) ??
			return lw.irRefused("no global {nodes[e].text}")
		if not nodes[gd].hasFlag(flagMut) and not nodes[gd].hasFlag(flagOrdered) and
			not g.c.isShared(g.ty(e)) and not g.irIsOwnedWord(g.ty(e)):   # a constant as a whole value: a fresh one (a map is kept: an element lent from a fresh one would outlive it)
			return g.irValue(lw, nodes[gd].kids(kidIds)[0])
		kept = g.irLoadValue(lw, g.ty(e), at, -1, 0)
		if nodes[gd].hasFlag(flagMut) or g.irIsOwnedWord(g.ty(e)) or not lw.ok: return kept
		return g.irOwnedCopyOf(lw, g.ty(e), kept)   # an immutable binding taken whole: one's own, as a constant's
	d = g.isConstName(nodes[e].text)
	if d is d and not nodes[d].kids(kidIds).isEmpty and
		nodes[nodes[d].kids(kidIds)[0]].kind == nStr:
		return [g.irStrLiteral(lw, nodes[nodes[d].kids(kidIds)[0]].text.copy())]   # a str constant: its literal
	if d is d and not nodes[d].kids(kidIds).isEmpty:
		return g.irValue(lw, nodes[d].kids(kidIds)[0])   # a constant computed from others: its expression
	lw.irFail("name {nodes[e].text}")
	[]

# the address of the module variable or constant list e names (kept in the data area), when no
# local or field of this takes its name
fn irGlobal(mut g Gen, mut lw IrLower, e NodeId) i64?:
	if nodes[e].kind != nIdent or g.globalOf(nodes[e].text) < 0 or
		lw.irLookup(nodes[e].text) != none:
		return none
	if lw.thisType != none and g.c.fieldIndexOf(declOf(tys, lw.thisType), nodes[e].text) >= 0:
		return none
	if nodes[e].text not in g.globalsNamed:
		g.globalsNamed[nodes[e].text.copy()] = true
	lw.irDef(irInt, IrInst(op = irDataAddr, imm = g.globalOf(nodes[e].text)))

# obj.f of a struct of numbers: the field's leaves among obj's
fn irField(mut g Gen, mut lw IrLower, e NodeId) i64[]:
	obj = nodes[e].kids(kidIds)[0]
	ot = g.ty(obj)
	if g.tyK(ot) == tRef or g.tyK(ot) == tBox:
		ot = innerOf(tys, ot)   # through a reference or a box: the value it points to
	if not g.irIsAggregate(ot) and not g.irIsPlaceStruct(ot):
		return lw.irRefused("field of {typeStr(tys, ot)}")
	fi = g.c.fieldIndexOf(declOf(tys, ot), nodes[e].text)
	if fi < 0: return lw.irRefused("field {nodes[e].text}")
	whole = g.irDeref(lw, obj)   # through a reference, the struct it points to
	if not g.irIsPlaceNode(obj) and g.tyK(g.ty(obj)) == tStruct and whole.len == 1 and
		lw.owned.any(.slot == whole[0] and .name < 0):
		return g.irFieldMovedOut(lw, whole[0], ot, fi)
	g.irFieldOf(lw, whole, ot, fi)

# obj?.field: none stays none, else some(obj.field); obj an optional of a struct, or of a
# reference or a box to one. A field that owns memory is deep-copied (it stays with its owner).
fn irSafeField(mut g Gen, mut lw IrLower, e NodeId):
	obj = nodes[e].kids(kidIds)[0]
	ot = g.ty(obj)
	t = g.ty(e)
	if g.tyK(ot) != tOption or g.tyK(t) != tOption: return lw.irRefused("?. on {typeStr(tys, ot)}")
	inner = innerOf(tys, ot)
	tag = -1
	base = -1   # the struct's address when there is one
	if g.irIsOption(ot):
		o = g.irValue(lw, obj)
		if not lw.ok or o.len != 2: return []
		tag = o[0]
		base = o[1]
	elif g.irIsTaggedOption(ot):
		a = g.irAddressOf(lw, obj)
		if not lw.ok: return []
		tag, base = g.irOptionAt(lw, ot, a)
		if g.tyK(inner) == tRef or g.tyK(inner) == tBox:
			p = lw.irDef(irInt, IrInst(op = irLoad, a = base))   # the payload points at the struct
			base = p
	elif g.c.isNicheOption(ot):
		base = g.irExpr(lw, obj)   # the word without a tag: the value's address, 0 for none
		tag = g.irTagOf(lw, ot, base)
	else:
		return lw.irRefused("?. on {typeStr(tys, ot)}")
	if not lw.ok: return []
	st = inner
	if g.tyK(st) == tRef or g.tyK(st) == tBox:
		st = innerOf(tys, st)
	fi = g.c.fieldIndexOf(declOf(tys, st), nodes[e].text) if g.tyK(st) == tStruct else -1
	if fi < 0: return lw.irRefused("?.{nodes[e].text} of {typeStr(tys, st)}")
	ft = g.c.structFieldTypeAt(declOf(tys, st), fi)
	at = lw.irElementAddr(base, -1, 0, g.c.structFieldOffsets(declOf(tys, st))[fi])
	yes = lw.f.irBlock()
	end = lw.f.irBlock()
	zero = lw.irConstOf(irInt, 0)
	if g.irIsOption(t):
		v = lw.f.irVreg(g.irClassOf(ft))
		lw.irPut(IrInst(op = irConst, dst = v, imm = 0))
		lw.irBranchIf(tag, irNe, zero, yes, end)
		lw.f.irEnter(yes)
		lw.irCopyValue([v], g.irLoadValue(lw, ft, at, -1, 0))
		lw.f.irJoin(end)
		return [lw.irBoolOf(tag), v]
	if not g.irIsTaggedOption(t): return lw.irRefused("?. giving {typeStr(tys, t)}")
	slot = g.irResultSlot(lw, t)
	lw.irZeroGap(slot, -1, 1, 0, g.sizeOf(t).alignUp(8), zero)
	g.irMarkNone(lw, t, slot)
	lw.irBranchIf(tag, irNe, zero, yes, end)
	lw.f.irEnter(yes)
	payload = g.irSomeAt(lw, t, slot)
	if g.irTakes(ft):
		g.irStoreLeaves(lw, ft, payload, -1, 1, 0, g.irLoadValue(lw, ft, at, -1, 0))
	elif g.isOwningType(ft):
		lw.irPut(IrInst(op = irDeepCopy, a = payload, b = at, ty = ft))
	else:
		lw.irPut(IrInst(op = irMemCopy, a = payload, b = at, imm = g.sizeOf(ft)))
	lw.f.irJoin(end)
	[slot]

# field fi of a value of struct type t: its leaves among a struct of numbers', or, of a place
# struct (one leaf, its address), the field's address (a list, a place struct) or its value read
fn irFieldOf(mut g Gen, mut lw IrLower, whole i64[], t TypeId, fi i64) i64[]:
	if g.irIsAggregate(t):
		start, n = g.irFieldSpan(t, fi)
		if whole.len < start + n: return []
		return whole[start..start + n].copy()
	if whole.len != 1: return []
	ft = g.c.structFieldTypeAt(declOf(tys, t), fi)
	if g.c.isExternType(declOf(tys, t)) and g.c.isCPointer(ft):
		return lw.irRefused("a C pointer field read")
	addr = g.irFieldAddr(lw, whole[0], t, fi)
	if g.irByAddress(ft): return [addr]
	g.irLoadValue(lw, ft, addr, -1, 0)

# field fi of the temporary struct at base: a part that owns memory moves out of it (which keeps
# an empty value), unless the struct's drop function reads it
fn irFieldMovedOut(mut g Gen, mut lw IrLower, base i64, t TypeId, fi i64):
	ft = g.c.structFieldTypeAt(declOf(tys, t), fi)
	if g.irIsOwnedWord(ft) and not nodes[declOf(tys, t)].hasFlag(flagDrop):
		# a map (or box): its word taken, the temporary keeps an empty one, and the statement owns it
		word = g.irWordMovedOut(lw, ft, g.irFieldAddr(lw, base, t, fi))
		g.irOwnedWord(lw, ft, word)
		return [word]
	if not g.irOwnedByAddress(ft) or nodes[declOf(tys, t)].hasFlag(flagDrop):
		return g.irFieldOf(lw, [base], t, fi)
	addr = g.irFieldAddr(lw, base, t, fi)
	taken = g.irTemporary(lw, ft)
	lw.irPut(IrInst(op = irMemCopy, a = taken, b = addr, imm = g.sizeOf(ft)))
	g.irEmptyAt(lw, addr, ft)
	[taken]

# the address of field fi of the place struct of type t at base
fn irFieldAddr(mut g Gen, mut lw IrLower, base i64, t TypeId, fi i64):
	off = g.c.structFieldOffsets(declOf(tys, t))[fi]
	a = lw.f.irVreg(irInt)
	if off == 0:
		# a vreg of its own: the field is a borrow, not the owned struct its address equals
		lw.irPut(IrInst(op = irCopy, dst = a, a = base))
	else:
		lw.irPut(IrInst(op = irAdd, dst = a, a = base, b = lw.irConstOf(irInt, off)))
	if lw.borrowsNoted:
		lw.irNoted(notePart, a, nodes[nodes[declOf(tys, t)].kids(kidIds)[fi]].text, base)
	a

# where in memory the place e is (a field of a place struct, or a field of a struct of numbers
# inside one): its address and type, or none when it is in vregs
fn irMemPlace(mut g Gen, mut lw IrLower, e NodeId) (i64, TypeId)?:
	if g.irGlobal(lw, e) is at: return (at, g.ty(e))
	if nodes[e].kind == nIdent and g.irFind(lw, nodes[e].text.copy()) == none and
		g.irFieldOfThis(lw, nodes[e].text) and g.irIsPlaceStruct(lw.thisType) and
		lw.thisType is selfType:
		# a field of this named alone, this in memory: the field where it is
		recv = g.irFind(lw, "self") ?? []
		if recv.len != 1: return none
		fi = g.c.fieldIndexOf(declOf(tys, selfType), nodes[e].text)
		return (
			g.irFieldAddr(lw, recv[0], selfType, fi),
			g.c.structFieldTypeAt(declOf(tys, selfType), fi)
		)
	if nodes[e].kind != nField: return none
	obj = nodes[e].kids(kidIds)[0]
	ot = g.ty(obj)
	if g.tyK(ot) == tRef or g.tyK(ot) == tBox:
		ot = innerOf(tys, ot)
	if g.tyK(ot) != tStruct: return none
	fi = g.c.fieldIndexOf(declOf(tys, ot), nodes[e].text)
	ft = g.c.structFieldTypeAt(declOf(tys, ot), fi)
	if g.irIsPlaceStruct(ot) or g.irPointsAway(g.ty(obj)):
		base = g.irValue(lw, obj)
		if base.len != 1: return none
		return (g.irFieldAddr(lw, base[0], ot, fi), ft)
	if g.irMemPlace(lw, obj) is inner:
		addr, _ = inner
		off = g.c.structFieldOffsets(declOf(tys, ot))[fi]
		a = lw.f.irVreg(irInt)
		lw.irPut(IrInst(op = irAdd, dst = a, a = addr, b = lw.irConstOf(irInt, off)))
		return (a, ft)
	none

# whether e is a literal whose value's bytes are all zero: 0, 0.0, false, or fill(n, z) of one
fn irIsZeroLiteral(mut g Gen, e NodeId) bool:
	k = nodes[e].kind
	if k == nInt: return g.intLitValue(e) == 0
	if k == nFloat: return g.floatLitBits(e) == 0
	if k == nBool: return nodes[e].ival == 0
	k == nArray and nodes[e].kids(kidIds).len == 1 and nodes[e].ival > 0 and
		g.irIsZeroLiteral(nodes[e].kids(kidIds)[0])

# whether the empty value of type t (irEmptyAt) is all zero bytes: of a number, a bool, an array
# of them
fn irZeroIsEmpty(mut g Gen, t TypeId) bool:
	k = g.tyK(t)
	k in [tInt, tFloat, tBool] or k == tArray and g.irZeroIsEmpty(innerOf(tys, t))

# [a, b, ...] of an array: a slot (a temporary when it owns) holding each value at its place;
# fill(N, x) (one value, ival N) x there, then copies of it (bytes copied doubling: the first,
# then the first two, four...; nothing for a zero)
fn irArrayLiteral(mut g Gen, mut lw IrLower, e NodeId, t TypeId):
	elem = innerOf(tys, t)
	stride = g.c.elemStride(elem)
	values = nodes[e].kids(kidIds).copy().map(g.irValue(lw, it))
	if not lw.ok: return -1
	slot = g.irResultSlot(lw, t)
	g.irEmptyAt(lw, slot, t)   # the literal of a declaration without values: just this
	for i, value in values:
		g.irPutValue(lw, lw.irElementAddr(slot, -1, 0, i * stride), elem, value)
	n = tys[t].bits
	if values.len == 1 and n > 1 and g.irIsZeroLiteral(nodes[e].kids(kidIds)[0]) and
		g.irZeroIsEmpty(elem):
		return slot   # zeros already
	if values.len == 1 and n > 1 and not g.isOwningType(elem):
		# the elements made so far copied after themselves, doubling: log2 n copies of bytes
		made = 1
		while made < n:
			k = made.min(n - made)
			at = lw.irElementAddr(slot, -1, 0, made * stride)
			lw.irPut(IrInst(op = irMemCopy, a = at, b = slot, imm = k * stride))
			made += k
		return slot
	if values.len == 1 and n > 1:
		for i in 1..n:
			at = lw.irElementAddr(slot, -1, 0, i * stride)
			if g.isOwningType(elem):
				lw.irPut(IrInst(op = irDeepCopy, a = at, b = slot, ty = elem))
			else:
				lw.irPut(IrInst(op = irMemCopy, a = at, b = slot, imm = g.sizeOf(elem)))
	slot

# a reference (or an optional one) of type t stored at addr as C holds a pointer: the address of
# its target, a window's its bytes', none 0
fn irPutCPointer(mut g Gen, mut lw IrLower, addr i64, t TypeId, value i64[]):
	zero = lw.irConstOf(irInt, 0)
	ptr = -1
	if tys[t].kind == tRef and value.len == 1:
		ptr = value[0]
		if g.irIsWindow(t):
			ptr = lw.irDef(irInt, IrInst(op = irLoad, a = value[0]))   # a window's first word is its bytes'
	elif g.c.isNicheOption(t) and value.len == 1:
		ptr = value[0]
	elif g.irIsOption(t) and value.len == 2:
		ptr = lw.f.irVreg(irInt)
		irPut(
			lw,
			IrInst(
				op = irSelect,
				dst = ptr,
				a = value[0],
				b = zero,
				c = value[1],
				d = zero,
				cond = irNe
			)
		)
	elif g.irIsTaggedOption(t) and value.len == 1:
		tag, at = g.irOptionAt(lw, t, value[0])
		bytes = lw.irDef(irInt, IrInst(op = irLoad, a = at))
		ptr = lw.f.irVreg(irInt)
		irPut(
			lw,
			IrInst(op = irSelect, dst = ptr, a = tag, b = zero, c = bytes, d = zero, cond = irNe)
		)
	else:
		lw.irFail("a C pointer of {typeStr(tys, t)}")
		return
	lw.irPut(IrInst(op = irStore, a = addr, c = ptr))

# T(f = v, ...): the values read in the order written, laid out in the fields' order
fn irStructLit(mut g Gen, mut lw IrLower, e NodeId):
	t = g.ty(e)
	if g.irIsPlaceStruct(t) and nodes[e].names().len == nodes[e].kids(kidIds).len:
		# in memory: a slot (a temporary when it owns), zeroed, each field put at its place; an
		# extern type's references are C pointers
		values = nodes[e].kids(kidIds).copy().map(g.irValue(lw, it))
		slot = g.irZeroedSlot(lw, t)
		sd = declOf(tys, t)
		cPointers = g.c.isExternType(sd)
		for i, value in values:
			fi = g.c.fieldIndexOf(sd, nodes[e].names()[i])
			ft = g.c.structFieldTypeAt(sd, fi)
			at = g.irFieldAddr(lw, slot, t, fi)
			if cPointers and g.c.isCPointer(ft):
				g.irPutCPointer(lw, at, ft, value)
			elif lw.borrowedKey == e and g.tyK(ft) == tStr and value.len == 1 and
				not lw.irOwns(value[0]) and value[0] not in lw.literals:
				# a key's text (irKeyBorrows): a header of the bytes it borrows, owning nothing
				header = value[0] if value[0] in lw.windows else lw.irBorrowedStr(value[0])
				lw.irPut(IrInst(op = irMemCopy, a = at, b = header, imm = 24))
			else:
				g.irPutValue(lw, at, ft, value)
		if nodes[sd].hasFlag(flagDrop):
			irPut(   # made: live (dropLiveOffset)
				lw,
				IrInst(
					op = irStore,
					a = slot,
					c = lw.irConstOf(irInt, 1),
					imm = g.c.dropLiveOffset(sd)
				)
			)
		return [slot]
	if not g.irIsAggregate(t) or nodes[e].names().len != nodes[e].kids(kidIds).len:
		return lw.irRefused("struct value of {typeStr(tys, t)}")
	sd = declOf(tys, t)
	kids = nodes[e].kids(kidIds).copy()
	values = []
	for kid in kids:
		values.push(g.irValue(lw, kid))
	out = []
	for fi in 0..g.c.nodes[sd].kids(g.c.kidIds).len:
		at = nodes[e].names().indexOf(nodes[nodes[sd].kids(kidIds)[fi]].text) ?? -1
		if at < 0:
			return lw.irRefused(
				"struct value without field {nodes[nodes[sd].kids(kidIds)[fi]].text}"
			)
		out.extend(values[at])
	out

# move place: an owned value by address moved into a temporary, the place left empty; a map's
# word taken, its place zeroed; a plain value copied, its place zeroed
fn irMoveOut(mut g Gen, mut lw IrLower, place NodeId):
	t = g.ty(place)
	if g.irOwnedByAddress(t) and g.irIsPlaceNode(place):
		from = g.irListAddr(lw, place)
		slot = g.irTemporary(lw, t)
		lw.moveWritten = true
		lw.keepEmptied = nodes[place].kind == nIdent and
			lw.irLookupAt(nodes[place].text) in lw.mutNames
		g.irMoveTo(lw, slot, from, t)
		lw.moveWritten = false
		lw.keepEmptied = false
		return [slot]
	if g.irByAddress(t) and not g.isOwningType(t) and g.irIsPlaceNode(place):
		# a plain value by address (a struct of a struct key): its bytes copied out, the place zeroed
		from = g.irListAddr(lw, place)
		slot = g.irResultSlot(lw, t)
		lw.irPut(IrInst(op = irMemCopy, a = slot, b = from, imm = g.sizeOf(t)))
		g.irEmptyAt(lw, from, t)
		return [slot]
	if not g.irTakes(t) or not g.irIsPlaceNode(place):
		return lw.irRefused("a move of {typeStr(tys, t)}")
	fresh = g.irNewValue(lw, t)
	held = g.irValue(lw, place)
	lw.irCopyValue(fresh, held)
	if not lw.ok: return []
	if g.irIsOwnedWord(t):
		# the place is left holding a fresh empty table: a map is never null
		table = g.irRtInstanceValues(
			lw,
			"mapNew",
			[innerOf(tys, t), valOf(tys, t)],
			[]
		) if g.tyK(t) ==
			tMap
			else [lw.irConstOf(irInt, 0)]
		if not lw.ok or table.len != 1: return []
		g.irGiveWord(lw, table[0])   # the place's now (a temporary: the same word)
		if g.irMemPlace(lw, place) is (addr, _):
			lw.irPut(IrInst(op = irStore, a = addr, c = table[0]))
		elif held.len == 1 and lw.irOwnedWordAt(held[0]) >= 0:
			irPut(   # what the local's drop frees
				lw,
				IrInst(op = irStore, a = lw.owned[lw.irOwnedWordAt(held[0])].slot, c = table[0])
			)
			lw.irCopyValue(held, table)
		else:
			return lw.irRefused("a move of a map local")
		g.irOwnedWord(lw, t, fresh[0])
		return fresh
	g.irStoreTo(lw, place, g.irEmptyLeaves(lw, t))
	fresh

fn irUnary(mut g Gen, mut lw IrLower, e NodeId, class i64) i64:
	op = nodes[e].ival
	a = g.irExpr(lw, nodes[e].kids(kidIds)[0])
	v = lw.f.irVreg(class)
	if op == unNeg and class != irFloat: return g.irFits(lw, g.irNegated(lw, a, g.ty(e)), g.ty(e))
	if op == unNeg:
		lw.irPut(IrInst(op = irFNeg, dst = v, a))
	elif op == unNot:
		lw.irPut(IrInst(op = irXor, dst = v, a, b = lw.irConstOf(irInt, 1)))
	elif op == unBnot:
		lw.irPut(IrInst(op = irNot, dst = v, a))
	else:
		lw.irFail("unary {op}")
	v if op == unNot else g.irNarrow(lw, v, g.ty(e))

# -a of integer type t, in 64 bits: a signed 64-bit one stops the program on the smallest value
fn irNegated(mut g Gen, mut lw IrLower, a i64, t TypeId) i64:
	lw.irDef(irInt, IrInst(op = irNeg, a, trap = g.irTraps(t)))

# the bits of the float x
fn irFloatBitsOf(mut lw IrLower, x i64) i64:
	lw.irDef(irInt, IrInst(op = irFloatBits, a = x))

fn irBinary(mut g Gen, mut lw IrLower, e NodeId, class i64) i64:
	op = nodes[e].ival
	l = nodes[e].kids(kidIds)[0]
	r = nodes[e].kids(kidIds)[1]
	if op == binCoalesce and g.irIsLeafOption(g.ty(l)):
		return g.irBinaryCoalesce(lw, e, class, l, r)
	if op == binAnd or op == binOr or isCompareOp(op):
		# a bool made by branches: 1 on the way in, 0 when the condition fails
		v = lw.f.irVreg(irInt)
		way = g.irSplitIf(lw, e)
		lw.irPut(IrInst(op = irConst, dst = v, imm = 1))
		lw.f.irElse(way)
		lw.irPut(IrInst(op = irConst, dst = v, imm = 0))
		lw.f.irJoin(way.end)
		return v
	lt = g.ty(l)
	if class < 0 or g.irClassOf(lt) != class or g.irClassOf(g.ty(r)) != class:
		lw.irFail("operator {nodes[e].ival} of {typeStr(tys, lt)}")
		return -1
	a = g.irExpr(lw, l)
	b = g.irExpr(lw, r)
	if op == binPow or (op == binMod and class == irFloat):
		return g.irBinaryPower(lw, e, class, op, a, b, lt)
	g.irBinaryArith(lw, e, class, op, r, a, b, lt)

# a ?? b of a leaf option: the value when there is one, else the right side
fn irBinaryCoalesce(mut g Gen, mut lw IrLower, e NodeId, class i64, l NodeId, r NodeId):
		# the value when there is one, else the right side (read only then)
		o = g.irOptionParts(lw, l)
		if o.len != 2:
			lw.irFail("optional of {typeStr(tys, g.ty(l))}")
			return -1
		v = lw.f.irVreg(class)
		before = lw.owned.copy()
		way = lw.irSplitNZ(o[0])
		lt = g.ty(l)
		owned = g.irIsOwnedWord(tys[lt].inner)
		# a place's map (box) where the right side never gives one: lent as the place's own word is
		lends = owned and g.irNever(r) and g.irNamesPlace(lw, l) and lw.irOwnedWordAt(o[1]) < 0
		if lends:
			lw.irPut(IrInst(op = irCopy, dst = v, a = o[1]))
		elif g.c.isOptionOfRef(lt) and g.tyK(g.ty(e)) != tRef:
			# a reference's target wanted: read through it
			lw.irCopyValue([v], g.irLoadValue(lw, innerOf(tys, tys[lt].inner), o[1], -1, 0))
		elif owned:
			lw.irPut(IrInst(op = irCopy, dst = v, a = g.irWordTaken(lw, innerOf(tys, lt), o[1])))
		else:
			lw.irPut(IrInst(op = irCopy, dst = v, a = o[1]))
		lw.f.irJumpTo(way.end)
		taken = lw.owned.copy()
		lw.f.irEnter(way.no)
		lw.irFallbackEntered(before)
		alt = g.irValue(lw, r)   # a return here leaves the function instead
		if not lw.ok: return -1
		if not lw.f.irEnded() and not g.irNever(r):
			if alt.len != 1:
				lw.irFail("scalar of type {typeStr(tys, g.ty(r))}")
				return -1
			irPut(
				lw,
				IrInst(
					op = irCopy,
					dst = v,
					a = g.irWordTaken(lw, innerOf(tys, lt), alt[0]) if owned else alt[0]
				)
			)
		lw.irFallbackLeft(taken)
		lw.f.irJoin(way.end)
		if lends: return o[1]
		if owned:
			g.irOwnedWord(lw, innerOf(tys, lt), v)
		v

# the runtime's power and a float's remainder
fn irBinaryPower(
	mut g Gen,
	mut lw IrLower,
	e NodeId,
	class i64,
	op i64,
	a i64,
	b i64,
	lt TypeId
) i64:
		# the runtime's: a ** b (a signed one stopping the program when it leaves the type, an
		# unsigned one wrapping), a float's remainder
		name = "remBits" if op == binMod
			else "fpow" if class == irFloat
			else "upow" if g.irUnsigned(lt)
			else "ipow"
		if class != irFloat:
			out = g.irCallRt(lw, name, [a, b])
			if not lw.ok or out.len != 1: return -1
			return g.irFits(lw, out[0], g.ty(e))
		# fpow and remBits take and give a float's bits
		out = g.irCallRt(lw, name, [lw.irFloatBitsOf(a), lw.irFloatBitsOf(b)])
		if not lw.ok or out.len != 1: return -1
		v = lw.irDef(irFloat, IrInst(op = irBitsToFloat, a = out[0]))
		g.irRounded(lw, v, g.ty(e))

# an arithmetic, bit or shift operator on two scalars
fn irBinaryArith(
	mut g Gen,
	mut lw IrLower,
	e NodeId,
	class i64,
	op i64,
	r NodeId,
	a i64,
	b i64,
	lt TypeId
) i64:
	v = lw.f.irVreg(class)
	irOp = irFloatOp(op) if class == irFloat else irIntOp(op)
	if irOp < 0:
		lw.irFail("operator {op}")
		return -1
	if (irOp == irShl or irOp == irShr) and not g.isIntLit(r) and
		not g.c.spanInside(r, 0, tys[g.ty(e)].bits - 1):
		irPut(
			lw,
			IrInst(
				op = irFailIf,
				a = b,
				b = lw.irConstOf(irInt, tys[g.ty(e)].bits),
				cond = irGe,
				uns = true,
				imm = g.failShift
			)
		)
	# the operands' ranges keep it inside its type, or an index's (lengths.zap, checked ahead):
	# no check
	proven = g.c.arithmeticInside(e) or nodes[e].hasFlag(flagInBounds) or e in lw.checked
	# an i32's + - * that may leave it: the operation of 32 bits, its overflow flag the check
	narrow = irOp in [irAdd, irSub, irMul] and g.irStopsOnOverflow(g.ty(e)) and
		tys[g.ty(e)].bits == 32 and g.irStopsOnOverflow(lt) and tys[lt].bits == 32 and
		not nodes[e].hasFlag(flagWrap) and not proven
	# a division's operands' width (imm): a constant divisor's code depends on it
	irPut(
		lw,
		IrInst(
			op = irOp,
			dst = v,
			a,
			b,
			uns = g.irUnsigned(lt),
			imm = tys[lt].bits if g.tyK(lt) == tInt else 64,
			size = 4 if narrow else 8,
			trap = narrow or irOp in [irAdd, irSub, irMul] and g.irTraps(g.ty(e)) and
				not nodes[e].hasFlag(flagWrap) and not proven
		)
	)
	if narrow: return v
	# & | ^ of values within the width stay within it, and so do a logical shift right, an
	# unsigned quotient and any remainder (smaller than its divisor, of the dividend's sign)
	stays = irOp in [irAnd, irOr, irXor, irRem] or (irOp in [irShr, irDiv] and g.irUnsigned(lt))
	if class == irFloat: return g.irRounded(lw, v, g.ty(e))
	if stays: return v
	arithmetic = irOp in [irAdd, irSub, irMul, irDiv] and not nodes[e].hasFlag(flagWrap)
	g.irFits(lw, v, g.ty(e)) if arithmetic and not proven else g.irNarrow(lw, v, g.ty(e))

# whether arithmetic of integer type t stops the program when its result leaves t (a signed
# type: an unsigned one is bits, wrapping) and that type is 64 bits wide (the operation's own
# overflow flag tells; a narrower one is checked by irFits)
fn irTraps(g Gen, t TypeId):
	g.irStopsOnOverflow(t) and tys[t].bits == 64

fn irStopsOnOverflow(g Gen, t TypeId):
	g.tyK(t) == tInt and tys[t].isSigned

# v, the 64-bit result of arithmetic of type t, made t: one leaving a signed type narrower than
# 64 bits stops the program, an unsigned one wraps
fn irFits(mut g Gen, mut lw IrLower, v i64, t TypeId):
	w = g.irNarrow(lw, v, t)
	if w != v and g.irStopsOnOverflow(t):
		lw.irPut(IrInst(op = irFailIf, a = w, b = v, cond = irNe, imm = g.failOverflow))
	w

# v of integer type from converted to integer type to: wrapped when asked (`u8.wrap(x)`) or when
# to is no narrower (a sign change keeps the bits), else the program stops when v does not fit;
# into a range type, it stops when v lies outside the range
fn irConverted(mut g Gen, mut lw IrLower, v i64, from TypeId, to TypeId, wrap bool):
	w = g.irNarrow(lw, v, to)
	if wrap: return w
	if tys[to].bits < tys[from].bits:
		lw.irPut(IrInst(op = irFailIf, a = w, b = v, cond = irNe, imm = g.failConversion))
		if tys[from].bits == 64 and not tys[from].isSigned and tys[to].isSigned:
			g.irConversionFails(lw, v, irLt, 0)   # a u64 past 2^63 reads as a negative word
	if tys[to].ranged:
		lo, hi = intBounds(tys, from)
		if lo < tys[to].lo or not tys[from].isSigned and tys[to].lo > 0:
			g.irConversionFails(lw, w, irLt, tys[to].lo)
		# (none past the largest of its width: w, narrowed to it, never is)
		if hi > tys[to].hi and tys[to].hi < intMax(tys[to].bits, true):
			g.irConversionFails(lw, w, irGt, tys[to].hi)
	w

# a conversion's check: the program stops when v cond k
fn irConversionFails(mut g Gen, mut lw IrLower, v i64, cond i64, k i64):
	irPut(
		lw,
		IrInst(op = irFailIf, a = v, b = lw.irConstOf(irInt, k), cond, imm = g.failConversion)
	)

# v wrapped to the width of integer type t when it is narrower than 64 bits
fn irNarrow(mut g Gen, mut lw IrLower, v i64, t TypeId) i64:
	if g.tyK(t) != tInt or tys[t].bits == 64: return v
	lw.irDef(irInt, IrInst(op = irTrunc, a = v, imm = tys[t].bits, uns = not tys[t].isSigned))

fn irIntOp(op i64):
	if op == binAdd: return irAdd
	if op == binSub: return irSub
	if op == binMul: return irMul
	if op == binDiv: return irDiv
	if op == binMod: return irRem
	if op == binBand: return irAnd
	if op == binBor: return irOr
	if op == binBxor: return irXor
	if op == binShl: return irShl
	if op == binShr: return irShr
	-1

fn irFloatOp(op i64):
	if op == binAdd: return irFAdd
	if op == binSub: return irFSub
	if op == binMul: return irFMul
	if op == binDiv: return irFDiv
	-1

# ---------- calls ----------
