# Where zap test runs the executables it builds (target.zap's runners): the host's here; another
# Linux's on a machine of its own, below every other process there and killed past runSeconds.
# x64's in a Docker container of linux/amd64 (debian bookworm: glibc, which the dynamic executables
# need; native, no emulation) with the working dir mounted, so the run reads the sources and writes its counts in place. arm64's on the machine
# arm64 in ZAP_SETUP names, over ssh, within the load limits of a machine that serves others
# (limited), and Android's on an emulator over adb (the device android in ZAP_SETUP names, or the first
# emulator of the target's machine: never a phone it was not told of): either keeps a copy of the
# sources the tests read (runSync), the executable goes in on ssh's stdin (adb push, as adb's
# stdin may end early), and what a test writes back (its counts) is fetched after the run. The
# ssh machine is also where the bench measures (remoteSuite, below).

import fs

fn androidWord():
	SetupWord(
		"android",
		"android=<adb serial>: the Android device of android's tests (default: an emulator)"
	)

# the image x64 Linux's executables run in
linuxImage = "--platform linux/amd64 debian:bookworm-slim"

# the variables a program reads that cross into its run
runPassed = ["ZAP_RUN"]

# adb: the SDK's (where the Android command-line tools install it), else the one on the PATH
fn adbPath():
	sdk = "{env.get("LOCALAPPDATA") ?? ""}/Android/Sdk/platform-tools/adb{host().extensionOf()}"
	quoteArg(sdk) if fs.exists(sdk) else "adb"

# the device the target's runs go to over adb: android of ZAP_SETUP, else the first emulator adb lists
# whose machine (uname -m) is the target's; "" when none answers
mut adbChosen = ""

fn adbSerial():
	if adbChosen != "": return adbChosen.copy()
	if androidWord().value() is named:
		adbChosen = named.copy()
		return adbChosen.copy()
	want = "aarch64" if onArm() else "x86_64"
	for line in Process.output("{adbPath()} devices").out.lines():
		words = line.trimmed().split("\t")
		if words.len == 2 and words[1] == "device" and words[0].startsWith("emulator-"):
			machine = Process.output("{adbPath()} -s {words[0]} shell uname -m").out.trimmed()
			if machine.endsWith(want):
				adbChosen = words[0].copy()
				return adbChosen.copy()
	""

# the remote dir that holds the copy of the working dir's sources
fn remoteTree():
	"/data/local/tmp/zap-tree" if runner() == runnerAdb else "zap-remote/tests"

# the command line that runs line on the remote machine (its stdin the line's; ssh kept alive
# while a long run prints nothing)
fn remote(line str):
	if runner() == runnerAdb: return "{adbPath()} -s {adbSerial()} shell \"{line}\""
	"ssh -o BatchMode=yes -o ServerAliveInterval=30 {benchHost()} \"{line}\""

# the machine of the target's runs, named for the line that says it cannot be reached
fn runnerName():
	if runner() == runnerAdb:
		return "no Android emulator of {targets[buildTarget].name}'s machine over adb (android in ZAP_SETUP)"
	if runner() == runnerSsh and benchHost() == "":
		return "no arm64 machine (arm64 in ZAP_SETUP names none)"
	if runner() == runnerSsh:
		return "the arm64 machine at {benchHost()} over ssh (arm64 in ZAP_SETUP)"
	"Docker (linux/amd64)"

# the machine cannot be reached: the tests are skipped
fn runnerUnavailable():
	if hostRuns(): return false
	if runner() == runnerAdb: return adbSerial() == ""
	if runner() == runnerSsh and benchHost() == "": return true
	probe = "ssh -o BatchMode=yes -o ConnectTimeout=10 {benchHost()} true" if runner() == runnerSsh
		else "docker info"
	Process.output(probe).code != 0

# The marks of code that only Windows runs: it reads the code zap builds for Windows x64, imports
# a module of Windows' own or calls a function of Windows itself
windowsOnly = [
	("disassembly(", "it reads the code built for Windows x64"),
	("import win\n", "it imports win, Windows' own functions"),
	("import gpu\n", "it imports gpu (Vulkan and a window, not on Linux yet)"),
	("import tensor\n", "it imports tensor, which runs on the GPU (not on Linux yet)"),
	("extern fn ", "it calls a function of Windows (an extern fn of kernel32)"),
	(".dll\" fn ", "it calls a function of a Windows library"),
	("extern loaded ", "it calls a function of a library loaded while it runs")
]

