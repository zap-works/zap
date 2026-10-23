# The ambient occlusion of a cell's picture (shaders/occlusion.gpu.zap): after its opaque parts
# are drawn, the raw occlusion of their depths, blurred across and up, multiplies the picture.
# The radius, intensity, bias, contrast and steadiness are the executable's defaults of
# fSAORadius, fSAOIntensity, fSAOBias, fSAOExpFactor and fSAOValueDiffFactor (Display), none of
# them in the ini files; 0x14154240B passes them as radius * 100, intensity / radius^6 and
# radius², and each frame a random angle (a random 32 bits times pi / 2^32).

import engine
import world.shaders

radius f32 = 250.0
intensity f32 = 15.0
bias f32 = 2.5
expFactor f32 = 0.11
valueDiffFactor f32 = 0.3

pub type Occlusion:
	normals engine.RenderTarget   # the opaque parts' view-space normals, drawn by scene.zap
	raws engine.RenderTarget[]   # this and the last frame's raw occlusion, trading places
	blurred engine.RenderTarget
	final engine.RenderTarget   # blurred both ways, as the picture takes it
	frame i64 = 0
	rawPass engine.ScreenPass
	blurPass engine.ScreenPass
	applyPass engine.ScreenPass

fn occlusionTarget(w i64, h i64):
	engine.newRenderTarget(w, h, true, false)

fn normalsTarget(w i64, h i64):
	engine.newRenderTarget(w, h, true, true)

pub fn newOcclusion() Occlusion:
	Occlusion(
		normals = normalsTarget(1, 1),
		raws = [occlusionTarget(1, 1), occlusionTarget(1, 1)],
		blurred = occlusionTarget(1, 1),
		final = occlusionTarget(1, 1),
		rawPass = engine.newScreenPass(shader(shaders.rawOcclusionPixel)),
		blurPass = engine.newScreenPass(shader(shaders.occlusionBlurPixel)),
		applyPass = engine.newScreenPass(shader(shaders.occlusionAppliedPixel))
	)

# the targets made again for a picture of w x h (nothing when they have that size)
pub fn fitOcclusion(mut o Occlusion, w i64, h i64):
	if o.final.width == w and o.final.height == h: return
	o.normals = normalsTarget(w, h)
	o.raws = [occlusionTarget(w, h), occlusionTarget(w, h)]
	o.blurred = occlusionTarget(w, h)
	o.final = occlusionTarget(w, h)
	o.frame = 0

# this frame's raw occlusion (red) and depth key (green)
pub fn rawNow(o Occlusion) engine.Texture:
	o.raws[o.frame % 2].colorTexture()

fn blurInto(
	mut r engine.Renderer,
	o Occlusion,
	from engine.RenderTarget,
	into engine.RenderTarget,
	step Vec2
):
	r.useTarget(into)
	r.drawScreenPass(o.blurPass, shaders.OcclusionBlur(raw = from.colorTexture(), step))

# The occlusion of what `scene` holds, seen through `projection` (its fov vertical) from a view
# that `toPrevious` carries into the last frame's, multiplied into it; `scene` is in use again
# after. The next frame's occlusion is the next call's.
# The fog fade SkyrimSE.exe's SAO composite (ISSAOCompositeSAOFog) multiplies the composed picture by,
# FogNearColor.w: BSShaderManager::State's invFrameBufferRange (CommonLibSSE's name, offset 0x9C;
# Nukem9's SkyrimSETest copies it into FogNearColor.w), a static 1 / 1.2 at 0x1420d694c that only
# the SetFramebufferRange console command changes; the RenderDoc captures show 0.8333 on every pose
# (reference/exe/README.md, "Render captures"). The alpha-blended effects drawn after it are
# untouched.
pub fogFade f32 = 1.0 / 1.2

pub fn drawOcclusion(
	mut r engine.Renderer,
	mut o Occlusion,
	scene engine.RenderTarget,
	projection Mat4,
	toPrevious Mat4
):
	across = f32(scene.width)
	high = f32(scene.height)
	m = projection.m
	r.setBlending(false)
	r.setDepth(false, false, false)
	o.frame += 1
	now = o.frame % 2
	r.useTarget(o.raws[now])
	r.drawScreenPass(
		o.rawPass,
		shaders.RawOcclusion(
			depth = scene.depthTexture(),
			unproject = Vec4(1.0 / m[0], 1.0 / m[5], m[10], m[14]),
			extent = Vec4(across, high, 1.0 / across, 1.0 / high),
			shape = Vec4(
				radius * 100.0,
				radius * radius,
				intensity / radius.pow(6.0),
				bias
			),
			normals = o.normals.colorTexture(),
			contrast = expFactor,
			history = o.raws[1 - now].colorTexture(),
			toPrevious,
			turn = engine.random01(o.frame, 0, 7) * pi,
			steadiness = valueDiffFactor,
			fresh = 1.0 if o.frame == 1 else 0.0
		)
	)
	r.blurInto(o, o.raws[now], o.blurred, Vec2(2.0 / across, 0.0))
	r.blurInto(o, o.blurred, o.final, Vec2(0.0, 2.0 / high))
	r.useTarget(scene)
	r.setBlendMode(.Premultiplied)
	r.drawScreenPass(
		o.applyPass,
		shaders.OcclusionApplied(occlusion = o.final.colorTexture(), fade = fogFade)
	)
	r.setBlending(false)
