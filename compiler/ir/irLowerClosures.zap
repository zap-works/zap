# The lowering of lambdas, closures and calls of function values (irLower.zap).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# a lambda's body lowered as a function of its own, emitted after the function it is in
type IrLambdaFn:
	key str
	lam NodeId?
	f IrFn
	checked bool = false   # its ownership checked (irLowerChecked)

# whether a bare name is a field of this (a method's receiver), which shadows the module's names
fn irFieldOfThis(mut g Gen, lw IrLower, name str):
	lw.thisType != none and g.c.fieldIndexOf(declOf(tys, lw.thisType), name) >= 0

# a named function as a value: { the wrapper that calls it with a closure's arguments (none
# without code: an instance made for it calls the function itself), no environment } in a slot
# that owns nothing
fn irFnValue(mut g Gen, mut lw IrLower, e NodeId, code bool = true):
	wrapper = lw.irConstOf(irInt, 0)
	if code:
		wrapper = lw.f.irVreg(irInt)
		irPut(
			lw,
			IrInst(op = irFnAddr, dst = wrapper, imm = g.irFnValueLabel(nodes[e].text, g.ty(e)))
		)
	slot = g.irClosureSlot(lw, wrapper, lw.irConstOf(irInt, 0))
	lw.literals.push(slot)
	[slot]

# a closure { code, environment } in a frame slot that owns nothing
fn irClosureSlot(mut g Gen, mut lw IrLower, code i64, env i64):
	slot = lw.irNewSlot(16)
	lw.irPut(IrInst(op = irStore, a = slot, c = code))
	lw.irPut(IrInst(op = irStore, a = slot, c = env, imm = 8))
	slot

# a lambda: its body a function of its own (irLowerLambda), its captures in an environment
# block headed by the function that drops and copies them (the layout of envFnLabel), the
# closure { code, environment } a temporary of the statement
fn irClosure(mut g Gen, mut lw IrLower, e NodeId):
	ft = g.ty(e)
	# a lambda that runs once reads its captures where the environment holds them (irLowerLambda):
	# what it takes out leaves that place empty for the environment's drop
	if "self" in nodes[e].names2(kidIds): return lw.irRefused("a lambda reading this")
	body = g.irLambdaCode(lw, e, g.irHeldOf(lw, e))
	if not lw.ok: return []
	# a given function it captures: pointed at as it is, copied whole
	caps = []
	for ci in 0..nodes[e].names2(kidIds).len:
		name = nodes[e].names2(kidIds)[ci].copy()
		gi = lw.irGivenAt(name)
		if gi < 0:
			caps.push(g.irFind(lw, name) ?? [])
		elif g.capByPointer(e, ci):
			caps.push([g.irGivenClosureWord(lw, lw.given[gi].copy())])
		else:
			caps.push([g.irGivenValue(lw, lw.given[gi].copy())])
	env = g.irEnvBlock(lw, e, caps, true)
	if not lw.ok: return []
	slot = g.irTemporary(lw, ft)
	lw.irPut(IrInst(op = irStore, a = slot, c = body))
	lw.irPut(IrInst(op = irStore, a = slot, c = env, imm = 8))
	[slot]

# the types of lambda e's environment after its header: a pointer for a capture pointed at
fn irEnvTypes(mut g Gen, e NodeId):
	out TypeId[] = []
	for ci in 0..nodes[e].ints(kidIds).len:
		out.push(tyInt(64, true) if g.capByPointer(e, ci) else nodes[e].ints(kidIds)[ci])
	out

