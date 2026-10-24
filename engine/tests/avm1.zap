# The ActionScript 2 machine on movies made here: bytecode assembled by hand into DoAction tags,
# run by the player, its traces read back. Arithmetic and text, variables, functions with
# registers, objects over a prototype, arrays, a clip sent to a frame, a text field set by script
# and an enterFrame handler counting frames.

import engine.swf
import engine.swf.avm1

# ActionScript bytecode written action by action
type Asm:
	out u8[] = []

	fn op(code i64):
		out.push(u8(code))

	fn act(code i64, body u8[]):
		out.push(u8(code))
		out.pushU16le(body.len)
		out.extend(body)

	# one Push of texts (a leading "#" a number, "r1" a register)
	mut fn push(items str[]):
		body u8[] = []
		for item in items:
			if item.startsWith("#"):
				body.push(7)
				body.pushI32le(i64.parse(item[1..]) ?? 0)
			elif item.startsWith("r") and item.len == 2:
				body.push(4)
				body.push(u8(i64.parse(item[1..]) ?? 0))
			else:
				body.push(0)
				body.extend(item.bytes())
				body.push(0)
		act(0x96, body)

	mut fn pushDouble(x f64):
		b = []
		b.pushF64le(x)
		body u8[] = [6]
		body.extend(b[4..8])
		body.extend(b[..4])
		act(0x96, body)

	# DefineFunction2 named `name`, its parameters in registers 1 on, its body
	fn function2(name str, params str[], body Asm):
		head = []
		head.extend(name.bytes())
		head.push(0)
		head.pushU16le(params.len)
		head.push(u8(params.len + 1))
		head.pushU16le(0)
		for k, p in params:
			head.push(u8(k + 1))
			head.extend(p.bytes())
			head.push(0)
		head.pushU16le(body.out.len)
		act(0x8E, head)
		out.extend(body.out)

	# DefineFunction (the first version): parameters as local variables
	fn function1(name str, body Asm):
		head = []
		head.extend(name.bytes())
		head.push(0)
		head.pushU16le(0)
		head.pushU16le(body.out.len)
		act(0x9B, head)
		out.extend(body.out)

fn swfTag(mut out u8[], code i64, body u8[]):
	out.pushU16le((code << 6) | 63)
	out.pushU32le(body.len)
	out.extend(body)

# a 550 x 400 stage
stageRect u8[] = [0x78, 0x00, 0x05, 0x5F, 0x00, 0x00, 0x0F, 0xA0, 0x00]

# PlaceObject2 of a character at a depth with an instance name
fn placeNamed(depth i64, character i64, name str):
	b u8[] = [0x22]
	b.pushU16le(depth)
	b.pushU16le(character)
	b.extend(name.bytes())
	b.push(0)
	b

# a movie of one frame: a sprite of three frames placed as "mc", a text field as "tf", then the
# code
fn movieOf(code Asm):
	tags = []
	sprite = []
	sprite.pushU16le(1)
	sprite.pushU16le(3)
	loop 3:
		swfTag(sprite, 1, [])
	swfTag(sprite, 0, [])
	swfTag(tags, 39, sprite)
	field = []
	field.pushU16le(2)
	field.extend(stageRect)
	field.extend([0, 0, 0])
	swfTag(tags, 37, field)
	swfTag(tags, 26, placeNamed(1, 1, "mc"))
	swfTag(tags, 26, placeNamed(2, 2, "tf"))
	action = code.out.copy()
	action.push(0)
	swfTag(tags, 12, action)
	swfTag(tags, 1, [])
	swfTag(tags, 0, [])
	head = []
	head.extend(stageRect)
	head.pushU16le(30 << 8)
	head.pushU16le(1)
	out = "FWS".bytes().copy()
	out.push(8)
	out.pushU32le(8 + head.len + tags.len)
	out.extend(head)
	out.extend(tags)
	swf.readSwf(out) ?? fail

fn played(code Asm):
	avm1.newPlayer(swf.newScene(code.movieOf()), avm1.Viewport())

test "arithmetic and text: numbers printed with 15 digits, + joining text":
	a = Asm()
	a.push(["#1", "#2", "#3"])
	a.op(0x0C)
	a.op(0x47)
	a.op(0x26)
	a.push(["a", "#1"])
	a.op(0x47)
	a.op(0x26)
	a.pushDouble(0.1)
	a.pushDouble(0.2)
	a.op(0x47)
	a.op(0x26)
	a.push(["#7", "#3"])
	a.op(0x3F)
	a.op(0x26)
	a.push(["#1", "#0"])
	a.op(0x0D)
	a.op(0x26)
	p = a.played()
	expect p.m.log == ["7", "a1", "0.3", "1", "Infinity"]
	expect avm1.numberText(1e21) == "1e+21" and avm1.numberText(-2.5) == "-2.5"

test "variables set, read and changed":
	a = Asm()
	a.push(["x", "#5"])
	a.op(0x1D)
	a.push(["x"])
	a.op(0x1C)
	a.op(0x50)
	a.op(0x26)
	p = a.played()
	expect p.m.log == ["6"]

