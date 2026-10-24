# A function taking a function, made for each one given (spec 14.3): a call passing a
# lambda or a function by name to a parameter the callee calls, gives on or lends to a lambda
# of its own gets an instance of the callee made for it, as a generic's type arguments do. There
# a call of the parameter runs the lambda's body in place, its captures read once where the
# instance starts (or, in a body expanded at the call site, the caller's own), or calls the
# function by name; the closure passed carries no code and its environment lives in the caller's
# frame. Any other use of the parameter makes the closure whole where it is read.

alias nodes = g.c.nodes
alias tys = g.c.types

# a parameter given a function: what was given and, while lowering, where it is
type IrGiven:
	at i64   # the name's index in scope (an instance's: the parameter's index; a held one's: the capture's)
	node NodeId   # the lambda, or the function's name
	site Subst   # the substitution the lambda's site is lowered under
	held IrGiven[] = []   # the lambda's captures that are given functions themselves
	closure i64 = -1   # its closure { no code, environment }, -1 while none is made
	caps i64[,] = []   # per capture: its leaves here (a held one's: none)
	inMemory bool = false   # caps read from the environment: a capture the lambda changes is its address
	part i64 = -1   # a key lambda's: only this part of its tuple (irKeyParts), -1 its whole value

# an instance of fnd made for what a call gave it: its label, the substitution it is lowered
# under, a method's type and generic impl and the parameters given
type IrGivenInstance:
	key str
	fnd NodeId
	sub Subst
	implType TypeId?
	implDecl NodeId?
	givens IrGiven[]

# the instance gi's code, its substitution in force: a method's its impl's; a generic's instance
# checked first when nothing did yet
fn genGivenInstance(mut g Gen, move gi IrGivenInstance):
	if g.c.instances.findIndex(.decl == gi.fnd) is ii:
		g.c.checkInstance(ii)
	if gi.implDecl is impl:
		g.setSubstOf(impl)
	else:
		g.c.subst = gi.sub.copy()
	g.irGivenNow = move gi.givens
	g.genFunction(gi.fnd, gi.implType, gi.key)
	g.irGivenNow = []
	g.setSubst([], [])

# the given parameter a name in scope is: its place in lw.given, or -1
fn irGivenAt(lw IrLower, name str):
	if lw.given.isEmpty: return -1
	at = lw.irLookupAt(name)
	if at < 0: return -1
	lw.given.findIndex(.at == at) ?? -1

# the parameters of fnd the argument nodes args give a function to that fnd calls, gives on
# or lends to a lambda of its own: each one's index and what is given
fn irGivens(mut g Gen, lw IrLower, fnd NodeId, args NodeId[]):
	out = []
	if nodes[fnd].hasFlag(flagExtern) or nodes[fnd].sub.isEmpty or
		args.len != nodes[fnd].kids.len or args.any(nodes[it].kind == nNamedArg):
		return out
	for i, arg in args:
		if nodes[nodes[fnd].kids[i]].ival != modeRead or g.tyK(g.ty(arg)) != tFn: continue
		if g.irGivenOf(lw, arg, i) is given and g.irCallsOnly(fnd, i):
			out.push(given)
	out

# what the argument arg gives a parameter of a fn type (at its index at), or none: a lambda
# lent to the call that does not read self (its captures the caller's leaves), a function by
# name, or a parameter given one itself
fn irGivenOf(mut g Gen, lw IrLower, arg NodeId, at i64) IrGiven?:
	k = nodes[arg].kind
	if k == nIdent:
		gi = lw.irGivenAt(nodes[arg].text)
		if gi >= 0:
			given = lw.given[gi].copy()
			given.at = at
			return given
		if not nodes[arg].hasFlag(flagFnRef) or lw.irLookupAt(nodes[arg].text) >= 0 or
			g.irFieldOfThis(lw, nodes[arg].text):
			return none
		fnd = try g.c.findFunc(nodes[arg].text)
		if not nodes[fnd].names.isEmpty or nodes[fnd].hasFlag(flagExtern) or
			nodes[fnd].kids.len != tys[g.ty(arg)].params.len:
			return none
		return IrGiven(at, node = arg, site = Subst(names = [], types = []))
	if k != nLambda or "self" in nodes[arg].names2() or not g.irFlagged(arg, flagBorrowLambda):
		return none
	held = g.irHeldOf(lw, arg)
	caps i64[,] = []
	for ci in 0..nodes[arg].names2().len:
		caps.push(
			[] if held.any(.at == ci) else lw.irLookup(nodes[arg].names2()[ci]) ?? return none
		)
	IrGiven(at, node = arg, site = lw.site.copy(), held, caps)

