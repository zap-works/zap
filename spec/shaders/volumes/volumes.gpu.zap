# 3D textures, cubes and cube arrays read by every read they have, in both stages (a 3D
# texture's offsets an IVec3, a cube's reads none), a 3D texture's texels fetched; and a shadow
# map compared at a level and with a bias.

import shaders.vecs

pub type Params:
	fog vecs.Texture3D
	sky vecs.TextureCube
	probes vecs.TextureCubeArray
	shadow vecs.ShadowMap
	shadows vecs.ShadowMapArray

fn reads(p Vec3, p2 Vec2, s Params) Vec4:
	a = s.fog.sample(p) + s.fog.sampleLevel(p, 1.0, IVec3(1, -2, 3)) +
		s.fog.sampleGrad(p, Vec3(0.01, 0.0, 0.0), Vec3(0.0, 0.01, 0.0)) +
		s.fog.fetch(IVec3(1, 2, 3), 0, IVec3(0, 0, -1))
	b = s.sky.sample(p) + s.sky.sampleBias(p, 0.5) + s.sky.gather(p, 2) + s.sky.sampleLevel(p, 2.0)
	c = s.probes.sample(p, 1.0) + s.probes.sampleLevel(p, 2.0, 1.5) + s.probes.gather(p, 0.0, 1)
	lit = s.shadow.compareLevel(p2, 0.5, 1.0) + s.shadow.compareBias(p2, 0.5, -0.5, IVec2(1, 1)) +
		s.shadows.compareLevel(p2, 2.0, 0.25, 0.0)
	size = s.fog.size(0) + IVec3(s.sky.size(1).x, 0, s.probes.size(0).z)
	lod = s.sky.lod(p) + s.probes.lod(p)
	a + b + c + Vec4(lit, lod.x, lod.y, f32(size.x + size.z))

pub fn vertex(id i32, s Params) Vec4:
	reads(Vec3(f32(id), 1.0, 0.0), Vec2(f32(id), 0.0), s)

pub fn pixel(s Params) Vec4:
	reads(pixelPosition.xyz, pixelPosition.xy, s)
