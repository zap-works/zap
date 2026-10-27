# The optimizer's common subexpressions and read-modify-write updates (irOpt.zap).

# In each block, an instruction that computes what one before it did (its operands not assigned
# in between, memory not written in between for a load) reads that one's result instead, a pure
# function's call with the same arguments and a division among them; a check made again is
# dropped. True when one was. One walk: the computations met are chained by their work's hash,
# and one still holds while nothing assigned its operands or result, nor wrote what it loaded
# (irHolds).
fn irCommon(mut f IrFn, facts IrFacts, visit bool[]):
	changed = false
	defs = f.irDefsFor()
	stored = -1   # the position of the last write to memory
	headerAt = -1   # the position of the last write to a list's header
	latest {i64: i64} = {}   # a work's hash -> the last computation met with it
	metAt i64[] = []   # each computation met: its position
	before i64[] = []   # the computation met before it with the same hash (-1: none)
	for bi in 0..f.blocks.len:
		dropped = 0   # checks made again, to take out at the end
		n = f.blocks[bi].insts.len
		if not visit[bi]:
			defs.start += n
			continue
		for k in 0..n:
			op = f.blocks[bi].insts[k].op
			if irIsMarker(op): continue   # it computes nothing and makes nothing stale
			dst = f.blocks[bi].insts[k].dst
			reuse = (
				irPureOp(op) and op != irConst and op != irCopy and op != irParam and
					op != irFrameSlot and dst >= 0
			) or
				op == irFailIf or op == irCall and f.blocks[bi].insts[k].pure > 0 and dst >= 0 or
				# a division made again: the first one stopped the program or gave the same
				(op == irDiv or op == irRem) and dst >= 0
			at = -1
			h = 0
			head = -1
			if reuse:
				h = f.blocks[bi].insts[k].irWorkHash(facts.consts)
				head = latest.get(h) ?? -1
				e = head
				while e >= 0 and metAt[e] >= defs.start:
					j = metAt[e] - defs.start
					if f.blocks[bi].insts[j].irHolds(metAt[e], defs, stored, headerAt) and
						f.blocks[bi].insts[j].irSameWork(f.blocks[bi].insts[k], facts.consts):
						at = j
						break
					e = before[e]
			if at >= 0 and op == irFailIf:
				f.irTakeOut(bi, k)
				dropped += 1
				changed = true
				continue
			if at >= 0 and f.blocks[bi].insts[at].dst != dst:
				line = f.blocks[bi].insts[k].line
				col = f.blocks[bi].insts[k].col
				f.blocks[bi].insts[k] = IrInst(
					op = irCopy,
					dst,
					a = f.blocks[bi].insts[at].dst,
					line,
					col
				)
				changed = true
			if reuse and at < 0 and not f.blocks[bi].insts[k].irReadsVreg(dst):
				# one of the same work met before no longer holds: it leaves the chain
				prev = head
				if head >= 0 and metAt[head] >= defs.start and
					f.blocks[bi].insts[metAt[head] - defs.start].irSameWork(
						f.blocks[bi].insts[k],
						facts.consts
					):
					prev = before[head]
				latest[h] = metAt.len
				metAt.push(defs.start + k)
				before.push(prev)
			if irWritesMemory(f.blocks[bi].insts[k].op):
				stored = defs.start + k
				if f.blocks[bi].insts[k].irWritesHeader():
					headerAt = defs.start + k
			defs.irNoteDef(dst, k)
		if dropped > 0:
			f.blocks[bi].insts = f.blocks[bi].insts.filter(.op >= 0)
		defs.start += n
	changed

