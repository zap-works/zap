# The checking of lambdas, closures and slices, and the walk over expressions (checkexpr.zap).

alias nodes = c.nodes
alias tys = c.types

# A lambda outside a pipeline is a closure value of type fn(P...) R. Parameter types come from
# annotations or from the expected fn type; outer variables it reads are captured by value.
fn checkLambda(mut c Checker, e NodeId, expected TypeId?) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	# the parameter names are read from e at each use: checking the body changes c
	n = nodes[e].names.len
	want TypeId? = none
	if c.tKind(expected) == tFn and expected is fnT:
		if tys[fnT].params.len == n:
			want = fnT
		else:
			c.errorAt(line, col, compileError("LambdaArity", ["{n}", "{c.showTy(fnT)}"]))
	ps = []
	ok = true
	for i in 0..n:
		te = nodes[e].types[i]
		pt TypeId? = none
		if nodes[te].kind != nTyAbsent:
			pt = c.resolveType(te)
		elif want is want:
			pt = tys[want].params[i]
		if pt == none:
			c.errorAt(
				line,
				col,
				compileError("CannotInferLambdaParameter", ["{nodes[e].names[i]}"])
			)
			ok = false
		ps.push(pt ?? tyError)
	c.lambdaCount += 1
	nodes[e].ival = c.lambdaCount
	c.enterScope()
	c.lamStack.push(e)
	c.lamBounds.push(c.scopeStarts.len - 1)
	for i in 0..n:
		c.addVar(nodes[e].names[i], ps[i], false, true, line, col)
	saveRet = c.currentRet
	saveLoop = c.loopDepth
	saveImpl = c.implType
	c.loopDepth = 0
	rt TypeId? = none
	wantRet TypeId? = match want:
		w: tys[w].ret
		none: none
	if not nodes[e].sub.isEmpty:
		rt = c.checkLambdaBlock(e, want, wantRet, line, col)
	else:
		rt = c.checkLambdaExpr(e, want, wantRet, line, col)
	c.currentRet = saveRet
	c.loopDepth = saveLoop
	c.implType = saveImpl
	c.lamStack.pop()
	c.lamBounds.pop()
	c.exitScope()
	res = tyError
	if ok:
		res = tyFn(tys, ps, rt)
	c.typed(e, res)

fn checkLambdaBlock(
	mut c Checker,
	e NodeId,
	want TypeId?,
	wantRet TypeId?,
	line i64,
	col i64
):
	rt TypeId? = none
	blk = nodes[e].sub[0]
	sInfer = c.inferringRet
	sInferRet = c.inferRet
	if want != none:
		rt = wantRet
		c.currentRet = rt
		c.inferringRet = false
	else:
		c.inferringRet = true
		c.inferRet = none
		c.currentRet = none
	savedTail = c.valueTail
	c.valueTail = nodes[blk].kids[nodes[blk].kids.len - 1] if not nodes[blk].kids.isEmpty else none
	c.checkBlock(blk)
	c.valueTail = savedTail
	c.reportTailReturns(blk)
	c.checkLambdaTail(blk, want, wantRet)
	if want == none:
		rt = c.inferRet ?? tyUnit
	c.inferringRet = sInfer
	c.inferRet = sInferRet
	if c.tKind(rt) != tUnit and not c.blockTerminates(blk):
		errorAt(
			c,
			line,
			col,
			compileError("MissingReturn", ["lambda", c.showTy(rt)])
		)
	rt

fn checkLambdaTail(mut c Checker, blk NodeId, want TypeId?, wantRet TypeId?):
	# a trailing expression is the lambda's result, as in a function, when no return was
	# seen and a value is wanted (or being inferred)
	kids = nodes[blk].kids
	if not kids.isEmpty and nodes[kids[len - 1]].kind == nExprStmt:
		last = kids[len - 1]
		ex = nodes[last].kids[0]
		et = typeOf(nodes, ex)
		if want == none and c.tKind(et) == tRef:
			# a lambda's result is a value: a reference is copied out (see checkReturn)
			et = innerOf(tys, et)
			ex = c.coerceTo(ex, et)
			nodes[last].kids[0] = ex
		if c.tKind(et) != tUnit and c.tKind(et) != tError:
			if want == none and isAssignable(tys, et, c.inferRet ?? et):
				# the result, or the same type an early return already gave
				nodes[last].kind = nReturn
				nodes[last].ival = 2   # implicit: not written as a return
				if c.inferRet == none:
					c.inferRet = c.heldType(et)
			elif wantRet is wr and c.tKind(wr) != tUnit and isAssignable(tys, et, wr):
				nodes[last].kind = nReturn
				nodes[last].ival = 2
				nodes[last].kids[0] = c.coerceTo(ex, wr)

fn checkLambdaExpr(
	mut c Checker,
	e NodeId,
	want TypeId?,
	wantRet TypeId?,
	line i64,
	col i64
):
	rt TypeId? = none
	body = nodes[e].kids[0]
	c.currentRet = wantRet
	bodyT = c.checkExpr(body, wantRet)
	if want == none and c.tKind(bodyT) == tRef:
		# a lambda's result is a value: a reference is copied out (see checkReturn)
		bodyT = innerOf(tys, bodyT)
		nodes[e].kids[0] = c.coerceTo(body, bodyT)
	rt = bodyT
	if want != none and c.tKind(wantRet) == tUnit:
		rt = tyUnit
	elif wantRet is wr and not isAssignable(tys, bodyT, wr):
		errorAt(
			c,
			line,
			col,
			compileError("LambdaReturnType", ["{c.showTy(bodyT)}", "{c.showTy(wr)}"])
		)
	elif wantRet is wr:
		nodes[e].kids[0] = c.coerceTo(body, wr)
		rt = wr
	else:
		rt = c.heldType(bodyT)   # a lambda's result holds a range's base, laid out as the range
	rt

