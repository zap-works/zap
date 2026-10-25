# What the engine says to the GPU through the RHI, the same for every backend: the targets of a
# pass, a draw and its state, the vertex layouts, textures and samplers as they are asked for,
# and the formats and usages (numbered as Vulkan numbers them; a backend maps them to its own).

pub backendVulkan = 0
pub backendD3d12 = 1

pub screenTarget = -1   # the swapchain's image
pub noTarget = -2   # a pass without color, or without depth

# a draw: its program and how its pipeline is made, its vertices, what it reads, its counts
# (the lists are the caller's, lent for the draw)
pub type DrawCall:
	program i64
	layout i64   # a vertex layout made by vertexLayout, -1 none (vertices made from their number)
	state PipelineState
	vertexBuffers ref i64[]   # per layout binding: a buffer handle...
	vertexOffsets ref i64[]   # ...and the offset in it
	indexBuffer i64   # a buffer handle (u32 indices), 0 none
	count i64   # vertices, or indices
	instances i64
	textures ref i64[]   # per sampler binding of the program (by binding number): a texture id, -1 none
	storage ref i64[]   # per storage binding (the shader's binding, before bufferBase): a buffer id, -1 none
	cull bool
	depthTest bool
	depthWrite bool
	depthBias bool   # pushed back by its slope (a shadow map's)
	decal bool = false   # pulled forward onto the surface it lies on (a decal)
	raster RasterState = RasterState()
	paramsCopy i64 = -1   # the program's parameters as copyParams copied them this frame, -1: as they are now
	# where it starts: its first index (or vertex), the offset added to each index, its first
	# instance (where the instance stream is read from)
	first i64 = 0
	vertexOffset i64 = 0
	firstInstance i64 = 0
	# Or the draws are read by the GPU from a buffer (an id) of commands from `indirectOffset`
	# (indexCommandBytes each for an indexed draw, else drawCommandBytes), `drawCount` of them, or
	# as many as the u32 at `countOffset` of buffer `countBuffer` says, up to drawCount (count and
	# instances unread)
	indirect i64 = -1
	indirectOffset i64 = 0
	drawCount i64 = 1
	countBuffer i64 = -1
	countOffset i64 = 0

# a compute stage run: its program, its groups along x, y and z, what it reads and writes (the
# lists are the caller's, lent for the run, as a draw's)
pub type ComputeCall:
	program i64
	x i64
	y i64
	z i64
	textures ref i64[]   # per sampler binding of the program: a texture id, -1 none
	storage ref i64[]   # per storage binding (the shader's binding, before bufferBase): a buffer id

# the bytes of a command of an indirect draw, as Vulkan and Direct3D 12 both lay it out: an
# indexed one (indices, instances, first index, vertex offset, first instance; u32 but the i32
# offset), one of vertices (vertices, instances, first vertex, first instance)
pub indexCommandBytes = 20
pub drawCommandBytes = 16   # a non-indexed draw

pub blendNone = 0
pub blendAlpha = 1   # src * a + dst * (1 - a)
pub blendAdd = 2   # src + dst
pub blendPremultiplied = 3   # src + dst * (1 - a)

# How a color target mixes what a draw writes with what it holds: factors and operations
# numbered as Vulkan's (factors ZERO 0, ONE 1, SRC_COLOR 2, ONE_MINUS_SRC_COLOR 3, DST_COLOR 4,
# ONE_MINUS_DST_COLOR 5, SRC_ALPHA 6, ONE_MINUS_SRC_ALPHA 7, DST_ALPHA 8, ONE_MINUS_DST_ALPHA 9,
# SRC_ALPHA_SATURATE 14; operations ADD 0, SUBTRACT 1, REVERSE_SUBTRACT 2, MIN 3, MAX 4), and the
# channels written (r 1, g 2, b 4, a 8).
pub type TargetBlend:
	on bool = false
	srcColor i64 = 1
	dstColor i64 = 0
	colorOp i64 = 0
	srcAlpha i64 = 1
	dstAlpha i64 = 0
	alphaOp i64 = 0
	writeMask i64 = 15

# the blending of one of the modes (blendNone and the others)
pub fn presetBlend(mode i64) TargetBlend:
	if mode == blendNone: return TargetBlend()
	src, dst = (6, 7) if mode == blendAlpha else (1, 1) if mode == blendAdd else (1, 7)
	TargetBlend(on = true, srcColor = src, dstColor = dst, srcAlpha = src, dstAlpha = dst)

