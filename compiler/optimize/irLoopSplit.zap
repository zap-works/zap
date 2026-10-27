# Values given a register through a loop (irOpt.zap), as LLVM's greedy allocator splits them at
# loop boundaries: each vreg a loop and the code outside it both name is a vreg of its own in the
# loop, copied in on the ways into the loop and back out on the ways out of it (the copies cost
# nothing where both take the same register). A vector, in a loop that calls nothing: a call keeps
# only an xmm register's low half, so a vector live across one lives in a slot everywhere
# (irRegs.zap), and the loop's copy crosses no call. An integer or a float, in an innermost loop:
# one that lives through the function and gives its register up outside may hold one in the hot
# loop, weighed by its uses there alone; copied in where it lives into the loop, and out where it
# lives on after unless the loop only reads it and it is assigned once (the one outside then has a
# hole for the loop's stretch, or the two hold one value: irMirrors).

# What a split keeps up to date so that it costs what its loop does, not what the function does
# (a huge function has thousands of loops)
type IrSplitting:
	live IrLive
	remade bool[]
	defs i64[]   # how many instructions assign each vreg
	named i64[]   # how many operands name each vreg, reads and writes, in the whole function
	preds i64[,]   # each block's predecessors
	loopsOf i64[,]   # the loops each block belongs to
	own i64[]   # while a loop splits: each both vreg's in the loop, else -1
	inside bool[]   # while a loop splits: whether each block is in it

# whether a loop's vregs were split from those outside it
fn irSplitLoops(mut f IrFn):
	any = false
	live = f.irLiveness(f.irLayout(), true)   # (its vregs are none remade)
	s = IrSplitting(
		live,
		remade = f.irRemade(),
		defs = f.irDefCounts(),
		named = f.irNamedCounts(),
		preds = f.irPredecessors(),
		loopsOf = f.irLoopsOf(),
		own = fill(f.classes.len, -1),
		inside = fill(f.blocks.len, false)
	)
	for li in f.irInnermostLoops():
		if f.irSplitLoop(li, s, true):
			any = true
	for li in 0..f.loops.len:
		if f.irSplitLoop(li, s, false):
			any = true
	any

# the loop li's vectors split, or its integers and floats (scalars), copied by their liveness
fn irSplitLoop(mut f IrFn, li i64, mut s IrSplitting, scalars bool):
	blocks = f.loops[li].blocks.copy()
	for b in blocks:
		s.inside[b] = true
	done = f.irSplitInside(li, blocks, s, scalars)
	for b in blocks:
		s.inside[b] = false
	done

fn irSplitInside(mut f IrFn, li i64, blocks i64[], mut s IrSplitting, scalars bool):
	if blocks.isEmpty: return false
	top = s.irEntryOf(blocks) ?? return false
	for b in blocks:
		insts = f.blocks[b].insts
		# a way on that is not a jump or a branch (falling through, a switch) keeps the loop as it is
		if insts.isEmpty or insts[len - 1].op not in [irJmp, irBranch, irBranchBit, irRet]:
			return false
		if not scalars and insts.any(irCalls(.op)): return false
	counts = f.irNamedIn(blocks)
	vregs = s.irSharedVregs(f, counts, not scalars)
	if vregs.isEmpty: return false
	ways = f.irWaysIntoOf(top, blocks, s.preds) ?? return false
	for v in vregs:
		s.own[v] = s.irNewVreg(f, f.classes[v])
		s.named[s.own[v]] = counts[v]
		s.named[v] -= counts[v]
	for b in blocks:
		for k in 0..f.blocks[b].insts.len:
			f.blocks[b].insts[k] = f.blocks[b].insts[k].irRenamed(s.own)
	read = []   # those copied in
	written = []   # those copied out: a vector's for every way out, a scalar's where it lives on
	for v in vregs:
		if blocks.any(f.blocks[it].insts.any(.dst == s.own[v])) or scalars and s.defs[v] != 1:
			written.push(v)
		if scalars:
			if s.live.irLiveAt(top, v): read.push(v)
		elif blocks.any(f.blocks[it].insts.any(.irReadsVreg(s.own[v]))):
			read.push(v)
	entry = s.irNewBlock(f)
	f.blocks[entry].insts = read.map(IrInst(op = irCopy, dst = s.own[it], a = it))
	f.blocks[entry].insts.push(IrInst(op = irJmp, target = top))
	s.preds[top].push(entry)
	for v in read:
		s.irNoteCopy(v)
	for (b, k) in ways:
		f.irRedirect(b, k, entry, s.preds)
		f.irJoinLoops(li, b, top, entry, s.loopsOf)
	for b in blocks:
		t = f.blocks[b].insts[f.blocks[b].insts.len - 1].copy()
		for k in 0..(0 if t.op == irRet else 1 if t.op == irJmp else 2):
			to = t.target if k == 0 else t.other
			if to < 0 or s.inside[to]: continue
			after = written.filter(s.live.irLiveAt(to, it)) if scalars else written.copy()
			for v in after:
				s.defs[v] += 1
				s.irNoteCopy(v)
			out = s.irNewBlock(f)
			f.blocks[out].insts = after.map(IrInst(op = irCopy, dst = it, a = s.own[it]))
			f.blocks[out].insts.push(IrInst(op = irJmp, target = to))
			s.preds[to].push(out)
			f.irRedirect(b, k, out, s.preds)
			f.irJoinLoops(li, b, to, out, s.loopsOf)
	for v in vregs:
		s.own[v] = -1
	true

# a new vreg of the class, known to the split
fn irNewVreg(mut s IrSplitting, mut f IrFn, class i64) i64:
	s.own.push(-1)
	s.named.push(0)
	s.defs.push(1)
	f.irVreg(class)

