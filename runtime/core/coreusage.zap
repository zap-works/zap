# The runtime's memory use: statistics and list growth (core.zap).

# ZAP_RUN=memstats: the allocation and free counts at exit (equal when nothing leaked), read
# before the formatting below allocates, and the most memory the process ever held
fn memStats():
	allocs = heapSum(16)
	frees = heapSum(24)
	if leakNotesOn():
		reportLeaks()
	if memstatsWord().on():
		writeRaw(
			stderrHandle,
			"zap memstats: allocations={allocs} frees={frees} peak={peakMemory() / 1048576} MB\n".bytes()
		)

# the peak working set of the process, in bytes (PROCESS_MEMORY_COUNTERS.PeakWorkingSetSize)
pub fn peakMemory() i64:
	processCounter(8)

# the memory the process holds now, in bytes: what it took from the system and has not given
# back (PROCESS_MEMORY_COUNTERS.PagefileUsage, its private bytes)
pub fn memoryCommitted() i64:
	processCounter(56)

# the processor cycles every thread of the process has spent so far (QueryProcessCycleTime), 0
# when the system does not tell
pub fn processorCycles() i64:
	cycles u64 = 0
	if not QueryProcessCycleTime(-1, out cycles): return 0
	i64(cycles)

# the processor cycles the calling thread has spent so far (QueryThreadCycleTime), 0 when the
# system does not tell: what a stretch of its work costs, which other processes move little
pub fn threadCycles() i64:
	cycles u64 = 0
	if not QueryThreadCycleTime(-2, out cycles): return 0   # (-2: the calling thread)
	i64(cycles)

# this process's id, as the system names it: a name no process running beside it has
pub fn processId() i64:
	GetCurrentProcessId()

# the processor seconds every thread of the process has spent so far, kernel and user (0 when
# the system does not tell)
pub fn processorSeconds() f64:
	creation = zeroBytes(8)
	exit = zeroBytes(8)
	kernel = zeroBytes(8)
	user = zeroBytes(8)
	if not GetProcessTimes(-1, creation, exit, kernel, user): return 0.0
	(i64(kernel.loadWord(0)) + i64(user.loadWord(0))) / 10000000.0

# a word of the process's PROCESS_MEMORY_COUNTERS, 0 when the system does not tell
fn processCounter(off i64) i64:
	counters = zeroBytes(72)
	counters[0] = 72
	if not K32GetProcessMemoryInfo(-1, counters, 72): return 0
	i64(counters.loadWord(off))

# a counter of every thread's heap summed (16: allocations, 24: frees): a block may be freed by
# another thread than the one that allocated it, so only the sum is exact
fn heapSum(off i64) i64:
	sum i64 = 0
	h = gv(slotHeaps)
	while h != 0:
		sum += __ld64(h + off)
		h = __ld64(h + 2096)
	sum

# the blocks allocated and not freed yet
pub fn liveBlocks() i64:
	heapSum(16) - heapSum(24)

# the blocks allocated since the program started (what a stretch of code allocates is the
# difference of two readings)
pub fn allocations() i64:
	heapSum(16)

# ---------- raw list support (the backend builds list literals through these) ----------
# l is the address of a { ptr, length, cap } header; elements are `stride` bytes each.

# the backend builds list literals through these; l is a list header's address
fn listGrowRaw(l i64, need i64, stride i64):
	cap = __ld64(l + 16)
	if need <= cap: return
	newCap = cap * 2 if cap > 0 else (32 / stride).max(2 if stride <= 1024 else 1)   # a first room of 32 bytes or two elements
	# a big block grows in place (bigGrow) without a copy: by a quarter, not twice what it
	# commits
	if cap * stride >= bigGrowQuarter and (__ld64(l) & (pageSize - 1)) == bigHead:
		newCap = cap + cap / 4
	while newCap < need:
		newCap *= 2
	listGrowTo(l, newCap, stride)

# listGrowRaw for a list made to a known size (a copy, a literal, a map's output): exactly need
# elements when that is more than double (bytes one more: the NUL of the str they may become)
fn listGrowExact(l i64, need i64, stride i64):
	if need > __ld64(l + 16):
		listGrowTo(l, (need + 1 if stride == 1 else need).max(__ld64(l + 16) * 2), stride)

# the room of the list at l made newCap elements (more than it has)
fn listGrowTo(l i64, newCap i64, stride i64):
	cap = __ld64(l + 16)
	old = __ld64(l)
	if cap > 0 and (old & (pageSize - 1)) == bigHead and bigGrow(old, newCap * stride):
		__st64(l + 16, newCap)   # more of its pages committed: nothing moves
		return
	# the elements past the length are written before they are read; a byte list's stay zeroed
	# (made a str, its bytes then end in a NUL whenever the room is larger): a small block's past
	# the copy zeroed here, a big one's by the allocator (whose new pages are zero already)
	n = __ld64(l + 8)
	small = stride == 1 and newCap <= smallMax
	items = rtAlloc(newCap) if stride == 1 and not small else rtAllocRaw(newCap * stride)
	if n > 0:
		__memcpy(items, __ld64(l), n * stride)
	if small:
		__memset(items + n, 0, newCap - n)
	if cap > 0:
		rtFree(__ld64(l))
	__st64(l, items)
	__st64(l + 16, newCap)

fn listPushRaw(l i64, src i64, stride i64):
	n = __ld64(l + 8)
	listGrowRaw(l, n + 1, stride)
	__memcpy(__ld64(l) + n * stride, src, stride)
	__st64(l + 8, n + 1)

# the backend's bounds checks jump here
fn boundsFail():
	stopWith("index-out-of-bounds", "index out of bounds", callsFrom(__returnAddress(), 0))
