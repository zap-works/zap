# Type checker, part 3: statements, definite termination, function bodies, signatures and the
# program-level driver (checkProgram).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# (the facts of a length about what the body changes forgotten, unless the caller did)
fn checkLoopBody(mut c Checker, b NodeId, forgotten bool = false):
	if not forgotten: c.forgetChangedIndexes(b)   # changed before the body's next turn
	c.loopDepth += 1
	c.checkBlock(b)
	c.loopDepth -= 1

fn isUnfixedOption(c Checker, t TypeId):
	c.tKind(t) == tOption and tys[t].inner == none

fn checkLet(mut c Checker, s NodeId):
	if c.rowLet(s): return
	line = nodes[s].line
	col = nodes[s].col
	# the name is read from the let node at each use: checking changes c (reporting, new nodes)
	isMut = nodes[s].hasFlag(flagMut)
	hasType = not nodes[s].types().isEmpty
	value = nodes[s].kids(kidIds)[0]
	bare = not isMut and not hasType
	existing = -1
	if bare and "#" in nodes[s].text:
		# a local of a loop unrolled for a register array (regarrays.zap): the parser took the
		# name for a new one in each copy, not knowing the fields; a field or a module variable
		# of that name is assigned instead, as in the loop (the copy's reads of it find it too)
		written = nodes[s].text.split("#")[0].copy()
		cd = c.lookupDecl(nConstDecl, "", written, line, col)
		if c.lookupVar(written) >= 0 or isFlagged(nodes, cd, flagMut):
			nodes[s].text = written
	if nodes[s].canAssign() and nodes[s].text != "_":
		existing = c.lookupVar(nodes[s].text)
		if existing < 0 and c.mutModuleVar(nodes[s].text, line, col):
			# `name = value` on a module variable: an assignment, not a new binding
			t = newNode(nodes, kidIds, nIdent, line, col)
			nodes[t].text = move nodes[s].text   # the name moves to the target
			nodes[s].kind = nAssign
			nodes[s].setKids(kidIds, [t, value])
			c.checkStmt(s)
			return
	if existing >= 0:
		c.checkLetReassign(s, existing, value, line, col)
		return
	c.checkLetNew(s, value, isMut, hasType, line, col)

fn checkLetReassign(mut c Checker, s NodeId, existing i64, value0 NodeId, line i64, col i64):
	value = value0
	# reassignment of an existing binding
	et = c.vars[existing].ty
	ek = c.tKind(et)
	if ek == tRef and tys[et].bits == 1 and
		not (nodes[value].kind == nUnary and nodes[value].ival == unMutRef):
		# a `mut ref` binding (a loop's element, an `is mut` name) assigned: its place takes the value
		target = newNode(nodes, kidIds, nIdent, line, col, text = nodes[s].text.copy())
		nodes[s].kind = nAssign
		nodes[s].setKids(kidIds, [target, value])
		c.checkStmt(s)
		return
	mutable = c.receiverChange(existing, line, col) or c.vars[existing].isMut
	if not mutable and nodes[value].kind == nUnary and nodes[value].ival == unMutRef:
		# a mut ref binding lends one place for as long as it is used
		c.errorAt(line, col, compileError("MutRefLendsOnce", ["{nodes[s].text}"]))
	elif not mutable:
		errorAt(
			c,
			line,
			col,
			compileError("AssignImmutable", [nodes[s].text.copy()])
		)
	elif c.isCapturedVar(existing) and ek != tList and ek != tMap:
		c.noteCapturedChange(existing, line, col)
	want TypeId? = none if c.isUnfixedOption(et) else et
	vt = c.checkExpr(value, want)
	if c.tKind(vt) == tList:
		c.tellEmptyList(existing, tys[vt].inner, c.inferredElemType(value, vt))   # a `[]` binding assigned a list
	if c.isUnfixedOption(et) and c.vars[existing].noneInit != none and c.tKind(vt) != tError:
		# `x = none` earlier: this assignment fixes the optional's type, in place, so the reads
		# of x already checked (a loop's test before the assignment) have it too
		if c.tKind(vt) == tOption:
			tys[et].inner = tys[vt].inner
		else:
			tys[et].inner = vt
	cur = c.vars[existing].ty
	c.noteNarrowedAt(value, cur)
	if not isAssignable(tys, vt, cur):
		value = c.narrowProven(value, cur)
		vt = typeOf(nodes, value)
	if not isAssignable(tys, vt, cur):
		errorAt(
			c,
			line,
			col,
			compileError(
				"AssignType",
				[
					"{nodes[s].text}",
					"{c.showTy(cur)}",
					"{c.showTy(vt)}",
					"{c.rangeHint(vt, cur)}"
				]
			)
		)
	madeKid = c.coerceTo(value, cur)
	nodes[s].setKid(kidIds, 0, madeKid)
	return