# lambda e's environment from each capture's leaves caps: a block on the heap headed by the
# function that drops and copies it, or (not heap) a slot of this frame whose header is 0
fn irEnvBlock(mut g Gen, mut lw IrLower, e NodeId, caps i64[,], heap bool):
	envTypes = g.irEnvTypes(e)
	envSize = envTypes.sum(g.c.slotSize(it))
	if envSize == 0: return lw.irConstOf(irInt, 0)
	env = -1
	if heap:
		block = g.irCallRt(lw, "rtAlloc", [lw.irConstOf(irInt, 8 + envSize)])
		if not lw.ok: return -1
		env = block[0]
		head = lw.irDef(irInt, IrInst(op = irFnAddr, imm = g.envFnLabel(envTypes, envSize)))
		lw.irPut(IrInst(op = irStore, a = env, c = head))
	else:
		env = lw.irNewSlot(8 + envSize)
		lw.irPut(IrInst(op = irStore, a = env, c = lw.irConstOf(irInt, 0)))
	off = 8
	for ci in 0..nodes[e].names2(kidIds).len:
		name = nodes[e].names2(kidIds)[ci].copy()
		if caps[ci].isEmpty:
			lw.irFail("capture of {name}")
			return -1
		g.irStoreCapture(lw, e, ci, lw.irElementAddr(env, -1, 0, off), caps[ci])
		if not lw.ok: return -1
		off += g.c.slotSize(envTypes[ci])
	env

# lambda e's capture ci, whose leaves here are leaves, stored in its environment at at: copied,
# moved or pointed at
fn irStoreCapture(mut g Gen, mut lw IrLower, e NodeId, ci i64, at i64, leaves i64[]):
	name = nodes[e].names2(kidIds)[ci].copy()
	ct = nodes[e].ints(kidIds)[ci]
	if g.capByPointer(e, ci):
		target = leaves[0]
		if not g.irByAddress(ct) and not g.irIsOwnedWord(ct) and g.irTakes(ct):
			# numbers in registers: a slot of their own from now on, kept in step around calls
			target = g.irSpillSlot(lw, leaves, ct)
		elif g.irIsOwnedWord(ct):
			# a map's or box's word: the slot that holds it (an owned one's own, else a copy)
			oi = lw.irOwnedWordAt(leaves[0])
			target = lw.owned[oi].slot if oi >= 0 else g.irLentCopy(lw, ct, leaves)
		elif not g.irByAddress(ct):
			lw.irFail("a capture by pointer of {typeStr(tys, ct)} (in registers)")
			return
		lw.irPut(IrInst(op = irStore, a = at, c = target))
		return
	copied = "|{name}|" in g.irShares(e)
	if copied:
		lw.irArenaMovedName(lw.irLookupAt(name), ct)   # one more owner, kept by the closure
	if g.irOwnedByAddress(ct):
		if not copied and lw.irOwns(leaves[0]):
			g.irMoveAs(lw, at, leaves[0], ct, ownCaptured)   # the local's value is the closure's now
		else:
			lw.irPut(IrInst(op = irDeepCopy, a = at, b = leaves[0], ty = ct))
	elif g.irIsOwnedWord(ct):
		given = -1 if copied else g.irGiveWord(lw, leaves[0])
		if given >= 0:
			lw.irPut(IrInst(op = irStore, a = at, c = given))
		else:
			lw.irPut(
				IrInst(op = irDeepCopy, a = at, b = g.irLentCopy(lw, ct, leaves), ty = ct)
			)
	elif g.irByAddress(ct):
		lw.irPut(IrInst(op = irMemCopy, a = at, b = leaves[0], imm = g.sizeOf(ct)))
	elif g.irTakes(ct):
		g.irStoreLeaves(lw, ct, at, -1, 1, 0, leaves)
	else:
		lw.irFail("a capture of {typeStr(tys, ct)}")

# lambda e's body lowered as a function of its own (emitted after this one), held its captures
# given in scope: its code's address
fn irLambdaCode(mut g Gen, mut lw IrLower, e NodeId, held IrGiven[]) i64:
	body = g.irLowerLambda(e, held, lw.foreign)
	if not body.ok:
		lw.irFail("lambda: {body.why}")
		return -1
	g.irLambdaSeq += 1
	key = "$lam:{e}:{g.irLambdaSeq}"
	g.irLambdaFns.push(IrLambdaFn(key = key.copy(), lam = e, f = body.f))
	lw.irDef(irInt, IrInst(op = irFnAddr, part = instPartOf(key = key)))   # its label made when emitted: only then is the body

