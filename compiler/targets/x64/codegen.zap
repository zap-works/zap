# The native backend's driver: the program's start, the functions generated on demand (each
# through the intermediate form or an extern stub), the fail
# stubs and the image. Calling convention: scalars travel in rax; arguments are pushed left to
# right (a function of the intermediate form writes them where the pushes would put them, in the
# area at the bottom of its frame: its rsp stays put): scalars by value, `read`/`mut` aggregates as
# the address of the caller's value, `move` aggregates by value; an aggregate result is written
# through a hidden pointer pushed last.

alias nodes = g.c.nodes
alias tys = g.c.types

type Gen:
	entry str   # the program's entry function: main, or the tests' runner
	f FnState   # the function being generated
	debugLines i64[]   # code position, line, column, file: where the code of each statement starts
	debugFiles str[]   # the source files the lines name
	curFile i64   # the file (in debugFiles) of the code being generated
	curLine i64   # the line and column of the expression being generated
	curCol i64
	c Checker   # owns the checked program (nodes, types, declarations, instances)
	a Asm
	# function context
	# program-wide
	fnLabels {str: i64}
	strOffs {str: i64}   # string literals: text -> data offset
	nameOffs {str: i64}   # [length][bytes] name blocks of descriptors: name -> data offset
	tdOffs {str: i64}   # type descriptors: type key -> data offset
	globalsOff i64
	globalOffs {str: i64}   # module variables: their global name -> data offset
	globalsNamed {str: bool} = {}   # the module variables the generated code names (irGlobal)
	failDivZero i64
	failShift i64
	failBounds i64
	failStep i64
	failOverflow i64
	failConversion i64
	fnValueNames {str: bool}   # the functions some code takes as a value (they keep the stack convention)
	provenL i64[]   # (list, counter) variable pairs whose L[i] is within bounds by the loop
	provenV i64[]   # that bounds the counter by L's length (no check emitted)
	floatOffs {i64: i64}   # float literals already in the data area, by their bits
# register costs its save, restore and load)
	curFnKey str   # the function being generated (for the cache debug output)
	failCpu i64
	avxDirty bool   # the upper halves may be dirty since the last vzeroupper
	inlineDepth i64   # inlined bodies being generated (a bound against recursion)
	varFloor i64   # names resolve to variables at or past this index (an inlined body sees only its own)
	inlineFn NodeId?   # the function whose body is being judged for inlining
	pending PendingReg[]   # registers reserved for locals a loop body declares
	planned Planned[]   # generated drop/copy/env functions still to emit
	loadedSlots {NodeId: i64}   # extern loaded fn -> the data word that holds its address
	inRt bool   # generating a function of the runtime
	libcTls i64 = 0   # the data word of the C library's thread block (ccall.zap)
	libcTable i64 = -1   # the table of arm64's library blocks (a64ccall.zap), in the zero storage
	hasCHelpers bool = false   # the stubs of dlopen and dlsym are generated
	xmm0Zero bool = false   # all of ymm0 zero since the last zero written to it (irKeepsXmm0)
	xmm0Held i64 = -1   # the spilled vector the instruction before left in ymm0 (irHeld)
	irCallStores {str: i64} = {}   # by a call's key: the arguments (bits by position) that are
# the callee's mut parameters, the places it may store into (irown.zap)
	mayBorrow {TypeId: bool} = {}   # irMayBorrow's answers (resolving an enum's payloads makes types)
	holdsClosure {str: bool} = {}   # irHoldsClosure's, by the struct's or enum's name (each
# resolving of a field's type makes a type of its own, so the same type has many ids)
	owning {TypeId: bool} = {}   # isOwningType's, while no type parameter is in force
	aggregate {TypeId: bool} = {}   # irIsAggregate's, so
	emitting i64 = 0   # the functions being emitted, one within another (samecode.zap)
	nested bool = false   #   and whether one began within another since none was
	emitted CodeRange[] = []   # the functions emitted that may be merged
	mergedInto {i64: i64} = {}   # a merged function's label -> the label of the one it became
	made IrMade[] = []   # the functions lowered, waiting to be made (irmade.zap)
	# what the lowering keeps across functions (each a field, so that a lowering run as a job on
	# a copy of g changes no module variable)
	irFileNow str = ""   # the file of the function being made (its lambdas' too)
	irLambdaFns IrLambdaFn[] = []   # the lambdas lowered, each a function of its own (irlowerclosures.zap)
	irLambdaSeq i64 = 0   # numbers their bodies: one lambda inlined into several functions is several
	irSpans i64 = 0   # numbers each place read in place (noteReadFrom, noteReadTo)
	irGivenInstances IrGivenInstance[] = []   # the instances made for the functions calls gave (irgiven.zap)
	irGivenNow IrGiven[] = []   # the given parameters of the instance being lowered
	irWorth {str: bool} = {}   # irCallsOnly's answers, by "function:parameter"
	irReporters {NodeId: bool} = {}   # irEndsProcess's answers for the runtime's functions
	irOwnPending IrOwnPending[] = []   # the errors the ownership check found, said once settled
	irOwnMarks NodeId[] = []   # the nodes the check decided something about since the function
	# was lowered (a borrow that becomes a copy, a shared value counted): lowered again with them
	irSaid str[] = []   # the lowering's and the check's traces, printed once settled (irOwnSettle)

