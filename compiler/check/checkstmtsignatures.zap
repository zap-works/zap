# The checking of function bodies, signatures, declaration names, field types and methods (checkstmt.zap).

alias nodes = c.nodes
alias tys = c.types

fn checkFnBody(mut c Checker, fnd NodeId, implType TypeId?, implIsMut bool):
	c.rejectForwardingConstructor(fnd)
	savedGpu = c.gpuCode
	c.gpuCode = nodes[fnd].hasFlag(flagGpu)
	savedMode = c.resultMode
	c.resultMode = c.resultModeOf(fnd)
	if c.resultMode == modeInferred or c.resultMode == modeGeneric:
		markImplicitReturns(nodes, nodes[fnd].sub[0])   # as a written result's (results.zap)
	c.trialFails = false
	round = 0
	again = true
	c.reportPending()   # what came before the body is reported as it was
	bodyErrors = c.errors
	hidden = c.hideLiveHandles()
	lengths = c.hideLengths(false)
	names = c.lengthNames
	c.lengthNames = 0
	while again:
		c.round = round
		errorsBefore = c.errors
		keptBefore = c.errorsKept
		# (a block's method found changing its receiver: mut from the next round)
		again = c.checkFnBodyRound(fnd, implType, implIsMut or nodes[fnd].hasFlag(flagMut)) and
			round < 8
		restoreTo = errorsBefore + c.errorsKept - keptBefore   # the bodies checked meanwhile keep theirs
		if c.deferred and c.atDefinition:
			c.pending.clear()   # checked again once the results it needs are known
			c.errors = restoreTo
			break
		if not again and c.resultMode != modeWritten:
			again = c.settleResult(fnd, restoreTo) and round < 8
		if again:
			# checked again: this round's errors come back if they are still there
			c.pending.clear()
			c.errors = restoreTo
		if c.trialCopy == fnd or c.asideCopy == fnd:
			c.pending.clear()   # a trial's errors are its own (resulttrials.zap)
		c.reportPending()
		round += 1
	c.noteReceiverWritten(fnd, bodyErrors)
	c.reportStaleReceivers()
	c.resultMode = savedMode
	c.round = 0
	c.liveHandles = hidden
	c.lenFacts = lengths
	c.lengthNames = names
	c.gpuCode = savedGpu
	if c.errors == bodyErrors and c.trialCopy != fnd and c.asideCopy != fnd:
		c.reportQuantities(fnd)   # (its own errors would blur them)
		if nodes[fnd].names.isEmpty and c.subst.names.isEmpty: c.checkWordsGiven(fnd)
	# said now: a body checked for a caller's sake goes back to the caller's errors after this
	c.reportPending()
	if nodes[fnd].hasFlag(flagFusedMath | flagOptionBlocks) and nodes[fnd].names.isEmpty and
		c.subst.names.isEmpty and c.errors == 0:
		c.fuseMath(fnd)   # not an instance's: its code as the generic's other instances'

# `fn newX(a, b) X` whose body is only X's literal of its parameters and of constants says what
# `X(a, b)` says where it is called, the constants as the fields' defaults: an error
fn rejectForwardingConstructor(mut c Checker, fnd NodeId):
	parts = c.programName(fnd).split(".")
	name = parts[len - 1]
	if not name.startsWith("new") or nodes[fnd].sub.isEmpty or nodes[fnd].types.isEmpty: return
	body = nodes[fnd].sub[0]
	if nodes[body].kids.len != 1: return
	e = nodes[body].kids[0]
	if nodes[e].kind in [nReturn, nExprStmt] and nodes[e].kids.len == 1:
		e = nodes[e].kids[0]
	ret = nodes[fnd].types[0]
	if nodes[e].kind != nCall or nodes[e].kids.isEmpty or nodes[ret].kind != nTyName: return
	callee = nodes[e].kids[0]
	# the result's type as written (a resolved one names its declaration by the global name)
	written = nodes[ret].text.copy()
	if nodes[ret].text2 == globalAlias and c.findDeclByGlobalName(nStructDecl, written) is d:
		written = nodes[d].text2.copy()
	if nodes[callee].kind != nIdent or nodes[callee].text != written: return
	params = nodes[fnd].kids.map(nodes[it].text.copy())
	for a in nodes[e].kids[1..nodes[e].kids.len]:
		v = nodes[a].kids[0] if nodes[a].kind == nNamedArg else a
		if nodes[a].kind == nNamedArg and nodes[a].text == "..": return
		if not (c.constantLiteral(v) or nodes[v].kind == nIdent and nodes[v].text in params): return
	saved = move c.curFile   # (checked before its body: the file may be the one before's)
	c.curFile = nodes[fnd].file().copy()
	c.errorAt(
		nodes[fnd].line,
		nodes[fnd].col,
		compileError("LiteralOnlyFunction", ["{name}", "{written}"])
	)
	c.curFile = saved

