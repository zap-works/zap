# Makes the blocks' textures (assets/blocks/) from photographed materials of ambientCG (CC0,
# ambientcg.com): each block face gets a color image (alpha: what a cutout lets through) and a
# surface image (its normal's x and y, roughness, ambient occlusion), 256 x 256, in the order of
# the texture layers (world/blocks.zap's tileNames). The faces no photograph has are composed:
# grass and snow over dirt on a side, ore in stone, leaves scattered from a leaf atlas, glass,
# water.
#
#   zap run projects/minecraft/makeTextures.zap <dir>     (the 1K-PNG sets of the materials below, unzipped)

import engine
import world
import fs
import image

size = 256

# ---------- reading a material ----------

type Material:
	color image.Image
	normal image.Image
	roughness image.Image
	occlusion image.Image

fn readMaterial(dir str, id str):
	prefix = "{dir}/{id}_1K-PNG_"
	Material(
		color = image.loadPng("{prefix}Color.png"),
		normal = image.loadPng("{prefix}NormalGL.png"),
		roughness = image.loadPng("{prefix}Roughness.png"),
		occlusion = readOr("{prefix}AmbientOcclusion.png", 255))

# the image at path, or a white one (a material without the map)
fn readOr(path str, value i64):
	if fs.exists(path): return image.loadPng(path)
	image.fromBytes(1, 1, [u8(value), u8(value), u8(value), 255])

# ---------- a tile: color and surface, size x size ----------

type Tile:
	color image.Image
	surface image.Image   # the normal's x and y (0..255 for -1..1), roughness, occlusion

fn newTile():
	blank = image.Rgba8(0, 0, 0, 0)
	Tile(
		color = image.Image(size, size, fill = blank),
		surface = image.Image(size, size, fill = blank)
	)

# The material over the tile: each texel the average of the image's texels under it (colors in
# linear light, normals renormalized); `crop` is the part of the image used (1: all of it, from
# the middle).
fn tileOf(m Material, crop f64):
	t = newTile()
	for y in 0..size:
		for x in 0..size:
			t.put(x, y, m.average(x, y, crop))
	t

# one texel of the tile from the images: color r g b a, normal x y, roughness, occlusion (0..1)
type Texel:
	r f64
	g f64
	b f64
	a f64
	nx f64
	ny f64
	rough f64
	ao f64

fn average(m Material, x i64, y i64, crop f64):
	w = m.color.width
	span = w * crop
	first = (w - span) / 2.0
	x0 = i64(first + x * span / size)
	x1 = i64(first + (x + 1) * span / size).max(x0 + 1)
	y0 = i64(first + y * span / size)
	y1 = i64(first + (y + 1) * span / size).max(y0 + 1)
	s = Texel(r = 0.0, g = 0.0, b = 0.0, a = 0.0, nx = 0.0, ny = 0.0, rough = 0.0, ao = 0.0)
	nz = 0.0
	for yy in y0..y1:
		for xx in x0..x1:
			s.r += m.color.linear(xx, yy, 0)
			s.g += m.color.linear(xx, yy, 1)
			s.b += m.color.linear(xx, yy, 2)
			s.a += m.color.channel(xx, yy, 3)
			s.nx += m.normal.channel(xx, yy, 0) * 2.0 - 1.0
			s.ny += m.normal.channel(xx, yy, 1) * 2.0 - 1.0
			nz += m.normal.channel(xx, yy, 2) * 2.0 - 1.0
			s.rough += m.roughness.channel(xx, yy, 0)
			s.ao += m.occlusion.channel(xx, yy, 0)
	n = f64((x1 - x0) * (y1 - y0))
	length = (s.nx * s.nx + s.ny * s.ny + nz * nz).sqrt().max(0.0001)
	Texel(
		r = s.r / n,
		g = s.g / n,
		b = s.b / n,
		a = s.a / n,
		nx = s.nx / length,
		ny = s.ny / length,
		rough = s.rough / n,
		ao = s.ao / n
	)

