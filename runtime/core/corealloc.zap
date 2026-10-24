# The runtime's allocator: big blocks, size classes, pages, frees and remote frees (core.zap).

# Big blocks (over 4096 bytes) come from the system rounded up to a power of two and, once
# freed, wait in a list of their size shared by all threads (slots 29..39 their heads, 53 a spin
# lock, 54 their length, 51 the bytes they hold) for the next request of that size: a task that fills a
# buffer per round gets the same pages back, already faulted in, instead of fresh ones from
# the system every time. The list keeps at most bigKeep bytes, of blocks no larger than
# bigKeepEach: past that a freed block goes back to the system, so a program's peak (a level
# loaded, a big list grown) does not stay held once it is over. A block grown in place is
# kept with the blocks of the largest size its committed pages hold. A cached block is zeroed
# again when handed out, as fresh pages would be.
bigKeep i64 = 33_554_432   # 32 MB
bigKeepEach i64 = 8_388_608   # 8 MB
# Asks for the memory the program maps from now on in 2 MB or more to be backed by the system's
# huge pages where it has them (Linux's transparent ones, MADV_HUGEPAGE; nothing on Windows, where
# they need a privilege): a program that touches big tables all over takes one fault and one TLB
# entry for 2 MB instead of 512, its memory then taken 2 MB at a time.
pub fn preferHugePages():
	gset(slotHuge, 1)

fn bigRound(size i64) i64:
	r i64 = 8192
	while r < size:
		r *= 2
	r

# the slot of the list of the freed big blocks of r bytes (bigRound's, at most bigKeepEach)
fn bigList(r i64) i64:
	list = slotBigLists
	s i64 = 8192
	while s < r:
		s *= 2
		list += 1
	list

fn bigLock():
	at = __globals() + 53 * 8
	spinning = true
	while spinning:
		if __cmpxchg(at, 0, 1) == 0:
			spinning = false
		else:
			__pause()

fn bigUnlock():
	gset(slotBigLock, fenced(0))

# A big block's header: +0 the end (from the header) of its bytes in use or zeroed (past it, up
# to the committed end, a cached block's pages hold what they held), +8 0 in use (its committed
# bytes once cached), +16 the bytes reserved for it, +24 the bytes committed (the next cached
# block once cached). Four times its pages are reserved, so a list that grows commits more of
# them in place (bigGrow) instead of copying into a block twice the size, both held at once.
bigHead i64 = 32
# a list of this many bytes or more in a big block grows by a quarter (listGrowRaw)
bigGrowQuarter i64 = 67_108_864

fn bigAlloc(size i64, zero bool) i64:
	r = bigRound(size)
	p = bigTake(r)
	if p == 0:
		# room to grow into: four times its pages, and a block of a megabyte or more up to a
		# gigabyte (address space only, committed as the block grows)
		room = (r * 4).max(1_073_741_824) if r >= 1_048_576 else r * 4
		# (only its pages committed, the system counting committed memory against the program)
		ready = wholePages(size)
		fresh = reserveCommitted(room, ready)
		if fresh == 0:
			outOfMemory()
		__st64(fresh, ready)   # fresh pages are zero
		__st64(fresh + 16, room)
		__st64(fresh + 24, ready)
		return fresh
	if zero:
		__memset(p + bigHead, 0, size - bigHead)
	__st64(p, size)
	__st64(p + 24, __ld64(p + 8))
	p

# a cached block for a request of r bytes (bigRound's), or 0: one of its size, else one up to
# four times it (a list grown in place kept its pages)
fn bigTake(r i64) i64:
	if r > bigKeepEach: return 0
	list = bigList(r)
	last = bigList((r * 4).min(bigKeepEach))
	bigLock()
	p = gv(list)
	while p == 0 and list < last:
		list += 1
		p = gv(list)
	if p != 0:
		gset(list, __ld64(p + 24))
		gset(slotBigCount, gv(slotBigCount) - 1)
		gset(slotBigBytes, gv(slotBigBytes) - __ld64(p + 8))
	bigUnlock()
	p

