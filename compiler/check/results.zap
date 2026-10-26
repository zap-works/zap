# Type checker, results: a function that writes no result has the type its `return`s and
# trailing expressions give (spec 5.1). Its body is checked when a caller first needs the result
# (checkBodyNow), once, the state of the body being checked put aside around it; the main loop
# then skips it. zap fmt writes a `pub` function's result found so (its module's contract), and
# checks a written one of a function that is not `pub` the same way (resultTrials.zap), dropping
# it where the body gives it alike.

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

resultOpen = 0   # not checked yet
resultChecking = 1
resultRecursive = 2   # being checked, and its result asked meanwhile
resultDone = 3

modeWritten = 0   # the result as written (none, a `pub` function's: it gives nothing)
modeInferred = 1
modeTrial = 2   # zap fmt: a copy of a body that writes its result checked as if it did not
modeGeneric = 3   # a generic's definition: it gives nothing unless it writes a result

# the state a body's check keeps in the checker, put aside while another body is checked
type BodyState:
	vars Var[]
	varIndex NameIndex
	scopeStarts i64[]
	currentRet TypeId?
	curFn NodeId?
	implType TypeId?
	curMod i64
	curFile str
	inferringRet bool
	inferRet TypeId?
	loopDepth i64
	matchStmt bool
	stmtExpr NodeId?
	valueTail NodeId?
	seqOk NodeId?
	mapExpected TypeId?
	weakExpected NodeId?
	lamStack NodeId[]
	lamBounds i64[]
	subst Subst
	gridLoops GridLoop[]
	retypes NodeId[]
	retypeTo TypeId[]
	relend bool
	round i64
	pending PendingError[]
	walkLets NodeId[]
	resultMode i64
	tailAgain bool
	trialFails bool
	openReturns NodeId[]
	openTries NodeId[]
	tryForms NodeId[]
	receiverChanged bool
	receiverSeen bool
	receiverUntold bool
	lenFacts LenFact[]   # (a scope that ends in the other body would end them)
	liveHandles LiveHandle[]
	lengthNames i64

# whether fnd writes no result and is a function whose body gives it: not the program's main,
# the runtime's nor the derived code's, with a body
fn resultUnwritten(c Checker, fnd NodeId):
	nodes[fnd].types().isEmpty and c.resultCandidate(fnd)

fn resultCandidate(c Checker, fnd NodeId):
	nodes[fnd].kind == nFnDecl and not nodes[fnd].hasFlag(flagExtern | flagGpu) and
		not nodes[fnd].sub().isEmpty and not nodes[fnd].text2().startsWith("$") and
		nodes[fnd].text2() != "main" and nodes[fnd].text != "main" and nodes[fnd].mod() != "rt" and
		nodes[fnd].mod() != "derive"

# The functions and the methods of plain impls whose bodies give their results, open before the
# bodies are checked (with zap fmt's notes on, the copies of those that write one: their trials)
fn openResults(mut c Checker):
	for d in c.decls[c.freshDecls..]:
		k = nodes[d].kind
		if k == nFnDecl and nodes[d].names().isEmpty:
			c.openResult(d, none)
		elif k == nImplDecl and nodes[d].names().isEmpty and nodes[d].origin() == none:
			for m in nodes[d].kids(kidIds).copy():
				c.openResult(m, d)

fn openResult(mut c Checker, fnd NodeId, impl NodeId?):
	if c.resultUnwritten(fnd):
		c.resultState[fnd] = resultOpen
		if impl is impl: c.methodImpl[fnd] = impl
	elif noting and c.resultCandidate(fnd) and not nodes[fnd].hasFlag(flagPub):
		c.trials.push(Trial(origin = fnd, copy = cloneTree(nodes, kidIds, fnd), impl))
	c.openLetTrial(fnd, impl)

# fnd's result asked: its body checked now when it is open, a call met while it is checked noted.
# A generic's definition check defers instead (made again once the result is known): false.
fn askResult(mut c Checker, fnd NodeId, state i64):
	if state == resultChecking:
		c.resultState[fnd] = resultRecursive
	elif state == resultOpen and not c.atDefinition:
		c.checkBodyNow(fnd)
	elif state == resultOpen:
		c.earlyResults.push(fnd)
		c.deferred = true
		return false
	true

# a function's body in the checker's loop, once: none when a caller needed its result first
fn checkDeclBody(mut c Checker, d NodeId):
	match c.resultState.get(d):
		state:
			if state == resultOpen: c.checkOpenBody(d)
		none:
			c.fillRowFunction(d)
			if nodes[d].names().isEmpty: c.checkFnBody(d, none, false)

