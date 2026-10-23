# What a frame records: passes (render targets set: a color texture, the swapchain's back buffer
# or none, and a depth texture or none), draws inside them, and what happens between them
# (resolving a multisampled target, compute stages). Each moves the textures it uses from their
# last use to its own (core's barriers.zap), in one barrier: a texture drawn into rests readable by
# any stage, a target drawn by two passes in a row stays one; the back buffer is drawn into from
# its first pass to the frame's end.
#
# The engine's clip space has y up, and its texture places start at a target's first row.
# Direct3D puts clip y = 1 at a target's first row: the screen is drawn as it comes, a target
# with y flipped by the vertex stage (the flip after the parameters), so a target holds what
# Vulkan's does. Counter-clockwise faces are in front on the screen, clockwise ones in a target
# (the same faces, seen through the flip or not), as there.

import win
import rhi.core

# ---------- passes ----------

# Begins a pass into the color targets (textures, or the screen alone) and the depth target (a
# texture or none), each cleared first or kept as it was.
pub fn beginTargets(mut d Device, colors i64[], depth i64, clearColor Vec4?, clearDepth bool):
	d.endPass()
	cmd = d.frames[d.state.frame].commands
	d.transitions(
		cmd,
		d.state.takeTextures(core.passUses(colors, depth, clearColor != none, clearDepth))
	)
	p = d.state.openPass(colors, depth)
	views = colors.map(d.colorTargetView(it))
	depthView = d.depthTargetView(depth)
	if depthView != 0:
		listOMSetRenderTargets(cmd, views.len, views, 0, [depthView])
	else:
		listOMSetColorTarget(cmd, views.len, views, 0, 0)
	screen = p.color == core.screenTarget
	d.state.pass = p
	core.stampPass(d, true)
	d.state.flip = 1.0 if screen else -1.0
	d.state.flipWords[0] = d.state.flip
	d.boundVertices.clear()
	d.forgetRootArguments()
	d.setRects(cmd, core.RasterState())
	d.clearTargets(clearColor, -1, 1.0 if clearDepth else none)

# the viewport and scissor of a draw's raster state (none: the whole target)
fn setRects(d Device, cmd i64, r core.RasterState):
	p ref core.Pass = d.state.pass
	v = r.viewportOf(p.width, p.height)
	listRSSetViewports(
		cmd,
		1,
		Viewport(
			x = v.x,
			y = v.y,
			width = v.width,
			height = v.height,
			minDepth = v.near,
			maxDepth = v.far
		)
	)
	c = r.scissorOf(p.width, p.height)
	listRSSetScissorRects(
		cmd,
		1,
		Rect(
			left = i32(c.x),
			top = i32(c.y),
			right = i32(c.x + c.width),
			bottom = i32(c.y + c.height)
		)
	)

# the render target view of a pass's color target (a texture or the screen), 0 none
fn colorTargetView(d Device, color i64):
	if color == core.screenTarget: return d.rtvHandle(d.backBuffer)
	d.rtvHandle(d.state.textures[color].targetView) if color >= 0 else 0

# the depth view of a pass's depth target, 0 none
fn depthTargetView(d Device, depth i64):
	d.dsvHandle(d.state.textures[depth].targetView) if depth >= 0 else 0

# what the draws set of the root signature forgotten (setting one clears it)
fn forgetRootArguments(mut d Device):
	d.boundViews = -1
	d.boundSamplers = -1
	d.boundParams = 0
	d.boundStorage.clear()
	d.boundArrays.clear()

# The pass's targets cleared where they are: color target `index` (-1 every one) to c, the depth
# to `depth`.
pub fn clearTargets(mut d Device, c Vec4?, index i64, depth f32?):
	p ref core.Pass = d.state.pass
	if not p.active: return
	cmd = d.frames[d.state.frame].commands
	if c is color:
		if p.color != core.noTarget:
			colors = [p.color]
			colors.extend(p.extraColors)
			for k, id in colors:
				if index < 0 or index == k:
					listClearRenderTargetView(
						cmd,
						d.colorTargetView(id),
						[color.r, color.g, color.b, color.a],
						0,
						0
					)
	if depth is z:
		depthView = d.depthTargetView(p.depth)
		if depthView != 0:
			listClearDepthStencilView(cmd, depthView, 1, z, 0, 0, 0)