# the first of the marks the code holds outside its comments, why it is Windows' own
fn markIn(marks (str, str)[], text str) str?:
	code = text.lines().map(codeOf(it).copy()).join("\n")
	for (written, why) in marks:
		if written in code: return why.copy()
	none

# why code that holds one of the marks is Windows' own, or runs zap where the runs have none (a
# container, another machine); none when it runs there
fn windowsMark(text str) str?:
	if markIn(windowsOnly, text) is why: return why.copy()
	if not hostRuns() and runner() != runnerSsh and markIn([("zapPath()", "")], text) != none:
		return "it runs zap, which its runs do not have"
	none

# the text and that of each of the declarations (by name) it names, and of those they name
fn withNamed(text str, declarations {str: str}):
	out = text.copy()
	named str[] = []
	grew = true
	while grew:
		grew = false
		words = wordsOf(out)
		for name in declarations.keys():
			if name in named or name not in words: continue
			named.push(name.copy())
			out = "{out}{declarations.get(name) ?? ""}\n"
			grew = true
	out

# the identifiers of a text
fn wordsOf(text str):
	out {str: bool} = {}
	i = 0
	while i < text.len:
		if not text[i].isWordByte():
			i += 1
			continue
		word = nameAt(text, i)
		out[word.copy()] = true
		i += word.len
	out

# whether a line of a file starts a test, and whether it is the file's own code again (a test's
# body is the lines after its first that are not)
fn startsTest(line str):
	line.startsWith("test \"")

fn atTopLevel(line str):
	line != "" and line[0] != '\t' and line[0] != ' ' and line[0] != '#'

# The file's text outside its tests, and each test's (by the line it starts on)
fn testParts(text str):
	outside = ""
	tests {i64: str} = {}
	current = -1
	n = 0
	for line in text.lines():
		n += 1
		if startsTest(line):
			current = n
			tests[n] = ""
		elif atTopLevel(line):
			current = -1
		if current < 0:
			outside += "{line}\n"
		else:
			tests[current] = "{tests.get(current) ?? ""}{line}\n"
	(outside, tests)

# The system the file's header says alone runs it (a line `host: windows (why)` or `host: linux
# (why)`), the name it is called by and why, or none.
fn headerHost(text str) (str, str)?:
	for line in headerLines(text):
		for system in ["Windows", "Linux"]:
			written = "host: {system.lower()}"
			if line.startsWith(written):
				return (
					system.copy(),
					"its header says {system} runs it {line[written.len..].trimmed()}"
				)
	none

# whether a run leaves the file out: its header names the other system, or, on a Linux run, its own
# code outside its tests, or a module beside it that it imports, is Windows' (only the zap that is
# given the paths says it)
fn skipsOnTarget(file str, text str):
	outside, _ = testParts(text)
	why = ""
	if headerHost(text) is (system, said):
		if system == ("Linux" if onLinux() else "Windows"): return false
		why = said
	elif onLinux():
		why = windowsMark(outside) ?? importedMark(file, outside) ?? return false
	else:
		return false
	if not runChild:
		print("skipped {file}: {why}")
	true

# why a module beside the file that its text imports (`import x`, `from x import`) is Windows'
# own, or none
fn importedMark(file str, text str) str?:
	for line in text.lines():
		words = line.trimmed().split(" ")
		if words.len >= 2 and (words[0] == "import" or words[0] == "from"):
			dir = "{dirPrefix(file)}{words[1].replace(".", "/")}"
			for f in moduleFiles(dir):
				if windowsMark(fs.readFile("{dir}/{f}") ?? "") is why: return why.copy()
	none

# the text of each declaration of those kinds (lsp.zap's sym kinds) in a source, by name
fn declTexts(text str, kinds i64[]):
	lines = text.replace("\r", "").lines()
	out {str: str} = {}
	for d in scanDecls(text):
		if d.kind in kinds:
			out[d.name.copy()] = lines[d.line..(d.endLine + 1).min(len)].join("\n")
	out

# the lines the file's tests that are Windows' own start on (their text, or that of a declaration
# of the file they name, or of those it names, holds a mark), each said to be skipped
fn skippedTests(file str):
	if not onLinux(): return []
	text = fs.readFile(file) ?? ""
	if headerHost(text) is (system, _) and system == "Linux": return []   # (all its tests are Linux's)
	_, tests = testParts(text)
	declarations = declTexts(text, [symFunction, symConstant, symVariable])
	lines = []
	for at in tests.keys().sorted():
		body = tests.get(at) ?? ""
		if windowsMark(withNamed(body, declarations)) is why:
			print("skipped {file}:{at}: {why}")
			lines.push(at)
	lines