# the lambda e's captures given in scope that it points at, each its capture's index (a body of
# e's own calls them as given)
fn irHeldOf(mut g Gen, lw IrLower, e NodeId):
	out = []
	for ci in 0..nodes[e].names2().len:
		name = nodes[e].names2()[ci].copy()
		gi = lw.irGivenAt(name)
		if gi >= 0 and g.capByPointer(e, ci):
			h = lw.given[gi].copy()
			h.at = ci
			out.push(h)
	out

# what an instance's label and lowering read of a given function: no place in this code
fn irGivenStatic(given IrGiven) IrGiven:
	IrGiven(
		at = given.at,
		node = given.node,
		site = given.site.copy(),
		held = given.held.map(.irGivenStatic()),
		part = given.part
	)

fn irGivenWhat(g Gen, given IrGiven) str:
	if nodes[given.node].kind != nLambda: return nodes[given.node].text.copy()
	part = "" if given.part < 0 else "#{given.part}"
	"{given.node}{part}{given.held.map("[{.at}={g.irGivenWhat(it)}]").join("")}"

# whether fnd's parameter i is worth an instance made for the function given it: fnd calls it,
# gives it on to a parameter worth one or to a pipeline's step, or lends it to a lambda of its
# own that does; any other use and the instance would only make the closure whole again
fn irCallsOnly(mut g Gen, fnd NodeId, i i64):
	key = "{fnd}:{i}"
	if g.irWorth.get(key) is known: return known
	g.irWorth[key.copy()] = true   # a recursion back to it: the rest decides
	g.c.readBody(fnd)
	worth = g.irOnlyCalled(nodes[fnd].sub[0], nodes[nodes[fnd].kids[i]].text.copy(), false)
	g.irWorth[key] = worth
	worth

# the same for the name p under node e, itself a call's callee when called
fn irOnlyCalled(mut g Gen, e NodeId, p str, called bool) bool:
	k = nodes[e].kind
	if nodes[e].text == p and not (k == nIdent and called): return false
	if k == nCall:
		for j in 1..nodes[e].kids.len:
			arg = nodes[e].kids[j]
			if nodes[arg].kind == nIdent and nodes[arg].text == p:
				if not g.irGivesOn(e, j - 1): return false
			elif not g.irOnlyCalled(arg, p, false):
				return false
		if not g.irOnlyCalled(nodes[e].kids[0], p, true): return false
	elif not nodes[e].kids.copy().all(g.irOnlyCalled(it, p, false)):   # (a body read may change the nodes)
		return false
	nodes[e].sub.copy().all(g.irOnlyCalled(it, p, false))

# whether the call e's argument j goes to a parameter worth an instance or to a pipeline step
fn irGivesOn(mut g Gen, e NodeId, j i64):
	callee = nodes[e].kids[0]
	if nodes[e].kids.any(nodes[it].kind == nNamedArg): return false
	if nodes[callee].kind == nIdent: return g.irParamWorth(g.c.findFunc(nodes[callee].text), j)
	if nodes[callee].kind != nField: return false
	obj = nodes[callee].kids[0]
	if stepCalls(nodes[callee].text) and nodes[e].kids.len == 2:
		return not (nodes[obj].kind == nCall and nodes[nodes[obj].kids[0]].kind == nField and
				nodes[nodes[obj].kids[0]].text == "parallel")
	ot = g.ty(obj)
	while g.tyK(ot) == tRef or g.tyK(ot) == tBox:
		ot = innerOf(tys, ot)
	g.tyK(ot) == tStruct and g.irParamWorth(g.c.findMethod(tys[ot].name, nodes[callee].text), j)

fn irParamWorth(mut g Gen, maybeFnd NodeId?, j i64):
	fnd = maybeFnd ?? return false
	nodes[fnd].kind == nFnDecl and not nodes[fnd].hasFlag(flagExtern) and
		not nodes[fnd].sub.isEmpty and j < nodes[fnd].kids.len and
		nodes[nodes[fnd].kids[j]].ival == modeRead and g.irCallsOnly(fnd, j)

