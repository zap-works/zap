# Driver: the commands behind the zap executable.

import fs

# the texts the lint's check again reads in place of files' own (by notePath), and those read
mut sourceOverrides {str: str} = {}
mut overridesRead {str: bool} = {}

fn readSource(file str):
	if not sourceOverrides.isEmpty:
		key = notePath(file)
		if sourceOverrides.get(key) is patched:
			overridesRead[key.copy()] = true
			return patched.copy()
	noteFileTime(file)   # (the stamps of what the build read hold it)
	fs.readFile(file) ?? exit(1, "zap: cannot open '{file}': {error}")

# ZAP_RUN=tokens: the entry file's tokens, one a line
fn traceTokens(toks Tok[]):
	for t in toks:
		line = "{t.line:>3}:{t.col:<3} {tokKindName(t.kind):<16}"
		if t.kind in [tkInt, tkFloat, tkStr, tkStrBegin, tkStrMid, tkStrEnd] or
			t.kind == tkIdent or t.kind == tkUident or (t.kind >= tkFn and t.kind <= tkContinue):
			line = "{line} {t.text}"
		eprint(line)

# Loads and checks a program; exits on errors.
fn frontend(file str):
	phaseStarts()
	prog = loadProgram(file) ?? exit(1)
	phaseEnded("load")
	if not prog.checkProgram():
		exit(1, writtenParsed("zap: type checking failed"))
	phaseEnded("check")
	prog

# Whether a file checks, its errors printed: an entry file with its tests' bodies, a module's
# file with the module's other files. The lint's findings kept when it does (lint.zap).
pub fn checksFile(file str) bool:
	prog = loadProgram(file, true) ?? return false
	dir = dirPrefix(file)
	target = file.copy()
	if prog.tests.any(prog.nodes[it].file() == file):
		# the tests' bodies are checked too (a refuses or stops test's source by its own run)
		prog.addTestEntry(file, prog.runnableTests(file), "", false, 0)
	elif not prog.hasMain() and dir.len > 1 and prog.exportsAny(file):
		# a file of a module (it has no main and exports something): checked with the module's
		# other files, through a program beside them that imports the module (found from there
		# like any import)
		name = fs.fileName(fs.dirOf(file))
		prog = loadProgramText("{dir}$check.zap", "import {name}\n\npass\n") ?? return false
		target = dir[..len - 1].copy()
	# the ownership is checked on the lowered form, as a build checks it, nothing written
	if not prog.checkNoted(true): return false
	linted = prog.lintedFiles()   # (before the backend takes the declarations)
	lowered = prog.genX64("")
	keepFindings(linted, target, lowered)
	lowered

# zap build and zap run
pub fn buildFile(file str, run bool, programArgs str[]):
	# executables go to build/ under the working directory (or the dir a test gave, or the user's
	# cache, runStamp.zap), never next to the sources
	exePath = exeFileOf(fs.stem(file))
	keeps = loadableBuild or not appBuild and (not run or hostRuns())
	phaseStarts()
	kept = keeps and runKept(file, exePath)
	phaseEnded("unchanged check")
	if kept:
		if not run:
			print("built {exePath} (kept)")
			return
		ranBuilt(startBuilt(exePath, programArgs))
	parseWritesHeld = run
	prog = frontend(file)
	_ = fs.createDir(fs.dirOf(exePath))
	irCacheOpen(file)
	phaseEnded("cache open")
	if not prog.genX64(exePath):
		failed = "zap: checking failed" if irOwnErrors > 0 else "zap: cannot write {exePath}"
		exit(1, writtenParsed(failed))
	if disasmWord().value() is which:
		traceDisasm(exePath, which)
	if run and not appBuild and profileWord().value() == none:
		# the caches and the stamp written while the program starts
		started = startBuilt(exePath, programArgs)
		saveBuilt(file, exePath, keeps)
		forgetLastGen()
		ranBuilt(started)
	saveBuilt(file, exePath, keeps)
	if appBuild and not loadableBuild:
		apk = "build/{fs.stem(file)}.apk"
		if not writeApk(exePath, fs.stem(file), apk):
			exit(1, "zap: cannot write {apk}")
		exePath = apk
	if not run:
		print("built {exePath}")
		return
	if appBuild:
		exit(i32(runApp(exePath, fs.stem(file), programArgs)))
	ranBuilt(startBuilt(exePath, programArgs))

