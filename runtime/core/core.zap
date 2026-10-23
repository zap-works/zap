# Runtime of native Zap programs (value model of spec §2): written in Zap over the
# compiler's intrinsics. Values are stored inline; a `str` is { ptr, length, cap } with cap 0 for
# bytes that are not owned (literals); a `T[]` is { ptr, length, cap } over a block of T.
# Memory comes from a size-class allocator over 4 MB chunks; blocks go back to it through
# rtFree, at the drops the ownership model inserts.
#
# The state of the runtime lives in module variables (`mut` at the top level), except the
# allocator's, which must exist before `$init` runs: that lives in a fixed block of the image
# (`__globals()`), one 8-byte slot each:
#   2 stack base (set at entry)    3 ZAP_RUN's text, read once (io.zap, runText)
#   10 the file the paths read are added to (io.zap, readsFile)
#   11..13 an Android app's: its image's place, its package's, logd's socket (system/linux/app/)
#   14 the hash of the state's layout    15 the module variables' address (loaded.zap)
#   16, 17 where the next build mapped beside the program goes above it, and the lowest below
#   (live.zap's liveReserve: slots, so the layout a loaded build must share does not change)
#   26 memcheck (ZAP_RUN=memcheck: guardAlloc)
#   27 initialised    28 the allocator's quick paths on (initialised, no leak notes, no checked run)
#   29..39 the big-block lists' heads, one a size (8 KB, 16 KB ... 8 MB)
#   40 the bytes the regions' chunks kept hold (corearena.zap)
#   41 the pages kept for the out-of-memory report (outOfMemory)
#   42 the bytes the checked run's blocks hold (guardAlloc)
#   50 the TLS index of the thread's heap
#   51 the bytes the big-block lists hold    52 the regions' chunks kept
#   53 the spin lock of both    54 the big-block lists' length
#   55 the head of the list of every thread's heap (for the statistics)
#   56..59 the leak notes' table, their walk's room, the code's start and end (leaks.zap)
#   60 leak notes on (ZAP_RUN=leaks)    61 main returned (the leak report judges)
#   62 the compiler's debug table (errors.zap; gen.zap's debugTableSlot writes it)
#   63 the checked run's reservation (guardAlloc)

# the slots by name
slotTrace = 3
slotReads = 10
slotLayout = 14
slotModuleVariables = 15
slotReservedAbove = 16
slotReservedBelow = 17
slotMemcheck = 26
slotReady = 27
slotQuick = 28
slotBigLists = 29
slotRegionBytes = 40
slotOomSpare = 41
slotGuardBytes = 42
slotHeapTls = 50
slotBigBytes = 51
slotRegionChunks = 52
slotBigLock = 53
slotBigCount = 54
slotHeaps = 55
slotLeakTable = 56
slotLeakWalk = 57
slotCodeStart = 58
slotCodeEnd = 59
slotLeakNotes = 60
slotMainReturned = 61
slotDebugTable = 62
slotGuard = 63

fn gv(i i64) i64:
	__ld64(__globals() + i * 8)

fn gset(i i64, v i64):
	__st64(__globals() + i * 8, v)

# the slots that several files read and write, by name (a slot's number is written once, here)
fn memcheckOn() bool:
	gv(slotMemcheck) == 1

fn setMemcheck():
	gset(slotMemcheck, 1)
	gset(slotQuick, 0)
	if gv(slotGuard) == 0:
		guardReserve()

fn leakNotesOn() bool:
	gv(slotLeakNotes) == 1

fn setLeakNotes(on i64):
	gset(slotLeakNotes, on)
	if on == 1:
		gset(slotQuick, 0)

fn mainReturned() bool:
	gv(slotMainReturned) == 1

fn setMainReturned():
	gset(slotMainReturned, 1)

fn debugTable() i64:
	gv(slotDebugTable)

# ---------- memory ----------
# A small block (up to 4096 bytes) has no header: 4 MB chunks are cut into 16 KB pages, each of
# one size class, whose record at the page's start (pageHead bytes) gives the size, the heap,
# the blocks in use and a free list; a block finds its page by its address. A big block gets
# pages of its own with a 16-byte header [size][0].
#
# A heap's pages only hold its own blocks: a block freed by another thread goes to its heap's
# remote list (one atomic push), which that heap takes into its pages when it next runs short.
# A page whose blocks are all free goes back to its chunk, and a chunk whose pages are all free
# to the system (unless no other chunk of the heap has a free page): a peak
# of small blocks (a level loaded, a world made) does not stay held once it is over, and a
# teardown frees in place, with nothing to sweep.

# the first allocation of the program: the heap slot is made before any thread exists (and
# before env.get below allocates)
fn initMem():
	gset(slotReady, 1)
	gset(slotOomSpare, allocPages(oomSpare))
	gset(slotHeapTls, TlsAlloc())
	if memcheckWord().on():
		setMemcheck()
	if leaksWord().on():
		startLeakNotes()
	if not memcheckOn() and not leakNotesOn():
		gset(slotQuick, 1)

# the runtime's diagnostic words of ZAP_RUN

fn memcheckWord() TraceWord:
	TraceWord(
		"memcheck",
		"every block on pages of its own, taken away when freed: a use after free stops at once"
	)

fn leaksWord() TraceWord:
	TraceWord("leaks", "the blocks never freed listed at exit, each by the calls that allocated it")

fn memstatsWord() TraceWord:
	TraceWord("memstats", "the allocation and free counts and the peak memory printed at exit")

# pages from the system, or the program ends
fn allocPagesOrFail(n i64) i64:
	p = allocPages(n)
	if p == 0:
		outOfMemory()
	p

# Memory committed at the start and given back when the system gives no more, so the report has
# pages (its stack's, a chunk of the heap) when a cap on the process's memory is reached.
oomSpare i64 = chunkSize + 65_536

fn outOfMemory():
	spare = gv(slotOomSpare)
	gset(slotOomSpare, 0)
	if spare != 0:
		freePages(spare)
	fail("out of memory")

# Every thread has a heap of its own, found through a TLS slot (global slot 50 holds the
# index): no lock, no sharing but the remote list. The heap record: +16 allocations, +24 frees,
# +32 the pages of each size class with a block to give (one list head per class, size/16),
# +2096 the next heap of the list in slot 55, +2104 the remote list's head, +2112 its chunks'
# list, +2136 how many chunks it holds, +2144 its spare page: the last page to empty, kept in
# its class's list (a block made and freed again and again does not take a page from its chunk
# and give it back each time) until another empties or a class needs a new page, +2152..+2176
# its arenas (see *arenas* below). A
# chunk (its page 0): +0 its heap, +8 its pages in use, +16 the next chunk, +24 its bytes committed (65,536 at a time), +32 a bitmap of its
# free pages, +64 one of the pages it has handed out before. A page: +0 the block size, +8 the
# heap, +16 the blocks in use, +24 the free list (linked through each block's first word), +32
# the next block never handed out, +40 and +192 the next and previous page of its class's list,
# +48 the chunk, +56 bit 0 while listed and bit 1 when used before (its new blocks are not
# zero).
fn heap() i64:
	h = __tlsGet(gv(slotHeapTls))
	if h != 0: return h
	heapNew()

# the first allocation of a thread: its heap record
fn heapNew() i64:
	h = allocPagesOrFail(4096)
	__tlsSet(gv(slotHeapTls), h)
	linked = false
	while not linked:
		first = gv(slotHeaps)
		__st64(h + 2096, first)
		linked = __cmpxchg(__globals() + 55 * 8, first, h) == first
	h
