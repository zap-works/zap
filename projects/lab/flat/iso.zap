# Isometric: a 2.5D world of diamond tiles made from noise, trees and rocks drawn in depth
# order, a character who walks to the tile clicked, the camera following her. Left click walks,
# the wheel zooms, the arrows pan. The tileset is a PNG made by makeTiles.zap.

import engine

mapSize = 48
tileW f32 = 64.0
tileH f32 = 32.0

# the ground kinds, by their place in the atlas's first rows
grass = 0
darkGrass = 1
dirt = 2
sand = 3
water = 4
stone = 5

# what stands on a tile
type Prop:
	tx i64
	ty i64
	kind i64   # 0 tree, 1 pine, 2 rock, 3 bush

type Hero:
	x f32   # her position in tiles (fractions between them)
	y f32
	goalX f32
	goalY f32
	facingLeft bool
	walkTime f32

pub type Iso:
	atlas engine.GpuTexture
	ground Grid<i64>
	props Prop[]
	hero Hero
	cam engine.Camera
	pan Vec2
	hoverX i64
	hoverY i64

pub fn newIso() Iso:
	ground = makeGround()
	props = makeProps(ground)
	sx, sy = startTile(ground)
	cam = engine.Camera()
	cam.zoom = 1.5
	Iso(atlas = engine.loadTexture("projects/lab/assets/tiles.png"), props,
		hero = Hero(x = f32(sx) + 0.5, y = f32(sy) + 0.5, goalX = f32(sx) + 0.5, goalY = f32(sy) + 0.5, facingLeft = false, walkTime = 0.0),
		ground, cam, pan = Vec2(0.0, 0.0), hoverX = -1, hoverY = -1)

fn makeGround():
	ground = Grid<i64>(mapSize, mapSize)
	for ty in 0..mapSize:
		for tx in 0..mapSize:
			n = engine.valueNoise(f32(tx) / 7.0, f32(ty) / 7.0, 3) * 0.7 +
				engine.valueNoise(f32(tx) / 3.0, f32(ty) / 3.0, 9) * 0.3
			path = (engine.valueNoise(f32(tx) / 5.0, f32(ty) / 5.0, 17) - 0.5).abs() < 0.035
			kind = water if n < 0.3
				else sand if n < 0.36
				else dirt if path
				else stone if n > 0.72
				else darkGrass if n > 0.55
				else grass
			ground[tx, ty] = kind
	ground

fn makeProps(ground Grid<i64>):
	props = []
	for ty in 0..mapSize:
		for tx in 0..mapSize:
			g = ground[tx, ty]
			roll = engine.random01(tx, ty, 77)
			if (g == grass or g == darkGrass) and roll < 0.09:
				props.push(Prop(tx, ty, kind = 0 if roll < 0.045 else 1))
			elif g == grass and roll < 0.13:
				props.push(Prop(tx, ty, kind = 3))
			elif g == stone and roll < 0.2:
				props.push(Prop(tx, ty, kind = 2))
	props

# the top corner of tile (tx, ty)'s diamond, in world pixels
fn tileToWorld(tx f32, ty f32):
	Vec2((tx - ty) * tileW / 2.0, (tx + ty) * tileH / 2.0)

# the tile a world point falls on (fractional)
fn worldToTile(p Vec2):
	a = p.x / (tileW / 2.0)
	b = p.y / (tileH / 2.0)
	Vec2((a + b) / 2.0, (b - a) / 2.0)

# the walkable tile nearest the middle of the map, where she starts
fn startTile(ground Grid<i64>):
	mid = mapSize / 2
	for radius in 0..mid:
		for ty in mid - radius..=mid + radius:
			for tx in mid - radius..=mid + radius:
				if walkable(ground, tx, ty) and ground[tx, ty] != stone: return (tx, ty)
	(mid, mid)

fn walkable(ground Grid<i64>, tx i64, ty i64):
	tx >= 0 and ty >= 0 and tx < mapSize and ty < mapSize and ground[tx, ty] != water

pub fn stepIso(mut s Iso, dt f32, w i64, h i64):
	# the camera: the wheel zooms, the arrows pan away from her
	s.cam.zoom = (s.cam.zoom * (1.0 + 0.12 * engine.wheelTurn())).clamp(0.5, 4.0)
	speed = 500.0 * dt / s.cam.zoom
	if engine.isKeyDown(.Left):
		s.pan.x -= speed
	if engine.isKeyDown(.Right):
		s.pan.x += speed
	if engine.isKeyDown(.Up):
		s.pan.y -= speed
	if engine.isKeyDown(.Down):
		s.pan.y += speed
	heroWorld = tileToWorld(s.hero.x, s.hero.y)
	s.cam.x = heroWorld.x + s.pan.x - f32(w) / 2.0 / s.cam.zoom
	s.cam.y = heroWorld.y + s.pan.y - f32(h) / 2.0 / s.cam.zoom
	# the tile under the mouse; a click sends her there
	hovered = s.cam.screenToWorld(engine.mousePosition()).worldToTile()
	s.hoverX = i64(hovered.x.floor())
	s.hoverY = i64(hovered.y.floor())
	if engine.isMousePressed(0) and walkable(s.ground, s.hoverX, s.hoverY):
		s.hero.goalX = f32(s.hoverX) + 0.5
		s.hero.goalY = f32(s.hoverY) + 0.5
		s.pan = Vec2(0.0, 0.0)
	s.hero.walk(s.ground, dt)

