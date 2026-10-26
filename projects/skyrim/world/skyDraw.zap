# The sky on the GPU and drawn behind the world: the atmosphere dome, the stars, the sun and its
# glare, and the cloud layers, each a mesh of the game's own (Meshes\Sky\Atmosphere.nif, Stars.nif,
# Clouds.nif) placed about the eye and pushed to the far plane (shaders/sky.gpu.zap), colored by
# the sky of the hour (sky.zap). The way in: newSkyDraw (game/sky.zap reads the files), then each
# frame advanceSky and, first after the clear, drawSky.

import engine
import skyrim.esm
import skyrim.nif
import world.shaders

# one mesh of a sky object: its vertices and triangles and the texture it names
pub type SkyMesh:
	model engine.Model
	indices engine.IndexBuffer
	count i64
	texture str   # the archive key of its texture, "" for none

# the sky on the GPU
pub type SkyDraw:
	program engine.Program
	dome SkyMesh
	clouds SkyMesh[]   # shape k is weather layer k
	stars SkyMesh[]
	quad SkyMesh   # the sun's and the glare's: a square about the origin facing +z
	textures engine.GpuTexture[]
	slots {str: i64}   # an archive key -> its place in `textures`
	sunTexture str
	glareTexture str
	scroll Vec2[]   # each cloud layer's texture offset so far
	time f32 = 0.0
	precipProgram engine.Program
	precipMeshes {str: PrecipitationMesh}   # by the precipitation's editor id
	precipOffsets Vec3[]   # the cube of each precipitation now falling, carried so far (game axes)
	precipSpins f32[]   # and a snow flake's turn

# the game's axes (z up) to the renderer's (y up)
fn yUp(v Vec3):
	Vec3(v.x, v.z, -v.y)

# a sky mesh made of a part of a model; its texture key is the part's
pub fn newSkyMesh(p nif.Part) SkyMesh:
	vertices = []
	for k in 0..p.positions.len:
		vertices.push(
			shaders.SkyVertex(
				position = p.positions[k].yUp(),
				uv = p.uvs[k] if k < p.uvs.len else Vec2(0.0, 0.0),
				color = p.colors[k] if k < p.colors.len else Vec4(1.0, 1.0, 1.0, 1.0)
			)
		)
	SkyMesh(
		model = engine.newModel(vertices),
		indices = engine.newIndexBuffer(p.indices),
		count = p.indices.len,
		texture = nif.textureKey(p.diffuse) if not p.diffuse.isEmpty else ""
	)

# a square of side 2 about the origin, facing +z
pub fn newQuad() SkyMesh:
	corners u32[] = [0, 1, 2, 0, 2, 3]
	vertices = [
		shaders.SkyVertex(position = Vec3(-1.0, -1.0, 0.0), uv = Vec2(0.0, 1.0), color = Vec4(1.0, 1.0, 1.0, 1.0)),
		shaders.SkyVertex(position = Vec3(1.0, -1.0, 0.0), uv = Vec2(1.0, 1.0), color = Vec4(1.0, 1.0, 1.0, 1.0)),
		shaders.SkyVertex(position = Vec3(1.0, 1.0, 0.0), uv = Vec2(1.0, 0.0), color = Vec4(1.0, 1.0, 1.0, 1.0)),
		shaders.SkyVertex(
			position = Vec3(-1.0, 1.0, 0.0),
			uv = Vec2(0.0, 0.0),
			color = Vec4(1.0, 1.0, 1.0, 1.0)
		)
	]
	SkyMesh(
		model = engine.newModel(vertices),
		indices = engine.newIndexBuffer(corners),
		count = 6,
		texture = ""
	)

pub fn newSkyDraw(
	dome nif.Part,
	clouds nif.Part[],
	stars nif.Part[],
	move textures engine.GpuTexture[],
	slots {str: i64},
	sunTexture str,
	glareTexture str,
	precipitations esm.Precipitation[]
) SkyDraw:
	meshes {str: PrecipitationMesh} = {}
	for p in precipitations:
		if p.editorId not in meshes: meshes[p.editorId.copy()] = p.newPrecipitationMesh(1)
	SkyDraw(
		program = engine.newProgram(shader(shaders.skyVertex, shaders.skyPixel)),
		dome = dome.newSkyMesh(),
		clouds = clouds.map(.newSkyMesh()),
		stars = stars.map(.newSkyMesh()),
		quad = newQuad(),
		textures,
		slots = slots.copy(),
		sunTexture = nif.textureKey(sunTexture),
		glareTexture = nif.textureKey(glareTexture),
		scroll = fill(clouds.len, Vec2(0.0, 0.0)),
		precipProgram = engine.newProgram(shader(shaders.precipVertex, shaders.precipPixel)),
		precipMeshes = meshes,
		precipOffsets = fill(precipSlots, Vec3(0.0, 0.0, 0.0)),
		precipSpins = fill(precipSlots, 0.0)
	)

