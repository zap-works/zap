# A kept stage's state written out and read back (keptstages.zap): the checker's nodes (as the
# parse cache writes them, numbered from the first, the bodies that wait apart: keptbodies.zap),
# declarations, modules, instances, types and
# the tables a later stage or the backend reads, then what the compiler keeps beside the checker
# (the types' index, the bodies kept of functions with number parameters). Every number is the
# checker's own: a kept state is the first stages of every program that reads it, so nothing is
# renumbered.

# long: one line a table, written and read in the same order
fn keptBytes(c Checker, stages CheckStage[]) u8[]?:
	out u8[] = []
	if not out.pushKeptNodes(c): return none
	out.pushIds(c.decls, 0)
	out.pushVarint(c.modules.len)
	for m in c.modules:
		out.pushModule(m)
	out.pushVarint(c.instances.len)
	for gi in c.instances:
		out.pushInstance(gi)
	out.pushVarint(c.types.len)
	for t in c.types:
		out.pushTy(t)
	out.pushVarint(stages.len)
	for s in stages:
		out.pushText(s.name)
		out.pushVarint(s.decls)
		out.pushVarint(s.modules)
		out.pushVarint(s.key)
		out.pushVarint(s.nodes)
		out.pushVarint(s.types)
		out.pushText(s.file)
	out.pushTypeIds(c.deriveTypes)
	out.pushInts(c.deriveKinds)
	out.pushInts(c.deriveDone)
	out.pushNamedNodes(c.boundFns)
	out.pushNamedNodes(c.boundCalls)
	out.pushNodeInts(c.fnEffects)
	out.pushPaths(c.effects)
	out.pushPaths(c.reads)
	out.pushPaths(c.valueEffects)
	out.pushVarint(c.layouts.len)
	for d, offsets in c.layouts:
		out.pushVarint(i64(d))
		out.pushInts(offsets)
	out.pushVarint(c.views.len)
	for d, view in c.views:
		out.pushVarint(i64(d))
		out.pushVarint(1 if view else 0)
	out.pushVarint(c.madeAsked.len)
	for key, made in c.madeAsked:
		out.pushVarint(key)
		out.pushIds(made, 0)
	out.pushTypeIds(c.aliasTy)
	out.pushTexts(c.aliasBounds)
	out.pushTexts(c.aliasFn)
	out.pushVarint(c.fieldwise.len)
	for f in c.fieldwise:
		out.pushVarint(f.derived)
		out.pushText(f.method)
		out.pushText(f.shape)
	out.pushVarint(c.fieldwiseDone)
	out.pushVarint(c.gradAsks.len)
	for g in c.gradAsks:
		out.pushVarint(i64(g.fd))
		out.pushInts(g.active.map(1 if it else 0))
		out.pushVarint(1 if g.top else 0)
	out.pushVarint(c.gradDone)
	out.pushInts(c.gradHelpers)
	out.pushVarint(c.gradHelpersDone)
	out.pushVarint(c.lentChecks.len)
	for l in c.lentChecks:
		out.pushLentCheck(l)
	out.pushVarint(c.arenaCalls.len)
	for a in c.arenaCalls:
		out.pushVarint(i64(a.stmt))
		out.pushVarint(i64(a.decl))
	out.pushVarint(c.rowFunctions.len)
	for f in c.rowFunctions:
		out.pushVarint(i64(f.decl))
		out.pushVarint(i64(f.origin))
		out.pushVarint(typeNumber(f.fields))
	out.pushVarint(c.rangeTypes.len)
	for name, t in c.rangeTypes:
		out.pushText(name)
		out.pushVarint(i64(t))
	out.pushVarint(c.mutParams.len)
	for name, mask in c.mutParams:
		out.pushText(name)
		out.pushVarint(mask)
	out.pushVarint(c.mutParamsTo)
	out.pushVarint(c.mutParamsStage)
	out.pushNodeInts(c.resultState)
	out.pushNodeNodes(c.methodImpl)
	out.pushNodeInts(c.receiverState)
	out.pushNodeNodes(c.receiverOf)
	out.pushVarint(c.receiverReaders.len)
	for d, readers in c.receiverReaders:
		out.pushVarint(i64(d))
		out.pushIds(readers, 0)
	out.pushIds(c.receiverStale, 0)
	out.pushIds(c.receiverAgain, 0)
	out.pushVarint(c.errorsMet)
	out.pushVarint(c.lambdaCount)
	out.pushVarint(c.safeCallCount)
	out.pushVarint(typeIndex.len)
	for h, t in typeIndex:
		out.pushVarint(h)
		out.pushVarint(i64(t))
	out.pushVarint(numberBodies.len)
	for f, body in numberBodies:
		out.pushVarint(i64(f))
		out.pushVarint(i64(body))
	out.pushVarint(1 if dropTypesSeen else 0)
	out

