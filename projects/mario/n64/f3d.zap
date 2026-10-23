# Fast3D, the drawing commands the game's models are stored as (the US version's microcode): a
# display list loads vertices into a buffer of 16, sets the state (geometry mode, textures and
# their tiles, the color combiner, lights) and draws triangles from the buffer. Here a list is
# read once and its triangles become batches: one per material (the state that shapes how they
# look), each a list of vertices for the engine, the textures decoded to RGBA8 alongside.
#
# A vertex for the engine is ten floats: its place (transformed by the draw's matrix), its color
# (or, lit, its normal), its texture coordinates and alpha, and a spare.

import image

# how a batch looks: what the color combiner takes (codes, graphics/shaders/n64.zap), its texture, layer and state
pub type Material:
	texture i64   # an index of Converted.textures, -1 none
	layer i64   # the geo layer: 1 opaque, 2 decal, 4 cut out, 5 to 7 blended...
	cullBack bool
	lit bool   # shaded by the lights: the vertices hold normals
	colorSel i64   # the combiner's (a - b) * c + d for color: four codes, 8 bits each
	alphaSel i64   # the same for alpha
	prim i64   # RGBA8888
	env i64
	wrapS i64   # 0 repeat, 1 mirror, 2 clamp
	wrapT i64
	smooth bool   # bilinear filtering
	ambient i64   # lit: RGB888 of the ambient light, the directional one, its direction (3 s8)
	diffuse i64
	direction i64
	billboard bool   # faces the camera, turned about its anchor (the node's place)
	anchorX i64
	anchorY i64
	anchorZ i64

pub type Batch:
	material Material
	vertices f32[]

pub type Converted:
	textures image.Image[]
	batches Batch[]

pub vertexFloats = 10

# the combiner's inputs as codes (each a vec4 in the shader)
pub selZero = 0
pub selTexel = 1
pub selPrim = 2
pub selShade = 3
pub selEnv = 4
pub selOne = 5
pub selTexelAlpha = 6
pub selPrimAlpha = 7
pub selShadeAlpha = 8
pub selEnvAlpha = 9

type Vert:
	x f32
	y f32
	z f32
	s i64
	t i64
	c0 i64   # r, g, b, or the normal's x, y, z (signed)
	c1 i64
	c2 i64
	a i64
	lit bool

type Tile:
	fmt i64
	siz i64
	line i64
	tmem i64
	palette i64
	cms i64
	cmt i64
	uls i64
	ult i64
	lrs i64
	lrt i64

type TexKey:
	addr i64
	fmt i64
	siz i64
	width i64
	height i64
	palette i64

# the state of the converter while it reads lists
pub type F3d:
	out Converted
	batchOf {Material: i64}
	textureOf {TexKey: i64}
	verts Vert[]
	geometry i64
	otherL i64
	otherH i64
	combine0 i64
	combine1 i64
	texOn bool
	texTile i64
	scaleS i64
	scaleT i64
	tiles Tile[]
	timgAddr i64
	timgSiz i64
	timgWidth i64
	loadAddr i64   # the last texture load: its source, its bytes
	loadBytes i64
	loadByTile bool   # LOADTILE (a rectangle of the image) rather than LOADBLOCK
	loadUls i64
	loadUlt i64
	tlutAddr i64
	prim i64
	env i64
	lightColors i64[]
	lightDirs i64[]
	directional i64
	transform Mat4
	billboard bool
	anchor Vec3

pub fn newF3d() F3d:
	F3d(
		out = Converted(textures = [], batches = []),
		batchOf = {},
		textureOf = {},
		verts = [],
		geometry = 0,
		otherL = 0,
		otherH = 0,
		combine0 = 0,
		combine1 = 0,
		texOn = false,
		texTile = 0,
		scaleS = 0xFFFF,
		scaleT = 0xFFFF,
		tiles = [],
		timgAddr = 0,
		timgSiz = 2,
		timgWidth = 0,
		loadAddr = 0,
		loadBytes = 0,
		loadByTile = false,
		loadUls = 0,
		loadUlt = 0,
		tlutAddr = 0,
		prim = -1,
		env = -1,
		lightColors = [],
		lightDirs = [],
		directional = 1,
		transform = Mat4(1.0),
		billboard = false,
		anchor = Vec3(0.0, 0.0, 0.0))

