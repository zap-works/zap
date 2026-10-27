# The JS target's expressions (jsModule.zap): each the text of a JS expression, the statements it
# needs first (a match, an if or a `??` that leaves, written as statements) put before the line
# that reads it.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

fn jsValue(mut g Gen, mut js Js, e NodeId) str:
	k = nodes[e].kind
	if k == nInt: return g.jsIntLiteral(js, e)
	if k == nFloat: return g.jsFloatLiteral(e)
	if k == nStr: return jsQuote(nodes[e].text)
	if k == nBool: return "true" if nodes[e].ival == 1 else "false"
	if k == nNone: return "null"
	if k == nInterp: return g.jsInterp(js, e)
	if k == nIdent: return g.jsName(js, e)
	if k == nField: return g.jsFieldValue(js, e)
	if k == nIndex: return g.jsIndex(js, e)
	if k == nCall: return g.jsCall(js, e)
	if k == nUnary: return g.jsUnary(js, e)
	if k == nBinary: return g.jsBinary(js, e)
	if k == nDeref: return g.jsValue(js, nodes[e].kids(kidIds)[0])
	if k == nStructLit: return g.jsStructLit(js, e)
	if k == nArray: return g.jsArrayLiteral(js, e)
	if k == nMapLit: return g.jsMapLit(js, e)
	if k == nSome: return g.jsSome(js, e)
	if k == nLambda: return g.jsLambda(js, e)
	if k == nRange: return g.jsRangeList(js, e)
	if k == nTry: return g.jsTry(js, e)
	if k in [nMatch, nIf, nBlock]:
		to = js.jsTemp()
		js.jsLine("let {to};")
		if k == nMatch:
			g.jsMatch(js, e, to.copy())
		elif k == nIf:
			g.jsIf(js, e, to.copy())
		else:
			js.jsOpen("")
			g.jsArmBody(js, e, to.copy())
			js.jsClose()
		return to
	if k in [nReturn, nBreak, nContinue]:
		g.jsStmt(js, e)
		return "undefined"
	js.jsRefuse(g, e, "an expression of kind {k}")
	"undefined"

# the value as a condition
fn jsCond(mut g Gen, mut js Js, e NodeId) str:
	g.jsValue(js, e)

# a str literal as JS writes it
fn jsQuote(s str) str:
	out = ['"']
	for b in s.bytes():
		if b == '"' or b == '\\':
			out.push('\\')
			out.push(b)
		elif b == 10:
			out.extend("\\n".bytes())
		elif b == 13:
			out.extend("\\r".bytes())
		elif b == 9:
			out.extend("\\t".bytes())
		elif b < 32:
			out.extend("\\u00".bytes())
			out.push(jsHexDigit(b >> 4))
			out.push(jsHexDigit(b & 15))
		else:
			out.push(b)
	out.push('"')
	str(move out)

fn jsHexDigit(d u8):
	'0' + d if d < 10 else 'a' + d - 10

# a float literal: an f32's rounded to single
fn jsFloatLiteral(g Gen, e NodeId):
	text = nodes[e].text.replace("_", "")
	t = g.ty(e)
	"Math.fround({text})" if g.tyK(t) == tFloat and tys[t].bits == 32 else text

fn jsIntLiteral(mut g Gen, mut js Js, e NodeId):
	if g.tyK(g.ty(e)) == tFloat: return g.jsFloatLiteral(e)
	v = g.intLitValue(e)
	if v > 9_007_199_254_740_991 or v < -9_007_199_254_740_991 or
		(g.tyK(g.ty(e)) == tInt and not tys[g.ty(e)].isSigned and v < 0):
		js.jsRefuse(g, e, "the number {nodes[e].text}, past 2^53")
	"{v}"

# "a{x}b": the parts joined, each value as its text
fn jsInterp(mut g Gen, mut js Js, e NodeId):
	parts = []
	for kid in nodes[e].kids(kidIds).copy():
		if nodes[kid].kind == nStr:
			if nodes[kid].text != "": parts.push(jsQuote(nodes[kid].text))
		else:
			parts.push(g.jsToStr(js, kid))
	if parts.isEmpty: return "\"\""
	if parts.len == 1 and nodes[nodes[e].kids(kidIds)[0]].kind != nStr: return parts[0].copy()
	if nodes[nodes[e].kids(kidIds)[0]].kind != nStr or nodes[nodes[e].kids(kidIds)[0]].text == "":
		parts.insert(0, "\"\"")
	"({parts.join(" + ")})"

# the text of a value, as print and an interpolation write it
fn jsToStr(mut g Gen, mut js Js, e NodeId) str:
	t = g.jsDerefType(g.ty(e))
	v = g.jsValue(js, e)
	g.jsStrOf(js, v, t, e)

