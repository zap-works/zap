# The player's objects (Ruffle's core/src/avm1/globals: key.rs, mouse.rs, stage.rs,
# selection.rs, color.rs, external_interface.rs, rectangle.rs) and Scaleform's additions:
# Stage.visibleRect (what the window shows of the stage, in the stage's pixels) and Stage.safeRect
# (the safe zone's inset), Selection's controller focus groups (one controller, in group 0),
# Mouse.getTopMostEntity (nothing under the pointer), a MovieClipLoader that loads nothing (the
# game's menus read no files), BitmapData.loadBitmap's exported bitmaps, and ExternalInterface, the movie's line to
# the game: a call is kept
# for the game to read, and a canned answer, when the game gave one, comes back at once through
# the "respond" callback GameDelegate registers, or a value of the movie's through another
# callback (Machine.answers).

# long: the player's objects' methods, one arm each
import engine.swf

fn flashNative(prog Program, mut m Machine, name str, me Value, args Value[]) Value ? Thrown:
	match name:
		"isDown": Value.Bool(try prog.intArg(m, args, 0, 0) in m.keysDown)
		"getCode", "getAscii": Value.Num(f64(m.lastKey))
		"isToggled": Value.Bool(false)
		"addListener", "removeListener": prog.listen(m, me, arg(args, 0), name == "addListener")
		"show", "hide": Value.Num(1.0)
		"setFocus":
			m.focus = arg(args, 0).objectId()
			Value.Bool(true)
		"getFocus":
			focus = m.focus ?? return Value.Null
			Value.Str(try prog.toText(m, .Obj(focus)))
		"captureFocus", "moveFocus", "setSelection": Value.Undefined
		"getBeginIndex", "getEndIndex", "getCaretIndex": Value.Num(-1.0)
		"getControllerMaskByFocusGroup": Value.Num(1.0)
		"getControllerFocusGroup", "setControllerFocusGroup": Value.Num(0.0)
		"getTopMostEntity": Value.Undefined
		"call": try prog.externalCall(m, args)
		"addCallback":
			key = try prog.textArg(m, args, 0)
			m.callbacks[key] = Callback(me = arg(args, 1), function = arg(args, 2))
			Value.Bool(true)
		"Rectangle", "Point":
			id = me.objectId() ?? return Value.Undefined
			keys = ["x", "y", "width", "height"] if name == "Rectangle" else ["x", "y"]
			for k, key in keys:
				m.setOwn(
					id,
					key,
					.Num(try prog.numberArg(m, args, k) if k < args.len else 0.0)
				)
			Value.Undefined
		"contains":
			x = try prog.numberArg(m, args, 0)
			y = try prog.numberArg(m, args, 1)
			r = try prog.rectOf(m, me)
			p = Vec2(f32(x), f32(y))
			Value.Bool(p.x >= r.x and p.x < r.x + r.z and p.y >= r.y and p.y < r.y + r.w)
		"clone":
			proto Handle<Obj>? = none
			if me.objectId() is o: proto = m.heap[o].proto
			id = m.newObject(proto)
			for key in ["x", "y", "width", "height"]:
				m.setOwn(id, key, try prog.getMember(m, me, key))
			Value.Obj(id)
		"Color", "Sound":
			if me is Obj(id): m.setOwn(id, "target", arg(args, 0))
			Value.Undefined
		"setRGB", "getRGB", "setTransform", "getTransform": try prog.colorNative(m, name, me, args)
		"attachSound", "start", "stop", "setVolume", "getVolume", "MovieClipLoader", "unloadClip", "getProgress": Value.Undefined
		"loadClip": Value.Bool(false)
		"loadBitmap": try prog.loadBitmap(m, args)
		"Date", "Error":
			if name == "Error" and me is Obj(id):
				if not args.isEmpty: m.setOwn(id, "message", arg(args, 0))
			Value.Undefined
		"getTime", "valueOf": Value.Num(m.primitiveOf(me).primitiveNumber())
		"getHours", "getMinutes", "getSeconds", "getMilliseconds", "getFullYear", "getMonth",
			"getDate", "getDay":
			Value.Num(0.0)
		"toString":
			if me is Obj(id):
				if m.heap[id].proto == m.protos.error:
					return Value.Str(try prog.toText(m, try prog.getMember(m, me, "message")))
			Value.Str("[object Object]")
		_:
			m.missing(name)
			Value.Undefined