# depth comparisons, numbered as Vulkan's (Direct3D 12's are one more)
pub compareNever = 0
pub compareLess = 1
pub compareEqual = 2
pub compareLessOrEqual = 3
pub compareGreater = 4
pub compareNotEqual = 5
pub compareGreaterOrEqual = 6
pub compareAlways = 7

# A rectangle of a target drawn into, in pixels from its top-left corner (the screen's too), and
# the depths it maps clip depths 0..1 to.
pub type Viewport:
	x f32
	y f32
	width f32
	height f32
	near f32 = 0.0
	far f32 = 1.0

# the pixels a draw may write, from the target's top-left corner
pub type Scissor:
	x i64
	y i64
	width i64
	height i64

# What a draw sets of the rasterizer and the depth test besides culling and the depth's test and
# write: the comparison, front faces culled in place of back ones, front faces clockwise in the
# engine's clip space (y up) in place of counter-clockwise, and its viewport and scissor (none:
# the whole target).
pub type RasterState:
	depthCompare i64 = compareLess
	cullFront bool = false
	frontClockwise bool = false
	viewport Viewport? = none
	scissor Scissor? = none

# What a frame's draws cost: the binds and uploads made, and those skipped because the last
# draw's were the same (each backend counts its own: a descriptor set pushed with Vulkan, root
# arguments and tables set with Direct3D 12).
pub type DrawStats:
	draws i64 = 0
	pipelineBinds i64 = 0
	pipelinesSkipped i64 = 0
	vertexBinds i64 = 0
	vertexSkipped i64 = 0
	indexBinds i64 = 0
	indexSkipped i64 = 0
	descriptorBinds i64 = 0
	descriptorsSkipped i64 = 0
	paramUploads i64 = 0
	paramsSkipped i64 = 0
	bytesUploaded i64 = 0   # parameter bytes copied into the frame's ring

# the counts on one line, for a debug print (each pair: made, skipped)
pub fn describeStats(s DrawStats) str:
	"draws {s.draws}, pipelines {s.pipelineBinds}/{s.pipelinesSkipped}, vertices {s.vertexBinds}/{s.vertexSkipped}, indices {s.indexBinds}/{s.indexSkipped}, descriptors {s.descriptorBinds}/{s.descriptorsSkipped}, parameters {s.paramUploads}/{s.paramsSkipped} ({s.bytesUploaded} bytes)"

pub type VertexBinding:
	stride i64
	perInstance bool

pub type VertexAttribute:
	location i64
	binding i64
	format i64
	offset i64

# how vertices are read from buffers: the buffers bound (in order) and the attributes in them
pub type VertexLayout:
	bindings VertexBinding[]
	attributes VertexAttribute[]

# what a draw's pipeline is besides its program and layout
pub type PipelineState:
	blend i64
	alphaToCoverage bool
	lines bool
	blends i64 = -1   # a blend set (blendSet: per color target), -1: every target as `blend`

pub type SamplerDesc:
	smooth bool   # linear filtering up close and far
	mipmaps i64   # 0 none, 1 the nearest level, 2 between levels
	repeat bool   # repeat past the edges (else clamp)
	mirror i64   # repeated mirrored instead: 1 across, 2 down, 3 both
	anisotropy bool
	compare bool   # a depth comparison (a shadow map)

pub fn isSameSampler(a SamplerDesc, b SamplerDesc) bool:
	a.smooth == b.smooth and a.mipmaps == b.mipmaps and a.repeat == b.repeat and
		a.mirror == b.mirror and a.anisotropy == b.anisotropy and a.compare == b.compare

pub type TextureDesc:
	width i64
	height i64
	layers i64   # 1, or an array's layers
	levels i64   # mip levels; 0: down to 1x1
	format i64
	samples i64   # 1, or a multisampled target's
	array bool   # read as an array (a TextureArray; with cube, a TextureCubeArray)
	target bool   # drawn into
	volume bool = false   # a 3D texture, `layers` its depth (read as a Texture3D)
	cube bool = false   # cubes of six layers each, +x -x +y -y +z -z (read as a TextureCube)

# the mip levels a texture has: as asked, or (0) down to 1x1
pub fn levelsOf(desc TextureDesc) i64:
	if desc.levels > 0: return desc.levels
	levels = 1
	while (1 << levels) <= desc.width.max(desc.height):
		levels += 1
	levels

