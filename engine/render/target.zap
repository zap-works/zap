# Drawing off the screen, for effects: render targets (a color texture, a depth texture, or
# both), read by shaders as a Texture (colorTexture) or a ShadowMap (shadowMap), and passes that
# run a pixel stage over a whole target (a sky, a blur, the final image).

import rhi
import rhi.core

pub type RenderTarget:
	color i64   # its color texture (-1: none)
	depth i64   # its depth texture (-1: none)
	width i64
	height i64
	samples i64   # 1, or a multisampled target's: read only by resolving it

	# its color texture, read by a shader's Texture
	pub fn colorTexture() Texture:
		Texture(id = color, width, height)

	# its depth texture, read by a shader's Texture (its depths in r)
	pub fn depthTexture() Texture:
		Texture(id = depth, width, height)

	# a shadow target's depth, read by a shader's ShadowMap
	pub fn shadowMap() ShadowMap:
		ShadowMap(id = depth, size = width)

	# its textures freed where it is dropped, the pass drawing into it ended first
	mut fn drop():
		dropTargets([color, depth])

# The textures of targets (-1 none) freed, the pass drawing into one of them ended first.
fn dropTargets(ids i64[]):
	drawQueued()
	p = gpu.currentPass()
	if p.active:
		for id in ids:
			if id >= 0 and (p.color == id or p.depth == id or id in p.extraColors):
				gpu.endPass()
				break
	for id in ids:
		if id >= 0:
			gpu.destroyTexture(id)

# a pass over a whole target: its program, drawn as one triangle that covers it
pub type ScreenPass:
	program Program

# a depth texture read with comparisons (a shadow map: smoothed between texels, lit beyond its
# edges), as a shader's ShadowMap
pub type ShadowMap:
	id i64
	size i64

# A target of w x h pixels with a color texture (half floats when `hdr`: values above 1 kept for
# bloom; smoothed when sampled) and, when `withDepth`, a depth texture.
pub fn newRenderTarget(w i64, h i64, hdr bool, withDepth bool) RenderTarget:
	color = newTargetTexture(w, h, core.fmtRgba16Float if hdr else core.fmtRgba8, 1, smoothly)
	depth = newTargetTexture(w, h, core.fmtD32, 1, none) if withDepth else -1
	RenderTarget(color, depth, width = w, height = h, samples = 1)

# A target of only depth, w x h, to draw on the screen with (useScreenWithDepth)
pub fn newDepthTarget(w i64, h i64) RenderTarget:
	depth = newTargetTexture(w, h, core.fmtD32, 1, none)
	RenderTarget(color = -1, depth, width = w, height = h, samples = 1)

# what the renderer draws next goes to the screen, tested against and written into the depth of
# `t` (the screen's size)
pub fn useScreenWithDepth(mut r Renderer, t RenderTarget):
	r.chooseTarget(core.screenTarget, t.depth)

# A target of only depth, size x size, for a shadow map: sampled with comparison (a shader's
# ShadowMap, smoothed between texels), lit beyond its edges.
pub fn newShadowTarget(size i64) RenderTarget:
	newShadowTargetBy(size, size)

# a shadow target of w x h
pub fn newShadowTargetBy(w i64, h i64) RenderTarget:
	depth = newTargetTexture(w, h, core.fmtD16, 1, core.SamplerDesc(..smoothly, compare = true))
	RenderTarget(color = -1, depth, width = w, height = h, samples = 1)

# A target of w x h pixels drawn with `samples` samples a pixel (half-float color, depth): its
# edges smooth once it is resolved into a plain target of the same size.
pub fn newMultisampleTarget(w i64, h i64, samples i64) RenderTarget:
	color = newTargetTexture(w, h, core.fmtRgba16Float, samples, none)
	depth = newTargetTexture(w, h, core.fmtD32, samples, none)
	RenderTarget(color, depth, width = w, height = h, samples)

