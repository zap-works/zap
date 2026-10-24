# Programs that must agree: the same program written in several languages, compared by what
# they print and raced for time and memory. Two readers:
#   - p.agree(input): every program of the problem prints the same bytes at its small size (the
#     other languages' programs are the oracle of a compiler), the test of a benchmark file;
#   - suite(problems, inputFor, args): a bench suite of `zap test --only bench` (spec 13.1),
#     `[--full] [--fresh] [--runs N] [name text]`: each program built with its compiler's fastest flags for
#     this processor, started directly (no shell in between), its stdout written to a file (on
#     Windows at high priority); the median wall time and processor cycles over the runs (1 by
#     default), and on Linux the processor's counts (std/perf: instructions, cache and branch
#     misses), the peak working set; the sources' lines and decisions against the fewest of the other
#     languages'. The quick sizes unless --full. A table for whoever reads, and `bench` lines
#     for zap test, which keeps the ratios of benchMeasures in bench.baseline; `--tokens` prints
#     only the tokens' lines, building and running nothing.
# A program is a source path: .zap built by the zap on the PATH (zap test puts itself first), .c
# and .cpp by gcc and g++ (WinLibs on Windows, the system's on Linux), .rs by rustc (or cargo,
# with a <source>.Cargo.toml beside it), .py run by python (python3 on Linux; CPython, standard
# library only, `-I`). A program that did not change since it was measured is not run again
# (cache.zap; --fresh measures all). Builds and outputs go to build/benchmarks/.
# A problem with script = true is raced another way (scripts.zap): a throwaway Zap script run by
# `zap run` after an edit of it, against the Python script, in wall time end to end.

import fs

# a problem: its Zap program and the same program in other languages, the argument at each size,
# whether it reads stdin, the extra gcc and g++ flags of its C and C++ programs
pub type Problem:
	name str
	zap str   # the Zap program's source
	others str[]   # the other languages' sources
	arg str   # the command-line argument at full size
	quickArg str   # a smaller size for a quick look
	smallArg str   # the smallest size, for the check of the outputs
	stdin bool
	flags str
	script bool = false   # a throwaway script raced end to end (scripts.zap): arg is its arguments, the only size

# the extension of a source path without its dot ("rs")
fn extensionOf(src str):
	ext = fs.extension(src)
	ext[len.min(1)..].copy()

# the table's label of a language, by its sources' extension
fn languageName(ext str):
	"c++" if ext == "cpp" else "rust" if ext == "rs" else ext.copy()

# the languages raced, in the table's order: the compiled ones, then Python
fn raced(problems Problem[]):
	exts str[] = []
	for p in problems:
		for src in p.others:
			ext = extensionOf(src)
			if ext not in exts:
				exts.push(ext)
	exts.sortedBy(["c", "cpp", "rs", "py"].indexOf(it) ?? 9)

# ---------- starting a program directly ----------

# SECURITY_ATTRIBUTES: the handles opened with it are inherited by the started program
extern type SecurityAttributes:
	size u32 = 24
	descriptor i64 = 0
	inherit i32 = 1

# STARTUPINFOA with STARTF_USESTDHANDLES: the program's stdin, stdout and stderr are given
extern type StartupInfo:
	size u32 = 104
	reserved i64 = 0
	desktop i64 = 0
	title i64 = 0
	x u32 = 0
	y u32 = 0
	width u32 = 0
	height u32 = 0
	columns u32 = 0
	rows u32 = 0
	fill u32 = 0
	flags u32 = 256
	showWindow u16 = 0
	reserved2Size u16 = 0
	reserved2 i64 = 0
	stdInput i64
	stdOutput i64
	stdError i64

# PROCESS_INFORMATION, written by CreateProcessA
extern type ProcessInformation:
	process i64 = 0
	thread i64 = 0
	processId u32 = 0
	threadId u32 = 0

# PROCESS_MEMORY_COUNTERS, written by K32GetProcessMemoryInfo
extern type MemoryCounters:
	size u32 = 72
	pageFaults u32 = 0
	peakWorkingSet i64 = 0
	workingSet i64 = 0
	quotaPeakPaged i64 = 0
	quotaPaged i64 = 0
	quotaPeakNonPaged i64 = 0
	quotaNonPaged i64 = 0
	pagefile i64 = 0
	peakPagefile i64 = 0