# an object freed once the frame that retired it is done on the GPU
pub type Retired:
	kind i64   # retiredBuffer and the others of device.zap, or the backend's own
	handle i64
	block i64   # its memory (-1 none): the block and the range in it
	offset i64
	size i64

# formats
pub fmtUndefined = 0
pub fmtRgba8 = 37
pub fmtBgra8 = 44   # the screen's
pub fmtR32Uint = 98   # of 1 to 4 components each 3 past the one before (Rg32Uint 101...)
pub fmtR32Sint = 99
pub fmtR32Float = 100
pub fmtRg32Uint = 101
pub fmtRg32Sint = 102
pub fmtRg32Float = 103
pub fmtRgba32Uint = 107
pub fmtRgba32Sint = 108
pub fmtRgba8Uint = 41
pub fmtRgb32Float = 106
pub fmtRgba32Float = 109
pub fmtRgba16Float = 97
pub fmtD16 = 124
pub fmtD32 = 126   # float
pub fmtRgba8Srgb = 43   # 4 bytes a pixel, sRGB-encoded (read as linear)
pub fmtBgra8Srgb = 50
pub fmtR8 = 9
pub fmtRg8 = 16
pub fmtRgb10A2 = 64   # 10 bits each of r, g, b from the lowest, 2 of a
pub fmtRg16Float = 83
pub fmtR11G11B10Float = 122   # unsigned floats: 11 bits each of r and g from the lowest, 10 of b
pub fmtD24S8 = 129   # depth of 24 bits and stencil of 8
pub fmtBc1 = 133   # BC1: blocks of 4x4 pixels in 8 bytes, RGB and a 1-bit alpha
pub fmtBc1Srgb = 134
pub fmtBc3 = 137   # BC3: blocks of 4x4 pixels in 16 bytes, RGBA
pub fmtBc3Srgb = 138
pub fmtBc4 = 139   # BC4: blocks of 4x4 pixels in 8 bytes, one channel
pub fmtBc5 = 141   # BC5: blocks of 4x4 pixels in 16 bytes, two channels (a normal map's x and y)
pub fmtBc7 = 145   # BC7: blocks of 4x4 pixels in 16 bytes, RGBA
pub fmtBc7Srgb = 146

pub fn isDepthFormat(format i64) bool:
	format in [fmtD32, fmtD16, fmtD24S8]

pub fn hasStencil(format i64) bool:
	format == fmtD24S8

# the bytes of a pixel of a format not of blocks
pub fn pixelBytes(format i64) i64:
	if format in [fmtR8]: return 1
	if format in [fmtRg8, fmtD16]: return 2
	if format >= fmtR32Uint and format <= fmtRgba32Float: return (format - fmtR32Uint) / 3 * 4 + 4
	if format in [fmtRgba16Float]: return 8
	4

# whether a format is of compressed blocks of 4x4 pixels
pub fn isBlockFormat(format i64) bool:
	format in [fmtBc1, fmtBc1Srgb, fmtBc3, fmtBc3Srgb, fmtBc4, fmtBc5, fmtBc7, fmtBc7Srgb]

# A w x h level of a texture of the format as its bytes lie, rows from the top: the bytes of a row
# (of pixels, or of blocks of 4x4) and the rows.
pub fn levelRows(format i64, w i64, h i64) (i64, i64):
	if isBlockFormat(format):
		block = 8 if format in [fmtBc1, fmtBc1Srgb, fmtBc4] else 16
		return ((w + 3) / 4 * block, (h + 3) / 4)
	(w * pixelBytes(format), h)

# the bytes of a w x h level of a texture of the format
pub fn levelBytes(format i64, w i64, h i64) i64:
	row, rows = levelRows(format, w, h)
	row * rows

# the format of a vertex input of the component type (the shader's: 2 int, 3 uint, 4 float) and size
pub fn inputFormat(base i64, rows i64) i64:
	if base == 3: return fmtR32Uint + (rows - 1) * 3
	if base == 2: return fmtR32Sint + (rows - 1) * 3
	[fmtR32Float, fmtRg32Float, fmtRgb32Float, fmtRgba32Float][rows - 1]

# buffer usages
pub bufTransferSrc = 1
pub bufTransferDst = 2
pub bufUniform = 0x10
pub bufStorage = 0x20
pub bufIndex = 0x40
pub bufVertex = 0x80
pub bufIndirect = 0x100   # commands of indirect draws, their counts
pub bufWritten = 0x1_0000_0000   # written by a compute stage (a backend may keep it apart; not an API's bit)
