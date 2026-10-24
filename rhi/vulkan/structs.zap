# The Vulkan structures the RHI passes, declared as C has them (extern types): the compiler lays
# them out and writes their pointers from the values they are made of. A handle is an i64; a
# VkBool32 a u32; a pointer the RHI never sets (a pNext with nothing chained) is an i64 left 0.
# A text a structure points to ends with \0. What Vulkan writes starts as zeros.

# a name in a list of names (char**)
pub extern type Name:
	text ref str

# a count Vulkan reads and writes (the length of a list asked for, then the length given)
pub extern type Count:
	n u32 = 0

pub extern type ApplicationInfo:
	sType u32 = 0
	next i64 = 0
	name ref str
	version u32
	engineName ref str
	engineVersion u32
	apiVersion u32

pub extern type InstanceCreateInfo:
	sType u32 = 1
	next i64 = 0
	flags u32 = 0
	app ref ApplicationInfo
	layerCount u32 = 0
	layers i64 = 0
	extensionCount u32
	extensions ref Name[]

pub extern type Win32SurfaceCreateInfo:
	sType u32 = 1_000_009_000
	next i64 = 0
	flags u32 = 0
	hinstance i64
	hwnd i64

pub extern type DeviceProperties:
	apiVersion u32 = 0
	driverVersion u32 = 0
	vendor u32 = 0
	device u32 = 0
	deviceType u32 = 0
	name u8[256]
	uuid u8[16]
	rest u8[532]   # the limits and the sparse properties

pub extern type QueueFamily:
	flags u32 = 0
	count u32 = 0
	timestampBits u32 = 0
	granularity u32[3]

pub extern type ExtensionProperties:
	name u8[256]
	version u32 = 0

pub extern type MemoryType:
	flags u32 = 0
	heap u32 = 0

pub extern type MemoryHeap:
	size i64 = 0
	flags u32 = 0

pub extern type MemoryProperties:
	typeCount u32 = 0
	types MemoryType[32] = fill(32, MemoryType())
	heapCount u32 = 0
	heaps MemoryHeap[16] = fill(16, MemoryHeap())

pub extern type DeviceQueueCreateInfo:
	sType u32 = 2
	next i64 = 0
	flags u32 = 0
	family u32
	count u32 = 1
	priorities ref f32[]

# Vulkan 1.2's features (descriptor indexing: the texture arrays' tables)
pub extern type Vulkan12Features:
	sType u32 = 51
	next ref FeatureLink? = none
	samplerMirrorClampToEdge u32 = 0
	drawIndirectCount u32 = 0
	storageBuffer8BitAccess u32 = 0
	uniformAndStorageBuffer8BitAccess u32 = 0
	storagePushConstant8 u32 = 0
	shaderBufferInt64Atomics u32 = 0
	shaderSharedInt64Atomics u32 = 0
	shaderFloat16 u32 = 0
	shaderInt8 u32 = 0
	descriptorIndexing u32 = 0
	shaderInputAttachmentArrayDynamicIndexing u32 = 0
	shaderUniformTexelBufferArrayDynamicIndexing u32 = 0
	shaderStorageTexelBufferArrayDynamicIndexing u32 = 0
	shaderUniformBufferArrayNonUniformIndexing u32 = 0
	shaderSampledImageArrayNonUniformIndexing u32 = 0
	shaderStorageBufferArrayNonUniformIndexing u32 = 0
	shaderStorageImageArrayNonUniformIndexing u32 = 0
	shaderInputAttachmentArrayNonUniformIndexing u32 = 0
	shaderUniformTexelBufferArrayNonUniformIndexing u32 = 0
	shaderStorageTexelBufferArrayNonUniformIndexing u32 = 0
	descriptorBindingUniformBufferUpdateAfterBind u32 = 0
	descriptorBindingSampledImageUpdateAfterBind u32 = 0
	descriptorBindingStorageImageUpdateAfterBind u32 = 0
	descriptorBindingStorageBufferUpdateAfterBind u32 = 0
	descriptorBindingUniformTexelBufferUpdateAfterBind u32 = 0
	descriptorBindingStorageTexelBufferUpdateAfterBind u32 = 0
	descriptorBindingUpdateUnusedWhilePending u32 = 0
	descriptorBindingPartiallyBound u32 = 0
	descriptorBindingVariableDescriptorCount u32 = 0
	runtimeDescriptorArray u32 = 0
	samplerFilterMinmax u32 = 0
	scalarBlockLayout u32 = 0
	imagelessFramebuffer u32 = 0
	uniformBufferStandardLayout u32 = 0
	shaderSubgroupExtendedTypes u32 = 0
	separateDepthStencilLayouts u32 = 0
	hostQueryReset u32 = 0
	timelineSemaphore u32 = 0
	bufferDeviceAddress u32 = 0
	bufferDeviceAddressCaptureReplay u32 = 0
	bufferDeviceAddressMultiDevice u32 = 0
	vulkanMemoryModel u32 = 0
	vulkanMemoryModelDeviceScope u32 = 0
	vulkanMemoryModelAvailabilityVisibilityChains u32 = 0
	shaderOutputViewportIndex u32 = 0
	shaderOutputLayer u32 = 0
	subgroupBroadcastDynamicId u32 = 0