# the checker the bytes hold (its global scope entered) with its stages, the types' index and the
# bodies kept of functions with number parameters; none when they are cut short
# long: one line a table, read in the order keptBytes writes them
fn keptRead(mut r Reader) KeptStages?:
	prog = newProgram("")
	waiting = r.readKeptNodes(prog.nodes)
	prog.decls = r.readIds(0)
	loop r.count():
		prog.modules.push(r.readModule())
	loop r.count():
		prog.instances.push(r.readInstance())
	prog.types = []
	loop r.count():
		prog.types.push(r.readTy())
	stages = []
	loop r.count():
		name = r.readText()
		decls = r.varint()
		modules = r.varint()
		key = r.varint()
		nodes = r.varint()
		types = r.varint()
		file = r.readText()
		stages.push(CheckStage(name, decls, modules, done = true, key, nodes, types, file))
	prog.derived = r.readTypeIds()
	if r.short: return none
	c = prog.newChecker()
	c.enterScope()
	c.deriveKinds = r.readInts()
	c.deriveDone = r.readInts()
	c.boundFns = r.readNamedNodes()
	c.boundCalls = r.readNamedNodes()
	c.fnEffects = r.readNodeInts()
	c.effects = r.readPaths()
	c.reads = r.readPaths()
	c.valueEffects = r.readPaths()
	loop r.count():
		d = NodeId(r.varint())
		c.layouts[d] = r.readInts()
	loop r.count():
		d = NodeId(r.varint())
		c.views[d] = r.varint() == 1
	loop r.count():
		key = r.varint()
		c.madeAsked[key] = r.readIds(0)
	c.aliasTy = r.readTypeIds()
	c.aliasBounds = r.readTexts()
	c.aliasFn = r.readTexts()
	loop r.count():
		derived = r.varint()
		method = r.readText()
		c.fieldwise.push(FieldwiseAsk(derived, method, shape = r.readText()))
	c.fieldwiseDone = r.varint()
	loop r.count():
		fd = NodeId(r.varint())
		active = r.readInts().map(it == 1)
		c.gradAsks.push(GradAsk(fd, active, top = r.varint() == 1))
	c.gradDone = r.varint()
	c.gradHelpers = r.readInts()
	c.gradHelpersDone = r.varint()
	loop r.count():
		c.lentChecks.push(r.readLentCheck())
	loop r.count():
		stmt = NodeId(r.varint())
		c.arenaCalls.push(ArenaCall(stmt, decl = NodeId(r.varint())))
	loop r.count():
		decl = NodeId(r.varint())
		origin = NodeId(r.varint())
		c.rowFunctions.push(RowFunction(decl, origin, fields = numberType(r.varint())))
	loop r.count():
		name = r.readText()
		c.rangeTypes[name] = TypeId(r.varint())
	loop r.count():
		name = r.readText()
		c.mutParams[name] = r.varint()
	c.mutParamsTo = r.varint()
	c.mutParamsStage = r.varint()
	c.resultState = r.readNodeInts()
	c.methodImpl = r.readNodeNodes()
	c.receiverState = r.readNodeInts()
	c.receiverOf = r.readNodeNodes()
	loop r.count():
		d = NodeId(r.varint())
		c.receiverReaders[d] = r.readIds(0)
	c.receiverStale = r.readIds(0)
	c.receiverAgain = r.readIds(0)
	c.errorsMet = r.varint()
	c.lambdaCount = r.varint()
	c.safeCallCount = r.varint()
	index {i64: TypeId} = {}
	loop r.count():
		h = r.varint()
		index[h] = TypeId(r.varint())
	bodies {NodeId: NodeId} = {}
	loop r.count():
		f = NodeId(r.varint())
		bodies[f] = NodeId(r.varint())
	drops = r.varint() == 1
	if r.short: return none
	KeptStages(checker = c, stages, index, bodies, drops, waiting)

# a count read, of at most the bytes left (a count past them is a file cut short)
fn count(mut r Reader):
	n = r.varint()
	if n < 0 or n > r.d.len - r.at:
		r.short = true
		return 0
	n

fn pushModule(mut out u8[], m Module):
	out.pushText(m.id)
	out.pushText(m.prefix)
	out.pushText(m.file)
	out.pushIds(m.imports, 0)
	out.pushVarint((1 if m.std else 0) + (2 if m.unit else 0))
	out.pushText(m.expects)

fn readModule(mut r Reader):
	id = r.readText()
	prefix = r.readText()
	file = r.readText()
	imports = r.readIds(0)
	bits = r.varint()
	Module(
		id,
		prefix,
		file,
		imports,
		std = bits & 1 != 0,
		unit = bits & 2 != 0,
		expects = r.readText()
	)

fn pushInstance(mut out u8[], gi GenInst):
	out.pushVarint(i64(gi.fnDecl))
	out.pushVarint(i64(gi.decl))
	out.pushText(gi.mangle)
	out.pushTexts(gi.sub.names)
	out.pushTypeIds(gi.sub.types)
	out.pushText(gi.site)
	out.pushTypeIds(gi.asked)
	out.pushVarint(1 if gi.checked else 0)
	out.pushVarint(gi.end)

