# Pseudo consoles (ConPTY): a program started on a console of its own whose screen comes out as
# the bytes a terminal reads (text and VT sequences) and whose keyboard is the bytes written in,
# as a terminal emulator or a server of terminals drives a shell. Nothing waits: read() gives what
# the program wrote so far.

extern fn CreatePipe(out read i64, out write i64, attrs i64, size i64) bool
extern fn PeekNamedPipe(pipe i64, buf i64, size i64, read i64, out available u32, left i64) bool
extern fn CreatePseudoConsole(size i64, input i64, output i64, flags i64, out console i64) i32
extern fn ResizePseudoConsole(console i64, size i64) i32
extern fn ClosePseudoConsole(console i64)
extern fn InitializeProcThreadAttributeList(list u8[], count i64, flags i64, out size i64) bool
extern fn UpdateProcThreadAttribute(
	list u8[],
	flags i64,
	attribute i64,
	value i64,
	size i64,
	previous i64,
	returned i64
) bool
extern fn DeleteProcThreadAttributeList(list u8[])
extern fn CreateProcessW(
	app i64,
	cmd u8[],
	procAttrs i64,
	threadAttrs i64,
	inherit bool,
	flags i64,
	env i64,
	dir u8[],
	startup StartupInfoEx,
	mut info ProcessInformation
) bool
extern fn TerminateProcess(h i64, code i64) bool
extern fn MultiByteToWideChar(page i64, flags i64, text u8[], n i64, wide u8[], room i64) i32

# STARTUPINFOEXW: STARTUPINFOW, then the attribute list that carries the pseudo console
extern type StartupInfoEx:
	cb u32 = 112
	reserved ref str?
	desktop ref u16[]?   # the desktop the windows open on, none: the caller's
	title ref str?
	x u32
	y u32
	xSize u32
	ySize u32
	xChars u32
	yChars u32
	fill u32
	flags u32
	show u16
	reserved2 u16
	reserved3 ref str?
	stdInput i64
	stdOutput i64
	stdError i64
	attributeList ref u8[]

extern type ProcessInformation:
	process i64
	thread i64
	processId u32
	threadId u32

# a call the system refused: its error code (GetLastError's, or an HRESULT)
pub type SystemError:
	code i64

# the last error of the calling thread
fn lastError():
	SystemError(code = rt.GetLastError())

# A program on a pseudo console. It ends when it goes: the program is stopped if still running.
pub type Pty:
	console i64   # the HPCON
	input i64   # this side's end of the program's keyboard
	output i64   # this side's end of the program's screen
	process i64
	code i64 = -1   # the exit code once it ended

	# What the program wrote since the last read (text and VT sequences), at most max bytes; empty
	# when it wrote nothing.
	fn read(max i64 = 65_536):
		buf u8[] = []
		if PeekNamedPipe(output, 0, 0, 0, out available, 0) and available > 0:
			buf = zeros(i64(available).min(max))
			rt.ReadFile(output, buf, buf.len, out got, 0)
			buf.truncate(i64(got))
		buf

	# The bytes as typed on the program's keyboard.
	fn write(bytes u8[]):
		done = 0
		while done < bytes.len:
			if not rt.WriteFile(input, bytes[done..], bytes.len - done, out written, 0): return
			done += written

	# The pseudo console's new size; the program redraws for it.
	fn resize(cols i64, rows i64):
		ResizePseudoConsole(console, coord(cols, rows))

	# Whether the program has ended (its exit code is then in `code`); a closed one has.
	fn hasEnded():
		if code != -1 or process == 0: return true
		if WaitForSingleObject(process, 0) != 0: return false
		rt.GetExitCodeProcess(process, out exit)
		code = exit
		true

	# Stops the program if it still runs (its code is then 1) and closes the pseudo console.
	fn close():
		if process == 0: return
		if not self.hasEnded():
			TerminateProcess(process, 1)
			WaitForSingleObject(process, 1000)
			self.hasEnded()
		ClosePseudoConsole(console)
		CloseHandle(input)
		CloseHandle(output)
		CloseHandle(process)
		process = 0

	mut fn drop():
		close()

# text as UTF-16 ended by a NUL, as the system's W functions take it
pub fn wide(text str) u16[]:
	room = text.len + 1
	out u16[] = zeros(room)
	n = MultiByteToWideChar(65_001, 0, text.bytes(), text.len, out, room)
	out.truncate(i64(n) + 1)
	out[n] = 0
	out

# a COORD by value: columns in the low half, rows in the high one
fn coord(cols i64, rows i64):
	(cols & 0xFFFF) | ((rows & 0xFFFF) << 16)

# Starts the command line `cmd` in the dir `dir` on a pseudo console of cols by rows; the
# error the system gave when it cannot.
pub fn startPty(cmd str, dir str, cols i64, rows i64) Pty ? SystemError:
	if not CreatePipe(out programIn, out input, 0, 0): return lastError()
	if not CreatePipe(out output, out programOut, 0, 0):
		why = lastError()
		CloseHandle(programIn)
		CloseHandle(input)
		return why
	hr = CreatePseudoConsole(coord(cols, rows), programIn, programOut, 0, out console)
	# the pseudo console holds its own copies of the program's ends
	CloseHandle(programIn)
	CloseHandle(programOut)
	if hr < 0:
		CloseHandle(input)
		CloseHandle(output)
		return SystemError(code = hr)
	pty = Pty(console, input, output, process = 0)
	pty.process = try spawnOn(console, cmd, dir)
	pty

# the process of cmd attached to the pseudo console: its handle
fn spawnOn(console i64, cmd str, dir str) i64 ? SystemError:
	size = 0
	one u8[] = [0]
	InitializeProcThreadAttributeList(one, 1, 0, out size)
	list u8[] = zeros(size)
	if not InitializeProcThreadAttributeList(list, 1, 0, out size): return lastError()
	# PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: the value is the HPCON itself
	if not UpdateProcThreadAttribute(list, 0, 0x2_0016, console, 8, 0, 0):
		why = lastError()
		DeleteProcThreadAttributeList(list)
		return why
	startup = StartupInfoEx(
		reserved = none,
		desktop = none,
		title = none,
		x = 0,
		y = 0,
		xSize = 0,
		ySize = 0,
		xChars = 0,
		yChars = 0,
		fill = 0,
		flags = 0x100,   # STARTF_USESTDHANDLES with none: this process's own are not passed on
		show = 0,
		reserved2 = 0,
		reserved3 = none,
		stdInput = 0,
		stdOutput = 0,
		stdError = 0,
		attributeList = list
	)
	info = ProcessInformation(process = 0, thread = 0, processId = 0, threadId = 0)
	# EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT
	started = CreateProcessW(0, wide(cmd), 0, 0, false, 0x8_0400, 0, wide(dir), startup, info)
	why = lastError()
	DeleteProcThreadAttributeList(list)
	if not started: return why
	CloseHandle(info.thread)
	info.process
