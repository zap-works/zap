# /dev/nvhost-as-gpu, a GPU address space (switchbrew: NV services#nvhost-as-gpu): the client
# reserves ranges of GPU addresses and maps nvmap memory into them; the GPU reads its commands
# and data through these maps (maxwell/address.zap). `object` is the space's index in the GPU.

# the page sizes: small, and the big page of the space (set when it is made)
smallPage = 0x1000

# the two regions GET_VA_REGIONS reports: small pages below 4 GiB, big pages above
smallRegionStart = 0x0400_0000
bigRegionStart = 0x1_0000_0000
addressEnd = 0x100_0000_0000

fn addressSpaceIoctl(mut k Kernel, s i64, cmd i64, mut io u8[]) i64:
	if s < 0: return nvInvalidState
	match cmd:
		0x4101: k.bindChannel(s, get32(io, 0))   # BIND_CHANNEL
		0x4102: k.allocateSpace(s, io)   # ALLOC_SPACE
		0x4103: nvOk   # FREE_SPACE
		0x4105: k.unmapBuffer(s, io)   # UNMAP_BUFFER
		0x4106: k.mapBufferEx(s, io)   # MAP_BUFFER_EX
		0x4108: k.vaRegions(s, io)   # GET_VA_REGIONS
		0x4109: k.allocateAddressSpace(s, io)   # ALLOC_AS_EX
		0x4114: k.remap(s, io)   # REMAP
		_: nvNotImplemented

# the channel behind a file descriptor reads through this space from now on
fn bindChannel(mut k Kernel, s i64, fd i64):
	device = k.nvDevice(fd) ?? return nvBadParameter
	if device.path != "/dev/nvhost-gpu": return nvBadParameter
	k.gpu.channels[device.object].space = s
	nvOk

# ALLOC_SPACE: a range of `pages` pages of `page_size` bytes, at the offset given when bit 0 of
# the flags says so, else the next free one (the offset comes back)
fn allocateSpace(mut k Kernel, s i64, mut io u8[]):
	size = get32(io, 0) * get32(io, 4)
	if get32(io, 8) & 1 == 0: put64(io, 16, k.gpu.spaces[s].reserve(size, get32(io, 4)))
	nvOk

fn unmapBuffer(mut k Kernel, s i64, io u8[]):
	nvOk if k.gpu.spaces[s].unmap(get64(io, 0)) else nvBadValue

# MAP_BUFFER_EX: flags (bit 0: at the offset given, bit 8: the kind is given), the kind, an
# nvmap handle, the page size, the offset into the handle and the size to map (0: the rest); the
# offset in the space comes back. Handle 0 with the kind flag only changes the kind of the
# mapping at the offset.
fn mapBufferEx(mut k Kernel, s i64, mut io u8[]):
	handle = get32(io, 8)
	kind = get32(io, 4)
	at = get64(io, 32)
	if handle == 0 and get32(io, 0) & 0x100 != 0:
		k.gpu.spaces[s].setKind(at, kind)
		return nvOk
	n = k.nvmapIndex(handle)
	if n < 0 or k.nv.handles[n].address < 0: return nvBadParameter
	inside = get64(io, 16)
	size = get64(io, 24)
	if size == 0: size = k.nv.handles[n].size - inside
	if get32(io, 0) & 1 == 0: at = k.gpu.spaces[s].reserve(size, get32(io, 12).max(smallPage))
	k.gpu.spaces[s].map(at, size, k.nv.handles[n].address + inside, kind)
	put64(io, 32, at)
	nvOk

# GET_VA_REGIONS: the small page region and the big page region
fn vaRegions(k Kernel, s i64, mut io u8[]):
	regions = [
		(smallRegionStart, smallPage, (bigRegionStart - smallRegionStart) / smallPage),
		(
			bigRegionStart,
			k.gpu.spaces[s].bigPageSize,
			(addressEnd - bigRegionStart) / k.gpu.spaces[s].bigPageSize
		)
	]
	put32(io, 8, 0x30)
	for n, region in regions:
		start, page, pages = region
		put64(io, 16 + n * 24, start)
		put32(io, 24 + n * 24, page)
		put64(io, 32 + n * 24, pages)
	nvOk

# ALLOC_AS_EX (flags, the descriptor, the big page size): the big page size and the range of addresses the space hands out
fn allocateAddressSpace(mut k Kernel, s i64, io u8[]):
	big = get32(io, 8)
	if big != 0: k.gpu.spaces[s].bigPageSize = big
	if get64(io, 16) != 0: k.gpu.spaces[s].rangeStart = get64(io, 16)
	if get64(io, 24) != 0: k.gpu.spaces[s].rangeEnd = get64(io, 24)
	k.gpu.spaces[s].nextFree = bigRegionStart.max(k.gpu.spaces[s].rangeStart)
	nvOk

# REMAP: entries of 20 bytes (flags and kind as halves, an nvmap handle, the offsets in it and
# in the space, and the count, all in big pages); handle 0 unmaps the pages
fn remap(mut k Kernel, s i64, io u8[]):
	page = k.gpu.spaces[s].bigPageSize
	for e in 0..io.len / 20:
		handle = get32(io, e * 20 + 4)
		inside = get32(io, e * 20 + 8) * page
		at = get32(io, e * 20 + 12) * page
		size = get32(io, e * 20 + 16) * page
		n = k.nvmapIndex(handle)
		if handle == 0: k.gpu.spaces[s].unmap(at)
		elif n < 0: return nvBadParameter
		else: k.gpu.spaces[s].map(at, size, k.nv.handles[n].address + inside, 0)
	nvOk