# a run killed past this many seconds
runSeconds = 120

# the files run at once: two on a remote machine, as it serves others
fn runJobs(jobs i64):
	jobs if hostRuns() or runner() == runnerDocker else jobs.min(2)

# the exit code of a process the system killed past its processor time (ulimit -S -t: a soft limit,
# for a hard one kills with SIGKILL, 137): 128 and SIGXCPU
cpuKilledCode = 152

# The command line that runs the executable exe (a path under the working dir) with the variables
# of runPassed and those `set` gives ("NAME=value" words, in place of runPassed's of that name),
# its exit code the program's, what it writes redirected as `tail` says (" > out 2>&1", or ""). With
# cpuSeconds, a Linux host stops each of its processes past that much processor time (ulimit -S -t,
# which the exit code cpuKilledCode tells); Windows counts it in the job runWithin puts it in.
fn runCommand(exe str, set str[], tail str, cpuSeconds i64 = 0):
	passed = runPassed.filter(n: env.get(n) != none and not set.any(.startsWith("{n}=")))
	vars = passed.map("{it}={env[it]}")
	vars.extend(set.copy())
	if hostRuns():
		local = exe if onWindows() or exe.startsWith("/") or exe.startsWith("./") else "./{exe}"
		capped = cpuSeconds > 0 and not onWindows()
		if vars.isEmpty and tail == "" and not capped: return quoteArg(hostPath(local))
		cap = "ulimit -S -t {cpuSeconds} && " if capped else ""
		return shellLine("{cap}{withVariables(vars, "{quoteArg(hostPath(local))}{tail}")}")
	if runner() == runnerDocker:
		mount = currentDir().replace("\\", "/")
		run = "timeout -s KILL {runSeconds} ./{exe}"
		return shellLine("docker run --rm -v {mount}:/zap -w /zap {vars.map("-e {it} ").join("")}{linuxImage} {run}{tail}")
	assigned = passed.map("{it}='{env[it]}' ").join("") + set.map("{it} ").join("")
	start = "{assigned}exec {limited("./{exe}", runSeconds)}"
	if runner() == runnerAdb:
		start = "{assigned}exec nice -n 19 timeout -s KILL {runSeconds} ./{exe}"
		made = remote("mkdir -p {remoteTree()}/{fs.dirOf(exe)}")
		push = "{made} && {adbPath()} -s {adbSerial()} push {hostPath(exe)} {remoteTree()}/{exe} > {nullDevice()} 2>&1"
		return shellLine(
			"{push} && {remote("cd {remoteTree()} && chmod +x {exe} && {start}")}{tail}"
		)
	run = "mkdir -p {remoteTree()}/{fs.dirOf(exe)} && cd {remoteTree()} && cat > {exe} && chmod +x {exe} && {start}"
	shellLine("{remote(run)} < {hostPath(exe)}{tail}")

# the files a run wrote that zap reads after it, fetched from the remote machine (a container
# writes them in place)
fn runFetch(path str):
	if not hostRuns() and runner() != runnerDocker:
		Process.run(
			shellLine("{remote("cat {remoteTree()}/{path}")} > {hostPath(path)} 2> {nullDevice()}")
		)

# whether this zap made the remote machine's copy (and takes it away at the end), and whether a
# zap test started it for one file of its run (which made the copy, and says what it skips)
mut runSynced = false
mut runChild = false