# the body of lambda e as a function: its arguments on the stack as the ABI's lambda reads
# them (the hidden result address first, the parameters, the environment deepest), its captures
# read from the environment (by pointer: the caller's value; copied: the block's copy), the
# given functions among them (held) called as given
fn irLowerLambda(mut g Gen, e NodeId, held IrGiven[], foreign i64):
	lw = IrLower(f = newIrFn(), fnd = none, names = [], vals = [], breaks = [], conts = [])
	lw.foreign = foreign   # a lambda of an inlined body of another file: that file's lowering says its errors
	ft = g.ty(e)
	rt = retOf(tys, ft)
	lw.rt = rt
	if not g.irResultOk(rt):
		lw.irFail("result of {typeStr(tys, rt)}")
		return lw
	hidden = 0 if g.c.isScalar(rt) else 1
	if hidden == 1:
		lw.hidden = lw.irDef(irInt, IrInst(op = irParam, imm = 0))
	np = tys[ft].params.len
	for i in 0..np:
		pt = tys[ft].params[i]
		lent = g.irIsAggregate(pt)
		if not (g.irClassOf(pt) >= 0 or g.irByAddress(pt) or lent):
			lw.irFail("parameter of {typeStr(tys, pt)}")
			return lw
		v = lw.f.irVreg(irInt if g.irByAddress(pt) or lent else g.irClassOf(pt))
		irPut(
			lw,
			IrInst(
				op = irParam,
				dst = v,
				imm = hidden + np - 1 - i,
				size = 4 if g.irIsF32(pt) else 8
			)
		)
		lw.irDeclare(nodes[e].names(kidIds)[i], g.irLoadValue(lw, pt, v, -1, 0) if lent else [v])
	env = lw.irDef(irInt, IrInst(op = irParam, imm = hidden + np))
	g.irDeclareCaptures(lw, e, env)
	if not lw.ok: return lw
	for h in held:
		at = lw.irLookupAt(nodes[e].names2(kidIds)[h.at])
		loaded = g.irGivenLoaded(lw, h.copy(), lw.vals[at][0])
		loaded.at = at
		lw.given.push(loaded)
	want = g.tyK(rt) != tUnit
	if nodes[e].sub(kidIds).isEmpty:
		g.irPlaceAt(lw, nodes[e].kids(kidIds)[0])   # an expression body has no statement to give its place
	result = g.irBlockValue(lw, nodes[e].sub(kidIds)[0], want) if not nodes[e].sub(kidIds).isEmpty
		else g.irValue(lw, nodes[e].kids(kidIds)[0])
	if not lw.f.irEnded() and lw.ok:
		irFunctionResult(
			g,
			lw,
			g.irAsResult(lw, rt, g.irTailType(nodes[e].sub(kidIds)[0] if not nodes[e].sub(kidIds).isEmpty else nodes[e].kids(kidIds)[0]), result),
			rt
		)
	lw

# lambda e's captures declared from its environment env (by pointer: the caller's value, a
# number it changes read here and written back on return; copied: the block's copy)
fn irDeclareCaptures(mut g Gen, mut lw IrLower, e NodeId, env i64):
	caps = g.irCapsOf(lw, e, env)
	if not lw.ok: return
	for ci in 0..nodes[e].names2(kidIds).len:
		name = nodes[e].names2(kidIds)[ci].copy()
		ct = nodes[e].ints(kidIds)[ci]
		if g.capByPointer(e, ci) and not g.irByAddress(ct) and name in nodes[e].bounds(kidIds):
			leaves = g.irLoadValue(lw, ct, caps[ci][0], -1, 0)
			lw.mutScalars.push(IrMutScalar(caps[ci][0], leaves.copy(), ct))
			lw.irDeclare(name, leaves)
		else:
			if g.irFlagged(e, flagOnce) and g.irOwnedByAddress(ct) and caps[ci].len == 1:
				lw.onceCaptures.push(caps[ci][0])   # its environment's to give: run once
			lw.irDeclare(name, caps[ci].copy())

