# Buffers, textures and samplers as Direct3D 12 makes them (core's resources.zap names them by ids
# and keeps them). A buffer is a range of a block: a 4 MB buffer of the default heap (written
# through the frame's ring and copied before the frame's passes) or of the upload heap (written
# by the CPU where it is mapped); a draw names a buffer by its id + 1 (0 is none). A texture is placed in a 4 MB heap
# of textures, or (a target, drawn into) a committed resource. A texture rests readable by any
# stage: a pass moves its targets to drawing and back, the uploads list moves what it copies
# into to copying and back when it closes; a buffer block rests readable and is moved to copying
# the same way. Mip levels are made on the GPU, each drawn from the level above by a screen pass
# of the uploads list (Direct3D 12 has no blit), halved as Vulkan's linear blit halves them: a
# texture of mip levels may be drawn into, so it lives in a heap of such textures.

import win
import rhi.core

# memory kinds of the blocks (core's memory.zap): buffers of a heap type, textures' heaps
kindDefaultBuffers = 1
kindUploadBuffers = 2
kindWrittenBuffers = 4   # of the default heap, written by compute stages (unordered access)
kindTextures = 10
kindDrawnTextures = 11   # a texture of mip levels (each drawn from the level above)

# ---------- memory ----------

# a range of a buffer block of the kind (kindDefaultBuffers...)
fn bufferRange(mut d Device, size i64, kind i64):
	if d.state.memory.rangeIn(kind, size, 256) is a: return a
	heapType = kindUploadBuffers if kind == kindUploadBuffers else kindDefaultBuffers
	bytes = size.max(core.blockSize).alignUp(65_536)
	desc = ResourceDesc(
		dimension = 1,
		width = bytes,
		height = 1,
		depthOrArraySize = 1,
		mipLevels = 1,
		format = 0,
		layout = 1,
		flags = u32(4 if kind == kindWrittenBuffers else 0)   # ALLOW_UNORDERED_ACCESS
	)
	state = stateGenericRead if heapType == kindUploadBuffers else stateCommon
	check(
		deviceCreateCommittedResource(d.device, HeapProperties(kind = u32(heapType)), 0, desc, state, 0, iidResource, out resource),
		"CreateCommittedResource (a buffer)"
	)
	mapped = mapResource(resource) if heapType == kindUploadBuffers else 0
	d.blockAddresses.push(gpuAddress(resource))
	a = d.state.memory.rangeInNew(resource, kind, bytes, mapped, size)
	if heapType == kindDefaultBuffers:
		# from common to resting readable, before anything reads it
		transition(d.uploadCommands(), resource, stateCommon, stateBufferRead)
	a

# a range of a texture heap for a resource of the description (`drawn`: one that allows render
# targets, in a heap of those): its offset and the heap
fn textureRange(mut d Device, mut desc ResourceDesc, drawn bool) core.Allocation:
	info = AllocationInfo()
	desc.alignment = 4096   # a small texture's alignment, when it may have it
	deviceGetResourceAllocationInfo(d.device, info, 0, 1, desc)
	if info.alignment != 4096:
		desc.alignment = 0
		deviceGetResourceAllocationInfo(d.device, info, 0, 1, desc)
	kind = kindDrawnTextures if drawn else kindTextures
	if d.state.memory.rangeIn(kind, info.size, info.alignment) is a: return a
	bytes = info.size.max(core.blockSize).alignUp(65_536)
	# DENY_BUFFERS and DENY_RT_DS_TEXTURES, or DENY_NON_RT_DS_TEXTURES
	heapDesc = HeapDesc(
		size = bytes,
		properties = HeapProperties(kind = 1),
		flags = 0x84 if drawn else 0x44
	)
	check(deviceCreateHeap(d.device, heapDesc, iidHeap, out heap), "CreateHeap")
	d.blockAddresses.push(0)
	d.state.memory.rangeInNew(heap, kind, bytes, 0, info.size)

# ---------- buffers ----------

