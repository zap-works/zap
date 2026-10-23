# Native functions: a call goes to its group's dispatch by name; `new` of a native class makes its
# own kind of object (an array, a boxed primitive, a date) before the constructor runs on it.

pub fn callNative(prog Program, mut m Machine, k i64, me Value, args Value[]) Value ? Thrown:
	group = m.natives[k].group
	name = m.natives[k].name.copy()
	match group:
		0: try prog.globalNative(m, name, me, args)
		1: try prog.objectNative(m, name, me, args)
		2: try prog.arrayNative(m, name, me, args)
		3: try prog.stringNative(m, name, me, args)
		4: try prog.mathNative(m, name, args)
		5: try prog.clipNative(m, name, me, args)
		6: try prog.textNative(m, name, me, args)
		_: try prog.flashNative(m, name, me, args)

# `new` of a native class
fn constructNative(
	prog Program,
	mut m Machine,
	k i64,
	ctor Handle<Obj>,
	args Value[]
) Value ? Thrown:
	name = m.natives[k].name.copy()
	proto = m.prototypeOf(ctor) ?? m.protos.object
	match name:
		"Array": Value.Obj(m.newArray(arrayArgs(args)))
		"String":
			text = try prog.textArg(m, args, 0) if not args.isEmpty else ""
			Value.Obj(m.newOf(proto, .Boxed(.Str(text))))
		"Number":
			x = try prog.numberArg(m, args, 0) if not args.isEmpty else 0.0
			Value.Obj(m.newOf(proto, .Boxed(.Num(x))))
		"Boolean": Value.Obj(m.newOf(proto, .Boxed(.Bool(arg(args, 0).isTrue()))))
		"Date": Value.Obj(m.newOf(proto, .Boxed(.Num(m.time))))
		"Object":
			if not args.isEmpty and args[0] is Obj: return args[0].copy()
			Value.Obj(m.newObject(proto))
		_:
			id = m.newObject(proto)
			try prog.callNative(m, k, .Obj(id), args)
			Value.Obj(id)

# new Array(n) is n undefined elements; new Array(a, b) is [a, b]
fn arrayArgs(args Value[]):
	if args.len == 1:
		if args[0] is Num(x): return fill(i64(x).clamp(0, 1 << 20), Value.Undefined)
	args.map(.copy())

# long: the global functions, one arm each
fn globalNative(prog Program, mut m Machine, name str, me Value, args Value[]) Value ? Thrown:
	match name:
		"ASSetPropFlags": try prog.setPropFlags(m, args)
		"setInterval", "setTimeout": Value.Num(
			f64(try prog.addInterval(m, args, name == "setTimeout"))
		)
		"clearInterval", "clearTimeout":
			id = try prog.intArg(m, args, 0, -1)
			m.intervals = m.intervals.filter(.id != id)
			Value.Undefined
		"parseInt": Value.Num(
			parseIntText(try prog.textArg(m, args, 0), try prog.intArg(m, args, 1, 0))
		)
		"parseFloat": Value.Num(parseFloatText(try prog.textArg(m, args, 0)))
		"isNaN": Value.Bool(isNaN(try prog.numberArg(m, args, 0)))
		"isFinite":
			x = try prog.numberArg(m, args, 0)
			Value.Bool(not isNaN(x) and x.abs() != 1.0 / 0.0)
		"escape", "unescape": Value.Str(try prog.textArg(m, args, 0))
		"getTimer": Value.Num(m.time.floor())
		"trace":
			text = try prog.textArg(m, args, 0)
			m.log.push(text)
			Value.Undefined
		"getVersion": Value.Str("WIN 8,0,0,0")
		_:
			m.missing(name)
			Value.Undefined

# ASSetPropFlags(object, names, set, clear): names a comma list, an array or null for all
fn setPropFlags(prog Program, mut m Machine, args Value[]) Value ? Thrown:
	id = arg(args, 0).objectId() ?? return Value.Undefined
	names = []
	which = arg(args, 1)
	if which is Obj(list):
		for v in m.heap[list].items.copy():
			names.push(try prog.toText(m, v))
	elif which is Str(s):
		names = s.split(",").map(.copy())
	else:
		names = m.heap[id].order.copy()
	set = try prog.intArg(m, args, 2, 0)
	clear = try prog.intArg(m, args, 3, 0)
	for name in names:
		if m.heap[id].props.getMut(name) is p: p.flags = (p.flags & ~clear) | set
	Value.Undefined

# setInterval(function, ms, args...) or setInterval(object, "method", ms, args...)
fn addInterval(prog Program, mut m Machine, args Value[], once bool) i64 ? Thrown:
	if args.len < 2: return 0
	byMethod = m.typeOf(args[1]) == "string" and args.len >= 3
	every = try prog.numberArg(m, args, 2 if byMethod else 1)
	rest = args[(3 if byMethod else 2).min(len)..].map(.copy())
	id = m.nextInterval
	m.nextInterval += 1
	ms = every.max(1.0) if not isNaN(every) else 1.0
	m.intervals.push(Interval(id, me = args[0].copy() if byMethod else .Undefined,
		function = args[1].copy() if byMethod else args[0].copy(), every = ms,
		next = m.time + ms, args = rest, once))
	id

# parseInt's reading: an optional sign, "0x" hexadecimal, digits of the radix up to the first
# that is not one; NaN without any
fn parseIntText(text str, radix0 i64):
	t = text.trimmed()
	sign = 1.0
	at = 0
	if t.startsWith("-") or t.startsWith("+"):
		sign = -1.0 if t.startsWith("-") else 1.0
		at = 1
	radix = radix0
	if (radix == 0 or radix == 16) and t[at..].lower().startsWith("0x"):
		radix = 16
		at += 2
	if radix == 0: radix = 10
	if radix < 2 or radix > 36: return 0.0 / 0.0
	v = 0.0
	digits = 0
	for c in t[at..].lower().chars():
		d = "0123456789abcdefghijklmnopqrstuvwxyz".indexOf(c) ?? break
		if d >= radix: break
		v = v * radix + d
		digits += 1
	if digits == 0: return 0.0 / 0.0
	sign * v

# parseFloat's reading: the longest prefix that is a number
fn parseFloatText(text str):
	t = text.trimmed()
	best = 0.0 / 0.0
	for end in 1..=t.len:
		if f64.parse(t[..end]) is x: best = x
	best