# The remote machine's copy of the sources the tests read, and of the user's files their headers
# need (`needed`, those present here), made by the zap the run starts with when it runs tests,
# and the dir for their executables (a container mounts the working dir instead); the ssh
# machine's has a zap built for it (build/zap), which the tests that run zap start
fn runSync(child bool, tests bool, needed str[]):
	runChild = child
	if child or not tests or hostRuns() or runner() == runnerDocker: return
	runSynced = true
	paths = ["tests", "spec", "std", "runtime"]
	paths.extend(needed.copy())
	parts = paths.filter(fs.exists(it)).map(quoteArg(it)).join(" ")
	tree = remoteTree()
	unpack = "rm -rf {tree} && mkdir -p {tree}/build/test && tar -xmf - -C {tree}"
	if runner() == runnerAdb:
		_ = fs.createDir("build")
		Process.output("tar -cf build/sources.tar {parts}")
		pushed = "/data/local/tmp/zap-sources.tar"
		Process.output("{adbPath()} -s {adbSerial()} push build/sources.tar {pushed}")
		Process.output(remote(unpack.replace("tar -xmf -", "tar -xmf {pushed}")))
		_ = fs.deleteFile("build/sources.tar")
		return
	built = zapForMachine() ?? ""
	if built == "":
		print("zap test: this zap's sources do not build for {targets[buildTarget].name}: the tests that run zap fail")
	else:
		parts = "{parts} -C {quoteArg(built)} build/zap"
		unpack = "{unpack} && chmod +x {tree}/build/zap"
	Process.run(shellLine("tar -cf - {parts} | {remote(unpack)}"))

# the copy taken away at the end of the run that made it
fn runCleanUp():
	if runSynced:
		Process.output(remote("rm -rf {remoteTree()} /data/local/tmp/zap-sources.tar"))

# ---------- the bench on the ssh machine ----------

# What a run on the ssh machine may use of it, as it serves others: two of its processors and
# this memory (the limit of the run's systemd scope)
remoteCores = "2,3"
remoteMemory = "6G"

# The line run on the ssh machine within its load limits: below every other process, on
# remoteCores, within remoteMemory, killed past seconds with every process it started (timeout
# signals its process group)
fn limited(line str, seconds i64):
	"systemd-run --user --scope --quiet -p MemoryMax={remoteMemory} nice -n 19 taskset -c {remoteCores} timeout -s KILL {seconds} {line}"

# The bench's dirs there: the timed suite's (the sources and a zap built for the machine copied
# in; its builds and its cache of runs kept from run to run) and its lock, which a timed run holds
# and a second one waits for; a run's own (runDir: its files, its script, what it prints), taken
# away at its end, where an A/B races (counted, side by side with others)
benchTree = "zap-remote/bench"
benchLock = "zap-remote/timed.lock"

fn runDir():
	"zap-remote/runs/{processId()}"

# a tar of this machine's unpacked there, the files' times kept (a measured input's time is in
# the cache's keys) though its clock may be behind this one
untar = "tar --warning=no-timestamp -xf -"

# a suite's run there killed past this many seconds
benchSeconds = 14_400

# the seconds between two looks at a detached run
followSeconds = 15

# a line run in a tree there, its zap and Rust's tools first on the PATH
fn inTree(tree str, line str):
	"cd {tree} && PATH=$PWD/build:$HOME/.cargo/bin:$PATH {line}"

# the dir of a suite's project, from its repository's root: its path's first two dirs
# (tests/benchmarks, projects/lab), or the root (".") for a suite there; it is synced with it
fn projectDir(suite str):
	dirs = fs.dirOf(suite).split("/").filter(it != "")
	"." if dirs.isEmpty else dirs[..len.min(2)].join("/")

# what a tar of a project leaves out: the builds and the history (the root's)
tarExcludes = "--exclude ./build --exclude ./.git"

# a zap built for the target's machine from this zap's sources, the dir whose build/zap it is
# (under the zap repository's build/); none when they do not build
fn zapForMachine() str?:
	dir = "{zapRoot()}build/{targets[buildTarget].name}"
	if not buildCompiler(zapRoot()[..zapRoot().len - 1], exePath(), targets[buildTarget], dir):
		return none
	dir

# Runs a bench suite (its path in the repository at root and its arguments) on the ssh machine,
# what it prints written to out: a timed run builds a zap for the machine from this zap's
# sources and, holding the lock, copies it with them into benchTree and runs the suite there; an
# A/B (ab, the base zap) is raced by remoteAb. Its exit code.
fn remoteSuite(root str, suite str, arguments str, ab str, out str):
	if runner() != runnerSsh:
		print("bench: measured here or on the ssh machine (linux-arm64), not on {targets[buildTarget].name}")
		return 1
	if ab != "": return remoteAb(root, suite, arguments, ab, out)
	zapRepo = zapRoot()[..zapRoot().len - 1]
	zapDir = zapForMachine() ?? ""
	if zapDir == "":
		print("bench: this zap's sources do not build for {targets[buildTarget].name}")
		return 1
	dir = projectDir(suite)
	parts = "-C {quoteArg(zapRepo)} runtime std -C {quoteArg(root)} {tarExcludes} {dir} -C {quoteArg(zapDir)} build/zap"
	# copied in under the lock, as the run before may still read the tree
	gone = "" if dir == "." else dir
	copy = "mkdir -p {benchTree} && cd {benchTree} && rm -rf runtime std {gone} && cp -a $HOME/{runDir()}/files/. . && chmod +x build/zap && cd"
	run = inTree(benchTree, limited("build/zap run {suite} {arguments}", benchSeconds))
	script = """
		cd
		mkdir -p zap-remote
		flock -n {benchLock} true || echo "zap test: waiting for the timed run that holds the lock on {benchHost()}"
		flock {benchLock} sh -c '{copy} && {run}'
		"""
	detachedRun(parts, script, out)