extern fn CreateFileA(
	path str,
	access i64,
	share i64,
	security SecurityAttributes,
	disposition i64,
	attrs i64,
	template i64
) i64
extern fn CreateProcessA(
	app i64,
	cmd str,
	procAttrs i64,
	threadAttrs i64,
	inherit bool,
	flags i64,
	env i64,
	dir i64,
	startup StartupInfo,
	mut info ProcessInformation
) bool
extern fn WaitForSingleObject(h i64, ms i64) i32
extern fn GetExitCodeProcess(h i64, out code u32) bool
extern fn K32GetProcessMemoryInfo(process i64, mut counters MemoryCounters, size i64) bool
extern fn QueryProcessCycleTime(process i64, out cycles u64) bool
extern fn GetStdHandle(which i64) i64
extern fn SetHandleInformation(h i64, mask i64, flags i64) bool
extern fn CloseHandle(h i64) bool
extern fn CreateJobObjectA(attributes i64, name i64) i64
extern fn SetInformationJobObject(job i64, kind i64, info u8[], size i64) bool
extern fn AssignProcessToJobObject(job i64, process i64) bool
extern fn QueryInformationJobObject(job i64, kind i64, info u8[], size i64, returned i64) bool
extern fn ResumeThread(thread i64) u32
extern fn TerminateProcess(process i64, code u32) bool

benchMemoryMb = 2048

# the megabytes a measured program may commit: memory of ZAP_SETUP, else benchMemoryMb; past
# it, a run is out of memory
fn memoryLimitMb():
	(i64.parse(memoryWord().value() ?? "") ?? benchMemoryMb).max(1)

# One run of a program: its wall time, its peak working set, its processor cycles and its exit
# code (-1 when it did not start), and where the processor counts them (std/perf) its
# instructions, cache and branch misses. overMemory: it failed at its memory limit; overTime: it
# was stopped at its time limit (its seconds that limit).
pub type Run:
	seconds f64
	peakBytes i64
	cycles i64
	code i64
	overMemory bool = false
	overTime bool = false
	instructions i64 = 0
	cacheMisses i64 = 0
	branchMisses i64 = 0

# a Python program's limit at full size, in seconds: a ratio under 0.01x prints as 0.00x, so a run
# stopped there tells as much and saves most of a cold full run's time
pythonSeconds = 60.0

# the word for a run over its memory in the table and in the `measured` lines
outOfMemory = "out of memory"

# A job of its own with a limit of limitMb of committed memory a process (0 for no job), 0 when
# it cannot be made.
fn memoryJob(limitMb i64):
	job = CreateJobObjectA(0, 0)
	if job == 0: return 0
	info u8[] = zeros(144)   # JOBOBJECT_EXTENDED_LIMIT_INFORMATION
	info[17] = 1   # LimitFlags: PROCESS_MEMORY (256)
	bytes = limitMb * 1_048_576
	for i in 0..8:
		info[112 + i] = (bytes >> (8 * i)) & 255   # ProcessMemoryLimit
	if SetInformationJobObject(job, 9, info, 144): return job
	CloseHandle(job)
	0

# the most committed memory a process of the job reached
fn jobPeak(job i64) i64:
	info u8[] = zeros(144)
	if not QueryInformationJobObject(job, 9, info, 144, 0): return 0
	i64(info.loadWord(128))   # PeakProcessMemoryUsed

# a file opened as an inheritable handle: read from (OPEN_EXISTING) or written (CREATE_ALWAYS)
fn inheritableFile(path str, writing bool):
	access = 1_073_741_824 if writing else -2_147_483_648   # GENERIC_WRITE, GENERIC_READ
	CreateFileA("{path}\0", access, 1, SecurityAttributes(), 2 if writing else 3, 128, 0)

