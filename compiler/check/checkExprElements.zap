# The checking of the methods of lists, vectors, bytes, numbers and text (checkExpr.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# Methods on T[]. Pipeline: length/isEmpty/sum/map/filter/each/sortedBy.
# Mutation (receiver must be mut): push/pop/remove/clear. Lookup: contains/first/last.
fn checkListMethod(mut c Checker, e NodeId, listT TypeId, expected TypeId?) TypeId:
	obj = c.calleeObj(e)
	m = c.calleeName(e)
	if m == "contains" and c.containsCallWritten(e, c.showTy(listT)): return tyError
	line = nodes[e].line
	col = nodes[e].col
	nargs = c.argCount(e)
	elem = c.innerOrError(listT)
	if m == "len": return tyN64
	if m == "isEmpty": return tyBool
	untold = tys[listT].inner == none   # a `[]` binding whose first telling use this may be
	if untold:
		c.tellEmptyList(c.varOfExpr(obj), c.listMethodElement(m), none)
		untold = tys[listT].inner == none
		elem = c.innerOrError(listT)
	if m != "push" and m != "extend":
		c.giveUpEmptyList(obj)
		if untold: return c.untoldList(obj, line, col)
	ek = c.tKind(elem)
	vr = c.checkVecListMethod(e, obj, elem)
	if vr is vr:
		return vr   # loadN / storeN of a vector type (vecs.zap)
	if m == "push": return c.checkListPush(e, obj, listT, elem, untold)
	if m == "loadWord" and isSameType(tys, elem, tyInt(8, false)):
		if not c.expectArgs(e, m, 1): return tyError
		c.checkIntArg(e, 0, "loadWord expects an integer index")
		c.proveWordByLength(e, obj, c.argAt(e, 0))
		return tyInt(64, false)   # the eight bytes at [i, i + 8), little-endian
	if m == "load16" or m == "store16":
		# xs.load16(i): bytes xs[i..i+16) as a u8x16; xs.store16(i, v): the bytes into xs[i..i+16)
		if c.tKind(elem) != tInt or tys[elem].bits != 8 or tys[elem].isSigned:
			c.errorAt(line, col, compileError("NeedsBytes", ["{m}", "{c.showTy(elem)}"]))
			return tyError
		return c.checkLoadStore(e, obj, m, tyBytes, m == "load16")
	if m == "load4" or m == "store4":
		# xs.load4(i): lanes xs[i..i+4) as an f64x4; xs.store4(i, v): the lanes into xs[i..i+4)
		if c.tKind(elem) != tFloat or tys[elem].bits != 64:
			c.errorAt(line, col, compileError("NeedsFloats", ["{m}", "{c.showTy(elem)}"]))
			return tyError
		return c.checkLoadStore(e, obj, m, tySimd, m == "load4")
	if m == "extend": return c.checkListExtend(e, obj, listT, elem, untold)
	if m == "pop":
		if nargs != 0:
			c.errorAt(line, col, compileError("PopArity", []))
			return tyError
		c.requireMutRoot(obj, line, col, "pop")
		return tyOption(tys, elem)
	if m == "sum" and nargs == 0 and c.isMapOrFilter(obj) and typeIsNumeric(tys, elem):
		# the sum of a map or a filter: a reduce, which the backend runs in the same loop as them
		c.sumAsReduce(e, elem)
		return c.checkReduce(e, elem, elem)
	if c.checkElementwise(e, m, obj, listT, elem) is ew: return ew
	c.mapExpected = innerOf(tys, expected) if c.tKind(expected) == tList else none
	pr = c.checkPipeline(e, m, elem, false)
	c.mapExpected = none
	if pr is pr: return pr
	if m == "join":
		if not c.expectArgs(e, m, 1): return tyError
		if ek != tStr and ek != tError and not (ek == tRef and c.tKind(tys[elem].inner) == tStr):
			c.errorAt(line, col, compileError("JoinNeedsStrs", ["{c.showTy(elem)}"]))
		c.checkStrArg(e, 0, "join expects a str separator")
		return tyStr
	if (m == "slice" or m == "window") and not nodes[e].hasFlag(flagInternal) or
		m == "repeat" and not nodes[nodes[e].kids(kidIds)[0]].hasFlag(flagInternal):
		c.errorAt(line, col, compileError("NoMethod", ["{m}", c.showTy(listT)]))
		return tyError
	if m == "slice" and c.sortedFirst(e):
		return listT   # the first k of the sort, kept alone
	c.checkRuntimeMethod(e, "list", "{c.showTy(elem)}[]", expected)

fn checkListPush(
	mut c Checker,
	e NodeId,
	obj NodeId,
	listT TypeId,
	listElem TypeId,
	untold bool
):
	line = nodes[e].line
	col = nodes[e].col
	nargs = c.argCount(e)
	elem = listElem
	if nargs != 1:
		c.errorAt(line, col, compileError("PushArity", []))
		return tyError
	c.requireMutRoot(obj, line, col, "push")
	at = c.checkExpr(c.argAt(e, 0), none if untold else elem)
	tellEmptyList(
		c,
		c.varOfExpr(obj),
		c.plainElement(at),
		c.inferredValueType(c.argAt(e, 0), at)
	)
	if untold or c.tellsEmptyListType(obj):
		elem = c.innerOrError(listT) if untold else elem
		c.keepConversion(c.argAt(e, 0))
		if not untold and c.floatHolds(at, elem):
			c.setArg(e, 0, c.numWiden(c.argAt(e, 0), elem))
			at = elem
		elif not untold:
			at = c.narrowArg(e, 0, at, elem)   # proven inside the element's type
	else:
		at = c.checkWidenedArg(e, 0, elem, at)
	if not isAssignable(tys, at, elem) and not c.retypeFlex(c.argAt(e, 0), elem):
		c.errorAt(line, col, compileError("PushType", ["{c.showTy(elem)}", "{c.showTy(at)}"]))
	c.setArg(e, 0, c.coerceTo(c.argAt(e, 0), elem))
	if e == c.stmtExpr:
		return tyUnit   # the index is not wanted
	if nodeCalls(nodes, kidIds, obj):
		errorAt(
			c,
			line,
			col,
			compileError("PushIndexNeedsPlace", [])
		)
		c.valueOnlyErrors += 1
	tyN64   # the index of the new element

