# The lowering of a function and of the inlining of calls (irlower.zap).

alias nodes = g.c.nodes
alias tys = g.c.types

# the function fnd lowered (lw.ok false when it cannot be)
fn irLowerFunction(mut g Gen, fnd NodeId, implType TypeId?, entry bool):
	lw = IrLower(f = newIrFn(), fnd, names = [], vals = [], breaks = [], conts = [])
	lw.ofRuntime = g.irOfRuntime(fnd)
	g.irDecide(fnd, implType)
	if not g.irCallable(fnd, not g.c.subst.names.isEmpty) or nodes[fnd].sub.isEmpty:
		lw.irFail(g.irSignatureWhy(fnd))
		return lw
	if implType is implType and not g.irIsPlaceStruct(implType) and
		not g.irIsAggregate(implType) and
		not g.irIsCarryingEnum(implType):
		lw.irFail("signature: this of {g.irKindName(implType)}")
		return lw
	plan = g.irArgPlan(fnd, implType != none, implType)
	regArgs = plan != none
	rt = g.c.fnRetType(fnd)
	lw.rt = rt
	lw.regResult = regArgs and g.irResultClasses(rt) != none
	# a result that is not a scalar: written at the address the caller pushes last
	extra = 0 if g.c.isScalar(rt) or lw.regResult else 1
	if extra == 1:
		lw.hidden = lw.irDef(irInt, IrInst(op = irParam, imm = 0))
	params = nodes[fnd].kids.copy()
	# each parameter's words on the stack: one, or a given value's
	words = params.map(p:
		pt = g.c.resolveType(nodes[p].types[0])
		g.sizeOf(pt).alignUp(8) / 8 if g.irGiven(pt, nodes[p].ival) or
			g.irMovedWords(pt, nodes[p].ival)
			else 1
	)
	if implType is implType:
		g.irLowerFunctionReceiver(lw, fnd, implType, plan, words, extra)
	first = 1 if implType != none else 0   # the first parameter's place in the plan
	for i in 0..params.len:
		g.irLowerFunctionParam(lw, params, i, words, extra, plan, first)
	lw.f.irParamsFirst()
	g.irGivensAtEntry(lw, params)   # this instance was made for them
	lw.firstLocal = lw.names.len
	tail = g.irTailType(nodes[fnd].sub[0])
	result = irAsResult(
		g,
		lw,
		rt,
		tail ?? tyUnit,
		g.irBlockValue(lw, nodes[fnd].sub[0], g.irBodyGivesValue(rt, nodes[fnd].sub[0]))
	)
	if entry and not lw.f.irEnded() and lw.ok:
		# the program's end: its locals go to the system with it (unless the leaks are counted)
		g.irCallRt(lw, "endWithoutTeardown", [])
	if not lw.f.irEnded() and lw.ok:
		if result.isEmpty and g.tyK(rt) != tUnit and g.c.blockTerminates(nodes[fnd].sub[0]):
			g.irLeave(lw, -1)   # past an endless loop, no value: the code here runs never
		else:
			g.irFunctionResult(lw, result, rt)
	lw

fn irLowerFunctionReceiver(
	mut g Gen,
	mut lw IrLower,
	fnd NodeId,
	implType TypeId,
	plan bool[]?,
	words i64[],
	extra i64
):
	lw.thisType = implType
	regArgs = plan != none
	if irSpreadIn(plan, 0):
		lw.irDeclare("self", g.irSpreadParam(lw, implType))   # its leaves in registers
		return
	# the receiver's address, pushed first: a place struct used where it
	# is, a struct of numbers read into leaves (written back by a mut method)
	selfAt = lw.f.irVreg(irInt)
	irPut(
		lw,
		IrInst(
			op = irParam,
			dst = selfAt,
			imm = 0 if regArgs else words.sum() + extra,
			regArgs
		)
	)
	if g.irIsAggregate(implType):
		leaves = g.irLoadValue(lw, implType, selfAt, -1, 0)
		if nodes[fnd].hasFlag(flagMut):
			lw.mutScalars.push(IrMutScalar(selfAt, leaves.copy(), implType))
		lw.irDeclare("self", leaves)
	else:
		lw.irDeclare("self", [selfAt])

