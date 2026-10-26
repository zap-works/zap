# The frame of an emitted function: slots, spills, blocks and saved registers (irx64.zap).

# What the code of f with its registers rs needs before it is emitted, its frame slots taken in
# state (the function's fresh one): read from f alone, so made with the passes (irmade.zap). Its
# labels come when it is emitted (irLabelBlocks).
fn irEmitOf(mut state FnState, move f IrFn, move rs IrRegs):
	nv = f.classes.len
	rs2 = rs
	zeroAt = fill(nv, false)
	filled = fill(nv, false)
	sealed = zeros(nv)
	low, high = state.irSlotOffsets(f, rs2, zeroAt, filled, sealed)
	deadStores = f.irDeadSlotStores(rs2, filled)
	em = IrEmit(
		f,
		rs = rs2,
		slots = zeros(nv),
		zeroAt,
		filled,
		deadStores,
		sealed,
		labels = [],
		retLabel = -1,
		zeroLow = low,
		zeroHigh = high
	)
	em.tailCalls = not em.f.blocks.any(
		.insts.any(.op in [irFrameSlot, irFrameAddr, irReturnAddress])
	)
	em.reads = zeros(nv)
	for block in em.f.blocks:
		for inst in block.insts:
			for v in inst.irReads():
				em.reads[v] += 1
	em

# each block's label and the return's, made in the assembler
fn irLabelBlocks(mut g Gen, mut em IrEmit):
	loop em.f.blocks.len:
		em.labels.push(g.a.asmNewLabel())
	em.retLabel = g.a.asmNewLabel()

# Each spilled vreg's slot, taken after every other: the costliest last, nearest rsp, where an
# offset fits a byte. A parameter that came on the stack and is assigned nowhere else (but an f32,
# which arrives as a single) is spilled where it came, above the return address, unless the
# function takes the address of words there (a moved parameter's, which it may change).
fn irSpillSlots(mut g Gen, mut em IrEmit):
	defs = zeros(em.f.classes.len)
	addressed = false
	for b in em.f.blocks:
		for inst in b.insts:
			if inst.dst >= 0:
				defs[inst.dst] += 1
			addressed = addressed or inst.op == irFrameAddr
	for b in em.f.blocks:
		if addressed: break
		for inst in b.insts:
			v = inst.dst
			if inst.op == irParam and not inst.regArgs and v >= 0 and em.rs.spilled[v] and
				defs[v] == 1 and
				(em.f.classes[v] == irInt or (em.f.classes[v] == irFloat and inst.size != 4)):
				em.slots[v] = 16 + 8 * inst.imm
	for v in (0..em.f.classes.len)
		.filter(
			(em.rs.spilled[it] or em.rs.saved[it]) and em.slots[it] == 0 and em.rs.slotOf[it] == it
		)
		.sortedBy(
			em.rs.weight[it]
		):
		em.slots[v] = g.allocSlot(32 if em.f.classes[v] == irVec else 8)
	for v in 0..em.f.classes.len:
		if em.rs.slotOf[v] != v: em.slots[v] = em.slots[em.rs.slotOf[v]]

# whether a copy's two vregs share one spill slot (irShareSlots): it makes no code
fn irCopyInPlace(em IrEmit, inst IrInst):
	em.rs.spilled[inst.dst] and em.rs.spilled[inst.a] and em.slots[inst.dst] == em.slots[inst.a]

# a frame slot free for good: its offset, size and last use
type FreeSlot:
	offset i64
	size i64
	lastUse i64

