# ActionScript 2's values and the conversions of the primitive ones (ECMA-262 3rd edition as Flash
# Player 7 and later apply it, after Ruffle's core/src/avm1/value.rs): a number is a double, a
# string's truth is whether it is empty, undefined and null are NaN as numbers. An object is a
# handle into the machine's heap; what converting one does (valueOf, toString) is the machine's.

pub type Value:
	Undefined
	Null
	Bool(b bool)
	Num(x f64)
	Str(s str)
	Obj(id Handle<Obj>)

pub fn isNaN(x f64) bool:
	x != x

pub fn isPrimitive(v Value) bool:
	match v:
		Obj: false
		_: true

pub fn isNullish(v Value) bool:
	match v:
		Undefined, Null: true
		_: false

# a primitive's truth (an object is true)
pub fn isTrue(v Value) bool:
	match v:
		Undefined, Null: false
		Bool(b): b
		Num(x): x != 0.0 and not isNaN(x)
		Str(s): not s.isEmpty
		Obj: true

# a primitive as a number (an object is NaN here; the machine asks it for valueOf first)
pub fn primitiveNumber(v Value) f64:
	match v:
		Bool(b): 1.0 if b else 0.0
		Num(x): x
		Str(s): textNumber(s)
		_: 0.0 / 0.0

# A text as a number, as Flash reads one: spaces around it dropped, "0x" hexadecimal, a decimal
# with an optional sign, point and exponent; NaN for anything else and for the empty text.
pub fn textNumber(s str) f64:
	t = s.trimmed()
	if t.isEmpty: return 0.0 / 0.0
	if t.startsWith("0x") or t.startsWith("0X"):
		v = i64.parse("0x{t[2..]}") ?? return 0.0 / 0.0
		return v
	if t == "Infinity" or t == "+Infinity": return 1.0 / 0.0
	if t == "-Infinity": return -1.0 / 0.0
	f64.parse(t) ?? 0.0 / 0.0

# A number as ActionScript prints it: 15 significant digits (printf's %.15g), an integer without a
# point, an exponent from 1e15 up and below 1e-5.
pub fn numberText(x f64) str:
	if isNaN(x): return "NaN"
	if x == 1.0 / 0.0: return "Infinity"
	if x == -1.0 / 0.0: return "-Infinity"
	if x == 0.0: return "0"
	a = x.abs()
	sign = "-" if x < 0.0 else ""
	exponent = i64((a.ln() / 10.0.ln()).floor())
	if 10.0.pow(exponent) > a: exponent -= 1
	if 10.0.pow(exponent + 1) <= a: exponent += 1
	if exponent >= 15 or exponent < -5:
		mantissa = roundDigits(a / 10.0.pow(exponent), 14)
		if mantissa >= 10.0:
			mantissa /= 10.0
			exponent += 1
		e = "+{exponent}" if exponent > 0 else "{exponent}"
		return "{sign}{shortest(mantissa)}e{e}"
	"{sign}{shortest(roundDigits(a, 14 - exponent))}"

# x rounded to this many decimals (negative: to tens, hundreds...)
fn roundDigits(x f64, decimals i64):
	if decimals >= 0:
		scale = 10.0.pow(decimals)
		return (x * scale).round() / scale
	scale = 10.0.pow(-decimals)
	(x / scale).round() * scale

# the shortest digits of a number that is no integer, or of one
fn shortest(x f64):
	if x == x.floor() and x < 1e15: return "{i64(x)}"
	"{x}"

# a primitive as text (an object's text is the machine's: its toString)
pub fn primitiveText(v Value) str:
	match v:
		Undefined: "undefined"
		Null: "null"
		Bool(b): "true" if b else "false"
		Num(x): numberText(x)
		Str(s): s.copy()
		Obj: "[object Object]"

# ToInt32: the number wrapped to a signed 32-bit integer, NaN and the infinities 0
pub fn toInt32(x f64) i64:
	if isNaN(x) or x.abs() == 1.0 / 0.0: return 0
	t = x.trunc()
	m = t.rem(4294967296.0)
	n = i64(m)
	if n < 0: n += 4_294_967_296
	if n >= 2_147_483_648: n -= 4_294_967_296
	n

# an index of an array from a property name: none when the name is not a whole number
pub fn indexOfName(name str) i64?:
	if name.isEmpty or name.len > 10: return none
	for c in name.chars():
		if c < "0" or c > "9": return none
	i64.parse(name)

# whether two values are the same (StrictEquals; objects by handle)
pub fn strictEquals(a Value, b Value) bool:
	if a is Num(x) and b is Num(y): return x == y
	if a is Str(x) and b is Str(y): return x == y
	if a is Bool(x) and b is Bool(y): return x == y
	if a is Obj(x) and b is Obj(y): return x == y
	if a is Undefined and b is Undefined: return true
	if a is Null and b is Null: return true
	false

pub fn isObject(v Value) bool:
	match v:
		Obj: true
		_: false
