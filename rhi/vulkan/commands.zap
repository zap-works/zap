# What a frame records: passes (dynamic rendering into a color target, a depth target or both,
# the screen being the swapchain image; render passes where the device has no dynamic rendering,
# renderpass.zap), draws inside them, and what happens between them
# (resolving a multisampled target, compute stages). Each begins after a barrier made of what it
# and the work before it use (core's barriers.zap): a target waits only for the stages that read
# or wrote it, in its own layout; a texture drawn into rests in SHADER_READ_ONLY_OPTIMAL, one the
# CPU fills in GENERAL.
#
# The engine's clip space has y up, and its texture places start at a target's first row: the
# screen is drawn with its viewport flipped (y up), a target as it comes, so what a target holds
# reads back the way it was drawn. Counter-clockwise faces are in front on the flipped screen,
# clockwise ones in a target (the same faces, seen through the flip or not).

import win
import rhi.core

# ---------- barriers ----------

# the stages `dst` (their access `read`) after the stages `src`, whose access `written` is made
# visible to them
pub fn memoryBarrier(cmd i64, src i64, written i64, dst i64, read i64):
	barrier = MemoryBarrier(srcAccess = u32(written), dstAccess = u32(read))
	vkCmdPipelineBarrier(cmd, src, dst, 0, 1, [barrier], 0, 0, 0, [])

# a copy after the copies before it (into the same texture: a level twice, the mips' blits)
pub fn copiesOrdered(cmd i64):
	memoryBarrier(cmd, stageTransfer, accessTransferWrite, stageTransfer, transferAccess)

transferAccess = accessTransferRead | accessTransferWrite

# waits for every write before it; levels and layers count from the first
pub fn imageBarrier(cmd i64, image i64, from i64, to i64, aspect i64, levels i64, layers i64):
	barrier = ImageMemoryBarrier(
		srcAccess = u32(accessAll),
		dstAccess = u32(accessAll),
		oldLayout = u32(from),
		newLayout = u32(to),
		image,
		range = ImageSubresourceRange(
			aspect = u32(aspect),
			levels = u32(levels),
			layers = u32(layers)
	))
	vkCmdPipelineBarrier(cmd, stageAllCommands, stageAllCommands, 0, 0, [], 0, 0, 1, [barrier])

shaderStages = stageVertexShader | stageFragmentShader | stageCompute
writeAccess = accessShaderWrite | accessColorWrite | accessDepthWrite | accessTransferWrite

# a use's image layout, the stages it runs in and its access
fn syncOf(use i64):
	if use == core.useColor:
		return (layoutColorAttachment, stageColorOutput, accessColorRead | accessColorWrite)
	if use == core.useDepth:
		return (layoutDepthAttachment, stageFragmentTests, accessDepthRead | accessDepthWrite)
	if use == core.useResolveFrom or use == core.useCopyFrom:
		return (layoutTransferSrc, stageTransfer, accessTransferRead)
	if use == core.useResolveInto: return (layoutTransferDst, stageTransfer, accessTransferWrite)
	if use == core.useNone: return (layoutUndefined, stageColorOutput, 0)
	(layoutShaderRead, shaderStages, accessShaderRead)

# the image of a texture or the screen: its aspect, levels and layers
fn imageOf(d Device, texture i64):
	if texture == core.screenTarget: return (d.swapImages[d.image], aspectColor, 1, 1)
	t = d.state.textures[texture]
	(t.image, wholeAspect(t.format), t.levels, t.layers)

