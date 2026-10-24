# Crashes on Linux (sys.zap): a crash is a signal whose handler, on a stack of its own (an
# overflow leaves none), reports it as errors.zap's crashFilter does. The walk of the calls and
# the context's layout are the machine's (arm64/stack.zap, x64/stack.zap).

extern "syscall sigaltstack" fn sysSigaltstack(stack u8[], old i64) i64
extern "syscall rt_sigaction" fn sysRtSigaction(signal i64, action u8[], old i64, size i64) i64
extern "syscall gettid" fn sysGettid() i64

# the signals a crash comes as: SIGILL, SIGTRAP, SIGBUS, SIGFPE, SIGSEGV
crashSignals = [4, 5, 7, 8, 11]

# a signal's line of crashTable: access-violation, stack-overflow (a fault within a page or so
# of sp, past the stack's end), division-by-zero, crash
fn signalRow(signal i64, fault i64, sp i64) i64:
	if signal == 11 or signal == 7: return 1 if fault < sp + 4096 and fault > sp - 65_536 else 0
	2 if signal == 8 else 3

# global slot 6: the thread that reports a crash (its id), 0 while none does
slotCrashing = 6

# A crash, reported by the first thread it meets; another thread's (a parallel step's workers
# crash at once) waits for that report to end the process, and a crash inside the report
# itself ends it at once.
fn crashSignal(signal i64, info i64, context i64):
	_ = info
	me = sysGettid()
	first = __cmpxchg(__globals() + slotCrashing * 8, 0, me)
	if first == me: _ = sysExitGroup(3)
	if first != 0:
		loop:
			sleepMs(1000)
	pc = __ld64(context + contextPc)
	fault = __ld64(context + contextFault)
	at = [pc]
	frames = allocPages(128 * 8)
	n = contextCalls(context, frames, 127)
	for k in 0..n:
		at.push(__ld64(frames + 8 * k) - 1)
	stack = programCalls(at)
	kind = signalRow(signal, fault, __ld64(context + contextSp))
	name = tableField(crashTable, kind, 0)
	inside = "" if functionAt(pc) >= 0 else " inside a function of the system the program called"
	detail = " (accessing address {hex(fault)})" if kind == 0
		else " (signal {signal})" if kind == 3
		else ""
	stopWith(
		name,
		"{tableField(crashTable, kind, 1)}{detail}{inside}{tableField(crashTable, kind, 2)}",
		stack
	)

# the stack a thread's crash handler runs on (an overflow leaves none): 1 MB of its own, set for
# the calling thread, as a new thread starts without one
fn setCrashStack():
	alt = zeroBytes(24)
	alt.setU64le(0, u64(allocPages(1_048_576)))
	alt.setU64le(16, 1_048_576)
	_ = sysSigaltstack(alt, 0)

# the handler set for each crash's signal (crashAction)
fn setCrashFilter() bool:
	setCrashStack()
	action = crashAction(__callback(crashSignal))
	for s in crashSignals:
		_ = sysRtSigaction(s, action, 0, 8)
	true

# the start of a worker thread: it reports a crash like the main thread
fn threadStarted():
	setCrashStack()

# GetModuleHandleA(0): where the executable is
fn getModuleHandleA(name i64) i64:
	_ = name
	imageBase

# the leak notes' table, and the code's place: the ELF's first segment (its headers and code)
fn startLeakNotes():
	gset(slotLeakTable, allocPages(leakSlots * leakWords * 8))
	segment = imageBase + __ld64(imageBase + 32)   # e_phoff: the first program header
	gset(slotCodeStart, __ld64(segment + 16))
	gset(slotCodeEnd, __ld64(segment + 16) + __ld64(segment + 40))
	gset(slotLeakWalk, allocPages(leakWalkRoom * 8))
	setLeakNotes(1)
