# The process on Linux (sys.zap): the arguments and the environment the kernel put on the
# stack at the start (global slot 2 keeps where: argc, the argument pointers, 0, the
# environment's, 0), the variables a program sets, and the processes it starts (by sh, or by
# execve for Process.output).

extern "syscall waitid" fn sysWaitid(kind i64, id i64, info u8[], options i64, usage i64) i64
extern "syscall clone" fn sysClone(flags i64, stack i64, parentTid i64, tls i64, childTid i64) i64
extern "syscall execve" fn sysExecve(path u8[], argv i64, envp i64) i64
extern "syscall wait4" fn sysWait4(pid i64, status u8[], options i64, usage i64) i64
extern "syscall pipe2" fn sysPipe2(fds u8[], flags i64) i64
extern "syscall dup3" fn sysDup3(from i64, to i64, flags i64) i64
extern "syscall chdir" fn sysChdir(path u8[]) i64
extern "syscall memfd_create" fn sysMemfdCreate(name u8[], flags i64) i64

slotStackBase = 2

# the address of the i-th word the kernel left on the stack
fn startWord(i i64) i64:
	__ld64(gv(slotStackBase) + 8 * i)

# the arguments after the program's name
fn commandLine() str[]:
	(1..startWord(0)).map(str(cBytes(startWord(1 + it))))

# the variables set by the program, "NAME=value", the latest last
mut envSet str[] = []

# the address of the environment's first pointer
fn environmentStart() i64:
	gv(slotStackBase) + 8 * (startWord(0) + 2)

# slot 9: the kernel's page size once read
slotPageBytes = 9

# The kernel's page size: 4 KB, or 16 KB or 64 KB on some (an Android of 16 KB pages), its
# auxiliary vector's AT_PAGESZ, the pairs after the environment's last pointer
fn pageBytes() i64:
	known = gv(slotPageBytes)
	if known != 0: return known
	at = environmentStart()
	while __ld64(at) != 0:
		at += 8
	at += 8
	size = 4096
	while __ld64(at) != 0:
		if __ld64(at) == 6: size = __ld64(at + 8)
		at += 16
	gset(slotPageBytes, size)
	size

# the value of the variable, none when it is not set
fn envValue(name str) str?:
	prefix = "{name}="
	for i in 0..envSet.len:
		v = envSet[len - 1 - i]
		if v.startsWith(prefix): return v[prefix.len..].copy()
	p = environmentStart()
	while __ld64(p) != 0:
		v = str(cBytes(__ld64(p)))
		if v.startsWith(prefix): return v[prefix.len..].copy()
		p += 8
	none

# GetEnvironmentVariableA: the value and its NUL in buf when they fit (its length), else the
# room they need; 0 when it is not set
fn getEnvironmentVariableA(name u8[], mut buf u8[], size i64) i32:
	value = envValue(str(name[..len - 1].copy())) ?? return 0
	if value.len + 1 > size: return i32(value.len + 1)
	for i, b in value.bytes():
		buf[i] = b
	buf[value.len] = 0
	i32(value.len)

fn setEnvironmentVariableA(name u8[], value u8[]) bool:
	envSet.push(str(name[..len - 1].copy()) + "=" + str(value[..len - 1].copy()))
	true

# the environment a process started gets: the program's, as it set it, and vars ("NAME=value")
fn childEnvironment(vars str[]) str[]:
	all str[] = []
	p = environmentStart()
	while __ld64(p) != 0:
		all.push(str(cBytes(__ld64(p))))
		p += 8
	all.extend(envSet)
	all.extend(vars)
	latestVariables(all)

# The C strings in one block of pages, then the pointers to each and 0 at the end (argv, envp):
# the block and where its pointers start
fn cStringArray(items str[]) (i64, i64):
	room = items.sum(it.len + 1) + 8 * (items.len + 1)
	block = allocPages(room)
	at = block
	ptrs = block + room - 8 * (items.len + 1)
	ptrStart = ptrs
	for s in items:
		__memcpy(at, sPtr(s), s.len)
		__st8(at + s.len, 0)
		__st64(ptrs, at)
		ptrs += 8
		at += s.len + 1
	__st64(ptrs, 0)
	(block, ptrStart)