# an open body checked: one whose result it gives, or a block's method whose receiver it tells
# (receivers.zap), or both
fn checkOpenBody(mut c Checker, fnd NodeId):
	result = c.resultState.get(fnd) != none
	receiver = c.receiverState.get(fnd) != none
	if result: c.resultState[fnd] = resultChecking
	if receiver: c.receiverState[fnd] = receiverChecking
	match c.methodImpl.get(fnd):
		impl: c.checkFnBody(fnd, c.implTypeOf(impl), nodes[fnd].hasFlag(flagMut))
		none: c.checkFnBody(fnd, none, false)
	if result: c.resultState[fnd] = resultDone
	if receiver: c.receiverState[fnd] = receiverDone

# fnd's body checked in the middle of another's: the other's state put aside meanwhile, its
# round's errors kept for it (they come back if it is checked again)
fn checkBodyNow(mut c Checker, fnd NodeId):
	saved = c.putBodyAside()
	before = c.errors
	c.enterScope()
	c.checkOpenBody(fnd)
	c.exitScope()
	c.errorsKept += c.errors - before
	c.takeBodyBack(saved)

fn putBodyAside(mut c Checker):
	saved = BodyState(
		vars = move c.vars,
		varIndex = move c.varIndex,
		scopeStarts = move c.scopeStarts,
		currentRet = c.currentRet,
		curFn = c.curFn,
		implType = c.implType,
		curMod = c.curMod,
		curFile = move c.curFile,
		inferringRet = c.inferringRet,
		inferRet = c.inferRet,
		loopDepth = c.loopDepth,
		matchStmt = c.matchStmt,
		stmtExpr = c.stmtExpr,
		valueTail = c.valueTail,
		seqOk = c.seqOk,
		mapExpected = c.mapExpected,
		weakExpected = c.weakExpected,
		lamStack = move c.lamStack,
		lamBounds = move c.lamBounds,
		subst = move c.subst,
		gridLoops = move c.gridLoops,
		retypes = move c.retypes,
		retypeTo = move c.retypeTo,
		relend = c.relend,
		round = c.round,
		pending = move c.pending,
		walkLets = move c.walkLets,
		resultMode = c.resultMode,
		tailAgain = c.tailAgain,
		trialFails = c.trialFails,
		openReturns = move c.openReturns,
		openTries = move c.openTries,
		tryForms = move c.tryForms,
		receiverChanged = c.receiverChanged,
		receiverSeen = c.receiverSeen,
		receiverUntold = c.receiverUntold,
		lenFacts = move c.lenFacts,
		liveHandles = move c.liveHandles,
		lengthNames = c.lengthNames
	)
	c.vars = []
	c.varIndex = NameIndex()
	c.scopeStarts = []
	c.curFile = ""
	c.lamStack = []
	c.lamBounds = []
	c.subst = Subst(names = [], types = [])
	c.gridLoops = []
	c.retypes = []
	c.retypeTo = []
	c.pending = []
	c.walkLets = []
	c.openReturns = []
	c.openTries = []
	c.tryForms = []
	c.lenFacts = []
	c.liveHandles = []
	c.lengthNames = 0
	c.inferringRet = false
	c.matchStmt = false
	c.stmtExpr = none
	c.valueTail = none
	c.seqOk = none
	c.mapExpected = none
	c.weakExpected = none
	c.relend = false
	c.receiverChanged = false
	c.receiverSeen = false
	c.receiverUntold = false
	saved

fn takeBodyBack(mut c Checker, move saved BodyState):
	c.vars = move saved.vars
	c.varIndex = move saved.varIndex
	c.scopeStarts = move saved.scopeStarts
	c.currentRet = saved.currentRet
	c.curFn = saved.curFn
	c.implType = saved.implType
	c.curMod = saved.curMod
	c.curFile = move saved.curFile
	c.inferringRet = saved.inferringRet
	c.inferRet = saved.inferRet
	c.loopDepth = saved.loopDepth
	c.matchStmt = saved.matchStmt
	c.stmtExpr = saved.stmtExpr
	c.valueTail = saved.valueTail
	c.seqOk = saved.seqOk
	c.mapExpected = saved.mapExpected
	c.weakExpected = saved.weakExpected
	c.lamStack = move saved.lamStack
	c.lamBounds = move saved.lamBounds
	c.subst = move saved.subst
	c.gridLoops = move saved.gridLoops
	c.retypes = move saved.retypes
	c.retypeTo = move saved.retypeTo
	c.relend = saved.relend
	c.round = saved.round
	c.pending = move saved.pending
	c.walkLets = move saved.walkLets
	c.resultMode = saved.resultMode
	c.tailAgain = saved.tailAgain
	c.trialFails = saved.trialFails
	c.openReturns = saved.openReturns
	c.openTries = saved.openTries
	c.tryForms = saved.tryForms
	c.receiverChanged = saved.receiverChanged
	c.receiverSeen = saved.receiverSeen
	c.receiverUntold = saved.receiverUntold
	c.lenFacts = move saved.lenFacts
	c.liveHandles = move saved.liveHandles
	c.lengthNames = saved.lengthNames

