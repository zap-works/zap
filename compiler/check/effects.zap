# What a function changes through each of its `mut` parameters (and `this`, for a `mut fn`), as
# paths relative to the parameter ("$.vars", "$.nodes[].names2"; "$" is the whole value; "$.nodes+"
# a list only grown at its end, its elements left as they were), and in
# each module variable that owns memory, under the key "@name": in its body or in the functions
# it calls. A call through a function value may change what any function used as a value changes
# (a lambda's body, a function passed by name), in each module variable. The
# ownership analysis uses it for a place lent to a call that also takes its owner as `mut`
# (`addVar(c, nodes[p].text, ...)`): the call is only wrong when what it changes overlaps the
# place it reads, so a function that changes `c.vars` may read `nodes[p].text` without a copy.
#
# The summaries are found together, after every body is checked (the calls inside a body need
# its types): the one walk of each body (bodyfacts.zap) lists the places it changes, then each
# summary starts empty and grows, over a worklist of the callers of what grew, until none changes.
# A runtime or extern function changes its `mut` parameters as a whole (its body works on raw
# memory).

# a place lent to a call whose `mut` parameter `param` of `callee` receives `arg`, which holds it
alias nodes = c.nodes
alias tys = c.types

type LentCheck:
	file str
	line i64
	col i64
	lent str   # the place lent ("nodes[].text")
	callee NodeId   # the function or method called
	param str   # its parameter that receives the owner ("self" for the receiver)
	arg str   # the place given to that parameter ("c")
	message str = ""   # the error when they overlap (a borrow held across the call), else the lent one's
	whole bool = false   # the error only when the call changes the place itself, not a part of it
	headersKept bool = false   # the place a pipeline goes over, its header read once (changeOverlaps)

# the key of a summary: a function and one of its parameters
fn effectKey(fnd NodeId, param str):
	"{fnd}:{param}"

# the paths a call to `fnd` changes through `param` when `arg` is given to it
fn changedThrough(c Checker, fnd NodeId, param str, arg str):
	out = []
	if c.effects.get(effectKey(fnd, param)) is paths:
		for p in paths:
			out.push(arg + p[1..])
	out

# the length a path is kept to: a deeper one is cut to its first parts, which covers it
fn cappedLen(p str):
	parts = 0
	for i, b in p:
		if b == 46 or b == 91:
			parts += 1
			if parts > 4: return i
	p.len

# Changed paths, kept without paths another one covers ("$.a" covers "$.a.b"), each also in an
# index, so a path met again (the summaries of callees repeat each other's) is found at once.
type PathSet:
	paths str[] = []
	have {str: bool} = {}

	# adds a path, cut to its first parts, unless one in the set covers it; those it covers go
	fn add(p str):
		q = p[..cappedLen(p)]
		if have.get(q) != none: return
		for at, ch in q:   # a path covering q is a prefix of it ending where a part does
			if (ch == 46 or ch == 91) and have.get(q[..at]) != none: return
		i = 0
		while i < paths.len:
			if paths[i].startsWith(q) and pathsOverlap(paths[i], q):
				have.remove(paths[i])
				paths.remove(i)
			else:
				i += 1
		paths.push(q.copy())
		have[q.copy()] = true

	fn addAll(ps str[]):
		for p in ps:
			add(p)

	fn has(p str):
		have.get(p) != none

# A place a body changes, found in the one walk of it: its root's name and the path below the
# root, and for a place given to a `mut` parameter of a function with a body, that function and
# parameter (what it changes there is in its summary).
type ChangeAt:
	root str
	below str
	callee NodeId? = none
	param str = ""
	named bool = false   # the variable named root given another value: no field of the receiver

# the path of change ch relative to the parameter `param` ("$..."), or "" when it is no part of
# it; in a method, a field named alone is a part of this
fn changedPath(ch ChangeAt, param str, fields str[]):
	if ch.root == param: return "${ch.below}"
	if not ch.named and param == "self" and ch.root in fields: return "$.{ch.root}{ch.below}"
	""

# A change to one summarized parameter: its path relative to the parameter, and the slot
# (EffectSlots) of the callee's parameter it was given to, -1 when the body changes it itself.
type PlannedChange:
	path str
	through i64 = -1

