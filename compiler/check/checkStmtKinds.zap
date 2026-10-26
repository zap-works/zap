# The checking of a statement by kind, blocks, terminating code, extern fields and recursive types (checkStmt.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

fn checkStmt(mut c Checker, s NodeId):
	indexed = c.beforeStmt(s)
	c.checkForgetting(s)
	c.afterStmt(s, indexed)

fn checkStmtOfKind(mut c Checker, s NodeId):
	if nodes[s].text == "$chain":
		c.chainStarts.push(c.vars.len)
		c.checkStmtOfKindAt(s)
		c.chainStarts.pop()
		return
	c.checkStmtOfKindAt(s)

fn checkStmtOfKindAt(mut c Checker, s NodeId):
	k = nodes[s].kind
	line = nodes[s].line
	col = nodes[s].col
	if k == nLet:
		c.checkLet(s)
	elif k == nAssign:
		c.checkStmtOfKindAssign(s, line, col)
	elif k == nReturn:
		c.checkReturn(s)
	elif k == nYield:
		c.checkYield(s)
	elif k == nExprStmt and c.eachAsFor(s):
		c.checkStmtOfKind(s)
	elif k == nExprStmt:
		c.checkStmtOfKindExpr(s, line, col)
	elif k == nIf:
		c.checkStmtOfKindIf(s, line, col)
	elif k == nWhile:
		c.checkStmtOfKindWhile(s, line, col)
	elif k == nFor:
		c.checkFor(s)
	elif k == nBreak:
		if c.loopDepth == 0:
			c.errorAt(line, col, compileError("BreakOutsideLoop", []))
	elif k == nContinue:
		if c.loopDepth == 0:
			c.errorAt(line, col, compileError("ContinueOutsideLoop", []))

fn checkStmtOfKindAssign(mut c Checker, s NodeId, line i64, col i64):
	if c.tableAssign(s): return
	c.bitsAssign(s)
	target = nodes[s].kids(kidIds)[0]
	value = nodes[s].kids(kidIds)[1]
	if nodes[target].kind == nIndex and not nodes[target].hasFlag(flagComma):
		base = nodes[target].kids(kidIds)[0]
		ot = c.derefIfRef(base, c.checkExpr(base, none))
		if nodes[s].ival == 0 and (c.tKind(ot) == tMap or
				c.isIndexable(ot) and c.findMethod(tys[ot].name, "set") != none):
			# m[k] = v stores v under k, a new key or not: m.set(k, v); m[k] += v changes
			# the value in place (indexMut), so the key is only read
			set = newNode(nodes, kidIds, nField, line, col, text = "set", kids = [base])
			call = newNode(
				nodes,
				kidIds,
				nCall,
				line,
				col,
				kids = [set, nodes[target].kids(kidIds)[1], value]
			)
			nodes[call].flags |= flagInternal
			nodes[s].kind = nExprStmt
			nodes[s].setKids(kidIds, [call])
			c.checkStmt(s)
			return
		if c.tKind(ot) != tList and c.tKind(ot) != tArray and c.tKind(ot) != tMap and
			c.tKind(ot) != tError and c.uniformNumberField(ot) == none and
			not c.isIndexable(ot):
			c.errorAt(line, col, compileError("IndexAssignNotSupported", ["{c.showTy(ot)}"]))
	tt = c.checkExpr(target, none)
	if nodes[target].kind == nIdent and c.tKind(tt) == tRef and tys[tt].bits == 1:
		tt = c.derefIfRef(target, tt)   # a `mut ref` binding's place
	# mutability: through a mut ref anything goes; otherwise the root variable must be mut
	block, name = c.mutBlocker(target, line, col)
	if nodes[target].kind == nIndex and
		c.tKind(c.derefType(typeOf(nodes, nodes[target].kids(kidIds)[0]))) == tStr:
		c.errorAt(line, col, compileError("StrNotInPlace", []))
	elif block == blockReadRef:
		c.errorAt(line, col, compileError("AssignThroughReadRef", []))
	elif block == blockShared:
		errorAt(
			c,
			line,
			col,
			compileError("AssignThroughShared", [])
		)
	elif block == blockConstant and not nodes[s].hasFlag(flagInit):
		c.errorAt(line, col, compileError("AssignConstant", ["{name}"]))
	elif block == blockImmutable:
		c.errorAt(line, col, compileError("AssignThroughImmutable", ["{name}"]))
	vt = c.checkExpr(value, tt)
	c.noteWidenedAt(value, tt, true)
	c.noteNarrowedAt(value, tt)
	if not isAssignable(tys, vt, tt):
		value = c.fitValue(value, tt)
		vt = typeOf(nodes, value)
	if not isAssignable(tys, vt, tt):
		if not c.retypeFlex(value, tt):
			errorAt(
				c,
				line,
				col,
				compileError(
					"AssignTypeMismatch",
					["{c.showTy(vt)}", "{c.showTy(tt)}", "{c.rangeHint(vt, tt)}"]
				)
			)
	madeKid = c.coerceTo(value, tt)
	nodes[s].setKid(kidIds, 1, madeKid)

