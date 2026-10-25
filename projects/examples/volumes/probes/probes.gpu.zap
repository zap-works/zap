# A kernel that reads a 3D texture (at texels' centres, by an offset, fetched), a cube and a
# cube array by directions toward each face, and a shadow map compared at a level and with a
# bias, and writes what it read as numbers.

import engine

pub type Probes:
	fog engine.Texture3D   # 4x4x4
	sky engine.TextureCube   # faces 2x2, one color a face
	rooms engine.TextureCubeArray   # two cubes
	shadow engine.ShadowMap   # cleared to 0.5
	out u32[]

# a color's bytes, r in the lowest
fn packed(c Vec4) u32:
	b = (c * 255.0 + 0.5).floor()
	u32(b.x) | u32(b.y) << 8 | u32(b.z) << 16 | u32(b.w) << 24

# the directions toward the faces +x -x +y -y +z -z
fn toward(face i32) Vec3:
	sign = 1.0 if face % 2 == 0 else -1.0
	axis = face / 2
	Vec3(sign if axis == 0 else 0.1, sign if axis == 1 else 0.2, sign if axis == 2 else 0.3)

pub fn probe(mut p Probes):
	i = globalId.x
	k = i * 8
	at = IVec3(i % 4, i / 4 % 4, i / 16)
	centre = (Vec3(f32(at.x), f32(at.y), f32(at.z)) + 0.5) / 4.0
	p.out[k] = packed(p.fog.sampleLevel(centre, 0.0))
	p.out[k + 1] = packed(p.fog.sampleLevel(centre, 0.0, IVec3(1, 0, -1)))
	p.out[k + 2] = packed(p.fog.fetch(at, 0))
	face = i % 6
	p.out[k + 3] = packed(p.sky.sampleLevel(toward(face), 0.0))
	p.out[k + 4] = packed(p.rooms.sampleLevel(toward(face), f32(i / 6 % 2), 0.0))
	uv = Vec2(0.25, 0.75)
	near = p.shadow.compareLevel(uv, 0.4, 0.0)
	far = p.shadow.compareBias(uv, 0.6, 0.0)
	p.out[k + 5] = u32(near * 100.0 + 0.5) + u32(far * 100.0 + 0.5) * 1000
	p.out[k + 6] = u32(p.fog.size(0).z * 100 + p.sky.size(0).x * 10 + p.rooms.size(0).z)
	p.out[k + 7] = 7
