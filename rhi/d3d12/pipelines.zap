# Programs and pipeline states as Direct3D 12 makes them (core keeps what both backends keep of
# them). A program is the DXIL of a vertex and a fragment stage (built with the program by the
# compiler, beside its SPIR-V) and a root signature standing in for Vulkan's
# push-descriptor layout: the parameter block a root constant buffer at b0 (its bytes copied
# into the ring when a draw finds them changed, the pass's y flip after them), each storage
# buffer a root SRV at its register (16 + its binding), the textures one table of SRVs and their
# samplers one table of samplers, each at its binding, and each texture array a table of SRVs and
# one of samplers at register 0 of space 1 + its binding. A pipeline state is a program drawn with one vertex layout, one
# blending, one kind of target and one state of the rasterizer and the depth test (Direct3D 12
# has no dynamic cull mode, depth test, write or bias: they are part of the pipeline, its key
# the state bits); it is made the first time a draw needs it. A compute program is the DXIL of
# its stage, its root signature made the same way (a storage buffer it writes a root UAV at
# u<16 + its binding), and its one pipeline state, made with it.

import win
import rhi.core

# A frame's table of a program's texture arrays' views: a range of the kept views (each array's
# from its place in it), the views it has room for, the lists' version it holds and the frame (the
# device's timeline) that last set it. A table is written only while no work of the GPU reads it:
# its frame's last use is done, and a table set earlier in this frame is replaced, not written,
# when the lists change.
pub type ArrayTable:
	first i64   # -1 none yet
	room i64
	version i64
	boundAt i64

# an array's samplers (one per texture, in its order): a range of the sampler heap, shared by the
# frames' tables, made again only when the samplers differ (key: their indices)
pub type SamplerRun:
	first i64   # -1 none yet
	count i64
	key i64[]
	version i64   # the lists' version it was found right for

# a program's Direct3D 12 objects
pub type ProgramRecord:
	rootSignature i64
	tables ArrayTable[]   # per frame in flight
	runs SamplerRun[]   # per texture array
	vertexDxil str
	fragmentDxil str
	pipeline i64 = 0   # a compute program's pipeline state (a graphics program's are made per key)

# the root parameters' places: the constants first, the storage buffers next, then the tables
fn bufferParameter(i i64):
	1 + i

# the place of texture array k's table of views (its samplers' is next): after the textures' tables
fn arrayParameter(rec core.ProgramState, k i64):
	bufferParameter(rec.buffers.len) + (2 if not rec.samplers.isEmpty else 0) + k * 2

# the Direct3D 12 objects of a program the compiler built (shader(...))
pub fn newProgram(mut device Device, mut p core.ProgramCode):
	if p.vertexDxil.isEmpty or p.fragmentDxil.isEmpty:
		fail("rhi: a program built without DXIL (the compiler found no DXC and said why when it built it, spec 11)")
	tables = fill(core.framesInFlight, ArrayTable(first = -1, room = 0, version = -1, boundAt = -1))
	runs = fill(p.arrays.len, SamplerRun(first = -1, count = 0, key = [], version = -1))
	device.programs.push(ProgramRecord(
		rootSignature = device.rootSignature(p.samplers, p.buffers, [], p.arrays),
		tables,
		runs,
		vertexDxil = move p.vertexDxil,
		fragmentDxil = move p.fragmentDxil))

# the Direct3D 12 objects of a compute program the compiler built (compute(...)): its root
# signature and its pipeline state
pub fn newCompute(mut d Device, mut c core.ComputeCode):
	if c.dxil.isEmpty:
		fail("rhi: a compute program built without DXIL (the compiler found no DXC and said why when it built it, spec 11)")
	signature = d.rootSignature(c.samplers, c.buffers, c.written, c.arrays)
	desc = ComputePipelineDesc(rootSignature = signature, cs = c.dxil, csSize = c.dxil.len)
	check(
		deviceCreateComputePipelineState(d.device, desc, iidPipelineState, out pipeline),
		"CreateComputePipelineState"
	)
	tables = fill(core.framesInFlight, ArrayTable(first = -1, room = 0, version = -1, boundAt = -1))
	runs = fill(c.arrays.len, SamplerRun(first = -1, count = 0, key = [], version = -1))
	d.programs.push(ProgramRecord(
		rootSignature = signature,
		tables,
		runs,
		vertexDxil = "",
		fragmentDxil = "",
		pipeline))

