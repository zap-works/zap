# The JS target's matches (jsModule.zap): the matched value held once, then an arm a test of its
# pattern; an if/else chain, or a labeled block each arm leaves when a guard may send the value
# on to the next arm. A pattern is a condition on the value and the names it binds, each a part
# of the value read where the arm starts.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# what a pattern asks of a value: the conditions, all true, and the names it binds to their texts
type JsPat:
	tests str[] = []
	binds JsBind[] = []

# a name a pattern binds, and the JS text of the part of the value it reads
type JsBind:
	name str
	text str
	alias bool = false   # `mut name`: the name is the part itself, changed in place

# a match, its value given to `into` when it has one
fn jsMatch(mut g Gen, mut js Js, e NodeId, into str?):
	subject = nodes[e].kids(kidIds)[0]
	arms = nodes[e].kidsFrom(kidIds, 1).copy()
	t = g.jsDerefType(g.ty(subject))
	v = g.jsValue(js, subject)
	if not jsSimple(v):
		held = js.jsTemp()
		js.jsLine("const {held} = {v};")
		v = held
	guarded = arms.any(not nodes[nodes[it].kids(kidIds)[0]].sub(kidIds).isEmpty)
	label = ""
	if guarded:
		label = js.jsTemp()
		js.jsOpen("{label}:")
	for i, arm in arms:
		pat = nodes[arm].kids(kidIds)[0]
		p = JsPat()
		g.jsPattern(js, pat, v, t, p)
		test = p.tests.join(" && ") if not p.tests.isEmpty else "true"
		if guarded:
			js.jsOpen("if ({test})")
		elif i == 0:
			js.jsOpen("if ({test})")
		elif p.tests.isEmpty:
			js.jsReopen(r"} else {")
		else:
			js.jsReopen("} else if ({test}) \{")
		for b in p.binds:
			if b.alias:
				js.jsBind(b.name, b.text)
			else:
				js.jsLine("let {js.jsDeclare(g, b.name)} = {b.text};")
		if guarded:
			guard = nodes[pat].sub(kidIds).copy()
			if not guard.isEmpty:
				js.jsOpen("if ({g.jsCond(js, guard[0])})")
			g.jsArm(js, arm, into.copy())
			js.jsLine("break {label};")
			if not guard.isEmpty: js.jsClose()
			js.jsClose()
		elif i == arms.len - 1:
			g.jsArm(js, arm, into.copy())
			js.jsClose()
		else:
			g.jsArm(js, arm, into.copy())
	if guarded: js.jsClose()

# an arm's body: its expression or its block, the value given to `into`
fn jsArm(mut g Gen, mut js Js, arm NodeId, into str?):
	if nodes[arm].kids(kidIds).len > 1:
		e = nodes[arm].kids(kidIds)[1]
		if into is to:
			g.jsInto(js, e, to.copy())
		else:
			g.jsExprStmt(js, e)
		return
	if not nodes[arm].sub(kidIds).isEmpty:
		g.jsArmBody(js, nodes[arm].sub(kidIds)[0], into)

# the pattern pat on the value v of type t: its tests and names added to p
fn jsPattern(mut g Gen, mut js Js, pat NodeId, v str, t TypeId, mut p JsPat):
	kind = nodes[pat].ival
	k = g.tyK(t)
	if kind == patWildcard: return
	if kind == patNone:
		p.tests.push("{v} === null")
		return
	if kind == patBind:
		if k == tResult and nodes[pat].bindsError():
			p.tests.push("{v} instanceof rt__Err")
			p.binds.push(JsBind(nodes[pat].text.copy(), "{v}.e"))
			return
		if k == tResult: p.tests.push("!({v} instanceof rt__Err)")
		if k == tOption: p.tests.push("{v} !== null")
		held = g.jsUnwrapped(v, t)
		p.binds.push(
			JsBind(nodes[pat].text.copy(), held.copy(), alias = nodes[pat].hasFlag(flagMut))
		)
		if not nodes[pat].kids(kidIds).isEmpty:
			g.jsPattern(js, nodes[pat].kids(kidIds)[0], held, g.jsInnerOf(t), p)
		return
	if kind == patLit:
		lit = g.jsValue(js, nodes[pat].kids(kidIds)[0])
		p.tests.push("{v} === {lit}")
		return
	if kind == patRange:
		parts = nodes[pat].kids(kidIds).copy()
		p.tests.push("{v} >= {g.jsValue(js, parts[0])}")
		if parts.len > 1:
			p.tests.push(
				"{v} {"<=" if nodes[pat].text2(kidIds) == "=" else "<"} {g.jsValue(js, parts[1])}"
			)
		return
	if kind == patCtor:
		g.jsCtorPattern(js, pat, v, t, p)
		return
	if kind == patTuple:
		for i, part in nodes[pat].kids(kidIds).copy():
			g.jsPattern(js, part, "{v}._{i}", g.jsFieldType(t, i), p)
		return
	if kind == patList:
		g.jsListPattern(js, pat, v, t, p)
		return
	js.jsRefuse(g, pat, "a pattern of kind {kind}")

