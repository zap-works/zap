# The code a compiler emits, against another's: each program is built with the base compiler and
# with build/zap, side by side, each into a dir of its own under build/golden, and those whose
# executables differ are listed. A file of tests alone is built by running its tests, the hash
# of its executable read from the run's dir it is given. With no path, the compiler itself is compared:
# the largest program here, and the one every change of the compiler reaches. A refactoring that
# must not change the emitted code is checked against the compiler from before it (copy
# build/zap.exe aside first).
#
#   zap run tools/golden.zap base.exe [files | dirs...]

import fs

goldenDir = "build/golden"

# a compiler's side of the comparison: its executable and the dir its builds go to
type Side:
	zap str
	dir str

# the side's dir emptied for the next file
fn cleared(side Side):
	_ = fs.deleteTree(side.dir)
	_ = fs.createDir(side.dir)

# the zap command line started in the side's dir, its output kept quiet (through the system's
# shell): its builds there, a test run's files in its run/
fn started(side Side, words str):
	_ = fs.createDir("{side.dir}/run")
	env[buildsVariable().name] = side.dir.copy()
	env["ZAP_TEST_RUN"] = "{side.dir}/run"
	line = "{side.zap} {words}"
	if exeSuffix() == ".exe":   # (cmd reads a slash as an option)
		return Process.start("cmd /c \"{side.zap.replace("/", "\\")} {words} > nul 2>&1\"")
	Process.start("sh -c '{line} > /dev/null 2>&1'")

# what the side made of the file: the program's bytes, else the hash of the executable its test
# run built (the first word of the run's .built, the executable itself deleted once run); "" when
# it made none
fn madeOf(side Side, file str):
	if fs.readFile("{side.dir}/{fs.stem(file)}{exeSuffix()}") is bytes: return bytes
	for name in fs.list("{side.dir}/run") ?? []:
		if name.endsWith(".built"):
			return (fs.readFile("{side.dir}/run/{name}") ?? "").split(" ")[0].copy()
	""

# the zap command line run by both sides at once, in dirs emptied first: their exit codes
fn ranBoth(sides Side[], words str):
	for s in sides: s.cleared()
	running = sides.map(.started(words))
	codes = []
	for i in 0..running.len:
		codes.push(running[i].wait())
	codes

# the file built by both sides at once (its tests run when it is no program): whether their
# executables are the same, and whether either side made one
fn compared(sides Side[], file str):
	if ranBoth(sides, "build {file}").any(it != 0):
		ranBoth(sides, "test --only tests --jobs 1 {file}")
	made = sides.map(.madeOf(file))
	(made[0] == made[1], made[0] != "" or made[1] != "")

# the source files the paths name: a dir's programs and test files, a file itself
fn sourcesOf(paths str[]):
	files = []
	for p in paths:
		if p.endsWith(".zap"):
			files.push(p.copy())
		else:
			for f in fs.walk(p, sources = true, programs = true): files.push(f.copy())
	files

mut a = args.copy()
if a.len < 1:
	exit(2, "usage: zap run tools/golden.zap base.exe [files | dirs...]")
sides = [
	Side(zap = a[0].copy(), dir = "{goldenDir}/base"),
	Side(zap = "build/zap{exeSuffix()}", dir = "{goldenDir}/new")
]
files = sourcesOf(a[1..].map(it.copy()) if a.len > 1 else ["compiler/zap.zap"])
mut differ = 0
mut empty = 0
for file in files:
	same, made = compared(sides, file)
	if not made:
		empty += 1
	elif not same:
		print("differs: {file}")
		differ += 1
note = "" if empty == 0 else " ({empty} built by neither)"
print("{differ} of {files.len} programs differ{note}")
exit(i32(differ.min(1)))
