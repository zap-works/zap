# The lowering of the walks of sequences and lists: each, yield and their lambdas (irLower.zap).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# A loop over a pipeline's source, its body the caller's: a list's elements in turn, or the
# integers of lo..hi. irEachBegin enters the body; irEachEnd steps to the next and leaves.
type IrEach:
	shell IrShell   # its step (cont) goes to the next element
	counter i64
	n i64
	ptr i64   # the element's address (a list), -1 for a range
	elem TypeId   # the element's type
	lo i64 = -1   # a stepped range: its first value and its step (the counter counts steps)
	stepV i64 = -1
	seq bool = false   # a Seq's walk (irSeqWalk): the fields below
	value i64[] = []   # the element of this turn (a Seq's, or the steps' before a consumer: given)
	given bool = false
	state i64 = -1   # which yield gave it
	resumes i64[] = []   # the block after each yield
	held IrOwned[] = []   # what the generator owns at a yield: dropped when the walk is left early
	hidden i64 = -1   # the name they are owned under while a turn runs
	done i64 = -1   # the block after the walk
	blocks0 i64 = -1   # the generator's blocks, from its first ...
	blocks1 i64 = -1   # ... to the turn's first
	loops0 i64 = -1   # the generator's own loops, from ...
	loops1 i64 = -1   # ... to

# whether e is a source a pipeline step reads in a loop: a list, lo..hi of integers, or a Seq
fn irIsSource(mut g Gen, e NodeId) bool:
	if g.tyK(g.ty(e)) == tSeq: return true
	if g.irIsList(g.irListType(e)) or g.tyK(g.irListType(e)) == tArray: return true
	if g.irParallelOf(e) is inner: return g.irIsSource(inner)
	nodes[e].kind == nRange and g.tyK(g.ty(nodes[e].kids(kidIds)[0])) == tInt

# A walk over a Seq: a step's (filter, map) over its receiver's walk, or a generator's.
fn irSeqBegin(mut g Gen, mut lw IrLower, e NodeId) IrEach:
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind == nField and nodes[e].kids(kidIds).len == 2 and
		g.tyK(g.ty(nodes[callee].kids(kidIds)[0])) == tSeq:
		each = g.irEachBegin(lw, nodes[callee].kids(kidIds)[0])
		if not lw.ok: return each
		lam = nodes[e].kids(kidIds)[1]
		if nodes[callee].text == "filter":
			yesB = lw.f.irBlock()
			g.irLambdaTest(lw, lam, each.value, yesB, each.shell.cont)   # not kept: the next element
			lw.f.irEnter(yesB)
		else:
			mark = lw.names.len
			each.value = g.irLambdaValue(lw, lam, each.value, true)
			g.irScopeEnd(lw, mark)
		return each
	g.irSeqWalk(lw, e)

