# The checking of binary operators, coalescing and match arms (checkExpr.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

fn checkBinary(mut c Checker, e NodeId, expected TypeId?) TypeId:
	op = nodes[e].ival
	if op == binIn: return c.checkMembership(e)
	lhs = nodes[e].kids(kidIds)[0]
	rhs = nodes[e].kids(kidIds)[1]

	if op == binCoalesce: return c.checkBinaryCoalesce(e, expected)
	if op == binAnd or op == binOr: return c.checkBinaryLogic(e)
	if (op == binEq or op == binNe) and c.isDotVariant(lhs) and not c.isDotVariant(rhs):
		# `.Clamp == mode`: the variant takes the other side's enum, so the sides trade places
		nodes[e].setKids(kidIds, [rhs, lhs])
		return c.checkBinary(e, expected)
	if (op == binEq or op == binNe) and (nodes[lhs].kind == nNone or nodes[rhs].kind == nNone):
		return c.checkBinaryPresence(e)
	if op in [binBand, binBor, binBxor, binShl, binShr]: return c.checkBinaryBitwise(e, expected)
	if op == binEq or op == binNe: return c.checkBinaryEquality(e)
	if op in [binLt, binGt, binLe, binGe]: return c.checkBinaryOrder(e)
	c.checkBinaryArith(e, expected)

fn checkBinaryCoalesce(mut c Checker, e NodeId, expected TypeId?) TypeId:
	lhs = nodes[e].kids(kidIds)[0]
	rhs = nodes[e].kids(kidIds)[1]
	line = nodes[e].line
	col = nodes[e].col
	isStmt = c.matchStmt   # `r ?? log.push(error)` alone: its sides need not be of one type
	c.matchStmt = false
	nodes[e].flags &= ~flagDerefPayload   # set again below for this instance of a generic
	lt = c.derefIfRef(lhs, c.checkExpr(lhs, none))
	if nodes[rhs].kind == nIdent and nodes[rhs].text == "fail" and c.lookupVar("fail") < 0:
		c.failWithError(rhs, lt)
	if c.tKind(lt) == tResult:
		c.noteFailAlone(rhs, lt)
		return c.checkBinaryCoalesceResult(e, isStmt, expected)
	if c.tKind(lt) != tOption:
		if c.tKind(lt) != tError:
			errorAt(
				c,
				line,
				col,
				compileError("FallbackNotOptional", ["{c.showTy(lt)}"])
			)
		return tyError
	inner = tys[lt].inner ?? expected ?? tyError   # (`none ?? v`: the expected type)
	if c.stops(rhs):
		c.noteTryOptional(e, lt)
		# `x ?? fail("why")`: the right side never gives a value, so it fits any
		c.checkExpr(rhs, none)
		if c.tKind(inner) == tRef and c.isPlainType(innerOf(tys, inner)):
			nodes[e].flags |= flagDerefPayload
			return c.typed(e, innerOf(tys, inner))
		return c.typed(e, inner)
	if c.tKind(inner) == tRef: return c.checkBinaryCoalesceRef(e, inner)
	rt = c.checkExpr(rhs, c.heldType(inner))
	if c.tKind(rt) == tRef:
		rt = c.derefIfRef(rhs, rt)   # a reference: its value (a box stays a box)
	res = rt if c.tKind(inner) == tError else inner
	if c.tKind(inner) == tInt and not isSameType(tys, rt, inner) and
		c.joinedInts([rhs], inner) is j:
		return c.typed(e, j)   # the fallback's range joins the value's
	if c.tKind(rt) == tOption and not isAssignable(tys, rt, res) and
		isAssignable(tys, rt, lt):
		res = lt   # an optional on both sides: the first present one
	elif c.tKind(rt) != tError and c.tKind(res) != tError and
		not isAssignable(tys, rt, res):
		errorAt(
			c,
			line,
			col,
			compileError("FallbackType", ["{c.showTy(res)}", "{c.showTy(rt)}"])
		)
		c.valueOnlyErrors += 1
	c.typed(e, res)

# `r ?? fail`: the program stops with r's error, `fail(error)` (the error's text when it is not a
# str); after an optional, `error` is refused as anywhere outside a result's fallback
fn failWithError(mut c Checker, rhs NodeId, lt TypeId):
	line = nodes[rhs].line
	col = nodes[rhs].col
	err = newNode(nodes, kidIds, nIdent, line, col, text = errorWord)
	if c.tKind(lt) == tResult and c.tKind(tys[lt].err ?? tyError) != tStr:
		err = shownValue(nodes, kidIds, err)
	callee = newNode(nodes, kidIds, nIdent, line, col, text = "fail")
	nodes[rhs].kind = nCall
	nodes[rhs].text = ""
	nodes[rhs].setKids(kidIds, [callee, err])

