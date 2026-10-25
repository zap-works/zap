# Buffers, textures and samplers as both backends keep them, named by ids (their place in the
# device's lists), and what is done with them the same way: a write's checks and where its bytes
# go (a host-visible buffer's own memory, else the frame's ring, copied from there before the
# frame's passes), the ring's growth, the objects retired, the samplers shared by textures. The
# API objects behind them are each backend's (device.zap's Backend).

import win

pub type Buffer:
	handle i64   # what a draw names it by: Vulkan's VkBuffer, Direct3D 12's id + 1
	alloc Allocation   # its range of a block (alloc.mapped: the CPU's address when host-visible)
	address i64 = 0   # its GPU address (Direct3D 12's)
	size i64
	hostVisible bool
	live bool = true

pub type Texture:
	image i64   # a VkImage, an ID3D12Resource
	view i64   # how shaders read it: a VkImageView, the slot of its view in Direct3D 12's heap
	targetView i64 = -1   # Direct3D 12's render target or depth view (its slot), -1 none
	alloc Allocation   # its range of a block (block -1: memory of its own)
	format i64
	width i64
	height i64
	layers i64
	levels i64
	samples i64
	array bool
	depth bool
	volume bool = false   # a 3D texture, layers its depth
	cube bool = false   # read as cubes of six layers
	sampler i64 = 0   # the sampler it is read with (samplerFor's handle)
	live bool = true
	hostCopy bool = false   # (Vulkan) its pixels may be copied in by the CPU (host image copy)...
	untouched bool = false   # ...while no GPU work has named it yet (a frame may be reading it)
	target bool = false   # drawn into by passes
	use i64 = useRead   # what it is used for now (barriers.zap)

# shared by the textures read the same way
pub type SamplerRecord:
	desc SamplerDesc
	handle i64   # a VkSampler, an index of the samplers on Direct3D 12

# ---------- buffers ----------

# a buffer of `size` bytes for the usages: device-local, or host-visible (its writes direct)
pub fn newBuffer<B Backend>(mut b B, size i64, usage i64, hostVisible bool) i64:
	buffer Buffer = b.newBuffer(size, usage, hostVisible)
	s mut ref DeviceState = b.deviceState()
	s.buffers.push(buffer)
	s.buffers.len - 1

# the handle a draw names a buffer by (DrawCall's vertexBuffers, indexBuffer)
pub fn bufferHandle(s DeviceState, id i64) i64:
	s.buffers[id].handle

# the buffer freed once the frames that may read it are done
pub fn destroyBuffer(mut s DeviceState, id i64):
	if not s.buffers[id].live: return
	b = s.buffers[id]
	s.buffers[id].live = false
	retire(
		s,
		Retired(
			kind = retiredBuffer,
			handle = b.handle,
			block = b.alloc.block,
			offset = b.alloc.offset,
			size = b.alloc.size
		)
	)

# Where `n` bytes written into the buffer at offset go, the CPU's address to copy them to once:
# the buffer's own memory when it is host-visible, else the ring, its copy into the buffer
# recorded before the frame's passes (the bytes are there before the uploads are submitted).
# The CPU only writes there: host-visible memory is write-combined, slow to read back.
fn writeTarget<B Backend>(mut b B, id i64, offset i64, n i64) i64:
	s mut ref DeviceState = b.deviceState()
	buffer = s.buffers[id]
	if offset + n > buffer.size:
		fail("rhi: {n} bytes written at {offset} of a buffer of {buffer.size}")
	if buffer.hostVisible: return buffer.alloc.mapped + offset
	ring, ringOffset, at = staging(b, n, 16)
	copyFromRing(b, ring, ringOffset, id, offset, n)
	at

# The backend's copy of n bytes from the ring into a buffer. (A function of its own: the check of
# a generic's body does not count a local passed to a bound's method as read.)
fn copyFromRing<B Backend>(mut b B, ring i64, ringOffset i64, id i64, offset i64, n i64):
	b.copyFromRing(ring, ringOffset, id, offset, n)

# the bytes of a list of plain values (bytes, vertices, records) written into a buffer at `offset`
pub fn writeBuffer<B Backend, T Copy>(mut b B, id i64, offset i64, values T[]):
	n = values.byteSize
	if n > 0:
		win.memoryAt(writeTarget(b, id, offset, n), n).write(0, values)

pub fn writeBufferWords<B Backend>(mut b B, id i64, offset i64, words u32[]):
	n = words.len * 4
	if n > 0:
		win.memoryAt(writeTarget(b, id, offset, n), n).write(0, words)

# only the first `count`
pub fn writeBufferFloats<B Backend>(mut b B, id i64, offset i64, values f32[], count i64):
	n = count * 4
	if n > 0:
		win.memoryAt(writeTarget(b, id, offset, n), n).write(0, values[..count])

