# long: the global object's table of classes and functions, one line each
#
# The global object as Flash Player 8 and Scaleform's GFx 3 make it (Ruffle's
# core/src/avm1/globals.rs): Object, Function, Array, String, Number, Boolean, Math, Date,
# MovieClip, Button, TextField, TextFormat, Key, Mouse, Stage, Selection, System, Color, Sound,
# flash.external.ExternalInterface and flash.geom's Rectangle and Point, and the global functions.
# Each native is a function object naming its group (the file whose dispatch runs it) and name.

groupGlobal = 0
groupObject = 1
groupArray = 2
groupString = 3
groupMath = 4
groupClip = 5
groupText = 6
groupFlash = 7

fn methods(mut m Machine, holder Handle<Obj>, group i64, names str[]):
	for name in names:
		f = m.nativeFn(group, name)
		m.define(holder, name, .Obj(f), dontEnum)

# a native class: its constructor (named `name` in its group) over the prototype
fn nativeClass(mut m Machine, group i64, name str, proto Handle<Obj>):
	ctor = m.nativeFn(group, name)
	m.define(ctor, "prototype", .Obj(proto), dontEnum | dontDelete)
	m.define(proto, "constructor", .Obj(ctor), dontEnum)
	m.define(proto, "__constructor__", .Obj(ctor), dontEnum)
	m.define(m.globals, name, .Obj(ctor), dontEnum)
	ctor

# the machine's global object and scope, every built-in made
pub fn installBuiltins(mut m Machine):
	p = m.protos
	object = m.nativeClass(groupObject, "Object", p.object)
	m.methods(object, groupObject, ["registerClass"])
	m.methods(p.object, groupObject, ["hasOwnProperty", "addProperty", "toString", "valueOf",
		"isPrototypeOf", "isPropertyEnumerable", "watch", "unwatch", "toLocaleString"])
	m.nativeClass(groupObject, "Function", p.function)
	m.methods(p.function, groupObject, ["call", "apply"])
	m.nativeClass(groupArray, "Array", p.array)
	m.methods(p.array, groupArray, ["push", "pop", "shift", "unshift", "splice", "slice", "join",
		"toString", "concat", "reverse", "sort", "sortOn"])
	array = m.heap[m.globals].props["Array"].value.objectId() ?? return
	for (name, v) in [("CASEINSENSITIVE", 1.0), ("DESCENDING", 2.0), ("UNIQUESORT", 4.0),
		("RETURNINDEXEDARRAY", 8.0), ("NUMERIC", 16.0)]:
		m.define(array, name, .Num(v), dontEnum | dontDelete | readOnly)
	string = m.nativeClass(groupString, "String", p.string)
	m.methods(string, groupString, ["fromCharCode"])
	m.methods(p.string, groupString, ["charAt", "charCodeAt", "indexOf", "lastIndexOf", "substr",
		"substring", "slice", "split", "toUpperCase", "toLowerCase", "concat", "toString",
		"valueOf"])
	m.nativeClass(groupString, "Number", p.number)
	m.methods(p.number, groupString, ["toString", "valueOf"])
	m.numberConstants()
	m.nativeClass(groupString, "Boolean", p.boolean)
	m.methods(p.boolean, groupString, ["toString", "valueOf"])
	m.nativeClass(groupFlash, "Date", p.date)
	m.methods(p.date, groupFlash, ["getTime", "valueOf", "getHours", "getMinutes", "getSeconds",
		"getMilliseconds", "getFullYear", "getMonth", "getDate", "getDay", "toString"])
	m.nativeClass(groupFlash, "Error", p.error)
	m.methods(p.error, groupFlash, ["toString"])
	m.define(p.error, "message", .Str("Error"), dontEnum)
	m.installMath()
	m.installClip()
	m.installFlash()
	m.methods(m.globals, groupGlobal, ["ASSetPropFlags", "setInterval", "clearInterval",
		"setTimeout", "clearTimeout", "parseInt", "parseFloat", "isNaN", "isFinite", "escape",
		"unescape", "getTimer", "trace", "updateAfterEvent", "ASnative", "getVersion"])
	m.define(m.globals, "NaN", .Num(0.0 / 0.0), dontEnum)
	m.define(m.globals, "Infinity", .Num(1.0 / 0.0), dontEnum)
	m.define(m.globals, "gfxExtensions", .Bool(true), 0)

