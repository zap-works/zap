# A pass that reads two textures of an array at literal indices: the first left of the middle, the
# second right of it.

import engine

pub type Pictures:
	pictures engine.Texture[]

pub fn pixel(uv Vec2, p Pictures) Vec4:
	p.pictures[0].sample(uv) if uv.x < 0.5 else p.pictures[1].sample(uv)
