# The JS target's calls (jsModule.zap): a function of the program by its name, a method of a type
# as `Type__name(receiver, ...)`, a method of a list, a str, a map or a number as the runtime's
# function of that method (`xs.push(x)` is rt__listPush(xs, x), as checkDecls.zap names them),
# the prelude's when it has one; a mut parameter whose value is no JS object goes in a box
# (`{v}`), its value written back to the caller's place after the call.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

fn jsCall(mut g Gen, mut js Js, e NodeId) str:
	callee = nodes[e].kids(kidIds)[0]
	args = nodes[e].kidsFrom(kidIds, 1).copy()
	if args.any(nodes[it].kind == nNamedArg):
		return js.jsRefused(g, e, "a call with named arguments")
	t = g.ty(e)
	if nodes[e].hasFlag(flagRangeConversion):
		return g.jsConvert(js, args[0], t, nodes[e].hasFlag(flagWrap))
	if nodes[callee].kind == nIdent and nodes[callee].text == "rt__listSlice" and args.len == 3:
		which = "rt__strSlice" if g.tyK(g.jsDerefType(g.ty(args[0]))) == tStr else "rt__listSlice"
		return "{which}({args.map(g.jsValue(js, it)).join(", ")})"
	if g.irVariantOf(callee, t) >= 0: return g.jsVariant(js, callee, t, args)
	if g.tyK(g.ty(callee)) == tFn and g.jsCallsValue(js, callee):
		f = g.jsValue(js, callee)
		return "{f}({args.map(g.jsStored(js, it)).join(", ")})"
	if nodes[callee].kind == nField: return g.jsMethodCall(js, e, callee, args)
	if nodes[callee].kind != nIdent: return js.jsRefused(g, e, "a call of this form")
	g.jsFreeCall(js, e, nodes[callee].text.copy(), args)

# whether the callee is a function value: a local, a field, an element, not a function's name
fn jsCallsValue(mut g Gen, js Js, callee NodeId):
	if nodes[callee].kind != nIdent: return true
	if js.jsLookup(nodes[callee].text) != none: return true
	if js.b.selfType is st and g.tyK(st) == tStruct and
		g.c.fieldIndexOf(declOf(tys, st), nodes[callee].text) >= 0:
		return true
	g.c.findFunc(nodes[callee].text) == none and
		g.c.findDeclByGlobalName(nConstDecl, nodes[callee].text) != none

# f(args) by name: print, a conversion, a function of the program or of the runtime, a generic's
# instance
fn jsFreeCall(mut g Gen, mut js Js, e NodeId, name str, args NodeId[]) str:
	if (name == "print" or name == "eprint") and args.len == 1:
		return "rt__printLine({g.jsToStr(js, args[0])}, {1 if name == "eprint" else 0})"
	if name.startsWith("__"): return g.jsIntrinsic(js, e, name, args)
	if args.len == 1 and primTypes.any(.name == name):
		return g.jsConvert(js, args[0], g.ty(e), false)
	if name == "Box" and args.len == 1: return g.jsStored(js, args[0])
	if name == "str" and args.len == 1: return g.jsStrCall(js, args[0])
	fnd = g.c.findFunc(name)
	if nodes[e].text2() != "" and jsSafe(name) in js.prelude:
		return "{jsSafe(name)}({args.map(g.jsStored(js, it)).join(", ")})"   # the prelude's, for any type
	if nodes[e].text2() != "":
		f = fnd ?? return js.jsRefused(g, e, "the generic {name}")
		ii = g.c.findInstance(f, nodes[e].text2()) ??
			return js.jsRefused(g, e, "the instance of {name}")
		key = "{jsSafe(name)}__{jsIdent(nodes[e].text2())}"
		js.jsWant(key.copy(), g.c.instances[ii].decl, inst = ii)
		return g.jsCallTo(
			js,
			key,
			g.c.instances[ii].decl,
			[],
			args,
			sub = g.c.instances[ii].sub.copy()
		)
	if fnd is f:
		js.jsWant(jsSafe(name), f)
		return g.jsCallTo(js, jsSafe(name), f, [], args)
	if builtinRtName(name) != "":
		rt = "rt__{builtinRtName(name)}"
		if g.c.findFunc(rt) is d:
			js.jsWant(rt.copy(), d)
			return g.jsCallTo(js, rt, d, [], args)
		if rt in js.prelude: return "{rt}({args.map(g.jsStored(js, it)).join(", ")})"
	if js.b.selfType is st and js.jsLookup("self") is recv and
		g.c.findMethod(tys[st].name, name) is md:
		return g.jsUserMethod(js, md, st, recv, none, args)
	js.jsRefused(g, e, "the call of {name}")

