# The lowering of calls and of the methods of numbers, lists and pipelines (irlower.zap).

alias nodes = g.c.nodes
alias tys = g.c.types

# a call: a number's or a list's method the form knows, a struct's method or a function inlined,
# or a function called; the substitution its lambdas are written under noted for the calls it
# makes
fn irCallOf(mut g Gen, mut lw IrLower, e NodeId):
	saved = move lw.site
	lw.site = g.c.subst.copy()
	out = g.irCallIn(lw, e)
	lw.site = saved
	out

fn irCallIn(mut g Gen, mut lw IrLower, e NodeId):
	span = g.irPipelineSpan(lw, e)
	out = g.irCallInAt(lw, e)
	if lw.ok and lw.floor == 0 and not lw.irInRuntimeCode():
		if span >= 0:
			lw.irNoted(noteReadTo, span, "")
		g.irNoteCall(lw, e)
	elif lw.ok and lw.borrowsNoted and not lw.irInRuntimeCode() and g.irCalledFn(lw, e) is fnd:
		g.irNoteCallReads(lw, e, fnd)   # an inlined body's call: what it reads of a borrow
	out

fn irCallInAt(mut g Gen, mut lw IrLower, e NodeId) i64[]:
	callee = nodes[e].kids[0]
	args = nodes[e].kids[1..nodes[e].kids.len].copy()
	gi = lw.irGivenAt(nodes[callee].text) if nodes[callee].kind == nIdent else -1
	if gi >= 0: return g.irGivenCall(lw, lw.given[gi].copy(), args)
	if nodes[e].hasFlag(flagRangeConversion) and g.irClassOf(g.ty(e)) < 0:
		return g.irValue(lw, args[0])   # a defined type's value of more than one word: the same
	if nodes[callee].kind == nIdent and nodes[callee].text == "rt__listSlice" and args.len == 3:
		return [g.irSlice(lw, e, args[0], args[1], args[2])]   # xs[lo..hi], the checker's call
	if nodes[e].hasFlag(flagRangeConversion):
		return [g.irConverted(lw, g.irExpr(lw, args[0]), g.ty(args[0]), g.ty(e), false)]
	if g.irIsVecCall(e): return g.irVecCall(lw, e)
	if g.irVariantOf(callee, g.ty(e)) >= 0: return g.irVariant(lw, callee, g.ty(e), args)
	if g.tyK(g.ty(callee)) == tFn and
		(
			nodes[callee].kind != nIdent or g.irFind(lw, nodes[callee].text.copy()) != none or
				g.irFieldOfThis(lw, nodes[callee].text)
		):
		return g.irClosureCall(lw, e, callee, args)   # a fn value held by a local, a field, an element
	if nodes[callee].kind == nField and nodes[callee].text == "fromBits" and args.len == 1 and
		g.tyK(g.ty(e)) == tFloat:
		v = lw.f.irVreg(irFloat)   # f64.fromBits(u), f32.fromBits(u): the float whose bits those are
		irPut(
			lw,
			IrInst(
				op = irBitsToF32 if g.irIsF32(g.ty(e)) else irBitsToFloat,
				dst = v,
				a = g.irExpr(lw, args[0])
			)
		)
		return [v]
	if nodes[callee].kind == nField: return g.irMethodCallIn(lw, e, args)
	if nodes[callee].kind != nIdent: return lw.irRefused("call form")
	g.irFreeCall(lw, e, args)