# A generator's walk. Its body is lowered in place, each yield writing the element and going to
# the turn's block (the caller's code, which follows: a for's body, a step's), and the turn's end
# going back after the yield that gave it (the state says which). The generator's frame slots are
# made before the walk, so they live through every turn; what it owns at a yield is zeroed there
# too, and owned while a turn runs (a return from it drops it), and dropped when the walk is left
# early (each.shell.end).
fn irSeqWalk(mut g Gen, mut lw IrLower, e NodeId):
	found = g.c.generatorOf(e)
	elem = innerOf(tys, g.ty(e))
	each = IrEach(
		shell = IrShell(pre = lw.f.cur, body = -1, cont = -1, end = -1),
		counter = -1,
		n = -1,
		ptr = -1,
		elem,
		seq = true
	)
	fnd = found ?? return lw.irWalkRefused(each)
	if nodes[fnd].sub(kidIds).isEmpty: return lw.irWalkRefused(each)
	if lw.seqs.any(.fnd == fnd):
		irFail(
			lw,
			"'{nodes[fnd].text}' walks itself through another generator: a generator cannot recurse"
		)
		return each
	callee = nodes[e].kids(kidIds)[0]
	recv i64[]? = none
	recvType TypeId? = none
	if nodes[callee].kind == nField and
		g.c.findFunc(nodes[callee].text, nameOf(nodes, callee)) != fnd:
		obj = nodes[callee].kids(kidIds)[0]
		recvType = innerOf(tys, g.ty(obj)) if g.tyK(g.ty(obj)) == tRef else g.ty(obj)
		recv = g.irValue(lw, obj)
	bound = g.irBindParams(lw, fnd, nodes[e].kidsFrom(kidIds, 1).copy())
	if not lw.ok: return each
	each.value = [lw.f.irVreg(irInt)] if g.irByAddress(elem) else g.irNewValue(lw, elem)
	each.state = lw.f.irVreg(irInt)
	pre = lw.f.cur   # the receiver and the arguments may have left the first block
	each.shell = lw.f.irShell()
	each.shell.pre = pre
	each.done = lw.f.irBlock()
	each.blocks0 = lw.f.irBlock()
	each.loops0 = lw.f.loops.len
	each.hidden = lw.names.len
	lw.irDeclare("$seq", [])
	params = nodes[fnd].kids(kidIds).copy()
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
		lw.irDeclare(nodes[params[i]].text, bound[i].copy())
	lw.f.irEnter(each.blocks0)
	lw.seqs.push(
		IrSeq(
			fnd,
			value = each.value.copy(),
			elem,
			state = each.state,
			body = each.shell.body,
			resumes = [],
			ownedAt = lw.owned.len,
			held = []
		)
	)
	lw.rets.push(
		IrReturn(leaves = [], end = each.done, t = tyUnit, owned = lw.owned.len, arenas = lw.arenas)
	)   # return: the walk ends
	g.irBlockValue(lw, nodes[fnd].sub(kidIds)[0], false)
	lw.f.irJumpTo(each.done)
	lw.rets.pop()
	sq = lw.seqs.pop() ?? return each.copy()
	g.irScopeEnd(lw, mark)
	lw.floor = savedFloor
	lw.thisType = savedThis
	each.resumes = sq.resumes.copy()
	each.held = sq.held.copy()
	each.blocks1 = lw.f.blocks.len
	each.loops1 = lw.f.loops.len
	lw.f.irEnter(each.shell.pre)
	lw.irSlotsHere(each.blocks0, each.blocks1)
	for o in each.held:
		g.irZeroSlot(lw, o.slot, o.t)
		held = o.copy()
		held.name = each.hidden
		lw.owned.push(held)
	lw.f.irJumpTo(each.blocks0)
	lw.f.irEnterBody(each.shell)
	each

# a generator whose body is being lowered into a walk: where its yields write and go
type IrSeq:
	fnd NodeId
	value i64[]
	elem TypeId
	state i64
	body i64
	resumes i64[]
	ownedAt i64   # the owned values before its body
	held IrOwned[]

# yield v: the element written, the turn run, and back here for the next one
fn irYield(mut g Gen, mut lw IrLower, s NodeId):
	if not lw.arenaLines.isEmpty and not lw.irInRuntimeCode():
		# the walk may stop at the yield, never reaching the block's end
		g.irOwnError(
			g.irFileNow,
			nodes[s].line,
			nodes[s].col,
			compileError("YieldInArena", ["{lw.arenaLines.last ?? 0}"])
		)
	if lw.seqs.isEmpty:
		lw.irFail("a yield outside a walk")
		return
	i = lw.seqs.len - 1
	value = g.irAs(lw, g.irValue(lw, nodes[s].kids(kidIds)[0]), lw.seqs[i].elem)
	if not lw.ok: return
	lw.irCopyValue(lw.seqs[i].value, value)
	lw.irPut(IrInst(op = irConst, dst = lw.seqs[i].state, imm = lw.seqs[i].resumes.len))
	for k in lw.seqs[i].ownedAt..lw.owned.len:
		if not lw.seqs[i].held.any(.slot == lw.owned[k].slot):
			lw.seqs[i].held.push(lw.owned[k].copy())
		lw.irConsumed(lw.owned[k].slot, ownSuspended)
	lw.f.irJumpTo(lw.seqs[i].body)
	resume = lw.f.irBlock()
	lw.seqs[i].resumes.push(resume)
	lw.f.irEnter(resume)
	for k in lw.seqs[i].ownedAt..lw.owned.len:
		lw.irPut(IrInst(op = irOwn, a = lw.owned[k].slot, imm = i64(lw.owned[k].t)))   # its own again

# the frame slots made in blocks from..to made in the block being filled instead (a slot's
# address is the same wherever it is made)
fn irSlotsHere(mut lw IrLower, from i64, to i64):
	for b in from..to:
		if lw.f.blocks[b].insts.any(.op == irFrameSlot):
			slots = lw.f.blocks[b].insts.filter(.op == irFrameSlot)
			lw.f.blocks[b].insts = lw.f.blocks[b].insts.filter(.op != irFrameSlot)
			for inst in slots:
				lw.f.irAppend(inst.copy())

