# Calls and construction (Ruffle's core/src/avm1/function.rs): a function of the movie's code runs
# in a new activation whose scope chain is a local scope over the one it was made in, its
# registers preloaded as DefineFunction2's flags say (this, arguments, super, _root, _parent,
# _global, in that order from register 1), its parameters in registers or local variables. `new`
# makes an object over the constructor's prototype and runs it with that object as `this`. A
# method knows the prototype it was found on, so `super` in it looks past that one.

import engine.swf

maxDepth = 200

# calls the function value with this `me`; `home` is the prototype the method was found on, none
# when it was not found on one
pub fn callValue(
	prog Program,
	mut m Machine,
	f Value,
	me Value,
	args Value[],
	home Handle<Obj>?
) Value ? Thrown:
	id = f.objectId() ?? return Value.Undefined
	match m.kindOf(id):
		Function(sf):
			if m.depth >= maxDepth: return Thrown(.Str("256 levels of recursion were exceeded"))
			m.depth += 1
			result = prog.callScript(m, id, sf, me, args, home)
			m.depth -= 1
			result
		Native(k): prog.callNative(m, k, me, args)
		Super(who, base):
			ctor = m.ownValue(base, "__constructor__")
			upper = m.heap[base].proto
			try prog.callValue(m, ctor, .Obj(who), args, upper)
		_: Value.Undefined

fn callScript(
	prog Program,
	mut m Machine,
	id Handle<Obj>,
	sf ScriptFn,
	me Value,
	args Value[],
	home Handle<Obj>?
) Value ? Thrown:
	def = prog.functionDef(sf) ?? return Value.Undefined
	activationObject = m.newObject(none)
	scope = m.newScope(sf.scope, local, activationObject)
	base = sf.base if sf.base in m.stage.nodes else m.stage.root
	a = Activation(block = sf.block, pool = sf.pool, registers = fill(def.registers.max(4) + 1,
		.Undefined), scope, me = me.copy(), target = base, base, callee = .Obj(id))
	a.superBase = home
	if home == none:
		if me.objectId() is o: a.superBase = m.heap[o].proto
	arguments = m.newArray(args.copy())
	a.arguments = arguments
	m.define(arguments, "callee", .Obj(id), dontEnum)
	prog.preload(m, a, def)
	for k, name in def.params:
		v = args[k].copy() if k < args.len else Value.Undefined
		r = def.paramRegisters[k] if k < def.paramRegisters.len else 0
		if r > 0 and r < a.registers.len: a.registers[r] = v
		else: m.setOwn(activationObject, name, v)
	saved = m.library
	m.library = prog.libraries[sf.block]
	flow = prog.execRange(m, a, def.body, def.end)
	m.library = saved
	match try flow:
		Return(v): v
		_: Value.Undefined

pub fn functionDef(prog Program, sf ScriptFn) ref FunctionDef?:
	if prog.blocks[sf.block].actions[sf.at] is Function(def): return def
	none

# DefineFunction2's preloaded registers
fn preload(prog Program, mut m Machine, mut a Activation, def FunctionDef):
	if not def.two: return
	r = 1
	for (bit, what) in [(1, 0), (4, 1), (16, 2), (64, 3), (128, 4), (256, 5)]:
		if (def.flags & bit) == 0: continue
		if r >= a.registers.len: break
		a.registers[r] = match what:
			0: a.me.copy()
			1: match a.arguments:
				args: .Obj(args)
				none: .Undefined
			2: m.superOf(a)
			3: .Obj(m.objectOfNode(prog, m.stage.root))
			4: prog.parentOf(m, a.base)
			_: .Obj(m.globals)
		r += 1

# `super` in an activation: its this, looked up past its method's prototype
pub fn superOf(mut m Machine, a Activation) Value:
	me = a.me.objectId() ?? return .Undefined
	base = a.superBase ?? return .Undefined
	.Obj(m.newOf(none, .Super(me, base)))

pub fn parentOf(prog Program, mut m Machine, n Handle<swf.Node>) Value:
	node = m.stage.nodes.get(n) ?? return .Undefined
	p = node.parent ?? return .Undefined
	.Obj(m.objectOfNode(prog, p))

