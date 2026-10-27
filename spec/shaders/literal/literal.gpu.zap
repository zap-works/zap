# A texture array without a length read only at literal indices (1 in the vertex stage, 0 and 2 in
# the pixel stage): the compiler gives it a length of 3.

import shaders.vecs

pub type Corner:
	position Vec2

pub type Lit:
	textures vecs.Texture[]

pub fn vertex(v Corner, p Lit) (Vec4, Vec2):
	shade = p.textures[1].sampleLevel(v.position, 0.0)
	(Vec4(v.position.x, v.position.y, shade.x, 1.0), v.position)

pub fn pixel(uv Vec2, p Lit) Vec4:
	p.textures[0].sample(uv) + p.textures[2].sample(uv)