# how fnd's body, about to be checked, gives its result
fn resultModeOf(c Checker, fnd NodeId):
	if c.trialCopy == fnd: return modeTrial
	if c.resultState.get(fnd) != none: return modeInferred
	if c.atDefinition and c.resultUnwritten(fnd): return modeGeneric
	modeWritten

# A return of a function whose result is being found: the first value fixes the type, every other
# gives the same (never widened to it). A trailing expression that is no value (a call of `()`, a
# call that changes an argument or its receiver, whose value may go unused, a call after returns
# of nothing) is a statement; one whose only errors are a value's (a match of arms of different
# types) is checked again as one.
fn checkResultReturn(mut c Checker, s NodeId, line i64, col i64, hasValue bool):
	fnd = c.curFn ?? return
	name = nodes[fnd].text2().copy()
	if not hasValue:
		if c.inferRet is t and c.tKind(t) != tUnit:
			c.errorAt(line, col, compileError("ResultsDiffer", ["{name}", "()", "{c.showTy(t)}"]))
		c.inferRet = c.inferRet ?? tyUnit
		return
	value = nodes[s].kids(kidIds)[0]
	if c.inferRet == none and c.untoldValue(value):
		if nodes[value].kind == nMatch:
			c.errorAt(line, col, compileError("ResultUntold", ["{name}"]))   # (a choice is checked once)
			c.inferRet = tyError
		else:
			c.openReturns.push(s)   # the type the other returns give (settleOpenReturns)
		return
	before = c.errors
	valueBefore = c.valueOnlyErrors
	c.resultValue = value   # (kept: the conversions of its operands are met again as the result settles)
	vt = c.checkExpr(value, c.inferRet)
	made = c.errors - before
	asValue = made > 0 and made <= c.valueOnlyErrors - valueBefore
	if nodes[s].ival == 2 and c.tailIsStatement(s, value, vt, asValue): return
	if c.resultMode == modeTrial and nodes[value].hasFlag(flagWidenCandidate):
		c.trialFails = true   # the written result lets its conversion go (canon.zap): it stays
	if c.tKind(vt) == tError: return
	if c.tKind(vt) == tRef:
		vt = innerOf(tys, vt)   # a value, as a written result's: what the reference points to
		madeKid = c.coerceTo(value, vt)
		nodes[s].setKid(kidIds, 0, madeKid)
	held = c.heldType(vt)
	match c.inferRet:
		t:
			if not isSameType(tys, held, t):
				c.errorAt(
					line,
					col,
					compileError("ResultsDiffer", ["{name}", "{c.showTy(vt)}", "{c.showTy(t)}"])
				)
				return
		none:
			c.keepConversion(nodes[s].kids(kidIds)[0])   # the result's type comes from it
			if c.isOptionOfRef(held):
				c.errorAt(
					line,
					col,
					compileError("ResultReference", ["{name}", "{c.showTy(held)}"])
				)
				c.inferRet = tyError
				return
			c.inferRet = held
	if not isSameType(tys, vt, held):
		c.coerceKid(s, 0, held)
	if c.tKind(held) == tFloat and tys[held].bits == 64 and c.widensToF64(nodes[s].kids(kidIds)[0]):
		c.errorAt(line, col, compileError("ResultWidened", ["{name}"]))

# `none`, an empty list or map, a choice of one (`none if c else x`): a value whose type only its
# place tells
fn untoldValue(c Checker, e NodeId) bool:
	k = nodes[e].kind
	if k == nMatch:
		for arm in c.matchArms(e):
			if c.armValue(arm) is v and c.untoldValue(v): return true
		return false
	k == nNone or (k == nArray or k == nMapLit) and nodes[e].kids(kidIds).isEmpty