# the state the game sets before each frame's lists (game_init.c): smooth shading, back faces
# culled, lit, one light, shade only, bilinear
fn resetState(mut f F3d):
	f.verts = fill(
		16,
		Vert(x = 0.0, y = 0.0, z = 0.0, s = 0, t = 0, c0 = 0, c1 = 0, c2 = 0, a = 0, lit = false)
	)
	f.geometry = 0x4 | 0x200 | 0x2000 | 0x2_0000
	f.otherL = 0
	f.otherH = 2 << 12
	# G_CC_SHADE: (0 - 0) * 0 + SHADE, for color and alpha (15, 31 and 7 are the slots' zeros)
	f.combine0 = 15 << 20 | 31 << 15 | 7 << 12 | 7 << 9 | 15 << 5 | 31
	f.combine1 = 15 << 28 | 4 << 15 | 7 << 12 | 4 << 9 | 15 << 24 | 4 << 6 | 7 << 21 | 7 << 18 | 7 << 3 | 4
	f.texOn = false
	f.texTile = 0
	f.tiles = fill(8, Tile(
		fmt = 0,
		siz = 2,
		line = 0,
		tmem = 0,
		palette = 0,
		cms = 0,
		cmt = 0,
		uls = 0,
		ult = 0,
		lrs = 0,
		lrt = 0
	))
	f.prim = -1
	f.env = -1
	f.lightColors = fill(8, 0x7F_7F7F)
	f.lightDirs = fill(8, 0x28 << 16 | 0x28 << 8 | 0x28)
	f.directional = 1

# The display list at `dl` (in layer `layer`, its vertices moved by `transform`) read into
# batches. A billboard keeps its vertices about its node, whose place becomes the anchor.
pub fn convertList(mut f F3d, s Segments, dl i64, layer i64, transform Mat4, billboard bool):
	f.resetState()
	f.continueList(s, dl, layer, transform, billboard)

# The display list read on from the state the last one left (a model's lists share it: a part
# drawn after another keeps the colors that one set).
pub fn continueList(mut f F3d, s Segments, dl i64, layer i64, transform Mat4, billboard bool):
	f.billboard = billboard
	f.transform = transform
	if billboard:
		f.anchor = Vec3(transform.m[12], transform.m[13], transform.m[14])
		f.transform = Mat4(1.0)
	returns = []
	at = dlAddress(dl)
	loop 1_000_000:
		w0 = s.u32At(at)
		w1 = s.u32At(at + 4)
		at += 8
		op = w0 >> 24
		if op == 0x04:
			f.loadVertices(s, w0, w1)
		elif op == 0xBF:
			f.triangle(s, layer, w1.bits(16, 8) / 10, w1.bits(8, 8) / 10, (w1 & 0xFF) / 10)
		elif op == 0x06:
			if w0.bits(16, 8) == 0:
				returns.push(at)
			at = dlAddress(w1)
		elif op == 0xB8:
			if returns.isEmpty: return
			at = returns.pop() ?? return
		elif op == 0xB6:
			f.geometry &= ~w1
		elif op == 0xB7:
			f.geometry |= w1
		elif op == 0xB9 or op == 0xBA:
			shift = w0.bits(8, 8)
			mask = ((1 << (w0 & 0xFF)) - 1) << shift
			if op == 0xB9:
				f.otherL = f.otherL & ~mask | w1
			else:
				f.otherH = f.otherH & ~mask | w1
		elif op == 0xBB:
			f.texTile = w0.bits(8, 3)
			f.texOn = (w0 & 0xFF) != 0
			f.scaleS = w1 >> 16
			f.scaleT = w1 & 0xFFFF
		elif op == 0xBC:
			if (w0 & 0xFF) == 0x02:
				f.directional = ((w1 - 0x8000_0000) / 32 - 1).max(0)
		elif op == 0x03:
			index = w0.bits(16, 8)
			if index >= 0x86 and index <= 0x94:
				slot = (index - 0x86) / 2
				f.lightColors[slot] = s.u8At(dlAddress(w1)) << 16 | s.u8At(dlAddress(w1) + 1) << 8 | u8At(
					s,
					dlAddress(w1) + 2
				)
				f.lightDirs[slot] = s.u8At(dlAddress(w1) + 8) << 16 | s.u8At(dlAddress(w1) + 9) << 8 | u8At(
					s,
					dlAddress(w1) + 10
				)
		elif op == 0xF5:
			t = w1.bits(24, 3)
			f.tiles[t].fmt = w0.bits(21, 3)
			f.tiles[t].siz = w0.bits(19, 2)
			f.tiles[t].line = w0.bits(9, 9)
			f.tiles[t].tmem = w0 & 0x1FF
			f.tiles[t].palette = w1.bits(20, 4)
			f.tiles[t].cmt = w1.bits(18, 2)
			f.tiles[t].cms = w1.bits(8, 2)
		elif op == 0xF2:
			t = w1.bits(24, 3)
			f.tiles[t].uls = w0.bits(12, 12)
			f.tiles[t].ult = w0 & 0xFFF
			f.tiles[t].lrs = w1.bits(12, 12)
			f.tiles[t].lrt = w1 & 0xFFF
		elif op == 0xFD:
			f.timgSiz = w0.bits(19, 2)
			f.timgWidth = (w0 & 0xFFF) + 1
			f.timgAddr = dlAddress(w1)
		elif op == 0xF3:
			f.loadAddr = f.timgAddr
			f.loadBytes = (w1.bits(12, 12) + 1) * bitsPerTexel(f.timgSiz) / 8
			f.loadByTile = false
		elif op == 0xF4:
			f.loadAddr = f.timgAddr
			f.loadByTile = true
			f.loadUls = w0.bits(12, 12) >> 2
			f.loadUlt = (w0 & 0xFFF) >> 2
		elif op == 0xF0:
			f.tlutAddr = f.timgAddr
		elif op == 0xFA:
			f.prim = w1
		elif op == 0xFB:
			f.env = w1
		elif op == 0xFC:
			f.combine0 = w0 & 0xFF_FFFF
			f.combine1 = w1
	fail("display list at {dl}: no end")