# A call through a function value: f(args) where f is a variable, field, element or expression of fn type.
fn checkClosureCall(mut c Checker, e NodeId, ft TypeId) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	nodes[e].flags |= flagClosure
	# the parameter types are read from ft at each use: checking an argument may add types
	nparams = tys[ft].params.len
	nargs = c.argCount(e)
	if nargs != nparams:
		errorAt(
			c,
			line,
			col,
			compileError("FunctionValueArity", ["{c.showTy(ft)}", "{nparams}", "{nargs}"])
		)
	n = nargs
	if nparams < n:
		n = nparams
	for i in 0..n:
		pt = tys[ft].params[i]
		at = c.narrowArg(e, i, c.checkExpr(c.argAt(e, i), pt), pt)
		if not isAssignable(tys, at, pt) and not c.retypeFlex(c.argAt(e, i), pt):
			c.errorAt(
				line,
				col,
				compileError(
					"FunctionValueArgument",
					["{i + 1}", "{c.showTy(pt)}", "{c.showTy(at)}"]
				)
			)
		c.setArg(e, i, c.coerceTo(c.argAt(e, i), pt))
	res = retOf(tys, ft)
	c.typed(e, res)

# True when an integer literal's text lies within i64.
fn intLiteralFitsI32(text str):
	match i64.parse(text):
		v: return v >= -2_147_483_648 and v <= 2_147_483_647
		none: return false

# A list literal of integer literals without an expected type: i64 unless one of them needs i64.
fn literalListNeedsI64(c Checker, elems NodeId[]):
	wide = false
	for el in elems:
		k = nodes[el].kind
		lit = el
		if k == nUnary and nodes[el].ival == unNeg:
			lit = nodes[el].kids[0]
		if nodes[lit].kind != nInt: return false
		if lit != el and not intLiteralFitsI32("-{nodes[lit].text}"):
			wide = true
		if lit == el and not intLiteralFitsI32(nodes[lit].text):
			wide = true
	wide

fn adoptNumeric(c Checker, expected TypeId?, kind i64):
	want = expected
	if c.tKind(want) == tOption:
		want = innerOf(tys, want)
	if c.tKind(want) == tResult:
		want = innerOf(tys, want)
	if c.tKind(want) == kind: return want
	if c.standInIndex(want) >= 0 and c.tKind(want) in [tInt, tFloat]:
		return want   # a literal as a T of the bound Num, whichever number its instances give
	none

# Types an expression. A reference where the context expects its value (and only then) is
# dereferenced here, so every consumer sees the value type.
# xs[lo..hi], xs[..hi], xs[lo..] (hi the length, the parser's indexNode), xs[lo..=hi]: the slice
# xs.slice(lo, hi), of a list or a str, checked as that call
fn checkSliceIndex(mut c Checker, e NodeId, expected TypeId?):
	line = nodes[e].line
	col = nodes[e].col
	base = nodes[e].kids[0]
	r = nodes[e].kids[1]
	callee = newNode(nodes, nField, line, col, text = "slice", kids = [base])
	nodes[e].kind = nCall
	nodes[e].kids = [callee, nodes[r].kids[0], nodes[r].kids[1]]
	nodes[e].flags |= flagInternal
	t = c.checkExpr(e, expected)
	call = e   # (under the reference or the copy a place asked for)
	while nodes[call].kind in [nUnary, nDeref] and nodes[call].kids.len == 1:
		call = nodes[call].kids[0]
	if nodes[call].kind == nCall and c.isSlice(call):
		n = nodes[call].kids.len
		c.proveSliceByLength(
			call,
			c.sliceList(call),
			nodes[call].kids[n - 2],
			nodes[call].kids[n - 1]
		)
	t

fn checkExpr(mut c Checker, e NodeId, expected TypeId?):
	walked = c.seqOk == e
	c.seqOk = none
	t = c.checkExprRaw(e, expected)
	if nodes[e].hasFlag(flagBaseView):
		t = c.baseView(e, t)
	if isDefined(tys, expected) and expected is defined and
		nodes[e].kind in [nArray, nMapLit, nStr, nInterp, nBool] and
		isSameType(tys, t, tys[defined].under):
		t = c.typed(e, defined)   # a literal where a defined type is expected is one, as a number's is
	if c.tKind(t) == tSeq:
		c.checkWalk(e, walked)
	if nodes[e].hasFlag(flagAutoCopy) and (c.tKind(t) == tRef or c.isOptionOfRef(t)):
		# the ownership analysis asked for a copy of the referenced value
		c.derefNode(e)
		nodes[e].flags |= flagAutoCopy
		return typeOf(nodes, e)
	if expected is expected and c.tKind(t) == tRef and c.tKind(expected) != tRef and
		c.tKind(expected) != tError and
		isAssignable(tys, innerOf(tys, t), expected):
		c.derefNode(e)
		return typeOf(nodes, e)
	if c.lendsPlace(e, t, expected):
		# a place where a read reference is asked for: it is lent (`ref` need not be written)
		c.refNode(e)
		nodes[e].flags = flagAutoRef
		return typeOf(nodes, e)
	t

# A Seq is walked where it is made, once: a for's collection or a step's receiver (seqOk), never
# stored, passed, returned or indexed. The generator's body is inlined into the loop that walks
# it, so a generator cannot walk itself.
fn checkWalk(mut c Checker, e NodeId, walked bool):
	line = nodes[e].line
	col = nodes[e].col
	if not walked:
		c.errorAt(line, col, compileError("SeqWalkedWhereMade", ["{seqSteps.join(", ")}"]))
		return
	gen = c.generatorOf(e)
	if gen is gen and gen == c.curFn:
		c.errorAt(line, col, compileError("GeneratorRecursion", ["{nodes[gen].text}"]))

