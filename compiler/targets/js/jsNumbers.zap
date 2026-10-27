# The JS target's numbers (jsModule.zap): every number a JS number. An f64 is one, an f32 one
# rounded (Math.fround) after each operation; an integer of 32 bits or fewer is exact, its
# operations wrapping (unsigned) or stopping past its range (signed) as Zap's do; one of 64 bits
# is exact up to 2^53, and an operation past that stops the program (the prelude's rt__i64 and
# rt__u64), never a silent difference from a native run.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

fn jsBinary(mut g Gen, mut js Js, e NodeId) str:
	op = nodes[e].ival
	l = nodes[e].kids(kidIds)[0]
	r = nodes[e].kids(kidIds)[1]
	if op == binAnd or op == binOr: return g.jsLogic(js, op, l, r)
	if op == binCoalesce: return g.jsCoalesce(js, e, l, r)
	lt = g.jsDerefType(g.ty(l))
	t = g.jsDerefType(g.ty(e))
	if op == binIn: return g.jsIn(js, l, r)
	a = g.jsValue(js, l)
	b = g.jsValue(js, r)
	if op == binEq or op == binNe: return jsEquality(g.jsComparesBare(lt), op == binNe, a, b)
	if op >= binLt and op <= binGe:
		sign = ["<", ">", "<=", ">="][op - binLt]
		if g.tyK(lt) in [tInt, tFloat, tStr, tBool] or g.jsPlainEnum(lt): return "({a} {sign} {b})"
		return "(rt__cmp({a}, {b}) {sign} 0)"
	k = g.tyK(t)
	if k == tStr and op == binAdd: return "({a} + {b})"
	if k == tFloat: return g.jsFloatOp(js, e, op, a, b, t)
	if k == tInt: return g.jsIntOp(js, e, op, a, b, t)
	if k == tStruct and op in [binAdd, binSub, binMul, binDiv]:
		fnd = g.derivedFn(g.arithFamily(e), t) ??
			return js.jsRefused(g, e, "this struct arithmetic")
		js.jsWant(nodes[fnd].text.copy(), fnd)
		return "{nodes[fnd].text}({a}, {b})"
	js.jsRefused(g, e, "the operator {op} on {typeStr(tys, t)}")

# a == b and a != b: JS's own for numbers, bools, strs and their optionals, else the prelude's
# comparison of the values
fn jsEquality(bare bool, negated bool, a str, b str):
	if bare: return "({a} {"!==" if negated else "==="} {b})"
	"{"!" if negated else ""}rt__eq({a}, {b})"

# whether JS's === compares values of type t as Zap's == does
fn jsComparesBare(g Gen, t TypeId) bool:
	k = g.tyK(t)
	if k in [tInt, tFloat, tBool, tStr, tUnit] or g.jsPlainEnum(t): return true
	if k != tOption: return false
	inner = tys[t].inner ?? return false
	g.jsComparesBare(g.jsDerefType(inner))

# a and b, a or b: b's lines (a match it needs) run only when a does not decide
fn jsLogic(mut g Gen, mut js Js, op i64, l NodeId, r NodeId):
	a = g.jsCond(js, l)
	mark = js.b.lines.len
	b = g.jsCond(js, r)
	jsOp = "&&" if op == binAnd else "||"
	if js.b.lines.len == mark: return "({a} {jsOp} {b})"
	pre = js.b.lines[mark..].copy()
	js.b.lines.truncate(mark)
	v = js.jsTemp()
	js.jsLine("let {v} = {a};")
	js.jsOpen("if ({"" if op == binAnd else "!"}{v})")
	for line in pre:
		js.b.lines.push("\t{line}")
	js.jsLine("{v} = {b};")
	js.jsClose()
	v

# a ?? b: a's value, or b when a is none (an error); b may leave (`?? return none`)
fn jsCoalesce(mut g Gen, mut js Js, e NodeId, l NodeId, r NodeId):
	a = g.jsValue(js, l)
	result = g.tyK(g.ty(l)) == tResult
	mark = js.b.lines.len
	leaves = nodes[r].kind in [nReturn, nBreak, nContinue] or
		nodes[r].kind == nCall and g.jsEndsProgram(r)
	b = "" if leaves else g.jsStored(js, r)
	nested = g.jsNestedOption(g.ty(l))
	if not leaves and js.b.lines.len == mark and not result and not nested: return "({a} ?? {b})"
	pre = js.b.lines[mark..].copy()
	js.b.lines.truncate(mark)
	v = js.jsTemp()
	js.jsLine("let {v} = {a};")
	missing = "{v} instanceof rt__Err" if result else "{v} === null"
	js.jsOpen("if ({missing})")
	if leaves:
		g.jsExprStmt(js, r)
	else:
		for line in pre:
			js.b.lines.push("\t{line}")
		js.jsLine("{v} = {b};")
	if nested:
		js.jsReopen(r"} else {")
		js.jsLine("{v} = {v}.$some;")
	js.jsClose()
	v

# whether the call never returns (exit)
fn jsEndsProgram(g Gen, e NodeId):
	callee = nodes[e].kids(kidIds)[0]
	nodes[callee].kind == nIdent and nodes[callee].text in ["exit", "rt__exit", "fail"]

