# The bodies of the kept stages' functions (keptstate.zap) wait in the kept file until a build
# reads them: most of a stage's nodes are its functions' bodies, and a small program lowers,
# inlines, instantiates or looks into few of them (the others' forms are kept lowered, keptir.zap, and
# what the walks of their bodies found is kept beside them, keptfacts.zap). A waiting body's
# nodes are empty (kind 0) in the checker's list until readBody puts them in, where they were.

# the bodies of a kept file that wait: the file's bytes and where each function's nodes are in
# them, and the functions its nodes take as values (noteFnValues', which looks at the nodes past
# them alone)
type WaitingBodies:
	bytes u8[] = []
	at {NodeId: i64} = {}
	nodes i64 = 0
	valueNames str[] = []

# the bodies of the program's kept stages not read yet
mut waitingBodies = WaitingBodies()

# fnd's body put in c's nodes when it waits
fn readBody(mut c Checker, fnd NodeId):
	at = waitingBodies.at.get(fnd) ?? return
	waitingBodies.at.remove(fnd)
	r = Reader(waitingBodies.bytes, at)
	r.readNodeRun(c.nodes)

# fnd's body known read where the nodes cannot be written: a body that waits there is the
# compiler's fault, which ends the build rather than read empty nodes
fn bodyRead(fnd NodeId):
	if waitingBodies.at.get(fnd) != none:
		exit(
			1,
			"zap: the body of function {fnd} was read before the kept file gave it (keptbodies.zap)"
		)

# every body that waits put in c's nodes (a stage after them kept with them)
fn readBodies(mut c Checker):
	for fnd in waitingBodies.at.keys():
		c.readBody(fnd)

# the kept stages' nodes, those of the bodies that may wait (bodiesThatWait) after the others',
# each function's apart (readKeptNodes); false when one names a node before the first
fn pushKeptNodes(mut out u8[], c Checker):
	bodies = c.bodiesThatWait()
	waits = fill(c.nodes.len, false)
	for (_, ids) in bodies:
		for id in ids:
			waits[id] = true
	out.pushVarint(c.nodes.len)
	if not out.pushNodeRun(c.nodes, (0..c.nodes.len).filter(not waits[it])): return false
	out.pushVarint(bodies.len)
	for (fnd, ids) in bodies:
		run u8[] = []
		if not run.pushNodeRun(c.nodes, ids): return false
		out.pushVarint(i64(fnd))
		out.pushVarint(run.len)
		out.extend(run)
	values {str: bool} = {}
	for n in c.nodes:
		if n.kind == nIdent and n.hasFlag(flagFnRef): values[n.text.copy()] = true
	out.pushTexts(values.keys())
	true

# the nodes pushKeptNodes wrote, those of the bodies that wait empty: the bodies' places
fn readKeptNodes(mut r Reader, mut nodes Node[]):
	nodes = fill(r.count(), waitingNode())   # (zero bytes: pages the bodies' places leave untouched)
	r.readNodeRun(nodes)
	out = WaitingBodies(nodes = nodes.len)
	loop r.count():
		fnd = NodeId(r.varint())
		n = r.count()
		out.at[fnd] = r.at
		r.at += n
	out.valueNames = r.readTexts()
	out

# the place of a node whose body waits, of zero bytes (a str moved out of is, an empty literal
# is not), which fill gives untouched
fn waitingNode():
	n = Node(
		kind = 0,
		line = 0,
		col = 0,
		text = "",
		text2 = "",
		origin = NodeId(0),
		kids = [],
		sub = [],
		types = [],
		names = [],
		flags = 0,
		ival = 0,
		ty = TypeId(0)
	)
	move n.text
	move n.text2
	n

# the nodes ids, each after the gap from the one before it, then its record
fn pushNodeRun(mut out u8[], nodes Node[], ids i64[]):
	out.pushVarint(ids.len)
	before = -1
	for id in ids:
		out.pushVarint(id - before - 1)
		before = id
		if not out.pushNodeRecord(nodes, id, 0): return false
	true