# A structure of features past Vulkan 1.2 chained after its 1.2 ones: Vulkan 1.3's or 1.4's, or
# an extension's, told apart by sType, its VkBool32s in their order (`on`, as many as the longest
# has; the rest left 0).
pub extern type FeatureLink:
	sType u32
	next ref FeatureLink? = none
	on u32[24]

# where a feature is in its structure's `on`: Vulkan 1.3's (sType 53) dynamic rendering; 1.4's
# (sType 55) maintenance5, maintenance6, host image copy and push descriptors; an extension's one
# feature first
pub v13DynamicRendering = 12
pub v14Maintenance5 = 15
pub v14Maintenance6 = 16
pub v14HostImageCopy = 19
pub v14PushDescriptor = 20
pub v13Features = u32(53)
pub v14Features = u32(55)
pub dynamicRenderingFeatures = u32(1_000_044_003)
pub dynamicStateFeatures = u32(1_000_267_000)   # VK_EXT_extended_dynamic_state's
pub dynamicState2Features = u32(1_000_377_000)

pub extern type Features2:
	sType u32 = 1_000_059_000
	next ref Vulkan12Features?
	features u32[55]   # VkPhysicalDeviceFeatures, in its order

pub extern type DeviceCreateInfo:
	sType u32 = 3
	next ref Features2?
	flags u32 = 0
	queueCount u32 = 1
	queue ref DeviceQueueCreateInfo
	layerCount u32 = 0
	layers i64 = 0
	extensionCount u32
	extensions ref Name[]
	features i64 = 0

pub extern type SurfaceCapabilities:
	minImageCount u32 = 0
	maxImageCount u32 = 0
	currentWidth u32 = 0
	currentHeight u32 = 0
	minWidth u32 = 0
	minHeight u32 = 0
	maxWidth u32 = 0
	maxHeight u32 = 0
	maxLayers u32 = 0
	transforms u32 = 0
	currentTransform u32 = 0
	compositeAlpha u32 = 0
	usage u32 = 0

pub extern type SwapchainCreateInfo:
	sType u32 = 1_000_001_000
	next i64 = 0
	flags u32 = 0
	surface i64
	minImageCount u32
	format u32
	colorSpace u32 = 0
	width u32
	height u32
	layers u32 = 1
	usage u32
	sharing u32 = 0
	familyCount u32 = 0
	families i64 = 0
	transform u32
	compositeAlpha u32 = 1
	presentMode u32
	clipped u32 = 1
	old i64

pub extern type ImageSubresourceRange:
	aspect u32
	baseLevel u32 = 0
	levels u32
	baseLayer u32 = 0
	layers u32

pub extern type ImageViewCreateInfo:
	sType u32 = 15
	next i64 = 0
	flags u32 = 0
	image i64
	viewType u32
	format u32
	swizzle u32[4]
	range ImageSubresourceRange

