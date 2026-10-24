# Text fields as ActionScript sees them (Ruffle's core/src/avm1/globals/text_field.rs and
# text_format.rs): text and htmlText, textColor, autoSize growing the bounds around the text,
# textWidth and textHeight measured in the field's font, and TextFormat objects read from and
# applied to the field's style. Scaleform translates a text that is a "$KEY" of its translation
# file when it is set, and so does this; its textAutoSize "shrink" (and "fit", whose growing is
# left out) makes the text smaller until it fits the field.

import engine.swf

textProperties = ["text", "htmlText", "textColor", "html", "textWidth", "textHeight", "length",
	"autoSize", "numLines", "scroll", "maxscroll", "bottomScroll", "textAutoSize"]

fn isTextProperty(name str):
	name in textProperties

fn fieldOf(prog Program, m Machine, n Handle<swf.Node>):
	m.stage.fieldOf(prog.scene, n)

fn textMember(prog Program, mut m Machine, n Handle<swf.Node>, name str) Value?:
	t = try prog.fieldOf(m, n)
	node = try m.stage.nodes.get(n)
	style, lines = t.fieldStyle(node)
	text = lines.map(.text()).join("\r")
	match name:
		"text": .Str(text.copy())
		"htmlText": .Str(node.text.copy())
		"html": .Bool(node.html)
		"textColor": .Num(f64(style.color.colorNumber()))
		"length": .Num(f64(text.chars().len))
		"textWidth": .Num(f64(prog.scene.textExtent(t, node).x))
		"textHeight": .Num(f64(prog.scene.textExtent(t, node).y))
		"numLines": .Num(f64(prog.scene.lineScroll(t, node).lines))
		"maxscroll": .Num(f64(prog.scene.lineScroll(t, node).maxscroll))
		"bottomScroll": .Num(f64(prog.scene.lineScroll(t, node).bottom))
		"textAutoSize": .Str("shrink" if node.shrink else "none")
		"scroll": .Num(f64(node.scroll.clamp(1, prog.scene.lineScroll(t, node).maxscroll)))
		_: none

fn colorNumber(c Vec4):
	(i64(c.x * 255.0 + 0.5) << 16) | (i64(c.y * 255.0 + 0.5) << 8) | i64(c.z * 255.0 + 0.5)

pub fn colorOf(rgb i64, alpha f32) Vec4:
	Vec4(f32((rgb >> 16) & 255) / 255.0, f32((rgb >> 8) & 255) / 255.0, f32(rgb & 255) / 255.0,
		alpha)

# sets a text property; false for one kept on the object (autoSize, its own name)
fn setTextMember(prog Program, mut m Machine, n Handle<swf.Node>, name str, v Value) bool ? Thrown:
	t = prog.fieldOf(m, n) ?? return false
	match name:
		"text":
			text = try prog.toText(m, v)
			style, _ = t.fieldStyle(m.stage.nodes[n])
			m.stage.nodes[n].format = style.overrideOf()
			m.stage.nodes[n].text = prog.translated(text)
			m.stage.nodes[n].html = false
		"htmlText":
			text = try prog.toText(m, v)
			m.stage.nodes[n].text = prog.translatedHtml(text)
			m.stage.nodes[n].html = true
			m.stage.nodes[n].format = none
		"textColor":
			rgb = toInt32(try prog.toNumber(m, v))
			m.stage.nodes[n].textColor = colorOf(rgb, 1.0)
		"html":
			m.stage.nodes[n].html = v.isTrue()
		"scroll":
			m.stage.nodes[n].scroll = toInt32(try prog.toNumber(m, v)).max(1)
		"textAutoSize":
			mode = (try prog.toText(m, v)).lower()
			m.stage.nodes[n].shrink = mode == "shrink" or mode == "fit"
		"autoSize":
			object = m.objectOfNode(prog, n)
			m.setOwn(object, "autoSize", v.copy())
		_:
			if displayIndex(name) == none: return false
			try prog.setDisplayProperty(m, n, name, v)
	prog.autoSize(m, n)
	true

