# The land around Riverwood drawn from above with the game's landscape shader, offscreen, and
# saved as a picture. Run from the repository root:
#
#   zap run projects/skyrim/terrainShot.zap --shot terrain.png
#   zap run projects/skyrim/terrainShot.zap --cells 4,-12,6,-10 --height 12000 --pitch -80 --shot t.png
#
#   needs: projects/skyrim/assets/game (fetch.zap)

import engine
import skyrim
import skyrim.esm
import game
import image
import math
import world
import world.shaders

fn colorOf(r f32, g f32, b f32):
	Vec4(r, g, b, 1.0)

# daylight over the land: a cool ambient from above, a warm sun, a pale far fog
fn daylight(
	projection Mat4,
	view Mat4,
	eye Vec3,
	move textures engine.Texture[]
):
	ambient Vec4[6]
	for i in 0..6:
		ambient[i] = colorOf(0.28, 0.32, 0.38) if i != 3 else colorOf(0.2, 0.2, 0.2)
	shaders.CellParams(
		projection,
		view,
		eye = eye.withW(1.0),
		ambient,
		sunColor = colorOf(0.9, 0.85, 0.75),
		sunToward = Vec3(0.35, 0.8, -0.3).normalized().withW(0.0),
		fogNearColor = colorOf(0.55, 0.62, 0.72),
		fogFarColor = colorOf(0.6, 0.68, 0.8),
		fog = Vec4(30000.0, 90000.0, 1.0, 0.8),
		right = Vec4(1.0, 0.0, 0.0, 0.0),
		up = Vec4(0.0, 1.0, 0.0, 0.0),
		lightCount = 0,
		lights = [],
		billboards = [],
		effects = [],
		looks = [],
		textures
	)

fn cellsOf(text str):
	parts = text.split(",").map(i64.parse(it) ?? fail("--cells is x0,y0,x1,y1"))
	if parts.len != 4: fail("--cells is x0,y0,x1,y1")
	parts

dir = skyrim.declareWithInstall(
	[
		ArgOption("--cells", true, "x0,y0,x1,y1 of the cells (4,-12,6,-10)"),
		ArgOption("--height", true, "the camera's height over the middle (12000)"),
		ArgOption("--pitch", true, "its pitch in degrees, -90 straight down (-75)"),
		ArgOption("--shot", true, "the picture to write")
	]
)
cells = cellsOf(args.option("--cells") ?? "4,-12,6,-10")
height = f32.parse(args.option("--height") ?? "") ?? 12000.0
pitch = f32.parse(args.option("--pitch") ?? "") ?? -75.0
out = args.option("--shot") ?? fail("give --shot picture.png")
install = skyrim.openInstall(dir) ?? fail
plugin = esm.openEsm(esm.pluginPath(dir, "Skyrim.esm")) ?? fail
t = install.terrainOf(plugin, 0x3C, cells[0], cells[1], cells[2], cells[3])
print("{t.grids.len} cells, {t.vertices.len} vertices, {t.textures.len} textures")

width = 1024
height_px = 768
mut frames = engine.newFrames()
mut win = engine.openWindow("Skyrim terrain", width, height_px)
mut r = engine.newRenderer()
depth = engine.newDepthTarget(width, height_px)
program = world.newTerrainProgram()
textures = t.textures.map(world.gpuTexture(t.body, it))
handles = textures.map(.texture())
draw = world.newTerrainDraw(t.vertices, t.indices, textures)
cx = (f32(cells[0] + cells[2] + 1) * 0.5) * esm.cellSize
cy = (f32(cells[1] + cells[3] + 1) * 0.5) * esm.cellSize
ground = t.heightAt(cx, cy) ?? 0.0
# the engine's y up: the game's (x, y, z) is (x, z, -y)
eye = Vec3(cx, ground + height, -(cy - height * 0.4))
forward = Vec3.lookDirection(0.0, pitch.radians())
params = daylight(
	Mat4.perspective(f32(60.0).radians(), f32(width) / f32(height_px), 50.0, 200000.0),
	Mat4.lookAlong(eye, forward),
	eye,
	handles
)
program.setParams(params)
if not win.nextFrame(frames): fail("the window closed")
r.useScreenWithDepth(depth)
r.clearTarget(colorOf(0.6, 0.68, 0.8))
r.setBlending(false)
r.setDepth(true, true, true)
r.drawIndexed(program, draw.model, draw.indices, draw.indices.count)
r.screenshot().savePng(out) ?? fail("cannot write {out}")
print("wrote {out}")