# a channel of an image (0..1) at x, y scaled to its size and wrapped (a small map stretches)
fn channel(img image.Image, x i64, y i64, c i64) f64:
	px = x % img.width
	py = y % img.height
	img[px, py][c] / 255.0

# a color channel in linear light (the image is sRGB; a square is close enough for averaging)
fn linear(img image.Image, x i64, y i64, c i64):
	v = img.channel(x, y, c)
	v * v

fn put(mut t Tile, x i64, y i64, v Texel):
	t.color[x, y] = image.Rgba8(
		image.unitToByte(f32(v.r.sqrt())),
		image.unitToByte(f32(v.g.sqrt())),
		image.unitToByte(f32(v.b.sqrt())),
		image.unitToByte(f32(v.a))
	)
	t.surface[x, y] = image.Rgba8(
		image.unitToByte(f32(v.nx * 0.5 + 0.5)),
		image.unitToByte(f32(v.ny * 0.5 + 0.5)),
		image.unitToByte(f32(v.rough)),
		image.unitToByte(f32(v.ao))
	)

fn texelAt(t Tile, x i64, y i64):
	color = t.color[x, y]
	surface = t.surface[x, y]
	r = unit(color.r)
	g = unit(color.g)
	b = unit(color.b)
	Texel(
		r = r * r,
		g = g * g,
		b = b * b,
		a = unit(color.a),
		nx = unit(surface.r) * 2.0 - 1.0,
		ny = unit(surface.g) * 2.0 - 1.0,
		rough = unit(surface.b), ao = unit(surface.a))

# a byte as 0..1
fn unit(byte u8) f64:
	byte / 255.0

# ---------- noise for the composed faces ----------

fn hash(x i64, y i64, seed i64) f64:
	f64(engine.random01(x, y, seed))

# smooth noise over x that wraps every `size` texels (a tile repeats seamlessly)
fn wave(x i64, period i64, seed i64):
	cells = size / period
	c = x / period
	t = f64(x % period) / f64(period)
	s = t.smoothstep(0.0, 1.0)
	a = hash(c % cells, 0, seed)
	b = hash((c + 1) % cells, 0, seed)
	a + (b - a) * s

# ---------- the composed faces ----------

# Dirt with a band of `cover` over its top, ragged at its lower edge (grass, snow): a side.
fn coveredSide(dirt Tile, cover Tile, seed i64):
	t = newTile()
	for x in 0..size:
		depth = 22.0 + wave(x, 32, seed) * 18.0 + wave(x, 8, seed + 1) * 9.0 +
			wave(x, 4, seed + 2) * 5.0
		for y in 0..size:
			if y < depth:
				t.put(x, y, cover.texelAt(x, y))
			else:
				v = dirt.texelAt(x, y)
				# the cover's shadow on the dirt just under it
				shade = 1.0 - 0.45 * (1.0 - ((y - depth) / 10.0).min(1.0))
				v.r *= shade * shade
				v.g *= shade * shade
				v.b *= shade * shade
				t.put(x, y, v)
	t

# Stone with ore: clusters of small irregular grains of its color, keeping the stone's light and
# shade, smoother than the rock around them.
fn oreIn(stone Tile, r f64, g f64, b f64, rough f64, seed i64):
	t = newTile()
	for y in 0..size:
		for x in 0..size:
			t.put(x, y, stone.texelAt(x, y))
	for cluster in 0..7:
		cx = hash(cluster, 1, seed) * size
		cy = hash(cluster, 2, seed) * size
		for k in 0..14:
			gx = i64(cx + (hash(cluster * 31 + k, 3, seed) - 0.5) * 44.0)
			gy = i64(cy + (hash(cluster * 31 + k, 4, seed) - 0.5) * 44.0)
			radius = 2.0 + hash(cluster * 31 + k, 5, seed) * 4.5
			reach = i64(radius) + 2
			for dy in -reach..=reach:
				for dx in -reach..=reach:
					d = f64(dx * dx + dy * dy).sqrt() +
						(hash(gx + dx, gy + dy, seed) - 0.5) * 2.5
					if d < radius:
						x = (gx + dx + size * 4) % size
						y = (gy + dy + size * 4) % size
						v = t.texelAt(x, y)
						light = ((v.r + v.g + v.b) / 3.0).sqrt() * 2.2
						v.r = r * light
						v.g = g * light
						v.b = b * light
						v.rough = rough
						t.put(x, y, v)
	t

