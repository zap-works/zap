# The 32-byte texture image control (TIC) and 32-byte texture sampler control (TSC) entries of the
# GPU's pools, read as plain values. The fields and their bits are Ryujinx's (Ryujinx.Graphics.Gpu/
# Image: TextureDescriptor.cs, SamplerDescriptor.cs), checked against yuzu's TICEntry and TSCEntry.

pub entryBytes = 32

# the layouts a TIC says its image has (bits 21-23 of word 2)
pub layoutBuffer = 0
pub layoutLinear = 2
pub layoutBlockLinear = 3

# the targets a TIC says (bits 23-26 of word 4)
pub target1d = 0
pub target2d = 1
pub target3d = 2
pub targetCube = 3
pub target1dArray = 4
pub target2dArray = 5
pub target1dBuffer = 6
pub target2dNoMipmap = 7
pub targetCubeArray = 8

anisotropies = [1, 2, 4, 6, 8, 10, 12, 16]

# A texture: the format (7 bits) and each component's type (3 bits), where each of R, G, B, A reads
# from (0 zero, 2 to 5 the texel's R to A, 6 the integer one, 7 the float one), the image's address
# and layout, its pitch (linear) or its block's size in GOBs as log2 (block linear), its size, the
# levels it has and the range sampled.
pub type Tic:
	format i64
	componentTypes i64[]
	swizzle i64[]
	address i64
	layout i64
	pitch i64
	blockWidth i64
	blockHeight i64
	blockDepth i64
	width i64
	height i64
	depth i64
	levels i64
	baseLevel i64
	maxLevel i64
	target i64
	srgb bool
	normalizedCoordinates bool

	fn isBlockLinear():
		layout >= layoutBlockLinear

pub fn decodeTic(entry u8[]) Tic:
	w0 = i64(entry.u32le(0))
	w1 = i64(entry.u32le(4))
	w2 = i64(entry.u32le(8))
	w3 = i64(entry.u32le(12))
	w4 = i64(entry.u32le(16))
	w5 = i64(entry.u32le(20))
	w7 = i64(entry.u32le(28))
	Tic(
		format = w0 & 0x7F,
		componentTypes = (0..4).map((w0 >> (7 + it * 3)) & 7),
		swizzle = (0..4).map((w0 >> (19 + it * 3)) & 7),
		address = w1 | (w2 & 0xFFFF) << 32,
		layout = (w2 >> 21) & 7,
		pitch = (w3 & 0xFFFF) << 5,
		blockWidth = w3 & 7,
		blockHeight = (w3 >> 3) & 7,
		blockDepth = (w3 >> 6) & 7,
		width = (w4 & 0xFFFF) + 1,
		height = (w5 & 0xFFFF) + 1,
		depth = ((w5 >> 16) & 0x3FFF) + 1,
		levels = (w3 >> 28) + 1,
		baseLevel = w7 & 0xF,
		maxLevel = (w7 >> 4) & 0xF,
		target = (w4 >> 23) & 0xF,
		srgb = (w4 >> 22) & 1 == 1,
		normalizedCoordinates = (w5 >> 31) & 1 == 1
	)

# A sampler: the wrap of each axis (0 repeat, 1 mirrored repeat, 2 clamp to edge, 3 clamp to
# border, 4 clamp, 5 to 7 the mirror clamps), the depth compare (its function 0 never to 7 always),
# the filters (mag and min: 1 nearest, 2 linear; mip: 1 none, 2 nearest, 3 linear), the anisotropy,
# the level of detail's bias and range, and the border color.
pub type Tsc:
	wrapU i64
	wrapV i64
	wrapW i64
	compareEnabled bool
	compareFunction i64
	maxAnisotropy i64
	magFilter i64
	minFilter i64
	mipFilter i64
	seamlessCube bool
	lodBias f32
	minLod f32
	maxLod f32
	borderColor f32[]

pub fn decodeTsc(entry u8[]) Tsc:
	w0 = i64(entry.u32le(0))
	w1 = i64(entry.u32le(4))
	w2 = i64(entry.u32le(8))
	bias = (w1 >> 12) & 0x1FFF
	Tsc(
		wrapU = w0 & 7,
		wrapV = (w0 >> 3) & 7,
		wrapW = (w0 >> 6) & 7,
		compareEnabled = (w0 >> 9) & 1 == 1,
		compareFunction = (w0 >> 10) & 7,
		maxAnisotropy = anisotropies[(w0 >> 20) & 7],
		magFilter = w1 & 3,
		minFilter = (w1 >> 4) & 3,
		mipFilter = (w1 >> 6) & 3,
		seamlessCube = (w1 >> 9) & 1 == 1,
		lodBias = f32(bias - (bias & 0x1000) * 2) / 256.0,
		minLod = f32(w2 & 0xFFF) / 256.0,
		maxLod = f32((w2 >> 12) & 0xFFF) / 256.0,
		borderColor = (0..4).map(f32.fromBits(entry.u32le(16 + it * 4)))
	)