# Each frame slot's offset (in rs.constVal), and the span they take: [low, high). A slot whose
# value is dropped for good (an irDrop of it, its address never kept in memory or in another
# vreg) is free past its last use, in layout order: the next slot of its size made after that
# takes the same offset, zeroed where it is made (zeroAt) since the first value's bytes may be
# there. A slot used in a loop it was not made in lives through the loop. A slot written whole
# where it is made before anything reads it (filled) is never zeroed: its offset is taken after
# the span of the others, which the frame's making zeroes.
fn irSlotOffsets(
	mut state FnState,
	f IrFn,
	mut rs IrRegs,
	mut zeroAt bool[],
	mut filled bool[],
	mut sealed i64[]
):
	nv = f.classes.len
	start = fill(nv, -1)
	end = fill(nv, -1)
	size = zeros(nv)
	dropped = fill(nv, false)
	escaped = fill(nv, false)
	blockStart = fill(f.blocks.len, -1)
	blockEnd = fill(f.blocks.len, -1)
	makings = zeros(nv)   # (a slot made in two places is filled at neither)
	ways = f.irSlotWaysOf(rs)
	pos = 0
	for b in rs.order:
		blockStart[b] = pos
		for inst in f.blocks[b].insts:
			if inst.op == irFrameSlot and inst.dst >= 0 and rs.isFrame[inst.dst]:
				start[inst.dst] = pos
				size[inst.dst] = inst.imm.alignUp(8)
				makings[inst.dst] += 1
				filled[inst.dst] = makings[inst.dst] == 1 and
					f.irFilledFirst(rs, ways, b, pos - blockStart[b], inst.dst, size[inst.dst])
			for v in inst.irReads():
				if rs.isFrame[v]:
					end[v] = end[v].max(pos)
					if inst.op == irDrop and inst.a == v:
						dropped[v] = true
					elif inst.irKeepsAddress(v):
						escaped[v] = true
			pos += 1
		blockEnd[b] = pos
	for v in 0..nv:
		filled[v] = filled[v] and makings[v] == 1
	# a slot made in a block the layout left out (its code never runs, but its address may still be
	# read): an offset of its own, after the rest
	for b in f.blocks:
		for inst in b.insts:
			if inst.op == irFrameSlot and inst.dst >= 0 and rs.isFrame[inst.dst] and
				start[inst.dst] < 0:
				start[inst.dst] = pos
				size[inst.dst] = inst.imm.alignUp(8)
				escaped[inst.dst] = true
	framed = (0..nv).filter(start[it] >= 0)
	for li in 0..f.loops.len:
		ls = pos
		le = -1
		for b in f.loops[li].blocks:
			if blockStart[b] >= 0:
				ls = ls.min(blockStart[b])
				le = le.max(blockEnd[b])
		for v in framed:
			if start[v] >= 0 and end[v] >= 0 and start[v] < le and end[v] >= ls and
				not (start[v] >= ls and end[v] < le):
				start[v] = start[v].min(ls)
				end[v] = end[v].max(le)
	slots = framed.filter(not filled[it]).sortedBy(start[it])
	slots.extend(framed.filter(filled[it]).sortedBy(start[it]))
	pool FreeSlot[] = []   # slots dropped for good
	low = 0
	high = 0
	any = false
	for v in slots:
		shares = dropped[v] and not escaped[v]
		disp = 0
		if shares and pool.findIndex(.size == size[v] and .lastUse < start[v]) is k:
			disp = pool[k].offset
			pool.remove(k)
			zeroAt[v] = not filled[v]
		else:
			disp = state.takeSlot(size[v])
			if not any and not filled[v]:
				high = disp + size[v]
				any = true
			if not filled[v]:
				low = disp
		rs.constVal[v] = disp
		if shares:
			pool.push((disp, size[v], end[v]))
		if not escaped[v]:
			sealed[v] = size[v]
	(low, high)

# whether inst keeps the address v itself: in memory, or as another value
fn irKeepsAddress(inst IrInst, v i64):
	(inst.op == irStore or inst.op == irUpdate) and inst.c == v or
		inst.dst >= 0 and inst.op != irLoad and not irCalls(inst.op) and inst.irReadsVreg(v)

# whether inst writes into the frame slot v and reads nothing of it: a store of a word at it
fn irStoresInto(inst IrInst, v i64):
	inst.op == irStore and inst.a == v and inst.b < 0 and inst.c != v

