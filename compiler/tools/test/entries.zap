# zap test's check (spec 13.1): every entry file under the paths checked as zap build checks it,
# without building. A few zaps check them, each a group of them in turn in one process (the
# compiler loaded once, the sources it reads read once); a file whose kept pass stands is not
# checked again (runs.zap).

import fs

# Every entry file under the paths checked; a file whose tests run is checked by running them. A
# file named alone is checked by this zap, whatever it holds (a module's file with its module, a
# program that must not check).
fn checkEntries(request TestRequest):
	if request.each != "": return checkListed(request.each)
	testsRun = "tests" in request.kinds
	alone = request.paths.len == 1 and fs.isSourceFile(request.paths[0]) and not testsRun
	files = sourceFiles(request.paths).filter(f:
		text = fs.readFile(f) ?? ""
		not isGpuFile(f) and isEntryText(text) and not (testsRun and hasTests(text))   # a GPU file's arrays are a group's memory
	)
	counts = [1, 0 if checksNoting(request.paths[0]) else 1] if alone
		else checkInGroups(files, request.jobs, not request.fresh)
	if counts[1] == 0:
		print("check: {counts[0]} entry files check")
	else:
		print("check: {counts[1]} of {counts[0]} entry files do not check")
	counts[1] == 0

# a file's check with what it reads noted (its .reads in the run's dir), which the lint's line of
# the file alone reads
fn checksNoting(file str):
	noteReadsTo(runFileOf(file, ".reads"))
	checks = checksFile(file)
	noteReadsTo("")
	checks

# zap test --only check, given its list by eachVariable: each file the list names checked in turn,
# what it reads noted apart (its .reads in the run's dir), then a line saying how it went (checkedLine). A zap that
# has spent half of what a zap may (testCpuSeconds: its checks of the lint's rewrites count) ends
# its group with groupEndsLine, the files left going to the next round's zaps.
fn checkListed(list str):
	checksShared = true   # the modules' functions checked once for the group (irx64.zap)
	for file in (fs.readFile(list) ?? "").lines():
		eprint(checkedLine(file, checksNoting(file)))
		if endsGroupWhenSpent(): break
	true

groupEndsLine = "== group ends: its processor time is spent =="

# Whether the zap has spent half of what a zap may (testCpuSeconds), saying groupEndsLine when it
# has: the one cut of the check and tests kinds' groups, which end after the file in hand.
fn endsGroupWhenSpent():
	if processorSeconds() <= testCpuSeconds / 2.0: return false
	eprint(groupEndsLine)
	true

# The together check of a list (toldTogether): the sources the list names after the test file,
# each line the code of the error its test expects and its path, checked as one program
# (loadUnits), then again without the ones that said an error, until the program checks or no
# source said one; each round's line names the sources that said one, the last line how it ended:
# checked (the sources left said none), else unclear. 0 when nothing said an error, else 1, the
# loading of a source that stops it too.
fn togetherCode(list str) i32:
	checksBefore = checksShared
	quiet = checkTogether(list)
	checksShared = checksBefore
	0 if quiet else 1

fn checkTogether(list str):
	lines = (fs.readFile(list) ?? "").lines()
	expects = lines[1..].map(.split(" ")[0].copy())
	units = lines[1..].map(it[(.indexOf(" ") ?? 0) + 1..].copy())
	checksShared = true   # the modules' functions checked once for every round (irx64.zap)
	left = (0..units.len).map(it)
	quiet = true
	irCacheOpen("{lines[0]}.together")   # (the cache of the test file's together checks)
	while not left.isEmpty:
		prog = loadUnits(
			lines[0],
			left.map(units[it].copy()),
			left.map(expects[it].copy()),
			left
		) ??
			return false
		eprint(togetherLine("check"))
		checked = prog.checkProgram()
		lowered = checked and prog.genX64("")   # (the ownership once it checks)
		quiet = quiet and lowered
		said = left.filter(units[it] in filesWithErrors)
		eprint(togetherLine("round {said.map("{it}").join(" ")}"))
		left = left.filter(it not in said)
		if checked: break
		if said.isEmpty:
			eprint(togetherLine("end unclear"))
			irCacheSave()
			return false
	eprint(togetherLine("end checked"))
	irCacheSave()
	quiet

fn checkedLine(file str, checks bool):
	"== checked {file}: {"yes" if checks else "no"} =="

# The files checked by jobs zaps at most, each a group of them in turn (checkListed): [how many,
# how many do not check]. A zap that ends before its group's last line (a check that ended the
# process) fails the file it was checking, and the files after it go to the next round's groups,
# as do those a zap that has spent half of what a zap may (groupEndsLine) leaves.
# With useKept, a file whose kept pass stands is counted, not checked; a file that checks keeps
# its pass.
fn checkInGroups(all str[], jobs i64, useKept bool):
	files = []
	kept = 0
	for f in all:
		if useKept and keptPass("check", f) != none:
			kept += 1
		else:
			files.push(f.copy())
	verdicts = fill(files.len, -1)   # 0 checks, 1 does not, -1 not checked yet
	said = fill(files.len, "")
	while verdicts.any(it < 0):
		left = (0..files.len).filter(verdicts[it] < 0)
		groups = jobs.min(left.len)
		mine = (0..groups).map(g: (0..left.len).filter(it % groups == g).map(left[it]))
		checkGroups(files, mine, verdicts, said)
	failed = 0
	for i, f in files:
		if verdicts[i] == 0:
			keepPass("check", f, runFileOf(f, ".reads"), 1)
		else:
			failed += 1
			eprint("FAIL {f}: it does not check")
			for line in said[i].trimmedEnd().lines():
				eprint("    {line}")
	if kept > 0:
		print("{kept} of {all.len} entry files unchanged since they checked (ZAP_RUN=fresh checks them)")
	[all.len, failed]

# One round: each group (indexes in files) checked by a zap of its own, all at once, a group's
# zap killed past testTimeoutMs a file; each file's verdict and what was said for it filled in
fn checkGroups(files str[], groups i64[,], mut verdicts i64[], mut said str[]):
	processes = []
	for g, group in groups:
		list = "{testRunDir()}/check-{g}.list"
		_ = fs.writeFile(list, group.map(files[it].copy()).join("\n"))
		processes.push(
			Process.start(
				shellLine(
					withVariable(
						eachVariable().name,
						list,
						"{quoteArg(exePath())} test --only check > {list}.out 2>&1"
					)
				)
			)
		)
	since = clockMs()
	while processes.any(not .isDone):
		for g, group in groups:
			if not processes[g].isDone and clockMs() - since > testTimeoutMs * group.len:
				processes[g].killTree()
		sleepMs(20)
	for g, group in groups:
		code = processes[g].wait()
		text = fs.readFile("{testRunDir()}/check-{g}.list.out") ?? ""
		at = 0   # the file of the group being checked
		lines = ""
		ends = false
		for line in text.lines():
			if line == groupEndsLine:
				ends = true
				continue
			if at < group.len and line == checkedLine(files[group[at]], true):
				verdicts[group[at]] = 0
			elif at < group.len and line == checkedLine(files[group[at]], false):
				verdicts[group[at]] = 1
			else:
				lines += "{line}\n"
				continue
			said[group[at]] = lines
			lines = ""
			at += 1
		if at < group.len and not ends:
			verdicts[group[at]] = 1
			said[group[at]] = "{lines}(its check ended the zap checking it: exit code {code})"
