# The JS target's statements (jsModule.zap): each a line or a block of the body being written,
# the lines an expression needs first (a match's, a `??`'s that leaves) written before it.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

fn jsStmt(mut g Gen, mut js Js, s NodeId):
	k = nodes[s].kind
	if k == nBlock:
		if nodes[s].text == "$splice":
			for kid in nodes[s].kids(kidIds).copy():
				g.jsStmt(js, kid)
			return
		js.jsOpen("")
		g.jsStmts(js, s)
		js.jsClose()
	elif k == nLet: g.jsLet(js, s)
	elif k == nAssign: g.jsAssign(js, s)
	elif k == nReturn: g.jsReturn(js, s)
	elif k == nExprStmt: g.jsExprStmt(js, nodes[s].kids(kidIds)[0])
	elif k == nIf: g.jsIf(js, s, none)
	elif k == nWhile: g.jsWhile(js, s)
	elif k == nFor: g.jsFor(js, s)
	elif k == nBreak: js.jsLine("break;")
	elif k == nContinue: js.jsLine("continue;")
	elif k == nYield: js.jsLine("yield {g.jsValue(js, nodes[s].kids(kidIds)[0])};")
	elif k == nMatch or k == nCall: g.jsExprStmt(js, s)
	else: js.jsRefuse(g, s, "a statement of kind {k}")

fn jsStmts(mut g Gen, mut js Js, blk NodeId):
	for kid in nodes[blk].kids(kidIds).copy():
		g.jsStmt(js, kid)

# an expression whose value is not used: a match or an if as statements, else its line
fn jsExprStmt(mut g Gen, mut js Js, e NodeId):
	k = nodes[e].kind
	if k == nMatch:
		g.jsMatch(js, e, none)
		return
	if k == nIf:
		g.jsIf(js, e, none)
		return
	if k in [nReturn, nBreak, nContinue]:
		g.jsStmt(js, e)
		return
	v = g.jsValue(js, e)
	if v != "" and v != "undefined": js.jsLine("{v};")

# `name = value`: a new name, or the name bound before given the value (a bare let of a name in
# scope); `x i64 = 0` and a loop's element binding always make a new one
fn jsLet(mut g Gen, mut js Js, s NodeId):
	name = nodes[s].text.copy()
	if nodes[s].kids(kidIds).isEmpty:
		t = g.c.resolveType(nodes[s].types()[0]) if nodes[s].ty == none else g.ty(s)
		js.jsLine("let {js.jsDeclare(g, name)} = {g.jsZero(js, t, s)};")
		return
	value = nodes[s].kids(kidIds)[0]
	if nodes[s].canAssign() and g.jsAssignedName(js, name) is known:
		js.jsLine("{known} = {g.jsStored(js, value)};")
		return
	# `x = mut ref place` of a number: x reads and writes the place itself
	if nodes[value].kind == nUnary and nodes[value].ival == unMutRef and
		not g.jsIsObject(g.ty(nodes[value].kids(kidIds)[0])):
		place = g.jsPlaceText(js, nodes[value].kids(kidIds)[0])
		js.jsBind(name, place)
		return
	text = g.jsStored(js, value)
	js.jsLine("let {js.jsDeclare(g, name)} = {text};")

# what a bare `name = v` assigns when the name is bound: a local, a field of the method's receiver,
# a module variable (main's ordered binding among them)
fn jsAssignedName(mut g Gen, mut js Js, name str) str?:
	if js.jsLookup(name) is known: return known
	if js.b.selfType is st and g.tyK(st) == tStruct and
		g.c.fieldIndexOf(declOf(tys, st), name) >= 0:
		return "self.{name}"
	d = try g.c.findDeclByGlobalName(nConstDecl, name)
	if not nodes[d].hasFlag(flagMut) and not nodes[d].hasFlag(flagOrdered): return none
	js.jsWantGlobal(g, d)
	jsSafe(name)

# the value as a place keeps it: a plain struct read from a place copied (JS would share the object)
fn jsStored(mut g Gen, mut js Js, e NodeId):
	v = g.jsValue(js, e)
	if g.jsCopiedWhenStored(js, e): return "rt__copy({v})"
	v

# whether a value read from a place is copied where it is stored: plain data held in an object
# (a constant's value that owns memory too: each use of it whole is a value of its own)
fn jsCopiedWhenStored(mut g Gen, js Js, e NodeId):
	t = g.ty(e)
	if not g.jsIsObject(t): return false
	if nodes[e].kind == nIdent and js.jsLookup(nodes[e].text) == none and
		g.c.findDeclByGlobalName(nConstDecl, nodes[e].text) is d and not nodes[d].hasFlag(flagMut):
		return true
	g.c.isPlainType(t) and g.jsIsPlace(e)