# The transitions as one barrier, with the work and memory of the buffers it also orders (stages
# `src` before `dst`, `memory`): each image from its use's layout to the next one's (from
# undefined when what it holds is discarded), after its use's stages (their writes made visible)
# and before the next one's. Nothing is recorded when there is nothing to order.
pub fn barrier(
	d Device,
	cmd i64,
	moves core.Transition[],
	src i64,
	dst i64,
	memory MemoryBarrier[]
):
	images = []
	srcStages = src
	dstStages = dst
	for m in moves:
		fromLayout, fromStages, fromAccess = syncOf(m.from)
		toLayout, toStages, toAccess = syncOf(m.to)
		srcStages |= fromStages
		dstStages |= toStages
		image, aspect, levels, layers = d.imageOf(m.texture)
		images.push(ImageMemoryBarrier(
			srcAccess = u32(fromAccess & writeAccess),
			dstAccess = u32(toAccess),
			oldLayout = u32(layoutUndefined if m.discard else fromLayout),
			newLayout = u32(toLayout),
			image,
			range = ImageSubresourceRange(
				aspect = u32(aspect),
				levels = u32(levels),
				layers = u32(layers)
		)))
	if srcStages == 0: return
	vkCmdPipelineBarrier(cmd, srcStages, dstStages, 0, memory.len, memory, 0, 0, images.len, images)

# the layout a shader reads a texture in: a target's at rest, GENERAL for one the CPU fills
# how a shader reads a sampler slot of the kind: a combined image sampler, or a storage image
pub fn descriptorOf(kind i64) i64:
	descStorageImage if core.isImageKind(kind) else descSampledImage

pub fn readLayout(t core.Texture) i64:
	layoutShaderRead if t.target else layoutGeneral

# ---------- passes ----------

# Begins a pass into the color targets (textures, or the screen alone) and the depth target (a
# texture or none), each cleared first or kept as it was.
pub fn beginTargets(mut d Device, colors i64[], depth i64, clearColor Vec4?, clearDepth bool):
	d.endPass()
	cmd = d.frames[d.state.frame].commands
	moves = d.state.takeTextures(core.passUses(colors, depth, clearColor != none, clearDepth))
	d.barrier(cmd, moves, 0, 0, [])
	p = d.state.openPass(colors, depth)
	colorViews = colors.map(
		d.swapViews[d.image] if it == core.screenTarget else d.state.textures[it].view
	)
	depthView = d.state.textures[depth].view if depth >= 0 else 0
	d.state.pass = p
	core.stampPass(d, true)
	if not d.support.dynamicRendering:
		views = colorViews.copy()
		if d.state.pass.depthFormat != core.fmtUndefined:
			views.push(depthView)
		d.beginRenderPass(cmd, views, clearColor, clearDepth)
		d.setRects(cmd, core.RasterState())
		return
	colorAttachments = colorViews.map(attachment(it, layoutColorAttachment, clearColor))
	depthClear Vec4? = none
	if clearDepth:
		depthClear = Vec4(r = 1.0, g = 0.0, b = 0.0, a = 0.0)
	depthAttachment = attachment(depthView, layoutDepthAttachment, depthClear)
	area = Rect2D(width = u32(d.state.pass.width), height = u32(d.state.pass.height))
	info = RenderingInfo(
		area,
		colorCount = u32(colorAttachments.len),
		colors = colorAttachments,
		depth = depthAttachment if depthView != 0 else none,
		stencil = none
	)
	vkCmdBeginRendering(cmd, info)
	d.setRects(cmd, core.RasterState())

# The viewport and scissor of a draw's raster state set (none: the whole target): the screen's
# viewport flipped so that y goes up.
fn setRects(d Device, cmd i64, raster core.RasterState):
	p ref core.Pass = d.state.pass
	v = raster.viewportOf(p.width, p.height)
	r = raster.scissorOf(p.width, p.height)
	viewport = Viewport(
		x = v.x,
		y = v.y + v.height,
		width = v.width,
		height = -v.height,
		minDepth = v.near,
		maxDepth = v.far
	)
		if p.color == core.screenTarget
		else Viewport(
			x = v.x,
			y = v.y,
			width = v.width,
			height = v.height,
			minDepth = v.near,
			maxDepth = v.far
		)
	vkCmdSetViewport(cmd, 0, 1, viewport)
	vkCmdSetScissor(
		cmd,
		0,
		1,
		Rect2D(x = i32(r.x), y = i32(r.y), width = u32(r.width), height = u32(r.height))
	)