# the changes to `param` among a body's
fn planChanges(es EffectSlots, changes ChangeAt[], param str, fields str[]):
	out = []
	for ch in changes:
		p = ch.changedPath(param, fields)
		if p == "": continue
		match ch.callee:
			callee:
				at = es.slotOf(callee, ch.param)
				if at >= 0: out.push(PlannedChange(p, at))
			none:
				out.push(PlannedChange(p))
	out

# the paths the planned changes make, by the summaries so far
fn addPlanned(es EffectSlots, plan PlannedChange[], mut out PathSet):
	for ch in plan:
		if ch.through < 0:
			out.add(ch.path)
		else:
			for q in es.sums[ch.through]:
				out.add(ch.path + q[1..])

# place e changed (only grown at its end, when grown), through `param` of `callee` when one is given
fn notePlace(
	c Checker,
	e NodeId,
	callee NodeId?,
	param str,
	mut out ChangeAt[],
	grown bool = false
):
	found, below = c.placePath(e)
	root = found ?? return
	out.push(
		ChangeAt(nodes[root].text.copy(), "{below}+" if grown else below, callee, param.copy())
	)

# the keys ("@name") of the module variables that own memory: the ones a borrow can point into
fn globalKeys(mut c Checker):
	out = []
	for d in c.decls:
		if nodes[d].kind == nConstDecl and nodes[d].hasFlag(flagMut) and
			not c.isPlainType(c.constTypeOf(d)):
			out.push("@{nodes[d].text}")
	out

# whether a function's body is not Zap the summary can follow (runtime, extern)
fn opaqueFunction(c Checker, fnd NodeId):
	nodes[fnd].mod() == "rt" or nodes[fnd].hasFlag(flagExtern) or nodes[fnd].sub.isEmpty

# The changes the arguments of call e make: each argument given to a `mut` (or move) parameter
# of `callee`.
fn noteCallChanges(c Checker, e NodeId, callee NodeId, first i64, mut out ChangeAt[]):
	nparams = nodes[callee].kids.len
	opaque = c.opaqueFunction(callee)
	for i in 0..argCount(c, e):
		if i + first >= nparams: break
		p = nodes[callee].kids[i + first]
		mode = nodes[p].ival
		if mode != modeMut and mode != modeMove: continue
		through NodeId? = none   # changed as a whole
		if not opaque and mode == modeMut:
			through = callee
		c.notePlace(c.argAt(e, i), through, nodes[p].text, out)

# the changes node e itself makes, not those under it
fn noteChange(c Checker, e NodeId, mut out ChangeAt[]):
	k = nodes[e].kind
	if k == nAssign:
		c.notePlace(nodes[e].kids[0], none, "", out)
	elif k == nLet and not nodes[e].kids.isEmpty:
		out.push(ChangeAt(nodes[e].text.copy(), "", named = true))   # given another value
		v = nodes[e].kids[0]
		if nodes[v].kind == nUnary and nodes[v].ival == unMutRef:
			c.notePlace(nodes[v].kids[0], none, "", out)   # changed through the reference, anywhere after
	elif k == nCall and not nodes[e].hasFlag(flagClosure):
		callee = nodes[e].kids[0]
		if nodes[callee].kind == nIdent:
			if c.findFunc(nodes[callee].text) is fnd:
				c.noteCallChanges(e, fnd, 0, out)
		elif nodes[callee].kind == nField:
			obj = nodes[callee].kids[0]
			if c.receiverHasMethods(obj):
				if c.calledMethod(callee) is md:
					if nodes[md].hasFlag(flagMut):
						through NodeId? = none
						if not c.opaqueFunction(md):
							through = md
						c.notePlace(obj, through, "self", out)
					c.noteCallChanges(e, md, 0, out)
			elif c.methodIsMutating(nodes[callee].text):
				c.notePlace(obj, none, "", out, grown = nodes[callee].text == "push")

# whether the receiver of a method call is a struct or an enum (a method of the program's, not
# a built-in one)
fn receiverHasMethods(c Checker, obj NodeId):
	ot = c.receiverType(obj)
	c.tKind(ot) == tStruct or c.tKind(ot) == tEnum

fn receiverType(c Checker, obj NodeId):
	ot = typeOf(nodes, obj)
	innerOf(tys, ot) if c.tKind(ot) == tRef else ot

