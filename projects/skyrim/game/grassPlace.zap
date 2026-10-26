# Where the grass grows, as SkyrimSE.exe's BGSGrassManager places it (AddCellGrass 0x140206d40, its
# placement of one vertex's square 0x140209020, the vertex's grass types 0x1402afb20), deterministic
# from the game's own seed rule: the cell's random generator (a Mersenne twister of the engine's, its
# rand 0x140ce44e0) is seeded with the cell's x times its y, and every draw below is made in the
# order the game makes it, so the plants stand where the game's stand.
#
# A cell's four quadrants of 17 x 17 vertices are visited at their odd columns and rows (a square of
# 256 units about each of 64 vertices a quadrant). A vertex's grass is that of its quadrant's base
# texture and of every layer one of whose nine neighbouring vertices holds more than 25 of 255; its
# density at each of the nine is the grass's percent when the layer covers the vertex at all. The
# square is cut into n x n sub-squares (n the least of 256 / iMinGrassSize and 256 / the grass's
# position range), each given a jittered plant with the chance the density, bilinear over the nine,
# says; the plant's place is kept as 16 bit floats about the origin of the block of 12 x 12 cells
# (rounded toward zero) the cell is in, and tested against the land there (slope by the nearest
# vertex's normal, the water's state), then given a shade, a turn, a basis (the slope's, for a grass
# that fits it) and a scale.

import skyrim.esm

# the cell's size, a vertex's spacing and a quadrant's side in units
cellSide f32 = 4096.0
vertexSpacing f32 = 128.0
quadrantSide = 17

# the vertices' neighbours in a quadrant's 17 x 17: row by row from the south west
neighbourOffsets = [-18, -17, -16, -1, 0, 1, 16, 17, 18]

# the settings read here, their defaults the executable's
grassSquare f32 = 256.0   # twice the manager's 128: the square a vertex covers
minGrassSize f32 = 20.0   # iMinGrassSize:Grass
grassTypesPerTexture = 2   # iMaxGrassTypesPerTexure:Grass (a list gives one more: the executable's loop)
layerFloor f32 = 25.0   # a layer is looked at where a neighbour has more of it than this
gridSquare = 12   # cells a block of grass groups

# ---------- the engine's random generator ----------

# The engine's twister (0x140ce4460 seeds it, 0x140ce44e0 draws): 624 words of state, one before
# them unused, the index after them. Its seed and its regeneration are not the standard twister's;
# the code below is the executable's.
pub type Twister:
	words u32[]   # [0] unused, [1..624] the state, [625] the index

# the generator seeded with `seed`
pub fn seededTwister(seed u32) Twister:
	words u32[] = fill(626, 0)
	words[1] = seed
	for k in 1..624:
		before = words[k]
		words[k + 1] = (((before >> 30) + u32(k)) ^ before) * 0x6c07_8965
	words[625] = 623
	Twister(words)

fn regenerate(mut t Twister):
	for k in 0..624:
		next = t.words[k + 2]
		current = t.words[k + 1]
		mixed = next % 624 + (current & 1)
		value = t.words[(k + 397) % 624 + 1] ^ (mixed << 1)
		t.words[k + 1] = (value ^ 0x9908_b0df) if (mixed & 1) != 0 else value
	t.words[625] = 0

# The next draw below `range`; a range of 0xffffffff or 0x7fff keeps the word's low bits instead.
pub fn nextBelow(mut t Twister, range u32) u32:
	if range == 0: return 0
	index = t.words[625]
	if index == 0: t.regenerate()
	word = t.words[i64(index) + 1]
	t.words[625] = (index + 1) % 624
	word ^= word >> 11
	word ^= (word & 0xff3a_58ad) << 7
	word ^= (word & 0xffff_df8c) << 15
	word ^= word >> 18
	if ((range + 1) & 0xffff_7fff) != 0: return word % range
	word & range

# ---------- 16 bit floats, as the instance data keeps them ----------

# the half float the executable makes of a float (0x140fde800: rounded to nearest, ties to even)
pub fn halfOf(f f32) u32:
	bits = f.toBits()
	magnitude = bits & 0x7fff_ffff
	sign = (bits >> 16) & 0x8000
	if magnitude > 0x477f_e000:
		if (bits & 0x7f80_0000) != 0x7f80_0000 or (bits & 0x7f_ffff) == 0: return 0x7c00 | sign
		return 0x7fff | sign
	if magnitude == 0: return sign
	value = magnitude
	if magnitude < 0x3880_0000:
		value = ((bits & 0x7f_ffff) | 0x80_0000) >> ((0x71 - (magnitude >> 23)) & 0x1f)
	else:
		value = magnitude - 0x3800_0000
	((value + 0xfff + ((value >> 13) & 1)) >> 13 & 0x7fff) | sign

