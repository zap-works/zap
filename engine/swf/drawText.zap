# Text drawn by its fonts' glyph shapes: a text field's lines of runs (layout.zap) each in the font
# its face names (the movie's own, else the scene's font map over its libraries), a static text's
# records glyph by glyph; each glyph a cached mesh in em units, scaled to the text's size. The font
# map comes from Scaleform's fontconfig.txt.

import engine

fn drawEditText(
	scene Scene,
	mut cache DrawCache,
	mut r engine.Renderer,
	t EditText,
	node Node,
	ctx Context
):
	_, given = t.fieldStyle(node)
	bounds = node.bounds ?? t.bounds
	placed = scene.placeLines(cache.fonts, t, bounds, given, node.shrink)
	placed = placed.scrolled(node.scroll, bounds)
	view = ctx.cutToField(bounds, placed)
	for line in placed:
		for j, run in line.runs:
			if j >= line.source.len: continue
			source = line.source[j]
			if not source.image.isEmpty:
				cache.drawInlineImage(scene, r, source, run.x, line.baseline, view)
				continue
			if run.font.id < 0:
				cache.noteMissing("font {t.font} \"{source.style.face}\"")
				continue
			f = scene.fontOf(run.font) ?? continue
			codes = source.text.chars().map(.charCode())
			x = run.x
			for i, code in codes:
				if f.byCode.get(code) is g:
					m = view.matrix.times(
						Affine(a = run.scale, d = run.scale, tx = x, ty = line.baseline)
					)
					cache.drawGlyph(scene, r, run.font, g, view, m, source.style.color)
					x += f.glyphs[g].advance * run.scale + source.style.spacing
				if i + 1 < codes.len: x += f.kerningOf(code, codes[i + 1]) * run.scale

# How a field's lines scroll: their count (as the field wraps them), the greatest `scroll` (the
# first line that leaves the last line at the bottom, 1 when all fit) and `bottomScroll` (the last
# line shown), for a field scrolled to the line `scroll` (1 at the top).
pub type LineScroll:
	lines i64
	maxscroll i64
	bottom i64

# the lines that fit the room (twips) from line k on, at least one
fn fitting(placed PlacedLine[], k i64, room f32):
	used = 0.0
	count = 0
	for j in k..placed.len:
		used += placed[j].height
		if used > room and count > 0: break
		count += 1
	count.max(1)

# how many of the last lines fit the room (twips), at least one
fn fittingAtEnd(placed PlacedLine[], room f32):
	used = 0.0
	count = 0
	for k in 0..placed.len:
		used += placed[len - 1 - k].height
		if used > room and count > 0: break
		count += 1
	count.max(1)

pub fn lineScroll(scene Scene, t EditText, node Node) LineScroll:
	_, lines = t.fieldStyle(node)
	fonts {str: FontRef} = {}
	bounds = node.bounds ?? t.bounds
	placed = scene.placeLines(fonts, t, bounds, lines, node.shrink)
	room = bounds.ymax - bounds.ymin - 2.0 * gutter
	maxscroll = (placed.len - placed.fittingAtEnd(room) + 1).max(1)
	top = node.scroll.clamp(1, maxscroll)
	LineScroll(
		lines = placed.len,
		maxscroll,
		bottom = (top + placed.fitting(top - 1, room) - 1).min(placed.len)
	)

# the lines from the field's `scroll`th on, moved up to its top
fn scrolled(placed PlacedLine[], scroll i64, bounds Rect):
	if scroll <= 1 or placed.len < 2: return placed.copy()
	room = bounds.ymax - bounds.ymin - 2.0 * gutter
	skip = (scroll - 1).min(placed.len - placed.fittingAtEnd(room)).max(0)
	if skip == 0: return placed.copy()
	shift = placed[skip].baseline - placed[skip].ascent - (bounds.ymin + gutter)
	out = placed[skip..].copy()
	for k in 0..out.len:
		out[k].baseline -= shift
	out

# The context a field's lines are drawn in: the field's box clips them when they are taller than
# it (a text field shows what fits its bounds; the scroll of the rest is not played).
fn cutToField(ctx Context, bounds Rect, placed PlacedLine[]):
	tall = 0.0
	for line in placed:
		tall += line.height
	if tall <= bounds.ymax - bounds.ymin + 2.0 * gutter: return ctx
	box = ctx.matrix.transformRect(bounds)
	Context(matrix = ctx.matrix, color = ctx.color,
		clip = ctx.clip.intersect(box) if ctx.clipped else box, clipped = true, node = ctx.node)

