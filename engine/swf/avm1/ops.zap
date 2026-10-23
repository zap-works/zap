# The actions without data (SWF specification v19, chapter 5; Ruffle's activation.rs): the stack's
# arithmetic, logic, strings and comparisons, variables and members, calls and objects, the
# timeline's play and stop. SWF 4's Add, Less and Equals are numeric; SWF 5's Add2, Less2 and
# Equals2 follow ECMA-262's rules.

import engine.swf

# long: the dispatch of the one-byte actions, one arm each
fn op(prog Program, mut m Machine, mut a Activation, code i64) Flow ? Thrown:
	match code:
		0x04: prog.stepTarget(m, a, 1)
		0x05: prog.stepTarget(m, a, -1)
		0x06: prog.setPlaying(m, a.target, true)
		0x07: prog.setPlaying(m, a.target, false)
		0x08, 0x09: pass
		0x0A, 0x0B, 0x0C, 0x0D, 0x3F:
			try prog.arithmetic(m, a, code)
		0x0E, 0x0F:
			try prog.numericCompare(m, a, code)
		0x10, 0x11:
			y = a.pop().isTrue()
			x = a.pop().isTrue()
			a.push(.Bool(x and y if code == 0x10 else x or y))
		0x12: a.push(.Bool(not a.pop().isTrue()))
		0x13, 0x29, 0x68:
			try prog.stringCompare(m, a, code)
		0x14, 0x31: a.push(.Num(f64((try prog.popText(m, a)).chars().len)))
		0x15, 0x35:
			try prog.stringExtract(m, a)
		0x17: a.pop()
		0x18:
			x = try prog.popNumber(m, a)
			a.push(.Num(x.trunc() if not isNaN(x) else x))
		0x1C:
			name = try prog.popText(m, a)
			a.push(try prog.getVariable(m, a, name))
		0x1D:
			v = a.pop()
			name = try prog.popText(m, a)
			try prog.setVariable(m, a, name, v)
		0x20:
			path = try prog.popText(m, a)
			a.target = prog.targetNode(m, a, path) ?? a.base
		0x21:
			y = try prog.popText(m, a)
			x = try prog.popText(m, a)
			a.push(.Str("{x}{y}"))
		0x22:
			try prog.getPropertyOp(m, a)
		0x23:
			try prog.setPropertyOp(m, a)
		0x24:
			try prog.cloneSprite(m, a)
		0x25:
			v = a.pop()
			if prog.nodeOfTarget(m, a, v) is n: prog.removeClip(m, n)
		0x26:
			text = try prog.popText(m, a)
			m.log.push(text)
		0x27:
			a.pop()
			a.pop()
			if a.pop().isTrue(): loop 4: a.pop()
		0x28: pass
		0x2A: return Thrown(a.pop())
		0x2B:
			v = a.pop()
			ctor = a.pop()
			a.push(v.copy() if prog.isInstance(m, v, ctor) else .Null)
		0x2C:
			try prog.implementsOp(m, a)
		0x30:
			n = i64(try prog.popNumber(m, a))
			a.push(.Num(f64(random(0..n.max(1)))))
		0x32, 0x36:
			text = try prog.popText(m, a)
			chars = text.chars()
			a.push(.Num(f64(chars[0].charCode()) if not chars.isEmpty else 0.0))
		0x33, 0x37: a.push(.Str(charText(i64(try prog.popNumber(m, a)))))
		0x34: a.push(.Num(m.time.floor()))
		0x3A:
			name = try prog.popText(m, a)
			object = a.pop()
			done = false
			if object is Obj(id): done = m.deleteOwn(id, name)
			a.push(.Bool(done))
		0x3B:
			name = try prog.popText(m, a)
			a.push(.Bool(m.deleteVariable(a, name)))
		0x3C:
			v = a.pop()
			name = try prog.popText(m, a)
			prog.defineLocal(m, a, name, v)
		0x41:
			name = try prog.popText(m, a)
			if not m.hasLocal(a, name): prog.defineLocal(m, a, name, .Undefined)
		0x3D:
			try prog.callFunctionOp(m, a)
		0x3E: return Flow.Return(a.pop())
		0x40:
			try prog.newObjectOp(m, a)
		0x42:
			args = try prog.popArgs(m, a)
			a.push(.Obj(m.newArray(args)))
		0x43:
			try prog.initObject(m, a)
		0x44:
			v = a.pop()
			a.push(.Str(m.typeOf(v)))
		0x45:
			v = a.pop()
			a.push(prog.targetPathOf(m, v))
		0x46:
			name = try prog.popText(m, a)
			v = try prog.getVariable(m, a, name)
			m.enumerate(a, v)
		0x55:
			v = a.pop()
			m.enumerate(a, v)
		0x47:
			try prog.add2(m, a)
		0x48, 0x67:
			try prog.less2(m, a, code == 0x67)
		0x49:
			y = a.pop()
			x = a.pop()
			a.push(.Bool(try prog.looseEquals(m, x, y)))
		0x4A: a.push(.Num(try prog.popNumber(m, a)))
		0x4B: a.push(.Str(try prog.popText(m, a)))
		0x4C: a.push(a.top())
		0x4D:
			y = a.pop()
			x = a.pop()
			a.push(y)
			a.push(x)
		0x4E:
			name = a.pop()
			object = a.pop()
			key = try prog.toText(m, name)
			a.push(try prog.getMember(m, object, key))
		0x4F:
			v = a.pop()
			name = a.pop()
			object = a.pop()
			key = try prog.toText(m, name)
			try prog.setMember(m, object, key, v)
		0x50, 0x51: a.push(.Num(try prog.popNumber(m, a) + (1.0 if code == 0x50 else -1.0)))
		0x52:
			try prog.callMethodOp(m, a)
		0x53:
			try prog.newMethodOp(m, a)
		0x54:
			ctor = a.pop()
			v = a.pop()
			a.push(.Bool(prog.isInstance(m, v, ctor)))
		0x60, 0x61, 0x62, 0x63, 0x64, 0x65:
			try prog.bitwise(m, a, code)
		0x66:
			y = a.pop()
			x = a.pop()
			a.push(.Bool(x.strictEquals(y)))
		0x69:
			try prog.extendsOp(m, a)
		_: m.missing(actionName(code))
	Flow.Next