# a rendering attachment: the view in its layout, cleared to `clear` (a color, or the depth
# first) and stored, or loaded
fn attachment(view i64, layout i64, clear Vec4?):
	match clear:
		c: RenderingAttachment(
			view,
			layout = u32(layout),
			loadOp = 1,
			clear = [c.r, c.g, c.b, c.a]
		)
		none: RenderingAttachment(
			view,
			layout = u32(layout),
			loadOp = 0,
			clear = fill(4, f32(0.0))
		)

# The pass's targets cleared where they are: color target `index` (-1 every one) to c, the depth
# to `depth`.
pub fn clearTargets(mut d Device, c Vec4?, index i64, depth f32?):
	p ref core.Pass = d.state.pass
	if not p.active: return
	clears = []
	if c is color:
		if p.color != core.noTarget:
			for k in 0..1 + p.extraColors.len:
				if index < 0 or index == k:
					clears.push(
						ClearAttachment(
							aspect = u32(aspectColor),
							attachment = u32(k),
							value = [color.r, color.g, color.b, color.a]
						)
					)
	if depth is z:
		if p.depth != core.noTarget:
			clears.push(
				ClearAttachment(
					aspect = u32(aspectDepth),
					attachment = 0,
					value = [z, 0.0, 0.0, 0.0]
				)
			)
	if clears.isEmpty: return
	rect = ClearRect(rect = Rect2D(width = u32(p.width), height = u32(p.height)))
	vkCmdClearAttachments(d.frames[d.state.frame].commands, clears.len, clears, 1, rect)

# does nothing outside a pass
pub fn endPass(mut d Device):
	if d.state.pass.active:
		cmd = d.frames[d.state.frame].commands
		if d.support.dynamicRendering: vkCmdEndRendering(cmd) else: vkCmdEndRenderPass(cmd)
		core.stampPass(d, false)
		d.state.pass.active = false

# ---------- draws ----------

# sets only the pipeline, dynamic state, descriptors and buffers that changed
pub fn draw(mut d Device, call core.DrawCall):
	if not d.state.drawReady(call): return
	cmd = d.frames[d.state.frame].commands
	# the pipeline's state bits are dynamic (none in its key) where the device sets them so
	bits = 0 if d.support.dynamicState else d.state.pass.stateBits(call)
	e = core.pipelineFor(d, call.program, call.layout, call.state, bits)
	bindsPipeline, bindsIndex = d.state.drawBinds(e.pipeline, call.indexBuffer)
	if bindsPipeline:
		vkCmdBindPipeline(cmd, 0, e.pipeline)
	d.setDynamicState(cmd, call)
	d.bindVertices(cmd, call, e.zeroBinding)
	d.pushDescriptors(cmd, call)
	if d.programs[call.program].arraysLayout != 0:
		d.bindTextureArrays(cmd, call.program, 0)
	if bindsIndex:
		vkCmdBindIndexBuffer(cmd, call.indexBuffer, 0, 1)
	core.recordDraw(d, call)

# The draw's commands read from its buffer: counted by the GPU (a count in another buffer), or
# drawCount of them in one call (one call each on a device without multi-draw indirect).
pub fn drawIndirect(mut d Device, call core.DrawCall, indexed bool):
	cmd = d.frames[d.state.frame].commands
	stride = core.indexCommandBytes if indexed else core.drawCommandBytes
	commands = d.state.buffers[call.indirect].handle
	if call.countBuffer >= 0:
		if not d.support.countedDraw:
			fail(
				"rhi: an indirect draw counted by the GPU on a device without drawIndirectCount"
			)
		counts = d.state.buffers[call.countBuffer].handle
		if indexed:
			vkCmdDrawIndexedIndirectCount(
				cmd,
				commands,
				call.indirectOffset,
				counts,
				call.countOffset,
				call.drawCount,
				stride
			)
		else:
			vkCmdDrawIndirectCount(
				cmd,
				commands,
				call.indirectOffset,
				counts,
				call.countOffset,
				call.drawCount,
				stride
			)
		return
	calls = 1 if d.support.multiDraw else call.drawCount
	each = call.drawCount if d.support.multiDraw else 1
	for k in 0..calls:
		if indexed:
			vkCmdDrawIndexedIndirect(
				cmd,
				commands,
				call.indirectOffset + k * stride,
				each,
				stride
			)
		else:
			vkCmdDrawIndirect(cmd, commands, call.indirectOffset + k * stride, each, stride)