# A loop-invariant element address kept while a loop's body runs: the list local, the index
# local, and where the address is (a cache register 0..4 or 15..18, else a frame slot, negative).
type Hoist:
	list i64
	index i64
	slot i64

# A hoist planned for a loop: the list local, the index local, the frame slots holding the
# list's items pointer and length (read before the loop), and whether the index is an outer
# counter (the address then holds for the whole loop).
type PlannedHoist:
	list i64
	index i64
	items i64
	length i64
	invariant bool
	advance bool = false   # indexed by the loop's counter, proven in bounds: made once before the
# loop and moved one element a step

# A counter of a `for` over constant bounds while its body is generated: lo <= variable < hi.
type RangeVar:
	variable i64
	lo i64
	hi i64

fn die(msg str):
	exit(1, "zap: {msg}")

# whether a function the form refused, so never generated, ends the process: not while the lint
# checks a rewrite again, where it is the check failing
mut refusalEnds = true

pub fn genX64(mut prog Program, exePath str) bool:
	g = Gen(
		entry = prog.entry.copy(),
		c = prog.newChecker(),
		a = Asm(),
		f = newFnState(none, none, tyUnit),
		debugLines = [],
		debugFiles = [],
		curFile = 0,
		curLine = 0,
		curCol = 0,
		fnLabels = {},
		strOffs = {},
		nameOffs = {},
		tdOffs = {},
		globalsOff = 0,
		globalOffs = {},
		failDivZero = -1,
		failShift = -1,
		failBounds = -1,
		failStep = -1,
		failOverflow = -1,
		failConversion = -1,
		fnValueNames = {},
		provenL = [],
		provenV = [],
		floatOffs = {},
		curFnKey = "",
		failCpu = -1,
		avxDirty = false,
		inlineDepth = 0,
		varFloor = 0,
		inlineFn = none,
		pending = [],
		planned = [],
		loadedSlots = {},
		inRt = false
	)
	g.noteFnValues()   # they keep the stack convention (takesRegArgs)
	g.globalsOff = g.a.asmDataZero(64 * 8)
	g.failDivZero = g.a.asmNewLabel()
	g.failShift = g.a.asmNewLabel()
	g.failStep = g.a.asmNewLabel()
	g.failBounds = g.a.asmNewLabel()
	g.failOverflow = g.a.asmNewLabel()
	g.failConversion = g.a.asmNewLabel()

	g.reserveGlobals()
	g.failCpu = g.a.asmNewLabel()
	start = g.a.asmNewLabel()
	g.a.asmPlace(start)
	if onArm():
		g.a64Start(prog.entry)
	elif onLinux():
		g.x64LinuxStart(prog.entry)
	else:
		g.genX64Start(prog.entry)
	entryLabel = start
	if appBuild:
		entryLabel = g.a.asmNewLabel()
		g.genAppEntry(entryLabel, start)
	g.genFailStub(g.failDivZero, failKindDivZero)
	g.genFailStub(g.failShift, failKindShift)
	g.genFailStub(g.failStep, failKindStep)
	g.genFailStub(g.failBounds, failKindBounds)
	g.genFailStub(g.failCpu, failKindOldCpu)
	g.genFailStub(g.failOverflow, failKindOverflow)
	g.genFailStub(g.failConversion, failKindConversion)
	g.genOsThreadEntry()
	loadEntry = g.loadableEntry(prog.entry) if loadableBuild else -1

	pending = g.pendingFunctions()
	phaseEnded("code setup")
	g.genFunctionsAndGlobals(pending)
	phaseEnded("code")
	phaseLoweringSaid()
	for key in g.fnLabels.keys():
		if g.fnLabels.get(key) is l:
			if g.a.labelPos[l] < 0:
				if not refusalEnds: return false
				die("x64: function '{key}' was referenced but never generated")
	g.irCheckUnreached(pending)
	if irOwnWord().on():
		eprint("irown: {irOwnSeconds} s verifying ownership")
	if lowerSharedWord().on():
		sayLowerShared()
	if irOwnErrors > 0: return false
	if exePath == "": return true   # checked only
	if irMissing > 0:
		eprint("zap: {irMissing} function(s) the intermediate form cannot take or broke")
		return false
	written = g.genX64Finish(exePath, entryLabel, loadEntry)
	phaseEnded("write")
	written