# obj.m(args): a number's, a pipeline's, a list's, a str's or a map's method the form knows, or
# a struct's method inlined or called
fn irMethodCallIn(mut g Gen, mut lw IrLower, e NodeId, args NodeId[]) i64[]:
	callee = nodes[e].kids[0]
	m = nodes[callee].text.copy()
	obj = nodes[callee].kids[0]
	if nodes[e].hasFlag(flagBoundCall) and
		g.c.boundCalls.get("{e} {typeMangled(tys, g.c.derefType(g.ty(obj)))}") is call:
		return g.irCallOf(lw, call)   # a function taking the instance's type first met the bound
	if g.c.derivedMethod(e, m) is family:
		# a function derive.zap wrote: T.fromJson(s), v.toJson(), a struct's hash, v.floor() of a
		# struct of numbers
		fromType = family in [
			"fromjson",
			"frombytes",
			"frombits",
			"read",
			"fromvalue",
			"readat",
			"fromcsv"
		]
		t = g.ty(e) if family == "frombits" or family == "read"
			else innerOf(tys, g.ty(e)) if fromType
			else g.ty(obj)
		fnd = g.derivedFn(family, t) ??
			return lw.irRefused("the derived {family} of {typeStr(tys, t)}")
		if not g.irCallable(fnd, false):
			return lw.irRefused("the derived {family} of {typeStr(tys, t)}")
		all NodeId[] = [] if fromType else [obj]
		all.extend(args)
		return g.irCallTo(lw, fnd, nodes[fnd].text.copy(), all)
	if m == "print" and args.len == 1 and g.tyK(g.ty(obj)) == tStruct and
		nodes[declOf(tys, g.ty(obj))].mod() == "rt" and
		nodes[declOf(tys, g.ty(obj))].text2 == "Stream":
		at = g.irAddressOf(lw, obj)
		text = g.irToStr(lw, args[0])
		if not lw.ok: return []
		return g.irCallRt(lw, "streamPrint", [at, text])
	ot = g.ty(obj)
	if g.tyK(ot) == tRef:
		ot = innerOf(tys, ot)
	if g.irScalarMethod(lw, e, m, obj, ot, args) is v: return v
	if g.irPipelineMethod(lw, e, m, obj, ot, args) is v: return v
	if g.irCollectionMethod(lw, e, m, obj, ot, args) is v: return v
	g.irUserMethod(lw, m, obj, ot, args)

# a method of a number, a bool or a value as a whole (take, copy, len, conversions), or none
fn irScalarMethod(
	mut g Gen,
	mut lw IrLower,
	e NodeId,
	m str,
	obj NodeId,
	ot TypeId,
	args NodeId[]
) i64[]?:
	ownCopy = m == "copy" and g.tyK(ot) in [tStruct, tEnum] and
		g.c.findMethod(tys[ot].name, m) != none
	if g.tyK(ot) == tInt and (m in intBitMethods) and m != "bitCount":
		return g.irBitMethod(lw, m, g.irExpr(lw, obj), tys[ot].bits, args)
	if g.tyK(ot) == tInt and m in bitFieldMethods: return g.irBitField(lw, e, m, obj, ot, args)
	if args.isEmpty and not ownCopy:
		if g.irScalarMethodTake(lw, e, m, obj, ot, args) is v: return v
		if g.irScalarMethodLen(lw, e, m, obj, ot, args) is v: return v
		if g.irScalarMethodMath(lw, e, m, obj, ot, args) is v: return v
	if m == "loadWord" and (g.irIsList(ot) or g.tyK(ot) == tStr) and args.len == 1:
		items, length = g.irItemsAndLength(lw, obj)
		idx = g.irExpr(lw, args[0])
		if not lw.ok: return irNoLeaves()
		if not nodes[e].hasFlag(flagInBounds):   # proven inside (lengths.zap)
			# i past the length (or below 0, a large unsigned number), then i + 8
			lw.irPut(
				IrInst(
					op = irFailIf,
					a = idx,
					b = length,
					cond = irGt,
					uns = true,
					imm = g.failBounds
				)
			)
			end = lw.irDef(irInt, IrInst(op = irAdd, a = idx, b = lw.irConstOf(irInt, 8)))
			lw.irPut(
				IrInst(
					op = irFailIf,
					a = end,
					b = length,
					cond = irGt,
					uns = true,
					imm = g.failBounds
				)
			)
		v = lw.irDef(irInt, IrInst(op = irLoad, a = items, b = idx, scale = 1))
		return [v]
	if (m == "min" or m == "max") and args.len == 1 and g.irClassOf(ot) >= 0 and
		g.irClassOf(g.ty(args[0])) == g.irClassOf(ot):
		return [g.irMinMax(lw, m == "max", g.irExpr(lw, obj), g.irExpr(lw, args[0]), ot)]
	none

