# MovieClip's natives (Ruffle's core/src/avm1/globals/movie_clip.rs): the timeline's goto, play and
# stop; clips made by script (attachMovie of an exported symbol, its class constructed at once,
# createEmptyMovieClip, duplicateMovieClip) and removed; depths as ActionScript numbers them
# (the timeline's from -16384); points and bounds between a clip's space and the stage's. The
# drawing API and drags do nothing yet.

import engine.swf

# ActionScript's depth 0 is the file's 16384
pub depthBias = 16_384

# long: MovieClip's methods, one arm each
fn clipNative(prog Program, mut m Machine, name str, me Value, args Value[]) Value ? Thrown:
	if name == "MovieClip": return Value.Undefined
	n = m.nodeOf(me) ?? return Value.Undefined
	match name:
		"gotoAndStop", "gotoAndPlay":
			f = try prog.frameOfValue(m, n, arg(args, 0)) ?? return Value.Undefined
			prog.gotoFrame(m, n, f, name == "gotoAndPlay")
		"play", "stop": prog.setPlaying(m, n, name == "play")
		"nextFrame", "prevFrame":
			prog.gotoFrame(m, n, m.stage.nodes[n].frame + (1 if name == "nextFrame" else -1), false)
		"attachMovie": return try prog.attachMovie(m, n, args)
		"createEmptyMovieClip":
			clipName = try prog.textArg(m, args, 0)
			depth = try prog.intArg(m, args, 1, 0)
			return Value.Obj(try prog.newClip(m, n, -1, clipName, depth, .Undefined))
		"createTextField": return try prog.newTextField(m, n, args)
		"duplicateMovieClip": return try prog.duplicate(m, n, args)
		"removeMovieClip": prog.removeClip(m, n)
		"getNextHighestDepth":
			top = -1
			for c in m.stage.nodes[n].children:
				top = top.max(m.stage.nodes[c].placed.depth - depthBias)
			return Value.Num(f64(top + 1))
		"getDepth": return Value.Num(f64(m.stage.nodes[n].placed.depth - depthBias))
		"swapDepths":
			other = arg(args, 0)
			depth = m.stage.nodes[m.nodeOf(other) ?? n].placed.depth
			if not other.isObject(): depth = try prog.intArg(m, args, 0, 0) + depthBias
			m.stage.swapDepth(n, depth)
		"localToGlobal", "globalToLocal":
			try prog.convertPoint(m, n, arg(args, 0), name == "localToGlobal")
		"getBounds", "getRect": return try prog.boundsObject(m, n, arg(args, 0))
		"hitTest": return Value.Bool(try prog.hitTest(m, n, args))
		"getInstanceAtDepth":
			depth = try prog.intArg(m, args, 0, 0) + depthBias
			c = m.stage.childAtDepth(n, depth) ?? return Value.Undefined
			return Value.Obj(m.objectOfNode(prog, c))
		"getBytesLoaded", "getBytesTotal": return Value.Num(1.0)
		"getSWFVersion": return Value.Num(f64(prog.version))
		_: m.missing("MovieClip.{name}")
	Value.Undefined

# a clip made by script: the character (-1 none) at the depth, named; its object made, the init
# object's properties copied onto it and its class constructed now
fn newClip(
	prog Program,
	mut m Machine,
	parent Handle<swf.Node>,
	character i64,
	name str,
	depth i64,
	init Value
) Handle<Obj> ? Thrown:
	prog.newNode(m, parent, character, name, depth, init, none, swf.Affine())

# MovieClip.createTextField(name, depth, x, y, width, height) (Ruffle's text_field.rs new): an
# empty field of the default format (12 pixels, black, left) with no font until a TextFormat
# gives one, its box at x, y in pixels
fn newTextField(prog Program, mut m Machine, parent Handle<swf.Node>, args Value[]) Value ? Thrown:
	name = try prog.textArg(m, args, 0)
	depth = try prog.intArg(m, args, 1, 0)
	x = try prog.numberArg(m, args, 2)
	y = try prog.numberArg(m, args, 3)
	w = try prog.numberArg(m, args, 4)
	h = try prog.numberArg(m, args, 5)
	field = swf.EditText(id = -1, bounds = swf.Rect(xmax = f32(w) * 20.0, ymax = f32(h) * 20.0),
		font = -1, fontClass = "", height = 240.0, color = Vec4(0.0, 0.0, 0.0, 1.0), align = 0,
		leftMargin = 0.0, rightMargin = 0.0, indent = 0.0, leading = 0.0, variable = "",
		text = "", html = false, wordWrap = false, multiline = false, border = false,
		autoSize = false)
	at = swf.Affine(tx = f32(x) * 20.0, ty = f32(y) * 20.0)
	Value.Obj(try prog.newNode(m, parent, -1, name, depth, .Undefined, field, at))

