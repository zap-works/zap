# The engine's GPU: the RHI's device on the window, and the drawing state a renderer keeps over
# it. A program draws as it says what it wants: the target the renderer draws into (useTarget,
# useScreen), its state (setDepth, setBlending, setBlendMode, setDepthBias, setAlphaToCoverage),
# a program's parameters (setParams: a value of the struct its stages take, textures and
# storage buffers included); each draw is then one call of the RHI with all of that. A pass
# over a target begins with its first draw or clear and ends when a draw or clear names another.

import rhi
import rhi.core
import win

mut gpu = rhi.emptyDevice()

# how what is drawn mixes with what is there
pub type Blend:
	None
	Alpha   # src * a + dst * (1 - a)
	Add   # src + dst: light that adds up
	Premultiplied   # src + dst * (1 - a)

	# the RHI's code of the blending
	fn code():
		match self:
			None: core.blendNone
			Alpha: core.blendAlpha
			Add: core.blendAdd
			Premultiplied: core.blendPremultiplied

# What a renderer's draws are drawn with: the target (a texture, core.screenTarget or
# core.noTarget, chosen in frame `frame`: a frame begins on the screen) and the color targets of
# a set after it, the depth target, the depth test and write, culling, blending (or a blend set
# per color target), the depth pushed back or pulled forward, alpha to coverage, and the rest of
# the rasterizer's state (the depth comparison, faces, viewport and scissor).
type DrawState:
	color i64 = core.screenTarget
	extraColors i64[] = []
	depth i64 = core.noTarget
	frame i64 = -1
	depthTest bool = false
	depthWrite bool = true
	cull bool = false
	blend Blend = .None
	depthBias bool = false
	decal bool = false
	alphaToCoverage bool = false
	blends i64 = -1
	raster core.RasterState = core.RasterState()

	# the color and depth targets drawn into now
	fn target():
		(color, depth) if frame == framesBegun else (core.screenTarget, core.noTarget)

	# the color targets drawn into now, in order
	fn colorTargets():
		if frame != framesBegun: return [core.screenTarget]
		colors = core.colorsOf(color)
		colors.extend(extraColors)
		colors

	# the pipeline state of a draw of lines or triangles
	fn pipeline(lines bool):
		core.PipelineState(blend = blend.code(), alphaToCoverage, lines, blends)

mut frameOpen = false   # a frame was begun and not yet shown

# ZAP_RUN=draws prints the last frame's draw counts (drawStatsText) every 120 frames
# (`draws=N`: every N), to stderr
mut statsEvery = 0
mut memoryEvery = 0
mut framesBegun = 0

fn drawStatsWord():
	TraceWord("draws", "prints the last frame's draw counts every 120 frames, draws=N every N")

fn memoryWord():
	TraceWord("gpumemory", "prints what the device holds at each frame, gpumemory=N every N")

# the GPU made for the window
fn openGpu(w Window):
	gpu = rhi.newDevice(w.handle, moduleHandle(), w.width, w.height)
	word = drawStatsWord()
	statsEvery = (i64.parse(word.value() ?? "") ?? 120).max(1) if word.on() else 0
	memoryEvery = (i64.parse(memoryWord().value() ?? "") ?? 1).max(1) if memoryWord().on() else 0

# ---------- frames ----------

# Begins the GPU's frame for the window's size; false while there is nothing to draw into (a
# minimized window). nextFrame calls it; a loop of its own calls it before drawing.
pub fn startFrame(w Window) bool:
	gpu.resize(w.width, w.height)
	if not gpu.beginFrame(): return false
	frameOpen = true
	framesBegun += 1
	if statsEvery > 0 and framesBegun % statsEvery == 0:
		eprint("frame {framesBegun}: {drawStatsText()}")
	if memoryEvery > 0 and framesBegun % memoryEvery == 0:
		eprint("frame {framesBegun}: {memoryText()}")
	true

# the frame drawn so far shown
fn endGpuFrame():
	drawQueued()
	if frameOpen:
		gpu.endFrame()
		frameOpen = false

# the backend the GPU draws through: "Vulkan" or "Direct3D 12"
pub fn backendName() str:
	gpu.backendName()

