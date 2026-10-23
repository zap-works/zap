# What the engine's frames cost when they draw many things, measured with `--bench N` (the CPU's
# milliseconds a frame) or ZAP_RUN=gputime: `--case boxes` (the default) draws 4000 boxes as
# sorted draws (`--unsorted`: in the order asked), each with its own parameters, four textures and
# two programs; `--case sprites`
# 40000 quads of the sprite batch over eight textures, the texture changing every fourth quad;
# `--case crowd` 3000 skinned arms (engine/tests/gltf/arm.gltf), each posed as one clip eased into
# another.
#   zap run projects/examples/stress/main.zap --bench 300 [--case sprites|crowd]

import engine
import boxes
import image
import math

width = 1280
height = 720
boxCount = 4000
spriteCount = 40_000
bodyCount = 3000

# a checker of 16 x 16 texels in the color c
fn checker(c u8):
	pixels = []
	for i in 0..256:
		v = c if (i % 16 / 4 + i / 64) % 2 == 0 else c / 2
		pixels.extend([v, 255 - v, c, 255])
	image.fromBytes(16, 16, pixels)

# a box's six faces, two triangles each
fn boxVertices():
	corners = [
		Vec3(-1.0, -1.0, -1.0),
		Vec3(1.0, -1.0, -1.0),
		Vec3(1.0, 1.0, -1.0),
		Vec3(-1.0, 1.0, -1.0),
		Vec3(-1.0, -1.0, 1.0), Vec3(1.0, -1.0, 1.0), Vec3(1.0, 1.0, 1.0), Vec3(-1.0, 1.0, 1.0)]
	faces = [0, 1, 2, 3, 5, 4, 7, 6, 4, 0, 3, 7, 1, 5, 6, 2, 3, 2, 6, 7, 4, 5, 1, 0]
	uvs = [Vec2(0.0, 0.0), Vec2(1.0, 0.0), Vec2(1.0, 1.0), Vec2(0.0, 1.0)]
	out = []
	for f in 0..6:
		for k in [0, 1, 2, 0, 2, 3]:
			out.push(boxes.BoxVertex(position = corners[faces[f * 4 + k]], uv = uvs[k]))
	out

mut frames = engine.newFrames()
mut win = engine.openWindow("Stress", width, height)
mut r = engine.newRenderer()
case = args.option("--case") ?? "boxes"
sorted = not args.hasFlag("--unsorted")
textures = (0..8).map(checker(u8(40 + it * 25)).newTexture())
plain = engine.newProgram(shader(boxes.boxVertex, boxes.boxPixel))
other = engine.newProgram(shader(boxes.boxVertex, boxes.boxPixel))
box = engine.newModel(boxVertices())
depth = engine.newRenderTarget(width, height, false, true)
projection = Mat4.perspective(1.0, f32(width) / f32(height), 0.5, 200.0)
models = [engine.loadSkinned("engine/tests/gltf/arm.gltf")]
mut crowd = engine.newCrowd(1)
skinned = engine.skinnedShadowProgram()
mut t f32 = 0.0
while win.nextFrame(frames):
	t += 1.0 / 60.0
	if case == "sprites":
		r.beginFrame(win.width, win.height, Vec4(0.1, 0.1, 0.1, 1.0), engine.Camera())
		for i in 0..spriteCount:
			x = f32(i * 37 % width) + (t * 30.0 + f32(i)).sin() * 8.0
			y = f32(i * 101 % height)
			r.drawQuad(textures[i / 4 % 8].texture(), x, y, 12.0, 12.0)
	elif case == "crowd":
		r.useTarget(depth)
		r.clearTarget(Vec4(0.1, 0.1, 0.1, 1.0))
		r.setDepth(true, true, false)
		crowd.clear()
		for i in 0..bodyCount:
			time = t + f32(i) * 0.01
			pose = engine.Pose(
				clip = 0,
				time = time % 1.0,
				from = 0,
				fromTime = (time * 0.5) % 1.0,
				blend = 0.5
			)
			at = Vec3(f32(i % 60 - 30), f32(i / 60 % 50 - 25), 0.0)
			crowd.addBody(0, models[0], pose, at, t, 0.4, 0.0, 0.0, engine.white)
		view = Mat4.lookAlong(Vec3(0.0, 0.0, 60.0), Vec3(0.0, 0.0, -1.0))
		r.drawCrowd(skinned, crowd, models, projection @ view)
		r.useScreen()
		r.beginOverlay(win.width, win.height, engine.Camera())
		r.draw(depth.colorTexture(), 0.0, 0.0)
	else:
		r.useTarget(depth)
		r.clearTarget(Vec4(0.1, 0.1, 0.1, 1.0))
		r.setBlending(false)
		r.setDepth(true, true, true)
		view = Mat4.lookAlong(Vec3(t.sin() * 5.0, 0.0, 60.0), Vec3(0.0, 0.0, -1.0))
		viewProjection = projection @ view
		if sorted:
			engine.beginSortedDraws()
		for i in 0..boxCount:
			place = Vec3(f32(i % 80 - 40), f32(i / 80 % 50 - 25), -f32(i / 4000) * 3.0)
			model = Mat4.translation(place) @ Mat4.rotationY(t + f32(i) * 0.1) @
				Mat4.scaling(Vec3(0.4, 0.4, 0.4))
			program = plain if i % 2 == 0 else other
			program.setParams(boxes.BoxParams(viewProjection, model,
				tint = Vec4(1.0, f32(i % 7) / 7.0, 1.0, 1.0), picture = textures[i % 4].texture()))
			r.drawModel(program, box)
		if sorted:
			engine.endSortedDraws()
		r.useScreen()
		r.beginOverlay(win.width, win.height, engine.Camera())
		r.draw(depth.colorTexture(), 0.0, 0.0)
	r.showFrame(win, frames)