# the method a call's callee `obj.name` names, or none
fn calledMethod(c Checker, callee NodeId):
	obj = nodes[callee].kids[0]
	if not c.receiverHasMethods(obj): return none
	c.findMethod(tys[c.receiverType(obj)].name, nodes[callee].text)

# The summaries while they are found, a slot each: the tracked parameters of a function
# (trackedParams, the module variables first) take consecutive slots, the same for every entry of
# that function.
type EffectSlots:
	entries {NodeId: i64[]}   # a function -> its entries in the facts
	tracked str[,]   # per entry: its tracked parameters
	base i64[]   # per entry: its first slot
	plans PlannedChange[,] = []   # per slot: what the body changes there itself or through calls
	hidden bool[] = []   # per slot of a module variable: the body never sees it
	sums str[,] = []   # per slot: the summary so far
	values str[,] = []   # per module variable: what a call through a function value may change

# the slot of a function's tracked parameter, or -1
fn slotOf(es EffectSlots, fnd NodeId, param str):
	at = es.entries.get(fnd) ?? return -1
	i = at[0]
	k = es.tracked[i].findIndex(it == param) ?? return -1
	es.base[i] + k

# the first slot of a function, or -1 when it has no entry
fn baseOf(es EffectSlots, fnd NodeId):
	at = es.entries.get(fnd) ?? return -1
	es.base[at[0]]

fn effectSlots(c Checker, fns FnFacts[], globals str[]):
	es = EffectSlots(entries = {}, tracked = [], base = [])
	for i in 0..fns.len:
		addUnder(es.entries, fns[i].fnd, i, once = true)
	slots = 0
	for i in 0..fns.len:
		params = c.trackedParams(fns[i].fnd, globals)
		first = es.entries[fns[i].fnd][0]
		if first < i:
			es.base.push(es.base[first])
		else:
			es.base.push(slots)
			slots += params.len
		es.tracked.push(params)
	for i in 0..fns.len:
		if es.base[i] + es.tracked[i].len <= es.plans.len: continue   # a later entry of a function
		for param in es.tracked[i]:
			hidden, plan = c.planSummary(es, fns[i], param)
			es.plans.push(plan)
			es.hidden.push(hidden)
			es.sums.push([])
	loop globals.len:
		es.values.push([])
	es

# What the body of f changes in one tracked parameter (or module variable), and whether it hides a
# module variable: the runtime and extern functions never see one, and a parameter or a field of
# the receiver with its name hides it. A runtime or extern function changes its parameters as a
# whole.
fn planSummary(c Checker, es EffectSlots, f FnFacts, param str) (bool, PlannedChange[]):
	if param.startsWith("@"):
		name = param[1..]
		if c.opaqueFunction(f.fnd) or name in f.fields or
			nodes[f.fnd].kids.any(nodes[it].text == name):
			return (true, [])
		if name not in f.names: return (false, [])
		return (false, es.planChanges(f.placesChanged, name, []))
	if c.opaqueFunction(f.fnd): return (false, [PlannedChange("$")])
	(false, es.planChanges(f.placesChanged, param, f.fields))

# whether the summaries of slot k of the callees at those bases are all empty
fn noneChanged(es EffectSlots, calleeBases i64[], k i64):
	for b in calleeBases:
		if not es.sums[b + k].isEmpty: return false
	true

# the summary of slot k of entry i under the summaries found so far; a module variable's also
# takes what the body calls: what any function value may change, each function's own
fn summarize(es EffectSlots, closureCalls bool, i i64, k i64, calleeBases i64[]):
	slot = es.base[i] + k
	through = k < es.values.len and not es.hidden[slot]
	if es.plans[slot].isEmpty and
		(
			not through or
				(not closureCalls or es.values[k].isEmpty) and es.noneChanged(calleeBases, k)
		):
		return []   # (most summaries of a module variable: nothing reaches it)
	out = PathSet()
	es.addPlanned(es.plans[slot], out)
	if through:
		if closureCalls:
			out.addAll(es.values[k])
		for b in calleeBases:
			out.addAll(es.sums[b + k])
	out.paths

fn sameSet(a str[], b str[]):
	if a.len != b.len: return false
	a.all(it in b)