fn irLowerFunctionParam(
	mut g Gen,
	mut lw IrLower,
	params NodeId[],
	i i64,
	words i64[],
	extra i64,
	plan bool[]?,
	first i64
):
	regArgs = plan != none
	pt = g.c.resolveType(nodes[params[i]].types[0])
	after = words[i + 1..].sum() + extra   # the words pushed after it
	if irSpreadIn(plan, first + i):
		lw.irDeclare(nodes[params[i]].text, g.irSpreadParam(lw, pt))   # its leaves in registers
		return
	if g.irGiven(pt, nodes[params[i]].ival):
		at = lw.irDef(irInt, IrInst(op = irFrameAddr, imm = 16 + 8 * after))
		lw.irOwnBegin(
			IrOwned(slot = at, t = pt, name = lw.names.len, key = nodes[params[i]].text.copy())
		)
		lw.irDeclare(nodes[params[i]].text, [at])
		return
	if g.irMovedWords(pt, nodes[params[i]].ival):
		at = lw.irDef(irInt, IrInst(op = irFrameAddr, imm = 16 + 8 * after))
		irDeclare(   # its leaves, from the stack
			lw,
			nodes[params[i]].text,
			[at] if g.irMovedPlace(pt, nodes[params[i]].ival) else g.irLoadValue(lw, pt, at, -1, 0)
		)
		return
	changed = g.irMutScalar(pt, nodes[params[i]].ival)
	lent = g.irLentAsCopy(pt) and not changed   # passed by its address: its leaves read here
	v = lw.f.irVreg(irInt if g.irByAddress(pt) or lent or changed else g.irClassOf(pt))   # a list: its address
	# a register argument's register, else the stack slot's distance from the last one
	irPut(
		lw,
		IrInst(
			op = irParam,
			dst = v,
			imm = 0 if regArgs else after,   # (a register's: irParamsFirst)
			regArgs,
			size = 4 if g.irIsF32(pt) else 8
		)
	)
	if changed:
		value = g.irLoadValue(lw, pt, v, -1, 0)
		lw.mutScalars.push(IrMutScalar(v, value.copy(), pt))
		lw.irDeclare(nodes[params[i]].text, value)
		return
	lw.irDeclare(nodes[params[i]].text, g.irLoadValue(lw, pt, v, -1, 0) if lent else [v])
	if nodes[params[i]].ival == modeMove and g.irIsOwnedWord(pt):
		g.irOwnedWord(lw, pt, v)   # a map moved in: this function's to drop
		lw.irNameOwned(lw.owned.len - 1, lw.names.len - 1, nodes[params[i]].text)

# a read value of type t spread over the registers: its leaves, each a parameter
fn irSpreadParam(mut g Gen, mut lw IrLower, t TypeId):
	g.irLeafTypes(t).map(leaf:
		v = g.irLeafVreg(lw, leaf)
		lw.irPut(IrInst(op = irParam, dst = v, regArgs = true))
		v
	)

# whether a call of fnd is lowered as its body: small, not generic, recursive one level deep
fn irInlines(mut g Gen, lw IrLower, fnd NodeId) bool:
	g.irInlinesAs(lw, fnd, false)