# a number, a string, a boolean, none, an empty list or map, or a tuple of those
fn constantLiteral(mut c Checker, v NodeId) bool:
	k = nodes[v].kind
	if k in [nInt, nFloat, nStr, nBool, nNone]: return true
	if k == nUnary and nodes[v].ival == unNeg: return c.constantLiteral(nodes[v].kids[0])
	if k in [nArray, nMapLit]: return nodes[v].kids.isEmpty
	if k != nStructLit or not nodes[v].text.startsWith("Tuple"): return false
	for kid in nodes[v].kids.copy():
		if not c.constantLiteral(kid): return false
	true

# A program's top-level binding whose value is computed is assigned where it stands, by a
# statement of main: a statement before it that reads the binding, itself or through the
# functions it calls by name, is an error naming both lines (where Python fails as it runs).
fn checkProgramOrder(mut c Checker):
	for d in c.decls.copy():
		if nodes[d].kind != nFnDecl or nodes[d].sub.isEmpty or
			nodes[d].text != "main" and not isUnitMain(c.modules, nodes[d].text):
			continue
		stmts = nodes[nodes[d].sub[0]].kids.copy()
		assignedAt {str: i64} = {}
		for i, st in stmts:
			if nodes[st].kind == nAssign and nodes[st].hasFlag(flagInit):
				assignedAt[nodes[nodes[st].kids[0]].text.copy()] = i
		if assignedAt.isEmpty: continue
		c.enterModuleOf(d)   # (the errors at main's file)
		for i, st in stmts:
			seen {NodeId: bool} = {}
			reads = []
			orderedReads(
				c,
				nodes[st].kids[1] if nodes[st].hasFlag(flagInit) else st,
				assignedAt,
				seen,
				reads
			)
			for r in reads:
				if assignedAt.get(nodes[r].text) is j:
					if j > i:
						init = stmts[j]
						parts = displayName(nodes[r].text).split(".")
						c.errorAt(
							nodes[st].line,
							nodes[st].col,
							compileError(
								"ReadBeforeAssigned",
								["{parts[len - 1]}", "{nodes[init].line}"]
							)
						)

# the names in e that an init statement of main assigns, through the functions e calls by name
fn orderedReads(
	mut c Checker,
	e NodeId,
	assignedAt {str: i64},
	mut seen {NodeId: bool},
	mut reads NodeId[]
):
	k = nodes[e].kind
	if k == nIdent and nodes[e].text in assignedAt:
		reads.push(e)
		return
	if k == nCall and not nodes[e].kids.isEmpty and nodes[nodes[e].kids[0]].kind == nIdent:
		fd = c.findDeclByGlobalName(nFnDecl, nodes[nodes[e].kids[0]].text)
		if fd is fd and fd not in seen and not nodes[fd].sub.isEmpty:
			seen[fd] = true
			c.orderedReads(nodes[fd].sub[0], assignedAt, seen, reads)
	for kid in nodes[e].kids.copy():
		c.orderedReads(kid, assignedAt, seen, reads)
	for b in nodes[e].sub.copy():
		c.orderedReads(b, assignedAt, seen, reads)