# the generator a call that gives a Seq calls (a function, or a method of its receiver's
# type), or none (a step: filter, map)
pub fn generatorOf(c Checker, e NodeId) NodeId?:
	if nodes[e].kind != nCall: return none
	callee = nodes[e].kids[0]
	if nodes[callee].kind == nIdent: return c.findFunc(nodes[callee].text)
	if nodes[callee].kind != nField or nodes[callee].kids.len != 1: return none
	rt = typeOf(nodes, nodes[callee].kids[0])
	if tys[rt].kind == tRef:
		rt = innerOf(tys, rt)
	if tys[rt].kind != tStruct and tys[rt].kind != tEnum:
		return none   # a module's function: its name says it
	c.findMethod(tys[rt].name, nodes[callee].text)

# whether e, of type t, is a variable, field or element of the type a read reference expected
# (`ref T` or `ref T?`) points to
fn lendsPlace(mut c Checker, e NodeId, t TypeId?, expected TypeId?):
	if t == none or c.tKind(t) == tRef or c.tKind(t) == tError: return false
	expectedT = expected ?? return false
	want = innerOf(tys, expectedT) if c.tKind(expectedT) == tOption else expectedT
	if c.tKind(want) != tRef or tys[want].bits == 1 or not isSameType(tys, tys[want].inner, t):
		return false
	k = nodes[e].kind
	if k != nIdent and k != nField and k != nIndex and k != nDeref: return false
	c.lvalueRoot(e) >= 0 or c.storedConstRoot(e)

fn checkExprRaw(mut c Checker, e NodeId, expected TypeId?) TypeId:
	if expected is expected and c.tKind(expected) == tFn and tys[expected].params.len == 1:
		# a function of one value: `it`, `.hp` in the expression make it one (placeholder.zap)
		c.itLambda(e)
		if nodes[e].kind == nLambda:
			t = c.checkLambda(e, expected)
			c.noteItForm(e, tys[expected].params[0])
			return t
	k = nodes[e].kind
	line = nodes[e].line
	col = nodes[e].col
	if k in [nReturn, nBreak, nContinue]:
		c.checkStmt(e)   # `?? return`: it leaves (stops says where it fits)
		return c.typed(e, tyUnit)
	if nodes[e].hasFlag(flagAutoRef): return c.checkExprRawAutoRef(e, expected)
	if k == nCall and nodes[e].hasFlag(flagAutoWiden): return c.checkExprRawAutoWiden(e, expected)
	if k == nInt and c.subst.names.isEmpty and
		c.exactFloatLiteral(e, c.adoptNumeric(expected, tFloat)):
		# an integer where a float is wanted is that float, when the float holds it exactly (a
		# generic's literals, shared by its instances, take each one's type their own way)
		nodes[e].kind = nFloat
		return c.typed(e, c.adoptNumeric(expected, tFloat) ?? tyFloat(64))
	if k == nInt: return c.checkExprRawInt(e, expected)
	if k == nFloat:
		t = c.adoptNumeric(expected, tFloat) ?? tyFloat(32 if c.gpuCode else 64)
		c.requireBound(expected, "Num", "a number literal", nodes[e].line, nodes[e].col)
		return c.typed(e, t)
	if k == nStr:
		if c.isReadRefStr(expected) and expected is lent:
			return c.typed(e, lent)   # a literal lives in the program's data: it may be lent
		return c.typed(e, tyStr)
	if k == nBool: return c.typed(e, tyBool)
	if k == nNone:
		if c.tKind(expected) == tOption and expected is optional: return c.typed(e, optional)
		return c.typed(e, tyOption(tys, none))
	if k == nInterp: return c.checkExprRawInterp(e)
	if k == nNamedArg: return c.checkExprRawNamedArg(e, line, col)
	if k == nIdent and c.tableElementCall(e, e, "$get"): return c.checkExpr(e, expected)
	if k == nIdent: return c.checkExprRawIdent(e, expected, line, col)
	if k == nBinary:
		t = c.checkBinary(e, expected)
		c.proveSumByLength(e)
		c.noteKnownValue(e)
		return t
	if k == nUnary: return c.checkExprRawUnary(e, expected, line, col)
	if k == nCall and c.isMarkupValue(e): return c.checkMarkupValue(e, expected)
	if k == nCall:
		c.liveGet(e)
		return c.checkCall(e, expected)
	if k == nField: return c.checkField(e, expected)
	if k == nStructLit: return c.checkExprRawStructLit(e, expected)
	if k == nMatch: return c.checkExprRawMatch(e, expected, line, col)
	if k == nTry: return c.checkExprRawTry(e, line, col)
	if k == nIndex and nodes[e].hasFlag(flagComma):
		if c.checkCommaIndex(e, expected) is cell: return cell
	if k == nIndex and nodes[nodes[e].kids[1]].kind == nRange: return c.checkSliceIndex(e, expected)
	if k == nIndex and c.tableElementCall(e, e, "$get"): return c.checkExpr(e, expected)
	if k == nIndex: return c.checkExprRawIndex(e, expected, line, col)
	if k == nDeref:
		# inserted by the checker; the reference checked again with the round
		kt = c.checkExpr(nodes[e].kids[0], none)
		nodes[e].ty = c.derefType(kt)
		return typeOf(nodes, e)
	if k == nSome: return c.checkExprRawSome(e, expected)
	if k == nMapLit: return c.checkExprRawMapLit(e, expected, line, col)
	if k == nRange: return c.checkExprRawRange(e, line, col)
	if k == nArray and c.tKind(expected) == tArray and expected is arrayT:
		return c.checkFixedArrayLit(e, arrayT)
	if k == nArray and nodes[e].kids.isEmpty and c.isTable(expected) and expected is tableT:
		return c.emptyTable(e, tableT, expected)
	if k == nArray and c.isTable(expected) and expected is tableT: return c.tableOfList(e, tableT)
	if k == nArray and c.tKind(expected) == tOption and expected is optT and
		tys[optT].inner != none and
		c.tKind(tys[optT].inner) == tArray:
		return c.checkFixedArrayLit(e, innerOf(tys, expected))   # wrapped where it is used
	if k == nArray: return c.checkExprRawArray(e, expected, line, col)
	if k == nLambda: return c.checkExprRawLambda(e, expected)
	c.typed(e, tyError)