# Process.start(cmd): sh runs the command line, not waited for (handle -1 when it cannot start):
# /bin/sh, or Android's /system/bin/sh
pub fn processStart(cmd str) Process:
	flushStdout()   # our output stays ahead of the child's
	shell = cstr("/bin/sh" if fileExists("/bin/sh") else "/system/bin/sh")
	argBlock, argv = cStringArray(["sh", "-c", cmd])
	envBlock, envp = cStringArray(childEnvironment([]))
	pid = sysClone(17, 0, 0, 0, 0)   # SIGCHLD: a fork
	if pid == 0:
		_ = sysExecve(shell, argv, envp)
		_ = sysExitGroup(127)
	freePages(argBlock)
	freePages(envBlock)
	if failed(pid): return Process(handle = -1)
	Process(handle = pid)

pub fn shellLine(line str) str:
	line.copy()

# Process.output(cmd) (io.zap's): the program found on the PATH and started by execve, its stdin
# a file in memory that holds input, its stdout and stderr one pipe read to its end
pub fn processOutput(
	cmd str = "",
	input str = "",
	vars str[] = [],
	dir str = "",
	argv str[] = []
) Process:
	flushStdout()
	words = commandWords(cmd.bytes()) if argv.isEmpty else argv.copy()
	if words.isEmpty: return Process(handle = -1)
	found = programPath(words[0]) ?? return Process(handle = -1)
	program = cstr(found if found.startsWith("/") or dir == "" else "{currentDir()}/{found}")
	there = cstr(dir)
	given = sysMemfdCreate(cstr("input"), 1)   # MFD_CLOEXEC
	writeRaw(given, input.bytes())
	_ = sysLseek(given, 0, 0)
	ends = zeroBytes(8)
	_ = sysPipe2(ends, 0x8_0000)   # O_CLOEXEC: no other program started gets them
	reader = i64(ends.u32le(0))
	writer = i64(ends.u32le(4))
	argBlock, argv = cStringArray(words)
	envBlock, envp = cStringArray(childEnvironment(vars))
	pid = sysClone(17, 0, 0, 0, 0)   # SIGCHLD: a fork
	if pid == 0:
		if dir != "" and failed(sysChdir(there)): _ = sysExitGroup(127)
		_ = sysDup3(given, 0, 0)
		_ = sysDup3(writer, 1, 0)
		_ = sysDup3(writer, 2, 0)
		_ = sysExecve(program, argv, envp)
		_ = sysExitGroup(127)
	freePages(argBlock)
	freePages(envBlock)
	_ = sysClose(given)
	_ = sysClose(writer)   # the pipe ends when the program and its children close theirs
	p = Process(handle = -1 if failed(pid) else pid)
	text u8[] = []
	readRest(reader, text)
	_ = sysClose(reader)
	p.out = str(move text)
	_ = p.wait()
	p

# the file a program named so runs: the name itself when it holds a /, else the first of the
# PATH's dirs that has it; none when there is none
fn programPath(name str) str?:
	if name.contains("/"): return name.copy() if fileExists(name) else none
	for dir in (envValue("PATH") ?? "/usr/bin:/bin").split(pathListSeparator()):
		full = "{dir}/{name}"
		if fileExists(full): return full
	none

# whether the process has ended, asked without taking its exit (WEXITED | WNOHANG | WNOWAIT)
fn processDone(p Process) bool:
	if p.handle == -1 or p.code != -1: return true
	info = zeroBytes(128)
	sysWaitid(1, p.handle, info, 0x100_0005, 0) == 0 and info.u32le(16) != 0

fn processWait(mut p Process) i64:
	if p.handle == -1 or p.code != -1: return p.code
	status = zeroBytes(8)
	_ = sysWait4(p.handle, status, 0, 0)
	s = i64(status.u32le(0))
	p.code = (s >> 8) & 255 if s & 127 == 0 else 128 + (s & 127)
	p.code
