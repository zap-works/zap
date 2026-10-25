# What one walk of each function's body finds, once every body is checked, read by the two
# summaries made then: what a function changes through its parameters and in the module
# variables (effects.zap) and what it does besides its result (purity.zap). A function's record
# holds both kinds of edge of the one call graph: the functions it calls by name or as a method,
# which its changes follow, and every function it reaches, one it names as a value included,
# which what it does follows; and what a call through a function value may change: the lambdas it
# writes and the functions it takes as values.

alias nodes = c.nodes
alias kidIds = c.kidIds

type FnFacts:
	fnd NodeId
	fields str[] = []   # a method's: the names of its receiver's fields
	names str[] = []   # the names its body mentions (a body that is not Zap the summary follows: none)
	calls NodeId[] = []   # the functions it calls by name or as a method (likewise)
	closureCalls bool = false   # whether it calls a function value
	placesChanged ChangeAt[] = []   # the places its body changes, in the order of the walk (effects.zap)
	own i64 = 0   # what its body does itself (purity.zap's bits)
	reaches NodeId[] = []   # the functions it calls or names as a value
	keeps i64 = doesUnknown   # what of theirs it does too
	memory bool = false   # a memory root: its calls are on no cycle
	lambdas LambdaChanges[] = []   # what each lambda its body writes changes and calls, in the order of the walk
	valued NodeId[] = []   # the functions its body takes as values (by name)

# every function's and method's record, in the order of the declarations, the bodies walked on
# the first call (but those whose records the kept stages kept: keptfacts.zap); a summary takes
# them while it reads them and gives them back (c.facts)
fn takeFacts(mut c Checker) FnFacts[]:
	if not c.factsMade:
		mod = c.curMod
		file = c.curFile.copy()
		out = []
		for d in c.decls:
			k = nodes[d].kind
			if k == nFnDecl:
				out.push(c.keptFacts.remove(d) ?? c.fnFacts(d, []))
			elif k == nImplDecl:
				fields = []
				sd = c.findTypeDecl(nodes[d].text)
				if sd is sd:
					fields.extend(nodes[sd].kids(kidIds).map(nodes[it].text.copy()))   # the list is the record's own
				for m in nodes[d].kids(kidIds).copy():
					out.push(c.keptFacts.remove(m) ?? c.fnFacts(m, fields.copy()))
		c.facts = move out
		c.factsMade = true
		c.curMod = mod
		c.curFile = file
	move c.facts

# the record of fnd: an extern's by its name, a body's by one walk of it; a memory root does
# none of what makes a function impure, and allocates; running out of memory (as a loop that
# never ends) and the allocator's first call reading the trace options, a call of itself once,
# are no stop it counts
fn fnFacts(mut c Checker, fnd NodeId, move fields str[]):
	f = FnFacts(fnd, fields)
	name = c.writtenName(fnd).copy()
	if nodes[fnd].hasFlag(flagExtern):
		f.own = externDoes(name) | (doesWait if name in waitRoots else 0)
	elif not nodes[fnd].sub().isEmpty:
		c.readBody(fnd)
		c.enterModuleOf(fnd)
		seen {str: bool} = {}
		c.noteFacts(nodes[fnd].sub()[0], f, seen, not c.opaqueFunction(fnd))
		f.names = seen.keys()
	if name in allocationRoots or name in freeRoots:
		f.keeps = doesAllocate | doesWait
		f.own = (f.own & f.keeps) | (doesAllocate if name in allocationRoots else 0)
		f.memory = true
	f

# what e and everything under it do themselves and the functions they reach; with changes, the
# names they mention, the functions they call and their calls of function values
fn noteFacts(mut c Checker, e NodeId, mut f FnFacts, mut seen {str: bool}, changes bool):
	c.noteCallable(e, f)
	if changes:
		c.noteMention(e, seen, f)
		c.noteChange(e, f.placesChanged)
	bits, d = c.nodeDoes(e)
	f.own |= bits
	if d is d and d not in f.reaches:
		f.reaches.push(d)
	for kid in nodes[e].kids(kidIds):
		c.noteFacts(kid, f, seen, changes)
	for sb in nodes[e].sub():
		c.noteFacts(sb, f, seen, changes)

# a lambda e is, or the function it takes as a value
fn noteCallable(c Checker, e NodeId, mut f FnFacts):
	if nodes[e].kind == nLambda:
		l = LambdaChanges()
		c.noteLambda(e, l)
		f.lambdas.push(l)
	if nodes[e].kind == nIdent and nodes[e].hasFlag(flagFnRef):
		d = c.findFunc(nodes[e].text)
		if d is d and d not in f.valued: f.valued.push(d)

# the name node e mentions, the function it calls by name or as a method, its call of a function value
fn noteMention(c Checker, e NodeId, mut seen {str: bool}, mut f FnFacts):
	k = nodes[e].kind
	if k == nIdent or k == nLet:
		seen[nodes[e].text.copy()] = true
	if k != nCall: return
	if nodes[e].hasFlag(flagClosure):
		f.closureCalls = true
		return
	if c.calledDecl(e) is d and d not in f.calls:
		f.calls.push(d)

# the function a call by name or as a method names, or none
fn calledDecl(c Checker, e NodeId):
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind == nIdent: return c.findFunc(nodes[callee].text)
	if nodes[callee].kind == nField: return c.calledMethod(callee)
	none
