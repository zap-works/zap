# The meshes of a chunk: a quad for each face of a block that something see-through lies beside,
# each corner one 32-bit word (vertexWord) that the world's vertex shader unpacks: where the
# corner is in the chunk, the texture's corner, the face, the material, how shut in the corner
# is (ambient occlusion, as Minecraft does it) and the texture layer. Water goes in a mesh of
# its own, drawn translucent.

import graphics.shaders

# the six faces: their normals, then their corners (block-relative, counterclockwise seen from
# outside, from the bottom-left of the texture)
faceNormals = [1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1]
faceCorners = [
	1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 1, 1,
	0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 0,
	0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 0,
	0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1,
	0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1,
	1, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0]
# the texture's corners, matching the face's: u 0 1 1 0, v 1 1 0 0
cornerU = [0, 1, 1, 0]
cornerV = [1, 1, 0, 0]

pub materialSolid = 0
pub materialLeaves = 1
pub materialWater = 2
pub materialLine = 3
# the face a plant's quads carry: lit as if facing up, swaying from their roots
pub plantFace = 6
# a plant's two crossed quads, each from both sides: their corners (block-relative), counterclockwise
plantCorners = [
	0, 0, 0, 1, 0, 1, 1, 1, 1, 0, 1, 0,
	1, 0, 1, 0, 0, 0, 0, 1, 0, 1, 1, 1,
	1, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 0,
	0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1]

pub type ChunkMesh:
	solid shaders.CornerWord[]   # four per face (a quad)
	water shaders.CornerWord[]

# A corner as one word: its parts packed (shaders.CornerParts)
pub fn vertexWord(
	x i64,
	y i64,
	z i64,
	u i64,
	v i64,
	face i64,
	material i64,
	open i64,
	layer i64
) shaders.CornerWord:
	parts = shaders.CornerParts(
		x = shaders.Across(x),
		y = shaders.Up(y),
		z = shaders.Across(z),
		u = u != 0,
		v = v != 0,
		face = shaders.FaceKind(face),
		material = shaders.Quarter(material),
		open = shaders.Quarter(open),
		layer = shaders.TextureLayer(layer)
	)
	shaders.CornerWord(word = parts.toBits())

# A chunk's blocks with a border of one block from the chunks around it (air above and below
# the world, and where a chunk is not made): every block of the chunk then reads its neighbors
# by a step in the list. The mesher needs nothing else, so it runs on any thread.
pub type Padded:
	blocks u8[]   # index ((y + 1) * paddedSide + z + 1) * paddedSide + x + 1

paddedSide = chunkSize + 2
paddedLayer = paddedSide * paddedSide

fn paddedIndex(x i64, y i64, z i64):
	((y + 1) * paddedSide + z + 1) * paddedSide + x + 1

# the blocks of chunk cx, cz and its border, copied out of the world
pub fn paddedChunk(w World, cx i64, cz i64) Padded:
	out = Padded(blocks = zeros(paddedLayer * (height + 2)))
	for dz in -1..2:
		for dx in -1..2:
			s = w.slotOf(cx + dx, cz + dz)
			if s < 0: continue
			# the part of that chunk inside the border: all of it in the middle, a row or a
			# column of it at the sides
			xa = chunkSize - 1 if dx < 0 else 0
			xb = 1 if dx > 0 else chunkSize
			za = chunkSize - 1 if dz < 0 else 0
			zb = 1 if dz > 0 else chunkSize
			for y in 0..height:
				for z in za..zb:
					source = (y * chunkSize + z) * chunkSize
					to = paddedIndex(dx * chunkSize, y, dz * chunkSize + z)
					for x in xa..xb:
						out.blocks[to + x] = w.slots[s].blocks[source + x]
	out

# the meshes of a chunk from its padded blocks
pub fn meshPadded(p Padded) ChunkMesh:
	out = ChunkMesh(solid = [], water = [])
	# the step in the list to each face's neighbor
	steps i64[6]
	steps[0] = 1
	steps[1] = -1
	steps[2] = paddedLayer
	steps[3] = -paddedLayer
	steps[4] = paddedSide
	steps[5] = -paddedSide
	for y in 0..height:
		for z in 0..chunkSize:
			row = paddedIndex(0, y, z)
			for x in 0..chunkSize:
				b = i64(p.blocks[row + x])
				if b != air:
					p.blockFaces(out, x, y, z, row + x, b, steps)
	out