fn numberConstants(mut m Machine):
	number = m.heap[m.globals].props["Number"].value.objectId() ?? return
	for (name, v) in [("MAX_VALUE", 1.7976931348623157e308), ("MIN_VALUE", 5e-324),
		("NaN", 0.0 / 0.0), ("POSITIVE_INFINITY", 1.0 / 0.0), ("NEGATIVE_INFINITY", -1.0 / 0.0)]:
		m.define(number, name, .Num(v), dontEnum | dontDelete | readOnly)

fn installMath(mut m Machine):
	math = m.newObject(m.protos.object)
	m.define(m.globals, "Math", .Obj(math), dontEnum)
	m.methods(math, groupMath, ["abs", "ceil", "floor", "round", "max", "min", "pow", "sqrt",
		"sin", "cos", "tan", "atan", "atan2", "asin", "acos", "exp", "log", "random"])
	for (name, v) in [("PI", pi), ("E", 2.718281828459045),
		("LN2", 0.6931471805599453), ("LN10", 2.302585092994046), ("LOG2E", 1.4426950408889634),
		("LOG10E", 0.4342944819032518), ("SQRT1_2", 0.7071067811865476),
		("SQRT2", 1.4142135623730951)]:
		m.define(math, name, .Num(v), dontEnum | dontDelete | readOnly)

fn installClip(mut m Machine):
	p = m.protos
	m.nativeClass(groupClip, "MovieClip", p.clip)
	m.methods(p.clip, groupClip, ["gotoAndStop", "gotoAndPlay", "play", "stop", "nextFrame",
		"prevFrame", "attachMovie", "createEmptyMovieClip", "duplicateMovieClip",
		"removeMovieClip", "getNextHighestDepth", "getDepth", "swapDepths", "localToGlobal",
		"globalToLocal", "getBounds", "getRect", "hitTest", "getInstanceAtDepth",
		"createTextField", "startDrag", "stopDrag", "setMask", "lineStyle", "beginFill",
		"beginGradientFill", "moveTo", "lineTo", "curveTo", "endFill", "clear", "loadMovie",
		"unloadMovie", "getURL", "getBytesLoaded", "getBytesTotal", "attachAudio",
		"getSWFVersion", "loadVariables"])
	m.nativeClass(groupClip, "Button", p.button)
	m.methods(p.button, groupClip, ["getDepth", "swapDepths"])
	m.nativeClass(groupText, "TextField", p.text)
	m.methods(p.text, groupText, ["getTextFormat", "setTextFormat", "setNewTextFormat",
		"getNewTextFormat", "replaceText", "replaceSel", "removeTextField", "getDepth",
		"getLineMetrics", "getLineOffset", "getLineIndexAtPoint", "getCharBoundaries",
		"addListener", "removeListener"])
	m.nativeClass(groupText, "TextFormat", p.textFormat)