pub fn drawDirect(mut device Device, call core.DrawCall, indexed bool):
	if indexed:
		vkCmdDrawIndexed(
			device.frames[device.state.frame].commands,
			call.count,
			call.instances,
			call.first,
			call.vertexOffset,
			call.firstInstance
		)
	else:
		vkCmdDraw(
			device.frames[device.state.frame].commands,
			call.count,
			call.instances,
			call.first,
			call.firstInstance
		)

# The draw's vertex buffers, then zeros for an input the layout lacks: bound unless the frame's
# last bind was the same.
fn bindVertices(mut d Device, cmd i64, call core.DrawCall, zeroBinding i64):
	n = call.vertexBuffers.len
	bound ref i64[] = d.boundVertices
	same = bound.len == 1 + n * 2 and bound[0] == zeroBinding
	if same:
		for i in 0..n:
			if bound[1 + i * 2] != call.vertexBuffers[i] or
				bound[2 + i * 2] != call.vertexOffsets[i]:
				same = false
				break
	if same:
		d.state.stats.vertexSkipped += 1
		return
	d.boundVertices.clear()
	d.boundVertices.push(zeroBinding)
	for i in 0..n:
		d.boundVertices.push(call.vertexBuffers[i])
		d.boundVertices.push(call.vertexOffsets[i])
	d.state.stats.vertexBinds += 1
	if n > 0:
		vkCmdBindVertexBuffers(cmd, 0, n, call.vertexBuffers, call.vertexOffsets)
	if zeroBinding >= 0:
		d.bindZeros(cmd, zeroBinding)

# The draw's dynamic state, set where it differs from what the pass's draws set before (all of
# it on the pass's first draw): the viewport and scissor, and where the device sets them so,
# culling, front faces, the depth test, write, comparison and bias.
fn setDynamicState(mut d Device, cmd i64, call core.DrawCall):
	if d.state.drawSetsRects(call):
		d.setRects(cmd, call.raster)
	if not d.support.dynamicState: return
	p ref core.Pass = d.state.pass
	bits = p.stateBits(call)
	cull = core.cullOf(bits)
	front = bits.bits(1, 1)
	test = bits.bits(2, 1)
	write = bits.bits(3, 1)
	bias = bits.bits(4, 2)
	compare = bits.bits(6, 3)
	old = p.state
	if old >= 0 and old == bits: return
	first = old < 0
	if first or core.cullOf(old) != cull:
		vkCmdSetCullMode(cmd, cullModeOf(bits))
	if first or old.bits(1, 1) != front:
		vkCmdSetFrontFace(cmd, front)
	if first or old.bits(2, 1) != test:
		vkCmdSetDepthTestEnable(cmd, test)
	if first or old.bits(3, 1) != write:
		vkCmdSetDepthWriteEnable(cmd, write)
	if first or old.bits(6, 3) != compare:
		vkCmdSetDepthCompareOp(cmd, compare)
	if first or old.bits(4, 2) != bias:
		vkCmdSetDepthBiasEnable(cmd, 1 if bias != 0 else 0)
		if bias != 0:
			constant, slope = core.depthBiasOf(bias)
			vkCmdSetDepthBias(cmd, constant, 0.0, slope)
	d.state.pass.state = bits

# the buffer of zeros (core's zeroBuffer) bound for an input a vertex layout does not feed
fn bindZeros(mut d Device, cmd i64, zeroBinding i64):
	if d.zeroHandles.isEmpty:
		zeros = core.zeroBuffer(d)
		d.zeroHandles = [d.state.buffers[zeros].handle]
		d.zeroOffsets = [0]
	vkCmdBindVertexBuffers(cmd, zeroBinding, 1, d.zeroHandles, d.zeroOffsets)