fn checkFnBodyRound(mut c Checker, fnd NodeId, implType TypeId?, implIsMut bool):
	line = nodes[fnd].line
	col = nodes[fnd].col
	c.enterScope()
	c.implType = implType
	c.receiverChanged = false
	c.receiverSeen = false
	c.receiverUntold = false
	c.enterModuleOf(fnd)
	if implType == none:
		c.implType = c.selfFieldsNamed(fnd)
	c.checkRefOrigins(fnd, implType)
	ik = c.tKind(implType)
	if implType is selfType and ik == tEnum:
		c.addVar("self", selfType, implIsMut, true, line, col)
	if implType is selfType and ik == tStruct:
		# 'this' and fields are accessible directly (without a prefix)
		c.addVar("self", selfType, implIsMut, true, line, col)
		for f in nodes[declOf(tys, selfType)].kids:
			ft = c.resolveType(nodes[f].types[0])
			field = c.addVar(nodes[f].text, ft, implIsMut, true, line, col)
			c.vars[field].isField = true
	c.checkFnBodyRoundParams(fnd)
	inferring = c.resultMode != modeWritten
	c.currentRet = none if inferring else c.writtenResult(fnd)
	c.curFn = fnd
	c.inferringRet = inferring
	c.inferRet = none
	c.openReturns.clear()
	c.openTries.clear()
	c.tryForms.clear()
	c.tailAgain = false
	c.loopDepth = 0
	if c.tKind(c.currentRet) == tSeq and
		(not nodes[fnd].names.isEmpty or not c.subst.names.isEmpty):
		c.errorAt(line, col, compileError("GenericGenerator", []))
	if nodes[fnd].hasFlag(flagExtern):
		c.checkExternSignature(fnd)
		c.currentRet = none
		c.implType = none
		c.exitScope()
		return false
	if nodes[fnd].sub.isEmpty:
		errorAt(
			c,
			line,
			col,
			compileError("MissingBody", ["{nodes[fnd].text}"])
		)
		c.currentRet = none
		c.implType = none
		c.exitScope()
		return false
	body = nodes[fnd].sub[0]
	c.checkStmts(body, nodes[body].kids.len)
	c.lostCopies(body)
	if nodes[fnd].mod() != "derive":
		c.reportTailReturns(body)
	if inferring:
		c.settleOpenReturns()
		c.settleOpenTries()
		c.currentRet = c.inferRet ?? tyUnit
		c.inferringRet = false
		if not c.givesNoValue(c.currentRet) and not c.blockTerminates(body) and
			c.tailOfStatements(body):
			c.tailAgain = true   # the body again, giving nothing
	if not c.givesNoValue(c.currentRet) and not c.blockTerminates(body) and not c.tailAgain:
		c.errorAt(
			line,
			col,
			compileError("MissingReturn", ["'{c.programName(fnd)}'", c.showTy(c.currentRet)])
		)
	# a get whose value an arm changes is a getMut now, a trailing expression a statement: the
	# body again
	if c.relend or c.tailAgain or c.receiverAgainFor(fnd):
		c.relend = false
		c.currentRet = none
		c.implType = none
		c.exitScope()
		return true
	# mut bindings of float literals that met an f32: f32 from the start, and the body again
	if not c.retypes.isEmpty:
		for i, s in c.retypes:
			te = c.typeToTE(c.retypeTo[i])
			nodes[te].flags |= flagInternal   # given by the uses, not written
			nodes[s].types.push(te)
		c.retypes.clear()
		c.retypeTo.clear()
		c.currentRet = none
		c.implType = none
		c.exitScope()
		return true
	c.noteImpliedMoves(fnd)
	c.currentRet = none
	c.implType = none
	c.exitScope()
	false

fn checkFnBodyRoundParams(mut c Checker, fnd NodeId):
	for p in nodes[fnd].kids:
		pt = c.resolveType(nodes[p].types[0])
		if nodes[p].ival == modeOut and not nodes[fnd].hasFlag(flagExtern):
			c.errorAt(
				nodes[p].line,
				nodes[p].col,
				compileError("OutParameterOutsideExtern", ["{nodes[p].text}"])
			)
		if c.tKind(pt) == tSeq:
			c.rejectSeq(nodes[p].line, nodes[p].col, "the parameter '{nodes[p].text}'")
		if nodes[p].ival == modeMut and not c.isMutPassable(pt):
			c.errorAt(
				nodes[p].line,
				nodes[p].col,
				compileError("MutParameterType", ["{nodes[p].text}", "{c.showTy(pt)}"])
			)
		# a mut parameter changes the caller's value, a move parameter its own
		addVar(
			c,
			nodes[p].text,
			pt,
			nodes[p].ival == modeMut or nodes[p].ival == modeMove,
			true,
			nodes[p].line,
			nodes[p].col
		)

# A block's method with type parameters of its own (parseunit.zap blockMethod), a generic
# function taking `self T` first: its body's bare names of T's fields made `self.field`, as a
# method's are, and T (for its bare calls of T's functions), else none.
fn selfFieldsNamed(mut c Checker, fnd NodeId) TypeId?:
	if nodes[fnd].kids.isEmpty or nodes[nodes[fnd].kids[0]].text != "self" or
		nodes[fnd].sub.isEmpty:
		return none
	t = c.resolveType(nodes[nodes[fnd].kids[0]].types[0])
	if c.tKind(t) == tStruct:
		fields = nodes[declOf(tys, t)].kids.map(nodes[it].text.copy())
		c.selfFieldsIn(nodes[fnd].sub[0], fields)
	t if c.tKind(t) == tStruct or c.tKind(t) == tEnum else none

