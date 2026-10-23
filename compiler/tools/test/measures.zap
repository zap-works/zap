# zap test's measured kinds (spec 13.1): `size`, a program's build (its time, its
# executable's sections and functions, the compiler's peak memory), `bench`, a suite's cases (each
# of std/compare's benchMeasures, Zap's program over its rival's), and `tokens`, the suites' tokens
# alone. Each repository keeps them in a baseline that only gets better (size.baseline,
# bench.baseline); shots.zap has the other measured kind.

import compare
import fs
import perf

# ---------- the cases: what an entry file's header says ----------

# the lines of a file's header (the comment lines it opens with), without `#` and the spaces after
fn headerLines(text str):
	out = []
	for line in text.lines():
		if not line.startsWith("#"): break
		out.push(line[1..].trimmed().copy())
	out

# The paths a file's header says it needs (a line `needs: a, b (why)`), from its repository's root:
# the user's own game files, never committed. A measured kind skips the file with a line when one
# is missing.
fn neededPaths(text str):
	out = []
	for line in headerLines(text):
		if line.startsWith("needs:"):
			list = line[6..].trimmed()
			for path in (list[..list.indexOf(" (") ?? len]).split(","):
				if path.trimmed() != "":
					out.push(path.trimmed().copy())
	out

# the paths of the file's `needs:` lines that are missing under the repository's root
fn missingNeeds(root str, text str):
	neededPaths(text).filter(not fs.exists("{root}/{it}"))