# ends the pass (its targets stay targets until the next use)
pub fn endPass(mut d Device):
	if not d.state.pass.active: return
	core.stampPass(d, false)
	d.state.pass.active = false

# a use's resource state
fn stateOf(use i64):
	if use == core.useColor: return stateRenderTarget
	if use == core.useDepth: return stateDepthWrite
	if use == core.useResolveFrom: return stateResolveSource
	if use == core.useCopyFrom: return stateCopySource
	if use == core.useResolveInto: return stateResolveDest
	if use == core.useNone: return statePresent
	stateShaderResource

# The transitions as one barrier: each resource from its use's state to the next one's (none
# between the same states).
pub fn transitions(d Device, cmd i64, moves core.Transition[]):
	barriers = []
	for m in moves:
		before = stateOf(m.from)
		after = stateOf(m.to)
		if before != after:
			resource = d.backBuffers[d.backBuffer] if m.texture == core.screenTarget
				else d.state.textures[m.texture].image
			barriers.push(ResourceBarrier(resource, before = u32(before), after = u32(after)))
	if not barriers.isEmpty:
		listResourceBarrier(cmd, barriers.len, barriers)

# ---------- draws ----------

# sets only the pipeline, root arguments and buffers that changed
pub fn draw(mut d Device, call core.DrawCall):
	if not d.state.drawReady(call): return
	cmd = d.frames[d.state.frame].commands
	# the state bits are the pipeline's (Direct3D 12 has no dynamic culling, depth test, write or bias)
	e = core.pipelineFor(d, call.program, call.layout, call.state, d.state.pass.stateBits(call))
	pipeline = e.pipeline
	signature = d.programs[call.program].rootSignature
	if signature != d.state.pass.layout:
		listSetGraphicsRootSignature(cmd, signature)
		d.state.pass.layout = signature
		d.forgetRootArguments()
	bindsPipeline, bindsIndex = d.state.drawBinds(pipeline, call.indexBuffer)
	if bindsPipeline:
		listSetPipelineState(cmd, pipeline)
	if d.state.drawSetsRects(call):
		d.setRects(cmd, call.raster)
	topology = 2 if call.state.lines else 4   # LINELIST or TRIANGLELIST
	if topology != d.state.pass.topology:
		listIASetPrimitiveTopology(cmd, topology)
		d.state.pass.topology = topology
	d.vertexBuffers(cmd, call, e.zeroBinding)
	d.rootArguments(cmd, call)
	if bindsIndex:
		b = d.state.buffers[call.indexBuffer - 1]
		listIASetIndexBuffer(   # R32_UINT
			cmd,
			IndexBufferView(location = b.address, size = u32(b.size), format = 42)
		)
	core.recordDraw(d, call)

# The draw's commands read from its buffer by ExecuteIndirect: drawCount of them, or as many as
# the count in another buffer says. (Direct3D's instance number starts at 0 whatever the first
# instance; the instance stream is read from it, as Vulkan reads it.)
pub fn drawIndirect(mut device Device, call core.DrawCall, indexed bool):
	cmd = device.frames[device.state.frame].commands
	signature = device.drawSignature(indexed)
	b = device.state.buffers[call.indirect]
	counts = 0
	countOffset = 0
	if call.countBuffer >= 0:
		c = device.state.buffers[call.countBuffer]
		counts = c.alloc.memory
		countOffset = c.alloc.offset + call.countOffset
	listExecuteIndirect(
		cmd,
		signature,
		call.drawCount,
		b.alloc.memory,
		b.alloc.offset + call.indirectOffset,
		counts,
		countOffset
	)