# The stores into frame slots whose address nothing keeps that no way reads again: from the
# store on, every path meets the function's end, the slot's next making when it is written
# whole where it is made (filled), or (in its block) a store over the same word, before a read
# of it. By irInstKey.
fn irDeadSlotStores(f IrFn, rs IrRegs, filled bool[]):
	slots = f.irSealedSlots(rs)
	out {i64: bool} = {}
	if slots.isEmpty: return out
	nb = f.blocks.len
	ns = slots.len
	at = fill(f.classes.len, -1)
	for k, v in slots:
		at[v] = k
	# each block's first event of each slot: 1 a read, 2 its making when filled (0: none)
	first = zeros(nb * ns)
	for b in rs.order:
		for inst in f.blocks[b].insts:
			for v in inst.irSlotsMet(at):
				if first[b * ns + at[v]] == 0:
					first[b * ns + at[v]] = inst.irSlotEvent(v, filled)
	# whether a read of the slot is reached from the block's start
	live = fill(nb * ns, false)
	changed = true
	while changed:
		changed = false
		i = rs.order.len - 1
		while i >= 0:
			b = rs.order[i]
			succs = f.irBlockSuccessors(b)
			for k in 0..ns:
				reads = first[b * ns + k] == 1 or
					first[b * ns + k] == 0 and succs.any(live[it * ns + k])
				if reads and not live[b * ns + k]:
					live[b * ns + k] = true
					changed = true
			i -= 1
	# each block walked from its end: per slot, its next event past the instruction (0: none in the
	# block) and the words stored whole before that event
	ahead = zeros(ns)
	words i64[,] = []
	loop ns:
		words.push([])
	for b in rs.order:
		insts = f.blocks[b].insts
		succs = f.irBlockSuccessors(b)
		met = []
		i = insts.len - 1
		while i >= 0:
			inst = insts[i]
			stores = inst.a >= 0 and at[inst.a] >= 0 and inst.irStoresInto(inst.a)
			if stores:
				k = at[inst.a]
				next = ahead[k]
				if inst.size == 8 and inst.imm in words[k]:
					next = 2   # the word written again first
				if next == 2 or next == 0 and not succs.any(live[it * ns + k]):
					out[irInstKey(b, i)] = true
			for v in inst.irSlotsMet(at):
				event = inst.irSlotEvent(v, filled)
				if event != 0:
					ahead[at[v]] = event
					words[at[v]] = []
					met.push(at[v])
			if stores and inst.size == 8:
				words[at[inst.a]].push(inst.imm)
				met.push(at[inst.a])
			i -= 1
		for k in met:
			ahead[k] = 0
			words[k] = []
	out

# the vregs of slots (those at numbers) inst may meet as irSlotEvent sees it: the one it makes and
# those it reads
fn irSlotsMet(inst IrInst, at i64[]) Seq<i64>:
	if inst.op == irFrameSlot and inst.dst >= 0 and at[inst.dst] >= 0: yield inst.dst
	for v in inst.irReads():
		if at[v] >= 0: yield v

# instruction i of block b as one number
fn irInstKey(b i64, i i64):
	b << 32 | i

# the saved vregs (irRegs.saved) the call at key is made between written to their slots (0x89) or
# read back (0x8B)
fn irSaveAround(mut g Gen, em IrEmit, key i64, op i64):
	if em.rs.saveAt.isEmpty or key not in em.rs.saveAt: return
	for v in em.rs.saveAt[key]:
		g.a.memOp(true, op, -1, em.rs.reg[v], 4, -1, g.irSlot(em, v))

# what inst does to the frame slot v for irDeadSlotStores: 1 reads it, 2 makes it anew (written
# whole before it is read), 0 neither (a store into it, a mark)
fn irSlotEvent(inst IrInst, v i64, filled bool[]):
	if inst.op == irFrameSlot and inst.dst == v: return 2 if filled[v] else 0
	if irIsMarker(inst.op) or inst.op == irNote or inst.irStoresInto(v): return 0
	1 if inst.irReadsVreg(v) else 0

# the frame slots of the layout whose address nothing keeps and whose offset no other slot takes
# (a slot made at the offset of one dropped before it may read, on a way past its making, the
# zeros that one left)
fn irSealedSlots(f IrFn, rs IrRegs):
	made = []
	kept = fill(f.classes.len, false)
	for b in rs.order:
		for inst in f.blocks[b].insts:
			if inst.op == irFrameSlot and inst.dst >= 0 and rs.isFrame[inst.dst]:
				made.push(inst.dst)
			for v in inst.irReads():
				# (a call given its address may keep it: return it, or store a reference to it)
				if rs.isFrame[v] and
					(inst.irKeepsAddress(v) or irCalls(inst.op) and v in inst.args):
					kept[v] = true
	takers {i64: i64} = {}
	for v in made:
		takers[rs.constVal[v]] = (takers.get(rs.constVal[v]) ?? 0) + 1
	made.filter(not kept[it] and (takers.get(rs.constVal[it]) ?? 0) == 1)

