# The GPU's virtual address space: ranges of GPU addresses the driver mapped onto memory the
# process owns (an nvmap handle's pages), read and written through the maps.

import recomp.switch.cpu

# `size` bytes at GPU address `gpu` are the guest's bytes from `host` on
pub type Mapping:
	gpu i64
	size i64
	host i64
	kind i64 = 0   # the surface kind the driver gave it (0 pitch linear)

pub type AddressSpace:
	mappings Mapping[] = []
	bigPageSize i64 = 0x1_0000
	rangeStart i64 = 0x0400_0000
	rangeEnd i64 = 0x100_0000_0000
	nextFree i64 = 0x1_0000_0000

	# The guest address of a GPU address and how many bytes follow it in its mapping; -1 and 1
	# when nothing is mapped there.
	fn locate(va i64) (i64, i64):
		for m in mappings:
			if va >= m.gpu and va < m.gpu + m.size:
				return (m.host + va - m.gpu, m.gpu + m.size - va)
		(-1, 1)

	# the guest address of a GPU address, -1 when unmapped
	fn translate(va i64):
		host, _ = locate(va)
		host

	# A range of `size` bytes aligned to `align`, taken from the free addresses above the last.
	mut fn reserve(size i64, align i64):
		at = nextFree.alignUp(align)
		nextFree = at + size
		at

	# the range mapped; an older mapping at the same address is replaced
	mut fn map(gpu i64, size i64, host i64, kind i64):
		unmap(gpu)
		mappings.push(Mapping(gpu, size, host, kind))

	# the kind of the mapping that begins at `gpu` changed
	mut fn setKind(gpu i64, kind i64):
		for mut m in mappings:
			if m.gpu == gpu: m.kind = kind

	# the mapping that begins at `gpu` removed; whether there was one
	mut fn unmap(gpu i64):
		for k, m in mappings:
			if m.gpu == gpu:
				mappings.remove(k)
				return true
		false

	# the bytes at a GPU address; what is unmapped reads as zeros
	fn read(va i64, n i64) u8[]:
		out u8[] = []
		while out.len < n:
			host, left = locate(va + out.len)
			take = left.min(n - out.len)
			if host < 0: out.extend(zeros(take))
			else: out.extend(cpu.memory.read(host, take))
		out

	# the bytes stored at a GPU address; what is unmapped is dropped
	fn write(va i64, bytes u8[]):
		done = 0
		while done < bytes.len:
			host, left = locate(va + done)
			take = left.min(bytes.len - done)
			if host >= 0: cpu.memory.write(host, bytes[done..done + take])
			done += take

	fn readWord(va i64):
		i64(read(va, 4).u32le(0))

	fn writeWord(va i64, v i64):
		bytes u8[] = []
		bytes.pushU32le(v & 0xFFFF_FFFF)
		write(va, bytes)