pub fn drawDirect(mut device Device, call core.DrawCall, indexed bool):
	if indexed:
		listDrawIndexedInstanced(
			device.frames[device.state.frame].commands,
			call.count,
			call.instances,
			call.first,
			call.vertexOffset,
			call.firstInstance
		)
	else:
		listDrawInstanced(
			device.frames[device.state.frame].commands,
			call.count,
			call.instances,
			call.first,
			call.firstInstance
		)

# the command signature of indirect draws of indices or of vertices, made the first time
fn drawSignature(mut d Device, indexed bool):
	if d.drawSignatures.isEmpty:
		for k in 0..2:
			arguments = [IndirectArgument(kind = k)]
			desc = CommandSignatureDesc(
				stride = u32(core.indexCommandBytes if k == 1 else core.drawCommandBytes),
				arguments
			)
			check(
				deviceCreateCommandSignature(d.device, desc, 0, iidCommandSignature, out signature),
				"CreateCommandSignature"
			)
			d.drawSignatures.push(signature)
	d.drawSignatures[1 if indexed else 0]

# the draw's vertex buffers (handles: buffer ids + 1) at their offsets, then zeros for an input
# the layout lacks (bound unless the pass's last draw bound the same)
fn vertexBuffers(mut d Device, cmd i64, call core.DrawCall, zeroSlot i64):
	if d.sameVertices(call, zeroSlot):
		d.state.stats.vertexSkipped += 1
		return
	d.state.stats.vertexBinds += 1
	d.boundVertices.clear()
	d.boundVertices.push(call.layout)
	d.boundVertices.push(zeroSlot)
	for i in 0..call.vertexBuffers.len:
		d.boundVertices.push(call.vertexBuffers[i])
		d.boundVertices.push(call.vertexOffsets[i])
	views = move d.views
	d.views = []
	views.clear()
	for i in 0..call.vertexBuffers.len:
		b = d.state.buffers[call.vertexBuffers[i] - 1]
		offset = call.vertexOffsets[i]
		stride = d.state.layouts[call.layout].bindings[i].stride
		views.push(
			VertexBufferView(
				location = b.address + offset,
				size = u32(b.size - offset),
				stride = u32(stride)
			)
		)
	if zeroSlot >= 0:
		z = d.state.buffers[core.zeroBuffer(d)]
		while views.len < zeroSlot:
			views.push(VertexBufferView(location = z.address, size = u32(z.size), stride = 0))
		views.push(VertexBufferView(location = z.address, size = u32(z.size), stride = 0))
	if not views.isEmpty:
		listIASetVertexBuffers(cmd, 0, views.len, views)
	d.views = move views

fn sameVertices(d Device, call core.DrawCall, zeroSlot i64):
	bound = d.boundVertices
	if bound.len != 2 + call.vertexBuffers.len * 2 or bound[0] != call.layout or
		bound[1] != zeroSlot:
		return false
	for i in 0..call.vertexBuffers.len:
		if bound[2 + i * 2] != call.vertexBuffers[i] or bound[3 + i * 2] != call.vertexOffsets[i]:
			return false
	true

# What the program reads, given with the draw: its parameters (copied into the ring as they are
# now, the pass's y flip after them, unless the last copy holds them), its storage buffers, its
# textures' views (copied into the frame's shader-visible views, unless the last draw's are the
# same) and their samplers' table; each set unless the pass's last draw set the same.
fn rootArguments(mut d Device, cmd i64, call core.DrawCall):
	changed = false
	paramsBuffer, paramsOffset = core.paramsOf(d, call.program, call.paramsCopy)
	params = d.state.buffers[paramsBuffer - 1].address + paramsOffset
	if params != d.boundParams:
		listSetGraphicsRootConstantBufferView(cmd, 0, params)
		d.boundParams = params
		changed = true
	# the storage buffers' addresses, each set where it differs from the pass's last draw's
	storage = d.state.programs[call.program].buffers.len
	if d.boundStorage.len != storage:
		d.boundStorage = fill(storage, -1)
	for i in 0..storage:
		address = d.state.buffers[d.state.drawStorage(call.program, i, call)].address
		if address != d.boundStorage[i]:
			listSetGraphicsRootShaderResourceView(cmd, bufferParameter(i), address)
			d.boundStorage[i] = address
			changed = true
	if not d.state.programs[call.program].samplers.isEmpty:
		changed = d.textureTables(cmd, call.program, call.textures, false) or changed
	if not d.state.programs[call.program].lists.slots.isEmpty:
		changed = d.arrayTables(cmd, call.program, false) or changed
	if changed:
		d.state.stats.descriptorBinds += 1
	else:
		d.state.stats.descriptorsSkipped += 1