fn checkListExtend(
	mut c Checker,
	e NodeId,
	obj NodeId,
	listT TypeId,
	listElem TypeId,
	untold bool
):
	line = nodes[e].line
	col = nodes[e].col
	nargs = c.argCount(e)
	elem = listElem
	if nargs != 1:
		c.errorAt(line, col, compileError("ExtendNeedsList", []))
		return tyError
	c.requireMutRoot(obj, line, col, "extend")
	a0 = c.argAt(e, 0)
	at = c.derefIfRef(a0, c.checkExpr(a0, none if untold else tyList(tys, elem)))
	if c.tKind(at) == tList:
		c.tellEmptyList(c.varOfExpr(obj), tys[at].inner, c.inferredElemType(a0, at))
		if untold:
			elem = c.innerOrError(listT)
	if c.tKind(at) != tError and
		(c.tKind(at) != tList or not isSameType(tys, tys[at].inner, elem)):
		c.errorAt(line, col, compileError("ExtendType", ["{c.showTy(elem)}", "{c.showTy(at)}"]))
	tyUnit

# the element type of the one kind of list a runtime method is for (u8[]'s pushU32le: u8, so
# `mut out = []` then `out.pushU32le(v)` makes out a u8[]), none for a method of every list
fn listMethodElement(mut c Checker, m str) TypeId?:
	fd = try c.findDeclInModule("rt", nFnDecl, "list{capital(m)}")
	if not nodes[fd].names().isEmpty or nodes[fd].kids(kidIds).isEmpty: return none
	te = nodes[nodes[fd].kids(kidIds)[0]].types()[0]
	if nodes[te].kind != nTyName or nodes[te].text != "List": return none
	c.resolveType(nodes[te].types()[0])

# A number's method on a list of numbers (`xs.sqrt()`, `xs.clamp(0.0, 1.0)`, `xs.max(0.0)`),
# the list having no method of the name or an argument of the element's type: the method on each
# element, written over as xs.map($x => $x.m(args)), a pipeline step the backend fuses with the
# steps around it. None when it is no such call: the list's own method (`xs.max()`) or no number's.
fn checkElementwise(mut c Checker, e NodeId, m str, obj NodeId, listT TypeId, elem TypeId) TypeId?:
	ek = c.tKind(elem)
	if (ek != tInt and ek != tFloat) or m in vectorMethods or c.fieldwiseArity(m) < 0: return none
	line = nodes[e].line
	col = nodes[e].col
	own = c.findDeclInModule("rt", nFnDecl, "list{capital(m)}")
	if own is own:
		ownArgs = nodes[own].kids(kidIds).len - 1
		if c.argCount(e) == ownArgs: return none
		for i in 0..argCount(c, e):
			a = c.argAt(e, i)
			at = c.derefIfRef(a, c.checkExpr(a, elem if c.isNumLit(a) else none))
			if c.tKind(at) != tError and not isSameType(tys, at, elem):
				c.errorAt(
					line,
					col,
					compileError(
						"ListOrElementMethod",
						[
							"{m}",
							"{c.showTy(listT)}",
							"{ownArgs}",
							"{c.showTy(elem)}",
							"{c.showTy(at)}"
						]
					)
				)
				return tyError
	param = newNode(nodes, kidIds, nIdent, line, col, text = "$x")
	callee = nodes[e].kids(kidIds)[0]
	nodes[callee].setKids(kidIds, [param])
	inner = newNode(nodes, kidIds, nCall, line, col, kids = nodes[e].kids(kidIds).copy())
	lam = newNode(nodes, kidIds, nLambda, line, col, kids = [inner])
	nodes[lam].nodePart().names = ["$x"]
	nodes[lam].nodePart().types = [newNode(nodes, kidIds, nTyAbsent, line, col)]
	nodes[lam].flags |= flagInternal
	madeKids = [newNode(nodes, kidIds, nField, line, col, text = "map", kids = [obj]), lam]
	nodes[e].setKids(kidIds, madeKids)
	c.mapExpected = none
	c.checkPipeline(e, "map", elem, false)

# `xs.sortedBy(f).slice(0, k)`, k a literal up to 64: the call becomes the sortedBy itself with
# only its first k kept (a selection of n log k, the same elements in the same order)
fn sortedFirst(mut c Checker, e NodeId):
	obj = c.calleeObj(e)
	if c.argCount(e) != 2 or nodes[obj].kind != nCall or nodes[obj].hasFlag(flagParallelSort) or
		nodes[obj].hasFlag(flagFirstK):
		return false
	callee = nodes[obj].kids(kidIds)[0]
	a0 = c.argAt(e, 0)
	a1 = c.argAt(e, 1)
	if nodes[callee].kind != nField or nodes[callee].text != "sortedBy" or nodes[a0].kind != nInt or
		nodes[a1].kind != nInt:
		return false
	if nodes[a0].text != "0": return false
	k = i64.parse(nodes[a1].text) ?? 0
	if k < 1 or k > 64: return false
	nodes[e].setKids(kidIds, nodes[obj].kids(kidIds).copy())
	nodes[e].flags = nodes[obj].flags | flagFirstK
	nodes[e].ival = k
	true

