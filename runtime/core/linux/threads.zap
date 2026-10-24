# Threads on Linux (sys.zap): a thread is a clone sharing the process, with a stack and slots
# of its own (tpidr_el0 points at them: what __tlsGet reads); Windows' events and semaphores the
# runtime waits on are words a futex sleeps on, in a record whose address is their handle.

extern "syscall futex" fn sysFutex(
	word i64,
	op i64,
	value i64,
	timeout u8[],
	other i64,
	more i64
) i64
extern "syscall sched_getaffinity" fn sysSchedGetaffinity(pid i64, size i64, mask u8[]) i64
extern "syscall sched_yield" fn sysSchedYield() i64

# global slot 4: the next of the thread's slots tlsAlloc gives out (each thread has 64)
slotTlsNext = 4

threadSlots = 64

# a thread's stack: twice what Windows reserves for each of the executable's (x64.zap's PE
# header), as a call keeps 16 bytes (its frame record) where x64's keeps 8 (the return address)
threadStack = 134_217_728

# the top of a stack for the main thread, of a thread's size (Linux gives it 8 MB): the start
# moves to it
fn mainStack() i64:
	base = mapStack(threadStack)
	if base == 0: _ = sysExitGroup(1)
	base + threadStack

fn tlsAlloc() i32:
	i32(__xadd(__globals() + slotTlsNext * 8, 1))

# CLONE_VM | FS | FILES | SIGHAND | THREAD | SYSVSEM | SETTLS: a thread of the process
cloneThread = 0xD_0F00

# CreateThread(0, 0, the entry, the record, 0, 0): a thread that runs the record's closure, its
# stack's top a frame record that returns into the entry (a64sys.zap's a64ThreadEntry) with the
# record's address above it; 0 when it cannot start
fn createThread(security i64, stack i64, start i64, param i64, flags i64, id i64) i64:
	_ = security + stack + flags + id
	base = mapStack(threadStack)   # its lowest page the guard an overflow meets
	slots = allocPages(threadSlots * 8)
	if base == 0 or slots == 0: return 0
	top = base + threadStack - 32
	__st64(top, 0)
	__st64(top + 8, start)
	__st64(top + 16, param)
	if failed(sysClone(cloneThread, top, 0, slots, 0)): return 0
	syncNew(syncThread, 0)

# ---------- events and semaphores ----------
# A record: its kind, then the word the futex sleeps on (an event's 1 when set, a semaphore's
# count), on a page of its own: a handle the runtime never closes (a pool's semaphore) is the
# system's on Windows, not a block of the program's heap.

syncEvent = 1

syncSemaphore = 2

syncThread = 3

fn syncNew(kind i64, count i64) i64:
	rec = allocPages(16)
	__st64(rec, kind)
	__st64(rec + 8, count)
	rec

# the handle of an event or a semaphore freed (a thread's handle names nothing to free but it)
fn closeSync(h i64) bool:
	freePages(h)
	true

# CreateEventA(0, false, false, 0): an event that wakes one waiter, then is clear again
fn createEventA(security i64, manual bool, initial bool, name i64) i64:
	_ = security + name
	_ = manual
	syncNew(syncEvent, 1 if initial else 0)

fn setEvent(h i64) bool:
	_ = __cmpxchg(h + 8, 0, 1)
	_ = sysFutex(h + 8, 129, 1, [], 0, 0)   # FUTEX_WAKE | FUTEX_PRIVATE_FLAG
	true

fn createSemaphoreA(security i64, initial i64, most i64, name i64) i64:
	_ = security + most + name
	syncNew(syncSemaphore, initial)

fn releaseSemaphore(h i64, count i64, previous i64) bool:
	_ = previous
	_ = __xadd(h + 8, count)
	_ = sysFutex(h + 8, 129, count.min(2_147_483_647), [], 0, 0)
	true

# whether the record's word was taken: an event cleared, a semaphore counted down
fn syncTake(h i64) bool:
	word = h + 8
	c = __ld64(word)
	if __ld64(h) == syncEvent: return c == 1 and __cmpxchg(word, 1, 0) == 1
	c > 0 and __cmpxchg(word, c, c - 1) == c

# a futex wait's timeout of ms milliseconds (a timespec), none for -1 (no end)
fn futexTimeout(ms i64) u8[]:
	timeout u8[] = []
	if ms >= 0:
		timeout = zeroBytes(16)
		timeout.setU64le(0, u64(ms / 1000))
		timeout.setU64le(8, u64(ms % 1000 * 1_000_000))
	timeout

# WaitForSingleObject on an event or a semaphore: 0 once taken, 258 (WAIT_TIMEOUT) when ms (-1:
# no end) passed first
fn waitForSingleObject(h i64, ms i64) i32:
	timeout = futexTimeout(ms)
	loop:
		if syncTake(h): return 0
		if ms == 0: return 258
		r = sysFutex(h + 8, 128, 0, timeout, 0, 0)   # FUTEX_WAIT | FUTEX_PRIVATE_FLAG, while 0
		if r == -110 and not syncTake(h): return 258   # ETIMEDOUT
	0

fn switchToThread() bool:
	_ = sysSchedYield()
	true

# the processors the process may run on (at least 1)
pub fn cpuCount() i64:
	mask = zeroBytes(128)
	n = sysSchedGetaffinity(0, 128, mask)
	(0..n.max(0)).sum(mask[it].bitCount()).max(1)

# ---------- locks and waits on a word ----------
# Windows' SRW lock and wait on an address as the channels use them, over a futex: the lock a word
# (0 free, 1 held, 2 held with a thread asleep on it).

fn acquireSRWLockExclusive(lock i64):
	c = __cmpxchg(lock, 0, 1)
	while c != 0:
		if c == 2 or __cmpxchg(lock, 1, 2) != 0:
			_ = sysFutex(lock, 128, 2, [], 0, 0)   # FUTEX_WAIT | FUTEX_PRIVATE_FLAG, while 2
		c = __cmpxchg(lock, 0, 2)

fn releaseSRWLockExclusive(lock i64):
	if __xadd(lock, -1) != 1:   # it was 2: one asleep on it is woken
		__st64(lock, fenced(0))
		_ = sysFutex(lock, 129, 1, [], 0, 0)   # FUTEX_WAKE | FUTEX_PRIVATE_FLAG

# asleep on the 8-byte word at address while it holds what compare points at (its low half, as the
# futex compares), for ms milliseconds at most (-1: no end); false when the time passed first
fn waitOnAddress(address i64, compare i64, size i64, ms i64) bool:
	_ = size
	r = sysFutex(address, 128, __ld64(compare) & 4_294_967_295, futexTimeout(ms), 0, 0)
	r != -110   # ETIMEDOUT

fn wakeByAddressAll(address i64):
	_ = sysFutex(address, 129, 2_147_483_647, [], 0, 0)
