# A world of blocks to walk, dig and build in, in the manner of Minecraft, without an edge: hills,
# beaches, seas and snowy peaks, trees, meadows of tall grass, ores below, made in chunks on
# other threads as the player walks (the frame never waits for them) and let go behind. The textures
# are photographed materials of ambientCG (CC0, assets/blocks/, made by makeTextures.zap), lit
# as light behaves under a sky the air scatters (graphics/). Click to take the mouse; WASD walk, space jumps, the mouse looks, the left
# button breaks the block aimed at, the right one places the block chosen (1-9 or the wheel);
# Esc lets the mouse go, and Esc again ends. A day lasts ten minutes; T held makes time fly. The
# GPU draws the sun's shadows, the sky with its clouds and stars, waving water that mirrors the
# sky, swaying leaves, bloom (graphics/).
#
#   zap run projects/minecraft/main.zap
#   zap run projects/minecraft/main.zap --frames 300 --step 16 --shot minecraft.png    (a scripted walk
#                                                                 that digs and builds, checking for leaks)
#   zap test --only size
#   zap run projects/minecraft/main.zap --time 0.45                      (start at that time of day, 0..1)

import engine
import graphics
import world
import image
import math

start = 128   # the column the player starts on (x and z)
seed = 2026
reach f32 = 6.0
walkSpeed f32 = 4.3
lookSpeed f32 = 0.0025
fovY f32 = 1.25   # radians
hotbar = [
	world.grass,
	world.dirt,
	world.stone,
	world.planks,
	world.brick,
	world.glass,
	world.log,
	world.leaves,
	world.sand
]

type Game:
	land world.World
	drawn graphics.ChunkDraw[]   # the chunks with meshes, in no order
	drawnKeys i64[]   # the key of each
	drawnAt {i64: i64}   # a chunk's key -> its place in drawn
	making MakeJob[]   # chunks being made on other threads
	meshing MeshJob[]   # and meshed
	busy {i64: bool}   # the keys of the chunks in making or meshing
	body world.Body
	yaw f32   # radians from -z toward +x
	pitch f32   # radians up
	selected i64   # the place in the hotbar
	target world.Hit   # the block aimed at
	faces i64   # in the meshes
	edits i64   # changes to the meshes so far (the shadows are drawn again)
	dayTime f32   # 0 .. 1 over a day (graphics.View)
	wheel f32 = 0.0   # the part of a notch the wheel turned toward the next choice
	outline engine.Mesh   # the lines around the block aimed at
	outlineAt Vec3?   # the corner they are drawn from (none: nothing aimed at)
	info str   # the line at the top, made again a few times a second
	infoAt f64   # when it was made

type MakeJob:
	cx i64
	cz i64
	job Background<u8[]>

type MeshJob:
	cx i64
	cz i64
	version i64   # the chunk's version when the job started (another: stale)
	job Background<world.ChunkMesh>

# ---------- the world and its meshes ----------

fn newGame():
	g = Game(
		land = world.emptyWorld(),
		drawn = [],
		drawnKeys = [],
		drawnAt = {},
		making = [],
		meshing = [],
		busy = {},
		body = world.newBody(Vec3(0.0, 0.0, 0.0)),
		yaw = 0.6,
		pitch = -0.2,
		selected = 0,
		target = noHit(),
		faces = 0,
		edits = 0,
		dayTime = 0.07,
		outline = engine.newMesh(
			world.outlineWords(0, 0, 0, 0, 0),
			mode = .Lines
		), outlineAt = none, info = "", infoAt = -1.0)
	# the land around the start made and meshed on every processor at once, the rest streamed
	# in as the player goes
	c = world.chunkOf(start)
	side = 2 * makeRadius + 1
	made = (0..side * side)
		.parallel()
		.map(k: world.generateChunk(c + k % side - makeRadius, c + k / side - makeRadius, seed))
	for k in 0..side * side:
		g.land.addChunk(c + k % side - makeRadius, c + k / side - makeRadius, move made[k])
	shown = 2 * viewRadius + 1
	batch = 16
	for first in 0..(shown * shown + batch - 1) / batch:
		meshes = (0..batch.min(shown * shown - first * batch))
			.parallel()
			.map(k:
				world.meshChunk(
					g.land,
					c + (first * batch + k) % shown - viewRadius,
					c + (first * batch + k) / shown - viewRadius
				)
			)
		for k, meshe in meshes:
			at = first * batch + k
			g.show(c + at % shown - viewRadius, c + at / shown - viewRadius, meshe)
	# on the ground at the start
	y = world.height - 1
	while y > 0 and not world.isSolid(g.land.at(start, y - 1, start)):
		y -= 1
	g.body = world.newBody(Vec3(f32(start) + 0.5, f32(y), f32(start) + 0.5))
	g

