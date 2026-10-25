# The Direct3D 12 and DXGI structures the backend passes, declared as C has them (extern types,
# laid out by the compiler). A union is written as the one member the backend uses, or as plain
# words where it uses several; a pointer the backend never sets is an i64 left 0.

pub extern type AdapterDesc1:
	description u8[256]   # 128 UTF-16 characters
	vendor u32 = 0
	device u32 = 0
	subsystem u32 = 0
	revision u32 = 0
	videoMemory i64 = 0
	systemMemory i64 = 0
	sharedMemory i64 = 0
	luid i64 = 0
	flags u32 = 0   # 2: a software adapter

pub extern type SwapChainDesc1:
	width u32
	height u32
	format u32
	stereo u32 = 0
	sampleCount u32 = 1
	sampleQuality u32 = 0
	usage u32 = 0x20   # DXGI_USAGE_RENDER_TARGET_OUTPUT
	bufferCount u32
	scaling u32 = 0   # DXGI_SCALING_STRETCH
	swapEffect u32 = 4   # DXGI_SWAP_EFFECT_FLIP_DISCARD
	alphaMode u32 = 0
	flags u32

pub extern type CommandQueueDesc:
	kind u32 = 0   # DIRECT
	priority i32 = 0
	flags u32 = 0
	nodeMask u32 = 0

pub extern type DescriptorHeapDesc:
	kind u32
	count u32
	flags u32
	nodeMask u32 = 0

pub extern type HeapProperties:
	kind u32   # 1 default, 2 upload, 3 readback
	cpuPage u32 = 0
	pool u32 = 0
	creationNode u32 = 0
	visibleNode u32 = 0

pub extern type HeapDesc:
	size i64
	properties HeapProperties
	alignment i64 = 0
	flags u32

pub extern type ResourceDesc:
	dimension u32   # 1 a buffer, 3 a 2D texture
	alignment i64 = 0
	width i64
	height u32
	depthOrArraySize u16
	mipLevels u16
	format u32
	sampleCount u32 = 1
	sampleQuality u32 = 0
	layout u32 = 0   # 1 row major (a buffer's)
	flags u32 = 0

pub extern type ClearValue:
	format u32
	values f32[4]   # a color, or the depth first

pub extern type AllocationInfo:
	size i64 = 0
	alignment i64 = 0

# a transition barrier: the resource's subresources (all) from one state to another
pub extern type ResourceBarrier:
	kind u32 = 0
	flags u32 = 0
	resource i64
	subresource u32 = 0xFFFF_FFFF
	before u32
	after u32
	pad u32 = 0

pub extern type Viewport:
	x f32
	y f32
	width f32
	height f32
	minDepth f32 = 0.0
	maxDepth f32 = 1.0

pub extern type Rect:
	left i32 = 0
	top i32 = 0
	right i32
	bottom i32

pub extern type VertexBufferView:
	location i64
	size u32
	stride u32

pub extern type IndexBufferView:
	location i64
	size u32
	format u32

# where a copy reads or writes: a subresource of a texture (kind 0, its index in `offset`), or a
# footprint of rows in a buffer (kind 1)
pub extern type TextureCopyLocation:
	resource i64
	kind u32
	pad u32 = 0
	offset i64
	format u32 = 0
	width u32 = 0
	height u32 = 0
	depth u32 = 1
	rowPitch u32 = 0
	pad2 u32 = 0

# a texture's view: 2D (a, b: the first level, the levels), an array (a, b, c, d: the first
# level, the levels, the first layer, the layers), multisampled (none)
pub extern type ShaderResourceViewDesc:
	format u32
	dimension u32
	mapping u32 = 0x1688   # the identity
	pad u32 = 0
	a u32 = 0
	b u32 = 0
	c u32 = 0
	d u32 = 0
	e u32 = 0
	f u32 = 0

# a texture's unordered access view: 2D (dimension 4; a, b: the level, the plane), the union
# taking 32 bytes
pub extern type UnorderedAccessViewDesc:
	format u32
	dimension u32 = 4
	a u32 = 0
	b u32 = 0
	rest u32[6] = zeros(6)

# a render target view of one level of a texture's layers (dimension 5: TEXTURE2DARRAY; the union
# takes 16 bytes)
pub extern type RenderTargetViewDesc:
	format u32
	dimension u32 = 5
	mip u32 = 0
	firstLayer u32 = 0
	layers u32 = 1
	plane u32 = 0

