# What each function does besides giving its result, found once every body is checked: whether
# it reaches outside the program (senses: reads a file, the clock, the environment; acts:
# prints, writes, sends, draws), changes or reads a module variable (`args` is one), calls a
# function value made where this cannot see (read from a field, an element or a module
# variable), reaches the runtime's own state (its intrinsics on global slots, atomics), whether
# it may stop the program (what one node stops on: stops.zap) or never end, allocates or waits. A function does what its body does
# and what every function it calls or names as a value does, grown together until none changes;
# a lambda's body counts for the function it is written in.
#
# A function that does none of the first six and changes no parameter is pure (allocating is the
# program's own business): the same arguments give the same result and nothing else happens. The
# backend treats its call as an operator (pureCallLevel); `parallel()` refuses a lambda or a loop
# body that acts or changes a module variable through any call it makes, and `background()` one
# that changes, prints or reads a module variable that can change (checkParallelBodies); the
# promises noAllocation and noLocks refuse a scope that allocates or waits (options.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

fn purityWord():
	TraceWord("purity", "what each function does besides its result, and the calls to it")

doesSense = 1   # reads outside the program: a file, the clock, the environment
doesAct = 2   # changes outside the program: prints, writes a file, sends, sleeps, draws
doesChange = 4   # changes a module variable
doesRead = 8   # reads a module variable
doesCallValue = 16   # calls a function value made where the analysis cannot see
doesRaw = 32   # reaches the runtime's own state (its global slots, a thread's, atomics, the stack)
doesStop = 64   # may stop the program (a failed check, an overflow, a stack too deep)
doesAllocate = 128   # takes memory from the heap
doesWait = 256   # waits for another thread or for time
doesEndless = 512   # may never end (a while loop, a cycle of calls)
doesPrint = 1024   # prints (the console's buffer is the runtime's, kept by no lock)
doesReadProgram = 2048   # reads a module variable that can change, not the runtime's own
doesImpure = 63   # what a pure function does none of
doesUnknown = 4095   # what a call whose body is not known may do

# the runtime's intrinsics that reach state no parameter holds
rawStateIntrinsics = [
	"__globals",
	"__database",
	"__xadd",
	"__cmpxchg",
	"__tlsGet",
	"__tlsSet",
	"__callRec",
	"__fini",
	"__returnAddress",
	"__fence"
]

# the system's functions that serve the program's own memory and threads besides those that
# allocate (options.zap's allocationRoots): nothing outside (Windows', then Linux's system calls,
# runtime/core/linux/)
ownExterns = [
	"VirtualFree",
	"VirtualQuery",
	"HeapFree",
	"TlsAlloc",
	"CreateThread",
	"CreateEventA",
	"SetEvent",
	"CreateSemaphoreA",
	"ReleaseSemaphore",
	"WaitForSingleObject",
	"SwitchToThread",
	"GetModuleHandleA",
	"GetStdHandle",
	"GetCurrentThreadId",
	"sysMmap",
	"sysMunmap",
	"sysMprotect",
	"sysMadvise",
	"sysFutex",
	"sysClone",
	"sysSchedYield",
	"sysSigaltstack",
	"sysRtSigaction"
]
# the system's functions that read outside the program without changing it; every other one acts
senseExterns = [
	"ReadFile",
	"GetLastError",
	"CreateFileA",
	"CloseHandle",
	"GetFileSizeEx",
	"SetFilePointerEx",
	"GetFileType",
	"CreateFileMappingA",
	"MapViewOfFile",
	"GetFileAttributesA",
	"FindFirstFileA",
	"FindNextFileA",
	"FindClose",
	"GetCommandLineA",
	"GetEnvironmentVariableA",
	"GetModuleFileNameA",
	"GetCurrentDirectoryA",
	"GetConsoleMode",
	"QueryPerformanceCounter",
	"QueryPerformanceFrequency",
	"K32GetProcessMemoryInfo",
	"GetExitCodeProcess",
	"GetProcessTimes",
	"QueryProcessCycleTime",
	"sysRead",
	"sysOpenat",
	"sysClose",
	"sysFstat",
	"sysNewfstatat",
	"sysLseek",
	"sysGetdents64",
	"sysGetcwd",
	"sysReadlinkat",
	"sysIoctl",
	"sysClockGettime",
	"sysGetrusage",
	"sysWaitid",
	"sysSchedGetaffinity"
]

