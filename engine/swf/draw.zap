# The display list played on the engine: a stage's nodes (display.zap) drawn depth by depth, each
# object's matrix and color transform composed with its parents', shapes as triangles (mesh.zap) of
# a color, a bitmap or a gradient texture, text by its font's glyph shapes, a button by its up
# state. A clip layer (PlaceObject's clip depth) masks the depths above it up to its clip depth by
# its bounds, the triangles cut to that rectangle on the CPU. A text's drop shadows are drawn
# (drawfilter.zap). Not drawn yet: blend modes, other filters, nine-slice scaling, a color
# transform's additions over bitmaps.

import engine
import image

# a font asked for by its name and weight
pub type FontChoice:
	name str
	bold bool

# What a stage draws from: the movie, the movies fonts come from (Scaleform's font libraries), the
# faces text asks for mapped to the fonts of those, and the pixels of Scaleform's external images
# by id.
pub type Scene:
	movie Swf
	libraries Swf[] = []
	fontMap {str: FontChoice} = {}
	images {i64: image.Image} = {}

# the scene of a movie alone: no libraries
pub fn newScene(move movie Swf) Scene:
	Scene(movie)

# a font of the scene: the movie's (library -1) or a library's; id -1 none
type FontRef:
	library i64
	id i64

# the textures and meshes made from a scene, kept from one frame to the next
pub type DrawCache:
	meshes {i64: ShapeMesh} = {}
	glyphs {i64: ShapeMesh} = {}   # by (library + 1) << 40 | font << 20 | glyph
	bitmaps {i64: engine.GpuTexture} = {}
	gradients {i64: engine.GpuTexture} = {}   # by shape << 16 | gradient
	fonts {str: FontRef} = {}
	white engine.GpuTexture
	ramp engine.GpuTexture   # the fringe's coverage: half at its inner end, none at its outer
	triangles i64 = 0   # drawn since the cache was made
	missing str[] = []   # what could not be drawn, each named once

# an empty cache, its white texel and its fringe's ramp made
pub fn newDrawCache() DrawCache:
	ramp u8[] = []
	for k in 0..rampSize:
		ramp.extend([255, 255, 255, 127 * (rampSize - 1 - k) / (rampSize - 1)])
	DrawCache(white = image.fromBytes(1, 1, [255, 255, 255, 255]).newTexture(),
		ramp = image.fromBytes(rampSize, 1, ramp).newTexture(engine.Sampling(smooth = true,
			mipmaps = false, repeat = false, mirror = 0, anisotropy = false)))

# the fringe's ramp texels, and how wide the fringe is in pixels: half of one, the fill already
# covering whole the pixels whose middle it covers (a wider fringe makes the glyphs bolder than the
# game's: the menus' comparison with its captures loses 2 to 4 points at a whole pixel)
rampSize = 16
fringeWidth f32 = 0.5

type Context:
	matrix Affine
	color ColorTransform
	clip Rect   # pixels, when clipped
	clipped bool
	node Handle<Node>? = none   # the node drawn, none for a part of one (a button's record, a glyph)

type Mask:
	until i64   # the last depth it masks
	rect Rect

# The stage's twips to a window's pixels as a scale mode fits it (Flash's Stage.scaleMode):
# "showAll" whole and as large as fits, "noBorder" filling the window, "exactFit" stretched to it,
# "noScale" at its size; centered unless `align` names the sides it keeps to ("T", "B", "L", "R",
# "TL"...).
pub fn viewTransform(s Swf, width f64, height f64, mode str, align str) Affine:
	size = s.stageSize()
	sx = f32(width) / size.x
	sy = f32(height) / size.y
	match mode.lower():
		"noborder":
			sx = sx.max(sy)
			sy = sx
		"exactfit": pass
		"noscale":
			sx = 1.0
			sy = 1.0
		_:
			sx = sx.min(sy)
			sy = sx
	a = align.upper()
	free = Vec2(f32(width) - size.x * sx, f32(height) - size.y * sy)
	x f32 = 0.0 if "L" in a else free.x if "R" in a else free.x * 0.5
	y f32 = 0.0 if "T" in a else free.y if "B" in a else free.y * 0.5
	Affine(a = sx / 20.0, d = sy / 20.0, tx = x - s.stage.xmin * sx / 20.0,
		ty = y - s.stage.ymin * sy / 20.0)

# the stage's display list drawn through toScreen
pub fn drawStage(
	scene Scene,
	st Stage,
	mut cache DrawCache,
	mut r engine.Renderer,
	toScreen Affine
):
	ctx = Context(matrix = toScreen, color = ColorTransform(), clip = Rect(), clipped = false,
		node = st.root)
	scene.drawChildren(st, cache, r, ctx)