# Work done again in a later block, across blocks as irCommon finds it in one: a check where one
# of the same work ran before it on every way there (its block dominates, its operands not
# assigned on a way between: irHeldTo) goes, as the first stopped the program or passed as the
# second would; a load or a pure operation in a block reached only through the first's (each block
# between entered from the one before it alone), its operands and the first's result not assigned
# between and, for a load, memory not written, reads the first's result. Each is compared with
# the last few kept of its work, the blocks walked in reverse postorder. True when one was.
fn irDominatedWork(mut f IrFn):
	order = f.irLayout()
	dom = f.irDomTree(order)
	consts = f.irFacts().consts
	preds = zeros(f.blocks.len)
	onlyPred = fill(f.blocks.len, -1)
	for b in 0..f.blocks.len:
		for t in f.irBlockSuccessors(b):
			preds[t] += 1
			onlyPred[t] = b
	kept {i64: i64[]} = {}   # a work's hash -> the sites of those kept with it
	touched i64[] = []   # the blocks with instructions taken out, dropped at the end (sites stay)
	changed = false
	for b in order:
		for k in 0..f.blocks[b].insts.len:
			inst = f.blocks[b].insts[k].copy()
			check = inst.op == irFailIf
			if not check and not (
				inst.dst >= 0 and
					(
						inst.op == irLoad and not inst.frame or inst.op != irLoad and inst.irPure()
					) and
					inst.op != irConst and inst.op != irCopy and inst.op != irParam and
					inst.op != irFrameSlot
			):
				continue
			site = b << 32 | k
			h = inst.irWorkHash(consts)
			sites i64[] = (kept.get(h) ?? []).copy()
			cover = -1
			for at in sites:
				x = f.blocks[at >> 32].insts[at & 0xFFFF_FFFF]
				if not x.irSameWork(inst, consts): continue
				if check and f.irSiteDominated(dom, at, site) and
					x.irReads().all(consts[it] != none or f.irHeldTo(dom, at, site, it)) or
					not check and x.dst != inst.dst and f.classes[x.dst] == f.classes[inst.dst] and
					f.irChainCovers(preds, onlyPred, at, site):
					cover = at
					break
			if cover >= 0:
				changed = true
				if check:
					f.irTakeOut(b, k)
					if b not in touched: touched.push(b)
				else:
					src = f.blocks[cover >> 32].insts[cover & 0xFFFF_FFFF].dst
					f.blocks[b].insts[k] = IrInst(
						op = irCopy,
						dst = inst.dst,
						a = src,
						line = inst.line,
						col = inst.col
					)
				continue
			if inst.dst >= 0 and inst.irReadsVreg(inst.dst): continue   # (`v = load [v]`: what it read is gone)
			sites.push(site)
			if sites.len > irWorkPeers: sites.remove(0)
			kept[h] = sites
	for b in touched:
		f.irDropTakenOut(b)
	changed

irWorkPeers = 4   # the computations of a work a later one is compared with

# whether the load or operation at site `at` still holds at `site`: site's block reached from
# at's through blocks each entered from the one before it alone, and on that way after `at` and
# before `site` nothing assigns at's operands or result, nor writes memory for a load
fn irChainCovers(f IrFn, preds i64[], onlyPred i64[], at i64, site i64):
	fb = at >> 32
	tb = site >> 32
	x = f.blocks[fb].insts[at & 0xFFFF_FFFF]
	spans = [(tb, 0, site & 0xFFFF_FFFF)]   # (block, from, to): the instructions between
	b = tb
	while b != fb:
		if preds[b] != 1 or spans.len > irChainLimit: return false
		b = onlyPred[b]
		if b != fb: spans.push((b, 0, f.blocks[b].insts.len))
	if fb == tb and (at & 0xFFFF_FFFF) >= (site & 0xFFFF_FFFF): return false
	if fb != tb: spans.push((fb, (at & 0xFFFF_FFFF) + 1, f.blocks[fb].insts.len))
	else: spans[0] = tb, (at & 0xFFFF_FFFF) + 1, site & 0xFFFF_FFFF
	reads = []
	for v in x.irReads():
		reads.push(v)
	for span in spans:
		bb, lo, hi = span
		for k in lo..hi:
			y = f.blocks[bb].insts[k]
			if y.dst >= 0 and (y.dst == x.dst or y.dst in reads): return false
			if x.op == irLoad and not x.steady and irWritesMemory(y.op):   # (a header's word too: the runtime stores into it by address)
				return false
	true

