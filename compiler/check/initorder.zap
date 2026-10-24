# The order module variables get their initial values: a variable whose initializer reads another
# (directly or through the functions it calls) comes after it, whichever file of the module holds
# each; variables that read none keep the order declared. Initializers that read each other in a
# circle have no order and are an error naming one of them.

alias nodes = c.nodes

# the module variables (by index of vars, byName their names') the initializer of vars[v] reads:
# the names in its expression and in the bodies of the functions it reaches (but those below node
# below), each body once
fn initReads(mut c Checker, vars NodeId[], byName {str: i64}, v i64, below i64):
	mod = c.curMod
	file = c.curFile.copy()
	c.enterModuleOf(vars[v])
	seen {NodeId: bool} = {}
	reads = []
	c.collectInitReads(nodes[vars[v]].kids[0], byName, seen, reads, below)
	c.curMod = mod
	c.curFile = file
	reads

fn collectInitReads(
	mut c Checker,
	e NodeId,
	byName {str: i64},
	mut seen {NodeId: bool},
	mut reads i64[],
	below i64
):
	k = nodes[e].kind
	if k == nIdent:
		if byName.get(nodes[e].text) is at:
			if at not in reads: reads.push(at)
		elif c.lookupDecl(nFnDecl, "", nodes[e].text, nodes[e].line, nodes[e].col) is fd:
			c.collectFunctionReads(fd, byName, seen, reads, below)
	if k == nCall and c.calledDecl(e) is fd:
		c.collectFunctionReads(fd, byName, seen, reads, below)
	for kid in nodes[e].kids.copy():
		c.collectInitReads(kid, byName, seen, reads, below)
	for b in nodes[e].sub.copy():
		c.collectInitReads(b, byName, seen, reads, below)

fn collectFunctionReads(
	mut c Checker,
	fd NodeId,
	byName {str: i64},
	mut seen {NodeId: bool},
	mut reads i64[],
	below i64
):
	if i64(fd) < below or fd in seen or nodes[fd].sub.isEmpty: return
	seen[fd] = true
	mod = c.curMod
	file = c.curFile.copy()
	c.enterModuleOf(fd)
	c.collectInitReads(nodes[fd].sub[0], byName, seen, reads, below)
	c.curMod = mod
	c.curFile = file

# vars in the order their initializers can run (each after those it reads), and the first
# variable found on a circle of reads (empty when there is no circle); the functions below node
# below are not walked (they read none of vars)
fn initOrder(mut c Checker, vars NodeId[], below i64 = 0):
	byName {str: i64} = {}
	for i, d in vars:
		byName[nodes[d].text.copy()] = i
	reads = []
	for v in 0..vars.len:
		reads.push(c.initReads(vars, byName, v, below))
	state i64[] = zeros(vars.len)   # 0 not seen, 1 on the path, 2 placed
	order = []
	circle = []
	for v in 0..vars.len:
		visitInit(vars, reads, v, state, order, circle)
	order, circle

fn visitInit(
	vars NodeId[],
	reads i64[,],
	v i64,
	mut state i64[],
	mut order NodeId[],
	mut circle NodeId[]
):
	if state[v] == 2: return
	if state[v] == 1:
		if circle.isEmpty: circle.push(vars[v])
		return
	state[v] = 1
	for w in reads[v]:
		if w != v: visitInit(vars, reads, w, state, order, circle)
		elif circle.isEmpty: circle.push(vars[v])
	state[v] = 2
	order.push(vars[v])

# a module variable whose initializer reads itself, or another that reads it back, is an error;
# those of stages whose variables a build with the same found on no circle (below, their nodes)
# are left out, as the functions they declare: they name no variable of the stages after
fn checkInitCycles(mut c Checker, below i64):
	vars = []
	for d in c.decls:
		if i64(d) >= below and nodes[d].kind == nConstDecl and not nodes[d].kids.isEmpty and
			not nodes[d].hasFlag(flagOrdered) and not c.constantLiteral(nodes[d].kids[0]):
			vars.push(d)
	_, circle = c.initOrder(vars, below)
	if not circle.isEmpty:
		d = circle[0]
		name = nodes[d].text.split("__")
		c.errors += 1
		errorAtFile(
			nodes[d].file(),
			nodes[d].line,
			nodes[d].col,
			compileError("InitCycle", [name[len - 1].copy()])
		)