fn checkBinaryCoalesceResult(mut c Checker, e NodeId, isStmt bool, expected TypeId?) TypeId:
	lhs = nodes[e].kids(kidIds)[0]
	rhs = nodes[e].kids(kidIds)[1]
	line = nodes[e].line
	col = nodes[e].col
	# r ?? value on a T ? E: its ok side, or the value, which reads the error as `error`:
	# match r { $ok: $ok  error: value }
	okPat = newNode(nodes, kidIds, nPattern, line, col, text = "$ok{e}")
	nodes[okPat].ival = patBind
	okValue = newNode(nodes, kidIds, nIdent, line, col, text = "$ok{e}")
	ok = newNode(nodes, kidIds, nArm, line, col, kids = [okPat, okValue])
	errPat = newNode(nodes, kidIds, nPattern, line, col, text = errorWord)
	nodes[errPat].ival = patBind
	rest = newNode(nodes, kidIds, nArm, line, col, kids = [errPat, rhs])
	nodes[e].kind = nMatch
	nodes[e].setKids(kidIds, [lhs, ok, rest])
	nodes[e].ival = 0
	nodes[e].flags = flagInternal
	c.matchStmt = isStmt
	c.checkExpr(e, expected)

fn checkBinaryCoalesceRef(mut c Checker, e NodeId, inner TypeId) TypeId:
	rhs = nodes[e].kids(kidIds)[1]
	line = nodes[e].line
	col = nodes[e].col
	# an optional reference: plain data comes out as the value, anything else stays a
	# reference (the right side is referenced too, a temporary lives to the end of
	# the statement)
	target = innerOf(tys, inner)
	if c.isPlainType(target):
		rt = c.derefIfRef(rhs, c.checkExpr(rhs, target))
		if not isAssignable(tys, rt, target):
			errorAt(
				c,
				line,
				col,
				compileError("FallbackType", ["{c.showTy(target)}", "{c.showTy(rt)}"])
			)
		nodes[e].flags |= flagDerefPayload
		return c.typed(e, target)
	rt = c.checkExpr(rhs, target)
	if c.tKind(rt) != tRef:
		if not isAssignable(tys, rt, target):
			errorAt(
				c,
				line,
				col,
				compileError("FallbackType", ["{c.showTy(target)}", "{c.showTy(rt)}"])
			)
		c.refNode(rhs)
	elif not isAssignable(tys, rt, inner):
		errorAt(
			c,
			line,
			col,
			compileError("FallbackType", ["{c.showTy(inner)}", "{c.showTy(rt)}"])
		)
	c.typed(e, inner)

fn checkBinaryLogic(mut c Checker, e NodeId) TypeId:
	op = nodes[e].ival
	lhs = nodes[e].kids(kidIds)[0]
	rhs = nodes[e].kids(kidIds)[1]
	line = nodes[e].line
	col = nodes[e].col
	lt = c.derefIfRef(lhs, c.checkExpr(lhs, tyBool))
	known = c.lenFacts.len
	c.narrowBy(lhs, op == binAnd, onlyLengths = true)   # the right runs when the left decided not
	c.forgetChangedIndexes(rhs)
	rt = c.derefIfRef(rhs, c.checkExpr(rhs, tyBool))
	c.lenFacts.truncate(known)
	if op == binOr: c.noteEqualsChain(e)
	if c.tKind(lt) != tBool or c.tKind(rt) != tBool:
		errorAt(
			c,
			line,
			col,
			compileError("LogicNeedsBool", ["{c.showTy(lt)}", "{c.showTy(rt)}"])
		)
	c.typed(e, tyBool)

fn checkBinaryPresence(mut c Checker, e NodeId) TypeId:
	lhs = nodes[e].kids(kidIds)[0]
	rhs = nodes[e].kids(kidIds)[1]
	line = nodes[e].line
	col = nodes[e].col
	# presence test: `opt == none` / `opt != none`
	val = lhs
	non = rhs
	if nodes[lhs].kind == nNone:
		val = rhs
		non = lhs
	vt = c.checkExpr(val, none)
	if c.tKind(vt) != tOption and c.tKind(vt) != tError:
		errorAt(
			c,
			line,
			col,
			compileError("NoneComparison", ["{c.showTy(vt)}"])
		)
	nodes[non].ty = vt
	c.typed(e, tyBool)