irChainLimit = 16   # the blocks a chain is followed back through

# whether a computation met at position p still holds: nothing assigned its result or operands
# since, and for a load nothing wrote memory since (a list's header, for a load of one; only
# those stores, calls and copies of bytes change one)
fn irHolds(old IrInst, p i64, defs IrDefs, stored i64, headerAt i64):
	if old.dst >= 0 and defs.at[old.dst] != p: return false
	if old.op == irLoad and not old.steady and (headerAt if old.header else stored) > p:
		return false
	not old.irReads().any(defs.at[it] > p)

# A load, an operation on it and a store of the result to the same place (`xs[k] &= m`), the
# loaded and computed values read nowhere else and memory not touched in between: one update in
# memory, where the store was. True when one was made.
fn irUpdates(mut f IrFn, facts IrFacts, visit bool[]):
	changed = false
	defs = f.irDefsFor()
	for bi in 0..f.blocks.len:
		made = false
		touched = -1   # the index of the block's last instruction that touches memory
		n = f.blocks[bi].insts.len
		if not visit[bi]:
			defs.start += n
			continue
		for k in 0..n:
			if f.irUpdateAt(bi, k, defs, touched, facts.reads):
				made = true
				changed = true
			if irWritesMemory(f.blocks[bi].insts[k].op):
				touched = k
			defs.irNoteDef(f.blocks[bi].insts[k].dst, k)
		if made:
			f.blocks[bi].insts = f.blocks[bi].insts.filter(.op >= 0)
		defs.start += n
	changed

# instruction k of block bi, when it stores an operation on a load of the same place, made the
# update (irUpdates); touched the index of the last instruction before it that touches memory
fn irUpdateAt(mut f IrFn, bi i64, k i64, defs IrDefs, touched i64, reads i64[]):
	if f.blocks[bi].insts[k].op != irStore or f.blocks[bi].insts[k].size != 8 or
		f.blocks[bi].insts[k].c < 0:
		return false
	# the operation that made the stored value, and the load it reads, before it
	j = defs.irDefIn(f.blocks[bi].insts[k].c)
	if j < 0 or touched > j: return false
	opA = f.blocks[bi].insts[j].a
	opB = f.blocks[bi].insts[j].b
	i = f.irLoadBefore(bi, defs, opA, j).max(f.irLoadBefore(bi, defs, opB, j))
	if i < 0 or touched > i or
		not irIsUpdate(
			f,
			f.blocks[bi].insts[i],
			f.blocks[bi].insts[j],
			f.blocks[bi].insts[k],
			reads
		):
		return false
	ldDst = f.blocks[bi].insts[i].dst
	ldA = f.blocks[bi].insts[i].a
	ldB = f.blocks[bi].insts[i].b
	# the address must not change between the load and the store
	if (ldA >= 0 and defs.at[ldA] > defs.start + i) or (ldB >= 0 and defs.at[ldB] > defs.start + i):
		return false
	x = opB if opA == ldDst else opA
	opOp = f.blocks[bi].insts[j].op
	stA = f.blocks[bi].insts[k].a
	stB = f.blocks[bi].insts[k].b
	stImm = f.blocks[bi].insts[k].imm
	stScale = f.blocks[bi].insts[k].scale
	stFrame = f.blocks[bi].insts[k].frame
	line = f.blocks[bi].insts[k].line
	col = f.blocks[bi].insts[k].col
	f.blocks[bi].insts[k] = IrInst(
		op = irUpdate,
		a = stA,
		b = stB,
		c = x,
		imm = stImm,
		scale = stScale,
		cond = i32(opOp),
		frame = stFrame,
		line,
		col
	)
	f.irTakeOut(bi, j)
	f.irTakeOut(bi, i)
	true

