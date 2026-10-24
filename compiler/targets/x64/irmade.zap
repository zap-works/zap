# The functions a round of genCalledFunctions lowered, made together: their passes (irSimplify, the
# ownership verified after each) and their registers run on every processor at once, each
# function's on its own form (irpipe.zap), then their code is emitted one after another in the
# order they were lowered, so the executable is the same whatever the processors.

alias nodes = g.c.nodes

# A function lowered, waiting to be made: a declaration's (node), a lambda's (node, lambda), or
# the module variables' code (no node: irEmitPlain's).
type IrMade:
	key str
	node NodeId?
	lambda bool = false
	ret TypeId   # what it gives (an instance's substitution in force when it was lowered)
	f IrFn
	cached u8[]? = none   # the form the cache holds for it as lowered (irCacheLookup)
	lowered str = ""   #   else its form as lowered, the cache's key, and the form its passes
	simplified u8[] = []   #   made (irCacheStore)
	numbers i64[,] = []   # the numbers the cache writes by their places (irNumbersOf)
	shard i64 = 0   # the cache's file of it (irShardOf)
	check IrOwnCheck = IrOwnCheck()   # its ownership verified after each pass
	em IrEmit? = none   # its form and registers, ready to be emitted
	state FnState? = none   #   with its frame's slots taken (irEmitOf)
	once PendingFn? = none   # checked once for a group of entries: noted once made clean
	clean bool = true   #   and whether its lowering found no error
	arm bool = false   # built for AArch64 (its registers: irAllocate)
	passed bool = false   # its form its passes' already (a kept one: keptir.zap)
	kept KeptPlan? = none   # to be kept: its form as its passes make it written to keptForm
	keptForm u8[] = []

# the lambdas the function lowered (and those they hold), each a function of its own
fn irMadeLambdas(mut g Gen):
	lambdaFns = move g.irLambdaFns
	g.irLambdaFns = []
	while true:
		l = lambdaFns.pop() ?? break
		if not l.checked:
			file = g.irFileNow.copy()
			g.irOwnProgram(l.f, l.key, file)   # (a lambda of the globals' code)
			g.irOwnSettle()
		lam = l.lam ?? fail("a lambda without its node")
		g.made.push(
			IrMade(
				key = l.key.copy(),
				node = lam,
				lambda = true,
				ret = retOf(g.c.types, g.ty(lam)),
				f = move l.f
			)
		)

# the functions lowered made: their passes on every processor (begun while the lowering went
# on: irpipe.zap), then their code in order
fn irMakeAll(mut g Gen):
	g.irShip()
	made = g.irPipeDrain()
	for i in 0..made.len:
		g.keepMadeForm(made[i])
		irOwnSeconds += made[i].check.seconds
		made[i].irCacheStore()
		verified = g.irVerified(made[i])
		if made[i].once is p:
			g.noteChecked(p, made[i].clean and verified)
		g.irEmitMade(made[i])

# m's form simplified (or the cache's taken) and its ownership verified as lowered and after each
# pass, then its registers allocated, its frame's slots taken and the frame planned
fn irPasses(mut m IrMade):
	if not m.passed:
		m.f.irOwnAfter("lowering")
		if not m.irTakeCached():
			m.f.irSimplify(m.arm)
			m.f.irOwnAfter("the passes")
			if m.lowered != "" and not m.f.irWrite(m.simplified, irRenamingOf(m.numbers, false)):
				m.lowered = ""   # a number the lowered form did not hold: not kept
		m.writeKeptForm()
	m.check = move m.f.check
	m.f.check = IrOwnCheck()
	if m.arm:
		m.f.a64NibbleMasks()
	rs = m.f.irAllocate(m.arm)
	state = newFnState(none, none, m.ret)
	em = state.irEmitOf(move m.f, move rs)
	if m.arm:
		em.a64PlanFrame()
	else:
		em.irPlanFrame()
	m.em = em
	m.f = newIrFn()
	m.state = move state

# whether m's form is the cache's (its numbers back to the program's), its ownership verified
fn irTakeCached(mut m IrMade):
	cached = m.cached ?? return false
	r = Reader(cached)
	f = r.irRead(irRenamingOf(m.numbers, true)) ?? return false
	f.check = move m.f.check
	m.f = move f
	m.f.irOwnAfter("the cache")
	true

# the source file whose cache holds m: its declaration's, "" for the module variables' code
fn madeFile(g Gen, m IrMade):
	node = m.node ?? return ""
	nodes[node].file().copy()

# whether no pass broke m's ownership: else an error of the build naming the function and the pass
fn irVerified(mut g Gen, m IrMade):
	fault = m.check.fault ?? return true
	if m.check.dump != "":
		eprint(m.check.dump.trimmedEnd())
	owner = "v{fault.owner}{" ({typeStr(g.c.types, TypeId(fault.t))})" if fault.t >= 0 else ""}"
	at = "b{fault.block}:{fault.inst}, line {fault.line}:{fault.col}"
	eprint(
		compileError(
			"OwnershipBroken",
			["{m.key}", "{m.check.pass}", "{owner} {fault.what} ({at})"]
		)
	)
	irMissing += 1
	false

# m's code: entered as any function, its frame its own
fn irEmitMade(mut g Gen, mut m IrMade):
	em = move m.em ?? fail("a function made without its registers")
	m.em = none
	if irWord().on():
		eprint("ir: {m.key}: {em.f.classes.len} vregs, {em.rs.order.len} blocks, {em.rs.spilled.count(it)} spilled")
	if irDumpWord().on():
		em.f.irDump(em.rs)
	r = g.beginFunction()
	g.a.asmPlace(fnLabel(g.fnLabels, g.a, m.key))
	match m.node:
		node:
			if not m.lambda:
				g.curFile = g.debugFile(nodes[node].file())   # (its lambdas' too)
				g.inRt = nodes[node].mod() == "rt"
			g.atNode(node)
			g.noteDebugLine(g.curLine, g.curCol, g.curFile)
		none:
			g.curFnKey = m.key.copy()
	g.f = move m.state ?? fail("a function made without its frame")
	m.state = none
	g.irEmitWhole(move em)
	g.endFunction(m.key, r)