fn checkBinaryBitwise(mut c Checker, e NodeId, expected TypeId?) TypeId:
	op = nodes[e].ival
	lhs = nodes[e].kids(kidIds)[0]
	rhs = nodes[e].kids(kidIds)[1]
	line = nodes[e].line
	col = nodes[e].col
	want TypeId? = none
	if c.tKind(expected) == tInt and expected is wanted:
		want = rangeBase(tys, wanted)
	lt = c.derefIfRef(lhs, c.checkExpr(lhs, want))
	rt = c.derefIfRef(
		rhs,
		c.checkExpr(rhs, rangeBase(tys, lt) if c.tKind(lt) == tInt else lt)
	)
	if c.tKind(lt) == tError or c.tKind(rt) == tError: return c.typed(e, tyError)
	if c.tKind(lt) == tBytes and c.tKind(rt) == tBytes and (op in [binBand, binBor, binBxor]):
		nodes[e].ty = tyBytes   # byte by byte
		return tyBytes
	if c.tKind(lt) == tVec and isSameType(tys, lt, rt) and c.vecHasOp(lt, op):
		nodes[e].ty = lt   # lane by lane
		return lt
	if op != binShl and op != binShr:
		c.noteWidenedOperands(e, lt, rt)
	else:
		c.noteWidenedToAnyInt(rhs, counts = true)
	if c.tKind(lt) != tInt or c.tKind(rt) != tInt:
		errorAt(
			c,
			line,
			col,
			compileError("BitwiseNeedsIntegers", ["{c.showTy(lt)}", "{c.showTy(rt)}"])
		)
	elif (op == binShl or op == binShr) and not isSameType(tys, lt, rt):
		# the shift count may be any integer: the result has the type of the shifted value
		c.widenKid(e, 1, tyInt(64, true))
	elif not isSameType(tys, lt, rt):
		# the narrower operand widens, as in arithmetic
		if c.numCommon(lt, rt) is common:
			c.widenKid(e, 0, common)
			c.widenKid(e, 1, common)
			return c.typed(e, c.carriedType(op, lhs, lt, rhs, rt, common))
		c.errorAt(line, col, c.operandsError("MixedTypes", lt, rt))
	if isDefined(tys, lt): return c.typed(e, c.keepDefined(lt, rangeBase(tys, underOf(tys, lt))))
	if op == binShl and not tys[rangeBase(tys, lt)].isSigned:   # bits
		return c.typed(e, rangeBase(tys, lt))
	c.typed(e, c.carriedType(op, lhs, lt, rhs, rt, lt))

fn checkBinaryEquality(mut c Checker, e NodeId) TypeId:
	op = nodes[e].ival
	lhs = nodes[e].kids(kidIds)[0]
	rhs = nodes[e].kids(kidIds)[1]
	line = nodes[e].line
	col = nodes[e].col
	lt = c.derefIfRef(lhs, c.checkExpr(lhs, none))
	rt = c.derefIfRef(rhs, c.checkExpr(rhs, lt))
	c.noteEmptyTest(e, op)
	c.noteWidenedOperands(e, lt, rt)
	c.requireBound(lt, "Eq", "'{binName(op)}'", line, col)
	common = c.widenToCommon(e, lt, rt)
	if common is common:
		lt = common
		rt = common
	# an optional and a value of its type: the value wrapped (equal when the optional holds it)
	if c.isNumLit(lhs) and c.tKind(rt) == tOption and tys[rt].inner != none:
		lt = c.checkExpr(lhs, tys[rt].inner)   # a literal on the left takes the value's type
	if c.tKind(lt) == tOption and tys[lt].inner != none and isSameType(tys, tys[lt].inner, rt):
		c.coerceKid(e, 1, lt)
		rt = lt
	elif c.tKind(rt) == tOption and tys[rt].inner != none and
		isSameType(tys, tys[rt].inner, lt):
		c.coerceKid(e, 0, rt)
		lt = rt
	withNone = nodes[lhs].kind == nNone or nodes[rhs].kind == nNone
	if not isSameType(tys, lt, rt):
		c.errorAt(
			line,
			col,
			c.operandsError("CannotCompare", lt, rt)
		)
	elif not withNone and not c.isEqNative(lt):
		# part by part: a struct's fields, a list's elements, an enum's variant and values
		if c.typeHasEq(lt):
			c.noteDerive(lt, deriveEq)
		else:
			c.errorAt(line, col, compileError("NoEquality", ["{c.showTy(lt)}"]))
	c.typed(e, tyBool)

fn checkBinaryOrder(mut c Checker, e NodeId) TypeId:
	op = nodes[e].ival
	lhs = nodes[e].kids(kidIds)[0]
	rhs = nodes[e].kids(kidIds)[1]
	line = nodes[e].line
	col = nodes[e].col
	litLeft = c.isNumLit(lhs) and not c.isNumLit(rhs)
	# a literal on the left adopts the type of the right operand (0 < n with n i64)
	lt TypeId = tyError
	rt TypeId = tyError
	if litLeft:
		rt = c.derefIfRef(rhs, c.checkExpr(rhs, none))
		lt = c.derefIfRef(lhs, c.checkExpr(lhs, c.numOrNone(rt)))
	else:
		lt = c.derefIfRef(lhs, c.checkExpr(lhs, none))
		rt = c.derefIfRef(rhs, c.checkExpr(rhs, c.numOrNone(lt)))
		if op == binGt: c.noteEmptyTest(e, op)
	c.noteWidenedOperands(e, lt, rt)
	common = c.widenToCommon(e, lt, rt)
	if common is common:
		lt = common
		rt = common
	c.requireBound(lt, "Ord", "'{binName(op)}'", line, col)
	lk = c.tKind(lt)
	if isSameType(tys, lt, rt) and lk != tInt and lk != tFloat and lk != tStr and
		lk != tError and
		c.typeHasOrd(lt):
		c.noteDerive(lt, deriveCmp)   # a tuple, list or array: in order, part by part
		return c.typed(e, tyBool)
	known = c.tKind(lt) != tError and c.tKind(rt) != tError
	if known and
		(not (typeIsNumeric(tys, lt) or c.tKind(lt) == tStr) or not isSameType(tys, lt, rt)) and
		not c.retypeFlex(lhs, rt) and not c.retypeFlex(rhs, lt):
		c.errorAt(line, col, c.operandsError("CannotOrder", lt, rt))
	c.rejectDecidedComparison(e, op)
	c.typed(e, tyBool)