# the name a function is written with (a method's text, a top-level function's local name)
fn writtenName(c Checker, fnd NodeId) ref str:
	nodes[fnd].text if nodes[fnd].text2() == "" else nodes[fnd].text2()

# the name the rules of the program's own code read a declaration by: its global name, which is
# the written one in the program's module, and a together check's source's written one, as it
# is the program's own (a module's keeps its global name: those rules leave it alone)
fn programName(c Checker, d NodeId) ref str:
	c.writtenName(d) if isUnitKey(nodes[d].text) else nodes[d].text

# what an extern does, by its name
fn externDoes(name str):
	0 if name in ownExterns else doesSense if name in senseExterns else doesAct

# the place an argument names: below its parameter's name and its `mut` or `move`
fn placeUnder(c Checker, e NodeId):
	at = e
	if nodes[at].kind == nNamedArg:
		at = nodes[at].kids(kidIds)[0]
	if nodes[at].kind == nUnary and nodes[at].ival in [unMutRef, unMove]:
		at = nodes[at].kids(kidIds)[0]
	at

# whether the place e is (a part of) a module variable
fn moduleVarPlace(c Checker, e NodeId):
	nodes[c.placeRootNode(c.placeUnder(e))].hasFlag(flagModuleVar)

# the places e itself may change: an assignment's target, a `mut` borrow's place, the receiver of
# a method that changes it, an argument given to a mut or move parameter
fn placesChanged(mut c Checker, e NodeId):
	k = nodes[e].kind
	if k == nAssign or k == nUnary and nodes[e].ival == unMutRef: return [nodes[e].kids(kidIds)[0]]
	if k != nCall or nodes[e].kids(kidIds).isEmpty or nodes[e].hasFlag(flagClosure): return []
	callee = nodes[e].kids(kidIds)[0]
	out = []
	first = 0
	if nodes[callee].kind == nField:
		md = c.calledMethod(callee)
		mutates = match md:
			md: nodes[md].hasFlag(flagMut)
			none: c.methodIsMutating(nodes[callee].text)
		if mutates:
			out.push(nodes[callee].kids(kidIds)[0])
		if md == none:
			first = 1   # a built-in method's runtime function takes the receiver first
	if c.calleeDecl(e) is d:
		if nodes[callee].kind == nIdent and nodes[d].hasFlag(flagMut) and c.argCount(e) > 0 and
			not nodes[d].kids(kidIds).isEmpty and nodes[nodes[d].kids(kidIds)[0]].text == "self":
			out.push(c.argAt(e, 0))   # a method's bare call, given self: `mut self`
		for i in 0..c.argCount(e):
			if i + first >= nodes[d].kids(kidIds).len: break
			mode = nodes[nodes[d].kids(kidIds)[i + first]].ival
			if mode == modeMut or mode == modeMove:
				out.push(c.argAt(e, i))
	out