# an intrinsic of the runtime's: the bounds of an integer type and a conversion to it (what a
# generic over numbers reads); one of raw memory is refused
fn jsIntrinsic(mut g Gen, mut js Js, e NodeId, name str, args NodeId[]) str:
	if (name == "__tylo" or name == "__tyhi") and args.len == 1 and g.tyK(g.ty(args[0])) == tInt:
		lo, hi = intBounds(tys, g.ty(args[0]))
		v = lo if name == "__tylo" else hi
		if v > 9_007_199_254_740_991 or v < -9_007_199_254_740_991:
			return js.jsRefused(g, e, "the bound {v} of {typeStr(tys, g.ty(args[0]))}, past 2^53")
		return "{v}"
	if name == "__cast" and args.len == 1 and g.tyK(g.ty(e)) in [tInt, tFloat]: return g.jsValue(js, args[0])
	js.jsRefused(g, e, "the intrinsic {name}")

# str(x): the text of bytes, or of any value as print writes it
fn jsStrCall(mut g Gen, mut js Js, arg NodeId) str:
	t = g.jsDerefType(g.ty(arg))
	if g.tyK(t) == tList and g.tyK(innerOf(tys, t)) == tInt and tys[innerOf(tys, t)].bits == 8:
		return "rt__strOfBytes({g.jsValue(js, arg)})"
	g.jsToStr(js, arg)

# a name of the program's text that JS takes as a name: other characters `_`
fn jsIdent(s str):
	str(s.bytes().map(it if .isWordByte() or it == '$' else '_'))

# a call of the function fnd under name, the receiver's text first when it has one
fn jsCallTo(
	mut g Gen,
	mut js Js,
	name str,
	fnd NodeId,
	first str[],
	args NodeId[],
	method bool = false,
	sub Subst? = none
) str:
	mark = js.b.writeBacks.len
	all = first.copy()
	all.extend(g.jsArgs(js, fnd, args, 0 if method else first.len, sub))
	backs = js.b.writeBacks[mark..].copy()
	js.b.writeBacks.truncate(mark)
	g.jsBoxedCall(js, "{name}({all.join(", ")})", backs)

# the boxes a call's arguments made, written back once the call ran
fn jsBoxedCall(mut g Gen, mut js Js, call str, backs str[]):
	if backs.isEmpty: return call.copy()
	r = js.jsTemp()
	js.jsLine("let {r};")
	"({r} = {call}, {backs.join(", ")}, {r})"

# the arguments' texts for fnd's parameters from the k-th on: a boxed parameter's a box of the place
fn jsArgs(mut g Gen, mut js Js, fnd NodeId, args NodeId[], k i64, sub Subst?):
	params = nodes[fnd].kids(kidIds).copy()
	out = []
	for i, a in args:
		if i + k >= params.len:
			out.push(g.jsValue(js, a))
			continue
		p = params[i + k]
		if g.jsBoxedIn(fnd, p, sub):
			place = g.jsPlaceText(js, g.jsUnmoved(a))
			box = js.jsTemp()
			js.jsLine("const {box} = \{v: {place}\};")
			js.b.writeBacks.push("{place} = {box}.v")
			out.push(box)
		elif nodes[p].ival == modeMove:
			out.push(g.jsStored(js, a))
		else:
			out.push(g.jsValue(js, a))
	out