# (written: the let is marked mutable, an array's zeros or a let the compiler makes; another is
# mutable when what follows changes it)
fn checkLetNew(
	mut c Checker,
	s NodeId,
	value0 NodeId,
	written bool,
	hasType bool,
	line i64,
	col i64
):
	value = value0
	declT TypeId? = none
	if hasType:
		declT = c.resolveType(nodes[s].types()[0])
	emptyList = nodes[value].kind == nArray and nodes[value].kids(kidIds).isEmpty and
		not nodes[value].hasFlag(flagInternal) and nodes[s].text != "_"
	vt TypeId = tyError
	if declT == none and nodes[value].kind == nMapLit and nodes[value].kids(kidIds).isEmpty and
		nodes[s].text != "_":
		c.errorAt(line, col, compileError("UntypedEmptyMap", ["{nodes[s].text}"]))
		vt = c.typed(value, tyError)
	elif emptyList and declT == none:
		vt = c.typed(value, tyList(tys, none))   # the element type: told by the first use (tellEmptyList)
	else:
		vt = c.checkExpr(value, declT)
	isMut = written or c.changedLater(s, declT ?? vt)
	if isMut:
		nodes[s].flags |= flagMut
	bare = not isMut and not hasType
	if isMut and not c.explicitRef(value) and (c.tKind(vt) == tRef or c.isOptionOfRef(vt)):
		if c.copiesFreely(vt):
			# a mutable binding of a referenced plain value: it gets its own copy
			nodes[value].flags |= flagAutoCopy
			vt = c.checkExpr(value, declT)
		else:
			c.errorAt(line, col, compileError("MutBindingOfReference", ["{nodes[s].text}"]))
	c.noteWidenedAt(value, declT, true)
	c.noteNarrowedAt(value, declT)
	if nodes[s].text == "_" and declT == none and nodes[value].kind == nCall and
		c.tKind(vt) != tResult and c.tKind(vt) != tError and not c.makesValueOnly(value):
		c.noteDroppedCall(s)
	if declT is declT and not isAssignable(tys, vt, declT):
		widened = c.fitValue(value, declT)
		if widened != value:
			nodes[s].setKid(kidIds, 0, widened)
			value = widened
			vt = typeOf(nodes, value)
	if declT is declT and not isAssignable(tys, vt, declT):
		errorAt(
			c,
			line,
			col,
			compileError(
				"InitializerType",
				[
					"{nodes[s].text}",
					"{c.showTy(declT)}",
					"{c.showTy(vt)}",
					"{c.rangeHint(vt, declT)}"
				]
			)
		)
	if declT != none:
		madeKid = c.coerceTo(value, declT)
		nodes[s].setKid(kidIds, 0, madeKid)
		c.noteToldType(s, value, declT)
	elif not hasType:
		c.noteArgBinding(s, vt)
	if nodes[s].text != "_" and c.lookupVarCurrent(nodes[s].text) >= 0:
		c.errorAt(line, col, compileError("AlreadyDeclared", ["{nodes[s].text}"]))
	# a mut binding of a range's value holds its base (a defined type's, the defined type)
	vty = declT ?? (c.heldType(vt) if isMut else vt)
	nv = c.addVar(nodes[s].text, vty, isMut, false, line, col)
	c.vars[nv].fromUses = hasType and nodes[nodes[s].types()[0]].hasFlag(flagInternal)
	if emptyList and (declT == none or c.tKind(declT) == tList):
		c.vars[nv].emptyInit = value
		c.vars[nv].emptyInfer = vty if declT == none else tyList(tys, none)   # with a type written, a shadow for zap fmt
		c.vars[nv].emptyLet = s
	if declT == none and nodes[value].kind == nNone:
		c.vars[nv].noneInit = value
	c.noteLengthBinding(nv, value)
	if bare and c.isNumberExpr(value):
		c.vars[nv].literal = value
		# a round checked again finds its uses already written as the value
		c.vars[nv].used = c.round > 0
	if declT == none and c.tKind(vty) == tFloat and tys[vty].bits == 64 and
		(
			isMut and c.isNumberExpr(value) or c.isNumberListIndex(value) or
				c.isNumberChoice(value)
		):
		c.vars[nv].flexLet = s
	if declT == none and isMut and c.isNumberExpr(value) and isSameType(tys, vty, tyInt(64, true)):
		c.vars[nv].flexLet = s   # an integer's: any other integer type it meets