# a field's style and lines as its node shows them: its text read, then the format and color a
# script set over all of it
pub fn fieldStyle(t EditText, node Node) (TextStyle, TextLine[]):
	style, lines = t.fieldText(node.text, node.html)
	if node.format is f:
		style = style.overridden(f)
		for mut line in lines:
			for j in 0..line.runs.len:
				line.runs[j].style = line.runs[j].style.overridden(f)
	if node.textColor is c:
		style.color = c
		for mut line in lines:
			for j in 0..line.runs.len:
				line.runs[j].style.color = c
	(style, lines)

# An inline image of a text drawn: its bitmap stretched over its box, standing on the baseline at
# x (twips), lowered by its vspace.
fn drawInlineImage(
	mut cache DrawCache,
	scene Scene,
	mut r engine.Renderer,
	run TextRun,
	x f32,
	baseline f32,
	ctx Context
):
	id = scene.movie.exports.get(run.image) ?? 0
	if scene.movie.bitmaps.get(id) == none:
		cache.noteMissing("image {run.image}")
		return
	tex = cache.bitmapTexture(scene, id, true, false) ?? return
	box = scene.imageBox(run) * 20.0
	top = baseline - box.y + run.vspace * 20.0
	corners = [Vec2(x, top), Vec2(x + box.x, top), Vec2(x + box.x, top + box.y),
		Vec2(x, top + box.y)].map(ctx.matrix.apply(it))
	uvs = [Vec2(0.0, 0.0), Vec2(1.0, 0.0), Vec2(1.0, 1.0), Vec2(0.0, 1.0)]
	tint = ctx.color.applyColor(Vec4(1.0, 1.0, 1.0, 1.0))
	r.drawTriangle(tex, corners[0], corners[1], corners[2], uvs[0], uvs[1], uvs[2], tint)
	r.drawTriangle(tex, corners[0], corners[2], corners[3], uvs[0], uvs[2], uvs[3], tint)
	cache.triangles += 2

# an inline image's size in pixels: the tag's, else its bitmap's
fn imageBox(scene Scene, run TextRun):
	if run.size.x > 0.0 and run.size.y > 0.0: return run.size
	id = scene.movie.exports.get(run.image) ?? return run.size
	w, h = (scene.movie.bitmaps.get(id) ?? return run.size).bitmapSize()
	Vec2(f32(w), f32(h))

# a run of a line placed: its font, its scale (twips per font unit) and where it starts
type PlacedRun:
	font FontRef
	scale f32
	x f32

# a line placed in the field, in twips: its runs and the text runs they are of (the line as the
# field wrapped it), its width, its baseline and height
type PlacedLine:
	runs PlacedRun[]
	source TextRun[]
	width f32
	start f32
	baseline f32
	height f32
	ascent f32
	descent f32

# The lines placed in the bounds as placeAll does; when the field shrinks its text and it is wider
# or taller than the field holds, placed again with every run's size made smaller by as much.
fn placeLines(
	scene Scene,
	mut fonts {str: FontRef},
	t EditText,
	bounds Rect,
	lines TextLine[],
	shrink bool
) PlacedLine[]:
	placed = scene.placeAll(fonts, t, bounds, lines)
	if not shrink: return placed
	wide f32 = 0.0
	tall = 0.0
	for line in placed:
		wide = wide.max(line.width)
		tall += line.height
	roomX = bounds.xmax - bounds.xmin - 2.0 * gutter - t.leftMargin - t.rightMargin
	roomY = bounds.ymax - bounds.ymin - 2.0 * gutter
	factor = (roomX / wide.max(1.0)).min(roomY / tall.max(1.0))
	if factor >= 1.0: return placed
	smaller = lines.copy()
	for k in 0..smaller.len:
		for j in 0..smaller[k].runs.len:
			smaller[k].runs[j].style.size *= factor
	scene.placeAll(fonts, t, bounds, smaller)

# the width of a run's text in its style (twips): its font's advances and kernings at its size, its
# letter spacing after each glyph; none without the font
fn runWidth(scene Scene, mut fonts {str: FontRef}, t EditText, text str, style TextStyle) f32?:
	f = try scene.fontOf(scene.fontFor(fonts, t.font, style.face))
	codes = text.chars().map(.charCode())
	f.lineWidth(codes) * style.size / f.em + style.spacing * f32(codes.len)

