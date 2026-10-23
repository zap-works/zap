# The process's address space as Horizon describes it to svcQueryMemory: regions of a memory
# type and permission, the gaps between them free. All of it lies in the guest memory's one span
# (cpu.Memory): the modules from its start, then the heap, the stacks and thread-local pages, and
# the alias region svcMapMemory maps into; a region mapped is committed in the host's memory. The
# types and permissions are switchbrew's (SVC#MemoryType, MemoryPermission).

import recomp.switch.cpu

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
		if not cpu.memory.commit(at, size):
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

# A game that takes a heap this large expects the first 2 GiB of the address space free for the
# stacks it maps at random addresses, so its heap starts past them; the host commits only the pages
# mapped.
bigHeap = 0x4000_0000
aliasRegionEnd = 0x8000_0000

# The layout of a process whose modules end at `codeEnd` (from the memory's base): the heap of up
# to heapMax bytes, then stacks, thread-local pages and shared memory; the memory span made to hold
# it all.
pub fn layout(base i64, codeEnd i64, heapMax i64, stackSize i64) Space:
	heapAt = (base + codeEnd).alignUp(0x20_0000)
	if heapMax >= bigHeap: heapAt = heapAt.max(aliasRegionEnd)
	stackAt = (heapAt + heapMax).alignUp(0x20_0000)
	tlsAt = stackAt + stackSize
	sharedAt = tlsAt + 0x10_0000
	sharedEnd = sharedAt + 0x1000_0000
	Space(
		heapAt,
		heapMax,
		stackAt,
		stackSize,
		tlsAt,
		tlsEnd = sharedAt,
		sharedAt,
		sharedEnd
	)

# the guest memory's span for a space laid out from base: up to its shared memory's end
pub fn spanSize(s Space, base i64) i64:
	s.sharedEnd - base
