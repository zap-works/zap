# The runtime's arena regions and the guarded allocations of a checked run (core.zap).

# An `arena:` block (spec *Arenas*) allocates from a region of its own, given back whole at
# its end, its blocks never freed one by one. The heap record holds the open arena (+2152, 0
# for none), the pauses of it (+2160: a statement that stores outside the block allocates from
# the heap meanwhile) and the first chunks of the regions closed, kept for the next ones (+2168
# the list, linked through +0, +2176 its length, at most regionsKept).
# A region is a list of chunks of 16 KB pages; each page's record (regionHead bytes) holds
# regionMark at +8, where a heap's page holds its heap, so rtFree tells a region's block by its
# page and frees nothing. A page is marked when the region first cuts a block from it (marking a
# chunk's sixteen pages at once would fault in sixteen system pages a region that uses one). A block larger than a page gets pages of its own, linked as a chunk.
# A chunk: +0 the next chunk, +8 the mark, +16 its bytes; the first chunk is the region's record:
# +24 the arena open before it, +32 its pauses, +40 the next free byte, +48 the end of its page,
# +56 the chunk being cut, +64 0 for an `arena:` block's region, 1 for an implicit one (regionOpen)
# while it holds all it was asked for, 2 once it has not.
regionMark i64 = 1
regionHead i64 = 80
regionChunk i64 = 262_144
regionsKept i64 = 8
# The other chunks of a closed region wait, any thread's, for the next regions (slot 52 the list,
# linked through +0, 40 its bytes, under the big blocks' lock): a thread that makes and drops a
# large arena again and again reuses pages already faulted in instead of fresh ones. At most
# regionKeep bytes, so a peak's pages do not stay held once it is over.
regionKeep i64 = 67_108_864

# whether p is a block of a region (a guarded or a big block is not, and reading its page would
# not be safe)
fn inRegion(p i64) bool:
	not isGuarded(p) and (p & (pageSize - 1)) != bigHead and
		__ld64((p & (-pageSize)) + 8) == regionMark

# an arena block's start: the thread allocates from a new region until arenaExit
fn arenaEnter():
	if gv(slotReady) == 0:
		initMem()
	h = heap()
	r = __ld64(h + 2168)
	if r != 0:
		__st64(h + 2168, __ld64(r))
		__st64(h + 2176, __ld64(h + 2176) - 1)
	else:
		r = regionChunkTake()
	__st64(r, 0)
	__st64(r + 24, __ld64(h + 2152))
	__st64(r + 32, __ld64(h + 2160))
	__st64(r + 40, r + regionHead)
	__st64(r + 48, r + pageSize)
	__st64(r + 56, r)
	__st64(r + 64, 0)
	__st64(h + 2152, r)
	__st64(h + 2160, 0)

# an arena block's end: its region given back whole, the arena around it (if any) open again
fn arenaExit():
	h = __tlsGet(gv(slotHeapTls))
	r = __ld64(h + 2152)
	c = __ld64(r)
	while c != 0:
		next = __ld64(c)
		regionChunkGive(c)
		c = next
	__st64(h + 2152, __ld64(r + 24))
	__st64(h + 2160, __ld64(r + 32))
	if __ld64(h + 2176) < regionsKept and not memcheckOn():
		__st64(r, __ld64(h + 2168))
		__st64(h + 2168, r)
		__st64(h + 2176, __ld64(h + 2176) + 1)
	else:
		regionChunkGive(r)

# pages for a region, the first marked (a cut chunk's others as the region reaches them)
fn regionChunkNew(bytes i64) i64:
	c = allocPagesOrFail(bytes)
	__st64(c + 8, regionMark)
	__st64(c + 16, bytes)
	c

# a chunk of regionChunk bytes for a region: one a closed region gave back, else new pages
fn regionChunkTake() i64:
	bigLock()
	c = gv(slotRegionChunks)
	if c != 0:
		gset(slotRegionChunks, __ld64(c))
		gset(slotRegionBytes, gv(slotRegionBytes) - regionChunk)
	bigUnlock()
	if c == 0: return regionChunkNew(regionChunk)
	__st64(c + 8, regionMark)   # (a big block's chunk of that size has it marked already; a cut one's too)
	c

# a chunk of a closed region kept for the next ones, or given back to the system (a checked run
# gives back all: a use after the block faults)
fn regionChunkGive(c i64):
	if __ld64(c + 16) == regionChunk and not memcheckOn():
		bigLock()
		if gv(slotRegionBytes) + regionChunk <= regionKeep:
			__st64(c, gv(slotRegionChunks))
			gset(slotRegionChunks, c)
			gset(slotRegionBytes, gv(slotRegionBytes) + regionChunk)
			bigUnlock()
			return
		bigUnlock()
	freePages(c)