# the same for an instance of a generic function
fn irInlinesAs(mut g Gen, lw IrLower, maybeFnd NodeId?, instance bool):
	fnd = maybeFnd ?? return false
	if nodes[fnd].kind != nFnDecl or (not nodes[fnd].names.isEmpty and not instance) or
		nodes[fnd].hasFlag(flagExtern) or nodes[fnd].sub.isEmpty:
		return false
	g.c.readBody(fnd)
	if g.irEndsProcess(fnd) or g.irEndsProcess(lw.fnd ?? fnd): return false
	callee = g.irOfRuntime(fnd)
	# the code the compiler writes (derive) calls the runtime as the runtime does
	inRuntime = (g.irInRuntime(lw) or g.irInDerived(lw)) if lw.rets.isEmpty
		else lw.rets[len - 1].runtime
	runtime = inRuntime and callee
	# a runtime body with a loop that allocates nothing (a probe, a heap's sift), called in a loop
	# of the program's (or by a body inlined for a call the program wrote there): the loops of
	# both in one function. (One that allocates spends its time there, not in the call.)
	byProgram = g.irInProgram(lw) if lw.rets.isEmpty else lw.rets[len - 1].written
	inLoop = not lw.breaks.isEmpty
	loops = g.holdsKind(nodes[fnd].sub[0], nWhile, nFor, false)
	hot = callee and byProgram and inLoop and loops and g.c.fnDoes(fnd) & doesAllocate == 0
	# a body with no loop, called in a loop of the program's: its work and values in that loop's
	# registers, and the runtime's calls in it lowered as the program's own (a runtime body only
	# when it gives nothing: one that gives a value may move it by hand, which the program's
	# ownership check would not follow)
	looped = byProgram and inLoop and not loops and (not callee or nodes[fnd].types.isEmpty)
	# a key part's call, made at every comparison of a sort: the program's function in place, as a
	# hot body (a part calls no loop: irCheapPart)
	keyed = lw.keyParts > 0 and not callee
	depth = irHotInlineDepth if hot
		else irRuntimeInlineDepth if runtime or callee or looped or keyed
		else irInlineDepth
	inlined = lw.rets.count(not .lambda)   # the bodies inlined around (a lambda's is none)
	# a recursive function's call of itself: one level of its body in place, its calls there calls
	# (not one whose call of itself is a statement's whole: a tail call, a loop, stays one)
	if fnd == lw.fnd and (inlined > 0 or g.callsItselfWhole(fnd, nodes[fnd].sub[0])): return false
	if g.givesItsOwnLocal(fnd): return false
	if inlined >= depth or lw.errorOut > 0:
		# a runtime body of a few nodes that calls nothing goes in at any depth (`markOf`): its call
		# costs more
		return callee and g.irNodeCount(nodes[fnd].sub[0], irTinyNodes + 1) <= irTinyNodes and
			g.irCallFree(nodes[fnd].sub[0])
	most = irHotInlineNodes if hot or keyed
		else irLoopInlineNodes if looped or fnd == lw.fnd
		else irProgramInlineNodes if not callee or byProgram and not inLoop and not g.irHasLoop(lw)
		else irInlineNodes if not runtime
		else irRuntimeInlineNodes if inlined == 0
		else irRuntimeNestedNodes
	# (a tiny runtime body that calls nothing goes in whatever the limit: its call costs more)
	count = g.irNodeCount(nodes[fnd].sub[0], most.max(irTinyNodes) + 1)
	if callee and count <= irTinyNodes and g.irCallFree(nodes[fnd].sub[0]): return true
	if count > most and irInlineWord().on():
		g.irSay("ir: {nodes[fnd].text} not inlined: over {most} nodes ({count} counted)")
	count <= most and (lw.inlined <= irInlineBlocks or g.irCallFree(nodes[fnd].sub[0]))

# whether the function being lowered has a loop (its registers go to the loop first: a runtime
# body inlined before it only crowds them)
fn irHasLoop(mut g Gen, lw IrLower):
	fnd = lw.fnd ?? return true
	g.holdsKind(nodes[fnd].sub[0], nWhile, nFor, false) if not nodes[fnd].sub.isEmpty else false

# whether fnd gives a reference (or a window) to a local of its own (listBytes' window `w`): its
# call copies the local out as the result, a body inlined would leave the reference pointing at a
# local its end empties
fn givesItsOwnLocal(mut g Gen, fnd NodeId):
	# (the result as written: a generic one's type is not known outside its instances)
	if nodes[fnd].types.isEmpty or nodes[nodes[fnd].types[0]].kind != nTyRef: return false
	body = nodes[fnd].sub[0]
	locals = []
	for st in nodes[body].kids:
		if nodes[st].kind == nLet: locals.push(nodes[st].text.copy())
	g.returnsName(body, locals)

