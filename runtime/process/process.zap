# A process started from a command line: `p = Process.start("git status")`, then `p.isDone`
# (whether it ended) and `p.wait()` (its exit code, kept in `p.code`); `Process.run(cmd)` starts
# one and waits for it; `Process.output(cmd)` runs one to its end and keeps what it wrote in `out`.
pub type Process:
	handle i64   # -1: it could not start
	code i64 = -1   # the exit code, once waited for; -1 before, or when it never started
	out str = ""   # Process.output's: what it wrote to stdout and stderr, in the order written

	# whether the process has ended (wait then gives its exit code at once)
	fn isDone() bool:
		processDone(self)

	# waits for the process to end; its exit code (kept in code), -1 when it never started
	mut fn wait() i64:
		processWait(self)

	# waits for the process to end, ms milliseconds at most: its exit code, or none while it still
	# runs (a wait that may never end, for a peer that never came, has a limit)
	mut fn waitWithin(ms i64) i64?:
		since = clockMs()
		while not self.isDone:
			if clockMs() - since >= ms: return none
			sleepMs(1)
		wait()

# Process's isDone and wait on Windows, functions a system's files replace (linux/process.zap)
fn processDone(p Process) bool:
	p.handle == -1 or p.code != -1 or WaitForSingleObject(p.handle, 0) == 0

fn processWait(mut p Process) i64:
	if p.handle == -1 or p.code != -1: return p.code
	WaitForSingleObject(p.handle, -1)
	p.code = exitCodeOf(p.handle)
	CloseHandle(p.handle)
	p.code

# cmd with its program's path written with backslashes: Windows finds no program named with `/`
# (`build/game.exe`); the arguments stay as written
fn windowsProgram(cmd str) str:
	quoted = cmd.startsWith("\"")
	end = (cmd.indexOf("\"", 1) ?? cmd.len) if quoted else cmd.indexOf(" ") ?? cmd.len
	"{cmd[..end].replace("/", "\\")}{cmd[end..]}"

# Process.start(cmd): the command line started, not waited for (handle -1 when it cannot start)
pub fn processStart(cmd str) Process:
	flushStdout()   # our output stays ahead of the child's
	si = zeroBytes(104)   # a STARTUPINFOA: cb = 104
	si[0] = 104
	procInfo = zeroBytes(24)   # a PROCESS_INFORMATION: hProcess, hThread
	started = CreateProcessA(0, cstr(windowsProgram(cmd)), 0, 0, true, 0, 0, 0, si, procInfo)
	if not started: return Process(handle = -1)
	CloseHandle(i64(procInfo.loadWord(8)))
	Process(handle = i64(procInfo.loadWord(0)))

# Process.run(cmd): the command line run and waited for; its exit code, -1 when it cannot start
pub fn processRun(cmd str) i64:
	p = processStart(cmd)
	p.wait()

# The command line that runs line in the shell of the system the program runs on, for what only
# a shell does (redirections, pipelines, a variable set for one line): Windows' cmd, or Linux's sh,
# which Process.start starts there
pub fn shellLine(line str) str:
	"cmd /c \"{line}\""

# an argument of a command line in double quotes, which group it in cmd's lines and sh's
pub fn quoteArg(s str) str:
	"\"{s.replace("\"", "\\\"")}\""

# a shell line (shellLine's) with a variable set for it alone
pub fn withVariable(name str, value str, line str) str:
	"set {name}={value}&& {line}" if onWindows() else "{name}={quoteArg(value)} {line}"

# a shell line with the variables ("NAME=value") set for it alone
pub fn withVariables(vars str[], line str) str:
	out = line.copy()
	for v in vars:
		at = v.indexOf("=") ?? v.len
		out = withVariable(v[..at], v[(at + 1).min(len)..], out)
	out