fn selfFieldsIn(mut c Checker, e NodeId, fields str[]):
	k = nodes[e].kind
	if k == nIdent and nodes[e].text in fields:
		recv = newNode(nodes, nIdent, nodes[e].line, nodes[e].col, text = "self")
		nodes[e].kind = nField
		nodes[e].kids = [recv]
		return
	if k == nLet and nodes[e].text in fields and nodes[e].types.isEmpty and
		not nodes[e].hasFlag(flagMut):
		# `count = v`, `count += 1`: the field assigned
		recv = newNode(nodes, nIdent, nodes[e].line, nodes[e].col, text = "self")
		place = newNode(
			nodes,
			nField,
			nodes[e].line,
			nodes[e].col,
			text = nodes[e].text.copy(),
			kids = [recv]
		)
		nodes[e].kind = nAssign
		nodes[e].ival = 1 if nodes[e].hasFlag(flagCompound) else 0
		nodes[e].kids.insert(0, place)
		nodes[e].text = ""
	for i, kid in nodes[e].kids.copy():
		if not (k == nCall and i == 0 and nodes[kid].kind == nIdent):
			c.selfFieldsIn(kid, fields)   # a call's bare name is a function's
	for b in nodes[e].sub.copy():
		c.selfFieldsIn(b, fields)

# An extern function is the one trust boundary: its signature is the only thing the compiler
# cannot verify, so it is kept to values that cross the system boundary as plain words
# (integers, bools, f64; the result may also be unit), as a str or List whose buffer address
# the system receives (and may write into: an out parameter is a List of one word), or as a
# struct whose address it receives (laid out as C would; `mut` when the system writes it), or
# as a function the system calls back (a top-level function over plain words, reached through
# a generated entry with the system's convention).
fn checkExternSignature(mut c Checker, fnd NodeId):
	# the name is read from the node in each message: resolving and reporting change c
	if not nodes[fnd].sub.isEmpty:
		errorAt(
			c,
			nodes[fnd].line,
			nodes[fnd].col,
			compileError("ExternWithBody", ["{nodes[fnd].text}"])
		)
	if not nodes[fnd].names.isEmpty:
		errorAt(
			c,
			nodes[fnd].line,
			nodes[fnd].col,
			compileError("ExternGeneric", ["{nodes[fnd].text}"])
		)
	for p in nodes[fnd].kids:
		pt = c.resolveType(nodes[p].types[0])
		pk = c.tKind(pt)
		if nodes[p].ival == modeOut:
			ot = c.resolveType(nodes[p].sub[0])
			if c.tKind(ot) != tInt and c.tKind(ot) != tFloat:
				c.errorAt(
					nodes[p].line,
					nodes[p].col,
					compileError(
						"ExternOutParameter",
						["{nodes[fnd].text}", "{nodes[p].text}", "{c.showTy(ot)}"]
					)
				)
			continue
		byWord = nodes[p].ival == modeRead and (c.isExternValue(pt) or pk == tList or pk == tStr)
		byAddress = (nodes[p].ival == modeRead or nodes[p].ival == modeMut) and pk == tStruct
		callback = nodes[p].ival == modeRead and pk == tFn and c.isCallbackType(pt)
		if byWord or byAddress:
			c.checkExternLayout(fnd, p, pt)
		if not byWord and not byAddress and not callback:
			c.errorAt(
				nodes[p].line,
				nodes[p].col,
				compileError(
					"ExternParameter",
					["{nodes[fnd].text}", "{nodes[p].text}", "{c.showTy(pt)}"]
				)
			)
	ret = c.fnRetType(fnd)
	if c.tKind(ret) != tUnit and not c.isExternValue(ret):
		c.errorAt(
			nodes[fnd].line,
			nodes[fnd].col,
			compileError("ExternResult", ["{nodes[fnd].text}", "{c.showTy(ret)}"])
		)

# A struct crosses as its bytes, so only an extern type's, whose fields stay in C's order: a plain
# struct's may be reordered (spec 14.2), alone or as a list's elements.
fn checkExternLayout(mut c Checker, fnd NodeId, p NodeId, pt TypeId):
	t = innerOf(tys, pt) if c.tKind(pt) == tList else pt
	if c.tKind(t) != tStruct or c.isExternType(declOf(tys, t)): return
	c.errorAt(
		nodes[p].line,
		nodes[p].col,
		compileError("ExternPlainStruct", ["{nodes[fnd].text}", "{nodes[p].text}", "{c.showTy(t)}"])
	)

# a function type the system can call: plain words in, a plain word or nothing out
fn isCallbackType(mut c Checker, t TypeId):
	r = retOf(tys, t)
	tys[t].params.all(c.isExternScalar(it)) and (c.tKind(r) == tUnit or c.isExternScalar(r))