# whether a return in e (the body's last expression is one, as the checker makes it) gives one of
# the names, or a reference to one
fn returnsName(g Gen, e NodeId, names str[]) bool:
	if nodes[e].kind == nReturn and not nodes[e].kids.isEmpty:
		r = nodes[e].kids[0]
		while nodes[r].kind == nDeref or nodes[r].kind == nUnary and
			(nodes[r].ival == unRef or nodes[r].ival == unMutRef):
			r = nodes[r].kids[0]
		return nodes[r].kind == nIdent and nodes[r].text in names
	nodes[e].kids.any(g.returnsName(it, names)) or nodes[e].sub.any(g.returnsName(it, names))

# whether e holds a call of fnd that is a statement's or a return's whole expression
fn callsItselfWhole(g Gen, fnd NodeId, e NodeId) bool:
	if (nodes[e].kind == nReturn or nodes[e].kind == nExprStmt) and not nodes[e].kids.isEmpty:
		call = nodes[e].kids[0]
		if nodes[call].kind == nCall and nodes[nodes[call].kids[0]].kind == nIdent and
			nodes[nodes[call].kids[0]].text == nodes[fnd].text:
			return true
	nodes[e].kids.any(g.callsItselfWhole(fnd, it)) or nodes[e].sub.any(g.callsItselfWhole(fnd, it))

# whether code makes no call once lowered: its calls are conversions, wraps, the runtime's
# intrinsics (`__ld32`), an integer's methods made in place, and the runtime's tiny bodies that
# call nothing so (inlined at any depth: irInlinesAs), a map's `table(m)` in its value's reader
fn irCallFree(mut g Gen, e NodeId) bool:
	g.irCallFreeAt(e, 0)

fn irCallFreeAt(mut g Gen, e NodeId, depth i64) bool:
	if nodes[e].kind == nCall:
		callee = nodes[e].kids[0]
		name = nodes[callee].text
		inPlace = nodes[e].hasFlag(flagWrap) or g.c.isConversionCall(e) or
			nodes[callee].kind == nIdent and
			name.startsWith("__") or nodes[callee].kind == nField and
			(
				name in intConversions or name in intBitMethods or name in bitFieldMethods or
					name in ["toF32", "toF64", "min", "max"] or
					name in ["len", "isEmpty"] and
					g.tyK(g.ty(nodes[callee].kids[0])) in [tList, tStr] or
					name == "take" and nodes[e].hasFlag(flagInternal)   # a `move xs[i]`
			)
		if not inPlace and nodes[callee].kind == nIdent and depth < irCallFreeDepth and
			g.c.calleeDecl(e) is d and nodes[d].kind == nFnDecl and g.irOfRuntime(d) and
			not nodes[d].sub.isEmpty:
			g.c.readBody(d)
			body = nodes[d].sub[0]
			inPlace = g.irNodeCount(body, irTinyNodes + 1) <= irTinyNodes and
				g.irCallFreeAt(body, depth + 1)
		if not inPlace: return false
	for kid in nodes[e].kids.copy():
		if not g.irCallFreeAt(kid, depth): return false
	for sb in nodes[e].sub.copy():
		if not g.irCallFreeAt(sb, depth): return false
	true

irCallFreeDepth = 2   # the tiny bodies a call-free one is followed into

# Whether fnd is on the way out of the process: one that stops the program (endsProgram), or one
# of the runtime's that reports a stop (the crash filter). That way is cold: a call into it stays
# a call, and nothing is inlined into its body.
fn irEndsProcess(mut g Gen, fnd NodeId):
	if endsProgram(nodes[fnd].text): return true
	if not g.irOfRuntime(fnd) or nodes[fnd].sub.isEmpty: return false
	match g.irReporters.get(fnd):
		known: known
		none:
			g.c.readBody(fnd)
			reports = g.irCallsStopWith(nodes[fnd].sub[0])
			g.irReporters[fnd] = reports
			reports

fn irCallsStopWith(g Gen, e NodeId) bool:
	if nodes[e].kind == nCall and nodes[nodes[e].kids[0]].kind == nIdent and
		nodes[nodes[e].kids[0]].text == "rt__stopWith":
		return true
	nodes[e].kids.any(g.irCallsStopWith(it)) or nodes[e].sub.any(g.irCallsStopWith(it))