# The program a size entry writes to be measured in its place, when its header has a line
# `writes: path (why)` (a path from its repository's root): the entry is run with that path as its
# argument first. Else the entry itself, as is; none when the run fails.
fn measuredEntry(file str) str?:
	for line in headerLines(fs.readFile(file) ?? ""):
		if line.startsWith("writes:"):
			path = line[7..].trimmed()
			root = repositoryOf(fullPath(file))
			written = "{"." if root == "" else root}/{path[..path.indexOf(" (") ?? len]}"
			ran = Process.output("{quoteArg(exePath())} run {quoteArg(file)} {quoteArg(written)}")
			if ran.code != 0:
				print("  {file}: does not write {written}")
				print(ran.out.trimmedEnd())
				return none
			return written
	file.copy()

# how long the file's tests may use the processor: its header's `limit: N s (why)`, else half
# the zap's limit
fn testLimitMs(text str):
	for line in headerLines(text):
		if line.startsWith("limit:"):
			seconds = line[6..].trimmed().split(" ").first ?? ""
			return (i64.parse(seconds) ?? testTimeoutMs / 2000) * 1000
	testTimeoutMs / 2

# whether the file's header needs files of the user's that are missing under its repository's
# root (the working dir outside one): then it is skipped, with a line saying so
fn skippedForNeeds(file str, text str):
	root = repositoryOf(fullPath(file))
	missing = missingNeeds("." if root == "" else root, text)
	if missing.isEmpty: return false
	print(
		"  skipped   {pathInRepository(file)}: needs {missing.join(", ")}, which the user supplies"
	)
	true

# whether a header line is `zap test ... --only <kinds>` with the kind among the kinds
fn headerNamesKind(line str, kind str):
	if not line.startsWith("zap test"): return false
	words = line.split(" ").filter(it != "")
	at = words.indexOf("--only") ?? return false
	at + 1 < words.len and kind in words[at + 1].split(",")

# The entry files under the request's paths a measured kind runs: those whose header names it
# (`zap test --only size`; tokens counts the bench suites'), a shots run in it (shotCommands); for
# size and shots only the files whose path holds the name text (a bench suite is given the text,
# its cases' names hold it)
fn measuredFiles(kind str, request TestRequest):
	suites = kind == "bench" or kind == "tokens"
	sourceFiles(request.paths).filter(f:
		text = fs.readFile(f) ?? ""
		(suites or request.name in f) and
			(
				not shotCommands(text).isEmpty if kind == "shots"
				else headerLines(text).any(headerNamesKind(it, "bench" if suites else kind))
			)
	)

# a file's path from its repository's root ('/' between parts), "" outside a repository
fn pathInRepository(file str):
	full = fullPath(file)
	root = repositoryOf(full)
	"" if root == "" else full[root.len + 1..].copy()

# The files grouped by their repository: each root and its files; a file outside a repository is
# named and left out
type RepoFiles:
	root str
	files str[]

fn byRepository(files str[]):
	groups RepoFiles[] = []
	for file in files:
		root = repositoryOf(fullPath(file))
		if root == "":
			print("{file}: not in a repository (a dir holding .git), which keeps the baseline")
			continue
		match groups.findIndex(.root == root):
			i: groups[i].files.push(file.copy())
			none: groups.push((root, [file.copy()]))
	groups

# ---------- the baselines ----------

# A measure of a run: its key in the baseline (the case and what is measured, "nbody time quick",
# "compiler/zap.zap .text"), its value, the decimals it is kept with, the margin past which it
# is worse (0.2: more than 20% above the baseline), and what its line says besides
type Measure:
	key str
	value f64
	decimals i64
	margin f64
	note str

# a line of a baseline: its key, its value as written, why a slower value was accepted ("")
type Kept:
	key str
	value f64
	text str
	reason str

slowerMark = "  # slower: "

fn valueText(value f64, decimals i64):
	str(i64(value.round())) if decimals == 0 else "{value:.2}"

# A baseline's lines: `key value`, a slower value accepted with its reason beside it
# (`key value  # slower: why`); `target 1.50` in bench.baseline
fn readBaseline(path str):
	out = []
	for raw in (fs.readFile(path) ?? "").lines():
		line = raw.trimmed()
		code = line.copy()
		reason = ""
		if line.indexOf(slowerMark) is at:
			code = line[..at].trimmed().copy()
			reason = line[at + slowerMark.len..].copy()
		words = code.split(" ").filter(it != "")
		if words.len < 2: continue
		if f64.parse(words[len - 1]) is value:
			out.push(
				Kept(
					key = words[..len - 1].join(" "),
					value,
					text = words[len - 1].copy(),
					reason
				)
			)
	out

# the baseline written: the target first, then the cases by key
fn writeBaseline(path str, kept Kept[]):
	text = ""
	ordered = kept.filter(.key == "target")
	ordered.extend(kept.filter(.key != "target").sortedBy(.key))
	for k in ordered:
		text += "{k.key} {k.text}"
		if k.reason != "":
			text += "{slowerMark}{k.reason}"
		text += "\n"
	_ = fs.createDir(fs.dirOf(path))
	_ = fs.writeFile(path, text)

# The measures against the baseline at path, a line each: worse past its margin fails; better
# (or new) is written by --update, or at once with locksBetter, and becomes the bound; worse is written only by
# `--update "why"`, the reason beside it. Whether none is worse.
fn judgeBaseline(path str, measures Measure[], request TestRequest, locksBetter bool = false):
	kept = readBaseline(path)
	passed = true
	changed = 0
	for m in measures:
		text = valueText(m.value, m.decimals)
		value = f64.parse(text) ?? m.value   # as the baseline would keep it
		note = "" if m.note == "" else ", {m.note}"
		margin = "{i64((m.margin * 100.0).round())}%"
		match kept.findIndex(.key == m.key):
			i:
				was = "baseline {kept[i].text}{note}"
				worse = value > kept[i].value * (1.0 + m.margin)
				if worse and not (request.update and request.slower != ""):
					print("  WORSE   {m.key:<32} {text:>12}  ({was}; past {margin})")
					passed = false
					continue
				better = value < kept[i].value
				state = "slower " if worse else "better " if better else "ok     "
				locks = request.update or locksBetter
				lock = "; --update locks it" if better and not locks else ""
				print("  {state} {m.key:<32} {text:>12}  ({was}{lock})")
				if worse or better and locks:
					reason = request.slower.copy() if worse else ""
					kept[i] = Kept(key = m.key.copy(), value, text, reason)
					changed += 1
			none:
				print("  new     {m.key:<32} {text:>12}  (no baseline{note})")
				if request.update:
					kept.push(Kept(key = m.key.copy(), value, text, reason = ""))
					changed += 1
	if changed > 0:
		writeBaseline(path, kept)
		print("  {changed} written to {path}")
	passed

# ---------- size ----------

# The size check: each entry file whose header says `zap test --only size` built with
# ZAP_RUN=map by this zap, measured against its repository's size.baseline. With ZAP_RUN=next, each
# one's largest functions.
fn sizeCheck(request TestRequest):
	passed = true
	for RepoFiles(root, files) in byRepository(measuredFiles("size", request)):
		measures = []
		for file in files:
			key = pathInRepository(file)
			match sizeMeasures(file, key):
				ms: measures.extend(ms)
				none: passed = false
			if request.next:
				largestFunctions(exeFileOf(fs.stem(file)), 10)
		passed = judgeBaseline("{root}/baselines/size.baseline", measures, request) and passed
	passed

# A program built and measured (the one the entry writes, measuredEntry): the build's time (20%; the median of three builds without the
# cache, a small one varies by more; one in a test of zap test), the compiler's peak, the executable, its sections and its functions (5%); none
# when it does not build
fn sizeMeasures(entry str, key str) Measure[]?:
	file = try measuredEntry(entry)
	exe = exeFileOf(fs.stem(file))
	trace = runVariable()
	before = trace.value()
	env[trace.name] = "{before ?? ""},{mapWord().name},{nocacheWord().name}"   # a cold build
	_ = fs.createDir("build/test")
	out = "build/test/size.out"
	runs = 1 if inTestRun() else 3   # (a test of zap test reads the lines, not the time)
	measured = compare.measure(quoteArg(exePath()), "build {quoteArg(file)}", "", out, runs, 0)
	env[trace.name] = before ?? ""
	image = fs.readBytes(exe) ?? []
	functions = (perf.readMap(exe) ?? []).len
	run = measured ?? return failedBuild(key, out)
	measures = [
		sizeMeasure("{key} build", run.seconds, 2, 0.2),
		sizeMeasure("{key} peak", run.peakBytes, 0, 0.05),
		sizeMeasure("{key} exe", image.len, 0, 0.05),
		sizeMeasure("{key} functions", functions, 0, 0.05)
	]
	for s in compare.sections(image):
		measures.push(sizeMeasure("{key} {s.name}", s.size, 0, 0.05))
	measures

fn failedBuild(key str, out str) Measure[]?:
	print("  {key}: does not build")
	for line in (fs.readFile(out) ?? "").trimmedEnd().lines():
		print("    {line}")
	none

fn sizeMeasure(key str, value f64, decimals i64, margin f64):
	Measure(key = key.copy(), value, decimals, margin, note = "")

# ZAP_RUN=next for size: the executable's largest functions, each one's bytes up to the next one's start
fn largestFunctions(exe str, count i64):
	fns = functionsOf(exe)
	sized = []
	for i in 1..fns.len:
		sized.push(   # start: the size
			perf.MapFunction(start = fns[i].start - fns[i - 1].start, name = fns[i - 1].name.copy())
		)
	print("  {exe}: its {count} largest functions")
	for f in sized.sortedBy(0 - .start)[..count.min(sized.len)]:
		print("    {f.start:>8}  {f.name}")

# ---------- bench ----------

# A case's measure a suite printed (its `bench` line, std/compare's suite): the case's name, the
# measure (std/compare's benchMeasures), Zap's value and its rival's, the rival, and how Zap's
# program runs (its source, its argument, its stdin's file)
type BenchCase:
	name str
	measure str
	zapValue i64
	rivalValue i64
	rival str
	source str
	arg str
	input str

# where the bench measures unless --target names another: arm64 in ZAP_SETUP's machine, an arm64 Linux
# one (linux-arm64); none for this machine (the variable unset or without a host)
fn benchTarget() str?:
	if benchHost() == "": return none
	"linux-arm64"

# The bench check: each suite (an entry file whose header says `zap test --only bench`, but one
# whose code is Windows' own off it) run on the target's machine, from its repository's root,
# at the quick sizes once, or the real sizes five times (--full);
# every case's ratios against the repository's bench.baseline, the cases whose time is above its
# target listed worst first. With ZAP_RUN=next, where the worst one's time goes.
fn benchCheck(request TestRequest):
	passed = true
	for RepoFiles(root, suites) in byRepository(measuredFiles("bench", request)):
		cases = []
		measured = []
		for suite in suites:
			if skipsOnTarget(suite, fs.readFile(suite) ?? ""): continue
			if not runSuite(root, suite, request, cases, measured):
				passed = false
		if request.ab != "": continue   # a race of two zaps: no baseline to judge
		# the numbers of a whole full run are written whatever the baseline says (a rival made faster
		# moves a ratio without Zap changing); the baseline's verdict is the run's result
		if request.full and request.name == "" and passed:
			rewriteReadme(root, measured)
		path = "{root}/baselines/bench.baseline"
		passed = judgeBaseline(path, caseMeasures(cases, request.full), request) and passed
		above = aboveTarget(path, cases.filter(.measure == "time"))
		if request.next:
			match above.first:
				c: whereTimeGoes(root, c)
				none: print("  next: no case above the target")
	passed

# The tokens check: each bench suite's tokens (`--tokens`: nothing built or run) against the
# repository's bench.baseline
fn tokensCheck(request TestRequest):
	passed = true
	for RepoFiles(root, suites) in byRepository(measuredFiles("tokens", request)):
		cases = []
		measured = []
		for suite in suites:
			passed = runSuite(root, suite, request, cases, measured, true) and passed
		path = "{root}/baselines/bench.baseline"
		# a count is the same each run: a better one is locked as it is found
		passed = judgeBaseline(path, caseMeasures(cases, request.full), request, true) and passed
	passed

# The cases' measures as bench.baseline keeps them: `case measure size` for a measure kept a size
# each (`nbody time quick`), else `case measure` (`nbody exe`); each its margin
fn caseMeasures(cases BenchCase[], full bool):
	out = []
	for c in cases:
		m = compare.benchMeasures.find(.name == c.measure) ?? continue
		ratio = c.benchRatio()
		size = " full" if full else " quick"
		out.push(
			Measure(
				key = "{c.name} {c.measure}{size if m.sized else ""}",
				value = ratio,
				decimals = 2,
				margin = m.fullMargin if full else m.quickMargin,
				note = "{c.rival}, {fromOne(ratio)} from 1.00"
			)
		)
	out

fn benchRatio(c BenchCase):
	f64(c.zapValue) / f64(c.rivalValue)

fn fromOne(ratio f64):
	"+{ratio - 1.0:.2}" if ratio >= 1.0 else "-{1.0 - ratio:.2}"

# Runs a suite (`zap run suite --runs N [--full] [name text]`, or `--tokens`) from the
# repository's root: its output printed but its `bench` lines, which are read into cases, and its
# `measured` lines (the README's numbers); whether it ended well.
fn runSuite(
	root str,
	suite str,
	request TestRequest,
	mut cases BenchCase[],
	mut measured Measured[],
	tokens bool = false
):
	_ = fs.createDir("{root}/build/test")
	out = hostPath("{root}/build/test/bench.out")
	_ = fs.deleteFile(out)   # (a run that writes none leaves no other run's)
	runs = 5 if request.full else 1
	fresh = " --fresh all" if request.freshAll else " --fresh" if request.fresh else ""
	full = (" --full" if request.full else "") + fresh
	if tokens:
		full = " --tokens"
	code = 0
	if hostRuns() or tokens:
		ab = "" if request.ab == "" else " --ab {quoteArg(request.ab)}"
		name = "" if request.name == "" else " {quoteArg(request.name)}"
		code = Process.run(
			shellLine(
				inDir(root, "{quoteArg(exePath())} run {quoteArg(pathInRepository(suite))} --runs {runs}{full}{ab}{name} > {quoteArg(out)}")
			)
		)
	else:
		# a name text goes unquoted: sh reads the line there
		name = "" if request.name == "" else " {request.name}"
		code = remoteSuite(
			root,
			pathInRepository(suite),
			"--runs {runs}{full}{name}",
			request.ab,
			out
		)
	for line in (fs.readFile(out) ?? "").lines():
		f = line.split("\t")
		if f.len >= 9 and f[0] == "bench":
			zapValue = i64.parse(f[3]) ?? 0
			rivalValue = i64.parse(f[4]) ?? 0
			if zapValue > 0 and rivalValue > 0:
				cases.push(
					BenchCase(
						name = f[1].copy(),
						measure = f[2].copy(),
						zapValue,
						rivalValue,
						rival = f[5].copy(),
						source = f[6].copy(),
						arg = f[7].copy(),
						input = f[8].trimmed().copy()
					)
				)
		elif parseMeasured(line) is m:
			measured.push(m)
		else:
			print(line.trimmedEnd())
	if code != 0:
		print("  {suite}: the suite failed (exit code {code})")
	code == 0

# The cases above the baseline's target (`target 1.50`), worst first, listed; none without one
fn aboveTarget(path str, cases BenchCase[]):
	kept = readBaseline(path)
	i = kept.findIndex(.key == "target") ?? return []
	target = kept[i].value
	above = cases.filter(.benchRatio() > target).sortedBy(0.0 - .benchRatio())
	if above.isEmpty:
		print("  no case above the target {kept[i].text}")
	else:
		print("  above the target {kept[i].text}, worst first: {above.map("{.name} {.benchRatio():.2}").join(", ")}")
	above

# ZAP_RUN=next for bench: the case's Zap program run under ZAP_RUN=profile (its hottest functions;
# on the machine that measured it),
# beside its rival's cycles
fn whereTimeGoes(root str, c BenchCase):
	print("  next: {c.name}, Zap {c.zapValue / 1e9:.3} Gcycles, {c.rival} {c.rivalValue / 1e9:.3} Gcycles")
	if not hostRuns():
		redirects = "{"" if c.input == "" else " < {c.input}"} > /dev/null"
		remoteProfile("build/zap run {c.source} {c.arg}", redirects)
		return
	input = "" if c.input == "" else " < {quoteArg(c.input)}"
	Process.run(
		shellLine(
			inDir(
				root,
				withVariable(
					runVariable().name,
					runWith("profile"),
					"{quoteArg(exePath())} run {quoteArg(c.source)} {c.arg}{input} > {nullDevice()}"
				)
			)
		)
	)