fn checkBinaryArith(mut c Checker, e NodeId, expected TypeId?) TypeId:
	op = nodes[e].ival
	lhs = nodes[e].kids(kidIds)[0]
	rhs = nodes[e].kids(kidIds)[1]
	line = nodes[e].line
	col = nodes[e].col
	litLeft = c.isNumLit(lhs) and not c.isNumLit(rhs)
	# arithmetic (a literal on the left adopts the type of the right operand)
	lt TypeId = tyError
	rt TypeId = tyError
	if litLeft:
		rt = c.derefIfRef(rhs, c.checkExpr(rhs, c.numOrNone(expected)))
		lt = c.derefIfRef(lhs, c.checkExpr(lhs, c.numOrNone(rt)))
	else:
		lt = c.derefIfRef(lhs, c.checkExpr(lhs, c.numOrNone(expected)))
		want = c.numOrNone(lt)
		if want == none:
			want = c.numOrNone(expected)
		rt = c.derefIfRef(rhs, c.checkExpr(rhs, want))
	c.requireBound(lt, "Num", "'{binName(op)}'", line, col)
	lk = c.tKind(lt)
	rk = c.tKind(rt)
	if op == binAdd and lk == tStr and rk == tStr:
		c.typed(e, tyStr)
		c.literalJoin(e)
		return tyStr
	if c.gridKind(lt) == gridWhole or c.gridKind(rt) == gridWhole:
		return c.checkGridMath(e, op, lt, rt, expected)
	if c.isTensorType(lt) or c.isTensorType(rt): return c.checkTensorMath(e, op, lt, rt, expected)
	if lk == tStruct or rk == tStruct: return c.checkStructMath(e, op, lt, rt)
	c.checkBinaryArithRest(e, lt, rt, expected)

fn checkBinaryArithRest(mut c Checker, e NodeId, lt TypeId, rt TypeId, expected TypeId?) TypeId:
	op = nodes[e].ival
	lhs = nodes[e].kids(kidIds)[0]
	rhs = nodes[e].kids(kidIds)[1]
	line = nodes[e].line
	col = nodes[e].col
	lk = c.tKind(lt)
	rk = c.tKind(rt)
	# vectors and matrices: lists of numbers, and lists of those
	if c.numListElem(lt) != none or c.numListElem(rt) != none or c.numMatrixElem(lt) != none or
		c.numMatrixElem(rt) != none:
		return c.checkListMath(e, op, lt, rt)
	if op == binMatmul and (lk == tArray or rk == tArray): return c.checkArrayProduct(e, lt, rt)
	if op == binMatmul:
		c.errorAt(line, col, compileError("ProductNotMatrix", []))
		return tyError
	if lk == tError or rk == tError: return tyError
	# a number next to a vector is that number in every lane (each instance writes how)
	if c.isOpenVector(lt) and (rk == tInt or rk == tFloat):
		madeKid = c.laneValue(nodes[e].kids(kidIds)[1], innerOf(tys, lt))
		nodes[e].setKid(kidIds, 1, madeKid)
		return c.typed(e, lt)
	if c.isOpenVector(rt) and (lk == tInt or lk == tFloat):
		madeKid = c.laneValue(nodes[e].kids(kidIds)[0], innerOf(tys, rt))
		nodes[e].setKid(kidIds, 0, madeKid)
		return c.typed(e, rt)
	if (lk == tSimd or lk == tVec) and (rk == tInt or rk == tFloat):
		madeKid = c.splatTo(nodes[e].kids(kidIds)[1], lt)
		nodes[e].setKid(kidIds, 1, madeKid)
		return c.checkBinary(e, expected)
	if (rk == tSimd or rk == tVec) and (lk == tInt or lk == tFloat):
		madeKid = c.splatTo(nodes[e].kids(kidIds)[0], rt)
		nodes[e].setKid(kidIds, 0, madeKid)
		return c.checkBinary(e, expected)
	if lk == tSimd and rk == tSimd and (op in [binAdd, binSub, binMul, binDiv]):
		nodes[e].ty = tySimd   # lane by lane
		return tySimd
	if lk == tBytes and rk == tBytes and (op in [binAdd, binSub, binBand, binBor, binBxor]):
		nodes[e].ty = tyBytes   # byte by byte, wrapping
		return tyBytes
	if lk == tVec or rk == tVec:
		if isSameType(tys, lt, rt) and c.vecHasOp(lt, op):
			nodes[e].ty = lt   # lane by lane (integers wrap)
			return lt
		errorAt(
			c,
			line,
			col,
			compileError("NoLaneOperator", ["{c.showTy(lt)}", "{c.showTy(rt)}"])
		)
		return tyError
	if not typeIsNumeric(tys, lt) or not typeIsNumeric(tys, rt):
		c.errorAt(
			line,
			col,
			compileError("ArithmeticNeedsNumbers", ["{c.showTy(lt)}", "{c.showTy(rt)}"])
		)
		return tyError
	c.noteWidenedOperands(e, lt, rt)
	if not isSameType(tys, lt, rt):
		common = c.numCommon(lt, rt) ?? return c.mixedOperands(e, lhs, lt, rhs, rt)
		c.widenKid(e, 0, common)
		c.widenKid(e, 1, common)
		return c.typed(e, c.arithResult(op, lhs, lt, rhs, rt, common))
	c.typed(e, c.arithResult(op, lhs, lt, rhs, rt, lt))