# The returns of untold values once the body is checked: of the type the others gave, or an error
# asking for the result when none gave one
fn settleOpenReturns(mut c Checker):
	fnd = c.curFn ?? return
	for s in c.openReturns:
		value = nodes[s].kids(kidIds)[0]
		line = nodes[s].line
		col = nodes[s].col
		match c.inferRet:
			t:
				vt = c.checkExpr(value, t)
				if isAssignable(tys, vt, t):
					madeKid = c.coerceTo(value, t)
					nodes[s].setKid(kidIds, 0, madeKid)
				else:
					c.errorAt(
						line,
						col,
						compileError(
							"ResultsDiffer",
							["{nodes[fnd].text2()}", "{c.showTy(vt)}", "{c.showTy(t)}"]
						)
					)
			none:
				c.errorAt(line, col, compileError("ResultUntold", ["{nodes[fnd].text2()}"]))
				c.inferRet = tyError
	c.openReturns.clear()

# whether the body being checked gives its function's result (not a lambda's): a try in it passes
# up to the result found (settleOpenTries)
fn findingResult(c Checker):
	c.inferringRet and c.lamStack.isEmpty and c.resultMode != modeWritten

# The tries of a body once its result is found: an optional's needs an optional result, a
# result's one with its error
fn settleOpenTries(mut c Checker):
	t = c.inferRet ?? tyUnit
	for e in c.openTries:
		c.checkTryResult(e, typeOf(nodes, nodes[e].kids(kidIds)[0]), t)
	c.openTries.clear()
	if c.tKind(t) == tOption:
		for e in c.tryForms:
			c.noteTryForm(e)
	c.tryForms.clear()

# whether t holds no error type (an untold part)
fn typeKnown(c Checker, t TypeId) bool:
	if c.tKind(t) == tError: return false
	if tys[t].inner is inner and not c.typeKnown(inner): return false
	if tys[t].val is val and not c.typeKnown(val): return false
	true

# whether the implicit return s of value (checked as vt, with errors or not) is a statement: made
# one again (a trial, which keeps the written form, fails instead)
fn tailIsStatement(mut c Checker, s NodeId, value NodeId, vt TypeId, failed bool):
	afterNothing = c.inferRet == tyUnit and nodes[value].kind == nCall
	if not failed and c.tKind(vt) != tUnit and not afterNothing and not c.actsOnly(value):
		return false
	if c.resultMode == modeTrial:
		c.trialFails = true
		return true
	nodes[s].kind = nExprStmt
	nodes[s].ival = 0
	c.tailAgain = c.tailAgain or failed
	true

# A body whose result is found, ending in an if/else or a match a branch of which gives nothing
# and with no `return` of a value: the branches' trailing values made statements (spec 5.1), so
# it gives nothing. Whether there were any.
fn tailOfStatements(mut c Checker, body NodeId):
	if c.holdsValueReturn(body): return false
	tails = []
	c.implicitTails(body, tails)
	for r in tails:
		nodes[r].kind = nExprStmt
		nodes[r].ival = 0
	not tails.isEmpty

# the implicit returns (markImplicitReturns) ending block b's trailing if/else or match
fn implicitTails(c Checker, b NodeId, mut out NodeId[]):
	if nodes[b].kids(kidIds).isEmpty: return
	last = nodes[b].kids(kidIds)[nodes[b].kids(kidIds).len - 1]
	k = nodes[last].kind
	if k == nIf:
		for s in nodes[last].sub():
			c.branchTails(s, out)
	elif k == nExprStmt and nodes[nodes[last].kids(kidIds)[0]].kind == nMatch:
		e = nodes[last].kids(kidIds)[0]
		for i in 1..nodes[e].kids(kidIds).len:
			if not nodes[nodes[e].kids(kidIds)[i]].sub().isEmpty:
				c.branchTails(nodes[nodes[e].kids(kidIds)[i]].sub()[0], out)

# a branch's block: its implicit return, or those of its own trailing if/else or match
fn branchTails(c Checker, b NodeId, mut out NodeId[]):
	if nodes[b].kids(kidIds).isEmpty: return
	last = nodes[b].kids(kidIds)[nodes[b].kids(kidIds).len - 1]
	if nodes[last].kind == nReturn and nodes[last].ival == 2:
		out.push(last)
	else:
		c.implicitTails(b, out)