pub extern type ImageCreateInfo:
	sType u32 = 14
	next i64 = 0
	flags u32 = 0
	imageType u32 = 1
	format u32
	width u32
	height u32
	depth u32 = 1
	levels u32
	layers u32
	samples u32
	tiling u32 = 0
	usage u32
	sharing u32 = 0
	familyCount u32 = 0
	families i64 = 0
	initialLayout u32 = 0

pub extern type BufferCreateInfo:
	sType u32 = 12
	next i64 = 0
	flags u32 = 0
	size i64
	usage u32
	sharing u32 = 0
	familyCount u32 = 0
	families i64 = 0

pub extern type MemoryRequirements:
	size i64 = 0
	alignment i64 = 0
	typeBits u32 = 0

# the memory an image made with this description would need, asked before it is made
pub extern type DeviceImageMemoryRequirements:
	sType u32 = 1_000_413_003
	next i64 = 0
	info ref ImageCreateInfo
	planeAspect u32 = 0

pub extern type MemoryRequirements2:
	sType u32 = 1_000_146_003
	next i64 = 0
	size i64 = 0
	alignment i64 = 0
	typeBits u32 = 0

pub extern type MemoryAllocateInfo:
	sType u32 = 5
	next i64 = 0
	size i64
	typeIndex u32

pub extern type SamplerCreateInfo:
	sType u32 = 31
	next i64 = 0
	flags u32 = 0
	magFilter u32
	minFilter u32
	mipmapMode u32
	addressU u32
	addressV u32
	addressW u32
	lodBias f32 = 0.0
	anisotropyEnable u32
	maxAnisotropy f32
	compareEnable u32
	compareOp u32
	minLod f32 = 0.0
	maxLod f32
	border u32
	unnormalized u32 = 0

# a pool of timestamps (VK_QUERY_TYPE_TIMESTAMP)
pub extern type QueryPoolCreateInfo:
	sType u32 = 11
	next i64 = 0
	flags u32 = 0
	kind u32 = 2
	count u32
	statistics u32 = 0

# a size Vulkan reads and writes (a size_t)
pub extern type Size:
	n i64 = 0

pub extern type PipelineCacheCreateInfo:
	sType u32 = 17
	next i64 = 0
	flags u32 = 0
	size i64
	data ref u8[]

pub extern type ShaderModuleCreateInfo:
	sType u32 = 16
	next i64 = 0
	flags u32 = 0
	codeSize i64
	code ref str

pub extern type DescriptorSetLayoutBinding:
	binding u32
	kind u32
	count u32 = 1
	stages u32
	samplers i64 = 0

pub extern type DescriptorSetLayoutCreateInfo:
	sType u32 = 32
	next ref DescriptorSetLayoutBindingFlags? = none
	flags u32
	count u32
	bindings ref DescriptorSetLayoutBinding[]

pub extern type PipelineLayoutCreateInfo:
	sType u32 = 30
	next i64 = 0
	flags u32 = 0
	setCount u32
	sets ref i64[]
	rangeCount u32 = 0
	ranges i64 = 0

pub extern type ShaderStage:
	sType u32 = 18
	next i64 = 0
	flags u32 = 0
	stage u32
	module i64
	name ref str
	specialization i64 = 0

pub extern type VertexBindingDescription:
	binding u32
	stride u32
	rate u32

pub extern type VertexAttributeDescription:
	location u32
	binding u32
	format u32
	offset u32

pub extern type VertexInputState:
	sType u32 = 19
	next i64 = 0
	flags u32 = 0
	bindingCount u32
	bindings ref VertexBindingDescription[]
	attributeCount u32
	attributes ref VertexAttributeDescription[]

pub extern type InputAssemblyState:
	sType u32 = 20
	next i64 = 0
	flags u32 = 0
	topology u32
	restart u32 = 0

pub extern type ViewportState:
	sType u32 = 22
	next i64 = 0
	flags u32 = 0
	viewportCount u32 = 1
	viewports i64 = 0
	scissorCount u32 = 1
	scissors i64 = 0