# the message a failed build ends with, once what it parsed is kept
fn writtenParsed(message str):
	writeParsed()
	message.copy()

# what a build keeps beside what it wrote: the caches and, but for an app's, the executable's stamp
fn saveBuilt(file str, exePath str, keeps bool):
	writeParsed()
	irCacheSave()
	keepCompilerKey(file, exePath)
	phaseEnded("cache save")
	if keeps: keepRun(file, exePath)
	phaseEnded("stamp")

# The executable built at exePath started with the program's arguments (here or where the
# target runs, run.zap), or run whole under ZAP_RUN=profile: the process, or the exit code
# profiled.
fn startBuilt(exePath str, programArgs str[]) Process:
	exe = hostPath(exePath)
	words = programArgs.map(" {quoteArg(it)}").join("")
	line = "{quoteArg(exe)}{words}" if hostRuns() and onWindows()
		else runCommand(exePath, [], words)
	p = match profileWord().value():
		watched: Process(handle = -1, code = profileRun(exePath, line, watched))
		none: Process.start(line)
	if p.handle == -1 and p.code == -1: exit(1, "zap: cannot start {exe}")
	p

# the program startBuilt started waited for, its exit code zap's
fn ranBuilt(move p Process):
	code = p.code if p.handle == -1 else p.wait()
	if code == 3_221_225_725:
		exit(3, "zap: crashed (stack overflow: unbounded recursion?)")
	if code == 3_221_225_477:
		exit(3, "zap: crashed (invalid memory access)")
	exit(i32(code - 4_294_967_296 if code > 2_147_483_647 else code))   # its 32 bits, signed

# ---------- zap test: the test blocks ----------
# Every test file under a path (a .zap file, or a dir: its .zap files and the dirs below)
# is built with its `test` blocks as the program and run; an `expects` test is checked on its own,
# by a second zap.

# The test blocks of the test files under the request's paths whose name holds its name text,
# its jobs files at once: [how many tests, how many failed]. A file whose header needs files of
# the user's that are missing is skipped, with a line. With update, a prints test whose output
# differs has its expected text rewritten to the output (for a change of output that is meant).
pub fn testBlocks(request TestRequest) i64[]:
	name = request.name
	if request.each != "":
		testListed(
			request.each,
			name,
			request.update,
			name == "" and not request.update and not request.fresh
		)
		return [0, 0]
	files = sourceFiles(request.paths).filter(f:
		text = fs.readFile(f) ?? ""
		hasTests(text) and name in text and not skipsOnTarget(f, text) and
			not skippedForNeeds(f, text)
	)
	counts = [0, 0]
	if files.len > 1:
		command = "test --only tests{targetOption()}"
		counts = testInGroups(
			files,
			runJobs(request.jobs),
			command,
			"{nameArgument(name)}{" --update" if request.update else ""}",
			name == "" and not request.update,
			not request.fresh
		)
	else:
		for file in files:
			one = testFile(file, name, request.update)
			counts[0] += one[0]
			counts[1] += one[1]
			if one[1] > 0:
				failedTestFiles.push(file.copy())
	counts

# the test files that failed in this run, named again by the summary
mut failedTestFiles str[] = []

# the summary of a run of test blocks
pub fn printTestSummary(counts i64[]):
	if not failedTestFiles.isEmpty:
		print("failed files: {failedTestFiles.join(", ")}")
	if counts[1] == 0:
		print("== {counts[0]} tests passed ==")
	else:
		print("== {counts[1]} of {counts[0]} tests failed ==")

# the name filter handed to the zap that tests one file: " \"name\"", or ""
fn nameArgument(name str):
	"" if name == "" else " {quoteArg(name)}"

# The .zap files under the paths, the files of a program's dirs too (its module files' tests
# run with them)
pub fn sourceFiles(paths str[]) str[]:
	files = []
	for path in paths:
		files.extend(fs.walk(path, sources = true))
	files

