# Programs and pipelines as Vulkan makes them (core keeps what both backends keep of them). A
# program is the SPIR-V of a vertex and a fragment stage (built with the program by the
# compiler) and the layout of what it reads (its samplers, its storage buffers, its parameter
# block, all pushed as descriptors with a draw that changes them in set 0; its texture arrays in
# set 1, a table of each frame's kept from draw to draw). A compute program is the SPIR-V of its
# stage, its layout made the same way, and its one pipeline, made with it.
# A pipeline is a program drawn with one vertex layout, one blending and one kind of target; it
# is made the first time a draw needs it. Viewport and scissor are dynamic state; culling, front
# faces, depth test, write, comparison and bias too where the device sets them so (Vulkan 1.3, or
# the extended dynamic states), else held by the pipeline (its key's state bits).

# A frame's table of a program's texture arrays: a descriptor set of set 1's layout (in a pool of
# its own, freed with it), the textures its variable binding has room for, the lists' version it
# holds and the frame (the device's timeline) that last bound it. A table is written only while no
# work of the GPU reads it: its frame's last use is done, and a table bound earlier in this frame
# is replaced, not written, when the lists change.
import rhi.core

pub type ArrayTable:
	pool i64
	set i64
	room i64
	version i64
	boundAt i64

# a program's Vulkan objects
pub type ProgramRecord:
	vertex i64
	fragment i64
	setLayout i64
	layout i64
	arraysLayout i64   # set 1's layout (its texture arrays), 0 none
	variable i64   # the array of a variable count (set 1's last binding, without a length), -1 none
	tables ArrayTable[]   # per frame in flight
	pipeline i64 = 0   # a compute program's pipeline (a graphics program's are made per key)

# the Vulkan objects of a program the compiler built (shader(...))
pub fn newProgram(mut device Device, mut p core.ProgramCode):
	vertex = device.shaderModule(p.vertexSpirv)
	fragment = device.shaderModule(p.fragmentSpirv)
	rec = device.programLayouts(p.samplers, p.buffers, p.paramBytes, p.arrays)
	rec.vertex = vertex
	rec.fragment = fragment
	device.programs.push(rec)

# the Vulkan objects of a compute program the compiler built (compute(...)): its stage's module,
# its layouts, and its pipeline
pub fn newCompute(mut d Device, mut c core.ComputeCode):
	module = d.shaderModule(c.spirv)
	rec = d.programLayouts(c.samplers, c.buffers, c.paramBytes, c.arrays)
	rec.vertex = module
	info = ComputePipelineCreateInfo(module, name = "main\0", layout = rec.layout)
	check(
		vkCreateComputePipelines(d.device, d.pipelineCache, 1, info, 0, out pipeline),
		"vkCreateComputePipelines"
	)
	rec.pipeline = pipeline
	d.programs.push(rec)

# A program's layouts (its modules left to the caller): one set (pushed) of the samplers,
# the storage buffers and the parameter block; its texture arrays' set 1; and the frames' tables.
fn programLayouts(
	d Device,
	samplers core.SamplerSlot[],
	buffers i64[],
	paramBytes i64,
	arrays core.TextureArraySlot[]
):
	if arrays.any(.count == 0) and not d.support.bindless:
		fail("rhi: a program that reads texture arrays (Texture[]) at computed indices on a device without descriptor indexing")
	bindings = samplers.map(layoutBinding(.binding, descriptorOf(.kind)))
	bindings.extend(buffers.map(layoutBinding(it, descStorageBuffer)))
	if paramBytes > 0:
		bindings.push(layoutBinding(core.paramsBinding, descUniformBuffer))
	setInfo = DescriptorSetLayoutCreateInfo(   # PUSH_DESCRIPTOR, when the device has them
		flags = 1 if d.support.pushDescriptor else 0,
		count = u32(bindings.len),
		bindings
	)
	check(
		vkCreateDescriptorSetLayout(d.device, setInfo, 0, out setLayout),
		"vkCreateDescriptorSetLayout"
	)
	arraysLayout, variable = d.arraySetLayout(arrays) if not arrays.isEmpty else (0, -1)
	sets = [setLayout, arraysLayout] if arraysLayout != 0 else [setLayout]
	check(
		vkCreatePipelineLayout(d.device, PipelineLayoutCreateInfo(setCount = u32(sets.len), sets), 0, out layout),
		"vkCreatePipelineLayout"
	)
	tables = fill(
		core.framesInFlight,
		ArrayTable(pool = 0, set = 0, room = 0, version = -1, boundAt = -1)
	)
	ProgramRecord(vertex = 0, fragment = 0, setLayout, layout, arraysLayout, variable, tables)

