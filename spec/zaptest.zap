# 13.1.1 `zap test`

import fs

# `zap test` is the one command that checks, the same in any repository. What runs is
# chosen three ways, combined: where (the paths, dirs or files, another repository's too; none
# is the working dir, at a repository's root every check before a commit), which tests (a text
# that is no existing path runs the tests whose name holds it, and only the `tests` kind unless
# `--only` names others) and which kinds (`--only` and a comma list; without it, every kind but
# `fmt`, which `--full` adds, and `doc` and the measures `size`, `bench` and `shots`, which run
# only when named).
#
# The kinds: `fmt` (every file laid out as `zap fmt` lays it out), `dups` (no new copy of code
# against the repository's `baselines/dups.baseline`: blocks of six or more lines alike once comments, names
# and literals are set aside), `limits` (no `.zap` file over 1,000 lines and no function body over
# 100 lines; a table file, or a function that is one line per arm, is exempt by a comment line
# `# long: why` in the file's leading comments, or in the comments directly above the function),
# `check` (every entry file, one with top-level statements or tests, checked as `zap build` checks
# without building; a file named alone is checked whatever it holds, a module's file with its
# module's other files), `tests` (the test blocks, 12), `build` (in the `zap` repository: the
# seed builds the compiler, which builds itself, the sources checking and building with themselves;
# `--full` builds it once more and the last two are byte-identical), `doc` (no
# public declaration without a comment line saying what it does, as `zap doc` answers from them; a
# module's name as the name text limits it), `tokens`, `size`, `bench` and `shots` (below). `dups`, `limits` and `build` check a whole repository: they run for
# a path that is a repository's root (a dir holding `.git`), or, named by `--only`, for the
# repository of every path.
#
# A run of `check` fails as `lint` too while a file under its paths has forms only types tell kept
# for its text (13.1.3), a line each; a run of `tests` keeps them but does not say them, as the files
# it runs may be programs a tool wrote. Where the lint is not noted (any host but Windows) the run
# ends with a line saying so, `lint: not run on linux; run zap test --only check on Windows
# before landing`.
#
# A test program's output is kept apart and shown once it ends: every line it says past its
# summary (`ok 12 tests`) leads with its file's path, and a program that ends with an error code
# after saying its tests passed fails its file (`the program stopped after its summary`).
#
# `--update` writes what a check keeps once it ran: each differing `prints` text, and
# `dups.baseline` without the copies that are gone (a word after it that is no path, `--update
# "why"`, is the reason a slower measure is accepted for, below; a name text goes before it). `--jobs N` runs N files at once (by default
# half the processors, up to 6, and no more than the free memory leaves 1.5 GB each): N zaps run
# or check the files in turn, the compiler loaded once a zap, every zap and what it starts below
# normal priority and killed past 4 GB of memory or 300 s of processor time, a zap past 1,200 s on
# one file killed too, which fails that file. `tests` hands each zap its next file as it ends one,
# the slowest of the run before first (`build/test/times.txt`, which a run of many files writes),
# so no zap ends long after the others, the first that fits in memory: a file starts only while
# the peaks of the files running and its own fit in the memory free, a file's peak the most its
# zap and what it started held at once in its last run (kept in `build/cache/passes/`; 1.5 GB for
# one never run), and one file runs even when it alone does not fit, a line saying which file waits for
# which files when none starts; a zap that ends before its file did fails that file, and one that
# does not end a minute after it was stopped past its limit is given up on and fails it too, another
# zap taking its place; `check` gives each zap a group of the entry files, the
# files after one that ended its zap going to the next round's zaps, as do those a zap leaves when
# it has spent half the processor time a zap may. A test program's functions keep their
# optimized form in `build/cache/` as a build's (13.1), and in `check` a module's function (not a
# generic's instance) is lowered and checked once for every entry whose module and the modules it
# imports are the same files, one that did not check checked again for each. What `zap test`
# starts finds the running zap first on the `PATH`, as `zap`; a test program's `zapFmt` (zap fmt
# on a file, the lint's findings kept for it by a check first, 13.1.3) is answered by the zap
# running it, in its own process (`ZAP_ANSWERS`), so no zap starts for it. A test file whose header names files of the user's
# that are missing (a line `needs: a, b (why)`, as for `shots` below) is skipped with a line.
# A file's tests may use the processor for 300 s, or the limit its header gives (a line `limit: 900 s
# (why)`, for a file whose tests build and run a large program), counted in the processor time of
# the program and what it starts (a job of the system on Windows, `ulimit -t` on Linux), so a loaded
# machine does not fail it; the clock stops a hang at three times the limit; its zap is killed 300 s
# past that.
# `ZAP_RUN=times` says where each test file's time went, a line `times <file>: <ms> ms: ...`
# after its tests: loading its program, its `refuses` and `stops` blocks, checking, code, the
# lint's check again of its findings (13.1.3), running.
#
# Every file a run writes (its tests' executables and dirs, what its zaps print) is in a dir of
# its own, `build/test/<id>/`, which the run takes away when it ends, so any number of runs share
# a checkout; what it starts is given the dir (`ZAP_TEST_RUN`). What a test starts builds in the
# test's own dir (`testDir()`, given as `ZAP_BUILDS`): `zap build` writes the executable there,
# and `builtExe(stem)` names it, so two tests, or two runs, never share a build.
#
# A run keeps each pass: a test file whose tests all passed (run with others: a file named alone
# always runs) or an entry file that checked, stamped in `build/cache/passes/` with the compiler's key,
# the files the run read for it (every Zap program it starts adds each path it reads to the file
# `ZAP_READS` names: the file itself, what it imports, the runtime, what its tests read; what is
# under `build/`, which builds, runs and caches write, left out) and the
# source names of their dirs (a file added to a module changes the module). While all of those
# stand, the next run counts the pass instead of running the file; another runtime runs every file
# again, and another compiler checks every file again and builds each test file's program, which
# runs only when its executable is not the one the pass ran (its hash kept with the pass; the
# counts its run writes go beside it, so no path of the run's is in it). What a program not
# written in Zap reads is not followed: `ZAP_RUN=fresh` runs every file, keeping the new passes. A run with a name text or `--update` neither counts nor
# keeps them. The compiler's key, which every cache of its results is kept under, is the sources
# its build read (`compiler/` and the runtime and std files it imports, by their paths from the
# repository), kept beside its executable: a compiler built again from the same sources, anywhere,
# is the same compiler (14.1); one without its key beside it is known by its executable's hash.