# `new f(args)`: a native constructor makes its own kind of object; a script one gets a new
# object over its prototype, with __constructor__ naming it
pub fn construct(prog Program, mut m Machine, f Value, args Value[]) Value ? Thrown:
	id = f.objectId() ?? return Value.Undefined
	if m.heap[id].kind is Native(k): return try prog.constructNative(m, k, id, args)
	proto = m.prototypeOf(id) ?? m.protos.object
	object = m.newObject(proto)
	m.define(object, "__constructor__", .Obj(id), dontEnum)
	if prog.version < 7: m.define(object, "constructor", .Obj(id), dontEnum)
	try prog.callValue(m, f, .Obj(object), args, proto)
	Value.Obj(object)

# a method found by name: the function and the prototype it was found on (none the object's own)
pub type Found:
	function Value
	home Handle<Obj>? = none

pub fn methodOf(prog Program, mut m Machine, object Value, name str) Found ? Thrown:
	if object is Obj(id):
		if m.kindOf(id) is Super(who, base):
			start = m.heap[base].proto
			holder = m.holderOf(start, name) ?? return Found(function = .Undefined)
			return Found(function = try prog.readProp(m, holder, name, .Obj(who)), home = holder)
		if m.heap[id].props.get(name) == none:
			if m.holderOf(id, name) is holder:
				return Found(function = try prog.readProp(m, holder, name, object), home = holder)
	Found(function = try prog.getMember(m, object, name))

# CallMethod: a method of an object by name, or the object itself when the name is empty
fn callMethodOp(prog Program, mut m Machine, mut a Activation) () ? Thrown:
	nameValue = a.pop()
	object = a.pop()
	args = try prog.popArgs(m, a)
	name = "" if nameValue.isNullish() else try prog.toText(m, nameValue)
	if name.isEmpty:
		me = m.superThis(object) ?? a.me.copy()
		a.push(try prog.callValue(m, object, me, args, none))
		return
	found = try prog.methodOf(m, object, name)
	if found.function is Undefined:
		m.fault("{name} is not a function of {prog.describeTarget(m, object)}")
		a.push(.Undefined)
		return
	me = m.superThis(object) ?? object.copy()
	a.push(try prog.callValue(m, found.function, me, args, found.home))

# a value as an error names it: a clip by its path and symbol, else its type
fn describeTarget(prog Program, m Machine, v Value):
	n = m.nodeOf(v) ?? return m.typeOf(v)
	character = m.stage.nodes[n].placed.character
	symbol = prog.scene.movie.linkages.get(character) ?? "{character}"
	"{m.stage.pathOf(n)} ({symbol})"

# the this of a super object, none for any other value
fn superThis(m Machine, v Value) Value?:
	id = try v.objectId()
	if m.heap[id].kind is Super(who, _): return .Obj(who)
	none

# CallFunction: a function by name from the scope chain, `this` the object it was found on (the
# target clip for a local variable)
fn callFunctionOp(prog Program, mut m Machine, mut a Activation) () ? Thrown:
	name = try prog.popText(m, a)
	args = try prog.popArgs(m, a)
	f, me = try prog.resolveCallable(m, a, name)
	if f is Undefined:
		m.fault("{name} is not a function")
		a.push(.Undefined)
		return
	a.push(try prog.callValue(m, f, me, args, none))

fn newObjectOp(prog Program, mut m Machine, mut a Activation) () ? Thrown:
	name = try prog.popText(m, a)
	args = try prog.popArgs(m, a)
	f = try prog.getVariable(m, a, name)
	if f is Undefined:
		m.fault("new {name}: no such class")
		a.push(.Undefined)
		return
	a.push(try prog.construct(m, f, args))

fn newMethodOp(prog Program, mut m Machine, mut a Activation) () ? Thrown:
	nameValue = a.pop()
	object = a.pop()
	args = try prog.popArgs(m, a)
	name = "" if nameValue.isNullish() else try prog.toText(m, nameValue)
	f = object.copy() if name.isEmpty else try prog.getMember(m, object, name)
	a.push(try prog.construct(m, f, args))