# whether the function being lowered is the runtime's
fn irInRuntime(g Gen, lw IrLower):
	fnd = lw.fnd ?? return false
	g.irOfRuntime(fnd)

# `__window(x) == k`'s value, which x's type decides, or none for another condition
fn irWindowTest(mut g Gen, cond NodeId) bool?:
	if nodes[cond].kind != nBinary or nodes[cond].ival != binEq: return none
	call = nodes[cond].kids[0]
	k = nodes[cond].kids[1]
	if nodes[call].kind != nCall or nodes[k].kind != nInt or
		nodes[nodes[call].kids[0]].kind != nIdent or
		nodes[nodes[call].kids[0]].text != "__window" or nodes[call].kids.len != 2:
		return none
	(1 if g.isTextWindow(g.ty(nodes[call].kids[1])) else 0) == g.intLitValue(k)

# whether the function being lowered is the program's entry
fn irLowersEntry(g Gen, lw IrLower):
	fnd = lw.fnd ?? return false
	g.isEntry(nodes[fnd].text)

# whether the function of that global name is an entry: the program's, or a together check's
# source's main (each a program of its own)
fn isEntry(g Gen, name str):
	name == g.entry or isUnitMain(g.c.modules, name)

# whether the function being lowered is the program's (not the runtime's, not a lambda)
fn irInDerived(g Gen, lw IrLower):
	fnd = lw.fnd ?? return false
	nodes[fnd].mod() == "derive"

fn irInProgram(g Gen, lw IrLower):
	fnd = lw.fnd ?? return false
	not g.irOfRuntime(fnd)

# whether fnd is the runtime's (its module rt: a function or a method of a runtime type)
fn irOfRuntime(g Gen, fnd NodeId):
	nodes[fnd].mod() == "rt"

# the nodes under e, counted up to cap (a widening the checker put in is no node: it makes no code)
fn irNodeCount(mut g Gen, e NodeId, cap i64) i64:
	if nodes[e].kind == nCall and nodes[e].hasFlag(flagAutoWiden):
		return g.irNodeCount(nodes[nodes[e].kids[0]].kids[0], cap)
	if nodes[e].kind == nIf and g.irWindowTest(nodes[e].kids[0]) is taken:
		# a branch the key's type decides (the runtime's maps): only the one lowered counts
		if taken: return 1 + g.irNodeCount(nodes[e].sub[0], cap)
		return 1 + (g.irNodeCount(nodes[e].sub[1], cap) if nodes[e].sub.len > 1 else 0)
	n = 1
	for k in nodes[e].kids:
		if n > cap: return n
		n += g.irNodeCount(k, cap)
	for k in nodes[e].sub:
		if n > cap: return n
		n += g.irNodeCount(k, cap)
	n

# where the lowering stands, to go back to when an inlined body cannot be lowered (it only
# adds blocks, loops, vregs, instructions of the block being filled and, in a region, reads of
# the frame to block 0)
type IrMark:
	blocks i64
	loops i64
	entry i64   # block 0's instructions
	owned i64
	classes i64
	cur i64
	insts i64
	names i64
	rets i64
	breaks i64
	floor i64
	thisType TypeId?
	literals i64
	literalWords i64
	made i64
	raw i64
	lambdas i64   # the lambda bodies lowered so far (irLambdaFns)

fn irMarkOf(g Gen, lw IrLower):
	IrMark(
		blocks = lw.f.blocks.len,
		loops = lw.f.loops.len,
		entry = lw.f.blocks[0].insts.len,
		owned = lw.owned.len,
		classes = lw.f.classes.len,
		cur = lw.f.cur,
		insts = lw.f.blocks[lw.f.cur].insts.len,
		names = lw.names.len,
		rets = lw.rets.len,
		breaks = lw.breaks.len,
		floor = lw.floor,
		thisType = lw.thisType,
		literals = lw.literals.len,
		literalWords = lw.literalWords.len,
		made = lw.made.len,
		raw = lw.raw.len,
		lambdas = g.irLambdaFns.len
	)