# whether shaders may compute in f64 (a GPU file's f64 is a double: spec 11)
pub fn gpuDoubles() bool:
	gpu.doubles()

# whether indirect draws may be counted by the GPU (drawIndirect's `counted`)
pub fn countedDraws() bool:
	gpu.countedDraws()

# whether the GPU reads textures of BC blocks (TextureFormat's Bc1..Bc7Srgb): Windows' and
# Linux's, no Android one
pub fn bcTextures() bool:
	gpu.bcTextures()

# whether the GPU reads textures of ASTC blocks (TextureFormat's Astc4x4..Astc6x6Srgb): Android's
# under Vulkan, never Direct3D 12
pub fn astcTextures() bool:
	gpu.astcTextures()

# whether frames wait for the screen's refresh (on from the start); off, frames show as fast
# as they are made, to measure them
pub fn setVsync(on bool):
	gpu.setVsync(on)

# ---------- targets ----------

# the renderer's draws go to the screen from here on
pub fn useScreen(mut r Renderer):
	r.chooseTarget(core.screenTarget, core.noTarget)

fn chooseTarget(mut r Renderer, color i64, depth i64):
	r.chooseTargets(core.colorsOf(color), depth)

# The renderer's draws go to color targets (textures, the screen alone, or none) and a depth
# target, its viewport and scissor the whole target's again.
fn chooseTargets(mut r Renderer, colors i64[], depth i64):
	r.state.color = colors[0] if not colors.isEmpty else core.noTarget
	r.state.extraColors = colors[1..].copy() if colors.len > 1 else []
	r.state.depth = depth
	r.state.frame = framesBegun
	r.state.raster.viewport = none
	r.state.raster.scissor = none

# whether the pass open is over the state's targets
fn passIsOver(s DrawState):
	color, depth = s.target()
	p = gpu.currentPass()
	p.active and p.color == color and p.depth == depth and
		p.extraColors == (s.extraColors if s.frame == framesBegun else [])

# the pass over the state's target, begun when it is not (its contents kept; the draws put off
# into the pass before drawn first)
fn ensurePass(s DrawState):
	if not s.passIsOver():
		drawQueued()
		_, depth = s.target()
		gpu.beginTargets(s.colorTargets(), depth, none, false)

# clears the renderer's target: its colors to c, its depth to the far end
pub fn clearTarget(r Renderer, c Vec4):
	drawQueued()
	if r.state.passIsOver():
		gpu.clearPass(c, true)
		return
	_, depth = r.state.target()
	gpu.beginTargets(r.state.colorTargets(), depth, c, true)

# clears color target `index` of the renderer's targets (a set's, in order) to c
pub fn clearColorTarget(r Renderer, index i64, c Vec4):
	drawQueued()
	r.state.ensurePass()
	gpu.clearTargets(c, index, none)

# clears the depth of the renderer's target to `depth` (0 near, 1 far)
pub fn clearDepthTarget(r Renderer, depth f32):
	drawQueued()
	r.state.ensurePass()
	gpu.clearTargets(none, -1, depth)

# ---------- state ----------

# the depth test and the depth written, and the culling of faces turned away
pub fn setDepth(mut r Renderer, test bool, write bool, cull bool):
	r.state.depthTest = test
	r.state.depthWrite = write
	r.state.cull = cull

# how the depth test compares a fragment's depth with the target's (core's compare...; LESS at first)
pub fn setDepthCompare(mut r Renderer, compare i64):
	r.state.raster.depthCompare = compare

# Which faces are culled (with setDepth's cull): the front ones in place of the back ones; and
# whether the front ones are clockwise in clip space (y up) in place of counter-clockwise.
pub fn setFaces(mut r Renderer, cullFront bool, frontClockwise bool):
	r.state.raster.cullFront = cullFront
	r.state.raster.frontClockwise = frontClockwise

# the rectangle of the target the renderer draws into (none: the whole target), until the target changes
pub fn setViewport(mut r Renderer, v core.Viewport?):
	r.state.raster.viewport = v

# the pixels the renderer's draws may write (none: the whole target), until the target changes
pub fn setScissor(mut r Renderer, s core.Scissor?):
	r.state.raster.scissor = s

