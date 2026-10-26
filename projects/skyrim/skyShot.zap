# The sky over Riverwood drawn headless from the executable's colors: the weather's sky, sun and
# clouds, the land lit by the hour's sun and ambient and fogged by the weather's fog, saved as a
# picture (no grading: the image space's pass is the scene's). Run from the repository root:
#
#   zap run projects/skyrim/skyShot.zap --hour 7.5 --yaw 90 --pitch 8 --shot morning.png
#   zap run projects/skyrim/skyShot.zap --hour 12 --shot noon.png
#   zap run projects/skyrim/skyShot.zap --hour 23 --pitch 40 --shot night.png
#   zap run projects/skyrim/skyShot.zap --hour 12 --weather SkyrimOvercastRain --last SkyrimClear --share 0.5 --pitch 20 --shot transition.png
#   zap run projects/skyrim/skyShot.zap --hour 23 --days 5.354 --yaw 98 --pitch 46 --shot moons.png
#   zap run projects/skyrim/skyShot.zap --hour 14 --weather SkyrimStormRain --seconds 2 --shot rain.png
#   zap run projects/skyrim/skyShot.zap --hour 10 --objects --yaw 20 --pitch -22 --above 1400 --shot shadows.png
#
#   needs: projects/skyrim/assets/game (fetch.zap)

import engine
import skyrim
import skyrim.nif
import skyrim.esm
import game
import image
import math
import world
import world.shaders

tamriel = 0x3C

# the models --objects stands on the land, each at a place in the game's units east and north of
# the arrival, turned by its yaw in degrees
objectModels = [
	"architecture/whiterun/wrbuildings/wrbreezehome01.nif",
	"landscape/trees/treepineforest01.nif",
	"landscape/trees/treepineforest02.nif",
	"landscape/trees/treepineforest03.nif"
]
# where the character arrives outside the Sleeping Giant Inn, in game units
arrival = Vec3(23259.771, -44476.164, 0.0)

pub type Objects:
	model engine.Model
	indices engine.IndexBuffer
	count i64
	program engine.Program

pub type Placed:
	model i64
	at Vec3
	yaw f32

objectPlaces = [
	Placed(0, Vec3(900.0, 2600.0, 0.0), 30.0),
	Placed(1, Vec3(300.0, 1500.0, 0.0), 0.0),
	Placed(2, Vec3(-900.0, 2100.0, 0.0), 70.0),
	Placed(3, Vec3(1700.0, 1700.0, 0.0), 120.0),
	Placed(1, Vec3(-300.0, 3300.0, 0.0), 200.0),
	Placed(2, Vec3(2400.0, 2900.0, 0.0), 310.0),
	Placed(3, Vec3(-1500.0, 1200.0, 0.0), 40.0)
]

# the objects' triangles in the renderer's axes (y up), one vertex list and its indices, standing on
# the land with the white and the flat-normal textures of the params
fn objectMesh(
	install skyrim.Install,
	t game.Terrain,
	white i32,
	flat i32
):
	vertices = []
	indices = []
	for o in objectPlaces:
		key = skyrim.modelKey(objectModels[o.model])
		model = install.readModel(key) ?? fail("no {key}")
		at = arrival + o.at
		ground = t.heightAt(at.x, at.y) ?? 0.0
		turn = o.yaw.radians()
		for part in model.drawParts():
			first = u32(vertices.len)
			for k in 0..part.positions.len:
				local = part.positions[k]
				game = Vec3(
					at.x + local.x * turn.cos() - local.y * turn.sin(),
					at.y + local.x * turn.sin() + local.y * turn.cos(),
					ground + local.z
				)
				n = part.normals[k] if k < part.normals.len else Vec3(0.0, 0.0, 1.0)
				normal = Vec3(
					n.x * turn.cos() - n.y * turn.sin(),
					n.x * turn.sin() + n.y * turn.cos(),
					n.z
				)
				up = Vec3(normal.x, normal.z, -normal.y)
				across = Vec3(0.0, 1.0, 0.0) if up.y.abs() < 0.9 else Vec3(1.0, 0.0, 0.0)
				vertices.push(
					shaders.CellVertex(
						position = Vec3(game.x, game.z, -game.y),
						normal = up,
						tangent = up.cross(across).normalized().withW(1.0),
						uv = part.uvs[k] if k < part.uvs.len else Vec2(0.0, 0.0),
						color = Vec4(0.6, 0.6, 0.6, 1.0),
						material = Vec4(0.0, 0.0, 0.0, 0.0),
						diffuse = white,
						normalMap = flat,
						billboard = -1
					)
				)
			for i in part.indices:
				indices.push(first + i)
	(vertices, indices)