# Whether the frame slot v of size bytes (at most 64 words), made at instruction k of block b, has
# every word written on each way from there before an instruction reads it or hands its address
# on (a call's result too: its callee may write part), each read past its making. A zero stored
# into a slot of more than 8 words is no write: the frame's zeroing makes it, and the store goes.
fn irFilledFirst(f IrFn, rs IrRegs, ways IrSlotWays, b i64, k i64, v i64, size i64):
	words = size / 8
	if words == 0 or words > 64 or not ways.irOnlyPast(b, v): return false
	looped = ways.looped[b]
	full = -1 if words == 64 else ~(-1 << words)
	# the words written on every way into each block a way reached, by block (a slot's ways are
	# short: no table of every block for each)
	into {i64: i64} = {}
	todo = [(b, k + 1, 0)]
	if not ways.irReadIn(b, v):   # (nothing written before its first reader: the walk starts there)
		if ways.readAt[v] == ways.readAt[v + 1]: return true
		first = ways.irFirstReader(v)
		if first >= 0:
			into[first] = 0
			todo = [(first, 0, 0)]
	while todo.pop() is (at, from, entry):
		insts = f.blocks[at].insts
		mask = entry
		i = from
		made = false
		while i < insts.len and not made and mask & full != full:   # (once full, no read fails)
			x = insts[i]
			if x.op == irFrameSlot and x.dst == v:
				made = true   # made anew: what follows is the next making's
			elif not irIsMarker(x.op) and x.op != irNote and x.irReadsVreg(v):
				if x.op == irStore and x.a == v and x.b < 0 and x.c != v and x.size == 8 and
					x.imm >= 0 and x.imm < size and x.imm % 8 == 0:
					if words <= 8 or not looped or not (rs.isConst[x.c] and rs.constVal[x.c] == 0):
						mask |= 1 << (x.imm / 8)
				elif x.op == irMemCopy and x.a == v and x.b != v and x.imm >= size:
					mask = full
				elif mask & full != full:
					return false
			i += 1
		if not made and mask & full != full:   # (every word written: no read on from here fails)
			for next in f.irBlockSuccessors(at):
				seen = next in into
				now = into[next] & mask if seen else mask
				if not seen or now != into[next]:
					into[next] = now
					todo.push((next, 0, now))
	true

# What the frame slots' ways are read from, found once for all of a function's slots: its
# dominators, the reached blocks reading each frame address (CSR: those of vreg v from
# readAt[v] to readAt[v + 1]), and the blocks in a loop.
type IrSlotWays:
	dom IrDom
	readAt i64[]
	readers i64[]
	looped bool[]

fn irSlotWaysOf(f IrFn, rs IrRegs):
	nv = f.classes.len
	vs = []   # each (frame address, block reading it), once a block
	bs = []
	last = fill(nv, -1)
	for b in rs.order:
		for inst in f.blocks[b].insts:
			for v in inst.irReads():
				if rs.isFrame[v] and last[v] != b:
					last[v] = b
					vs.push(v)
					bs.push(b)
	readAt = zeros(nv + 1)
	for v in vs:
		readAt[v + 1] += 1
	for v in 0..nv:
		readAt[v + 1] += readAt[v]
	readers = zeros(vs.len)
	next = readAt.copy()
	for i, v in vs:
		readers[next[v]] = bs[i]
		next[v] += 1
	looped = fill(f.blocks.len, false)
	for l in f.loops:
		for b in l.blocks:
			looped[b] = true
	IrSlotWays(dom = f.irDomTree(rs.order), readAt, readers, looped)

# whether every way from the function's start to an instruction reading v passes block b: b
# dominates every other reached block reading v
fn irOnlyPast(ways IrSlotWays, b i64, v i64):
	for i in ways.readAt[v]..ways.readAt[v + 1]:
		r = ways.readers[i]
		if r != b and not ways.dom.irDominates(b, r): return false
	true

# whether block b reads the frame address v
fn irReadIn(ways IrSlotWays, b i64, v i64):
	(ways.readAt[v]..ways.readAt[v + 1]).any(ways.readers[it] == b)

# The block reading v (some block does) that dominates every other reading it, -1 when none does:
# a way from v's making past a block that does not read it meets that one before any other reader
fn irFirstReader(ways IrSlotWays, v i64):
	first = ways.readers[ways.readAt[v]]
	for i in ways.readAt[v]..ways.readAt[v + 1]:
		if ways.dom.enter[ways.readers[i]] < ways.dom.enter[first]: first = ways.readers[i]
	for i in ways.readAt[v]..ways.readAt[v + 1]:
		if not ways.dom.irDominates(first, ways.readers[i]): return -1
	first