# A match giving its value, of two arms of one pattern each and no condition, whose first arm
# gives the name it binds (`v: v`) and whose other gives a value of that name's type, or leaves (on an
# optional the other arm is none or _, on a result _ or error): zap fmt may write it with ??
# (canon.zap, rewrite.zap)
fn coalesceForm(mut c Checker, e NodeId, scrutT TypeId, isStmt bool):
	if not noting or isStmt or nodes[e].hasFlag(flagInternal) or nodes[e].text == "??" or
		nodes[e].kids(kidIds).len != 3:
		return
	a1 = nodes[e].kids(kidIds)[1]
	a2 = nodes[e].kids(kidIds)[2]
	if nodes[a1].ival != 0 or nodes[a2].ival != 0 or c.armGuard(a1) != none or
		c.armGuard(a2) != none or
		c.armBlock(a1) != none or c.armBlock(a2) != none:
		return
	p1 = c.armPattern(a1)
	k2 = nodes[c.armPattern(a2)].ival
	sk = c.tKind(scrutT)
	if nodes[p1].ival != patBind or not nodes[p1].kids(kidIds).isEmpty or
		not (
			sk == tOption and (k2 == patNone or k2 == patWildcard) or
				sk == tResult and not nodes[p1].bindsError() and
				(k2 == patWildcard or nodes[c.armPattern(a2)].bindsError())
		):
		return
	v = c.armBody(a1)
	while (nodes[v].kind == nDeref or nodes[v].kind == nSome) and not nodes[v].kids(kidIds).isEmpty:
		v = nodes[v].kids(kidIds)[0]   # as checked: the bound name read
	other = c.armBody(a2)
	alike = c.stops(other) or
		nodes[v].ty != none and nodes[other].ty != none and
		isSameType(tys, c.derefType(typeOf(nodes, v)), c.derefType(typeOf(nodes, other)))
	if alike and nodes[v].kind == nIdent and nodes[v].text == nodes[p1].text:
		c.canonNote(noteCoalesce, nodes[e].line, nodes[e].col, 0, "")