# the meshes of chunk cx, cz of the world
pub fn meshChunk(w World, cx i64, cz i64) ChunkMesh:
	w.paddedChunk(cx, cz).meshPadded()

# the faces of block b at x, y, z of the chunk, index i in the padded blocks
fn blockFaces(p Padded, mut out ChunkMesh, x i64, y i64, z i64, i i64, b i64, steps i64[6]):
	if b == tallGrass:
		plant(out.solid, x, y, z, faceLayer(b, 0))
		return
	for f in 0..6:
		n = i64(p.blocks[i + steps[f]])
		# hidden behind an opaque block, or inside a body of its own see-through kind
		if isOpaque(n) or (n == b and not isOpaque(b)): continue
		open i64[4]
		if b == water:
			for c in 0..4:
				open[c] = 3
			face(out.water, x, y, z, b, f, open)
		else:
			for c in 0..4:
				open[c] = p.openness(i + steps[f], f, c, steps)
			face(out.solid, x, y, z, b, f, open)

# the quad of face f of the block at x, y, z of the chunk, how open each corner is given
fn face(mut words shaders.CornerWord[], x i64, y i64, z i64, b i64, f i64, open i64[4]):
	layer = faceLayer(b, faceNormals[f * 3 + 1])
	material = materialLeaves if b == leaves else materialWater if b == water else materialSolid
	# The quad is drawn as triangles 0 1 2 and 0 2 3 of its words; when the other diagonal
	# joins the brighter corners it starts at corner 1 instead, so a shadow does not bend.
	first = 0 if open[0] + open[2] >= open[1] + open[3] else 1
	for k in 0..4:
		c = (first + k) % 4
		at = f * 12 + c * 3
		words.push(
			vertexWord(
				x + faceCorners[at],
				y + faceCorners[at + 1],
				z + faceCorners[at + 2],
				cornerU[c],
				cornerV[c],
				f,
				material,
				open[c],
				layer
			)
		)

# How open corner c of face f is (3 open .. 0 shut in): the blocks in the layer before the face
# that touch the corner (two beside it, one across) shut it in; both beside shut it in fully.
# `front` is the index of the block in front of the face, its neighbors read by their steps.
fn openness(p Padded, front i64, f i64, c i64, steps i64[6]):
	at = f * 12 + c * 3
	axis = f / 2   # the faces go +x -x +y -y +z -z
	a1 = (axis + 1) % 3
	a2 = (axis + 2) % 3
	# toward the corner along the face's two axes: a step forward or back
	s1 = steps[a1 * 2] if faceCorners[at + a1] == 1 else steps[a1 * 2 + 1]
	s2 = steps[a2 * 2] if faceCorners[at + a2] == 1 else steps[a2 * 2 + 1]
	side1 = isOpaque(p.blocks[front + s1])
	side2 = isOpaque(p.blocks[front + s2])
	if side1 and side2: return 0
	corner = isOpaque(p.blocks[front + s1 + s2])
	3 - (1 if side1 else 0) - (1 if side2 else 0) - (1 if corner else 0)

# the quads of a plant at x, y, z (in the chunk)
fn plant(mut words shaders.CornerWord[], x i64, y i64, z i64, layer i64):
	for q in 0..4:
		for c in 0..4:
			at = q * 12 + c * 3
			words.push(
				vertexWord(
					x + plantCorners[at],
					y + plantCorners[at + 1],
					z + plantCorners[at + 2],
					cornerU[c],
					cornerV[c],
					plantFace,
					materialLeaves,
					3,
					layer
				)
			)

# a box's 12 edges, as pairs of corners numbered by their bits: 1 x, 2 y, 4 z
boxEdges = [0, 1, 2, 3, 4, 5, 6, 7, 0, 2, 1, 3, 4, 6, 5, 7, 0, 4, 1, 5, 2, 6, 3, 7]

# the outline of block x, y, z as 12 lines, relative to its chunk's x0, z0
pub fn outlineWords(x i64, y i64, z i64, x0 i64, z0 i64) shaders.CornerWord[]:
	words shaders.CornerWord[] = []
	words.reserve(boxEdges.len)
	for c in boxEdges:
		words.push(
			vertexWord(
				x - x0 + (c & 1),
				y + c.bits(1, 1),
				z - z0 + c.bits(2, 1),
				0,
				0,
				0,
				materialLine,
				0,
				0
			)
		)
	words
