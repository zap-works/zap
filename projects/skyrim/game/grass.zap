# The grass of the exterior cells (the placement is game/grassPlace.zap): each plant a place, a
# shade, a basis and a scale, grouped by the kind of grass, to draw as the executable's grass
# shader does (world/grass.zap). The way in, for the cell agent:
#
#   g = install.grassOf(plugin, world, x0, y0, x1, y1)     the cells' grass
#   sc.showGrass(g)                                          into the cell's scene

import skyrim
import skyrim.esm
import skyrim.nif
import world
import world.shaders

# one plant, as the game's instance data holds it (its 16 half floats), decoded
pub type Plant:
	place Vec3   # in the game's space: the block's origin and the stored x and y
	shade f32   # the colour's brightness the land and the dice give it
	rows f32[]   # the basis: the three rows of the matrix that turns the model, x then y then z
	delta f32   # how much taller the dice make it (a scale of 1 + delta, along z or every axis)
	phase f32   # the wind's phase: (stored x + stored y) x -1/128

# the plants of one kind of grass
pub type Planted:
	grass esm.Grass
	plants Plant[]

# the weights of a grass at the nine vertices about a vertex
type VertexGrass:
	grass esm.Grass
	weights f32[]

# a quadrant's layers' coverage by vertex, in bytes (as the land keeps them), and what each lays
type QuadrantCover:
	bytes (f32[])[]   # by layer slot 0..5, 289 vertices each (terrain.zap's byteOf)
	textures i64[]   # the layer slot's LTEX, 0 for none

fn coverOf(l esm.Land, quadrant i64):
	bytes = []
	textures = []
	loop 6:
		zeros f32[] = fill(quadrantSide * quadrantSide, 0.0)
		bytes.push(zeros)
		textures.push(0)
	for layer in l.layers.filter(.quadrant == quadrant and .order < 6):
		textures[layer.order] = layer.texture
		for k, opacity in layer.opacity:
			bytes[layer.order][k] = byteOf(opacity)
	QuadrantCover(bytes, textures)

# the share of the base texture at a vertex: one less the layers' (FUN_1402aae40)
fn baseShare(c QuadrantCover, vertex i64):
	total = 0.0
	for slot in 0..5:
		total += c.bytes[slot][vertex]
	1.0 - total * 0.003921569

# a list of grass, each as many as the executable's loop takes (one more than the setting)
fn listed(mut plugin esm.Esm, ltex i64):
	out = []
	if ltex == 0: return out
	t = plugin.landTexture(ltex) ?? return out
	for form in t.grass:
		if out.len > grassTypesPerTexture: break
		if plugin.grassOf(form) is g: out.push(g)
	out

# the grass at the vertex of a quadrant, base texture first then the layers in order, each with its
# weight at the nine vertices about it (0x1402afb20)
fn vertexGrass(
	mut plugin esm.Esm,
	l esm.Land,
	quadrant i64,
	cover QuadrantCover,
	vertex i64
):
	out = []
	for g in plugin.listed(l.base[quadrant]):
		weights = []
		for offset in neighbourOffsets:
			share = cover.baseShare(vertex + offset)
			weights.push(g.density * 0.01 if share > 0.0 else 0.0)
		out.push(VertexGrass(g, weights))
	for slot in 0..6:
		if cover.textures[slot] == 0: continue
		reaches = false
		for offset in neighbourOffsets:
			if cover.bytes[slot][vertex + offset] > layerFloor: reaches = true
		if not reaches: continue
		for g in plugin.listed(cover.textures[slot]):
			weights = []
			for offset in neighbourOffsets:
				weights.push(g.density * 0.01 if cover.bytes[slot][vertex + offset] > 0.0 else 0.0)
			out.push(VertexGrass(g, weights))
	out

# the rows of the turn about z whose sine is s and cosine c, and of the turn that takes z to the
# normal and the plant's turn on it (0x140209020's basis, stored as the executable lays it out)
fn basisOf(fits bool, normal Vec3, s f32, c f32):
	if not fits: return [s, -c, 0.0, c, s, 0.0, 0.0, 0.0, 1.0]
	ax = normal.x.abs()
	ay = normal.y.abs()
	az = normal.z.abs()
	t = Vec3(0.0, 0.0, 0.0)
	if not (ax > ay) and not (ax > az):
		t = Vec3(0.0, -normal.z, normal.y)
	elif not (ay > ax) and not (ay > az):
		t = Vec3(-normal.z, 0.0, normal.x)
	else:
		t = Vec3(-normal.y, normal.x, 0.0)
	length = (t.x * t.x + t.y * t.y + t.z * t.z).sqrt()
	if length > 0.000001:
		k = 1.0 / length
		t = Vec3(t.x * k, t.y * k, t.z * k)
	else:
		t = Vec3(0.0, 0.0, 0.0)
	b = Vec3(
		normal.z * t.y - normal.y * t.z,
		normal.x * t.z - normal.z * t.x,
		normal.y * t.x - normal.x * t.y
	)
	p = Vec3(c * t.x + s * b.x, c * t.y + s * b.y, c * t.z + s * b.z)
	q = Vec3(s * t.x - c * b.x, s * t.y - c * b.y, s * t.z - c * b.z)
	[p.x, q.x, normal.x, p.y, q.y, normal.y, p.z, q.z, normal.z]

