# Conversions that may run the movie's code (ECMA-262 9.1 to 9.9 as Flash applies them): an
# object's primitive value is what its valueOf gives, else its toString's; a clip's text is its
# path; an object as text is its toString's.

# an object's primitive value (valueOf, then toString); a primitive as it is
import engine.swf

pub fn toPrimitive(prog Program, mut m Machine, v Value) Value ? Thrown:
	id = v.objectId() ?? return v.copy()
	if m.heap[id].kind is Clip(n): return Value.Str(m.stage.pathOf(n))
	found = try prog.methodOf(m, v, "valueOf")
	if found.function is Obj:
		p = try prog.callValue(m, found.function, v, [], found.home)
		if p.isPrimitive(): return p
	Value.Str(try prog.objectText(m, v))

pub fn toNumber(prog Program, mut m Machine, v Value) f64 ? Thrown:
	if v is Obj:
		p = try prog.toPrimitive(m, v)
		return p.primitiveNumber()
	v.primitiveNumber()

pub fn toText(prog Program, mut m Machine, v Value) str ? Thrown:
	if v is Obj: return try prog.objectText(m, v)
	v.primitiveText()

# an object's text: its toString's, a clip's path
fn objectText(prog Program, mut m Machine, v Value) str ? Thrown:
	id = v.objectId() ?? return v.primitiveText()
	if m.heap[id].kind is Clip(n): return m.stage.pathOf(n)
	if m.heap[id].kind is Text(n): return m.stage.pathOf(n)
	found = try prog.methodOf(m, v, "toString")
	if found.function is Obj:
		t = try prog.callValue(m, found.function, v, [], found.home)
		if t is Obj: return "[object Object]"
		return t.primitiveText()
	"[object Object]"

# the object a value is (a primitive boxed), none for undefined and null
pub fn toObject(prog Program, mut m Machine, v Value) Handle<Obj>?:
	match v:
		Obj(id): id
		Str: m.newOf(m.protos.string, .Boxed(v.copy()))
		Num: m.newOf(m.protos.number, .Boxed(v.copy()))
		Bool: m.newOf(m.protos.boolean, .Boxed(v.copy()))
		_: none

# the integer an argument gives, `otherwise` when it is missing
pub fn intArg(prog Program, mut m Machine, args Value[], k i64, otherwise i64) i64 ? Thrown:
	if k >= args.len or args[k] == .Undefined: return otherwise
	x = try prog.toNumber(m, args[k])
	if isNaN(x): return 0
	i64(x.trunc().clamp(-9e15, 9e15))

pub fn numberArg(prog Program, mut m Machine, args Value[], k i64) f64 ? Thrown:
	if k >= args.len: return 0.0 / 0.0
	try prog.toNumber(m, args[k])

pub fn textArg(prog Program, mut m Machine, args Value[], k i64) str ? Thrown:
	if k >= args.len: return "undefined"
	try prog.toText(m, args[k])

pub fn arg(args Value[], k i64) Value:
	args[k].copy() if k < args.len else .Undefined