fn noHit():
	world.Hit(found = false, x = 0, y = 0, z = 0, nx = 0, ny = 0, nz = 0)

fn grid():
	graphics.Grid(size = world.chunkSize, height = world.height)

fn chunkCorner(cx i64, cz i64):
	Vec3(f32(cx * world.chunkSize), 0.0, f32(cz * world.chunkSize))

# chunk cx, cz drawn with these meshes (its old ones replaced)
fn show(mut g Game, cx i64, cz i64, m world.ChunkMesh):
	key = world.chunkKey(cx, cz)
	g.edits += 1
	g.faces += (m.solid.len + m.water.len) / 4
	match g.drawnAt.get(key):
		i:
			g.faces -= (g.drawn[i].solid.model.count + g.drawn[i].water.model.count) / 4
			g.drawn[i].solid.setMeshVertices(m.solid)
			g.drawn[i].water.setMeshVertices(m.water)
		none:
			g.drawn.push(
				graphics.ChunkDraw(
					solid = engine.newMesh(m.solid),
					water = engine.newMesh(m.water),
					origin = chunkCorner(cx, cz)
				)
			)
			g.drawnKeys.push(key)
			g.drawnAt[key] = g.drawn.len - 1

# the meshes of the chunk at place i of drawn let go (the last one takes its place)
fn hide(mut g Game, i i64):
	g.edits += 1
	g.faces -= (g.drawn[i].solid.model.count + g.drawn[i].water.model.count) / 4
	g.drawnAt.remove(g.drawnKeys[i])
	last = g.drawn.len - 1
	if i != last:
		g.drawn[i] = move g.drawn[last]
		g.drawnKeys[i] = g.drawnKeys[last]
		g.drawnAt[g.drawnKeys[i]] = i
	g.drawn.pop()
	g.drawnKeys.pop()

# ---------- streaming: the land made and meshed around the player ----------

viewRadius = 11   # chunks drawn around the player's (the fog hides what is past)
makeRadius = viewRadius + 1   # chunks made: one more ring, the border of the last drawn ones
keepRadius = makeRadius + 2   # chunks kept as the player goes away (not lost at once on a turn back)
jobsAtOnce = 12   # jobs of each kind in flight

# One step of the streaming: the chunks made and meshed since the last frame taken in, the
# nearest missing ones started, the far ones let go. With `wait` every job started is finished
# before it returns (a scripted run sees the same world at the same frame).
fn streamWorld(mut g Game, wait bool):
	cx = world.chunkOf(i64(g.body.feet.x.floor()))
	cz = world.chunkOf(i64(g.body.feet.z.floor()))
	g.takeMade()
	g.takeMeshed()
	g.startJobs(cx, cz)
	while wait and (not g.making.isEmpty or not g.meshing.isEmpty):
		sleepMs(1)
		g.takeMade()
		g.takeMeshed()
		g.startJobs(cx, cz)
	g.letGo(cx, cz)