fn irRollback(mut g Gen, mut lw IrLower, m IrMark):
	lw.f.blocks.truncate(m.blocks)
	lw.f.loops.truncate(m.loops)
	lw.f.blocks[0].insts.truncate(m.entry)
	lw.f.classes.truncate(m.classes)
	lw.f.leafTypes.truncate(m.classes)   # the vregs made again from there are typed anew
	lw.f.cur = m.cur
	lw.f.blocks[m.cur].insts.truncate(m.insts)
	g.irForgetNames(lw, m.names)
	lw.owned.truncate(m.owned)
	lw.loopOwned.truncate(m.breaks)
	lw.rets.truncate(m.rets)
	lw.breaks.truncate(m.breaks)
	lw.conts.truncate(m.breaks)
	lw.floor = m.floor
	lw.thisType = m.thisType
	lw.literals.truncate(m.literals)
	lw.literalWords.truncate(m.literalWords)
	lw.made.truncate(m.made)
	lw.raw.truncate(m.raw)
	g.irLambdaFns.truncate(m.lambdas)
	lw.ok = true
	lw.why = ""

# fnd's body in place when the form can lower it, else none (nothing added)
fn irTryInline(
	mut g Gen,
	mut lw IrLower,
	fnd NodeId,
	recv i64[]?,
	recvType TypeId?,
	args NodeId[]
) i64[]?:
	m = g.irMarkOf(lw)
	into = lw.resultAt   # (back for the call made instead, should the body not go in place)
	line = lw.line
	col = lw.col
	g.irDecide(fnd, recvType)   # (its lambdas and arena statements, as for a call of it)
	value = g.irInline(lw, fnd, recv, recvType, args)
	lw.line = line   # the body's statements said their own places: the code after it is the caller's
	lw.col = col
	if lw.ok:
		if lw.rets.isEmpty:
			lw.inlined += lw.f.blocks.len - m.blocks   # its nested bodies' blocks among them
		return value
	if irInlineWord().on():
		g.irSay("ir: {nodes[fnd].text} not inlined: {lw.why}")
	g.irRollback(lw, m)
	lw.resultAt = into
	lw.placed = -1
	none

# the leaves fnd's parameters take from the arguments' nodes, read in the caller's scope (a
# failure when a parameter's mode or type has no form in place)
fn irBindParams(
	mut g Gen,
	mut lw IrLower,
	fnd NodeId,
	args NodeId[],
	givens IrGiven[] = []
):
	params = nodes[fnd].kids.copy()
	if params.len != args.len or args.any(nodes[it].kind == nNamedArg):
		lw.irFail("call's arguments")
		return []
	bound = []
	for i in 0..params.len:
		pt = g.c.resolveType(nodes[params[i]].types[0])
		mode = nodes[params[i]].ival
		if givens.any(.at == i):
			noLeaves i64[] = []
			bound.push(noLeaves)   # read through lw.given
		elif g.irByAddress(pt) and (mode == modeRead or mode == modeMut):
			lw.sharedParams += 1
			bound.push(
				[
					g.irStackList(lw, args[i]) if mode == modeRead and g.stackListOk(args[i])
					else g.irAddressOf(lw, args[i])
				]
			)
		elif mode == modeMut and g.irTakes(pt) and nodes[args[i]].kind == nIdent and
			lw.irLookup(nodes[args[i]].text) is leaves:
			lw.sharedParams += 1
			bound.push(leaves)   # the caller's local itself: what the body changes, it has
		elif (mode == modeRead or (mode == modeMove and not g.isOwningType(pt))) and
			g.irTakes(pt):
			value = g.irValue(lw, args[i])
			fresh = g.irNewValue(lw, pt)   # the body may rebind its parameter
			lw.irCopyValue(fresh, value)
			bound.push(fresh)
		else:
			lw.irFail("parameter of {typeStr(tys, pt)}")
			return []
	bound

