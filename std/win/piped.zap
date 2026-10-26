# Programs run with pipes for their standard streams, without a window or a console: what they
# write to stdout and stderr is read as it comes, without waiting, and what is written goes to
# their stdin, as a daemon drives a program that speaks a line protocol. The program and every
# program it starts are one job: closing it stops them all.

extern fn SetHandleInformation(h i64, mask i64, flags i64) bool
extern fn CreateJobObjectW(attrs i64, name i64) i64
extern fn SetInformationJobObject(job i64, kind i64, info u8[], size i64) bool
extern fn AssignProcessToJobObject(job i64, process i64) bool
extern fn TerminateJobObject(job i64, code i64) bool
extern fn ResumeThread(thread i64) u32
extern fn SetEnvironmentVariableW(name u16[], value i64) bool

# A program whose stdin, stdout and stderr are pipes. It ends when it goes: the program and what
# it started are stopped if still running.
pub type Piped:
	input i64   # this side's end of the program's stdin, 0 once closed
	output i64   # this side's end of its stdout and stderr
	process i64
	job i64
	code i64 = -1   # the exit code once it ended

	# What the program wrote since the last read, at most max bytes; empty when it wrote nothing.
	fn read(max i64 = 65_536):
		buf u8[] = []
		if PeekNamedPipe(output, 0, 0, 0, out available, 0) and available > 0:
			buf = zeros(i64(available).min(max))
			rt.ReadFile(output, buf, buf.len, out got, 0)
			buf.truncate(i64(got))
		buf

	# The bytes written to the program's stdin; whether they all went (not after closeInput).
	fn write(bytes u8[]) bool:
		done = 0
		while done < bytes.len:
			if input == 0 or
				not rt.WriteFile(input, bytes[done..], bytes.len - done, out written, 0):
				return false
			done += written
		true

	# The program's stdin closed: it reads its end.
	fn closeInput():
		if input == 0: return
		CloseHandle(input)
		input = 0

	# Whether the program has ended (its exit code is then in `code`); a closed one has.
	fn hasEnded():
		if code != -1 or process == 0: return true
		if WaitForSingleObject(process, 0) != 0: return false
		rt.GetExitCodeProcess(process, out exit)
		code = exit
		true

	# Stops the program and every program it started if still running (its code is then 1).
	fn close():
		if process == 0: return
		if not self.hasEnded():
			TerminateJobObject(job, 1)
			WaitForSingleObject(process, 1000)
			self.hasEnded()
		self.closeInput()
		CloseHandle(output)
		CloseHandle(process)
		CloseHandle(job)
		process = 0

	mut fn drop():
		close()

# The environment variable gone from this program, and so from the programs it starts.
pub fn unsetVariable(name str):
	SetEnvironmentVariableW(wide(name), 0)

# Starts the command line `cmd` (found on PATH) in the dir `dir` with pipes for its standard
# streams, stderr into stdout's; the error the system gave when it cannot.
pub fn startPiped(cmd str, dir str) Piped ? SystemError:
	if not CreatePipe(out programIn, out input, 0, 0): return lastError()
	if not CreatePipe(out output, out programOut, 0, 0):
		why = lastError()
		CloseHandle(programIn)
		CloseHandle(input)
		return why
	# HANDLE_FLAG_INHERIT on the program's ends only
	SetHandleInformation(programIn, 1, 1)
	SetHandleInformation(programOut, 1, 1)
	job = CreateJobObjectW(0, 0)
	# JOBOBJECT_EXTENDED_LIMIT_INFORMATION with JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
	limits u8[] = zeros(144)
	limits.setU32le(16, 0x2000)
	SetInformationJobObject(job, 9, limits, limits.len)
	noAttributes u8[] = []
	startup = StartupInfoEx(
		cb = 104,
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
		flags = 0x100,   # STARTF_USESTDHANDLES
		show = 0,
		reserved2 = 0,
		reserved3 = none,
		stdInput = programIn,
		stdOutput = programOut,
		stdError = programOut,
		attributeList = noAttributes
	)
	info = ProcessInformation(process = 0, thread = 0, processId = 0, threadId = 0)
	# CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW: in the job before it runs
	started = CreateProcessW(0, wide(cmd), 0, 0, true, 0x800_0404, 0, wide(dir), startup, info)
	why = lastError()
	CloseHandle(programIn)
	CloseHandle(programOut)
	if not started:
		CloseHandle(input)
		CloseHandle(output)
		CloseHandle(job)
		return why
	AssignProcessToJobObject(job, info.process)
	ResumeThread(info.thread)
	CloseHandle(info.thread)
	Piped(input, output, process = info.process, job)