fn jsStrOf(mut g Gen, mut js Js, v str, t TypeId, at NodeId):
	k = g.tyK(t)
	if k == tStr: return v.copy()
	if k == tInt or k == tBool: return "String({v})"
	if k == tFloat: return "rt__fmtFloat({v}, {tys[t].bits})"
	fnd = g.derivedFn("str", t) ?? return js.jsRefused(g, at, "the text of {typeStr(tys, t)}")
	js.jsWant(nodes[fnd].text.copy(), fnd)
	"{nodes[fnd].text}({v})"

fn jsRefused(mut js Js, g Gen, e NodeId, what str):
	js.jsRefuse(g, e, what)
	"undefined"

# the type a reference or a box reaches
fn jsDerefType(g Gen, t TypeId):
	u = t
	while g.tyK(u) == tRef or g.tyK(u) == tBox:
		u = innerOf(tys, u)
	u

# whether an enum carries no values: its values are the numbers of its variants
fn jsPlainEnum(g Gen, t TypeId):
	g.tyK(t) == tEnum and nodes[declOf(tys, t)].kids(kidIds).all(nodes[it].kids(kidIds).isEmpty)

# a name: a local, a field of the method's receiver, a function, or a module variable
fn jsName(mut g Gen, mut js Js, e NodeId) str:
	name = nodes[e].text
	if js.jsLookup(name) is v: return v
	if substTypeFor(name, g.c.subst) is n and g.tyK(n) == tNum: return "{tys[n].bits}"   # a number parameter
	if js.b.selfType is st and g.tyK(st) == tStruct and
		g.c.fieldIndexOf(declOf(tys, st), name) >= 0:
		return "self.{name}"
	if g.c.findDeclByGlobalName(nConstDecl, name) is d:
		js.jsWantGlobal(g, d)
		return jsSafe(name)
	if g.c.findFunc(name) is fnd:
		js.jsWant(jsSafe(name), fnd)
		return jsSafe(name)
	js.jsRefused(g, e, "the name {name}")

# obj.f: a field, a variant of an enum (Enum.Variant, .Variant), a safe field (obj?.f)
fn jsFieldValue(mut g Gen, mut js Js, e NodeId):
	t = g.ty(e)
	if g.irVariantOf(e, t) >= 0: return g.jsVariant(js, e, t, [])
	if nodes[e].kids(kidIds).isEmpty: return js.jsRefused(g, e, "the field {nodes[e].text}")
	obj = nodes[e].kids(kidIds)[0]
	o = g.jsValue(js, obj)
	if nodes[e].hasFlag(flagSafe): return "({o}?.{nodes[e].text} ?? null)"
	"{o}.{nodes[e].text}"

# a variant's value: a plain enum's number, a carrying one's object of its tag and payload
fn jsVariant(mut g Gen, mut js Js, field NodeId, t TypeId, args NodeId[]):
	ed = declOf(tys, t)
	vi = nodes[ed].kids(kidIds).findIndex(nodes[it].text == nodes[field].text) ?? -1
	if g.jsPlainEnum(t): return "{vi}"
	v = nodes[ed].kids(kidIds)[vi]
	parts = ["$tag: {jsQuote(nodes[v].text)}"]
	for i, p in nodes[v].kids(kidIds).copy():
		if i < args.len:
			parts.push("{jsPayloadName(nodes[p].text, i)}: {g.jsStored(js, args[i])}")
	"\{{parts.join(", ")}\}"

# the property of a variant's i-th value: its name, or its place when it has none
fn jsPayloadName(name str, i i64):
	name.copy() if name != "" else "_{i}"

# xs[i], s[i], m[k]: checked as Zap checks them
fn jsIndex(mut g Gen, mut js Js, e NodeId):
	obj = nodes[e].kids(kidIds)[0]
	t = g.jsDerefType(g.ty(obj))
	o = g.jsValue(js, obj)
	i = g.jsValue(js, nodes[e].kids(kidIds)[1])
	k = g.tyK(t)
	if k == tStr: return "rt__strByte({o}, {i})"
	if k == tMap: return "rt__mapIndex({o}, {i})"
	if k == tStruct: return "{o}[{g.jsFieldNames(t)}[rt__at({g.jsFieldNames(t)}, {i})]]"
	"rt__index({o}, {i})"

# the names of a struct's fields, as a JS list (`v[i]` of a struct of one number type)
fn jsFieldNames(g Gen, t TypeId):
	names = nodes[declOf(tys, t)].kids(kidIds).map(jsQuote(nodes[it].text))
	"[{names.join(", ")}]"

# [a, b]; a fixed array's `[v]` of N elements is v N times
fn jsArrayLiteral(mut g Gen, mut js Js, e NodeId):
	items = nodes[e].kids(kidIds).copy().map(g.jsStored(js, it))
	t = g.ty(e)
	if g.tyK(t) == tArray and items.len == 1 and tys[t].bits > 1:
		return "rt__fill({tys[t].bits}, {items[0]})"
	if g.tyK(t) == tArray and items.isEmpty: return g.jsZero(js, t, e)   # `a f32[R, C]`: zeros
	"[{items.join(", ")}]"