# the sky `dt` seconds on: its clouds scroll
pub fn advanceSky(mut sd SkyDraw, sky Sky, dt f32):
	sd.time += dt
	for k, c in sky.clouds:
		if k < sd.scroll.len: sd.scroll[k] = sd.scroll[k] + c.scroll * (dt * cloudStep)
	for k, n in sky.precipitation:
		if k >= precipSlots: break
		sd.precipOffsets[k] = n.carried(sd.precipOffsets[k], dt)
		sd.precipSpins[k] = (sd.precipSpins[k] + n.spec.rotationVelocity.radians() * dt) % tau

fn textureOf(sd SkyDraw, key str):
	if sd.slots.get(key) is k: return sd.textures[k].texture()
	engine.Texture(id = -1, width = 1, height = 1)

# a matrix from three axes and an origin
fn basis(x Vec3, y Vec3, z Vec3, at Vec3):
	Mat4([x.x, x.y, x.z, 0.0, y.x, y.y, y.z, 0.0, z.x, z.y, z.z, 0.0, at.x, at.y, at.z, 1.0])

# the view without its move: the sky stays about the eye
fn rotationOnly(view Mat4):
	m = view.m
	m[12] = 0.0
	m[13] = 0.0
	m[14] = 0.0
	Mat4(m)

# the square of half-width `half` at `place` from the eye, turned to face it (the sun's billboards)
fn facing(place Vec3, half f32):
	d = place.normalized()
	up = Vec3(0.0, 1.0, 0.0) if d.y.abs() < 0.999 else Vec3(1.0, 0.0, 0.0)
	right = up.cross(d).normalized()
	basis(right * half, d.cross(right) * half, d, place)

# the stars turn about the sky's pole (the game's z) once in fStarsRotateDays days
starsRotateDays f32 = 4.0

# The sun's and its glare's squares as Sun::Init 0x14041b290 builds them: half-widths fSunBaseSize
# and fSunGlareSize in units, on billboards standing where Sun::Update puts the disc (400 units out
# at the horizon and at noon, nearer between: the quad grows as the sun climbs) with scale 1, no node
# above them scaling (a root's scale would carry the disc's place with it, leaving the angles as
# they are). The glare's own scale (0.25 to 1, shrinking as the terrain hides the sun) is the
# occlusion query's and stays 1: nothing hides the sun here.
sunBaseSize f32 = 425.0
sunGlareSize f32 = 600.0
sunGlareMultiplier f32 = 2.0

fn textured(
	sd SkyDraw,
	key str,
	viewProjection Mat4,
	tint Vec4,
	scale f32,
	offset Vec2,
	kind f32
):
	shaders.SkyParams(
		viewProjection,
		horizon = Vec4(0.0, 0.0, 0.0, 1.0),
		lower = Vec4(0.0, 0.0, 0.0, 1.0),
		upper = Vec4(0.0, 0.0, 0.0, 1.0),
		tint,
		offset,
		kind,
		glow = scale,
		texture = sd.textureOf(key)
	)

fn drawSkyMesh(mut r engine.Renderer, sd SkyDraw, mesh SkyMesh, params shaders.SkyParams):
	sd.program.setParams(params)
	r.drawIndexed(sd.program, mesh.model, mesh.indices, mesh.count)

# the moons: each a square of its size facing the eye, drawn added in the moon glare's color (the
# moons' alpha its fade) after the stars it hides
fn drawMoons(mut r engine.Renderer, sd SkyDraw, sky Sky, vp Mat4, scale f32):
	r.setBlendMode(.Add)
	for m in sky.moons:
		if m.alpha <= 0.0: continue
		right = m.place.right.yUp()
		up = m.place.up.yUp()
		axes = basis(right * m.half, up * m.half, right.cross(up), m.place.center.yUp())
		tint = sky.colors[esm.moonGlareColor].withW(m.alpha)
		r.drawSkyMesh(
			sd,
			sd.quad,
			sd.textured(nif.textureKey(m.texture), vp @ axes, tint, scale, Vec2(0.0, 0.0), 3.0)
		)

