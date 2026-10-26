# A prepared cell on the GPU and drawn into its picture (picture.zap): one vertex buffer and one
# index buffer as they lie in its file, its textures sent with their levels, read by index
# (bindless); the opaque runs first, then the cut-out ones, then the blended and the added with
# the depth only tested, each run culled unless it is two-sided, the particles of each kind after
# its runs. Time runs its effects' controllers and its particle systems.

import engine
import skyrim.nif
import world.shaders

pub type CellScene:
	program engine.Program
	model engine.Model
	indices engine.IndexBuffer
	runs Run[]
	textures engine.GpuTexture[]   # the cell's, whose handles the params read
	params shaders.CellParams
	lights shaders.PointLight[]   # as prepared, before they flicker
	shadows CellShadows
	picture Picture
	effects nif.Effect[]
	emitters Emitter[]
	art SpellArt[]   # the art of the spells, shown where the game puts it
	movables Movable[]   # the doors posed by their sequences (movables.zap)
	movableStates MovableState[]   # by movable
	solidMovables engine.Model   # their solid parts this frame, the one-sided and the two-sided
	twoSidedMovables engine.Model
	emittance Emittance   # the color the externally lit parts take by the weather and hour (setTime)
	shown ArtShown[] = []   # what is drawn this frame
	swarms engine.Swarm[]
	debugIds bool = false   # draws each pixel's texture index instead of its light (main.zap --ids)
	time f32 = 0.0   # seconds since the cell opened
	pinnedDimmers f32[] = []   # the dimmer each light takes in place of its flicker's, 0 for none
	step f32 = 0.0   # the seconds of the last step
	blendedParticles engine.Model   # this frame's quads
	addedParticles engine.Model
	terrainProgram engine.Program   # the landscape's (terrain.zap)
	terrains MeshDraw[] = []   # the landscapes added with addTerrain
	lodProgram engine.Program   # the distant land's and objects' (lod.zap)
	lods MeshDraw[] = []   # the batches added with addLodMesh
	treeProgram engine.Program   # the distant trees' (treeLod.zap)
	treeDraws MeshDraw[] = []   # the batches added with addTreeMesh
	water WaterSet   # the water planes and their passes (water.zap)
	grass GrassSet   # the grass and its program (grass.zap)
	skyDraw SkyDraw? = none   # the exterior's sky drawn behind everything (skyScene.zap)
	sunShadows SunShadows? = none   # the sun's cascaded maps, made when the sun is up (sunShadow.zap)
	sky Sky? = none   # the sky of this frame
	skyScale f32 = 1.0
	skyDays f32 = 0.0

# a spell's art drawn this frame: its index among the scene's, and where its model's space is in
# the cell's (y up)
pub type ArtShown:
	art i64
	place Mat4

# the lights kept dormant beyond the cell's, for the art that gives one (a hand's casting)
artLights = 2

pub tiled = engine.Sampling(
	smooth = true,
	mipmaps = true,
	repeat = true,
	mirror = 0,
	anisotropy = true
)

# a prepared texture sent to the GPU with its levels
pub fn gpuTexture(body u8[], t PreparedTexture) engine.GpuTexture:
	mips = []
	for s in t.levels[1..]:
		mips.push(body.bytesAt(s).copy())
	engine.newTextureOfFormat(
		t.width,
		t.height,
		body.bytesAt(t.levels[0]),
		tiled,
		format = t.format,
		mips = mips
	)

fn gray(c Vec3):
	c.withW(1.0)