# a struct's value: an object of its fields, as written
fn jsStructLit(mut g Gen, mut js Js, e NodeId):
	names = nodes[e].names(kidIds).copy()
	kids = nodes[e].kids(kidIds).copy()
	if names.len != kids.len: return js.jsRefused(g, e, "a struct's value without its field names")
	if g.tyK(g.ty(e)) == tStruct and nodes[declOf(tys, g.ty(e))].hasFlag(flagDrop):
		return js.jsRefused(g, e, "a value of {typeStr(tys, g.ty(e))}, a type with a drop function")
	parts = []
	for i, kid in kids:
		parts.push("{names[i]}: {g.jsStored(js, kid)}")
	"\{{parts.join(", ")}\}"

fn jsMapLit(mut g Gen, mut js Js, e NodeId):
	kids = nodes[e].kids(kidIds).copy()
	values = nodes[e].sub(kidIds).copy()
	made = g.jsNewMap(g.jsDerefType(g.ty(e)))
	if kids.isEmpty: return "{made}()"
	parts = []
	for i, kid in kids:
		parts.push("[{g.jsValue(js, kid)}, {g.jsStored(js, values[i])}]")
	"{made}([{parts.join(", ")}])"

# how a map of type t is made: a JS Map, or the prelude's rt$KeyMap when its keys are values JS
# would compare by identity (structs, lists)
fn jsNewMap(g Gen, t TypeId):
	key = g.jsDerefType(innerOf(tys, t))
	"new Map" if g.jsComparesBare(key) else "new rt$KeyMap"

# some(x) is x (an optional of an optional's `{$some: x}`, so some(none) is not none); a result's
# ok value is the value, its error an rt__Err
fn jsSome(mut g Gen, mut js Js, e NodeId):
	v = g.jsStored(js, nodes[e].kids(kidIds)[0])
	if g.tyK(g.ty(e)) == tResult and nodes[e].ival == 2: return "new rt__Err({v})"
	if g.jsNestedOption(g.ty(e)): return "\{$some: {v}\}"
	v

# whether t is an optional whose value is itself an optional (some(none) told from none)
fn jsNestedOption(g Gen, t TypeId):
	if g.tyK(t) != tOption: return false
	inner = tys[t].inner ?? return false
	g.tyK(g.jsDerefType(inner)) == tOption

# the value an optional v of type t holds, read once it is known not none
fn jsUnwrapped(g Gen, v str, t TypeId):
	"{v}.$some" if g.jsNestedOption(t) else v.copy()

# a lambda: an arrow function, its parameters new names in a scope of their own
fn jsLambda(mut g Gen, mut js Js, e NodeId):
	saved = js.b.lines.len
	depth = js.b.depth
	js.b.scopes.push(JsScope())
	params = nodes[e].names(kidIds).map(js.jsDeclare(g, it))
	if not nodes[e].kids(kidIds).isEmpty and nodes[e].sub(kidIds).isEmpty:
		mark = js.b.lines.len
		body = g.jsValue(js, nodes[e].kids(kidIds)[0])
		if js.b.lines.len == mark:
			js.b.scopes.truncate(js.b.scopes.len - 1)
			wrapped = "({body})" if body.startsWith("\{") else body   # an object, not a block
			return "(({params.join(", ")}) => {wrapped})"
		pre = js.b.lines[mark..].copy()
		js.b.lines.truncate(mark)
		js.b.scopes.truncate(js.b.scopes.len - 1)
		inner = pre.map("\t{it}").join("\n")
		return "(({params.join(", ")}) => \{\n{inner}\n{"\t".repeat(depth + 1)}return {body};\n{"\t".repeat(depth)}\})"
	js.b.depth += 1
	ret = g.jsLambdaResult(e)
	outerRet = js.b.ret
	js.b.ret = ret
	g.jsBodyOf(js, nodes[e].sub(kidIds)[0], ret)
	js.b.ret = outerRet
	inner = js.b.lines[saved..].join("\n")
	js.b.lines.truncate(saved)
	js.b.depth = depth
	js.b.scopes.truncate(js.b.scopes.len - 1)
	"(({params.join(", ")}) => \{\n{inner}\n{"\t".repeat(depth)}\})"

# the result type of a lambda, unit when it gives none
fn jsLambdaResult(g Gen, e NodeId):
	t = g.ty(e)
	if g.tyK(t) == tFn and tys[t].ret is r: return r
	tyUnit

# lo..hi as a value: the list of its numbers
fn jsRangeList(mut g Gen, mut js Js, e NodeId):
	parts = nodes[e].kids(kidIds).map(g.jsValue(js, it))
	"rt__range({parts.join(", ")})"

# try x: the value, or its none or error returned
fn jsTry(mut g Gen, mut js Js, e NodeId):
	inner = nodes[e].kids(kidIds)[0]
	v = js.jsTemp()
	js.jsLine("const {v} = {g.jsValue(js, inner)};")
	if g.tyK(g.ty(inner)) == tResult:
		js.jsLine("if ({v} instanceof rt__Err) return {v};")
	else:
		js.jsLine("if ({v} === null) return null;")
	v
