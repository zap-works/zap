# The test blocks of `zap test`: every `test "name" { ... }` of a file becomes a function the
# generated entry runs through testRun, which counts the failed expectations; once they all ran,
# every block the program allocated must have been freed (module variables included, after
# they are dropped), as ZAP_RUN=memstats checks. A test with `prints` statements captures
# stdout (testCaptureStart / testCaptureStop), each `prints` comparing what came since the last
# one with its text (testPrints). A test over a table of cases (`test "name" for x in cases:`)
# reports each case that failed (testCaseStart / testCaseEnd), each case counted as a test. The
# messages go to stderr, so a captured test's own output stays its own.

type TestState:
	failures i64   # the failed expectations of the running test
	updates str   # zap test --update: where a prints test that differs notes its output, or ""
	caseIndex i64 = -1   # the case of a table running, from 0
	caseShown str = ""   # its element, as the report shows it
	caseFailures i64 = 0   # the failures before the case started
	casesFailed i64 = 0   # the cases of the running table that failed
	ran i64 = 0   # the tests run, each case of a table one
	ranFailed i64 = 0   # those that failed
	countsFile str = ""   # where testExit writes ran and ranFailed for zap test, or ""
	index i64 = -1   # the running test's number, from 0
	asked i64 = 0   # the requests made of the zap running the tests (zapFmt)
	dir str = ""   # the running test's dir (testDir), "" until it asks for one
	listings i64 = 0   # the programs disassembly built
	ticks i64 = 0   # testTick's calls in the running test

mut testState = TestState(failures = 0, updates = "")

# zap test --update: a `prints` whose output differs notes it in the file instead of failing
# (zap rewrites the test's text from it)
fn testUpdatesTo(file str):
	testState.updates = file.copy()

# zap test: testExit writes how many tests ran and failed, each case of a table one, to the file
# beside the executable, its name's suffix taken off for `.counts`
fn testCountsBeside():
	exe = exePath()
	testState.countsFile = "{exe[..exe.len - exeSuffix().len]}.counts"

# a failed `expect`: where, the condition as written, and what its form says it was (each detail
# a line, cut past 300 bytes)
fn testFail(where str, text str, details str[]):
	testState.failures += 1
	msg = "    {where}: expect {text} failed"
	for detail in details:
		msg += "\n        {cutAt(detail, 300)}"
	eprint(msg)

# the text, or its first `most` bytes and how many more there are
fn cutAt(text str, most i64) str:
	if text.len <= most: return text.copy()
	"{text[..most]}... ({text.len - most} more bytes)"

# runs one test; 1 when it failed, 0 when it passed
fn testRun(file str, name str, body fn()) i64:
	testState.failures = 0
	testState.caseIndex = -1
	testState.casesFailed = 0
	testState.index += 1
	console.captured.reserve(65_536)   # the capture's room comes before the count
	setMemcheck()   # a use after free or a second free stops it at once
	dir = testDirPath()
	_ = deleteTree(dir)   # a run before whose test had the path
	env[buildsVariable().name] = dir   # what the test builds goes there
	body()
	endTestInput()
	_ = deleteTree(dir)
	testState.dir = ""
	if testState.caseIndex >= 0 and testState.failures == testState.caseFailures:
		testState.ran += testState.caseIndex + 1   # a table: each case a test
		testState.ranFailed += testState.casesFailed
	else:
		testState.ran += 1
		testState.ranFailed += 1 if testState.failures > 0 else 0
	if testState.failures > 0:
		eprint("FAIL {file}: {name}")
		return 1
	0

# The dir of the running test for the files it writes, its own (beside the test program,
# numbered by the test): made empty at the test's first call, removed with what it holds when the
# test ends. Ends with a slash: testDir() + "data.txt".
# The instructions the program `source` compiles the function `name` to (ZAP_RUN=disasm=name:
# a name of its map, `main` the program's statements), one a line without its address: what a
# test of the code a shape compiles to reads (spec 14.3)
pub fn disassembly(source str, name str) str:
	testState.listings += 1
	file = "{testDir()}listing{testState.listings}.zap"
	_ = writeFile(file, source)
	listing = processOutput("{zapPath()} build {file}", vars = [runAssignment("disasm={name}")]).out
	listing.lines().filter(.len > 10 and it[8] == ' ').map(it[10..].copy()).join("\n")

pub fn testDir() str:
	if testState.dir == "":
		testState.dir = testDirPath()
		_ = createDir(testState.dir[..len - 1])
	testState.dir.copy()

# the running test's dir (testDir), made or not
fn testDirPath() str:
	exe = exePath().replace("\\", "/")
	"{exe[..len - exeSuffix().len]}-{testState.index}/"

# text with dir taken out of the paths in it, written whole or from the working dir (as a program
# names its sources, spec 14.1)
pub fn withoutDir(text str, dir str) str:
	local = dir.replace("{currentDir().replace("\\", "/")}/", "")
	text.replace(dir, "").replace(local, "")

# A program and a module of its in the test's dir: the module's file `moduleFile` ("glow/glow.zap")
# holding source, the program's file `program` holding main; the dir
pub fn testProgram(moduleFile str, source str, program str, main str) str:
	dir = testDir()
	_ = createDir("{dir}{moduleFile[..(moduleFile.indexOf("/") ?? 0)]}")
	_ = writeFile("{dir}{moduleFile}", source)
	_ = writeFile("{dir}{program}", main)
	dir

# the zap a test runs: the working dir's build/zap, named as the system names an executable
pub fn zapPath() str:
	"build/zap{exeSuffix()}"

