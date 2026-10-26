# Riverwood's exterior drawn headless as the game draws it, in a cell scene (world/scene.zap): the
# sky of the hour, the land of the loaded cells with its grass (game/grass.zap), the distant land,
# objects, trees and water beyond them (game/lod.zap), and the water of the cells (game/water.zap)
# with its flow map, refraction of the river bed and reflection of the sky; the picture of its
# last frame, graded as the game grades it. Run from the repository root:
#
#   zap run projects/skyrim/waterShot.zap --frames 40 --step 16 --at 21000,-43000 --eye 350 --yaw 260 --pitch -10 --shot river.png
#   zap run projects/skyrim/waterShot.zap --frames 40 --step 16 --at 21700,-44100 --eye 140 --yaw 140 --pitch -12 --shot grass.png
#   zap run projects/skyrim/waterShot.zap --frames 40 --step 16 --hour 18 --yaw 90 --pitch 4 --shot evening.png
#   zap run projects/skyrim/waterShot.zap --frames 40 --step 16 --no-water --no-grass --shot far-land.png
#
#   needs: projects/skyrim/assets/game (fetch.zap)
#   needs: projects/skyrim/assets/prepared (prepare.zap, for the scene's cell)

import engine
import skyrim
import skyrim.esm
import game
import math
import world

tamriel = 0x3C
# where the character arrives outside the Sleeping Giant Inn, in game units
arrival = Vec3(23259.771, -44476.164, 0.0)

args.options(
	[
		skyrim.installOption,
		ArgOption("--hour", true, "the game hour (12)"),
		ArgOption("--at", true, "the eye's x,y in game units (the inn's door)"),
		ArgOption("--eye", true, "the eye over the ground (170)"),
		ArgOption("--yaw", true, "degrees from north, clockwise (0)"),
		ArgOption("--pitch", true, "degrees up (-5)"),
		ArgOption("--no-water", false, "leave the water out"),
		ArgOption("--debug", true, "a diagnostic picture of the water: 1 normals, 2 reflection, 3 refraction, 4 depths"),
		ArgOption("--no-grass", false, "leave the grass out"),
		ArgOption("--no-sky", false, "leave the sky out"),
		ArgOption("--with-cell", false, "keep the inn the scene is made of (far away, but real data)"),
		ArgOption("--no-terrain", false, "leave the near land out"),
		ArgOption("--grass-radius", true, "the cells about the eye that grow grass (2)"),
		ArgOption("--no-lod", false, "leave the distant land, objects, trees and water out"),
		ArgOption("--shot", true, "the picture to write")
	]
)
dir = skyrim.installDir()
hour = f32.parse(args.option("--hour") ?? "") ?? 12.0
yaw = f32.parse(args.option("--yaw") ?? "") ?? 0.0
pitch = f32.parse(args.option("--pitch") ?? "") ?? -5.0
if args.option("--shot") == none: fail("give --shot picture.png")
at = Vec2(arrival.x, arrival.y)
if args.option("--at") is text:
	parts = text.split(",")
	at = Vec2(f32.parse(parts[0]) ?? arrival.x, f32.parse(parts[1]) ?? arrival.y)
install = skyrim.openInstall(dir) ?? fail
mut plugin = esm.openEsm(esm.pluginPath(dir, "Skyrim.esm")) ?? fail
settings = skyrim.readIniSettings()

clock = plugin.openSkyClock(tamriel, at.x, at.y, hour, 7) ?? fail("no sky")
sky = clock.skyAt(hour, 0.0)
space = clock.imageSpaceAt(sky)
tint = sky.colors[14]
print("sky at {hour}: sun toward {sky.sunToward}, daylight {sky.daylight}, water multiplier {tint}")

# the scene: the inn's prepared cell with nothing in it, the exterior put in
loaded, file = world.readCell(
	world.cellPath("riverwoodsleepinggiantinn"),
	args.hasFlag("--with-cell")
) ??
	fail("prepare the inn first: zap run projects/skyrim/prepare.zap")
mut head = loaded
if not args.hasFlag("--with-cell"):
	head.vertices = engine.Span(0, 0)
	head.indices = engine.Span(0, 0)
	head.runs = []
	head.textures = []
	head.lights = []
	head.billboards = []
	head.effects = []
	head.surfaces = []
	head.emitters = []
	head.spellArt = []
	head.movables = []
width = 1280
height = 720
mut frames = engine.newFrames()
mut win = engine.openWindow("Skyrim water", width, height)
mut r = engine.newRenderer()
mut scene = head.newCellScene(file)
cx, cy = esm.gridOf(Vec3(at.x, at.y, 0.0))
area = game.loadedAround(cx, cy, 5)
t = install.terrainOf(plugin, tamriel, cx - 2, cy - 2, cx + 2, cy + 2)
if not args.hasFlag("--no-terrain"):
	scene.showTerrain(t)
if not args.hasFlag("--no-sky"):
	scene.showSky(install.newSkyDrawing(clock))
scene.water.debug = f32.parse(args.option("--debug") ?? "") ?? 0.0
scene.setSky(sky, space, 0.0)
if not args.hasFlag("--no-lod"):
	eyeAt = Vec2(at.x, at.y)
	lod = install.lodOf("tamriel", eyeAt, area, settings)
	scene.showLod(lod)
	scene.showTrees(install.treesOf("tamriel", eyeAt, area, settings))
	print("{lod.blocks.len} distant blocks")
if not args.hasFlag("--no-grass"):
	radius = i64.parse(args.option("--grass-radius") ?? "") ?? 2
	started = clockSeconds()
	grass = install.grassOf(plugin, tamriel, cx - radius, cy - radius, cx + radius, cy + radius)
	print("{grass.count} plants of {grass.kinds.len} kinds in {(clockSeconds() - started):.1} s")
	current = clock.weathers.get(clock.state.current) ?? fail("no weather")
	# the wind moves a blade by the weather's speed from 5 to 125 units, at most 60
	wind = f32(5.0 + (125.0 - 5.0) * current.windSpeed / 255.0).min(60.0)
	scene.showGrass(grass, wind)
if not args.hasFlag("--no-water"):
	water = install.waterOf(plugin, "skyrim.esm", tamriel, cx - 2, cy - 2, cx + 2, cy + 2, tint)
	if not args.hasFlag("--no-lod"):
		lod2 = install.lodOf("tamriel", at, area, settings)
		water.addDistant(install, plugin, tamriel, lod2, tint)
	print("{water.planes} water planes, {water.materials.len} materials, {water.vertices.len} vertices")
	scene.showWater(water)

ground = t.heightAt(at.x, at.y) ?? 0.0
eyeHeight = f32.parse(args.option("--eye") ?? "") ?? 170.0
eye = Vec3(at.x, ground + eyeHeight, -at.y)
view = Mat4.lookAlong(eye, Vec3.lookDirection(yaw.radians(), pitch.radians()))
aspect = f32(width) / f32(height)
while win.nextFrame(frames):
	scene.advance(frames.dt)
	projection = scene.picture.beginFrame(
		Mat4.perspective(f32(65.0).radians(), aspect, 15.0, 350000.0),
		view,
		width,
		height
	)
	r.drawCell(scene, width, height, projection, view, eye)
	r.finishCell(scene)
	r.showFrame(win, frames)