# the nearest chunks that need making, then those that need meshing (made, with every chunk
# around them made), ring by ring out from cx, cz
fn startJobs(mut g Game, cx i64, cz i64):
	for r in 0..=makeRadius:
		for k in 0..ringCells(r):
			dx, dz = ringCell(r, k)
			x = cx + dx
			z = cz + dz
			key = world.chunkKey(x, z)
			if key in g.busy: continue
			if not g.land.has(x, z):
				if g.making.len < jobsAtOnce:
					g.making.push(
						MakeJob(
							cx = x,
							cz = z,
							job = background((): world.generateChunk(x, z, seed))
						)
					)
					g.busy[key] = true
			elif r <= viewRadius and key not in g.drawnAt and g.land.aroundMade(x, z) and
				g.meshing.len < jobsAtOnce:
				padded = g.land.paddedChunk(x, z)
				g.meshing.push(
					MeshJob(
						cx = x,
						cz = z,
						version = g.land.versionOf(x, z),
						job = background((): padded.meshPadded())
					)
				)
				g.busy[key] = true

# the cells on ring r around a chunk (r = 0: the chunk itself)
fn ringCells(r i64):
	1 if r == 0 else 8 * r

# the k-th cell of ring r: along its top and bottom rows, then down its sides
fn ringCell(r i64, k i64):
	if r == 0: return (0, 0)
	side = 2 * r + 1
	if k < side: return (k - r, -r)
	if k < 2 * side: return (k - side - r, r)
	j = k - 2 * side   # the cells of the two sides between the rows
	(-r if j % 2 == 0 else r, j / 2 - r + 1)

fn aroundMade(w world.World, cx i64, cz i64):
	for dz in -1..2:
		for dx in -1..2:
			if not w.has(cx + dx, cz + dz): return false
	true

# the chunks made since the last look kept
fn takeMade(mut g Game):
	i = 0
	while i < g.making.len:
		match g.making[i].job.tryReceive():
			blocks:
				x = g.making[i].cx
				z = g.making[i].cz
				g.land.addChunk(x, z, blocks)
				g.busy.remove(world.chunkKey(x, z))
				g.making.remove(i)
			none: i += 1

# the meshes made since the last look shown (dropped when an edit changed the chunk meanwhile:
# it is meshed again)
fn takeMeshed(mut g Game):
	i = 0
	while i < g.meshing.len:
		match g.meshing[i].job.tryReceive():
			m:
				x = g.meshing[i].cx
				z = g.meshing[i].cz
				key = world.chunkKey(x, z)
				if g.meshing[i].version == g.land.versionOf(x, z):
					g.show(x, z, m)
				g.busy.remove(key)
				g.meshing.remove(i)
			none: i += 1

# the meshes beyond the view and the chunks beyond reach let go (a chunk the player changed is
# kept, with its changes)
fn letGo(mut g Game, cx i64, cz i64):
	i = 0
	while i < g.drawn.len:
		o = g.drawn[i].origin
		if ringOf(world.chunkOf(i64(o.x)) - cx, world.chunkOf(i64(o.z)) - cz) >
			viewRadius + 1:
			g.hide(i)
		else:
			i += 1
	for s in 0..g.land.slots.len:
		x = g.land.slots[s].cx
		z = g.land.slots[s].cz
		if not g.land.slots[s].blocks.isEmpty and not g.land.slots[s].edited and
			ringOf(x - cx, z - cz) > keepRadius and world.chunkKey(x, z) not in g.busy:
			g.land.dropChunk(x, z)

fn ringOf(dx i64, dz i64):
	dx.abs().max(dz.abs())

# the meshes of chunk cx, cz made again from the blocks, now (an edit shows at once)
fn remesh(mut g Game, cx i64, cz i64):
	g.land.touchChunk(cx, cz)
	if world.chunkKey(cx, cz) in g.drawnAt:
		g.show(cx, cz, g.land.meshChunk(cx, cz))