# take, copy and the other methods that move or copy a value, or none
fn irScalarMethodTake(
	mut g Gen,
	mut lw IrLower,
	e NodeId,
	m str,
	obj NodeId,
	ot TypeId,
	args NodeId[]
) i64[]?:
	moves = m == "take" and g.c.isMoveCall(e)
	if moves and g.irIsOwnedWord(ot) and g.irIsPlaceNode(obj): return g.irMoveOut(lw, obj)
	if moves and g.irTakes(ot) and not g.isOwningType(ot):
		# a plain value moved: read, and its place left the empty value
		fresh = g.irNewValue(lw, ot)
		lw.irCopyValue(fresh, g.irValue(lw, obj))
		if g.irIsPlaceNode(obj):
			g.irStoreTo(lw, obj, g.irEmptyLeaves(lw, ot))
		return fresh
	if m == "intoStr" and g.irIsList(ot) and g.irIsPlaceNode(obj):
		from = g.irListAddr(lw, obj)
		slot = g.irTemporary(lw, tyStr)
		lw.keepEmptied = true   # `str(move bytes)`: the list stays, empty
		g.irMoveTo(lw, slot, from, tyStr)   # the same three words, read as a str
		lw.keepEmptied = false
		return [slot]
	if m == "bytes" and g.irIsStr(ot) and g.irIsWindow(g.ty(e)):
		ptr, n = g.irTextWords(lw, obj)
		return [lw.irWindowSlot(ptr, n)] if lw.ok else irNoLeaves()   # a window of the bytes
	if m == "copy" and g.irIsWindow(g.ty(e)): return g.irValue(lw, obj)   # a copy of a window (T = ref str) is the window
	if m == "copy" and args.isEmpty and g.tyK(ot) == tBox and tys[ot].counted:
		# a shared value: one more owner, as its implicit copies are made
		g.irMark(obj, flagAutoCopy)
		v = g.irValue(lw, obj)
		g.irUnmark(obj, flagAutoCopy)
		return v
	if m == "copy" and args.isEmpty and g.irIsOwnedWord(ot):
		w = g.irExpr(lw, obj)
		if not lw.ok: return irNoLeaves()
		return g.irOwnedCopyOf(lw, ot, [w])
	if m == "copy" and g.irTakes(ot) and not g.isOwningType(ot):   # leaves: a copy is the value
		return g.irValue(lw, obj)
	if m == "copy" and g.irOwnedByAddress(g.ty(e)) and not g.irIsPlaceNode(obj) and
		not g.irIsStr(ot):
		# of a value made here: a temporary is the copy itself, anything else (a window, a
		# slot made here) is copied deep (the copy reads items and length)
		value = g.irValue(lw, obj)
		if not lw.ok or value.len != 1: return lw.irRefused("a copy of {typeStr(tys, ot)}")
		if lw.owned.any(.slot == value[0] and .name < 0): return value
		slot = g.irTemporary(lw, g.ty(e))
		lw.irPut(IrInst(op = irDeepCopy, a = slot, b = value[0], ty = g.ty(e)))
		return [slot]
	if (moves or m == "copy") and g.irByAddress(ot) and g.irIsPlaceNode(obj):
		# a new owner: the place's bytes moved (take) or a deep copy of them
		from = g.irListAddr(lw, obj)
		slot = g.irTemporary(lw, ot)
		if moves:
			lw.moveWritten = true
			lw.keepEmptied = true   # a written move of a mut place: it stays, empty
			g.irMoveTo(lw, slot, from, ot)
			lw.moveWritten = false
			lw.keepEmptied = false
		else:
			lw.irPut(IrInst(op = irDeepCopy, a = slot, b = from, ty = ot))
		return [slot]
	none

