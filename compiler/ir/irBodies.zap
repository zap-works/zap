# Bodies inlined once and copied: a call's body is lowered from its source at the first two calls
# alike in a function; when both gave the same form and changed nothing else the lowering keeps,
# it is copied from then on (its vregs and blocks renumbered, its parameters' leaves the call's)
# instead of lowered again. Calls are alike when what the lowering of a body reads of the state
# around it is the same (irBodyKey). A body whose parameters are the caller's places (a mut local,
# an address), that takes a receiver or a given function, or whose result goes to a place of the
# caller's is always lowered from its source.

alias nodes = g.c.nodes
alias tys = g.c.types

# A body's form as lowered at a call, numbered from where it began: vreg r is the call's input r
# (its parameters' leaves, in order) below `inputs`, else the (r - inputs)-th it made; block 0
# is the block it began in, block k the k-th it made.
type IrBody:
	trusted bool = false   # lowered twice alike: copied from now on
	inputs i64
	head IrInst[]   # added to the block it began in
	blocks IrBlock[]
	classes i64[]
	leafTypes i64[]   # the leaf types of the vregs it made, as far as it typed them
	loops IrLoop[]
	switches IrSwitch[]
	end i64   # the block it ends in
	result i64[]
	named i64[]   # pairs: a vreg and the node that read it last (lw.namedBy)
	line i64   # where the lowering stands after it, -1 where it began
	col i64

# where the lowering stood when a body began
type IrBodyStart:
	inputs i64[]
	vregs i64
	blocks i64
	cur i64
	insts i64
	loops i64
	switches i64
	typed i64   # leafTypes' length
	inputTypes i64[]
	inputNames i64[]   # lw.namedBy of each input, -1 for none
	names i64   # lw.namedBy's size
	line i64
	col i64
	kept i64[]   # irBodyKept
	program i64[]   # irBodyShared

# fnd's body in place (irBodyInPlace), copied when it was lowered alike before; inputs its
# parameters' leaves when it may be copied, else none
fn irBodyOnce(
	mut g Gen,
	mut lw IrLower,
	fnd NodeId,
	inputs i64[,]?,
	written bool,
	into i64
):
	g.c.readBody(fnd)
	body = nodes[fnd].sub()[0]
	rt = g.c.fnRetType(fnd)
	runtime = g.irOfRuntime(fnd)
	leaves = inputs ?? return g.irBodyInPlace(lw, body, rt, runtime, written, into)
	flat = []
	for l in leaves:
		flat.extend(l)
	key = g.irBodyKey(lw, fnd, written)
	if lw.bodies.get(key) is seen and seen.trusted: return lw.irBodyCopy(seen, flat)
	start = g.irBodyStartOf(lw, flat)
	result = g.irBodyInPlace(lw, body, rt, runtime, written, into)
	if not lw.ok: return result
	taken = g.irBodyTaken(lw, start, result)
	match lw.bodies.get(key):
		seen:
			# the second call alike: copied from now on when it was lowered the same
			same = seen.inputs >= 0 and start.program == g.irBodyShared()
			if taken is t and not irSameBody(seen, t):
				same = false
			lw.bodies[key.copy()] = irBodyNever()
			if same and taken is t:
				lw.bodies[key.copy()] = t
				lw.bodies[key].trusted = true
		none:
			lw.bodies[key.copy()] = taken ?? irBodyNever()
	result

# a body never copied (lowered from its source at every call)
fn irBodyNever():
	IrBody(
		inputs = -1,
		head = [],
		blocks = [],
		classes = [],
		leafTypes = [],
		loops = [],
		switches = [],
		end = 0,
		result = [],
		named = [],
		line = 0,
		col = 0
	)