# A struct's literal (the call e of struct d's name) that names each field, at least one `f = b.f`
# of one local b of its type (not a field) and one not, every field plain data, the others' values
# reading b only by its fields: zap fmt writes `Type(..b, g = v)` (canon.zap). b's fields are
# copied either way, read before the others' values, which cannot change them.
fn baseForm(mut c Checker, e NodeId, d NodeId):
	if not noting or not nodes[d].names().isEmpty or
		nodes[e].kids(kidIds).len - 1 != nodes[d].kids(kidIds).len:
		return   # a generic type, a field left out
	base = ""
	fromBase = []
	for i in 1..c.nodes[e].kids(c.kidIds).len:
		a = nodes[e].kids(kidIds)[i]
		if nodes[a].kind != nNamedArg or nodes[a].text == "..": return
		v = nodes[a].kids(kidIds)[0]
		from = false
		if nodes[v].kind == nField and nodes[v].text == nodes[a].text and
			nodes[nodes[v].kids(kidIds)[0]].kind == nIdent:
			b = nodes[nodes[v].kids(kidIds)[0]].text
			if base == "" or base == b:
				base = b.copy()
				from = true
		fromBase.push(from)
	if base == "" or fromBase.all(it): return
	vi = c.lookupVar(base)
	if vi < 0 or c.vars[vi].isField or
		not isSameType(tys, c.derefType(c.vars[vi].ty), tyOfDecl(tys, nodes, d)):
		return
	for f in nodes[d].kids(kidIds).copy():
		if not c.isPlainType(c.resolveType(nodes[f].types()[0])): return
	for i in 1..c.nodes[e].kids(c.kidIds).len:
		if not fromBase[i - 1] and
			not c.readsFieldsOnly(nodes[nodes[e].kids(kidIds)[i]].kids(kidIds)[0], base):
			return
	# the text: the type's name (module.Type) to the parentheses' end, on one line
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind != nIdent: return
	src = c.file if c.curFile == "" else c.curFile
	line = nodes[callee].line
	text = sourceLineOf(src, line)
	start = nodes[callee].col - 1
	open = start
	while open < text.len and text[open].isWordByte():
		open += 1
	if start < 0 or open == start or open >= text.len or text[open] != '(' or
		text[start..open] != nodes[callee].text:
		return
	close = closingOf(text, open)
	if close < 0: return
	parts = topLevelParts(text[open + 1..close - 1])
	if parts.len != fromBase.len: return
	kept = []
	for i in 0..parts.len:
		field = nodes[nodes[e].kids(kidIds)[i + 1]].text
		if fromBase[i]:
			if parts[i] != "{field} = {base}.{field}":
				return   # written otherwise than the tree says
		else:
			kept.push(parts[i].copy())
	canonNote(
		c,
		noteReplace,
		line,
		start + 1,
		close - start,
		"{text[start..open]}(..{base}, {kept.join(", ")})"
	)

# whether e reads the variable `name` only through its fields (no call on it, no other use)
fn readsFieldsOnly(c Checker, e NodeId, name str) bool:
	k = nodes[e].kind
	if k == nIdent and nodes[e].text == name: return false
	if k == nCall:
		callee = nodes[e].kids(kidIds)[0]
		if nodes[callee].kind == nField and nodes[nodes[callee].kids(kidIds)[0]].kind == nIdent and
			nodes[nodes[callee].kids(kidIds)[0]].text == name:
			return false   # a method of it, which may change it
	if k == nField and nodes[nodes[e].kids(kidIds)[0]].kind == nIdent and
		nodes[nodes[e].kids(kidIds)[0]].text == name:
		return true
	nodes[e].kids(kidIds).all(c.readsFieldsOnly(it, name)) and
		nodes[e].sub().all(c.readsFieldsOnly(it, name))

# whether e is `.Variant` or `.Variant(...)`, a variant whose enum its place gives
fn isDotVariant(c Checker, e NodeId):
	v = e
	if nodes[v].kind == nCall:
		v = nodes[v].kids(kidIds)[0]
	nodes[v].kind == nField and nodes[v].hasFlag(flagDotVariant)

# ---------- match ----------

# A match arm binding a List or Map out of a `mut` place keeps it mutable: those are references.
# (lowered: also through a method call the checker made a runtime function's, `m.getMut(k)`)
fn scrutRootIsMut(mut c Checker, e0 NodeId, lowered bool = false):
	v = c.scrutRoot(e0, lowered)
	v >= 0 and c.vars[v].isMut

# whether a match's `mut` name on e names a place that may change: a `mut` root, or the receiver
# of a block's method whose mode its body tells (receivers.zap)
fn mutNameHasPlace(mut c Checker, e NodeId, line i64, col i64):
	c.scrutRootIsMut(e, lowered = true) or c.receiverNamed(c.scrutRoot(e, true), line, col)

# the variable at the root of the place a match's names point into, or -1
fn scrutRoot(mut c Checker, e0 NodeId, lowered bool) i64:
	e = matchedPlaceOf(nodes, kidIds, e0)
	while lowered and nodes[e].kind == nCall and nodes[c.writtenCallee(e)].kind == nField:
		e = matchedPlaceOf(nodes, kidIds, nodes[c.writtenCallee(e)].kids(kidIds)[0])
	if nodes[e].kind != nIdent: return -1
	c.lookupVar(nodes[e].text)

# A name bound by a match arm points into the value matched: it may change it when that value
# is a mutable place (`match hosted { server => step(server) }` steps the server in place).
fn bindMut(mut c Checker, matchExpr NodeId, t TypeId) bool:
	_ = t
	c.scrutRootIsMut(nodes[matchExpr].kids(kidIds)[0])

# the functions that end the program: a call of one never gives a value
stoppingFunctions = [
	"fail",
	"failAt",
	"boundsFail",
	"exit",
	"exitWith",
	"exitSaying",
	"stopWith"
]

# whether name (a local name or the runtime's global one) is a function that ends the program
fn endsProgram(name str):
	name in stoppingFunctions or
		(name.startsWith("rt__") and name[4..] in stoppingFunctions)