# the batches read so far, given away (the textures stay, shared by what is read next)
pub fn takeBatches(mut f F3d) Batch[]:
	out = move f.out.batches
	f.out.batches = []
	f.batchOf.clear()
	out

# a display list's address as the graphics chip sees it (16 segments)
fn dlAddress(a i64):
	a.bits(24, 4) << 24 | (a & 0xFF_FFFF)

fn loadVertices(mut f F3d, s Segments, w0 i64, w1 i64):
	n = w0.bits(20, 4) + 1
	first = w0.bits(16, 4)
	lit = (f.geometry & 0x2_0000) != 0
	base = dlAddress(w1)
	for i in 0..n:
		at = base + i * 16
		p = f.transform.project(
			Vec3(f32(s.s16At(at)), f32(s.s16At(at + 2)), f32(s.s16At(at + 4)))
		)
		f.verts[(first + i) & 15] = Vert(
			x = p.x,
			y = p.y,
			z = p.z,
			s = s.s16At(at + 8),
			t = s.s16At(at + 10),
			c0 = s.u8At(at + 12),
			c1 = s.u8At(at + 13),
			c2 = s.u8At(at + 14), a = s.u8At(at + 15), lit)

# a triangle of the buffer's vertices i, j, k added to the batch of the current state
fn triangle(mut f F3d, s Segments, layer i64, i i64, j i64, k i64):
	colorSel, alphaSel = combinerCodes(f.combine0, f.combine1)
	usesTexel = f.texOn and (readsTexel(colorSel) or readsTexel(alphaSel))
	tile = f.tiles[f.texTile]
	texture = -1
	width = 32
	height = 32
	if usesTexel:
		texture, width, height = textureOf(f, s, tile)
	lit = f.verts[i & 15].lit
	sun = f.directional.min(7)
	m = Material(
		texture,
		layer,
		cullBack = (f.geometry & 0x2000) != 0,
		lit,
		colorSel,
		alphaSel,
		prim = f.prim,
		env = f.env,
		wrapS = wrapOf(tile.cms),
		wrapT = wrapOf(tile.cmt),
		smooth = f.otherH.bits(12, 2) != 0,
		ambient = f.lightColors[sun] if lit else 0,
		diffuse = f.lightColors[0] if lit else 0,
		direction = f.lightDirs[0] if lit else 0,
		billboard = f.billboard,
		anchorX = i64(f.anchor.x),
		anchorY = i64(f.anchor.y), anchorZ = i64(f.anchor.z))
	b = f.batchFor(m)
	bilinear = 0.5 if f.otherH.bits(12, 2) != 0 else 0.0
	for v in [i & 15, j & 15, k & 15]:
		vt = f.verts[v]
		u = f32(((vt.s * f.scaleS) >> 16) - tile.uls * 8) / 32.0 + bilinear
		w = f32(((vt.t * f.scaleT) >> 16) - tile.ult * 8) / 32.0 + bilinear
		out = mut ref f.out.batches[b].vertices
		out.push(vt.x)
		out.push(vt.y)
		out.push(vt.z)
		if vt.lit:
			n = f.transform
			nx = f32(i8.wrap(vt.c0))
			ny = f32(i8.wrap(vt.c1))
			nz = f32(i8.wrap(vt.c2))
			d = Vec3(
				n.m[0] * nx + n.m[4] * ny + n.m[8] * nz,
				n.m[1] * nx + n.m[5] * ny + n.m[9] * nz,
				n.m[2] * nx + n.m[6] * ny + n.m[10] * nz
			)
				.normalized()
			out.push(d.x)
			out.push(d.y)
			out.push(d.z)
		else:
			out.push(f32(vt.c0) / 255.0)
			out.push(f32(vt.c1) / 255.0)
			out.push(f32(vt.c2) / 255.0)
		out.push(u / f32(width))
		out.push(w / f32(height))
		out.push(f32(vt.a) / 255.0)
		out.push(0.0)

