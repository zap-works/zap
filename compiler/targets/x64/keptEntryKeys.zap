# The keys of the program's own forms (keptEntry.zap), by declaration as Rust's red-green: each
# name the program declares has a value, the declarations of that name as the check left them
# (without their bodies or places, with the results found for them) and what the program decides
# of those functions (what each changes and does, whether it is taken as a value); a function's
# tree adds to its own hash the values of the names it writes and of the types its nodes were
# given. A declaration checked again whose signature, type and facts come out the same leaves the
# forms that read it kept; one that changes, or a new one of a name a tree writes, makes those
# forms again.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# the value of each name the program's own declarations give (a function's key and a method's
# name too), by nameKey
fn entryNameValues(g Gen):
	facts = g.entryFactsByKey()
	values {i64: i64} = {}
	for d in g.c.decls:
		if i64(d) < g.keptIr.nodes or nodes[d].mod() == "derive": continue
		value = g.nodeDigest(d, false, i64(d))
		if nodes[d].kind == nFnDecl:
			values.addValue(nodes[d].text, mixIn(value, facts.get(nodes[d].text) ?? 0))
			continue
		values.addValue(nodes[d].text, value)
		if nodes[d].text2() != "": values.addValue(nodes[d].text2(), value)
		if nodes[d].kind != nImplDecl: continue
		owner = g.c.findTypeDecl(nodes[d].text) ?? continue
		for m in nodes[d].kids(kidIds):
			key = "{nodes[owner].text}_{nodes[m].text}"
			method = mixIn(g.nodeDigest(m, false, i64(m)), facts.get(key) ?? 0)
			values.addValue(key, method)
			values.addValue(nodes[m].text, method)
	values

fn addValue(mut values {i64: i64}, name str, value i64):
	values[nameKey(name)] = mixIn(values.get(nameKey(name)) ?? 0, value)

# what the program decides of each of its own functions, by key: the same in any order
fn entryFactsByKey(g Gen):
	facts {str: i64} = {}
	for name in g.fnValueNames.keys():
		facts.xorFact(name, "value")
	for key, paths in g.c.effects:
		colon = key.indexOf(":") ?? continue
		d = i64.parse(key[..colon]) ?? continue
		if d >= g.keptIr.nodes and g.keptIr.entry.names.get(NodeId(d)) is name:
			facts.xorFact(name, "{key[colon..]} {paths.join(" ")}")
	for d, bits in g.c.fnEffects:
		if i64(d) >= g.keptIr.nodes and g.keptIr.entry.names.get(d) is name:
			facts.xorFact(name, "does {bits}")
	facts

fn xorFact(mut facts {str: i64}, name str, line str):
	facts[name.copy()] = (facts.get(name) ?? 0) ^ (line.hash() & hashMask)

# the names d's tree writes and the program's types its nodes were given, each with its value
# (names and values by their names' hashes): what its check and lowering read of the other
# declarations; closures the names each type is made of, found once a build
fn treeReads(g Gen, d NodeId, values {i64: i64}, mut closures {i64: i64[]}):
	names {i64: bool} = {}
	types {i64: bool} = {}
	g.noteTreeReads(d, names, types)
	for t in types.keys():
		if t not in closures: closures[t] = g.typeNames(TypeId(t))
		for name in closures[t]:
			names[name] = true
	h = 0
	for name in names.keys():
		h ^= mixIn(name, values.get(name) ?? 0)
	h

fn noteTreeReads(g Gen, e NodeId, mut names {i64: bool}, mut types {i64: bool}):
	text = nodes[e].text
	if text != "" and not text.startsWith("$"): names[nameKey(text)] = true   # (a name the
	# parser made names no declaration)
	if nodes[e].ty is t and i64(t) >= g.keptIr.types: types[i64(t)] = true
	for k in nodes[e].kids(kidIds):
		g.noteTreeReads(k, names, types)
	for t in nodes[e].types():
		g.noteTreeReads(t, names, types)
	for s in nodes[e].sub():
		g.noteTreeReads(s, names, types)

# a name as treeReads keeps it
fn nameKey(name str):
	name.hash() & hashMask

# the names of the program's own declarations type t is made of
fn typeNames(g Gen, t TypeId):
	names {i64: bool} = {}
	seen {i64: bool} = {}
	g.addTypeNames(t, seen, names)
	names.keys()

fn addTypeNames(g Gen, t TypeId, mut seen {i64: bool}, mut names {i64: bool}):
	if i64(t) < g.keptIr.types or i64(t) in seen: return
	seen[i64(t)] = true
	for part in [tys[t].inner, tys[t].err, tys[t].val, tys[t].ret, tys[t].under]:
		if part is p: g.addTypeNames(p, seen, names)
	for p in tys[t].params:
		g.addTypeNames(p, seen, names)
	if tys[t].defined is d and i64(d) >= g.keptIr.nodes: names[nameKey(nodes[d].text)] = true
	decl = tys[t].decl ?? return
	if i64(decl) < g.keptIr.nodes: return
	names[nameKey(nodes[decl].text)] = true
	if nodes[decl].origin() is tmpl: names[nameKey(nodes[tmpl].text)] = true
	for a in nodes[decl].ints():
		g.addTypeNames(a, seen, names)
	if nodes[decl].kind != nStructDecl: return
	for f in nodes[decl].kids(kidIds):
		if not nodes[f].types().isEmpty and nodes[nodes[f].types()[0]].ty is ft:
			g.addTypeNames(ft, seen, names)