fn checkExprRawAutoRef(mut c Checker, e NodeId, expected TypeId?) TypeId:
	# a reference or dereference inserted when this expression was checked before (another
	# instance of a generic body, whose types may need none): the operand takes its node back
	copied = nodes[e].hasFlag(flagAutoCopy)
	nodes[e] = nodes[nodes[e].kids[0]].copy()
	if copied:
		nodes[e].flags |= flagAutoCopy   # asked by the ownership analysis, kept for each check
	c.checkExprRaw(e, expected)

fn checkExprRawAutoWiden(mut c Checker, e NodeId, expected TypeId?) TypeId:
	# a widening inserted when this expression was checked before (another instance of a
	# generic body): the operand takes its node back and is widened again if this context
	# needs it, so a literal adopts the type of every instance
	inner = nodes[nodes[e].kids[0]].kids[0]
	nodes[e] = nodes[inner].copy()
	c.checkExprRaw(e, expected)

fn checkExprRawInt(mut c Checker, e NodeId, expected TypeId?):
	# 'a' alone is a byte; the integer of the language: 64 bits (the GPU's 32)
	plain = tyInt(8, false) if nodes[e].hasFlag(flagByte) else tyInt(32 if c.gpuCode else 64, true)
	t = c.adoptNumeric(expected, tInt) ?? plain
	c.requireBound(expected, "Num", "a number literal", nodes[e].line, nodes[e].col)
	nodes[e].ty = t
	c.checkIntLiteralRange(e)
	t

fn checkExprRawInterp(mut c Checker, e NodeId) TypeId:
	for i in 0..nodes[e].kids.len:
		part = nodes[e].kids[i]
		pt = c.derefIfRef(part, c.checkExpr(part, none))
		if nodes[part].kind == nStr: continue
		if nodes[e].hasFlag(flagShownIfAny) and
			(not c.isPrintable(pt) or not c.hasBound(pt, "Show")):
			# an expect's report: the part shows that it has no text
			blank = newNode(nodes, nStr, nodes[part].line, nodes[part].col, text = "(no text)")
			c.typed(blank, tyStr)
			nodes[e].kids[i] = blank
			continue
		c.noteFormat(pt)
		c.requireBound(pt, "Show", "interpolation", nodes[part].line, nodes[part].col)
		if not c.isPrintable(pt) and c.tKind(pt) != tError:
			errorAt(
				c,
				nodes[part].line,
				nodes[part].col,
				compileError("CannotInterpolate", ["{c.showTy(pt)}"])
			)
	c.typed(e, tyStr)

fn checkExprRawNamedArg(mut c Checker, e NodeId, line i64, col i64):
	if nodes[e].text == "..":
		errorAt(
			c,
			line,
			col,
			compileError("BaseOutsideLiteral", [])
		)
	else:
		c.errorAt(line, col, compileError("NamedArgumentMisplaced", ["{nodes[e].text}"]))
	c.checkExpr(nodes[e].kids[0], none)
	tyError

fn checkExprRawIdent(mut c Checker, e NodeId, expected TypeId?, line i64, col i64) TypeId:
	# the name is read from e at each use until e is renamed: the lookups change c
	v = c.lookupVar(nodes[e].text)
	if v < 0 and "#" in nodes[e].text:
		# a copy's name for a field or a module variable a loop unrolled for a register
		# array assigns (see checkLet): the name itself
		written = nodes[e].text.split("#")[0].copy()
		if c.lookupVar(written) >= 0 or
			c.lookupDecl(nConstDecl, "", written, line, col) != none:
			nodes[e].text = written
			v = c.lookupVar(nodes[e].text)
	if v < 0 and c.numberParam(nodes[e].text) is number:
		return c.typed(e, c.numberValue(number, line, col))
	if v < 0 and nodes[e].text == "$len":
		c.errorAt(line, col, compileError("LenOutsideIndex", []))
		return c.typed(e, tyError)
	if v < 0: return c.checkExprRawIdentUnbound(e, expected, line, col)
	c.vars[v].used = true
	t = c.vars[v].ty
	lit = c.vars[v].literal
	nodes[e].origin = lit if lit != none and c.tKind(t) == tInt else none   # its value (ranges.zap)
	if lit is lit and expected is expected and
		not isSameType(tys, rangeBase(tys, t), rangeBase(tys, expected)) and
		(c.tKind(expected) == tInt and c.tKind(t) == tInt or c.tKind(expected) == tFloat):
		# a local bound to numbers alone is its value: it takes the type the place asks for, as
		# a module's number constant does (`steps = 2400.0` beside an f32 is an f32); a float's
		# stays a float beside an integer
		copied = cloneTree(nodes, lit)
		nodes[e] = move nodes[copied]
		nodes[e].line = line
		nodes[e].col = col
		return c.checkExprRaw(e, expected)
	if c.tKind(expected) == tList and expected is listT and tys[listT].inner != none and
		c.tKind(t) == tList:
		c.tellEmptyList(v, tys[listT].inner, tys[listT].inner)   # a `[]` binding given to a place of a list type
	c.typed(e, t)