# the parameters of a function that a summary is kept for, then the module variables
fn trackedParams(c Checker, fnd NodeId, globals str[]):
	out = globals.copy()
	if nodes[fnd].hasFlag(flagMut):
		out.push("self")
	for p in nodes[fnd].kids:
		if nodes[p].ival == modeMut:
			out.push(nodes[p].text.copy())   # the list is the summary's own
	out

# every summary, grown together until none changes: each slot is summarized once, the
# functions' callees first, then again whenever a slot it reads grows (a callee's summary, or what
# a call through a function value may change)
fn findEffects(mut c Checker):
	fns = c.takeFacts()
	globals = c.globalKeys()
	es = c.effectSlots(fns, globals)
	callees = []   # per entry: the entries of the functions it calls
	calleeBases = []   # per entry: their first slots, in the order of its calls
	for i in 0..fns.len:
		called = []
		bases = []
		if not es.tracked[i].isEmpty and not c.opaqueFunction(fns[i].fnd):
			for d in fns[i].calls:
				if es.entries.get(d) is at:
					called.extend(at)
					bases.push(es.base[at[0]])
		callees.push(called)
		calleeBases.push(bases)
	# the slots each slot is read by, and the entry each slot is summarized for
	readers i64[,] = []
	loop es.plans.len:
		readers.push([])
	entryOf = fill(es.plans.len, -1)
	for i in 0..fns.len:
		b = es.base[i]
		if es.tracked[i].isEmpty or entryOf[b] >= 0: continue   # none, or a later entry
		for k in 0..es.tracked[i].len:
			slot = b + k
			entryOf[slot] = i
			for ch in es.plans[slot]:
				if ch.through >= 0:
					readers[ch.through].push(slot)
			if k < globals.len and not es.hidden[slot]:
				for cb in calleeBases[i]:
					readers[cb + k].push(slot)
	# the first pass in post-order: a function's callees are summarized before it
	order = []
	visited = fill(fns.len, false)
	for i in 0..fns.len:
		postOrder(callees, i, visited, order)
	queued = fill(es.plans.len, false)
	pending = []
	for i in order:
		for k in 0..es.tracked[i].len:
			slot = es.base[i] + k
			if entryOf[slot] == i and not queued[slot]:
				queued[slot] = true
				pending.push(slot)
	lambdas, valued = c.valueCallables(fns)
	rounds = 0
	loop:
		head = 0
		while head < pending.len and head < 64 * es.plans.len:
			slot = pending[head]
			head += 1
			queued[slot] = false
			i = entryOf[slot]
			if not es.summarizeSlot(fns[i].closureCalls, i, slot - es.base[i], calleeBases[i]):
				continue
			for r in readers[slot]:
				if not queued[r]:
					queued[r] = true
					pending.push(r)
		# what a call through a function value may change, from the summaries so far; where it
		# grew, the functions that call one are summarized again there (their callers follow)
		rounds += 1
		grown = es.valueEffectsGrew(globals, lambdas, valued)
		if grown.isEmpty or rounds > 8: break
		pending = []
		for i in order:
			if not fns[i].closureCalls: continue
			for k in grown:
				slot = es.base[i] + k
				if entryOf[slot] == i and not es.hidden[slot] and not queued[slot]:
					queued[slot] = true
					pending.push(slot)
	for i in 0..fns.len:
		for k in 0..es.tracked[i].len:
			paths = es.sums[es.base[i] + k]
			if not paths.isEmpty:
				c.effects[effectKey(fns[i].fnd, es.tracked[i][k])] = paths.copy()
	for k in 0..globals.len:
		if not es.values[k].isEmpty:
			c.valueEffects[globals[k].copy()] = es.values[k].copy()
	c.facts = fns

# What a lambda's body changes and calls, walked once: what a call through a function value may
# change.
type LambdaChanges:
	placesChanged ChangeAt[] = []
	calls NodeId?[] = []   # the functions it calls by name or as a method, none for a call of a
#   function value, in the order of the walk

# the lambdas written in the functions' bodies, and the functions used as values (passed or
# bound by name)
fn valueCallables(c Checker, fns FnFacts[]):
	lambdas = []
	valued = []
	for f in fns:
		if not nodes[f.fnd].sub.isEmpty:
			c.collectCallables(nodes[f.fnd].sub[0], lambdas, valued)
	(lambdas, valued)