# the nodes pushNodeRun wrote put in their places
fn readNodeRun(mut r Reader, mut nodes Node[]):
	before = -1
	loop r.count():
		id = before + 1 + r.varint()
		if id < 0 or id >= nodes.len:
			r.short = true
			return
		nodes[id] = r.readNodeRecord(0)
		before = id

# The bodies of c's functions and methods that only their own nodes name, by function, with the
# nodes of each: a body's tree, and the nodes it names that nothing outside the bodies reaches
# (the checker's, named as a node's origin). A body that another body names into, or that a node
# reached from the declarations and the tables a build reads apart from the bodies (the arena
# calls, the instances, the types) names into, is kept with the other nodes.
fn bodiesThatWait(c Checker):
	fns = c.functionsWithBodies()
	owner = fill(c.nodes.len, -1)
	waits = fill(fns.len, true)
	for k, fnd in fns:
		open = [i64(c.nodes[fnd].sub[0])]
		while open.pop() is e:
			if owner[e] == k: continue
			if owner[e] >= 0:
				waits[owner[e]] = false
				waits[k] = false
				continue
			owner[e] = k
			open.extend(c.heldBy(e))
	# what the tables reach outside the bodies, a declaration's body itself aside
	reached = fill(c.nodes.len, false)
	open = c.namedByTables()
	while open.pop() is e:
		if reached[e]: continue
		if owner[e] >= 0:
			waits[owner[e]] = false
			continue
		reached[e] = true
		for n in c.namedBy(e):
			k = owner[n]
			if k < 0 or not (e == i64(fns[k]) and n == i64(c.nodes[fns[k]].sub[0])): open.push(n)
	# a node a body names that nothing reached is the body's own; one of another body's joins them
	for e in 0..c.nodes.len:
		if owner[e] < 0: continue
		k = owner[e]
		open = c.namedBy(e)
		while open.pop() is n:
			if owner[n] == k or reached[n]: continue
			if owner[n] >= 0:
				waits[owner[n]] = false
				waits[k] = false
				continue
			owner[n] = k
			open.extend(c.namedBy(n))
	ids i64[,] = []
	loop fns.len:
		ids.push([])
	for e in 0..c.nodes.len:
		if owner[e] >= 0 and waits[owner[e]]: ids[owner[e]].push(e)
	out = []
	for k, fnd in fns:
		if waits[k]: out.push((fnd, ids[k].copy()))
	out

# the functions and methods of c that have a body
fn functionsWithBodies(c Checker):
	out = []
	for d in c.decls:
		k = c.nodes[d].kind
		if k == nFnDecl: out.push(d)
		elif k == nImplDecl: out.extend(c.nodes[d].kids)
	out.filter(c.nodes[it].kind == nFnDecl and not c.nodes[it].sub.isEmpty and
			not c.nodes[it].hasFlag(flagExtern))

# the nodes of node e's tree below it
fn heldBy(c Checker, e i64):
	n = c.nodes[e]
	out = n.kids.map(i64(it))
	out.extend(n.sub.map(i64(it)))
	out.extend(n.types.map(i64(it)))
	if n.kind == nArm and n.ival != 0: out.push(n.ival)
	out

# the nodes node e names: those below it and the one it stands for (origin)
fn namedBy(c Checker, e i64):
	out = c.heldBy(e)
	if c.nodes[e].origin is o: out.push(i64(o))
	out

# the nodes the tables a build reads apart from the bodies name
fn namedByTables(c Checker):
	out = c.decls.map(i64(it))
	for f, body in numberBodies:
		out.push(i64(f))
		out.push(i64(body))
	for a in c.arenaCalls:
		out.push(i64(a.stmt))
	for gi in c.instances:
		out.push(i64(gi.fnDecl))
		out.push(i64(gi.decl))
	for m in c.modules:
		out.extend(m.imports.map(i64(it)))
	for t in c.types:
		if t.decl is d: out.push(i64(d))
		if t.defined is d: out.push(i64(d))
	for _, call in c.boundCalls:
		out.push(i64(call))
	for _, made in c.madeAsked:
		out.extend(made.map(i64(it)))
	out