# The plants of one grass in the 256 unit square whose south west corner is `corner`, the draws
# taken from the cell's generator in the game's order. `block` is the origin of the block of cells
# the cell is in.
fn plantSquare(
	mut rng Twister,
	g VertexGrass,
	corner Vec2,
	block Vec2,
	lands LandMap,
	cosines f32[],
	waterHeight f32,
	mut out Plant[]
):
	grass = g.grass
	count = i64(grassSquare / minGrassSize)
	if grass.positionRange > 0.0: count = count.min(i64(grassSquare / grass.positionRange))
	if count == 0: return
	step = 1.0 / f32(count)
	half = grassSquare * step * 0.5
	coolest = slopeCosine(cosines, grass.maxSlope)
	warmest = slopeCosine(cosines, grass.minSlope)
	w = g.weights
	for i0 in 0..count:
		along = 0.5 + f32(i0)
		x0 = (half + half) * along + corner.x
		twice = step + step
		px = twice * along
		xi = i64(px)
		fx = px - f32(xi)
		for i1 in 0..count:
			across = 0.5 + f32(i1)
			y0 = across * half + across * half + corner.y
			py = twice * across
			yi = i64(py)
			fy = py - f32(yi)
			k = xi + yi * 3
			mix = ((1.0 - fx) * w[k] + w[k + 1] * fx) * (1.0 - fy) +
				((1.0 - fx) * w[k + 3] + w[k + 4] * fx) * fy
			threshold = i64(mix * 32768.0)
			if threshold == 0: continue
			if rng.nextBelow(0x7fff) >= threshold: continue
			r1 = rng.nextBelow(0xffff_ffff)
			r2 = rng.nextBelow(0xffff_ffff)
			jx = f32(r1) * 0.00000000046566129 - 1.0
			jy = f32(r2) * 0.00000000046566129 - 1.0
			hx = halfOf((jx * half + x0) - block.x)
			hy = halfOf((jy * half + y0) - block.y)
			qx = halfValue(hx)
			qy = halfValue(hy)
			at = Vec2(block.x + qx, block.y + qy)
			s = lands.surfaceAt(at.x, at.y) ?? continue
			if not grass.waterAllows(s.height, waterHeight): continue
			if s.normal.z < coolest or s.normal.z > warmest: continue
			luma = s.color.x * 0.31 + s.color.y * 0.37 + s.color.z * 0.32
			r3 = rng.nextBelow(0xffff_ffff)
			shaded = luma * ((f32(r3) * 0.00000000011641532 - 0.25) * grass.colorRange +
					(1.0 - grass.colorRange))
			shade = f32(0.99) if shaded >= 1.0 else shaded.max(0.0)
			r4 = rng.nextBelow(0xffff_ffff)
			sine = f32(r4) * 0.00000000046566129 - 1.0
			cosine = (1.0 - sine * sine).sqrt()
			r5 = rng.nextBelow(0xffff_ffff)
			delta = (f32(r5) * 0.00000000046566129 - 1.0) * grass.heightRange
			rows = basisOf((grass.flags & esm.flagFitSlope) != 0, s.normal, sine, cosine)
			stored = rows.map(halfValue(halfOf(it)))
			out.push(
				Plant(
					place = Vec3(at.x, at.y, halfValue(halfOf(s.height))),
					shade = halfValue(halfOf(shade)),
					rows = stored,
					delta = halfValue(halfOf(delta)),
					phase = (qx + qy) * -0.0078125
				)
			)

# how the water's state limits a grass at a height (0x140209020's switch); the states above 5
# let it grow anywhere
fn waterAllows(g esm.Grass, height f32, water f32):
	d = g.waterDistance
	match g.waterState:
		0: water - d <= height
		1: height >= water and height <= water + d
		2: height <= water - d
		3: height <= water and height >= water - d
		4: height >= water + d or height <= water - d
		5: height <= water + d and height >= water - d
		_: true

# The plants of the cell: its generator seeded with its x times its y, then the vertices of each
# quadrant visited column by column, row by row up each, every grass of a vertex planted in turn.
pub fn plantsOfCell(
	mut plugin esm.Esm,
	world i64,
	x i64,
	y i64,
	lands LandMap,
	cosines f32[],
	mut into {i64: Plant[]}
):
	if lands.cells.get(landKey(x, y)) is land:
		plugin.plantsIn(world, x, y, land, lands, cosines, into)