# whether an instruction may write memory through an address it holds (a slot it mentions is no
# longer known to be zero): everything but a load, a copy of the address alone or a drop's check
# Whether the instruction writes zeros over a slot of stillZero (frame slots made or zeroed whole in
# the block, nothing but zero written since): it needs no code; stillZero kept up to date
fn irZerosOverZeros(em IrEmit, inst IrInst, mut stillZero i64[]):
	if inst.op == irFrameSlot and inst.dst >= 0 and em.rs.isFrame[inst.dst] and
		not em.filled[inst.dst]:
		stillZero.push(inst.dst)   # zeroed at entry, or where it is made when it shares an offset
	elif inst.op == irStore and inst.a >= 0 and inst.a in stillZero and inst.b < 0 and
		inst.c >= 0 and em.rs.isConst[inst.c] and em.rs.constVal[inst.c] == 0 or
		inst.op == irMemSet and inst.a in stillZero and em.rs.isConst[inst.b] and
		em.rs.constVal[inst.b] == 0:
		return true
	elif not stillZero.isEmpty and inst.irTouchesSlots():
		kept = stillZero.filter(not inst.irReadsVreg(it) and inst.dst != it)
		stillZero.clear()
		stillZero.extend(kept)
	false

fn irTouchesSlots(inst IrInst):
	inst.op != irLoad and inst.op != irConst

# A loop's step block (the branch back to its top) that a branch inside the loop goes to, as a
# test that skips the rest of the body does: placed right before the top, so that way falls from
# the step into the top, one taken jump a turn (the step after the body's end costs a jump)
fn irRotateLoops(mut em IrEmit):
	em.rotated = zeros(em.f.blocks.len)
	placed = fill(em.f.blocks.len, -1)
	for i, b in em.order:
		placed[b] = i
	for l in em.f.loops:
		top = l.blocks.find(em.f.blocks[it].loopTop) ?? continue
		step = l.blocks.find(it != top and em.f.irEndsInBranchTo(it, top)) ?? continue
		skipped = l.blocks.any(it != step and em.f.irEndsInBranchTo(it, step))
		if not skipped or placed[step] < 0 or placed[top] < 0 or
			em.framed[step] != em.framed[top] or step == em.frameAt:
			continue
		em.order.remove(placed[step])
		em.order.insert(em.order.indexOf(top) ?? continue, step)
		for i, b in em.order:
			placed[b] = i
		em.rotated[step] = true

# whether block b ends in a branch one of whose ways is block to
fn irEndsInBranchTo(f IrFn, b i64, to i64):
	insts = f.blocks[b].insts
	if insts.isEmpty: return false
	last = insts[len - 1]
	(last.op == irBranch or last.op == irBranchBit) and (last.target == to or last.other == to)

# instructions at ii whose code is one: a division and its remainder, a product and its carry or
# high half; how many were written, none when the one at ii stands alone
fn irEmitJoined(mut g Gen, em IrEmit, insts IrInst[], ii i64) i64?:
	inst = insts[ii]
	if ii + 1 < insts.len and inst.irDivPair(insts[ii + 1]) and not em.rs.isConst[inst.b]:
		g.irEmitDivide(em, inst, insts[ii + 1].dst)   # one division gives both
		return 2
	if inst.op == irLoad:
		for at in ii + 1..(ii + 3).min(insts.len):
			if g.irMulCarry(em, insts, at, ii) is taken:
				return taken   # from the load: its factor goes into rax
			if at + 1 < insts.len and insts[at].irMulPair(insts[at + 1]) and
				em.irMulOfLoad(
					insts,
					ii,
					at,
					insts[at] if insts[at].op == irMulHigh else insts[at + 1]
				):
				g.irEmitMulHighLoaded(em, insts, ii, at)
				return at + 2 - ii
	if (g.irMulCarry(em, insts, ii, -1) ?? g.irCarryOf(em, insts, ii)) is taken: return taken
	if ii + 1 < insts.len and inst.irMulPair(insts[ii + 1]):
		high = inst if inst.op == irMulHigh else insts[ii + 1]
		g.irEmitMulHigh(em, high, insts[ii + 1].dst if inst.op == irMulHigh else inst.dst)
		return 2
	none