fn readInstance(mut r Reader):
	fnDecl = NodeId(r.varint())
	decl = NodeId(r.varint())
	mangle = r.readText()
	names = r.readTexts()
	sub = Subst(names, types = r.readTypeIds())
	site = r.readText()
	asked = r.readTypeIds()
	checked = r.varint() == 1
	GenInst(fnDecl, decl, mangle, sub, site, asked, checked, end = r.varint())

fn pushTy(mut out u8[], t Ty):
	out.pushVarint(t.kind)
	out.pushVarint(t.bits)
	out.pushVarint(
		(1 if t.isSigned else 0) + (2 if t.counted else 0) + (4 if t.ranged else 0) +
			(8 if t.closed else 0)
	)
	out.pushText(t.name)
	out.pushText(t.display)
	out.pushVarint(nodeNumber(t.decl))
	out.pushVarint(typeNumber(t.inner))
	out.pushVarint(typeNumber(t.err))
	out.pushVarint(typeNumber(t.val))
	out.pushTypeIds(t.params)
	out.pushVarint(typeNumber(t.ret))
	out.pushText(t.param)
	out.pushVarint(t.lo)
	out.pushVarint(t.hi)
	out.pushVarint(nodeNumber(t.defined))
	out.pushVarint(typeNumber(t.under))
	out.pushText(t.definedName)

fn readTy(mut r Reader):
	t = blankTy(r.varint())
	t.bits = r.varint()
	bits = r.varint()
	t.isSigned = bits & 1 != 0
	t.counted = bits & 2 != 0
	t.ranged = bits & 4 != 0
	t.closed = bits & 8 != 0
	t.name = r.readText()
	t.display = r.readText()
	t.decl = numberNode(r.varint())
	t.inner = numberType(r.varint())
	t.err = numberType(r.varint())
	t.val = numberType(r.varint())
	t.params = r.readTypeIds()
	t.ret = numberType(r.varint())
	t.param = r.readText()
	t.lo = r.varint()
	t.hi = r.varint()
	t.defined = numberNode(r.varint())
	t.under = numberType(r.varint())
	t.definedName = r.readText()
	t

fn pushLentCheck(mut out u8[], l LentCheck):
	out.pushText(l.file)
	out.pushVarint(l.line)
	out.pushVarint(l.col)
	out.pushText(l.lent)
	out.pushVarint(i64(l.callee))
	out.pushText(l.param)
	out.pushText(l.arg)
	out.pushText(l.message)
	out.pushVarint((1 if l.whole else 0) + (2 if l.headersKept else 0))

fn readLentCheck(mut r Reader):
	file = r.readText()
	line = r.varint()
	col = r.varint()
	lent = r.readText()
	callee = NodeId(r.varint())
	param = r.readText()
	arg = r.readText()
	message = r.readText()
	bits = r.varint()
	LentCheck(
		file,
		line,
		col,
		lent,
		callee,
		param,
		arg,
		message,
		whole = bits & 1 != 0,
		headersKept = bits & 2 != 0
	)

# a node's number + 1, 0 for none (as typeNumber writes a type)
fn nodeNumber(d NodeId?):
	if d is d: i64(d) + 1 else: 0

fn numberNode(n i64) NodeId?:
	NodeId(n - 1) if n > 0 else none

fn pushTypeIds(mut out u8[], ts TypeId[]):
	out.pushVarint(ts.len)
	for t in ts:
		out.pushVarint(i64(t))

fn readTypeIds(mut r Reader):
	out = []
	loop r.count():
		out.push(TypeId(r.varint()))
	out

fn pushInts(mut out u8[], xs i64[]):
	out.pushVarint(xs.len)
	for x in xs:
		out.pushVarint(x)

fn readInts(mut r Reader):
	out = []
	loop r.count():
		out.push(r.varint())
	out

fn pushNamedNodes(mut out u8[], m {str: NodeId}):
	out.pushVarint(m.len)
	for name, d in m:
		out.pushText(name)
		out.pushVarint(i64(d))

fn readNamedNodes(mut r Reader):
	out {str: NodeId} = {}
	loop r.count():
		name = r.readText()
		out[name] = NodeId(r.varint())
	out

fn pushNodeInts(mut out u8[], m {NodeId: i64}):
	out.pushVarint(m.len)
	for d, x in m:
		out.pushVarint(i64(d))
		out.pushVarint(x)

fn readNodeInts(mut r Reader):
	out {NodeId: i64} = {}
	loop r.count():
		d = NodeId(r.varint())
		out[d] = r.varint()
	out

fn pushNodeNodes(mut out u8[], m {NodeId: NodeId}):
	out.pushVarint(m.len)
	for d, e in m:
		out.pushVarint(i64(d))
		out.pushVarint(i64(e))

fn readNodeNodes(mut r Reader):
	out {NodeId: NodeId} = {}
	loop r.count():
		d = NodeId(r.varint())
		out[d] = NodeId(r.varint())
	out

fn pushPaths(mut out u8[], m {str: str[]}):
	out.pushVarint(m.len)
	for name, paths in m:
		out.pushText(name)
		out.pushTexts(paths)

fn readPaths(mut r Reader):
	out {str: str[]} = {}
	loop r.count():
		name = r.readText()
		out[name] = r.readTexts()
	out