# the index of the load in block bi that last assigned v before instruction j, -1 when v's last
# assignment is not one
fn irLoadBefore(f IrFn, bi i64, defs IrDefs, v i64, j i64):
	d = defs.irDefIn(v)
	d if d >= 0 and d < j and f.blocks[bi].insts[d].op == irLoad else -1

# instruction k of block bi marked as taken out (op -1, no result): a pass filters the block once
# it is done, so it allocates nothing per instruction
fn irTakeOut(mut f IrFn, bi i64, k i64):
	f.blocks[bi].insts[k].op = -1
	f.blocks[bi].insts[k].dst = -1

# the instructions of block bi marked taken out (irTakeOut) gone
fn irDropTakenOut(mut f IrFn, bi i64):
	insts = move f.blocks[bi].insts
	kept IrInst[] = []
	kept.reserve(insts.len)
	for k in 0..insts.len:
		if insts[k].op >= 0:
			kept.push(move insts[k])   # (the survivors move, none is copied)
	f.blocks[bi].insts = kept

# whether an operation may write memory: a store, an update, a copy or a setting of bytes, an
# atomic, a call, or a fence (what another thread wrote shows after it)
fn irWritesMemory(op i64):
	op in [irStore, irUpdate, irMemCopy, irMemCopyN, irMemSet, irXadd, irCmpxchg, irFence] or
		irCalls(op)

# whether an instruction may write a list's length or items: only those stores and updates do,
# the rest that write memory may
fn irWritesHeader(inst IrInst):
	inst.header if inst.op == irStore or inst.op == irUpdate else irWritesMemory(inst.op)

# whether an operation calls (a call, a drop, a deep copy)
fn irCalls(op i64):
	op in [irCall, irCallPtr, irDrop, irDeepCopy]

fn irIsUpdate(f IrFn, ld IrInst, op IrInst, st IrInst, reads i64[]):
	if ld.op != irLoad or ld.size != 8 or f.classes[ld.dst] != irInt: return false
	if ld.a != st.a or ld.b != st.b or ld.imm != st.imm or ld.scale != st.scale or
		ld.frame != st.frame:
		return false
	if not (op.op in [irAdd, irSub, irAnd, irOr, irXor]) or st.c != op.dst or op.trap or
		op.size != 8:
		return false
	operandOk = (op.a == ld.dst and op.b != ld.dst) or
		(op.b == ld.dst and op.op != irSub and op.a != ld.dst)
	operandOk and reads[ld.dst] == 1 and reads[op.dst] == 1

# in each block, a shift by x & 63 (x not assigned in between) shifts by x: the processor takes
# the count modulo 64 itself
fn irShiftMasks(mut f IrFn, facts IrFacts, visit bool[]):
	changed = false
	defs = f.irDefsFor()
	for bi in 0..f.blocks.len:
		alias insts = f.blocks[bi].insts
		if not visit[bi]:
			defs.start += insts.len
			continue
		for k in 0..insts.len:
			if (insts[k].op == irShl or insts[k].op == irShr) and insts[k].b >= 0:
				j = defs.irDefIn(insts[k].b)
				if j >= 0 and insts[j].op == irAnd and (facts.consts[insts[j].b] ?? -1) == 63 and
					defs.at[insts[j].a] <= defs.start + j:
					insts[k].b = insts[j].a
					changed = true
			defs.irNoteDef(insts[k].dst, k)
		defs.start += insts.len
	changed

