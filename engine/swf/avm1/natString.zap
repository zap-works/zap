# String's, Number's, Boolean's and Math's natives (Ruffle's core/src/avm1/globals/string.rs,
# number.rs, boolean.rs and math.rs). Strings are indexed by character, a primitive `this` read
# as it is and a boxed one by its value.

# the primitive a `this` stands for: itself, or a boxed object's value
fn primitiveOf(m Machine, me Value):
	if me is Obj(id):
		if m.heap[id].kind is Boxed(v): return v.copy()
	me.copy()

# long: String's, Number's and Boolean's methods, one arm each
fn stringNative(prog Program, mut m Machine, name str, me Value, args Value[]) Value ? Thrown:
	match name:
		"String": return Value.Str(try prog.textArg(m, args, 0) if not args.isEmpty else "")
		"Number": return Value.Num(try prog.numberArg(m, args, 0) if not args.isEmpty else 0.0)
		"Boolean": return Value.Bool(arg(args, 0).isTrue())
		"fromCharCode":
			out = ""
			for k in 0..args.len:
				out = "{out}{charText(try prog.intArg(m, args, k, 0))}"
			return Value.Str(out)
		"valueOf": return m.primitiveOf(me)
		_: pass
	self = m.primitiveOf(me)
	if self is Num(x):
		if name == "toString":
			radix = try prog.intArg(m, args, 0, 10)
			return Value.Str(numberText(x) if radix == 10 else radixText(x, radix))
	if self is Bool(b): return Value.Str("true" if b else "false")
	text = try prog.toText(m, self)
	chars = text.chars()
	n = chars.len
	match name:
		"toString": Value.Str(text)
		"charAt":
			k = try prog.intArg(m, args, 0, 0)
			Value.Str(chars[k].copy() if k >= 0 and k < n else "")
		"charCodeAt":
			k = try prog.intArg(m, args, 0, 0)
			Value.Num(f64(chars[k].charCode()) if k >= 0 and k < n else 0.0 / 0.0)
		"indexOf":
			part = try prog.textArg(m, args, 0)
			from = (try prog.intArg(m, args, 1, 0)).clamp(0, n)
			Value.Num(f64(charIndexOf(chars, part.chars(), from)))
		"lastIndexOf":
			part = (try prog.textArg(m, args, 0)).chars()
			last = -1
			k = 0
			while k <= n - part.len:
				if charsAt(chars, part, k): last = k
				k += 1
			Value.Num(f64(last))
		"substr":
			start = sliceIndex(try prog.intArg(m, args, 0, 0), n)
			count = (try prog.intArg(m, args, 1, n - start)).clamp(0, n - start)
			Value.Str(chars[start..start + count].join(""))
		"substring":
			a = (try prog.intArg(m, args, 0, 0)).clamp(0, n)
			b = (try prog.intArg(m, args, 1, n)).clamp(0, n)
			Value.Str(chars[a.min(b)..a.max(b)].join(""))
		"slice":
			a = sliceIndex(try prog.intArg(m, args, 0, 0), n)
			b = sliceIndex(try prog.intArg(m, args, 1, n), n)
			Value.Str(chars[a..b.max(a)].join(""))
		"split": Value.Obj(m.newArray(try prog.splitText(m, text, args)))
		"toUpperCase": Value.Str(text.upper())
		"toLowerCase": Value.Str(text.lower())
		"concat":
			out = text
			for k in 0..args.len:
				out = "{out}{try prog.textArg(m, args, k)}"
			Value.Str(out)
		_:
			m.missing("String.{name}")
			Value.Undefined

fn charsAt(chars str[], part str[], k i64):
	for j in 0..part.len:
		if chars[k + j] != part[j]: return false
	true

fn charIndexOf(chars str[], part str[], from i64):
	k = from
	while k <= chars.len - part.len:
		if charsAt(chars, part, k): return k
		k += 1
	-1

fn splitText(prog Program, mut m Machine, text str, args Value[]) Value[] ? Thrown:
	if args.isEmpty or args[0] == .Undefined: return [Value.Str(text.copy())]
	sep = try prog.textArg(m, args, 0)
	parts = text.chars().map(.copy()) if sep.isEmpty else text.split(sep).map(.copy())
	limit = try prog.intArg(m, args, 1, parts.len)
	parts[..limit.clamp(0, len)].map(Value.Str(.copy()))

# an integer in another radix (Number's toString(radix)), lower-case digits
fn radixText(x f64, radix i64):
	if radix < 2 or radix > 36 or isNaN(x): return numberText(x)
	n = i64(x.trunc())
	if n == 0: return "0"
	digits = "0123456789abcdefghijklmnopqrstuvwxyz"
	out = ""
	v = n.abs()
	while v > 0:
		out = "{digits[v % radix..v % radix + 1]}{out}"
		v /= radix
	"-{out}" if n < 0 else out

# long: Math's functions, one arm each
fn mathNative(prog Program, mut m Machine, name str, args Value[]) Value ? Thrown:
	x = try prog.numberArg(m, args, 0)
	Value.Num(match name:
		"abs": x.abs()
		"ceil": x.ceil()
		"floor": x.floor()
		"round": (x + 0.5).floor()
		"max": try prog.extreme(m, args, true)
		"min": try prog.extreme(m, args, false)
		"pow": x.pow(try prog.numberArg(m, args, 1))
		"sqrt": x.sqrt()
		"sin": x.sin()
		"cos": x.cos()
		"tan": x.tan()
		"atan": x.atan()
		"atan2": x.atan2(try prog.numberArg(m, args, 1))
		"asin": x.asin()
		"acos": x.acos()
		"exp": x.exp()
		"log": x.ln()
		_: random(0..1_000_000) / 1_000_000.0
	)

fn extreme(prog Program, mut m Machine, args Value[], most bool) f64 ? Thrown:
	if args.isEmpty: return -1.0 / 0.0 if most else 1.0 / 0.0
	best = try prog.numberArg(m, args, 0)
	for k in 1..args.len:
		x = try prog.numberArg(m, args, k)
		if isNaN(x) or isNaN(best): return 0.0 / 0.0
		best = x.max(best) if most else x.min(best)
	best