# An A/B on the ssh machine: the two zaps' builds of each program and the suite itself built here
# for it (the suite's --ab-for), synced with the suite's project into a run's own dir and raced
# there (--ab-built)
fn remoteAb(root str, suite str, arguments str, ab str, out str):
	target = targets[buildTarget].name
	zap = quoteArg(exePath())
	# (built under root's build/, whatever dir a test gives its builds)
	builds = withVariable(
		"ZAP_BUILDS",
		"build",
		"{zap} run {suite} {arguments} --ab {quoteArg(ab)} --ab-for {target}"
	)
	suiteBuild = withVariable(
		"ZAP_BUILDS",
		"build",
		"{zap} build --target {target} {suite} > {nullDevice()}"
	)
	stem = fs.stem(suite)
	if Process.run(shellLine(inDir(root, builds))) != 0 or
		Process.run(shellLine(inDir(root, suiteBuild))) != 0:
		print("bench: the A/B's programs or its suite do not build for {target}")
		return 1
	parts = "-C {quoteArg(root)} {tarExcludes} {projectDir(suite)} -C {quoteArg(root)} build/benchmarks/ab build/{stem}"
	race = limited("build/{stem} {arguments} --ab base --ab-built", benchSeconds)
	script = """
		chmod +x files/build/{stem} files/build/benchmarks/ab/*
		{inTree("files", race)}
		"""
	code = detachedRun(parts, script, out)
	_ = fs.deleteTree("{root}/build/benchmarks/ab")
	code

# Runs a script on the ssh machine apart from this connection, which may drop while a long run
# goes on: the tar of parts unpacked into runDir()/files, the script started there by setsid
# (in runDir()), what it prints fetched every followSeconds into out (a line that says it waits
# shown as it comes), the dir taken away at its end. Its exit code.
fn detachedRun(parts str, script str, out str):
	dir = runDir()
	local = "{fs.dirOf(out.replace("\\", "/"))}/run.sh"
	_ = fs.writeFile(local, script)
	unpack = "rm -rf {dir} && mkdir -p {dir}/files && cd {dir}/files && {untar}"
	start = "cd {dir} && cat > run.sh && (setsid sh -c 'sh run.sh > out 2>&1; echo $? > code' < /dev/null > /dev/null 2>&1 &)"
	if Process.run(shellLine("tar -cf - {parts} | {remote(unpack)}")) != 0 or
		Process.run(shellLine("{remote(start)} < {quoteArg(hostPath(local))}")) != 0:
		print("bench: the run could not be started on {benchHost()}")
		Process.output(remote("rm -rf {dir}"))
		return 1
	_ = fs.writeFile(out, "")
	got = 0
	while true:
		sleepMs(followSeconds * 1000)
		looked = Process.output(
			remote("cat {dir}/code 2>/dev/null; echo :; tail -c +{got + 1} {dir}/out")
		)
		if looked.code != 0: continue   # (the connection dropped: the run goes on)
		at = looked.out.indexOf(":\n") ?? continue
		fresh = looked.out[at + 2..]
		_ = fs.appendFile(out, fresh)
		got += fresh.len
		for line in fresh.lines():
			if line.startsWith("zap test: waiting"):
				eprint(line)
		if i64.parse(looked.out[..at].trimmed()) is code:
			Process.output(remote("rm -rf {dir}"))
			return code

# next (ZAP_RUN) on the ssh machine: the line (`zap run` of a program) run in benchTree under
# ZAP_RUN=profile within the load limits, its stdin and stdout redirected; its exit code
fn remoteProfile(line str, redirects str):
	traced = "ZAP_RUN=profile {limited(line, benchSeconds)}{redirects}"
	Process.run(shellLine(remote(inTree(benchTree, traced))))