fn installFlash(mut m Machine):
	for name in ["Key", "Mouse", "Stage", "Selection", "System", "Sound", "Color", "flash",
		"Accessibility", "IME", "MovieClipLoader"]:
		holder = m.stageObject if name == "Stage" else m.newObject(m.protos.object)
		m.define(m.globals, name, .Obj(holder), dontEnum)
		match name:
			"Key":
				m.methods(holder, groupFlash, ["isDown", "getCode", "getAscii", "addListener",
					"removeListener", "isToggled"])
				m.keyConstants(holder)
			"Mouse":
				m.methods(holder, groupFlash, ["addListener", "removeListener", "show", "hide",
					"getTopMostEntity"])
				m.define(holder, "_listeners", .Obj(m.mouseListeners), dontEnum)
			"Stage":
				m.methods(holder, groupFlash, ["addListener", "removeListener"])
			"Selection":
				m.methods(holder, groupFlash, [
					"setFocus",
					"getFocus",
					"captureFocus",
					"addListener",
					"removeListener",
					"moveFocus", "setSelection", "getBeginIndex", "getEndIndex",
					"getCaretIndex", "getControllerMaskByFocusGroup", "getControllerFocusGroup",
					"setControllerFocusGroup"])
			"System":
				caps = m.newObject(m.protos.object)
				m.define(holder, "capabilities", .Obj(caps), dontEnum)
				m.setOwn(caps, "version", .Str("WIN 8,0,0,0"))
				m.setOwn(caps, "os", .Str("Windows"))
			"Sound", "Color":
				proto = m.newObject(m.protos.object)
				ctor = m.nativeClass(groupFlash, name, proto)
				m.methods(proto, groupFlash, ["setRGB", "getRGB", "setTransform",
					"getTransform", "attachSound", "start", "stop", "setVolume", "getVolume"])
				m.define(m.globals, name, .Obj(ctor), dontEnum)
			"MovieClipLoader":
				proto = m.newObject(m.protos.object)
				ctor = m.nativeClass(groupFlash, name, proto)
				m.methods(proto, groupFlash, ["loadClip", "unloadClip", "getProgress",
					"addListener", "removeListener"])
				m.define(m.globals, name, .Obj(ctor), dontEnum)
			"flash": m.installFlashPackage(holder)
			_: pass

fn keyConstants(mut m Machine, key Handle<Obj>):
	for (name, code) in [("BACKSPACE", 8), ("TAB", 9), ("ENTER", 13), ("SHIFT", 16),
		("CONTROL", 17), ("ALT", 18), ("CAPSLOCK", 20), ("ESCAPE", 27), ("SPACE", 32),
		("PGUP", 33), ("PGDN", 34), ("END", 35), ("HOME", 36), ("LEFT", 37), ("UP", 38),
		("RIGHT", 39), ("DOWN", 40), ("INSERT", 45), ("DELETEKEY", 46)]:
		m.define(key, name, .Num(f64(code)), dontEnum | dontDelete | readOnly)

# flash.external.ExternalInterface and flash.geom's Rectangle and Point
fn installFlashPackage(mut m Machine, flash Handle<Obj>):
	external = m.newObject(m.protos.object)
	m.define(flash, "external", .Obj(external), dontEnum)
	interface = m.newObject(m.protos.object)
	m.define(external, "ExternalInterface", .Obj(interface), dontEnum)
	m.methods(interface, groupFlash, ["call", "addCallback"])
	m.define(interface, "available", .Bool(true), dontEnum)
	geom = m.newObject(m.protos.object)
	m.define(flash, "geom", .Obj(geom), dontEnum)
	rectangle = m.nativeFn(groupFlash, "Rectangle")
	m.define(rectangle, "prototype", .Obj(m.protos.rectangle), dontEnum)
	m.define(geom, "Rectangle", .Obj(rectangle), dontEnum)
	point = m.nativeFn(groupFlash, "Point")
	m.define(point, "prototype", .Obj(m.protos.point), dontEnum)
	m.define(geom, "Point", .Obj(point), dontEnum)
	display = m.newObject(m.protos.object)
	m.define(flash, "display", .Obj(display), dontEnum)
	bitmapData = m.newObject(m.protos.object)
	m.define(display, "BitmapData", .Obj(bitmapData), dontEnum)
	m.methods(bitmapData, groupFlash, ["loadBitmap"])
	m.methods(m.protos.rectangle, groupFlash, ["contains", "clone"])
	m.methods(m.protos.point, groupFlash, ["clone"])