fn testSource(names str[], ran str):
	text = "import fs\n"
	for name in names:
		text += "\ntest \"{name}\":\n\tran = \"{ran}\"\n\t_ = fs.appendFile(ran, \"{name}\\n\")\n"
	text

fn makeDir(dir str):
	for sub in ["a", "b", "c", "d"]:
		_ = fs.createDir("{dir}{sub}")
	ran = "{dir}ran.txt"
	_ = fs.writeFile("{dir}a/one.zap", testSource(["alpha one", "beta one"], ran))
	_ = fs.writeFile("{dir}b/two.zap", testSource(["alpha two"], ran))
	_ = fs.writeFile("{dir}c/entry.zap", "print(1)\n")
	_ = fs.writeFile("{dir}d/broken.zap", "print(undefinedName)\n")

# zap test with the arguments and the variables set for it, `@` in them the test's dir (made at
# the test's first run): its exit code, the tests that ran, and what it said of the kinds
fn zapTest(arguments str, vars str[] = [], zap str = zapPath()):
	dir = testDir()
	if not fs.exists("{dir}a"):
		makeDir(dir)
	_ = fs.deleteFile("{dir}ran.txt")
	tested = Process.output(
		"{zap} test --jobs 1 {arguments.replace("@", dir)}",
		vars = vars.map(.replace("@", dir))
	)
	code = tested.code
	ran = (fs.readFile("{dir}ran.txt") ?? "").trimmedEnd().lines().sorted().join(", ")
	said = tested.out
		.lines()
		.filter(
		.startsWith("==") or .startsWith("check:") or .startsWith("fmt:") or
		.startsWith("zap test:") or " unchanged since " in it or .startsWith("  skipped")
		)
	"exit {code}, ran [{ran}]\n{said.join("\n")}"

test "a dir runs its files' tests and checks, a repository's checks left out":
	print(zapTest("@a"))
	prints """
		exit 0, ran [alpha one, beta one]
		== check ==
		check: 0 entry files check
		== tests ==
		== 2 tests passed ==
		== every check passed: check, tests ==
		"""

test "ZAP_RUN=times says where a test file's time went":
	file = "{testDir()}timed.zap"
	source = """
		test "r" refuses UnknownVariable:
			print(nope)

		test "t":
			expect true
		"""
	_ = fs.writeFile(file, source)
	said = Process.output("{zapPath()} test --only tests {file}", vars = ["ZAP_RUN=times"]).out
	line = said.lines().find(.startsWith("times ")) ?? ""
	words = line.replace(file, "f").replace(",", "").replace(":", "").split(" ")
	print(words.filter(it != "ms" and i64.parse(it) == none).join(" "))
	prints "times f load expects check code lint run"