fn namedWeather(mut plugin esm.Esm, name str):
	form = plugin.formByEditorId("WTHR", name) ?? fail("no weather {name}")
	plugin.weatherOf(form) ?? fail("not a weather")

args.options(
	[
		skyrim.installOption,
		ArgOption("--hour", true, "the game hour (12)"),
		ArgOption("--weather", true, "the weather's editor id (SkyrimClear)"),
		ArgOption("--last", true, "the weather giving way, with --share its remainder"),
		ArgOption("--share", true, "how far the weather has come in (1)"),
		ArgOption("--days", true, "the game days passed, for the moons (the hour's share of a day)"),
		ArgOption("--seconds", true, "how long the rain or snow has fallen (0)"),
		ArgOption("--yaw", true, "degrees from north, clockwise (0)"),
		ArgOption("--pitch", true, "degrees up (12)"),
		ArgOption("--above", true, "the eye's height over the land (170)"),
		ArgOption("--unshadowed", false, "with --objects, read no shadows"),
		ArgOption("--objects", false, "stand the game's houses and pines about the eye, casting the sun's shadows"),
		ArgOption("--shot", true, "the picture to write")
	]
)
dir = skyrim.installDir()
hour = f32.parse(args.option("--hour") ?? "") ?? 12.0
share = f32.parse(args.option("--share") ?? "") ?? 1.0
days = f32.parse(args.option("--days") ?? "") ?? hour / 24.0
seconds = f32.parse(args.option("--seconds") ?? "") ?? 0.0
yaw = f32.parse(args.option("--yaw") ?? "") ?? 0.0
pitch = f32.parse(args.option("--pitch") ?? "") ?? 12.0
above = f32.parse(args.option("--above") ?? "") ?? 170.0
out = args.option("--shot") ?? fail("give --shot picture.png")
install = skyrim.openInstall(dir) ?? fail
plugin = esm.openEsm(esm.pluginPath(dir, "Skyrim.esm")) ?? fail

current = plugin.namedWeather(args.option("--weather") ?? "SkyrimClear")
last = none
if args.option("--last") is name: last = plugin.namedWeather(name)
climate = plugin.climateOf(plugin.worldClimate(tamriel) ?? fail("no climate")) ?? fail("no climate")
mut sky = world.skyAt(
	current,
	last,
	climate,
	world.SkyTime(hour, share = share if last != none else 1.0, extension = 0.5)
)
settings = plugin.gameSettings()
sky.moons = world.moonsAt(
	climate,
	world.moonSettings("Masser", world.masserDefaults(), settings),
	world.moonSettings("Secunda", world.secundaDefaults(), settings),
	(days * 24.0 - world.startHour).max(0.0),
	i64(days),
	sky.starsAlpha
)
currentSpec = plugin.precipitationOf(current.precipitation)
lastSpec = none
if last is l: lastSpec = plugin.precipitationOf(l.precipitation)
sky.precipitation = current.precipitationsOf(
	currentSpec,
	last,
	lastSpec,
	share if last != none else 1.0
)
spaces = []
weights = []
for k, form in sky.imageSpaces:
	if plugin.imageSpaceOf(form) is s:
		spaces.push(s)
		weights.push(sky.imageWeights[k])
space = esm.mixedSpaces(spaces, weights)
print("{current.editorId} at {hour}: sun toward {sky.sunToward}, daylight {sky.daylight}, sunlight scale {space.sunlightScale}, sky scale {space.skyScale}")

t = install.terrainOf(plugin, tamriel, 4, -12, 6, -10)
width = 1280
height = 720
mut frames = engine.newFrames()
mut win = engine.openWindow("Skyrim sky", width, height)
mut r = engine.newRenderer()
depth = engine.newDepthTarget(width, height)
cloudPaths = current.layers.map(.texture.copy())
if last is l: cloudPaths.extend(l.layers.map(.texture.copy()))
precipitations = []
if currentSpec is p: precipitations.push(p.copy())
if lastSpec is p: precipitations.push(p.copy())
sd = install.skyDrawing(cloudPaths, precipitations, climate)
loop i64(seconds * 30.0):
	sd.advanceSky(sky, 1.0 / 30.0)