# The textures named (per sampler binding: a placeholder where none is) as a table of views and
# their samplers' table, a draw's set unless the pass's last draw set the same (a compute stage's
# always: `compute`); whether either was set. The textures are compared in place with the last
# table's (a draw makes no list).
fn textureTables(mut d Device, cmd i64, program i64, textures ref i64[], compute bool):
	changed = false
	n = d.state.programs[program].samplers.len
	same = d.lastTableIds.len == n
	samplerKey = 0
	for i in 0..n:
		id = d.state.textureOf(program, i, textures)
		same = same and d.lastTableIds[i] == id
		samplerKey = samplerKey << 8 | d.state.textures[id].sampler
	tables = bufferParameter(d.state.programs[program].buffers.len)
	# the views copied into the frame's shader-visible ones, unless the last table holds them
	if not same:
		f = d.state.frame
		first = f * ringViews + d.frames[f].viewsUsed
		if d.frames[f].viewsUsed + n > ringViews:
			fail("rhi: a frame uses more than {ringViews} texture views")
		d.frames[f].viewsUsed += n
		d.lastTableIds.clear()
		for i in 0..n:
			id = d.state.textureOf(program, i, textures)
			d.lastTableIds.push(id)
			deviceCopyDescriptorsSimple(
				d.device,
				1,
				d.srvCpuStart + (first + i) * d.viewSize,
				d.viewCpuStart + d.state.textures[id].view * d.viewSize,
				0
			)
		d.lastTable = first
	if compute:
		listSetComputeRootDescriptorTable(cmd, tables, d.srvGpuStart + d.lastTable * d.viewSize)
		samplers = d.samplerTable(samplerKey << 4 | n)
		listSetComputeRootDescriptorTable(
			cmd,
			tables + 1,
			d.samplerGpuStart + samplers * d.samplerSize
		)
		return true
	if d.lastTable != d.boundViews:
		listSetGraphicsRootDescriptorTable(cmd, tables, d.srvGpuStart + d.lastTable * d.viewSize)
		d.boundViews = d.lastTable
		changed = true
	samplers = d.samplerTable(samplerKey << 4 | n)
	if samplers != d.boundSamplers:
		listSetGraphicsRootDescriptorTable(
			cmd,
			tables + 1,
			d.samplerGpuStart + samplers * d.samplerSize
		)
		d.boundSamplers = samplers
		changed = true
	changed

# the table of the last table's textures' samplers (made once for each set of samplers): its first slot
fn samplerTable(mut d Device, key i64):
	if d.samplerTables.get(key) is first: return first
	ids = d.lastTableIds
	first = d.samplerRange(ids.len)
	for i in 0..ids.len:
		desc = d.state.samplers[d.state.textures[ids[i]].sampler].desc
		deviceCreateSampler(
			d.device,
			desc.samplerDescription(),
			d.samplerCpuStart + (first + i) * d.samplerSize
		)
	d.samplerTables[key] = first
	first

# a range of n slots of the sampler heap: its first
fn samplerRange(mut d Device, n i64):
	match d.slots.rangeIn(1, n.max(1), 1):
		a: a.offset
		none: fail("rhi: the sampler heap's {samplerHeapSize} samplers are all taken (texture arrays' and draws' tables)")

# ---------- texture arrays ----------