# what node e does itself (not what is under it), and the function it calls or names as a
# value (-1 for none)
fn nodeDoes(mut c Checker, e NodeId):
	k = nodes[e].kind
	bits = 0
	if k == nIdent and nodes[e].hasFlag(flagModuleVar):
		bits |= doesRead
		if c.curMod < 0 or c.modules[c.curMod].id != "rt":
			bits |= doesReadProgram
	if c.tKind(typeOf(nodes, e)) == tFn and
		(k in [nField, nIndex, nDeref] or k == nIdent and nodes[e].hasFlag(flagModuleVar)):
		bits |= doesCallValue
	if c.placesChanged(e).any(c.moduleVarPlace(it)):
		bits |= doesChange
	if c.allocationAt(e) != "":
		bits |= doesAllocate
	if k == nIdent and nodes[e].hasFlag(flagFnRef): return (bits, c.findFunc(nodes[e].text))
	if k == nWhile:
		bits |= doesEndless
	if k != nCall or nodes[e].kids(kidIds).isEmpty: return (bits | c.stopBit(e), none)
	callee = nodes[e].kids(kidIds)[0]
	if nodes[e].hasFlag(flagClosure):
		# what its value does counts where the value is made; whether it allocates or waits is
		# not known here
		return (bits | doesStop | doesEndless | doesAllocate | doesWait, none)
	if c.isSlice(e): bits |= c.stopBit(e)   # checked in place, not by the runtime's function
	match c.calleeDecl(e):
		d:
			if endsProgram(c.writtenName(d)): return (bits | doesStop, none)
			(bits, d)
		none:
			if nodes[callee].kind == nIdent and isPrintBuiltin(nodes[callee].text):
				bits |= doesAct | doesPrint
			if nodes[callee].kind == nIdent and nodes[callee].text in rawStateIntrinsics:
				bits |= doesRaw
			(bits | c.stopBit(e), none)

# doesStop when e itself may stop the program (stops.zap), else 0
fn stopBit(mut c Checker, e NodeId):
	0 if c.stopFact(e) == "" else doesStop

# the runtime's function that gives a block back (with options.zap's allocationRoots, the
# memory roots: the allocator's state, its first call reading the trace options, is its own)
freeRoots = ["rtFree"]

# what a module variable's initializer does: its expression and every function it reaches
pub fn initializerDoes(mut c Checker, d NodeId) i64:
	mod = c.curMod
	file = c.curFile.copy()
	c.enterModuleOf(d)
	f = FnFacts(fnd = d)
	seen {str: bool} = {}
	c.noteFacts(nodes[d].kids(kidIds)[0], f, seen, false)
	c.curMod = mod
	c.curFile = file
	bits = f.own
	for callee in f.reaches:
		bits |= c.fnDoes(callee)
	bits

# Tarjan's walk: the entries on a cycle of calls (one calling itself included)
type CallCycles:
	index i64[]
	low i64[]
	onStack bool[]
	stack i64[] = []
	next i64 = 0
	cyclic bool[]

fn visitCalls(mut t CallCycles, callees i64[,], v i64):
	t.index[v] = t.next
	t.low[v] = t.next
	t.next += 1
	t.stack.push(v)
	t.onStack[v] = true
	for w in callees[v]:
		if t.index[w] < 0:
			t.visitCalls(callees, w)
			t.low[v] = t.low[v].min(t.low[w])
		elif t.onStack[w]:
			t.low[v] = t.low[v].min(t.index[w])
	if t.low[v] != t.index[v]: return
	part = []
	loop:
		w = t.stack.pop() ?? break
		t.onStack[w] = false
		part.push(w)
		if w == v: break
	if part.len > 1 or v in callees[v]:
		for w in part:
			t.cyclic[w] = true