program = world.newTerrainProgram()
textures = t.textures.map(world.gpuTexture(t.body, it))
handles = textures.map(.texture())
objects = args.hasFlag("--objects")
# the objects' two textures follow the land's: a white one and a flat normal map
whiteTexture = image.fromBytes(1, 1, [255, 255, 255, 255]).newTexture()
flatTexture = image.fromBytes(1, 1, [128, 128, 255, 255]).newTexture()
handles.push(whiteTexture.texture())
handles.push(flatTexture.texture())
draw = world.newTerrainDraw(t.vertices, t.indices, textures)
ground = t.heightAt(arrival.x, arrival.y) ?? 0.0
# the renderer's y is up: the game's (x, y, z) is (x, z, -y)
eye = Vec3(arrival.x, ground + above, -arrival.y)
view = Mat4.lookAlong(eye, Vec3.lookDirection(yaw.radians(), pitch.radians()))
projection = Mat4.perspective(f32(65.0).radians(), f32(width) / f32(height), 50.0, 200000.0)
ambient Vec4[6]
params = shaders.CellParams(
	projection,
	view,
	eye = eye.withW(1.0),
	ambient,
	sunColor = Vec4(0.0, 0.0, 0.0, 1.0),
	sunToward = Vec4(0.0, 1.0, 0.0, 0.0),
	fogNearColor = Vec4(0.0, 0.0, 0.0, 1.0),
	fogFarColor = Vec4(0.0, 0.0, 0.0, 1.0),
	fog = Vec4(0.0, 1.0, 1.0, 1.0),
	right = Vec4(1.0, 0.0, 0.0, 0.0),
	up = Vec4(0.0, 1.0, 0.0, 0.0),
	lightCount = 0,
	lights = [],
	billboards = [],
	effects = [],
	looks = [],
	textures = handles.copy()
)
params.lightBy(sky, space)
params.looks = [
	shaders.Look(
		specular = Vec4(0.0, 0.0, 0.0, 1.0),
		emit = Vec4(0.0, 0.0, 0.0, 0.0),
		lighting = Vec4(0.0, 0.0, 0.0, 0.0),
		maps = Vec4(0.0, 0.0, 0.0, 0.0),
		environment = Vec4(0.0, 0.0, 0.0, 0.0)
	)
]
if not win.nextFrame(frames): fail("the window closed")
standing Objects? = none
# the sun's maps live as long as the frame is drawn (a target frees its textures where it is dropped)
sunShadows = world.newSunShadows()
if objects:
	vertices, indices = install.objectMesh(t, i32(handles.len - 2), i32(handles.len - 1))
	standing = Objects(
		model = engine.newModel(vertices),
		indices = engine.newIndexBuffer(indices),
		count = indices.len,
		program = engine.newProgram(shader(shaders.cellVertex, shaders.cellPixel))
	)
	fit = view.fitSun(projection.m[0], projection.m[5], 50.0, 200000.0, params.sunToward.xyz)
	params.useSunShadows(sunShadows, fit)
	cascadeParams = params.copy()
	if args.hasFlag("--unshadowed"): params.sunShadowCount = 0
	r.setBlending(false)
	r.setDepthBias(true)
	for k in 0..world.cascadeCount:
		r.useTarget(sunShadows.maps[k])
		r.clearTarget(engine.white)
		r.setDepth(true, true, false)
		cascadeParams.sunCascade = k
		sunShadows.program.setParams(cascadeParams)
		if standing is o: r.drawIndexed(sunShadows.program, o.model, o.indices, o.count)
	r.setDepthBias(false)
program.setParams(params)
r.useScreenWithDepth(depth)
r.clearTarget(params.fogFarColor)
r.drawSky(sd, sky, projection, view, space.skyScale, 0.0)
r.setBlending(false)
r.setDepth(true, true, true)
r.drawIndexed(program, draw.model, draw.indices, draw.indices.count)
if standing is o:
	o.program.setParams(params)
	r.setDepth(true, true, false)
	r.drawIndexed(o.program, o.model, o.indices, o.count)
r.drawPrecipitation(sd, sky, projection, view, width, height)
r.screenshot().savePng(out) ?? fail("cannot write {out}")
print("wrote {out}")