# Runs a command line with stdin from a file (NUL for none) and stdout to a file, the runner's
# stderr passed on; measures it from its start to its end. It runs in a job of its own that
# limits its memory to limitMb (0 for no limit); a run that failed with its peak at the limit
# (within an eighth) is overMemory, one still running at limitSeconds (0 for none) is stopped,
# overTime.
pub fn runMeasured(line str, inputPath str, outPath str, limitMb i64, limitSeconds f64 = 0.0) Run:
	input = inheritableFile("NUL" if inputPath == "" else inputPath.copy(), false)
	output = inheritableFile(outPath, true)
	errors = GetStdHandle(-12)
	SetHandleInformation(errors, 1, 1)   # HANDLE_FLAG_INHERIT: a pipe's handle may lack it
	startup = StartupInfo(stdInput = input, stdOutput = output, stdError = errors)
	info = ProcessInformation()
	t0 = clockSeconds()
	job = memoryJob(limitMb) if limitMb > 0 else 0
	# HIGH_PRIORITY_CLASS; CREATE_SUSPENDED when it joins the job before its first instruction
	flags = 132 if job != 0 else 128
	started = CreateProcessA(
		0,
		"{rt.windowsProgram(line)}\0",
		0,
		0,
		true,
		flags,
		0,
		0,
		startup,
		info
	)
	run = Run(seconds = 0.0, peakBytes = 0, cycles = 0, code = -1)
	if started:
		if job != 0:
			AssignProcessToJobObject(job, info.process)
			ResumeThread(info.thread)
		waited = WaitForSingleObject(
			info.process,
			-1 if limitSeconds <= 0.0 else i64(limitSeconds * 1000.0)
		)
		if waited == 258:   # WAIT_TIMEOUT
			TerminateProcess(info.process, 1)
			WaitForSingleObject(info.process, -1)
			run.overTime = true
		run.seconds = limitSeconds if run.overTime else clockSeconds() - t0
		counters = MemoryCounters()
		if K32GetProcessMemoryInfo(info.process, counters, 72):
			run.peakBytes = counters.peakWorkingSet
		if QueryProcessCycleTime(info.process, out cycles):
			run.cycles = i64(cycles)
		GetExitCodeProcess(info.process, out code)
		run.code = code
		limit = limitMb * 1_048_576
		run.overMemory = job != 0 and code != 0 and jobPeak(job) >= limit - limit / 8
		CloseHandle(info.thread)
		CloseHandle(info.process)
	if job != 0: CloseHandle(job)
	CloseHandle(input)
	CloseHandle(output)
	run

# Runs a program `runs` times within limitMb of memory (0 for no limit): the median wall time and
# of each count, the largest peak working set, or none when a run failed. A run over its memory
# ends the measure with that run, overMemory.
pub fn measure(
	exe str,
	arg str,
	inputPath str,
	outPath str,
	runs i64,
	limitMb i64,
	limitSeconds f64 = 0.0
) Run?:
	all = []
	loop runs:
		run = runMeasured("{exe} {arg}", inputPath, outPath, limitMb, limitSeconds)
		if run.overMemory:
			eprint("{exe} ran out of memory (past {limitMb} MB)")
			return run
		if run.overTime: return run
		if run.code != 0:
			eprint("{exe} failed with code {run.code}")
			return none
		all.push(run)
	medianRun(all)

# the runs' median wall time and median of each count, their largest peak
pub fn medianRun(all Run[]) Run:
	mid = all.len / 2
	Run(
		seconds = all.map(.seconds).sorted()[mid],
		peakBytes = all.map(.peakBytes).max() ?? 0,
		cycles = all.map(.cycles).sorted()[mid],
		code = 0,
		instructions = all.map(.instructions).sorted()[mid],
		cacheMisses = all.map(.cacheMisses).sorted()[mid],
		branchMisses = all.map(.branchMisses).sorted()[mid]
	)

# ---------- building ----------

fn sh(line str):
	Process.run(shellLine(line))

# where the other languages' builds and every program's outputs go
benchDir = "build/benchmarks"

# the executable a program in another language builds to
fn rivalExe(stem str, ext str):
	"{benchDir}/{stem}.{ext}{exeSuffix()}"

# Whether the build described by `recipe` (the sources and the command) is not the one that made
# exe; notes it as made when it is about to be.
fn stale(exe str, recipe str):
	stamp = "{exe}.recipe"
	if fs.exists(exe) and (fs.readFile(stamp) ?? "") == recipe: return false
	_ = fs.deleteFile(exe)
	_ = fs.writeFile(stamp, recipe)
	true

# the flags of every Rust build: this processor, one code unit (as rustc -O3 builds the fastest
# programs), and no warnings, which are the programs' authors' to read
rustFlags = "-C target-cpu=native -C codegen-units=1 -A warnings"

# A dir searched before the C++ compiler's own headers, with a copy of libstdc++'s ext/pb_ds:
# WinLibs' g++ reaches its deepest headers through lib/gcc/<target>/<version>/../../../../include,
# a path longer than Windows' 260 characters, so it cannot open them where they are (Windows'
# alone).
fn shortHeaders():
	dir = "build\\benchmarks\\include"
	if fs.exists("{dir}\\ext\\pb_ds"): return dir
	# the first dir searched (a line indented by a space) ending in include/c++/<version> is
	# libstdc++'s
	for line in Process.output("g++ -x c++ -E -v nul").out.lines():
		parts = line.trimmed().split("/")
		if line.startsWith(" ") and parts.len > 2 and parts[len - 2] == "c++":
			# each `..` taken out with the dir before it, or the copy hits the same limit
			dirs str[] = []
			for part in parts:
				if part == "..":
					dirs.pop()
				else:
					dirs.push(part.copy())
			from = "{dirs.join("\\")}\\ext\\pb_ds"
			Process.output("xcopy /e /i /q /y {from} {dir}\\ext\\pb_ds")
			break
	dir

