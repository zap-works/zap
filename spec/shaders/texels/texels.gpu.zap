# Texels fetched by integer coordinates, with no sampler: a color texture's, an array's layer's,
# an integer texture's (its numbers as they are), with an offset; and the integer vectors' math.

import shaders.vecs

pub type Params:
	picture vecs.Texture
	layers vecs.TextureArray
	counts vecs.UintTexture
	signs vecs.IntTexture

fn reads(at IVec2, p Params) Vec4:
	c = p.picture.fetch(at, 0) + p.picture.fetch(at, 1, IVec2(-1, 2)) + p.layers.fetch(at, 3, 0)
	n UVec4 = p.counts.fetch(at, 0) + p.counts.fetch(at * 2, 0, IVec2(1, 0))
	s IVec4 = p.signs.fetch(at.yx, 0) - IVec4(1, 2, 3, 4)
	m = n.xy * UVec2(3, 5) + UVec2(n.z >> 2, n.w & 7)
	c + Vec4(f32(m.x), f32(m.y), f32(s.z), f32(p.counts.size(0).x))

pub fn vertex(id i32, p Params) Vec4:
	reads(IVec2(id, id / 2), p)

pub fn pixel(p Params) Vec4:
	reads(IVec2(i32(pixelPosition.x), i32(pixelPosition.y)), p)