fn checkExprRawIdentUnbound(mut c Checker, e NodeId, expected TypeId?, line i64, col i64) TypeId:
	cd = c.lookupDecl(nConstDecl, "", nodes[e].text, line, col)
	if cd is cd: return c.checkExprRawIdentConst(e, cd, expected, line, col)
	fd = c.lookupDecl(nFnDecl, "", nodes[e].text, line, col)
	if fd is fd: return c.checkExprRawIdentFnRef(e, fd, line, col)
	if nodes[e].text == argsWord:
		# the program's arguments: the runtime's list, read in place
		nodes[e].kind = nField
		nodes[e].kids = [newNode(nodes, nIdent, line, col, text = runtimeAlias)]
		nodes[e].text = "programArgs"
		return c.checkExpr(e, expected)
	name = nodes[e].text
	if "[" in name and name.endsWith("]"):
		# an element of an immutable array declared without values, read before its let
		c.errorAt(line, col, compileError("ReadBeforeSet", ["{name}"]))
	elif c.gpuCode and c.gpuValueType(name) is given:
		return c.typed(e, given)   # a value the GPU gives (gpucheck.zap)
	elif nodes[e].hasFlag(flagPlaceholder):
		errorAt(
			c,
			line,
			col,
			compileError("NoCallArgument", ["{placeholderForm(name)}"])
		)
	elif name == errorWord:
		c.errorAt(line, col, compileError("ErrorOutsideFallback", ["{name}"]))
	elif c.sourceAt(line, col + name.len, 1) == "." and name[0] >= 'a' and name[0] <= 'z':
		c.errorAt(line, col, unknownModule(name))   # a prefix (spec 8)
	else:
		c.errorAt(line, col, compileError("UnknownVariable", ["{name}"]))
	c.typed(e, tyError)

fn checkExprRawIdentConst(
	mut c Checker,
	e NodeId,
	cd NodeId,
	expected TypeId?,
	line i64,
	col i64
) TypeId:
	nodes[e].text = nodes[cd].text.copy()   # the constant's qualified name
	if nodes[cd].hasFlag(flagMut):
		nodes[e].flags |= flagModuleVar
	t = c.constTypeOf(cd)
	nodes[e].origin = nodes[cd].kids[0] if not nodes[cd].hasFlag(flagMut) and c.tKind(t) == tInt and   # its value (ranges.zap)
		c.numericLiteralConstant(cd)
		else none
	if expected is expected and
		not isSameType(tys, rangeBase(tys, t), rangeBase(tys, expected)) and
		c.numericLiteralConstant(cd) and
		(c.tKind(expected) == tInt or c.tKind(expected) == tFloat):
		# a number constant written without a type is its literal: it takes the type
		# the place asks for, as the literal would (one that does not fit is reported)
		lit = cloneTree(nodes, nodes[cd].kids[0])
		nodes[e] = move nodes[lit]
		nodes[e].line = line
		nodes[e].col = col
		return c.checkExprRaw(e, expected)
	c.typed(e, t)

fn checkExprRawIdentFnRef(mut c Checker, e NodeId, fd NodeId, line i64, col i64) TypeId:
	# a top-level function used as a value
	if not nodes[fd].names.isEmpty:
		c.errorAt(line, col, compileError("GenericAsValue", ["{nodes[fd].text}"]))
	ps = []
	for ai in 0..c.nodes[fd].kids.len:
		p = nodes[fd].kids[ai]
		if nodes[p].ival == modeMut:
			errorAt(
				c,
				line,
				col,
				compileError("MutParameterAsValue", ["{nodes[fd].text}"])
			)
		ps.push(c.resolveType(nodes[p].types[0]))
	nodes[e].text = nodes[fd].text.copy()   # the function's qualified name
	nodes[e].flags |= flagFnRef
	ret = c.fnRetType(fd)
	t = tyFn(tys, ps, ret)
	c.typed(e, t)

fn checkExprRawUnary(mut c Checker, e NodeId, expected TypeId?, line i64, col i64) TypeId:
	op = nodes[e].ival
	operand = nodes[e].kids[0]
	if op == unNeg and nodes[operand].kind == nInt and not nodes[operand].text.startsWith("-"):
		# fold `-literal` into one literal so the range check sees the sign (-2147483648 is a valid i64)
		nodes[e].kind = nInt
		nodes[e].text = "-{nodes[operand].text}"
		nodes[e].kids = []
		return c.checkExpr(e, expected)
	if op == unOut:
		errorAt(
			c,
			line,
			col,
			compileError("OutOutsideExtern", ["{nodes[operand].text}"])
		)
		return c.typed(e, tyError)
	if op == unMove and c.tableElementCall(e, operand, "$take"): return c.checkExpr(e, expected)
	if op == unMove: return c.checkExprRawUnaryMove(e, operand, expected, line, col)
	if op == unRef or op == unMutRef: return c.checkExprRawUnaryRef(e, operand, op, line, col)
	if op == unBnot:
		want TypeId? = c.baseExpected(expected) if c.tKind(expected) == tInt else none
		t = c.checkExpr(operand, want)
		if c.tKind(t) != tInt and c.tKind(t) != tError:
			c.errorAt(line, col, compileError("ComplementNeedsInteger", ["{c.showTy(t)}"]))
		return c.typed(e, rangeBase(tys, t))
	if op == unNot:
		t = c.checkExpr(operand, tyBool)
		if c.tKind(t) != tBool and c.tKind(t) != tError:
			c.errorAt(line, col, compileError("NotNeedsBool", ["{c.showTy(t)}"]))
		return c.typed(e, tyBool)
	c.checkExprRawUnaryNeg(e, operand, expected, line, col)