# ---------- the files run in parallel ----------
# Each test file is run by a zap of its own (`zap test --only tests file`), several at once, a new
# one started only while the machine has 3 GB free. Every process of the run (the zaps, the
# programs they build and start) lives in a job of the system, below normal priority, that kills
# one past testMemoryMb or testCpuSeconds of processor time; a file whose zap runs past
# testTimeoutMs is killed with what it started: a runaway fails its file instead of the machine.
# A file's artifacts are its own (runFileOf), the outputs printed in the files' order.

testMemoryMb = 4096
testCpuSeconds = 300
# a process that waits or spins in the system past it is killed with what it started (the job's
# limit counts only time in the program's own code)
testTimeoutMs = 600_000
# the memory a file's zap and its programs may take, which the free memory leaves room for
testJobMb = 1536

extern fn CreateJobObjectA(attributes i64, name i64) i64
extern fn SetInformationJobObject(job i64, kind i64, info u8[], size i64) bool
extern fn QueryInformationJobObject(job i64, kind i64, info u8[], size i64, returned i64) bool
extern fn AssignProcessToJobObject(job i64, process i64) bool
extern fn GetCurrentProcess() i64
extern fn GlobalMemoryStatusEx(status u8[]) bool
extern fn GetProcessId(process i64) i64

# the process h and every process it started, killed
fn killTree(p Process):
	killProcessTree(GetProcessId(p.handle))

# cmd run to its end, or killed with what it started once it has run ms milliseconds, or, with
# cpuMs, once it and what it started have used cpuMs of processor time (on Windows, counted by a
# job of the system; on Linux the caller's runCommand caps each process with ulimit -t): its exit
# code, -2 when it was killed past the time, -3 past the processor time. With asks, the requests
# a test program makes there are answered meanwhile (answers.zap).
fn runWithin(cmd str, ms i64, asks str = "", cpuMs i64 = 0):
	p = Process.start(cmd)
	if p.handle == -1: return -1
	job = jobHolding(p) if cpuMs > 0 else 0
	since = clockMs()
	looked = since
	asked = 0
	code = 0
	while not p.isDone:
		now = clockMs()
		if now - since >= ms:
			code = -2
		elif job != 0 and now - looked >= 100:
			looked = now
			if jobCpuMs(job) >= cpuMs: code = -3
		if code < 0:
			p.killTree()
			p.wait()
			break
		if asks != "" and answerAsked(asks, asked):
			asked += 1
		else:
			sleepMs(1)
	if job != 0: closeJob(job)
	if code < 0: return code
	return p.wait()

# a job of the system holding p and what it starts from now on, 0 when p cannot be put in one
fn jobHolding(p Process) i64:
	job = CreateJobObjectA(0, 0)
	if job == 0: return 0
	if AssignProcessToJobObject(job, p.handle): return job
	closeJob(job)
	0

# the job released (its processes go on)
fn closeJob(job i64):
	_ = CloseHandle(job)

# the processor time, in milliseconds, the processes of the job have used, those that ended too
fn jobCpuMs(job i64) i64:
	info u8[] = zeros(48)   # JOBOBJECT_BASIC_ACCOUNTING_INFORMATION
	if not QueryInformationJobObject(job, 1, info, 48, 0): return 0
	(i64(info.loadWord(0)) + i64(info.loadWord(8))) / 10_000   # TotalUserTime and TotalKernelTime, 100 ns

# how long a file's tests may take on the wall clock whatever their processor time, which
# only a hang reaches: three times their limit of processor time
fn testWallMs(limitMs i64):
	limitMs * 3

# how many files are run at once unless --jobs says: half the processors, up to 6, as many as
# the free memory gives each testJobMb
pub fn defaultTestJobs() i64:
	(cpuCount() / 2).min(freeMemory() / (testJobMb * 1_048_576)).clamp(1, 6)

# the 8 bytes of v at off in bytes, low byte first
fn bytesWord(mut bytes u8[], off i64, v i64):
	for i in 0..8:
		bytes[off + i] = (v >> (8 * i)) & 255