fn arithmetic(prog Program, mut m Machine, mut a Activation, code i64) () ? Thrown:
	y = try prog.popNumber(m, a)
	x = try prog.popNumber(m, a)
	a.push(.Num(match code:
		0x0A: x + y
		0x0B: x - y
		0x0C: x * y
		0x0D: x / y
		_: x.rem(y) if y != 0.0 else 0.0 / 0.0
	))

fn numericCompare(prog Program, mut m Machine, mut a Activation, code i64) () ? Thrown:
	y = try prog.popNumber(m, a)
	x = try prog.popNumber(m, a)
	a.push(.Bool(x == y if code == 0x0E else x < y))

fn stringCompare(prog Program, mut m Machine, mut a Activation, code i64) () ? Thrown:
	y = try prog.popText(m, a)
	x = try prog.popText(m, a)
	order = x.cmp(y)
	a.push(.Bool(order == 0 if code == 0x13 else order < 0 if code == 0x29 else order > 0))

# StringExtract: count characters from index (from 1)
fn stringExtract(prog Program, mut m Machine, mut a Activation) () ? Thrown:
	count = i64(try prog.popNumber(m, a))
	index = i64(try prog.popNumber(m, a))
	chars = (try prog.popText(m, a)).chars()
	start = (index - 1).clamp(0, chars.len)
	end = (start + count).clamp(start, chars.len) if count >= 0 else chars.len
	a.push(.Str(chars[start..end].join("")))

# a character's text from its code, empty for 0 and below
pub fn charText(code i64) str:
	"" if code <= 0 else str.fromCode(code)

fn bitwise(prog Program, mut m Machine, mut a Activation, code i64) () ? Thrown:
	y = toInt32(try prog.popNumber(m, a))
	x = toInt32(try prog.popNumber(m, a))
	v = match code:
		0x60: x & y
		0x61: x | y
		0x62: x ^ y
		0x63: x << (y & 31)
		0x64: x >> (y & 31)
		_: (x & 0xFFFF_FFFF) >> (y & 31)
	a.push(.Num(f64(toInt32(v) if code != 0x65 else v)))

fn add2(prog Program, mut m Machine, mut a Activation) () ? Thrown:
	y0 = a.pop()
	x0 = a.pop()
	y = try prog.toPrimitive(m, y0)
	x = try prog.toPrimitive(m, x0)
	if m.typeOf(x) == "string" or m.typeOf(y) == "string":
		a.push(.Str("{x.primitiveText()}{y.primitiveText()}"))
		return
	a.push(.Num(x.primitiveNumber() + y.primitiveNumber()))