# What the program reads, pushed with the draw: its textures with their samplers, its storage
# buffers, and its parameters (as they are now). Nothing is pushed when the frame's last push
# was the same: the same layout naming the same views, samplers, buffers and parameter copy
# (compared in place with what it named).
fn pushDescriptors(mut d Device, cmd i64, call core.DrawCall):
	program = call.program
	paramsBuffer, paramsOffset = core.paramsOf(d, program, call.paramsCopy)
	layout = d.programs[program].layout
	samplers = d.state.programs[program].samplers.len
	storage = d.state.programs[program].buffers.len
	# what the push names (the layout, the parameters' copy, each texture's view and sampler, each
	# storage buffer), compared with the last one's
	same = d.pushed.len == 3 + samplers * 2 + storage and d.pushed[0] == layout and
		d.pushed[1] == paramsBuffer and d.pushed[2] == paramsOffset
	for i in 0..samplers:
		id = d.state.drawTexture(program, i, call)
		d.state.textures[id].untouched = false
		same = same and d.pushed[3 + i * 2] == d.state.textures[id].view and
			d.pushed[4 + i * 2] == d.state.textures[id].sampler
	for i in 0..storage:
		same = same and
			d.pushed[3 + samplers * 2 + i] ==
			d.state.buffers[d.state.drawStorage(program, i, call)].handle
	if same:
		d.state.stats.descriptorsSkipped += 1
		return
	# set 0 pushed with another pipeline layout disturbs the set bound at 1
	if d.pushed.isEmpty or d.pushed[0] != layout:
		d.boundArrays.clear()
	d.pushed.clear()
	d.pushed.push(layout)
	d.pushed.push(paramsBuffer)
	d.pushed.push(paramsOffset)
	for i in 0..samplers:
		t = d.state.textures[d.state.drawTexture(program, i, call)]
		d.pushed.push(t.view)
		d.pushed.push(t.sampler)
	for i in 0..storage:
		d.pushed.push(d.state.buffers[d.state.drawStorage(program, i, call)].handle)
	d.pushSet(cmd, 0, program, call.textures, call.storage, paramsBuffer, paramsOffset)
	d.state.stats.descriptorBinds += 1

# The program's set 0 pushed at the bind point (0 graphics, 1 compute): its textures with their
# samplers, its storage buffers (of those named per binding) and its parameters' copy. The lists
# a push is made of are the device's, kept from push to push: a draw makes none.
fn pushSet(
	mut d Device,
	cmd i64,
	bindPoint i64,
	program i64,
	textures ref i64[],
	storage ref i64[],
	paramsBuffer i64,
	paramsOffset i64
):
	layout = d.programs[program].layout
	samplers = d.state.programs[program].samplers.len
	buffersRead = d.state.programs[program].buffers.len
	paramBytes = d.state.programs[program].params.len * 4
	# the descriptions first (the writes point at them, so they stay unchanged while the writes live);
	# the lists are the device's, moved out and back and filled by loops, so a draw allocates none
	images = move d.pushImages
	d.pushImages = []
	images.clear()
	for i in 0..samplers:
		id = d.state.textureOf(program, i, textures)
		d.state.textures[id].untouched = false
		t = d.state.textures[id]
		images.push(
			DescriptorImageInfo(sampler = t.sampler, view = t.view, layout = u32(t.readLayout()))
		)
	buffers = move d.pushBuffers
	d.pushBuffers = []
	buffers.clear()
	for i in 0..buffersRead:
		b = d.state.buffers[d.state.storageOf(program, i, storage)]
		buffers.push(DescriptorBufferInfo(buffer = b.handle, offset = 0, range = b.size))
	if paramBytes > 0:
		buffers.push(
			DescriptorBufferInfo(buffer = paramsBuffer, offset = paramsOffset, range = paramBytes)
		)
	writes = move d.pushWrites
	d.pushWrites = []
	writes.clear()
	for i in 0..samplers:
		writes.push(
			WriteDescriptorSet(
				binding = d.state.programs[program].samplers[i].binding,
				kind = u32(descriptorOf(d.state.programs[program].samplers[i].kind)),
				image = images[i],
				buffer = none
			)
		)
	for i, buffer in buffers:
		binding = d.state.programs[program].buffers[i] if i < buffersRead else core.paramsBinding
		kind = descStorageBuffer if i < buffersRead else descUniformBuffer
		writes.push(
			WriteDescriptorSet(binding = u32(binding), kind = u32(kind), image = none, buffer)
		)
	if writes.isEmpty:
		pass
	elif d.support.pushDescriptor:
		vkCmdPushDescriptorSet(cmd, bindPoint, layout, 0, writes.len, writes)
	else:
		d.bindWrittenSet(cmd, bindPoint, program, writes)
	# the writes let go of the descriptions before all go back to the device
	writes.clear()
	d.pushWrites = move writes
	d.pushImages = move images
	d.pushBuffers = move buffers