# Process.output(cmd): the program run to its end with no shell between, the line split into its
# words (commandWords), and the program found on the PATH (or named from here); its stdin is
# `input`, `vars` ("NAME=value") are set for it alone, it runs in `dir` ("": here), and what it
# writes to stdout and stderr, one stream in the order written, is kept in `out` (`p.code` its
# exit code, -1 when it cannot start)
pub fn processOutput(cmd str, input str = "", vars str[] = [], dir str = "") Process:
	runToEnd(windowsProgram(cmd), input, vars, dir)

# Process.output(argv) of a list: the words given as they are, `Process.output(["git", "-C", dir,
# "log"])`: each one argument, quoted for the system, with no splitting at its spaces
pub fn processOutputList(argv str[], input str = "", vars str[] = [], dir str = "") Process:
	runToEnd(argvLine(argv), input, vars, dir)

fn runToEnd(line str, input str, vars str[], dir str) Process:
	flushStdout()
	inOurs, inTheirs = childPipe(false, input.len + 1)
	writeRaw(inOurs, input.bytes())   # the pipe holds it all: written before the program starts
	CloseHandle(inOurs)
	outOurs, outTheirs = childPipe(true, 65_536)
	si = zeroBytes(104)   # a STARTUPINFOA: cb = 104, STARTF_USESTDHANDLES, the three handles
	si[0] = 104
	si.setU32le(60, 256)
	si.setU64le(80, u64(inTheirs))
	si.setU64le(88, u64(outTheirs))
	si.setU64le(96, u64(outTheirs))
	all = processVariables() if not vars.isEmpty else []
	all.extend(vars)
	block = "" if vars.isEmpty else "{latestVariables(all).join("\0")}\0\0"
	envBlock = 0 if vars.isEmpty else sPtr(block)   # 0: the program gets this one's
	there = "{dir}\0"
	procInfo = zeroBytes(24)
	started = CreateProcessA(
		0,
		cstr(line),
		0,
		0,
		true,
		0,
		envBlock,
		0 if dir == "" else sPtr(there),
		si,
		procInfo
	)
	CloseHandle(inTheirs)
	CloseHandle(outTheirs)   # the pipe ends when the program and its children close theirs
	p = Process(handle = -1)
	if started:
		CloseHandle(i64(procInfo.loadWord(8)))
		p.handle = i64(procInfo.loadWord(0))
	text u8[] = []
	readRest(outOurs, text)
	CloseHandle(outOurs)
	p.out = str(move text)
	_ = p.wait()
	p

# The words as one command line that Windows' rules (commandWords) split back into them: an
# argument with a space, a tab or a quote, or none, in double quotes, a quote inside it and the
# backslashes before it (or before the closing quote) escaped
fn argvLine(argv str[]) str:
	argv.map(windowsArgument(it)).join(" ")

fn windowsArgument(s str) str:
	if not s.isEmpty and not s.contains(" ") and not s.contains("\t") and not s.contains("\""):
		return s.copy()
	out u8[] = []
	out.push('"')
	slashes = 0
	for b in s.bytes():
		if b == '\\':
			slashes += 1
			continue
		loop (slashes * 2 + 1) if b == '"' else slashes:
			out.push('\\')
		slashes = 0
		out.push(b)
	loop slashes * 2:
		out.push('\\')
	out.push('"')
	str(move out)

# A pipe whose one end a started process inherits: (ours, its), its end the write end when the
# process writes into it; size the bytes it holds before a write waits
fn childPipe(childWrites bool, size i64) (i64, i64):
	_ = CreatePipe(out readEnd, out writeEnd, 0, size)
	ours = writeEnd if not childWrites else readEnd
	theirs = writeEnd if childWrites else readEnd
	_ = SetHandleInformation(theirs, 1, 1)   # HANDLE_FLAG_INHERIT
	(ours, theirs)

# the environment variables of this process, "NAME=value" each
fn processVariables() str[]:
	all str[] = []
	block = GetEnvironmentStringsA()
	at = block
	while __ld8(at) != 0:
		v = str(cBytes(at))
		at += v.len + 1
		all.push(v)
	_ = FreeEnvironmentStringsA(block)
	all