# a block of n bytes from the open arena's region
fn regionAlloc(h i64, n i64, zero bool) i64:
	r = __ld64(h + 2152)
	size = n.alignUp(16).max(16)
	if size > pageSize - regionHead:
		if __ld64(r + 64) != 0: return regionFull(h, r, n, zero)
		big = regionChunkNew(wholePages(size + regionHead))
		__st64(big, __ld64(r))
		__st64(r, big)
		return big + regionHead   # fresh pages: zero
	b = __ld64(r + 40)
	if b + size > __ld64(r + 48):
		page = __ld64(r + 48)
		cur = __ld64(r + 56)
		if page >= cur + __ld64(cur + 16):
			if __ld64(r + 64) != 0: return regionFull(h, r, n, zero)
			page = regionChunkTake()
			__st64(page, __ld64(r))
			__st64(r, page)
			__st64(r + 56, page)
		__st64(page + 8, regionMark)
		b = page + regionHead
		__st64(r + 48, page + pageSize)
	__st64(r + 40, b + size)
	if zero:
		zeroBlock(b, size)
	b

# An implicit region: a statement of a loop whose allocations cannot leave it
# (irRegionStatement) allocates from a region of one chunk, ended with the statement; its
# temporaries made of the region's blocks alone are not dropped one by one but go with it. Once
# the chunk is used up the rest comes from the heap (the region paused): regionClean then says so,
# and the statement's temporaries are dropped as anywhere else.
fn regionOpen():
	arenaEnter()
	__st64(__ld64(heap() + 2152) + 64, 1)

# whether the open implicit region holds every block its statement asked for
fn regionClean() bool:
	__ld64(__ld64(heap() + 2152) + 64) == 1

fn regionClose():
	arenaExit()

# a temporary of an implicit region's statement at its drop: dropped only once the region no longer
# holds every block (else its blocks go with the region)
fn regionDropped<T>(x T):   # (x is the caller's own, lent: dropped where it is)
	if not regionClean():
		__drop(x)

# a block of an implicit region that has no room left: from the heap, the region paused (its end
# takes the pause back)
fn regionFull(h i64, r i64, n i64, zero bool) i64:
	__st64(r + 64, 2)
	__st64(h + 2160, __ld64(h + 2160) + 1)
	allocBlock(n, zero)

# A statement of an arena block that stores outside it (or a runtime function keeping state):
# what it allocates comes from the heap until arenaResume.
fn arenaPause():
	h = __tlsGet(gv(slotHeapTls))
	if h != 0 and __ld64(h + 2152) != 0:
		__st64(h + 2160, __ld64(h + 2160) + 1)

fn arenaResume():
	h = __tlsGet(gv(slotHeapTls))
	if h != 0 and __ld64(h + 2160) > 0:
		__st64(h + 2160, __ld64(h + 2160) - 1)

# ---------- checked runs ----------
# With ZAP_RUN=memcheck (every test) each block gets pages of its own, never handed out again:
# freeing it decommits them, so a later use of it (through a reference, a window or a copy of
# its address) faults at once, however long after. The pages come from one reservation
# (slot 63): its head holds the next free page and a byte per page, 1 where a block starts
# (a second free finds 0); a block sits 16 bytes into its first page, after its size. Once the
# reservation is used up, or the blocks in use hold guardBudget bytes (a page each: a program of
# a few hundred megabytes would hold gigabytes, past a test's cap), blocks come from the heap.

guardSpan i64 = 1 << 36
guardBudget i64 = 1 << 28
guardPages i64 = guardSpan >> 12
guardHead i64 = wholePages(8 + guardPages)

fn guardReserve():
	base = reserveHighPages(guardSpan)
	if base == 0 or not commitPages(base, guardHead): return
	__st64(base, base + guardHead)
	gset(slotGuard, base)

# a block of n bytes on pages of its own, zeroed; 0 when there is no room left
fn guardAlloc(n i64) i64:
	base = gv(slotGuard)
	if base == 0: return 0
	bytes = wholePages(n + 16)
	held = __globals() + slotGuardBytes * 8
	if __xadd(held, bytes) + bytes > guardBudget:
		__xadd(held, -bytes)
		return 0
	at = __xadd(base, bytes)
	if at + bytes > base + guardSpan or not commitPages(at, bytes):
		__xadd(held, -bytes)
		return 0
	__st8(base + 8 + ((at - base) >> 12), 1)
	__st64(at, n)
	at + 16

fn isGuarded(p i64) bool:
	base = gv(slotGuard)
	base != 0 and p > base + guardHead and p < base + guardSpan

fn guardFree(p i64):
	base = gv(slotGuard)
	at = p - 16
	mark = base + 8 + ((at - base) >> 12)
	if (at & 4095) != 0 or __ld8(mark) != 1:
		fail("a block freed twice")
	__st8(mark, 0)
	bytes = wholePages(__ld64(at) + 16)
	__xadd(__globals() + slotGuardBytes * 8, -bytes)
	_ = VirtualFree(at, bytes, 16_384)   # MEM_DECOMMIT

# ---------- strings ----------
# A str is { ptr, len, cap }: its bytes, their length, and the room of the block it owns (0 for
# bytes it does not own: a literal's, a window's). A short one (up to strShort bytes) owns no
# block: its bytes are in its own 24 bytes, zeros after them, and its last byte is 128 + its
# length, so its cap word is negative. Both are read through textPtrAt and textLenAt (the
# compiler's irStrWords reads them the same way); a window ({ ptr, len }) is never short.