# ---------- texture arrays ----------

# The program's texture arrays (set 1) bound from the frame's table at the bind point (0
# graphics, 1 compute): the table written first when the lists changed since (a new one when this
# frame already bound it, or it lacks room), bound unless it is what the draws' set 1 holds.
fn bindTextureArrays(mut d Device, cmd i64, program i64, bindPoint i64):
	f = d.state.frame
	t = d.programs[program].tables[f]
	version = d.state.programs[program].lists.version
	variable = d.programs[program].variable
	room = d.state.programs[program].lists
		.tableRoom(variable)
		.min(d.support.maxTextures) if variable >=
		0
		else 0
	if t.set == 0 or t.room < room or (t.version != version and t.boundAt == d.state.timeline):
		if t.pool != 0:
			core.retire(
				d.state,
				core.Retired(kind = retiredPool, handle = t.pool, block = -1, offset = 0, size = 0)
			)
		pool, set = d.newArrayTable(program, room)
		d.programs[program].tables[f] = ArrayTable(pool, set, room, version = -1, boundAt = -1)
	if d.programs[program].tables[f].version != version:
		d.writeArrayTable(program, d.programs[program].tables[f].set, room)
		d.programs[program].tables[f].version = version
	set = d.programs[program].tables[f].set
	layout = d.programs[program].layout
	if bindPoint != 0:
		vkCmdBindDescriptorSets(cmd, bindPoint, layout, 1, 1, [set], 0, 0)
	elif d.boundArrays.len != 2 or d.boundArrays[0] != layout or d.boundArrays[1] != set:
		vkCmdBindDescriptorSets(cmd, 0, layout, 1, 1, [set], 0, 0)
		d.boundArrays.clear()
		d.boundArrays.push(layout)
		d.boundArrays.push(set)
		d.state.stats.descriptorBinds += 1
	d.programs[program].tables[f].boundAt = d.state.timeline

# a table for the program's texture arrays: a pool of its own and its set, the variable binding
# with room for `room` textures
fn newArrayTable(mut d Device, program i64, room i64):
	rec ref ProgramRecord = d.programs[program]
	slots ref core.TextureArraySlot[] = d.state.programs[program].lists.slots
	total = (0..slots.len)
		.map(room if it == rec.variable else d.fixedRoom(slots[it], false))
		.sum()
	sizes = [DescriptorPoolSize(kind = u32(descSampledImage), count = u32(total.max(1)))]
	check(   # UPDATE_AFTER_BIND
		vkCreateDescriptorPool(d.device, DescriptorPoolCreateInfo(flags = 2, maxSets = 1, sizeCount = 1, sizes), 0, out pool),
		"vkCreateDescriptorPool"
	)
	layouts = [rec.arraysLayout]
	counts = [u32(room)]
	variable = VariableCountAllocateInfo(counts)
	if rec.variable >= 0:
		check(
			vkAllocateDescriptorSets(d.device, DescriptorSetAllocateInfo(next = variable, pool, layouts), out set),
			"vkAllocateDescriptorSets"
		)
		return (pool, set)
	check(
		vkAllocateDescriptorSets(d.device, DescriptorSetAllocateInfo(next = none, pool, layouts), out fixed),
		"vkAllocateDescriptorSets"
	)
	(pool, fixed)