# A blending per color target of the renderer's targets, in their order ([]: every target as
# setBlendMode says).
pub fn setTargetBlends(mut r Renderer, blends core.TargetBlend[]):
	r.state.blends = -1 if blends.isEmpty else gpu.blendSet(blends.copy())

# alpha blending on (Blend.Alpha) or off
pub fn setBlending(mut r Renderer, on bool):
	r.state.blend = .Alpha if on else .None

# how what the renderer draws next mixes with what is there
pub fn setBlendMode(mut r Renderer, mode Blend):
	r.state.blend = mode

# depth pushed back by a slope-scaled amount while drawing a shadow map (no self-shadowing acne)
pub fn setDepthBias(mut r Renderer, on bool):
	r.state.depthBias = on

# what is drawn lies on a surface drawn before (a shadow, a mark): it is pulled toward the eye
# so it is seen on it rather than half hidden in it
pub fn setDecal(mut r Renderer, on bool):
	r.state.decal = on

# whether a fragment's alpha says how many of a pixel's samples it covers (cut-out foliage
# drawn with soft edges into a multisampled target)
pub fn setAlphaToCoverage(mut r Renderer, on bool):
	r.state.alphaToCoverage = on

# ---------- programs ----------

# A program the compiler built of its stages (`newProgram(shader(lit.vertex, lit.pixel))`): the
# RHI's program and the vertex layouts its vertex and instance structs make (a plain value,
# copied freely; what its parameters are now is the engine's).
pub type Program:
	id i64
	layout i64   # the vertex struct's attributes (-1: the program reads no vertex buffer)
	instanced i64   # the vertex's and the instance's (-1: no instance struct)
	vertexStride i64
	instanceStride i64

# what a program's parameters are now: the parts of its block (one per parameter struct its
# stages take), the block's words, the textures and storage buffers by binding (their elements'
# bytes as the packer wrote them, the shared storage that holds them (holders) and its buffer), the texture
# arrays' ids and those the RHI was last given
type ProgramState:
	parts core.ProgramPart[]
	words u32[]
	textures i64[]
	bytes u8[,]
	holders i64[]
	storage i64[]
	arrays i64[,]
	given i64[,]
	written bool[] = []   # a kernel's: per storage buffer, whether it writes it

mut programs ProgramState[] = []

# declared before the buffers, so dropped after them at exit (the last declared go first): a
# buffer's drop draws what is queued
mut queue = DrawQueue(open = false, draws = [], words = [])

# A storage buffer of the programs' parameters, shared by every program's binding that lists the
# same elements (a crowd's palette its body and its shadow programs read is uploaded once): the
# bytes it holds, its buffer, how many bindings name it, and whether a kernel writes it (then
# its binding's alone: what it holds is the GPU's, not the bytes given).
type SharedStorage:
	bytes u8[]
	buffer GpuBuffer
	users i64
	written bool = false

mut sharedStorage SharedStorage[] = []

# the program of the code the compiler built: newProgram(shader(lit.vertex, lit.pixel))
pub fn newProgram(code str) Program:
	c = core.readProgram(code)
	id = gpu.newProgram(code)
	layout = c.layoutOf(false)
	instanced = c.layoutOf(true)
	keepProgram(
		id,
		move c.parts,
		c.paramBytes,
		c.samplers.len,
		zeros(c.buffers.len),
		c.arrays.len
	)
	Program(id, layout, instanced, vertexStride = c.vertexStride, instanceStride = c.instanceStride)

# The compute program of the code the compiler built: newKernel(compute(kernels.sum, 64)). Its
# parameters are set as a program's (setParams: a storage buffer it writes is its own, never
# shared), then dispatch runs it and readStorage reads what it wrote.
pub fn newKernel(code str) Program:
	c = core.readCompute(code)
	id = gpu.newCompute(code)
	keepProgram(id, c.parts, c.paramBytes, c.samplers.len, c.written, c.arrays.len)
	Program(id, layout = -1, instanced = -1, vertexStride = 0, instanceStride = 0)

