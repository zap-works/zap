# The functions of the operating system the runtime uses, declared as they are. An `extern fn`
# is the one place where the compiler takes a signature on trust: everything that crosses is a
# plain word (a handle, a count, a flag) or a buffer: a `u8[]` or `str` parameter hands
# the system the address of the bytes (a window selects a tail), and an `out` parameter is where
# the system writes a number back. Handles and addresses from the system are
# i64; a DWORD parameter is declared i64 too (the system reads the low 32 bits); a BOOL result
# is a bool, an int result an i32.

extern fn GetStdHandle(which i64) i64
extern fn WriteFile(h i64, buf u8[], n i64, out written u32, overlapped i64) bool
extern fn ReadFile(h i64, buf u8[], n i64, out got u32, overlapped i64) bool
extern fn ExitProcess(code i64)
extern fn VirtualAlloc(addr i64, size i64, kind i64, protect i64) i64
extern fn VirtualFree(addr i64, size i64, kind i64) bool
extern fn CreateFileA(
	path u8[],
	access i64,
	share i64,
	security i64,
	disposition i64,
	attrs i64,
	template i64
) i64
extern fn CloseHandle(h i64) bool
extern fn GetLastError() i32
extern fn GetFileSizeEx(h i64, out size i64) bool
extern fn SetFilePointerEx(h i64, distance i64, out position i64, method i64) bool
extern fn GetFileType(h i64) i32
extern fn CreateFileMappingA(h i64, attrs i64, protect i64, sizeHigh i64, sizeLow i64, name i64) i64
extern fn MapViewOfFile(mapping i64, access i64, offHigh i64, offLow i64, size i64) i64
extern fn DeleteFileA(path u8[]) bool
extern fn MoveFileExA(from u8[], to u8[], flags i64) bool
extern fn GetCurrentProcessId() i64
extern fn GetFileAttributesA(path u8[]) i32
extern fn GetFileAttributesExA(path u8[], level i64, info u8[]) bool
extern fn CreateDirectoryA(path u8[], security i64) bool
extern fn RemoveDirectoryA(path u8[]) bool
extern fn FindFirstFileA(pattern u8[], found u8[]) i64
extern fn FindNextFileA(h i64, found u8[]) bool
extern fn FindClose(h i64) bool
extern fn GetCommandLineA() i64
extern fn GetEnvironmentVariableA(name u8[], buf u8[], size i64) i32
extern fn SetEnvironmentVariableA(name u8[], value u8[]) bool
extern fn GetModuleFileNameA(module i64, buf u8[], size i64) i32
extern fn GetCurrentDirectoryA(size i64, buf u8[]) i32
extern fn GetConsoleMode(h i64, out mode u32) bool
extern fn Sleep(ms i64)
extern fn QueryPerformanceCounter(out count i64) bool
extern fn QueryPerformanceFrequency(out perSecond i64) bool
extern fn K32GetProcessMemoryInfo(process i64, counters u8[], size i64) bool
extern fn QueryProcessCycleTime(process i64, out cycles u64) bool
extern fn GetProcessTimes(
	process i64,
	creation u8[],
	exit u8[],
	kernel u8[],
	user u8[]
) bool
extern fn GetModuleHandleA(name i64) i64
extern fn VirtualQuery(address i64, info u8[], size i64) i64
extern fn CreateProcessA(
	app i64,
	cmd u8[],
	procAttrs i64,
	threadAttrs i64,
	inherit bool,
	flags i64,
	env i64,
	dir i64,
	startup u8[],
	info u8[]
) bool
extern fn WaitForSingleObject(h i64, ms i64) i32
extern fn CreatePipe(out read i64, out write i64, security i64, size i64) bool
extern fn SetHandleInformation(h i64, mask i64, flags i64) bool
extern fn GetEnvironmentStringsA() i64
extern fn FreeEnvironmentStringsA(block i64) bool
extern fn GetExitCodeProcess(h i64, out code u32) bool
extern fn CreateThread(security i64, stack i64, start i64, param i64, flags i64, id i64) i64
extern fn TlsAlloc() i32
extern fn CreateEventA(security i64, manual bool, initial bool, name i64) i64
extern fn SetEvent(h i64) bool
extern fn SwitchToThread() bool
extern fn GetCurrentThreadId() i64
extern fn CreateSemaphoreA(security i64, initial i64, most i64, name i64) i64
extern fn ReleaseSemaphore(h i64, count i64, previous i64) bool
extern fn AcquireSRWLockExclusive(lock i64)
extern fn ReleaseSRWLockExclusive(lock i64)
extern "kernelbase.dll" fn WaitOnAddress(address i64, compare i64, size i64, ms i64) bool
extern "kernelbase.dll" fn WakeByAddressAll(address i64)