# the label of fnd's instance (key its own) for what givens gives it, noted to be made when
# something calls it: a method's type and generic impl
fn irGivenKey(
	mut g Gen,
	key str,
	fnd NodeId,
	givens IrGiven[],
	implType TypeId?,
	implDecl NodeId?
):
	made = key.copy()
	for given in givens:
		made = "{made}$given{given.at}:{g.irGivenWhat(given)}"
	new = not g.irGivenInstances.any(.key == made)
	if g.asksNoting:
		match g.givenAsk(made, fnd, givens, implType, implDecl, new):
			ask: g.noteAsk(ask)
			none: g.asksSpoiled = true   # (keptir.zap: not asked for again)
	if new:
		g.irGivenInstances.push(
			IrGivenInstance(
				key = made.copy(),
				fnd,
				sub = g.c.subst.copy(),
				implType,
				implDecl,
				givens = givens.map(.irGivenStatic())
			)
		)
	made

# the instance a kept form's lowering made for the functions given (givenAsk) made again
fn irGivenAgain(mut g Gen, ask KeptAsk):
	if g.irGivenInstances.any(.key == ask.text): return
	givens = []
	for k in 0..(ask.types.len - 1) / 3:
		givens.push(
			IrGiven(
				at = ask.types[1 + 3 * k],
				node = NodeId(ask.types[2 + 3 * k]),
				site = Subst(names = [], types = []),
				part = ask.types[3 + 3 * k]
			)
		)
	g.irGivenInstances.push(
		IrGivenInstance(
			key = ask.text.copy(),
			fnd = NodeId(ask.types[0]),
			sub = Subst(names = [], types = []),
			implType = none,
			implDecl = none,
			givens
		)
	)

# the given parameters of the instance being lowered, where it starts: each one's closure (the
# parameter declared at at) and the captures read from it
fn irGivensAtEntry(mut g Gen, mut lw IrLower, params NodeId[]):
	for given in g.irGivenNow:
		at = lw.irLookupAt(nodes[params[given.at]].text)
		loaded = g.irGivenLoaded(lw, given.copy(), lw.vals[at][0])
		loaded.at = at
		lw.given.push(loaded)

# given with its closure at closure: the captures its lambda reads (and those of the functions
# they hold) loaded from the environment here
fn irGivenLoaded(mut g Gen, mut lw IrLower, move given IrGiven, closure i64) IrGiven:
	given.closure = closure
	given.inMemory = true
	if nodes[given.node].kind != nLambda or nodes[given.node].names2().isEmpty: return given
	given.caps = g.irCapsOf(lw, given.node, g.irEnvOf(lw, closure))
	for h in 0..given.held.len:
		given.held[h] = g.irGivenLoaded(lw, given.held[h].copy(), given.caps[given.held[h].at][0])
	given

# the closure given is passed as: its own, one without code (a function by name), or one whose
# environment is made in this frame from the captures (none to drop: a lent lambda's are
# pointers and plain numbers)
fn irGivenClosureWord(mut g Gen, mut lw IrLower, given IrGiven):
	if given.closure >= 0: return given.closure
	if nodes[given.node].kind != nLambda: return g.irFnValue(lw, given.node, false)[0]
	slot = g.irClosureSlot(lw, lw.irConstOf(irInt, 0), g.irGivenEnv(lw, given))
	lw.literals.push(slot)
	slot

# the environment of a given lambda whose captures are the caller's leaves, in this frame
fn irGivenEnv(mut g Gen, mut lw IrLower, given IrGiven) i64:
	caps = given.caps.copy()
	for h in given.held:
		caps[h.at] = [g.irGivenClosureWord(lw, h)]
	g.irEnvBlock(lw, given.node, caps, false)

# the given function as a whole closure { code, environment } where it is read as a value (its
# environment headed now, so a copy of it copies the captures)
fn irGivenValue(mut g Gen, mut lw IrLower, given IrGiven):
	if nodes[given.node].kind != nLambda: return g.irFnValue(lw, given.node)[0]
	code = g.irGivenCode(lw, given)
	env = g.irEnvOf(lw, given.closure) if given.closure >= 0 else g.irGivenEnv(lw, given)
	if not lw.ok: return -1
	types = g.irEnvTypes(given.node)
	if not types.isEmpty:
		head = lw.f.irVreg(irInt)
		irPut(
			lw,
			IrInst(
				op = irFnAddr,
				dst = head,
				imm = g.envFnLabel(types, types.sum(g.c.slotSize(it)))
			)
		)
		lw.irPut(IrInst(op = irStore, a = env, c = head))
	slot = g.irClosureSlot(lw, code, env)
	lw.literals.push(slot)
	slot

# the given lambda's body as a function of its own, lowered under its site's substitution
fn irGivenCode(mut g Gen, mut lw IrLower, given IrGiven):
	sav = move g.c.subst
	g.c.subst = given.site.copy()
	code = g.irLambdaCode(lw, given.node, given.held)
	g.c.subst = sav
	code