# whether parameter p of fnd is boxed, under the substitution of the instance called (the caller's
# own is in force where the call is written)
fn jsBoxedIn(mut g Gen, fnd NodeId, p NodeId, sub Subst?):
	given = sub ?? return g.jsBoxedParam(fnd, p)
	saved = move g.c.subst
	g.c.subst = given.copy()
	out = g.jsBoxedParam(fnd, p)
	g.c.subst = saved
	out

# the place an argument names, a `mut` or `move` before it taken off
fn jsUnmoved(g Gen, a NodeId):
	if nodes[a].kind == nUnary and nodes[a].ival in [unMove, unMutRef, unRef]:
		return nodes[a].kids(kidIds)[0]
	a

# obj.m(args): a size, a derived function, a stream's print, the runtime's method of a list, a
# str, a map or a number, a method of the program's types
fn jsMethodCall(mut g Gen, mut js Js, e NodeId, callee NodeId, args NodeId[]):
	m = nodes[callee].text.copy()
	obj = nodes[callee].kids(kidIds)[0]
	ot = g.jsDerefType(g.ty(obj))
	k = g.tyK(ot)
	if nodes[callee].hasFlag(flagSize) and args.isEmpty and k != tStruct and k != tEnum:
		return g.jsSize(js, obj, ot, m)
	if nodes[e].hasFlag(flagBoundCall) and
		g.c.boundCalls.get("{e} {typeMangled(tys, g.c.derefType(g.ty(obj)))}") is call:
		return g.jsCall(js, call)
	if g.c.derivedMethod(e, m) is family: return g.jsDerivedCall(js, e, family, obj, args)
	if m == "print" and args.len == 1 and k == tStruct and
		nodes[declOf(tys, ot)].text2() == "Stream":
		return "rt__streamPrint({g.jsValue(js, obj)}, {g.jsToStr(js, args[0])})"
	if m == "copy" and args.isEmpty and
		(k != tStruct and k != tEnum or g.c.findMethod(tys[ot].name, m) == none):
		if k == tStr or not g.jsIsObject(ot): return g.jsValue(js, obj)
		return "rt__copy({g.jsValue(js, obj)})"
	if (k == tStruct or k == tEnum) and g.c.findMethod(tys[ot].name, m) is md:
		return g.jsUserMethod(js, md, ot, "", obj, args)
	if (k == tInt or k == tFloat) and args.isEmpty and m.startsWith("to") and
		primTypes.any(.name == m[2..].lower()):
		return g.jsConvert(js, obj, g.ty(e), false)   # x.toI64(): the conversion
	if m == "intoStr" and k == tList:
		bytes = g.jsTake(js, obj, ot) if g.jsIsPlace(obj) else g.jsValue(js, obj)
		return "rt__strOfBytes({bytes})"   # str(move bytes): the list left empty
	if m == "take" and args.isEmpty and g.jsIsPlace(obj): return g.jsTake(js, obj, ot)
	if k == tInt and (m in intBitMethods or m in bitFieldMethods):
		parts = [g.jsValue(js, obj)]
		parts.extend(args.map(g.jsValue(js, it)))
		return "rt__int{capital(m)}({parts.join(", ")}, {tys[ot].bits}, {tys[ot].isSigned})"
	if k == tFloat and (m == "toBits" or m == "fromBits"):
		return "rt__float{capital(m)}({g.jsValue(js, obj)}, {tys[ot].bits})"
	name = jsRuntimeMethod(k, ot, m, tys)
	if nodes[obj].kind == nRange: name = "rt__list{capital(m)}"   # (lo..hi).map(f): its list's
	if name == "": return js.jsRefused(g, e, "the method {m} of {typeStr(tys, ot)}")
	recv = g.jsPlaceText(js, obj) if g.jsBoxedReceiver(name) else g.jsValue(js, obj)
	if g.c.findFunc(name) is d and name not in js.prelude:
		js.jsWant(name.copy(), d)
		return g.jsCallTo(js, name, d, [recv], args)
	if name not in js.prelude: return js.jsRefused(g, e, "the method {m} of {typeStr(tys, ot)}")
	all = [recv]
	all.extend(args.map(g.jsStored(js, it)))
	if g.jsNestedOption(g.ty(e)): all.push("true")   # (an element that is itself none told apart)
	call = "{name}({all.join(", ")})"
	rt = g.ty(e)
	"Math.fround({call})" if g.tyK(rt) == tFloat and tys[rt].bits == 32 else call