# whether e never gives a value (a return, a break, a continue, fail, exit), so its place may
# take a value of any type
fn stops(c Checker, e NodeId):
	k = nodes[e].kind
	if k in [nReturn, nBreak, nContinue]: return true
	if k != nCall: return false
	callee = nodes[e].kids(kidIds)[0]
	nodes[callee].kind == nIdent and endsProgram(nodes[callee].text)

fn armBlock(c Checker, arm NodeId) NodeId?:
	if not nodes[arm].sub().isEmpty: return nodes[arm].sub()[0]
	none

fn armBody(c Checker, arm NodeId):
	nodes[arm].kids(kidIds)[1]

# Checks one arm body. In statement form arms are blocks or unit expressions and the match has
# no value; in expression form every arm yields the same type.
fn checkArmBody(mut c Checker, arm NodeId, resultT TypeId?, isStmt bool):
	blk = c.armBlock(arm)
	if blk is blk:
		if isStmt:
			c.checkBlock(blk)
			return tyUnit
		# expression match: the block's last statement is the arm's value
		n = nodes[blk].kids(kidIds).len
		valued = n > 0 and nodes[nodes[blk].kids(kidIds)[n - 1]].kind == nExprStmt
		c.checkStmts(blk, n - 1 if valued else n)
		if valued:
			st = nodes[blk].kids(kidIds)[n - 1]
			ex = nodes[st].kids(kidIds)[0]
			t = c.checkExpr(ex, resultT)
			if resultT is resultT and isAssignable(tys, t, resultT):
				madeKid = c.coerceTo(ex, resultT)
				nodes[st].setKid(kidIds, 0, madeKid)
				t = resultT
			return t
		if n > 0 and c.blockTerminates(blk):
			if resultT is resultT: return resultT
			return tyError
		errorAt(
			c,
			nodes[arm].line,
			nodes[arm].col,
			compileError("ArmMissingValue", [])
		)
		c.valueOnlyErrors += 1
		return tyError
	body = c.armBody(arm)
	# a nested match in a statement-form arm is a statement too
	if isStmt and nodes[body].kind == nMatch:
		c.matchStmt = true
	want = resultT
	if isStmt:
		want = none
	t = c.checkExpr(body, want)
	if not isStmt and resultT is resultT and c.tKind(t) != tError and
		not isSameType(tys, t, resultT) and
		isAssignable(tys, t, resultT):
		madeKid = c.coerceTo(body, resultT)
		nodes[arm].setKid(kidIds, 1, madeKid)
		t = resultT
	t

fn unifyArmType(
	mut c Checker,
	e NodeId,
	arm NodeId,
	maybeResultT TypeId?,
	bodyT TypeId,
	isStmt bool
) TypeId?:
	if isStmt: return maybeResultT
	v = c.armValue(arm)
	if v is v and c.stops(v):
		return maybeResultT   # `none => fail("...")`: it leaves, any type fits
	resultT = maybeResultT ?? return bodyT
	# a place of T beside a ref T: the place is lent, and the match yields ref T
	if c.tKind(resultT) == tRef and tys[resultT].bits == 0 and
		isSameType(tys, bodyT, tys[resultT].inner) and c.armValue(arm) is lendable and
		c.isLendable(lendable):
		c.refNode(lendable)
		return resultT
	if c.tKind(bodyT) == tRef and tys[bodyT].bits == 0 and
		isSameType(tys, resultT, tys[bodyT].inner) and c.placesBefore(e, arm):
		for prior in c.matchArms(e):
			if prior == arm: break
			if c.armValue(prior) is place: c.refNode(place)
		return bodyT
	if c.isReadRefStr(bodyT) and c.literalsBefore(e, arm):
		# "" then a borrowed str: the literals are lent too, and the match yields ref str
		for prior in c.matchArms(e):
			if prior == arm: break
			if c.armValue(prior) is literal: nodes[literal].ty = bodyT
		return bodyT
	if isDefined(tys, bodyT) and typeIsNumeric(tys, resultT) and
		c.tKind(resultT) == c.tKind(bodyT) and c.literalsBefore(e, arm, true):
		# number literals, then a defined type's value: the literals are of that type
		for prior in c.matchArms(e):
			if prior == arm: break
			if c.armValue(prior) is literal: c.checkExpr(literal, bodyT)
		return bodyT
	if not isSameType(tys, bodyT, resultT):
		errorAt(
			c,
			nodes[arm].line,
			nodes[arm].col,
			compileError("ArmTypesDiffer", ["{c.showTy(resultT)}", "{c.showTy(bodyT)}"])
		)
		c.valueOnlyErrors += 1
	resultT

# the match's type once its arms are checked (a statement's unit); `missing` the error when the
# arms do not cover every value, "" when they do
fn matchEnd(mut c Checker, e NodeId, resultT TypeId?, isStmt bool, missing str) TypeId:
	if missing != "":
		c.errorAt(nodes[e].line, nodes[e].col, missing)
	c.typed(e, tyUnit if isStmt else resultT ?? tyUnit)