# Every function's bits (Checker.fnEffects): its own, a function on a cycle of calls may never
# end or overflow the stack, then each grown by its callees' until none changes; the parallel
# bodies checked of the functions from node below on (those before it were with the facts kept).
pub fn findFnEffects(mut c Checker, below i64):
	mod = c.curMod
	file = c.curFile.copy()
	fns = c.takeFacts()
	entry {NodeId: i64} = {}
	for i, f in fns:
		entry[f.fnd] = i
	callees = []
	callers i64[,] = []
	for _ in fns:
		callers.push([])
	for i, f in fns:
		at = []
		for d in f.reaches:
			if entry.get(d) is j:
				at.push(j)
				callers[j].push(i)
		if f.memory: at.clear()
		callees.push(at)
	n = fns.len
	t = CallCycles(
		index = fill(n, -1),
		low = zeros(n),
		onStack = zeros(n),
		cyclic = zeros(n)
	)
	for i in 0..n:
		if t.index[i] < 0:
			t.visitCalls(callees, i)
	bits = []
	for i in 0..n:
		bits.push(fns[i].own | (doesStop | doesEndless if t.cyclic[i] else 0))
	pending = []
	for i in 0..n:
		pending.push(i)
	head = 0
	while head < pending.len:
		i = pending[head]
		head += 1
		for j in callers[i]:
			grown = bits[j] | (bits[i] & fns[j].keeps)
			if grown != bits[j]:
				bits[j] = grown
				pending.push(j)
	trace = purityWord().on()
	for i in 0..n:
		c.fnEffects[fns[i].fnd] = bits[i]
		if trace:
			why = ""
			if bits[i] & doesImpure != 0:
				seen = []
				why = " ({c.chainFrom(fns[i].fnd, bits[i] & -bits[i], seen)})"   # its lowest bit's
			eprint("purity: {displayName(nodes[fns[i].fnd].text)}: {doingWords(bits[i])}{why}")
	c.facts = fns
	c.checkParallelBodies(below)
	c.curMod = mod
	c.curFile = file

# the bits' names, for ZAP_RUN=purity ("pure" for none)
fn doingWords(bits i64):
	words = [
		"senses",
		"acts",
		"changes",
		"reads",
		"calls a value",
		"reaches the runtime's state",
		"may stop",
		"allocates",
		"waits",
		"may never end",
		"prints",
		"reads the program's state"
	]
	out = []
	for i, w in words:
		if bits & (1 << i) != 0:
			out.push(w)
	if bits & doesImpure == 0:
		out.insert(0, "pure")
	out.join(", ")

# what calling fnd does, all of it when it is not known (a generic's instance: what its generic does)
fn fnDoes(c Checker, fnd NodeId):
	if c.fnEffects.get(fnd) is does: return does
	generic = nodes[fnd].origin() ?? return doesUnknown
	c.fnEffects.get(generic) ?? doesUnknown

# How the backend may treat a call of fnd: 2 as an operator that never stops and ends (made once for the
# same arguments, taken out of a loop, dropped when unused), 1 one that may stop (made once for
# the same arguments), 0 as a call. Only a pure function that is not generic, whose parameters
# are read numbers or bools and whose result is one, and not the runtime's (its raw reads and
# writes of memory are not followed).
pub fn pureCallLevel(mut c Checker, fnd NodeId) i64:
	if not nodes[fnd].names().isEmpty or nodes[fnd].hasFlag(flagMut) or
		nodes[fnd].hasFlag(flagExtern) or nodes[fnd].mod() == "rt":
		return 0
	does = c.fnDoes(fnd)
	if does & doesImpure != 0: return 0
	for p in nodes[fnd].kids(kidIds).copy():
		if nodes[p].ival != modeRead or nodes[p].types().isEmpty or
			not c.numberOrBool(c.resolveType(nodes[p].types()[0])):
			return 0
	if not c.numberOrBool(c.fnRetType(fnd)): return 0
	1 if does & (doesStop | doesEndless) != 0 else 2

fn numberOrBool(c Checker, t TypeId):
	c.tKind(t) in [tInt, tFloat, tBool]

# ---------- parallel bodies and background jobs ----------

actWords = "act outside the program (print, write, send)"

# whether call e runs its last argument on several threads (a parallel pipeline or loop,
# written by checkexpr.zap and checkstmt.zap as a call of the runtime's parallelMap or parallelDo)
fn runsInParallel(c Checker, e NodeId):
	if nodes[e].kind != nCall or nodes[e].kids(kidIds).len < 2: return false
	callee = nodes[e].kids(kidIds)[0]
	name = nodes[callee].text
	nodes[callee].kind == nIdent and nodes[callee].hasFlag(flagInternal) and
		(
			name.endsWith("parallelMap") or name.endsWith("parallelDo") or
				name.endsWith("parallelStream")
		)

