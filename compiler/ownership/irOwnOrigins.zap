# Where each value of a function points: the origins the ownership checks read (irOwn.zap).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# Where each vreg may point, over the whole function at once (not per point), to a fixed point:
# into the memory of holders (the frame slots, a moved parameter's words, the blocks calls give,
# and what lies outside the function: a parameter's memory, the program's data), directly (an
# address into a slot),
# through what a holder owns (a list's items) or through a borrow stored in its memory.
type IrOrigins:
	holder i64[] = []   # per vreg: the holder whose address it is, or -1
	outside bool[] = []   # per holder: memory outside the function
	mayHold bool[] = []   # per holder: whether its memory may hold borrows (a view, a list of
# references)
	resultBorrows bool[] = []   # per holder: as a call's result, whether it may borrow what the call
# is given (a closure a call gives owns what it captured)
	points i64[,] = []   # per vreg: the holders it may point into, in order
	holds i64[,] = []   # per holder: the holders the borrows in its memory may point into, in order
	reach i64[,] = []   # per vreg: points and, on through holds, what those borrows reach
	reached bool[] = []   # per vreg: whether its reach was found

fn irOriginsOf(mut g Gen, f IrFn):
	nv = f.classes.len
	o = IrOrigins(
		holder = fill(nv, -1),
		outside = [],
		mayHold = [],
		resultBorrows = [],
		points = [],
		holds = []
	)
	loop nv:
		o.points.push([])
	ownerType = fill(nv, -1)   # an owner's type, by its slot's vreg
	for b in f.blocks:
		for inst in b.insts:
			if inst.op == irOwn and inst.a >= 0:
				ownerType[inst.a] = inst.imm
	for b in f.blocks:
		for inst in b.insts:
			d = inst.dst
			# a call's result that may be an address may be a block it made (a closure's
			# environment): memory of its own
			made = d >= 0 and (inst.op == irCall or inst.op == irCallPtr) and
				not g.irHoldsData(f, d)
			if d >= 0 and o.holder[d] < 0 and
				(made or inst.op in [irFrameSlot, irFrameAddr, irParam, irDataAddr]):
				h = o.outside.len
				o.holder[d] = h
				o.outside.push(inst.op == irParam or inst.op == irDataAddr)
				o.mayHold.push(ownerType[d] < 0 or g.irMayHoldBorrows(TypeId(ownerType[d])))
				o.resultBorrows.push(ownerType[d] < 0 or g.irMayBorrow(TypeId(ownerType[d])))
				o.holds.push([])
				o.points[d].push(h)
	changed = true
	while changed:
		changed = false
		for b in f.blocks:
			for inst in b.insts:
				if o.irOriginStep(g, f, inst):
					changed = true
	o.reach = []
	loop nv:
		o.reach.push([])
	o.reached = zeros(nv)
	o

