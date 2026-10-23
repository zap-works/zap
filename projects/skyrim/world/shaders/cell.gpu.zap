# A cell drawn as Skyrim lights an interior (lighting.gpu.zap), per pixel: the diffuse texture
# and the vertex color, the normal bent by the normal map (tangent space), its alpha masking the
# highlight, the part's look read from the cell's looks. An effect's texture (fire, glow, a
# particle) is drawn unlit, as its effect is this frame (its controllers run on the CPU). Each
# vertex names its textures, read by index from the cell's (bindless).

import engine

# a vertex of a cell as the prepared file holds it (y up); a billboard's position, normal and
# tangent are along its node's axes (x right, y up, z toward the eye), scaled, from its pivot
pub type CellVertex:
	position Vec3
	normal Vec3
	tangent Vec4   # w: the sign of the bitangent against normal x tangent
	uv Vec2
	color Vec4
	# its look's index in the looks, 0, the alpha under which a texel is dropped, 0; an effect's:
	# its index in the effects, 1 for a particle (0 for a mesh), the cutout, 1 (2 when its light adds up)
	material Vec4
	diffuse i32   # the cell's texture
	normalMap i32   # an effect's: its palette
	billboard i32   # the billboard it turns with, -1 none

# A placed billboard node: where it stands and its mode (w), and the axis it turns about (its
# node's y for a mode that rotates about up, its z for Bethesda's).
pub type Billboard:
	pivot Vec4
	axis Vec4

# An effect as it is this frame: its UV's offset and scale; its base color (its alpha times the
# alpha's); where its falloff starts and stops (cosines of the angle to the eye) and the
# opacities there; its palette's use (1 its color read through it, + 2 its alpha), its scale,
# and 1 when the vertex colors' alpha, and their color, are read.
pub type EffectState:
	uv Vec4
	color Vec4
	falloff Vec4
	palette Vec4
	lighting Vec4   # how far its light colors it, its soft depth (0 none), its clamp mode, 1 when
	# that light is its reference's emittance source's

# a placed light: where, how far it reaches, its color times its fade
pub type PointLight:
	place Vec4   # x, y, z, radius
	color Vec4
	# its flicker's period in seconds, how far it takes the intensity (0..1) and how far it moves
	# the light; 1 when the light casts shadows
	flicker Vec4

pub type CellParams:
	projection Mat4
	view Mat4
	eye Vec4
	ambient Vec4[6]   # from +x, -x, +y, -y, +z, -z
	sunColor Vec4
	sunToward Vec4   # the direction toward the cell's directional light
	fogNearColor Vec4
	fogFarColor Vec4
	fog Vec4   # near, far, power, max
	right Vec4   # the camera's right and up
	up Vec4
	emittance Vec4 = Vec4(1.0, 1.0, 1.0, 1.0)   # the color the cell's emittance source gives now
	# an actor's part (actor.gpu.zap): its look, its cutout; its textures
	part Look = Look(
		specular = Vec4(0.0, 0.0, 0.0, 1.0),
		emit = Vec4(0.0, 0.0, 0.0, 0.0),
		lighting = Vec4(0.0, 0.0, 0.0, 0.0),
		maps = Vec4(0.0, 0.0, 0.0, 0.0),
		environment = Vec4(0.0, 0.0, 0.0, 0.0)
	)
	partCutout f32 = 0.0
	debugId f32 = 0.0   # 1: each pixel is its part's texture index (red low byte, green high byte), diagnostics only
	normalPass f32 = 0.0   # 1: each pixel is its view-space normal (the occlusion's normal buffer)
	partDiffuse i32 = 0
	partNormalMap i32 = 0
	partTone Vec4 = Vec4(0.0, 0.0, 0.0, 0.0)   # how its skin is toned (nif.toneFace...), its tint and detail maps
	partToneColor Vec4 = Vec4(0.5, 0.5, 0.5, 1.0)   # the skin's tone or the hair's color
	lightCount i32
	shadowCount i32 = 0   # the lights first in `lights` that cast shadows, each its two maps
	shadowLight Vec4 = Vec4(0.0, 0.0, 0.0, 1.0)   # a shadow map's pass: its light, its radius
	shadowSide f32 = 1.0   # the hemisphere drawn: 1 above the light, -1 below
	shadow0 engine.ShadowMap = engine.ShadowMap(id = -1, size = 1)
	shadow1 engine.ShadowMap = engine.ShadowMap(id = -1, size = 1)
	shadow2 engine.ShadowMap = engine.ShadowMap(id = -1, size = 1)
	shadow3 engine.ShadowMap = engine.ShadowMap(id = -1, size = 1)
	shadow4 engine.ShadowMap = engine.ShadowMap(id = -1, size = 1)
	shadow5 engine.ShadowMap = engine.ShadowMap(id = -1, size = 1)
	shadow6 engine.ShadowMap = engine.ShadowMap(id = -1, size = 1)
	shadow7 engine.ShadowMap = engine.ShadowMap(id = -1, size = 1)
	# the sun's cascaded shadow maps (sunshadow.gpu.zap): the cascades, the matrix of each taking a
	# place to its map (clip space: x and y -1..1, z -1..1 over the light's depth), where each ends and
	# starts in view depth, the bias of the first and of the others (in depth over the light's), the
	# shadow distance squared, the cascade a pass draws
	sunShadowCount i32 = 0
	sunCascade i32 = 0
	sunProjection0 Mat4 = Mat4(
		m = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]
	)
	sunProjection1 Mat4 = Mat4(
		m = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]
	)
	sunProjection2 Mat4 = Mat4(
		m = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]
	)
	sunEnds Vec4 = Vec4(0.0, 0.0, 0.0, 0.0)
	sunStarts Vec4 = Vec4(0.0, 0.0, 0.0, 0.0)
	sunBias Vec4 = Vec4(0.0, 0.0, 0.0, 0.0)
	sunShadowDistance2 f32 = 1.0
	sunShadow0 engine.ShadowMap = engine.ShadowMap(id = -1, size = 1)
	sunShadow1 engine.ShadowMap = engine.ShadowMap(id = -1, size = 1)
	sunShadow2 engine.ShadowMap = engine.ShadowMap(id = -1, size = 1)
	# the opaque parts' depths over 7000 in green (occlusion.gpu.zap's key), for soft effects
	depthKey engine.Texture = engine.Texture(id = -1, width = 1, height = 1)
	lights PointLight[]
	billboards Billboard[]
	effects EffectState[]
	looks Look[]
	textures engine.Texture[]   # the cell's, read by index (an actor's program: the actor's)