# the root signature of what a program reads (`written`: per storage buffer, whether a compute
# stage writes it, a root UAV then)
fn rootSignature(
	d Device,
	samplers core.SamplerSlot[],
	buffers i64[],
	written bool[],
	arrays core.TextureArraySlot[]
):
	unused = [DescriptorRange(kind = 0, base = 0, offset = 0)]   # what a root CBV or SRV ignores
	views = []
	samplerRanges = []
	for i in 0..samplers.len:
		# a texture's SRV at t<binding>, a storage image's UAV at u<binding>
		views.push(
			DescriptorRange(
				kind = u32(1 if core.isImageKind(samplers[i].kind) else 0),
				base = samplers[i].binding,
				offset = u32(i)
			)
		)
		samplerRanges.push(
			DescriptorRange(kind = 3, base = samplers[i].binding, offset = u32(i))
		)
	# each texture array: its views and its samplers at register 0 of its space (a length, or
	# unbounded: the rest of the space)
	arrayRanges = []
	for a in arrays:
		count = a.count if a.count > 0 else 0xFFFF_FFFF
		space = 1 + a.binding
		arrayRanges.push([DescriptorRange(kind = 0, count, base = 0, space, offset = 0)])
		arrayRanges.push([DescriptorRange(kind = 3, count, base = 0, space, offset = 0)])
	parameters = [RootParameter(kind = 2, a = 0, ranges = unused)]   # the constant buffer at b0
	for i, b in buffers:
		# an SRV at t<binding>, or a UAV at u<binding>
		kind = 4 if i < written.len and written[i] else 3
		parameters.push(RootParameter(kind = u32(kind), a = u32(b), ranges = unused))
	if not samplers.isEmpty:
		parameters.push(RootParameter(kind = 0, a = u32(views.len), ranges = views))
		parameters.push(
			RootParameter(kind = 0, a = u32(samplerRanges.len), ranges = samplerRanges)
		)
	parameters.extend(arrayRanges.map(ranges: RootParameter(kind = 0, a = 1, ranges)))
	desc = RootSignatureDesc(count = u32(parameters.len), parameters)
	hr = D3D12SerializeRootSignature(desc, 1, out blob, out errors)
	if hr < 0:
		why = ""
		if errors != 0:
			at, n = blobBytes(errors)
			text = win.memoryAt(at, n).bytes(0, n)
			why = str(move text)
		fail("rhi: D3D12SerializeRootSignature failed: {why}")
	at, n = blobBytes(blob)
	check(
		deviceCreateRootSignature(d.device, 0, at, n, iidRootSignature, out signature),
		"CreateRootSignature"
	)
	win.release(blob)
	signature

# ---------- pipeline states ----------

# The program's pipeline state for a key, loaded from the library (or made, and kept for the next
# run's): core's pipelineOf makes it the first time a draw needs it, or with its program.
pub fn newPipeline(mut device Device,
	program i64,
	key core.PipelineKey,
	layout core.VertexLayout,
	variant core.PipelineVariant
) core.PipelineEntry:
	name = variant.libraryName()
	e = device.newPipelineState(program, key, layout, name)
	device.stored.push(StoredPipeline(name, pipeline = e.pipeline))
	e

# a pipeline state's name in a library: its variant hashed (the program's code among it), as UTF-16
fn libraryName(v core.PipelineVariant):
	bytes = v.toBytes()
	h = str(move bytes).hash()
	text = "zap{h >> 32 & 0xFFFFFFFF:08x}{h & 0xFFFFFFFF:08x}"
	wide = []
	for c in text.bytes():
		wide.push(c)
		wide.push(0)
	wide.push(0)
	wide.push(0)
	wide