# the cell's light as the pixel stage reads it, the eye and the view set each frame
fn paramsOf(h CellHead, textures engine.GpuTexture[]):
	l = h.light
	lights = h.lights.copy()
	lights.extend(fill(artLights, shaders.PointLight(place = Vec4(0.0, 0.0, 0.0, 1.0),
		color = Vec4(0.0, 0.0, 0.0, 1.0), flicker = Vec4(0.0, 0.0, 0.0, 0.0))))
	ambient Vec4[6]
	for i in 0..6:
		ambient[i] = l.ambient[i].gray() if i < l.ambient.len else Vec4(0.0, 0.0, 0.0, 1.0)
	shaders.CellParams(
		projection = Mat4(1.0),
		view = Mat4(1.0),
		eye = Vec4(0.0, 0.0, 0.0, 1.0),
		ambient,
		# the lighting shader's DirLightColor is the light times the image space's sunlight scale
		# (0x141549550; FarmInteriorIS's 1.5, as the captures' constant buffers hold it)
		sunColor = (l.sunColor * h.imageSpace.sunlightScale).gray(),
		sunToward = l.sunToward.withW(0.0),
		fogNearColor = l.fogNearColor.gray(),
		fogFarColor = l.fogFarColor.gray(),
		fog = Vec4(l.fogNear, l.fogFar, l.fogPower, l.fogMax),
		right = Vec4(1.0, 0.0, 0.0, 0.0),
		up = Vec4(0.0, 1.0, 0.0, 0.0),
		lightCount = i32(h.lights.len),
		lights,
		billboards = h.billboards.copy(),
		effects = h.effects.map(.effectState(0.0)),
		looks = h.surfaces.map(surfaceLook(it, h.textureKeys)),
		textures = textures.map(.texture())
	)

# the prepared cell's vertices, indices and textures sent to the GPU as they lie in its file
pub fn newCellScene(h CellHead, file engine.Prepared) CellScene:
	body = file.bodyOf()
	program = engine.newProgram(shader(shaders.cellVertex, shaders.cellPixel))
	model = engine.newModel(body.bytesAt(h.vertices), program.vertexStride)
	indices = engine.newIndexBuffer(body.bytesAt(h.indices))
	textures = h.textures.map(gpuTexture(body, it))
	params = h.paramsOf(textures)
	shadows = newCellShadows(h.lights)
	params.useShadows(shadows)
	scene = CellScene(
		program,
		model,
		indices,
		runs = h.runs.copy(),
		textures,
		params,
		lights = h.lights.copy(),
		shadows,
		picture = h.imageSpace.newPicture(),
		effects = h.effects.copy(),
		emitters = h.emitters.copy(),
		art = h.spellArt.copy(),
		movables = h.movables.map(.copy()),
		movableStates = fill(h.movables.len, MovableState()),
		solidMovables = engine.newDynamicModel(),
		twoSidedMovables = engine.newDynamicModel(),
		emittance = h.emittance.copy(),
		swarms = (0..h.emitters.len).map(engine.newSwarm(it + 1)),
		blendedParticles = engine.newDynamicModel(),
		addedParticles = engine.newDynamicModel(),
		terrainProgram = newTerrainProgram(),
		lodProgram = newLodProgram(),
		treeProgram = newTreeProgram(),
		water = newWaterSet(),
		grass = newGrassSet()
	)
	scene.setTime(capturedWeather, startHour)
	# the fires have burned a while when the cell opens
	loop 60:
		scene.advance(1.0 / 30.0)
	scene

# the hour a new game starts at (Skyrim.esm's GLOB GameHour)
pub startHour f32 = 8.0

# the light the scene's externally lit parts take with this weather outside at this game hour
pub fn setTime(mut sc CellScene, weather i64, hour f32):
	sc.params.emittance = sc.emittance.emittanceAt(weather, hour).withW(1.0)

fn pinnedDimmer(sc CellScene, k i64):
	sc.pinnedDimmers[k] if k < sc.pinnedDimmers.len else 0.0

# the scene `dt` seconds on: its particles run, its effects as they are then
pub fn advance(mut sc CellScene, dt f32):
	sc.time += dt
	sc.step = dt
	for k, e in sc.emitters:
		sc.swarms[k].runSwarm(e, sc.time, dt)
	sc.advanceMovables(dt)
	sc.stepSky(dt)
	sc.advanceWater(dt)
	sc.advanceGrass(dt)
	sc.params.effects = sc.effects.map(.effectState(sc.time))
	for k, l in sc.lights:
		sc.params.lights[k] = l.flickered(sc.time, k, sc.pinnedDimmer(k))