# what inst adds to the origins: whether they grew
fn irOriginStep(mut o IrOrigins, mut g Gen, f IrFn, inst IrInst):
	op = inst.op
	d = inst.dst
	if op == irOwn:
		if inst.b < 0 or inst.a < 0 or o.holder[inst.a] < 0: return false
		return o.points[inst.b].irSetPut(o.holder[inst.a])   # the word is the owner's value
	if op == irCopy and d >= 0 and d < f.leafTypes.len and f.leafTypes[d] == irMovedBytes:
		return o.irPointsThrough(d, inst.a)   # a word given away: what it owns is its own
	if op in [irCopy, irAdd, irSub, irAnd, irOr, irSelect]:
		if d < 0 or g.irHoldsData(f, d): return false
		grew = false
		for v in inst.irReads():
			if o.irPointsAlso(d, v):
				grew = true
		return grew
	if op == irLoad:
		# what memory holds: an address into what the holder owns, or a borrow it keeps
		if d < 0 or inst.size < 8 or (inst.header and inst.imm != 0) or g.irHoldsData(f, d):
			return false
		if d < f.leafTypes.len and f.leafTypes[d] == irMovedBytes:
			return o.irPointsThrough(d, inst.a)   # a word of a value moved out: its own now
		return o.irPointsAlso(d, inst.a) or o.irPointsThrough(d, inst.a)
	if op == irStore:
		# (no memory holds a borrow of itself: a word read from a place and written back, the
		# runtime's numbers in an inlined body, is none)
		if inst.c < 0: return false
		grew = false
		for i in 0..o.points[inst.c].len:
			if o.irHoldOne(inst.a, o.points[inst.c][i]):
				grew = true
		return grew
	if op == irMemCopy and inst.cond == 1 and inst.b >= 0:
		# a value's bytes moved: what it owned is the destination's own, what it borrowed is
		# borrowed there
		held i64[] = []
		for h in o.points[inst.b]:
			held.irSetJoin(o.holds[h])
		return o.irHoldAt(inst.a, held)
	if op == irMemCopy or op == irMemCopyN:
		# bytes copied: what they point into goes along (a window copied out of a list borrows
		# the list)
		return o.irHoldAt(inst.a, o.irBytesOf(inst.b))
	if op == irDeepCopy:
		held i64[] = []
		for h in o.points[inst.b]:
			held.irSetJoin(o.holds[h])
		return o.irHoldAt(inst.a, held)
	if op == irCall or op == irCallPtr:
		# what it is given may come back in its result or go into any place it is given
		reached = []
		for v in inst.args():
			o.irBytesInto(v, reached)
		o.irBytesInto(inst.a, reached)
		grew = false
		borrows = d >= 0 and
			(d >= f.leafTypes.len or f.leafTypes[d] < 0 or g.irMayBorrow(TypeId(f.leafTypes[d])))
		if borrows and not g.irHoldsData(f, d) and o.points[d].irSetJoin(reached):
			grew = true
		if inst.c >= 0:
			for i in 0..o.points[inst.c].len:
				h = o.points[inst.c][i]
				if o.resultBorrows[h] and o.holds[h].irSetJoin(reached):
					grew = true
		# what it may store into: its mut parameters (all it is given, when not known); no memory
		# holds a borrow of itself
		stores = (g.irCallStores.get(inst.key()) ?? -1) if op == irCall else -1
		for i, v in inst.args():
			if v >= 0 and (stores == -1 or i >= 63 or (stores >> i) & 1 != 0) and
				o.irHoldAtApart(v, reached):
				grew = true
		if inst.a >= 0 and (stores == -1 or inst.args().len >= 63 or
				(stores >> inst.args().len) & 1 != 0) and o.irHoldAtApart(inst.a, reached):
			grew = true
		return grew
	false

# v's places added to d's: whether d's grew
fn irPointsAlso(mut o IrOrigins, d i64, v i64):
	if v < 0 or d == v: return false
	grew = false
	for i in 0..o.points[v].len:
		h = o.points[v][i]
		if o.points[d].irSetPut(h):
			grew = true
	grew

# the borrows kept in the memory v points into added to d's places: whether they grew
fn irPointsThrough(mut o IrOrigins, d i64, v i64):
	if v < 0: return false
	grew = false
	for h in o.points[v].copy():
		if o.points[d].irSetJoin(o.holds[h]):
			grew = true
	grew

# what the bytes v points to may point into: the holders' own memory and their borrows
fn irBytesOf(o IrOrigins, v i64):
	if v < 0: return []
	out = o.points[v].copy()
	for h in o.points[v]:
		out.irSetJoin(o.holds[h])
	out

# bytes v points to (irBytesOf) joined into the set out
fn irBytesInto(o IrOrigins, v i64, mut out i64[]):
	if v < 0: return
	out.irSetJoin(o.points[v])
	for h in o.points[v]:
		out.irSetJoin(o.holds[h])

# the memory at address a now may hold a borrow into holder x, unless it points into x itself:
# whether that grew
fn irHoldOne(mut o IrOrigins, a i64, x i64):
	if a < 0 or x in o.points[a]: return false
	grew = false
	for i in 0..o.points[a].len:
		h = o.points[a][i]
		if o.mayHold[h] and o.holds[h].irSetPut(x):
			grew = true
	grew

# irHoldOne of each holder in to
fn irHoldAtApart(mut o IrOrigins, a i64, to i64[]):
	grew = false
	for x in to:
		if o.irHoldOne(a, x):
			grew = true
	grew