# lambda e's captures read from its environment env: each one's leaves, its address when
# pointed at and by address or changed by the lambda
fn irCapsOf(mut g Gen, mut lw IrLower, e NodeId, env i64):
	caps = []
	off = 8
	for ci in 0..nodes[e].names2(kidIds).len:
		name = nodes[e].names2(kidIds)[ci].copy()
		ct = nodes[e].ints(kidIds)[ci]
		at = lw.irElementAddr(env, -1, 0, off)
		if g.capByPointer(e, ci):
			p = lw.irDef(irInt, IrInst(op = irLoad, a = at))
			changed = name in nodes[e].bounds(kidIds)
			caps.push([p] if g.irByAddress(ct) or changed else g.irLoadValue(lw, ct, p, -1, 0))
			off += 8
			continue
		if name in nodes[e].bounds(kidIds):
			lw.irFail("a lambda changing its copy of {name}")
			return caps
		caps.push([at] if g.irByAddress(ct) else g.irLoadValue(lw, ct, at, -1, 0))
		off += g.c.slotSize(ct)
	caps

# a call through a value: the environment pushed first, the
# arguments as read parameters (scalars by value, the rest by address), the hidden result
# address last; the code called through the value
fn irClosureCall(mut g Gen, mut lw IrLower, e NodeId, callee NodeId, args NodeId[]) i64[]:
	vs = g.irClosureArgs(lw, g.ty(callee), args)
	if not lw.ok: return []
	g.irClosureCallValues(lw, callee, vs)

# the words a closure of type ft is called with for the argument nodes args
fn irClosureArgs(mut g Gen, mut lw IrLower, ft TypeId, args NodeId[]):
	params = tys[ft].params.copy()
	if params.len != args.len or args.any(nodes[it].kind == nNamedArg):
		return lw.irRefused("a closure's arguments")
	vs = []
	for i, arg in args:
		pt = params[i]
		if g.irByAddress(pt):
			vs.push(g.irAddressOf(lw, arg))
		else:
			vs.push(g.irClosureArg(lw, pt, g.irValue(lw, arg)))
	vs

# a closure's argument of type pt from a value's leaves: a struct of numbers in a slot (its
# address), a scalar as its bits, a value by address as that address
fn irClosureArg(mut g Gen, mut lw IrLower, pt TypeId, value i64[]):
	if g.irByAddress(pt) and value.len == 1: return value[0]
	if g.irIsAggregate(pt): return g.irLentCopy(lw, pt, value)
	if g.irClassOf(pt) >= 0 and value.len == 1: return g.irArgBits(lw, value[0], pt)
	lw.irFail("a closure's argument of {typeStr(tys, pt)}")
	-1

# the fn value callee called with the words vs (irClosureCall): its result
fn irClosureCallValues(mut g Gen, mut lw IrLower, callee NodeId, move vs i64[]) i64[]:
	f = g.irAddressOf(lw, callee)
	if not lw.ok: return []
	g.irClosureCallAt(lw, g.ty(callee), f, vs)

# the closure of type ft at address f called with the words vs: its result
fn irClosureCallAt(mut g Gen, mut lw IrLower, ft TypeId, f i64, move vs i64[]):
	rt = retOf(tys, ft)
	if not g.c.isScalar(rt) and g.tyK(rt) != tUnit:
		if not g.irTakes(rt) and not g.irByAddress(rt):
			return lw.irRefused("a closure's result of {typeStr(tys, rt)}")
		slot = g.irResultSlot(lw, rt)
		g.irPutSynced(lw, IrInst(op = irCallPtr, a = f, c = slot, part = instPartOf(vs)))
		return g.irCallResult(lw, rt, slot)
	dst = -1 if g.tyK(rt) == tUnit else lw.f.irVreg(g.irClassOf(rt))
	g.irPutSynced(lw, IrInst(op = irCallPtr, a = f, dst, part = instPartOf(vs)))
	if dst >= 0 and g.irIsOwnedWord(rt):
		g.irOwnedWord(lw, rt, dst)
	[dst] if dst >= 0 else []

