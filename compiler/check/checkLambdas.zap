# The checking of lambdas and closures: a lambda as a closure value, its block and its tail, and a
# call through a function value (checkExprWalk.zap walks the expressions that hold them).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# A lambda outside a pipeline is a closure value of type fn(P...) R. Parameter types come from
# annotations or from the expected fn type; outer variables it reads are captured by value.
fn checkLambda(mut c Checker, e NodeId, expected TypeId?) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	# the parameter names are read from e at each use: checking the body changes c
	n = nodes[e].names(kidIds).len
	want TypeId? = none
	if c.tKind(expected) == tFn and expected is fnT:
		if tys[fnT].params.len == n:
			want = fnT
		else:
			c.errorAt(line, col, compileError("LambdaArity", ["{n}", "{c.showTy(fnT)}"]))
	ps = []
	ok = true
	for i in 0..n:
		te = nodes[e].types(kidIds)[i]
		pt TypeId? = none
		if nodes[te].kind != nTyAbsent:
			pt = c.resolveType(te)
		elif want is want:
			pt = tys[want].params[i]
		if pt == none:
			c.errorAt(
				line,
				col,
				compileError("CannotInferLambdaParameter", ["{nodes[e].names(kidIds)[i]}"])
			)
			ok = false
		ps.push(pt ?? tyError)
	c.lambdaCount += 1
	nodes[e].ival = i32(c.lambdaCount)
	c.enterScope()
	c.lamStack.push(e)
	c.lamBounds.push(c.scopeStarts.len - 1)
	for i in 0..n:
		c.addVar(nodes[e].names(kidIds)[i], ps[i], false, true, line, col)
	saveRet = c.currentRet
	saveLoop = c.loopDepth
	saveImpl = c.implType
	c.loopDepth = 0
	rt TypeId? = none
	wantRet TypeId? = match want:
		w: tys[w].ret
		none: none
	if not nodes[e].sub(kidIds).isEmpty:
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
	blk = nodes[e].sub(kidIds)[0]
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
	c.valueTail = nodes[blk].kids(kidIds)[
		nodes[blk].kids(kidIds).len - 1
	] if not nodes[blk].kids(kidIds).isEmpty
		else none
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
	kids = nodes[blk].kids(kidIds)
	if not kids.isEmpty and nodes[kids[len - 1]].kind == nExprStmt:
		last = kids[len - 1]
		ex = nodes[last].kids(kidIds)[0]
		et = typeOf(nodes, ex)
		if want == none and c.tKind(et) == tRef:
			# a lambda's result is a value: a reference is copied out (see checkReturn)
			et = innerOf(tys, et)
			ex = c.coerceTo(ex, et)
			nodes[last].setKid(kidIds, 0, ex)
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
				madeKid = c.coerceTo(ex, wr)
				nodes[last].setKid(kidIds, 0, madeKid)

fn checkLambdaExpr(
	mut c Checker,
	e NodeId,
	want TypeId?,
	wantRet TypeId?,
	line i64,
	col i64
):
	rt TypeId? = none
	body = nodes[e].kids(kidIds)[0]
	c.currentRet = wantRet
	bodyT = c.checkExpr(body, wantRet)
	if want == none and c.tKind(bodyT) == tRef:
		# a lambda's result is a value: a reference is copied out (see checkReturn)
		bodyT = innerOf(tys, bodyT)
		madeKid = c.coerceTo(body, bodyT)
		nodes[e].setKid(kidIds, 0, madeKid)
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
		madeKid = c.coerceTo(body, wr)
		nodes[e].setKid(kidIds, 0, madeKid)
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
