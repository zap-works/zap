# The nodes the loader made wait apart from the checker's until their stage is checked: a stage's
# nodes go in after those of the stages before it and of what their check made, so a stage's
# nodes and types are numbered alike whatever stages come after it, and a kept stage
# (keptstages.zap) is the same in every program that begins with it.

# what the loader made, as it numbered it, and where each node went
import shader

type LoadedNodes:
	nodes Node[]   # a node taken out once it went in
	slot i64[]   # where each node waits in nodes
	at i64[]   # its place among the checker's, -1 while it waits
	owner i64[]   # the stage it goes in with, -1 none
	byStage i64[,]   # each stage's nodes, in their order
	decls NodeId[]
	modules Module[]
	tests NodeId[]
	bodies {NodeId: NodeId}   # numberBodies as parsed
	shaders LoadedShader[]   # preparedShaders as linked

type LoadedShader:
	call NodeId
	prepared shader.Prepared

# what prog's loader made taken out of it, each node given the stage that first reaches it: from
# the stage's declarations, the imports of its modules, the bodies kept of its functions and, the
# last stage's, the tests
fn takeLoaded(mut prog Program, stages CheckStage[]):
	loaded = LoadedNodes(
		nodes = move prog.nodes,
		slot = [],
		at = [],
		owner = [],
		byStage = [],
		decls = move prog.decls,
		modules = move prog.modules,
		tests = move prog.tests,
		bodies = {},
		shaders = []
	)
	for f, body in numberBodies:
		if i64(f) < loaded.nodes.len and i64(body) < loaded.nodes.len:   # (an earlier program's left out)
			loaded.bodies[f] = body
	for (call, prepared) in preparedShaders:
		loaded.shaders.push(LoadedShader(call, prepared.copy()))
	prog.nodes = []
	prog.decls = []
	prog.modules = []
	prog.tests = []
	numberBodies = {}
	preparedShaders = []
	loaded.slot = (0..loaded.nodes.len).map(it)
	loaded.at = fill(loaded.nodes.len, -1)
	loaded.owner = fill(loaded.nodes.len, -1)
	declsAt = 0
	modulesAt = 0
	for i, s in stages:
		loaded.byStage.push([])
		if s.done: continue
		last = i == stages.len - 1
		roots = loaded.decls[declsAt..(len if last else s.decls)].copy()
		for m in loaded.modules[modulesAt..(len if last else s.modules)]:
			roots.extend(m.imports)
		if last: roots.extend(loaded.tests)
		loaded.own(roots, i)
		for f in loaded.bodies.keys():
			if loaded.owner[f] == i: loaded.own([loaded.bodies.get(f) ?? continue], i)
		declsAt = s.decls
		modulesAt = s.modules
	for e in 0..loaded.nodes.len:
		if loaded.owner[e] >= 0: loaded.byStage[loaded.owner[e]].push(e)
	loaded

# the nodes under the roots that no stage holds yet given to stage i
fn own(mut loaded LoadedNodes, roots NodeId[], i i64):
	open = roots.map(i64(it))
	while open.pop() is e:
		if loaded.owner[e] >= 0: continue
		loaded.owner[e] = i
		for k in loaded.nodes[e].kids: open.push(i64(k))
		for k in loaded.nodes[e].sub: open.push(i64(k))
		for k in loaded.nodes[e].types: open.push(i64(k))
		if loaded.nodes[e].origin is o: open.push(i64(o))
		if loaded.nodes[e].kind == nArm and loaded.nodes[e].ival != 0:
			open.push(loaded.nodes[e].ival)

# stage i's nodes, modules and declarations put after the checker's (a module it holds already
# left out), then what names its nodes renumbered: the bodies kept, the shaders. A stage with more
# nodes than the stages after it (the last, a recompiled game's module) has its nodes put in place
# in the loader's list when they fit there, which becomes the checker's, the nodes still waiting
# put apart first: the program's nodes are never in two lists at once.
fn admitStage(
	mut c Checker,
	mut loaded LoadedNodes,
	i i64,
	decls NodeId[],
	modules Module[],
	last bool
):
	ids = loaded.byStage[i].copy()
	for k, e in ids:
		loaded.at[e] = c.nodes.len + k
	if ids.len > loaded.waitingAfter(i) and c.nodes.len + ids.len <= loaded.nodes.len:
		c.takeLoadedNodes(loaded, ids, i)
	else:
		for e in ids:
			c.nodes.push(loaded.movedNode(e))
	for m in modules:
		if moduleIndex(c.modules, m.id) >= 0: continue
		moved = m.copy()
		moved.imports = m.imports.map(loaded.placeOf(it))
		c.modules.push(moved)
	for d in decls:
		c.addDecl(loaded.placeOf(d))
	for f in loaded.bodies.keys():
		if loaded.owner[f] == i:
			numberBodies[loaded.placeOf(f)] = loaded.placeOf(loaded.bodies.get(f) ?? continue)
	for s in loaded.shaders:
		if loaded.owner[s.call] == i:
			preparedShaders.push((loaded.placeOf(s.call), s.prepared.copy()))

# how many nodes wait for the stages after stage i
fn waitingAfter(loaded LoadedNodes, i i64):
	n = 0
	for j in i + 1..loaded.byStage.len:
		n += loaded.byStage[j].len
	n

# The nodes ids (ascending) of stage i moved to their places past the checker's within loaded's
# list, the checker's nodes put before them, and that list the checker's; the nodes of the stages
# after it, put apart before, loaded's list then. A node's place less its own grows with its index:
# those that go down move first, in order, then those that go up, from the last, so none is
# written over before it moves.
fn takeLoadedNodes(mut c Checker, mut loaded LoadedNodes, ids i64[], i i64):
	apart = []
	for j in i + 1..loaded.byStage.len:
		for e in loaded.byStage[j]:
			apart.push(move loaded.nodes[loaded.slot[e]])
			loaded.slot[e] = apart.len - 1
	n0 = c.nodes.len
	down = ids.len
	for k, e in ids:
		if loaded.slot[e] >= n0 + k:
			down = k
			break
	for k in down..ids.len:
		loaded.nodes[n0 + k] = loaded.movedNode(ids[k])
	k = down - 1
	while k >= 0:
		loaded.nodes[n0 + k] = loaded.movedNode(ids[k])
		k -= 1
	loaded.nodes.truncate(n0 + ids.len)
	for j in 0..n0:
		loaded.nodes[j] = move c.nodes[j]
	c.nodes = move loaded.nodes
	loaded.nodes = move apart

# node e taken out, what it names renumbered as the checker's
fn movedNode(mut loaded LoadedNodes, e i64):
	n = move loaded.nodes[loaded.slot[e]]
	for k in 0..n.kids.len:
		n.kids[k] = loaded.placeOf(n.kids[k])
	for k in 0..n.sub.len:
		n.sub[k] = loaded.placeOf(n.sub[k])
	for k in 0..n.types.len:
		n.types[k] = loaded.placeOf(n.types[k])
	if n.origin is o: n.origin = loaded.placeOf(o)
	if n.kind == nArm and n.ival != 0: n.ival = i32(loaded.at[n.ival])
	n

# where the loaded node e went among the checker's
fn placeOf(loaded LoadedNodes, e NodeId):
	if loaded.at[e] < 0: exit(1, "zap: a node of the program was named before its stage")
	NodeId(loaded.at[e])
