# The sun's cascaded shadow maps as the exterior reads them (RENDER_SHADOWMASK of Community
# Shaders' Utility.hlsl, which is the vanilla shadow mask): three cascades of the view, each a
# depth map the sun's orthographic camera drew; a place takes the cascade its view depth falls in
# (past the first cascade's start of overlap the two are blended with a smoothstep), compared
# through eight rotated spiral taps of fPoissonRadiusScale / iShadowMapResolution, and the shadow
# fades out toward fShadowDistance as 1 - (distance / shadow distance)^16.

import engine

# the eight taps of the spiral (Random::SpiralSampleOffsets8)
spiralTaps Vec2[8] = [
	Vec2(-0.7071, 0.7071),
	Vec2(0.0, -0.875),
	Vec2(0.5303, 0.5303),
	Vec2(-0.625, 0.0),
	Vec2(0.3536, -0.3536),
	Vec2(0.0, 0.375),
	Vec2(-0.1768, -0.1768),
	Vec2(0.125, 0.0)
]

# the taps' radius in map units: fPoissonRadiusScale 4 over iShadowMapResolution 2048
poissonRadius f32 = 4.0 / 2048.0

# the vertex stage of a cascade's depth pass: the part's vertex in the sun camera of p.sunCascade
pub fn sunShadowVertex(v CellVertex, p CellParams) (Vec4, ShadowPoint):
	world, _, _ = placed(v, p)
	(sunProjectionOf(p.sunCascade, p) @ world.withW(1.0), ShadowPoint(
		uv = v.uv,
		height = 1.0,
		material = v.material,
		diffuse = v.diffuse))

# only the depth, as any shadow map
pub fn sunShadowPixel(b ShadowPoint, p CellParams):
	castsShadowAt(b, p)

# the matrix taking a place to cascade k's map
fn sunProjectionOf(k i32, p CellParams) Mat4:
	if k == 0:
		return p.sunProjection0
	if k == 1:
		return p.sunProjection1
	p.sunProjection2

# the cascade k's map compared at uv against `depth`
fn compareSun(k i32, uv Vec2, depth f32, p CellParams) f32:
	if k == 0:
		return p.sunShadow0.compare(uv, depth)
	if k == 1:
		return p.sunShadow1.compare(uv, depth)
	p.sunShadow2.compare(uv, depth)

# an angle from 0 to 2 pi that changes from place to place (interleaved gradient noise)
fn spinAt(world Vec3) f32:
	g = (world.x * 0.06711056 + world.z * 0.00583715).fract()
	(52.9829189 * g).fract() * tau

# how much of the sun reaches `world` through cascade k: the eight rotated taps, the map's bias off the
# depth
fn sunThrough(k i32, world Vec3, bias f32, p CellParams) f32:
	at = sunProjectionOf(k, p) @ world.withW(1.0)
	uv = Vec2(at.x * 0.5 + 0.5, at.y * 0.5 + 0.5)
	depth = at.z * 0.5 + 0.5 - bias
	s = spinAt(world).sin()
	c = spinAt(world).cos()
	sum f32 = 0.0
	for n in 0..8:
		tap = spiralTaps[n]
		turned = Vec2(tap.x * c - tap.y * s, tap.x * s + tap.y * c)
		sum += compareSun(k, uv + turned * poissonRadius, depth, p)
	sum / 8.0

# How much of the sun reaches `world`: 1 where the scene has no sun shadows, and past the shadow
# distance
pub fn sunVisibility(world Vec3, p CellParams) f32:
	if p.sunShadowCount < 1:
		return 1.0
	depth = -(p.view @ world.withW(1.0)).z
	if depth > p.sunEnds.z:
		return 1.0
	cascade i32 = 0
	bias = p.sunBias.x
	if p.sunEnds.x < depth:
		cascade = 1
		bias = p.sunBias.y
	if p.sunShadowCount > 2 and p.sunEnds.y < depth:
		cascade = 2
	visible = sunThrough(cascade, world, bias, p)
	if cascade < 1 and p.sunStarts.y < depth:
		into = ((depth - p.sunStarts.y) / (p.sunEnds.x - p.sunStarts.y)).clamp(0.0, 1.0)
		blend = into * into * (3.0 - 2.0 * into)
		visible = visible + (sunThrough(1, world, p.sunBias.y, p) - visible) * blend
	d = world - p.eye.xyz
	near = ((d @ d) / p.sunShadowDistance2).clamp(0.0, 1.0)
	fade = 1.0 - near.pow(8.0)
	1.0 + (visible - 1.0) * fade