# `for x in xs.parallel() { body }`: the parts of the source run on every processor at once, as
# parallelDo(parallelChunks(), $c => { for x in part($c) { body } }). The body runs on several
# threads, so it may change only what it declares and the elements of a list at an index made
# from the loop's variable (`heights[i] = ...`): two parts never write the same place.
fn checkParallelFor(mut c Checker, s NodeId):
	line = nodes[s].line
	col = nodes[s].col
	locals str[] = [nodes[s].text.copy()]
	made str[] = [nodes[s].text.copy()]
	c.parallelWrites(nodes[s].sub()[0], made, locals)
	part = c.parallelPart(nodes[s].kids(kidIds)[0]) ?? return
	each = newNode(nodes, kidIds, nFor, line, col, text = nodes[s].text.copy(), kids = [part])
	nodes[each].nodePart().sub = [nodes[s].sub()[0]]
	block = newNode(nodes, kidIds, nBlock, line, col, kids = [each])
	lam = newNode(nodes, kidIds, nLambda, line, col)
	nodes[lam].nodePart().names = ["$c"]
	nodes[lam].nodePart().types = [newNode(nodes, kidIds, nTyAbsent, line, col)]
	nodes[lam].nodePart().sub = [block]
	call = newNode(
		nodes,
		kidIds,
		nCall,
		line,
		col,
		kids = [c.internalName("parallelDo", line, col), c.chunksCall(line, col), lam]
	)
	nodes[s].kind = nExprStmt
	nodes[s].setKids(kidIds, [call])
	nodes[s].nodePart().sub = []
	nodes[s].text = ""
	c.checkStmt(s)

# whether e is `src.parallel().map(f)`
fn isParallelMap(c Checker, e NodeId):
	if nodes[e].kind != nCall or nodes[e].kids(kidIds).len != 2: return false
	f = nodes[e].kids(kidIds)[0]
	nodes[f].kind == nField and nodes[f].text == "map" and
		c.isParallelStep(nodes[f].kids(kidIds)[0])

# `for x in src.parallel().map(f) { body }`: the results read in order as the pool makes them,
# the threads going on ahead while the body runs, as
# { $stream = parallelStream(n, $k => ...); for _ in 0..$stream.count { x = $stream.next(); body } }
# (parallelMapCall); the stream gives the rest up when the loop is left early.
fn checkParallelStream(mut c Checker, s NodeId):
	line = nodes[s].line
	col = nodes[s].col
	iter = nodes[s].kids(kidIds)[0]
	call = c.parallelMapCall(
		iter,
		nodes[nodes[iter].kids(kidIds)[0]].kids(kidIds)[0],
		"parallelStream"
	) ??
		return
	name = "$stream{s}"
	made = newNode(nodes, kidIds, nLet, line, col, text = name.copy(), kids = [call])
	nodes[made].flags |= flagMut
	count = newNode(
		nodes,
		kidIds,
		nField,
		line,
		col,
		text = "count",
		kids = [newNode(nodes, kidIds, nIdent, line, col, text = name.copy())]
	)
	next = newNode(
		nodes,
		kidIds,
		nField,
		line,
		col,
		text = "next",
		kids = [newNode(nodes, kidIds, nIdent, line, col, text = name.copy())]
	)
	take = newNode(
		nodes,
		kidIds,
		nLet,
		line,
		col,
		text = nodes[s].text.copy(),
		kids = [newNode(nodes, kidIds, nCall, line, col, kids = [next])]
	)
	body = nodes[s].sub()[0]
	stmts = [take]
	stmts.extend(nodes[body].kids(kidIds))
	nodes[body].setKids(kidIds, stmts)
	each = newNode(
		nodes,
		kidIds,
		nFor,
		line,
		col,
		text = "_",
		kids = [
			newNode(
				nodes,
				kidIds,
				nRange,
				line,
				col,
				kids = [newNode(nodes, kidIds, nInt, line, col, text = "0"), count]
			)
		]
	)
	nodes[each].nodePart().sub = [body]
	nodes[s].kind = nBlock
	nodes[s].setKids(kidIds, [made, each])
	nodes[s].nodePart().sub = []
	nodes[s].text = ""
	c.checkBlock(s)