# whether e names a place (a variable, a field or an element of one)
fn jsIsPlace(g Gen, e NodeId) bool:
	k = nodes[e].kind
	if k == nIdent: return true
	if k == nField and not nodes[e].kids(kidIds).isEmpty:
		return g.jsIsPlace(nodes[e].kids(kidIds)[0]) or
			nodes[nodes[e].kids(kidIds)[0]].kind == nCall
	if k == nIndex or k == nDeref: return g.jsIsPlace(nodes[e].kids(kidIds)[0])
	false

# `place = value`, `place op= value`
fn jsAssign(mut g Gen, mut js Js, s NodeId):
	target = nodes[s].kids(kidIds)[0]
	value = nodes[s].kids(kidIds)[1]
	if nodes[target].kind == nIndex and
		g.tyK(g.jsDerefType(g.ty(nodes[target].kids(kidIds)[0]))) == tMap:
		m = g.jsValue(js, nodes[target].kids(kidIds)[0])
		key = g.jsValue(js, nodes[target].kids(kidIds)[1])
		js.jsLine("rt__mapSet({m}, {key}, {g.jsStored(js, value)});")
		return
	v = g.jsStored(js, value)
	js.jsLine("{g.jsPlaceText(js, target)} = {v};")

# the JS text of a place written to: a name, a field, an element (its index checked)
fn jsPlaceText(mut g Gen, mut js Js, e NodeId) str:
	k = nodes[e].kind
	if k == nIdent: return g.jsName(js, e)
	if k == nDeref or k == nUnary: return g.jsPlaceText(js, nodes[e].kids(kidIds)[0])
	if k == nField:
		obj = nodes[e].kids(kidIds)[0]
		return "{g.jsPlaceText(js, obj)}.{nodes[e].text}"
	if k == nCall: return js.jsRefused(g, e, "an assignment through the reference a function gives")
	if k == nIndex:
		xs = nodes[e].kids(kidIds)[0]
		at = g.jsValue(js, nodes[e].kids(kidIds)[1])
		list = g.jsPlaceText(js, xs)
		t = g.jsDerefType(g.ty(xs))
		if g.tyK(t) == tStruct:
			return "{list}[{g.jsFieldNames(t)}[rt__at({g.jsFieldNames(t)}, {at})]]"
		return "{list}[rt__at({list}, {at})]"
	g.jsValue(js, e)

fn jsReturn(mut g Gen, mut js Js, s NodeId):
	if nodes[s].kids(kidIds).isEmpty:
		js.jsLine("return;")
		return
	e = nodes[s].kids(kidIds)[0]
	if g.tyK(g.ty(e)) == tUnit and nodes[e].kind != nCall:
		g.jsExprStmt(js, e)
		js.jsLine("return;")
		return
	js.jsLine("return {g.jsReturned(js, e, js.b.ret)};")

# the value a function of result type rt returns: an error of a result made an rt__Err when the
# value is of the error's type (the checker leaves which side to the backend)
fn jsReturned(mut g Gen, mut js Js, e NodeId, rt TypeId):
	v = g.jsStored(js, e)
	if g.tyK(rt) != tResult or g.tyK(g.ty(e)) == tResult: return v
	vt = g.ty(e)
	if isSameType(tys, vt, errOf(tys, rt)) and not isSameType(tys, vt, innerOf(tys, rt)):
		return "new rt__Err({v})"
	v

# an if, its value given to `into` when it has one
fn jsIf(mut g Gen, mut js Js, s NodeId, into str?):
	cond = g.jsCond(js, nodes[s].kids(kidIds)[0])
	js.jsOpen("if ({cond})")
	g.jsArmBody(js, nodes[s].sub()[0], into)
	if nodes[s].sub().len > 1:
		js.jsReopen(r"} else {")
		g.jsArmBody(js, nodes[s].sub()[1], into)
	js.jsClose()

# a block that gives its last expression's value to `into` (none: its value unused)
fn jsArmBody(mut g Gen, mut js Js, blk NodeId, into str?):
	kids = nodes[blk].kids(kidIds).copy()
	for i, s in kids:
		if i == kids.len - 1 and into is to and nodes[s].kind == nExprStmt:
			g.jsInto(js, nodes[s].kids(kidIds)[0], to)
		elif i == kids.len - 1 and into is to and nodes[s].kind == nIf and nodes[s].sub().len > 1:
			g.jsIf(js, s, to.copy())
		else:
			g.jsStmt(js, s)