pub extern type RasterizationState:
	sType u32 = 23
	next i64 = 0
	flags u32 = 0
	depthClamp u32 = 0
	discard u32 = 0
	polygonMode u32 = 0
	cullMode u32 = 0
	frontFace u32 = 0
	depthBias u32 = 0
	biasConstant f32 = 0.0
	biasClamp f32 = 0.0
	biasSlope f32 = 0.0
	lineWidth f32 = 1.0

pub extern type MultisampleState:
	sType u32 = 24
	next i64 = 0
	flags u32 = 0
	samples u32
	sampleShading u32 = 0
	minSampleShading f32 = 0.0
	sampleMask i64 = 0
	alphaToCoverage u32
	alphaToOne u32 = 0

pub extern type StencilOpState:
	fail u32 = 0
	pass u32 = 0
	depthFail u32 = 0
	compare u32 = 0
	compareMask u32 = 0
	writeMask u32 = 0
	reference u32 = 0

pub extern type DepthStencilState:
	sType u32 = 25
	next i64 = 0
	flags u32 = 0
	test u32 = 0
	write u32 = 0
	compare u32 = 0
	bounds u32 = 0
	stencil u32 = 0
	front StencilOpState
	back StencilOpState
	minBounds f32 = 0.0
	maxBounds f32 = 1.0

pub extern type BlendAttachment:
	blend u32
	srcColor u32
	dstColor u32
	colorOp u32 = 0
	srcAlpha u32
	dstAlpha u32
	alphaOp u32 = 0
	writeMask u32 = 15

pub extern type ColorBlendState:
	sType u32 = 26
	next i64 = 0
	flags u32 = 0
	logicOpEnable u32 = 0
	logicOp u32 = 0
	attachmentCount u32
	attachments ref BlendAttachment[]
	constants f32[4]

pub extern type DynamicState:
	sType u32 = 27
	next i64 = 0
	flags u32 = 0
	count u32
	states ref u32[]

pub extern type PipelineRenderingCreateInfo:
	sType u32 = 1_000_044_002
	next i64 = 0
	viewMask u32 = 0
	colorCount u32
	formats ref u32[]
	depthFormat u32
	stencilFormat u32 = 0

pub extern type GraphicsPipelineCreateInfo:
	sType u32 = 28
	next ref PipelineRenderingCreateInfo?
	flags u32 = 0
	stageCount u32
	stages ref ShaderStage[]
	vertexInput ref VertexInputState
	inputAssembly ref InputAssemblyState
	tessellation i64 = 0
	viewport ref ViewportState
	rasterization ref RasterizationState
	multisample ref MultisampleState
	depthStencil ref DepthStencilState
	colorBlend ref ColorBlendState
	dynamic ref DynamicState
	layout i64
	renderPass i64 = 0
	subpass u32 = 0
	basePipeline i64 = 0
	baseIndex i32 = -1

# a compute pipeline: its one stage inline (a VkPipelineShaderStageCreateInfo: its fields laid
# where C lays the nested struct, from the pad on) and its layout
pub extern type ComputePipelineCreateInfo:
	sType u32 = 29
	next i64 = 0
	flags u32 = 0
	pad u32 = 0
	stageType u32 = 18
	stageNext i64 = 0
	stageFlags u32 = 0
	stage u32 = 0x20   # COMPUTE
	module i64
	name ref str
	specialization i64 = 0
	layout i64
	basePipeline i64 = 0
	baseIndex i32 = -1

pub extern type CommandPoolCreateInfo:
	sType u32 = 39
	next i64 = 0
	flags u32
	family u32

pub extern type CommandBufferAllocateInfo:
	sType u32 = 40
	next i64 = 0
	pool i64
	level u32 = 0
	count u32 = 1

pub extern type CommandBufferBeginInfo:
	sType u32 = 42
	next i64 = 0
	flags u32
	inheritance i64 = 0

pub extern type FenceCreateInfo:
	sType u32 = 8
	next i64 = 0
	flags u32

pub extern type SemaphoreCreateInfo:
	sType u32 = 9
	next i64 = 0
	flags u32 = 0

pub extern type SubmitInfo:
	sType u32 = 4
	next i64 = 0
	waitCount u32
	waits ref i64[]
	waitStages ref u32[]
	bufferCount u32
	buffers ref i64[]
	signalCount u32
	signals ref i64[]