# the chunks a change at column x, z shows in: its own, and those beside it when it lies on
# their edge (their faces and shadows touch it)
fn remeshAround(mut g Game, x i64, z i64):
	for cz in world.chunkOf(z - 1)..=world.chunkOf(z + 1):
		for cx in world.chunkOf(x - 1)..=world.chunkOf(x + 1):
			g.remesh(cx, cz)

fn setBlockAt(mut g Game, x i64, y i64, z i64, b i64):
	g.land.setBlock(x, y, z, b)
	g.remeshAround(x, z)

# breaks the block aimed at (not the bottom layer); its kind, or air when there is none
fn breakTarget(mut g Game):
	t = g.target
	if not t.found or t.y == 0: return world.air
	b = g.land.at(t.x, t.y, t.z)
	g.setBlockAt(t.x, t.y, t.z, world.air)
	b

# places the block chosen against the face aimed at; whether there was room
fn placeAtTarget(mut g Game):
	t = g.target
	if not t.found: return false
	x = t.x + t.nx
	y = t.y + t.ny
	z = t.z + t.nz
	there = g.land.at(x, y, z)
	if y < 0 or y >= world.height or not g.land.has(world.chunkOf(x), world.chunkOf(z)) or
		(there != world.air and there != world.water) or
		world.blockTouchesBody(x, y, z, g.body.feet):
		return false
	g.setBlockAt(x, y, z, hotbar[g.selected])
	true

# ---------- the frame ----------

fn eye(g Game):
	g.body.feet + Vec3(0.0, world.eyeHeight, 0.0)

# walks by what is held this frame (relative to where the camera faces), then aims
fn steer(mut g Game, forward f32, strafe f32, jump bool, dt f32):
	fx = g.yaw.sin()
	fz = -g.yaw.cos()
	walk = Vec3(fx * forward - fz * strafe, 0.0, fz * forward + fx * strafe)
	if walk.length() > 1.0:
		walk = walk.normalized()
	g.land.stepBody(g.body, walk * walkSpeed, jump, dt)
	g.pitch = g.pitch.clamp(-1.55, 1.55)
	g.aimAt(g.land.raycast(g.eye(), Vec3.lookDirection(g.yaw, g.pitch), reach))

# the block aimed at, its outline made again when it is another one
fn aimAt(mut g Game, t world.Hit):
	same = t.found == g.target.found and t.x == g.target.x and t.y == g.target.y and
		t.z == g.target.z
	g.target = t
	if same and (g.outlineAt != none) == t.found: return
	g.outlineAt = none
	if t.found:
		corner = chunkCorner(world.chunkOf(t.x), world.chunkOf(t.z))
		g.outlineAt = corner
		engine.setMeshVertices(
			g.outline,
			world.outlineWords(t.x, t.y, t.z, i64(corner.x), i64(corner.z))
		)

fn underwater(g Game):
	e = g.eye()
	g.land.at(i64(e.x.floor()), i64((e.y + 0.12).floor()), i64(e.z.floor())) == world.water

fn drawWorld(
	mut r engine.Renderer,
	mut p graphics.Pipeline,
	g Game,
	tiles graphics.Materials,
	time f32,
	w i64,
	h i64
):
	view = graphics.View(
		eye = g.eye(),
		forward = Vec3.lookDirection(g.yaw, g.pitch),
		fovY = fovY,
		time,
		dayTime = g.dayTime,
		underwater = g.underwater()
	)
	r.drawFrame(p, view, g.drawn, grid(), g.outline, g.outlineAt, g.edits, tiles, w, h)

# the line at the top, made again four times a second (not every frame: it is a new string)
fn updateInfo(mut g Game, fps i64, now f64):
	if now - g.infoAt < 0.25: return
	p = g.body.feet
	aimed = world.blockName(
		g.land.at(g.target.x, g.target.y, g.target.z) if g.target.found else world.air
	)
	hour = ((g.dayTime * 24.0 + 6.0) % 24.0).floor()
	g.info = "{fps} fps   x {p.x.floor()} y {p.y.floor()} z {p.z.floor()}   {hour}h   aiming at {aimed}   {g.drawn.len} chunks   {g.faces} faces"
	g.infoAt = now