# what of the lowering's state the lowering of fnd's body reads, beside fnd: its calls inlined
# or not (irInlinesAs), its returns, drops and arenas, the flags its instructions carry
fn irBodyKey(g Gen, lw IrLower, fnd NodeId, written bool):
	top = "-" if lw.rets.isEmpty
		else "{lw.rets[len - 1].runtime} {lw.rets[len - 1].written} {lw.rets[len - 1].lambda}"
	["{fnd}",
		"{written}",
		"{top}",
		"{lw.rets.count(not .lambda)}",
		"{lw.breaks.len}",
		"{lw.inlined > irInlineBlocks}",
		"{lw.keyParts}",
		"{lw.foreign}",
		"{lw.arenas}",
		"{lw.inRegion}",
		"{lw.arenaClean}",
		"{lw.keying}",
		"{lw.choosing}",
		"{lw.conditions}",
		"{lw.seqs.len}",
		"{lw.given.len}",
		"{lw.owned.len}",
		"{lw.moveWritten}",
		"{lw.keepEmptied}",
		"{lw.borrowsNoted}",
		"{lw.hidden}",
		"{lw.regResult}",
		"{lw.firstLocal}",
		"{lw.proven.len}",
		"{lw.checked.len}",
		"{lw.steady.len}",
		"{lw.loopElems.len}",
		"{lw.spills.len}",
		"{lw.armWrites.len}",
		"{lw.mutScalars.len}",
		"{lw.windows.len}",
		"{lw.onceCaptures.len}",
		"{lw.fromBase.len}",
		"{lw.arenaWalk.len}",
		"{lw.keptBlocks.len}",
		"{lw.recycleInto}",
		"{lw.lentTry}",
		"{lw.f.cur == 0}"].join(" ")

# the sizes of the lowering's own state a copied body must leave as it found them
fn irBodyKept(lw IrLower):
	[lw.owned.len,
		lw.literals.len,
		lw.literalWords.len,
		lw.made.len,
		lw.raw.len,
		lw.spills.len,
		lw.checked.len,
		lw.steady.len,
		lw.proven.len,
		lw.keptInner.len,
		lw.keptBlocks.len,
		lw.armWrites.len,
		lw.windows.len,
		lw.onceCaptures.len,
		lw.given.len,
		lw.mutScalars.len,
		lw.loopElems.len,
		lw.fromBase.len,
		lw.arenaWalk.len,
		lw.mutNames.len,
		lw.givenSlots.len,
		lw.places.len,
		lw.wordPlaces.len,
		lw.localLambdas.len,
		lw.f.places.len,
		lw.f.merges.len,
		lw.hidden,
		lw.placed,
		lw.lentTry,
		lw.recycleInto,
		lw.inlined,
		lw.f.blocks[0].insts.len if lw.f.cur != 0 else -1]

# the sizes of the program's state (types, nodes, labels, data, lambdas): a body lowered the
# second time must add nothing to them for its copies to be the same
fn irBodyShared(g Gen):
	[g.irLambdaFns.len,
		g.irLambdaSeq,
		g.irSpans,
		g.irGivenInstances.len,
		tys.len,
		nodes.len,
		g.planned.len,
		g.strOffs.len,
		g.fnLabels.len,
		g.globalsNamed.len,
		g.floatOffs.len,
		g.irCallStores.len]

fn irBodyStartOf(g Gen, lw IrLower, inputs i64[]):
	IrBodyStart(
		inputs = inputs.copy(),
		vregs = lw.f.classes.len,
		blocks = lw.f.blocks.len,
		cur = lw.f.cur,
		insts = lw.f.blocks[lw.f.cur].insts.len,
		loops = lw.f.loops.len,
		switches = lw.f.switches.len,
		typed = lw.f.leafTypes.len,
		inputTypes = inputs.map(lw.f.leafTypes[it] if it < lw.f.leafTypes.len else -1),
		inputNames = inputs.map(lw.namedBy.get(it) ?? -1),
		names = lw.namedBy.len,
		line = lw.line,
		col = lw.col,
		kept = lw.irBodyKept(),
		program = g.irBodyShared()
	)