# The sky of this hour behind everything: the dome, the stars, the glare and the sun, the clouds.
# `scale` is the image space's sky scale, added to the colors (PParams.y of Sky.hlsl); `days` turns
# the stars.
pub fn drawSky(
	mut r engine.Renderer,
	sd SkyDraw,
	sky Sky,
	projection Mat4,
	view Mat4,
	scale f32,
	days f32
):
	vp = projection @ view.rotationOnly()
	r.setDepth(false, false, false)
	r.setBlendMode(.Alpha)
	dome = shaders.SkyParams(
		viewProjection = vp,
		horizon = sky.colors[8].withW(1.0),
		lower = sky.colors[7].withW(1.0),
		upper = sky.colors[0].withW(1.0),
		tint = Vec4(1.0, 1.0, 1.0, 1.0),
		kind = 0.0,
		glow = scale
	)
	r.drawSkyMesh(sd, sd.dome, dome)
	if sky.starsAlpha > 0.0:
		turn = (days % starsRotateDays) / starsRotateDays * tau
		spin = basis(
			Vec3(turn.cos(), 0.0, turn.sin()),
			Vec3(0.0, 1.0, 0.0),
			Vec3(-turn.sin(), 0.0, turn.cos()),
			Vec3(0.0, 0.0, 0.0)
		)
		r.setBlendMode(.Alpha)
		tint = (sky.colors[6] * sky.starsAlpha).withW(1.0)
		for s in sd.stars:
			r.drawSkyMesh(
				sd,
				s,
				sd.textured(s.texture, vp @ spin, tint, scale, Vec2(0.0, 0.0), 1.0)
			)
	r.drawMoons(sd, sky, vp, scale)
	if sky.daylight > 0.0:
		toward = Vec3(sky.sunPlace.x, sky.sunPlace.z, -sky.sunPlace.y)
		r.setBlendMode(.Add)
		if sky.glare > 0.0:
			tint = (sky.colors[15] * sunGlareMultiplier).withW(sky.glare)
			r.drawSkyMesh(
				sd,
				sd.quad,
				sd.textured(
					sd.glareTexture,
					vp @ toward.facing(sunGlareSize),
					tint,
					0.0,
					Vec2(0.0, 0.0),
					3.0
				)
			)
		tint = sky.colors[5].withW(sky.daylight)
		r.drawSkyMesh(
			sd,
			sd.quad,
			sd.textured(
				sd.sunTexture,
				vp @ toward.facing(sunBaseSize),
				tint,
				scale,
				Vec2(0.0, 0.0),
				3.0
			)
		)
	r.setBlendMode(.Alpha)
	for k, c in sky.clouds:
		if k >= sd.clouds.len or c.alpha <= 0.0: continue
		offset = sd.scroll[k] if k < sd.scroll.len else Vec2(0.0, 0.0)
		key = nif.textureKey(c.texture)
		r.drawSkyMesh(
			sd,
			sd.clouds[k],
			sd.textured(key, vp, c.color.withW(c.alpha), scale, offset, 1.0)
		)
	r.setBlending(false)

# The rain or snow falling in this sky, over what is drawn: each precipitation's cube of particles
# about the eye, tested against the depth and written to none. `eye` is the camera's place.
pub fn drawPrecipitation(
	mut r engine.Renderer,
	sd SkyDraw,
	sky Sky,
	projection Mat4,
	view Mat4,
	width i64,
	height i64
):
	if sky.precipitation.isEmpty: return
	eye = view.inverseAffine().applyPoint(Vec3(0.0, 0.0, 0.0))
	r.setBlendMode(.Alpha)
	r.setDepth(true, false, false)
	for k, n in sky.precipitation:
		if k >= precipSlots or n.amount <= 0.0: continue
		mesh = sd.precipMeshes.get(n.spec.editorId) ?? continue
		velocity = n.velocityOf()
		sd.precipProgram.setParams(
			shaders.PrecipParams(
				viewProjection = projection @ view,
				offset = sd.precipOffsets[k].yUp(),
				box = n.spec.boxSize,
				center = eye,
				snow = 1.0 if n.spec.snow else 0.0,
				streak = (velocity * streakShare).yUp(),
				spin = sd.precipSpins[k],
				scaleAdjust = Vec2(f32(height) / f32(width), 1.0),
				texture = sd.textureOf(nif.textureKey(n.spec.texture))
			)
		)
		shown = i64(n.amount * f32(cubeParticles)).min(cubes * cubeParticles)
		r.drawIndexed(sd.precipProgram, mesh.model, mesh.indices, shown * 6)
	r.setBlending(false)