# the big block at user address b grown in place to hold n bytes: true when its reservation
# had the room (the bytes past those in use read zero)
fn bigGrow(b i64, n i64) bool:
	h = b - bigHead
	end = n + bigHead
	need = wholePages(end)
	clean = __ld64(h)
	committed = __ld64(h + 24)
	if end > clean and clean < committed:
		__memset(h + clean, 0, end.min(committed) - clean)   # a former use's bytes
	cleanEnd = end.max(clean)
	if need > committed:
		if need > __ld64(h + 16) or not commitPages(h, need): return false
		__st64(h + 24, need)
		if clean >= committed:
			cleanEnd = need   # the new pages come zeroed
	__st64(h, cleanEnd)
	true

fn bigFree(h i64):
	r = __ld64(h + 24)
	bigLock()
	if r > bigKeepEach or gv(slotBigBytes) + r > bigKeep:
		bigUnlock()
		freePages(h)
		return
	list = bigList(bigRound(r + 1) / 2)   # grown in place: the size its committed pages hold
	__st64(h + 8, r)
	__st64(h + 24, gv(list))
	gset(list, h)
	gset(slotBigCount, gv(slotBigCount) + 1)
	gset(slotBigBytes, gv(slotBigBytes) + r)
	bigUnlock()

# zeroes a block of n bytes (a multiple of 16): small blocks with plain stores (rep stosb
# costs more to start than a dozen stores)
fn zeroBlock(p i64, n i64):
	if n > 128:
		__memset(p, 0, n)
		return
	at = p
	end = p + n
	while at < end:
		__st64(at, 0)
		__st64(at + 8, 0)
		at += 16

chunkSize i64 = 4_194_304
commitStep i64 = 262_144   # a chunk's pages are committed this many bytes at a time
pageSize i64 = 16_384
pageHead i64 = 208   # a page's record: its blocks start after it
smallMax i64 = 4096   # larger blocks are big blocks

# zeroed; public with rtFree only for the tests of a second free and of a use after free (no safe
# program can do either)
pub fn rtAlloc(n i64) i64:
	b = allocPop(n)
	if b == 0:
		b = regionPop(n)
		if b == 0: return allocSlow(n, true)
	zeroBlock(b, n.alignUp(16).max(16))   # its class's size
	b

# rtAlloc for a block its caller fills before anything reads it (a grown list's elements, a new
# string's bytes): a reused block is not zeroed first
fn rtAllocRaw(n i64) i64:
	b = allocPop(n)
	if b != 0: return b
	b2 = regionPop(n)
	b2 if b2 != 0 else allocSlow(n, false)

# The quick path of rtAlloc in an open arena (not paused), small enough to be written there: a
# small block, the next bytes of its region's page. 0 for anything else.
fn regionPop(n i64) i64:
	h = 0 if gv(slotQuick) == 0 or n > smallMax else __tlsGet(gv(slotHeapTls))
	r = 0 if h == 0 else __ld64(h + 2152)
	b = 0 if r == 0 or __ld64(h + 2160) != 0 else __ld64(r + 40)
	size = ((n + 15) & -16).max(16)   # (no call: written where a box is made)
	if b == 0 or b + size > __ld64(r + 48): return 0
	__st64(r + 40, b + size)
	b

# The quick path of rtAlloc, small enough to be written where a block is made: a small block
# off the free list of its class's head page (the spare too, then in use again), in this thread's
# heap with no arena open. 0 for anything else.
fn allocPop(n i64) i64:
	h = 0 if gv(slotQuick) == 0 or n > smallMax else __tlsGet(gv(slotHeapTls))
	page = 0 if h == 0 or __ld64(h + 2152) != 0 else __ld64(h + 32 + ((n + 15) >> 4).max(1) * 8)
	b = 0 if page == 0 else __ld64(page + 24)
	if b == 0: return 0
	if page == __ld64(h + 2144):
		__st64(h + 2144, 0)
	__st64(page + 24, __ld64(b))
	__st64(page + 16, __ld64(page + 16) + 1)
	__st64(h + 16, __ld64(h + 16) + 1)
	b

# a block of n bytes made the long way: past the end of the head page, in an arena, a new page
# or a big block
fn allocSlow(n i64, zero bool) i64:
	b = allocFast(n, zero)
	b if b != 0 else allocBlock(n, zero)