# Set 1's layout for a program's texture arrays: each a binding of combined images, updated after
# it is bound and partially bound (a table holds only the textures listed); the last binding, when
# it has no length, of a variable count (as many as its table has room for, up to the device's
# limit). On a device without descriptor indexing, each array has a length (read at literal
# indices) and its table holds that many. The layout and the array of a variable count (-1 none).
fn arraySetLayout(d Device, arrays core.TextureArraySlot[]):
	last = 0
	for k in 0..arrays.len:
		if arrays[k].binding > arrays[last].binding:
			last = k
	variable = last if arrays[last].count == 0 else -1
	bindings = []
	flags = []
	for k in 0..arrays.len:
		bindings.push(DescriptorSetLayoutBinding(
			binding = arrays[k].binding,
			kind = u32(descSampledImage),
			count = u32(d.fixedRoom(arrays[k], k == variable)),
			stages = everyStage))
		flags.push(
			u32(
				bindUpdateAfterBind | bindPartiallyBound | (
					bindVariableCount if k == variable else 0
				)
			)
		)
	bindingFlags = DescriptorSetLayoutBindingFlags(count = u32(flags.len), flags)
	info = DescriptorSetLayoutCreateInfo(   # UPDATE_AFTER_BIND_POOL
		next = bindingFlags if d.support.bindless else none,
		flags = 2 if d.support.bindless else 0,
		count = u32(bindings.len),
		bindings
	)
	check(
		vkCreateDescriptorSetLayout(d.device, info, 0, out layout),
		"vkCreateDescriptorSetLayout (texture arrays)"
	)
	(layout, variable)

# the textures an array's binding holds in set 1's layout: its length, the device's limit for the
# one of a variable count, a fixed room for another without a length
fn fixedRoom(d Device, slot core.TextureArraySlot, variable bool) i64:
	slot.count if slot.count > 0 else d.support.maxTextures if variable else unboundedRoom

# the room of an array without a length that is not set 1's last binding (only the last may vary)
unboundedRoom = 4096

# binding flags of descriptor indexing
bindUpdateAfterBind = 1
bindPartiallyBound = 4
bindVariableCount = 8

# the stages a binding is seen by: every graphics stage and compute
everyStage = 0x3F

# a descriptor binding seen by every stage
fn layoutBinding(binding i64, kind i64):
	DescriptorSetLayoutBinding(binding = u32(binding), kind = u32(kind), stages = everyStage)

fn shaderModule(d Device, code str):
	info = ShaderModuleCreateInfo(codeSize = code.len, code)
	check(vkCreateShaderModule(d.device, info, 0, out module), "vkCreateShaderModule")
	module

# ---------- pipelines ----------