# Conversion and math methods on numbers: abs,
# plus floor/ceil/round/sqrt on floats.
# f64x4: lane(i) f64, sum() f64, sqrt() f64x4, max(w) / min(w) f64x4, ltMask(w) / leMask(w) /
# gtMask(w) / geMask(w) i64 (bit i set when lane i compares true)
# the n arguments of the vector method m, each a vector of type want (reported when not); false
# when the count is wrong
fn vectorArgs(mut c Checker, e NodeId, m str, n i64, want TypeId):
	if not c.expectArgs(e, m, n): return false
	for i in 0..n:
		at = c.derefIfRef(c.argAt(e, i), c.checkExpr(c.argAt(e, i), want))
		if c.tKind(at) != c.tKind(want):
			errorAt(
				c,
				nodes[e].line,
				nodes[e].col,
				compileError("ArgumentsOfType", ["{m}", "{c.showTy(want)}", "{c.showTy(at)}"])
			)
	true

fn checkSimdMethod(mut c Checker, e NodeId):
	m = c.calleeName(e)
	line = nodes[e].line
	col = nodes[e].col
	if m == "lane":
		if not c.expectArgs(e, m, 1): return tyError
		c.checkIntArg(e, 0, "lane expects an index 0..3")
		return tyFloat(64)
	if m in ["sum", "sqrt", "rsqrtEstimate"]:
		c.expectArgs(e, m, 0)
		if m == "sum": return tyFloat(64)
		return tySimd
	if m == "spread":
		if not c.expectArgs(e, m, 1): return tyError
		c.checkIntArg(e, 0, "spread expects a lane index 0..3")
		return tySimd
	if (m in ["mulAdd", "mulSub", "subMul"]) and nodes[e].hasFlag(flagInternal):
		# x * y + z, x * y - z, z - x * y under `use fusedMultiplyAdd` (fuse.zap), rounded once
		if not c.vectorArgs(e, m, 2, tySimd): return tyError
		return tySimd
	if m in ["mulAdd", "mulSub", "subMul"]:
		c.errorAt(line, col, compileError("MultiplyAdd", []))
		return tyError
	if m == "sums4":
		if not c.vectorArgs(e, m, 3, tySimd): return tyError
		return tySimd
	if m in ["max", "min", "ltMask", "leMask", "gtMask", "geMask"]:
		if not c.vectorArgs(e, m, 1, tySimd): return tyError
		if m == "max" or m == "min": return tySimd
		return tyInt(64, true)
	c.errorAt(line, col, compileError("VectorNoMethod", ["Simd<4, f64>", "{m}"]))
	tyError

# u8x16: shuffle(idx) u8x16 (byte i = v[idx[i] & 15], or 0 when idx[i] has its high bit set),
# blend(w, mask) u8x16 (w where the mask byte has its high bit set, else v), eqBytes(w) u8x16
# (0xFF where equal), eqMask(w) / gtMask(w) i64 (the bytes that compare true, signed for gt),
# lane(i) i64
fn checkBytesMethod(mut c Checker, e NodeId):
	m = c.calleeName(e)
	line = nodes[e].line
	col = nodes[e].col
	if m == "lane":
		if not c.expectArgs(e, m, 1): return tyError
		c.checkIntArg(e, 0, "lane expects an index 0..15")
		return tyInt(64, true)
	if m in ["shuffle", "eqBytes", "eqMask", "gtMask", "blend"]:
		want = 1
		if m == "blend":
			want = 2
		if not c.vectorArgs(e, m, want, tyBytes): return tyError
		if m == "eqMask" or m == "gtMask": return tyInt(64, true)
		return tyBytes
	c.errorAt(line, col, compileError("VectorNoMethod", ["Simd<16, u8>", "{m}"]))
	tyError

# a conversion of a numT to target: one to the type the value already has is an error (it reads
# as if something happened), except in a generic body, where T may be anything
fn conversionTo(mut c Checker, e NodeId, numT TypeId, target TypeId) TypeId:
	c.refuseRoundTrip(e, target)
	k = c.tKind(numT)
	same = k == c.tKind(target) and tys[numT].bits == tys[target].bits and
		tys[numT].isSigned == tys[target].isSigned and (k == tFloat or not tys[numT].ranged) and
		not isDefined(tys, numT)
	if same and c.subst.names.isEmpty and not nodes[e].hasFlag(flagAutoWiden) and
		not nodes[nodes[e].kids(kidIds)[0]].hasFlag(flagInternal) and
		tys[numT].param == "" and c.curFile != "<derived>":
		errorAt(
			c,
			nodes[e].line,
			nodes[e].col,
			compileError("NeedlessConversion", ["{c.showTy(target)}"])
		)
	if nodes[e].hasFlag(flagAutoWiden) or nodes[e].hasFlag(flagWrap) or
		nodes[nodes[e].kids(kidIds)[0]].hasFlag(flagInternal):
		return target   # the checker's widening gives the place's type itself
	c.convertedRange(numT, target)