pub type CellPoint:
	world Vec3
	normal Vec3
	tangent Vec4
	uv Vec2
	color Vec4
	material Vec4
	diffuse i32
	normalMap i32

# A billboard node's axes this frame (x, y, z as columns): its z toward the eye, its y the camera's
# up (facing modes), its axis (turning about up), or its z kept (Bethesda's: turning in its plane).
fn billboardAxes(b Billboard, p CellParams) Mat3:
	mode = i32(b.pivot.w)
	toEye = p.eye.xyz - b.pivot.xyz
	if mode == 1 or mode == 9:
		up = b.axis.xyz
		back = (toEye - up * (toEye @ up)).normalized()
		return Mat3(up.cross(back), up, back)
	if mode == 5:
		back = b.axis.xyz
		up = (p.up.xyz - back * (p.up.xyz @ back)).normalized()
		return Mat3(up.cross(back), up, back)
	if mode == 3 or mode == 4:
		back = toEye.normalized()
		right = p.up.xyz.cross(back).normalized()
		return Mat3(right, back.cross(right), back)
	Mat3(p.right.xyz, p.up.xyz, p.right.xyz.cross(p.up.xyz))

# where a vertex is this frame, its normal and tangent: a billboard's turned with its node
fn placed(v CellVertex, p CellParams) (Vec3, Vec3, Vec4):
	if v.billboard < 0:
		return (v.position, v.normal, v.tangent)
	b = p.billboards[v.billboard]
	axes = billboardAxes(b, p)
	(b.pivot.xyz + axes @ v.position, axes @ v.normal, (axes @ v.tangent.xyz).withW(v.tangent.w))

pub fn cellVertex(v CellVertex, p CellParams) (Vec4, CellPoint):
	world, normal, tangent = placed(v, p)
	(p.projection @ p.view @ world.withW(1.0), CellPoint(
		world,
		normal,
		tangent,
		uv = v.uv,
		color = v.color,
		material = v.material,
		diffuse = v.diffuse,
		normalMap = v.normalMap))

# the normal n bent by a normal map's texel along the ways its u (t) and v (bt) run, its z made
# again from x and y, so two-channel maps serve too
pub fn bentBy(n Vec3, t Vec3, bt Vec3, map Vec4) Vec3:
	xy = map.xy * 2.0 - Vec2(1.0, 1.0)
	z = (1.0 - (xy @ xy).min(1.0)).sqrt()
	(t * xy.x + bt * xy.y + n * z).normalized()

# The vertex normal bent by the normal map. A two-sided part's back is not turned toward the eye:
# lit as its front faces, as the game's (the inn's hanging herbs show their backs dark).
fn bentNormal(b CellPoint, map Vec4) Vec3:
	n = b.normal.normalized()
	t = (b.tangent.xyz - n * (n @ b.tangent.xyz)).normalized()
	bentBy(n, t, n.cross(t) * b.tangent.w, map)

# A soft effect's share where it meets the opaque parts behind it (Effect.hlsl's SOFT): faded in
# over `depth` units of the gap between them; all of it when `depth` is 0.
fn softness(world Vec3, depth f32, p CellParams) f32:
	if depth <= 0.0:
		return 1.0
	seen = p.view @ world.withW(1.0)
	clip = p.projection @ seen
	uv = Vec2(clip.x / clip.w * 0.5 + 0.5, clip.y / clip.w * 0.5 + 0.5)   # a target's rows upward, as the occlusion reads them
	behind = p.depthKey.sampleLevel(uv, 0.0).g * 7000.0
	((behind + seen.z) / depth).clamp(0.0, 1.0)