fn drawChildren(scene Scene, st Stage, mut cache DrawCache, mut r engine.Renderer, ctx Context):
	masks Mask[] = []
	node = ctx.node ?? return
	for c in st.nodes[node].children:
		p = st.nodes[c].placed
		masks = masks.filter(.until >= p.depth)
		matrix = ctx.matrix.times(p.matrix)
		if p.clipDepth > 0:
			if scene.boundsOf(st, c, matrix) is b: masks.push(Mask(until = p.clipDepth, rect = b))
			continue
		if not p.visible: continue
		child = Context(matrix, color = ctx.color.then(p.color), clip = ctx.clip,
			clipped = ctx.clipped, node = c)
		for m in masks:
			child.clip = child.clip.intersect(m.rect) if child.clipped else m.rect
			child.clipped = true
		if child.color.mul.w <= 0.0 and child.color.add.w <= 0.0: continue
		if not p.filters.isEmpty: scene.drawShadows(st, cache, r, p, child)
		scene.drawCharacter(st, cache, r, p.character, child)

fn drawCharacter(
	scene Scene,
	st Stage,
	mut cache DrawCache,
	mut r engine.Renderer,
	id i64,
	ctx Context
):
	movie = scene.movie
	if movie.shapes.get(id) is s:
		cache.ensureMesh(s)
		scene.drawMesh(cache, r, id, false, ctx, none)
	elif ctx.node is node and st.fieldOf(scene, node) is t:
		scene.drawEditText(cache, r, t, st.nodes[node], ctx)
	elif movie.texts.get(id) is t:
		scene.drawStaticText(cache, r, t, ctx)
	elif movie.buttons.get(id) is b:
		for rec in b.records.sortedBy(.depth):
			if (rec.states & 1) == 0: continue
			child = Context(
				matrix = ctx.matrix.times(rec.matrix),
				color = ctx.color.then(rec.color),
				clip = ctx.clip, clipped = ctx.clipped, node = none)
			scene.drawCharacter(st, cache, r, rec.character, child)
	elif ctx.node != none:
		scene.drawChildren(st, cache, r, ctx)

fn ensureMesh(mut cache DrawCache, s Shape):
	if s.id in cache.meshes: return
	mesh = s.shapeMesh(10.0)
	for k, img in mesh.gradients:
		cache.gradients[(s.id << 16) | k] = img.newTexture(engine.Sampling(
			smooth = true,
			mipmaps = false,
			repeat = false, mirror = 0, anisotropy = false))
	mesh.gradients.clear()
	cache.meshes[s.id] = mesh

# A mesh of the cache (a shape's, or a glyph's when `glyph`) drawn in the context; `color`, when
# given, paints its solid parts instead of their own color (a glyph in its text's color).
fn drawMesh(
	scene Scene,
	mut cache DrawCache,
	mut r engine.Renderer,
	key i64,
	glyph bool,
	ctx Context,
	color Vec4?
):
	count = cache.partCount(key, glyph)
	for k in 0..count:
		bitmap, gradient, smooth, repeat = cache.partPaint(key, glyph, k)
		tex = cache.white.texture()
		uv = Affine(a = 0.0, d = 0.0)
		if bitmap >= 0:
			tex = cache.bitmapTexture(scene, bitmap, smooth, repeat) ?? continue
			uv = Affine(a = 1.0 / f32(tex.width), d = 1.0 / f32(tex.height))
		elif gradient >= 0:
			tex = (cache.gradients.get((key << 16) | gradient) ?? continue).texture()
			uv = Affine()
		mesh = cache.glyphs[key] if glyph else cache.meshes[key]
		cache.triangles += mesh.parts[k].emitPart(tex, uv, ctx, color, r)
		if bitmap < 0 and gradient < 0:
			cache.triangles += mesh.parts[k].emitFringe(cache.ramp.texture(), ctx, color, r)

fn partCount(cache DrawCache, key i64, glyph bool):
	mesh = (cache.glyphs.get(key) if glyph else cache.meshes.get(key)) ?? return 0
	mesh.parts.len

# the paint of a mesh's part: its bitmap, gradient, smoothing and repeat
fn partPaint(cache DrawCache, key i64, glyph bool, k i64):
	mesh = cache.glyphs[key] if glyph else cache.meshes[key]
	p = mesh.parts[k]
	(p.bitmap, p.gradient, p.smooth, p.repeat)

# the bitmap's texture, made the first time from the movie's bitmap or the scene's image of that id
fn bitmapTexture(
	mut cache DrawCache,
	scene Scene,
	id i64,
	smooth bool,
	repeat bool
) engine.Texture?:
	if cache.bitmaps.get(id) is t: return t.texture()
	sampling = engine.Sampling(smooth, mipmaps = false, repeat, mirror = 0, anisotropy = false)
	if scene.images.get(id) is img:
		cache.bitmaps[id] = img.newTexture(sampling)
		return cache.bitmaps[id].texture()
	b = scene.movie.bitmaps.get(id) ?? return cache.noteMissing("bitmap {id}")
	match b.decodeBitmap(scene.movie.jpegTables):
		img:
			cache.bitmaps[id] = img.newTexture(sampling)
			cache.bitmaps[id].texture()
		error: cache.noteMissing("bitmap {id}: {error}")