# a heap of timestamps (D3D12_QUERY_HEAP_TYPE_TIMESTAMP)
pub extern type QueryHeapDesc:
	kind u32 = 1
	count u32
	nodeMask u32 = 0

# an argument of an indirect command: its kind (0 DRAW, 1 DRAW_INDEXED), the union unused
pub extern type IndirectArgument:
	kind u32
	a u32 = 0
	b u32 = 0
	c u32 = 0

pub extern type CommandSignatureDesc:
	stride u32
	count u32 = 1
	arguments ref IndirectArgument[]
	nodeMask u32 = 0

pub extern type DepthStencilViewDesc:
	format u32
	dimension u32   # 3 a 2D texture, 5 multisampled
	flags u32 = 0
	mip u32 = 0
	a u32 = 0
	b u32 = 0

pub extern type SamplerDescription:
	filter u32
	addressU u32
	addressV u32
	addressW u32
	lodBias f32 = 0.0
	maxAnisotropy u32
	compare u32
	border f32[4]
	minLod f32 = 0.0
	maxLod f32

pub extern type DescriptorRange:
	kind u32   # 0 SRV, 3 a sampler
	count u32 = 1
	base u32
	space u32 = 0
	offset u32

# a root parameter: a table (a = its ranges' count, ranges), or a root CBV, SRV or UAV (a = its
# register); visible to every stage
pub extern type RootParameter:
	kind u32
	pad u32 = 0
	a u32
	b u32 = 0
	ranges ref DescriptorRange[]
	visibility u32 = 0

pub extern type RootSignatureDesc:
	count u32
	parameters ref RootParameter[]
	staticCount u32 = 0
	statics i64 = 0
	flags u32 = 1   # ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT

pub extern type InputElement:
	semantic ref str
	index u32
	format u32
	slot u32
	offset u32
	slotClass u32
	stepRate u32

pub extern type BlendTarget:
	enable u32 = 0
	logicEnable u32 = 0
	src u32 = 2
	dst u32 = 1
	op u32 = 1
	srcAlpha u32 = 2
	dstAlpha u32 = 1
	opAlpha u32 = 1
	logicOp u32 = 0
	writeMask u8 = 15
	pad u8[3] = [u8(0), u8(0), u8(0)]

# a compute pipeline state: its root signature and its stage's bytecode
pub extern type ComputePipelineDesc:
	rootSignature i64
	cs ref str
	csSize i64
	nodeMask u32 = 0
	cachedBlob i64 = 0
	cachedSize i64 = 0
	flags u32 = 0

pub extern type GraphicsPipelineDesc:
	rootSignature i64
	vs ref str
	vsSize i64
	ps ref str
	psSize i64
	ds i64 = 0
	dsSize i64 = 0
	hs i64 = 0
	hsSize i64 = 0
	gs i64 = 0
	gsSize i64 = 0
	streamOutput i64[4] = [0, 0, 0, 0]
	alphaToCoverage u32
	independentBlend u32 = 0
	targets BlendTarget[8]
	sampleMask u32 = 0xFFFF_FFFF
	fill u32 = 3   # SOLID
	cull u32   # 1 none, 3 back
	frontCounterClockwise u32
	depthBias i32
	depthBiasClamp f32 = 0.0
	slopeScaledDepthBias f32
	depthClip u32 = 1
	multisample u32
	antialiasedLines u32 = 0
	forcedSamples u32 = 0
	conservative u32 = 0
	depthEnable u32
	depthWrite u32
	depthFunc u32 = 2   # LESS
	stencilEnable u32 = 0
	stencilRead u8 = 255
	stencilWrite u8 = 255
	stencilPad u8[2] = [u8(0), u8(0)]
	frontStencil u32[4] = [u32(1), 1, 1, 8]   # keep, keep, keep, always
	backStencil u32[4] = [u32(1), 1, 1, 8]
	inputs ref InputElement[]
	inputCount u32
	inputPad u32 = 0
	stripCut u32 = 0
	topologyType u32   # 2 lines, 3 triangles
	targetCount u32
	targetFormats u32[8]
	depthFormat u32
	sampleCount u32
	sampleQuality u32 = 0
	nodeMask u32 = 0
	cachedBlob i64 = 0
	cachedSize i64 = 0
	flags u32 = 0