# the memory at address a now may hold borrows into the holders in to: whether that grew
fn irHoldAt(mut o IrOrigins, a i64, to i64[]):
	if a < 0 or to.isEmpty: return false
	grew = false
	for h in o.points[a].copy():
		if o.mayHold[h] and o.holds[h].irSetJoin(to):
			grew = true
	grew

# v's reach found (read as o.reach[v]): where it points, and on through the borrows held there
fn irReachOf(mut o IrOrigins, v i64):
	if not o.reached[v]:
		out = o.points[v].copy()
		at = 0
		while at < out.len:
			h = out[at]
			at += 1
			for x in o.holds[h]:
				if x not in out:
					out.push(x)
		o.reach[v] = out
		o.reached[v] = true

# whether an instruction's type is owner type t
fn irSameType(mut g Gen, ty TypeId?, t i64):
	match ty:
		x: isSameType(tys, x, TypeId(t))
		none: false

# whether a value of type t may hold borrows: one that may borrow (irMayBorrow), or a closure
# (its environment may point at what it captured), or a value holding one
fn irMayHoldBorrows(mut g Gen, t TypeId):
	if g.irMayBorrow(t): return true
	open = []
	holds, _ = g.irHoldsClosure(t, open)
	holds

# whether a value of type t may hold a closure, and whether that is known for good: not when a
# type t is inside of (open) was met again (its answer then still to come)
fn irHoldsClosure(mut g Gen, maybeT TypeId?, mut open str[]) (bool, bool):
	t = maybeT ?? return (false, true)
	k = g.tyK(t)
	if k == tFn: return (true, true)
	if k in [tOption, tList, tBox, tArray]: return g.irHoldsClosure(tys[t].inner, open)
	if k == tMap: return g.irHoldsClosure(tys[t].val, open)
	if k == tResult:
		ok, okKnown = g.irHoldsClosure(tys[t].inner, open)
		if ok: return (true, true)
		err, errKnown = g.irHoldsClosure(tys[t].err, open)
		return (err, err or okKnown and errKnown)
	if k != tStruct and k != tEnum: return (false, true)
	name = typeStr(tys, t)
	if g.holdsClosure.get(name) is known: return (known, true)
	if name in open: return (false, false)
	open.push(name.copy())
	fields = []
	sd = declOf(tys, t)
	if k == tStruct:
		for i in 0..g.c.nodes[sd].kids(g.c.kidIds).len:
			fields.push(g.c.structFieldTypeAt(sd, i))
	else:
		for v in nodes[sd].kids(kidIds).copy():
			for fd in nodes[v].kids(kidIds).copy():
				fields.push(g.c.resolveType(nodes[fd].types()[0]))
	holds = false
	known = true
	for ft in fields:
		h, hk = g.irHoldsClosure(ft, open)
		if h:
			holds = true
			break
		known = known and hk
	open.pop()
	known = holds or known or open.isEmpty
	if known and g.c.subst.names.isEmpty:
		g.holdsClosure[name.copy()] = holds
	(holds, known)

# whether vreg v holds data that is never an address: a float, a vector, or a leaf of a number type
fn irHoldsData(mut g Gen, f IrFn, v i64):
	if f.classes[v] != irInt: return true
	if v >= f.leafTypes.len or f.leafTypes[v] < 0: return false
	k = g.tyK(TypeId(f.leafTypes[v]))
	k in [tInt, tBool, tFloat, tEnum, tUnit]

# whether each vreg is only ever assigned a constant (irConst)
fn irConstantVregs(f IrFn):
	constant = fill(f.classes.len, true)
	for b in f.blocks:
		for inst in b.insts:
			if inst.dst >= 0 and inst.op != irConst:
				constant[inst.dst] = false
	constant

# x put in the ordered set: whether it was not there
fn irSetPut(mut set i64[], x i64):
	i = 0
	while i < set.len and set[i] < x:
		i += 1
	if i < set.len and set[i] == x: return false
	set.insert(i, x)
	true

# from's members put in the ordered set: whether it grew
fn irSetJoin(mut set i64[], from i64[]):
	grew = false
	for x in from:
		if set.irSetPut(x):
			grew = true
	grew