# a program's parameters' state, empty: the RHI's program `id` of these parts, block, textures,
# storage buffers (whether a compute program writes each) and texture arrays
fn keepProgram(
	id i64,
	move parts core.ProgramPart[],
	paramBytes i64,
	textures i64,
	move written bool[],
	arrays i64
):
	while programs.len <= id:
		programs.push(
			ProgramState(
				parts = [],
				words = [],
				textures = [],
				bytes = [],
				holders = [],
				storage = [],
				arrays = [],
				given = []
			)
		)
	buffers = written.len
	programs[id] = ProgramState(
		words = zeros(paramBytes / 4),
		textures = fill(textures, -1),
		bytes = fill(buffers, []),
		holders = fill(buffers, -1),
		storage = fill(buffers, -1),
		arrays = fill(arrays, []),
		given = fill(arrays, []),
		parts,
		written)

# The kernel (newKernel) run over x by y by z groups of invocations with its parameters as
# setParams last set them, between the frame's passes (the draws put off before it drawn first);
# what it writes is read by what follows.
pub fn dispatch(k Program, x i64, y i64 = 1, z i64 = 1):
	drawQueued()
	if not frameOpen:
		fail("a dispatch outside a frame")
	gpu.dispatch(
		core.ComputeCall(
			program = k.id,
			x,
			y,
			z,
			textures = programs[k.id].textures,
			storage = programs[k.id].storage
		)
	)

# The first n bytes of the kernel's storage buffer `buffer` (its place among its parameters'
# lists, in the order of their fields) as the GPU left them: the frame ends with them read back
# (as a screenshot ends it), so a loop's next frame begins after.
pub fn readStorage(k Program, buffer i64, n i64) u8[]:
	drawQueued()
	if not frameOpen:
		fail("a storage buffer read back outside a frame")
	bytes = gpu.readBuffer(programs[k.id].storage[buffer], n)
	frameOpen = false
	bytes

# the RHI's vertex layout of a program's inputs: its vertex struct's (binding 0), and with
# `instanced` its instance struct's too (binding 1, a step per instance); -1 when it has none
fn layoutOf(c core.ProgramCode, instanced bool) i64:
	if instanced and c.instanceStride == 0 or not instanced and c.vertexStride == 0: return -1
	bindings = [core.VertexBinding(stride = c.vertexStride, perInstance = false)]
	if instanced:
		bindings.push(core.VertexBinding(stride = c.instanceStride, perInstance = true))
	attributes = c.inputs
		.filter(.stream == 0 or instanced)
		.map(input: core.VertexAttribute(location = input.location, binding = input.stream,
			format = core.inputFormat(input.base, input.rows), offset = input.offset))
	gpu.vertexLayout(core.VertexLayout(bindings, attributes))

# what a struct of a program's parameters has: the packer the shader compiler writes for it
pub bound GpuParams:
	fn gpuName(self GpuParams) str
	fn gpuWrite(
		self GpuParams,
		mut words u32[],
		at i64,
		mut textures i64[],
		textureAt i64,
		mut buffers u8[,],
		bufferAt i64,
		mut arrays i64[,],
		arrayAt i64
	)

# The program's parameters set from a value of one of the structs its stages take (its
# numbers into the block as the GPU lays them out, its textures, its storage buffers' elements,
# its texture arrays): what the program's draws read from here on. A storage buffer is uploaded
# only when its elements changed (and not at all when another program's holds them: it is
# shared), a texture array given to the RHI only when its textures did (the draws put off before
# it drawn first, with the textures they were asked with): a `Material[]` and a
# `Texture[]` set again each frame cost a comparison.
pub fn setParams<P GpuParams>(p Program, params P):
	id = p.id
	name = params.gpuName()
	k = -1
	for i in 0..programs[id].parts.len:
		if programs[id].parts[i].name == name:
			k = i
	if k < 0:
		fail("setParams: the program's stages take no {name}")
	word = programs[id].parts[k].offset / 4
	firstTexture = programs[id].parts[k].firstTexture
	firstBuffer = programs[id].parts[k].firstBuffer
	buffers = programs[id].parts[k].buffers
	firstArray = programs[id].parts[k].firstArray
	arrays = programs[id].parts[k].arrays
	params.gpuWrite(
		programs[id].words,
		word,
		programs[id].textures,
		firstTexture,
		programs[id].bytes,
		firstBuffer,
		programs[id].arrays,
		firstArray
	)
	rhi.setParams(gpu, id, programs[id].words)
	arraysChanged = false
	for a in firstArray..firstArray + arrays:
		if programs[id].arrays[a] != programs[id].given[a]:
			programs[id].given[a] = programs[id].arrays[a].copy()
			arraysChanged = true
	if arraysChanged:
		drawQueued()
		rhi.setTextureArrays(gpu, id, programs[id].arrays)
	for b in firstBuffer..firstBuffer + buffers:
		setStorage(id, b)