# a call of a given parameter with the argument nodes args: the function by name called, or the
# lambda's body in place
fn irGivenCall(mut g Gen, mut lw IrLower, given IrGiven, args NodeId[]) i64[]:
	if nodes[given.node].kind != nLambda:
		return g.irNamedCall(
			lw,
			g.c.findFunc(nodes[given.node].text) ?? fail("no function given"),
			args
		)
	# (a key lambda's node is typed as its key: a part takes the element)
	params = args.map(g.ty(it)) if given.part >= 0 else tys[g.ty(given.node)].params.copy()
	if params.len != args.len or args.any(nodes[it].kind == nNamedArg):
		return lw.irRefused("a lambda's arguments")
	values = []
	for i, arg in args:
		values.push([g.irAddressOf(lw, arg)] if g.irByAddress(params[i]) else g.irValue(lw, arg))
	if not lw.ok: return []
	g.irGivenCallValues(lw, given, values)

# the same with each argument's leaves (a value by address: its address): the lambda's body in
# place, or when it cannot be, the lambda lowered as a function of its own and called
fn irGivenCallValues(mut g Gen, mut lw IrLower, given IrGiven, values i64[,]) i64[]:
	if nodes[given.node].kind != nLambda:
		if values.len != 1: return lw.irRefused("a call of {nodes[given.node].text} with values")
		return g.irFnRefValue(lw, given.node, values[0])
	m = g.irMarkOf(lw)
	value = g.irLambdaInPlace(lw, given, values)
	if lw.ok or given.part >= 0: return value   # (a part has no function of its own)
	if irInlineWord().on():
		g.irSay("ir: lambda {given.node} not in place: {lw.why}")
	g.irRollback(lw, m)
	ft = g.ty(given.node)
	vs = []
	for i, v in values:
		vs.push(g.irClosureArg(lw, tys[ft].params[i], v))
	slot = g.irGivenValue(lw, given)
	if not lw.ok: return []
	g.irClosureCallAt(lw, ft, slot, vs)

# the environment of the closure at closure
fn irEnvOf(mut g Gen, mut lw IrLower, closure i64) i64:
	lw.irDef(irInt, IrInst(op = irLoad, a = closure, imm = 8))

# the given lambda's body in place for its parameters' leaves values, its captures where given
# keeps them (a changed one read from its address and written back after), nothing of this
# function's in its scope
fn irLambdaInPlace(mut g Gen, mut lw IrLower, given IrGiven, values i64[,]):
	lam = given.node
	ft = g.ty(lam)
	if (given.part < 0 and tys[ft].params.len != values.len) or
		given.caps.len != nodes[lam].names2().len:
		return lw.irRefused("a lambda's arguments")
	mark = lw.names.len
	savedFloor = lw.floor
	savedThis = lw.thisType
	sav = move g.c.subst
	g.c.subst = given.site.copy()
	lw.floor = mark
	lw.thisType = none
	back = []
	for ci in 0..nodes[lam].names2().len:
		name = nodes[lam].names2()[ci].copy()
		ct = nodes[lam].ints()[ci]
		if given.held.find(.at == ci) is h:
			lw.irDeclare(name, given.caps[ci].copy())
			inner = h.copy()
			inner.at = lw.names.len - 1
			lw.given.push(inner)
		elif given.inMemory and name in nodes[lam].bounds() and not g.irByAddress(ct):
			leaves = g.irLoadValue(lw, ct, given.caps[ci][0], -1, 0)
			back.push(IrMutScalar(given.caps[ci][0], leaves.copy(), ct))
			lw.irDeclare(name, leaves)
		else:
			lw.irDeclare(name, given.caps[ci].copy())
	for i in 0..values.len:
		lw.irDeclare(nodes[lam].names[i], values[i].copy())
	body = nodes[lam].kids[0] if nodes[lam].sub.isEmpty else nodes[lam].sub[0]
	value = g.irKeyPartValue(lw, g.irKeyParts(lam)[given.part]) if given.part >= 0
		else g.irBodyInPlace(lw, body, retOf(tys, ft))
	if lw.ok and not lw.f.irEnded():
		for b in back:
			g.irStoreLeaves(lw, b.ty, b.addr, -1, 1, 0, b.leaves)
	g.irScopeEnd(lw, mark)
	g.c.subst = sav
	lw.floor = savedFloor
	lw.thisType = savedThis
	value
