# Object's and Function's natives (Ruffle's core/src/avm1/globals/object.rs and function.rs):
# Object.registerClass binds an exported symbol to a class, so its instances are made over that
# class's prototype and constructed by it; addProperty makes a property of a getter and a setter;
# call and apply run a function with a `this` given.

# long: Object's and Function's methods, one arm each
fn objectNative(prog Program, mut m Machine, name str, me Value, args Value[]) Value ? Thrown:
	match name:
		"Object":
			if not args.isEmpty and not args[0].isNullish():
				return Value.Obj(prog.toObject(m, args[0]) ?? m.newObject(m.protos.object))
			Value.Obj(m.newObject(m.protos.object))
		"registerClass":
			symbol = try prog.textArg(m, args, 0)
			key = "{m.library}|{symbol}"
			if arg(args, 1) is Obj(ctor): m.classes[key] = ctor
			else: m.classes.remove(key)
			Value.Bool(true)
		"hasOwnProperty":
			id = me.objectId() ?? return Value.Bool(false)
			key = try prog.textArg(m, args, 0)
			if m.heap[id].props.get(key) != none: return Value.Bool(true)
			Value.Bool(m.isArray(id) and (indexOfName(key) ?? m.heap[id].items.len) <
					m.heap[id].items.len)
		"addProperty": Value.Bool(try prog.addProperty(m, me, args))
		"toString", "toLocaleString":
			if me is Obj(id):
				if m.typeOf(me) == "function": return Value.Str("[type Function]")
			Value.Str("[object Object]")
		"valueOf": me.copy()
		"isPrototypeOf":
			id = me.objectId() ?? return Value.Bool(false)
			other = arg(args, 0).objectId() ?? return Value.Bool(false)
			chain = m.heap[other].proto
			loop 64:
				o = chain ?? break
				if o == id: return Value.Bool(true)
				chain = m.heap[o].proto
			Value.Bool(false)
		"isPropertyEnumerable":
			id = me.objectId() ?? return Value.Bool(false)
			key = try prog.textArg(m, args, 0)
			p = m.heap[id].props.get(key) ?? return Value.Bool(false)
			Value.Bool((p.flags & dontEnum) == 0)
		"watch", "unwatch": Value.Bool(false)
		"call":
			rest = args[1.min(len)..].map(.copy())
			try prog.callValue(m, me, prog.thisFor(m, arg(args, 0)), rest, none)
		"apply":
			rest = []
			if arg(args, 1) is Obj(list): rest = m.heap[list].items.copy()
			try prog.callValue(m, me, prog.thisFor(m, arg(args, 0)), rest, none)
		"Function": Value.Undefined
		_:
			m.missing("Object.{name}")
			Value.Undefined

# call's and apply's `this`: undefined or null is the root
fn thisFor(prog Program, mut m Machine, v Value):
	if v.isNullish(): return Value.Obj(m.objectOfNode(prog, m.stage.root))
	v.copy()

# addProperty(name, getter, setter): false when the name is empty or the getter no function
fn addProperty(prog Program, mut m Machine, me Value, args Value[]) bool ? Thrown:
	id = me.objectId() ?? return false
	name = try prog.textArg(m, args, 0)
	getter = arg(args, 1).objectId() ?? return false
	if name.isEmpty: return false
	setter = arg(args, 2).objectId()
	m.setOwn(id, name, .Undefined)
	if m.heap[id].props.getMut(name) is p:
		p.getter = getter
		p.setter = setter
	true