# A program's storage binding set to the elements its packer wrote: left as it is when its
# storage holds them, else named to another binding's that does (shared), else written into its
# own (when no other binding names it) or into one of its own. The bytes are moved into the
# storage they are uploaded to, not copied.
fn setStorage(id i64, b i64):
	old = programs[id].holders[b]
	written = b < programs[id].written.len and programs[id].written[b]
	if old >= 0 and sharedStorage[old].bytes == programs[id].bytes[b] and not written:
		return   # the elements its storage holds
	e = -1
	for i in 0..sharedStorage.len:
		if i != old and sharedStorage[i].users > 0 and not written and
			not sharedStorage[i].written and
			sharedStorage[i].bytes == programs[id].bytes[b]:
			e = i
			break
	if e >= 0:
		sharedStorage[e].users += 1
		letGoStorage(old)
	elif old >= 0 and sharedStorage[old].users == 1:
		e = old
		fillStorage(e, id, b)
	else:
		letGoStorage(old)
		for i in 0..sharedStorage.len:
			if e < 0 and sharedStorage[i].users == 0:
				e = i
		if e < 0:
			sharedStorage.push(SharedStorage(bytes = [], buffer = GpuBuffer(), users = 0))
			e = sharedStorage.len - 1
		sharedStorage[e].users = 1
		fillStorage(e, id, b)
	sharedStorage[e].written = written
	programs[id].holders[b] = e
	programs[id].storage[b] = sharedStorage[e].buffer.id

# shared storage e given a program's elements (its buffer made twice their size when they do not
# fit: elements grow often)
fn fillStorage(e i64, id i64, b i64):
	written = b < programs[id].written.len and programs[id].written[b]
	if written and not sharedStorage[e].written and sharedStorage[e].buffer.id >= 0:
		sharedStorage[e].buffer = GpuBuffer()   # one a kernel writes is made apart (core.bufWritten)
	usage = core.bufStorage | core.bufWritten if written else core.bufStorage
	sharedStorage[e].buffer.fillBuffer(programs[id].bytes[b], usage, spare = 2)
	sharedStorage[e].bytes = programs[id].bytes.remove(b)
	programs[id].bytes.insert(b, [])

# a binding no longer names shared storage e: free when none does (its buffer kept for the next
# elements a binding needs storage for: two programs that share a list changing each frame
# trade two buffers, none made)
fn letGoStorage(e i64):
	if e < 0: return
	sharedStorage[e].users -= 1
	if sharedStorage[e].users == 0:
		sharedStorage[e].bytes = []

# ---------- buffers the CPU fills ----------

# A buffer the CPU fills again and again (a model's vertices, indices, draw commands, a storage
# buffer): kept while what it is given fits, replaced by a larger one when it does not.
pub type GpuBuffer:
	id i64 = -1   # the RHI's buffer, -1 none yet
	room i64 = 0   # the bytes it holds

	# the buffer freed where it is dropped, the draws put off that may read it drawn first
	mut fn drop():
		if id >= 0:
			drawQueued()
			gpu.destroyBuffer(id)

# The buffer given the bytes of the values, for the usage: replaced first when they do not fit
# or there is none (a draw may name it even empty) by one of their size, at least 256 bytes,
# `spare` times that.
fn fillBuffer<T Copy>(mut b GpuBuffer, values T[], usage i64, spare i64 = 1):
	n = values.byteSize
	if n > b.room or b.id < 0:
		room = n.max(256) * spare
		b = GpuBuffer(id = rhi.newBuffer(gpu, room, usage, false), room)
	if n > 0:
		rhi.writeBuffer(gpu, b.id, 0, values)

# ---------- draws ----------