# The interpreter a .py runs with: the base CPython of the one on the PATH (python, Linux's
# python3), because a virtual environment's python.exe starts that one as a child process and
# the child's time and memory would not be measured.
fn python():
	name = "python" if onWindows() else "python3"
	asked = Process.output("{name} -I -c \"import sys;print(sys._base_executable)\"")
	if asked.code != 0: return name
	exe = asked.out.trimmed()
	if exe == "": return name
	"\"{exe}\"" if " " in exe else exe.copy()

# a Rust program with crates: a cargo package named after it, in this dir
fn cargoDir(stem str):
	"{benchDir}/{stem}.cargo"

# the command that builds the program at src (the one that runs it for a .py); a cargo package's
# executable is then copied to rivalExe (build)
fn buildRecipe(src str, flags str):
	ext = extensionOf(src)
	stem = fs.stem(src)
	if ext == "py": return "{python()} -I {src}"
	if ext == "zap": return "zap build {src}"
	exe = rivalExe(stem, ext)
	if ext == "rs" and fs.exists("{src}.Cargo.toml"):
		cargo = "cargo build -q --release --manifest-path {cargoDir(stem)}/Cargo.toml"
		return withVariable("RUSTFLAGS", rustFlags, cargo)
	if ext == "rs": return "rustc --edition 2021 -C opt-level=3 {rustFlags} {src} -o {exe}"
	# static: the C++ runtime on Windows' PATH may not be the compiler's own; the flags after the
	# source, where a library (-lgmp) resolves what it calls
	headers = " -I{shortHeaders()}" if onWindows() else ""
	cc = "g++ -std=gnu++17{headers}" if ext == "cpp" else "gcc"
	"{cc} -O3 -fomit-frame-pointer -march=native -static -w {src} {flags} -o {exe}"

# the command that runs the program at src: its executable (built when its source or flags
# changed), or the interpreter and the source; "" when it cannot be built
pub fn build(src str, flags str) str:
	ext = extensionOf(src)
	stem = fs.stem(src)
	if ext != "zap":
		provideLibraries(flags)   # (a library the machine lacks fetched once)
	if ext == "py": return buildRecipe(src, flags)
	if ext == "zap":
		if Process.output(buildRecipe(src, flags)).code != 0:
			eprint("cannot build {src}")
			return ""
		return builtExe(stem)
	_ = fs.createDir(benchDir)
	exe = rivalExe(stem, ext)
	source = fs.readFile(src) ?? ""
	manifest = fs.readFile("{src}.Cargo.toml") ?? ""
	command = buildRecipe(src, flags)
	package = ext == "rs" and manifest != ""
	if package:
		if not stale(exe, source + manifest + command): return exe
		writePackage(stem, source, manifest)
	elif not stale(exe, source + command):
		return exe
	built = sh(command) == 0 and
		(not package or copied("{cargoDir(stem)}/target/release/{stem}{exeSuffix()}", exe))
	if not built or not fs.exists(exe):
		eprint("cannot build {src}")
		_ = fs.deleteFile("{exe}.recipe")
		return ""
	exe

# a Rust program's cargo package: its source as src/main.rs, its manifest named after it
fn writePackage(stem str, source str, manifest str):
	dir = cargoDir(stem)
	_ = fs.createDir("{dir}/src")
	_ = fs.writeFile("{dir}/src/main.rs", source)
	cargo = ""
	for line in manifest.lines():
		cargo += "name = \"{stem}\"" if line.startsWith("name = ") else line.copy()
		cargo += "\n"
	_ = fs.writeFile("{dir}/Cargo.toml", cargo)

# whether the executable at from was copied to to, runnable
fn copied(from str, to str):
	bytes = fs.readBytes(from) ?? return false
	_ = fs.writeBytes(to, bytes) ?? return false
	fs.canRun(to)

# ---------- the sections of an executable ----------