# `f32(f64(x).sqrt())` with x an f32: converted only to call a method its own type has and
# converted back, an error showing the direct form (x.sqrt()); a conversion the method needs stays
fn refuseRoundTrip(mut c Checker, e NodeId, target TypeId):
	outer = nodes[e].kids(kidIds)[0]
	if nodes[outer].hasFlag(flagInternal) or tys[target].param != "": return
	call = nodes[outer].kids(kidIds)[0]
	if nodes[call].kind != nCall: return
	f = nodes[call].kids(kidIds)[0]
	# a runtime method is a call of its function by then, the receiver its first argument
	runtime = nodes[call].hasFlag(flagMethod)
	if not runtime and nodes[f].kind != nField: return
	m = nodes[f].names()[0] if runtime else nodes[f].text
	inner = nodes[call].kids(kidIds)[1] if runtime else nodes[f].kids(kidIds)[0]
	if conversionMethod(conversionType(m)) == m: return
	wide = c.writtenConversionFrom(inner, target)
	if wide == none or c.tKind(wide) != c.tKind(target) or
		not isSameType(tys, nodes[call].ty, wide):
		return
	w = wide ?? return
	if c.tKind(target) == tInt and tys[w].isSigned != tys[target].isSigned and
		not (tys[w].isSigned and tys[w].bits > tys[target].bits):
		return   # the bits read with the other sign: its method differs (abs, max, >>)
	for i in (2 if runtime else 1)..nodes[call].kids(kidIds).len:
		arg = nodes[call].kids(kidIds)[i]
		if not c.isNumLit(arg) and c.writtenConversionFrom(arg, target) == none: return
	if not c.numHasMethod(target, m): return
	c.errorAt(
		nodes[e].line,
		nodes[e].col,
		compileError("ConversionRoundTrip", ["{c.showTy(target)}", "{m}", "{c.showTy(wide)}"])
	)

# the type e converts to when e is a conversion written in the program of a value of type from;
# none otherwise
fn writtenConversionFrom(c Checker, e NodeId, from TypeId) TypeId?:
	if nodes[e].kind != nCall or nodes[e].kids(kidIds).len != 1: return none
	f = nodes[e].kids(kidIds)[0]
	if nodes[f].kind != nField or nodes[f].hasFlag(flagInternal) or nodes[e].hasFlag(flagAutoWiden):
		return none
	if conversionMethod(conversionType(nodes[f].text)) != nodes[f].text: return none
	x = nodes[f].kids(kidIds)[0]
	if nodes[x].ty == none or not isSameType(tys, nodes[x].ty, from): return none
	typeOf(nodes, e)

# whether a number of type t has the method m giving a t (a float has every runtime float method:
# an f32's only the f64 has is computed in f64)
fn numHasMethod(c Checker, t TypeId, m str):
	if m in ["abs", "min", "max"]: return true
	if c.tKind(t) != tFloat: return false
	if m in ["floor", "ceil", "round", "sqrt", "trunc"]: return true
	fd = c.findDeclInModule("rt", nFnDecl, "f64{capital(m)}") ?? return false
	c.declIsPub(fd)

# `i64(n)`, `u8(1)`: a conversion written on a number (its receiver a plain value), a
# candidate for zap fmt: where a place widens n to its type anyway (noteWidenedAt), the call goes
fn markWideningCall(mut c Checker, e NodeId):
	if not noting: return
	m = c.calleeName(e)
	if m not in intConversions and m != "toF64" and m != "toF32": return
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind != nField or nodes[callee].kids(kidIds).len != 1: return
	if nodes[nodes[callee].kids(kidIds)[0]].kind == nFloat: return
	nodes[e].flags |= flagWidenCandidate

# e, a value whose place takes its type from it (or from its siblings: a list's elements, a
# tuple's values): a conversion written there tells that type, and zap fmt keeps it
fn keepConversion(mut c Checker, e NodeId):
	nodes[e].flags &= ~flagWidenCandidate

# e, a conversion call marked by markWideningCall, given to a place of type target that would
# widen its receiver to target on its own (an integer to a wider one, a literal to the place's
# type, and at the places that go through numWiden (toF64) an integer to f64): noted for zap fmt
# as the receiver alone
fn noteWidenedAt(mut c Checker, e NodeId, maybeTarget TypeId?, toF64 bool = false):
	target = maybeTarget ?? return
	if not noting or not nodes[e].hasFlag(flagWidenCandidate): return
	callee = nodes[e].kids(kidIds)[0]
	recv = nodes[callee].kids(kidIds)[0]
	if nodes[recv].kind == nInt:
		# the literal takes the place's type itself, also where the conversion's would widen to it
		if c.tKind(target) != tInt or
			not isSameType(tys, c.heldType(typeOf(nodes, e)), target) and
			not intWidensTy(tys, c.heldType(typeOf(nodes, e)), target):
			return
	else:
		if not isSameType(tys, c.heldType(typeOf(nodes, e)), c.heldType(target)): return
		from = nodes[recv].ty ?? return
		if c.tKind(from) != tInt: return
		if not intWidensTy(tys, from, target) and not (toF64 and c.floatHolds(from, target)): return
	c.noteConversionDropped(e)

# e, a conversion call marked by markWideningCall, given to a place of its own type (where a
# value lands: fitValue) that narrows its receiver to it anyway, proven inside (narrowProven):
# noted for zap fmt as the receiver alone. A receiver of known value is left: its literals and
# names bound to them would take the place's type (`u8(r % 9)` of r = 12345 is no `r % 9`).
fn noteNarrowedAt(mut c Checker, e NodeId, maybeTarget TypeId?):
	target = maybeTarget ?? return
	if not noting or not nodes[e].hasFlag(flagWidenCandidate): return
	recv = nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0]
	if nodes[recv].ty == none or c.knownInt(recv) != none or
		not isSameType(tys, c.heldType(typeOf(nodes, e)), target):
		return
	if c.narrowsProven(recv, target): c.noteConversionDropped(e, whole = true)