# a value an extern fn takes or gives by value: a plain word, or an f32 (in the low half of a
# float register, where the system's convention puts it)
fn isExternValue(mut c Checker, t TypeId):
	c.isExternScalar(t) or (c.tKind(t) == tFloat and tys[t].bits == 32)

fn isExternScalar(mut c Checker, t TypeId):
	k = c.tKind(t)
	k == tInt or k == tBool or (k == tFloat and tys[t].bits == 64)

fn resolveFnSignature(mut c Checker, fnd NodeId):
	for p in nodes[fnd].kids:
		c.resolveType(nodes[p].types[0])
	if not nodes[fnd].types.isEmpty:
		c.resolveType(nodes[fnd].types[0])

# Resolves every type written in a signature or field before bodies are checked, so each
# type expression carries its global name for the backend (which resolves without module context).
fn resolveSignatures(mut c Checker):
	n = c.decls.len
	for i in c.freshDecls..n:
		d = c.decls[i]
		k = nodes[d].kind
		c.enterModuleOf(d)
		if c.isGenericTemplate(d) or (k == nImplDecl and not nodes[d].names.isEmpty):
			continue   # checked per instance
		if k == nImplDecl and not nodes[d].names2().isEmpty:
			# the active substitution is the checker's own; the impl keeps its lists
			c.subst = Subst(names = nodes[d].names2().copy(), types = nodes[d].ints().copy())
		if k == nStructDecl:
			for f in nodes[d].kids:
				c.resolveType(nodes[f].types[0])
		elif k == nEnumDecl:
			for v in nodes[d].kids:
				for f in nodes[v].kids:
					c.resolveType(nodes[f].types[0])
		elif k == nFnDecl or k == nImplDecl:
			# the function itself, or each method of the impl (read by index: resolving grows nodes)
			nfns = 1
			if k == nImplDecl:
				nfns = nodes[d].kids.len
			for j in 0..nfns:
				fnd = d
				if k == nImplDecl:
					fnd = nodes[d].kids[j]
				# type parameters stand in for an unknown type while the signature is resolved;
				# the substitution in force moves aside and comes back after
				sav = move c.subst
				subN = []
				subT = []
				if k == nImplDecl:
					# an instance's methods are written in terms of the impl's type parameters
					for g in 0..c.nodes[d].names2().len:
						subN.push(nodes[d].names2()[g].copy())
						subT.push(nodes[d].ints()[g])
				for g in nodes[fnd].names:
					subN.push(g.copy())
					subT.push(tyError)
				c.subst = Subst(names = subN, types = subT)
				c.resolveFnSignature(fnd)
				c.subst = sav
		elif k == nConstDecl and not nodes[d].types.isEmpty:
			c.resolveType(nodes[d].types[0])
		elif k == nBoundDecl:
			for m in nodes[d].kids.copy():
				c.resolveFnSignature(m)   # its types by their global names, for any module
		if k == nImplDecl:
			c.subst = Subst(names = [], types = [])
	c.curMod = -1
	c.curFile = ""

fn implTypeOf(mut c Checker, d NodeId) TypeId?:
	sd = try c.findTypeDecl(nodes[d].text)
	tyOfDecl(tys, nodes, sd)

fn isFnLike(k i64):
	k in [nFnDecl, nConstDecl, nBoundDecl]

# Two declarations of the same name in one module would silently shadow each other.
fn checkDuplicateDecls(mut c Checker):
	first {str: NodeId} = {}   # a kind class, module and name -> its first declaration
	for i, decl in c.decls:
		b = decl
		bk = nodes[b].kind
		if not isFnLike(bk) and not isTypeDeclKind(bk) or
			isTypeDeclKind(bk) and nodes[b].origin != none or nodes[b].text2 == "":
			continue
		key = "{isTypeDeclKind(bk)}|{nodes[b].mod()}|{nodes[b].text2}"
		match first.get(key):
			a:
				if i < c.freshDecls: continue   # said by its own stage
				c.enterModuleOf(b)
				at = "{nodes[a].file()}:{nodes[a].line}" if nodes[a].file() != ""
					else "?:{nodes[a].line}"
				errorAt(
					c,
					nodes[b].line,
					nodes[b].col,
					compileError("AlreadyDeclaredInModule", ["{nodes[b].text2}", "{at}"])
				)
			none: first[key] = b