fn armPattern(c Checker, arm NodeId):
	nodes[arm].kids(kidIds)[0]

# the expected type of an arm: none while every arm before it is a string literal and the
# result would be str, so a later arm that borrows a str makes them all ref str
fn armWant(c Checker, e NodeId, arm NodeId, resultT TypeId?):
	if resultT == tyStr and c.literalsBefore(e, arm): return none
	resultT

# whether every arm of match e before arm yields a plain string literal (there is one at least)
fn literalsBefore(c Checker, e NodeId, arm NodeId, numbers bool = false):
	for prior in c.matchArms(e):
		if prior == arm: return true
		v = c.armValue(prior) ?? return false
		if (not c.isNumLit(v) if numbers else nodes[v].kind != nStr): return false
	false

# whether e is a place a reference can point at: a variable, a field or an element of one
fn isLendable(c Checker, maybeE NodeId?) bool:
	e = maybeE ?? return false
	k = nodes[e].kind
	if k == nIdent: return true
	(k == nField or k == nIndex) and c.isLendable(nodes[e].kids(kidIds)[0])

# whether every arm of match e before arm yields a place (there is one at least)
fn placesBefore(c Checker, e NodeId, arm NodeId):
	for prior in c.matchArms(e):
		if prior == arm: return true
		if not c.isLendable(c.armValue(prior)): return false
	false

# the expression an arm yields: its body, or the last statement of its block, if any
fn armValue(c Checker, arm NodeId) NodeId?:
	blk = c.armBlock(arm) ?? return c.armBody(arm)
	n = nodes[blk].kids(kidIds).len
	if n == 0 or nodes[nodes[blk].kids(kidIds)[n - 1]].kind != nExprStmt: return none
	nodes[nodes[blk].kids(kidIds)[n - 1]].kids(kidIds)[0]

# the condition of an arm (`Rect(w, h) and w == h:`, kept by its pattern), or none
fn armGuard(c Checker, arm NodeId) NodeId?:
	pat = c.armPattern(arm)
	nodes[pat].sub()[0] if not nodes[pat].sub().isEmpty else none

# the names the arm's pattern has bound so far (the variables of the innermost scope) and their
# types, in the order of the names: "r f32, w f32"
fn boundSignature(c Checker):
	start = c.scopeStarts[len - 1]
	parts = []
	for i in start..c.vars.len:
		if c.vars[i].name == "_" or c.vars[i].name == mapPatternName: continue
		parts.push("{c.vars[i].name} {c.showTy(c.vars[i].ty)}")
	parts.sort()
	parts.join(", ")

# The rest of an arm once its pattern's names are in scope: its condition, a bool that may read
# them; the names held to those the other patterns written in the same arm bind (`alts`: per
# written arm, its first pattern's); its body, whose type joins the match's (returned). An arm's
# value whose type only the arms before it give (no outer expected type) is told so: `.Variant`
# takes its type from where it goes, not from a sibling.
fn checkArmRest(
	mut c Checker,
	e NodeId,
	arm NodeId,
	resultT TypeId?,
	expected TypeId?,
	isStmt bool,
	mut alts {i64: str}
) TypeId?:
	guard = c.armGuard(arm)
	if guard is guard:
		gt = c.checkExpr(guard, tyBool)
		if c.tKind(gt) != tBool and c.tKind(gt) != tError:
			errorAt(
				c,
				nodes[guard].line,
				nodes[guard].col,
				compileError("ArmConditionNotBool", ["{c.showTy(gt)}"])
			)
	group i64 = nodes[arm].ival
	if group > 0:
		names = c.boundSignature()
		match alts.get(group):
			first:
				if first != names:
					c.errorAt(
						nodes[arm].line,
						nodes[arm].col,
						compileError("ArmBindingsDiffer", ["{first}", "{names}"])
					)
			none: alts[group] = names
	if expected == none and resultT != none and not isStmt:
		c.weakExpected = c.armValue(arm)
	open = expected == none and not isStmt and resultT != none
	want = c.armWant(e, arm, resultT)
	if open and want is w and c.tKind(w) == tInt and not isDefined(tys, w):
		want = rangeBase(tys, w)   # the arms' ranges join (joinedInts)
	bodyT = c.checkArmBody(arm, want, isStmt)
	c.weakExpected = none
	if open and not isSameType(tys, bodyT, resultT):
		upTo = []
		valued = true
		for prior in c.matchArms(e):
			match c.armValue(prior):
				v: upTo.push(v)
				none: valued = false
			if prior == arm: break
		if valued and c.joinedInts(upTo, none) is j: return j
	c.unifyArmType(e, arm, resultT, bodyT, isStmt)

# a list of its own: callers check each arm with a mutable checker while they walk the arms
fn matchArms(c Checker, e NodeId):
	nodes[e].kidsFrom(kidIds, 1).copy()
