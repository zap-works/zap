# The process's use of memory and processors on Linux (sys.zap, coreusage.zap).

extern "syscall getrusage" fn sysGetrusage(who i64, usage u8[]) i64
extern "syscall getpid" fn sysGetpid() i64

# the process's rusage (RUSAGE_SELF)
fn usageOf() u8[]:
	usage = zeroBytes(144)
	_ = sysGetrusage(0, usage)
	usage

# coreusage.zap's PROCESS_MEMORY_COUNTERS words: 8 the peak (ru_maxrss), 56 what it holds now
# (the resident pages of /proc/self/statm)
fn processCounter(off i64) i64:
	if off == 8: return usageOf().i64le(32) * 1024
	h = openForRead("/proc/self/statm")   # (its size reads 0: read, not sized)
	if h == -1: return 0
	buf = zeroBytes(256)
	n = readSome(h, buf, 256)
	_ = sysClose(h)
	buf.truncate(n.max(0))
	words = str(move buf).split(" ")
	(i64.parse(words[1]) ?? 0) * pageBytes() if words.len > 1 else 0

pub fn processId() i64:
	sysGetpid()

# the processor time of the process, in nanoseconds (CLOCK_PROCESS_CPUTIME_ID): its cycles at a
# nominal 1 GHz
pub fn processorCycles() i64:
	time = zeroBytes(16)
	_ = sysClockGettime(2, time)
	nanosOf(time)

# the calling thread's processor time in nanoseconds (CLOCK_THREAD_CPUTIME_ID), as processorCycles
pub fn threadCycles() i64:
	time = zeroBytes(16)
	_ = sysClockGettime(3, time)
	nanosOf(time)

pub fn processorSeconds() f64:
	usage = usageOf()
	f64(usage.i64le(0) + usage.i64le(16)) + f64(usage.i64le(8) + usage.i64le(24)) / 1_000_000.0