# A buffer of `size` bytes: in the default heap, or host-visible (its writes direct). A draw
# names it by its id + 1: the buffers' next id + 1.
pub fn newBuffer(mut device Device, size i64, usage i64, hostVisible bool) core.Buffer:
	n = size.max(16)
	kind = kindUploadBuffers if hostVisible
		else kindWrittenBuffers if usage & core.bufWritten != 0
		else kindDefaultBuffers
	a = device.bufferRange(n, kind)
	core.Buffer(
		handle = device.state.buffers.len + 1,
		alloc = a,
		address = device.blockAddresses[a.block] + a.offset,
		size = n,
		hostVisible
	)

# a buffer block left for copies until the uploads list closes
fn copyInto(mut d Device, block i64):
	mark = -1 - block
	if mark not in d.uploadTouched:
		transition(
			d.uploadCommands(),
			d.state.memory.blocks[block].memory,
			stateBufferRead,
			stateCopyDest
		)
		d.uploadTouched.push(mark)

# n bytes of the ring (its handle: its buffer id + 1) copied into a buffer, recorded before the
# frame's passes
pub fn copyFromRing(mut device Device, ring i64, ringOffset i64, id i64, offset i64, n i64):
	b = device.state.buffers[id]
	device.copyInto(b.alloc.block)
	r = device.state.buffers[ring - 1]
	listCopyBufferRegion(
		device.uploadCommands(),
		b.alloc.memory,
		b.alloc.offset + offset,
		r.alloc.memory,
		r.alloc.offset + ringOffset,
		n
	)

# ---------- textures ----------

pub fn newTexture(mut d Device, desc core.TextureDesc) core.Texture:
	if core.isBlockFormat(desc.format) and
		(desc.target or desc.width % 4 != 0 or desc.height % 4 != 0):
		fail("rhi: a texture of BC blocks is {desc.width}x{desc.height} (sizes multiples of 4), not a target")
	isDepth = core.isDepthFormat(desc.format)
	levels = desc.levelsOf()
	layers = desc.layers.max(1)
	samples = desc.samples.max(1)
	# ALLOW_DEPTH_STENCIL or ALLOW_RENDER_TARGET (a target, or a texture of mip levels drawn: not
	# one of blocks, whose levels are written)
	drawn = not desc.target and levels > 1 and not isDepth and samples == 1 and
		not core.isBlockFormat(desc.format)
	flags = 1 if drawn else 0
	if desc.target:
		flags = 2 if isDepth else 1
	# a 2D texture's layers (a cube's six faces each), or a 3D one's depth
	rd = ResourceDesc(
		dimension = 4 if desc.volume else 3,
		width = desc.width,
		height = u32(desc.height),
		depthOrArraySize = u16(layers),
		mipLevels = u16(levels),
		format = u32(typelessFormat(
			desc.format
		)), sampleCount = u32(samples), flags = u32(flags))
	resource = 0
	alloc = core.Allocation(block = -1, offset = 0, size = 0, memory = 0, mapped = 0)
	if desc.target:
		# committed, with the value it is cleared to most
		clear = ClearValue(
			format = u32(dxgiFormat(desc.format)),
			values = [f32(1.0), 0.0, 0.0, 0.0]
		) if isDepth
			else ClearValue(
				format = u32(dxgiFormat(desc.format)),
				values = [f32(0.0), 0.0, 0.0, 0.0]
			)
		check(
			deviceCreateCommittedTarget(d.device, HeapProperties(kind = 1), 0, rd, stateShaderResource, clear, iidResource, out committed),
			"CreateCommittedResource (a target)"
		)
		resource = committed
	else:
		alloc = d.textureRange(rd, drawn)
		check(
			deviceCreatePlacedResource(d.device, alloc.memory, alloc.offset, rd, stateShaderResource, 0, iidResource, out placed),
			"CreatePlacedResource (a texture)"
		)
		resource = placed
	view = takeSlot(d.destroyViews, "texture views")
	deviceCreateShaderResourceView(
		d.device,
		resource,
		desc.viewDesc(levels, layers, samples),
		d.viewCpuStart + view * d.viewSize
	)
	targetView = -1
	if desc.target and not isDepth:
		targetView = takeSlot(d.destroyRtvs, "render target views")
		deviceCreateRenderTargetView(d.device, resource, 0, d.rtvHandle(targetView))
	elif desc.target:
		targetView = takeSlot(d.destroyDsvs, "depth views")
		deviceCreateDepthStencilView(
			d.device,
			resource,
			DepthStencilViewDesc(format = u32(dxgiFormat(desc.format)), dimension = u32(5 if samples > 1 else 3)),
			d.dsvHandle(targetView))
	core.Texture(
		image = resource,
		view,
		targetView,
		alloc,
		format = desc.format,
		width = desc.width,
		height = desc.height,
		layers,
		levels, samples, array = desc.array, depth = isDepth, volume = desc.volume, cube = desc.cube)