# The writes of a parallel loop's body checked: a let or an assignment to a name the body did
# not declare, a change of a list's own (push, remove...) outside, and an element written at an
# index made from neither the loop's variable nor a local of the body computed from it (`made`:
# `at = i * 4`), are errors. `locals` and `made` grow with the body's declarations, in order.
fn parallelWrites(mut c Checker, e NodeId, mut made str[], mut locals str[]):
	k = nodes[e].kind
	line = nodes[e].line
	col = nodes[e].col
	if k == nLet:
		name = nodes[e].text.copy()
		if name not in locals and c.lookupVar(name) >= 0:
			c.errorAt(line, col, compileError("ParallelChange", ["{name}"]))
		if not nodes[e].kids(kidIds).isEmpty and
			mentionsAny(nodes, kidIds, nodes[e].kids(kidIds)[0], made):
			made.push(name.copy())
		locals.push(move name)
	elif k == nFor:
		locals.push(nodes[e].text.copy())
	elif k == nLambda:
		for n in nodes[e].names():
			locals.push(n.copy())
	elif k == nAssign:
		target = nodes[e].kids(kidIds)[0]
		root = c.rootName(target).copy()
		if root != "" and root not in locals and not c.indexedBy(target, made):
			c.errorAt(line, col, compileError("ParallelIndex", ["{root}", "{made[0]}"]))
	elif k == nCall:
		callee = nodes[e].kids(kidIds)[0]
		if nodes[callee].kind == nField and c.methodIsMutating(nodes[callee].text):
			root = c.rootName(nodes[callee].kids(kidIds)[0]).copy()
			if root != "" and root not in locals:
				c.errorAt(
					line,
					col,
					compileError("ParallelChangeBy", ["{nodes[callee].text}", "{root}"])
				)
	for i in 0..c.nodes[e].kids(c.kidIds).len:
		c.parallelWrites(nodes[e].kids(kidIds)[i], made, locals)
	for i in 0..c.nodes[e].sub().len:
		c.parallelWrites(nodes[e].sub()[i], made, locals)

# whether the place e is reached through an index whose expression uses one of the names
fn indexedBy(c Checker, e NodeId, names str[]):
	at = e
	while nodes[at].kind in [nField, nIndex, nDeref]:
		if nodes[at].kind == nIndex and
			mentionsAny(nodes, kidIds, nodes[at].kids(kidIds)[1], names):
			return true
		at = nodes[at].kids(kidIds)[0]
	false

# whether e is made of number literals alone (and + - * / %, parentheses, and `cond ? a : b`
# whose condition cannot change and whose branches are such numbers): a value that is the same
# wherever it is written, so each use may take the type its place asks for
fn isNumberExpr(mut c Checker, e NodeId) bool:
	k = nodes[e].kind
	if k == nInt or k == nFloat: return true
	if k == nMatch and nodes[e].kids(kidIds).len == 3 and c.isSteady(nodes[e].kids(kidIds)[0]):
		# `cond ? a : b` (ifValueNode): two arms, each a value
		for i in 1..3:
			arm = nodes[e].kids(kidIds)[i]
			if not nodes[arm].sub().isEmpty or nodes[arm].kids(kidIds).len < 2 or
				not c.isNumberExpr(nodes[arm].kids(kidIds)[1]):
				return false
		return true
	if k == nUnary: return nodes[e].ival == unNeg and c.isNumberExpr(nodes[e].kids(kidIds)[0])
	if k == nBinary:
		op = nodes[e].ival
		arith = op in [binAdd, binSub, binMul, binDiv, binMod]
		return arith and c.isNumberExpr(nodes[e].kids(kidIds)[0]) and
			c.isNumberExpr(nodes[e].kids(kidIds)[1])
	false

# `cond ? 0.9 : 1.0` with any condition: a choice between numbers alone, whose type the uses of
# its binding may decide as they would a literal's
fn isNumberChoice(mut c Checker, e NodeId):
	if nodes[e].kind != nMatch or nodes[e].kids(kidIds).len != 3: return false
	for i in 1..3:
		arm = nodes[e].kids(kidIds)[i]
		if not nodes[arm].sub().isEmpty or nodes[arm].kids(kidIds).len < 2 or
			not c.isNumberExpr(nodes[arm].kids(kidIds)[1]):
			return false
	true