# A program's pipeline for a key (core's pipelineOf makes it the first time a draw needs it, or
# with its program).
pub fn newPipeline(mut d Device,
	program i64,
	key core.PipelineKey,
	layout core.VertexLayout,
	variant core.PipelineVariant
) core.PipelineEntry:
	_ = variant
	renderPass = 0 if d.support.dynamicRendering
		else d.renderPassOf(key.colorFormats(), key.depthFormat, key.samples, false, false)
	rec ref ProgramRecord = d.programs[program]
	inputs ref core.VertexInput[] = d.state.programs[program].inputs
	entry = "main\0"
	stages = [
		ShaderStage(stage = 1, module = rec.vertex, name = entry),
		ShaderStage(stage = 0x10, module = rec.fragment, name = entry)
	]
	bindings, attributes, zeroBinding = layout.newPipelineVertexInput(inputs)
	vertexInput = VertexInputState(
		bindingCount = u32(bindings.len),
		bindings,
		attributeCount = u32(attributes.len),
		attributes
	)
	assembly = InputAssemblyState(topology = 1 if key.lines else 3)   # LINE_LIST or TRIANGLE_LIST
	raster, depth = rasterOf(key.bits)
	multisample = MultisampleState(
		samples = u32(key.samples),
		alphaToCoverage = 1 if key.alphaToCoverage else 0
	)
	viewport = ViewportState()
	attachments = d.state.targetBlends(key).map(.blendAttachment())
	blend = ColorBlendState(
		attachmentCount = u32(attachments.len),
		attachments,
		constants = fill(4, f32(0.0))
	)
	# viewport, scissor; depth bias, cull mode, front face, depth test, write, compare, bias on
	states = [u32(0), 1]
	if d.support.dynamicState:
		states.extend(
			[
				3,
				1_000_267_000,
				1_000_267_001,
				1_000_267_006,
				1_000_267_007,
				1_000_267_008,
				1_000_377_002
			]
		)
	dynamic = DynamicState(count = u32(states.len), states)
	formats = key.colorFormats().map(u32(it))
	rendering = PipelineRenderingCreateInfo(
		colorCount = u32(attachments.len),
		formats,
		depthFormat = u32(key.depthFormat)
	)
	info = GraphicsPipelineCreateInfo(
		next = rendering if renderPass == 0 else none,
		stageCount = 2,
		stages,
		vertexInput,
		inputAssembly = assembly,
		viewport,
		rasterization = raster, multisample, depthStencil = depth, colorBlend = blend, dynamic, layout = rec.layout, renderPass)
	check(
		vkCreateGraphicsPipelines(d.device, d.pipelineCache, 1, info, 0, out pipeline),
		"vkCreateGraphicsPipelines"
	)
	core.PipelineEntry(pipeline, zeroBinding)

# A pipeline's rasterization and depth: filled triangles, culled, faced, tested, written, compared
# and biased as the state bits say (all 0 where they are dynamic, set by the draws).
fn rasterOf(bits i64):
	constant, slope = core.depthBiasOf(bits.bits(4, 2))
	raster = RasterizationState(
		cullMode = u32(cullModeOf(bits)),
		frontFace = bits.bits(1, 1),
		depthBias = u32(1 if bits.bits(4, 2) != 0 else 0),
		biasConstant = constant,
		biasSlope = slope
	)
	depth = DepthStencilState(
		test = bits.bits(2, 1),
		write = bits.bits(3, 1),
		compare = bits.bits(6, 3),
		front = StencilOpState(),
		back = StencilOpState()
	)
	(raster, depth)

# the faces the state bits cull, as Vulkan names them: NONE, BACK, FRONT
fn cullModeOf(bits i64):
	[0, 2, 0, 1][core.cullOf(bits)]

# the vertex inputs a program reads: from the layout, or zeros from an extra binding; returns the
# bindings, the attributes and the zeros binding (-1 when none)
fn newPipelineVertexInput(layout core.VertexLayout, inputs ref core.VertexInput[]
):
	bindings = (0..layout.bindings.len).map(i: VertexBindingDescription(
		binding = u32(i),
		stride = u32(layout.bindings[i].stride),
		rate = 1 if layout.bindings[i].perInstance else 0))
	attributes = []
	zeroBinding = -1
	for input in inputs:
		found = false
		for a in layout.attributes:
			if a.location == input.location and not found:
				attributes.push(
					VertexAttributeDescription(
						location = u32(a.location),
						binding = u32(a.binding),
						format = u32(a.format),
						offset = u32(a.offset)
					)
				)
				found = true
		if not found:
			if zeroBinding < 0:
				zeroBinding = layout.bindings.len
				# the same zeros for every copy
				bindings.push(
					VertexBindingDescription(
						binding = u32(zeroBinding),
						stride = 0,
						rate = 1
					)
				)
			attributes.push(VertexAttributeDescription(
				location = input.location,
				binding = u32(zeroBinding),
				format = u32(core.inputFormat(input.base, input.rows)),
				offset = 0))
	(bindings, attributes, zeroBinding)

# a color attachment's blending (core's numbers are Vulkan's)
fn blendAttachment(b core.TargetBlend):
	BlendAttachment(
		blend = u32(1 if b.on else 0),
		srcColor = u32(b.srcColor),
		dstColor = u32(b.dstColor),
		colorOp = u32(b.colorOp),
		srcAlpha = u32(b.srcAlpha),
		dstAlpha = u32(b.dstAlpha),
		alphaOp = u32(b.alphaOp),
		writeMask = u32(b.writeMask)
	)
