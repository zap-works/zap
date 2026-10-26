# zap test's tests that expect an error (spec 12, 13.1): a test's header or a case in its body,
# `refuses Name` or `stops Name`. A refuses test's source must be refused with that error (and
# the part of its message the test names); a stops test's must check, then run checked
# (ZAP_RUN=memcheck, as the tests themselves) and stop on that error (exit code 3) with the text
# in its report. A file's tests whose sources can share a program (sharesProgram) are checked
# together after the file's declarations (toldTogether), by this zap (by another when a source
# reaches the GPU's compile, whose errors still stop a zap); a stops test's source
# that checked there is then a module of the file's test program, whose main the test program
# started again with the source's number runs (stopsRun): no build of its own. Every other test
# is checked, or built and run, by a zap of its own (toldAlone). The sources are written in the
# run's dir, so a run cut short leaves none beside the test file; a source checked together finds
# its imports from the test file's dir, one checked alone only std's.

import fs

# what checking or running a test's source told: the exit code and what was said
type Told:
	code i64
	said str

# the stops tests whose sources checked together, left to run in the file's test program: each
# test and its source's path, kept until it ran
type StopsLeft:
	tests Node[]
	paths str[]

# set by zap test when it starts a test program again: the number of the stops test whose source
# it runs in place of the tests
fn stopsVariable():
	InternalVariable("ZAP_TEST_STOPS")

# The tests that expect an error, each judged in their order but the stops tests left to run in
# the file's test program (left): how many failed.
fn testExpected(prog Program, file str, tests NodeId[], mut left StopsLeft):
	since = clockMs()
	told Told?[] = fill(tests.len, none)
	joined = (0..tests.len).filter(sharesProgram(prog.nodes[tests[it]].names()[0]))
	paths = []
	if not joined.isEmpty:
		paths = toldTogether(file, joined.map(prog.nodes[tests[it]].copy()), joined, told)
	failed = 0
	for i, t in tests:
		if prog.nodes[t].ival == 3 and (told[i]?.code ?? 1) == 0:
			left.tests.push(prog.nodes[t].copy())
			left.paths.push(paths[joined.findIndex(it == i) ?? 0].copy())
			continue
		said = told[i] ?? toldAlone(file, prog.nodes[t])
		if not judged(file, prog.nodes[t], said):
			failed += 1
	for path in paths:
		if path not in left.paths:
			_ = fs.deleteFile(path)
	if not tests.isEmpty:
		notePhase("expects", clockMs() - since)
	failed

# The stops tests left, each run by the file's test program at exe started again with its
# source's number, checked: how many failed. Their sources are taken away.
fn stopsRun(file str, exe str, left StopsLeft):
	since = clockMs()
	out = runFileOf(file, ".said")
	failed = 0
	for k, t in left.tests:
		set = [runAssignment("memcheck"), "{stopsVariable().name}={k}"]
		code = runWithin(runCommand(exe, set, " > {out} 2>&1"), testTimeoutMs / 2)
		if not judged(file, t, Told(code, said = fs.readFile(out) ?? "")):
			failed += 1
	left.takeAway()
	if not left.tests.isEmpty:
		notePhase("stops", clockMs() - since)
	failed

# the stops tests left failed when the file's test program was not built (why), their sources
# taken away: how many
fn stopsUnbuilt(file str, left StopsLeft, why str):
	for t in left.tests:
		judged(file, t, Told(code = 1, said = why.copy()))
	left.takeAway()
	left.tests.len

fn takeAway(left StopsLeft):
	for path in left.paths:
		_ = fs.deleteFile(path)

# Whether a test's source can share a program with the file's declarations and its other tests:
# one holding a test block or a parts line is checked alone, as a file of tests or a program of
# parts.
fn sharesProgram(source str):
	not source.lines().any(.trimmedStart().startsWith("test \"") or .startsWith("parts "))

# whether what the test was told is what it expects; else its failure said
fn judged(file str, t Node, told Told):
	runs = t.ival == 3
	if runs and onJs() and told.code == 0 and told.said.startsWith("skipped "):
		print(told.said.trimmed())   # its source reaches what the JS target does not write
		return true
	if (told.code == 3 if runs else told.code != 0) and t.text2() in told.said and
		t.names2().all(it in told.said):
		return true
	eprint("FAIL {file}: {t.text} ({t.names()[1]})")
	eprint(
		"    {"the program" if runs else "the compiler"} said (exit code {told.code}): {told.said.trimmed()}"
	)
	false

# the test's source checked, or built and run, by a zap of its own
fn toldAlone(file str, t Node):
	runs = t.ival == 3
	src = "{expectsSourceBase(file, runs)}{fs.extension(file)}"
	out = runFileOf(file, ".said")
	_ = fs.writeFile(src, t.names()[0])
	code = Process.run(
		shellLine(
			withVariable(
				runVariable().name,
				runWith("nocache"),
				"{quoteArg(exePath())}{(" build{targetOption()} " if runs else " test --only check ")}{src} > {out} 2>&1"
			)
		)
	)
	if runs and code == 0:
		exe = exeFileOf(fs.stem(src))
		# the report reads the source: it stays until here
		code = Process.run(runCommand(exe, [runAssignment("memcheck")], " > {out} 2>&1"))
		_ = fs.deleteFile(exe)
	_ = fs.deleteFile(src)
	Told(code, said = fs.readFile(out) ?? "")