# the float a half float stands for
pub fn halfValue(h u32) f32:
	sign = (h & 0x8000) << 16
	exponent = (h >> 10) & 0x1f
	mantissa = h & 0x3ff
	if exponent == 0x1f: return f32.fromBits(sign | 0x7f80_0000 | (mantissa << 13))
	if exponent == 0:
		if mantissa == 0: return f32.fromBits(sign)
		shift = 0
		m = mantissa
		while (m & 0x400) == 0:
			m <<= 1
			shift += 1
		return f32.fromBits(sign | ((113 - u32(shift)) << 23) | ((m & 0x3ff) << 13))
	f32.fromBits(sign | ((exponent + 112) << 23) | (mantissa << 13))

# ---------- the cosine table the slopes are read from ----------

# cos(k x 2 pi / 512), k from 0 to 511, the angle a sum of steps in single precision as the
# executable builds its table (0x140ef2ca0)
pub fn cosineTable() f32[]:
	step f32 = 0.012271846644580364
	angle = 0.0
	out = []
	loop 512:
		out.push(angle.cos())
		angle += step
	out

# the table's cosine of a slope in degrees (an index of degrees x 512 / 360, kept to 9 bits)
fn slopeCosine(table f32[], degrees f32):
	table[i64(degrees * 1.4222221) & 0x1ff]

# ---------- the land under a plant ----------

# the cells' lands the placement reads: its own and the neighbours a rounded plant can fall into
pub type LandMap:
	cells {i64: esm.Land}

pub fn landKey(x i64, y i64) i64:
	(x + 4096) * 8192 + (y + 4096)

# a cell's land and its neighbours' (the cells a plant of the block can reach), read once
pub fn landsAround(mut plugin esm.Esm, world i64, x i64, y i64) LandMap:
	cells {i64: esm.Land} = {}
	for dy in -1..=1:
		for dx in -1..=1:
			if plugin.landOf(world, x + dx, y + dy) is l: cells[landKey(x + dx, y + dy)] = l
	LandMap(cells)

fn floorCell(v f32) i64:
	i64((v / cellSide).floor())

# the index of the square or quadrant a distance falls in, a distance on a border (a multiple, not
# 0) belonging to the lower one (0x1402aeef0)
fn indexOf(distance f32, size i64):
	at = i64(distance)
	k = i64(distance / f32(size))
	if at != 0 and at % size == 0: return k - 1
	k

# What the land holds at a point: its height, the nearest vertex's normal and color (VNML, VCLR) of
# the three vertices of the triangle under it. None where no cell of the map has land there.
pub type Surface:
	height f32
	normal Vec3
	color Vec3

pub fn surfaceAt(m LandMap, x f32, y f32) Surface?:
	cx = floorCell(x)
	cy = floorCell(y)
	if m.cells.get(landKey(cx, cy)) is land:
		return surfaceIn(land, x - f32(cx) * cellSide, y - f32(cy) * cellSide)
	none

# the surface at (lx, ly) from the south west corner of this cell's land
fn surfaceIn(land esm.Land, lx f32, ly f32) Surface?:
	if lx > cellSide or ly > cellSide: return none
	qx = indexOf(lx, 2048).clamp(0, 1)
	qy = indexOf(ly, 2048).clamp(0, 1)
	col = indexOf(lx - f32(qx * 2048), 128).clamp(0, 15) + qx * 16
	row = indexOf(ly - f32(qy * 2048), 128).clamp(0, 15) + qy * 16
	u = (lx - f32(col) * vertexSpacing) / vertexSpacing
	v = (ly - f32(row) * vertexSpacing) / vertexSpacing
	at = row * 33 + col
	lowerLeft = at
	lowerRight = at + 1
	upperLeft = at + 33
	upperRight = at + 34
	h = land.heights
	corners = []
	height = 0.0
	if (row + col) % 2 == 0:
		if u <= v:
			corners = [upperLeft, lowerLeft, upperRight]
			height = h[lowerLeft] + v * (h[upperLeft] - h[lowerLeft]) +
				u * (h[upperRight] - h[upperLeft])
		else:
			corners = [lowerRight, lowerLeft, upperRight]
			height = h[lowerLeft] + u * (h[lowerRight] - h[lowerLeft]) +
				v * (h[upperRight] - h[lowerRight])
	else:
		if u + v > 1.0:
			corners = [upperRight, lowerRight, upperLeft]
			height = h[upperRight] + (1.0 - u) * (h[upperLeft] - h[upperRight]) +
				(1.0 - v) * (h[lowerRight] - h[upperRight])
		else:
			corners = [lowerLeft, lowerRight, upperLeft]
			height = h[lowerLeft] + u * (h[lowerRight] - h[lowerLeft]) +
				v * (h[upperLeft] - h[lowerLeft])
	nearest = corners[0]
	nearestDistance = 3.4028235e38
	for c in corners:
		dx = f32(c % 33) * vertexSpacing - lx
		dy = f32(c / 33) * vertexSpacing - ly
		d = dy * dy + dx * dx
		if d < nearestDistance:
			nearest = c
			nearestDistance = d
	Surface(height, normal = land.normals[nearest], color = land.colors[nearest])