# how shaders read the texture: 2D, an array, multisampled, 3D (a, b: the first level, the
# levels), a cube (the same), cubes (a, b, c, d: the first level, the levels, the first face,
# the cubes)
fn viewDesc(desc core.TextureDesc, levels i64, layers i64, samples i64):
	format = u32(readFormat(desc.format))
	if samples > 1: return ShaderResourceViewDesc(format, dimension = 6)
	if desc.volume: return ShaderResourceViewDesc(format, dimension = 8, a = 0, b = u32(levels))
	if desc.cube and desc.array:
		return ShaderResourceViewDesc(
			format,
			dimension = 10,
			a = 0,
			b = u32(levels),
			c = 0,
			d = u32(layers / 6)
		)
	if desc.cube: return ShaderResourceViewDesc(format, dimension = 9, a = 0, b = u32(levels))
	if desc.array:
		return ShaderResourceViewDesc(
			format,
			dimension = 5,
			a = 0,
			b = u32(levels),
			c = 0,
			d = u32(layers)
		)
	ShaderResourceViewDesc(format, dimension = 4, a = 0, b = u32(levels))

# a texture left for copies until the uploads list closes
fn copyIntoTexture(mut d Device, id i64):
	if id not in d.uploadTouched:
		transition(
			d.uploadCommands(),
			d.state.textures[id].image,
			stateShaderResource,
			stateCopyDest
		)
		d.uploadTouched.push(id)

# what the uploads list left for copies put back to rest
fn restUploads(mut d Device, cmd i64):
	barriers = []
	for mark in d.uploadTouched:
		if mark < 0:
			barriers.push(
				ResourceBarrier(
					resource = d.state.memory.blocks[-1 - mark].memory,
					before = u32(stateCopyDest),
					after = u32(stateBufferRead)
				)
			)
		else:
			barriers.push(
				ResourceBarrier(
					resource = d.state.textures[mark].image,
					before = u32(stateCopyDest),
					after = u32(stateShaderResource)
				)
			)
	if not barriers.isEmpty:
		listResourceBarrier(cmd, barriers.len, barriers)
	d.uploadTouched = []

# A level (w x h) of a layer written: its rows (of pixels, or of blocks) staged in the ring at the
# pitch copies want (256 bytes), the footprint of a level of blocks whole blocks.
pub fn copyLevel(mut device Device, id i64, level i64, layer i64, w i64, h i64, pixels u8[]):
	t = device.state.textures[id]
	row, rows = core.levelRows(t.format, w, h)
	pitch = row.alignUp(256)
	ring, ringOffset, at = core.staging(device, pitch * rows, 512)
	room = win.memoryAt(at, pitch * rows)
	if pitch == row:
		room.write(0, pixels[..row * rows])
	else:
		# row by row from the list (never read back from the ring: write-combined)
		for k in 0..rows:
			room.write(k * pitch, pixels[k * row..(k + 1) * row])
	device.copyIntoTexture(id)
	r = device.state.buffers[ring - 1]
	blocks = core.isBlockFormat(t.format)
	# a 3D texture's layer is a slice of its depth, at that z of the level
	destination = TextureCopyLocation(
		resource = t.image,
		kind = 0,
		offset = level if t.volume else level + layer * t.levels
	)
	source = TextureCopyLocation(
		resource = r.alloc.memory,
		kind = 1,
		offset = r.alloc.offset + ringOffset,
		format = u32(dxgiFormat(t.format)),
		width = u32(w.alignUp(4) if blocks else w), height = u32(
			h.alignUp(4) if blocks else h
		), rowPitch = u32(pitch))
	listCopyTextureRegion(
		device.uploadCommands(),
		destination,
		0,
		0,
		layer if t.volume else 0,
		source,
		0
	)