# len, isEmpty, bits, conversions and rounding of a number or text, or none
fn irScalarMethodLen(
	mut g Gen,
	mut lw IrLower,
	e NodeId,
	m str,
	obj NodeId,
	ot TypeId,
	args NodeId[]
) i64[]?:
	if m == "len" and g.tyK(ot) == tArray: return [lw.irConstOf(irInt, tys[ot].bits)]
	if (m == "len" or m == "isEmpty") and (g.irIsList(ot) or g.tyK(ot) == tStr):
		_, n = g.irItemsAndLength(lw, obj)
		if m == "len": return [n]
		empty = lw.f.irVreg(irInt)
		irPut(
			lw,
			IrInst(op = irSet, dst = empty, a = n, b = lw.irConstOf(irInt, 0), cond = irEq)
		)
		return [empty]
	if m == "toBits" and g.irClassOf(ot) == irFloat:
		v = lw.f.irVreg(irInt)
		irPut(
			lw,
			IrInst(
				op = irF32Bits if g.irIsF32(ot) else irFloatBits,
				dst = v,
				a = g.irExpr(lw, obj)
			)
		)
		return [v]
	if m == "toF64" and g.tyK(ot) == tFloat: return [g.irExpr(lw, obj)]   # the same value, exactly (an f32 travels as its f64)
	if irOneOps.find(.name == m and .operands == 1) is op and g.irOneOpTakes(op, [ot]):
		return g.irOneOpOf(lw, op, [obj], g.ty(e))
	if m == "round" and g.irClassOf(ot) == irFloat:
		# the runtime's fround takes and gives the f64's bits
		bits = lw.irDef(irInt, IrInst(op = irFloatBits, a = g.irExpr(lw, obj)))
		r = g.irCallRt(lw, "fround", [bits])
		if not lw.ok or r.len != 1: return irNoLeaves()
		v = lw.irDef(irFloat, IrInst(op = irBitsToFloat, a = r[0]))
		return [g.irRounded(lw, v, g.ty(e))]
	if m == "toF32" and g.irClassOf(ot) == irFloat:
		return [g.irRounded(lw, g.irExpr(lw, obj), g.ty(e))]
	if m == "bitCount" and g.tyK(ot) == tInt:
		a = g.irExpr(lw, obj)
		if tys[ot].bits < 64:
			masked = lw.f.irVreg(irInt)   # the type's own bits only
			irPut(
				lw,
				IrInst(
					op = irAnd,
					dst = masked,
					a,
					b = lw.irConstOf(irInt, (1 << tys[ot].bits) - 1)
				)
			)
			a = masked
		v = lw.irDef(irInt, IrInst(op = irTzcnt, a, imm = 1))
		return [v]
	none

# abs, hash, bitCount and numeric conversions of a number, or none
fn irScalarMethodMath(
	mut g Gen,
	mut lw IrLower,
	e NodeId,
	m str,
	obj NodeId,
	ot TypeId,
	args NodeId[]
) i64[]?:
	if m == "abs" and g.irClassOf(ot) == irFloat:
		# the sign bit cleared
		bits = lw.f.irVreg(irInt)
		irPut(
			lw,
			IrInst(
				op = irAnd,
				dst = bits,
				a = lw.irFloatBitsOf(g.irExpr(lw, obj)),
				b = lw.irConstOf(irInt, 0x7FFF_FFFF_FFFF_FFFF)
			)
		)
		v = lw.irDef(irFloat, IrInst(op = irBitsToFloat, a = bits))
		return [v]
	if m == "abs" and g.tyK(ot) == tInt and tys[ot].isSigned:
		# the smallest value's negation does not fit the type: it stops the program
		a = g.irExpr(lw, obj)
		neg = g.irFits(lw, g.irNegated(lw, a, ot), ot)
		v = lw.f.irVreg(irInt)
		irPut(
			lw,
			IrInst(
				op = irSelect,
				dst = v,
				a,
				b = lw.irConstOf(irInt, 0),
				c = neg,
				d = a,
				cond = irLt
			)
		)
		return [v]
	if m == "hash" and g.tyK(ot) == tInt and args.isEmpty:
		a = g.irExpr(lw, obj)
		mul = lw.f.irVreg(irInt)
		irPut(
			lw,
			IrInst(
				op = irMul,
				dst = mul,
				a,
				b = lw.irConstOf(irInt, -7_046_029_254_386_353_131)
			)
		)
		high = lw.f.irVreg(irInt)
		irPut(
			lw,
			IrInst(
				op = irShr,
				dst = high,
				a = mul,
				b = lw.irConstOf(irInt, 32),
				uns = true
			)
		)
		v = lw.irDef(irInt, IrInst(op = irXor, a = mul, b = high))
		return [v]
	if conversionBits(m) > 0 and g.tyK(ot) == tInt:
		return [
			irConverted(
				g,
				lw,
				g.irExpr(lw, obj),
				ot,
				g.ty(e),
				nodes[e].hasFlag(flagWrap)
			)
		]
	if conversionBits(m) > 0 and g.irClassOf(ot) == irFloat:
		return [g.irFloatToIntOf(lw, g.irExpr(lw, obj), g.ty(e))]
	oc = g.irClassOf(ot)
	if (m in floatConversions and oc == irInt and g.tyK(ot) == tInt) or
		(m == "sqrt" and oc == irFloat):
		a = g.irExpr(lw, obj)
		v = lw.irDef(irFloat, IrInst(op = irFSqrt if m == "sqrt" else irIntToFloat, a))
		return [g.irRounded(lw, v, g.ty(e))]
	none