# This process, and every process it starts, in a job below normal priority that kills a process
# past testMemoryMb of committed memory or testCpuSeconds of processor time (no limit on all of
# them together: one that followed the memory free at the start made the tests fail by what else
# ran). Once per run, by the zap that begins it: the zaps it starts are in the same job.
pub fn capTestProcesses():
	job = CreateJobObjectA(0, 0)
	if job == 0: return
	info u8[] = zeros(144)   # JOBOBJECT_EXTENDED_LIMIT_INFORMATION
	bytesWord(info, 0, testCpuSeconds * 10_000_000)   # PerProcessUserTimeLimit, in 100 ns
	# LimitFlags: PROCESS_TIME 2, PRIORITY_CLASS 32, PROCESS_MEMORY 256
	bytesWord(info, 16, 2 | 32 | 256)
	bytesWord(info, 56, 0x4000)   # PriorityClass: BELOW_NORMAL_PRIORITY_CLASS
	bytesWord(info, 112, testMemoryMb * 1_048_576)   # ProcessMemoryLimit
	if SetInformationJobObject(job, 9, info, 144):
		AssignProcessToJobObject(job, GetCurrentProcess())

# the machine's physical memory not in use, in bytes
fn freeMemory() i64:
	status u8[] = zeros(64)   # MEMORYSTATUSEX, dwLength first
	status[0] = 64
	if not GlobalMemoryStatusEx(status): return 0
	i64(status.loadWord(16))   # ullAvailPhys

extern fn CreateToolhelp32Snapshot(flags i64, pid i64) i64
extern fn Process32First(snapshot i64, entry u8[]) bool
extern fn Process32Next(snapshot i64, entry u8[]) bool
extern fn OpenProcess(access i64, inherit bool, pid i64) i64
extern fn K32GetProcessMemoryInfo(process i64, counters u8[], size i64) bool

# The memory each of the processes holds now with every process it started, and theirs: their
# working sets, in bytes (0 for one that ended). One look at every process for them all.
fn treeMemories(pids i64[]):
	snapshot = CreateToolhelp32Snapshot(2, 0)   # TH32CS_SNAPPROCESS
	if snapshot == -1: return zeros(pids.len)
	ids i64[] = []
	parents i64[] = []
	entry u8[] = zeros(304)   # PROCESSENTRY32, dwSize first
	entry[0] = 48
	entry[1] = 1
	going = Process32First(snapshot, entry)
	while going:
		ids.push(entry.u32le(8))   # th32ProcessID
		parents.push(entry.u32le(32))   # th32ParentProcessID
		going = Process32Next(snapshot, entry)
	CloseHandle(snapshot)
	pids.map(treeOf(it, ids, parents).map(processMemory(it)).sum())

# the process and the ones it started, and theirs, of the processes' ids and their parents'
fn treeOf(pid i64, ids i64[], parents i64[]):
	tree = [pid]
	at = 0
	while at < tree.len:
		for i, parent in parents:
			if parent == tree[at] and ids[i] != parent and ids[i] not in tree:
				tree.push(ids[i])
		at += 1
	tree

# the working set of the process with the id, 0 when it cannot be read
fn processMemory(pid i64):
	h = OpenProcess(0x1000, false, pid)   # PROCESS_QUERY_LIMITED_INFORMATION
	if h == 0: return 0
	counters u8[] = zeros(72)   # PROCESS_MEMORY_COUNTERS
	counters[0] = 72
	read = K32GetProcessMemoryInfo(h, counters, 72)
	CloseHandle(h)
	i64(counters.loadWord(16)) if read else 0   # WorkingSetSize

# the name a file's artifacts take: its path, every separator a dash
fn testSlug(file str):
	file.replace("/", "-").replace("\\", "-").replace(":", "-").replace(".zap", "")