# she walks toward the goal, three tiles a second, and stops at water
fn walk(mut hero Hero, ground Grid<i64>, dt f32):
	toGoal = Vec2(hero.goalX - hero.x, hero.goalY - hero.y)
	if toGoal.length() <= 0.05:
		hero.walkTime = 0.0
		return
	step = toGoal.normalized() * (3.0 * dt).min(toGoal.length())
	nx = hero.x + step.x
	ny = hero.y + step.y
	if walkable(ground, i64(nx.floor()), i64(ny.floor())):
		hero.x = nx
		hero.y = ny
		hero.walkTime += dt
	else:
		hero.goalX = hero.x
		hero.goalY = hero.y
	hero.facingLeft = step.x - step.y < 0.0

# what stands on the ground: its depth and its prop, -1 for the hero
type Standing:
	depth f32
	prop i64

pub fn drawIso(s Iso, mut r engine.Renderer, w i64, h i64):
	cam = s.cam
	atlas = s.atlas.texture()
	r.beginFrame(w, h, engine.rgb8(24, 34, 52), cam)
	# the ground, the tiles in view only
	view = Vec2(f32(w) / cam.zoom, f32(h) / cam.zoom)
	for ty in 0..mapSize:
		for tx in 0..mapSize:
			p = tileToWorld(f32(tx), f32(ty))
			if p.x + tileW / 2.0 < cam.x or p.x - tileW / 2.0 > cam.x + view.x or
				p.y + tileH < cam.y or p.y > cam.y + view.y:
				continue
			kind = s.ground[tx, ty]
			engine.drawRegion(
				r,
				engine.Region(atlas, (kind % 4) * 64, (kind / 4) * 32, 64, 32),
				p.x - tileW / 2.0,
				p.y,
				tileW,
				tileH
			)
	if s.hoverX >= 0 and s.hoverY >= 0 and s.hoverX < mapSize and s.hoverY < mapSize:
		p = tileToWorld(f32(s.hoverX), f32(s.hoverY))
		engine.drawRegion(
			r,
			engine.Region(atlas, 128, 32, 64, 32),
			p.x - tileW / 2.0,
			p.y,
			tileW,
			tileH
		)
	# what stands on the ground, back to front: the props and her, by their depth (tx + ty)
	order = (0..s.props.len).map(Standing(f32(s.props[it].tx + s.props[it].ty) + 1.0, it))
	order.push(Standing(s.hero.x + s.hero.y, -1))
	for item in order.sortedBy(.depth):
		if item.prop < 0:
			r.drawHero(atlas, s.hero)
			continue
		pr = s.props[item.prop]
		base = tileToWorld(f32(pr.tx) + 0.5, f32(pr.ty) + 0.5)
		if base.x + 64.0 < cam.x or base.x - 64.0 > cam.x + view.x or base.y < cam.y or
			base.y - 100.0 > cam.y + view.y:
			continue
		engine.drawRegion(
			r,
			engine.Region(atlas, 192, 32, 64, 32),
			base.x - 32.0,
			base.y - 16.0,
			64.0,
			32.0
		)
		if pr.kind <= 1:
			engine.drawRegion(
				r,
				engine.Region(atlas, pr.kind * 64, 64, 64, 96),
				base.x - 32.0,
				base.y - 92.0,
				64.0,
				96.0
			)
		else:
			engine.drawRegion(
				r,
				engine.Region(atlas, 128 + (pr.kind - 2) * 64, 112, 64, 48),
				base.x - 32.0,
				base.y - 40.0,
				64.0,
				48.0
			)
	r.endFrame()

# her shadow, then her figure: two frames swapped while she walks, mirrored to face left
fn drawHero(mut r engine.Renderer, atlas engine.Texture, h Hero):
	base = tileToWorld(h.x, h.y)
	engine.drawRegion(
		r,
		engine.Region(atlas, 192, 32, 64, 32),
		base.x - 20.0,
		base.y - 8.0,
		40.0,
		16.0
	)
	f = 1 if h.walkTime > 0.0 and i64(h.walkTime * 8.0) % 2 == 1 else 0
	engine.drawRegion(
		r,
		engine.Region(atlas, f * 32, 176, 32, 48),
		base.x - 16.0,
		base.y - 46.0,
		32.0,
		48.0,
		engine.white,
		h.facingLeft
	)