# the value of e given to the name `to`: a match or an if written as statements
fn jsInto(mut g Gen, mut js Js, e NodeId, to str):
	k = nodes[e].kind
	if k == nMatch:
		g.jsMatch(js, e, to.copy())
	elif k == nIf and nodes[e].sub().len > 1:
		g.jsIf(js, e, to.copy())
	elif k in [nReturn, nBreak, nContinue]:
		g.jsStmt(js, e)
	else:
		js.jsLine("{to} = {g.jsStored(js, e)};")

# a condition: its lines before the loop's test when it needs some
fn jsWhile(mut g Gen, mut js Js, s NodeId):
	mark = js.b.lines.len
	cond = g.jsCond(js, nodes[s].kids(kidIds)[0])
	if js.b.lines.len == mark:
		js.jsOpen("while ({cond})")
	else:
		pre = js.b.lines[mark..].copy()
		js.b.lines.truncate(mark)
		js.jsOpen("while (true)")
		for l in pre:
			js.b.lines.push("\t{l}")
		js.jsLine("if (!({cond})) break;")
	g.jsStmts(js, nodes[s].sub()[0])
	js.jsClose()

# a for over a range, a list, a map's keys or a generator
fn jsFor(mut g Gen, mut js Js, s NodeId):
	iter = nodes[s].kids(kidIds)[0]
	name = nodes[s].text.copy()
	if nodes[iter].kind == nRange:
		g.jsForRange(js, s, iter)
		return
	t = g.jsDerefType(g.ty(iter))
	if nodes[s].hasFlag(flagMut) and not g.jsIsObject(innerOf(tys, t)):
		# `for mut x in xs` of numbers: x is the element itself
		list = js.jsTemp()
		js.jsLine("const {list} = {g.jsValue(js, iter)};")
		i = js.jsTemp()
		js.jsOpen("for (let {i} = 0; {i} < {list}.length; {i}++)")
		js.jsBind(name, "{list}[{i}]")
		g.jsStmts(js, nodes[s].sub()[0])
		js.jsClose()
		return
	src = g.jsValue(js, iter)
	if g.tyK(t) == tMap: src = "{src}.keys()"
	x = js.jsFresh(g, name)
	js.jsOpen("for (const {x} of {src})")
	js.jsBind(name, x)
	g.jsStmts(js, nodes[s].sub()[0])
	js.jsClose()

# lo..hi (hi past the last), with a step after it: down when the step is a negative literal
fn jsForRange(mut g Gen, mut js Js, s NodeId, iter NodeId):
	parts = nodes[iter].kids(kidIds).copy()
	# lo, hi and the step read once each, in that order (the loop's test reads hi each turn)
	values = parts.map(g.jsValue(js, it))
	if not values.all(jsSimple(it)):
		for i in 0..values.len:
			held = js.jsTemp()
			js.jsLine("const {held} = {values[i]};")
			values[i] = held
	lo = values[0].copy()
	hi = values[1].copy()
	step = values[2].copy() if values.len > 2 else "1"
	down = parts.len > 2 and nodes[parts[2]].kind == nInt and nodes[parts[2]].text.startsWith("-")
	i = js.jsFresh(g, nodes[s].text)
	advance = "{i}++" if step == "1" else "{i} += {step}"
	js.jsOpen("for (let {i} = {lo}; {i} {">" if down else "<"} {hi}; {advance})")
	js.jsBind(nodes[s].text, i)
	g.jsStmts(js, nodes[s].sub()[0])
	js.jsClose()

# whether a JS text is a name or a number, read again for nothing
fn jsSimple(text str):
	text.bytes().all(.isWordByte() or it == '$' or it == '.')

# the zero value of type t, for a variable declared without one
fn jsZero(mut g Gen, mut js Js, t TypeId, at NodeId) str:
	k = g.tyK(t)
	if k == tInt or k == tFloat: return "0"
	if k == tBool: return "false"
	if k == tStr: return "\"\""
	if k == tOption: return "null"
	if k == tList: return "[]"
	if k == tMap: return "{g.jsNewMap(t)}()"
	if k == tArray:
		return "Array.from(\{length: {tys[t].bits}\}, () => {g.jsZero(js, innerOf(tys, t), at)})"
	if k == tOption or k == tUnit: return "null"
	if k == tEnum and g.jsPlainEnum(t): return "0"
	js.jsRefuse(g, at, "the zero of {typeStr(tys, t)}")
	"undefined"