# Where a draw starts (its first index or vertex, the offset added to each index, its first
# instance), or the buffer of commands the GPU reads its draws from (a buffer id, -1 none: its
# offset, how many, the buffer whose count says how many of those, -1 none): core.DrawCall's
# fields of the same names.
type DrawRange:
	first i64
	vertexOffset i64
	firstInstance i64
	indirect i64
	indirectOffset i64
	drawCount i64
	countBuffer i64

# a draw from the start of its buffers
fn wholeDraw():
	DrawRange(
		first = 0,
		vertexOffset = 0,
		firstInstance = 0,
		indirect = -1,
		indirectOffset = 0,
		drawCount = 1,
		countBuffer = -1
	)

# one draw of the program with the renderer's state: `count` vertices (or indices) of the
# layout from the buffers, `instances` copies (put off while sorted draws are open)
fn drawWith(
	r Renderer,
	p Program,
	layout i64,
	buffers i64[],
	offsets i64[],
	indexBuffer i64,
	count i64,
	instances i64,
	lines bool
):
	r.drawRanged(p, layout, buffers, offsets, indexBuffer, count, instances, lines, wholeDraw())

# a draw as drawWith makes it, from where `range` says (or of the commands it names)
fn drawRanged(
	r Renderer,
	p Program,
	layout i64,
	buffers i64[],
	offsets i64[],
	indexBuffer i64,
	count i64,
	instances i64,
	lines bool,
	range DrawRange
):
	s = r.state
	s.ensurePass()
	if queue.open:
		s.putOff(p.id, layout, buffers, offsets, indexBuffer, count, instances, lines, range)
		return
	st = programs[p.id]
	gpu.draw(core.DrawCall(
		program = p.id,
		layout,
		state = s.pipeline(lines),
		vertexBuffers = buffers,
		vertexOffsets = offsets,
		indexBuffer,
		count,
		instances,
		textures = st.textures,
		storage = st.storage,
		cull = s.cull,
		depthTest = s.depthTest,
		depthWrite = s.depthWrite,
		depthBias = s.depthBias,
		decal = s.decal,
		raster = s.raster,
		first = range.first,
		vertexOffset = range.vertexOffset,
		firstInstance = range.firstInstance,
		indirect = range.indirect,
		indirectOffset = range.indirectOffset,
		drawCount = range.drawCount,
		countBuffer = range.countBuffer))

# The vertex buffers (handles) and offsets of the draw being made, kept from draw to draw so that
# a draw makes no list: streams() names the first, addStream() an instance stream after it.
mut streamBuffers i64[] = []
mut streamOffsets i64[] = []

fn streams(buffer i64, offset i64):
	streamBuffers.clear()
	streamOffsets.clear()
	streamBuffers.push(buffer)
	streamOffsets.push(offset)

fn addStream(buffer i64, offset i64):
	streamBuffers.push(buffer)
	streamOffsets.push(offset)

# the vertex layout of a draw of a model of `stride` bytes a vertex, checked against what the
# program reads
fn vertexLayoutFor(p Program, stride i64, instanced bool):
	if p.layout < 0:
		fail(
			"a model drawn by a program that reads no vertices (its vertex stage takes its number)"
		)
	if stride != p.vertexStride:
		fail("a model of {stride}-byte vertices drawn by a program whose vertex struct is {p.vertexStride} bytes")
	if instanced and p.instanced < 0:
		fail("instances drawn by a program whose vertex stage takes no instance struct")
	p.instanced if instanced else p.layout

# ---------- sorted draws ----------

# A draw put off, with the state and the parameters it was asked with: its lists are in the
# queue's words from `first` (the vertex buffers, then their offsets, the textures by binding,
# the storage buffers), lent to the draw as windows when it is made; its program's parameters
# copied for it into the frame (rhi.copyParams).
type QueuedDraw:
	program i64
	layout i64
	pipeline core.PipelineState
	indexBuffer i64
	count i64
	instances i64
	cull bool
	depthTest bool
	depthWrite bool
	depthBias bool
	decal bool
	raster core.RasterState
	first i64
	buffers i64
	textures i64
	storage i64
	params i64
	range DrawRange

type DrawQueue:
	open bool
	draws QueuedDraw[]
	words i64[]