# The program's texture arrays' tables set: the frame's views (written first when the lists
# changed since: into a new range when this frame already set it or it lacks room) and each
# array's samplers (made again when they differ); a draw's each set unless the pass's last draw
# set the same (a compute stage's always: `compute`). Whether one was set.
fn arrayTables(mut d Device, cmd i64, program i64, compute bool):
	f = d.state.frame
	lists ref core.TextureLists = d.state.programs[program].lists
	version = lists.version
	# summed by a loop, not a mapped list: this runs at every draw with texture arrays
	room = 0
	for k in 0..lists.slots.len:
		room += core.tableRoom(lists, k)
	t = d.programs[program].tables[f]
	if t.first < 0 or t.room < room or (t.version != version and t.boundAt == d.state.timeline):
		if t.first >= 0:
			core.retire(
				d.state,
				core.Retired(
					kind = retiredViewRange,
					handle = t.first,
					block = -1,
					offset = 0,
					size = t.room
				)
			)
		first = match d.slots.rangeIn(0, room, 1):
			a: a.offset
			none: fail("rhi: the shader-visible heap has no room for {room} more texture views (texture arrays)")
		d.programs[program].tables[f] = ArrayTable(first, room, version = -1, boundAt = -1)
	if d.programs[program].tables[f].version != version:
		writeArrayTable(
			d,
			program,
			d.programs[program].tables[f].first + ringViews * core.framesInFlight
		)
		d.programs[program].tables[f].version = version
	d.programs[program].tables[f].boundAt = d.state.timeline
	# the GPU handles (views and samplers, per array), each set where it differs from the pass's
	# last draw's
	base = d.programs[program].tables[f].first + ringViews * core.framesInFlight
	arrays = d.state.programs[program].lists.slots.len
	if d.boundArrays.len != arrays * 2:
		d.boundArrays = zeros(arrays * 2)
	first = d.state.programs[program].arrayParameter(0)
	changed = false
	at = 0
	for k in 0..arrays:
		views = d.srvGpuStart + (base + at) * d.viewSize
		samplers = d.samplerGpuStart + d.samplerRun(program, k) * d.samplerSize
		if compute:
			listSetComputeRootDescriptorTable(cmd, first + k * 2, views)
			listSetComputeRootDescriptorTable(cmd, first + k * 2 + 1, samplers)
			changed = true
		elif views != d.boundArrays[k * 2]:
			listSetGraphicsRootDescriptorTable(cmd, first + k * 2, views)
			d.boundArrays[k * 2] = views
			changed = true
		if not compute and samplers != d.boundArrays[k * 2 + 1]:
			listSetGraphicsRootDescriptorTable(cmd, first + k * 2 + 1, samplers)
			d.boundArrays[k * 2 + 1] = samplers
			changed = true
		at += d.state.programs[program].lists.tableRoom(k)
	changed

# every array's views copied into a table from its heap slot `at` (a placeholder's for an id that
# names no live texture of the array's kind); what does not fit an array's length is left out
fn writeArrayTable(mut d Device, program i64, at i64):
	lists = d.state.programs[program].lists
	place = at
	for k, slot in lists.slots:
		n = lists.ids[k].len.min(lists.tableRoom(k))
		for i in 0..n:
			id = d.state.arrayTexture(slot, lists.ids[k][i])
			deviceCopyDescriptorsSimple(
				d.device,
				1,
				d.srvCpuStart + (place + i) * d.viewSize,
				d.viewCpuStart + d.state.textures[id].view * d.viewSize,
				0
			)
		place += lists.tableRoom(k)