# Key's, Mouse's and Stage's listeners: an object added once to the holder's list
fn listen(prog Program, mut m Machine, holder Value, who Value, add bool) Value:
	id = holder.objectId() ?? return .Bool(false)
	list = m.keyListeners
	if m.heap[id].props.get("_listeners") is p:
		list = p.value.objectId() ?? list
	else:
		list = m.newArray([])
		m.define(id, "_listeners", .Obj(list), dontEnum)
	if id != m.stageObject and m.heap[id].props.get("isDown") != none: list = m.keyListeners
	m.heap[list].items = m.heap[list].items.filter(not .strictEquals(who))
	if add: m.heap[list].items.push(who.copy())
	.Bool(true)

fn rectOf(prog Program, mut m Machine, r Value) Vec4 ? Thrown:
	x = try prog.toNumber(m, try prog.getMember(m, r, "x"))
	y = try prog.toNumber(m, try prog.getMember(m, r, "y"))
	w = try prog.toNumber(m, try prog.getMember(m, r, "width"))
	h = try prog.toNumber(m, try prog.getMember(m, r, "height"))
	Vec4(f32(x), f32(y), f32(w), f32(h))

# ExternalInterface.call(name, args...): kept for the game, answered by its canned response
fn externalCall(prog Program, mut m Machine, args Value[]) Value ? Thrown:
	name = try prog.textArg(m, args, 0)
	rest = args[1.min(len)..].map(.copy())
	m.external.push(ExternalCall(name = name.copy(), args = rest.map(.copy())))
	if m.answers.get(name) is a:
		value = prog.memberAt(m, pathParts(a.path))
		call = (m.callbacks.get("call") ?? return Value.Undefined).copy()
		if not value.isNullish():
			try prog.callValue(m, call.function, call.me, [.Str(a.callback.copy()), value], none)
	for reply in (m.replies.get(name) ?? []).copy():
		try prog.applyReply(m, rest, reply)
	first = try prog.toText(m, arg(rest, 1))
	keyed = "{name}:{first}" if "{name}:{first}" in m.responses else name
	answer = (m.responses.get(keyed) ?? return Value.Undefined).copy()
	respond = (m.callbacks.get("respond") ?? return Value.Undefined).copy()
	reply Value[] = [arg(rest, 0)]
	reply.extend(answer)
	try prog.callValue(m, respond.function, respond.me, reply, none)
	Value.Undefined

# what the game writes into the arguments of a call (`rest`: its id, then them)
fn applyReply(prog Program, mut m Machine, rest Value[], reply Reply) () ? Thrown:
	match reply:
		Text(slot, text):
			try prog.writeText(m, arg(rest, 1 + slot), text)
		TextAt(slot, index, texts):
			k = try prog.intArg(m, rest, 1 + index, -1)
			if k >= 0 and k < texts.len: try prog.writeText(m, arg(rest, 1 + slot), texts[k])
		Fill(slot, rows):
			array = arg(rest, 1 + slot).objectId() ?? return
			items Value[] = []
			for row in rows:
				id = m.newObject(m.protos.object)
				for member in row.members:
					m.setOwn(id, member.name, member.value.copy())
				items.push(.Obj(id))
			if m.isArray(array): m.heap[array].items = items
		Merge(slot, key, rows):
			array = arg(rest, 1 + slot).objectId() ?? return
			if not m.isArray(array): return
			for row in rows:
				wanted = ""
				for member in row.members:
					if member.name == key: wanted = member.value.primitiveText()
				found = -1
				items = m.heap[array].items.copy()
				for k, item in items:
					if primitiveText(try prog.getMember(m, item, key)) == wanted: found = k
				id = m.newObject(m.protos.object) if found < 0
					else items[found].objectId() ?? return
				for member in row.members:
					m.setOwn(id, member.name, member.value.copy())
				if found < 0: m.heap[array].items.push(.Obj(id))