# Draws from here to endSortedDraws are put off and given to the GPU in an order that binds
# less: each run of opaque draws (no blending, the depth tested and written, not a decal) grouped
# by program, then state, then textures and vertex buffers, in the order asked where those are
# the same. Any other draw keeps its place among them and closes the run before it, so what is
# blended (or a decal, the sky) is drawn after what it was asked after. The draws keep the
# parameters they were asked with; anything else done with the GPU (another target, a clear, a
# capture, the frame's end) draws them first.
pub fn beginSortedDraws():
	queue.open = true

# the draws put off since beginSortedDraws given to the GPU in their order; draws go straight
# to it again
pub fn endSortedDraws():
	drawQueued()
	queue.open = false

fn putOff(
	s DrawState,
	program i64,
	layout i64,
	buffers i64[],
	offsets i64[],
	indexBuffer i64,
	count i64,
	instances i64,
	lines bool,
	range DrawRange
):
	first = queue.words.len
	st = programs[program]
	queue.words.extend(buffers)
	queue.words.extend(offsets)
	queue.words.extend(st.textures)
	queue.words.extend(st.storage)
	params = gpu.copyParams(program)
	queue.draws.push(QueuedDraw(
		program,
		layout,
		pipeline = s.pipeline(lines),
		indexBuffer,
		count,
		instances,
		cull = s.cull,
		depthTest = s.depthTest,
		depthWrite = s.depthWrite,
		depthBias = s.depthBias,
		decal = s.decal,
		raster = s.raster,
		first,
		buffers = buffers.len,
		textures = st.textures.len,
		storage = st.storage.len,
		params,
		range))

# whether a put-off draw may move among its neighbours: it covers what it covers whatever was
# drawn before (opaque, the depth tested and written)
fn sortable(q QueuedDraw):
	q.pipeline.blend == core.blendNone and q.pipeline.blends < 0 and q.depthTest and
		q.depthWrite and not q.decal

# the draws put off given to the GPU, each run of sortable ones in the order of its keys, and
# the queue emptied
fn drawQueued():
	if queue.draws.isEmpty: return
	n = queue.draws.len
	i = 0
	while i < n:
		if not queue.draws[i].sortable():
			drawPutOff(i)
			i += 1
			continue
		end = i
		while end < n and queue.draws[end].sortable():
			end += 1
		sortRun(i, end)
		for at in sortedRun:
			drawPutOff(at)
		i = end
	queue.draws.clear()
	queue.words.clear()

# The parts of a run's keys and its order, kept from run to run so that sorting makes no list:
# each draw's pipeline, textures and first vertex buffer, then their ranks; the places in order.
mut keyPipelines i64[] = []
mut keyTextures i64[] = []
mut keyVertices i64[] = []
mut keyValues i64[] = []
mut sortedRun i64[] = []
fewDistinct = 32

# The places of the sortable draws from..end in the order of their keys into sortedRun: each part
# of a key replaced by its rank among the run's values of it, and the ranks and the place packed
# into one integer, so that what is sorted is integers.
fn sortRun(from i64, end i64):
	keyPipelines.clear()
	keyTextures.clear()
	keyVertices.clear()
	for k in from..end:
		pipeline, textures, vertices = sortKey(k)
		keyPipelines.push(pipeline)
		keyTextures.push(textures)
		keyVertices.push(vertices)
	pipelineBits = rankParts(keyPipelines)
	textureBits = rankParts(keyTextures)
	vertexBits = rankParts(keyVertices)
	placeBits = bitsFor(end - from)
	sortedRun.clear()
	if pipelineBits + textureBits + vertexBits + placeBits > 63:
		keys = (0..end - from).map((keyPipelines[it], keyTextures[it], keyVertices[it], it))
		keys.sort()
		for (_, _, _, at) in keys:
			sortedRun.push(from + at)
		return
	for j in 0..end - from:
		parts = (keyPipelines[j] << textureBits | keyTextures[j]) << vertexBits | keyVertices[j]
		sortedRun.push(parts << placeBits | j)
	sortedRun.sort()
	mask = (1 << placeBits) - 1
	for j in 0..sortedRun.len:
		sortedRun[j] = from + (sortedRun[j] & mask)