# the blocks in their order (em.order), the frame made at the start of frameAt
fn irEmitBlocks(mut g Gen, em IrEmit):
	# each block's way in: how many blocks go there, and the last one met
	preds = zeros(em.f.blocks.len)
	predOf = fill(em.f.blocks.len, -1)
	for b in em.order:
		for s in em.f.irBlockSuccessors(b):
			preds[s] += 1
			predOf[s] = b
	for oi in 0..em.order.len:
		b = em.order[oi]
		next = em.order[oi + 1] if oi + 1 < em.order.len else -1
		g.f.framed = em.framed[b]
		if em.rotated[b] or
			em.f.blocks[b].loopTop and not (oi > 0 and em.rotated[em.order[oi - 1]]):
			g.placeLoopTop(em.labels[b])
		else:
			g.a.asmPlace(em.labels[b])
		if b == em.frameAt:
			g.irEmitFrame(em)
		elif em.framed[b]:
			g.irSavesAt(em, b, false)
		if b == em.frameAt or oi == 0 or preds[b] != 1 or predOf[b] != em.order[oi - 1]:
			g.xmm0Zero = false   # reached from elsewhere: only the block before it leaves it known
		g.xmm0Held = -1
		insts = em.f.blocks[b].insts
		ii = 0
		stillZero = []   # frame slots made or zeroed whole in this block, nothing but zero written since
		foldUses i64[] = []   # the instructions that read a float's load from memory (irFoldedUse)
		foldLoads = []   #   and those loads
		while ii < insts.len:
			inst = insts[ii]
			if irIsMarker(inst.op) or irInstKey(b, ii) in em.deadStores or
				inst.op == irJmp and not irGoesOn(insts, ii):
				ii += 1   # ownership stated, no code; a store nothing reads; or a jump after a stop
				continue
			if not em.irVecEmitted(inst):
				g.xmm0Held = -1   # its code may write ymm0
			if em.irZerosOverZeros(inst, stillZero):
				ii += 1
				continue
			if inst.op == irLoad and em.irFoldedUse(insts, ii) is use and use not in foldUses:
				foldUses.push(use)
				foldLoads.push(ii)
				ii += 1   # read where it is used
				continue
			if inst.line > 0 and inst.line != g.curLine:
				g.curLine = inst.line
				g.curCol = inst.col
				g.noteDebugLine(g.curLine, g.curCol, g.curFile)
			g.xmm0Zero = g.xmm0Zero and em.irKeepsXmm0(inst, -1)
			if inst.op == irParam and inst.regArgs:
				ii += g.irParamsIn(em, insts, ii)   # read at once
				continue
			if g.irEmitJoined(em, insts, ii) is taken:
				ii += taken
				continue
			run = em.irZeroRun(insts, ii)
			if run > 0:
				at = g.irOnFrame(em, inst)
				base = 4 if at.frame else g.irIntIn(em, inst.a, 0)
				g.irZeroWords(base, at.imm, run)
				if em.rs.isFrame[inst.a] and inst.imm == 0 and em.sealed[inst.a] > 0 and
					8 * run >= em.sealed[inst.a]:
					stillZero.push(inst.a)
				ii += run
				continue
			if em.irTailCall(insts, ii, b):
				g.irEmitTailCall(em, inst)
				break   # the jump is the block's end
			if inst.op == irRet:
				g.irEmitReturn(em, inst, em.retTo[b])
			else:
				fold = foldUses.indexOf(ii)
				keeps = em.irKeepsXmm0(
					inst,
					insts[foldLoads[fold ?? 0]].dst if fold != none else -1
				)
				if not keeps:
					g.xmm0Zero = false
				if fold is j:
					if inst.op == irVecOp and inst.cond == 1:
						g.irEmitVecFma(em, inst, insts[foldLoads[j]].copy())
					elif inst.op == irVecOp:
						g.irEmitVecOpFrom(em, inst, insts[foldLoads[j]].copy())
					else:
						g.irEmitFloatArith(em, inst, insts[foldLoads[j]].copy())
				else:
					outs = insts.irCallOutsAt(ii)
					g.irSaveAround(em, irInstKey(b, ii), 0x89)
					if outs.isEmpty:
						g.irEmitInst(em, inst, next)
					else:
						g.irEmitCall(em, inst, outs)   # its result's leaves with it
					g.irSaveAround(em, irInstKey(b, ii), 0x8B)
					ii += outs.len
				if not keeps:
					g.xmm0Zero = false
			ii += 1
		if (insts.isEmpty or not isTerminator(insts[len - 1].op)) and irGoesOn(insts, insts.len):
			g.a.jmpLabel(em.labels[b + 1])   # falls into the block after it

