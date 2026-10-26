# The distant trees as Skyrim's distant tree shader draws them (Community Shaders' DistantTree.hlsl):
# each tree two crossed vertical quads of the tree list's size cut from the atlas, scaled and turned
# about the vertical by its instance and put at its place, alpha tested at 0x80, lit by half the sun
# plus the ambient along the quad's normal (the face turned away from the eye, as the derivatives'
# cross product points) with no shadow, and fogged as any surface of the cell.

import engine

# a corner of a tree's quad: where the tree stands (y up), the corner in the tree's own space (the
# game's, z up), the atlas coordinate, the quad's normal in the tree's space, and the instance's
# cosine and sine of its turn, its scale and the atlas texture's index in the program's list
pub type TreeVertex:
	place Vec3
	corner Vec3
	uv Vec2
	plane Vec3
	instance Vec4

pub type TreePoint:
	world Vec3
	normal Vec3
	uv Vec2
	atlas f32

# a vector of the tree's space turned about the vertical by the instance's turn
fn turned(v Vec3, i Vec4) Vec3:
	Vec3(i.x * v.x - i.y * v.y, i.y * v.x + i.x * v.y, v.z)

pub fn treeVertex(v TreeVertex, p CellParams) (Vec4, TreePoint):
	world = v.place + inEngine(turned(v.corner * v.instance.z, v.instance))
	(
		p.projection @ p.view @ world.withW(1.0),
		TreePoint(
			world,
			normal = inEngine(turned(v.plane, v.instance)),
			uv = v.uv,
			atlas = v.instance.w
		)
	)

# the alpha test's reference, 0x80
treeAlphaRef f32 = 0.5019608

pub fn treePixel(b TreePoint, p CellParams) Vec4:
	if p.debugId > 0.5:
		return Vec4(0.0, 0.0, 0.0, 1.0)
	texel = p.textures[engine.tileSlot(b.atlas)].sample(b.uv)
	if texel.a < treeAlphaRef:
		discard()
	toEye = (p.eye.xyz - b.world).normalized()
	n = b.normal.normalized()
	away = n if (n @ toEye) < 0.0 else n * -1.0
	if p.normalPass > 0.5:
		return (p.view @ (away * -1.0).withW(0.0)).xyz.withW(1.0)
	light = p.sunColor.rgb * 0.5 + ambientOf(away, p)
	c = texel.rgb * light
	fogged(c, b.world, p).withW(1.0)
