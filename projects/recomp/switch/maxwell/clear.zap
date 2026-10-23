# The 3D engine's clear of a render target (CLEAR_SURFACE): the target's every pixel set to the
# clear color in the target's format. A whole surface is cleared, so its block-linear order does
# not matter: a pixel's bytes stay together in a GOB's 16-byte pieces. Registers and formats are
# yuzu's (maxwell_3d.h, RenderTargetFormat); the scissor, the clear's own rectangle, layers past
# the first and depth or stencil are not done yet.

import recomp.switch.textures

reg3dRenderTargets = 0x200   # eight of 0x10 words: address high, low, width, height, format, tiling
reg3dClearColor = 0x360
reg3dClearSurface = 0x674

renderTargetWords = 0x10
tilingPitchLinear = 0x1000

# a render target's size, format and layout from its registers
pub type RenderTarget:
	address i64
	width i64   # pixels, or bytes a row when pitch linear
	height i64
	format i64
	tiling i64

	fn isPitchLinear():
		tiling & tilingPitchLinear != 0

	# the bytes the target takes in memory for pixels of `bpp` bytes
	fn bytes(bpp i64):
		if isPitchLinear(): return width * height
		s = textures.Surface(
			rowBytes = width * bpp,
			rows = height,
			blockHeight = (tiling >> 4) & 0xF
		)
		s.layoutBytes()

pub fn renderTarget(regs i64[], index i64) RenderTarget:
	r = reg3dRenderTargets + index * renderTargetWords
	RenderTarget(
		address = (regs[r] & 0xFF) << 32 | regs[r + 1],
		width = regs[r + 2],
		height = regs[r + 3],
		format = regs[r + 4],
		tiling = regs[r + 5]
	)

fn unorm(v f32, bits i64):
	max = (1 << bits) - 1
	i64((v.clamp(0.0, 1.0) * f32(max)).round())

fn pushHalf(mut out u8[], v f32):
	out.pushU16le(halfBits(v))

# a non-negative small float of a half's top bits: 11 bits keep 6 of its mantissa, 10 keep 5
fn smallFloat(v f32, bits i64):
	i64(halfBits(v.max(0.0))) >> (16 - bits)

# long: a table of the formats a clear writes
# A pixel of color c (RGBA) in a render target format; none for a format not written yet.
pub fn pixelOf(format i64, c Vec4) u8[]?:
	out = []
	match format:
		0xC0:   # R32G32B32A32_FLOAT
			for v in [c.x, c.y, c.z, c.w]:
				out.pushU32le(v.toBits())
		0xCA:   # R16G16B16A16_FLOAT
			for v in [c.x, c.y, c.z, c.w]:
				out.pushHalf(v)
		0xCF, 0xD0:   # B8G8R8A8 (UNORM, SRGB)
			for v in [c.z, c.y, c.x, c.w]:
				out.push(u8(unorm(v, 8)))
		0xD1:   # A2B10G10R10_UNORM
			out.pushU32le(
				unorm(c.x, 10) | unorm(c.y, 10) << 10 | unorm(c.z, 10) << 20 | unorm(c.w, 2) << 30
			)
		0xD5, 0xD6:   # A8B8G8R8 (UNORM, SRGB)
			for v in [c.x, c.y, c.z, c.w]:
				out.push(u8(unorm(v, 8)))
		0xDE:   # R16G16_FLOAT
			out.pushHalf(c.x)
			out.pushHalf(c.y)
		0xE0:   # R11G11B10_FLOAT
			out.pushU32le(
				smallFloat(c.x, 11) | smallFloat(c.y, 11) << 11 | smallFloat(c.z, 10) << 22
			)
		0xE5:   # R32_FLOAT
			out.pushU32le(c.x.toBits())
		0xE8:   # B5G6R5_UNORM
			out.pushU16le(unorm(c.z, 5) | unorm(c.y, 6) << 5 | unorm(c.x, 5) << 11)
		0xEA:   # R8G8_UNORM
			out.push(u8(unorm(c.x, 8)))
			out.push(u8(unorm(c.y, 8)))
		0xF2:   # R16_FLOAT
			out.pushHalf(c.x)
		0xF3:   # R8_UNORM
			out.push(u8(unorm(c.x, 8)))
		_: return none
	out

# CLEAR_SURFACE: bits 2-5 the components to clear, 6-9 the render target
fn clearSurface(mut g Gpu, c i64, sub i64, arg i64):
	g.stats.clears += 1
	if (arg >> 2) & 0xF != 0xF: return g.note("a clear of some components only")
	s = g.spaceOf(c)
	if s < 0: return
	regs = g.channels[c].engines[sub].regs
	rt = renderTarget(regs, (arg >> 6) & 0xF)
	color = Vec4(
		f32.fromBits(u32(regs[reg3dClearColor])),
		f32.fromBits(u32(regs[reg3dClearColor + 1])),
		f32.fromBits(u32(regs[reg3dClearColor + 2])),
		f32.fromBits(u32(regs[reg3dClearColor + 3]))
	)
	if g.renders:
		g.commands.push(.Clear(rt, color))
		return
	pixel = pixelOf(rt.format, color) ??
		return g.note("a clear of render target format {rt.format:x}")
	n = rt.bytes(pixel.len)
	bytes u8[] = zeros(n)
	for at in (0..n / pixel.len).map(it * pixel.len):
		for k, b in pixel:
			bytes[at + k] = b
	g.spaces[s].write(rt.address, bytes)