# A load of the bytes a store before it wrote (the same size, base and offset, an index of the
# same vreg or of the same constant, none of them nor the stored value assigned since, memory not
# written in between) reads the stored value, an integer narrower than 8 bytes wrapped and
# extended as the load would: `xs[k] += 1` then `xs[k] > k` waits on no store's way to memory.
# The store is in the load's block, or ends the one block before it that leads there (`if xs[k] <
# m: m = xs[k]`). True when one was.
fn irStoredLoads(mut f IrFn, facts IrFacts, visit bool[]):
	changed = false
	defs = f.irDefsFor()
	known = IrKnownConsts(at = fill(f.classes.len, -1), value = zeros(f.classes.len))
	nobody = IrPlace(base = -1, index = -1, scale = 1, offset = 0)
	preds = zeros(f.blocks.len)
	onlyPred = fill(f.blocks.len, -1)
	for b in 0..f.blocks.len:
		for t in f.irBlockSuccessors(b):
			preds[t] += 1
			onlyPred[t] = b
	endSt = fill(f.blocks.len, -1)   # each block's last write of memory, when a store
	endAt = fill(f.blocks.len, nobody)
	starts = zeros(f.blocks.len)   # each block's first position in the walk
	for bi in 0..f.blocks.len:
		n = f.blocks[bi].insts.len
		starts[bi] = defs.start
		if not visit[bi]:
			defs.start += n
			continue
		st = -1   # the last instruction that wrote memory, when it is a store of 8 bytes
		stB = bi   # its block
		stAt = nobody
		pb = onlyPred[bi]
		if preds[bi] == 1 and pb < bi and pb >= 0 and endSt[pb] >= 0:
			st = endSt[pb]
			stB = pb
			stAt = endAt[pb]
		for k in 0..n:
			inst = f.blocks[bi].insts[k].copy()
			if inst.op == irLoad and st >= 0 and inst.size == f.blocks[stB].insts[st].size and
				not inst.frame and inst.dst >= 0 and
				f.classes[inst.dst] == f.classes[f.blocks[stB].insts[st].c]:
				c = f.blocks[stB].insts[st].c
				p = starts[stB] + st
				place = f.irStoredPlace(inst, defs, known, facts)
				if place == stAt and defs.at[c] < p and defs.at[place.base] < p and
					(place.index < 0 or defs.at[place.index] < p):
					wide = inst.size == 8
					f.blocks[bi].insts[k] = IrInst(
						op = irCopy if wide else irTrunc,
						dst = inst.dst,
						a = c,
						imm = 0 if wide else 8 * inst.size,
						uns = inst.uns,
						line = inst.line,
						col = inst.col
					)
					changed = true
			if irWritesMemory(inst.op):
				st = -1
				if inst.op == irStore and not inst.frame and inst.c >= 0 and
					(inst.size == 8 or inst.size in [1, 2, 4] and f.classes[inst.c] == irInt):
					st = k
					stB = bi
					stAt = f.irStoredPlace(inst, defs, known, facts)
			if inst.dst >= 0:
				known.at[inst.dst] = defs.start + k if inst.op == irConst else -1
				known.value[inst.dst] = inst.imm
			defs.irNoteDef(inst.dst, k)
		if st >= 0 and stB == bi:
			endSt[bi] = st
			endAt[bi] = stAt
		defs.start += n
	changed

# the constants vregs were last assigned in the block walked (irStoredLoads): where, -1 for none
type IrKnownConsts:
	at i64[]
	value i64[]

# a load's or a store's address: base + index * scale + offset, a constant index in the offset
type IrPlace:
	base i64
	index i64
	scale i64
	offset i64

fn irStoredPlace(f IrFn, inst IrInst, defs IrDefs, known IrKnownConsts, facts IrFacts):
	b = inst.b
	if b >= 0 and (facts.consts[b] != none or known.at[b] >= 0 and known.at[b] == defs.at[b]):
		v = facts.consts[b] ?? known.value[b]
		return IrPlace(base = inst.a, index = -1, scale = 1, offset = inst.imm + v * inst.scale)
	IrPlace(base = inst.a, index = b, scale = inst.scale if b >= 0 else 1, offset = inst.imm)