# A declared name holds no '_' (camelCase and PascalCase): the compiler joins names with it
# (a module's prefix, a method's type, a generic instance's types), so a name written with one
# could be another declaration's. An extern keeps the system's spelling.
fn checkDeclNames(mut c Checker):
	for decl in c.decls[c.freshDecls..].copy():
		d = decl
		k = nodes[d].kind
		if nodes[d].origin != none or nodes[d].hasFlag(flagExtern) or nodes[d].mod() == "derive":
			continue
		if isFnLike(k) or isTypeDeclKind(k):
			c.noUnderscore(d, nodes[d].text2)
		elif k == nImplDecl:
			for m in nodes[d].kids:
				c.noUnderscore(m, nodes[m].text)

fn noUnderscore(mut c Checker, d NodeId, name str):
	if "_" in name and not name.startsWith("$"):
		c.enterModuleOf(d)
		c.errorAt(nodes[d].line, nodes[d].col, compileError("UnderscoreInName", ["{name}"]))

# A variant field holds values, not references; a struct field no list or map of references.
fn checkFieldTypes(mut c Checker):
	savedMod = c.curMod
	savedFile = c.curFile.copy()
	for i in c.freshDecls..c.decls.len:
		d = c.decls[i]
		k = nodes[d].kind
		if not nodes[d].names.isEmpty:
			continue   # a generic template: its instances are checked
		c.enterModuleOf(d)   # names resolve, and errors point, in its file
		if k == nStructDecl and nodes[d].hasFlag(flagTypeAlias):
			if not nodes[d].kids.isEmpty: c.checkBitsDecl(d)
		elif k == nStructDecl:
			for f in nodes[d].kids:
				ft = c.resolveType(nodes[f].types[0])
				if c.tKind(ft) == tSeq:
					c.rejectSeq(nodes[f].line, nodes[f].col, "the field '{nodes[f].text}'")
				c.rejectTupleField(f, ft)
				if c.holdsRefs(ft):
					c.errorAt(
						nodes[f].line,
						nodes[f].col,
						compileError("FieldOfReferences", ["{nodes[f].text}", "{c.showTy(ft)}"])
					)
		elif k == nEnumDecl:
			for v in nodes[d].kids:
				for f in nodes[v].kids:
					c.rejectTupleField(f, c.resolveType(nodes[f].types[0]))
					rejectRef(
						c,
						c.resolveType(nodes[f].types[0]),
						nodes[f].line,
						nodes[f].col,
						"a variant field"
					)
	c.curMod = savedMod
	c.curFile = savedFile

# A field holds no tuple, alone or in a list, an optional, an array or as a map's value: values
# kept together get a type with named fields (a map's key may group values as a tuple).
fn rejectTupleField(mut c Checker, f NodeId, t TypeId):
	if c.holdsTuple(t):
		c.errorAt(
			nodes[f].line,
			nodes[f].col,
			compileError("TupleField", ["{nodes[f].text}", "{c.showTy(t)}"])
		)

fn holdsTuple(c Checker, t TypeId) bool:
	k = c.tKind(t)
	if k in [tOption, tList, tArray]: return tys[t].inner != none and c.holdsTuple(innerOf(tys, t))
	if k == tMap: return tys[t].val != none and c.holdsTuple(valOf(tys, t))
	c.isTupleType(t)

# Whether the lint's quick check again (canon.zap) checks only the bodies of the files it patched,
# the rules that count what every body reads (the fields read as quantities, the names a function's
# effects decide) and the shaders left out: a note's errors are in its own file, but for those a
# changed result makes in a caller, which the whole check that must end it finds.
mut bodiesPatchedOnly = false

fn bodyLeft(c Checker, d NodeId):
	file = nodes[d].file()
	bodiesPatchedOnly and not file.startsWith("<") and sourceOverrides.get(notePath(file)) == none

# The program checked stage by stage (CheckStage, spec 14.2), from where the kept stages left the
# checker (keptstages.zap): each stage's nodes, declarations and modules put after those of the
# stages before it (stagenodes.zap) and checked, kept when it may be; then what reads the whole
# program (the order of main's statements, the effects, the promises). Whether it checks.
pub fn checkProgram(mut prog Program) bool:
	stages = prog.stages.copy()
	if not stages.any(not .done): stages.push(CheckStage("", prog.decls.len, prog.modules.len))
	loaded = prog.takeLoaded(stages)
	c = prog.keptChecker()
	declsAt = 0
	modulesAt = 0
	for i, s in stages:
		if s.done: continue
		last = i == stages.len - 1
		c.freshDecls = c.decls.len
		c.freshInstances = c.instances.len
		c.freshModules = c.modules.len
		c.admitStage(
			loaded,
			i,
			loaded.decls[declsAt..(len if last else s.decls)].copy(),
			loaded.modules[modulesAt..(len if last else s.modules)].copy()
		)
		declsAt = s.decls
		modulesAt = s.modules
		c.checkStage(last, prog.entry)
		stages[i].decls = c.decls.len
		stages[i].modules = c.modules.len
		stages[i].nodes = c.nodes.len
		stages[i].types = c.types.len
		stages[i].done = true
		c.keepStage(stages[..i + 1])
	prog.tests = loaded.tests.map(loaded.placeOf(it))
	prog.stages = move stages
	c.checkWhole(prog)

