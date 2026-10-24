# The types past the kept stages' a kept form names (keptir.zap): those the program made of the
# kept stages' types and generics alone (`{str: f64}`, `MapTable<str, f64>`), which another
# program makes alike under other ids. A form whose lowering met one keeps an ask of it by its
# parts; the build that takes the form finds the type it made of those parts, else lowers the
# function.

# a part a type has not (an optional's error, a struct's element)
keptNoPart = -1 << 40

# t as a kept form's ask names it: a kept stages' type as it is, else -1 - k, the k-th of asks, a
# type of its parts (added with its parts' asks before it when there is none); none when a part is
# neither, or the type is not one tyOnce makes once of its parts
fn keptTypeRef(g Gen, t TypeId?, mut asks KeptAsk[]) i64?:
	id = t ?? return keptNoPart
	if i64(id) < g.keptIr.types: return i64(id)
	if asks.findIndex(.kind == keptType and .off == i64(id)) is k: return -1 - k
	ty = g.c.types[id].copy()
	if ty.param != "" or not ty.closed: return none
	parts = [ty.kind, ty.bits, flagOf(ty.isSigned), flagOf(ty.counted), flagOf(ty.ranged), ty.lo, ty.hi]
	for part in [ty.inner, ty.err, ty.val, ty.ret, ty.under]:
		parts.push(try g.keptTypeRef(part, asks))
	if ty.defined is d and i64(d) >= g.keptIr.nodes: return none
	parts.push(i64(ty.defined ?? NodeId(0)) if ty.defined != none else keptNoPart)
	parts.push(ty.params.len)
	for p in ty.params:
		parts.push(try g.keptTypeRef(p, asks))
	if ty.decl is d:
		if i64(d) < g.keptIr.nodes:
			parts.extend([1, i64(d)])
		else:
			# an instance of a kept stages' generic struct or enum: its template and arguments
			tmpl = g.c.nodes[d].origin ?? return none
			if i64(tmpl) >= g.keptIr.nodes: return none
			args = g.c.nodes[d].ints().copy()
			parts.extend([2, i64(tmpl), args.len])
			for a in args:
				parts.push(try g.keptTypeRef(a, asks))
	else:
		parts.push(0)
	asks.push(
		KeptAsk(keptType, "{ty.name}\n{ty.display}\n{ty.definedName}", types = parts, off = i64(id))
	)
	-1 - (asks.len - 1)

# whether each of ts is a kept stages' type or one of their parts (keptTypeRef)
fn keptTypesOfParts(g Gen, ts TypeId[]):
	asks = []
	ts.all(g.keptTypeRef(it, asks) != none)

# the type a kept form's ref r names in this program: found holds its asks' types (-1 not found)
fn keptPartOf(r i64, found i64[]) TypeId?:
	if r == keptNoPart: return none
	id = r if r >= 0 else found[-1 - r]
	TypeId(id)

# the type of the parts a keptType ask names that this program made, as tyOnce made it: none
# when it made none such, or not of those ids
fn keptTypeFound(g Gen, ask KeptAsk, found i64[]) TypeId?:
	p = ask.types
	names = ask.text.split("\n")
	params = []
	n = p[13]
	for k in 0..n:
		params.push(keptPartOf(p[14 + k], found) ?? return none)
	at = 14 + n
	decl NodeId? = none
	if p[at] == 1:
		decl = NodeId(p[at + 1])
	elif p[at] == 2:
		args = []
		for k in 0..p[at + 2]:
			args.push(keptPartOf(p[at + 3 + k], found) ?? return none)
		tmpl = NodeId(p[at + 1])
		decl = g.c.madeInstanceAsked(tmpl, args) ?? g.c.madeInstanceNamed(tmpl, args) ?? return none
	t = Ty(
		kind = p[0],
		bits = p[1],
		isSigned = p[2] == 1,
		name = names[0].copy(),
		display = names[1].copy(),
		decl,
		inner = keptPartOf(p[7], found),
		err = keptPartOf(p[8], found),
		val = keptPartOf(p[9], found),
		params,
		ret = keptPartOf(p[10], found),
		counted = p[3] == 1,
		param = "",
		ranged = p[4] == 1,
		lo = p[5],
		hi = p[6],
		defined = NodeId(p[12]) if p[12] != keptNoPart else none,
		under = keptPartOf(p[11], found),
		definedName = names[2].copy()
	)
	tyFound(g.c.types, t)

# the types a kept form's keptType asks name found, in order (each one's parts before it): -1
# for the other asks; none when this program made one of them not (the form is not taken)
fn keptTypesFound(g Gen, asks KeptAsk[]) i64[]?:
	found = fill(asks.len, -1)
	for k, ask in asks:
		if ask.kind == keptType: found[k] = i64(try g.keptTypeFound(ask, found))
	found

# an ask's types as a kept form keeps them: each past the kept stages' as keptTypeRef names it;
# none when one is not of their parts
fn keptAskTypes(g Gen, ts i64[], mut asks KeptAsk[]) i64[]?:
	out = []
	for t in ts:
		out.push(try g.keptTypeRef(TypeId(t), asks))
	out

# a type an ask names (keptAskTypes): a kept stages' type, or the k-th ask's found
fn keptAskType(r i64, found i64[]) TypeId:
	keptPartOf(r, found) ?? tyUnit

fn flagOf(b bool):
	1 if b else 0