# a pipeline's consumer or step over a source (any, find, map, sortBy, reduce...), or none
fn irPipelineMethod(
	mut g Gen,
	mut lw IrLower,
	e NodeId,
	m str,
	obj NodeId,
	ot TypeId,
	args NodeId[]
) i64[]?:
	if (m in ["any", "all", "count"]) and args.len == 1 and g.irIsSource(obj) and
		g.irIsLambda1(args[0]):
		return [g.irTestEach(lw, m, obj, args[0])]
	if m == "count" and args.isEmpty and g.tyK(g.ty(obj)) == tSeq:
		return [g.irTestEach(lw, m, obj, none)]
	et = g.ty(e)
	if (m == "find" or (m == "findIndex" and nodes[obj].kind != nRange)) and args.len == 1 and
		g.irIsSource(obj) and g.irIsLambda1(args[0]) and
		g.irIsLeafOption(et) and
		(
			m == "findIndex" or g.tyK(tys[et].inner) == tRef or
				g.irClassOf(g.irSourceElem(obj)) >= 0
		):
		return g.irFindEach(lw, m, e, obj, args[0])
	if m == "find" and args.len == 1 and g.irIsSource(obj) and nodes[obj].kind != nRange and
		g.irIsLambda1(args[0]) and g.irIsTaggedOption(et) and g.irIsWindow(innerOf(tys, et)):
		return g.irFindWindow(lw, e, obj, args[0])
	if m == "mean" and args.isEmpty and g.irIsSteps(obj): return g.irMean(lw, obj)
	if (m == "groupBy" or m == "countBy") and args.len == 1 and g.irIsSteps(obj) and
		g.irIsLambda1(args[0]):
		return g.irCollectBy(lw, m, e, obj, args[0])
	if m == "zip" and args.len == 1 and g.irIsSteps(obj): return g.irZip(lw, e, obj, args[0])
	if m == "flatMap" and args.len == 1 and g.irIsSource(obj) and g.irIsLambda1(args[0]) and
		g.irIsList(et):
		return g.irFlatMap(lw, e, obj, args[0])
	if m == "toList" and args.isEmpty and g.tyK(g.ty(obj)) == tSeq:
		return g.irGather(lw, m, e, obj, none)
	if g.irIsGather(e): return g.irGather(lw, m, e, obj, args[0])
	if m == "sortBy" and args.len == 1 and g.irIsList(g.irListType(obj)) and
		nodes[args[0]].kind == nLambda and nodes[args[0]].names.len == 1:
		if g.irSortByParts(lw, obj, args[0]) is sorted: return sorted
		# the keys, then the runtime's listSortBy<T, K>(xs, move keys) moves the elements
		k = g.irKeysOf(lw, obj, args[0]) ?? return irNoLeaves()
		return irRtInstanceValues(
			g,
			lw,
			"listSortBy",
			[innerOf(tys, g.irListType(obj)), k.kt],
			[k.list, k.keys]
		)
	if m == "sortedBy" and args.len == 1 and g.irKeyed(obj) and
		nodes[args[0]].kind == nLambda and nodes[args[0]].names.len == 1 and
		g.tyK(et) == tList and g.irIsList(et):
		return g.irSortedBy(lw, e, obj, args[0])
	if (m == "minBy" or m == "maxBy") and args.len == 1 and g.irKeyed(obj) and
		nodes[args[0]].kind == nLambda and
		nodes[args[0]].names.len == 1 and
		(g.irIsLeafOption(et) or (g.irIsTaggedOption(et) and g.irIsWindow(innerOf(tys, et)))):
		return g.irExtremeBy(lw, m == "maxBy", et, obj, args[0])
	if m == "reduce" and args.len == 2 and g.irIsSteps(obj) and
		nodes[args[1]].kind == nLambda and nodes[args[1]].names.len == 2 and
		g.irTakes(et) and not g.isOwningType(et):
		return g.irReduce(lw, e, obj, args[0], args[1])
	if m == "sum" and nodes[e].hasFlag(flagBytesSum) and g.irIsList(g.ty(obj)):
		return g.irCallTo(lw, g.rtDecl("bytesSum"), "rt__bytesSum", [obj])   # eight at a time
	if m == "sum" and args.isEmpty and g.irIsSource(obj) and g.irClassOf(et) >= 0 and
		g.irClassOf(et) == g.irClassOf(g.irSourceElem(obj)):
		return g.irGather(lw, m, e, obj, none)
	none

