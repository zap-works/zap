# The shadows of Skyrim's omnidirectional shadow lights: each light's dual paraboloid map, as the
# vanilla shadow passes draw and read it (Community Shaders' Utility.hlsl, RENDER_SHADOWMAP_PB and
# RENDER_SHADOWMASKDPB): each hemisphere about the light's x axis seen from the light through a
# paraboloid, the depth the distance over the light's radius; a place is lit where it is no farther
# from the light than the map's depth there.

import engine

# a place `d` from a light as its map sees it: the paraboloids' axis is the light's own x axis
# (Gamebryo's direction of a light; the game's x, the renderer's too), carried to y
fn lightAxis(d Vec3) Vec3:
	Vec3(d.y, d.x, d.z)

# the shadow camera's projection on the axis, z' = (z - 0.1) / 0.9 in world units, as the game's
# shadow passes carry it (RenderDoc captures, reference/exe/README.md, "Render captures"): the same
# in the map and in the read, it bends the paraboloid's directions and the distance toward the axis
axisScale f32 = 1.0 / 0.9
axisShift f32 = 0.1 / 0.9

# a place `d` from a light of `radius` in clip space of the paraboloid map of the hemisphere
# `side` (1 above the light, -1 below): its direction bent halfway to the axis, over its height
fn paraboloid(d0 Vec3, radius f32, side f32) Vec4:
	a = lightAxis(d0)
	d = Vec3(a.x, a.y * axisScale - axisShift, a.z)
	h = (d.normalized() + Vec3(0.0, side, 0.0)).normalized()
	over = (h.y * side).max(1.0e-4)
	Vec4(h.x / over, h.z / over, d.length() / radius * 2.0 - 1.0, 1.0)

pub type ShadowPoint:
	uv Vec2
	height f32   # over the light along its hemisphere's side: below 0 the other's
	material Vec4
	diffuse i32

# a vertex of the cell in the map of p.shadowLight's hemisphere p.shadowSide
pub fn shadowVertex(v CellVertex, p CellParams) (Vec4, ShadowPoint):
	world, _, _ = placed(v, p)
	d = world - p.shadowLight.xyz
	(paraboloid(d, p.shadowLight.w, p.shadowSide), ShadowPoint(
		uv = v.uv,
		height = lightAxis(d).y * p.shadowSide,
		material = v.material,
		diffuse = v.diffuse))

# what a shadow map keeps of a part: effects cast none, cut-out texels none
pub fn castsShadowAt(b ShadowPoint, p CellParams):
	if b.material.w > 0.5:
		discard()
	if b.material.z > 0.0:
		if p.textures[b.diffuse].sample(b.uv).a < b.material.z:
			discard()

# only the depth, of the hemisphere's side
pub fn shadowPixel(b ShadowPoint, p CellParams):
	if b.height < 0.0:
		discard()
	castsShadowAt(b, p)

# the shadow map k (two a light: above it, below it) read at uv against `depth`: the share lit,
# smoothed between texels
fn compareIn(k i32, uv Vec2, depth f32, p CellParams) f32:
	if k == 0:
		return p.shadow0.compare(uv, depth)
	if k == 1:
		return p.shadow1.compare(uv, depth)
	if k == 2:
		return p.shadow2.compare(uv, depth)
	if k == 3:
		return p.shadow3.compare(uv, depth)
	if k == 4:
		return p.shadow4.compare(uv, depth)
	if k == 5:
		return p.shadow5.compare(uv, depth)
	if k == 6:
		return p.shadow6.compare(uv, depth)
	p.shadow7.compare(uv, depth)

# the game's shadow mask filter (RENDER_SHADOWMASKDPB as SkyrimSE.exe's shader holds it): 16 taps
# of this disk in 0..1, scaled to -1..1 and to a filter radius of 1/512 of the atlas
poissonTaps Vec2[16] = [
	Vec2(0.493393, 0.394269),
	Vec2(0.798547, 0.885922),
	Vec2(0.247322, 0.926450),
	Vec2(0.051454, 0.140782), Vec2(0.831843, 0.009552), Vec2(0.428632, 0.017151),
	Vec2(0.015656, 0.749779), Vec2(0.758385, 0.496170), Vec2(0.223487, 0.562151),
	Vec2(0.011628, 0.406995), Vec2(0.241462, 0.304636), Vec2(0.430311, 0.727226),
	Vec2(0.981811, 0.278359), Vec2(0.407056, 0.500534), Vec2(0.123478, 0.463546),
	Vec2(0.809534, 0.682272)]
filterRadius f32 = 1.0 / 512.0
depthBias f32 = 0.0125   # in distance over radius

# How much of the shadow light i reaches `world`, as the game's mask reads it: at the place itself
# (no normal offset), the 16 taps compared against the distance over the radius less the bias. The
# atlas keeps both hemispheres in one texture, half its height each, so a tap's v here is twice the
# atlas's; a tap that would leave its hemisphere keeps its v (the game drops its v offset).
fn lightReaching(i i32, world Vec3, p CellParams) f32:
	l = p.lights[i]
	d = world - l.place.xyz
	side f32 = 1.0 if lightAxis(d).y >= 0.0 else -1.0
	at = paraboloid(d, l.place.w, side).xyz * 0.5 + Vec3(0.5, 0.5, 0.5)
	k = i * 2 + (0 if side > 0.0 else 1)
	sum f32 = 0.0
	for n in 0..16:
		offset = (poissonTaps[n] * 2.0 - Vec2(1.0, 1.0)) * filterRadius
		u = at.x + offset.x
		v = at.y + offset.y * 2.0 * side
		if v < 0.0 or v > 1.0: v = at.y
		sum += compareIn(k, Vec2(u, v), at.z - depthBias, p)
	sum / 16.0

# how much of each shadow light (at most four) reaches `world`; read by the stage that owns the
# parameters (a program whose parameters are a second part reads none)
pub fn shadowsAt(world Vec3, p CellParams) Vec4:
	out f32[4]
	for i in 0..4:
		out[i] = lightReaching(i, world, p) if i < p.shadowCount else 1.0
	Vec4(out[0], out[1], out[2], out[3])