test "a text that is no path runs the tests whose name holds it":
	print(zapTest("@a @b alpha"))
	prints """
		exit 0, ran [alpha one, alpha two]
		== 2 tests passed ==
		"""

# the lines of failures and counts of one zap testing three files in turn, the second's test
# body `b` (the dir shown as d)
fn groupSays(b str):
	dir = "{testDir()}group"
	_ = fs.createDir(dir)
	_ = fs.writeFile("{dir}/a.zap", "test \"a\":\n\texpect true\n")
	_ = fs.writeFile("{dir}/b.zap", "test \"b\":\n\t{b}\n")
	_ = fs.writeFile("{dir}/c.zap", "test \"c\":\n\texpect true\n")
	said = Process.output(
		"{zapPath()} test --jobs 1 --only tests {dir}",
		vars = ["ZAP_RUN=fresh"]
	).out.lines()
	said.filter(.startsWith("FAIL") or .startsWith("== ")).map(.replace(dir, "d")).join("\n")

test "a file that ends its zap fails alone, the files after it run by another zap":
	# (brackets nested deeper than the compiler's stack: its zap crashes)
	print(groupSays("x = {"[".repeat(100_000)}{"]".repeat(100_000)}"))
	prints """
		FAIL d/b.zap: its tests ended without a summary (killed past a limit of memory or time, or crashed: exit code 3)
		== 1 of 3 tests failed ==
		== failed: tests ==
		"""

# the lines a zap testing a dir of a passing file and b.zap (named dir, its source b) said, the dir
# shown as d
fn passingAndSays(name str, b str):
	dir = "{testDir()}{name}"
	_ = fs.createDir(dir)
	_ = fs.writeFile("{dir}/a.zap", "test \"a\":\n\texpect true\n")
	_ = fs.writeFile("{dir}/b.zap", b)
	Process.output(
		"{zapPath()} test --jobs 1 --only tests {dir}",
		vars = ["ZAP_RUN=fresh"]
	).out.lines().map(.replace(dir, "d"))

test "a program that stops past its summary fails its file, every line it says then naming it":
	late = "test \"one\":\n\t_ = background((): stopsLate())\n\texpect true\n"
	late += "test \"two\":\n\texpect true\ntest \"three\":\n\texpect true\n"
	late += "fn stopsLate() i64:\n\tsleepMs(300)\n\titems i64[] = []\n\titems[5]\n"
	said = passingAndSays("late", late)
	print(said.filter(.startsWith("FAIL") or .startsWith("== ") or " zap: error" in it).join("\n"))
	prints """
		d/b.zap: zap: error[index-out-of-bounds]: index out of bounds
		FAIL d/b.zap: the program stopped after its summary (exit code 3)
		== 1 of 4 tests failed ==
		== failed: tests ==
		"""

test "a program that dies without a summary fails its file by name, the summary naming it too":
	dies = "test \"one\":\n\texpect true\n"
	dies += "test \"two\":\n\titems i64[] = []\n\texpect items[5] == 0\n"
	dies += "test \"three\":\n\texpect true\ntest \"four\":\n\texpect true\n"
	said = passingAndSays("dies", dies)
	print(
		said
			.filter(.startsWith("FAIL") or .startsWith("failed files") or .startsWith("== "))
			.join("\n")
	)
	prints """
		FAIL d/b.zap: the tests ended without a summary (exit code 3)
		failed files: d/b.zap
		== 3 of 5 tests failed ==
		== failed: tests ==
		"""

test "a file that does not lex, parse or load its imports fails, its zap going on":
	print(groupSays("print(\"never closed)"))
	prints """
		FAIL d/b.zap: the tests do not compile
		== 1 of 3 tests failed ==
		== failed: tests ==
		"""

test "a file runs its own tests":
	print(zapTest("--only tests @b/two.zap"))
	prints """
		exit 0, ran [alpha two]
		== 1 tests passed ==
		"""

test "--only check checks every entry file, a file of tests too":
	print(zapTest("--only check @"))
	prints """
		exit 1, ran []
		check: 1 of 4 entry files do not check
		== failed: check ==
		"""

test "a measured kind with nothing to measure fails when named, an unknown kind is refused":
	print(zapTest("--only shots,tests @b"))
	print(zapTest("--only nothing @b"))
	prints """
		exit 1, ran [alpha two]
		== 1 tests passed ==
		== failed: shots ==
		exit 2, ran []
		zap test: no kind of check is named nothing: build, fmt, dups, limits, check, doc, tests, tokens, size, bench, shots
		"""