pub extern type PresentInfo:
	sType u32 = 1_000_001_001
	next i64 = 0
	waitCount u32
	waits ref i64[]
	swapchainCount u32
	swapchains ref i64[]
	indices ref u32[]
	results i64 = 0

pub extern type Rect2D:
	x i32 = 0
	y i32 = 0
	width u32
	height u32

pub extern type Viewport:
	x f32
	y f32
	width f32
	height f32
	minDepth f32 = 0.0
	maxDepth f32 = 1.0

pub extern type RenderingAttachment:
	sType u32 = 1_000_044_001
	next i64 = 0
	view i64
	layout u32
	resolveMode u32 = 0
	resolveView i64 = 0
	resolveLayout u32 = 0
	loadOp u32
	storeOp u32 = 0
	clear f32[4]   # a color, or the depth first

pub extern type RenderingInfo:
	sType u32 = 1_000_044_000
	next i64 = 0
	flags u32 = 0
	area Rect2D
	layers u32 = 1
	viewMask u32 = 0
	colorCount u32
	colors ref RenderingAttachment[]
	depth ref RenderingAttachment?
	stencil ref RenderingAttachment?

pub extern type MemoryBarrier:
	sType u32 = 46
	next i64 = 0
	srcAccess u32
	dstAccess u32

pub extern type ImageMemoryBarrier:
	sType u32 = 45
	next i64 = 0
	srcAccess u32
	dstAccess u32
	oldLayout u32
	newLayout u32
	srcFamily u32 = 4_294_967_295   # VK_QUEUE_FAMILY_IGNORED
	dstFamily u32 = 4_294_967_295
	image i64
	range ImageSubresourceRange

pub extern type BufferCopy:
	src i64
	dst i64
	size i64

pub extern type ImageSubresourceLayers:
	aspect u32
	level u32
	baseLayer u32
	layers u32

pub extern type Offset3D:
	x i32
	y i32
	z i32

pub extern type Extent3D:
	width u32
	height u32
	depth u32

# a copy from the CPU's memory straight into an image, no staging (Vulkan 1.4's host image copy)
pub extern type MemoryToImageCopy:
	sType u32 = 1_000_270_002
	next i64 = 0
	host ref u8[]
	rowLength u32 = 0
	imageHeight u32 = 0
	layers ImageSubresourceLayers
	imageOffset Offset3D
	extent Extent3D

pub extern type CopyMemoryToImageInfo:
	sType u32 = 1_000_270_005
	next i64 = 0
	flags u32 = 0
	image i64
	layout u32
	regionCount u32 = 1
	regions ref MemoryToImageCopy

# an image's layout changed by the CPU (an image the host copies into)
pub extern type HostImageLayoutTransitionInfo:
	sType u32 = 1_000_270_006
	next i64 = 0
	image i64
	oldLayout u32
	newLayout u32
	range ImageSubresourceRange

# what a format can do, its 64 bits of features (VkFormatProperties3 chained to VkFormatProperties2)
pub extern type FormatProperties3:
	sType u32 = 1_000_360_000
	next i64 = 0
	linearTiling u64 = 0
	optimalTiling u64 = 0
	buffer u64 = 0

pub extern type FormatProperties2:
	sType u32 = 1_000_059_002
	next ref FormatProperties3?
	linearTiling u32 = 0
	optimalTiling u32 = 0
	buffer u32 = 0

# whether an image the host copies into is as fast for the GPU as one it does not
pub extern type HostImageCopyPerformance:
	sType u32 = 1_000_270_009
	next i64 = 0
	optimalDeviceAccess u32 = 0
	identicalMemoryLayout u32 = 0

pub extern type ImageFormatInfo2:
	sType u32 = 1_000_059_004
	next i64 = 0
	format u32
	imageType u32 = 1
	tiling u32 = 0
	usage u32
	flags u32 = 0

pub extern type ImageFormatProperties2:
	sType u32 = 1_000_059_003
	next ref HostImageCopyPerformance?
	maxExtent u32[3]
	maxMipLevels u32 = 0
	maxArrayLayers u32 = 0
	sampleCounts u32 = 0
	maxResourceSize i64 = 0