test "a function's parameters in registers, called by name":
	body = Asm()
	body.push(["r1", "#2"])
	body.op(0x0C)
	body.op(0x3E)
	a = Asm()
	a.function2("twice", ["n"], body)
	a.push(["#21", "#1", "twice"])
	a.op(0x3D)
	a.op(0x26)
	p = a.played()
	expect p.m.log == ["42"] and p.m.errors == 0

test "objects made by a constructor share its prototype's methods":
	ctor = Asm()
	ctor.push(["this"])
	ctor.op(0x1C)
	ctor.push(["v", "#1"])
	ctor.op(0x4F)
	method = Asm()
	method.push(["this"])
	method.op(0x1C)
	method.push(["v"])
	method.op(0x4E)
	method.push(["#1"])
	method.op(0x47)
	method.op(0x3E)
	a = Asm()
	a.function1("C", ctor)
	a.push(["C"])
	a.op(0x1C)
	a.push(["prototype"])
	a.op(0x4E)
	a.push(["get"])
	a.function1("", method)
	a.op(0x4F)
	a.push(["o", "#0", "C"])
	a.op(0x40)
	a.op(0x1D)
	a.push(["#0", "o"])
	a.op(0x1C)
	a.push(["get"])
	a.op(0x52)
	a.op(0x26)
	a.push(["o"])
	a.op(0x1C)
	a.push(["C"])
	a.op(0x1C)
	a.op(0x54)
	a.op(0x26)
	p = a.played()
	expect p.m.log == ["2", "true"] and p.m.errors == 0

test "an array sorted, joined and grown":
	a = Asm()
	a.push(["a", "#2", "#1", "#3", "#3"])
	a.op(0x42)
	a.op(0x1D)
	a.push(["#0", "a"])
	a.op(0x1C)
	a.push(["sort"])
	a.op(0x52)
	a.op(0x17)
	a.push(["-", "#1", "a"])
	a.op(0x1C)
	a.push(["join"])
	a.op(0x52)
	a.op(0x26)
	a.push(["#4", "#1", "a"])
	a.op(0x1C)
	a.push(["push"])
	a.op(0x52)
	a.op(0x26)
	p = a.played()
	expect p.m.log == ["1-2-3", "4"]

test "a clip sent to its third frame and a text field given its text by script":
	a = Asm()
	a.push(["#3", "#1", "mc"])
	a.op(0x1C)
	a.push(["gotoAndStop"])
	a.op(0x52)
	a.op(0x17)
	a.push(["mc"])
	a.op(0x1C)
	a.push(["_currentframe"])
	a.op(0x4E)
	a.op(0x26)
	a.push(["tf"])
	a.op(0x1C)
	a.push(["text", "hello"])
	a.op(0x4F)
	a.push(["tf"])
	a.op(0x1C)
	a.push(["text"])
	a.op(0x4E)
	a.op(0x26)
	p = a.played()
	expect p.m.log == ["3", "hello"] and p.m.errors == 0
	mc = p.m.stage.nodeAt("mc") ?? fail("no mc")
	tf = p.m.stage.nodeAt("tf") ?? fail("no tf")
	expect p.m.stage.nodes[mc].frame == 2 and not p.m.stage.nodes[mc].playing
	expect p.m.stage.nodes[tf].text == "hello"

test "an enterFrame handler runs once a frame":
	count = Asm()
	count.push(["count", "count"])
	count.op(0x1C)
	count.op(0x50)
	count.op(0x1D)
	a = Asm()
	a.push(["count", "#0"])
	a.op(0x1D)
	a.push(["this"])
	a.op(0x1C)
	a.push(["onEnterFrame"])
	a.function1("", count)
	a.op(0x4F)
	p = a.played()
	loop 10:
		p.advance()
	root = p.m.objectLinked(p.m.stage.root) ?? fail("no root object")
	expect p.m.ownValue(root, "count") == .Num(10.0) and p.m.errors == 0

test "the heap's dead activations are collected between frames":
	count = Asm()
	count.push(["count", "count"])
	count.op(0x1C)
	count.op(0x50)
	count.op(0x1D)
	a = Asm()
	a.push(["count", "#0"])
	a.op(0x1D)
	a.push(["this"])
	a.op(0x1C)
	a.push(["onEnterFrame"])
	a.function1("", count)
	a.op(0x4F)
	p = a.played()
	loop 3000:
		p.advance()
	root = p.m.objectLinked(p.m.stage.root) ?? fail("no root object")
	expect p.m.ownValue(root, "count") == .Num(3000.0) and p.m.heap.len < 8000

test "a press and a release over a field with button handlers":
	handler = Asm()
	handler.push(["presses", "presses"])
	handler.op(0x1C)
	handler.op(0x50)
	handler.op(0x1D)
	a = Asm()
	a.push(["presses", "#0"])
	a.op(0x1D)
	for name in ["onPress", "onRelease"]:
		a.push(["tf"])
		a.op(0x1C)
		a.push([name])
		a.function1("", handler)
		a.op(0x4F)
	p = a.played()
	p.pointer(640.0, 360.0, false)
	p.pointer(640.0, 360.0, true)
	p.pointer(640.0, 360.0, false)
	root = p.m.objectLinked(p.m.stage.root) ?? fail("no root object")
	expect p.m.ownValue(root, "presses") == .Num(2.0) and p.m.errors == 0