# The lines of a field that wraps its words (wordWrap) broken where they pass its width: a word
# (with the spaces after it) that would end past the right edge, its spaces left out, starts the
# next line.
fn wrapLines(
	scene Scene,
	mut fonts {str: FontRef},
	t EditText,
	bounds Rect,
	lines TextLine[]
):
	room = bounds.xmax - bounds.xmin - 2.0 * gutter - t.leftMargin - t.rightMargin
	out = []
	for line in lines:
		current = []
		width = 0.0
		for run in line.runs:
			if not run.image.isEmpty:
				current.push(run.copy())
				width += scene.imageBox(run).x * 20.0
				continue
			for word in run.text.wordsKeepingSpaces():
				w = scene.runWidth(fonts, t, word, run.style) ?? 0.0
				inked = scene.runWidth(fonts, t, word.trimmedEnd(), run.style) ?? 0.0
				if width + inked > room and width > 0.0:
					out.push(TextLine(runs = move current))
					current = []
					width = 0.0
				if not current.isEmpty and current[len - 1].style == run.style and
					current[len - 1].image.isEmpty:
					current[len - 1].text = "{current[current.len - 1].text}{word}"
				else:
					current.push(TextRun(text = word.copy(), style = run.style.copy()))
				width += w
		out.push(TextLine(runs = move current))
	out

# the text's words, each with the spaces after it, leading spaces their own
fn wordsKeepingSpaces(text str):
	out = []
	start = 0
	b = text.bytes()
	for k in 1..=b.len:
		if k == b.len or (b[k] != ' ' and b[k - 1] == ' '):
			out.push(text[start..k].copy())
			start = k
	out

# the lines placed in the bounds (wrapped first when the field wraps): each run in its face's font
# (found once into `fonts`), the runs of a line one after the other on one baseline below the
# tallest's ascent, the line where its first run's alignment puts it
fn placeAll(
	scene Scene,
	mut fonts {str: FontRef},
	t EditText,
	bounds Rect,
	given TextLine[]
):
	out = []
	y = bounds.ymin + gutter
	lines = scene.wrapLines(fonts, t, bounds, given) if t.wordWrap else given.copy()
	for line in lines:
		runs = []
		width, ascent, descent, leading = f32(0.0), f32(0.0), f32(0.0), f32(0.0)
		styles = line.runs.map(.style.copy())
		if styles.isEmpty: styles = [TextStyle(face = "", size = t.height, color = t.color,
			align = t.align)]
		for k, style in styles:
			if k < line.runs.len and not line.runs[k].image.isEmpty:
				box = scene.imageBox(line.runs[k]) * 20.0
				runs.push(PlacedRun(font = FontRef(library = -1, id = -1), scale = 0.0, x = width))
				width += box.x
				ascent = ascent.max(box.y)
				continue
			which = scene.fontFor(fonts, t.font, style.face)
			if scene.fontOf(which) == none:
				runs.push(PlacedRun(font = which, scale = 0.0, x = width))
				continue
			f = scene.fontOf(which) ?? continue
			scale = style.size / f.em
			runs.push(PlacedRun(font = which, scale, x = width))
			if k < line.runs.len:
				width += scene.runWidth(fonts, t, line.runs[k].text, style) ?? 0.0
			ascent = ascent.max(f.ascent * scale)
			descent = descent.max(f.descent * scale)
			leading = leading.max(f.leading * scale)
		start = t.lineStart(bounds, styles[0], width)
		for mut run in runs:
			run.x += start
		height = ascent + descent + leading + t.leading
		out.push(PlacedLine(
			runs,
			source = line.runs.copy(),
			width,
			start,
			baseline = y + ascent,
			height,
			ascent, descent))
		y += height
	out

# the font of a face for a field whose own font is `id`, found once
fn fontFor(scene Scene, mut fonts {str: FontRef}, id i64, face str):
	key = "{id}|{face}"
	if fonts.get(key) is known: return known
	found = scene.findFont(id, face)
	fonts[key] = found
	found

# the size of a field's text in pixels, as its script measures it before any wrapping: its widest line, its lines' heights together
pub fn textExtent(scene Scene, t EditText, node Node) Vec2:
	_, lines = t.fieldStyle(node)
	fonts {str: FontRef} = {}
	unwrapped = t.copy()
	unwrapped.wordWrap = false
	placed = scene.placeLines(fonts, unwrapped, node.bounds ?? t.bounds, lines, node.shrink)
	width = 0.0
	height = 0.0
	for line in placed:
		width = width.max(line.width / 20.0)
		height += line.height / 20.0
	Vec2(width, height)

# a field's lines measured in pixels in their fonts: each line's width and start from the field's
# left edge, the first line's height and its fonts' ascent and descent at the field's sizes
pub type TextMetrics:
	widths f32[]
	starts f32[]
	lineHeight f32
	ascent f32
	descent f32
	tops f32[] = []   # each line's top from the field's top, pixels
	heights f32[] = []
	texts str[] = []   # each line's text as the field wrapped it