# Each level below the first made from the one above it (halved and smoothed as a linear blit
# does), every layer: on the GPU, in the uploads list after the copies of the first level, a
# screen pass of mips.gpu.zap drawn into each level and layer (its target view written into the
# one slot kept for them) reading the level above (a view of that one level and layer in the
# frame's ring of views), each moved to drawing and back to rest around its draw.
pub fn generateMips(mut d Device, id i64):
	t = d.state.textures[id]
	if core.isBlockFormat(t.format):
		fail("rhi: the mip levels of a texture of BC blocks are written (writeTextureLevel), not made")
	if t.levels < 2 or t.samples > 1 or t.depth: return
	program = mipProgram(d)
	cmd = d.uploadCommands()
	# the copies into the first level done: the whole texture back at rest (readable)
	if id in d.uploadTouched:
		transition(cmd, t.image, stateCopyDest, stateShaderResource)
		d.uploadTouched.remove(d.uploadTouched.indexOf(id) ?? 0)
	listSetDescriptorHeaps(cmd, 2, [d.srvHeap, d.samplerHeap])
	listSetGraphicsRootSignature(cmd, d.programs[program].rootSignature)
	# a target's state bits: no culling, clockwise faces in front, no depth
	e = core.pipelineOf(d, program, core.PipelineKey(
		layout = -1,
		blend = core.blendNone,
		alphaToCoverage = false,
		lines = false,
		colorFormat = t.format,
		depthFormat = core.fmtUndefined,
		samples = 1, bits = 2))
	listSetPipelineState(cmd, e.pipeline)
	listIASetPrimitiveTopology(cmd, 4)
	# the parameters: none but the y flip of a target (rows from the first, as the levels hold them)
	ring, offset, at = core.transient(d, 16, 256)
	win.memoryAt(at, 16).write(0, [-f32(1.0), 0.0, 0.0, 0.0])
	listSetGraphicsRootConstantBufferView(cmd, 0, d.state.buffers[ring - 1].address + offset)
	listSetGraphicsRootDescriptorTable(
		cmd,
		bufferParameter(0) + 1,
		d.samplerGpuStart + d.mipSampler * d.samplerSize
	)
	format = u32(readFormat(t.format))
	f = d.state.frame
	for layer in 0..t.layers:
		w = t.width
		h = t.height
		for level in 1..t.levels:
			nw = (w / 2).max(1)
			nh = (h / 2).max(1)
			# the level above, one layer of it, in the frame's ring of views
			if d.frames[f].viewsUsed + 1 > ringViews:
				fail("rhi: a frame uses more than {ringViews} texture views")
			slot = f * ringViews + d.frames[f].viewsUsed
			d.frames[f].viewsUsed += 1
			deviceCreateShaderResourceView(
				d.device,
				t.image,
				ShaderResourceViewDesc(format, dimension = 5, a = u32(level - 1), b = 1, c = u32(layer), d = 1),
				d.srvCpuStart + slot * d.viewSize)
			listSetGraphicsRootDescriptorTable(
				cmd,
				bufferParameter(0),
				d.srvGpuStart + slot * d.viewSize
			)
			# this level of this layer as the target (a target view is read when it is set: one slot serves every draw)
			rtv = d.mipTarget
			deviceCreateRenderTargetViewOf(
				d.device,
				t.image,
				RenderTargetViewDesc(format = u32(dxgiFormat(t.format)), mip = u32(level), firstLayer = u32(layer)),
				d.rtvHandle(rtv))
			sub = u32(level + layer * t.levels)
			listResourceBarrier(
				cmd,
				1,
				[
					ResourceBarrier(
						resource = t.image,
						subresource = sub,
						before = u32(stateShaderResource),
						after = u32(stateRenderTarget)
					)
				]
			)
			listOMSetColorTarget(cmd, 1, [d.rtvHandle(rtv)], 1, 0)
			listRSSetViewports(
				cmd,
				1,
				Viewport(x = 0.0, y = 0.0, width = f32(nw), height = f32(nh))
			)
			listRSSetScissorRects(cmd, 1, Rect(right = i32(nw), bottom = i32(nh)))
			listDrawInstanced(cmd, 3, 1, 0, 0)
			listResourceBarrier(
				cmd,
				1,
				[
					ResourceBarrier(
						resource = t.image,
						subresource = sub,
						before = u32(stateRenderTarget),
						after = u32(stateShaderResource)
					)
				]
			)
			w = nw
			h = nh

