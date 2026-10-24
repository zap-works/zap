# An offset the compiler cannot read as a constant.

import shaders.vecs

pub type Params:
	picture vecs.Texture

pub fn pixel(uv Vec2, p Params) Vec4:
	p.picture.sample(uv, IVec2(i32(uv.x), 0))