test "the measures run when named, not in a plain run":
	_ = fs.createDir("{testDir()}m")
	_ = fs.writeFile("{testDir()}m/measured.zap", "# zap test --only size\nprint(1)\n")
	print(zapTest("@m"))
	prints """
		exit 0, ran []
		== check ==
		check: 1 entry files check
		== tests ==
		== 0 tests passed ==
		== every check passed: check, tests ==
		"""

test "fmt runs in the full run and when named, not in a plain run":
	print(zapTest("--full @c"))
	print(zapTest("--only fmt @c"))
	prints """
		exit 0, ran []
		== fmt ==
		fmt: every file laid out
		== check ==
		check: 1 entry files check
		== tests ==
		== 0 tests passed ==
		== every check passed: fmt, check, tests ==
		exit 0, ran []
		fmt: every file laid out
		"""

# what zap test says of the tests of a file `name`.zap in a dir of its own, its text the header
# lines and the body of a test "t"
fn headedSaid(name str, header str, body str):
	dir = "{testDir()}{name}"
	_ = fs.createDir(dir)
	_ = fs.writeFile("{dir}/{name}.zap", "{header}\n\ntest \"t\":\n{body}")
	Process.output("{zapPath()} test --jobs 1 --only tests {dir}").out

test "a test file whose header needs a file of the user's that is missing is skipped":
	said = headedSaid("game", "# needs: game/rom.bin (the player's dump)", "\tpass\n")
	print("game.zap: needs game/rom.bin, which the user supplies" in said)
	prints "true"

test "a test file's header gives its own limit":
	said = headedSaid(
		"slow",
		"# limit: 1 s (a test that must be stopped)",
		"\tn = 0\n\twhile n >= 0:\n\t\tn += 1\n"
	)
	stopped = said.lines().any("slow.zap: the tests ran past " in it and .endsWith(" were stopped"))
	print(stopped)   # (by the processor's limit, or on a loaded machine by the clock's, 3 s)
	prints "true"

test "a test that waits without using the processor is not stopped by its limit":
	said = headedSaid("waits", "# limit: 2 s (a test that waits)", "\tsleepMs(3000)\n")
	print("1 tests passed" in said)
	prints "true"

test "a module's function checked once for a group still fails each entry that imports it":
	dir = testDir()
	_ = fs.createDir("{dir}g/pairs")
	moved = "pub fn one() i64:\n\t1\n\npub fn moved() i64:\n\txs = [1, 2]\n\tys = move xs\n\txs.len + ys.len\n"
	_ = fs.writeFile("{dir}g/pairs/pairs.zap", moved)
	for name in ["a", "b"]:
		_ = fs.writeFile("{dir}g/{name}.zap", "import pairs\n\nprint(pairs.one())\n")
	said = Process.output("{zapPath()} test --jobs 1 --only check {dir}g").out
	print(said.lines().filter(.startsWith("check:")))
	prints "[\"check: 2 of 2 entry files do not check\"]"

test "what a test builds is in its own dir":
	file = "{testDir()}built.zap"
	_ = fs.writeFile(file, "print(7)\n")
	said = Process.output("{zapPath()} build {file}").out.trimmed()
	print("{said == "built {builtExe("built")}"} {builtExe("built").startsWith(testDir())}")
	print(Process.output(builtExe("built")).out.trimmed())
	prints """
		true true
		7
		"""

# a run's own dir: the test's run/ (the files under the test's dir are not the run's)
ownRun = ["ZAP_TEST_RUN=@run"]
freshRun = ["ZAP_TEST_RUN=@run", "ZAP_RUN=fresh"]

test "a pass is kept: the next run counts it while the files it read are the same":
	print(zapTest("--only tests,check @a @b @c", freshRun))
	prints """
		exit 0, ran [alpha one, alpha two, beta one]
		== check ==
		check: 1 entry files check
		== tests ==
		== 3 tests passed ==
		== every check passed: check, tests ==
		"""
	print(zapTest("--only tests,check @a @b @c", ownRun))
	prints """
		exit 0, ran []
		== check ==
		1 of 1 entry files unchanged since they checked (ZAP_RUN=fresh checks them)
		check: 1 entry files check
		== tests ==
		2 of 2 files unchanged since they passed (ZAP_RUN=fresh runs them)
		== 3 tests passed ==
		== every check passed: check, tests ==
		"""
	_ = fs.appendFile("{testDir()}b/two.zap", "\n# changed\n")
	print(zapTest("--only tests @a @b", ownRun))
	prints """
		exit 0, ran [alpha two]
		1 of 2 files unchanged since they passed (ZAP_RUN=fresh runs them)
		== 3 tests passed ==
		"""