# a section of a PE executable: its name (".text"), where it is loaded (va, relative to the
# image), its size there, and its place and size in the file
pub type Section:
	name str
	va i64
	size i64
	raw i64
	rawSize i64

# the sections of a PE executable's bytes (none when they are no PE file)
pub fn sections(data u8[]) Section[]:
	if data.len < 64: return []
	pe = i64(data.u32le(60))
	# its signature: PE and two zeros (an ELF's bytes have none)
	if pe + 24 > data.len or data.u32le(pe) != 0x4550: return []
	count = data.u16le(pe + 6)
	first = pe + 24 + i64(data.u16le(pe + 20))
	out = []
	for i in 0..count:
		s = first + i * 40
		if s + 40 > data.len: break
		name = []
		for b in data[s..s + 8]:
			if b == 0: break
			name.push(b)
		out.push(
			Section(
				name = str(move name),
				va = data.u32le(s + 12),
				size = data.u32le(s + 8),
				raw = data.u32le(s + 20),
				rawSize = data.u32le(s + 16)
			)
		)
	out

# ---------- the size of a program's source ----------

# A program's code size: its lines (non-blank once comments, string contents and Zap's test
# blocks are out) and its decisions.
type CodeSize:
	lines i64
	decisions i64

# a Zap source without its test blocks (each opens with `test` at the margin and closes with a
# `}` there)
fn withoutTests(source str):
	kept = []
	inTest = false
	for line in source.lines():
		if line.startsWith("test "):
			inTest = true
		if not inTest:
			kept.push(line.copy())
		if inTest and line == "}":
			inTest = false
	kept.join("\n")

# the source with comments (// and /* */) and the insides of string and character literals taken
# out, its line breaks kept
fn strippedCode(source str) str:
	s = source.bytes()
	out = []
	i = 0
	while i < s.len:
		c = s[i]
		next = s[i + 1] if i + 1 < s.len else 0
		if c == '/' and next == '/':
			while i < s.len and s[i] != '\n':
				i += 1
		elif c == '/' and next == '*':
			i += 2
			while i < s.len and not (s[i] == '*' and i + 1 < s.len and s[i + 1] == '/'):
				if s[i] == '\n':
					out.push('\n')
				i += 1
			i += 2
		elif c == '"':
			out.push('"')
			i += 1
			while i < s.len and s[i] != '"':
				if s[i] == '\n':
					out.push('\n')
				i += 2 if s[i] == '\\' else 1
			out.push('"')
			i += 1
		elif c == '\'' and (next == '\\' or i + 2 < s.len and s[i + 2] == '\''):
			# a character literal ('x', '\n'); a quote that opens none is a Rust lifetime
			i += 2
			while i < s.len and s[i] != '\'':
				i += 1
			out.push('\'')
			out.push('\'')
			i += 1
		else:
			out.push(c)
			i += 1
	str(move out)

# decisions, alike in every language: if, for, while, loop, case, &&, ||, `?` between spaces, a match arm (`=>` outside parentheses, its pattern not `_`)
fn decisions(line str):
	b = line.bytes()
	count = 0
	depth = 0
	i = 0
	while i < b.len:
		c = b[i]
		if c.isWordByte():
			start = i
			while i < b.len and b[i].isWordByte():
				i += 1
			word = line[start..i]
			if word == "if" or word == "for" or word == "while" or word == "loop" or word == "case":
				count += 1
			continue
		next = b[i + 1] if i + 1 < b.len else 0
		if c == '(':
			depth += 1
		elif c == ')':
			depth -= 1
		elif c == '&' and next == '&' or c == '|' and next == '|':
			count += 1
			i += 1
		elif c == '?' and i > 0 and b[i - 1] == ' ' and next == ' ':
			count += 1
		elif c == '=' and next == '>' and depth <= 0 and not line.trimmed().startsWith("_ "):
			count += 1
		i += 1
	count

fn codeSize(path str):
	source = fs.readFile(path) ?? ""
	code = strippedCode(withoutTests(source) if path.endsWith(".zap") else source.copy())
	size = CodeSize(lines = 0, decisions = 0)
	for line in code.lines():
		if line.trimmed() != "":
			size.lines += 1
			size.decisions += decisions(line)
	size

# ---------- the table ----------

# a run's time and peak memory cells, or its "out of memory"
fn runCells(r Run?):
	if r is run:
		if run.overMemory: return "{outOfMemory:>14}"
		if run.overTime: return "{"> {i64(run.seconds)} s":>14}"
		return "{i64((run.seconds * 1000.0).round()):>7}{run.peakBytes / 1048576.0:>7.1}"
	"{"-":>7}{"-":>7}"