pub fn textMetrics(scene Scene, t EditText, node Node) TextMetrics:
	_, lines = t.fieldStyle(node)
	fonts {str: FontRef} = {}
	bounds = node.bounds ?? t.bounds
	placed = scene.placeLines(fonts, t, bounds, lines, node.shrink)
	first = placed.first ?? return TextMetrics(widths = [], starts = [], lineHeight = 0.0,
		ascent = 0.0, descent = 0.0)
	TextMetrics(
		widths = placed.map(.width / 20.0),
		starts = placed.map((.start - bounds.xmin) / 20.0),
		lineHeight = first.height / 20.0,
		ascent = first.ascent / 20.0,
		descent = first.descent / 20.0,
		tops = placed.map((.baseline - .ascent - bounds.ymin) / 20.0),
		heights = placed.map(.height / 20.0),
		texts = placed.map(.source.map(.text).join(""))
	)

fn drawStaticText(
	scene Scene,
	mut cache DrawCache,
	mut r engine.Renderer,
	t StaticText,
	ctx Context
):
	for rec in t.records:
		which = FontRef(library = -1, id = rec.font)
		f = scene.movie.fonts.get(rec.font) ?? continue
		scale = rec.height / f.em
		x = rec.x
		for k, glyph in rec.glyphs:
			m = ctx.matrix.times(t.matrix).times(Affine(a = scale, d = scale, tx = x, ty = rec.y))
			cache.drawGlyph(scene, r, which, glyph, ctx, m, rec.color)
			x += rec.advances[k]

fn drawGlyph(
	mut cache DrawCache,
	scene Scene,
	mut r engine.Renderer,
	which FontRef,
	glyph i64,
	ctx Context,
	m Affine,
	color Vec4
):
	f = scene.fontOf(which) ?? return
	if glyph < 0 or glyph >= f.glyphs.len: return
	key = ((which.library + 1) << 40) | (which.id << 20) | glyph
	if key not in cache.glyphs:
		cache.glyphs[key] = f.glyphs[glyph].shape.shapeMesh(f.em / 256.0)
	at = Context(..ctx, matrix = m, node = none)
	scene.drawMesh(cache, r, key, true, at, color)

fn fontOf(scene Scene, which FontRef) ref Font?:
	if which.library < 0: return scene.movie.fonts.get(which.id)
	scene.libraries[which.library].fonts.get(which.id)

# The font a field's text is drawn in: its face's (the font map's name and weight, looked for in
# the libraries, else what a library exports by that name), else the field's own font when it has
# glyphs, else the face the field's font is imported by.
pub fn findFont(scene Scene, id i64, face0 str) FontRef:
	face = face0.copy()
	found = FontRef(library = -1, id = -1)
	if face.isEmpty:
		if scene.movie.fonts.get(id) is own:
			if not own.glyphs.isEmpty: found = FontRef(library = -1, id)
		for i in scene.movie.imports:
			if i.id == id: face = i.name.copy()
	if found.id < 0 and not face.isEmpty:
		found = scene.fontByFace(face)
	found

fn fontByFace(scene Scene, face str):
	choice = scene.fontMap.get(face) ?? FontChoice(name = face.copy(), bold = false)
	for pass in 0..2:
		for k, lib in scene.libraries:
			for id in lib.fonts.keys().sorted():
				f = lib.fonts[id]
				if f.glyphs.isEmpty or f.name != choice.name: continue
				if pass == 0 and f.bold != choice.bold: continue
				return FontRef(library = k, id)
	for k, lib in scene.libraries:
		if lib.exports.get(face) is id:
			if id in lib.fonts: return FontRef(library = k, id)
	FontRef(library = -1, id = -1)

# what fontconfig.txt says: the font libraries and the faces' fonts
pub type FontConfig:
	libraries str[]   # the movies the fonts come from, as written ("Interface\fonts_en.swf")
	map {str: FontChoice}

# Scaleform's fontconfig.txt: `fontlib "file"` lines and `map "$Face" = "Font name" Weight` lines
# (a weight of Bold, Demi or Heavy is bold); the other lines are left
pub fn readFontConfig(text str) FontConfig:
	config = FontConfig(libraries = [], map = {})
	for line in text.lines():
		parts = line.split("\"")
		words = line.trimmed().words()
		if words.isEmpty or parts.len < 3: continue
		if words[0] == "fontlib":
			config.libraries.push(parts[1].copy())
		elif words[0] == "map" and parts.len >= 5:
			weight = parts[4].trimmed().lower()
			bold = weight in ["bold", "demi", "heavy"]
			config.map[parts[1].copy()] = FontChoice(name = parts[3].copy(), bold)
	config
