# zap test: the one command that checks a repository, or the dirs and files it is given. What runs
# is chosen three ways, combined: where (paths, a repository's root when none is given), which
# tests (a text their name holds) and which kinds of check (--only). spec 13.1 states the command.

import fs

# the kinds of check, in the order they run
checkKinds = [
	"build",
	"fmt",
	"dups",
	"limits",
	"check",
	"doc",
	"tests",
	"tokens",
	"size",
	"bench",
	"shots"
]

# the kinds that measure the entry files whose header asks for them (measures.zap, shots.zap)
measuredKinds = ["tokens", "size", "bench", "shots"]

# the kinds a zap on Linux leaves out: the suites and the rivals are Windows programs, the shots
# its GPU
windowsKinds = ["tokens", "size", "bench", "shots"]

# the measures that run only when --only names them: minutes each, and what a change of the
# language breaks the other kinds catch; doc lists what is left to write
namedKinds = ["doc", "size", "bench", "shots"]

# the kinds a plain run leaves out and --full adds: the layout is checked once, by the full run
fullKinds = ["fmt"]

# the kinds that check a whole repository: they run for a path that is a repository's root, or,
# named by --only, for the repository of every path
repositoryKinds = ["build", "dups", "limits"]

type TestRequest:
	paths str[]
	name str   # a text the names of the tests to run hold; "" for every test
	kinds str[]
	only bool   # the kinds were named by --only
	update bool
	slower str   # why a slower measure is accepted (--update "why")
	full bool   # fmt too, the fixed point's third build, bench at the real sizes, five runs
	fresh bool   # every file checked and tested again, bench measures every program again (ZAP_RUN=fresh)
	next bool   # where the worst measured case's time or bytes go (ZAP_RUN=next)
	jobs i64
	ab str = ""   # bench: Zap's programs raced against this zap's builds of them, no rivals (ZAP_RUN=ab=zap.exe)
	freshAll bool = false   # bench measures every language's programs again (ZAP_RUN=fresh=all)
	each str = ""   # the file listing the files this zap checks, or tests, in turn (set by the zap that starts it)

# the diagnostics of zap test, ZAP_RUN's words
fn freshWord():
	TraceWord(
		"fresh",
		"zap test: every file checked and tested again, the passes kept ignored; bench: Zap's programs measured again (fresh=all: every one's)"
	)

fn nextWord():
	TraceWord("next", "zap test: where the worst measured case's time or bytes go")

fn abWord():
	TraceWord(
		"ab",
		"zap test, bench: Zap's programs by the given zap and by this one, in turns (ab=build/base/zap.exe)"
	)

# set by the zap test that starts a zap for a list of files: the file listing them
fn eachVariable():
	InternalVariable("ZAP_TEST_EACH")

# zap test's command line refused: why, then its usage
fn testRefused(why str):
	commands.find(.name == "test")?.refused(why) ?? why.copy()

# the command line of zap test read: a path that exists is where, another text which tests
fn parseTestArgs(line CommandLine):
	request = TestRequest(
		paths = [],
		name = "",
		kinds = [],
		only = line.hasFlag("--only"),
		update = line.hasFlag("--update"),
		slower = line.option("--update") ?? "",
		full = line.hasFlag("--full"),
		fresh = freshWord().on(),
		next = nextWord().on(),
		jobs = defaultTestJobs(),
		ab = abWord().value() ?? "",
		freshAll = (freshWord().value() ?? "") == "all",
		each = eachVariable().value() ?? ""
	)
	env[eachVariable().name] = ""   # (for this zap alone: what it starts is not another's group)
	if line.option("--target") is name:
		chooseTarget(name)
	elif "bench" in (line.option("--only") ?? "").split(",") and benchTarget() is name:
		chooseTarget(name)
	if line.option("--jobs") is jobs:
		request.jobs = i64.parse(jobs) ?? 0
		if request.jobs < 1:
			exit(2, testRefused("--jobs takes a number of files, 1 or more"))
	for kind in (line.option("--only") ?? "").split(","):
		if kind in checkKinds:
			request.kinds.push(kind.copy())
		elif request.only:
			exit(2, testRefused("no kind of check is named {kind}: {checkKinds.join(", ")}"))
	for a in line.operands:
		if fs.exists(a):
			request.paths.push(withoutFinalSlash(a))
		elif request.name == "":
			request.name = a.copy()
		else:
			exit(2, testRefused("neither {a} nor {request.name} is a path; one name text at most"))
	if request.paths.isEmpty:
		request.paths.push(".")
	if not request.only:
		# a name text picks tests; with none, every kind
		request.kinds = ["tests"] if request.name != "" or not hostRuns()
			else checkKinds.filter(
				it not in namedKinds and (request.full or it not in fullKinds) and
					(onWindows() or it not in windowsKinds)
			)
	request