# whether call e is the stream a `for` over a parallel map makes (checkParallelStream): a local of the loop
fn isParallelStream(c Checker, e NodeId):
	if nodes[e].kind != nCall or nodes[e].kids(kidIds).len != 3: return false
	callee = nodes[e].kids(kidIds)[0]
	nodes[callee].kind == nIdent and nodes[callee].hasFlag(flagInternal) and
		nodes[callee].text.endsWith("parallelStream")

# whether call e is the runtime's background(f), which runs f beside the thread that calls it
fn runsAsJob(mut c Checker, e NodeId):
	if nodes[e].kind != nCall or nodes[e].kids(kidIds).len != 2 or nodes[e].hasFlag(flagClosure):
		return false
	d = c.calleeDecl(e) ?? return false
	c.findDeclInModule("rt", nFnDecl, "background") == d

# The lambdas parallel() runs on several threads, checked through every call they make: none
# may act outside the program or change a module variable. A background job runs beside the
# thread that started it, which goes on changing what it likes: the job may act outside (a
# device, a file), but neither change nor read a module variable that can change, nor print
# (the console's buffer is the starting thread's); what it needs is captured, what it makes goes
# back as its result or through a Channel.
fn checkParallelBodies(mut c Checker, below i64):
	reported = []
	for d in c.functionDecls():
		# (a file's own errors would blur them)
		if i64(d) < below or c.hasErrorsIn(nodes[d].file()): continue
		c.parallelBodiesIn(d, d, reported)

fn parallelBodiesIn(mut c Checker, fnd NodeId, e NodeId, mut reported str[]):
	if e == fnd:
		if nodes[fnd].sub().isEmpty: return
		c.enterModuleOf(fnd)
		c.parallelBodiesIn(fnd, nodes[fnd].sub()[0], reported)
		return
	if c.runsInParallel(e):
		c.checkParallelBody(fnd, nodes[e].kids(kidIds)[nodes[e].kids(kidIds).len - 1], reported)
	elif c.runsAsJob(e):
		c.checkJobBody(fnd, nodes[e].kids(kidIds)[1], reported)
	for kid in nodes[e].kids(kidIds).copy():
		c.parallelBodiesIn(fnd, kid, reported)
	for sbAt in 0..nodes[e].sub().len:
		sb = nodes[e].sub()[sbAt]
		c.parallelBodiesIn(fnd, sb, reported)

# the body checked; the parts' count the compiler's code reads in it (parallelChunks) is the
# runtime's to keep safe: it is set before any worker reads it
fn checkParallelBody(mut c Checker, fnd NodeId, body NodeId, mut reported str[]):
	c.refuseDoings(fnd, body, [doesAct, doesChange], "parallelChunks", "ParallelEffect", reported)

# A job's body checked. It is a lambda or a function's name, so that what it does is seen. A
# channel's wait it reaches (waitForChannel) reads only the count of the jobs alive, which the
# runtime keeps safe.
fn checkJobBody(mut c Checker, fnd NodeId, body NodeId, mut reported str[]):
	k = nodes[body].kind
	if k != nLambda and not (k == nIdent and nodes[body].hasFlag(flagFnRef)):
		errorAtFile(
			nodes[fnd].file(),
			nodes[body].line,
			nodes[body].col,
			compileError("JobBodyUnseen", [])
		)
		c.errors += 1
		return
	c.refuseDoings(
		fnd,
		body,
		[doesChange, doesPrint, doesReadProgram],
		"waitForChannel",
		"JobEffect",
		reported
	)