# a new block, known to the split
fn irNewBlock(mut s IrSplitting, mut f IrFn) i64:
	s.preds.push([])
	s.loopsOf.push([])
	s.inside.push(false)
	f.irBlock()

# a copy between v and its own in the loop was made: each is named once more
fn irNoteCopy(mut s IrSplitting, v i64):
	s.named[v] += 1
	s.named[s.own[v]] += 1

# irLoopEntry read from the predecessors (a huge function has many loops)
fn irEntryOf(s IrSplitting, blocks i64[]) i64?:
	top = -1
	for b in blocks:
		for p in s.preds[b]:
			if s.inside[p]: continue
			if top >= 0 and b != top: return none
			top = b
	if top < 0: return none
	top

# how many operands name each vreg, in the whole function
fn irNamedCounts(f IrFn):
	named = zeros(f.classes.len)
	for blk in f.blocks:
		for inst in blk.insts:
			for v in inst.irReads():
				named[v] += 1
			if inst.dst >= 0: named[inst.dst] += 1
	named

# how many operands name each vreg in the blocks
fn irNamedIn(f IrFn, blocks i64[]):
	counts {i64: i64} = {}
	for b in blocks:
		for inst in f.blocks[b].insts:
			for v in inst.irReads():
				counts[v] = (counts.get(v) ?? 0) + 1
			if inst.dst >= 0: counts[inst.dst] = (counts.get(inst.dst) ?? 0) + 1
	counts

# the vregs named both in the loop's blocks and elsewhere (counts: how often in the blocks): its
# vectors, or its integers and floats but those made again where they are read (irRemade), in
# rising order
fn irSharedVregs(s IrSplitting, f IrFn, counts {i64: i64}, vectors bool):
	both = []
	for v, n in counts:
		if s.named[v] > n and
			(f.classes[v] == irVec if vectors else f.classes[v] != irVec and
					(v >= s.remade.len or not s.remade[v])):
			both.push(v)
	both.sort()
	both

# whether each block is one of these
fn irInside(f IrFn, blocks i64[]):
	inside = fill(f.blocks.len, false)
	for b in blocks:
		inside[b] = true
	inside

# the one block a loop (its blocks inside) is entered at: its first, or where the jumps into it
# were threaded; none when it is entered at two
fn irLoopEntry(f IrFn, inside bool[]) i64?:
	top = -1
	for b in 0..f.blocks.len:
		if inside[b]: continue
		for s in f.irBlockSuccessors(b):
			if inside[s] and top >= 0 and s != top: return none
			if inside[s]:
				top = s
	if top < 0: return none
	top

# The vregs whose one assignment is a constant or an address of the frame or of data: the
# registers write them where they are read (irAllocateConstants), so a loop's copy would only
# take a register.
fn irRemade(f IrFn):
	isConst, isFrame, isData, _ = f.irAllocateConstants()
	(0..f.classes.len).map(isConst[it] or isFrame[it] or isData[it])

# The loops no other loop is inside, none sharing a block: the loop that is the smallest of
# each of its blocks.
fn irInnermostLoops(f IrFn):
	smallest = fill(f.blocks.len, -1)   # each block's smallest loop
	for li, l in f.loops:
		for b in l.blocks:
			if smallest[b] < 0 or l.blocks.len < f.loops[smallest[b]].blocks.len:
				smallest[b] = li
	claimed = fill(f.blocks.len, false)
	inner = []
	for li, l in f.loops:
		if l.blocks.isEmpty or l.blocks.any(smallest[it] != li or claimed[it]): continue
		for b in l.blocks:
			claimed[b] = true
		inner.push(li)
	inner

# block b's way k (0 target, 1 other) sent to block to
fn irSendWay(mut f IrFn, b i64, k i64, to i64):
	if k == 0:
		f.blocks[b].insts[len - 1].target = to
	else:
		f.blocks[b].insts[len - 1].other = to

# block b's way k sent to block to, the predecessors kept
fn irRedirect(mut f IrFn, b i64, k i64, to i64, mut preds i64[,]):
	t = f.blocks[b].insts[len - 1]
	old = t.target if k == 0 else t.other
	f.irSendWay(b, k, to)
	if old != to and not (0..f.irNextCount(b)).any(f.irNextAt(b, it) == old):
		if preds[old].indexOf(b) is at: preds[old].remove(at)
	if b not in preds[to]: preds[to].push(b)

# the block put on the way from b to to joins each loop around loop li that holds both (loopsOf:
# the loops each block belongs to)
fn irJoinLoops(mut f IrFn, li i64, b i64, to i64, put i64, mut loopsOf i64[,]):
	for o in loopsOf[b].copy():
		if o != li and o in loopsOf[to] and o not in loopsOf[put]:
			f.loops[o].blocks.push(put)
			loopsOf[put].push(o)

# inst with each vreg own names (own[v] >= 0) read and written as that one
fn irRenamed(inst IrInst, own i64[]):
	r = inst.copy()
	if r.dst >= 0 and own[r.dst] >= 0: r.dst = own[r.dst]
	if r.a >= 0 and own[r.a] >= 0: r.a = own[r.a]
	if r.c >= 0 and own[r.c] >= 0: r.c = own[r.c]
	if irReadsBD(r.op):
		if r.b >= 0 and own[r.b] >= 0: r.b = own[r.b]
		if r.d >= 0 and own[r.d] >= 0: r.d = own[r.d]
	for i in 0..r.args().len:
		if own[r.args()[i]] >= 0: r.instPart().args[i] = own[r.args()[i]]
	r