# the bounds of a field whose autoSize is not "none" made to hold its text, from the side it
# names ("left" keeps the left edge, "right" the right one, "center" the middle)
fn autoSize(prog Program, mut m Machine, n Handle<swf.Node>):
	t = prog.fieldOf(m, n) ?? return
	object = m.objectLinked(n) ?? return
	mode = primitiveText(m.ownValue(object, "autoSize")).lower()
	if mode in ["none", "false", "undefined"]: return
	size = prog.scene.textExtent(t, m.stage.nodes[n]) * 20.0
	b = t.bounds
	w = size.x + 80.0
	h = size.y + 80.0
	x0 = (b.xmin + b.xmax - w) * 0.5
	if mode == "left" or mode == "true": x0 = b.xmin
	elif mode == "right": x0 = b.xmax - w
	m.stage.nodes[n].bounds = swf.Rect(xmin = x0, ymin = b.ymin, xmax = x0 + w, ymax = b.ymin + h)

# a new field's own text translated
fn translateField(prog Program, mut m Machine, n Handle<swf.Node>):
	if prog.translations.isEmpty or prog.fieldOf(m, n) == none: return
	text = m.stage.nodes[n].text.copy()
	html = m.stage.nodes[n].html
	m.stage.nodes[n].text = prog.translatedHtml(text) if html else prog.translated(text)

# a text translated when it is a key of the translation file
pub fn translated(prog Program, text str) str:
	if text.startsWith("$"):
		if prog.translations.get(text) is t: return t.copy()
	text.copy()

# an HTML text with each run of text between tags that is a key translated
pub fn translatedHtml(prog Program, html str) str:
	if "$" not in html: return html.copy()
	out = ""
	at = 0
	while at < html.len:
		open = html.indexOf("<", at) ?? html.len
		out = "{out}{prog.translated(html[at..open])}"
		if open >= html.len: break
		close = html.indexOf(">", open) ?? html.len - 1
		out = "{out}{html[open..close + 1]}"
		at = close + 1
	out

# a TextFormat object of a style
fn formatObject(mut m Machine, lines swf.TextLine[]):
	id = m.newObject(m.protos.textFormat)
	styles = []
	for l in lines:
		styles.extend(l.runs.map(.style.copy()))
	first = (styles.first ?? return id).copy()
	alignNames = ["left", "right", "center", "justify"]
	m.setOwn(id, "font", .Str(first.face.copy()) if styles.all(.face == first.face)
		else .Null)
	m.setOwn(id, "size", .Num(f64(first.size) / 20.0) if styles.all(.size == first.size)
		else .Null)
	m.setOwn(id, "color", .Num(f64(first.color.colorNumber()))
		if styles.all(.color == first.color) else .Null)
	m.setOwn(id, "align", .Str(alignNames[first.align.clamp(0, 3)])
		if styles.all(.align == first.align) else .Null)
	m.setOwn(id, "letterSpacing", .Num(f64(first.spacing) / 20.0)
		if styles.all(.spacing == first.spacing) else .Null)
	for name in ["bold", "italic", "underline", "url", "target", "leftMargin", "rightMargin",
		"indent", "leading", "kerning", "bullet", "tabStops", "blockIndent"]:
		m.setOwn(id, name, .Null)
	id

# an override with what a TextFormat object sets (its null properties leave the override's)
fn appliedFormat(
	prog Program,
	mut m Machine,
	override swf.TextOverride,
	format Value
) swf.TextOverride ? Thrown:
	out = override.copy()
	if format.objectId() == none: return out
	font = try prog.getMember(m, format, "font")
	if not font.isNullish(): out.face = try prog.toText(m, font)
	size = try prog.getMember(m, format, "size")
	if not size.isNullish(): out.size = f32(try prog.toNumber(m, size)) * 20.0
	color = try prog.getMember(m, format, "color")
	if not color.isNullish(): out.color = colorOf(toInt32(try prog.toNumber(m, color)), 1.0)
	spacing = try prog.getMember(m, format, "letterSpacing")
	if not spacing.isNullish(): out.spacing = f32(try prog.toNumber(m, spacing)) * 20.0
	align = try prog.getMember(m, format, "align")
	if not align.isNullish():
		out.align = match (try prog.toText(m, align)).lower():
			"right": 1
			"center": 2
			"justify": 3
			_: 0
	out