# a function the form can call (not inline), or lower: by name, not extern, generic only as an
# instance (its substitution in force), its parameters scalars it reads, values reached by address
# it reads or changes, owned values given to it, structs of numbers it reads; its result one the
# form takes
fn irCallable(mut g Gen, maybeFnd NodeId?, instance bool) bool:
	fnd = maybeFnd ?? return false
	if nodes[fnd].kind != nFnDecl or (not nodes[fnd].names(kidIds).isEmpty and not instance):
		return false
	for p in nodes[fnd].kids(kidIds).copy():
		pt = g.c.resolveType(nodes[p].types(kidIds)[0])
		mode = nodes[p].ival
		# a plain value moved in is copied; a mut map is the table's address, never reassigned
		reads = mode == modeRead or (mode == modeMove and not g.isOwningType(pt)) or
			(mode == modeMut and g.tyK(pt) == tMap) or (mode == modeMove and g.irIsOwnedWord(pt))
		given = g.irGiven(pt, mode) or g.irMovedWords(pt, mode)
		lent = mode == modeRead and g.irLentAsCopy(pt)   # its address: a copy of its leaves
		out = mode == modeOut and g.irClassOf(pt) >= 0   # an extern's: the system writes where the word points
		if not (reads and g.irClassOf(pt) >= 0) and
			not ((mode == modeRead or mode == modeMut) and g.irByAddress(pt)) and not given and
			not lent and not g.irMutScalar(pt, mode) and not out:
			return false
	g.irResultOk(g.c.fnRetType(fnd))

# whether a parameter is a struct of numbers the function changes: its address passed (as
# the ABI passes it), the leaves read on entry and written back on the way out
fn irMutScalar(mut g Gen, pt TypeId, mode i64):
	mode == modeMut and g.irIsAggregate(pt)

# whether a parameter is an owned value given to the function: its words on the stack, the
# function's to drop
fn irGiven(mut g Gen, pt TypeId, mode i64):
	mode == modeMove and g.isOwningType(pt) and g.irByAddress(pt)

# whether a parameter is a struct of numbers (or an optional number) moved in: its words on the
# stack (as the ABI passes a moved value), read as leaves
fn irMovedWords(mut g Gen, pt TypeId, mode i64):
	mode == modeMove and
		(
			g.irIsAggregate(pt) or g.irIsOption(pt) and not g.isOwningType(pt) or
				g.irMovedPlace(pt, mode)
		)

# a value in memory that owns nothing (an array, a struct) moved in: its words on the stack, used
# there
fn irMovedPlace(mut g Gen, pt TypeId, mode i64):
	mode == modeMove and not g.isOwningType(pt) and
		(g.tyK(pt) == tArray or g.irIsPlaceStruct(pt) or g.irIsWindow(pt))

# whether the form takes a result of type t: none, a plain scalar, leaves, or a value reached by
# address (owned: through a frame slot)
fn irResultOk(mut g Gen, t TypeId):
	g.tyK(t) == tUnit or (g.irClassOf(t) >= 0 and not g.isOwningType(t)) or g.irTakes(t) or
		g.irByAddress(t)

# what of fnd's signature the form does not take (for ZAP_RUN=ir)
fn irSignatureWhy(mut g Gen, fnd NodeId):
	if not nodes[fnd].names(kidIds).isEmpty: return "signature: generic"
	if nodes[fnd].hasFlag(flagExtern) or nodes[fnd].sub(kidIds).isEmpty: return "signature: extern"
	for p in nodes[fnd].kids(kidIds).copy():
		pt = g.c.resolveType(nodes[p].types(kidIds)[0])
		if not g.irCallable(fnd, false) and
			not (g.irClassOf(pt) >= 0 and nodes[p].ival == modeRead) and not g.irByAddress(pt):
			return "signature: parameter {["read", "mut", "move", "out"][nodes[p].ival.min(3)]} {g.irKindName(pt)}"
	"signature: result {g.irKindName(g.c.fnRetType(fnd))}"

fn irKindName(g Gen, t TypeId):
	k = tys[t].kind
	names = [
		"unit",
		"bool",
		"int",
		"float",
		"str",
		"struct",
		"enum",
		"option",
		"result",
		"?",
		"?",
		"list",
		"map",
		"fn",
		"error",
		"ref",
		"simd",
		"bytes",
		"box",
		"vec",
		"array"
	]
	names[k] if k >= 0 and k < names.len else "kind {k}"