# ---------- the calls that answer through a pointer ----------

# bytes written to h from the bytes, or -1 when the call failed
fn writeSome(h i64, bytes u8[]) i64:
	if not WriteFile(h, bytes, bytes.len, out written, 0): return -1
	i64(written)

# bytes read from h into the first n bytes of buf (0 at the end of the data), or -1 when the
# call failed; buf must have room for n
fn readSome(h i64, buf u8[], n i64) i64:
	if not ReadFile(h, buf, n, out got, 0): return -1
	i64(got)

# the bytes of an open file not read yet (its size past the current position), 0 when the
# handle has no size (see fileSize)
fn fileLeft(h i64) i64:
	size = fileSize(h)
	if size == 0 or not SetFilePointerEx(h, 0, out at, 1):   # FILE_CURRENT
		return size
	(size - at).max(0)

# the size of an open file, 0 when the handle has none (a pipe, a console: GetFileSizeEx may
# give a pipe the bytes waiting in it, so only a disk file, FILE_TYPE_DISK, has a size)
fn fileSize(h i64) i64:
	if GetFileType(h) != 1 or not GetFileSizeEx(h, out size): return 0
	size

# the processor's counter, which only goes up, and how many counts make a second
fn counterNow() i64:
	_ = QueryPerformanceCounter(out count)
	count

fn counterFrequency() i64:
	_ = QueryPerformanceFrequency(out perSecond)
	perSecond

fn exitCodeOf(h i64) i64:
	_ = GetExitCodeProcess(h, out code)
	i64(code)

fn isConsoleHandle(h i64) bool:
	GetConsoleMode(h, out _)

# n bytes rounded up to whole system pages (4 KB)
fn wholePages(n i64) i64:
	n.alignUp(4096)

# pages from the system, zeroed (MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE)
fn allocPages(n i64) i64:
	VirtualAlloc(0, n, 12_288, 4)

# address space for n bytes, none of it committed yet (MEM_RESERVE, PAGE_NOACCESS); 0 when
# there is none
fn reservePages(n i64) i64:
	VirtualAlloc(0, n, 8192, 1)

# reservePages' address space taken from the top (MEM_TOP_DOWN), clear of the low addresses a
# program may reserve at its own (std/vmem)
fn reserveHighPages(n i64) i64:
	VirtualAlloc(0, n, 0x10_2000, 1)

# address space for n bytes at `at` (a multiple of 64 KB), none of it committed yet (MEM_RESERVE,
# PAGE_NOACCESS); false when some of it is taken
fn reservePagesAt(at i64, n i64) bool:
	VirtualAlloc(at, n, 8192, 1) == at

# the committed pages of [p, p + n) given back, reserved again: zero when next committed
fn decommitPages(p i64, n i64):
	_ = VirtualFree(p, n, 16_384)   # MEM_DECOMMIT

# the first n bytes of a reservation committed (MEM_COMMIT, PAGE_READWRITE): zeroed when new
fn commitPages(p i64, n i64) bool:
	VirtualAlloc(p, n, 4096, 4) != 0

fn freePages(p i64):
	VirtualFree(p, 0, 32_768)   # MEM_RELEASE

# n zero bytes, for the system to fill
fn zeroBytes(n i64) u8[]:
	zero u8 = 0
	fill(n, zero)

# the bytes of s with a NUL after them, for the system calls that take C strings
fn cstr(s str) u8[]:
	b u8[] = []
	b.extend(s.bytes())
	b.push(0)
	b

# the bytes of a NUL-terminated string the system handed back at address p
fn cBytes(p i64) u8[]:
	b u8[] = []
	i i64 = 0
	while __ld8(p + i) != 0:
		b.push(u8(__ld8(p + i)))
		i += 1
	b

# v, where the runtime counts on x64's order of loads and stores (a lock given back, a result
# published, a flag read before what it guards): x64 keeps that order by itself, AArch64 is given
# a barrier, and on both the compiler moves no load or store across it nor reads a value again
# from a load before it (a flag looked at twice)
fn fenced(v i64) i64:
	__fence(v)

# whether the program runs on Windows (runtime/system/linux/ says no): what a test of Windows' own tools
# asks before it starts them
pub fn onWindows() bool:
	true