# Less2 (Greater with the operands swapped): undefined when either is NaN
fn less2(prog Program, mut m Machine, mut a Activation, greater bool) () ? Thrown:
	second = a.pop()
	first = a.pop()
	x = try prog.toPrimitive(m, second if greater else first)
	y = try prog.toPrimitive(m, first if greater else second)
	if x is Str(s) and y is Str(t):
		a.push(.Bool(s.cmp(t) < 0))
		return
	p = x.primitiveNumber()
	q = y.primitiveNumber()
	if isNaN(p) or isNaN(q):
		a.push(.Undefined)
		return
	a.push(.Bool(p < q))

# ECMA-262's == (11.9.3), objects through their primitive value
pub fn looseEquals(prog Program, mut m Machine, x Value, y Value) bool ? Thrown:
	if x.isNullish() or y.isNullish(): return x.isNullish() and y.isNullish()
	if x is Obj and y is Obj: return x.strictEquals(y)
	if x is Obj:
		p = try prog.toPrimitive(m, x)
		return try prog.looseEquals(m, p, y)
	if y is Obj:
		p = try prog.toPrimitive(m, y)
		return try prog.looseEquals(m, x, p)
	if x is Str(s) and y is Str(t): return s == t
	if x is Bool(b) and y is Bool(c): return b == c
	x.primitiveNumber() == y.primitiveNumber()

fn stepTarget(prog Program, mut m Machine, a Activation, by i64):
	n = a.target
	if n not in m.stage.nodes: return
	prog.gotoFrame(m, n, m.stage.nodes[n].frame + by, false)

pub fn setPlaying(prog Program, mut m Machine, n Handle<swf.Node>, play bool):
	if n in m.stage.nodes: m.stage.nodes[n].playing = play

# InitObject: count pairs of value and name, the last pushed first
fn initObject(prog Program, mut m Machine, mut a Activation) () ? Thrown:
	n = toInt32(try prog.popNumber(m, a)).max(0)
	id = m.newObject(m.protos.object)
	loop n:
		v = a.pop()
		name = try prog.popText(m, a)
		m.setOwn(id, name, v)
	a.push(.Obj(id))

# Enumerate2: undefined, then the names of the object's enumerable properties
fn enumerate(mut m Machine, mut a Activation, v Value):
	a.push(.Undefined)
	id = v.objectId() ?? return
	names = []
	seen {str: bool} = {}
	chain Handle<Obj>? = id
	loop 64:
		o = chain ?? break
		for name in m.heap[o].order:
			if name in seen: continue
			seen[name.copy()] = true
			if (m.heap[o].props[name].flags & dontEnum) == 0: names.push(name.copy())
		if m.heap[o].kind is Array:
			for k in 0..m.heap[o].items.len:
				names.push("{k}")
		if m.heap[o].kind is Clip(n) and n in m.stage.nodes:
			for c in m.stage.nodes[n].children:
				if not m.stage.nodes[c].placed.name.isEmpty:
					names.push(m.stage.nodes[c].placed.name.copy())
		chain = m.heap[o].proto
	for name in names:
		a.push(.Str(name))

fn implementsOp(prog Program, mut m Machine, mut a Activation) () ? Thrown:
	ctor = a.pop()
	n = toInt32(try prog.popNumber(m, a)).max(0)
	interfaces = []
	loop n:
		if a.pop() is Obj(i): interfaces.push(i)
	id = ctor.objectId() ?? return
	proto = m.prototypeOf(id) ?? return
	m.heap[proto].interfaces = interfaces

# Extends: the subclass's prototype a new object over the superclass's, its __constructor__ the
# superclass
fn extendsOp(prog Program, mut m Machine, mut a Activation) () ? Thrown:
	superclass = a.pop()
	subclass = a.pop()
	sup = superclass.objectId() ?? return
	sub = subclass.objectId() ?? return
	proto = m.newObject(m.prototypeOf(sup) ?? m.protos.object)
	m.define(proto, "__constructor__", .Obj(sup), dontEnum)
	m.define(sub, "prototype", .Obj(proto), dontEnum)

# whether the value's prototype chain has the constructor's prototype or an interface it names
pub fn isInstance(prog Program, m Machine, v Value, ctor Value) bool:
	id = v.objectId() ?? return false
	c = ctor.objectId() ?? return false
	proto = m.prototypeOf(c) ?? return false
	chain = m.heap[id].proto
	loop 64:
		o = chain ?? return false
		if o == proto: return true
		for i in m.heap[o].interfaces:
			if i == c: return true
		chain = m.heap[o].proto
	false

pub fn typeOf(m Machine, v Value) str:
	match v:
		Undefined: "undefined"
		Null: "null"
		Bool: "boolean"
		Num: "number"
		Str: "string"
		Obj(id):
			match m.heap[id].kind:
				Function, Native: "function"
				Clip: "movieclip"
				_: "object"