fn checkExprRawUnaryMove(
	mut c Checker,
	e NodeId,
	operand NodeId,
	expected TypeId?,
	line i64,
	col i64
) TypeId:
	ok = nodes[operand].kind
	mutVar = false
	if ok == nIdent:
		v = c.lookupVar(nodes[operand].text)
		mutVar = v >= 0 and c.tKind(c.vars[v].ty) != tFn and
			(c.vars[v].isField and c.receiverChange(v, line, col) or c.vars[v].isMut)
	if ok in [nField, nIndex, nDeref] or mutVar:
		# `move place`: the value leaves its mutable variable, field or element, which keeps
		# the empty value of its type (the take the backend knows); an immutable variable
		# is moved whole and is gone
		callee = newNode(nodes, nField, line, col, text = "take", kids = [operand])
		nodes[e].kind = nCall
		nodes[e].ival = 0
		nodes[e].kids = [callee]
		nodes[e].flags |= flagInternal
		return c.checkExpr(e, expected)
	t = c.checkExpr(operand, expected)
	if ok != nIdent:
		c.errorAt(line, col, compileError("MoveNeedsPlace", []))
	c.typed(e, t)

fn checkExprRawUnaryRef(mut c Checker, e NodeId, operand NodeId, op i64, line i64, col i64) TypeId:
	# a reference made by the compiler (flagAlias) may point to a temporary that lives
	# to the end of the statement; its operand is re-checked against the known type
	made = nodes[e].hasFlag(flagAlias)
	want TypeId? = none
	if made and nodes[e].ty != none and c.tKind(typeOf(nodes, e)) == tRef:
		want = innerOf(tys, typeOf(nodes, e))
	t = c.checkExpr(operand, want)
	ok = nodes[operand].kind
	if made:
		# nothing to require
		pass
	elif (ok != nIdent and ok != nField and ok != nIndex and ok != nDeref) or
		(c.lvalueRoot(operand) < 0 and not (op == unRef and c.storedConstRoot(operand))):
		c.errorAt(line, col, compileError("RefNeedsPlace", []))
	elif op == unMutRef:
		c.requireMutRoot(operand, line, col, "mut ref")
	if c.tKind(t) == tRef and op == unMutRef and c.subst.names.isEmpty:
		c.errorAt(line, col, compileError("AlreadyReference", []))
		return c.typed(e, t)
	if c.tKind(t) == tRef:
		# a place that holds a reference (an element of a (ref str)[], a T that is a
		# reference): the reference it holds, which the backend reads from it
		return c.typed(e, t)
	res = tyRef(tys, t, op == unMutRef)
	c.typed(e, res)

fn checkExprRawUnaryNeg(
	mut c Checker,
	e NodeId,
	operand NodeId,
	expected TypeId?,
	line i64,
	col i64
) TypeId:
	t = c.checkExpr(operand, c.baseExpected(expected))
	if c.isTensorType(t): return c.checkTensorNeg(e, operand, expected)
	if c.uniformNumberField(t) != none:
		# -v of a struct of numbers is -1 * v: every field negated (-0.0 included)
		field = c.uniformNumberField(t)
		minusOne = newNode(
			nodes,
			nFloat if c.tKind(field) == tFloat else nInt,
			line,
			col,
			text = "-1"
		)
		nodes[minusOne].ty = field
		nodes[e].kind = nBinary
		nodes[e].ival = binMul
		nodes[e].kids = [minusOne, operand]
		c.noteDerive(t, deriveArith)
		return c.typed(e, t)
	c.requireBound(t, "Num", "unary '-'", line, col)
	if not typeIsNumeric(tys, t) and c.tKind(t) != tError:
		c.errorAt(line, col, compileError("NegateNeedsNumber", ["{c.showTy(t)}"]))
	if c.carries(t, t, binSub):
		base = rangeBase(tys, t)
		return c.typed(e, spanType(tys, c.rangeTypes, base, typeSpanIn(tys, t, base).negSpan()))
	c.typed(e, rangeBase(tys, t))

fn checkExprRawStructLit(mut c Checker, e NodeId, expected TypeId?):
	want = expected
	if c.tKind(expected) == tBox and expected is boxT and tys[boxT].counted:
		want = innerOf(tys, boxT)
	if not c.placeTuple(e, want): return tyError
	st = c.checkStructLit(e, want)
	if c.tKind(st) == tStruct and nodes[declOf(tys, st)].hasFlag(flagShared):
		return c.shareLiteral(e, st)
	st

fn checkExprRawMatch(mut c Checker, e NodeId, expected TypeId?, line i64, col i64) TypeId:
	isStmt = c.matchStmt   # the scrutinee may contain nested (expression) matches
	c.matchStmt = false
	scrutT = c.derefIfRef(nodes[e].kids[0], c.checkExpr(nodes[e].kids[0], none))
	c.matchStmt = isStmt
	sk = c.tKind(scrutT)
	if c.isMatchable(scrutT):
		t = c.checkMatchArms(e, scrutT, expected)
		c.coalesceForm(e, scrutT, isStmt)
		return t
	c.matchStmt = false
	if sk != tError:
		c.errorAt(line, col, compileError("CannotMatch", ["{c.showTy(scrutT)}"]))
	c.typed(e, tyError)

fn checkExprRawTry(mut c Checker, e NodeId, line i64, col i64) TypeId:
	t = c.checkExpr(nodes[e].kids[0], none)
	tk = c.tKind(t)
	res = tyError
	if tk == tOption and (c.findingResult() or c.tKind(c.currentRet) == tOption) and
		nodes[nodes[e].kids[0]].kind not in [nIdent, nField, nIndex, nDeref, nUnary]:
		# a value made here (a call's): `x ?? return none`, and its code (a place's is lent)
		ret = newNode(nodes, nReturn, line, col, kids = [newNode(nodes, nNone, line, col)])
		nodes[e].kind = nBinary
		nodes[e].ival = binCoalesce
		nodes[e].kids.push(ret)
		return c.checkExpr(e, none)
	if tk == tOption or tk == tResult:
		if c.findingResult():
			c.openTries.push(e)   # the result found decides (settleOpenTries)
		else:
			c.checkTryResult(e, t, c.currentRet ?? tyUnit)
		res = (tys[t].inner ?? tyError) if tk == tOption else innerOf(tys, t)
	elif tk != tError:
		c.errorAt(line, col, compileError("TryNeedsFallible", ["{c.showTy(t)}"]))
	c.typed(e, res)