# a method of a list, a str or a map the runtime has, or none
fn irCollectionMethod(
	mut g Gen,
	mut lw IrLower,
	e NodeId,
	m str,
	obj NodeId,
	ot TypeId,
	args NodeId[]
) i64[]?:
	if m == "slice" and nodes[e].hasFlag(flagInternal) and args.len == 2 and
		(g.irIsList(g.irListType(obj)) or g.tyK(g.irListType(obj)) == tStr):
		return [g.irSlice(lw, e, obj, args[0], args[1])]
	if g.irIsStr(g.ty(obj)) and m != "len" and m != "isEmpty" and m != "bytes" and
		m != "loadWord":
		return g.irStrMethod(lw, e, m, obj, args)
	if m == "toFixed" and args.len == 1 and g.irClassOf(ot) == irFloat:
		return irCallRt(
			g,
			lw,
			"fmtFixed",
			[lw.irFloatBitsOf(g.irExpr(lw, obj)), g.irExpr(lw, args[0])]
		)
	if g.tyK(ot) == tMap:
		# the runtime's generic function for the key and the value
		kt = innerOf(tys, ot)
		textKey = g.tyK(kt) == tStr or (g.c.refIsWindow(kt) and g.tyK(tys[kt].inner) == tStr)
		name = "mapAddText" if m == "add" and textKey else "map{capital(m)}"
		if g.rtDeclOrNone(name) == none: return lw.irRefused("method {m} of a map")
		return g.irRtInstanceCall(lw, name, [innerOf(tys, ot), valOf(tys, ot)], obj, args)
	if m == "extend" and args.len == 1 and g.irIsList(ot) and
		g.irBytesOfInterpolation(args[0]) is interp and
		not nodes[interp].kids.any(g.tyK(g.ty(it)) != tInt and g.irMentions(it, g.irRootName(obj))):
		# the parts made first, as the str would be: only a text part could read the list's bytes
		return g.irInterpolationOnto(lw, interp, obj)
	gathered = m == "extend" and args.len == 1 and g.irIsGather(args[0]) and
		not g.irMentions(args[0], g.irRootName(obj))
	if m == "extend" and args.len == 1 and (gathered or not g.c.isPlainType(innerOf(tys, ot))) and
		g.irIsList(ot):
		list = g.irListAddr(lw, obj)
		if gathered:
			# xs.extend(ys.map(f)): f's values pushed onto xs as they are made, no list between
			call = args[0]
			callee = nodes[call].kids[0]
			return irGather(
				g,
				lw,
				nodes[callee].text.copy(),
				call,
				nodes[callee].kids[0],
				nodes[call].kids[1],
				list
			)
		given = g.irValue(lw, args[0])
		if not lw.ok or given.len != 1: return lw.irRefused("extend's list")
		return g.irRtInstanceValues(lw, "listAppend", [innerOf(tys, ot)], [list, given[0]])
	if (m == "pop" or m == "join" or (m == "extend" and g.c.isPlainType(innerOf(tys, ot)))) and
		g.irIsList(ot):
		# the runtime's generic function for the element
		return g.irRtInstanceCall(lw, "list{capital(m)}", [innerOf(tys, ot)], obj, args)
	if m == "push" and args.len == 1 and g.irIsList(ot) and g.irIsOwnedWord(tys[ot].inner):
		value = g.irValue(lw, args[0])   # a box's (a map's) word, the list's from now on
		given = g.irGiveWordOf(lw, innerOf(tys, ot), value[0]) if lw.ok and value.len == 1 else -1
		if given < 0:
			return lw.irRefused("a push of a {typeStr(tys, tys[ot].inner)} not owned here")
		return [g.irPush(lw, g.irListAddr(lw, obj), innerOf(tys, ot), [given])]
	if m == "push" and args.len == 1 and g.irIsList(ot) and
		(
			g.irOwnedByAddress(innerOf(tys, ot)) or
				(
					not g.isOwningType(innerOf(tys, ot)) and
						(g.irTakes(tys[ot].inner) or g.irByAddress(tys[ot].inner))
				)
		):
		value = g.irValue(lw, args[0])   # first: a call in it may move the list
		return [g.irPush(lw, g.irListAddr(lw, obj), innerOf(tys, ot), value)]
	none