# the body lowered since start as an IrBody, none when it changed more than the form (or read a
# vreg or a block of the caller's beside its inputs and the block it began in)
fn irBodyTaken(g Gen, lw IrLower, start IrBodyStart, result i64[]) IrBody?:
	f = lw.f
	if lw.irBodyKept() != start.kept or f.blocks[start.cur].insts.len < start.insts: return none
	for i, v in start.inputs:
		if (f.leafTypes[v] if v < f.leafTypes.len else -1) != start.inputTypes[i]: return none
	own = fill(f.classes.len, -1)
	for i, v in start.inputs:
		own[v] = i
	for v in start.vregs..f.classes.len:
		own[v] = v - start.vregs + start.inputs.len
	ways = fill(f.blocks.len, -1)
	ways[start.cur] = 0
	for b in start.blocks..f.blocks.len:
		ways[b] = b - start.blocks + 1
	shift = IrBodyShift(
		own,
		ways,
		switches = -start.switches,
		from = IrBodyPlace(line = start.line, col = start.col),
		to = IrBodyPlace(line = -1, col = -1)
	)
	head = f.blocks[start.cur].insts[start.insts..len].copy()
	blocks = f.blocks[start.blocks..].copy()
	if head.any(not shift.irBodyMaps(it)) or blocks.any(.insts.any(not shift.irBodyMaps(it))):
		return none
	if f.loops[start.loops..].any(shift.ways[.pre] < 0) or result.any(shift.own[it] < 0):
		return none
	named = try g.irBodyNamed(lw, start)
	moved = lw.line != start.line or lw.col != start.col   # (the body's last statement's place)
	IrBody(
		inputs = start.inputs.len,
		head = head.map(shift.irBodyMoved(it)),
		blocks = blocks.map(IrBlock(insts = .insts.map(shift.irBodyMoved(it)), loopTop = .loopTop, cold = .cold)),
		classes = f.classes[start.vregs..].copy(),
		leafTypes = f.leafTypes[start.vregs..].copy() if f.leafTypes.len > start.vregs else [],
		loops = f.loops[start.loops..].map(IrLoop(pre = shift.ways[.pre], blocks = .blocks.map(shift.ways[it]))),
		switches = f.switches[start.switches..].map(
			IrSwitch(values = .values.copy(), targets = .targets.map(shift.ways[it]))
		),
		end = shift.ways[f.cur],
		result = result.map(shift.own[it]),
		named,
		line = lw.line if moved else -1,
		col = lw.col if moved else -1
	)

# the names the body read (lw.namedBy) of its inputs and the vregs it made, as pairs of its vreg
# and the node; none when it wrote another
fn irBodyNamed(g Gen, lw IrLower, start IrBodyStart) i64[]?:
	named = []
	added = 0
	for i, v in start.inputs:
		now = lw.namedBy.get(v) ?? -1
		if now != start.inputNames[i]:
			named.push(i)
			named.push(now)
			if start.inputNames[i] < 0: added += 1
	for v in start.vregs..lw.f.classes.len:
		if lw.namedBy.get(v) is node:
			named.push(v - start.vregs + start.inputs.len)
			named.push(node)
			added += 1
	if lw.namedBy.len != start.names + added or named.any(it == -1): return none
	named

# a body's vregs, blocks and switches renumbered: own (by vreg, -1 none) and ways (by block)
type IrBodyShift:
	own i64[]
	ways i64[]
	switches i64   # added to a switch's number
	# the place the lowering stood at (an instruction put before the body's first statement has
	# its call's), as the body's (-1) or the call's
	from IrBodyPlace
	to IrBodyPlace

type IrBodyPlace:
	line i64
	col i64

# whether shift renumbers every vreg and block inst names
fn irBodyMaps(shift IrBodyShift, inst IrInst):
	if inst.dst >= 0 and (inst.dst >= shift.own.len or shift.own[inst.dst] < 0): return false
	for v in inst.irReads():
		if v >= shift.own.len or shift.own[v] < 0: return false
	if not isTerminator(inst.op): return true
	if inst.op == irSwitch and inst.imm + shift.switches < 0: return false
	(inst.target < 0 or shift.ways[inst.target] >= 0) and
		(inst.other < 0 or shift.ways[inst.other] >= 0)

