# The engine's own shaders, GPU code of this module (the compiler sends these functions to the
# GPU; their types are the CPU's too):
#   - the sprite batch's quads (render.zap): each corner placed by the projection, its texel
#     (of the batch's texture it names, or of its one texture on a device without texture
#     arrays) tinted;
#   - a skinned body's vertex (skin.zap): bent by up to four entries of its palette (three rows
#     of a matrix each, in the crowd's storage buffer from the body's first row), then scaled,
#     turned about y and set where the body stands. It passes on the place, the normal, the
#     texture place and flags, the color (tinted) and the flash and fade, as `Skinned`: a
#     program's pixel stage declares a struct of the same fields to read them. A crowd's depth
#     alone (a shadow map's) is skinnedDepth.

# a corner of a sprite's quad, placed in pixels
pub type SpriteVertex:
	position Vec2
	uv Vec2
	tint Vec4
	image i32   # of the batch's images

pub type SpriteParams:
	projection Mat4
	images Texture[]   # the textures of the batch's quads

pub type SpritePoint:
	uv Vec2
	tint Vec4
	image i32

# a batch's of one texture
pub type SpriteParamsOne:
	projection Mat4
	image Texture

fn spriteCorner(v SpriteVertex, projection Mat4) (Vec4, SpritePoint):
	(
		projection @ Vec4(v.position.x, v.position.y, 0.0, 1.0),
		SpritePoint(uv = v.uv, tint = v.tint, image = v.image)
	)

pub fn spriteVertex(v SpriteVertex, p SpriteParams) (Vec4, SpritePoint):
	spriteCorner(v, p.projection)

pub fn spritePixel(b SpritePoint, p SpriteParams) Vec4:
	p.images[b.image].sample(b.uv) * b.tint

pub fn spriteVertexOne(v SpriteVertex, p SpriteParamsOne) (Vec4, SpritePoint):
	spriteCorner(v, p.projection)

pub fn spritePixelOne(b SpritePoint, p SpriteParamsOne) Vec4:
	p.image.sample(b.uv) * b.tint

# a skinned model's vertex: as glTF gives it (gltf.zap, skinVertexFloats floats)
pub type SkinVertex:
	position Vec3
	normal Vec3
	uvFlags Vec4   # u, v, textured, emissive
	baseColor Vec4
	joints Vec4   # palette entries
	weights Vec4

# a body of a crowd: where it stands (x, y, z) and its turn about y; its scale, its palette's
# first row, its flash, its fade; its tint
pub type SkinBody:
	place Vec4
	shape Vec4
	tint Vec4

# a crowd's, with the palette rows of every body
pub type SkinParams:
	viewProjection Mat4
	palette Vec4[]

# what a skinned vertex passes on
pub type Skinned:
	position Vec3
	normal Vec3
	uv Vec4
	color Vec4
	flash Vec2   # flash, fade

# bent by the palette, then scaled, turned and placed
pub fn skinnedVertex(v SkinVertex, body SkinBody, p SkinParams) (Vec4, Skinned):
	first = i32(body.shape.y)
	a = first + i32(v.joints.x) * 3
	b = first + i32(v.joints.y) * 3
	c = first + i32(v.joints.z) * 3
	d = first + i32(v.joints.w) * 3
	w = v.weights
	r0 = p.palette[a] * w.x + p.palette[b] * w.y + p.palette[c] * w.z + p.palette[d] * w.w
	r1 = p.palette[a + 1] * w.x + p.palette[b + 1] * w.y + p.palette[c + 1] * w.z +
		p.palette[d + 1] * w.w
	r2 = p.palette[a + 2] * w.x + p.palette[b + 2] * w.y + p.palette[c + 2] * w.z +
		p.palette[d + 2] * w.w
	p4 = v.position.withW(1.0)
	q = Vec3(r0 @ p4, r1 @ p4, r2 @ p4) * body.shape.x
	m = Vec3(r0.xyz @ v.normal, r1.xyz @ v.normal, r2.xyz @ v.normal)
	place = body.place
	s = place.w.sin()
	co = place.w.cos()
	world = Vec3(place.x + q.x * co + q.z * s, place.y + q.y, place.z - q.x * s + q.z * co)
	normal = Vec3(m.x * co + m.z * s, m.y, -m.x * s + m.z * co).normalized()
	(
		p.viewProjection @ world.withW(1.0),
		Skinned(
			position = world,
			normal = normal,
			uv = v.uvFlags,
			color = v.baseColor * body.tint,
			flash = body.shape.zw
		)
	)

# a skinned body's depth alone (a shadow map's): nothing to color
pub fn skinnedDepth(b Skinned):
	pass