test "a file that failed keeps no pass":
	print(zapTest("--only check @c @d", ownRun))
	print(zapTest("--only check @c @d", ownRun))
	prints """
		exit 1, ran []
		check: 1 of 2 entry files do not check
		== failed: check ==
		exit 1, ran []
		1 of 2 entry files unchanged since they checked (ZAP_RUN=fresh checks them)
		check: 1 of 2 entry files do not check
		== failed: check ==
		"""

# the repository's runtime, for a compiler kept in a test's dir
fn repositoryRuntime():
	"runtime={currentDir().replace("\\", "/")}/runtime"

# This compiler copied to dir/builds/zap, one more byte if padded, with the key of the sources a
# build of the compiler writes beside it (build.zap's keepCompilerKey): its bytes' hash, then key
fn compilerKeptIn(dir str, builds str, padded bool, key i64):
	_ = fs.createDir("{dir}{builds}")
	exe = "{dir}{builds}/zap{exeSuffix()}"
	bytes = fs.readBytes(zapPath()) ?? []
	if padded: bytes.push(0)
	_ = fs.writeBytes(exe, bytes)
	_ = fs.writeFile("{dir}{builds}/zap.sources", "{(fs.readFile(exe) ?? "").hash()}\n{key}")

# what zap test said of the tests @a and @b run by the compiler in dir/builds
fn testedBy(dir str, builds str, vars str[]):
	zap = "{dir}{builds}/zap{exeSuffix()}"
	set = vars.filter(not .startsWith("ZAP_RUN="))
	words = [repositoryRuntime()]
	words.extend(vars.filter(it.startsWith("ZAP_RUN=")).map(it["ZAP_RUN=".len..].copy()))
	set.push("ZAP_RUN={words.join(",")}")
	said = zapTest("--only tests @a @b", set, zap).lines()
	said[1..].copy()

test "a kept pass stands for a compiler of the same sources key, not past a change of compiler/":
	dir = testDir()
	compilerKeptIn(dir, "one", false, 7)
	compilerKeptIn(dir, "two", true, 7)
	compilerKeptIn(dir, "three", false, 8)
	print(testedBy(dir, "one", freshRun))
	print(testedBy(dir, "two", ownRun))
	print(testedBy(dir, "three", ownRun))
	prints """
		["== 3 tests passed =="]
		["2 of 2 files unchanged since they passed (ZAP_RUN=fresh runs them)", "== 3 tests passed =="]
		["== 3 tests passed =="]
		"""

test "two runs side by side in one checkout each write in a dir of their own":
	dir = testDir()
	makeDir(dir)
	run = env.get("ZAP_TEST_RUN") ?? ""
	env["ZAP_TEST_RUN"] = ""   # each a run of its own, as two started by hand
	runs = (0..2).map(i:
		Process.start(
			shellLine(
				withVariable(
					"ZAP_RUN",
					"fresh",
					"\"{zapPath()}\" test --jobs 2 --only tests {dir}a {dir}b > {dir}run{i}.txt 2>&1"
				)
			)
		)
	)
	env["ZAP_TEST_RUN"] = run
	for mut r in runs:
		r.wait()
	for i in 0..2:
		print((fs.readFile("{dir}run{i}.txt") ?? "").lines().filter(.startsWith("== ")))
	prints """
		["== 3 tests passed =="]
		["== 3 tests passed =="]
		"""

test "each case of a table counts as a test":
	_ = fs.createDir("{testDir()}e")
	_ = fs.writeFile(
		"{testDir()}e/cases.zap",
		"test \"cases\" for n in [1, 2, 3]:\n\texpect n < 3\n"
	)
	print(zapTest("--only tests @e"))
	prints """
		exit 1, ran []
		== 1 of 3 tests failed ==
		== failed: tests ==
		"""

mut lastDir = ""

test "a test writes its files in a dir of its own":
	dir = testDir()
	_ = fs.writeFile("{dir}note.txt", "kept")
	print("{fs.readFile("{dir}note.txt") ?? "-"} {testDir() == dir}")
	lastDir = dir
	prints "kept true"

test "the dir goes when its test ends":
	print("{fs.exists(lastDir)} {testDir() != lastDir}")
	prints "false true"

# `check` on one file sees its module's other files and its tests' bodies.

fn checked(file str, source str):
	dir = testDir()
	_ = fs.createDir("{dir}shapes")
	_ = fs.writeFile("{dir}shapes/area.zap", "pub fn area(s Square) i64:\n\ts.side * s.side\n")
	_ = fs.writeFile("{dir}shapes/{file}", source)
	Process.output("{zapPath()} test --only check {dir}shapes/{file}").out.trimmed().copy()