# place.take(): its value, the place left empty (the empty value of its type)
fn jsTake(mut g Gen, mut js Js, obj NodeId, t TypeId):
	place = g.jsPlaceText(js, obj)
	v = js.jsTemp()
	js.jsLine("const {v} = {place};")
	js.jsLine("{place} = {g.jsZero(js, t, obj)};")
	v

# whether the runtime's method takes its receiver to change it whole (none yet: a list, a map
# and a struct change in place)
fn jsBoxedReceiver(g Gen, name str):
	false

# the runtime's function of the method m of a receiver of kind k (checkDecls.zap's names), "" when
# the receiver has none
fn jsRuntimeMethod(k i64, t TypeId, m str, types Ty[]):
	if k == tStr: return "rt__{strMethodRt(m) if strMethodRt(m) != "" else "str{capital(m)}"}"
	if k == tList or k == tArray: return "rt__list{capital(m)}"
	if k == tMap: return "rt__map{capital(m)}"
	if k == tFloat: return "rt__f64{capital(m)}"
	if k == tInt: return "rt__int{capital(m)}"
	if k == tBool: return "rt__bool{capital(m)}"
	if k == tOption: return "rt__option{capital(m)}"
	""

# xs.len, s.len, m.len, x.isEmpty
fn jsSize(mut g Gen, mut js Js, obj NodeId, t TypeId, m str) str:
	o = g.jsValue(js, obj)
	k = g.tyK(t)
	if m == "len":
		if k == tStr: return "rt__strLen({o})"
		if k == tMap: return "{o}.size"
		return "{o}.length"
	if m == "isEmpty":
		if k == tMap: return "({o}.size === 0)"
		return "({o}.length === 0)"
	js.jsRefused(g, obj, "the size {m} of {typeStr(tys, t)}")

# a method of the program's types: Type__m(receiver, ...)
fn jsUserMethod(
	mut g Gen,
	mut js Js,
	md NodeId,
	ot TypeId,
	recvText str,
	obj NodeId?,
	args NodeId[]
) str:
	impl = g.c.findImplDeclOf(tys[ot].name, md)
	generic = g.c.implIsGenericOf(impl)
	name = "{jsIdent(tys[ot].name)}__{nodes[md].text}"
	js.jsWant(name.copy(), md, implType = ot, impl = impl if generic else none)
	given Subst? = none
	if generic and impl is d:
		given = Subst(names = nodes[d].names2().copy(), types = nodes[d].ints().copy())
	recv = recvText.copy()
	backs = []
	if obj is o: recv = g.jsValue(js, o)
	if g.jsBoxedSelf(md):
		# the receiver in a box, its value written back to the caller's place after the call
		place = recvText.copy()
		if obj is o: place = g.jsPlaceText(js, g.jsUnmoved(o))
		box = js.jsTemp()
		js.jsLine("const {box} = \{v: {place}\};")
		recv = box.copy()
		backs.push("{place} = {box}.v")
	call = g.jsCallTo(js, name, md, [recv], args, method = true, sub = given)
	g.jsBoxedCall(js, call, backs)

# a function derive.zap wrote: T.fromJson(s), v.toJson(), ...
fn jsDerivedCall(mut g Gen, mut js Js, e NodeId, family str, obj NodeId, args NodeId[]) str:
	fromType = family in [
		"fromjson",
		"frombytes",
		"frombits",
		"read",
		"fromvalue",
		"readat",
		"fromcsv"
	]
	t = g.ty(e) if family == "frombits" or family == "read"
		else innerOf(tys, g.ty(e)) if fromType
		else g.ty(obj)
	fnd = g.derivedFn(family, t) ??
		return js.jsRefused(g, e, "the derived {family} of {typeStr(tys, t)}")
	js.jsWant(nodes[fnd].text.copy(), fnd)
	first = []
	if not fromType: first.push(g.jsValue(js, obj))
	g.jsCallTo(js, nodes[fnd].text.copy(), fnd, first, args)