# The tests of one file whose name holds `name`: [how many, how many failed]. With update, a
# prints test that differs notes its output instead of failing, and its text is rewritten. The
# stops tests whose sources checked together are modules of the file's test program (StopsLeft).
# With useKept, a program built as the file's kept pass ran it is not run again (runTests).
fn testFile(file str, name str, update bool, useKept bool = false):
	updates = runFileOf(file, ".updates") if update else ""
	began = clockMs()
	prog = loadProgramModules(file, readSource(file), true) ?? return unloaded(file)
	notePhase("load", clockMs() - began)
	windows = skippedTests(file)   # (none but on Linux)
	expected = prog.tests.filter(
		prog.nodes[it].file() == file and prog.nodes[it].ival >= 2 and
			name in prog.nodes[it].text and
			prog.nodes[it].line not in windows
	)
	count = expected.len
	left = StopsLeft(tests = [], paths = [])
	failed = 0
	n = 0
	if not expected.isEmpty:
		failed = prog.testExpected(file, expected, left)
		n = left.tests.len
		# their checks loaded programs of their own in this zap, which forgot the file's; the stops
		# sources go in before the runtime, which what they name reaches too
		prog = loadOwnModules(file, readSource(file)) ?? return unloaded(file)
		if not prog.addUnits(file, left.paths, fill(n, "-"), (0..n).map(it), false):
			return [count, failed + n]   # (a source the together check passed does not load: said)
		if not prog.addRuntime(false, true): return unloaded(file)
	runnable = prog.runnableTests(file).filter(
		name in prog.nodes[it].text and prog.nodes[it].line not in windows
	)
	prog.linkLoaded()
	if not runnable.isEmpty or n > 0:
		if update:
			_ = fs.deleteFile(updates)   # a run cut short left it
		ran = prog.runTests(file, runnable, updates, left, name == "", useKept)
		count += ran[0]
		failed += ran[1]
	if timesWord().on():
		eprint("times {file}: {clockMs() - began} ms: {testPhases.join(", ")}")
	if update:
		rewritten = applyUpdates(updates)
		if rewritten > 0:
			print("== {rewritten} expected texts rewritten ==")
	[count, failed]

# a test file whose loading said an error (it does not lex or parse, an import is missing): its
# tests one failure
fn unloaded(file str):
	eprint("FAIL {file}: the tests do not compile")
	[1, 1]

fn timesWord():
	TraceWord(
		"times",
		"where each test file's time goes: loading, the tests that expect an error, checking, code, lint, running"
	)

# the phases of the test file this zap runs, each "name ms" (ZAP_RUN=times)
mut testPhases str[] = []

# a phase's milliseconds noted, when ZAP_RUN has times
fn notePhase(name str, ms i64):
	if timesWord().on():
		testPhases.push("{name} {ms} ms")

# The runnable tests as functions $test0..; an entry runs each through testRun, its exit code
# the number of failed tests. Started with arguments, the entry runs the program's own main
# instead: a test can start its program again as a child (a client of the server it tests)
# with "{exePath()} client ...". Started with ZAP_TEST_STOPS set to k, it runs the main of the
# k-th of its stops sources (units, the last modules) instead. A prints test that differs notes
# its output in `updates` instead of failing, when it is not "" (zap test --update); with
# counted, the counts of the run go beside the executable (testCountsBeside).
fn addTestEntry(mut prog Program, file str, tests NodeId[], updates str, counted bool, stops i64):
	main = "fn $testMain():\n"
	if stops > 0:
		main += "\tstops = env.get({zapQuote(stopsVariable().name)}) ?? \"\"\n"
		for k in 0..stops:
			main += "\tif stops == \"{k}\":\n\t\t{prefixFor(unitModuleId(k))}main()\n\t\treturn\n"
	if prog.hasMain():
		main += "\tif args.len > 0:\n\t\tmain()\n\t\treturn\n"
	main += "\tfailed = 0\n"
	if counted:   # (beside the executable: a path of the run's would make each build another)
		main += "\t$rt.testCountsBeside()\n"
	if updates != "":
		main += "\t$rt.testUpdatesTo({zapQuote(updates)})\n"
	for i, test in tests:
		t = test
		f = newNode(prog.nodes, prog.kidIds, nFnDecl, prog.nodes[t].line, prog.nodes[t].col)
		prog.nodes[f].text = "$test{i}"
		prog.nodes[f].setText2("$test{i}")
		prog.nodes[f].nodePart().file = file.copy()
		prog.nodes[f].flags = prog.nodes[t].flags & flagOptions
		prog.nodes[f].nodePart().sub.push(prog.testBody(file, t))
		prog.decls.push(f)
		main += "\tfailed += $rt.testRun({zapQuote(file)}, {zapQuote(prog.nodes[t].text)}, $test{i})\n"
	main += "\t$rt.testExit(failed)\n"
	entry = parseInternal(main, "<tests>", prog.nodes, prog.kidIds)
	prog.adoptDecls(moduleIndex(prog.modules, ""), entry, file)
	prog.entry = "$testMain"

