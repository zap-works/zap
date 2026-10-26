# The runtime's console output and the ways a program ends (core.zap).

type Console:
	out u8[]
	isConsole i64   # 0 not asked yet, 1 yes, 2 no
	inBuf u8[]   # 64 KB once stdin was read, inLen of them valid
	inLen i64
	inPos i64
	inEof bool
	inGiven bool   # the input is inBuf alone (stdin.feed): no handle read
	capturing bool = false   # stdout goes to `captured`, not to the handle (a `prints` test's)
	captured u8[] = []

stdoutBufSize i64 = 65_536
stdinBufSize i64 = 65_536

mut console = Console(
	out = [],
	isConsole = 0,
	inBuf = [],
	inLen = 0,
	inPos = 0,
	inEof = false,
	inGiven = false
)
# what ends the threads the program started, once the first started (threads.zap's endThreads):
# with true, their background jobs done first
mut threadsEnd fn(bool) = (_): pass

fn threadsEnded(waitJobs bool):
	ends = threadsEnd
	ends(waitJobs)

mut stdoutHandle = GetStdHandle(-11)
mut stderrHandle = GetStdHandle(-12)
mut stdinHandle = GetStdHandle(-10)

# every byte to the handle, in as many calls as the system takes
fn writeRaw(h i64, bytes u8[]):
	n = bytes.len
	done i64 = 0
	while done < n:
		w = writeSome(h, bytes[done..n])
		if w <= 0: return
		done += w

# before a child process starts or the program ends
fn flushStdout():
	if console.out.len > 0:
		writeRaw(stdoutHandle, console.out)
		console.out.clear()

mut outputSent = false

# print's and eprint's output sent to the file at path (made again) until outputBack: what a zap
# answering a test program's request says (spec 13.1), apart from its own output
pub fn outputTo(path str):
	flushStdout()
	h = CreateFileA(cstr(path), 1_073_741_824, 1, 0, 2, 128, 0)   # GENERIC_WRITE, CREATE_ALWAYS
	if h == -1: return
	stdoutHandle = h
	stderrHandle = h
	outputSent = true

pub fn outputBack():
	if not outputSent: return
	flushStdout()
	CloseHandle(stdoutHandle)
	stdoutHandle = GetStdHandle(-11)
	stderrHandle = GetStdHandle(-12)
	outputSent = false

fn stdoutIsConsole() bool:
	if console.isConsole == 0:
		console.isConsole = 2
		if isConsoleHandle(stdoutHandle):
			console.isConsole = 1
	console.isConsole == 1

fn stdoutWrite(bytes u8[]):
	arenaPause()   # the buffer and a test's capture outlive any arena
	stdoutBuffer(bytes, false)
	arenaResume()

# the bytes into stdout's buffer, a line break after them when line
fn stdoutBuffer(bytes u8[], line bool):
	if console.capturing:
		console.captured.extend(bytes)
		if line:
			console.captured.push('\n')
		return
	n = bytes.len + (1 if line else 0)
	if console.out.len + n > stdoutBufSize:
		flushStdout()
	if n > stdoutBufSize:
		writeRaw(stdoutHandle, bytes)
		if line:
			writeRaw(stdoutHandle, "\n".bytes())
		return
	console.out.extend(bytes)
	if line:
		console.out.push('\n')

# bytes to a handle: stdout goes through its buffer, anything else is written at once
fn writeToHandle(h i64, bytes u8[]):
	if h == stdoutHandle:
		stdoutWrite(bytes)
	else:
		flushStdout()
		writeRaw(h, bytes)

# text and a newline to a handle, in one write; stdout on a console is flushed at every line
fn writeLineToHandle(h i64, text str):
	if h == stdoutHandle:
		arenaPause()   # the buffer and a test's capture outlive any arena
		stdoutBuffer(text.bytes(), true)
		arenaResume()
		if stdoutIsConsole():
			flushStdout()
		return
	flushStdout()
	line u8[] = []
	line.reserve(text.len + 1)
	line.extend(text.bytes())
	line.push('\n')
	writeRaw(h, line)

# prints the text and a line break on standard output, or on standard error when toErr
fn printLine(s str, toErr bool):
	if toErr and stderrKeeping:
		arenaPause()   # the lines kept outlive any arena
		stderrKept.extend(s.bytes())
		stderrKept.push(10)
		arenaResume()
		return
	writeLineToHandle(stderrHandle if toErr else stdoutHandle, s)

mut stderrKeeping = false
mut stderrKept u8[] = []

# Standard error's lines (eprint's) kept from here until takeStderr() gives them, instead of
# written: what a tool that runs a check in its own process reads as that check's output.
pub fn keepStderr():
	stderrKeeping = true

# the lines kept since keepStderr(), standard error written to again
pub fn takeStderr() str:
	stderrKeeping = false
	kept = move stderrKept
	stderrKept = []
	str(move kept)

# the end of a program whose main returned: every block it allocated is free by now (the slot
# says so to the leak report)
# main's end reached with nothing to judge its teardown (no leak notes, poisoning or memory
# stats): the program ends there, and the system takes back what its locals hold
fn endWithoutTeardown():
	if not exitFrees():
		endAfterMain(0)

# whether the end frees every block, the module variables' too: for what counts them (the
# leaks, memcheck, memstats); else the system takes the memory back whole
fn exitFrees() bool:
	leakNotesOn() or memcheckOn() or memstatsWord().on()

fn endAfterMain(code i64):
	setMainReturned()
	exitWith(code)

# exit(code, message): the line to stderr, then the end with the code
fn exitSaying(code i64, message str):
	printLine(message, true)
	exitWith(code)

# ends the program now with this exit code
fn exitWith(code i64):
	flushStdout()
	threadsEnded(false)
	__fini()   # the module variables, the console among them
	memStats()
	ExitProcess(code)

# A Stream writes bytes somewhere: the console for now, files and sockets later. `write` and
# `writeBytes` add nothing; `print(value)`, the one way to write a line, formats any value and
# adds a newline (the compiler writes the formatting, like for `print`).

# the console's standard output or error
pub type Stream:
	handle i64

	# writes the text as it is, with no line break
	fn write(text str):
		writeToHandle(handle, text.bytes())

	# writes the bytes as they are
	fn writeBytes(b u8[]):
		writeToHandle(handle, b)

# the standard output as a stream (stdout.write(text), .print(value), .writeBytes)
pub stdout = Stream(handle = stdoutHandle)

# the standard error as a stream
pub stderr = Stream(handle = stderrHandle)

# stream.print(value): the formatted value and a newline
fn streamPrint(s Stream, text str):
	writeLineToHandle(s.handle, text)