# a method of a struct, an enum or a box of one: inlined or called
fn irUserMethod(mut g Gen, mut lw IrLower, m str, obj NodeId, ot TypeId, args NodeId[]) i64[]:
	counted = g.tyK(ot) == tStruct and nodes[declOf(tys, ot)].hasFlag(flagShared)   # reached through its counted pointer
	if g.irIsAggregate(ot) or (g.irIsPlaceStruct(ot) and not counted) or
		g.irIsCarryingEnum(ot):
		md = g.c.findMethod(tys[ot].name, m)
		implDecl = g.c.findImplDeclOf(tys[ot].name, md)
		generic = g.c.implIsGenericOf(implDecl)
		if md is md and g.irInlines(lw, md):
			sav = g.c.subst.copy()
			if generic and implDecl is impl:
				g.setSubstOf(impl)
			m0 = g.irMarkOf(lw)
			recv = g.irValue(lw, obj)
			inlined = g.irTryInline(lw, md, recv.copy(), ot, args)
			g.c.subst = sav
			if inlined is v:
				if nodes[md].hasFlag(flagMut) and g.irIsAggregate(ot) and
					not g.irIsPlaceNode(obj):
					lw.irFail("a mut method of a value that is not a place")
				elif nodes[md].hasFlag(flagMut) and g.irIsAggregate(ot):
					g.irStoreTo(lw, obj, recv)   # the leaves it changed: copies of an element's, a field's
				return v.copy()
			g.irRollback(lw, m0)
		if md is md: return g.irMethodCall(lw, md, implDecl, generic, ot, obj, args)
	if (g.tyK(ot) == tBox and g.tyK(tys[ot].inner) == tStruct) or counted:
		inner = ot if counted else innerOf(tys, ot)
		md = g.c.findMethod(tys[inner].name, m)
		implDecl = g.c.findImplDeclOf(tys[inner].name, md)
		if md is md:
			return irMethodCall(
				g,
				lw,
				md,
				implDecl,
				g.c.implIsGenericOf(implDecl),
				inner,
				obj,
				args
			)
	lw.irRefused("method {m} of {typeStr(tys, ot)}")

