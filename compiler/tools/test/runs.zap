# A zap test run's own files, and the passes it keeps (spec 13.1). Every file a run writes (its
# tests' executables and dirs, what its zaps print and read) goes to a dir of the run's own, so
# any number of runs share a checkout. A file that passed check or tests keeps its pass, stamped
# (stamps.zap) with the files the zaps and the programs of its run read (ZAP_READS, the runtime's
# env.zap) and the compiler: while all of them stand, the next run counts the pass instead of
# running the file again. Each test file run keeps its peak memory beside them, by which the next
# run starts it (groups.zap).

import fs

# set by zap test for what it starts: the dir of the run's files, its processes already in the
# run's capped job
fn testRunVariable():
	InternalVariable("ZAP_TEST_RUN")

# whether a zap test started this one (for one file, or a test of zap test itself)
fn inTestRun():
	testRunVariable().value() != none

# The dir of the run's files: build/test/<id of the zap test that began the run>, made by it
# (which takes it away at its end) and handed to the processes it starts
fn testRunDir():
	if testRunVariable().value() is dir: return dir.copy()
	dir = "build/test/{processId()}"
	_ = fs.deleteTree(dir)   # a run before whose zap had the id
	_ = fs.createDir(dir)
	env[testRunVariable().name] = dir.copy()
	dir

# the run's file for a source file's artifact: its path, every separator a dash, then the ending
fn runFileOf(file str, ending str):
	"{testRunDir()}/{testSlug(file)}{ending}"

# ---------- the passes kept ----------

# a file of the run's own dir (a test of zap test's), which keeps nothing
fn ofTheRun(file str):
	fullPath(file).lower().startsWith("{fullPath(testRunDir()).lower()}/")

# where a file's pass of a kind is kept (check or tests; peak: its peak memory), by its path and
# the target
fn passFileOf(kind str, file str):
	"build/cache/passes/{kind}-{testSlug(fullPath(file))}{targetTag()}.txt"

# How many tests a file's kept pass of the kind counted (a check one), while everything it rests
# on stands; none when it does not, or when the tests run elsewhere (what they read there is not
# known here)
fn keptPass(kind str, file str):
	if not hostRuns(): return none
	kept = try keptWhileSame(fs.readFile(passFileOf(kind, file)) ?? return none)
	i64.parse(kept.split(" ")[0].trimmed())

# A test file's kept pass, while the files its run read stand, whatever compiler kept it: the
# hash of the executable it ran, how many tests the run counted, and those files. A run of an
# executable that came out the same is not made again (runTests).
type KeptRun:
	built str
	ran i64
	files str[]

fn keptRun(file str) KeptRun?:
	if not hostRuns(): return none
	text = fs.readFile(passFileOf("tests", file)) ?? return none
	words = (try keptWhileFilesSame(text)).trimmed().split(" ")
	if words.len != 3: return none
	KeptRun(built = words[1].copy(), ran = try i64.parse(words[2]), files = stampedFiles(text))

# The pass of a file kept: the tests it counted (and a tests one what the run built, KeptRun's
# built and ran), stamped with the file and what the run's processes read for it (the reads
# file), but what is under build/, which only builds, runs and caches write (a test builds what it
# reads there first). A path outside the working dir is not the checkout's and is left out. A file
# of the run's own dir (a test of zap test's) keeps none.
fn keepPass(kind str, file str, reads str, tests i64, built str = ""):
	if not hostRuns() or ofTheRun(file): return
	files = [file.copy()]
	seen = [fullPath(file).lower()]
	for f in repositoryReads(reads):
		key = fullPath(f).lower()
		if key not in seen:
			seen.push(key.copy())
			files.push(f.copy())
	_ = fs.createDir("build/cache/passes")
	_ = fs.writeFile(
		passFileOf(kind, file),
		stamped(files, "{tests}{" " if built != "" else ""}{built}")
	)

# The files of the checkout a run's reads file names (as the working dir's relative paths), but
# what is under build/: the files a kept pass rests on, and those whose lint a check says
fn repositoryReads(reads str):
	here = "{fullPath(".").lower()}/"
	made = "{fullPath("build").lower()}/"
	files = []
	seen str[] = []
	for path in (fs.readFile(reads) ?? "").lines():
		full = fullPath(path)
		key = full.lower()
		if key.startsWith(here) and not key.startsWith(made) and key not in seen:
			seen.push(key.copy())
			files.push(full[here.len..].copy())
	files

# The repository files an entry's check read: its run's reads file while the run's dir stands,
# else what its kept pass stamped
fn entryReads(file str):
	made = repositoryReads(runFileOf(file, ".reads"))
	if not made.isEmpty: return made
	stampedFiles(fs.readFile(passFileOf("check", file)) ?? "")

# ---------- the peaks kept ----------

# the most memory a test file's zap and what it started held at once in the file's last run, in
# bytes; none when it never ran
fn keptPeak(file str):
	i64.parse((fs.readFile(passFileOf("peak", file)) ?? return none).trimmed())

fn keepPeak(file str, bytes i64):
	if ofTheRun(file): return
	_ = fs.createDir("build/cache/passes")
	_ = fs.writeFile(passFileOf("peak", file), "{bytes}")