pub extern type BufferImageCopy:
	offset i64
	rowLength u32 = 0
	imageHeight u32 = 0
	layers ImageSubresourceLayers
	imageOffset Offset3D
	extent Extent3D

pub extern type ImageBlit:
	src ImageSubresourceLayers
	srcOffsets Offset3D[2]
	dst ImageSubresourceLayers
	dstOffsets Offset3D[2]

pub extern type ImageResolve:
	src ImageSubresourceLayers
	srcOffset Offset3D
	dst ImageSubresourceLayers
	dstOffset Offset3D
	extent Extent3D

pub extern type ClearAttachment:
	aspect u32
	attachment u32
	value f32[4]

pub extern type ClearRect:
	rect Rect2D
	baseLayer u32 = 0
	layers u32 = 1

pub extern type DescriptorImageInfo:
	sampler i64
	view i64
	layout u32

pub extern type DescriptorBufferInfo:
	buffer i64
	offset i64
	range i64

pub extern type WriteDescriptorSet:
	sType u32 = 35
	next i64 = 0
	set i64 = 0
	binding u32
	element u32 = 0
	count u32 = 1
	kind u32
	image ref DescriptorImageInfo?
	buffer ref DescriptorBufferInfo?
	texelView i64 = 0

# ---------- texture arrays' tables (descriptor indexing) ----------

# per binding of a set layout: its flags (update after bind 1, partially bound 4, variable count 8)
pub extern type DescriptorSetLayoutBindingFlags:
	sType u32 = 1_000_161_000
	next i64 = 0
	count u32
	flags ref u32[]

pub extern type DescriptorPoolSize:
	kind u32
	count u32

pub extern type DescriptorPoolCreateInfo:
	sType u32 = 33
	next i64 = 0
	flags u32
	maxSets u32
	sizeCount u32
	sizes ref DescriptorPoolSize[]

# the descriptors a set's variable binding (its last) is allocated with
pub extern type VariableCountAllocateInfo:
	sType u32 = 1_000_161_003
	next i64 = 0
	count u32 = 1
	counts ref u32[]

pub extern type DescriptorSetAllocateInfo:
	sType u32 = 34
	next ref VariableCountAllocateInfo?
	pool i64
	count u32 = 1
	layouts ref i64[]

# a write of several images (a run of an array's elements)
pub extern type WriteDescriptorImages:
	sType u32 = 35
	next i64 = 0
	set i64
	binding u32
	element u32
	count u32
	kind u32
	images ref DescriptorImageInfo[]
	buffer i64 = 0
	texelView i64 = 0

# the limits of descriptor indexing (asked with vkGetPhysicalDeviceProperties2)
pub extern type DescriptorIndexingProperties:
	sType u32 = 1_000_161_002
	next i64 = 0
	maxUpdateAfterBindDescriptorsInAllPools u32 = 0
	uniformBufferNonUniformNative u32 = 0
	sampledImageNonUniformNative u32 = 0
	storageBufferNonUniformNative u32 = 0
	storageImageNonUniformNative u32 = 0
	inputAttachmentNonUniformNative u32 = 0
	robustBufferAccessUpdateAfterBind u32 = 0
	quadDivergentImplicitLod u32 = 0
	maxPerStageSamplers u32 = 0
	maxPerStageUniformBuffers u32 = 0
	maxPerStageStorageBuffers u32 = 0
	maxPerStageSampledImages u32 = 0
	maxPerStageStorageImages u32 = 0
	maxPerStageInputAttachments u32 = 0
	maxPerStageResources u32 = 0
	maxSetSamplers u32 = 0
	maxSetUniformBuffers u32 = 0
	maxSetUniformBuffersDynamic u32 = 0
	maxSetStorageBuffers u32 = 0
	maxSetStorageBuffersDynamic u32 = 0
	maxSetSampledImages u32 = 0
	maxSetStorageImages u32 = 0
	maxSetInputAttachments u32 = 0

pub extern type Properties2:
	sType u32 = 1_000_059_001
	next ref DescriptorIndexingProperties
	properties DeviceProperties