# The runnable tests built and run, then the stops tests left (stopsRun): [how many ran, how many
# failed], each case of a table one (the program writes them to the file of counts); all of them
# failed when it did not end well. With lint (every test of the file), the lint's findings kept.
# What it built is told in the file's .built (its hash, how many the run counted); with useKept, a
# program built as the kept pass's (keptRun) is not run, what that run read noted as read.
fn runTests(
	mut prog Program,
	file str,
	tests NodeId[],
	updates str,
	left StopsLeft,
	lint bool,
	useKept bool
):
	counts = runFileOf(file, ".counts")
	_ = fs.deleteFile(counts)   # a run cut short left it
	prog.addTestEntry(file, tests, updates, true, left.tests.len)
	since = clockMs()
	if not prog.checkNoted(lint):
		eprint("FAIL {file}: the tests do not compile")
		return [tests.len, tests.len + stopsUnbuilt(file, left, "the tests do not compile")]
	linted = prog.lintedFiles() if lint else []   # (before the backend takes the declarations)
	notePhase("check", clockMs() - since)
	since = clockMs()
	exe = runFileOf(file, exeExtension())
	irCacheOpen(file)
	if not prog.genX64(exe):
		irCacheClose()
		eprint("FAIL {file}: cannot write {exe}")
		return [tests.len, tests.len + stopsUnbuilt(file, left, "cannot write {exe}")]
	irCacheSave()
	notePhase("code", clockMs() - since)
	if lint:
		since = clockMs()
		keepFindings(linted, file, true)
		notePhase("lint", clockMs() - since)
	built = hashWord(fs.readFile(exe) ?? "")
	if useKept and keptRun(file) is kept and kept.built == built:
		_ = fs.appendFile(runFileOf(file, ".reads"), kept.files.map("{it}\n").join(""))
		left.takeAway()
		_ = fs.deleteFile(exe)
		_ = fs.writeFile(runFileOf(file, ".built"), "{built} {kept.ran}")
		return [kept.ran, 0]
	ran = [0, 0] if tests.isEmpty else prog.ranTests(file, exe, tests, counts)
	ran[1] += stopsRun(file, exe, left)
	_ = fs.deleteFile(exe)
	_ = fs.writeFile(runFileOf(file, ".built"), "{built} {ran[0]}")
	ran

# the test program at exe run: [how many tests ran, how many failed]
fn ranTests(prog Program, file str, exe str, tests NodeId[], counts str):
	allFailed = [tests.len, tests.len]
	since = clockMs()
	limit = testLimitMs(fs.readFile(file) ?? "")
	asks = runFileOf(file, "") if hostRuns() else ""   # (a program run elsewhere asks nothing)
	set str[] = [] if asks == "" else ["{answersVariable().name}={asks}"]
	cpuSeconds = (limit + 999) / 1000
	out = runFileOf(file, ".out")
	code = runWithin(
		runCommand(exe, set, " > {quoteArg(out)} 2>&1", cpuSeconds),
		testWallMs(limit),
		asks,
		limit
	)
	notePhase("run", clockMs() - since)
	runFetch(counts)
	runFetch(out)
	said = (fs.readFile(counts) ?? "").split(" ")
	ran = i64.parse(said[0]) ?? tests.len
	failed = (i64.parse(said[1]) ?? code) if said.len == 2 else code
	showProgramOutput(file, out, testSummary(ran, failed) if said.len == 2 else "")
	if code == -3 or (code == cpuKilledCode and hostRuns() and not onWindows()):
		eprint(
			"FAIL {file}: the tests ran past {limit / 1000} s of processor time and were stopped"
		)
		return allFailed
	if code == -2:
		eprint("FAIL {file}: the tests ran past {testWallMs(limit) / 1000} s on the clock and were stopped")
		return allFailed
	if said.len == 2 and failed == 0 and code != 0:
		eprint("FAIL {file}: the program stopped after its summary (exit code {code})")
		return [ran, 1]
	if code < 0 or code > tests.len:
		eprint("FAIL {file}: the tests crashed (exit code {code})")   # a failure stopped the program
		return allFailed
	if said.len != 2:
		eprint("FAIL {file}: the tests ended without a summary (exit code {code})")   # out of memory, killed
		return [tests.len, code.max(1)]
	[ran, failed]

