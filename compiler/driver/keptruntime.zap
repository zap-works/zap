# The runtime loaded, checked and kept once in a zap that answers a test's requests (answers.zap):
# each program it then checks starts from a copy of that state, so the runtime's modules are
# parsed and checked once, not for every program. The program goes after the kept declarations
# (Checker.freshDecls), and the checker starts from the tables the runtime's check left
# (Checker.adoptKept).

# set while a zap answers requests: loadProgramModules starts from the kept runtime
mut keepRuntime = false

# set while the runtime's check runs: the checker is kept in the program (checkProgram)
mut keepsChecker = false

mut keptRuntime Program? = none
mut keptRuntimeFailed = false
mut keptTypeIndex {i64: TypeId} = {}
mut keptNumberBodies {NodeId: NodeId} = {}

# a program of entryFile holding the runtime as kept, none when the runtime cannot be kept
fn programOnKeptRuntime(entryFile str) Program?:
	if not keepRuntime or keptRuntimeFailed: return none
	if keptRuntime == none:
		keptRuntime = checkedRuntime()
		if keptRuntime == none:
			keptRuntimeFailed = true
			return none
	prog = (keptRuntime ?? return none).copy()
	prog.file = entryFile.copy()
	prog.entry = "main"
	typeIndex = keptTypeIndex.copy()
	numberBodies = keptNumberBodies.copy()
	prog

# the runtime alone, loaded and checked without the lint's notes, its checker kept; none when it
# does not check
fn checkedRuntime() Program?:
	prog = newProgram("")
	prog.entry = ""
	if not prog.addRuntime(true, true): return none
	prog.orderStages()
	noted = noting
	noting = false
	keepsChecker = true
	checked = prog.checkProgram()
	keepsChecker = false
	noting = noted
	if not checked or prog.kept == none: return none
	keptTypeIndex = typeIndex.copy()
	keptNumberBodies = numberBodies.copy()
	prog

# the checker c of the runtime's check kept in prog, to start the next check from
fn keepChecker(mut prog Program, move c Checker):
	c.freshDecls = prog.decls.len
	c.freshInstances = prog.instances.len
	prog.kept = move c

# what a check goes on with from the kept runtime's checker k: the counters and the asks its
# bodies left (lambdas numbered, the types noted for printing and derivatives, the generic types
# made, the ranges' types)
fn adoptKept(mut c Checker, move k Checker):
	c.freshDecls = k.freshDecls
	c.freshInstances = k.freshInstances
	c.lambdaCount = k.lambdaCount
	c.safeCallCount = k.safeCallCount
	c.madeAsked = move k.madeAsked
	c.deriveKinds = move k.deriveKinds
	c.deriveDone = move k.deriveDone
	c.rangeTypes = move k.rangeTypes
	c.fieldwise = move k.fieldwise
	c.fieldwiseDone = k.fieldwiseDone
	c.gradAsks = move k.gradAsks
	c.gradDone = k.gradDone
	c.gradHelpers = move k.gradHelpers
	c.gradHelpersDone = k.gradHelpersDone