# Room for `n` bytes in this frame's ring: the ring's buffer handle, the offset there, and the
# CPU's address to write to. A full ring is replaced by one twice its size (the old one retired).
pub fn transient<B Backend>(mut b B, n i64, alignment i64) (i64, i64, i64):
	s mut ref DeviceState = b.deviceState()
	s.frames[s.frame].ringShared = true
	ringRoom(b, n, alignment)

# Room in the ring for bytes an upload copies out before the frame's passes (a texture level, a
# buffer's bytes). A full ring that only uploads use is emptied by running and waiting for the
# uploads so far, not grown: a level's hundreds of textures stage through one small ring.
pub fn staging<B Backend>(mut b B, n i64, alignment i64) (i64, i64, i64):
	s mut ref DeviceState = b.deviceState()
	f = s.frame
	full = ringPlace(s.frames[f].ringUsed, s.buffers[s.frames[f].ring].size, n, alignment) < 0
	fits = ringPlace(0, s.buffers[s.frames[f].ring].size, n, alignment) >= 0
	if full and fits and not s.frames[f].ringShared:
		b.flushUploads()
		t mut ref DeviceState = b.deviceState()
		t.frames[f].ringUsed = 0
		t.frames[f].ringPlaced = 0   # what went before is copied: the ring holds what follows
	ringRoom(b, n, alignment)

fn ringRoom<B Backend>(mut b B, n i64, alignment i64) (i64, i64, i64):
	s mut ref DeviceState = b.deviceState()
	f = s.frame
	ring = s.frames[f].ring
	used = s.frames[f].ringUsed
	at = ringPlace(used, s.buffers[ring].size, n, alignment)
	s.frames[f].ringPlaced += n + (at - used if at >= 0 else 0)
	if at < 0:
		bigger = ringGrown(s.buffers[ring].size, n)
		destroyBuffer(s, ring)
		ring = newBuffer(b, bigger, ringUsage(), true)
		u mut ref DeviceState = b.deviceState()
		u.frames[f].ring = ring
		at = 0
	t mut ref DeviceState = b.deviceState()
	t.frames[f].ringUsed = at + n
	buffer = t.buffers[ring]
	(buffer.handle, at, buffer.alloc.mapped + at)

# a buffer of zeros, read by an input a vertex layout does not feed
pub fn zeroBuffer<B Backend>(mut b B) i64:
	s mut ref DeviceState = b.deviceState()
	if s.zeros >= 0: return s.zeros
	zeros = newBuffer(b, 256, bufVertex, false)
	t mut ref DeviceState = b.deviceState()
	t.zeros = zeros
	writeBuffer(b, zeros, 0, fill(256, u8(0)))
	zeros

# ---------- textures ----------

# read sharp and clamped until setSampler
pub fn newTexture<B Backend>(mut b B, desc TextureDesc) i64:
	texture Texture = b.newTexture(desc)
	texture.target = desc.target
	texture.sampler = samplerFor(
		b,
		SamplerDesc(
			smooth = false,
			mipmaps = 0,
			repeat = false,
			mirror = 0,
			anisotropy = false,
			compare = false
		)
	)
	s mut ref DeviceState = b.deviceState()
	s.textures.push(texture)
	s.textures.len - 1

# the texture freed once the frames that may read it are done
pub fn destroyTexture(mut s DeviceState, id i64):
	if not s.textures[id].live: return
	t = s.textures[id]
	s.textures[id].live = false
	s.touchTables(id)
	s.retire(Retired(kind = retiredView, handle = t.view, block = -1, offset = 0, size = 0))
	retire(
		s,
		Retired(
			kind = retiredImage,
			handle = t.image,
			block = t.alloc.block,
			offset = t.alloc.offset,
			size = t.alloc.size
		)
	)
	if t.targetView >= 0:
		retire(
			s,
			Retired(
				kind = retiredDepthView if t.depth else retiredColorView,
				handle = t.targetView,
				block = -1,
				offset = 0,
				size = 0
			)
		)

# the pixels (4 bytes each, rows from the top) of a layer's first level replaced
pub fn writeTexture<B Backend>(mut b B, id i64, layer i64, pixels u8[]):
	writeTextureLevel(b, id, 0, layer, pixels)