# the program mip levels are made with, its sampler (linear, clamped) and its target view's slot,
# made the first time
fn mipProgram(mut d Device):
	if d.mipProgram < 0:
		d.mipProgram = core.newProgram(d, shader(mips.pixel))
		d.mipSampler = d.samplerRange(1)
		d.mipTarget = takeSlot(d.destroyRtvs, "render target views")
		deviceCreateSampler(
			d.device,
			samplerDescription(core.SamplerDesc(smooth = true, mipmaps = 0, repeat = false, mirror = 0, anisotropy = false, compare = false)),
			d.samplerCpuStart + d.mipSampler * d.samplerSize)
	d.mipProgram

# ---------- samplers ----------

# the Direct3D sampler of a description, as Vulkan's (resources.zap there) reads
fn samplerDescription(desc core.SamplerDesc):
	# point or linear filtering, its mip levels nearest or blended; anisotropic when smooth;
	# a comparison's filter for a shadow map
	mipLinear = 1 if desc.mipmaps == 2 else 0
	filter = 0x14 | mipLinear if desc.smooth else mipLinear
	if desc.anisotropy and desc.smooth:
		filter = 0x55
	if desc.compare:
		filter |= 0x80
	# WRAP 1, MIRROR 2, CLAMP 3, BORDER 4 (a shadow map lit past its edges)
	wrap = 1 if desc.repeat else 4 if desc.compare else 3
	u = 2 if (desc.mirror & 1) != 0 else wrap
	v = 2 if (desc.mirror & 2) != 0 else wrap
	SamplerDescription(
		filter = u32(filter),
		addressU = u32(u),
		addressV = u32(v),
		addressW = u32(wrap),
		maxAnisotropy = u32(8 if desc.anisotropy else 1),
		compare = u32(4 if desc.compare else 1),
		border = [f32(1.0), 1.0, 1.0, 1.0],
		maxLod = 0.25 if desc.mipmaps == 0 else 1000.0)

# ---------- retired objects ----------

# a retired object let go (core's destroyRetired gives its memory back)
pub fn destroyObject(mut device Device, r core.Retired):
	if r.kind == core.retiredImage:
		win.release(r.handle)
	elif r.kind == core.retiredView:
		device.destroyViews.push(r.handle)
	elif r.kind == core.retiredColorView:
		device.destroyRtvs.push(r.handle)
	elif r.kind == core.retiredDepthView:
		device.destroyDsvs.push(r.handle)
	elif r.kind == retiredViewRange or r.kind == retiredSamplerRange:
		device.slots.release(0 if r.kind == retiredViewRange else 1, r.handle, r.size)