# the path, without its extension, of the source a test of the file writes in the run's dir
fn expectsSourceBase(file str, runs bool):
	runFileOf(file, "-fails" if runs else "-rejected")

# ---------- the sources checked together ----------
# One check (checkTogether, in the zap running the tests) checks the test file's declarations
# and the sources after them as one program, each source a module of its own and a program alone
# (loadUnits), and says which ones said an error (togetherLine); each error line names its
# source's file. A source is told the lines of the round it said an error in, exit code 1, or,
# once a round's program checked, the lines it said and exit code 0. A source whose loading stops
# the zap (it does not lex or parse, an import is missing) is told what the zap said once it was
# named, its exit code, and the others are checked again without it. A source that said an error
# in a round that said one in no source's file (the test file's, a module's, none), and every
# source when the zap ended so or stopped past the loading, is checked again alone, told all the
# zap said.

# the tests' told filled in (each at joined's place): the sources' paths, for the caller to take
# away
fn toldTogether(file str, tests Node[], joined i64[], mut told Told?[]):
	base = expectsSourceBase(file, false)
	paths = (0..tests.len).map("{base}-{it}{fs.extension(file)}")
	for k, t in tests:
		_ = fs.writeFile(paths[k], t.names()[0])
	# each source's line of the list: the code of the error its test expects (a stops test's
	# none: "-"), its path
	lines = (0..tests.len).map(
		"{tests[it].text2()[6..tests[it].text2().len - 1] if tests[it].ival == 2 else "-"} {paths[it]}"
	)
	left = (0..tests.len).map(it)
	while left.len > 1:
		code, text = checkedTogether(file, left.map(lines[it].copy()))
		run = readTogether(text, left.map(paths[it].copy()), code)
		for p, k in left:
			if run.told[p] is one:
				told[joined[k]] = one.copy()
		if not run.stopped: break
		left = left.filter(told[joined[it]] == none)
	for k in 0..tests.len:
		if told[joined[k]] == none:
			code, text = checkedTogether(file, [lines[k].copy()])
			said = text.lines().filter(togetherWhat(it) == none).map(.copy())
			told[joined[k]] = Told(code, said = said.join("\n"))
	paths

# The exit code and the text of a together check, in this zap, of the sources of the lines after
# the file's declarations: what it says kept.
fn checkedTogether(file str, lines str[]):
	list = runFileOf(file, ".together")
	_ = fs.writeFile(list, "{file}\n{lines.join("\n")}")
	keepStderr()
	code = togetherCode(list)
	(code, takeStderr())

# what one together zap told: each source's (none: left to its own zap), and whether it stopped
# while loading a source (the sources not told are checked again)
type TogetherRun:
	told Told?[]
	stopped bool

# the together zap's text read (sources its list in order, code its exit code)
fn readTogether(text str, sources str[], code i64):
	run = TogetherRun(told = fill(sources.len, none), stopped = false)
	decided = fill(sources.len, false)   # told, or left to its own zap
	said = fill(sources.len, "")   # each source's lines in this round
	loose = false   # a line of this round said in none of the sources
	to = -1   # the source whose lines the indented ones continue, -1 none's
	stage = -1   # the source being loaded, -1 past the loading
	staged = ""   # what was said since that source was named
	for line in text.lines():
		if togetherWhat(line) is what:
			if what.startsWith("unit "):
				stage = i64.parse(what[5..]) ?? -1
				staged = ""
			elif what == "link" or what == "check":
				stage = -1
			elif what.startsWith("round"):
				for word in what[5..].trimmed().split(" "):
					if i64.parse(word) is p and p < sources.len:
						decided[p] = true
						if not loose:
							run.told[p] = Told(code = 1, said = said[p].copy())
				said = fill(sources.len, "")
				loose = false
				to = -1
			elif what == "end checked" and not loose:
				for p in 0..sources.len:
					if not decided[p]:
						run.told[p] = Told(code = 0, said = said[p].copy())
				return run
			else:
				return run   # unclear, or checked past a line said in no source
			continue
		staged += "{line}\n"
		if sources.findIndex(line.startsWith("{it}:")) is p:
			to = p
		elif not line.startsWith(" "):
			to = -1   # (an indented line shows the line of the error above it)
		if to >= 0:
			said[to] += "{line}\n"
		else:
			loose = true
	if stage >= 0:
		run.told[stage] = Told(code, said = staged.copy())
		run.stopped = true
	run

# a line of the together zap between what it says of its sources
fn togetherLine(what str):
	"== together {what} =="

# what a together zap's line says, none for a line of the program's check
fn togetherWhat(line str) str?:
	if line.startsWith("== together ") and line.endsWith(" =="): return line[12..len - 3].copy()
	none