fn newNode(
	prog Program,
	mut m Machine,
	parent Handle<swf.Node>,
	character i64,
	name str,
	depth i64,
	init Value,
	field swf.EditText?,
	matrix swf.Affine
) Handle<Obj> ? Thrown:
	at = depth + depthBias
	if m.stage.childAtDepth(parent, at) is old: prog.removeClip(m, old)
	placed = swf.Placed(depth = at, character, matrix, color = swf.ColorTransform(),
		ratio = -1, name = name.copy(), clipDepth = 0, blend = 0, visible = true, placedAt = 0)
	n = m.stage.addChild(prog.scene, parent, placed, -1)
	m.stage.nodes[n].field = field.copy()
	id = m.objectOfNode(prog, n)
	if init is Obj(from):
		for key in m.heap[from].order.copy():
			v = m.heap[from].props[key].value.copy()
			m.setOwn(id, key, v)
	try prog.takeStageChanges(m, n)
	id

fn attachMovie(prog Program, mut m Machine, n Handle<swf.Node>, args Value[]) Value ? Thrown:
	symbol = try prog.textArg(m, args, 0)
	character = prog.scene.movie.exported(symbol, m.library) ?? return Value.Undefined
	name = try prog.textArg(m, args, 1)
	depth = try prog.intArg(m, args, 2, 0)
	Value.Obj(try prog.newClip(m, n, character, name, depth, arg(args, 3)))

fn duplicate(prog Program, mut m Machine, n Handle<swf.Node>, args Value[]) Value ? Thrown:
	parent = m.stage.nodes[n].parent ?? return Value.Undefined
	name = try prog.textArg(m, args, 0)
	depth = try prog.intArg(m, args, 1, 0)
	character = m.stage.nodes[n].placed.character
	id = try prog.newClip(m, parent, character, name, depth, arg(args, 2))
	c = m.nodeOf(.Obj(id)) ?? return Value.Undefined
	m.stage.nodes[c].placed.matrix = m.stage.nodes[n].placed.matrix
	m.stage.nodes[c].placed.color = m.stage.nodes[n].placed.color
	Value.Obj(id)

# CloneSprite: the source clip copied under a new name at a depth (the file's numbering)
fn cloneSprite(prog Program, mut m Machine, mut a Activation) () ? Thrown:
	depth = toInt32(try prog.popNumber(m, a))
	name = try prog.popText(m, a)
	source = a.pop()
	n = prog.nodeOfTarget(m, a, source) ?? return
	try prog.duplicate(m, n, [.Str(name), .Num(f64(depth - depthBias))])

# a clip taken off the stage, its unload handlers queued
pub fn removeClip(prog Program, mut m Machine, n Handle<swf.Node>):
	if n == m.stage.root: return
	m.stage.removeNode(n)
	prog.takeRemoved(m)

# localToGlobal and globalToLocal: the point object's x and y changed in place
fn convertPoint(
	prog Program,
	mut m Machine,
	n Handle<swf.Node>,
	point Value,
	toStage bool
) () ? Thrown:
	x = try prog.toNumber(m, try prog.getMember(m, point, "x"))
	y = try prog.toNumber(m, try prog.getMember(m, point, "y"))
	matrix = m.stage.stageMatrix(n)
	if not toStage: matrix = matrix.inverse()
	p = matrix.apply(Vec2(f32(x), f32(y)) * 20.0) / 20.0
	try prog.setMember(m, point, "x", .Num(f64(p.x)))
	try prog.setMember(m, point, "y", .Num(f64(p.y)))

# getBounds(space): the clip's bounds in another clip's space (its own when none), pixels
fn boundsObject(prog Program, mut m Machine, n Handle<swf.Node>, space Value) Value ? Thrown:
	other = m.nodeOf(space) ?? n
	matrix = m.stage.stageMatrix(other).inverse().times(m.stage.stageMatrix(n))
	b = prog.scene.boundsOf(m.stage, n, matrix) ?? swf.Rect()
	id = m.newObject(m.protos.object)
	m.setOwn(id, "xMin", .Num(f64(b.xmin) / 20.0))
	m.setOwn(id, "xMax", .Num(f64(b.xmax) / 20.0))
	m.setOwn(id, "yMin", .Num(f64(b.ymin) / 20.0))
	m.setOwn(id, "yMax", .Num(f64(b.ymax) / 20.0))
	Value.Obj(id)

# hitTest(x, y): whether the stage point is in the clip's bounds; hitTest(clip): whether the
# two clips' bounds meet
fn hitTest(prog Program, mut m Machine, n Handle<swf.Node>, args Value[]) bool ? Thrown:
	mine = prog.scene.boundsOf(m.stage, n, m.stage.stageMatrix(n)) ?? return false
	if arg(args, 0) is Obj:
		other = m.nodeOf(arg(args, 0)) ?? return false
		theirs = prog.scene.boundsOf(m.stage, other, m.stage.stageMatrix(other)) ?? return false
		return (mine.xmin <= theirs.xmax and theirs.xmin <= mine.xmax and
				mine.ymin <= theirs.ymax and theirs.ymin <= mine.ymax)
	x = f32(try prog.numberArg(m, args, 0)) * 20.0
	y = f32(try prog.numberArg(m, args, 1)) * 20.0
	x >= mine.xmin and x <= mine.xmax and y >= mine.ymin and y <= mine.ymax