# the index of the art of this ARTO or PROJ, none when the cell has none
pub fn artOf(sc CellScene, form i64) i64?:
	for k, a in sc.art:
		if a.form == form: return k
	none

# the art drawn this frame with its model's space at `place` in the cell's
pub fn showArt(mut sc CellScene, art i64, place Mat4):
	sc.shown.push(ArtShown(art, place))

# a vertex of the art's model moved to where it is shown
fn movedBy(v shaders.CellVertex, place Mat4):
	shaders.CellVertex(
		position = place.applyPoint(v.position),
		normal = place.applyDirection(v.normal).normalized(),
		tangent = place.applyDirection(v.tangent.xyz).normalized().withW(v.tangent.w),
		uv = v.uv,
		color = v.color,
		material = v.material,
		diffuse = v.diffuse,
		normalMap = v.normalMap,
		billboard = v.billboard
	)

# the shown art's triangles with the particles', the lit parts with the blended
fn fillArt(sc CellScene, mut blended shaders.CellVertex[], mut added shaders.CellVertex[]):
	for s in sc.shown:
		for part in sc.art[s.art].parts:
			for v in part.vertices:
				if part.kind == .Added:
					added.push(v.movedBy(s.place))
				else:
					blended.push(v.movedBy(s.place))

# the lights the shown art gives set after the cell's
fn placeArtLights(mut sc CellScene):
	base = sc.lights.len
	count = 0
	for s in sc.shown:
		light = sc.art[s.art].light ?? continue
		if count >= artLights: break
		at = s.place.applyPoint(Vec3(0.0, 0.0, 0.0))
		placed = shaders.PointLight(place = at.withW(light.place.w), color = light.color,
			flicker = light.flicker)
		sc.params.lights[base + count] = placed.flickered(sc.time, base + count, 0.0)
		count += 1
	sc.params.lightCount = i32(base + count)

# the particles' quads facing the camera this frame, the blended's and the added's
fn fillParticles(mut sc CellScene):
	blended = []
	added = []
	right = sc.params.right.xyz
	up = sc.params.up.xyz
	for k, e in sc.emitters:
		if e.added:
			sc.swarms[k].swarmQuads(e, right, up, added)
		else:
			sc.swarms[k].swarmQuads(e, right, up, blended)
	sc.fillArt(blended, added)
	solid = []
	twoSided = []
	sc.fillMovables(solid, twoSided, blended, added)
	sc.solidMovables.fillModel(solid)
	sc.twoSidedMovables.fillModel(twoSided)
	sc.blendedParticles.fillModel(blended)
	sc.addedParticles.fillModel(added)

fn drawKind(mut r engine.Renderer, sc CellScene, kind Kind, depthWrite bool):
	for run in sc.runs:
		if run.kind != kind: continue
		r.setDepth(true, depthWrite, not run.twoSided)
		r.drawIndexed(sc.program, sc.model, sc.indices, run.count, firstIndex = run.first)