test "a module file sees the types of its module's other files":
	print(checked("square.zap", "pub type Square:\n\tside i64\n"))
	prints "check: 1 entry files check"

test "an error in a module file is reported at its line":
	print(
		"square.zap:5:" in checked(
			"square.zap",
			"pub type Square:\n\tside i64\n\nfn wrong() i64:\n\t\"x\"\n"
		)
	)
	prints "true"

test "the bodies of a file's tests are checked":
	dir = testDir()
	_ = fs.writeFile("{dir}onlytests.zap", "test \"t\":\n\ty str = 1\n\tprint(y)\n")
	print(
		"onlytests.zap:2:" in Process.output("{zapPath()} test --only check {dir}onlytests.zap").out
	)
	prints "true"

# A block that `refuses` an error or `stops` on one (12: a test's header or a case in its body) is
# a program of its own after the declarations of its file: it sees the file's types, functions, module bindings and
# imports (the file minus its tests goes before it), a declaration of its own hiding the file's of that name, and an unused value or
# binding in it is no error, unless that is the error it refuses. A file's blocks are checked
# together: the file's declarations once, then each block, a module of its own (its statements
# its own main), make one program that the zap running the file's tests checks in its own process,
# and each error goes to the block whose
# source its place is in. A test passes when its error is among its block's, as when the block is
# checked alone: what a check says only once the program checks (the ownership's, found on the
# lowered form) comes from a check of the program again without the blocks that said an error.
# The check goes on past an error: one file's errors hide none of another's (a generic's
# definition, a parallel body), nor one function's another's (a quantity). A block whose loading
# stops the check (it does not lex or parse, an import is missing) is told what the check said
# and the others are checked again without it, and one an error placed in none of the blocks may
# be of (in the file's declarations, a module's file, nowhere) is checked again alone. A block
# that holds a test block or a `parts` line is a file of its own instead (a file of tests, a
# program of parts), which finds std's modules only. The blocks' sources are written in the run's
# dir, never beside the test file, so a run cut short leaves nothing in the sources; a block's
# imports are found from the test file's dir. A `stops` block is checked with the others, and one that
# checks is a module of the file's test program: that program started again with the block's
# number (`ZAP_TEST_STOPS`) runs the block's statements, checked (`ZAP_RUN=memcheck`), in place
# of the tests, so the block needs no build of its own; its module bindings are given where they
# stand, never before the tests run.

test "a file's compile errors checked together after its declarations, each test told its own":
	file = "{testDir()}rejects.zap"
	source = r"""
		type Point:
			x i64

		fn shown(p Point) str:
			"{p.x}"

		test "a block sees the file's declarations, an unused binding no error" refuses AssignImmutable:
			label = shown(Point(x = 1))
			fn f(x i64):
				x = 2

		test "a block's own declaration hides the file's" refuses NoField:
			type Point:
				y i64
			print(Point(y = 1).x)

		test "an unused binding is the error a block may expect" refuses UnusedVariable:
			total = 1
			later = total + 1
			print(total)

		test "an error found once the program checks" refuses ArenaEscape:
			mut last str[] = []
			arena:
				h = (0..3).map("h{it}")
				last = h
			print(last.len)

		test "a source that does not parse" refuses UnterminatedString:
			print("never closed)

		test "a block of tests is a file of its own" refuses UnknownCompileError:
			test "t" refuses AssignImutable:
				x = 1

		test "the cases of a test are blocks of their own":
			refuses AssignImmutable:
				fn g(x i64):
					x = 3
			refuses NoField:
				print(Point(x = 1).x)

		test "a source that says no error" refuses AssignImmutable:
			print(1)
		"""
	_ = fs.writeFile(file, source)
	said = Process.output("{zapPath()} test --jobs 1 --only tests {file}").out.lines()
	print(
		said.filter(.startsWith("FAIL") or .startsWith("== ")).map(.replace(file, "f")).join("\n")
	)
	prints """
		FAIL f: the cases of a test are blocks of their own (refuses NoField, line 40)
		FAIL f: a source that says no error (refuses AssignImmutable)
		== 2 of 9 tests failed ==
		== failed: tests ==
		"""