# a walk's turn ended: back after the yield that gave it; left early (each.shell.end): what the
# generator holds dropped. The generator's loops run the turn's blocks too, and the walk is a
# loop of its own around them.
fn irSeqEnd(mut g Gen, mut lw IrLower, each IrEach):
	lw.f.irJoin(each.shell.cont)
	n = each.resumes.len
	for k in 0..n - 1:
		other = lw.f.irBlock()
		lw.irBranchIf(each.state, irEq, lw.irConstOf(irInt, k), each.resumes[k], other)
		lw.f.irEnter(other)
	lw.f.irJumpTo(each.resumes[n - 1] if n > 0 else each.done)
	turn = [each.shell.body, each.shell.cont]
	turn.extend((each.blocks1..lw.f.blocks.len).map(it))
	lw.f.irEnter(each.shell.end)
	i = each.held.len - 1
	while i >= 0:
		g.irDropSlot(lw, each.held[i])
		i -= 1
	lw.f.irJumpTo(each.done)
	lw.owned = lw.owned.filter(.name != each.hidden)
	for li in each.loops0..each.loops1:
		lw.f.loops[li].blocks.extend(turn)
	# inner loops before the loops around them: the turn's loops before the generator's
	loops = lw.f.loops[..each.loops0].copy()
	loops.extend(lw.f.loops[each.loops1..].copy())
	loops.extend(lw.f.loops[each.loops0..each.loops1].copy())
	lw.f.loops = loops
	walk = [each.shell.body, each.shell.cont]
	walk.extend((each.blocks0..lw.f.blocks.len).filter(it != each.shell.end and it != each.done))
	lw.f.loops.push(IrLoop(pre = each.shell.pre, blocks = walk))
	lw.f.irEnter(each.done)

# the source of `source.parallel()` (its steps run in order through the form), or none
fn irParallelOf(mut g Gen, e NodeId) NodeId?:
	if nodes[e].kind != nCall or nodes[e].kids(kidIds).len != 1: return none
	callee = nodes[e].kids(kidIds)[0]
	nodes[callee].kids(kidIds)[0] if nodes[callee].kind == nField and
		nodes[callee].text == "parallel"
		else none

# room >= 0: the list at that address made to hold one element of stride bytes for each turn,
# before the walk (a map's output)
fn irEachBegin(mut g Gen, mut lw IrLower, obj0 NodeId, room i64 = -1, stride i64 = 1):
	if g.tyK(g.ty(obj0)) == tSeq: return g.irSeqBegin(lw, obj0)
	obj = g.irParallelOf(obj0) ?? obj0
	each = IrEach(
		shell = IrShell(pre = -1, body = -1, cont = -1, end = -1),
		counter = lw.f.irVreg(irInt),
		n = -1,
		ptr = -1,
		elem = tyError
	)
	if nodes[obj].kind == nRange:
		lo = g.irExpr(lw, nodes[obj].kids(kidIds)[0])
		each.n = g.irExpr(lw, nodes[obj].kids(kidIds)[1])
		each.elem = g.ty(nodes[obj].kids(kidIds)[0])
		if nodes[obj].kids(kidIds).len > 2:
			# stepped: k from 0 to the number of steps, the element lo + k * step
			each.lo = lo
			each.stepV = g.irExpr(lw, nodes[obj].kids(kidIds)[2])
			each.n = g.irRangeTrips(lw, lo, each.n, each.stepV)
			lw.irPut(IrInst(op = irConst, dst = each.counter, imm = 0))
		else:
			lw.irPut(IrInst(op = irCopy, dst = each.counter, a = lo))
	elif g.tyK(g.irListType(obj)) == tArray:
		at = g.irListType(obj)
		each.elem = innerOf(tys, at)
		each.n = lw.irConstOf(irInt, tys[at].bits)
		each.ptr = lw.irDef(irInt, IrInst(op = irCopy, a = g.irListAddr(lw, obj)))   # its elements where they are
		lw.irPut(IrInst(op = irConst, dst = each.counter, imm = 0))
	else:
		each.elem = innerOf(tys, g.irListType(obj))
		items, n = g.irItemsAndLength(lw, obj)
		if not lw.ok: return each
		each.n = n
		each.ptr = lw.irDef(irInt, IrInst(op = irCopy, a = items))
		lw.irPut(IrInst(op = irConst, dst = each.counter, imm = 0))
	if room >= 0:
		turns = lw.irDef(irInt, IrInst(op = irSub, a = each.n, b = each.counter))
		g.irGrowCall(lw, "listGrowExact", room, turns, stride)
	each.shell = lw.f.irShell()
	lw.irBranchIf(each.counter, irLt, each.n, each.shell.body, each.shell.end)
	lw.f.irEnterBody(each.shell)
	each