# the conversion call e noted for zap fmt as its receiver alone, where its text is the
# conversion's; parenthesized when an operation that is not the whole value (whole) of its place
fn noteConversionDropped(mut c Checker, e NodeId, whole bool = false):
	if c.inResultValue(e): return
	callee = nodes[e].kids(kidIds)[0]
	recv = nodes[callee].kids(kidIds)[0]
	src = c.file if c.curFile == "" else c.curFile
	text = sourceLineOf(src, nodes[callee].line)
	t = conversionType(c.calleeName(e))
	start = nodes[callee].col - 1   # i64(x): the type's name
	if start + t.len >= text.len or text[start..start + t.len + 1] != "{t}(": return
	end = closingOf(text, start + t.len)
	# a receiver is no place: u8(55).isDigit() and f64(i).ln() need their conversion
	if end < 0 or end < text.len and text[end] == '.': return
	if whole or nodes[recv].kind in [nIdent, nField, nCall, nIndex, nInt]:
		c.canonNote(noteReplace, nodes[callee].line, end, 1, "")
		c.canonNote(noteReplace, nodes[callee].line, start + 1, t.len + 1, "")
	else:
		c.canonNote(noteReplace, nodes[callee].line, start + 1, t.len, "")   # (a + b) keeps its parentheses

# whether e is the value a function's result is being found from, or an operand of its operations:
# without its conversion the result found would differ (results-differ, result-widened)
fn inResultValue(c Checker, e NodeId):
	root = c.resultValue ?? return false
	c.operandOf(root, e)

fn operandOf(c Checker, root NodeId, e NodeId) bool:
	root == e or (nodes[root].kind == nBinary or nodes[root].kind == nUnary) and
		nodes[root].kids(kidIds).any(c.operandOf(it, e))

# a binary operation whose operands have one type: a conversion call on one side that the other
# side's type would have made anyway (u8 + i64 is i64) is noted, as long as the other side is not
# one too (both gone, the two narrow values would meet at a narrower type) and has a type of its
# own (an integer literal takes the conversion's: f64(n) / 2 is not n / 2)
fn noteWidenedOperands(mut c Checker, e NodeId, lt TypeId, rt TypeId):
	if not noting: return
	lhs = nodes[e].kids(kidIds)[0]
	rhs = nodes[e].kids(kidIds)[1]
	lc = nodes[lhs].hasFlag(flagWidenCandidate)
	rc = nodes[rhs].hasFlag(flagWidenCandidate)
	if not isSameType(tys, c.heldType(lt), c.heldType(rt)):
		if lc and not rc and c.ownTypeIs(rhs, rt): c.noteWidenedBeside(lhs, rt)
		if rc and not lc and c.ownTypeIs(lhs, lt): c.noteWidenedBeside(rhs, lt)
		return   # (ranges of one base are the same type)
	if lc and not rc and c.ownTypeIs(rhs, rt): c.noteWidenedAt(lhs, c.heldType(rt), true)
	if rc and not lc and c.ownTypeIs(lhs, lt): c.noteWidenedAt(rhs, c.heldType(lt), true)

# e, a conversion call marked by markWideningCall, beside an operand of the integer type other
# that its own type widens to: the operation is computed in other's type with or without the
# conversion (u8 + i64 and u32(u8) + i64 are an i64), so the receiver alone is noted. Only plain
# integers: a literal or a range type beside them may take another type.
fn noteWidenedBeside(mut c Checker, e NodeId, other TypeId):
	recv = nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0]
	from = nodes[recv].ty ?? return
	own = c.heldType(typeOf(nodes, e))
	if nodes[recv].kind == nInt or c.tKind(from) != tInt or c.tKind(own) != tInt: return
	if c.tKind(other) != tInt or not c.isPlainInt(from) or not c.isPlainInt(other): return
	if intWidensTy(tys, own, other) and intWidensTy(tys, from, own) and
		intWidensTy(tys, from, other):
		c.noteConversionDropped(e)

# whether t is an integer type of its own: no range, not a defined one, and not a natural (n32 and n64 add and
# subtract as quantities, so an operation beside one is typed by it)
fn isPlainInt(c Checker, t TypeId):
	not tys[t].ranged and not isDefined(tys, t) and t != tyN32 and t != tyN64

# e, a conversion call marked by markWideningCall, given to a place that takes any integer (an
# index; a shift count, which widens to an i64 on its own with counts): noted as its receiver
# alone when the receiver widens to the conversion's type, so the place reads the same value
fn noteWidenedToAnyInt(mut c Checker, e NodeId, counts bool = false):
	if not noting or not nodes[e].hasFlag(flagWidenCandidate): return
	recv = nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0]
	from = nodes[recv].ty ?? return
	own = c.heldType(typeOf(nodes, e))
	if nodes[recv].kind == nInt or c.tKind(from) != tInt or c.tKind(own) != tInt: return
	if not c.isPlainInt(from) or not intWidensTy(tys, from, own): return
	if counts and not intWidensTy(tys, from, tyInt(64, true)) and
		not isSameType(tys, from, tyInt(64, true)):
		return
	c.noteConversionDropped(e, whole = not counts)   # (an index's brackets keep what it was)

# whether e has the type t on its own (typeStandsAlone): an f32 is never a float literal's, which
# is an f64 alone
fn ownTypeIs(mut c Checker, e NodeId, t TypeId):
	c.typeStandsAlone(e) and
		not (c.tKind(t) == tFloat and tys[c.heldType(t)].bits == 32 and c.literalsOnly(e))

# whether e is made of number literals alone
fn literalsOnly(c Checker, e NodeId) bool:
	k = nodes[e].kind
	k == nInt or k == nFloat or
		(k == nBinary or k == nUnary) and nodes[e].kids(kidIds).all(c.literalsOnly(it))

# whether a literal's text is a float's (an integer a place made a float keeps its own text)
fn floatLiteralText(text str):
	not text.startsWith("0x") and ("." in text or "e" in text)