# Every array's textures written into a table (a placeholder for an id that names no live
# texture of the array's kind); what does not fit its binding is left out.
fn writeArrayTable(mut d Device, program i64, set i64, room i64):
	lists = d.state.programs[program].lists
	variable = d.programs[program].variable
	images = []
	for k, slot in lists.slots:
		n = lists.ids[k].len.min(room if k == variable else d.fixedRoom(slot, false))
		run = []
		for i in 0..n:
			id = d.state.arrayTexture(slot, lists.ids[k][i])
			d.state.textures[id].untouched = false
			run.push(
				DescriptorImageInfo(
					sampler = d.state.textures[id].sampler,
					view = d.state.textures[id].view,
					layout = u32(d.state.textures[id].readLayout())
				)
			)
		images.push(run)
	writes = []
	for k in 0..lists.slots.len:
		if not images[k].isEmpty:
			writes.push(WriteDescriptorImages(
				set,
				binding = lists.slots[k].binding,
				element = 0,
				count = u32(images[k].len),
				kind = u32(descSampledImage),
				images = images[k]))
	if not writes.isEmpty:
		vkUpdateDescriptorSets(d.device, writes.len, writes, 0, 0)

# ---------- compute ----------

# the stages that read a buffer a compute stage writes, and their access
bufferReaders = stageDrawIndirect | stageVertexInput | shaderStages | stageTransfer
bufferReads = accessIndirectRead | accessIndexRead | accessVertexRead | accessUniformRead |
	accessShaderRead | accessTransferRead

# A compute stage run between passes (the pass open ends): the textures drawn into back at rest,
# and when its program writes a buffer (its declaration's `written`), after the stages that read
# buffers before it; its pipeline and what it reads pushed, its groups dispatched, and its writes
# done before what reads a buffer next.
pub fn dispatch(mut d Device, call core.ComputeCall):
	d.endPass()
	cmd = d.frames[d.state.frame].commands
	program = call.program
	paramsBuffer, paramsOffset = core.paramsOf(d, program, -1)
	writes = true in d.state.programs[program].written
	d.barrier(cmd, d.state.restTextures(), bufferReaders if writes else 0, stageCompute, [])
	vkCmdBindPipeline(cmd, 1, d.programs[program].pipeline)   # COMPUTE
	d.pushSet(cmd, 1, program, call.textures, call.storage, paramsBuffer, paramsOffset)
	if d.programs[program].arraysLayout != 0:
		d.bindTextureArrays(cmd, program, 1)
	vkCmdDispatch(cmd, call.x, call.y, call.z)
	if writes or d.state.programs[program].samplers.any(core.isImageKind(.kind)):
		memoryBarrier(
			cmd,
			stageCompute,
			accessShaderWrite,
			bufferReaders,
			bufferReads | accessShaderWrite
		)

# Ends the frame as endFrame does, with the first n bytes of a buffer copied out on the way (what a
# compute stage wrote): returned once the GPU is done.
pub fn readBuffer(mut d Device, id i64, n i64) u8[]:
	d.endPass()
	cmd = d.frames[d.state.frame].commands
	readback = core.newBuffer(d, n, core.bufTransferDst, true)
	memoryBarrier(cmd, stageAllCommands, writeAccess, stageTransfer, accessTransferRead)
	vkCmdCopyBuffer(
		cmd,
		d.state.buffers[id].handle,
		d.state.buffers[readback].handle,
		1,
		BufferCopy(src = 0, dst = 0, size = n)
	)
	memoryBarrier(cmd, stageTransfer, accessTransferWrite, stageHost, accessHostRead)
	d.endFrame()
	d.waitIdle()
	bytes = win.memoryAt(d.state.buffers[readback].alloc.mapped, n).bytes(0, n)
	d.state.destroyBuffer(readback)
	bytes