# the element of this turn: its leaves (an address for a type reached by address)
fn irEachValue(mut g Gen, mut lw IrLower, each IrEach) i64[]:
	if each.seq or each.given: return each.value.copy()
	if each.stepV >= 0:
		scaled = lw.irDef(irInt, IrInst(op = irMul, a = each.counter, b = each.stepV))
		v = lw.irDef(irInt, IrInst(op = irAdd, a = each.lo, b = scaled))
		return [v]
	[each.counter] if each.ptr < 0
		else g.irLoadValue(lw, each.elem, each.ptr, -1, g.c.elemStride(each.elem))

# how many values lo..hi by step holds (0 when none): ceil(|hi - lo| / |step|) when the step goes
# towards hi
fn irRangeTrips(mut g Gen, mut lw IrLower, lo i64, hi i64, step i64) i64:
	zero = lw.irConstOf(irInt, 0)
	diff = lw.irDef(irInt, IrInst(op = irSub, a = hi, b = lo))
	negStep = lw.irDef(irInt, IrInst(op = irNeg, a = step))
	negDiff = lw.irDef(irInt, IrInst(op = irNeg, a = diff))
	absStep = lw.f.irVreg(irInt)
	irPut(
		lw,
		IrInst(op = irSelect, dst = absStep, a = step, b = zero, c = negStep, d = step, cond = irLt)
	)
	num = lw.f.irVreg(irInt)
	irPut(
		lw,
		IrInst(op = irSelect, dst = num, a = step, b = zero, c = negDiff, d = diff, cond = irLt)
	)
	rounded = lw.irDef(irInt, IrInst(op = irAdd, a = num, b = absStep))
	less = lw.irDef(irInt, IrInst(op = irSub, a = rounded, b = lw.irConstOf(irInt, 1)))
	trips = lw.irDef(irInt, IrInst(op = irDiv, a = less, b = absStep))
	lw.irDef(irInt, IrInst(op = irSelect, a = num, b = zero, c = zero, d = trips, cond = irLe))

fn irEachEnd(mut g Gen, mut lw IrLower, each IrEach):
	if each.seq:
		g.irSeqEnd(lw, each)
		return
	lw.f.irJoin(each.shell.cont)
	if each.ptr >= 0:
		irPut(
			lw,
			IrInst(
				op = irAdd,
				dst = each.ptr,
				a = each.ptr,
				b = lw.irConstOf(irInt, g.c.elemStride(each.elem))
			)
		)
	lw.irPut(IrInst(op = irAdd, dst = each.counter, a = each.counter, b = lw.irConstOf(irInt, 1)))
	lw.irBranchIf(each.counter, irLt, each.n, each.shell.body, each.shell.end)
	lw.irLoopDone(each.shell)

# a one-parameter lambda's value for the element: its parameter bound to it (the caller ends
# the scope from `mark`)
fn irLambdaValue(mut g Gen, mut lw IrLower, lam NodeId, value i64[], want bool) i64[]:
	gi = lw.irGivenAt(nodes[lam].text) if nodes[lam].kind == nIdent else -1
	if gi >= 0: return g.irGivenCallValues(lw, lw.given[gi].copy(), [value.copy()])
	if g.irIsFnRef1(lam): return g.irFnRefValue(lw, lam, value)
	if g.irIsFnValue1(lam):
		return irClosureCallValues(
			g,
			lw,
			lam,
			[g.irClosureArg(lw, tys[g.ty(lam)].params[0], value)]
		)
	lw.irDeclare(nodes[lam].names(kidIds)[0], value.copy())
	g.irLambdaBody(lw, lam, want)

# a lambda's body with its parameters declared: an expression's value, or a block's, whose
# returns (the implicit one at its end, an early one) leave the lambda as an inlined body's do
fn irLambdaBody(mut g Gen, mut lw IrLower, lam NodeId, want bool):
	if nodes[lam].sub(kidIds).isEmpty: return g.irValue(lw, nodes[lam].kids(kidIds)[0])
	rt = retOf(tys, g.ty(lam))
	if want and not g.irTakes(rt) and not g.irByAddress(rt):
		return lw.irRefused("a lambda's value of {typeStr(tys, rt)}")
	result = []
	if want:
		result = [g.irResultSlot(lw, rt)] if g.irByAddress(rt) else g.irNewValue(lw, rt)
	end = lw.f.irBlock()
	lw.rets.push(
		IrReturn(
			leaves = result.copy(),
			end,
			t = rt if want else tyUnit,
			owned = lw.owned.len,
			arenas = lw.arenas,
			runtime = g.irInRuntime(lw) if lw.rets.isEmpty else lw.rets[len - 1].runtime,
			written = g.irInProgram(lw) if lw.rets.isEmpty else lw.rets[len - 1].written,
			lambda = true
		)
	)
	value = g.irBlockValue(lw, nodes[lam].sub(kidIds)[0], want)
	if not lw.f.irEnded() and lw.ok:
		if want:
			irResultTo(
				g,
				lw,
				result,
				rt,
				g.irAsResult(lw, rt, g.irTailType(nodes[lam].sub(kidIds)[0]), value)
			)
		g.irDropFrom(lw, lw.rets[len - 1].owned)
	lw.f.irJumpTo(end)
	lw.owned.truncate(lw.rets[len - 1].owned)   # each way to the end dropped what the body owns
	lw.rets.pop()
	lw.f.irEnter(end)
	if want:
		g.irOwnGivenWords(lw, rt, result)
	result