# what body does of `bits`, through every call, refused with the error `name` (the runtime's
# function `trusted` is not followed)
fn refuseDoings(
	mut c Checker,
	fnd NodeId,
	body NodeId,
	bits i64[],
	trusted str,
	name str,
	mut reported str[]
):
	for bit in bits:
		seen = []
		if c.findDeclInModule("rt", nFnDecl, trusted) is d: seen.push(d)
		found, chain = c.doingAt(body, bit, seen)
		at = found ?? continue
		key = "{nodes[fnd].file()}:{nodes[at].line}:{nodes[at].col}"
		if key in reported: continue
		reported.push(key)
		errorAtFile(
			nodes[fnd].file(),
			nodes[at].line,
			nodes[at].col,
			compileError(name, ["{refusedWords(bit)}", "{chain}"])
		)
		c.errors += 1

# what a body cannot do, as its error says it
fn refusedWords(bit i64):
	if bit == doesAct: return actWords
	if bit == doesPrint: return "print (the console is the starting thread's)"
	if bit == doesReadProgram:
		return "read a module variable that can change (capture what it needs)"
	"change a module variable"

# the first node under e that does `bit`, itself or through the function it reaches, and the
# chain to what does it ("log -> print"); (none, "") when none. The functions in `seen` are on
# the chain already, or not followed.
fn doingAt(mut c Checker, e NodeId, bit i64, mut seen NodeId[]) (NodeId?, str):
	bits, d = c.nodeDoes(e)
	if bits & bit != 0: return (e, c.doingName(e, bit))
	if d is d and d not in seen and c.fnDoes(d) & bit != 0:
		chain = c.chainFrom(d, bit, seen)
		if chain != "": return (e, chain)
	for kid in nodes[e].kids(kidIds).copy():
		at, chain = c.doingAt(kid, bit, seen)
		if at != none: return (at, chain)
	for sbAt in 0..nodes[e].sub().len:
		sb = nodes[e].sub()[sbAt]
		at, chain = c.doingAt(sb, bit, seen)
		if at != none: return (at, chain)
	(none, "")

# the chain from the function d to what does `bit` ("f -> g -> print"), "" when none is found
fn chainFrom(mut c Checker, d NodeId, bit i64, mut seen NodeId[]):
	seen.push(d)
	name = displayName(c.writtenName(d))
	if bit == doesAllocate and c.writtenName(d) in allocationRoots: return "{name}, which allocates"
	# a wait of the system that a system's own function (linux/) stands for ends the chain there too
	if bit == doesWait and c.writtenName(d) in waitRoots: return "{name}, which waits"
	if nodes[d].sub().isEmpty: return "{name}, which waits" if bit == doesWait else name
	mod = c.curMod
	file = c.curFile.copy()
	c.enterModuleOf(d)
	c.readBody(d)
	_, inner = c.doingAt(nodes[d].sub()[0], bit, seen)
	c.curMod = mod
	c.curFile = file
	if inner != "": return "{name} -> {inner}"
	# a function stopping with no node that stops is on a cycle of calls
	"{name}, which calls itself again (its stack may overflow)" if bit == doesStop else ""

# what node e does that `bit` names, as a chain's last link: the print, the module variable
fn doingName(mut c Checker, e NodeId, bit i64):
	if nodes[e].kind == nCall and nodes[e].hasFlag(flagClosure):
		return "a call of a function value, whose body is not known"
	if bit == doesAllocate: return c.allocationAt(e)
	if bit == doesAct or bit == doesPrint: return nodes[nodes[e].kids(kidIds)[0]].text.copy()
	if bit == doesCallValue:
		return "a function value read from a field, an element or a module variable"
	if bit == doesStop: return c.stopFact(e)
	if bit == doesRaw: return nodes[nodes[e].kids(kidIds)[0]].text.copy()
	"'{displayName(c.moduleVarUnder(e))}'"

# the name of the first module variable under e, "" when none
fn moduleVarUnder(c Checker, e NodeId) ref str:
	if nodes[e].kind == nIdent and nodes[e].hasFlag(flagModuleVar): return nodes[e].text
	for kid in nodes[e].kids(kidIds):
		name = c.moduleVarUnder(kid)
		if name != "": return name
	""
