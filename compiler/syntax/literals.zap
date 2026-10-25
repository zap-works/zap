# The values of literals and constant expressions known when compiling.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types
alias vars = g.f.vars

fn constIntValue(mut g Gen, e NodeId) i64:
	if nodes[e].kind == nInt: return g.intLitValue(e)
	# the intrinsic is classified first: sizeOf and isOwningType change g
	nm = nodes[nodes[e].kids(kidIds)[0]].text
	isKind = nm == "__tykind"
	isSize = nm == "__sizeof"
	isOwning = nm == "__owning"
	isSigned = nm == "__tysigned"
	isWindow = nm == "__window"
	at = g.ty(nodes[e].kids(kidIds)[1])
	if isWindow: return 1 if g.isTextWindow(at) else 0
	if isKind: return g.tyK(at)
	if isSize: return g.sizeOf(at)
	if isOwning:
		if g.isOwningType(at): return 1
		return 0
	if isSigned:
		if g.tyK(at) == tInt and tys[at].isSigned: return 1
		return 0
	g.c.elemStride(at)

# the integer literal e stands for: e itself, or the value of the immutable module constant e
# names (keyBits = -0x10000000), when no local takes that name; none when it is neither
fn intLitOf(g Gen, e NodeId) NodeId?:
	k = nodes[e].kind
	if k == nInt: return e
	if k != nIdent: return none
	v = g.findVar(nodes[e].text)
	if v >= 0:
		lit = vars[v].literal   # an inlined constant argument, an unrolled counter
		l = try lit
		return l if nodes[l].kind == nInt else none
	np = g.c.numberParam(nodes[e].text)
	if np is np and tys[np].decl != none: return declOf(tys, np)   # a number parameter's value
	d = try g.isConstName(nodes[e].text)
	if nodes[d].kids(kidIds).isEmpty or nodes[nodes[d].kids(kidIds)[0]].kind != nInt: return none
	nodes[d].kids(kidIds)[0]

# whether e is an integer known when compiling (a literal or a constant of one): an operand
# that can be an immediate, a divisor turned into a multiplication...
fn isIntLit(g Gen, e NodeId):
	g.intLitOf(e) != none

fn intLitValue(g Gen, e0 NodeId):
	e = g.intLitOf(e0) ?? e0
	text = nodes[e].text
	t = g.ty(e)
	if g.tyK(t) == tInt and not tys[t].isSigned: return parseUnsigned(text)
	match i64.parse(text):
		v: return v
		none:
			die("x64: bad integer literal {text}")
			return 0

fn floatLitBits(g Gen, e NodeId) i64:
	text = nodes[e].text
	t = g.ty(e)
	match f64.parse(text):
		d:
			if g.tyK(t) == tFloat and tys[t].bits == 32: return i64(f64(f32(d)).toBits())
			return i64(d.toBits())
		none:
			die("x64: bad float literal {text}")
			return 0

fn parseUnsigned(text str) i64:
	v u64 = 0
	for b in text:
		if b < 48 or b > 57: break
		v = v * 10 + u64(b - 48)
	i64(v)
