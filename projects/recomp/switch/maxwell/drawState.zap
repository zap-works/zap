# What a renderer needs at a draw, as plain values decoded from the 3D engine's registers
# (draw.zap). Register offsets, here in words, are Ryujinx's (Ryujinx.Graphics.Gpu/Engine/Threed:
# ThreedClassState.cs, DrawManager.cs, IbStreamer.cs), checked against yuzu's maxwell_3d.h.

# the draw's registers
reg3dFirstVertex = 0x50D   # then the first instance
reg3dShaderBase = 0x582   # the address programs' offsets are from (high, low)
reg3dDrawBegin = 0x586
reg3dVertexArrayFirst = 0x35D   # the vertex array draw's first vertex and count
reg3dDepthMode = 0x35F
reg3dIndexBuffer = 0x5F2   # address high, low, end high, low, format, first, count
reg3dIndexBufferCount = 0x5F8
reg3dVertexArrayBeginEnd = 0x485   # first instance, then subsequent instances: one word each
reg3dIndexBeginEnd = 0x5F9   # 32, 16, 8 bit first instance, then the same subsequent
reg3dInlineIndexU8 = 0x4C1
reg3dInlineIndexU32 = 0x57A
reg3dInlineIndexU16 = 0x57C

# vertex fetch: 32 attributes of a word, 16 streams of 4 (control, address high, low, divisor)
# and their end addresses, then which streams advance by instance
reg3dVertexAttributes = 0x458
reg3dVertexStreams = 0x700
reg3dVertexStreamEnds = 0x7C0
reg3dVertexStreamInstanced = 0x620
attributeCount = 32
streamCount = 16

# programs: six stages of 16 words (control with the enable in bit 0, offset from the base), the
# constant buffer window (size, address high, low, offset) and the stages' bind registers 8 apart
reg3dPrograms = 0x800
programWords = 16
programStages = 6
reg3dConstantWindow = 0x8E0
reg3dConstantBind = 0x904
reg3dTextureBufferIndex = 0x982
constantStages = 5
constantSlots = 18

# the pools: samplers then textures, each address high, low and the highest index
reg3dSamplerPool = 0x557
reg3dTexturePool = 0x55D

# targets: the color targets are at reg3dRenderTargets (clear.zap); the control word, the zeta
# target (address high, low, format, layout, layer size), its size and enable
reg3dRtControl = 0x487
reg3dZeta = 0x3F8
reg3dZetaSize = 0x48A
reg3dZetaEnable = 0x54D
renderTargetCount = 8

# viewports: 16 transforms of 8 words (scale, translate, swizzle, precision), 16 extents of 4
# (x and width, y and height, near, far), 16 scissors of 4 (enable, x, y)
reg3dViewportTransforms = 0x280
reg3dViewportExtents = 0x300
reg3dScissors = 0x380
viewportCount = 16

# blend, depth and cull
reg3dBlendIndependent = 0x4B9
reg3dBlendConstant = 0x4C7
reg3dBlendCommon = 0x4CF   # 8 words: separate alpha, color op, src, dst, alpha op, src, (unknown), dst
reg3dBlendEnableCommon = 0x4D7   # then one enable a target
reg3dBlendTargets = 0x780   # 8 of 8 words: separate alpha, color op, src, dst, alpha op, src, dst
reg3dDepthTestEnable = 0x4B3
reg3dDepthWriteEnable = 0x4BA
reg3dDepthTestFunction = 0x4C3
reg3dYControl = 0x4EB
reg3dCull = 0x646   # enable, front face, cull face
reg3dClipControl = 0x64F

# a draw's inline indices are kept up to this many
maxInlineIndices = 0x1_0000

# One vertex attribute: where it reads from (a stream or, when constant, the constant color), at
# what offset, and its size (the hardware's size code) and numeric type code.
pub type VertexAttribute:
	index i64
	stream i64
	offset i64
	size i64
	kind i64
	constant bool
	bgra bool

pub type VertexStream:
	index i64
	address i64
	limit i64
	stride i64
	divisor i64
	enabled bool
	instanced bool

# an enabled stage: its slot (VertexA, VertexB, tessellation control and evaluation, geometry,
# pixel), the stage kind (0 vertex to 4 pixel) and the program's GPU address
pub type StageProgram:
	slot i64
	kind i64
	address i64

pub type BoundConstantBuffer:
	kind i64   # the stage kind
	slot i64
	address i64
	size i64

pub type IndexBuffer:
	address i64
	end i64
	format i64   # 0 bytes, 1 shorts, 2 words

pub type Pool:
	address i64
	highest i64

pub type ZetaBuffer:
	enabled bool
	address i64
	format i64
	layout i64
	layerSize i64
	width i64
	height i64
	depth i64

# a viewport: the transform to the target and the extent the clip is in
pub type Viewport:
	scale Vec3
	translate Vec3
	swizzle i64
	x i64
	y i64
	width i64
	height i64
	near f32
	far f32

pub type Scissor:
	enabled bool
	x1 i64
	x2 i64
	y1 i64
	y2 i64

# the blend of one color target: operations and factors are the hardware's codes
pub type Blend:
	enabled bool
	separateAlpha bool
	colorOp i64
	colorSource i64
	colorDestination i64
	alphaOp i64
	alphaSource i64
	alphaDestination i64

pub type DepthState:
	testEnabled bool
	writeEnabled bool
	function i64

pub type CullState:
	enabled bool
	frontFace i64
	face i64

# One draw: what to draw (indexed or not, the first vertex or index and the count, instances and
# inline indices), the vertex fetch, the programs, the constant buffers bound, the pools, the
# targets and the fixed-function state.
pub type DrawCall:
	topology i64
	indexed bool
	first i64
	count i64
	baseVertex i64
	firstInstance i64
	instances i64 = 1
	index IndexBuffer
	inlineIndices i64[]
	attributes VertexAttribute[]
	streams VertexStream[]
	programs StageProgram[]
	constantBuffers BoundConstantBuffer[]
	samplerPool Pool
	texturePool Pool
	textureBufferSlot i64
	targets RenderTarget[]
	targetCount i64
	targetMap i64[]
	zeta ZetaBuffer
	viewports Viewport[]
	scissors Scissor[]
	blend Blend[]
	blendConstant Vec4
	depth DepthState
	cull CullState
	depthMode i64
	clipControl i64
	yControl i64
	# kept when a renderer draws the frame later: the programs' names (their hashes, stage order)
	# and the vertex and pixel stages' constants as they were at the draw
	programNames str[] = []
	vertexConstants u32[] = []
	pixelConstants u32[] = []