test "a block's source is in the run's dir, its imports found from the file's":
	dir = "{testDir()}blocks"
	_ = fs.createDir("{dir}/geo")
	_ = fs.writeFile("{dir}/geo/geo.zap", "pub type Point:\n\tx i64\n")
	source = r"""
		test "a block imports from the file's dir" refuses AssignImmutable:
			import geo
			fn f(p geo.Point):
				p = geo.Point(x = 1)

		test "a stops block too" stops Failure("far 2"):
			import geo
			fail("far {geo.Point(x = 2).x}")

		test "a block that says another error" refuses NoField:
			y str = 1
			print(y)
		"""
	_ = fs.writeFile("{dir}/main.zap", source)
	said = Process.output("{zapPath()} test --jobs 1 --only tests {dir}/main.zap").out.lines()
	compiler = said.find(.trimmedStart().startsWith("the compiler said")) ?? ""
	left = (fs.list(dir) ?? []).sorted().join(", ")
	print("{said.filter(.startsWith("FAIL")).len} {dir not in compiler} {left}")
	prints "1 true geo, main.zap"

test "a file's stops blocks run in its test program, each told its own":
	file = "{testDir()}stops.zap"
	source = r"""
		xs = [1, 2]

		fn second() i64:
			xs[1]

		test "a block sees the file's declarations" stops IndexOutOfBounds:
			print(xs[second() + 5])

		test "a block's module binding is given where it stands" stops Failure("at its place"):
			fn picked() i64:
				if args.len == 0:
					fail("at its place")
				1
			limit = picked()
			fn above(n i64):
				n > limit
			print(above(1))

		test "a block that does not stop" stops Failure("never"):
			print(1)

		test "a block that does not check" stops Failure("never"):
			y str = 1
			print(y)

		test "the tests run beside them":
			expect second() == 2
		"""
	_ = fs.writeFile(file, source)
	said = Process.output("{zapPath()} test --jobs 1 --only tests {file}").out.lines()
	print(
		said.filter(.startsWith("FAIL") or .startsWith("== ")).map(.replace(file, "f")).join("\n")
	)
	prints """
		FAIL f: a block that does not check (stops Failure("never"))
		FAIL f: a block that does not stop (stops Failure("never"))
		== 2 of 5 tests failed ==
		== failed: tests ==
		"""

test "an error hides none of another file's or another function's":
	dir = testDir()
	sources = [
		("gen/gen.zap", "pub fn twice<T>(x T) T:\n\tx + x\n"),
		(
			"par/par.zap",
			"fn note(x i64) i64:\n\tprint(x)\n\tx\n\npub fn notes() i64:\n\t(0..10).parallel().map(i: note(i)).len\n"
		),
		(
			"main.zap",
			"import gen\nimport par\n\nfn wrong(x Nope):\n\tpass\n\nfn show(n u32, xs i64[]):\n\tif n < xs.len:\n\t\tprint(xs[n])\n\nshow(1, [1, 2])\nprint(gen.twice(2) + par.notes())\n"
		)
	]
	for (path, text) in sources:
		_ = fs.createDir("{dir}{fs.dirOf(path)}")
		_ = fs.writeFile("{dir}{path}", text)
	said = Process.output("{zapPath()} build {dir}main.zap").out
	for code in ["unknown-type", "needs-bound", "parallel-effect", "unsigned-quantity"]:
		print("{code} {"error[{code}]" in said}")
	prints """
		unknown-type true
		needs-bound true
		parallel-effect true
		unsigned-quantity true
		"""

