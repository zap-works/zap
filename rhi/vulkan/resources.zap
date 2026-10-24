# Buffers, textures and samplers as Vulkan makes them (core's resources.zap names them by ids and
# keeps them). A buffer that stays is device-local and written through staging; what a frame
# hands the GPU once (its vertices, its parameters, the staging of an upload) comes from the
# frame's ring. A texture the CPU fills lives in the GENERAL layout (copied into and sampled
# without a layout change); one drawn into rests in SHADER_READ_ONLY_OPTIMAL, and the passes take
# it into their own layouts (commands.zap).

import win
import rhi.core

# ---------- buffers ----------

# a buffer of `size` bytes for the usages: device-local, or host-visible (its writes direct)
pub fn newBuffer(mut d Device, size i64, usage i64, hostVisible bool) core.Buffer:
	info = BufferCreateInfo(
		size = size.max(16),
		usage = usage & 0xFFFF_FFFF | core.bufTransferDst | core.bufTransferSrc   # (bufWritten is not Vulkan's)
	)
	check(vkCreateBuffer(d.device, info, 0, out handle), "vkCreateBuffer")
	req = MemoryRequirements()
	vkGetBufferMemoryRequirements(d.device, handle, req)
	alloc = d.allocate(req.size, req.alignment, req.typeBits, hostVisible)
	check(vkBindBufferMemory(d.device, handle, alloc.memory, alloc.offset), "vkBindBufferMemory")
	core.Buffer(handle, alloc, size = size.max(16), hostVisible)

# n bytes of the ring copied into a buffer, recorded before the frame's passes
pub fn copyFromRing(mut device Device, ring i64, ringOffset i64, id i64, offset i64, n i64):
	vkCmdCopyBuffer(
		device.uploadCommands(),
		ring,
		device.state.buffers[id].handle,
		1,
		BufferCopy(src = ringOffset, dst = offset, size = n)
	)

# ---------- textures ----------

pub fn newTexture(mut d Device, desc core.TextureDesc) core.Texture:
	if core.isBlockFormat(desc.format) and
		(not d.support.blocks or desc.target or desc.width % 4 != 0 or desc.height % 4 != 0):
		fail("rhi: a texture of BC blocks is {desc.width}x{desc.height} (sizes multiples of 4), not a target, on a device with textureCompressionBC")
	isDepth = core.isDepthFormat(desc.format)
	levels = desc.levelsOf()
	usage = imgSampled | imgTransferDst | imgTransferSrc
	if desc.target:
		usage |= imgDepthAttachment if isDepth else imgColorAttachment
	# a texture of pixels from the CPU takes them straight from it where the device can
	hostCopy = d.support.hostCopy and not desc.target and desc.format == core.fmtRgba8 and
		desc.samples <= 1
	if hostCopy:
		usage |= imgHostTransfer
	info = ImageCreateInfo(
		format = u32(desc.format),
		width = u32(desc.width),
		height = u32(desc.height),
		levels = u32(levels),
		layers = u32(desc.layers.max(1)),
		samples = u32(desc.samples.max(1)), usage = u32(usage))
	check(vkCreateImage(d.device, info, 0, out img), "vkCreateImage")
	req = MemoryRequirements()
	vkGetImageMemoryRequirements(d.device, img, req)
	alloc = d.allocate(req.size, req.alignment, req.typeBits, false)
	check(vkBindImageMemory(d.device, img, alloc.memory, alloc.offset), "vkBindImageMemory")
	aspect = wholeAspect(desc.format)
	# a depth and stencil texture read as its depth
	view = d.newView(
		img,
		desc.format,
		aspect & ~aspectStencil,
		desc.array,
		levels,
		desc.layers.max(1)
	)
	# a target into its rest (passes take it from there), any other into GENERAL, where it stays
	# (by the CPU at once, for a texture it copies into)
	if hostCopy:
		transition = HostImageLayoutTransitionInfo(
			image = img,
			oldLayout = u32(layoutUndefined),
			newLayout = u32(layoutGeneral),
			range = ImageSubresourceRange(
				aspect = u32(aspect),
				levels = u32(levels),
				layers = u32(desc.layers.max(1))
		))
		check(vkTransitionImageLayout(d.device, 1, transition), "vkTransitionImageLayout")
	else:
		imageBarrier(
			d.uploadCommands(),
			img,
			layoutUndefined,
			layoutShaderRead if desc.target else layoutGeneral,
			aspect,
			levels,
			desc.layers.max(1)
		)
	core.Texture(
		image = img,
		view,
		alloc,
		format = desc.format,
		width = desc.width,
		height = desc.height,
		layers = desc.layers.max(1),
		levels,
		samples = desc.samples.max(
			1
		), array = desc.array, depth = isDepth, hostCopy, untouched = true)

