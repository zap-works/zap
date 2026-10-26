# The types past the kept stages' a kept form names (keptir.zap): those the program made of the
# kept stages' types and generics alone (`{str: f64}`, `MapTable<str, f64>`), which another
# program makes alike under other ids, and of the program's own structs of such fields (`{str:
# Row[]}`), which another program declares alike. A form whose lowering met one keeps an ask of it by its
# parts; the build that takes the form finds the type it made of those parts, else lowers the
# function.

# a part a type has not (an optional's error, a struct's element)
keptNoPart = -1 << 40
keptOwnNamed = keptNoPart + 1   # a defined type the program declares, by its name

# the declaration of the type the program declares under name (keptentry.zap)
fn ownTypeNamed(g Gen, name str) NodeId?:
	d = try g.keptIr.entry.types.get(name)
	NodeId(d) if d >= 0 else none

# t as a kept form's ask names it: a kept stages' type as it is, else -1 - k, the k-th of asks, a
# type of its parts (added with its parts' asks before it when there is none); none when a part is
# neither, or the type is not one tyOnce makes once of its parts
fn keptTypeRef(g Gen, t TypeId?, mut asks KeptAsk[]) i64?:
	id = t ?? return keptNoPart
	if i64(id) < g.keptIr.types: return i64(id)
	if asks.findIndex(.kind == keptType and .off == i64(id)) is k: return -1 - k
	ty = g.c.types[id].copy()
	if ty.param != "": return none
	if not ty.closed:
		if not g.keptIr.entry.planning: return none
		return g.freshTypeRef(id, asks)
	parts = [
		ty.kind,
		ty.bits,
		flagOf(ty.isSigned),
		flagOf(ty.counted),
		flagOf(ty.ranged),
		ty.lo,
		ty.hi
	]
	for part in [ty.inner, ty.err, ty.val, ty.ret, ty.under]:
		parts.push(try g.keptTypeRef(part, asks))
	if ty.defined is d and i64(d) >= g.keptIr.nodes:
		if not g.keptIr.entry.planning: return none
		parts.push(keptOwnNamed)   # (the program's own: found by its name)
	else:
		parts.push(i64(ty.defined ?? NodeId(0)) if ty.defined != none else keptNoPart)
	parts.push(ty.params.len)
	for p in ty.params:
		parts.push(try g.keptTypeRef(p, asks))
	if ty.decl is d:
		if i64(d) < g.keptIr.nodes:
			parts.extend([1, i64(d)])
		elif g.keptIr.entry.planning and g.c.nodes[d].origin() == none:
			parts.push(4)   # a type the program declares, found by its name
		elif g.c.nodes[d].origin() is tmpl:
			# an instance of a kept stages' generic struct or enum: its template and arguments
			if i64(tmpl) >= g.keptIr.nodes: return none
			args = g.c.nodes[d].ints().copy()
			parts.extend([2, i64(tmpl), args.len])
			for a in args:
				parts.push(try g.keptTypeRef(a, asks))
		else:
			# a struct of the program's own: its fields' types, the struct found again by its name
			if d in keptOwnOpen: return none   # (one that holds itself)
			fields = try g.ownStructFields(d)
			keptOwnOpen.push(d)
			refs = fields.map(g.keptTypeRef(it, asks))
			keptOwnOpen.pop()
			parts.extend([3, fields.len])
			for r in refs:
				parts.push(try r)
	else:
		parts.push(0)
	asks.push(
		KeptAsk(keptType, "{ty.name}\t{ty.display}\t{ty.definedName}", types = parts, off = i64(id))
	)
	-1 - (asks.len - 1)

# the program's own structs keptTypeRef is naming the fields of
mut keptOwnOpen NodeId[] = []

# the types of the fields of d, a struct the program declares that a kept form may name by them:
# not generic, without a drop function, its fields' types resolved by the check; none for another
fn ownStructFields(g Gen, d NodeId) TypeId[]?:
	n = g.c.nodes[d]
	if n.kind != nStructDecl or not n.names().isEmpty or n.hasFlag(flagDrop): return none
	fields = []
	for f in n.kids(g.c.kidIds):
		fields.push(try g.c.nodes[g.c.nodes[f].types()[0]].ty)
	fields

# the struct of the program's own named name whose fields are of those types, if there is one
fn ownStructNamed(g Gen, name str, fields TypeId[]) NodeId?:
	for d in g.c.decls:
		if i64(d) < g.keptIr.nodes or g.c.nodes[d].text != name: continue
		if g.ownStructFields(d) is own and own == fields: return d
	none

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
fn keptTypeFound(g Gen, ask KeptAsk, found i64[]):
	p = ask.types
	if p[0] == keptFreshType:
		return g.c.nodes[keptNodeOf(p[1], NodeId(0), [], g.keptIr.entry.taking)].ty
	names = ask.text.split("\t")
	params = []
	n = p[13]
	for k in 0..n:
		params.push(try keptPartOf(p[14 + k], found))
	at = 14 + n
	decl NodeId? = none
	if p[at] == 1:
		decl = NodeId(p[at + 1])
	elif p[at] == 2:
		args = []
		for k in 0..p[at + 2]:
			args.push(try keptPartOf(p[at + 3 + k], found))
		tmpl = NodeId(p[at + 1])
		decl = g.c.madeInstanceAsked(tmpl, args) ?? g.c.madeInstanceNamed(tmpl, args) ?? return none
	elif p[at] == 4:
		decl = try g.ownTypeNamed(names[0])
	elif p[at] == 3:
		fields = []
		for k in 0..p[at + 1]:
			fields.push(try keptPartOf(p[at + 2 + k], found))
		decl = try g.ownStructNamed(names[0], fields)
	defined NodeId? = none
	if p[12] == keptOwnNamed:
		defined = try g.ownTypeNamed(names[2])
	elif p[12] != keptNoPart:
		defined = NodeId(p[12])
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
		defined,
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
fn keptAskType(r i64, found i64[]):
	keptPartOf(r, found) ?? tyUnit

fn flagOf(b bool):
	1 if b else 0