# Array k's samplers, one per texture in its order: the range that holds them, made again (the
# old one given back once the frame is done) when they differ. Its first slot.
fn samplerRun(mut d Device, program i64, k i64):
	old = d.programs[program].runs[k].first
	count = d.programs[program].runs[k].count
	version = d.state.programs[program].lists.version
	if old >= 0 and d.programs[program].runs[k].version == version: return old
	lists = d.state.programs[program].lists
	n = lists.ids[k].len.min(lists.tableRoom(k))
	key = (0..n).map(i:
		d.state.textures[d.state.arrayTexture(lists.slots[k], lists.ids[k][i])].sampler
	)
	if old >= 0 and d.programs[program].runs[k].key == key:
		d.programs[program].runs[k].version = version
		return old
	if old >= 0:
		core.retire(
			d.state,
			core.Retired(
				kind = retiredSamplerRange,
				handle = old,
				block = -1,
				offset = 0,
				size = count
			)
		)
	first = d.samplerRange(key.len)
	for i in 0..key.len:
		deviceCreateSampler(
			d.device,
			d.state.samplers[key[i]].desc.samplerDescription(),
			d.samplerCpuStart + (first + i) * d.samplerSize
		)
	d.programs[program].runs[k] = SamplerRun(first, count = key.len.max(1), key, version)
	first

# ---------- compute ----------

# A compute stage run between passes (the pass open ends): the textures drawn into back at rest,
# its root signature, pipeline state and what it reads set, the blocks of the buffers it writes
# moved to unordered access, its groups dispatched, then its writes done (a UAV barrier) and those
# blocks back to rest.
pub fn dispatch(mut d Device, call core.ComputeCall):
	d.endPass()
	cmd = d.frames[d.state.frame].commands
	d.transitions(cmd, d.state.restTextures())
	program = call.program
	listSetComputeRootSignature(cmd, d.programs[program].rootSignature)
	listSetPipelineState(cmd, d.programs[program].pipeline)
	paramsBuffer, paramsOffset = core.paramsOf(d, program, -1)
	if paramsBuffer != 0:
		listSetComputeRootConstantBufferView(
			cmd,
			0,
			d.state.buffers[paramsBuffer - 1].address + paramsOffset
		)
	written = d.writtenBlocks(program, call.storage)
	for block in written:
		transition(cmd, d.state.memory.blocks[block].memory, stateBufferRead, stateUnorderedAccess)
	for i in 0..d.state.programs[program].buffers.len:
		address = d.state.buffers[d.state.storageOf(program, i, call.storage)].address
		if d.state.programs[program].written[i]:
			listSetComputeRootUnorderedAccessView(cmd, bufferParameter(i), address)
		else:
			listSetComputeRootShaderResourceView(cmd, bufferParameter(i), address)
	if not d.state.programs[program].samplers.isEmpty:
		d.textureTables(cmd, program, call.textures, true)
	if not d.state.programs[program].lists.slots.isEmpty:
		d.arrayTables(cmd, program, true)
	listDispatch(cmd, call.x, call.y, call.z)
	for block in written:
		memory = d.state.memory.blocks[block].memory
		listResourceBarrier(
			cmd,
			1,
			[ResourceBarrier(kind = 2, resource = memory, before = 0, after = 0)]
		)
		transition(cmd, memory, stateUnorderedAccess, stateBufferRead)

# the memory blocks of the storage buffers a compute program writes (each once)
fn writtenBlocks(d Device, program i64, storage ref i64[]):
	blocks i64[] = []
	for i in 0..d.state.programs[program].buffers.len:
		if d.state.programs[program].written[i]:
			block = d.state.buffers[d.state.storageOf(program, i, storage)].alloc.block
			if block not in blocks:
				blocks.push(block)
	blocks

# Ends the frame as endFrame does, with the first n bytes of a buffer copied out on the way (what a
# compute stage wrote) into a readback buffer: returned once the GPU is done.
pub fn readBuffer(mut d Device, id i64, n i64) u8[]:
	d.endPass()
	cmd = d.frames[d.state.frame].commands
	readback = d.readbackBuffer(n)
	b = d.state.buffers[id]
	memory = d.state.memory.blocks[b.alloc.block].memory
	transition(cmd, memory, stateBufferRead, stateCopySource)
	listCopyBufferRegion(cmd, readback, 0, memory, b.alloc.offset, n)
	transition(cmd, memory, stateCopySource, stateBufferRead)
	d.endFrame()
	d.waitIdle()
	bytes = win.memoryAt(mapResource(readback), n).bytes(0, n)
	win.release(readback)
	bytes