fn checkStmtOfKindExpr(mut c Checker, s NodeId, line i64, col i64):
	ex = nodes[s].kids(kidIds)[0]
	# a lambda's last statement may be its result: there a choice of expressions is a value
	c.matchStmt = nodes[ex].kind == nMatch and
		not (s == c.valueTail and c.matchArms(ex).all(c.armBlock(it) == none)) or
		nodes[ex].kind == nBinary and nodes[ex].ival == binCoalesce and s != c.valueTail
	c.stmtExpr = ex
	t = c.checkExpr(ex, none)
	c.stmtExpr = none
	c.matchStmt = false
	if s != c.valueTail and c.tKind(t) == tResult:
		errorAt(
			c,
			line,
			col,
			compileError("ResultIgnored", [])
		)
	if s != c.valueTail and c.tKind(t) != tUnit and c.tKind(t) != tError and
		c.makesValueOnly(ex) and c.reportsUnused("CopyIgnored"):
		c.errorAt(line, col, compileError("CopyIgnored", ["{c.showTy(t)}"]))

fn checkStmtOfKindIf(mut c Checker, s NodeId, line i64, col i64):
	ct = c.checkExpr(nodes[s].kids(kidIds)[0], tyBool)
	if c.tKind(ct) != tBool and c.tKind(ct) != tError:
		c.errorAt(line, col, compileError("ConditionNotBool", ["if", "{c.showTy(ct)}"]))
	cond = nodes[s].kids(kidIds)[0]
	c.checkNarrowed(nodes[s].sub()[0], cond, true)
	if nodes[s].sub().len > 1:
		c.checkNarrowed(nodes[s].sub()[1], cond, false)
	elif c.blockLeaves(nodes[s].sub()[0]) and not nodes[s].hasFlag(flagArena):
		c.narrowBy(cond, false)   # what follows runs only when it failed

fn checkStmtOfKindWhile(mut c Checker, s NodeId, line i64, col i64):
	c.forgetChangedIndexes(nodes[s].sub()[0])   # the condition is evaluated after the body too
	ct = c.checkExpr(nodes[s].kids(kidIds)[0], tyBool)
	if c.tKind(ct) != tBool and c.tKind(ct) != tError:
		c.errorAt(line, col, compileError("ConditionNotBool", ["while", "{c.showTy(ct)}"]))
	c.enterScope()
	c.narrowBy(nodes[s].kids(kidIds)[0], true, onlyLengths = true)
	c.checkLoopBody(nodes[s].sub()[0], forgotten = true)
	c.exitScope()