# long: TextField's and TextFormat's methods, one arm each
fn textNative(prog Program, mut m Machine, name str, me Value, args Value[]) Value ? Thrown:
	n = m.nodeOf(me) ?? return Value.Undefined
	t = prog.fieldOf(m, n) ?? return Value.Undefined
	match name:
		"addListener", "removeListener":
			prog.listen(m, me, arg(args, 0), name == "addListener")
		"getTextFormat", "getNewTextFormat":
			_, lines = t.fieldStyle(m.stage.nodes[n])
			Value.Obj(m.formatObject(lines))
		"setTextFormat", "setNewTextFormat":
			format = args[len - 1].copy() if not args.isEmpty else Value.Undefined
			old = (m.stage.nodes[n].format ?? swf.TextOverride()).copy()
			m.stage.nodes[n].format = try prog.appliedFormat(m, old, format)
			prog.autoSize(m, n)
			Value.Undefined
		"replaceText", "replaceSel":
			text = try prog.textArg(m, args, args.len - 1)
			m.stage.nodes[n].text = text
			Value.Undefined
		"removeTextField":
			prog.removeClip(m, n)
			Value.Undefined
		"getDepth": Value.Num(f64(m.stage.nodes[n].placed.depth - depthBias))
		"getLineMetrics":
			metrics = prog.scene.textMetrics(t, m.stage.nodes[n])
			k = try prog.intArg(m, args, 0, 0)
			if k < 0 or k >= metrics.widths.len: return Value.Undefined
			id = m.newObject(m.protos.object)
			for (key, v) in [("width", metrics.widths[k]), ("height", metrics.lineHeight),
				("ascent", metrics.ascent), ("descent", metrics.descent),
				("x", metrics.starts[k]), ("leading", 0.0)]:
				m.setOwn(id, key, .Num(f64(v)))
			Value.Obj(id)
		"getLineOffset":
			k = try prog.intArg(m, args, 0, 0)
			offsets = lineOffsets(try prog.toText(m, try prog.getMember(m, me, "text")),
				prog.scene.textMetrics(t, m.stage.nodes[n]).texts)
			Value.Num(f64(offsets[k]) if k >= 0 and k < offsets.len else -1.0)
		"getLineIndexAtPoint":
			y = f32(try prog.toNumber(m, arg(args, 1)))
			metrics = prog.scene.textMetrics(t, m.stage.nodes[n])
			for k, top in metrics.tops:
				if y >= top and y < top + metrics.heights[k]: return Value.Num(f64(k))
			Value.Num(-1.0)
		"getCharBoundaries":
			i = try prog.intArg(m, args, 0, 0)
			metrics = prog.scene.textMetrics(t, m.stage.nodes[n])
			offsets = lineOffsets(try prog.toText(m, try prog.getMember(m, me, "text")),
				metrics.texts)
			k = -1
			for j, start in offsets:
				if start <= i: k = j
			if k < 0: return Value.Undefined
			id = m.newObject(m.protos.object)
			top = metrics.tops[k]
			bottom = top + metrics.heights[k]
			for (key, v) in [("x", metrics.starts[k]), ("y", top), ("width", 0.0),
				("height", metrics.heights[k]), ("left", metrics.starts[k]), ("top", top),
				("right", metrics.starts[k]), ("bottom", bottom)]:
				m.setOwn(id, key, .Num(f64(v)))
			Value.Obj(id)
		_:
			m.missing("TextField.{name}")
			Value.Undefined

# Where each wrapped line starts in the field's text, the index of its first character (counted
# as ActionScript counts them): the lines found in order, each from where the one before it ended
# (the breaks between them, a paragraph's end or the space a wrap fell on, belong to neither).
fn lineOffsets(text str, lines str[]):
	chars = text.chars()
	out = []
	at = 0
	for line in lines:
		part = line.chars()
		found = charIndexOf(chars, part, at)
		if found < 0: found = at
		out.push(found)
		at = found + part.len
	out