# uv kept inside the texture's outer texels on the axes the effect's clamp mode clamps (0 both, 1 u,
# 2 v, 3 none), so the wrapping sampler never blends in the far edge
fn clampedUv(uv Vec2, size IVec2, mode f32) Vec2:
	half = Vec2(0.5 / f32(size.x), 0.5 / f32(size.y))
	u = uv.x.clamp(half.x, 1.0 - half.x) if mode < 1.5 else uv.x
	v = uv.y.clamp(half.y, 1.0 - half.y) if mode < 0.5 or (mode > 1.5 and mode < 2.5) else uv.y
	Vec2(u, v)

# a palette's color at u along row v: its largest level, its ends not wrapped into each other
fn paletteAt(palette engine.Texture, u f32, v f32) Vec4:
	half = 0.5 / f32(palette.size().x)
	palette.sampleLevel(Vec2(u.clamp(half, 1.0 - half), v), 0.0)

# An effect (the vanilla BSEffectShader, Community Shaders' Effect.hlsl): its texture times its
# base color and the vertex color; through its palette where it has one, the color the palette's
# at the texture's green (brightened by its scale) and the alpha at its alpha, the row each picked
# by that product's red or alpha in place of multiplying. A lit one's color is taken that far
# toward itself times the cell's light there; then the fog (light that adds up only dimmed).
# Its opacity goes from the falloff's start to its stop as the surface turns from facing the eye
# to edge on; light that adds up is weighed by its alpha here (the blending adds it whole).
fn effectPixel(b CellPoint, p CellParams, toEye Vec3) Vec4:
	e = p.effects[i32(b.material.x + 0.5)]
	t = p.textures[b.diffuse].sample(
		clampedUv(b.uv * e.uv.zw + e.uv.xy, p.textures[b.diffuse].size(), e.lighting.z)
	)
	# a particle always takes its color and alpha (Effect.hlsl's VC, which particles are drawn with),
	# a mesh as its flags say
	particle = b.material.y > 0.5
	vertex = b.color.rgb if e.palette.w > 0.5 or particle else Vec3(1.0, 1.0, 1.0)
	tint = e.color * vertex.withW(b.color.a if e.palette.z > 0.5 or particle else 1.0)
	mode = e.palette.x
	palette = p.textures[b.normalMap]
	rgb = t.rgb * tint.rgb
	if (mode > 0.5 and mode < 1.5) or mode > 2.5:
		rgb = paletteAt(palette, t.g, tint.r).rgb * e.palette.y
	f = e.falloff
	facing = (b.normal.normalized() @ toEye).abs()
	opacity = f.w.lerp(f.z, ((facing - f.y) / (f.x - f.y).max(0.001)).clamp(0.0, 1.0))
	# Effect.hlsl: the falloff and the soft fade go into the alpha before the palette reads it, so a
	# paletted alpha takes its row from all of them
	seen = tint.a * opacity * softness(b.world, e.lighting.y, p)
	alpha = paletteAt(palette, t.a, seen).a if mode > 1.5 else t.a * seen
	if alpha < b.material.z:
		discard()
	if p.debugId > 0.5:
		if alpha < 0.5:
			discard()
		return idColor(b, 1.0)
	c = rgb.lerp(rgb * emittanceOf(e.lighting.w, p), e.lighting.x)
	if b.material.w > 1.5:
		return (c * (1.0 - fogAmount(b.world, p)) * alpha).withW(alpha)
	fogged(c, b.world, p).withW(alpha)

# the texture's index as a color (diagnostics, compare.zap's error by material): low byte, high byte, kind
fn idColor(b CellPoint, kind f32) Vec4:
	Vec4(f32(b.diffuse % 256) / 255.0, f32(b.diffuse / 256) / 255.0, kind * 0.5, 1.0)

pub fn cellPixel(b CellPoint, p CellParams) Vec4:
	toEye = (p.eye.xyz - b.world).normalized()
	if b.material.w > 0.5:
		return effectPixel(b, p, toEye)
	t = p.textures[b.diffuse].sample(b.uv)
	alpha = t.a * b.color.a
	if alpha < b.material.z:
		discard()
	if p.debugId > 0.5:
		if alpha < 0.5:
			discard()
		return idColor(b, 0.0)
	map = p.textures[b.normalMap].sample(b.uv)
	n = bentNormal(b, map)
	if p.normalPass > 0.5:
		return (p.view @ n.withW(0.0)).xyz.withW(1.0)
	look = p.looks[i32(b.material.x + 0.5)]
	shadows = shadowsAt(b.world, p)
	shaded(t.rgb, b.color.rgb, n, b.world, b.uv, map.a, look, shadows, p).withW(alpha)