# Ends the frame as endFrame does, with the first level of a target's color copied out on the
# way: its pixels (rows from the top, as its format lays them out) once the GPU is done.
pub fn readTexture(mut d Device, id i64) u8[]:
	d.endPass()
	cmd = d.frames[d.state.frame].commands
	t = d.state.textures[id]
	t.checkReadable()
	n = core.levelBytes(t.format, t.width, t.height)
	d.barrier(
		cmd,
		d.state.takeTextures([core.TextureUse(texture = id, use = core.useCopyFrom)]),
		0,
		0,
		[]
	)
	readback = core.newBuffer(d, n, core.bufTransferDst, true)
	region = BufferImageCopy(
		offset = 0,
		layers = layersAt(0, 0, 1),
		imageOffset = Offset3D(x = 0, y = 0, z = 0),
		extent = Extent3D(width = u32(t.width), height = u32(t.height), depth = 1)
	)
	vkCmdCopyImageToBuffer(
		cmd,
		t.image,
		layoutTransferSrc,
		d.state.buffers[readback].handle,
		1,
		region
	)
	memoryBarrier(cmd, stageTransfer, accessTransferWrite, stageHost, accessHostRead)
	d.endFrame()
	d.waitIdle()
	bytes = win.memoryAt(d.state.buffers[readback].alloc.mapped, n).bytes(0, n)
	d.state.destroyBuffer(readback)
	bytes

# ---------- between passes ----------

# a multisampled texture's samples averaged into a plain one of its size
pub fn resolve(mut d Device, from i64, into i64):
	d.endPass()
	cmd = d.frames[d.state.frame].commands
	d.barrier(cmd, d.state.takeTextures(core.resolveUses(from, into)), 0, 0, [])
	a = d.state.textures[from]
	b = d.state.textures[into]
	corner = Offset3D(x = 0, y = 0, z = 0)
	region = ImageResolve(
		src = layersAt(0, 0, 1),
		srcOffset = corner,
		dst = layersAt(0, 0, 1),
		dstOffset = corner,
		extent = Extent3D(
			width = u32(a.width.min(b.width)),
			height = u32(a.height.min(b.height)),
			depth = 1
	))
	vkCmdResolveImage(cmd, a.image, layoutTransferSrc, b.image, layoutTransferDst, 1, region)

# Ends the frame as endFrame does, with the screen's pixels copied out on the way: they are
# returned (r, g, b, a, rows from the top) once the GPU is done.
pub fn endFrameCapturing(mut d Device) u8[]:
	d.endPass()
	cmd = d.frames[d.state.frame].commands
	w = d.state.width
	h = d.state.height
	if not d.state.pass.screenTouched:
		imageBarrier(
			cmd,
			d.swapImages[d.image],
			layoutUndefined,
			layoutColorAttachment,
			aspectColor,
			1,
			1
		)
		d.state.pass.screenTouched = true
	imageBarrier(
		cmd,
		d.swapImages[d.image],
		layoutColorAttachment,
		layoutTransferSrc,
		aspectColor,
		1,
		1
	)
	readback = core.newBuffer(d, w * h * 4, core.bufTransferDst, true)
	region = BufferImageCopy(
		offset = 0,
		layers = layersAt(0, 0, 1),
		imageOffset = Offset3D(x = 0, y = 0, z = 0),
		extent = Extent3D(width = u32(w), height = u32(h), depth = 1)
	)
	vkCmdCopyImageToBuffer(
		cmd,
		d.swapImages[d.image],
		layoutTransferSrc,
		d.state.buffers[readback].handle,
		1,
		region
	)
	imageBarrier(
		cmd,
		d.swapImages[d.image],
		layoutTransferSrc,
		layoutColorAttachment,
		aspectColor,
		1,
		1
	)
	d.endFrame()
	d.waitIdle()
	bgra = win.memoryAt(d.state.buffers[readback].alloc.mapped, w * h * 4).bytes(0, w * h * 4)
	d.state.destroyBuffer(readback)
	core.rgbaOf(bgra, w * h)
