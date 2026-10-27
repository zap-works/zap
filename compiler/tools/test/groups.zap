# zap test's tests kind over many files (spec 13.1): a few zaps run them, each its group of them
# in turn (testListed): the compiler loaded once a zap, each file's program built and run, its
# output kept apart. A zap is handed its next file when it ended the one before, the slowest of
# the run before first (build/test/times.txt), so none ends long after the others. A zap that
# ends before its file did (killed past a limit, crashed) fails that file, and another zap takes
# its place. A file starts only while the peaks of the files running and its own fit in the memory
# free (fitsBeside): its peak from its run before (runs.zap), the memory each zap and what it
# started hold sampled while it runs.

import fs

# One group's zap (zap test --only tests, given its list by eachVariable): each file the list names tested in turn,
# what it and the programs it starts read noted apart (its .reads in the run's dir), then the
# line saying how it went (testedLine); the list grows while the zap runs, and ends with
# listEnd, or when the zap has spent half its processor time (endsGroupWhenSpent), the files left
# going to other zaps.
fn testListed(list str, name str, update bool, useKept bool):
	done = 0
	while true:
		text = fs.readFile(list) ?? ""
		files = text[..i64(text.lastIndexOf("\n") ?? 0)].lines().filter(it != "")   # (whole lines only)
		if done >= files.len:   # (none read while the list is written)
			sleepMs(10)
			continue
		file = files[done]
		if file == listEnd: return
		reads = runFileOf(file, ".reads")
		noteReadsTo(reads)
		env[pathsReadVariable().name] = reads.copy()
		began = clockMs()
		testPhases.clear()
		counts = testFile(file, name, update, useKept)
		noteReadsTo("")
		eprint(testedLine(file, counts, clockMs() - began))   # (stdout flushed before it)
		done += 1
		if endsGroupWhenSpent(): return

listEnd = "== end =="

# the line after a file's output in its group's: how many tests, how many failed, milliseconds
fn testedLine(file str, counts i64[], ms i64):
	"== tested {file}: {counts[0]} {counts[1]} {ms} =="

# a group's zap running: its list, its files so far (indexes in the run's), how many of them
# ended, and when it was handed its last one
type TestGroup:
	list str
	process Process
	files i64[]
	ended i64
	since i64
	closed bool   # listEnd written
	limit i64 = 0   # the milliseconds its file may take (its tests' limit and the build's)
	held i64 = 0   # the memory it and what it started hold, at the last look
	peak i64 = 0   # the most of it since it was handed its last file
	stopped i64 = 0   # when its zap was told to stop past its limit, 0 before
	abandoned bool = false   # its zap did not end after it was stopped: counted done

# what the run knows of each file: whether it ended (or failed with its group's zap), how many
# tests it ran, how many failed, its milliseconds, the most memory its zap held while it ran
type TestedFiles:
	ended bool[]
	tests i64[]
	failed i64[]
	took i64[]
	peaks i64[]

# Every test file run, jobs zaps at once, `zap <command><tail>` for the list of each (eachVariable): [how many tests,
# how many failed]. With keeps, a file that passes keeps its pass (runs.zap), and, with useKept
# too, a file whose kept pass stands is counted, not run.
fn testInGroups(
	all str[],
	jobs i64,
	command str,
	tail str,
	keeps bool,
	useKept bool
):
	counts = [0, 0]
	files = []
	for f in all:
		if keeps and useKept and keptPass("tests", f) is tests:
			counts[0] += tests
		else:
			files.push(f.copy())
	n = files.len
	run = TestedFiles(
		ended = fill(n, false),
		tests = zeros(n),
		failed = zeros(n),
		took = zeros(n),
		peaks = zeros(n)
	)
	runGroups(files, slowestFirst(files), jobs.min(n), command, tail, run)
	for i, f in files:
		keepPeak(f, run.peaks[i])
		if keeps and run.failed[i] == 0:
			built = (fs.readFile(runFileOf(f, ".built")) ?? "").trimmed()
			keepPass("tests", f, runFileOf(f, ".reads"), run.tests[i], built)
		counts[0] += run.tests[i]
		counts[1] += run.failed[i]
		if run.failed[i] > 0:
			failedTestFiles.push(f.copy())
	if all.len > n:
		print(
			"{all.len - n} of {all.len} files unchanged since they passed (ZAP_RUN=fresh runs them)"
		)
	if n > 1:
		order = (0..n).sortedBy(-run.took[it])
		_ = fs.writeFile(testTimes, order.map("{run.took[it]} {files[it]}").join("\n"))
		print(
			"slowest: {order[..5.min(n)].map("{files[it]} {(run.took[it] + 500) / 1000} s").join(", ")}"
		)
	counts

# each file's milliseconds in the run before, the slowest first
testTimes = "build/test/times.txt"

# the files' indexes, the slowest in the run before first; a file it did not run before them all
fn slowestFirst(files str[]):
	took {str: i64} = {}
	for line in (fs.readFile(testTimes) ?? "").lines():
		at = line.indexOf(" ") ?? continue
		took[line[at + 1..].copy()] = i64.parse(line[..at]) ?? 0
	(0..files.len).sortedBy(-(took.get(files[it]) ?? 1 << 60))