# `tokens`, `size`, `bench` and `shots` measure the entry files whose header asks for them
# (`zap test --only size`, `zap test --only bench`, `zap run <entry> ... --shot x.png` lines;
# `tokens` counts the bench suites'), a name text picking the programs or cases that hold it:
# `size` a build's time, peak memory, bytes, sections and functions (compiler/zap.zap's self-build
# among them; an entry whose header has a line `writes: path (why)` is run with that path, from
# its repository's root, and the program it writes there is the one built), `bench` each case's ratio in std/compare's `benchMeasures`, Zap's program over the
# rival best at it, `tokens` those ratios of the tokens alone, so every `zap test` checks them,
# and `shots` each scripted run's pictures against the run before. `size`, `bench` and `tokens`
# keep a baseline in the repository's `baselines` folder that only gets better: a value worse than
# its line by more than the measure's margin fails and names the case, `--update` writes a better
# one (a run of `tokens` writes it itself: a count is the same every run), and a worse one only
# with a reason, `--update "why"`, written beside it; `ZAP_RUN=next` shows
# where the worst case's time or bytes go (`zap doc commands` has the options, `zap doc environment`
# the words).
#
# A bench suite is a program std/compare speaks for (`suiteRequest` reads its arguments, `benchLine`
# prints a case's measure; `zap doc compare`): it ends with 1 when a program failed or the outputs
# differ, and measures again only a program whose source, build, compiler or input changed since
# the run kept in `build/bench-cache/` (`ZAP_RUN=fresh` ignores it, `fresh=all` for the rivals' too). A C library that a program in
# another language links and the machine lacks (GMP, pidigits') is fetched once a machine, as DXC
# is (11), and given to the builds and runs through the variables gcc, cargo and Python read
# (std/compare's libraries.zap): what zap fetches is kept outside every checkout, in the
# machine's `%LOCALAPPDATA%/zap/<name>/` (`~/.cache/zap/<name>/` elsewhere; std/fs's
# `cacheDir("zap")`), unpacked from an archive and noted whole (`fetchUnpacked`, `isFetched`).
#
# `bench` measures on this machine, or on the remote one of the target `--target` names or
# arm64 in ZAP_SETUP names (the arm64 Linux machine, `linux-arm64`, by its ssh name; none when it is
# unset, and `memory=MB` there caps what a measured program may commit). For a remote target, a zap built for it from the running zap's
# sources, the runtime, std and the suite's project are synced into its `~/zap-remote/bench`, where the builds and the cache of runs stay,
# and the suite runs there under the load limits of a machine that serves others (below every
# other process, on two of its processors, within the memory of its systemd scope, killed with
# what it started past a time limit), holding the machine's lock: a second timed run waits,
# saying so. Where the processor counts (std/perf, Linux's perf_event_open), a case's measures
# also hold its instructions, cache misses and branch misses, and `time` is its cycles. `ZAP_RUN=ab=zap`
# builds Zap's programs with that zap and with this one, here, and races them there by those
# counts in a dir of its own, without the lock, so any number of A/Bs run side by side; beside
# each problem's medians, its hot functions: the instructions sampled in each in either build,
# and where their code differs. Its tests are skipped, saying so, when the machine does not
# answer.

test "a machine's copy is unpacked from its archive's dir and noted whole":
	dir = testDir()
	_ = fs.createDir("{dir}top/lib")
	_ = fs.writeFile("{dir}top/lib/a.txt", "a")
	_ = fs.writeFile("{dir}top/other.txt", "o")
	Process.output("tar -cf pack.tar top", dir = dir)
	url = "file://{"" if dir.startsWith("/") else "/"}{dir}pack.tar"
	copy = "{dir}copy"
	print("{fs.isFetched(copy)} {fs.fetchUnpacked(url, "top/lib", copy)} {fs.isFetched(copy)}")
	print("{fs.readFile("{copy}/a.txt") ?? "-"} {fs.exists("{copy}/other.txt")}")
	prints """
		false true true
		a false
		"""

# `shots` keeps the pictures under `build/shots/<entry>/`: the run saves into `run/` (a program
# that saves one picture a scene saves `<shot>.<backend>-<scene>.png` beside the shot's path, as
# lab's `--tour N --shot x.png` does), and each picture is kept as its own: `<name>.kept.png` the
# one the next run is compared with, `.diff.png` (std/image's `diff`) where a failing one differs.
# A picture is the same when at most one pixel in 1,000 differs by more than 8 in a channel;
# `--update` keeps a differing one. A header line `needs: a, b (why)` names files of the user's
# own under the repository's root (a game's assets, never committed); `shots` skips the file with
# a line while one is missing.

# `tools/golden.zap`: `zap run tools/golden.zap base.exe [files | dirs...]` builds each program
# with `base.exe` and with `build/zap.exe`, the two side by side, each into a dir of its own under
# `build/golden`, and lists those whose code differs (a file of tests alone by the hash of the
# executable its tests' run built), so a refactoring that must not change the output is checked
# against the compiler from before it (a copy of `build/zap.exe` kept aside first). With no path
# it compares the compiler itself, the largest program and the one every change of the compiler
# reaches; a dir is for a change the compiler's own code does not exercise (SIMD, the GPU).

test "golden lists the programs whose code differs":
	dir = testDir()
	for n in 1..=2:
		_ = fs.writeFile("{dir}p{n}.zap", "print({n})\n")
	print(Process.output("{zapPath()} run tools/golden.zap {zapPath()} {dir}").out.trimmed())
	prints "0 of 2 programs differ"

# A compiler copied into a dir under the repository (build/base/zap, the base side of golden.zap)
# finds runtime/ and std/ by walking up from its own dir to the first holding both.
test "a compiler kept in a subdir of the repository builds without a copy of runtime and std":
	dir = testDir()
	exe = "{dir}kept/zap{exeSuffix()}"
	_ = fs.createDir("{dir}kept")
	_ = fs.writeBytes(exe, fs.readBytes(zapPath()) ?? [])
	_ = fs.writeFile("{dir}hello.zap", "print(1)\n")
	Process.output("{exe} build {dir}hello.zap")
	expect fs.exists(builtExe("hello"))