# The next common case of allocBlock (allocPop's failed) in a function that calls nothing (its
# locals stay in scratch registers, none saved): a small block from the head page of its class,
# past its last block. 0 when that takes more (allocBlock then does it all), as in an open arena
# (allocPop's, its page used up).
fn allocFast(n i64, zero bool) i64:
	if gv(slotReady) == 0 or n > smallMax or gv(slotLeakNotes) == 1 or gv(slotMemcheck) == 1:   # (leakNotesOn: a call would count)
		return 0
	h = __tlsGet(gv(slotHeapTls))
	size = n.alignUp(16).max(16)
	if h == 0 or __ld64(h + 2152) != 0 and __ld64(h + 2160) == 0: return 0
	page = __ld64(h + 32 + (size >> 1))
	if page == 0 or page == __ld64(h + 2144) or __ld64(page + 24) != 0: return 0
	b = __ld64(page + 32)
	if b + size > page + pageSize: return 0
	__st64(page + 32, b + size)
	dirty = (__ld64(page + 56) & 2) != 0
	__st64(page + 16, __ld64(page + 16) + 1)
	__st64(h + 16, __ld64(h + 16) + 1)
	if zero and dirty:
		at = b
		while at < b + size:
			__st64(at, 0)
			__st64(at + 8, 0)
			at += 16
	b

# a block of n bytes, zeroed when `zero` (a block fresh from the system always is)
fn allocBlock(n i64, zero bool) i64:
	if gv(slotReady) == 0:
		initMem()
	h = heap()
	if __ld64(h + 2152) != 0 and __ld64(h + 2160) == 0: return regionAlloc(h, n, zero)
	__st64(h + 16, __ld64(h + 16) + 1)
	if memcheckOn():
		b = guardAlloc(n)
		if b != 0:
			if leakNotesOn():
				noteBlock(b, n)
			return b
	if n > smallMax:
		size = n.alignUp(16) + bigHead
		big = bigAlloc(size, zero)
		__st64(big + 8, 0)
		if leakNotesOn():
			noteBlock(big + bigHead, n)
		return big + bigHead
	size = n.alignUp(16).max(16)
	slot = h + 32 + size / 2   # the class's pages: size/16, 8 bytes per head
	page = __ld64(slot)
	if page == 0 and __ld64(h + 2104) != 0:
		takeRemote(h)
		page = __ld64(slot)
	while page != 0:
		b = __ld64(page + 24)
		if b != 0:
			__st64(page + 24, __ld64(b))   # off the free list
			__st64(page + 16, __ld64(page + 16) + 1)
			if page == __ld64(h + 2144):
				__st64(h + 2144, 0)   # the spare in use again
			if zero:
				zeroBlock(b, size)
			if leakNotesOn():
				noteBlock(b, n)
			return b
		cut = __ld64(page + 32)
		if cut + size <= page + pageSize:
			__st64(page + 32, cut + size)
			__st64(page + 16, __ld64(page + 16) + 1)
			if page == __ld64(h + 2144):
				__st64(h + 2144, 0)
			if zero and (__ld64(page + 56) & 2) != 0:
				zeroBlock(cut, size)
			if leakNotesOn():
				noteBlock(cut, n)
			return cut
		# full: out of the class's list until a block of it is freed
		unlistPage(h, page)
		page = __ld64(slot)
	page = newPage(h, size)
	__st64(page + 32, page + pageHead + size)
	__st64(page + 16, 1)
	b = page + pageHead
	if zero and (__ld64(page + 56) & 2) != 0:
		zeroBlock(b, size)
	if leakNotesOn():
		noteBlock(b, n)
	b