# try e of a value of type t in a function whose result is ret: an optional's passes none up to an
# optional result, a result's its error to a result of that error
fn checkTryResult(mut c Checker, e NodeId, t TypeId, ret TypeId):
	line = nodes[e].line
	col = nodes[e].col
	if c.tKind(t) == tOption and c.tKind(ret) != tOption:
		c.errorAt(line, col, compileError("TryNeedsOptionalResult", []))
	elif c.tKind(t) == tResult and
		(c.tKind(ret) != tResult or not isSameType(tys, errOf(tys, ret), tys[t].err)):
		c.errorAt(line, col, compileError("TryNeedsResult", []))

fn checkExprRawIndex(mut c Checker, e NodeId, expected TypeId?, line i64, col i64) TypeId:
	# a list literal of numbers indexed where a number is asked for: its numbers are of that type
	wantList TypeId? = none
	base = nodes[e].kids[0]
	if nodes[base].kind == nArray and
		(c.tKind(expected) == tInt or c.tKind(expected) == tFloat) and
		nodes[base].kids.all(c.isNumberExpr(it)):
		wantList = tyList(tys, expected)
	ot = c.derefIfRef(nodes[e].kids[0], c.checkExpr(nodes[e].kids[0], wantList))
	if c.gridKind(ot) > 0:
		c.errorAt(line, col, compileError("GridCellSpelling", []))
		return c.typed(e, tyError)
	if c.tKind(ot) == tMap or c.isIndexable(ot):
		# m[k], pool[h]: the value the index method lends, read where it is (an assignment
		# or a change through it makes it indexMut: lendForChange)
		lend = "indexLive" if c.isLiveHandle(nodes[e].kids[0], nodes[e].kids[1]) else "index"
		callee = newNode(nodes, nField, line, col, text = lend, kids = [nodes[e].kids[0]])
		call = newNode(nodes, nCall, line, col, kids = [callee, nodes[e].kids[1]])
		nodes[e].kind = nDeref
		nodes[e].kids = [call]
		nodes[e].flags |= flagInternal
		return c.checkExpr(e, expected)
	indexT = c.derefIfRef(nodes[e].kids[1], c.checkExpr(nodes[e].kids[1], tyInt(64, true)))
	if c.tKind(indexT) != tInt and c.tKind(indexT) != tError:
		c.errorAt(line, col, compileError("IndexNotInteger", ["{c.showTy(indexT)}"]))
	c.noteWidenedToAnyInt(nodes[e].kids[1])
	ok = c.tKind(ot)
	if ok == tList or ok == tStr:
		c.proveIndexByLength(e)
	if ok == tList:
		c.giveUpEmptyList(nodes[e].kids[0])
		if tys[ot].inner == none: return c.typed(e, c.untoldList(nodes[e].kids[0], line, col))
		return c.typed(e, c.innerOrError(ot))
	if ok == tArray:
		idx = nodes[e].kids[1]
		n = tys[ot].bits
		if nodes[idx].kind == nInt and n >= 0:
			iv = i64.parse(nodes[idx].text) ?? 0
			if iv < 0 or iv >= n:
				c.errorAt(line, col, compileError("IndexOutside", ["{iv}", "{c.showTy(ot)}"]))
		return c.typed(e, innerOf(tys, ot))
	if ok == tStr:
		nodes[e].ty = tyInt(8, false)   # the byte at i (a str is bytes, like Go)
		return typeOf(nodes, e)
	field = c.uniformNumberField(ot)
	if ok == tStruct and field is field:
		# a struct of one number type is indexed by its fields' order: v[0] is v.x of a Vec3
		idx = nodes[e].kids[1]
		n = nodes[declOf(tys, ot)].kids.len
		if nodes[idx].kind == nInt:
			iv = i64.parse(nodes[idx].text) ?? 0
			if iv < 0 or iv >= n:
				errorAt(
					c,
					line,
					col,
					compileError(
						"FieldIndexOutside",
						["{iv}", "{c.showTy(ot)}", "{n}", "{n - 1}"]
					)
				)
		return c.typed(e, field)
	if ok != tError:
		c.errorAt(line, col, compileError("CannotIndex", ["{c.showTy(ot)}"]))
	c.typed(e, tyError)

fn checkExprRawSome(mut c Checker, e NodeId, expected TypeId?) TypeId:
	# made by coerceTo; checked again for another instance of a generic, it wraps that
	# instance's type, the one expected here
	t = typeOf(nodes, e)
	if c.tKind(expected) == c.tKind(t) and (c.tKind(t) == tOption or c.tKind(t) == tResult) and
		expected is wrapped:
		t = wrapped
	kt = c.checkExpr(nodes[e].kids[0], tys[t].inner)
	if c.tKind(t) == tResult:
		nodes[e].ival = 1 if isSameType(tys, kt, tys[t].inner) else 2
	c.typed(e, t)

