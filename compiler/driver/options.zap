# A scope's options, `use name, name` as its first line (parse.zap): fusedMultiplyAdd (fuse.zap),
# and the promises noAllocation, noLocks and noStops, checked here through every call the scope makes, the
# user's functions and the runtime's alike (what each does: purity.zap), the error naming the
# chain of calls to the offender. The rules are conservative: what they cannot follow is refused.
#
# noAllocation refuses a list or map literal, a string built from parts or joined with +, a
# lambda that captures (its environment is on the heap), a Box, a call of a function value (its
# body is not known), a built-in call that gives a list, a map, a string or a box or that grows a
# list or a map, and a reached function that is rtAlloc, rtAllocRaw or an extern that allocates.
# noLocks refuses a call of a function value and a reached extern that waits (WaitForSingleObject,
# Sleep, SwitchToThread...), which the channels, a background job and a socket's wait all do.
# noStops refuses what may stop the program unless proven not to (stops.zap names the operation
# and the fact missing), a function value's call, and a reached function on a cycle of calls (its
# stack may overflow); a loop that may never end does not stop it.

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# the flag of each name of options, in its order
optionFlags = [flagFusedMath, flagNoAllocation, flagNoLocks, flagNoStops]
pub flagPromises = 1_152_923_153_874_288_640   # flagNoAllocation | flagNoLocks | flagNoStops
pub flagOptions = 1_152_925_361_487_478_784   # flagFusedMath | flagPromises | flagOptionBlocks

# the flag of an option's name, 0 for a name that is none
pub fn optionFlag(name str) i64:
	i = options.indexOf(name) ?? -1
	0 if i < 0 else optionFlags[i]

fn optionName(flag i64):
	options[optionFlags.indexOf(flag) ?? 0].copy()

allocationRoots = ["rtAlloc", "rtAllocRaw", "VirtualAlloc", "HeapAlloc"]
waitRoots = [
	"WaitForSingleObject",
	"WaitForSingleObjectEx",
	"WaitForMultipleObjects",
	"Sleep",
	"SleepEx",
	"SwitchToThread",
	"AcquireSRWLockExclusive",
	"WaitOnAddress",
	"sysFutex",
	"sysNanosleep",
	"sysSchedYield"
]
growingMethods = ["push", "extend", "insert", "reserve", "set"]

promiseFlags = [flagNoAllocation, flagNoLocks, flagNoStops]
# what each promise refuses, in promiseFlags' order (purity.zap's bits)
promiseBits = [doesAllocate, doesWait, doesStop]

fn promiseBit(kind i64):
	promiseBits[promiseFlags.indexOf(kind) ?? 0]

# Every function's and block's promises, once the bodies are checked and what each function
# does is known, but those below node below (the kept stages', checked with them); none after an
# error (what a function does is not known then: its errors would be echoes in other files)
pub fn checkPromises(mut c Checker, below i64):
	if c.errors > 0: return
	for d in c.functionDecls():
		if i64(d) >= below: c.checkPromisesOf(d)

fn checkPromisesOf(mut c Checker, fnd NodeId):
	if not nodes[fnd].hasFlag(flagPromises | flagOptionBlocks) or nodes[fnd].sub().isEmpty: return
	c.enterModuleOf(fnd)
	for kind in promiseFlags:
		if nodes[fnd].hasFlag(kind):
			c.reportOffender(nodes[fnd].sub()[0], kind)
		else:
			c.promiseBlocks(nodes[fnd].sub()[0], kind)

# the blocks under e with the promise, each checked whole
fn promiseBlocks(mut c Checker, e NodeId, kind i64):
	if nodes[e].kind == nBlock and nodes[e].hasFlag(kind):
		c.reportOffender(e, kind)
		return
	for k in nodes[e].kids(kidIds).copy():
		c.promiseBlocks(k, kind)
	for s in nodes[e].sub().copy():
		c.promiseBlocks(s, kind)

fn reportOffender(mut c Checker, scope NodeId, kind i64):
	seen = []
	found, chain = c.doingAt(scope, promiseBit(kind), seen)
	at = found ?? return
	how = " by this call: " if nodes[at].kind == nCall and " -> " in chain else ": "
	c.errorAt(
		nodes[at].line,
		nodes[at].col,
		compileError("OptionBroken", ["{optionName(kind)}", "{how}", "{chain}"])
	)

# what e itself allocates, named ("a list literal"), or ""
fn allocationAt(mut c Checker, e NodeId):
	k = nodes[e].kind
	t = typeOf(nodes, e)
	tk = c.tKind(t)
	if k == nArray and tk == tList: return "a list literal"
	if k == nMapLit: return "a map literal"
	if k == nInterp: return "a string built from parts"
	if k == nBinary and nodes[e].ival == binAdd and tk == tStr: return "a string joined with +"
	if k == nLambda and not nodes[e].ints().isEmpty:
		return "a lambda that captures (its environment is on the heap)"
	if (k == nStructLit or k == nCall) and tk == tBox: return "a Box"
	if k == nCall and nodes[nodes[e].kids(kidIds)[0]].kind == nField and
		c.calledMethod(nodes[e].kids(kidIds)[0]) == none:
		callee = nodes[e].kids(kidIds)[0]   # a built-in method of a list, a map or a str
		m = nodes[callee].text
		rk = c.tKind(c.derefType(c.receiverType(nodes[callee].kids(kidIds)[0])))
		if m in growingMethods and (rk == tList or rk == tMap):
			return "{m}, which grows a {c.showTy(c.derefType(c.receiverType(nodes[callee].kids(kidIds)[0])))}"
		if tk in [tList, tMap, tStr]: return "{m}, which gives a {c.showTy(t)}"
	""

# the function a call names: the user's, the runtime's, or a built-in's runtime function; none
fn calleeDecl(mut c Checker, e NodeId):
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind == nIdent:
		d = c.lookupDecl(nFnDecl, "", nodes[callee].text, nodes[e].line, nodes[e].col)
		if d != none: return d
		named = c.findDeclByGlobalName(nFnDecl, nodes[callee].text)   # the checker wrote it (a method's)
		if named != none: return named
		rt = builtinRtName(nodes[callee].text)
		return none if rt == "" else c.findDeclInModule("rt", nFnDecl, rt)
	if nodes[callee].kind != nField: return none
	d = c.calledMethod(callee)
	if d != none: return d
	derived = c.derivedCallee(e)
	if derived != none: return derived
	rtMethodDecl(
		c,
		c.tKind(c.derefType(c.receiverType(nodes[callee].kids(kidIds)[0]))),
		nodes[callee].text
	)