# Leaves scattered from an atlas of 3 x 3 leaves (each one's alpha in the opacity map), over a
# clear tile that repeats seamlessly: what no leaf covers lets the light through.
fn scatteredLeaves(atlas Material, opacity image.Image, seed i64):
	t = newTile()
	cell = atlas.color.width / 3
	leaf = 72
	for k in 0..70:
		pick = i64(hash(k, 0, seed) * 9.0).min(8)
		ax = pick % 3 * cell
		ay = pick / 3 * cell
		ox = i64(hash(k, 1, seed) * size)
		oy = i64(hash(k, 2, seed) * size)
		turned = hash(k, 3, seed) > 0.5   # half of them upside down
		mirrored = hash(k, 4, seed) > 0.5
		tint = 0.55 + hash(k, 5, seed) * 0.45
		for ly in 0..leaf:
			for lx in 0..leaf:
				sx = lx * cell / leaf
				sy = ly * cell / leaf
				if mirrored:
					sx = cell - 1 - sx
				if turned:
					sx = cell - 1 - sx
					sy = cell - 1 - sy
				alpha = opacity.channel(ax + sx, ay + sy, 0)
				if alpha < 0.5: continue
				x = (ox + lx) % size
				y = (oy + ly) % size
				nx = atlas.normal.channel(ax + sx, ay + sy, 0) * 2.0 - 1.0
				ny = atlas.normal.channel(ax + sx, ay + sy, 1) * 2.0 - 1.0
				if mirrored != turned:
					nx = -nx
				if turned:
					ny = -ny
				t.put(x, y, Texel(
					r = atlas.color.linear(ax + sx, ay + sy, 0) * tint,
					g = atlas.color.linear(ax + sx, ay + sy, 1) * tint,
					b = atlas.color.linear(ax + sx, ay + sy, 2) * tint,
					a = 1.0,
					nx,
					ny,
					rough = atlas.roughness.channel(ax + sx, ay + sy, 0),
					ao = 0.75 + 0.25 * tint))
	t

# A tuft of grass: blades of the atlas (9 side by side, each the atlas's height) of several
# heights, leaning a little, rooted at the bottom edge; darker toward their roots.
fn grassTuft(atlas Material, opacity image.Image, seed i64):
	t = newTile()
	column = atlas.color.width / 9
	for k in 0..42:
		blade = i64(hash(k, 0, seed) * 9.0).min(8)
		height = i64((0.5 + 0.5 * hash(k, 1, seed)) * size)
		width = 22 + i64(hash(k, 2, seed) * 10.0)
		x0 = i64(hash(k, 3, seed) * (size - width))
		lean = (hash(k, 4, seed) - 0.5) * 0.5
		for ty in 0..height:
			for tx in 0..width:
				sx = blade * column + tx * column / width
				sy = ty * (atlas.color.height - 1) / height
				if opacity.channel(sx, sy, 0) < 0.5: continue
				x = x0 + tx + i64(lean * (height - ty))
				if x < 0 or x >= size: continue
				y = size - height + ty
				root = f64(ty) / f64(height)
				t.put(x, y, Texel(
					r = atlas.color.linear(sx, sy, 0),
					g = atlas.color.linear(sx, sy, 1),
					b = atlas.color.linear(sx, sy, 2),
					a = 1.0,
					nx = atlas.normal.channel(sx, sy, 0) * 2.0 - 1.0,
					ny = atlas.normal.channel(sx, sy, 1) * 2.0 - 1.0,
					rough = atlas.roughness.channel(sx, sy, 0),
					ao = 1.0 - 0.6 * root * root))
	t