# whether e holds a written `return` of a value outside its lambdas
fn holdsValueReturn(c Checker, e NodeId) bool:
	k = nodes[e].kind
	if k == nLambda: return false
	if k == nReturn and nodes[e].ival != 2 and not nodes[e].kids(kidIds).isEmpty: return true
	nodes[e].kids(kidIds).any(c.holdsValueReturn(it)) or nodes[e].sub().any(c.holdsValueReturn(it))

# whether e is a call that changes an argument or its receiver (effects.zap), or a choice of which
# one such call is (a match's arm, the fallback of ??)
fn actsOnly(c Checker, e NodeId) bool:
	k = nodes[e].kind
	if k == nMatch:
		for arm in c.matchArms(e):
			if c.armValue(arm) is v and c.actsOnly(v): return true
		return false
	if k == nBinary and nodes[e].ival == binCoalesce: return c.actsOnly(nodes[e].kids(kidIds)[1])
	changes = []
	c.noteChange(e, changes)
	not changes.isEmpty

# whether the f64 e is an integer widened (`a * 1.5` of an i64 a): a typo that would make a
# function and its callers float ones, refused unless the result is written
fn widensToF64(c Checker, e NodeId) bool:
	k = nodes[e].kind
	if k == nCall and nodes[e].hasFlag(flagAutoWiden):
		callee = nodes[e].kids(kidIds)[0]
		return nodes[callee].text == "toF64" and nodes[nodes[callee].kids(kidIds)[0]].kind != nInt
	(k == nBinary or k == nUnary) and nodes[e].kids(kidIds).any(c.widensToF64(it))

# The end of the last round of a body whose result it gives: the result found kept (written
# into the declaration) or refused; a trial's compared with the written one. Whether the body
# goes again.
fn settleResult(mut c Checker, fnd NodeId, restoreTo i64):
	t = c.inferRet ?? tyUnit
	name = nodes[fnd].text2().copy()
	gives = c.tKind(t) != tUnit and c.tKind(t) != tError
	recursive = (c.resultState.get(fnd) ?? -1) == resultRecursive
	if c.resultMode == modeTrial:
		same = isSameType(tys, t, c.writtenResult(fnd)) and c.typeKnown(t)
		c.trialAlike = c.errors == restoreTo and not c.trialFails and same
		return false
	if c.resultMode == modeGeneric:
		if gives:
			c.errorAt(
				nodes[fnd].line,
				nodes[fnd].col,
				compileError("GenericResult", ["{name}", "{c.showTy(t)}"])
			)
			c.writeResult(fnd, tyError)   # its calls are not reported again
		return false
	res = t
	if gives and not c.typeKnown(t) and c.errors == restoreTo:
		c.errorAt(nodes[fnd].line, nodes[fnd].col, compileError("ResultUntold", ["{name}"]))
		res = tyError
	if recursive and gives:
		# its calls of itself read as giving nothing: what that made them is not reported
		c.pending.clear()
		c.errors = restoreTo
		c.errorAt(
			nodes[fnd].line,
			nodes[fnd].col,
			compileError("ResultRecursive", ["{name}", "{c.showTy(t)}"])
		)
		res = tyError
	if c.tKind(res) != tUnit:
		c.writeResult(fnd, res)
		c.rejectForwardingConstructor(fnd)
		if nodes[fnd].hasFlag(flagPub) and c.tKind(res) != tError: c.noteResultWritten(fnd, res)
	false

# the result found for fnd written into its declaration, which the passes after read
fn writeResult(mut c Checker, fnd NodeId, t TypeId):
	te = c.typeToTE(t)
	nodes[te].flags |= flagInternal   # found, not written
	nodes[fnd].nodePart().types.push(te)

# zap fmt: the result t a `pub` function's body gives written after its parameters, where the
# file can name its types (sourceType)
fn noteResultWritten(mut c Checker, fnd NodeId, t TypeId):
	if not noting: return
	text = c.sourceType(t) ?? return
	src = c.file if c.curFile == "" else c.curFile
	if paramsEnd(src, nodes[fnd].line, nodes[fnd].col) is ends:
		line, close = ends
		c.canonNote(noteReplace, line, close + 2, 0, " {text}")

# zap fmt: the written result of fnd, which its body gives alike, dropped
fn noteResultDropped(mut c Checker, fnd NodeId):
	if not noting: return
	src = c.file if c.curFile == "" else c.curFile
	if resultSpan(src, nodes[fnd].line, nodes[fnd].col) is span:
		line, col, cut = span
		c.canonNote(noteReplace, line, col, cut, "")
