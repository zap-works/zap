# The emulated address space: pages of 4 KB made on first touch, those of the image filled from
# its file (image.zap), those of a region the caller opened (the stack, scratch memory) zeroed,
# found through a two-level page table (engine.memoryMap). An access anywhere else is a fault:
# the read gives 0, the write is dropped, and `fault` says where, for the machine to stop at the
# instruction that made it.

import engine.memoryMap

pageSize = 4096

pub type Region:
	start u64
	size n64

pub type Memory:
	image Image
	regions Region[] = []
	pages memoryMap.WideMap = memoryMap.WideMap()
	fault str = ""

	# opens [start, start + size) as memory of zeros
	fn open(start u64, size n64):
		regions.push(Region(start, size))

	# the place in the pages' bytes of `at`, its page made on first touch; -1 for an address
	# nothing maps
	fn placeOf(at u64) i64:
		p = pages.readAt(i64.wrap(at))
		if p >= 0 or not makePage(at & ~u64(pageSize - 1)): return p
		pages.readAt(i64.wrap(at))

	fn makePage(at u64):
		mapped = image.holds(at)
		if not mapped:
			for r in regions:
				if at - r.start < u64(r.size) or r.start - at < pageSize: mapped = true
		if not mapped: return false
		slot = pages.bytes.len
		if image.holds(at): pages.bytes.extend(image.mappedBytes(at, pageSize))
		else: pages.bytes.extend(zeros(pageSize))
		pages.mapPage(i64.wrap(at), slot, slot)
		true

	# the n bytes (1 to 8) at `at`, little-endian
	mut fn read(at u64, n i64) u64:
		offset = i64(at & (pageSize - 1))
		if offset + n <= pageSize:
			p = placeOf(at)
			if p < 0: return faulted("read", at)
			return match n:
				1: pages.bytes[p]
				2: pages.bytes.u16le(p)
				4: pages.bytes.u32le(p)
				_: pages.bytes.u64le(p)
		v u64 = 0
		for k in 0..n:
			v |= read(at + u64(k), 1) << u64(8 * k)
		v

	# v's low n bytes (1 to 8) at `at`
	fn write(at u64, n i64, v u64):
		offset = i64(at & (pageSize - 1))
		if offset + n <= pageSize:
			p = placeOf(at)
			if p < 0:
				faulted("write", at)
				return
			match n:
				1: pages.bytes[p] = u8.wrap(v)
				2: pages.bytes.setU16le(p, u16.wrap(v))
				4: pages.bytes.setU32le(p, u32.wrap(v))
				_: pages.bytes.setU64le(p, v)
			return
		for k in 0..n:
			write(at + u64(k), 1, v >> u64(8 * k))

	fn faulted(what str, at u64) u64:
		if fault.isEmpty: fault = "{what} of unmapped memory at 0x{at:x}"
		0

	# the n bytes at `at`
	mut fn bytes(at u64, n i64):
		out = []
		for k in 0..n:
			out.push(u8.wrap(read(at + u64(k), 1)))
		out

	# the bytes written from `at` on
	mut fn put(at u64, data u8[]):
		for k in 0..data.len:
			write(at + u64(k), 1, data[k])