# a call of a function by its name: an intrinsic, a builtin, the runtime's, a generic one's, a
# method of this one's, or a function of the program
fn irFreeCall(mut g Gen, mut lw IrLower, e NodeId, args NodeId[]) i64[]:
	callee = nodes[e].kids[0]
	name = nodes[callee].text.copy()
	if name.startsWith("__"): return g.irIntrinsic(lw, e, name, args)
	if name == "Box" and args.len == 1 and g.tyK(g.ty(e)) == tBox:
		return g.irBox(lw, g.ty(e), args[0])
	if name == "bindExtern" and args.len == 2:
		loaded = g.c.findFunc(nodes[args[0]].text) ??
			return lw.irRefused("bindExtern of no function")
		g.irBindLoaded(lw, loaded, args[1])   # a loaded function's address kept
		return []
	if name == "bindExterns":
		for i in 0..nodes[e].types.len:
			g.irBindLoaded(lw, nodes[e].types[i], nodes[e].sub[i])
		return []
	if (name == "print" or name == "eprint") and args.len == 1:
		text = g.irToStr(lw, args[0])
		if not lw.ok: return []
		return irCallRt(
			g,
			lw,
			"printLine",
			[text, lw.irConstOf(irInt, 1 if name == "eprint" else 0)]
		)
	fnd = g.c.findFunc(name)
	if fnd == none and builtinRtName(name) != "" and nodes[e].text2 == "":
		rt = builtinRtName(name)
		return g.irCallTo(lw, g.rtDecl(rt), "rt__{rt}", args)   # a function of the runtime's
	if nodes[e].text2 != "": return g.irInstanceCall(lw, fnd, nodes[e].text2.copy(), args)
	if fnd == none and lw.thisType is selfType and lw.irLookup("self") is recv:
		# a method of this one, called on it by its name alone
		md = g.c.findMethod(tys[selfType].name, name)
		if md is md and g.irInlines(lw, md) and
			g.irTryInline(lw, md, recv, selfType, args) is v:
			return v
	g.irNamedCall(lw, fnd ?? return lw.irRefused("a call of {name}"), args)

# a call of the function fnd (not generic) with the argument nodes args: inlined when small
fn irNamedCall(mut g Gen, mut lw IrLower, fnd NodeId, args NodeId[]) i64[]:
	if g.irInlines(lw, fnd) and g.irTryInline(lw, fnd, none, none, args) is v: return v
	if not g.irCallable(fnd, false) or nodes[fnd].kids.len != args.len or
		args.any(nodes[it].kind == nNamedArg):
		return lw.irRefused("call of {nodes[fnd].text}")
	g.irCallTo(lw, fnd, nodes[fnd].text.copy(), args)

# a float converted to the integer type t: one cvttsd2si when the value lands
# in t's range, the runtime's f2i (which saturates, NaN to 0) when it does not
fn irFloatToIntOf(mut g Gen, mut lw IrLower, x i64, t TypeId):
	bits = tys[t].bits
	signed = tys[t].isSigned
	v = lw.irDef(irInt, IrInst(op = irFloatToInt, a = x))
	fastB = lw.f.irBlock()
	slowB = lw.f.irBlock()
	endB = lw.f.irBlock()
	if bits == 64 and signed:
		lw.irBranchIf(v, irEq, lw.irConstOf(irInt, -9_223_372_036_854_775_807 - 1), slowB, fastB)
	elif bits < 64:
		lo = -(1 << (bits - 1)) if signed else 0
		hi = (1 << (bits - 1)) - 1 if signed else (1 << bits) - 1
		inLow = lw.f.irBlock()
		lw.irBranchIf(v, irLt, lw.irConstOf(irInt, lo), slowB, inLow)
		lw.f.irEnter(inLow)
		lw.irBranchIf(v, irGt, lw.irConstOf(irInt, hi), slowB, fastB)
	else:
		lw.f.irJumpTo(slowB)   # u64: the runtime's
	lw.f.irEnter(slowB)
	raw = lw.irDef(irInt, IrInst(op = irFloatBits, a = x))
	f2i = g.c.findFunc("rt__f2i")
	irPut(
		lw,
		IrInst(
			op = irCall,
			dst = v,
			args = [raw, lw.irConstOf(irInt, bits), lw.irConstOf(irInt, 1 if signed else 0)],
			key = "rt__f2i",
			regArgs = g.takesRegArgs(f2i, false)
		)
	)
	lw.f.irJumpTo(endB)
	lw.f.irEnter(fastB)
	lw.f.irJoin(endB)
	v