# the checker the kept stages left (prog.kept), with the bodies they keep, else one of its own
# with its global scope
fn keptChecker(mut prog Program):
	match move prog.kept:
		kept:
			c = move kept
			c.file = prog.file.copy()
			numberBodies = move prog.keptBodies
			return c
		none: pass
	c = prog.newChecker()
	c.enterScope()   # global scope (constants resolve through their declarations, see constTypeOf)
	c

# the stage's declarations and modules, those after c.freshDecls and c.freshModules, checked:
# their names and signatures, then the bodies and the instances they make; the last stage's
# program has its entry
fn checkStage(mut c Checker, last bool, entry str):
	c.receiversOpen = false
	c.checkDuplicateDecls()
	c.checkFromImports()
	c.checkDeclNames()
	c.checkBoundNames()
	c.resolveTypeAliases()
	c.definedTypeMethods()
	c.openReceivers()
	c.resolveSignatures()
	c.markDropTypes()
	c.checkFieldTypes()
	if last: c.checkEntryPoints(entry)
	c.openResults()   # a constant's value may call one
	c.receiversOpen = true
	n0 = c.decls.len
	for i in c.freshDecls..n0:
		d = c.decls[i]
		if nodes[d].kind == nConstDecl:
			c.constTypeOf(d)
	# generic functions and impls once at their definitions (bounds.zap), the other function and
	# method bodies, and the instances (each a copy of its generic's body, checked once with its
	# types for the backend, reporting nothing: the definition did). Instances appended while
	# checking (new generic types or calls) are picked up by the loops.
	c.checkBoundsAtDefinition()
	c.receiversDefined()
	c.checkBlockMethods()
	c.checkBodies()

# the bodies of the stage's functions and methods and of the instances, until checking them adds
# none
fn checkBodies(mut c Checker):
	declsDone = c.freshDecls
	instDone = c.freshInstances
	while declsDone < c.decls.len or instDone < c.instances.len or c.addDerived():
		while declsDone < c.decls.len:
			d = c.decls[declsDone]
			declsDone += 1
			k = nodes[d].kind
			if k == nFnDecl:
				if not c.bodyLeft(d): c.checkDeclBody(d)
			elif k == nImplDecl:
				if not nodes[d].names.isEmpty:
					if c.findTypeDecl(nodes[d].text) == none:
						errorAt(
							c,
							nodes[d].line,
							nodes[d].col,
							compileError("UnknownSelfType", ["{nodes[d].text2}"])
						)
					continue   # template: checked at its definition, its instances here
				failed = match nodes[d].origin:
					origin: origin in c.failedGenerics
					none: false
				if not failed and not c.bodyLeft(d):
					c.checkImplMethods(d)
		while instDone < c.instances.len:
			i = instDone
			instDone += 1
			if c.instances[i].fnDecl in c.failedGenerics:
				continue   # its definition's errors are reported
			# the active substitution is the checker's own; the instance keeps its lists. The
			# instance is read again after its body is checked, which may add instances.
			c.subst = c.instances[i].sub.copy()
			before = c.errors
			c.instances[i].checked = true
			c.checkFnBody(c.instances[i].decl, none, false)
			if c.errors > before:
				gi = c.instances[i]
				eprint("{gi.site}: note: the errors above are in {c.instanceName(gi)}, made by this call")
			c.subst = Subst(names = [], types = [])

# what reads the whole program once its stages are checked, then the program given back to its
# owner; whether it checks
fn checkWhole(mut c Checker, mut prog Program):
	whole = not bodiesPatchedOnly
	if whole: c.reportQuantityFields()
	c.checkProgramOrder()
	stage = factsStage(prog.stages)
	if stage is s and not c.factsMade: c.keptFacts = s.keptFactsOf()
	walked = c.keptFacts.isEmpty
	below = 0 if walked else (stage ?? fail("kept facts of no stage")).nodes
	c.checkInitCycles(below)
	c.checkRecursiveTypes()
	c.checkLentArguments()
	c.pauseArenaGlobalCalls()
	if not c.lentDone:
		c.findEffects()   # the lowering's ownership check judges with them
		c.lentDone = true
	c.findFnEffects(below)
	c.keptFacts = {}
	if stage is s and walked and c.errors == 0: s.keepFacts(c.facts)   # (no circle among them)
	if whole: c.checkNameRules()
	c.checkPromises()
	c.reportPending()
	c.exitScope()
	c.runTrials()
	c.resultState.clear()   # every body checked
	c.receiverState.clear()
	ok = c.errors == 0
	c.giveBack(prog)
	ok and (not whole or prog.finishShaders())   # their code once it checks