# Ends the frame as endFrame does, with the first level of a target's color copied out on the
# way: its pixels (rows from the top, as its format lays them out) once the GPU is done.
pub fn readTexture(mut d Device, id i64) u8[]:
	d.endPass()
	cmd = d.frames[d.state.frame].commands
	t = d.state.textures[id]
	t.checkReadable()
	d.transitions(
		cmd,
		d.state.takeTextures([core.TextureUse(texture = id, use = core.useCopyFrom)])
	)
	row, rows = core.levelRows(t.format, t.width, t.height)
	pitch = row.alignUp(256)
	readback = d.readbackBuffer(pitch * rows)
	destination = TextureCopyLocation(
		resource = readback,
		kind = 1,
		offset = 0,
		format = u32(dxgiFormat(t.format)),
		width = u32(t.width),
		height = u32(t.height),
		rowPitch = u32(pitch))
	listCopyTextureRegion(
		cmd,
		destination,
		0,
		0,
		0,
		TextureCopyLocation(resource = t.image, kind = 0, offset = 0),
		0
	)
	d.endFrame()
	d.waitIdle()
	bytes = unpitched(
		win.memoryAt(mapResource(readback), pitch * rows).bytes(0, pitch * rows),
		row,
		pitch,
		rows
	)
	win.release(readback)
	bytes

# a buffer of n bytes the CPU reads back, in the copy destination's state
fn readbackBuffer(d Device, n i64):
	desc = ResourceDesc(
		dimension = 1,
		width = n.max(16),
		height = 1,
		depthOrArraySize = 1,
		mipLevels = 1,
		format = 0,
		layout = 1
	)
	check(
		deviceCreateCommittedResource(d.device, HeapProperties(kind = 3), 0, desc, stateCopyDest, 0, iidResource, out readback),
		"CreateCommittedResource (a readback)"
	)
	readback

# rows of `row` bytes each laid `pitch` apart, packed together
fn unpitched(rows u8[], row i64, pitch i64, count i64):
	packed = fill(row * count, u8(0))
	for y in 0..count:
		for x in 0..row:
			packed[y * row + x] = rows[y * pitch + x]
	packed

# ---------- between passes ----------

# a multisampled texture's samples averaged into a plain one of its size
pub fn resolve(mut d Device, from i64, into i64):
	d.endPass()
	cmd = d.frames[d.state.frame].commands
	d.transitions(cmd, d.state.takeTextures(core.resolveUses(from, into)))
	a = d.state.textures[from]
	b = d.state.textures[into]
	listResolveSubresource(cmd, b.image, 0, a.image, 0, dxgiFormat(b.format))

# Ends the frame as endFrame does, with the screen's pixels copied out on the way: they are
# returned (r, g, b, a, rows from the top) once the GPU is done.
pub fn endFrameCapturing(mut d Device) u8[]:
	d.endPass()
	cmd = d.frames[d.state.frame].commands
	w = d.state.width
	h = d.state.height
	pitch = (w * 4).alignUp(256)
	buffer = d.backBuffers[d.backBuffer]
	transition(
		cmd,
		buffer,
		stateRenderTarget if d.state.pass.screenTouched else statePresent,
		stateCopySource
	)
	readback = d.readbackBuffer(pitch * h)
	destination = TextureCopyLocation(
		resource = readback,
		kind = 1,
		offset = 0,
		format = u32(dxgiFormat(core.screenFormat)),
		width = u32(w),
		height = u32(h),
		rowPitch = u32(pitch))
	listCopyTextureRegion(
		cmd,
		destination,
		0,
		0,
		0,
		TextureCopyLocation(resource = buffer, kind = 0, offset = 0),
		0
	)
	d.presentFrame(stateCopySource)
	d.waitIdle()
	bgra = unpitched(
		win.memoryAt(mapResource(readback), pitch * h).bytes(0, pitch * h),
		w * 4,
		pitch,
		h
	)
	win.release(readback)
	core.rgbaOf(bgra, w * h)