# whether irvecx64.zap writes an instruction's code (which keeps g.xmm0Held)
fn irVecEmitted(em IrEmit, inst IrInst):
	op = inst.op
	if op in [irVecOp, irVecSplat, irVecMask]: return true
	if op == irStore: return inst.c >= 0 and em.f.classes[inst.c] == irVec
	(op in [irLoad, irCopy, irConst]) and inst.dst >= 0 and
		em.f.classes[inst.dst] == irVec

# The instruction after insts[ii], the load of an f64 (or of a vector) read nowhere else,
# that takes it as its memory operand (vsubsd x, a, [mem]; vsubpd; vfmadd231pd), when nothing between writes
# memory, calls, or changes the address's registers or the loaded value; none when there is no
# such one.
fn irFoldedUse(em IrEmit, insts IrInst[], ii i64) i64?:
	load = insts[ii]
	if load.dst < 0 or em.reads[load.dst] != 1: return none
	class = em.f.classes[load.dst]
	if not (class == irFloat and load.size == 8 or class == irVec and load.size >= 16): return none
	at = [load.a, load.b].filter(it >= 0)
	for k in ii + 1..(ii + 16).min(insts.len):
		inst = insts[k]
		if inst.irReadsVreg(load.dst):
			# a vector instruction of the load's width (an f64's: any)
			wide = (inst.imm >> 5) & 1 == 1
			width = class == irFloat or wide == (load.size == 32)
			if inst.op == irVecOp and inst.cond == 1:
				# an FMA, the load one of its three operands
				uses = [inst.a, inst.b, inst.c].filter(it == load.dst).len
				return k if uses == 1 and width else none
			if inst.a == inst.b: return none
			if class == irVec:
				# a two-operand AVX instruction, its last operand the load
				return k if inst.op == irVecOp and inst.cond == 0 and inst.b == load.dst and width
					else none
			arith = inst.op in [irFAdd, irFSub, irFMul, irFDiv]
			commutes = inst.op == irFAdd or inst.op == irFMul
			if arith and (inst.b == load.dst or commutes): return k
			return none
		if irIsMarker(inst.op): continue
		if inst.op not in irFoldsPast or inst.dst == load.dst or inst.dst in at or
			inst.dst >= 0 and em.f.classes[inst.dst] == irInt and
			at.any(em.rs.reg[it] >= 0 and em.rs.reg[it] == em.rs.reg[inst.dst]):
			return none
	none

# what a float's load may be moved past to where it is read: what only computes its dst
irFoldsPast = [
	irLoad, irConst, irCopy, irFAdd, irFSub, irFMul, irFDiv, irFNeg, irFSqrt, irIntToFloat,
	irAdd, irSub, irMul, irAnd, irOr, irXor, irShl, irShr, irVecOp
]

# Whether an instruction's code writes ymm0 nothing but zero (an f64's or a vector's zero, kept
# there: g.xmm0Zero): an integer's, or one on floats and vectors in registers, a constant (but
# zero) read from the data, whose scratch xmm0 is never loaded (loaded: the vreg of a load it reads
# from memory, -1 none)
fn irKeepsXmm0(em IrEmit, inst IrInst, loaded i64):
	op = inst.op
	if irIsMarker(op) or op == irJmp: return true
	ints = op in [
		irAdd,
		irSub,
		irAnd,
		irOr,
		irXor,
		irMul,
		irShl,
		irShr,
		irNeg,
		irNot,
		irConst,
		irCopy
	]
	if ints or op == irLoad:
		return inst.dst < 0 or em.f.classes[inst.dst] == irInt or
			(op == irLoad or op == irCopy) and em.irInReg(inst.dst) or
			op == irConst and (em.rs.isConst[inst.dst] or em.irInReg(inst.dst))
	if op == irStore: return em.f.classes[inst.c] == irInt or em.irInReg(inst.c)
	if op in [irFAdd, irFSub, irFMul, irFDiv, irVecOp]:
		other = inst.b if inst.a == loaded else inst.a
		return em.irInReg(inst.dst) and em.irZeroOrInReg(other) and
			(op != irVecOp or inst.cond == 0)
	if op == irFSqrt or op == irFNeg: return em.irInReg(inst.dst) and em.irInReg(inst.a)
	if op == irBranch or op == irSet:
		if em.f.classes[inst.a] == irInt: return op == irBranch or em.irInReg(inst.dst)
		swap = inst.cond == irLt or inst.cond == irLe   # irCompareFloat's side in a register
		return em.irZeroOrInReg(inst.b if swap else inst.a) and
			(op == irBranch or em.irInReg(inst.dst))
	false