# `[0.3, 0.4][i]`: an element of a list literal of numbers alone
fn isNumberListIndex(mut c Checker, e NodeId):
	if nodes[e].kind != nIndex: return false
	base = nodes[e].kids(kidIds)[0]
	if nodes[base].kind != nArray: return false
	nodes[base].kids(kidIds).all(c.isNumberExpr(it))

# whether e reads only what cannot change while the function runs (immutable locals and
# constants, literals, and operators over them) and calls nothing: evaluated again at each use
# it gives the same value
fn isSteady(mut c Checker, e NodeId) bool:
	k = nodes[e].kind
	if k in [nInt, nFloat, nBool]: return true
	if k == nIdent:
		v = c.lookupVar(nodes[e].text)
		return v < 0 or not c.vars[v].isMut
	if k in [nUnary, nBinary, nField]: return nodes[e].kids(kidIds).all(c.isSteady(it))
	false

# yield v: in a generator's body (a function whose result is a Seq<T>), v a T the loop walking
# it takes
fn checkYield(mut c Checker, s NodeId):
	line = nodes[s].line
	col = nodes[s].col
	value = nodes[s].kids(kidIds)[0]
	if c.inferringRet or not c.lamStack.isEmpty or c.tKind(c.currentRet) != tSeq:
		c.checkExpr(value, none)
		c.errorAt(line, col, compileError("YieldOutsideGenerator", []))
		return
	elem = innerOf(tys, c.currentRet)
	vt = c.checkExpr(value, elem)
	v = value
	c.noteNarrowedAt(value, elem)
	if not isAssignable(tys, vt, elem):
		v = c.fitValue(value, elem)
		vt = typeOf(nodes, v)
	if not isAssignable(tys, vt, elem) and not c.retypeFlex(v, elem):
		c.errorAt(line, col, compileError("GeneratorType", ["{c.showTy(elem)}", "{c.showTy(vt)}"]))
		return
	madeKid = c.coerceTo(v, elem)
	nodes[s].setKid(kidIds, 0, madeKid)

fn checkReturn(mut c Checker, s NodeId):
	line = nodes[s].line
	col = nodes[s].col
	hasValue = not nodes[s].kids(kidIds).isEmpty
	if c.inferringRet:
		c.checkReturnInferred(s, line, col, hasValue)
		return
	ret = c.currentRet ?? tyUnit
	rk = c.tKind(ret)
	if not hasValue:
		if not c.givesNoValue(ret):
			c.errorAt(line, col, compileError("MissingValue", ["{c.showTy(ret)}"]))
		return
	value = nodes[s].kids(kidIds)[0]
	if rk == tSeq:
		c.checkExpr(value, none)
		c.errorAt(line, col, compileError("GeneratorReturn", []))
		return
	if rk == tResult:
		c.checkReturnResult(s, value, ret, line, col)
		return
	if rk == tOption:
		c.checkReturnOption(s, value, ret, line, col)
		return
	vt = c.checkExpr(value, ret)
	c.noteWidenedAt(value, ret, true)
	c.noteNarrowedAt(value, ret)
	if rk == tUnit:
		if c.tKind(vt) != tUnit and c.tKind(vt) != tError:
			c.errorAt(line, col, compileError("NoValueExpected", ["{c.showTy(vt)}"]))
	elif not isSameType(tys, vt, ret):
		if c.tKind(vt) == tRef and isAssignable(tys, vt, ret):
			madeKid = c.coerceTo(value, ret)
			nodes[s].setKid(kidIds, 0, madeKid)
		else:
			widened = c.fitValue(value, ret)
			if widened != value:
				nodes[s].setKid(kidIds, 0, widened)
			else:
				errorAt(
					c,
					line,
					col,
					compileError(
						"ReturnMismatch",
						["{c.showTy(ret)}", "{c.showTy(vt)}", "{c.rangeHint(vt, ret)}"]
					)
				)