fn withoutFinalSlash(path str):
	end = path.len
	while end > 1 and (path[end - 1] == '/' or path[end - 1] == '\\'):
		end -= 1
	path[..end].copy()

# zap test [paths...] [name text] [--only kinds] [--update [why]] [--full] [--jobs N]: every kind
# asked for that has something to check, in checkKinds' order; the exit
# code 1 when one failed, or when a kind --only names has nothing to check
pub fn testCommand(line CommandLine):
	request = line.parseTestArgs()
	child = inTestRun()   # (another zap test's: for one file, entries to check, a test of it)
	if not child:
		capTestProcesses()
	run = testRunDir()
	_ = fs.createDir(run)   # (one a test of zap test names)
	# what the checks start (a bench suite's builds, a scripted run) finds this zap as `zap`
	env["PATH"] = "{fs.dirOf(exePath())}{pathListSeparator()}{env.get("PATH") ?? ""}"
	# no check opens a window or reads the person at the machine
	if not headlessWord().on():
		env[runVariable().name] = runWith(headlessWord().name)
	failed = []
	kinds = []
	for kind in checkKinds.filter(it in request.kinds):
		if kind in repositoryKinds and repositoriesFor(kind, request).isEmpty:
			if request.only:
				print("{kind}: no repository it checks among the paths")
				failed.push(kind.copy())
			continue
		if kind in measuredKinds and measuredFiles(kind, request).isEmpty:
			if request.only:
				print("{kind}: no entry file among the paths asks for it")
				failed.push(kind.copy())
			continue
		kinds.push(kind.copy())
	if onLinux() and not hostRuns():
		if runnerUnavailable():
			print("tests: skipped, {runnerName()} does not answer")
			exit(0)
		runSync(child, "tests" in kinds)
	times = []
	for kind in kinds:
		if kinds.len > 1:
			print("== {kind} ==")
		t0 = clockMs()
		if not runCheck(kind, request):
			failed.push(kind.copy())
		times.push("{kind} {(clockMs() - t0 + 500) / 1000} s")
	# the lint's findings, which the checks of check and tests kept (lint.zap); only the check of
	# every file says them, since a run of tests may be of programs a tool wrote
	lintSaid = request.each == "" and request.name == "" and "check" in kinds
	if lintSaid and not lintCheck(request.paths):
		failed.push("lint")
	runCleanUp()
	if not child:
		_ = fs.deleteTree(run)
	if kinds.len > 1 and not child:
		print("times: {times.join(", ")}")
	if kinds.len > 1 or not failed.isEmpty:
		if failed.isEmpty:
			print("== every check passed: {kinds.join(", ")} ==")
		else:
			print("== failed: {failed.join(", ")} ==")
	if lintSaid and not child and lintNotRun() != "":
		print(lintNotRun())
	exit(0 if failed.isEmpty else 1)

# one kind of check over the request's paths: whether it passed
fn runCheck(kind str, request TestRequest):
	if kind in repositoryKinds:
		passed = true
		for root in repositoriesFor(kind, request):
			passed = root.repositoryCheck(kind, request) and passed
		return passed
	if kind == "fmt":
		changed = 0
		for path in request.paths:
			changed += formatPath(path, true)
		if changed > 0:
			print("fmt: {changed} files not laid out (zap fmt <path> lays them out)")
		else:
			print("fmt: every file laid out")
		return changed == 0
	if kind == "check": return request.checkEntries()
	if kind == "doc": return request.undocumentedCheck()
	if kind == "tokens": return request.tokensCheck()
	if kind == "size": return request.sizeCheck()
	if kind == "bench": return request.benchCheck()
	if kind == "shots": return request.shotsCheck()
	counts = request.testBlocks()
	printTestSummary(counts)
	counts[1] == 0