# what a test program wrote, line by line; those after its summary line name the file
fn showProgramOutput(file str, out str, summary str):
	past = false
	for line in (fs.readFile(out) ?? "").lines():
		eprint("{file}: {line}" if past else line)
		past = past or line == summary
	_ = fs.deleteFile(out)

# the file's tests that run in its program (prints and plain ones; an imported module's run
# with that module)
fn runnableTests(prog Program, file str):
	prog.tests.filter(prog.nodes[it].file() == file and prog.nodes[it].ival < 2)

# whether the file declares something public
fn exportsAny(prog Program, file str):
	prog.decls.any(prog.nodes[it].file() == file and prog.nodes[it].hasFlag(flagPub))

# whether the program declares a main of its own
fn hasMain(prog Program):
	prog.decls.any(prog.nodes[it].kind == nFnDecl and prog.nodes[it].text == "main")

# a test's body; a table's cases each report their failure, and the body of a test with
# `prints` checks is wrapped in the capture of stdout
fn testBody(mut prog Program, file str, t NodeId):
	body = prog.nodes[t].sub()[0]
	line = prog.nodes[t].line
	col = prog.nodes[t].col
	if prog.nodes[t].text2() == "for":
		prog.reportCases(file, t, body)
	if prog.nodes[t].ival != 1: return body
	blk = newNode(prog.nodes, prog.kidIds, nBlock, line, col)
	start = internalCallStmt(prog.nodes, prog.kidIds, "testCaptureStart", [], line, col)
	prog.nodes[blk].pushKid(prog.kidIds, start)
	always = newNode(prog.nodes, prog.kidIds, nBool, line, col)
	prog.nodes[always].ival = 1
	inner = newNode(prog.nodes, prog.kidIds, nIf, line, col)
	prog.nodes[inner].pushKid(prog.kidIds, always)
	prog.nodes[inner].nodePart().sub.push(body)
	prog.nodes[blk].pushKid(prog.kidIds, inner)
	madeKid = internalCallStmt(prog.nodes, prog.kidIds, "testCaptureStop", [], line, col)
	prog.nodes[blk].pushKid(prog.kidIds, madeKid)
	blk

# the loop of a table of cases (`test "name" for x in cases:`): each round starts a case with
# its element's text and ends it, reported when it failed
fn reportCases(mut prog Program, file str, t NodeId, body NodeId):
	cases = prog.nodes[body].kids(prog.kidIds)[0]
	round = prog.nodes[cases].sub()[0]
	line = prog.nodes[t].line
	col = prog.nodes[t].col
	element = newNode(prog.nodes, prog.kidIds, nIdent, line, col)
	prog.nodes[element].text = prog.nodes[cases].text.copy()
	toText = newNode(prog.nodes, prog.kidIds, nIdent, line, col)
	prog.nodes[toText].text = "str"
	shown = newNode(prog.nodes, prog.kidIds, nCall, line, col)
	prog.nodes[shown].pushKid(prog.kidIds, toText)
	prog.nodes[shown].pushKid(prog.kidIds, element)
	madeKid = internalCallStmt(prog.nodes, prog.kidIds, "testCaseStart", [shown], line, col)
	prog.nodes[round].insertKid(prog.kidIds,
		0, madeKid)
	fileText = newNode(prog.nodes, prog.kidIds, nStr, line, col)
	prog.nodes[fileText].text = file.copy()
	nameText = newNode(prog.nodes, prog.kidIds, nStr, line, col)
	prog.nodes[nameText].text = prog.nodes[t].text.copy()
	madeKid = internalCallStmt(
		prog.nodes,
		prog.kidIds,
		"testCaseEnd",
		[fileText, nameText],
		line,
		col
	)
	prog.nodes[round].pushKid(prog.kidIds, madeKid)