pub fn arm64Word() SetupWord:
	SetupWord(
		"arm64",
		"arm64=<ssh name>: the arm64 Linux machine of the bench and linux-arm64's tests"
	)

pub fn memoryWord() SetupWord:
	SetupWord("memory", "memory=MB: what a measured program may commit (2048 by default)")

# the machine arm64 in ZAP_SETUP names, "" for none
pub fn benchHost() str:
	arm64Word().value() ?? ""

# set by zap test for a test program it runs on this machine: where the program asks it to lay
# out a file (zapFmt)
pub fn answersVariable() InternalVariable:
	InternalVariable("ZAP_ANSWERS")

# zap fmt run on a test's file, with lint the forms only types tell kept for it by a check first
# (13.1.3): asked of the zap running the test (ZAP_ANSWERS), which does both in its own process,
# its compiler loaded; else zaps of their own run. Request n is the file <asks>-<n>.ask (what,
# then the file), its answer the file <asks>-<n>.done; one at a time.
pub fn zapFmt(file str, lint bool = false):
	asks = answersVariable().value() ?? ""
	if asks == "":
		if lint:
			_ = processOutput("{zapPath()} test --only check {file}")
		_ = processOutput("{zapPath()} fmt {file}")
		return
	ask = "{asks}-{testState.asked}"
	testState.asked += 1
	_ = writeFile("{ask}.tmp", "{"lint" if lint else "fmt"}\n{file}")
	_ = moveFile("{ask}.tmp", "{ask}.ask")   # (whole when the zap reads it)
	while not fileExists("{ask}.done"):
		sleepMs(1)

# what a program that starts zap build sets for the builds to go where it wants
pub fn buildsVariable() InternalVariable:
	InternalVariable("ZAP_BUILDS")

# the dir `zap build` writes executables in, ending with a slash: build/ under the working dir, or
# the running test's own dir for what a test starts (spec 13.1)
pub fn buildsDir() str:
	dir = buildsVariable().value() ?? return "build/"
	dir.copy() if dir.endsWith("/") else "{dir}/"

# the executable `zap build` writes for a source of this stem, as the system names it
pub fn builtExe(stem str) str:
	"{buildsDir()}{stem}{exeSuffix()}"

# stdout kept to compare with the test's `prints` texts
fn testCaptureStart():
	flushStdout()
	console.captured.clear()
	console.capturing = true

# the end of the capture: what came after the last `prints` goes to stdout
fn testCaptureStop():
	console.capturing = false
	if not console.captured.isEmpty:
		writeRaw(stdoutHandle, console.captured)
		console.captured.clear()

# `prints text`: the output since the last check against the text (each without one final
# newline); the next check starts after it
fn testPrints(expected str, where str):
	got = withoutFinalNewline(str(console.captured.copy()))
	console.captured.clear()
	want = withoutFinalNewline(expected)
	if got != want:
		if testState.updates != "":
			_ = appendFile(testState.updates, "{where}\n{got.len}\n{got}\n")
			eprint("    {where}: the expected text is rewritten")
			return
		testState.failures += 1
		eprint("    {where}: printed\n{indentLines(got)}\n    instead of\n{indentLines(want)}")

# a case of a table starts: its element as the report shows it
fn testCaseStart(shown str):
	testState.caseIndex += 1
	testState.caseShown = shown.copy()
	testState.caseFailures = testState.failures

# a case of a table ended: reported when it failed
fn testCaseEnd(file str, name str):
	if testState.failures > testState.caseFailures:
		testState.casesFailed += 1
		eprint("FAIL {file}: {name} [{testState.caseIndex}] {testState.caseShown}")
	testState.caseFailures = testState.failures   # a failure after the last case is the test's

# stdin.feed(text): the rest of the test reads its standard input from text (stdin.line(),
# stdin.all())
pub fn feed(input Input, text str):
	console.inBuf = text.bytes().copy()
	console.inLen = console.inBuf.len
	console.inPos = 0
	console.inEof = false
	console.inGiven = true

# 1 at a test's first call, then 2, 3...: an argument whose evaluations a test counts
pub fn testTick() i64:
	testState.ticks += 1
	testState.ticks

# the input, the arguments and the ticks of a test are given back with it
fn endTestInput():
	programArgs = commandLine()
	declaredOptions = []
	testState.ticks = 0
	console.inBuf = []
	console.inLen = 0
	console.inPos = 0
	console.inEof = false
	console.inGiven = false

fn withoutFinalNewline(s str) str:
	if s.endsWith("\n"): return s[..len - 1].copy()
	s.copy()

fn indentLines(s str) str:
	"        " + s.replace("\n", "\n        ")

# the number of failed tests out of those run (each case of a table one), then the exit code (the
# failed test blocks, at most 255)
# the line a test program says when its tests ran, which zap test finds again in its output
pub fn testSummary(ran i64, failed i64) str:
	if failed == 0: return "ok   {ran} tests"
	"{failed} of {ran} tests failed"

fn testExit(failed i64):
	eprint(testSummary(testState.ran, testState.ranFailed))
	if testState.countsFile != "":
		_ = writeFile(testState.countsFile, "{testState.ran} {testState.ranFailed}")
	console.captured = []
	flushStdout()
	threadsEnded(true)
	__fini()   # the module variables, the console among them
	leaked = liveBlocks()
	if leakNotesOn():
		setMainReturned()   # ZAP_RUN=leaks: the tests ran to their end, so the report judges
		reportLeaks()
	if leaked != 0:
		writeRaw(stderrHandle, "FAIL the tests left {leaked} blocks allocated\n".bytes())
		ExitProcess(failed.clamp(1, 255))
	ExitProcess(failed.min(255))