# A page of h for blocks of `size` bytes, at the head of the class's list: a free page of a
# chunk of h, or of a new chunk. A page that held blocks before is dirty (bit 1 of +56): a block
# cut from it is zeroed when asked.
fn newPage(h i64, size i64) i64:
	spare = __ld64(h + 2144)
	if spare != 0:
		# another class's empty page, made over as one of this class whose blocks are not zero
		# (the caller takes its first block)
		__st64(h + 2144, 0)
		unlistPage(h, spare)
		__st64(spare, size)
		__st64(spare + 200, 4_294_967_296 / size + 1)
		__st64(spare + 24, 0)
		__st64(spare + 32, spare + pageHead)
		__memset(spare + 64, 0, 128)
		__st64(spare + 56, __ld64(spare + 56) | 2)
		listPage(h, spare)
		return spare
	c = __ld64(h + 2112)
	k = -1
	while c != 0 and k < 0:
		k = firstFreePage(c)
		if k < 0:
			c = __ld64(c + 16)
	if c == 0:
		c = reserveCommitted(chunkSize, commitStep)
		if c == 0:
			outOfMemory()
		__st64(c + 24, commitStep)
		__st64(c, h)
		__st64(c + 16, __ld64(h + 2112))
		__st64(h + 2112, c)
		__st64(h + 2136, __ld64(h + 2136) + 1)
		for w in 0..4:
			__st64(c + 32 + w * 8, -1)   # every page free...
		__st64(c + 32, -2)   # ...but page 0, the chunk's record
		k = 1
	committed = __ld64(c + 24)
	if (k + 1) * pageSize > committed:
		to = ((k + 1) * pageSize).alignUp(commitStep)
		if not commitPages(c + committed, to - committed):
			outOfMemory()
		__st64(c + 24, to)
	word = c + 32 + (k >> 6) * 8
	__st64(word, __ld64(word) & (~(1 << (k & 63))))
	seenWord = c + 64 + (k >> 6) * 8
	seen = (__ld64(seenWord) >> (k & 63)) & 1
	__st64(seenWord, __ld64(seenWord) | (1 << (k & 63)))
	__st64(c + 8, __ld64(c + 8) + 1)
	page = c + k * pageSize
	__st64(page, size)
	__st64(page + 8, h)
	__st64(page + 16, 0)
	__st64(page + 24, 0)
	__st64(page + 32, page + pageHead)
	__st64(page + 48, c)
	__st64(page + 56, seen * 2)
	listPage(h, page)
	page

# whether a chunk of h other than c has a free page
fn otherFreePages(h i64, c i64) bool:
	o = __ld64(h + 2112)
	while o != 0:
		if o != c and firstFreePage(o) >= 0: return true
		o = __ld64(o + 16)
	false

# the index of a free page of chunk c, or -1
fn firstFreePage(c i64) i64:
	for w in 0..4:
		bits = __ld64(c + 32 + w * 8)
		if bits != 0:
			k = 0
			while ((bits >> k) & 1) == 0:
				k += 1
			return w * 64 + k
	-1

# page at the head of its class's list (+40 the next page, +192 the previous one, 0 at the head;
# +56 bit 0 while listed)
fn listPage(h i64, page i64):
	slot = h + 32 + __ld64(page) / 2
	head = __ld64(slot)
	__st64(page + 40, head)
	__st64(page + 192, 0)
	if head != 0:
		__st64(head + 192, page)
	__st64(slot, page)
	__st64(page + 56, __ld64(page + 56) | 1)

fn unlistPage(h i64, page i64):
	next = __ld64(page + 40)
	prev = __ld64(page + 192)
	if prev == 0:
		__st64(h + 32 + __ld64(page) / 2, next)
	else:
		__st64(prev + 40, next)
	if next != 0:
		__st64(next + 192, prev)
	__st64(page + 56, __ld64(page + 56) & -2)

# Ownership rules out a second free in safe code, and checked runs (ZAP_RUN=memcheck) catch one in
# the runtime's own (guardFree), so a small block is freed with no check of its own; a block made
# before ZAP_RUN=memcheck was set has its bytes overwritten when freed under it. A big block sits
# 16 bytes into its pages; a small one at least pageHead bytes into its page.
pub fn rtFree(p i64):
	if p == 0: return
	# the common case, calling nothing: a small block of this thread's heap whose page stays
	# listed, in use or (when the heap has no spare) the spare from now on
	h = 0 if gv(slotQuick) == 0 or (p & (pageSize - 1)) == bigHead else __tlsGet(gv(slotHeapTls))
	page = p & (-pageSize)
	if h == 0 or __ld64(page + 8) != h or (__ld64(page + 56) & 1) == 0 or
		__ld64(page + 16) == 1 and __ld64(h + 2144) != 0:
		if h != 0 and __ld64(page + 8) == regionMark: return   # an arena's: freed with its region
		freeSlow(p)
		return
	if __ld64(page + 16) == 1:
		__st64(h + 2144, page)
	__st64(p, __ld64(page + 24))
	__st64(page + 24, p)
	__st64(page + 16, __ld64(page + 16) - 1)
	__st64(h + 24, __ld64(h + 24) + 1)