fn irBodyMoved(shift IrBodyShift, inst IrInst):
	r = inst.irRenamed(shift.own)
	if r.line == shift.from.line and r.col == shift.from.col:
		r.line = i32(shift.to.line)
		r.col = i32(shift.to.col)
	if isTerminator(r.op):
		if r.target >= 0: r.target = shift.ways[r.target]
		if r.other >= 0: r.other = shift.ways[r.other]
		if r.op == irSwitch: r.imm += shift.switches
	r

# whether two bodies' forms are the same
fn irSameBody(a IrBody, b IrBody):
	a.inputs == b.inputs and a.classes == b.classes and a.leafTypes == b.leafTypes and
		a.end == b.end and a.result == b.result and a.named == b.named and a.line == b.line and
		a.col == b.col and irSameInsts(a.head, b.head) and a.blocks.len == b.blocks.len and
		(0..a.blocks.len).all(
			a.blocks[it].loopTop == b.blocks[it].loopTop and
				a.blocks[it].cold == b.blocks[it].cold and
				irSameInsts(a.blocks[it].insts, b.blocks[it].insts)
		) and a.loops.len == b.loops.len and
		(0..a.loops.len).all(
			a.loops[it].pre == b.loops[it].pre and a.loops[it].blocks == b.loops[it].blocks
		) and
		a.switches.len == b.switches.len and
		(0..a.switches.len).all(
			a.switches[it].values == b.switches[it].values and
				a.switches[it].targets == b.switches[it].targets
		)

fn irSameInsts(a IrInst[], b IrInst[]):
	a.len == b.len and (0..a.len).all(a[it].irSameInst(b[it]))

fn irSameInst(a IrInst, b IrInst):
	a.op == b.op and a.irInstNumbers() == b.irInstNumbers() and
		a.irInstFlags() == b.irInstFlags() and
		a.args == b.args and a.key == b.key and a.steady == b.steady and a.foreign == b.foreign

# the body t in place at the block being filled, its inputs' leaves inputs: its result's leaves
fn irBodyCopy(mut lw IrLower, t IrBody, inputs i64[]):
	base = lw.f.classes.len
	own = inputs.copy()
	for i in 0..t.classes.len:
		own.push(base + i)
	ways = [lw.f.cur]
	for k in 0..t.blocks.len:
		ways.push(lw.f.blocks.len + k)
	shift = IrBodyShift(
		own,
		ways,
		switches = lw.f.switches.len,
		from = IrBodyPlace(line = -1, col = -1),
		to = IrBodyPlace(line = lw.line, col = lw.col)
	)
	lw.f.classes.extend(t.classes)
	if not t.leafTypes.isEmpty:
		while lw.f.leafTypes.len < base:
			lw.f.leafTypes.push(-1)
		lw.f.leafTypes.extend(t.leafTypes)
	for inst in t.head:
		lw.f.blocks[lw.f.cur].insts.push(shift.irBodyMoved(inst))
	for b in t.blocks:
		lw.f.blocks.push(
			IrBlock(insts = b.insts.map(shift.irBodyMoved(it)), loopTop = b.loopTop, cold = b.cold)
		)
	for sw in t.switches:
		lw.f.switches.push(
			IrSwitch(values = sw.values.copy(), targets = sw.targets.map(shift.ways[it]))
		)
	for l in t.loops:
		lw.f.loops.push(IrLoop(pre = shift.ways[l.pre], blocks = l.blocks.map(shift.ways[it])))
	lw.f.cur = shift.ways[t.end]
	for i in 0..t.named.len / 2:
		lw.namedBy[shift.own[t.named[2 * i]]] = t.named[2 * i + 1]
	if t.line >= 0:
		lw.line = t.line
		lw.col = t.col
	t.result.map(shift.own[it])