fn collectCallables(c Checker, e NodeId, mut lambdas LambdaChanges[], mut valued NodeId[]):
	if nodes[e].kind == nLambda:
		l = LambdaChanges()
		c.noteLambda(e, l)
		lambdas.push(l)
	if nodes[e].kind == nIdent and nodes[e].hasFlag(flagFnRef):
		d = c.findFunc(nodes[e].text)
		if d is d and d not in valued: valued.push(d)
	for k in nodes[e].kids:
		c.collectCallables(k, lambdas, valued)
	for sb in nodes[e].sub:
		c.collectCallables(sb, lambdas, valued)

fn noteLambda(c Checker, e NodeId, mut l LambdaChanges):
	c.noteChange(e, l.placesChanged)
	if nodes[e].kind == nCall:
		if nodes[e].hasFlag(flagClosure):
			l.calls.push(none)
		elif c.calledDecl(e) is d:
			l.calls.push(d)
	for kid in nodes[e].kids:
		c.noteLambda(kid, l)
	for sb in nodes[e].sub:
		c.noteLambda(sb, l)

# es.values found again for every module variable: the changes in the lambdas' bodies and the
# summaries of what they call and of the functions used as values; the module variables where it
# grew
fn valueEffectsGrew(
	mut es EffectSlots,
	globals str[],
	lambdas LambdaChanges[],
	valued NodeId[]
):
	grown = []
	for k in 0..es.values.len:
		paths = PathSet()
		name = globals[k][1..]
		for l in lambdas:
			es.addPlanned(es.planChanges(l.placesChanged, name, []), paths)
			for call in l.calls:
				match call:
					d:
						b = es.baseOf(d)
						if b >= 0: paths.addAll(es.sums[b + k])
					none:
						paths.addAll(es.values[k])   # what any function value may change there
		for d in valued:
			b = es.baseOf(d)
			if b >= 0: paths.addAll(es.sums[b + k])
		if not sameSet(es.values[k], paths.paths):
			es.values[k] = move paths.paths
			grown.push(k)
	grown

fn postOrder(callees i64[,], i i64, mut visited bool[], mut out i64[]):
	if visited[i]: return
	visited[i] = true
	for j in callees[i]:
		postOrder(callees, j, visited, out)
	out.push(i)

# the summary of slot k of entry i found again; whether it grew
fn summarizeSlot(mut es EffectSlots, closureCalls bool, i i64, k i64, calleeBases i64[]):
	paths = es.summarize(closureCalls, i, k, calleeBases)
	slot = es.base[i] + k
	if sameSet(es.sums[slot], paths): return false
	es.sums[slot] = paths
	true

# A call in an arena block to a function that changes a module variable owning memory: its
# statement allocates from the heap, since what the call stores there outlives the block.
pub fn pauseArenaGlobalCalls(mut c Checker):
	if c.arenaCalls.isEmpty: return
	if c.lentChecks.isEmpty:
		c.findEffects()   # checkLentArguments found none
	globals = c.globalKeys()
	for call in c.arenaCalls:
		for g in globals:
			if c.effects.get(effectKey(call.decl, g)) is paths and not paths.isEmpty:
				nodes[call.stmt].flags |= flagArenaPause
				break

# The places lent to calls that also change their owner, judged with the summaries: an error
# where what the call changes overlaps what it reads.
pub fn checkLentArguments(mut c Checker):
	if c.lentChecks.isEmpty: return
	c.findEffects()
	c.lentDone = true
	reported str[] = []
	for lentCheck in c.lentChecks:
		lc = lentCheck
		key = "{lc.file}:{lc.line}:{lc.col}"
		if key in reported: continue
		for q in c.changedThrough(lc.callee, lc.param, lc.arg):
			if (
				changedPlace(q) == lc.lent if lc.whole
				else changeOverlaps(q, lc.lent, lc.headersKept)
			):
				if lc.message != "":
					errorAtFile(
						lc.file,
						lc.line,
						lc.col,
						"{lc.message} (the call changes '{changedPlace(q)}')"
					)
				else:
					errorAtFile(
						lc.file,
						lc.line,
						lc.col,
						compileError("LentAndChanged", ["{lc.lent}", "{changedPlace(q)}"])
					)
				c.errors += 1
				reported.push(key)
				break