# the first n statements of the block b, each known as b's (mutability.zap)
fn checkStmts(mut c Checker, b NodeId, n i64):
	c.openBlocks.push(b)
	c.openAt.push(0)
	c.openMentions.push(Mentions())
	c.openIndexed.push(false)
	for i in 0..n:
		c.openAt[len - 1] = i
		c.checkStmt(nodes[b].kids(kidIds)[i])
	c.openBlocks.truncate(c.openBlocks.len - 1)
	c.openAt.truncate(c.openAt.len - 1)
	c.openMentions.truncate(c.openMentions.len - 1)
	c.openIndexed.truncate(c.openIndexed.len - 1)

fn checkBlock(mut c Checker, b NodeId):
	c.enterScope()
	if nodes[b].text == "$again" and not c.chainStarts.isEmpty:
		c.widenNarrowed(c.chainStarts[len - 1])
	c.checkStmts(b, nodes[b].kids(kidIds).len)
	c.lostCopies(b)
	c.exitScope()

# `mut m = xs[i]` with m plain data: m is a copy. When what follows only ever changes m (and
# reads it only to change it), the changes are lost: an error that says how to change the
# element itself.
fn lostCopies(mut c Checker, b NodeId):
	kids = nodes[b].kids(kidIds).copy()
	for i in 0..kids.len:
		s = kids[i]
		if nodes[s].kind != nLet or not nodes[s].hasFlag(flagMut) or nodes[s].kids(kidIds).isEmpty:
			continue
		value = nodes[s].kids(kidIds)[0]
		vk = nodes[value].kind
		t = typeOf(nodes, value)
		if vk != nIndex and (vk != nField or nodes[value].hasFlag(flagSafe)) or
			c.tKind(t) != tStruct or not c.isPlainType(t):
			continue
		name = nodes[s].text.copy()
		writes = 0
		reads = 0
		for j in i + 1..kids.len:
			w, r = c.usesOf(kids[j], name)
			writes += w
			reads += r
		if writes > 0 and reads == 0:
			place = exprText(nodes, kidIds, value)
			c.errorAt(
				nodes[s].line,
				nodes[s].col,
				compileError("ChangedCopyLost", ["{name}", "{place}"])
			)

# how many times e writes to `name` (an assignment whose target starts at it) and reads it
# otherwise (a read inside the value written to it only feeds it, so it does not count)
fn usesOf(c Checker, e NodeId, name str) (i64, i64):
	k = nodes[e].kind
	if k == nIdent: return (0, 1 if nodes[e].text == name else 0)
	if k == nAssign and c.rootName(nodes[e].kids(kidIds)[0]) == name: return (1, 0)
	if k == nLambda: return (0, 1 if mentions(nodes, kidIds, e, false, name) else 0)
	w = 0
	r = 0
	for kid in nodes[e].kids(kidIds):
		kw, kr = c.usesOf(kid, name)
		w += kw
		r += kr
	for sb in nodes[e].sub():
		sw, sr = c.usesOf(sb, name)
		w += sw
		r += sr
	(w, r)

# the variable a place starts at (m in m.hp, xs in xs[i].x), or ""
fn rootName(c Checker, e NodeId) ref str:
	rootNameOf(nodes, kidIds, e)

# ---- definite termination: does every path through a block end in return/exit? ----

fn stmtHasBreak(c Checker, s NodeId) bool:
	k = nodes[s].kind
	if k == nBreak: return true
	if k == nIf:
		if c.blockHasBreak(nodes[s].sub()[0]): return true
		return nodes[s].sub().len > 1 and c.blockHasBreak(nodes[s].sub()[1])
	if k == nExprStmt:
		ex = nodes[s].kids(kidIds)[0]
		if nodes[ex].kind == nMatch:
			for arm in c.matchArms(ex):
				blk = c.armBlock(arm)
				if blk is blk and c.blockHasBreak(blk): return true
		return false
	false   # a break inside a nested loop belongs to that loop

fn blockHasBreak(c Checker, b NodeId) bool:
	nodes[b].kids(kidIds).any(c.stmtHasBreak(it))