# x in xs: a list's element, a map's key, a part of a str, a number of a range
fn jsIn(mut g Gen, mut js Js, l NodeId, r NodeId):
	a = g.jsValue(js, l)
	if nodes[r].kind == nRange:
		parts = nodes[r].kids(kidIds).copy()
		lo = g.jsValue(js, parts[0])
		hi = g.jsValue(js, parts[1])
		return "({a} >= {lo} && {a} < {hi})"
	t = g.jsDerefType(g.ty(r))
	b = g.jsValue(js, r)
	k = g.tyK(t)
	if k == tMap: return "{b}.has({a})"
	if k == tStr: return "{b}.includes({a})"
	"rt__listContains({b}, {a})"

fn jsFloatOp(mut g Gen, mut js Js, e NodeId, op i64, a str, b str, t TypeId):
	if op > binPow: return js.jsRefused(g, e, "the operator {op} on floats")
	v = "({a} {["+", "-", "*", "/", "%", "**"][op]} {b})"
	"Math.fround{v}" if tys[t].bits == 32 else v

# integer arithmetic of type t: wrapping when unsigned and 32 bits or fewer, else checked
fn jsIntOp(mut g Gen, mut js Js, e NodeId, op i64, a str, b str, t TypeId) str:
	bits = tys[t].bits
	signed = tys[t].isSigned
	wraps = nodes[e].hasFlag(flagWrap)
	if op == binDiv: return g.jsIntResult("rt__div({a}, {b})", bits, signed, wraps)
	if op == binMod: return "rt__mod({a}, {b})"
	if op == binPow: return g.jsIntResult("({a} ** {b})", bits, signed, wraps)
	if op == binMul and not signed and bits <= 32: return "rt__mulU({a}, {b}, {bits})"
	if op <= binMul: return g.jsIntResult("({a} {["+", "-", "*"][op]} {b})", bits, signed, wraps)
	names = ["rt__band", "rt__bor", "rt__bxor", "rt__shl", "rt__shr"]
	if op >= binBand and op <= binShr: return "{names[op - binBand]}({a}, {b}, {bits}, {signed})"
	js.jsRefused(g, e, "the operator {op} on integers")

# the value of an integer operation made a value of its type: wrapped (unsigned, or asked),
# else stopped when it leaves the type (64 bits: past 2^53)
fn jsIntResult(g Gen, v str, bits i64, signed bool, wraps bool):
	if bits == 64: return "rt__{"i64" if signed else "u64"}({v})"
	if wraps or not signed: return "rt__wrapInt({v}, {bits}, {signed})"
	"rt__fitInt({v}, {bits})"

fn jsUnary(mut g Gen, mut js Js, e NodeId) str:
	op = nodes[e].ival
	kid = nodes[e].kids(kidIds)[0]
	if op == unMove and g.jsIsPlace(kid):
		return g.jsTake(js, kid, g.jsDerefType(g.ty(kid)))   # the place is left empty, usable again
	if op in [unMove, unRef, unMutRef]: return g.jsValue(js, kid)
	a = g.jsValue(js, kid)
	if op == unNot: return "!{a}"
	t = g.jsDerefType(g.ty(e))
	if op == unNeg:
		if g.tyK(t) == tFloat: return "(-{a})"
		return g.jsIntResult("(-{a})", tys[t].bits, tys[t].isSigned, false)
	if op == unBnot: return "rt__bnot({a}, {tys[t].bits}, {tys[t].isSigned})"
	js.jsRefused(g, e, "the unary operator {op}")

# x as type to (`i64(x)`, `u8.wrap(x)`, a range's or a defined type's): checked as Zap checks it
fn jsConvert(mut g Gen, mut js Js, arg NodeId, to TypeId, wrap bool):
	from = g.jsDerefType(g.ty(arg))
	v = g.jsValue(js, arg)
	fk = g.tyK(from)
	tk = g.tyK(to)
	if tk == tFloat: return "Math.fround({v})" if tys[to].bits == 32 else v
	if tk != tInt: return v
	if fk == tFloat: return "rt__floatToInt({v}, {tys[to].bits}, {tys[to].isSigned})"
	if fk == tBool: return "({v} ? 1 : 0)"
	if fk != tInt: return v
	if tys[to].ranged and not wrap: return "rt__inRange({v}, {tys[to].lo}, {tys[to].hi})"
	if wrap or tys[from].bits == tys[to].bits and tys[from].isSigned != tys[to].isSigned:
		return "rt__wrapInt({v}, {tys[to].bits}, {tys[to].isSigned})"   # (a sign change keeps the bits)
	if g.jsIntFits(from, to): return v
	"rt__toInt({v}, {tys[to].bits}, {tys[to].isSigned})"

# whether every value of integer type from is one of to
fn jsIntFits(g Gen, from TypeId, to TypeId):
	if tys[to].ranged: return false
	if tys[from].isSigned == tys[to].isSigned: return tys[from].bits <= tys[to].bits
	not tys[from].isSigned and tys[from].bits < tys[to].bits
