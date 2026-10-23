# The 3D engine's registers read into a DrawCall (drawstate.zap): the decoders are plain functions
# of the register array, and `drawOf` gathers them at a draw's end.

# the stage kind (0 vertex to 4 pixel) of each program slot
slotKinds = [0, 0, 1, 2, 3, 4]

# a 40-bit GPU address held in two registers, high word first
fn addressAt(regs i64[], at i64):
	(regs[at] & 0xFF) << 32 | regs[at + 1]

fn floatAt(regs i64[], at i64):
	f32.fromBits(u32(regs[at]))

fn flagAt(regs i64[], at i64):
	regs[at] & 1 != 0

# the attributes that read something: bits 0-4 the stream, 6 constant, 7-20 the offset, 21-26 the
# size code, 27-29 the type code, 31 BGRA order
fn decodeAttributes(regs i64[]):
	out = []
	for i in 0..attributeCount:
		w = regs[reg3dVertexAttributes + i]
		if (w >> 21) & 0x3F == 0: continue
		out.push(
			VertexAttribute(
				index = i,
				stream = w & 0x1F,
				constant = (w >> 6) & 1 == 1,
				offset = (w >> 7) & 0x3FFF,
				size = (w >> 21) & 0x3F,
				kind = (w >> 27) & 7,
				bgra = (w >> 31) & 1 == 1
			)
		)
	out

# a stream: control bits 0-11 the stride and 12 enabled, then its address and divisor
fn decodeStreams(regs i64[]):
	out = []
	for i in 0..streamCount:
		r = reg3dVertexStreams + i * 4
		out.push(
			VertexStream(
				index = i,
				address = addressAt(regs, r + 1),
				limit = addressAt(regs, reg3dVertexStreamEnds + i * 2),
				stride = regs[r] & 0xFFF,
				divisor = regs[r + 3],
				enabled = (regs[r] >> 12) & 1 == 1,
				instanced = flagAt(regs, reg3dVertexStreamInstanced + i)
			)
		)
	out

fn decodePrograms(regs i64[]):
	out = []
	base = addressAt(regs, reg3dShaderBase)
	for slot in 0..programStages:
		r = reg3dPrograms + slot * programWords
		if flagAt(regs, r):
			out.push(StageProgram(slot, kind = slotKinds[slot], address = base + regs[r + 1]))
	out

# the buffers bound: `bound` holds enable, address and size for each stage's slots
fn decodeConstantBuffers(bound i64[]):
	out = []
	for kind in 0..constantStages:
		for slot in 0..constantSlots:
			at = (kind * constantSlots + slot) * 3
			if bound[at] != 0:
				out.push(
					BoundConstantBuffer(kind, slot, address = bound[at + 1], size = bound[at + 2])
				)
	out

fn decodePool(regs i64[], at i64):
	Pool(address = addressAt(regs, at), highest = regs[at + 2])

fn decodeZeta(regs i64[]):
	ZetaBuffer(
		enabled = flagAt(regs, reg3dZetaEnable),
		address = addressAt(regs, reg3dZeta),
		format = regs[reg3dZeta + 2],
		layout = regs[reg3dZeta + 3],
		layerSize = regs[reg3dZeta + 4],
		width = regs[reg3dZetaSize],
		height = regs[reg3dZetaSize + 1],
		depth = regs[reg3dZetaSize + 2]
	)

fn decodeViewports(regs i64[]):
	out = []
	for i in 0..viewportCount:
		t = reg3dViewportTransforms + i * 8
		e = reg3dViewportExtents + i * 4
		out.push(
			Viewport(
				scale = Vec3(floatAt(regs, t), floatAt(regs, t + 1), floatAt(regs, t + 2)),
				translate = Vec3(floatAt(regs, t + 3), floatAt(regs, t + 4), floatAt(regs, t + 5)),
				swizzle = regs[t + 6],
				x = regs[e] & 0xFFFF,
				width = (regs[e] >> 16) & 0xFFFF,
				y = regs[e + 1] & 0xFFFF,
				height = (regs[e + 1] >> 16) & 0xFFFF,
				near = floatAt(regs, e + 2),
				far = floatAt(regs, e + 3)
			)
		)
	out