fn stmtTerminates(c Checker, s NodeId) bool:
	k = nodes[s].kind
	if k == nReturn: return true
	if k == nIf and nodes[s].hasFlag(flagArena): return c.blockTerminates(nodes[s].sub()[0])
	if k == nIf:
		return nodes[s].sub().len > 1 and c.blockTerminates(nodes[s].sub()[0]) and
			c.blockTerminates(nodes[s].sub()[1])
	if k == nWhile:
		# `while true` without a break never falls through
		cond = nodes[s].kids(kidIds)[0]
		return nodes[cond].kind == nBool and nodes[cond].ival == 1 and
			not c.blockHasBreak(nodes[s].sub()[0])
	if k == nExprStmt: return c.exprTerminates(nodes[s].kids(kidIds)[0])
	false

# whether a function of that result type gives no value: `()`, or `() ? E` (`fn f() ? E`),
# whose body may end or `return` bare, the ok side
fn givesNoValue(c Checker, ret TypeId?):
	k = c.tKind(ret)
	k == tUnit or k == tSeq or (k == tResult and c.tKind(innerOf(tys, ret)) == tUnit)

fn blockTerminates(c Checker, b NodeId) bool:
	nodes[b].kids(kidIds).any(c.stmtTerminates(it))

# An expression statement that never falls through: exit(), or a match whose every arm ends
# in a return (a block arm, a nested match, or exit).
fn exprTerminates(c Checker, e NodeId) bool:
	k = nodes[e].kind
	if k == nCall:
		callee = nodes[e].kids(kidIds)[0]
		if nodes[callee].kind == nIdent and endsProgram(nodes[callee].text): return true
	if k != nMatch: return false
	arms = c.matchArms(e)
	if arms.isEmpty: return false
	for arm in arms:
		blk = c.armBlock(arm)
		if blk is blk:
			if not c.blockTerminates(blk): return false
		elif not c.exprTerminates(c.armBody(arm)):
			return false
	true

# ---- value-recursive types: a struct/enum that contains itself by value has no finite size ----

fn declContainsByValue(mut c Checker, d NodeId, target NodeId, mut visiting NodeId[]):
	if d in visiting:
		return false   # a different cycle on the path: reported from its own root
	visiting.push(d)
	found = false
	if nodes[d].kind == nStructDecl:
		for f in nodes[d].kids(kidIds).copy():
			if found: break
			ft = c.resolveType(nodes[f].types()[0])
			found = c.typeContainsByValue(ft, target, visiting)
	elif nodes[d].kind == nEnumDecl:
		for v in nodes[d].kids(kidIds).copy():
			if found: break
			for f in nodes[v].kids(kidIds).copy():
				if found: break
				ft = c.resolveType(nodes[f].types()[0])
				found = c.typeContainsByValue(ft, target, visiting)
	visiting.pop()
	found

fn typeContainsByValue(mut c Checker, t TypeId, target NodeId, mut visiting NodeId[]) bool:
	k = c.tKind(t)
	if k == tStruct or k == tEnum:
		if declOf(tys, t) == target: return true
		return c.declContainsByValue(declOf(tys, t), target, visiting)
	if k == tOption: return c.typeContainsByValue(innerOf(tys, t), target, visiting)
	if k == tResult:
		return c.typeContainsByValue(innerOf(tys, t), target, visiting) or
			c.typeContainsByValue(errOf(tys, t), target, visiting)
	false   # List, Map and fn values are references: they break the cycle