# The files run by zaps zaps at a time, each handed the first of order that fits (nextFitting)
# when it ended its file (a zap that spent half its processor time ends its group cleanly, the next
# zap taking the files left); a zap killed when its file runs past its wall limit (testWallMs, and the
# build's), and one that ends before its file did fails that file, another zap taking its place.
# Each file that ended shown and told in run.
fn runGroups(files str[], order i64[], zaps i64, command str, tail str, mut run TestedFiles):
	running TestGroup[] = []
	waiting = order.copy()
	peaks = files.map(keptPeak(it) ?? testJobMb * 1_048_576)
	started = 0
	looked = 0
	said = WaitSaid(key = "", at = 0)
	while run.ended.any(not it):
		if clockMs() - looked >= 100:
			running.lookAtMemory()
			looked = clockMs()
		free = freeMemory()
		blocked = false
		for k in 0..running.len:
			running[k].readEnded(files, run)
			if running[k].isGone():
				running[k].endedEarly(files, run, waiting)
			elif running[k].ended == running[k].files.len:
				if nextFitting(waiting, peaks, running, k, free) is j:
					running[k].hand(waiting.remove(j), files)
				elif waiting.isEmpty and not running[k].closed:
					_ = fs.appendFile(running[k].list, "{listEnd}\n")
					running[k].closed = true
				else:
					blocked = not waiting.isEmpty
			elif clockMs() - running[k].since > running[k].limit:
				running[k].stopPastLimit(files, run)
		running = running.filter(not .isGone())
		while running.len < zaps:
			j = nextFitting(waiting, peaks, running, -1, free) ?? break
			list = "{testRunDir()}/tests-{processId()}-{started}.list"   # (a test may start a zap test)
			_ = fs.writeFile(list, "")
			line = withVariable(
				eachVariable().name,
				list,
				"{quoteArg(exePath())} {command}{tail} > {list}.out 2>&1"
			)
			group = TestGroup(
				list,
				process = Process.start(shellLine(line)),
				files = [],
				ended = 0,
				since = 0,
				closed = false
			)
			group.hand(waiting.remove(j), files)
			running.push(group)
			started += 1
		if blocked or (running.len < zaps and not waiting.isEmpty):
			said.sayWaiting(files, peaks, waiting, running, free)
		sleepMs(20)
	for k in 0..running.len:
		if not running[k].closed:
			_ = fs.appendFile(running[k].list, "{listEnd}\n")
		if running[k].process.waitWithin(stopWaitMs) == none:
			eprint("tests: a zap did not end {stopWaitMs / 1000} s after its files ended: stopping it")
			running[k].process.killTree()

# Whether a file whose peak memory is own may start beside the files running, their peaks
# running: when none runs, whatever its peak, or when their peaks and its own fit in the memory
# free (free counting what the run's zaps hold now, which their peaks hold)
fn fitsBeside(own i64, running i64[], free i64):
	running.isEmpty or running.sum() + own <= free

# Whether a group's zap holds memory for a file: it runs, and has a file handed that it has not
# ended. A zap that ended (zapEnded), or one given up on, holds none, whatever it was handed.
fn holdsMemory(zapEnded bool, ended i64, handed i64):
	not zapEnded and ended < handed

# The index in waiting of the first file whose peak (of peaks, by file) fits beside the peaks
# running (fitsBeside); none when none fits.
fn firstFitting(waiting i64[], peaks i64[], running i64[], free i64):
	waiting.findIndex(fitsBeside(peaks[it], running, free))

# The index in waiting of the first file that fits beside the files the groups run, for group k
# to run it (-1: a zap to start); none when none fits. What the groups holding memory for a file
# and group k hold now counts as free.
fn nextFitting(waiting i64[], peaks i64[], groups TestGroup[], k i64, free i64):
	busy = groups.filter(.runsFile())
	held = busy.map(.held).sum() + (groups[k].held if k >= 0 else 0)
	firstFitting(waiting, peaks, busy.map(peaks[.files[.ended]].max(.peak)), free + held)

fn runsFile(group TestGroup):
	holdsMemory(group.isGone(), group.ended, group.files.len)

# whether the group's zap ended, or was given up on after it was stopped
fn isGone(group TestGroup):
	group.abandoned or group.process.isDone

# What the wait for memory last said: it says again when what it waits for changes, or after a
# minute.
type WaitSaid:
	key str
	at i64

# The line saying what the wait is for: the file next to start with its peak, the memory free,
# and the files running with theirs (in MB).
fn waitingLine(file str, own i64, free i64, running str[], needs i64[]):
	beside = (0..running.len).map("{running[it]} {needs[it] / 1_048_576} MB").join(", ")
	if running.isEmpty:
		beside = "no file running"
	"tests: waiting to start {file} ({own / 1_048_576} MB; {free / 1_048_576} MB free; {beside})"