# the start: the processor checked, the module variables, the entry, then the end with code 0
fn genX64Start(mut g Gen, entry str):
	g.genX64CpuCheck()
	g.genX64Run(entry)

# the module variables, the entry, then the end with code 0
fn genX64Run(mut g Gen, entry str):
	g.a.callLabel(fnLabel(g.fnLabels, g.a, "$init"))
	g.a.callLabel(fnLabel(g.fnLabels, g.a, entry))
	g.a.movRaxImm(0)
	g.a.pushRax()
	g.callRtNamed("endAfterMain", 8)
	g.a.em1(0xCC)

fn genX64CpuCheck(mut g Gen):
	g.a.leaRaxData(g.globalsOff)
	g.a.em4(0x48, 0x89, 0x60, 0x10)   # mov [rax+16], rsp
	# the processor is x86-64-v3 (the code uses AVX2, FMA and BMI2 freely): leaf 1 ecx has FMA
	# (12) and AVX (28), leaf 7 ebx AVX2 (5) and BMI2 (8)
	g.a.em5(0xB8, 0x01, 0x00, 0x00, 0x00)   # mov eax, 1
	g.a.em2(0x0F, 0xA2)   # cpuid
	g.a.em2(0x89, 0xCA)   # mov edx, ecx
	g.a.em2(0x81, 0xE2)   # and edx, FMA | AVX
	g.a.emit32(0x1000_1000)
	g.a.em2(0x81, 0xFA)   # cmp edx, FMA | AVX
	g.a.emit32(0x1000_1000)
	g.a.jccLabel(0x85, g.failCpu)   # (at the start: no function of its own)
	g.a.em5(0xB8, 0x07, 0x00, 0x00, 0x00)   # mov eax, 7
	g.a.em2(0x31, 0xC9)   # xor ecx, ecx
	g.a.em2(0x0F, 0xA2)   # cpuid
	g.a.em3(0x81, 0xE3, 0x20)   # and ebx, AVX2 | BMI2
	g.a.emN([0x01, 0x00, 0x00])
	g.a.em3(0x81, 0xFB, 0x20)   # cmp ebx, AVX2 | BMI2
	g.a.emN([0x01, 0x00, 0x00])
	g.a.jccLabel(0x85, g.failCpu)

fn genX64Finish(mut g Gen, exePath str, entry i64, loadEntry i64):
	g.mergeSameCode()
	if not onArm():
		g.a.asmRelax(g.debugLines, 4)
	g.writeDebugTable()
	if appBuild:
		g.writeAppTag(exePath)
	g.writeLayoutHash()
	ok = g.a.asmWriteElf(exePath, entry, g.globalsOff) if onLinux()
		else g.a.asmWritePe(exePath, entry, g.globalsOff + moduleVariablesSlot * 8)
	if ok and loadableBuild:
		g.writeLoadFile(exePath, loadEntry)
	if ok:
		if mapWord().on() or profileWord().on() or disasmWord().on():   # the last two read it
			g.writeSymbolMap(exePath)
	ok

# A function waiting to be generated: a declaration, a method (implDecl the generic impl whose
# instance it belongs to, else -1).
type PendingFn:
	key str
	fnd NodeId
	implType TypeId?
	implDecl NodeId?

# every function and method the program declares, by the label its calls name
fn pendingFunctions(mut g Gen):
	out = []
	for d in g.c.decls:
		k = nodes[d].kind
		if g.isTemplateDecl(d): continue
		if k == nFnDecl and nodes[d].names.isEmpty:
			out.push(
				PendingFn(key = nodes[d].text.copy(), fnd = d, implType = none, implDecl = none)
			)
		elif k == nImplDecl:
			sd = g.c.findTypeDecl(nodes[d].text) ?? continue
			implType = tyOfDecl(tys, nodes, sd)
			generic NodeId? = d if not nodes[d].names2().isEmpty else none
			for m in nodes[d].kids:
				out.push(
					PendingFn(
						key = "{tys[implType].name}_{nodes[m].text}",
						fnd = m,
						implType,
						implDecl = generic
					)
				)
	out

fn isTemplateDecl(g Gen, d NodeId):
	k = nodes[d].kind
	(k in [nStructDecl, nEnumDecl, nImplDecl]) and not nodes[d].names.isEmpty