fn wrapOf(cm i64):
	2 if (cm & 2) != 0 else 1 if (cm & 1) != 0 else 0

fn batchFor(mut f F3d, m Material):
	if f.batchOf.get(m) is b: return b
	f.out.batches.push(Batch(material = m, vertices = []))
	f.batchOf[m] = f.out.batches.len - 1
	f.out.batches.len - 1

# The texture the render tile shows, decoded once: its index and size in texels. A LOADBLOCK
# brought a run of bytes laid out with the tile's row length; a LOADTILE a rectangle of the image.
fn textureOf(mut f F3d, s Segments, tile Tile):
	bits = bitsPerTexel(tile.siz)
	width = (tile.lrs - tile.uls) / 4 + 1
	height = (tile.lrt - tile.ult) / 4 + 1
	if not f.loadByTile and tile.line > 0:
		width = tile.line * 64 / bits
		height = (f.loadBytes * 8 / bits / width).max(1)
	key = TexKey(
		addr = f.loadAddr,
		fmt = tile.fmt,
		siz = tile.siz,
		width,
		height,
		palette = f.tlutAddr + tile.palette * 32
	)
	if f.textureOf.get(key) is t: return (t, width, height)
	pal = s.banks[segmentOf(f.tlutAddr)]
	palAt = offsetOf(f.tlutAddr) + (tile.palette * 32 if tile.siz == 0 else 0)
	rgba = image.Image(0, 0, fill = image.Rgba8(0, 0, 0, 0))
	if f.loadByTile:
		# the rectangle's rows, each from its place in the image
		rowBytes = f.timgWidth * bitsPerTexel(f.timgSiz) / 8
		packed = []
		for y in 0..height:
			start = offsetOf(f.loadAddr) + (f.loadUlt + y) * rowBytes + f.loadUls * bits / 8
			for x in 0..width * bits / 8:
				packed.push(s.banks[segmentOf(f.loadAddr)][start + x])
		rgba = decodeTexels(packed, 0, width, height, tile.fmt, tile.siz, pal, palAt)
	else:
		rgba = decodeTexels(
			s.banks[segmentOf(f.loadAddr)],
			offsetOf(f.loadAddr),
			width,
			height,
			tile.fmt,
			tile.siz,
			pal,
			palAt
		)
	f.out.textures.push(rgba)
	f.textureOf[key] = f.out.textures.len - 1
	(f.out.textures.len - 1, width, height)

# ---------- the color combiner ----------

# The first cycle's (a - b) * c + d, color and alpha, as input codes (8 bits each, a lowest).
# The console's numbers mean different inputs in each slot: they are mapped to the same codes.
fn combinerCodes(w0 i64, w1 i64):
	ca = colorInput(w0.bits(20, 4), false)
	cb = colorInput(w1.bits(28, 4), false)
	cc = colorMultiplier(w0.bits(15, 5))
	cd = colorInput(w1.bits(15, 3), true)
	aa = alphaInput(w0.bits(12, 3))
	ab = alphaInput(w1.bits(12, 3))
	ac = alphaMultiplier(w0.bits(9, 3))
	ad = alphaInput(w1.bits(9, 3))
	(ca | cb << 8 | cc << 16 | cd << 24, aa | ab << 8 | ac << 16 | ad << 24)

fn colorInput(v i64, isD bool):
	match v:
		1, 2: selTexel
		3: selPrim
		4: selShade
		5: selEnv
		6: selOne if isD else selZero
		_: selZero

fn colorMultiplier(v i64):
	match v:
		1, 2: selTexel
		3: selPrim
		4: selShade
		5: selEnv
		6: selOne
		8, 9: selTexelAlpha
		10: selPrimAlpha
		11: selShadeAlpha
		12: selEnvAlpha
		_: selZero

fn alphaInput(v i64):
	match v:
		1, 2: selTexel
		3: selPrim
		4: selShade
		5: selEnv
		6: selOne
		_: selZero

fn alphaMultiplier(v i64):
	match v:
		1, 2: selTexel
		3: selPrim
		4: selShade
		5: selEnv
		_: selZero

fn readsTexel(codes i64):
	found = false
	for k in 0..4:
		c = codes >> (k * 8) & 0xFF
		if c == selTexel or c == selTexelAlpha:
			found = true
	found