fn ratioCell(ratio f64):
	"{"{ratio:.2}x":>8}"

# The line zap test reads for the README's numbers: a program's time, peak memory and tokens
# (0 time and memory for one not raced, "out of memory" for the time of one over its memory)
fn printNumbers(problem str, language str, run Run?, tokens i64):
	ms = 0
	bytes = 0
	if run is r:
		ms = i64((r.seconds * 1000.0).round())
		bytes = r.peakBytes
	print("measured\t{problem}\t{language}\t{ms}\t{bytes}\t{tokens}")

# What a bench suite is asked (`zap run suite [--runs N] [--full] [--fresh] [name text]`): the runs of each
# case, the real sizes instead of the quick ones, and the text the cases' names hold ("" for all)
pub type SuiteRequest:
	runs i64
	full bool
	fresh bool   # the cache of Zap's measured runs is ignored
	name str
	freshAll bool = false   # `--fresh all`: every language's too
	ab str = ""   # `--ab zap.exe`: Zap's programs raced against that zap's builds of them (abSuite)
	abFor str = ""   # `--ab-for target`: the two builds of each made for the target, not raced
	abBuilt bool = false   # `--ab-built`: the two builds --ab-for made raced here, none built
	tokens bool = false   # `--tokens`: the tokens' bench lines alone (tokensLines)

# the request of a suite that only times its programs (a project's): `--tokens`, which asks for
# tokens alone, ends it at once, nothing built or run
pub fn timedSuiteRequest(all str[]) SuiteRequest:
	request = suiteRequest(all)
	if request.tokens: exit(0)
	request

# the request in a suite's arguments
pub fn suiteRequest(all str[]) SuiteRequest:
	request = SuiteRequest(runs = 1, full = false, fresh = false, name = "")
	i = 0
	while i < all.len:
		a = all[i]
		if a == "--runs" and i + 1 < all.len:
			request.runs = i64.parse(all[i + 1]) ?? 1
			i += 1
		elif a == "--full":
			request.full = true
		elif a == "--tokens":
			request.tokens = true
		elif a == "--fresh":
			request.fresh = true
			if i + 1 < all.len and all[i + 1] == "all":
				request.freshAll = true
				i += 1
		elif a == "--ab" and i + 1 < all.len:
			request.ab = all[i + 1].copy()
			i += 1
		elif a == "--ab-for" and i + 1 < all.len:
			request.abFor = all[i + 1].copy()
			i += 1
		elif a == "--ab-built":
			request.abBuilt = true
		else:
			request.name = all[i].copy()
		i += 1
	request

# The bench's measures (spec 13.1), each a ratio of Zap's program to the rival best at it: its
# word in the `bench` lines and in bench.baseline's keys, whether it is kept a size each (else once
# a case), its margin past which a ratio is worse at the quick sizes and with --full, and whether
# it needs the programs built and run (the tokens do not: every zap test checks them).
pub type BenchMeasure:
	name str
	sized bool
	quickMargin f64
	fullMargin f64
	built bool = true

# time: processor cycles; memory: peak working set; instructions, cachemisses, branchmisses: the
# processor's counts (std/perf, where it counts them); exe: the executable's bytes, the rivals the
# compiled ones (C, C++, Rust); tokens: tokens.zap's count, Python a rival too
pub benchMeasures = [
	BenchMeasure(name = "time", sized = true, quickMargin = 0.2, fullMargin = 0.1),
	BenchMeasure(name = "memory", sized = true, quickMargin = 0.2, fullMargin = 0.1),
	BenchMeasure(name = "instructions", sized = true, quickMargin = 0.05, fullMargin = 0.03),
	BenchMeasure(name = "cachemisses", sized = true, quickMargin = 0.5, fullMargin = 0.3),
	BenchMeasure(name = "branchmisses", sized = true, quickMargin = 0.3, fullMargin = 0.2),
	BenchMeasure(name = "exe", sized = false, quickMargin = 0.05, fullMargin = 0.05),
	BenchMeasure(name = "tokens", sized = false, quickMargin = 0.0, fullMargin = 0.0, built = false)
]

# The line zap test reads for a case's measure (spec 13.1): the case, the measure, Zap's value and
# its rival's, the rival, how to run Zap's program (its source, its argument, its stdin's file, ""
# for none)
pub fn benchLine(
	name str,
	measure str,
	zapValue i64,
	rivalValue i64,
	rival str,
	source str,
	arg str,
	input str
):
	print("bench\t{name}\t{measure}\t{zapValue}\t{rivalValue}\t{rival}\t{source}\t{arg}\t{input}")

