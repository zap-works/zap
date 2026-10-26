# An element of a texture array handed to a function (the shader tests expect the error: the
# index is passed instead).

import shaders.vecs

pub type Pictures:
	textures vecs.Texture[]
	which i32

fn shade(picture vecs.Texture, at Vec2) Vec4:
	picture.sample(at)

pub fn pixel(uv Vec2, p Pictures) Vec4:
	shade(p.textures[p.which], uv)