# whether an expression's type is its own, not taken from what it is next to: anything but an
# integer literal (one made a float by its place too) or a choice, and an operation all of whose
# parts are
fn typeStandsAlone(c Checker, e NodeId) bool:
	k = nodes[e].kind
	if k == nInt: return false
	if k == nIdent and c.knownInt(e) != none: return false   # a constant of a literal: it takes its neighbour's type
	if k == nFloat: return floatLiteralText(nodes[e].text)
	if k == nBinary and (nodes[e].ival == binShl or nodes[e].ival == binShr):   # the shifted value's
		return c.typeStandsAlone(nodes[e].kids(kidIds)[0])
	if k == nBinary or k == nUnary: return nodes[e].kids(kidIds).all(c.typeStandsAlone(it))
	if k == nMatch or k == nIf: return false
	if k in [nNone, nMapLit, nLambda] or k == nArray and nodes[e].kids(kidIds).isEmpty or   # typed by the place
		c.isDotVariant(e):
		return false
	if k == nArray: return c.typeStandsAlone(nodes[e].kids(kidIds)[0])   # its first element's
	if k == nSome: return false   # a value its place made optional
	if c.isTupleLiteral(e): return nodes[e].kids(kidIds).all(c.typeStandsAlone(it))   # its parts'
	if k == nCall and nodes[e].hasFlag(flagMethod):
		# a method made a call of its runtime function: the receiver is the first argument
		return c.typeStandsAlone(nodes[e].kids(kidIds)[1]) and
			nodes[e].kidsFrom(kidIds, 2).all(nodes[it].kind != nLambda)
	if k == nCall and nodes[nodes[e].kids(kidIds)[0]].kind == nField and
		nodes[nodes[e].kids(kidIds)[0]].kids(kidIds).len == 1:
		# a method's result follows its receiver (zeros(n) is a list of the literal's type), and a
		# lambda given to it may hold literals of its own
		return c.typeStandsAlone(nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0]) and
			nodes[e].kidsFrom(kidIds, 1).all(nodes[it].kind != nLambda)
	true

fn checkNumMethod(mut c Checker, e NodeId, numT TypeId):
	m = c.calleeName(e)
	line = nodes[e].line
	col = nodes[e].col
	nk = c.tKind(numT)
	vs = c.checkVecSplat(e, numT)
	if vs is vs: return vs
	if nk == tInt and m in bitFieldMethods: return c.checkBitFieldMethod(e, numT)
	rfo = c.checkNumMethodFormat(e, numT)
	if rfo is rfo: return rfo
	rco = c.checkNumMethodConvert(e, numT)
	if rco is rco: return rco
	rfl = c.checkNumMethodFloat(e, numT)
	if rfl is rfl: return rfl
	rbi = c.checkNumMethodBits(e, numT)
	if rbi is rbi: return rbi
	rra = c.checkNumMethodRange(e, numT)
	if rra is rra: return rra
	# a function taking the number's type first, or its base's for a range or a natural (n.alignUp(8))
	r = c.callReceiverFunction(e, numT, none) ??
		c.callReceiverFunction(e, rangeBase(tys, numT), none)
	if r is r: return r
	c.errorAt(
		line,
		col,
		compileError("NoMethod", ["{m}", "{c.showTy(numT)}"])
	)
	tyError

fn checkNumMethodFormat(mut c Checker, e NodeId, numT TypeId) TypeId?:
	m = c.calleeName(e)
	line = nodes[e].line
	col = nodes[e].col
	nk = c.tKind(numT)
	if c.gpuCode and nk == tFloat and gpuDerivative(m):
		c.expectArgs(e, m, 0)
		return numT
	if c.gpuCode and gpuLaneArity(m) >= 0 and m not in laneBoolMethods:
		if c.expectArgs(e, m, gpuLaneArity(m)) and m == "laneAt":
			a = c.argAt(e, 0)
			at = c.derefIfRef(a, c.checkExpr(a, tyInt(32, true)))
			if not isAssignable(tys, at, tyInt(32, true)):
				errorAt(
					c,
					nodes[a].line,
					nodes[a].col,
					compileError("GpuArgumentType", ["{m}", "i32", "{c.showTy(at)}"])
				)
		return numT   # across the lanes that run together (gpuCheck.zap)
	if m == "toFixed" and nk == tInt and nodes[e].hasFlag(flagInternal):
		c.errorAt(line, col, compileError("DecimalsNeedFloat", ["{c.showTy(numT)}"]))
		return tyError
	if m == "toHex" and nk == tInt and nodes[e].hasFlag(flagInternal):
		# "{n:x}": the runtime's i64ToHex or u64ToHex, the receiver widened to its argument
		return checkRuntimeMethod(
			c,
			e,
			"i64" if tys[numT].isSigned else "u64",
			c.showTy(numT),
			none
		)
	none

fn checkNumMethodConvert(mut c Checker, e NodeId, numT TypeId) TypeId?:
	m = c.calleeName(e)
	nk = c.tKind(numT)
	internal = nodes[nodes[e].kids(kidIds)[0]].hasFlag(flagInternal)   # written for Simd<N>(x)
	if m == "splat4" and internal and c.tKind(numT) == tFloat:
		c.expectArgs(e, m, 0)
		return tySimd   # the value in every lane
	if m == "splat16" and internal and nk == tInt:
		c.expectArgs(e, m, 0)
		return tyBytes   # the low byte in every lane
	for i, intConversion in intConversions:
		if m == intConversion:
			c.expectArgs(e, m, 0)
			return c.conversionTo(e, numT, tyInt(conversionBits(m), i < 4))
	if m == "toF32":
		c.expectArgs(e, m, 0)
		return c.conversionTo(e, numT, tyFloat(32))
	if m == "toF64":
		c.expectArgs(e, m, 0)
		return c.conversionTo(e, numT, tyFloat(64))
	if m == "abs":
		c.expectArgs(e, m, 0)
		return numT
	none