# the value an optional or a result holds when it holds one
fn jsInnerOf(g Gen, t TypeId):
	if g.tyK(t) == tOption or g.tyK(t) == tResult: return g.jsDerefType(innerOf(tys, t))
	t

# Variant(...), Struct(...): its tag tested, then its parts, by name or by place
fn jsCtorPattern(mut g Gen, mut js Js, pat NodeId, v str, t0 TypeId, mut p JsPat):
	t = t0
	held = v.copy()
	if g.tyK(t) == tResult:
		# a variant of the error's type tests the error, any other the value
		errT = g.jsDerefType(errOf(tys, t))
		ofError = g.tyK(errT) == tEnum and
			nodes[declOf(tys, errT)].kids(kidIds).any(nodes[it].text == nodes[pat].text)
		p.tests.push("{"" if ofError else "!("}{v} instanceof rt__Err{"" if ofError else ")"}")
		held = "{v}.e" if ofError else v.copy()
		t = errT if ofError else g.jsDerefType(innerOf(tys, t))
	if g.tyK(t) == tOption:
		p.tests.push("{v} !== null")
		held = g.jsUnwrapped(v, t)
		t = g.jsInnerOf(t)
	k = g.tyK(t)
	if k == tEnum:
		ed = declOf(tys, t)
		vi = nodes[ed].kids(kidIds).findIndex(nodes[it].text == nodes[pat].text) ?? -1
		if vi < 0:
			js.jsRefuse(g, pat, "the variant {nodes[pat].text}")
			return
		if g.jsPlainEnum(t):
			p.tests.push("{held} === {vi}")
			return
		variant = nodes[ed].kids(kidIds)[vi]
		p.tests.push("{held}.$tag === {jsQuote(nodes[variant].text)}")
		fields = nodes[variant].kids(kidIds).copy()
		for i, part in nodes[pat].kids(kidIds).copy():
			at = i
			if i < nodes[pat].names(kidIds).len and nodes[pat].names(kidIds)[i] != "":
				at = fields.findIndex(nodes[it].text == nodes[pat].names(kidIds)[i]) ?? i
			if at >= fields.len: continue
			ft = g.jsDerefType(g.c.resolveType(nodes[fields[at]].types(kidIds)[0]))
			g.jsPattern(js, part, "{held}.{jsPayloadName(nodes[fields[at]].text, at)}", ft, p)
		return
	if k == tStruct:
		sd = declOf(tys, t)
		for i, part in nodes[pat].kids(kidIds).copy():
			name = nodes[pat].names(kidIds)[i] if i < nodes[pat].names(kidIds).len else ""
			fi = g.c.fieldIndexOf(sd, name) if name != "" else i
			if fi < 0: continue
			field = nodes[sd].kids(kidIds)[fi]
			g.jsPattern(js, part, "{held}.{nodes[field].text}", g.jsFieldType(t, fi), p)
		return
	js.jsRefuse(g, pat, "the pattern {nodes[pat].text} on {typeStr(tys, t)}")

# the type of field i of struct type t
fn jsFieldType(mut g Gen, t TypeId, i i64):
	if g.tyK(t) != tStruct: return tyError
	sd = declOf(tys, t)
	if i >= nodes[sd].kids(kidIds).len: return tyError
	g.jsDerefType(g.c.structFieldTypeAt(sd, i))

# [a, ..rest, b]: its length, then each element from the front or the back, the rest a slice
fn jsListPattern(mut g Gen, mut js Js, pat NodeId, v str, t TypeId, mut p JsPat):
	parts = nodes[pat].kids(kidIds).copy()
	rest = parts.findIndex(nodes[it].ival == patRest)
	elem = g.jsDerefType(innerOf(tys, t))
	fixed = parts.len - (1 if rest != none else 0)
	p.tests.push("{v}.length {">=" if rest != none else "==="} {fixed}")
	for i, part in parts:
		if rest is r and i == r:
			if nodes[part].text != "":
				p.binds.push(
					JsBind(
						nodes[part].text.copy(),
						"{v}.slice({r}, {v}.length - {parts.len - r - 1})"
					)
				)
			continue
		at = "{i}" if rest == none or i < (rest ?? 0) else "{v}.length - {parts.len - i}"
		g.jsPattern(js, part, "{v}[{at}]", elem, p)