# An extern type's fields: what C has (integers, floats, bools, other extern types, fixed
# arrays of those) and C pointers, as references: to such a value or to a str's bytes, to the
# elements of a list of such values, optional (none: NULL). Nothing the type would own.
fn checkExternFields(mut c Checker, d NodeId):
	if not nodes[d].names().isEmpty:
		c.errorAt(nodes[d].line, nodes[d].col, compileError("ExternTypeGeneric", []))
	for f in nodes[d].kids(kidIds).copy():
		ft = c.resolveType(nodes[f].types()[0])
		t = ft
		if c.tKind(t) == tOption and tys[t].inner != none and c.tKind(tys[t].inner) == tRef:
			t = innerOf(tys, t)
		ok = c.isCField(t)
		if c.tKind(t) == tRef:
			inner = innerOf(tys, t)
			ok = tys[t].bits == 0 and
				(
					c.isCField(inner) or c.tKind(inner) == tStr or
						c.tKind(inner) == tList and c.isCField(innerOf(tys, inner))
				)
		if not ok:
			c.errorAt(
				nodes[f].line,
				nodes[f].col,
				compileError(
					"ExternFieldType",
					["{nodes[f].text}", "{nodes[d].text2()}", "{c.showTy(ft)}"]
				)
			)

# a value C holds in place: a number, a bool, an extern type, a fixed array of those
fn isCField(mut c Checker, t TypeId) bool:
	k = c.tKind(t)
	if k in [tInt, tFloat, tBool]: return true
	if k == tStruct: return c.isExternType(declOf(tys, t))
	if k == tArray: return c.isCField(innerOf(tys, t))
	false

fn checkRecursiveTypes(mut c Checker):
	n = c.decls.len
	for i in 0..n:
		d = c.decls[i]
		if nodes[d].hasFlag(flagShared) and nodes[d].mod() != "rt":
			c.enterModuleOf(d)   # (the error at its file)
			c.errorAt(nodes[d].line, nodes[d].col, compileError("SharedTypeOfRuntime", []))
		if not isTypeDeclKind(nodes[d].kind) or c.isGenericTemplate(d): continue
		c.enterModuleOf(d)
		if c.isExternType(d):
			c.checkExternFields(d)
		visiting = []
		if c.declContainsByValue(d, d, visiting):
			c.errorAt(
				nodes[d].line,
				nodes[d].col,
				compileError("TypeContainsItself", ["{nodes[d].text2()}"])
			)
	c.curMod = -1
	c.curFile = ""

# Checks a function body, then analyses ownership; when the analysis inserted copies the body
# is checked again with the marks (a few rounds at most).
# One way to give the result: the last expression of a body is its value, and `return` is
# for leaving early. A `return value` written as the last statement (or the last of each
# branch of a final if/else) is noted for zap fmt, which writes the value alone.
fn reportTailReturns(mut c Checker, blk NodeId):
	n = nodes[blk].kids(kidIds).len
	if n == 0: return
	last = nodes[blk].kids(kidIds)[n - 1]
	if nodes[last].kind == nReturn and nodes[last].ival == 0 and
		not nodes[last].kids(kidIds).isEmpty:
		if not noting: return
		src = c.file if c.curFile == "" else c.curFile
		text = sourceLineOf(src, nodes[last].line)
		at = nodes[last].col - 1
		if at >= 0 and at + 7 <= text.len and text[at..at + 7] == "return ":
			c.canonNote(noteReplace, nodes[last].line, at + 1, 7, "")
	elif nodes[last].kind == nIf and nodes[last].sub().len > 1:
		for b in nodes[last].sub():
			c.reportTailReturns(b)

