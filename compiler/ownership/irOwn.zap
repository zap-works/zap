# The verifier of the form's ownership (ir.zap's irOwn and irOwnEnd), run on the lowered form and
# after each pass of irSimplify that changes it (like Swift's OSSA verifier). It follows each
# owner along every path from the entry, as the set of what it may be there: not begun, owning,
# moved out (moved, given, returned), dropped, moved out as it is (its bytes left), or set aside
# while a generator's walk runs its turn (read as owned, owned again where it resumes). A fault is
# a value begun again while it owns one (the first leaks), still owned where the function returns
# (a leak), dropped or consumed again once its bytes were moved out as they are (freed twice),
# read once it may only be consumed, or a borrow read past its owner: an address made from the
# owner's (a copy, plus or minus an offset) once it is consumed, or the items of a list read from
# it once it is dropped. A drop, or a write into an owner, reads nothing: an owner that owns
# nothing holds zero bytes, whose drop frees nothing (the drop flag). The first fault stops the
# build, naming the function and the pass after which it showed.

# what an owner may be on the paths to a point, as bits: eight per owner, eight owners a word
ownNotBegun = 1
ownLive = 2
ownMovedOut = 4
ownFreed = 8
ownAsIs = 16
ownSetAside = 32   # suspended while a walk's turn runs: read as owned, but neither begun nor leaking
ownEnded = ownMovedOut | ownFreed | ownAsIs
ownLiveBits = u64(0x0202_0202_0202_0202)   # the live bit of each owner in a word

type IrOwnFault:
	what str
	owner i64   # its vreg
	t i64   # its type
	block i64
	inst i64
	line i64
	col i64

# the function's owners: each one's vreg and type, and each vreg's owner by address (the owner's
# vreg, or an address made from it) and by its memory (a list's items read from one), -1 for none
type IrOwners:
	vregs i64[]
	types i64[]
	addr i64[]
	heap i64[]

# the first ownership fault of f, or none: the owners' states found to a fixed point over the
# blocks in layout order (irOwnEntries), then each block run once with them
fn irOwnFault(f IrFn) IrOwnFault?:
	if not f.blocks.any(.insts.any(.op == irOwn)): return none
	order = f.irLayout()
	o = f.irOwnersOf(order)
	words = (o.vregs.len + 7) / 8
	entry = f.irOwnEntries(order, o)
	st = fill(words, u64(0))
	for b in order:
		for w in 0..words:
			st[w] = entry[b * words + w]
		if f.irOwnCheckBlock(b, st, o) is fault: return fault
	none

# the leaf type (IrFn.leafTypes) of a word of a value that is moved out, the bytes it points to
# its own
irMovedBytes = -2

# what each owner may be on entry to each block (flat, (o.vregs.len + 7) / 8 words a block), to a
# fixed point over the blocks in layout order: only the markers change it
fn irOwnEntries(f IrFn, order i64[], o IrOwners):
	words = (o.vregs.len + 7) / 8
	n = f.blocks.len
	# each block's markers, flat: its owner and the state it leaves, those of block b from
	# markAt[b] to markAt[b + 1]
	markAt = zeros(n + 1)
	marks = []
	for b in 0..n:
		markAt[b] = marks.len
		for inst in f.blocks[b].insts:
			if irIsMarker(inst.op) and o.irOwnerOf(inst.a) is i:
				marks.push(i)
				marks.push(i64(inst.irOwnAfterMarker()))
	markAt[n] = marks.len
	entry = fill(n * words, u64(0))
	reached = fill(n, false)
	for w in 0..words:
		entry[w] = 0x0101_0101_0101_0101   # nothing begun
	reached[0] = true
	st = fill(words, u64(0))
	changed = true
	while changed:
		changed = false
		for b in order:
			for w in 0..words:
				st[w] = entry[b * words + w]
			j = markAt[b]
			while j < markAt[b + 1]:
				st.irOwnSet(marks[j], u64(marks[j + 1]))
				j += 2
			for i in 0..f.irNextCount(b):
				if irOwnJoin(entry, reached, f.irNextAt(b, i), st):
					changed = true
	entry

# st joined into block s's states on entry: whether they grew
fn irOwnJoin(mut entry u64[], mut reached bool[], s i64, st u64[]):
	at = s * st.len
	grew = not reached[s]
	reached[s] = true
	for w in 0..st.len:
		if entry[at + w] | st[w] != entry[at + w]:
			entry[at + w] |= st[w]
			grew = true
	grew

# the owner whose vreg is v, or none
fn irOwnerOf(o IrOwners, v i64) i64?:
	if v < 0 or o.addr[v] < 0 or o.vregs[o.addr[v]] != v: return none
	o.addr[v]

# what a marker leaves its owner
fn irOwnAfterMarker(inst IrInst) u64:
	if inst.op == irOwn: return u64(ownLive)
	if inst.cond == ownDropped: return u64(ownFreed)
	if inst.cond == ownMovedAsIs: return u64(ownAsIs)
	if inst.cond == ownSuspended: return u64(ownSetAside)
	u64(ownMovedOut)

fn irOwnGet(st u64[], i i64) i64:
	(st[i >> 3] >> u64((i & 7) * 8)) & 255

fn irOwnSet(mut st u64[], i i64, bits u64):
	shift = u64((i & 7) * 8)
	st[i >> 3] = (st[i >> 3] & ~(u64(255) << shift)) | (bits << shift)

