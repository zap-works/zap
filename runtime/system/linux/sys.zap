# The runtime's system layer on Linux (`zap build --target android`): each declaration of this
# dir takes the place of the runtime's own of the same name, a Windows function's (an extern fn
# the runtime calls by name) by the one named with its first letter lowered (target.zap). They
# make what the runtime needs of each out of Linux's system calls, declared below with their
# numbers on arm64: an answer from -4095 to -1 is the error's number negated.

extern "syscall getcwd" fn sysGetcwd(buf u8[], size i64) i64
extern "syscall ioctl" fn sysIoctl(fd i64, request i64, arg u8[]) i64
extern "syscall read" fn sysRead(fd i64, buf u8[], n i64) i64
extern "syscall write" fn sysWrite(fd i64, buf u8[], n i64) i64
extern "syscall exit_group" fn sysExitGroup(code i64) i64
extern "syscall nanosleep" fn sysNanosleep(duration u8[], left i64) i64
extern "syscall clock_gettime" fn sysClockGettime(clock i64, time u8[]) i64
extern "syscall munmap" fn sysMunmap(addr i64, size i64) i64
extern "syscall mmap" fn sysMmap(addr i64, size i64, protect i64, flags i64, fd i64, offset i64) i64
extern "syscall mprotect" fn sysMprotect(addr i64, size i64, protect i64) i64
extern "syscall madvise" fn sysMadvise(addr i64, size i64, advice i64) i64

# ---------- errors ----------

# the thread's slot of its last error, past those tlsAlloc gives out
lastErrorSlot = 63

# an answer of a system call: the error's number kept for getLastError when it is one
fn failed(answer i64) bool:
	if answer < 0 and answer > -4096:
		__tlsSet(lastErrorSlot, -answer)
		return true
	false

# GetLastError: the code Windows gives for the last error, which std's fs names (2 a file not
# found, 3 a dir on the way, 5 denied, 32 held), from Linux's number
fn getLastError() i32:
	e = __tlsGet(lastErrorSlot)
	match e:
		2: 2   # ENOENT
		20: 3   # ENOTDIR
		1, 13: 5   # EPERM, EACCES
		16, 26: 32   # EBUSY, ETXTBSY
		17: 183   # EEXIST
		_: i32.wrap(e)   # (another: its own number)

# ---------- memory ----------
# Windows hands out its pages at a multiple of 64 KB, and the runtime's pages count on it (they
# are aligned to their size): a mapping is made 64 KB longer and its ends cut off. Linux unmaps
# by the size, which the page before the mapping keeps (its last word).

pageAlign = 65_536

protectNone = 0

protectReadWrite = 3

# MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE: the memory behind a page is the system's when
# first touched
mapPrivate = 0x4022

# n bytes of new pages at a multiple of 64 KB, with the size in the page before them, protected
# so (0 when there are none)
fn mapPages(n i64, protect i64) i64:
	page = pageBytes()
	size = n.alignUp(page)
	total = size + pageAlign + page
	base = sysMmap(0, total, protectNone, mapPrivate, -1, 0)
	if failed(base): return 0
	p = (base + page).alignUp(pageAlign)
	if p - page > base:
		_ = sysMunmap(base, p - page - base)
	if base + total > p + size:
		_ = sysMunmap(p + size, base + total - p - size)
	_ = sysMprotect(p - page, page, protectReadWrite)
	__st64(p - 8, size)
	if protect != protectNone and failed(sysMprotect(p, size, protect)): return 0
	p

# MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_GROWSDOWN | MAP_STACK: the kernel's RLIMIT_DATA
# charges private writable mappings that are not stacks, so a thread's stack mapped so is not data
mapStackFlags = 0x2_4122

# n bytes of a stack, its lowest page the guard an overflow meets (0 when there is none)
fn mapStack(n i64) i64:
	base = sysMmap(0, n, protectReadWrite, mapStackFlags, -1, 0)
	if failed(base): return 0
	_ = sysMprotect(base, pageBytes(), protectNone)
	base