# one whole-repository kind of check over the repository at root: whether it passed
fn repositoryCheck(root str, kind str, request TestRequest):
	if kind == "build": return compilerFixedPoint(root, request.full)
	if kind == "limits": return limitsCheck(root)
	dupsCheck(root, request.update)

# The repositories a whole-repository kind checks: the paths that are a repository's root, or,
# when --only names the kinds, the repository of every path; build only the zap repository's
fn repositoriesFor(kind str, request TestRequest):
	roots str[] = []
	for path in request.paths:
		full = fullPath(path)
		root = repositoryOf(full)
		if root != "" and (request.only or root == full) and root not in roots and
			(kind != "build" or isCompilerRepository(root)):
			roots.push(root)
	roots

fn isCompilerRepository(root str):
	fs.exists("{root}/{compilerSource}")

# the repository a path is in: the nearest dir at or above it holding .git, or ""
fn repositoryOf(full str):
	dir = full.copy()
	while dir != "":
		if fs.exists("{dir}/.git"): return dir
		up = fs.dirOf(dir)
		if up == dir: break
		dir = up.copy()
	""

# The zap repository at root (spec 14.1): zap1 is the compiler the host's seed (the newest of the
# branches seed and origin/seed) builds from the sources, in build/fixedpoint/1, or root's
# build/zap.exe when its stamp says the seed built it from these sources; zap1 builds zap2, the
# sources building themselves. Only --full goes on: zap2 builds zap3, and zap2 == zap3 says the
# compiler the seed built and the one it built itself generate the same code. It runs again only
# when the seed, or the sources a compiler is built from (compiler/, runtime/, std/), changed
# since it held (held.txt: a line for the plain run, one more once the full run held).
fn compilerFixedPoint(root str, full bool):
	dir = "{root}/{fixedPointDir}"
	branch = seedBranch(root)
	key = "{gitSays(root, "rev-parse {branch}", "")} {compilerSourcesHash(root)}"
	held = "{dir}/held.txt"
	kept = (fs.readFile(held) ?? "").lines()
	if key in kept and (not full or "full {key}" in kept):
		print("build: the fixed point holds (the seed and the sources unchanged since it held)")
		return true
	_ = fs.deleteFile(held)
	said = selfBuilds(root, branch, dir, full)
	if said == "":
		if full:
			print("build: the seed builds the compiler, and it rebuilds itself byte-identically")
			_ = fs.writeFile(held, "{key}\nfull {key}")
		else:
			print("build: the seed's compiler builds itself (--full: and again, byte-identically)")
			_ = fs.writeFile(held, key)
	else:
		print("build: {said}")
	said == ""

# where the fixed point builds, from the repository's root
fixedPointDir = "build/fixedpoint"

# the fixed point's builds in dir: what failed, "" when none did
fn selfBuilds(root str, branch str, dir str, full bool):
	zap = builtCompiler(root, host())
	if not root.seedBuiltFromCurrentSources(branch):
		said = seedBuild(root, branch, dir)
		if said != "": return said
		zap = builtCompiler("{dir}/1", host())
	last = 3 if full else 2
	for i in 2..=last:
		if not buildCompiler(root, zap, host(), "{dir}/{i}"):
			return "zap{i - 1} cannot build the compiler"
		zap = builtCompiler("{dir}/{i}", host())
	if full and not sameBytes(builtCompiler("{dir}/2", host()), builtCompiler("{dir}/3", host())):
		return "zap3 differs from zap2 (the compiler does not reproduce itself)"
	""

# zap1: the host's seed of the branch builds the compiler in dir/1; what failed, "" when nothing
fn seedBuild(root str, branch str, dir str):
	_ = fs.deleteFile("{dir}/{seedFile}")
	if Process.run(shellLine(inDir(root, seedLine(branch, host(), fixedPointDir)))) != 0:
		return "no seed for {hostTarget()} in the branch {branch}"
	if not buildCompiler(root, "{dir}/{seedFile}", host(), "{dir}/1"):
		return "the seed refuses these sources: promote the seeds with zap build --seeds (spec 14.1)"
	""

# a hash of the sources a build of the compiler reads, their paths and texts
fn compilerSourcesHash(root str):
	texts = []
	for dir in compilerSourceDirs:
		for file in fs.zapFiles("{root}/{dir}", false):
			texts.push("{file[root.len..]}\n{fs.readFile(file) ?? ""}")
	texts.join("\n").hash()