fn checkNumMethodFloat(mut c Checker, e NodeId, numT TypeId) TypeId?:
	m = c.calleeName(e)
	line = nodes[e].line
	col = nodes[e].col
	nk = c.tKind(numT)
	if nk == tFloat:
		if m == "toBits":
			c.expectArgs(e, m, 0)
			return tyInt(tys[numT].bits, false)   # the bits of the float: a u64, or an f32's u32
		if m in ["floor", "ceil", "round", "sqrt", "trunc"]:
			c.expectArgs(e, m, 0)
			return numT
		if m == "mulAdd" and nodes[e].hasFlag(flagInternal):
			# x * y + z under `use fusedMultiplyAdd` (fuse.zap), rounded once
			if not c.expectArgs(e, m, 2): return tyError
			for i in 0..2:
				c.checkExpr(c.argAt(e, i), numT)
			return numT
		if m in ["mulAdd", "mulSub", "subMul"]:
			c.errorAt(line, col, compileError("MultiplyAdd", []))
			return tyError
		fd = c.findDeclInModule("rt", nFnDecl, "f64{capital(m)}")
		if fd is fd and c.declIsPub(fd) and tys[numT].bits == 64:
			# the runtime's f64Sin, f64Atan2, f64Smoothstep...: the receiver is the first argument
			return c.checkRuntimeMethod(e, "f64", c.showTy(numT), none)
		if fd is fd and c.declIsPub(fd):
			# an f32's: the f64's, one implementation for both widths, computed in f64 and its
			# number rounded once, f32(f64(x).m(f64(args)))
			callee = nodes[e].kids(kidIds)[0]
			madeKid = c.widened(nodes[callee].kids(kidIds)[0])
			nodes[callee].setKid(kidIds, 0, madeKid)
			for i in 1..nodes[e].kids(kidIds).len:
				if not c.isNumLit(nodes[e].kids(kidIds)[i]):
					madeKid = c.widened(nodes[e].kids(kidIds)[i])
					nodes[e].setKid(kidIds, i, madeKid)
			if not isSameType(tys, c.fnRetType(fd), tyFloat(64)): return c.checkExpr(e, none)   # isClose
			wideCall = newNode(nodes, kidIds, nCall, line, col, kids = nodes[e].kids(kidIds).copy())
			narrow = newNode(nodes, kidIds, nField, line, col, text = "toF32", kids = [wideCall])
			nodes[narrow].flags |= flagInternal
			nodes[e].setKids(kidIds, [narrow])
			return c.checkExpr(e, none)
		if m == "toFixed" and nodes[e].hasFlag(flagInternal):
			# "{x:.2}": the runtime's decimals of a float
			if not c.expectArgs(e, m, 1): return tyError
			c.checkIntArg(e, 0, "toFixed expects an integer number of decimals")
			return tyStr
	none

fn checkNumMethodBits(mut c Checker, e NodeId, numT TypeId) TypeId?:
	m = c.calleeName(e)
	nk = c.tKind(numT)
	if nk == tInt and not tys[numT].isSigned and (m in ["rotateLeft", "rotateRight"]):
		if c.expectArgs(e, m, 1):
			c.checkIntArg(e, 0, "{m} expects an integer count")
		return numT   # turned by the count modulo the width
	if nk == tInt and not tys[numT].isSigned and m == "byteSwap":
		c.expectArgs(e, m, 0)
		return numT
	if nk == tInt and not tys[numT].isSigned and m == "mulHigh":
		if c.expectArgs(e, m, 1):
			arg = c.argAt(e, 0)
			at = c.checkExpr(arg, numT)
			if not isSameType(tys, at, numT) and at != tyError:
				c.errorAt(
					nodes[arg].line,
					nodes[arg].col,
					compileError("ArgumentTypeAt", ["1", m, "{c.showTy(numT)}", "{c.showTy(at)}"])
				)
		return numT   # the high half of the product twice the width
	if nk == tInt and not tys[numT].isSigned and m == "leadingZeros":
		c.expectArgs(e, m, 0)
		return tyInt(64, true)   # zero bits above the highest set (the width for 0)
	if nk == tInt and (m in ["bitCount", "trailingZeros", "hash"]):
		c.expectArgs(e, m, 0)
		if m == "hash":
			c.requireBound(numT, "Hash", "hash()", nodes[e].line, nodes[e].col)
		return tyInt(64, true)   # bits set; zero bits below the lowest set (the width for 0); the hash
	none

fn checkNumMethodRange(mut c Checker, e NodeId, numT TypeId) TypeId?:
	m = c.calleeName(e)
	line = nodes[e].line
	col = nodes[e].col
	nk = c.tKind(numT)
	if (nk == tInt or nk == tFloat) and m == "clamp":
		# x.clamp(lo, hi) is x.max(lo).min(hi): each side read once
		if not c.expectArgs(e, m, 2): return tyError
		callee = nodes[e].kids(kidIds)[0]
		lo = nodes[e].kids(kidIds)[1]
		hi = nodes[e].kids(kidIds)[2]
		maxF = newNode(
			nodes,
			kidIds,
			nField,
			line,
			col,
			text = "max",
			kids = [nodes[callee].kids(kidIds)[0]]
		)
		maxC = newNode(nodes, kidIds, nCall, line, col, kids = [maxF, lo])
		nodes[callee].text = "min"
		nodes[callee].setKids(kidIds, [maxC])
		nodes[e].setKids(kidIds, [callee, hi])
		return c.checkExpr(e, numT)
	if nk == tInt or nk == tFloat:
		if m == "min" or m == "max":
			if not c.expectArgs(e, m, 1): return tyError
			arg = c.argAt(e, 0)
			at = c.checkExpr(arg, rangeBase(tys, numT))
			if not isSameType(tys, rangeBase(tys, at), rangeBase(tys, numT)):
				c.errorAt(
					line,
					col,
					compileError("MinMaxType", ["{m}", "{c.showTy(numT)}", "{c.showTy(at)}"])
				)
			return c.extremeType(m, nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0], numT, arg, at)
	none

