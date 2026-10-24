# GPU-driven draws (engine/render/indirect.zap) on the backend the environment picks: four quads in one
# model, one index buffer of two orders of a quad's corners, eight copies placed by an instance
# stream, drawn three ways into a frame read back each: drawIndexed once a quad (its indices from
# a first index, its corners from a vertex offset, its two copies from a first instance), one
# drawIndirect of the same four commands, and one counted by the GPU (the counter). The three
# frames must be the same, every copy of its quad's color where it is placed; and with the counter
# set to two, the counted draw must draw what the first two commands do. A device without counted
# draws checks the other two.
#   zap run projects/examples/indirect/main.zap            (from the repository's root; ZAP_RUN=gpu=d3d12 for Direct3D 12)

import engine
import quads
import image

size = 256
colors = [
	Vec4(1.0, 0.0, 0.0, 1.0),
	Vec4(0.0, 1.0, 0.0, 1.0),
	Vec4(0.0, 0.0, 1.0, 1.0),
	Vec4(1.0, 1.0, 1.0, 1.0)
]

# copy i's place in clip space: four across, two rows
fn placeOf(i i64):
	Vec2(x = -0.75 + f32(i % 4) * 0.5, y = 0.5 if i < 4 else -0.5)

# the frame drawn one way (0 drawIndexed, 1 drawIndirect, 2 counted, 3 the first two commands), read back
fn frameOf(
	way i64,
	mut win engine.Window,
	mut frames engine.Frames,
	mut r engine.Renderer,
	p engine.Program,
	shapes engine.Model,
	copies engine.Model,
	ib engine.IndexBuffer, commands engine.DrawCommands) image.Image:
		if not win.nextFrame(frames):
			fail("the window closed")
		r.useScreen()
		r.clearTarget(Vec4(0.0, 0.0, 0.0, 1.0))
		r.setDepth(false, false, false)
		if way == 0:
			for k in 0..4:
				engine.drawIndexed(
					r,
					p,
					shapes,
					ib,
					6,
					firstIndex = k % 2 * 6,
					vertexOffset = k * 4,
					instances = 2,
					firstInstance = k * 2,
					copies = copies
				)
		elif way == 3:
			r.drawIndirect(p, shapes, ib, commands, count = 2, copies = copies)
		else:
			r.drawIndirect(p, shapes, ib, commands, counted = way == 2, copies = copies)
		r.screenshot()

mut frames = engine.newFrames()
mut win = engine.openWindow("Indirect draws", size, size)
mut r = engine.newRenderer()
p = engine.newProgram(shader(quads.vertex, quads.pixel))
p.setParams(quads.View(scale = 1.0))
mut corners = []
for k in 0..4:
	for (x, y) in [(-0.15, -0.15), (0.15, -0.15), (0.15, 0.15), (-0.15, 0.15)]:
		corners.push(
			quads.Corner(
				position = Vec2(x = f32(x), y = f32(y)),
				color = Vec4(x = colors[k].r, y = colors[k].g, z = colors[k].b, w = 1.0)
			)
		)
shapes = engine.newModel(corners)
places = (0..8).map(quads.Place(offset = placeOf(it)))
copies = engine.newModel(places)
indices u32[] = [0, 1, 2, 0, 2, 3, 0, 2, 3, 0, 1, 2]
ib = engine.newIndexBuffer(indices)
list = (0..4).map(k:
	engine.DrawCommand(
		count = 6,
		instances = 2,
		firstIndex = u32(k % 2 * 6),
		vertexOffset = i32(k * 4),
		firstInstance = u32(k * 2)
	)
)
commands = engine.newDrawCommands(list)
counts = engine.countedDraws()
shots = ([0, 1, 2] if counts else [0, 1]).map(
	frameOf(it, win, frames, r, p, shapes, copies, ib, commands)
)
same = shots[0].cells == shots[1].cells and (not counts or shots[1].cells == shots[2].cells)
print("{engine.backendName()}: direct, indirect{" and counted" if counts else ""} frames the same: {same}")
# each copy's center of its quad's color
mut placed = 0
for i in 0..8:
	at = placeOf(i)
	x = i64((at.x + 1.0) * 0.5 * f32(size))
	y = i64((1.0 - at.y) * 0.5 * f32(size))
	c = colors[i / 2]
	px = shots[1][x, y]
	if i64(px.r) == i64(c.r * 255.0) and i64(px.g) == i64(c.g * 255.0) and
		i64(px.b) == i64(c.b * 255.0):
		placed += 1
print("copies of the right color where placed: {placed} of 8")
counted = true
if counts:
	commands.setDrawCount(2)
	two = frameOf(2, win, frames, r, p, shapes, copies, ib, commands)
	first = frameOf(3, win, frames, r, p, shapes, copies, ib, commands)
	counted = two.cells == first.cells and two.cells != shots[1].cells
	print("counted to two, the frame of the first two commands: {counted}")
else:
	print("counted draws: the device has none")
if placed != 8 or not counted:
	exit(1)