# fnd's body in place: recv the receiver's leaves (a method; its own leaves, so a mut method
# changes them), args the arguments' nodes, read in the caller's scope first; the result's leaves
fn irInline(
	mut g Gen,
	mut lw IrLower,
	fnd NodeId,
	recv i64[]?,
	recvType TypeId?,
	args NodeId[]
):
	into = lw.resultAt   # (its result's place: taken by the body, not the arguments' calls)
	lw.resultAt = -1
	params = nodes[fnd].kids.copy()
	givens = g.irGivens(lw, fnd, args)
	lw.sharedParams = 0
	bound = g.irBindParams(lw, fnd, args, givens)
	if not lw.ok: return []
	mark = lw.names.len
	savedFloor = lw.floor
	savedThis = lw.thisType
	lw.floor = mark
	if recv is r:
		lw.irDeclare("self", r.copy())
		lw.thisType = recvType
	else:
		lw.thisType = none
	for i in 0..params.len:
		if nodes[params[i]].ival == modeMut:
			lw.mutNames.push(lw.names.len)   # the caller's place: a written move leaves it, empty
		lw.irDeclare(nodes[params[i]].text, bound[i].copy())
	for given in givens:
		inner = given.copy()
		inner.at = lw.names.len - params.len + given.at
		lw.given.push(inner)
	foreign = 1 if nodes[fnd].file() != g.irFileNow else 0
	lw.foreign += foreign
	copied = recv == none and givens.isEmpty and lw.sharedParams == 0 and into < 0 and
		nodes[fnd].names.isEmpty
	result = g.irBodyOnce(
		lw,
		fnd,
		bound if copied else none,
		g.irInProgram(lw) if lw.rets.isEmpty
		else not lw.rets[len - 1].runtime and lw.rets[len - 1].written,
		into
	)
	lw.foreign -= foreign
	g.irScopeEnd(lw, mark)
	lw.floor = savedFloor
	lw.thisType = savedThis
	result

# whether the body's last statement is the value of a function of result type rt: not for a
# result without a value (`? E`) whose body ends in a statement (neither an E nor the result itself)
fn irBodyGivesValue(mut g Gen, rt TypeId, body NodeId):
	tail = g.irTailType(body)
	noValue = g.irIsResult(rt) and g.tyK(tys[rt].inner) == tUnit and
		(tail == none or not (isSameType(tys, tail, tys[rt].err) or isSameType(tys, tail, rt)))
	g.tyK(rt) != tUnit and not noValue

# a body lowered in place, its parameters declared: its result's leaves (an owned one a
# temporary of the caller's statement, the body's return moves into it), a return leaving it
fn irBodyInPlace(
	mut g Gen,
	mut lw IrLower,
	body NodeId,
	rt TypeId,
	runtime bool = false,
	written bool = false,
	into i64 = -1   # where the result goes (irBox's block), -1 for a slot of its own
):
	if not g.irTakes(rt) and not g.irByAddress(rt):
		return lw.irRefused("result of {typeStr(tys, rt)}")
	result = [into] if into >= 0 and g.irByAddress(rt)
		else [g.irResultSlot(lw, rt)] if g.irByAddress(rt)
		else g.irNewValue(lw, rt)
	end = lw.f.irBlock()
	lw.rets.push(
		IrReturn(
			leaves = result.copy(),
			end,
			t = rt,
			owned = lw.owned.len,
			arenas = lw.arenas,
			runtime,
			written
		)
	)
	value = g.irBlockValue(lw, body, g.irBodyGivesValue(rt, body))
	if not lw.f.irEnded() and lw.ok:
		g.irResultTo(lw, result, rt, g.irAsResult(lw, rt, g.irTailType(body), value))
		g.irDropFrom(lw, lw.rets[len - 1].owned)
	lw.f.irJumpTo(end)
	lw.owned.truncate(lw.rets[len - 1].owned)   # each way to the end dropped what the body owns
	lw.rets.pop()
	lw.f.irEnter(end)
	g.irOwnGivenWords(lw, rt, result)
	if into >= 0 and g.irByAddress(rt) and lw.ok:
		lw.placed = into
	result

# ---------- statements ----------