# A level (w x h) of a layer replaced by its bytes, as the format lays them out: copied in by the
# CPU at once while no GPU work has named the texture (host image copy), else staged through the
# ring and copied before the frame's passes.
pub fn copyLevel(mut d Device, id i64, level i64, layer i64, w i64, h i64, pixels u8[]):
	t = d.state.textures[id]
	n = core.levelBytes(t.format, w, h)
	corner = Offset3D(x = 0, y = 0, z = 0)
	extent = Extent3D(width = u32(w), height = u32(h), depth = 1)
	if t.hostCopy and t.untouched:
		region = MemoryToImageCopy(
			host = pixels,
			layers = layersAt(level, layer, 1),
			imageOffset = corner,
			extent
		)
		check(
			vkCopyMemoryToImage(d.device, CopyMemoryToImageInfo(image = t.image, layout = u32(layoutGeneral), regions = region)),
			"vkCopyMemoryToImage"
		)
		return
	d.state.textures[id].untouched = false
	ring, ringOffset, at = core.staging(d, n, 16)
	win.memoryAt(at, n).write(0, pixels[..n])
	cmd = d.uploadCommands()
	region = BufferImageCopy(
		offset = ringOffset,
		layers = layersAt(level, layer, 1),
		imageOffset = corner,
		extent
	)
	vkCmdCopyBufferToImage(cmd, ring, t.image, layoutGeneral, 1, region)
	copiesOrdered(cmd)

# each level below the first made from the one above it (halved, smoothed), every layer
pub fn generateMips(mut d Device, id i64):
	d.state.textures[id].untouched = false
	t = d.state.textures[id]
	if core.isBlockFormat(t.format):
		fail("rhi: the mip levels of a texture of BC blocks are written (writeTextureLevel), not made")
	cmd = d.uploadCommands()
	w = t.width
	h = t.height
	for level in 1..t.levels:
		nw = (w / 2).max(1)
		nh = (h / 2).max(1)
		corner = Offset3D(x = 0, y = 0, z = 0)
		blit = ImageBlit(
			src = layersAt(level - 1, 0, t.layers),
			srcOffsets = [corner, Offset3D(x = i32(w), y = i32(h), z = 1)],
			dst = layersAt(level, 0, t.layers), dstOffsets = [
				corner,
				Offset3D(x = i32(nw), y = i32(nh), z = 1)
		])
		vkCmdBlitImage(cmd, t.image, layoutGeneral, t.image, layoutGeneral, 1, blit, 1)
		copiesOrdered(cmd)
		w = nw
		h = nh

# the aspects of a texture of the format: its color, or its depth and stencil
pub fn wholeAspect(format i64) i64:
	if not core.isDepthFormat(format): return aspectColor
	aspectDepth | (aspectStencil if core.hasStencil(format) else 0)

# a level of a texture's color, its layers from `first`
fn layersAt(level i64, first i64, layers i64):
	ImageSubresourceLayers(
		aspect = u32(aspectColor),
		level = u32(level),
		baseLayer = u32(first),
		layers = u32(layers)
	)

# ---------- samplers ----------

# the VkSampler of a description
pub fn newSampler(mut d Device, desc core.SamplerDesc) i64:
	filter = u32(1 if desc.smooth else 0)
	wrap = u32(0 if desc.repeat else 3 if desc.compare else 2)   # REPEAT, CLAMP_TO_BORDER (lit), CLAMP_TO_EDGE
	# past a shadow map's edge, lit (FLOAT_OPAQUE_WHITE); a depth compared LESS_OR_EQUAL
	# MIRRORED_REPEAT along the axes it mirrors
	wrapU, wrapV = u32(1) if (desc.mirror & 1) != 0
		else wrap, u32(1) if (desc.mirror & 2) != 0
		else wrap
	info = SamplerCreateInfo(
		magFilter = filter,
		minFilter = filter,
		mipmapMode = 1 if desc.mipmaps == 2 else 0,
		addressU = wrapU,
		addressV = wrapV,
		addressW = wrap,
		anisotropyEnable = 1 if desc.anisotropy else 0,
		maxAnisotropy = 8.0,
		compareEnable = 1 if desc.compare else 0,
		compareOp = 3,
		maxLod = 0.25 if desc.mipmaps == 0 else 1000.0,
		border = 4)
	check(vkCreateSampler(d.device, info, 0, out handle), "vkCreateSampler")
	handle

# ---------- retired objects ----------

# a retired object destroyed (core's destroyRetired gives its memory back)
pub fn destroyObject(mut d Device, r core.Retired):
	if r.kind == core.retiredBuffer:
		vkDestroyBuffer(d.device, r.handle, 0)
	elif r.kind == core.retiredImage:
		vkDestroyImage(d.device, r.handle, 0)
	elif r.kind == core.retiredView:
		vkDestroyImageView(d.device, r.handle, 0)
	elif r.kind == retiredPool:
		vkDestroyDescriptorPool(d.device, r.handle, 0)
	elif r.kind == retiredFramebuffer:
		vkDestroyFramebuffer(d.device, r.handle, 0)