helpText = "click to play: WASD walk, space jumps, the mouse looks, left breaks, right places, 1-9 or the wheel choose, T speeds time, Esc frees the mouse"

fn drawHud(
	mut r engine.Renderer,
	g Game,
	font engine.Font,
	icons engine.GpuTexture[],
	w i64,
	h i64,
	help bool
):
	r.beginOverlay(w, h, engine.Camera())
	cx = f32(w / 2)
	cy = f32(h / 2)
	r.fillRect(cx - 10.0, cy - 1.0, 20.0, 2.0, Vec4(1.0, 1.0, 1.0, 0.85))
	r.fillRect(cx - 1.0, cy - 10.0, 2.0, 20.0, Vec4(1.0, 1.0, 1.0, 0.85))
	slot f32 = 52.0
	left = cx - slot * f32(hotbar.len) / 2.0
	top = f32(h) - slot - 12.0
	engine.fillRect(
		r,
		left - 4.0,
		top - 4.0,
		slot * f32(hotbar.len) + 8.0,
		slot + 8.0,
		Vec4(0.0, 0.0, 0.0, 0.45)
	)
	for i in 0..hotbar.len:
		x = left + f32(i) * slot
		if i == g.selected:
			r.fillRect(x, top, slot, slot, Vec4(1.0, 1.0, 1.0, 0.9))
		r.drawQuad(icons[i].texture(), x + 6.0, top + 6.0, slot - 12.0, slot - 12.0)
	name = world.blockName(hotbar[g.selected])
	r.drawTextCentered(font, name, cx, top - 30.0, engine.white)
	r.drawLabel(font, g.info, height = 28.0, background = Vec4(0.0, 0.0, 0.0, 0.4))
	if help:
		tw = f32(font.textWidth(helpText))
		engine.fillRect(
			r,
			cx - tw / 2.0 - 10.0,
			cy + 30.0,
			tw + 20.0,
			30.0,
			Vec4(0.0, 0.0, 0.0, 0.55)
		)
		r.drawText(font, helpText, cx - tw / 2.0, cy + 34.0, engine.white)
	r.endFrame()

# ---------- playing ----------

# a frame of play: the mouse taken or let go, looking, breaking and placing, choosing, walking;
# false when the player ends the game
fn playFrame(mut g Game, win engine.Window, dt f32):
	if engine.isKeyPressed(.Escape):
		if not engine.isMouseCaptured(): return false
		win.captureMouse(false)
	playing = engine.isMouseCaptured()
	if not playing and engine.isMousePressed(0):
		win.captureMouse(true)
	elif playing:
		motion = engine.mouseMotion()
		g.yaw += f32(motion.x) * lookSpeed
		g.pitch -= f32(motion.y) * lookSpeed
		if engine.isMousePressed(0):
			g.breakTarget()
		if engine.isMousePressed(1):
			g.placeAtTarget()
	for k in 0..hotbar.len:
		if engine.isKeyPressed(.Char('1' + k)):
			g.selected = k
	n = hotbar.len
	# whole notches of the wheel, a smooth wheel's fractions kept until they make one
	g.wheel += engine.wheelTurn()
	notches = i64(g.wheel)
	g.wheel -= f32(notches)
	g.selected = ((g.selected - notches) % n + n) % n
	steer(
		g,
		engine.keyAxis(.Char('W'), .Char('S')),
		engine.keyAxis(.Char('D'), .Char('A')),
		engine.isKeyDown(.Space),
		dt
	)
	true

# ---------- the scripted walk (a frame limit) ----------