# the type of a source's elements
fn irSourceElem(mut g Gen, obj NodeId):
	g.ty(nodes[obj].kids(kidIds)[0]) if nodes[obj].kind == nRange
		else innerOf(tys, g.irListType(obj))

# whether e is a lambda of one parameter
fn irIsLambda1(g Gen, e NodeId):
	(nodes[e].kind == nLambda and nodes[e].names(kidIds).len == 1) or g.irIsFnRef1(e) or
		g.irIsFnValue1(e)

# a value of a fn type of one parameter where a pipeline takes a lambda (`xs.map(ops[0])`)
fn irIsFnValue1(g Gen, e NodeId):
	t = nodes[e].ty ?? return false
	nodes[e].kind != nLambda and not g.irIsFnRef1(e) and tys[t].kind == tFn and
		tys[t].params.len == 1

# a named function of one parameter where a pipeline takes a lambda (`xs.filter(isSmall)`)
fn irIsFnRef1(g Gen, e NodeId):
	if nodes[e].kind != nIdent or not nodes[e].hasFlag(flagFnRef): return false
	fnd = g.c.findFunc(nodes[e].text, nameOf(nodes, e)) ?? return false
	nodes[fnd].kids(kidIds).len == 1

# the named function called with the element's leaves (a scalar or an address)
fn irFnRefValue(mut g Gen, mut lw IrLower, e NodeId, value i64[]) i64[]:
	fnd = g.c.findFunc(nodes[e].text, nameOf(nodes, e)) ??
		return lw.irRefused("a call of {nodes[e].text} with the element")
	if value.len != 1 or not g.irCallable(fnd, false):
		return lw.irRefused("a call of {nodes[e].text} with the element")
	g.irCallValues(lw, fnd, nodes[fnd].text.copy(), [value[0]])

# any, all or count of a lambda over a source (a Seq's count() of every element, lam -1): a loop
# that stops at the first answer
fn irTestEach(mut g Gen, mut lw IrLower, m str, obj NodeId, lam NodeId?):
	result = lw.irDef(irInt, IrInst(op = irConst, imm = 1 if m == "all" else 0))
	each = g.irEachBegin(lw, obj)
	if not lw.ok: return -1
	yesB = lw.f.irBlock()
	noB = lw.f.irBlock()
	if lam is lam:
		g.irLambdaTest(lw, lam, g.irEachValue(lw, each), yesB, noB)
	else:
		lw.f.irJumpTo(yesB)   # a Seq's count(): every element
	lw.f.irEnter(yesB)
	if m == "any":
		lw.irPut(IrInst(op = irConst, dst = result, imm = 1))
		lw.f.irJumpTo(each.shell.end)
	elif m == "count":
		lw.irPut(IrInst(op = irAdd, dst = result, a = result, b = lw.irConstOf(irInt, 1)))
	lw.f.irJumpTo(each.shell.cont)
	lw.f.irEnter(noB)
	if m == "all":
		lw.irPut(IrInst(op = irConst, dst = result, imm = 0))
		lw.f.irJumpTo(each.shell.end)
	g.irEachEnd(lw, each)
	result

# whether sortedBy, minBy and maxBy take obj: a list, a range of integers, or map and filter
# steps of values that own nothing (run in the keys' loop, their elements gathered there)
fn irKeyed(mut g Gen, obj NodeId):
	g.irIsList(g.irListType(obj)) or
		(nodes[obj].kind == nRange and g.tyK(g.ty(nodes[obj].kids(kidIds)[0])) == tInt) or
		g.irGathersSteps(obj)

# whether obj is map and filter steps whose elements irKeysOf gathers in its own loop
fn irGathersSteps(mut g Gen, obj NodeId):
	g.irFusedStep(obj) != none and not g.isOwningType(g.irStepsElem(obj)) and
		g.irTakes(g.irStepsElem(obj))