# clear glass: a pale frame, a few streaks; the rest lets everything through
fn glassPane():
	t = newTile()
	for y in 0..size:
		for x in 0..size:
			edge = x.min(y).min(size - 1 - x).min(size - 1 - y)
			streak = (x + y) % 97 < 3 and (x - y + size) % 211 < 60
			shade = 0.55 + 0.25 * hash(x, y, 7) if edge < 10 else 0.9
			t.put(x, y, Texel(
				r = shade * 0.8,
				g = shade * 0.85,
				b = shade * 0.9,
				a = 1.0 if edge < 10 or streak else 0.0,
				nx = 0.0,
				ny = 0.0,
				rough = 0.1, ao = 1.0))
	t

# water's own color (its waves and its mirror are the shader's)
fn waterSurface():
	t = newTile()
	for y in 0..size:
		for x in 0..size:
			n = 0.85 + 0.15 * hash(x / 8, y / 8, 11)
			put(
				t,
				x,
				y,
				Texel(
					r = 0.02 * n,
					g = 0.09 * n,
					b = 0.12 * n,
					a = 1.0,
					nx = 0.0,
					ny = 0.0,
					rough = 0.05,
					ao = 1.0
				)
			)
	t

# ---------- the program ----------

fn save(move t Tile, name str):
	saveImage(t.color, "{name}.png")
	saveImage(t.surface, "{name}_surface.png")
	print("wrote {name}")

fn saveImage(move picture image.Image, file str):
	path = "projects/minecraft/assets/blocks/{file}"
	picture.savePng(path) ?? fail("cannot write {path}")

a = args
if a.len < 1:
	fail("usage: zap run projects/minecraft/makeTextures.zap <dir of the unzipped 1K-PNG sets>")
dir = a[0]
_ = fs.createDir("projects/minecraft/assets/blocks")
grass = tileOf(readMaterial(dir, "Grass004"), 1.0)
dirt = tileOf(readMaterial(dir, "Ground048"), 1.0)
stone = tileOf(readMaterial(dir, "Rock030"), 1.0)
snow = tileOf(readMaterial(dir, "Snow010A"), 1.0)
leafAtlas = readMaterial(dir, "LeafSet024")
# every layer of world.tileNames; the four the others are made from last, given away
for name in world.tileNames:
	match name:
		"grass_top", "dirt", "stone", "snow": pass
		"dirt_grass": save(dirt.coveredSide(grass, 3), name)
		"sand": save(tileOf(readMaterial(dir, "Ground080"), 1.0), name)
		"trunk_side": save(tileOf(readMaterial(dir, "Bark014"), 1.0), name)
		"trunk_top": save(tileOf(readMaterial(dir, "TreeEnd003"), 0.6), name)
		"leaves_transparent": save(
			leafAtlas.scatteredLeaves(image.loadPng("{dir}/LeafSet024_1K-PNG_Opacity.png"), 5),
			name
		)
		"wood": save(tileOf(readMaterial(dir, "Planks037A"), 1.0), name)
		"brick_red": save(tileOf(readMaterial(dir, "Bricks075A"), 1.0), name)
		"glass": save(glassPane(), name)
		"water": save(waterSurface(), name)
		"dirt_snow": save(dirt.coveredSide(snow, 9), name)
		"stone_coal": save(stone.oreIn(0.03, 0.028, 0.03, 0.3, 13), name)
		"tall_grass": save(
			grassTuft(readMaterial(dir, "Foliage001"), image.loadPng("{dir}/Foliage001_1K-PNG_Opacity.png"), 21),
			name
		)
		"stone_iron": save(stone.oreIn(0.35, 0.16, 0.08, 0.6, 17), name)
		_: save(tileOf(readMaterial(dir, "Gravel023"), 1.0), name)
save(grass, "grass_top")
save(dirt, "dirt")
save(stone, "stone")
save(snow, "snow")