fn plantsIn(
	mut plugin esm.Esm,
	world i64,
	x i64,
	y i64,
	land esm.Land,
	lands LandMap,
	cosines f32[],
	mut into {i64: Plant[]}
):
	rng = seededTwister(u32.wrap(x * y))
	water = plugin.waterHeightOf(world, x, y)
	block = Vec2(
		f32(x / gridSquare * gridSquare) * cellSide,
		f32(y / gridSquare * gridSquare) * cellSide
	)
	for quadrant in 0..4:
		cover = land.coverOf(quadrant)
		origin = Vec2(
			f32(x) * cellSide + f32(quadrant % 2) * 2048.0,
			f32(y) * cellSide + f32(quadrant / 2) * 2048.0
		)
		for column in (1..16).filter(it % 2 == 1):
			for row in (1..16).filter(it % 2 == 1):
				vertex = row * quadrantSide + column
				corner = Vec2(
					origin.x + f32(column) * vertexSpacing - 128.0,
					origin.y + f32(row) * vertexSpacing - 128.0
				)
				for g in plugin.vertexGrass(land, quadrant, cover, vertex):
					fresh = []
					rng.plantSquare(g, corner, block, lands, cosines, water, fresh)
					if into.get(g.grass.formId) == none: into[g.grass.formId] = []
					into[g.grass.formId].extend(fresh)

# ---------- the grass of a set of cells ----------

# The land's cells' grass: each kind with its model (the game's axes), its texture, and its plants.
pub type Grassland:
	kinds Planted[]
	models world.GrassModel[]
	textures world.PreparedTexture[]
	body u8[]
	count i64

# the grass model's first part with a triangle: vertices and indices, its texture's path
fn modelOf(
	install skyrim.Install,
	g esm.Grass,
	mut table TextureTable,
	mut body u8[]
) world.GrassModel?:
	key = skyrim.modelKey(g.model)
	n = install.readModel(key) ?? return none
	for part in n.drawParts():
		if part.indices.isEmpty: continue
		vertices = []
		for k, at in part.positions:
			vertices.push(
				shaders.GrassVertex(
					position = at,
					uv = part.uvs[k] if k < part.uvs.len else Vec2(0.0, 0.0),
					color = part.colors[k] if k < part.colors.len else Vec4(1.0, 1.0, 1.0, 1.0)
				)
			)
		texture = table.textureIndex(install, part.diffuse, flatDiffuse, body)
		return world.GrassModel(vertices, indices = part.indices.copy(), texture = f32(texture))
	none

# The grass of the cells x0..x1, y0..y1 (inclusive) of the world: the land of the cells and their
# neighbours read, every plant placed with the cells' own generators.
pub fn grassOf(
	install skyrim.Install,
	mut plugin esm.Esm,
	world i64,
	x0 i64,
	y0 i64,
	x1 i64,
	y1 i64
) Grassland:
	body = []
	table = newTextureTable(body)
	lands = LandMap(cells = {})
	for y in y0 - 1..=y1 + 1:
		for x in x0 - 1..=x1 + 1:
			if plugin.landOf(world, x, y) is l: lands.cells[landKey(x, y)] = l
	cosines = cosineTable()
	found {i64: Plant[]} = {}
	for y in y0..=y1:
		for x in x0..=x1:
			plugin.plantsOfCell(world, x, y, lands, cosines, found)
	out = Grassland(kinds = [], models = [], textures = [], body = [], count = 0)
	for form in found.keys().sorted():
		g = plugin.grassOf(form) ?? continue
		model = install.modelOf(g, table, body) ?? continue
		plants = (found.get(form) ?? []).copy()
		out.count += plants.len
		out.kinds.push(Planted(g, plants))
		out.models.push(model)
	out.textures = table.textures.copy()
	out.body = body
	out

# a plant as the shader reads it, of the kind with this number
fn instanceOf(p Plant, kind i64):
	r = p.rows
	shaders.GrassInstance(
		place = p.place.withW(p.shade),
		rowX = Vec4(r[0], r[1], r[2], p.phase),
		rowY = Vec4(r[3], r[4], r[5], p.delta),
		rowZ = Vec4(r[6], r[7], r[8], f32(kind))
	)

# the grass in the scene: its textures sent to the GPU, each kind drawn as instances of its model
pub fn showGrass(mut sc world.CellScene, g Grassland, wind f32):
	textures = g.textures.map(world.gpuTexture(g.body, it))
	kinds = []
	for k, planted in g.kinds:
		kinds.push(
			world.GrassKind(
				model = g.models[k].copy(),
				instances = planted.plants.map(.instanceOf(k)),
				wavePeriod = planted.grass.wavePeriod,
				uniform = (planted.grass.flags & esm.flagUniformScale) != 0
			)
		)
	sc.addGrass(kinds, textures, wind)
