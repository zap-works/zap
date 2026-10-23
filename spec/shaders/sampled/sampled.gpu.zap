# Every texture read on each kind, in both stages: a vertex stage has no derivatives, so its
# reads take explicit levels (a bias the level, the level of detail (0, 0)); the pixel stage's
# take the derivatives' with the constant offsets, gathers and comparisons on layers.

import shaders.vecs

pub type Params:
	picture vecs.Texture
	layers vecs.TextureArray
	shadow vecs.ShadowMap
	shadows vecs.ShadowMapArray

fn reads(uv Vec2, p Params) Vec4:
	a = p.picture.sampleBias(uv, 0.5) + p.picture.sampleGrad(uv, Vec2(0.01, 0.0), Vec2(0.0, 0.01))
	b = p.picture.gather(uv, 3) + p.layers.gather(uv, 2.0, 1, IVec2(1, -1))
	c = p.layers.sampleBias(uv, 1.0, -0.5, IVec2(-8, 7)) +
		p.layers.sampleGrad(uv, 1.0, Vec2(0.01, 0.0), Vec2(0.0, 0.01))
	d = p.shadow.gatherCompare(uv, 0.5) + p.shadows.gatherCompare(uv, 1.0, 0.5, IVec2(x = 0, y = 1))
	lit = p.shadow.compare(uv, 0.5, IVec2(2, 2)) + p.shadows.compare(uv, 3.0, 0.25)
	lod = p.picture.lod(uv) + p.layers.lod(uv)
	size = p.shadows.size(0)
	a + b + c + d + Vec4(lit, lod.x, lod.y, f32(size.z))

pub fn vertex(id i32, p Params) Vec4:
	reads(Vec2(f32(id), 0.0), p)

pub fn pixel(p Params) Vec4:
	uv = pixelPosition.xy
	reads(uv, p) + p.picture.sample(uv, IVec2(1, 0)) + p.picture.sampleLevel(uv, 2.0, IVec2(0, -1))