fn checkReturnInferred(mut c Checker, s NodeId, line i64, col i64, hasValue bool):
	if c.lamStack.isEmpty and c.resultMode != modeWritten:
		c.checkResultReturn(s, line, col, hasValue)   # the function's own (results.zap)
		return
	if not hasValue:
		if c.inferRet != none and c.tKind(c.inferRet) != tUnit:
			errorAt(
				c,
				line,
				col,
				compileError("LambdaMissingValue", ["{c.showTy(c.inferRet)}"])
			)
		else:
			c.inferRet = tyUnit
		return
	value = nodes[s].kids(kidIds)[0]
	vt = c.checkExpr(value, c.inferRet)
	if c.tKind(vt) == tRef:
		# a lambda's result is a value: a reference (a window into a temporary of the lambda,
		# or into a parameter) is copied out
		vt = innerOf(tys, vt)
		madeKid = c.coerceTo(value, vt)
		nodes[s].setKid(kidIds, 0, madeKid)
	if c.inferRet == none:
		c.keepConversion(nodes[s].kids(kidIds)[0])   # the result's type comes from it
	inferred = c.inferRet ?? c.heldType(vt)
	c.inferRet = inferred
	if isAssignable(tys, vt, inferred) and not isSameType(tys, vt, inferred):
		c.coerceKid(s, 0, inferred)
	elif not isAssignable(tys, vt, inferred):
		errorAt(
			c,
			line,
			col,
			compileError("LambdaReturnsDiffer", ["{c.showTy(vt)}", "{c.showTy(inferred)}"])
		)
	else:
		madeKid = c.coerceTo(value, inferred)
		nodes[s].setKid(kidIds, 0, madeKid)
	return

fn checkReturnResult(mut c Checker, s NodeId, value NodeId, ret TypeId, line i64, col i64):
	# value T -> Ok, value E -> Err, or a Result passed through directly; when T is an optional, its
	# value and none are T's too
	inner = tys[ret].inner
	optional TypeId? = none
	if inner is t and c.tKind(t) == tOption: optional = t
	vt =c.checkExpr(value, optional ?? ret if nodes[value].kind == nNone else ret)
	if isSameType(tys, vt, ret) or isSameType(tys, vt, inner) or
		isSameType(tys, vt, tys[ret].err):
		return
	if isRangeIntoWrapped(tys, vt, ret):
		madeKid = c.coerceTo(value, ret)
		nodes[s].setKid(kidIds, 0, madeKid)
		return
	if optional is o and isAssignable(tys, vt, o):
		madeKid = c.coerceTo(value, o)
		nodes[s].setKid(kidIds, 0, madeKid)   # some(value)
		return
	c.errorAt(
		line,
		col,
		compileError(
			"ReturnType",
			["{c.showTy(tys[ret].inner)}", "{c.showTy(tys[ret].err)}", "{c.showTy(vt)}"]
		)
	)
	return

fn checkReturnOption(mut c Checker, s NodeId, value NodeId, ret TypeId, line i64, col i64):
	# value T -> Some(T), or none/optional passed through directly; references give their value
	vt = c.checkExpr(value, ret)
	if tys[ret].inner != none and isSameType(tys, vt, tys[ret].inner) and
		c.tKind(vt) == tOption and
		not isSameType(tys, vt, ret):
		# an optional returned as the value of an optional of optionals: wrapped explicitly
		w = newNode(nodes, kidIds, nSome, nodes[value].line, nodes[value].col)
		nodes[w].pushKid(kidIds, value)
		nodes[w].ty = ret
		nodes[s].setKid(kidIds, 0, w)
		return
	if isSameType(tys, vt, ret): return
	if tys[ret].inner != none and isSameType(tys, vt, tys[ret].inner):
		madeKid = c.coerceTo(value, ret)
		nodes[s].setKid(kidIds, 0, madeKid)   # some(value), written out for the backends
		return
	if c.isOptionOfRef(vt) and isAssignable(tys, vt, ret) or isRangeIntoWrapped(tys, vt, ret):
		madeKid = c.coerceTo(value, ret)
		nodes[s].setKid(kidIds, 0, madeKid)
		return
	if c.tKind(vt) == tRef and tys[ret].inner != none and
		isAssignable(tys, vt, innerOf(tys, ret)):
		madeKid = c.coerceTo(value, tys[ret].inner)
		nodes[s].setKid(kidIds, 0, madeKid)
		return
	errorAt(
		c,
		line,
		col,
		compileError(
			"ReturnType",
			["{c.showTy(ret)}", "{c.showTy(tys[ret].inner)}", "{c.showTy(vt)}"]
		)
	)
	return