# `xs.each(f)` as a statement is `for x in xs:` with f's body: f a lambda of one parameter, or a
# form of `it` or `.field` (`team.filter(.alive).each(print(.name))`), the end of a pipeline; a
# lambda of two is `for a, b in xs:` (an index and an element, a key and a value)
fn eachAsFor(mut c Checker, s NodeId):
	e = nodes[s].kids(kidIds)[0]
	if nodes[e].kind != nCall or nodes[e].kids(kidIds).len != 2: return false
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind != nField or nodes[callee].text != "each" or
		nodes[callee].kids(kidIds).isEmpty:
		return false
	lam = nodes[e].kids(kidIds)[1]
	c.itLambda(lam)
	if nodes[lam].kind != nLambda or nodes[lam].names().len < 1 or nodes[lam].names().len > 2:
		return false
	line = nodes[s].line
	col = nodes[s].col
	body = nodes[lam].sub()[0] if not nodes[lam].sub().isEmpty else lam
	if nodes[lam].sub().isEmpty:
		run = newNode(nodes, kidIds, nExprStmt, line, col, kids = [nodes[lam].kids(kidIds)[0]])
		body = newNode(nodes, kidIds, nBlock, line, col, kids = [run])
	xs = nodes[callee].kids(kidIds)[0]
	refused = c.isParallelStep(xs) and nodes[lam].names().len != 1 or
		not c.isParallelStep(xs) and c.parallelEachChain(xs)
	if refused:
		name = "ParallelEachParams" if c.isParallelStep(xs) else "ParallelEachSource"
		c.errorAt(line, col, compileError(name, []))
		nodes[s].kind = nBlock   # checked no further
		nodes[s].setKids(kidIds, [])
		return true
	if nodes[lam].names().len == 1:
		nodes[s].kind = nFor
		nodes[s].setText(nodes[lam].names()[0].copy())
		nodes[s].setKids(kidIds, [xs])
		nodes[s].nodePart().sub = [body]
		return true
	c.eachIndexed(s, xs, nodes[lam].names()[0].copy(), nodes[lam].names()[1].copy(), body)
	true

# whether xs is map and filter steps over a `.parallel()`
fn parallelEachChain(c Checker, xs NodeId):
	at = xs
	while nodes[at].kind == nCall and not c.isParallelStep(at):
		f = nodes[at].kids(kidIds)[0]
		if nodes[f].kind != nField or nodes[f].kids(kidIds).len != 1 or
			nodes[f].text not in ["map", "filter", "flatMap"]:
			return false
		at = nodes[f].kids(kidIds)[0]
	c.isParallelStep(at)

# statement s made `for first, second in xs:` with the body, as the parser makes that loop: over
# the indexes (a map's keys), the second name bound to the element; xs bound to a hidden name
# first when it is not one, for as long as the loop
fn eachIndexed(mut c Checker, s NodeId, xs NodeId, first str, second str, body NodeId):
	line = nodes[s].line
	col = nodes[s].col
	list = xs
	hidden NodeId? = none
	if nodes[xs].kind != nIdent:
		bound = newNode(nodes, kidIds, nLet, line, col, kids = [xs])
		nodes[bound].setText("$each{line}_{col}")
		list = newNode(nodes, kidIds, nIdent, line, col)
		nodes[list].setText(nodes[bound].text.copy(), nodes[bound].name)
		hidden = bound
	zero = newNode(nodes, kidIds, nInt, line, col)
	nodes[zero].setText("0")
	r = newNode(
		nodes,
		kidIds,
		nRange,
		line,
		col,
		kids = [zero, lenOf(nodes, kidIds, line, col, cloneTree(nodes, kidIds, list))]
	)
	idx = newNode(nodes, kidIds, nIdent, line, col)
	nodes[idx].setText(first.copy())
	at = newNode(nodes, kidIds, nIndex, line, col, kids = [cloneTree(nodes, kidIds, list), idx])
	borrow = newNode(nodes, kidIds, nUnary, line, col, kids = [at])
	nodes[borrow].ival = unRef
	bind = newNode(nodes, kidIds, nLet, line, col, kids = [borrow])
	nodes[bind].setText(second.copy())
	nodes[bind].flags = flagInternal
	nodes[body].insertKid(kidIds, 0, bind)
	walk = newNode(nodes, kidIds, nFor, line, col, kids = [r])
	nodes[walk].setText(first.copy())
	nodes[walk].nodePart().sub = [body]
	nodes[walk].flags |= flagInternal
	if hidden is h:
		always = newNode(nodes, kidIds, nBool, line, col)
		nodes[always].ival = 1
		scope = newNode(nodes, kidIds, nBlock, line, col, kids = [h, walk])
		nodes[s].kind = nIf
		nodes[s].setKids(kidIds, [always])
		nodes[s].nodePart().sub = [scope]
	else:
		nodes[s] = nodes[walk].copy()