# the wait for memory said, when it is new
fn sayWaiting(
	mut said WaitSaid,
	files str[],
	peaks i64[],
	waiting i64[],
	groups TestGroup[],
	free i64
):
	if waiting.isEmpty: return
	busy = groups.filter(.runsFile())
	names = busy.map(files[.files[.ended]].copy())
	key = "{files[waiting[0]]} {names.join(" ")}"
	if key == said.key and clockMs() - said.at < 60_000: return
	said.key = key
	said.at = clockMs()
	needs = busy.map(peaks[.files[.ended]].max(.peak))
	eprint(waitingLine(files[waiting[0]], peaks[waiting[0]], free, names, needs))

# the memory each group's zap and what it started hold now, and the most since its last file
fn lookAtMemory(mut groups TestGroup[]):
	held = treeMemories(groups.map(GetProcessId(.process.handle)))
	for k, mut group in groups:
		group.held = held[k]
		group.peak = group.peak.max(held[k])

# the group handed file i (of files) to test next
fn hand(mut group TestGroup, i i64, files str[]):
	file = files[i]
	group.files.push(i)
	group.since = clockMs()
	group.peak = group.held
	group.limit = testWallMs(testLimitMs(fs.readFile(file) ?? "")) + testTimeoutMs / 2
	_ = fs.appendFile(group.list, "{file}\n")

# the group's zap ended: when it said groupEndsLine, the file handed after it goes back to waiting;
# else the file it was running, if any, failed with what it said
fn endedEarly(
	mut group TestGroup,
	files str[],
	mut run TestedFiles,
	mut waiting i64[]
):
	# a zap given up on did not end when stopped: waiting for it would hang the run
	code = -1 if group.abandoned else group.process.wait()
	group.readEnded(files, run)
	spent = (fs.readFile("{group.list}.out") ?? "").lines().any(it == groupEndsLine)
	while spent and group.ended < group.files.len:
		waiting.push(group.files.pop() ?? break)
	group.failPending(
		files,
		run,
		"its tests ended without a summary (killed past a limit of memory or time, or crashed: exit code {code})"
	)

# the file the group was running, if any, failed with why and what its zap said
fn failPending(mut group TestGroup, files str[], mut run TestedFiles, why str):
	group.readEnded(files, run)   # (what it wrote before it ended)
	if group.ended < group.files.len:
		showLines(group.leftOver())
		i = group.files[group.ended]
		eprint("FAIL {files[i]}: {why}")
		run.tell(i, [1, 1, 0], group.peak)
		group.ended = group.files.len

# The group's file ran past its limit: its zap is stopped with what it started, and if it is
# still there stopWaitMs later, given up on (counted done, its file failed) so the run goes on.
fn stopPastLimit(mut group TestGroup, files str[], mut run TestedFiles):
	i = group.files[group.ended]
	if group.stopped == 0:
		eprint("tests: {files[i]} ran past {group.limit / 1000} s: stopping its zap")
		group.stopped = clockMs()
		group.process.killTree()
	elif clockMs() - group.stopped > stopWaitMs:
		eprint("tests: the zap of {files[i]} did not end {stopWaitMs / 1000} s after it was stopped, given up on")
		group.abandoned = true
		group.failPending(
			files,
			run,
			"its tests ran past {group.limit / 1000} s and their zap did not end when stopped"
		)

# how long a zap stopped past its limit has to end
stopWaitMs = 60_000

# the files of the group that ended since the last look shown, and told in run
fn readEnded(mut group TestGroup, files str[], mut run TestedFiles):
	text = fs.readFile("{group.list}.out") ?? ""
	at = 0   # the group's file whose output the lines are
	lines = ""
	for line in text.lines():
		if at < group.files.len and testedOf(line, files[group.files[at]]) is told:
			i = group.files[at]
			if at >= group.ended:
				run.tell(i, told, group.peak)
				showLines(lines)
				group.ended = at + 1
			lines = ""
			at += 1
		else:
			lines += "{line}\n"

# file i ended: [how many tests, how many failed, milliseconds], and its zap's peak memory
fn tell(mut run TestedFiles, i i64, told i64[], peak i64):
	run.ended[i] = true
	run.peaks[i] = peak
	run.tests[i] = told[0]
	run.failed[i] = told[1]
	run.took[i] = told[2]

fn showLines(lines str):
	if lines.trimmedEnd() != "":
		print(lines.trimmedEnd())

# what the group's zap said after its last file that ended
fn leftOver(group TestGroup):
	text = fs.readFile("{group.list}.out") ?? ""
	at = 0
	lines = ""
	for line in text.lines():
		if line.startsWith("== tested ") and at < group.ended:
			at += 1
			lines = ""
		else:
			lines += "{line}\n"
	lines

# [how many tests, how many failed, milliseconds] the line tells of the file, none when it is not
# the file's testedLine
fn testedOf(line str, file str) i64[]?:
	head = "== tested {file}: "
	if not line.startsWith(head) or not line.endsWith(" =="): return none
	words = line[head.len..len - 3].split(" ")
	if words.len != 3: return none
	[
		try i64.parse(words[0]),
		try i64.parse(words[1]),
		try i64.parse(words[2])
	]
