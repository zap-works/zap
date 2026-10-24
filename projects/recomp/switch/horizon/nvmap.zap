# /dev/nvmap, the memory the GPU's buffers are made of (switchbrew: NV services#nvmap): a handle
# is made with a size, then given the address of the process's memory that backs it, which the
# GPU's address spaces later map.

# the heap every handle lives in (the carveout)
heapCarveout = 0x4000_0000

pub type NvHandle:
	size i64
	address i64 = -1
	alignment i64 = 0
	kind i64 = 0
	flags i64 = 0
	heap i64 = 0
	freed bool = false

# the handle's index in Nv.handles, -1 for one that does not exist
fn nvmapIndex(k Kernel, handle i64):
	if handle < 1 or handle > k.nv.handles.len or k.nv.handles[handle - 1].freed: return -1
	handle - 1

# the guest address of a handle's memory, -1 when it has none
pub fn nvmapAddress(k Kernel, handle i64) i64:
	n = k.nvmapIndex(handle)
	-1 if n < 0 else k.nv.handles[n].address

fn nvmapIoctl(mut k Kernel, cmd i64, mut io u8[]) i64:
	match cmd:
		0x0101:   # CREATE
			k.nv.handles.push(NvHandle(size = get32(io, 0)))
			put32(io, 4, k.nv.handles.len)
			nvOk
		0x0103, 0x010E: k.nvmapIdentity(cmd, io)   # FROM_ID, GET_ID
		0x0104: k.nvmapAllocate(io)   # ALLOC
		0x0105: k.nvmapRelease(io)   # FREE
		0x0109: k.nvmapQuery(io)   # PARAM
		_: nvNotSupported

# FROM_ID and GET_ID: a handle is its own id
fn nvmapIdentity(k Kernel, cmd i64, mut io u8[]):
	if cmd == 0x0103:
		put32(io, 4, get32(io, 0))
		return nvOk
	put32(io, 0, get32(io, 4))
	nvOk

fn nvmapAllocate(mut k Kernel, mut io u8[]):
	n = k.nvmapIndex(get32(io, 0))
	if n < 0: return nvBadParameter
	k.nv.handles[n].heap = get32(io, 4)
	k.nv.handles[n].flags = get32(io, 8)
	k.nv.handles[n].alignment = get32(io, 12)
	k.nv.handles[n].kind = io[16]
	k.nv.handles[n].address = get64(io, 24)
	nvOk

fn nvmapRelease(mut k Kernel, mut io u8[]):
	n = k.nvmapIndex(get32(io, 0))
	if n < 0: return nvBadParameter
	put64(io, 8, k.nv.handles[n].address)
	put32(io, 16, k.nv.handles[n].size)
	put32(io, 20, 0)
	k.nv.handles[n].freed = true
	nvOk

fn nvmapQuery(k Kernel, mut io u8[]):
	n = k.nvmapIndex(get32(io, 0))
	if n < 0: return nvBadParameter
	value = match get32(io, 4):
		1: k.nv.handles[n].size   # SIZE
		2: k.nv.handles[n].alignment   # ALIGNMENT
		4: heapCarveout   # HEAP
		5: k.nv.handles[n].kind   # KIND
		_: return nvNotSupported
	put32(io, 8, value)
	nvOk