# rtFree's every other case: a big block, another thread's block, a page that empties or comes
# back to its class's list, the notes and checks of ZAP_RUN=leaks and ZAP_RUN=memcheck
fn freeSlow(p i64):
	if inRegion(p): return
	if leakNotesOn():
		forgetBlock(p)
	hp = heap()
	__st64(hp + 24, __ld64(hp + 24) + 1)
	if isGuarded(p):
		guardFree(p)
		return
	if (p & (pageSize - 1)) == bigHead:
		freeBigBlock(p)
		return
	page = p & (-pageSize)
	if memcheckOn():
		__memset(p, 221, __ld64(page))
	owner = __ld64(page + 8)
	if owner != hp:
		freeRemote(owner, p)
		return
	freeLocal(hp, page, p)

# a large block back (the rare paths out of rtFree's way, so its own code stays small)
fn freeBigBlock(p i64):
	h = p - bigHead
	# a large block in use has 0 there; a cached one its committed bytes
	if __ld64(h + 8) != 0:
		fail("a block freed twice")
	bigFree(h)

# another heap's block: onto its remote list, for it to take back
fn freeRemote(owner i64, p i64):
	at = owner + 2104
	pushed = false
	while not pushed:
		first = __ld64(at)
		__st64(p, first)
		pushed = __cmpxchg(at, first, p) == first

# block b back into its page (of hp): the page listed again if it was full, given back to its
# chunk once empty
fn freeLocal(hp i64, page i64, b i64):
	__st64(b, __ld64(page + 24))
	__st64(page + 24, b)
	used = __ld64(page + 16) - 1
	__st64(page + 16, used)
	if used == 0:
		old = __ld64(hp + 2144)
		if old != 0 and old != page:
			unlistPage(hp, old)   # the spare before (empty, listed) goes back
			freePage(hp, old)
		if (__ld64(page + 56) & 1) == 0:
			listPage(hp, page)
		__st64(hp + 2144, page)
	elif (__ld64(page + 56) & 1) == 0:
		listPage(hp, page)   # full before: it has a block to give again

# page back into its chunk's free pages; the chunk to the system once none of its pages is in
# use, unless no other chunk of h has a free page
fn freePage(h i64, page i64):
	c = __ld64(page + 48)
	k = (page - c) / pageSize
	word = c + 32 + (k >> 6) * 8
	__st64(word, __ld64(word) | (1 << (k & 63)))
	left = __ld64(c + 8) - 1
	__st64(c + 8, left)
	if left > 0: return
	if not otherFreePages(h, c):
		decommitChunk(c)   # the heap's last free pages: kept for the next ones
		return
	prev = h + 2112 - 16   # the list's head, seen as a chunk whose link is at +16
	while __ld64(prev + 16) != c:
		prev = __ld64(prev + 16)
	__st64(prev + 16, __ld64(c + 16))
	__st64(h + 2136, __ld64(h + 2136) - 1)
	freePages(c)

# the pages of the empty chunk c past its first commitStep bytes given back to the system (they
# read zero when committed again: no page of them has been used)
fn decommitChunk(c i64):
	committed = __ld64(c + 24)
	if committed <= commitStep: return
	_ = VirtualFree(c + commitStep, committed - commitStep, 16_384)   # MEM_DECOMMIT
	__st64(c + 24, commitStep)
	first = commitStep / pageSize
	__st64(c + 64, __ld64(c + 64) & ((1 << first) - 1))
	for w in 1..4:
		__st64(c + 64 + w * 8, 0)

# the blocks other threads freed for this thread's heap taken back (a pool worker, at the start
# of a round: the caller frees what the last round made)
fn takeRemoteFrees():
	h = __tlsGet(gv(slotHeapTls))
	if h != 0 and __ld64(h + 2104) != 0:
		takeRemote(h)

# the blocks other threads freed for the heap h, taken into its pages
fn takeRemote(h i64):
	at = h + 2104
	b = __ld64(at)
	while __cmpxchg(at, b, 0) != b:
		b = __ld64(at)
	while b != 0:
		next = __ld64(b)
		freeLocal(h, b & (-pageSize), b)
		b = next
