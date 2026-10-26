# A texture array handed to a function, which no backend can do (the shader tests expect the
# error).

import shaders.vecs

pub type Pictures:
	textures vecs.Texture[]

fn pick(all vecs.Texture[], at Vec2) Vec4:
	all[0].sample(at)

pub fn pixel(uv Vec2, p Pictures) Vec4:
	pick(p.textures, uv)