# whether v lives in a register (not a slot, not a constant written where it is read)
fn irInReg(em IrEmit, v i64):
	v >= 0 and not em.rs.spilled[v] and not em.rs.isConst[v] and em.rs.reg[v] >= 0

# the same, or a zero constant
fn irZeroOrInReg(em IrEmit, v i64):
	em.irInReg(v) or v >= 0 and em.rs.isConst[v] and em.rs.constVal[v] == 0

# how many stores from instruction ii on write zero to the consecutive words of one address
# (0 when that one does not)
fn irZeroRun(em IrEmit, insts IrInst[], ii i64):
	n = 0
	while ii + n < insts.len and em.irStoresZero(insts[ii + n]) and
		insts[ii + n].a == insts[ii].a and
		insts[ii + n].frame == insts[ii].frame and insts[ii + n].imm == insts[ii].imm + 8 * n:
		n += 1
	n

# whether an instruction stores a word of zero at an address with no index
fn irStoresZero(em IrEmit, inst IrInst):
	inst.op == irStore and inst.size == 8 and inst.b < 0 and inst.c >= 0 and
		em.rs.isConst[inst.c] and em.rs.constVal[inst.c] == 0 and em.f.classes[inst.c] == irInt

# n words of zero at [base + disp]: two at a time from xmm0 (vxorps, then vmovups), the last one
# alone by vmovq; a single word by mov qword [mem], 0
fn irZeroWords(mut g Gen, base i64, disp i64, n i64):
	if n == 1:
		g.irStoreImm(0, 8, base, -1, 1, disp)
		return
	g.irVexRR(0, 0, 0x57, 0, 0, 0)   # vxorps xmm0, xmm0, xmm0
	k = 0
	while k + 2 <= n:
		g.irVexRM(0, 0, 0x11, 0, 0, base, -1, 1, disp + 8 * k)   # vmovups [mem], xmm0
		k += 2
	if k < n:
		g.irVexRM(1, 0, 0xD6, 0, 0, base, -1, 1, disp + 8 * k)   # vmovq [mem], xmm0

# the registers to give back as they were found: int ones by their numbers, xmm (or v) ones as
# irFloatCode + theirs; a function's those calls keep (and rsi, rdi), a region's all it uses
fn irSavedRegs(f IrFn, rs IrRegs, all bool):
	out i64[] = []
	for v in 0..f.classes.len:
		code = f.irRegCode(rs, v)
		if code >= 0 and (all or f.irKept(rs, v)) and code not in out:
			out.push(code)
	out

# the first code of a float register (irSavedRegs), past every integer one of either machine
irFloatCode = 32

# v's register as irSavedRegs numbers it, -1 for none
fn irRegCode(f IrFn, rs IrRegs, v i64):
	r = rs.reg[v]
	if r < 0: return -1
	irFloatCode + r if f.classes[v] != irInt else r

# whether v's register is one calls keep (or, on x64, rsi and rdi)
fn irKept(f IrFn, rs IrRegs, v i64):
	r = rs.reg[v]
	if rs.arm: return r in (irArmKeptInt if f.classes[v] == irInt else irArmKeptFloat)
	if f.classes[v] != irInt: return r >= 6
	r in [3, 5, 6, 7] or r >= 12

fn irSaveReg(mut g Gen, code i64, slot i64, restore bool):
	if code >= irFloatCode:
		g.irVexL(1, 0, 0, 0, code - irFloatCode, 0, -1, 4)   # vmovups: the register's low 128 bits, all calls keep
		g.a.em1(0x10 if restore else 0x11)
		g.irModRm(code - irFloatCode, 4, -1, 1, g.irDisp(slot))
	else:
		g.a.memOp(true, 0x8B if restore else 0x89, -1, code, 4, -1, g.irDisp(slot))

# ---------- operands ----------