fn newPipelineState(
	d Device,
	program i64,
	key core.PipelineKey,
	layout core.VertexLayout,
	name u8[]
):
	rec ref ProgramRecord = d.programs[program]
	inputs ref core.VertexInput[] = d.state.programs[program].inputs
	bits = key.bits
	# the vertex inputs the program reads: from the layout, or zeros from an extra slot
	semantic = "ATTR\0"
	elements = []
	zeroSlot = -1
	for input in inputs:
		found = false
		for a in layout.attributes:
			if a.location == input.location and not found:
				perInstance = layout.bindings[a.binding].perInstance
				elements.push(InputElement(
					semantic,
					index = u32(a.location),
					format = u32(dxgiFormat(a.format)),
					slot = u32(a.binding),
					offset = u32(a.offset), slotClass = u32(1 if perInstance else 0), stepRate = u32(
						1 if perInstance else 0
				)))
				found = true
		if not found:
			if zeroSlot < 0:
				zeroSlot = layout.bindings.len
			# the same zeros for every vertex (a buffer view of stride 0)
			elements.push(InputElement(
				semantic,
				index = input.location,
				format = u32(dxgiFormat(core.inputFormat(input.base, input.rows))),
				slot = u32(zeroSlot), offset = 0, slotClass = 0, stepRate = 0))
	colorFormats = key.colorFormats()
	formats u32[8] = zeros(8)
	for k, f in colorFormats:
		formats[k] = u32(dxgiFormat(f))
	targets BlendTarget[8] = fill(8, BlendTarget())
	blends = d.state.targetBlends(key)
	for k, b in blends:
		targets[k] = blendTarget(b)
	withDepth = key.depthFormat != core.fmtUndefined
	bias, slope = core.depthBiasOf(bits.bits(4, 2))
	desc = GraphicsPipelineDesc(
		rootSignature = rec.rootSignature,
		vs = rec.vertexDxil,
		vsSize = rec.vertexDxil.len,
		ps = rec.fragmentDxil,
		psSize = rec.fragmentDxil.len,
		alphaToCoverage = u32(1 if key.alphaToCoverage else 0),
		independentBlend = u32(1 if blends.len > 1 else 0),
		targets,
		cull = u32([1, 3, 1, 2][core.cullOf(bits)]),   # NONE, BACK, FRONT
		frontCounterClockwise = u32(1 if bits.bits(1, 1) == 0 else 0),
		depthBias = i32(i64(bias)),
		slopeScaledDepthBias = slope,
		multisample = u32(1 if key.samples > 1 else 0),
		depthEnable = u32(1 if withDepth and bits.bits(2, 1) == 1 else 0),
		depthWrite = u32(1 if withDepth and bits.bits(3, 1) == 1 else 0),
		depthFunc = bits.bits(6, 3) + 1,
		inputs = elements,
		inputCount = u32(elements.len),
		topologyType = u32(2 if key.lines else 3),
		targetCount = u32(colorFormats.len),
		targetFormats = formats,
		depthFormat = u32(
			dxgiFormat(key.depthFormat) if withDepth else 0
		), sampleCount = u32(key.samples))
	# from the library when it holds this one (a desc that differs from the one stored is refused)
	if d.library != 0 and
		libraryLoadGraphicsPipeline(d.library, name, desc, iidPipelineState, out loaded) >= 0:
		return core.PipelineEntry(pipeline = loaded, zeroBinding = zeroSlot)
	check(
		deviceCreateGraphicsPipelineState(d.device, desc, iidPipelineState, out pipeline),
		"CreateGraphicsPipelineState"
	)
	core.PipelineEntry(pipeline, zeroBinding = zeroSlot)

# a color target's blending: core's factors (Vulkan's numbers) as Direct3D 12's, a color one in
# the alpha's place as its alpha one
fn blendTarget(b core.TargetBlend):
	BlendTarget(
		enable = u32(1 if b.on else 0),
		src = u32(blendFactors[b.srcColor]),
		dst = u32(blendFactors[b.dstColor]),
		op = u32(b.colorOp + 1),
		srcAlpha = u32(alphaFactors[b.srcAlpha]),
		dstAlpha = u32(alphaFactors[b.dstAlpha]),
		opAlpha = u32(b.alphaOp + 1),
		writeMask = u8(b.writeMask)
	)

# Direct3D 12's blend factors by Vulkan's numbers (the constant's as BLEND_FACTOR), and those of
# the alpha (SRC_COLOR as SRC_ALPHA, DEST_COLOR as DEST_ALPHA)
blendFactors = [1, 2, 3, 4, 9, 10, 5, 6, 7, 8, 14, 15, 14, 15, 11]
alphaFactors = [1, 2, 5, 6, 7, 8, 5, 6, 7, 8, 14, 15, 14, 15, 11]