# the least value a rival reached in a measure, and that rival (0 and "" before one did)
type Least:
	value i64 = 0
	rival str = ""

# the value kept when it is less than the least so far (0 is no value)
fn offer(mut least Least, value i64, rival str):
	if value > 0 and (least.value == 0 or value < least.value):
		least.value = value
		least.rival = rival.copy()

# What the rivals of a problem raced so far: the best of the compiled ones in each built measure
# (an out of memory or failed one has none), the sources' fewest lines and decisions, the
# languages that print something else than Zap, whether any program failed.
type Rivals:
	bestTime f64 = 0.0
	cycles Least = Least()
	memory Least = Least()
	exe Least = Least()
	instructions Least = Least()
	cacheMisses Least = Least()
	branchMisses Least = Least()
	differing str[] = []
	leastLines i64 = 0
	leastDecisions i64 = 0
	failed bool = false

# Builds one rival's program just before its runs, races it and adds it to the rivals; its cells.
# A program over its memory is noted ("out of memory") and the race goes on.
fn raceRival(
	mut best Rivals,
	mut cache Cache,
	p Problem,
	ext str,
	zapOutput i64,
	arg str,
	input str,
	runs i64,
	full bool
):
	source = p.others.find(extensionOf(it) == ext) ?? return runCells(none)
	size = codeSize(source)
	best.leastLines = size.lines if best.leastLines == 0 else best.leastLines.min(size.lines)
	best.leastDecisions = size.decisions if best.leastDecisions == 0
		else best.leastDecisions.min(size.decisions)
	outPath = "{benchDir}/{p.name}.{ext}.out"
	# Python runs once at full size: a run can take minutes
	result = cache.outcome(
		p.name,
		source,
		p.flags,
		arg,
		input,
		1 if full and ext == "py" else runs,
		outPath,
		pythonSeconds if full and ext == "py" else 0.0
	)
	if not result.built:
		best.failed = true
		return runCells(none)
	other = move result.run
	printNumbers(p.name, languageName(ext), other, tokenCount(source))
	if other is run:
		if run.overMemory or run.overTime: return runCells(other)   # (stopped: its output is part of one)
		if result.output != zapOutput:
			best.differing.push(ext.copy())
		# the rival is a compiled one: a Python program's helper processes are not in its cycles
		# and memory
		if ext != "py":
			if best.bestTime == 0.0 or run.seconds < best.bestTime:
				best.bestTime = run.seconds
			rival = languageName(ext)
			best.cycles.offer(run.cycles, rival)
			best.memory.offer(run.peakBytes, rival)
			best.exe.offer(result.exeBytes, rival)
			best.instructions.offer(run.instructions, rival)
			best.cacheMisses.offer(run.cacheMisses, rival)
			best.branchMisses.offer(run.branchMisses, rival)
	else:
		best.failed = true
	runCells(other)