# Each of the parts replaced by its rank among their distinct values; the bits a rank takes.
# A run's parts are mostly few values (programs, textures), gathered by a look among those found
# so far; past fewDistinct, every part is sorted.
fn rankParts(mut parts i64[]):
	keyValues.clear()
	for v in parts:
		if keyValues.len > fewDistinct: break
		if keyValues.isEmpty or keyValues[len - 1] != v and v not in keyValues:
			keyValues.push(v)
	if keyValues.len > fewDistinct:
		keyValues.clear()
		keyValues.extend(parts)
	keyValues.sort()
	m = 0
	for v in keyValues:
		if m == 0 or keyValues[m - 1] != v:
			keyValues[m] = v
			m += 1
	for j in 0..parts.len:
		lo = 0
		hi = m - 1
		while lo < hi:
			mid = (lo + hi) / 2
			if keyValues[mid] < parts[j]:
				lo = mid + 1
			else:
				hi = mid
		parts[j] = lo
	bitsFor(m)

# the bits that hold the numbers 0..n-1
fn bitsFor(n i64):
	bits = 0
	while 1 << bits < n:
		bits += 1
	bits

# the order of a sortable draw: its program and pipeline, its first four textures, its first
# vertex buffer
fn sortKey(k i64):
	q = queue.draws[k]
	flags = (
		1 if q.pipeline.alphaToCoverage else 0
	) | (2 if q.pipeline.lines else 0) | (4 if q.cull else 0) | (8 if q.depthBias else 0)
	pipeline = q.program << 32 | (q.layout + 1) << 8 | flags
	t = q.first + q.buffers * 2
	textures = 0
	for u in 0..4:
		texture = queue.words[t + u] if u < q.textures else -1
		textures = textures << 16 | (texture + 1) & 0xFFFF
	vertices = queue.words[q.first] if q.buffers > 0 else 0
	(pipeline, textures, vertices)

# a put-off draw given to the GPU with its state and parameters
fn drawPutOff(k i64):
	q = queue.draws[k]
	o = q.first + q.buffers
	t = o + q.buffers
	s = t + q.textures
	gpu.draw(core.DrawCall(
		program = q.program,
		layout = q.layout,
		state = q.pipeline,
		vertexBuffers = queue.words[q.first..o],
		vertexOffsets = queue.words[o..t],
		indexBuffer = q.indexBuffer,
		count = q.count,
		instances = q.instances,
		textures = queue.words[t..s],
		storage = queue.words[s..s + q.storage],
		cull = q.cull,
		depthTest = q.depthTest,
		depthWrite = q.depthWrite,
		depthBias = q.depthBias,
		decal = q.decal,
		raster = q.raster,
		paramsCopy = q.params,
		first = q.range.first,
		vertexOffset = q.range.vertexOffset,
		firstInstance = q.range.firstInstance,
		indirect = q.range.indirect,
		indirectOffset = q.range.indirectOffset, drawCount = q.range.drawCount, countBuffer = q.range.countBuffer))

# ---------- what the draws cost ----------

# what the last frame's draws bound and uploaded, and what they skipped as the same as before
pub fn drawStats() core.DrawStats:
	gpu.drawStats()

# what the device holds on one line (rhi/core/budget.zap)
pub fn memoryText() str:
	gpu.memoryText()

# the most host-visible memory the device has held (what uploads stage through), in bytes
pub fn hostMemoryPeak() i64:
	gpu.hostPeak()

# the last frame's draw counts on one line, for a debug print
pub fn drawStatsText() str:
	gpu.drawStats().describeStats()

# `count` vertices made by the program from their numbers alone (its vertex stage takes an
# i32), no buffer read: particles, a quad per light; `instances` copies (each its number too)
pub fn drawGenerated(r Renderer, p Program, count i64, instances i64 = 1):
	streamBuffers.clear()
	streamOffsets.clear()
	r.drawWith(p, -1, streamBuffers, streamOffsets, 0, count, instances, false)

# the bytes of a list of plain values (vertices, instances) copied into this frame's memory for
# the GPU: the buffer and the offset there
fn frameData<T Copy>(values T[]) (i64, i64):
	n = values.byteSize
	handle, offset, at = rhi.transient(gpu, n.max(4), 16)
	if n > 0:
		win.memoryAt(at, n).write(0, values)
	(handle, offset)
