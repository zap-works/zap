# The process's address space as Horizon describes it to svcQueryMemory: regions of a memory
# type and permission, the gaps between them free. All of it lies in the guest memory's one span
# (core.Memory): the modules from its start, then the heap, the stacks and thread-local pages, and
# the alias region svcMapMemory maps into; a region mapped is committed in the host's memory. The
# types and permissions are switchbrew's (SVC#MemoryType, MemoryPermission).

import recomp.switch.cpu.core

pub typeFree = 0
pub typeCode = 3
pub typeCodeData = 4
pub typeHeap = 5
pub typeShared = 6
pub typeStack = 0xB
pub typeThreadLocal = 0xC
pub typeTransfer = 0xE
pub typeInaccessible = 0x10

pub permRead = 1
pub permWrite = 2
pub permExecute = 4

pub pageSize = 0x1000

# the 36-bit address space's end, past which nothing is mapped
pub addressSpaceEnd = 1 << 36

pub type Region:
	at i64
	size i64
	kind i64
	perm i64

	fn end():
		at + size

pub type Space:
	regions Region[] = []   # sorted by address, none overlapping
	heapAt i64 = 0
	heapMax i64 = 0
	heapSize i64 = 0
	stackAt i64 = 0   # where svcMapMemory's alias region begins
	stackSize i64 = 0
	tlsAt i64 = 0   # the next thread-local page's address
	tlsEnd i64 = 0
	sharedAt i64 = 0   # the next address shared and transfer memory is mapped at
	sharedEnd i64 = 0
	# the regions svcGetInfo names (alias, heap, ASLR, stack): where the game picks addresses
	aliasRegion Region = Region(0, 0, typeFree, 0)
	heapRegion Region = Region(0, 0, typeFree, 0)
	aslrRegion Region = Region(0, 0, typeFree, 0)
	stackRegion Region = Region(0, 0, typeFree, 0)

	# The region holding addr, or the free gap around it. Past the guest memory's span (sharedEnd)
	# nothing can be mapped, so a game that picks addresses at random there is told to look again.
	fn query(addr i64):
		if sharedEnd > 0 and addr >= sharedEnd:
			return Region(
				at = sharedEnd,
				size = addressSpaceEnd - sharedEnd,
				kind = typeInaccessible,
				perm = 0
			)
		start = 0
		for r in regions:
			if addr < r.at:
				return Region(at = start, size = r.at - start, kind = typeFree, perm = 0)
			if addr < r.end(): return r.copy()
			start = r.end()
		end = sharedEnd if sharedEnd > 0 else addressSpaceEnd
		Region(at = start, size = end - start, kind = typeFree, perm = 0)

	# [at, at + size) mapped as kind with perm, replacing what was there
	fn map(at i64, size i64, kind i64, perm i64):
		if not core.memory.commit(at, size):
			fail("the host has no memory for {size:x} bytes at {at:x}")
		unmap(at, size)
		k = 0
		while k < regions.len and regions[k].at < at:
			k += 1
		regions.insert(k, Region(at, size, kind, perm))

	# [at, at + size) made free, the regions that overlap it cut
	fn unmap(at i64, size i64):
		end = at + size
		kept = []
		for r in regions:
			if r.end() <= at or r.at >= end:
				kept.push(r.copy())
				continue
			if r.at < at:
				kept.push(Region(..r, size = at - r.at))
			if r.end() > end:
				kept.push(Region(at = end, size = r.end() - end, kind = r.kind, perm = r.perm))
		regions = kept

	# the permission of [at, at + size) changed, the kind kept
	mut fn protect(at i64, size i64, perm i64):
		r = query(at)
		map(at, size, r.kind, perm)

# A game (a heap this large) gets a 36-bit space's regions as Horizon, and Eden the oracle, give
# them: stacks below 2 GiB, the alias region to 8 GiB, the heap's from 8 GiB, ASLR over the whole
# 64 GiB; so its addresses are the oracle's. The host commits only the pages mapped.
bigHeap = 0x4000_0000
gameHeapAt = 0x2_0000_0000

# a game's regions: alias, heap, ASLR, stack (where and how large)
gameRegions = [
	Region(at = 0x8000_0000, size = 0x1_8000_0000, kind = typeFree, perm = 0),
	Region(at = gameHeapAt, size = 0x2_0000_0000, kind = typeFree, perm = 0),
	Region(at = 0x800_0000, size = 0xF_F800_0000, kind = typeFree, perm = 0),
	Region(at = 0x800_0000, size = 0x7800_0000, kind = typeFree, perm = 0)
]

# The layout of a process whose modules end at `codeEnd` (from the memory's base): the heap of up
# to heapMax bytes, then stacks, thread-local pages and shared memory; the memory span made to hold
# it all.
pub fn layout(base i64, codeEnd i64, heapMax i64, stackSize i64) Space:
	game = heapMax >= bigHeap
	heapAt = gameHeapAt if game else (base + codeEnd).alignUp(0x20_0000)
	stackAt = (heapAt + heapMax).alignUp(0x20_0000)
	tlsAt = stackAt + stackSize
	sharedAt = tlsAt + 0x10_0000
	sharedEnd = sharedAt + 0x1000_0000
	s = Space(heapAt, heapMax, stackAt, stackSize, tlsAt, tlsEnd = sharedAt, sharedAt, sharedEnd)
	if game:
		s.aliasRegion = gameRegions[0]
		s.heapRegion = gameRegions[1]
		s.aslrRegion = gameRegions[2]
		s.stackRegion = gameRegions[3]
		return s
	half = stackSize / 2
	s.aliasRegion = Region(at = stackAt, size = half, kind = typeFree, perm = 0)
	s.heapRegion = Region(at = heapAt, size = heapMax, kind = typeFree, perm = 0)
	s.aslrRegion = Region(at = base, size = sharedEnd - base, kind = typeFree, perm = 0)
	s.stackRegion = Region(at = stackAt + half, size = half, kind = typeFree, perm = 0)
	s

# the guest memory's span for a space laid out from base: up to its shared memory's end
pub fn spanSize(s Space, base i64) i64:
	s.sharedEnd - base