# the word struct t packs into with toBits (u32, or u64 past 32 bits), else none after an error
fn packedType(mut c Checker, t TypeId, line i64, col i64) TypeId?:
	total = c.packedBits(t)
	d = declOf(tys, t)
	if total < 0:
		f = nodes[d].kids(kidIds)[-1 - total]
		c.errorAt(
			line,
			col,
			compileError(
				"CannotPackBits",
				[
					"{c.showTy(t)}",
					"{nodes[f].text}",
					"{c.showTy(c.resolveType(nodes[f].types()[0]))}"
				]
			)
		)
		return none
	if total > 64 or total > 32 and c.gpuCode:
		c.errorAt(line, col, compileError("BitsTooWide", ["{c.showTy(t)}", "{total}"]))
		return none
	tyInt(32 if total <= 32 else 64, false)

# x.bit(n) and x.bits(from, count), bit n of x and its count bits from bit from (low to high), and
# x.withBit(n, on) and x.withBits(from, count, v), x with them set: a few instructions in place
# (irMethodsIntrinsics.zap); a position or count whose value the compiler knows lies inside x's
# width or is an error, any other is checked where it runs
fn checkBitFieldMethod(mut c Checker, e NodeId, numT TypeId):
	m = c.calleeName(e)
	base = rangeBase(tys, numT)
	single = m == "bit" or m == "withBit"
	positions = 1 if single else 2
	if not c.expectArgs(e, m, positions + (1 if m.startsWith("with") else 0)): return tyError
	for i in 0..positions:
		c.checkIntArg(e, i, "{m} expects integer bit positions")
	if m.startsWith("with"):
		arg = c.argAt(e, positions)
		want = tyBool if single else base
		at = c.checkExpr(arg, want)
		if not isAssignable(tys, at, want) and at != tyError:
			c.errorAt(
				nodes[arg].line,
				nodes[arg].col,
				compileError(
					"ArgumentTypeAt",
					["{positions + 1}", m.copy(), "{c.showTy(want)}", "{c.showTy(at)}"]
				)
			)
		madeKid = c.coerceTo(arg, want)
		nodes[e].setKid(kidIds, positions + 1, madeKid)
	from = foldedInt(nodes, kidIds, c.argAt(e, 0), x: none)
	count i64? = 1
	if not single:
		count = foldedInt(nodes, kidIds, c.argAt(e, 1), x: none)
	if from is from and count is count and
		(from < 0 or count < 1 or from + count > tys[base].bits):
		c.errorAt(
			nodes[e].line,
			nodes[e].col,
			compileError("BitsOutside", ["{from}..{from + count}", "{c.showTy(base)}"])
		)
		return tyError
	tyBool if m == "bit" else base

# Methods on str.
fn checkStrMethod(mut c Checker, e NodeId) TypeId:
	m = c.calleeName(e)
	if m == "contains" and c.containsCallWritten(e, "str"): return tyError
	line = nodes[e].line
	col = nodes[e].col
	nargs = c.argCount(e)
	if m == "len":
		c.expectArgs(e, m, 0)
		return tyN64
	if m == "isEmpty":
		c.expectArgs(e, m, 0)
		return tyBool
	if m == "bytes":
		c.expectArgs(e, m, 0)
		return tyRef(tys, tyList(tys, tyInt(8, false)), false)   # the bytes, no copy
	if m == "indexOf" and nargs >= 1 and c.isByteValue(c.argAt(e, 0)):
		# s.indexOf(b) of a byte: the runtime's byte search
		nodes[nodes[e].kids(kidIds)[0]].text = "indexOfByte"
		nodes[e].flags |= flagInternal
		return c.checkRuntimeMethod(e, "str", "str", none)
	if m == "slice" or m == "window":
		if not nodes[e].hasFlag(flagInternal):
			c.errorAt(line, col, compileError("NoMethod", ["{m}", "str"]))
			return tyError
		if not c.expectArgs(e, m, 2): return tyError
		c.checkIntArg(e, 0, "{m} expects integer bounds")
		c.checkIntArg(e, 1, "{m} expects integer bounds")
		return tyRef(tys, tyStr, false)   # a window, no copy
	if m == "loadWord":
		if not c.expectArgs(e, m, 1): return tyError
		c.checkIntArg(e, 0, "loadWord expects an integer index")
		c.proveWordByLength(e, c.calleeObj(e), c.argAt(e, 0))
		return tyInt(64, false)   # the eight bytes at [i, i + 8), little-endian
	c.checkRuntimeMethod(e, "str", "str", none)

# whether the argument e is a byte: a character or number literal, or a value of an integer type
# (s.indexOf(b) searches for the byte)
fn isByteValue(mut c Checker, e NodeId):
	k = nodes[e].kind
	if k == nInt: return true
	if k == nIdent:
		v = c.lookupVar(nodes[e].text)
		return v >= 0 and c.tKind(c.derefType(c.vars[v].ty)) == tInt
	if k in [nStr, nInterp, nLambda]: return false
	probe = cloneTree(nodes, kidIds, e)
	c.tKind(c.derefType(c.checkExpr(probe, none))) == tInt

# ---------- generics (monomorphization) ----------