# What the script does at a frame: walks, turns, looks down, digs two blocks and fills the hole
# with bricks, checking each change; then looks out over the world for the picture.
fn scriptedFrame(mut g Game, frame i64, dt f32):
	if frame >= 100 and frame < 130:
		g.yaw += 0.03
	if frame >= 130 and frame < 150:
		g.pitch -= 0.05
	g.steer(1.0 if frame >= 40 and frame < 100 else 0.0, 0.0, frame == 60, dt)
	if frame == 160 or frame == 170:
		t = g.target
		b = g.breakTarget()
		if b == world.air or g.land.at(t.x, t.y, t.z) != world.air:
			fail("the script could not break the block at {t.x} {t.y} {t.z}")
		print("broke {world.blockName(b)} at {t.x} {t.y} {t.z}")
	if frame == 180 or frame == 185:
		g.selected = 4
		g.steer(0.0, 0.0, false, 0.0)
		t = g.target
		if not g.placeAtTarget() or g.land.at(t.x + t.nx, t.y + t.ny, t.z + t.nz) != world.brick:
			fail("the script could not place a brick against {t.x} {t.y} {t.z}")
		print("placed brick at {t.x + t.nx} {t.y + t.ny} {t.z + t.nz}")
	if frame >= 200 and frame < 230:
		g.pitch += 0.045
		g.yaw -= 0.02

# ---------- the program ----------

# the blocks' textures, one layer per face image: `suffix` "" their colors, "_surface" their
# normals, roughness and occlusion
fn loadLayers(suffix str):
	engine.newTextureArray(
		world.tileNames.map(image.loadPng("projects/minecraft/assets/blocks/{it}{suffix}.png"))
	)

mut frames = engine.newFrames()
scripted = frames.limit >= 0
mut win = engine.openWindow("Minecraft", 1280, 720)
mut r = engine.newRenderer()
mut pipeline = graphics.newPipeline(win.width, win.height)
font = engine.loadFont("Segoe UI", 18)
tiles = graphics.Materials(colors = loadLayers(""), surfaces = loadLayers("_surface"))
icons = hotbar.map(b:
	engine.loadTexture(
		"projects/minecraft/assets/blocks/{world.tileNames[world.faceLayer(b, 0)]}.png"
	)
)
started = clockSeconds()
mut g = newGame()
g.dayTime = f32(f64.parse(args.option("--time") ?? "") ?? f64(g.dayTime))
print("the world is made and meshed in {(clockSeconds() - started):.2} s: {g.faces} faces")
mut steadyBlocks = 0   # the blocks the program holds once it has settled
mut allocAt100 = 0
mut endBlocks = 0   # and after the last frame, everything still alive
while win.nextFrame(frames, escEnds = false):
	dt = frames.dt
	g.dayTime = graphics.advanceDay(g.dayTime, dt * 40.0 if engine.isKeyDown(.Char('T')) else dt)
	if scripted:
		g.scriptedFrame(frames.count, 1.0 / 60.0)
	elif not g.playFrame(win, dt):
		break
	g.streamWorld(scripted)
	g.updateInfo(frames.clock.fps, frames.clock.elapsed)
	r.drawWorld(pipeline, g, tiles, f32(frames.clock.elapsed), win.width, win.height)
	r.drawHud(g, font, icons, win.width, win.height, not scripted and not engine.isMouseCaptured())
	# read before the last frame is shown: its screenshot makes the RHI's retired lists once
	if frames.isLastFrame():
		endBlocks = liveBlocks()
	r.showFrame(win, frames)
	if frames.count == 100:
		steadyBlocks = liveBlocks()
		allocAt100 = allocations()
if scripted:
	print(frames.fpsText())
	# what the frames allocate they free: the blocks held after the last frame are those held at
	# frame 100 (read inside the loop: after it, what the loop used may be let go already)
	if frames.count > 100 and endBlocks != steadyBlocks:
		fail("memory grew while the frames ran: {steadyBlocks} blocks held at frame 100, {endBlocks} at the end")
	print("allocations a frame: {(allocations() - allocAt100) / (frames.count - 100)}")
	print("memory steady: {endBlocks} blocks held")
win.captureMouse(false)