# a Zap string literal of s
fn zapQuote(s str):
	"\"{s.replace("\\", "\\\\").replace("\"", "\\\"").replace(r"{", r"\{")}\""

# ---------- zap test --update ----------

# One rewrite: the test at `line` of `file` prints `text`.
type Update:
	file str
	line i64
	text str

# the updates the tests noted in the file, each test's file rewritten (its tests from the last
# up, so the lines above stay where they are); how many tests changed
fn applyUpdates(updatesFile str):
	records = fs.readFile(updatesFile) ?? ""
	updates = []
	at = 0
	while at < records.len:
		nl = records.indexOf("\n", at) ?? -1
		if nl < 0: break
		where = records[at..nl]
		nl2 = records.indexOf("\n", nl + 1) ?? -1
		size = i64.parse(records[nl + 1..nl2]) ?? 0
		colon = where.len - 1
		while colon > 0 and where[colon] != ':':
			colon -= 1
		updates.push(Update(
			file = where[..colon].copy(),
			line = i64.parse(where[colon + 1..]) ?? 0,
			text = records[nl2 + 1..nl2 + 1 + size].copy()))
		at = nl2 + 1 + size + 1
	files str[] = []
	for u in updates:
		if u.file not in files:
			files.push(u.file.copy())
	changed = 0
	for f in files:
		text = fs.readFile(f) ?? ""
		# the file keeps its line endings: \r\n when its first line ends so
		first = text.indexOf("\n") ?? -1
		ending = "\r\n" if first > 0 and text[first - 1] == '\r' else "\n"
		lines = text.replace("\r\n", "\n").lines()
		mine = updates.filter(.file == f).sortedBy(-.line)
		for u in mine:
			if rewriteExpected(lines, u.line - 1, u.text):
				changed += 1
			else:
				eprint("{f}:{u.line}: the expected text could not be found to rewrite")
		_ = fs.writeFile(f, "{lines.join(ending)}{ending}")
	_ = fs.deleteFile(updatesFile)
	changed

# The text of the `prints` statement at index `at` replaced by `text`: one line in quotes when it
# fits, else a block between triple quotes indented one tab past the statement.
fn rewriteExpected(mut lines str[], at i64, text str):
	if at < 0 or at >= lines.len: return false
	indent = lines[at][0..lines[at].len - lines[at].trimmedStart().len].copy()
	if not lines[at].trimmedStart().startsWith("{printsWord} "): return false
	start = indent.len + printsWord.len + 1
	head = lines[at][0..start].copy()
	# where the old text ends: on this line, or the line holding the closing triple quote
	last = at
	tail = ""
	if lines[at][start..lines[at].len].startsWith("\"\"\""):
		j = at + 1
		while j < lines.len and not lines[j].trimmed().startsWith("\"\"\""):
			j += 1
		if j >= lines.len: return false
		last = j
		closing = lines[j].trimmed()
		tail = closing[3..].trimmed().copy()
	else:
		rest = lines[at][start..lines[at].len]
		k = 1
		while k < rest.len and rest[k] != '"':
			k += 2 if rest[k] == '\\' else 1
		tail = rest[k + 1..].copy()
	out = []
	if "\n" not in text and text.len < 70:
		out.push(head + zapQuote(text) + tail)
	else:
		out.push("{head}\"\"\"")
		for l in text.lines():
			out.push("{indent}\t{l.replace("\\", "\\\\").replace(r"{", r"\{")}")
		out.push("{indent}\t\"\"\"{tail}")
	for _ in at..=last:
		lines.remove(at)
	for i in 0..out.len:
		lines.insert(at + i, out[i].copy())
	true