fn checkExprRawMapLit(mut c Checker, e NodeId, expected TypeId?, line i64, col i64) TypeId:
	# the keys (kids) and values (sub) are read from e at each use: checking changes c
	nkeys = nodes[e].kids.len
	wantK TypeId? = none
	wantV TypeId? = none
	if c.tKind(expected) == tMap and expected is mapT:
		wantK = tys[mapT].inner
		wantV = tys[mapT].val
	if nkeys == 0:
		if c.tKind(expected) == tMap and expected is mapT: return c.typed(e, mapT)
		errorAt(
			c,
			line,
			col,
			compileError("UntypedEmptyMapLiteral", [])
		)
		return c.typed(e, tyError)
	kt TypeId? = none
	vt TypeId? = none
	for i in 0..nkeys:
		wk = kt
		if wk == none:
			wk = wantK
		wv = vt
		if wv == none:
			wv = wantV
		if wantK == none:
			c.weakExpected = nodes[e].kids[i]   # the first key's type, not the place's
		kk = c.checkExpr(nodes[e].kids[i], wk)
		if wantK == none:
			c.keepConversion(nodes[e].kids[i])
		c.weakExpected = nodes[e].sub[i] if wantV == none else none
		vv = c.checkExpr(nodes[e].sub[i], wv)
		c.weakExpected = none
		if wantV == none:
			c.keepConversion(nodes[e].sub[i])
		if wantV is wantV and not isSameType(tys, vv, wantV) and isAssignable(tys, vv, wantV):
			nodes[e].sub[i] = c.coerceTo(nodes[e].sub[i], wantV)   # i64 into i64?, as a list's elements
			vv = wantV
		if kt == none:
			key = c.heldType(kk)
			kt = key
			c.requireBound(key, "Hash", "a map key", line, col)
			if not c.isHashKey(key):
				c.errorAt(line, col, compileError("MapKeyType", ["{c.showTy(key)}"]))
			else:
				c.noteHashKey(key)
		if c.heldType(kk) == kt and not isSameType(tys, kk, kt):
			nodes[e].kids[i] = c.coerceTo(nodes[e].kids[i], kt)   # a range: its base
		elif not isSameType(tys, kk, kt):
			errorAt(
				c,
				line,
				col,
				compileError("MapKeysDiffer", ["{c.showTy(kt)}", "{c.showTy(kk)}"])
			)
		if vt == none:
			vt = c.heldType(vv)
		if c.heldType(vv) == vt and not isSameType(tys, vv, vt):
			nodes[e].sub[i] = c.coerceTo(nodes[e].sub[i], vt)   # a range: its base
		elif not isSameType(tys, vv, vt):
			errorAt(
				c,
				line,
				col,
				compileError("MapValuesDiffer", ["{c.showTy(vt)}", "{c.showTy(vv)}"])
			)
	res = tyMap(tys, kt ?? tyError, vt ?? tyError)   # (keys given: both told)
	c.typed(e, res)

fn checkExprRawRange(mut c Checker, e NodeId, line i64, col i64) TypeId:
	errorAt(
		c,
		line,
		col,
		compileError("RangeOutsideFor", [])
	)
	for b in nodes[e].kids.copy():
		c.checkExpr(b, none)
	c.typed(e, tyError)

fn checkExprRawArray(mut c Checker, e NodeId, expected TypeId?, line i64, col i64) TypeId:
	# the elements are read from e at each use: checking changes c
	nelems = nodes[e].kids.len
	wantElem TypeId? = none
	if c.tKind(expected) == tList and expected is listT:
		wantElem = tys[listT].inner
	if nelems == 0:
		if c.tKind(expected) == tList and expected is listT: return c.typed(e, listT)   # a `[]` binding's own type: its element type is still to be told
		errorAt(
			c,
			line,
			col,
			compileError("UntypedEmptyListLiteral", [])
		)
		return c.typed(e, tyError)
	placed = wantElem   # the element type the place gives, which a proven value narrows to
	if wantElem == none and c.literalListNeedsI64(nodes[e].kids):
		wantElem = tyInt(64, true)
	e0 = c.narrowElement(e, 0, c.checkExpr(nodes[e].kids[0], wantElem), placed)
	if wantElem == none:
		c.keepConversion(nodes[e].kids[0])
	# the place asks for an element type the elements are assignable to (i64 into i64?): each is
	# coerced to it; with no place, a borrow of plain data (a loop's element) is copied in
	held = wantElem ?? c.heldType(c.plainElement(e0))
	widened = (wantElem != none or held != e0) and isAssignable(tys, e0, held)
	elemT = e0
	if widened:
		elemT = held
		nodes[e].kids[0] = c.coerceTo(nodes[e].kids[0], elemT)
	for i in 1..nelems:
		if wantElem == none:
			c.weakExpected = nodes[e].kids[i]   # the first element's type, not the place's
		et = c.narrowElement(e, i, c.checkExpr(nodes[e].kids[i], elemT), placed)
		c.weakExpected = none
		if wantElem == none:
			c.keepConversion(nodes[e].kids[i])
		if (widened or isSameType(tys, rangeBase(tys, et), elemT)) and
			isAssignable(tys, et, elemT):
			nodes[e].kids[i] = c.coerceTo(nodes[e].kids[i], elemT)
		elif not isSameType(tys, et, elemT):
			errorAt(
				c,
				line,
				col,
				compileError("ListElementsDiffer", ["{c.showTy(elemT)}", "{c.showTy(et)}"])
			)
	res = tyList(tys, elemT)
	c.typed(e, res)

# element i of the list literal e, of type et, where the place gives the element type want:
# narrowed to it where proven inside (narrowProven, noted for zap fmt as narrowArg notes): its type
fn narrowElement(mut c Checker, e NodeId, i i64, et TypeId, maybeWant TypeId?):
	want = maybeWant ?? return et
	x = nodes[e].kids[i]
	c.noteNarrowedAt(x, want)
	if isAssignable(tys, et, want) or not c.narrowsProven(x, want): return et
	nodes[e].kids[i] = c.narrowProven(x, want)
	typeOf(nodes, nodes[e].kids[i])

fn checkExprRawLambda(mut c Checker, e NodeId, expected TypeId?):
	hidden = c.hideLiveHandles()
	lengths = c.hideLengths(true)
	t = c.checkLambda(e, expected)
	c.liveHandles = hidden
	c.lenFacts = lengths
	t

# ---------- fixed arrays: T[N] ----------