# The program's entry declared; in a together check (loadUnits) every source's main, each a
# program of its own, a missing one an error at its source's start.
fn checkEntryPoints(mut c Checker, entry str):
	units = c.modules.filter(.unit)
	if units.isEmpty and entry != "" and c.findFunc(entry) == none:
		eprint(compileError("NoEntryPoint", []))
		c.errors += 1
	for m in units:
		if c.findFunc("{m.prefix}main") == none:
			errorAtFile(m.file, 1, 1, compileError("NoEntryPoint", []))
			c.errors += 1

# the methods of impl d, of a type or an instance of a generic one (its substitution in names2
# and ints)
fn checkImplMethods(mut c Checker, d NodeId):
	implType = c.implTypeOf(d)
	c.enterModuleOf(d)
	if implType == none:
		c.errorAt(
			nodes[d].line,
			nodes[d].col,
			compileError("UnknownSelfType", ["{nodes[d].text2}"])
		)
	# the active substitution is the checker's own; the impl keeps its lists
	c.subst = Subst(names = nodes[d].names2().copy(), types = nodes[d].ints().copy())
	if not nodes[d].names2().isEmpty:
		for m in nodes[d].kids:
			c.resolveFnSignature(m)
	for m in nodes[d].kids:
		if c.resultState.get(m) == none and c.receiverState.get(m) == none:
			c.checkFnBody(m, implType, nodes[m].hasFlag(flagMut))
		elif (c.resultState.get(m) ?? -1) == resultOpen or
			(c.receiverState.get(m) ?? -1) == receiverOpen:
			c.checkOpenBody(m)
	c.subst = Subst(names = [], types = [])

# Parses the printing and encoding functions the noted types still lack (derive.zap) into
# a module of their own, `derive`, ready for checking (like any program code, so the ownership
# analysis covers them); whether there were any.
fn addDerived(mut c Checker):
	if c.errors > 0: return false
	text = c.deriveSource()
	if text == "": return false
	c.addDerivedText(text)
	true

# the module of the code the compiler writes, made on first use: its index
fn deriveModule(mut c Checker):
	m = moduleIndex(c.modules, "derive")
	if m >= 0: return m
	c.modules.push(
		Module(id = "derive", prefix = "derive__", file = "<derived>", imports = [], std = true)
	)
	c.modules.len - 1

fn derivedWord():
	TraceWord("derived", "the printing and encoding functions the compiler wrote")

# Functions the compiler wrote as source text, parsed into the `derive` module with their
# signatures resolved (their bodies are checked with the rest of the program).
fn addDerivedText(mut c Checker, text str):
	if derivedWord().on():
		eprint(text)   # the written functions, for inspection
	# the file name is written where it is stored: each place holds a string of its own
	parsed = parseInternal(text, "<derived>", nodes)
	m = c.deriveModule()
	savedMod = c.curMod
	savedFile = move c.curFile
	for d in parsed:
		nodes[d].declPart().mod = "derive"
		nodes[d].declPart().file = "<derived>"
		# the written name becomes the local name; the global one carries the module prefix
		nodes[d].text2 = move nodes[d].text
		nodes[d].text = c.modules[m].prefix + nodes[d].text2
		c.enterModuleOf(d)   # (its types are the names the derive module sees)
		c.resolveFnSignature(d)
		c.addDecl(d)
	c.curMod = savedMod
	c.curFile = savedFile

# how an instance reads in a message: name<T1, T2>
fn instanceName(c Checker, gi GenInst):
	"{nodes[gi.fnDecl].text2}<{gi.sub.types.map(c.showTy(it)).join(", ")}>"

# Instance i's body checked with its types, once: an instance the backend asked for after the
# checker's loop (rtMangle) is checked where it is first generated or inlined.
pub fn checkInstance(mut c Checker, i i64):
	if c.instances[i].checked: return
	c.instances[i].checked = true
	sav = move c.subst
	c.enterScope()
	c.subst = c.instances[i].sub.copy()   # the checker's own; the instance keeps its lists
	c.checkFnBody(c.instances[i].decl, none, false)
	c.exitScope()
	c.subst = sav