# the owners (each irOwn's vreg) and the addresses made from them: the vregs assigned once from
# an owner's address (a copy, plus or minus), or its list's items; one walk in layout order,
# where such a vreg's assignment comes before its reads
fn irOwnersOf(f IrFn, order i64[]):
	nv = f.classes.len
	o = IrOwners(vregs = [], types = [], addr = fill(nv, -1), heap = fill(nv, -1))
	defs = zeros(nv)
	for b in f.blocks:
		for inst in b.insts:
			if inst.dst >= 0:
				defs[inst.dst] += 1
			elif inst.op == irOwn and inst.a >= 0 and o.addr[inst.a] < 0:
				o.addr[inst.a] = o.vregs.len
				o.vregs.push(inst.a)
				o.types.push(inst.imm)
	for b in order:
		for inst in f.blocks[b].insts:
			d = inst.dst
			if d < 0 or inst.a < 0 or defs[d] != 1 or o.addr[d] >= 0: continue
			if inst.op in [irCopy, irAdd, irSub]:
				o.addr[d] = o.addr[inst.a]
				o.heap[d] = o.heap[inst.a]
			elif inst.op == irLoad and inst.header and inst.imm == 0 and inst.b < 0:
				o.heap[d] = o.addr[inst.a]   # a list's items
	o

# block b's instructions run over the owners' states st: its first fault, or none
fn irOwnCheckBlock(f IrFn, b i64, mut st u64[], o IrOwners) IrOwnFault?:
	insts = f.blocks[b].insts
	for k, inst in insts:
		op = inst.op
		if irIsMarker(op):
			i = o.irOwnerOf(inst.a) ?? -1
			was = st.irOwnGet(i) if i >= 0 else 0
			what = ""
			if i < 0:
				what = "consumed, never begun"
			elif op == irOwn and was & ownLive != 0:
				what = "begun again while it owns a value (that one leaks)"
			elif op == irOwnEnd and was & ownAsIs != 0:
				what = "consumed again once its bytes were moved out as they are"
			if what != "": return f.irOwnFaultAt(b, k, inst.a, what, o)
			st.irOwnSet(i, inst.irOwnAfterMarker())
			continue
		if op == irRet and st.any(it & ownLiveBits != 0):
			i = (0..o.vregs.len).find(st.irOwnGet(it) & ownLive != 0) ?? 0
			return f.irOwnFaultAt(
				b,
				k,
				o.vregs[i],
				"never consumed: it leaks where the function returns",
				o
			)
		if op == irDrop and o.irOwnerOf(inst.a) is i:
			if st.irOwnGet(i) & ownAsIs != 0:
				return f.irOwnFaultAt(
					b,
					k,
					inst.a,
					"dropped once its bytes were moved out as they are (freed twice)",
					o
				)
			continue
		if irRecyclesList(inst): continue   # a kept list's drop: what it owns (none, once moved) back to its loop
		isCall = op == irCall or op == irCallPtr
		writes = op in [irStore, irMemSet, irMemCopy, irDeepCopy]   # a: where it writes
		v = -1 if writes else irOwnBadRead(st, o, inst.a)
		if v < 0 and not isCall: v = irOwnBadRead(st, o, inst.c)   # a call's c: where it writes its result
		if v < 0 and not isCall: v = irOwnBadRead(st, o, inst.b)
		if v < 0 and not isCall: v = irOwnBadRead(st, o, inst.d)
		if v < 0 and isCall:
			for x in inst.args():
				if v < 0: v = irOwnBadRead(st, o, x)
		if v >= 0: return f.irOwnFaultAt(b, k, o.irOwnerVreg(v), irOwnRead(st, o, v) ?? "", o)
	none

# whether inst is the drop of a list a loop keeps from turn to turn (its block back to the loop)
fn irRecyclesList(inst IrInst):
	inst.op == irCall and inst.key().startsWith("rt__listRecycle")

# v when reading it where the owners are st is a fault, else -1
fn irOwnBadRead(st u64[], o IrOwners, v i64):
	if v < 0 or (o.addr[v] < 0 and o.heap[v] < 0): return -1
	v if irOwnRead(st, o, v) != none else -1

# what is wrong with reading vreg v where the owners are st, or none
fn irOwnRead(st u64[], o IrOwners, v i64) str?:
	if v < 0: return none
	i = o.addr[v]
	if i >= 0 and st.irOwnGet(i) & (ownLive | ownSetAside) == 0 and st.irOwnGet(i) & ownEnded != 0:
		return "read after it is consumed" if o.vregs[i] == v
			else "a borrow of it (v{v}) used after it is consumed"
	h = o.heap[v]
	if h >= 0 and st.irOwnGet(h) & (ownLive | ownSetAside) == 0 and st.irOwnGet(h) & ownFreed != 0:
		return "a borrow of its memory (v{v}) used after it is dropped"
	none

# the owner v is the address of, or whose memory it holds
fn irOwnerVreg(o IrOwners, v i64):
	o.vregs[o.addr[v] if o.addr[v] >= 0 else o.heap[v]]

fn irOwnFaultAt(f IrFn, b i64, k i64, owner i64, what str, o IrOwners):
	inst = f.blocks[b].insts[k]
	oi = o.vregs.findIndex(it == owner) ?? -1
	IrOwnFault(
		what = what.copy(),
		owner,
		t = o.types[oi] if oi >= 0 else -1,
		block = b,
		inst = k,
		line = inst.line,
		col = inst.col
	)

# ---------- where values die: the program's check, right after lowering ----------