fn noteMissing(mut cache DrawCache, what str) engine.Texture?:
	if what not in cache.missing: cache.missing.push(what.copy())
	none

# A part's triangles through the context's matrix (the paint's place through `uv` after the
# part's own paint matrix), cut to its clip; how many were drawn.
fn emitPart(
	part MeshPart,
	tex engine.Texture,
	uv Affine,
	ctx Context,
	color Vec4?,
	mut r engine.Renderer
):
	textured = part.bitmap >= 0 or part.gradient >= 0
	tint = ctx.color.applyColor(color ?? part.color) if not textured
		else ctx.color.applyColor(Vec4(1.0,
			1.0, 1.0, 1.0))
	if tint.w <= 0.0: return 0
	paint = uv.times(part.paint)
	drawn = 0
	for k in (0..part.triangles.len - 2 step 3):
		corners = []
		for j in 0..3:
			p = part.triangles[k + j]
			at = ctx.matrix.apply(p)
			t = paint.apply(p)
			corners.push(Vec4(at.x, at.y, t.x, t.y))
		if ctx.clipped: corners = clipPolygon(corners, ctx.clip)
		for j in 2..corners.len:
			a = corners[0]
			b = corners[j - 1]
			c = corners[j]
			r.drawTriangle(tex, a.xy, b.xy, c.xy, a.zw, b.zw, c.zw, tint)
			drawn += 1
	drawn

# Scaleform's edge anti-aliasing: a fringe outside each outline edge of a solid part, its coverage
# fading from half at the edge to none, so the edge's pixels blend as the game's do.
fn emitFringe(
	part MeshPart,
	ramp engine.Texture,
	ctx Context,
	color Vec4?,
	mut r engine.Renderer
):
	tint = ctx.color.applyColor(color ?? part.color)
	if tint.w <= 0.0: return 0
	drawn = 0
	for k, e in part.edges:
		a = ctx.matrix.apply(e.xy)
		b = ctx.matrix.apply(e.zw)
		along = b - a
		if along.length() < 0.01: continue
		out = Vec2(along.y, -along.x).normalized()
		if (ctx.matrix.apply(part.insides[k]) - a) @ out > 0.0: out = -out
		far = out * fringeWidth
		corners = [Vec4(a.x, a.y, 0.0, 0.5), Vec4(b.x, b.y, 0.0, 0.5),
			Vec4(b.x + far.x, b.y + far.y, 1.0, 0.5), Vec4(a.x + far.x, a.y + far.y, 1.0, 0.5)]
		if ctx.clipped: corners = clipPolygon(corners, ctx.clip)
		for j in 2..corners.len:
			r.drawTriangle(ramp, corners[0].xy, corners[j - 1].xy, corners[j].xy, corners[0].zw,
				corners[j - 1].zw, corners[j].zw, tint)
			drawn += 1
	drawn

# A convex polygon (each corner a place x, y and a texture place z, w) cut to a rectangle, edge by
# edge (Sutherland and Hodgman).
pub fn clipPolygon(polygon Vec4[], rect Rect) Vec4[]:
	out = polygon.copy()
	for edge in 0..4:
		input = move out
		for k in 0..input.len:
			a = input[k]
			b = input[(k + 1) % len]
			da = a.insideBy(edge, rect)
			db = b.insideBy(edge, rect)
			if da >= 0.0: out.push(a)
			if (da >= 0.0) != (db >= 0.0): out.push(a + (b - a) * (da / (da - db)))
	out

fn insideBy(v Vec4, edge i64, rect Rect):
	match edge:
		0: v.x - rect.xmin
		1: rect.xmax - v.x
		2: v.y - rect.ymin
		_: rect.ymax - v.y

# the rectangle both cover (empty, min over max, when they do not meet)
pub fn intersect(a Rect, b Rect) Rect:
	Rect(xmin = a.xmin.max(b.xmin), ymin = a.ymin.max(b.ymin), xmax = a.xmax.min(b.xmax),
		ymax = a.ymax.min(b.ymax))

fn union(a Rect, b Rect):
	Rect(xmin = a.xmin.min(b.xmin), ymin = a.ymin.min(b.ymin), xmax = a.xmax.max(b.xmax),
		ymax = a.ymax.max(b.ymax))

# the bounds of a node under m (pixels): its character's, or its children's together
pub fn boundsOf(scene Scene, st Stage, n Handle<Node>, m Affine) Rect?:
	movie = scene.movie
	id = st.nodes[n].placed.character
	if movie.shapes.get(id) is s: return m.transformRect(s.bounds)
	if st.fieldOf(scene, n) is t: return m.transformRect(st.nodes[n].bounds ?? t.bounds)
	if movie.texts.get(id) is t: return m.times(t.matrix).transformRect(t.bounds)
	out Rect? = none
	for c in st.nodes[n].children:
		if st.nodes[c].placed.clipDepth > 0: continue
		b = scene.boundsOf(st, c, m.times(st.nodes[c].placed.matrix)) ?? continue
		out = (out ?? b).union(b)
	out