# whether a call, a function value or another function's body asked for the label of key
fn labelWanted(g Gen, key str):
	match g.fnLabels.get(key):
		l: g.a.labelPos[l] < 0
		none: false

# Only what is called is generated: from the entry and the backend's own calls, each declared
# function, generic instance, drop, copy and environment function whose label something asked
# for, until generating them asks for nothing new. A function nothing calls takes no room.
fn genCalledFunctions(mut g Gen, pending PendingFn[]):
	doneFn = fill(pending.len, false)
	doneInst = []
	doneGiven = []
	progress = true
	while progress:
		progress = false
		for i in 0..pending.len:
			if not doneFn[i] and g.labelWanted(pending[i].key):
				doneFn[i] = true
				progress = true
				p = pending[i]
				if g.checkedBefore(p): continue
				if p.implDecl is impl:
					g.setSubstOf(impl)   # its substitution in force while it is generated
				g.genFunction(p.fnd, p.implType, p.key.copy(), p.copy())
				g.setSubst([], [])
		# generic instances, including the ones the backend itself requests from the runtime:
		# generating may add instances (moving the list)
		ii = 0
		while ii < g.c.instances.len:
			if doneInst.len <= ii:
				doneInst.push(false)
			key = "{nodes[g.c.instances[ii].fnDecl].text}_{g.c.instances[ii].mangle}"
			if not doneInst[ii] and g.labelWanted(key):
				doneInst[ii] = true
				progress = true
				g.c.checkInstance(ii)
				gi = g.c.instances[ii].copy()
				g.setSubst(gi.sub.names, gi.sub.types)   # its substitution in force while it is generated
				g.genFunction(gi.decl, none, key)
				g.setSubst([], [])
			ii += 1
		# the instances made for the functions calls gave (irgiven.zap): generating may add some
		gi = 0
		while gi < g.irGivenInstances.len:
			if doneGiven.len <= gi:
				doneGiven.push(false)
			if not doneGiven[gi] and g.labelWanted(g.irGivenInstances[gi].key):
				doneGiven[gi] = true
				progress = true
				g.genGivenInstance(g.irGivenInstances[gi].copy())
			gi += 1
		g.irMakeAll()   # (their code may ask for more)
		if not g.planned.isEmpty:
			g.genDropFunctions()
			progress = true

# the function fnd under key: an extern's stub, or lowered to be made with the round's others (a
# function the form cannot take fails the build: irMissing); once: checked once for a group
fn genFunction(mut g Gen, fnd NodeId, implType TypeId?, move key str, move once PendingFn? = none):
	if nodes[fnd].hasFlag(flagExtern):
		g.genExternFunction(fnd, key)
		if once is p: g.noteChecked(p, true)
		return
	_ = g.irTryFunction(fnd, key, implType, move once)

# the label of a function by its key (only the labels and the assembler change, so the key may
# be read from the nodes)
fn fnLabel(mut labels {str: i64}, mut a Asm, key str):
	match labels.get(key):
		l: return l
		none:
			l = a.asmNewLabel()
			labels[key.copy()] = l   # the map keeps a key of its own
			return l

# the substitution of the impl instance d in force (c's own copy: the instance keeps its lists)
fn setSubstOf(mut g Gen, d NodeId):
	g.c.subst = Subst(names = nodes[d].names2().copy(), types = nodes[d].ints().copy())

fn setSubst(mut g Gen, names str[], types TypeId[]):
	g.c.subst = Subst(names = names.copy(), types = types.copy())   # the substitution in force is c's own

# The entry of a system thread (CreateThread's start routine, the thread record in rcx: +0 the
# closure's code, +8 its environment): runs the closure and returns 1 as the exit code.
fn genOsThreadEntry(mut g Gen):
	g.a.asmPlace(fnLabel(g.fnLabels, g.a, "$osThreadEntry"))
	if onArm():
		g.a64ThreadEntry()
		return
	if onLinux():
		g.x64LinuxThreadEntry()
		return
	g.genThreadRun()
	g.a.movRaxImm(1)
	g.a.em1(0xC3)   # ret

# the closure of the thread's record in rcx run (+0 its code, +8 its environment), in a frame of
# its own given back after
fn genThreadRun(mut g Gen):
	g.a.framePrologue()
	g.a.em3(0x48, 0x89, 0xC8)   # mov rax, rcx
	g.a.em3(0xFF, 0x70, 0x08)   # push [rax+8]
	g.a.em2(0xFF, 0x10)   # call [rax]
	g.a.addRsp(8)
	g.a.em1(0x5D)   # pop rbp