# a target read smoothed between texels, clamped
smoothly = core.SamplerDesc(
	smooth = true,
	mipmaps = 0,
	repeat = false,
	mirror = 0,
	anisotropy = false,
	compare = false
)

# a w x h texture of the format drawn into, `samples` a pixel, read with `sampler` (none: sharp)
fn newTargetTexture(w i64, h i64, format i64, samples i64, sampler core.SamplerDesc?):
	id = gpu.newTexture(core.TextureDesc(
		width = w,
		height = h,
		layers = 1,
		levels = 1,
		format,
		samples,
		array = false, target = true))
	if sampler is how:
		gpu.setSampler(id, how)
	id

# a multisampled target's samples averaged into the color of `into` (a plain target)
pub fn resolveTarget(from RenderTarget, into RenderTarget):
	drawQueued()
	gpu.resolve(from.color, into.color)

# what the renderer draws next goes to the target (its whole area)
pub fn useTarget(mut r Renderer, t RenderTarget):
	chooseTarget(
		r,
		t.color if t.color >= 0 else core.noTarget,
		t.depth if t.depth >= 0 else core.noTarget
	)

# ---------- passes over a whole target ----------

# A pass whose pixel stage runs once per pixel of the target: the program the compiler built of
# a pixel stage alone (shader(blur.pixel)), whose first parameter is where it is across the
# target (0..1, a Vec2).
pub fn newScreenPass(code str) ScreenPass:
	ScreenPass(program = newProgram(code))

# runs the pass over the renderer's target with its parameters
pub fn drawScreenPass<P GpuParams>(r Renderer, pass ScreenPass, params P):
	setParams(pass.program, params)
	drawGenerated(r, pass.program, 3)

# ---------- sets of targets ----------

# a depth target's format: 16 bits, 24 bits with a stencil of 8, a float
pub type DepthFormat:
	D16
	D24S8
	D32Float

	# the RHI's code of the format
	fn code():
		match self:
			D16: core.fmtD16
			D24S8: core.fmtD24S8
			D32Float: core.fmtD32

# Targets drawn into at once, all one size: color targets of their formats (a pixel stage returns
# a struct of one Vec4 per target, in their order) and a depth target or none. Each is read by a
# later draw as a texture (colorTexture, depthTexture), and a color one back by the CPU (readColor).
pub type TargetSet:
	colors i64[]   # the color textures
	depth i64   # the depth texture, -1 none
	width i64
	height i64

	# color target k as a shader's Texture (smoothed when sampled)
	pub fn colorTexture(k i64) Texture:
		Texture(id = colors[k], width, height)

	# its depth texture, read by a shader's Texture (its depths in r)
	pub fn depthTexture() Texture:
		Texture(id = depth, width, height)

	mut fn drop():
		ids = colors.copy()
		ids.push(depth)
		dropTargets(ids)

# A set of w x h targets: a color target of each format (up to 8) and a depth target of `depth`'s
# format, or none.
pub fn newTargetSet(w i64, h i64, formats TextureFormat[], depth DepthFormat?) TargetSet:
	if formats.len > core.mostColorTargets:
		fail("a set of {formats.len} color targets (at most {core.mostColorTargets})")
	colors = formats.map(newTargetTexture(w, h, .code(), 1, smoothly))
	depthId = -1
	if depth is d:
		depthId = newTargetTexture(w, h, d.code(), 1, none)
	TargetSet(colors, depth = depthId, width = w, height = h)

# what the renderer draws next goes to the set's targets (their whole area)
pub fn useTargetSet(mut r Renderer, s TargetSet):
	r.chooseTargets(s.colors, s.depth)

# The bytes of color target k as its format lays them out (rows from the top): the frame ends with
# them read back (as a screenshot ends it), so a loop's next frame begins after.
pub fn readColor(s TargetSet, k i64) u8[]:
	drawQueued()
	if not frameOpen:
		fail("a target read back outside a frame")
	bytes = gpu.readTexture(s.colors[k])
	frameOpen = false
	bytes