# A bench suite (see the top): the problems, the input the stdin problems read at a mode ("full",
# "quick"), and the arguments of the suite's run. Ends with 1 when a program failed; a rival over
# its memory (memory in ZAP_SETUP) is not a failure, a Zap program over it is.
pub fn suite(problems Problem[], inputFor fn(str) str, all str[]):
	request = suiteRequest(all)
	runs = request.runs
	full = request.full
	name = request.name
	_ = fs.createDir(benchDir)
	if problems.any(.script):
		scriptSuite(problems, request)
		return
	if request.ab != "":
		abSuite(problems, inputFor, request)
		return
	if request.tokens:
		tokensLines(problems, name)
		return
	exts = raced(problems)
	cache = newCache(request.fresh, request.freshAll)
	head1 = "                       zap"
	head2 = "problem          ms     MB"
	for ext in exts:
		head1 += "{languageName(ext):>16}"
		head2 += "      ms     MB"
	print("{head1}   zap / best other")
	print("{head2}    time  memory   lines  decisions  output")
	failed = false
	for p in problems:
		if name not in p.name: continue
		arg = p.arg if full else p.quickArg
		input = inputFor("full" if full else "quick") if p.stdin else ""
		zapResult = cache.outcome(
			p.name,
			p.zap,
			"",
			arg,
			input,
			runs,
			"{benchDir}/{p.name}.zap.out"
		)
		if not zapResult.built:
			failed = true
			continue
		zap = move zapResult.run
		printNumbers(p.name, "zap", zap, tokenCount(p.zap))
		cells = runCells(zap)
		best = Rivals()
		zapSize = codeSize(p.zap)
		for ext in exts:
			cells += " {best.raceRival(cache, p, ext, zapResult.output, arg, input, runs, full)}"
		ratios = "{"-":>8}{"-":>8}"
		if zap is zapRun and not zapRun.overMemory and best.bestTime > 0.0:
			# cycles, not wall time: a run starved by other load takes the seconds but not the cycles
			timeRatio = zapRun.seconds / best.bestTime
			if zapRun.cycles > 0 and best.cycles.value > 0:
				timeRatio = f64(zapRun.cycles) / f64(best.cycles.value)
			ratios = ratioCell(timeRatio) +
				ratioCell(f64(zapRun.peakBytes) / f64(best.memory.value))
		linesRatio = f64(zapSize.lines) / f64(best.leastLines.max(1))
		decisionsRatio = f64(zapSize.decisions) / f64(best.leastDecisions.max(1))
		ratios += "{ratioCell(linesRatio)}   {ratioCell(decisionsRatio)}"
		check = "ok" if best.differing.isEmpty else "DIFFERS: {best.differing.join(", ")}"
		failed = failed or best.failed or not best.differing.isEmpty
		print("{p.name:<14}{cells}{ratios}  {check}")
		match zap:
			zr:
				# the lines zap test reads, how to run Zap's program with them (for --next)
				if best.cycles.value > 0 and not zr.overMemory:
					for m in benchMeasures.filter(.built):
						value, rival = builtValue(m.name, zr, zapResult.exeBytes, best)
						benchLine(
							p.name,
							m.name,
							value,
							rival.value,
							rival.rival,
							p.zap,
							arg,
							input
						)
				if zr.overMemory: failed = true
			none: failed = true
	print(cache.cacheLine())
	if failed:
		exit(1)

# Zap's value in a built measure and the least of its rivals (a count the processor did not give
# is 0, which zap test leaves out)
fn builtValue(measure str, zap Run, exeBytes i64, best Rivals):
	match measure:
		"time": (zap.cycles, best.cycles.copy())
		"memory": (zap.peakBytes, best.memory.copy())
		"instructions": (zap.instructions, best.instructions.copy())
		"cachemisses": (zap.cacheMisses, best.cacheMisses.copy())
		"branchmisses": (zap.branchMisses, best.branchMisses.copy())
		_: (exeBytes, best.exe.copy())

# --tokens: each problem's tokens against the fewest of its rivals', nothing built or run
fn tokensLines(problems Problem[], name str):
	for p in problems:
		if name not in p.name: continue
		least = Least()
		for source in p.others:
			least.offer(tokenCount(source), languageName(extensionOf(source)))
		benchLine(p.name, "tokens", tokenCount(p.zap), least.value, least.rival, p.zap, "", "")

# whether the problem's programs in every language print the same bytes at the small size, with
# stdin from input ("" for none); a difference is named on stderr. The Zap program is built,
# unless own is an executable that runs its main given the arguments (a test's own program,
# 12): then it runs that.
pub fn agree(p Problem, input str, own str = "") bool:
	if p.script: return p.scriptAgree()
	zapExe = build(p.zap, "") if own == "" else quoteArg(own)
	if zapExe == "": return false
	lines = ["{zapExe} {p.smallArg}"]
	for src in p.others:
		exe = build(src, p.flags)
		if exe == "": return false
		lines.push("{exe} {p.smallArg}")
	outDir = "{benchDir}/{p.name}"
	_ = fs.createDir(outDir)
	sameOutput(lines, input, outDir)

# Whether the programs the command lines start print the same bytes, each with stdin from
# inputPath ("" for none) and stdout to outDir/<n>.out. A command that fails or prints
# something else is named on stderr; lineEndingsAlike reads CRLF as LF.
pub fn sameOutput(lines str[], inputPath str, outDir str, lineEndingsAlike bool = false) bool:
	first str? = none
	same = true
	for i, line in lines:
		out = "{outDir}/{i}.out"
		if runMeasured(line, inputPath, out, 0).code != 0:
			eprint("    {line}: failed")
			same = false
			continue
		text = fs.readFile(out) ?? ""
		if lineEndingsAlike:
			text = scriptLineEndings(text)
		if first is f:
			if text != f:
				eprint("    {line}: prints something else than {lines[0]} ({out} against {outDir}/0.out)")
				same = false
		else:
			first = text
	same