# n bytes rounded up to whole pages of the kernel's size
fn wholePages(n i64) i64:
	n.alignUp(pageBytes())

fn allocPages(n i64) i64:
	mapPages(n, protectReadWrite)

fn reservePages(n i64) i64:
	mapPages(n, protectNone)

fn commitPages(p i64, n i64) bool:
	not failed(sysMprotect(p, wholePages(n), protectReadWrite))

fn freePages(p i64):
	_ = sysMunmap(p - pageBytes(), __ld64(p - 8) + pageBytes())

# VirtualFree of pages committed (MEM_DECOMMIT, the one kind the runtime gives it): their memory
# given back, the pages reserved again (zero when next committed)
fn virtualFree(addr i64, size i64, kind i64) bool:
	_ = kind
	_ = sysMadvise(addr, size, 4)   # MADV_DONTNEED
	not failed(sysMprotect(addr, size, protectNone))

# VirtualAlloc of new pages (MEM_COMMIT | MEM_RESERVE, the one kind the runtime gives it, for a
# live build): at addr when it is free (0: anywhere), protected as Windows' PAGE_ value says; 0
# when there are none
fn virtualAlloc(addr i64, size i64, kind i64, protect i64) i64:
	_ = kind
	n = wholePages(size)
	p = sysMmap(addr, n, protectionOf(protect), 0x22, -1, 0)   # MAP_PRIVATE | MAP_ANONYMOUS, addr a hint
	if failed(p): return 0
	if addr != 0 and p != addr:
		_ = sysMunmap(p, n)
		return 0
	p

# Linux's protection for a PAGE_ value of Windows'
fn protectionOf(page i64) i64:
	match page:
		2: 1   # PAGE_READONLY: read
		4: 3   # PAGE_READWRITE
		0x20: 5   # PAGE_EXECUTE_READ
		0x40: 7   # PAGE_EXECUTE_READWRITE
		_: 0   # PAGE_NOACCESS

# ---------- the standard streams ----------

# GetStdHandle(-10, -11, -12): the descriptors 0, 1, 2
fn getStdHandle(which i64) i64:
	-10 - which

fn writeSome(h i64, bytes u8[]) i64:
	n = sysWrite(h, bytes, bytes.len)
	-1 if failed(n) else n

fn readSome(h i64, buf u8[], n i64) i64:
	got = sysRead(h, buf, n)
	-1 if failed(got) else got

# a terminal answers TCGETS
fn isConsoleHandle(h i64) bool:
	termios = zeroBytes(64)
	sysIoctl(h, 0x5401, termios) == 0

# ---------- time ----------

# a timespec's nanoseconds
fn nanosOf(time u8[]) i64:
	time.i64le(0) * 1_000_000_000 + time.i64le(8)

# global slot 5: CLOCK_MONOTONIC when the program first read it
slotClockStart = 5

# the nanoseconds of CLOCK_MONOTONIC, which only goes up, since the program's first reading (a
# machine up for months counts past what clockMs may multiply by 1000)
fn counterNow() i64:
	time = zeroBytes(16)
	_ = sysClockGettime(1, time)
	now = nanosOf(time)
	if gv(slotClockStart) == 0:
		_ = __cmpxchg(__globals() + slotClockStart * 8, 0, now - 1)
	now - gv(slotClockStart)

fn counterFrequency() i64:
	1_000_000_000

# Sleep(ms)
fn sleep(ms i64):
	time = zeroBytes(16)
	time.setU64le(0, u64(ms / 1000))
	time.setU64le(8, u64(ms % 1000 * 1_000_000))
	_ = sysNanosleep(time, 0)

# ExitProcess(code): every thread ends
fn exitProcess(code i64):
	_ = sysExitGroup(code)

# Linux's number of the thread's last error (std's modules map it to the codes they name)
fn lastErrno() i64:
	__tlsGet(lastErrorSlot)

pub fn onWindows() bool:
	false
