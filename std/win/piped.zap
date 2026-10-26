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
extern fn LocalAlloc(flags i64, size i64) i64
extern fn LocalFree(memory i64) i64
extern fn QueryInformationJobObject(job i64, kind i64, info u8[], size i64, returned i64) bool

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
		readPipe(output, max)

	# The bytes written to the program's stdin; whether they all went (not after closeInput).
	fn write(bytes u8[]):
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

	# the processor seconds the program and what it started have spent, and the most memory they
	# held at once, in bytes
	fn usage():
		times u8[] = zeros(48)
		limits u8[] = zeros(144)
		QueryInformationJobObject(job, 1, times, times.len, 0)
		QueryInformationJobObject(job, 9, limits, limits.len, 0)
		((times.i64le(0) + times.i64le(8)) / 10_000_000.0, limits.i64le(136))

	mut fn drop():
		close()

# The environment variable gone from this program, and so from the programs it starts.
pub fn unsetVariable(name str) bool:
	SetEnvironmentVariableW(wide(name), 0)

# Starts the command line `cmd` (found on PATH) in the dir `dir` with pipes for its standard
# streams, stderr into stdout's; the error the system gave when it cannot. A memory cap (bytes)
# and a processor cap (a share of the machine, 0 to 1) bound the program and what it starts, 0 for
# none: past the memory its allocations fail, and its threads wait past the processor share.
pub fn startPiped(cmd str, dir str, memoryCap i64 = 0, cpuCap f64 = 0.0) Piped ? SystemError:
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
	limits.setU32le(16, 0x2000 | (0x200 if memoryCap > 0 else 0))
	limits.setU64le(120, u64(memoryCap))
	SetInformationJobObject(job, 9, limits, limits.len)
	if cpuCap > 0.0:
		# JOBOBJECT_CPU_RATE_CONTROL_INFORMATION: enabled, a hard cap, in hundredths of a percent
		rate u8[] = zeros(8)
		rate.setU32le(0, 0x5)
		rate.setU32le(4, i64(cpuCap * 10_000.0).max(1).min(10_000))
		SetInformationJobObject(job, 15, rate, rate.len)
	# PROC_THREAD_ATTRIBUTE_HANDLE_LIST: the program inherits its pipes' ends and nothing else (not
	# this program's sockets or files)
	size = 0
	one u8[] = [0]
	InitializeProcThreadAttributeList(one, 1, 0, out size)
	list u8[] = zeros(size)
	InitializeProcThreadAttributeList(list, 1, 0, out size)
	handles = LocalAlloc(0, 16)
	memoryAt(handles, 16).write(0, [programIn, programOut])
	UpdateProcThreadAttribute(list, 0, 0x2_0002, handles, 16, 0, 0)
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
		flags = 0x100,   # STARTF_USESTDHANDLES
		show = 0,
		reserved2 = 0,
		reserved3 = none,
		stdInput = programIn,
		stdOutput = programOut,
		stdError = programOut,
		attributeList = list
	)
	info = ProcessInformation(process = 0, thread = 0, processId = 0, threadId = 0)
	# CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT | EXTENDED_STARTUPINFO_PRESENT |
	# CREATE_NO_WINDOW: in the job before it runs
	started = CreateProcessW(0, wide(cmd), 0, 0, true, 0x808_0404, 0, wide(dir), startup, info)
	why = lastError()
	DeleteProcThreadAttributeList(list)
	LocalFree(handles)
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