# The cell seen from `eye` on a screen of w x h pixels, its opaque and cut out parts drawn into
# its picture's HDR target cleared to the fog's color: what else is opaque (the actors) is drawn
# next, then finishCell.
pub fn drawCell(
	mut r engine.Renderer,
	mut sc CellScene,
	w i64,
	h i64,
	projection Mat4,
	view Mat4,
	eye Vec3
):
	sc.fitSunShadows(projection, view)
	r.drawSunShadowMaps(sc)
	r.drawShadowMaps(sc)
	sc.picture.fitPicture(w, h)
	r.useTarget(sc.picture.scene)
	r.clearTarget(sc.params.fogFarColor)
	r.drawSkyBehind(sc, projection, view)
	sc.params.projection = projection
	sc.params.view = view
	sc.params.eye = eye.withW(1.0)
	sc.params.debugId = 1.0 if sc.debugIds else 0.0
	toWorld = view.inverseAffine()
	sc.params.right = toWorld.applyDirection(Vec3(1.0, 0.0, 0.0)).normalized().withW(0.0)
	sc.params.up = toWorld.applyDirection(Vec3(0.0, 1.0, 0.0)).normalized().withW(0.0)
	sc.placeArtLights()
	sc.program.setParams(sc.params)
	sc.fillParticles()
	sc.shown = []
	r.setBlending(false)
	r.drawKind(sc, .Opaque, true)
	r.drawKind(sc, .Tested, true)
	r.drawMovables(sc)
	r.drawTerrains(sc)
	r.drawLods(sc)
	r.drawTrees(sc)
	r.drawGrass(sc, false)

# the movables posed this frame: the one-sided parts culled, the two-sided not
fn drawMovables(mut r engine.Renderer, sc CellScene):
	r.setDepth(true, true, true)
	r.drawModel(sc.program, sc.solidMovables)
	r.setDepth(true, true, false)
	r.drawModel(sc.program, sc.twoSidedMovables)

# the opaque and cut out parts' view-space normals, the normal buffer the occlusion reads
fn drawNormals(mut r engine.Renderer, mut sc CellScene):
	r.useTarget(sc.picture.occlusion.normals)
	r.clearTarget(Vec4(0.0, 0.0, 0.0, 0.0))
	sc.params.normalPass = 1.0
	sc.program.setParams(sc.params)
	r.setBlending(false)
	r.drawKind(sc, .Opaque, true)
	r.drawKind(sc, .Tested, true)
	r.drawMovables(sc)
	r.drawTerrains(sc)
	r.drawLods(sc)
	r.drawTrees(sc)
	r.drawGrass(sc, true)
	sc.params.normalPass = 0.0
	sc.program.setParams(sc.params)

# The ambient occlusion of what drawCell and the actors left, then the cell's see-through parts
# and particles drawn over it, then the picture graded onto the screen.
pub fn finishCell(mut r engine.Renderer, mut sc CellScene):
	if sc.debugIds:
		r.drawIds(sc)
		return
	r.drawNormals(sc)
	r.drawOcclusion(
		sc.picture.occlusion,
		sc.picture.scene,
		sc.params.projection,
		sc.picture.previousView @ sc.picture.view.inverseAffine()
	)
	r.drawWaters(sc)
	sc.params.depthKey = sc.picture.occlusion.rawNow()
	sc.program.setParams(sc.params)
	r.setBlendMode(.Alpha)
	r.drawKind(sc, .Blended, false)
	r.setDepth(true, false, false)
	r.drawModel(sc.program, sc.blendedParticles)
	r.drawFalling(sc)
	r.setBlendMode(.Add)
	r.drawKind(sc, .Added, false)
	r.setDepth(true, false, false)
	r.drawModel(sc.program, sc.addedParticles)
	r.setBlending(false)
	r.drawPicture(sc.picture, sc.step)
	r.setDepth(true, true, false)

# the picture of ids: the see-through parts and particles drawn opaque over the rest, the target onto
# the screen as it is (no occlusion, no grading, no smoothing)
fn drawIds(mut r engine.Renderer, mut sc CellScene):
	sc.program.setParams(sc.params)
	r.setBlending(false)
	r.drawKind(sc, .Blended, true)
	r.drawModel(sc.program, sc.blendedParticles)
	r.drawKind(sc, .Added, true)
	r.drawModel(sc.program, sc.addedParticles)
	r.useScreen()
	r.drawScreenPass(
		sc.picture.resolved,
		shaders.Resolved(picture = sc.picture.scene.colorTexture())
	)
	r.setDepth(true, true, false)