# The bytes of a level of a layer replaced, as the texture's format lays them out (4 bytes a
# pixel, or blocks of 4x4 pixels: levelBytes): mip levels made ahead (a compressed texture's).
pub fn writeTextureLevel<B Backend>(mut b B, id i64, level i64, layer i64, bytes u8[]):
	s mut ref DeviceState = b.deviceState()
	t = s.textures[id]
	w = (t.width >> level).max(1)
	h = (t.height >> level).max(1)
	n = levelBytes(t.format, w, h)
	if bytes.len < n or level >= t.levels:
		fail("rhi: level {level} of a {t.width}x{t.height} texture of {t.levels} levels needs {n} bytes, got {bytes.len}")
	b.copyLevel(id, level, layer, w, h, bytes)

# Textures read when a draw names none, one of each sampler kind (placeholders[kind - 1]): a
# white texel (as a 2D texture, an array, a shadow map, a 3D texture, a cube, a cube array), zero
# integers.
pub fn placeholderTextures<B Backend>(mut b B):
	made = []
	for kind in 1..samplerKindCount + 1:
		cube = kind == samplerKindCube or kind == samplerKindCubeArray
		integer = kind == samplerKindInt or kind == samplerKindUint
		id = newTexture(
			b,
			TextureDesc(
				width = 1,
				height = 1,
				layers = 6 if cube else 1,
				levels = 1,
				format = (fmtR32Sint if kind == samplerKindInt else fmtR32Uint) if integer
				else fmtRgba8,
				samples = 1,
				array = isLayeredKind(kind),
				target = false,
				volume = kind == samplerKind3D,
				cube
			)
		)
		for layer in 0..(6 if cube else 1):
			writeTexture(b, id, layer, [u8(0), u8(0), u8(0), u8(0)] if integer else fill(4, u8(255)))
		made.push(id)
	s mut ref DeviceState = b.deviceState()
	s.placeholders = made

# whether a texture is read as a sampler kind's: of its dimension, layers or not, one sample
pub fn readsAs(t Texture, kind i64) bool:
	t.live and t.samples <= 1 and t.array == isLayeredKind(kind) and
		t.volume == (kind == samplerKind3D) and
		t.cube == (kind == samplerKindCube or kind == samplerKindCubeArray)

# the texture a draw reads at its program's sampler i: the one the draw names, else a placeholder
pub fn drawTexture(s DeviceState, program i64, i i64, call DrawCall) i64:
	s.textureOf(program, i, call.textures)

# the texture read at the program's sampler i of those named (per sampler binding), else a
# placeholder
pub fn textureOf(s DeviceState, program i64, i i64, textures ref i64[]) i64:
	slot = s.programs[program].samplers[i]
	id = textures[slot.binding] if slot.binding < textures.len else -1
	if id < 0 or not s.textures[id].live:
		return s.placeholders[i64(slot.kind) - 1]
	id

# the texture an array reads for an id: the texture, or a placeholder when the id names no live
# texture read as the array's kind
pub fn arrayTexture(s DeviceState, slot TextureArraySlot, id i64) i64:
	if id < 0 or id >= s.textures.len or not s.textures[id].readsAs(i64(slot.kind)):
		return s.placeholders[i64(slot.kind) - 1]
	id

# the buffer a draw names for its program's storage buffer i
pub fn drawStorage(s DeviceState, program i64, i i64, call DrawCall) i64:
	s.storageOf(program, i, call.storage)

# the buffer named (per storage binding) for the program's storage buffer i
pub fn storageOf(s DeviceState, program i64, i i64, storage ref i64[]) i64:
	local = s.programs[program].buffers[i] - bufferBase
	id = storage[local] if local < storage.len else -1
	if id < 0:
		fail("rhi: a draw or a compute run without the storage buffer its program reads at binding {local}")
	id

# ---------- samplers ----------

# how the texture is read from now on
pub fn setSampler<B Backend>(mut b B, id i64, desc SamplerDesc):
	sampler = samplerFor(b, desc)
	s mut ref DeviceState = b.deviceState()
	if sampler != s.textures[id].sampler:
		s.textures[id].sampler = sampler
		touchTables(s, id)

# the sampler of a description: the one made, else one made now
pub fn samplerFor<B Backend>(mut b B, desc SamplerDesc) i64:
	s mut ref DeviceState = b.deviceState()
	if s.samplers.find(isSameSampler(.desc, desc)) is made: return made.handle
	handle = b.newSampler(desc)
	t mut ref DeviceState = b.deviceState()
	t.samplers.push(SamplerRecord(desc = desc, handle = handle))
	handle

# the texture arrays' tables that hold a texture (destroyed, or read with another sampler) written
# again before they are read
fn touchTables(mut s DeviceState, id i64):
	for mut program in s.programs:
		program.lists.touchTexture(id)

# A texture read back is a target of one sample, of color: anything else stops the program.
pub fn checkReadable(t Texture):
	if not t.target or t.samples > 1 or t.depth or isBlockFormat(t.format):
		fail("rhi: only a color target of one sample is read back")