# the text of an object the game was given set through its own `text` (a component's setter
# keeps the text it draws)
fn writeText(prog Program, mut m Machine, field Value, text str) () ? Thrown:
	try prog.setMember(m, field, "text", .Str(text.copy()))

# BitmapData.loadBitmap: a bitmap the movie exports by that name, as an object of its width and
# height (what the menus read of it before they show it in a text's <img>), undefined for none
fn loadBitmap(prog Program, mut m Machine, args Value[]) Value ? Thrown:
	name = try prog.textArg(m, args, 0)
	id = prog.scene.movie.exports.get(name) ?? return Value.Undefined
	w, h = (prog.scene.movie.bitmaps.get(id) ?? return Value.Undefined).bitmapSize()
	data = m.newObject(m.protos.object)
	m.setOwn(data, "width", .Num(f64(w)))
	m.setOwn(data, "height", .Num(f64(h)))
	Value.Obj(data)

# Color's methods over its target clip's color transform
fn colorNative(prog Program, mut m Machine, name str, me Value, args Value[]) Value ? Thrown:
	target = try prog.getMember(m, me, "target")
	n = m.nodeOf(target) ?? return Value.Undefined
	c = m.stage.nodes[n].placed.color
	match name:
		"setRGB":
			rgb = try prog.intArg(m, args, 0, 0)
			v = colorOf(rgb, 0.0)
			m.stage.nodes[n].placed.color = swf.ColorTransform(mul = Vec4(0.0, 0.0, 0.0, c.mul.w),
				add = Vec4(v.x, v.y, v.z, c.add.w))
		"getRGB":
			return Value.Num(f64((i64(c.add.x * 255.0) << 16) | (i64(c.add.y * 255.0) << 8) |
					i64(c.add.z * 255.0)))
		"setTransform":
			t = arg(args, 0)
			out = c
			for (k, key) in [(0, "r"), (1, "g"), (2, "b"), (3, "a")]:
				ka = try prog.getMember(m, t, "{key}a")
				kb = try prog.getMember(m, t, "{key}b")
				if not ka.isNullish(): out.mul[k] = f32(try prog.toNumber(m, ka)) / 100.0
				if not kb.isNullish(): out.add[k] = f32(try prog.toNumber(m, kb)) / 255.0
			m.stage.nodes[n].placed.color = out
		_:
			id = m.newObject(m.protos.object)
			for (k, key) in [(0, "r"), (1, "g"), (2, "b"), (3, "a")]:
				m.setOwn(id, "{key}a", .Num(f64(c.mul[k]) * 100.0))
				m.setOwn(id, "{key}b", .Num(f64(c.add[k]) * 255.0))
			return Value.Obj(id)
	Value.Undefined

# Stage's members: its size, Scaleform's visible and safe rectangles, the scale mode and align
fn stageMember(prog Program, mut m Machine, name str) Value?:
	view = m.viewport
	match name:
		"width": .Num(f64(prog.scene.movie.stageSize().x))
		"height": .Num(f64(prog.scene.movie.stageSize().y))
		"scaleMode": .Str(view.scaleMode.copy())
		"align": .Str(view.align.copy())
		"visibleRect":
			r = prog.visibleRect(m)
			.Obj(m.rectangle(f64(r.x), f64(r.y), f64(r.z), f64(r.w)))
		"safeRect":
			r = prog.visibleRect(m)
			.Obj(m.rectangle(view.safeX, view.safeY, f64(r.z) - 2.0 * view.safeX,
				f64(r.w) - 2.0 * view.safeY))
		_: none

fn rectangle(mut m Machine, x f64, y f64, w f64, h f64):
	id = m.newObject(m.protos.rectangle)
	for (key, v) in [("x", x), ("y", y), ("width", w), ("height", h), ("left", x), ("top", y),
		("right", x + w), ("bottom", y + h)]:
		m.setOwn(id, key, .Num(v))
	id