fn decodeScissors(regs i64[]):
	out = []
	for i in 0..viewportCount:
		r = reg3dScissors + i * 4
		out.push(
			Scissor(
				enabled = flagAt(regs, r),
				x1 = regs[r + 1] & 0xFFFF,
				x2 = (regs[r + 1] >> 16) & 0xFFFF,
				y1 = regs[r + 2] & 0xFFFF,
				y2 = (regs[r + 2] >> 16) & 0xFFFF
			)
		)
	out

# The blend of each color target: one set of registers for all, or a set each when independent.
fn decodeBlend(regs i64[]):
	independent = flagAt(regs, reg3dBlendIndependent)
	out = []
	for i in 0..renderTargetCount:
		r = reg3dBlendTargets + i * 8 if independent else reg3dBlendCommon
		enable = reg3dBlendEnableCommon + 1 + i if independent else reg3dBlendEnableCommon
		# the common set has an unknown word before the alpha destination
		alphaDestination = regs[r + 6] if independent else regs[r + 7]
		out.push(
			Blend(
				enabled = flagAt(regs, enable),
				separateAlpha = flagAt(regs, r),
				colorOp = regs[r + 1],
				colorSource = regs[r + 2],
				colorDestination = regs[r + 3],
				alphaOp = regs[r + 4],
				alphaSource = regs[r + 5],
				alphaDestination
			)
		)
	out

# The draw as the engine's registers, constant buffer bindings and inline indices stand now.
pub fn drawOf(e Engine, topology i64, indexed bool, first i64, count i64) DrawCall:
	regs = e.regs
	rtControl = regs[reg3dRtControl]
	DrawCall(
		topology,
		indexed,
		first,
		count,
		baseVertex = regs[reg3dFirstVertex],
		firstInstance = regs[reg3dFirstVertex + 1],
		index = IndexBuffer(
			address = addressAt(regs, reg3dIndexBuffer),
			end = addressAt(regs, reg3dIndexBuffer + 2),
			format = regs[reg3dIndexBuffer + 4]
		),
		inlineIndices = e.inlineIndices.copy(),
		attributes = decodeAttributes(regs),
		streams = decodeStreams(regs),
		programs = decodePrograms(regs),
		constantBuffers = decodeConstantBuffers(e.bound),
		samplerPool = decodePool(regs, reg3dSamplerPool),
		texturePool = decodePool(regs, reg3dTexturePool),
		textureBufferSlot = regs[reg3dTextureBufferIndex],
		targets = (0..renderTargetCount).map(renderTarget(regs, it)),
		targetCount = rtControl & 0xF,
		targetMap = (0..renderTargetCount).map((rtControl >> (4 + it * 3)) & 7),
		zeta = decodeZeta(regs),
		viewports = decodeViewports(regs),
		scissors = decodeScissors(regs),
		blend = decodeBlend(regs),
		blendConstant = Vec4(
			floatAt(regs, reg3dBlendConstant),
			floatAt(regs, reg3dBlendConstant + 1),
			floatAt(regs, reg3dBlendConstant + 2),
			floatAt(regs, reg3dBlendConstant + 3)
		),
		depth = DepthState(
			testEnabled = flagAt(regs, reg3dDepthTestEnable),
			writeEnabled = flagAt(regs, reg3dDepthWriteEnable),
			function = regs[reg3dDepthTestFunction]
		),
		cull = CullState(
			enabled = flagAt(regs, reg3dCull),
			frontFace = regs[reg3dCull + 1],
			face = regs[reg3dCull + 2]
		),
		depthMode = regs[reg3dDepthMode],
		clipControl = regs[reg3dClipControl],
		yControl = regs[reg3dYControl]
	)
