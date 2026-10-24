# Values given a register through a loop (iropt.zap), as LLVM's greedy allocator splits them at
# loop boundaries: each vreg a loop and the code outside it both name is a vreg of its own in the
# loop, copied in on the ways into the loop and back out on the ways out of it (the copies cost
# nothing where both take the same register). A vector, in a loop that calls nothing: a call keeps
# only an xmm register's low half, so a vector live across one lives in a slot everywhere
# (irregs.zap), and the loop's copy crosses no call. An integer or a float, in an innermost loop:
# one that lives through the function and gives its register up outside may hold one in the hot
# loop, weighed by its uses there alone; copied in where it lives into the loop, and out where it
# lives on after unless the loop only reads it and it is assigned once (the one outside then has a
# hole for the loop's stretch, or the two hold one value: irMirrors).

# whether a loop's vregs were split from those outside it
fn irSplitLoops(mut f IrFn):
	any = false
	live = f.irLiveness(f.irLayout(), true)   # (its vregs are none remade)
	remade = f.irRemade()
	defs = f.irDefCounts()
	for li in f.irInnermostLoops():
		if f.irSplitLoop(li, live, true, remade, defs):
			any = true
	for li in 0..f.loops.len:
		if f.irSplitLoop(li, live, false, remade, defs):
			any = true
	any

# the loop li's vectors split, or its integers and floats (scalars), copied by their liveness
fn irSplitLoop(mut f IrFn, li i64, live IrLive, scalars bool, remade bool[], mut defs i64[]):
	blocks = f.loops[li].blocks.copy()
	if blocks.isEmpty: return false
	inside = f.irInside(blocks)
	top = f.irLoopEntry(inside) ?? return false
	for b in blocks:
		insts = f.blocks[b].insts
		# a way on that is not a jump or a branch (falling through, a switch) keeps the loop as it is
		if insts.isEmpty or insts[len - 1].op not in [irJmp, irBranch, irBranchBit, irRet]:
			return false
		if not scalars and insts.any(irCalls(.op)): return false
	vregs = f.irSharedVregs(inside, not scalars, remade)
	if vregs.isEmpty: return false
	ways = f.irWaysInto(top, blocks) ?? return false
	own = fill(f.classes.len, -1)   # each shared vreg's in the loop
	for v in vregs:
		own[v] = f.irVreg(f.classes[v])
		defs.push(1)
	for b in blocks:
		for k in 0..f.blocks[b].insts.len:
			f.blocks[b].insts[k] = f.blocks[b].insts[k].irRenamed(own)
	read = []   # those copied in
	written = []   # those copied out: a vector's for every way out, a scalar's where it lives on
	for v in vregs:
		if blocks.any(f.blocks[it].insts.any(.dst == own[v])) or scalars and defs[v] != 1:
			written.push(v)
		if scalars:
			if live.irLiveAt(top, v): read.push(v)
		elif blocks.any(f.blocks[it].insts.any(.irReadsVreg(own[v]))):
			read.push(v)
	entry = f.irBlock()
	f.blocks[entry].insts = read.map(IrInst(op = irCopy, dst = own[it], a = it))
	f.blocks[entry].insts.push(IrInst(op = irJmp, target = top))
	for (b, k) in ways:
		f.irSendWay(b, k, entry)
		f.irJoinLoops(li, b, top, entry)
	for b in blocks:
		t = f.blocks[b].insts[f.blocks[b].insts.len - 1].copy()
		for k in 0..(0 if t.op == irRet else 1 if t.op == irJmp else 2):
			to = t.target if k == 0 else t.other
			if to < 0 or inside[to]: continue
			after = written.filter(live.irLiveAt(to, it)) if scalars else written.copy()
			for v in after:
				defs[v] += 1
			out = f.irBlock()
			f.blocks[out].insts = after.map(IrInst(op = irCopy, dst = it, a = own[it]))
			f.blocks[out].insts.push(IrInst(op = irJmp, target = to))
			f.irSendWay(b, k, out)
			f.irJoinLoops(li, b, to, out)
	true

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

# the vregs named both in the loop's blocks and elsewhere: its vectors, or its integers and floats
# but those made again where they are read (irRemade)
fn irSharedVregs(f IrFn, inside bool[], vectors bool, remade bool[]):
	nv = f.classes.len
	inLoop = fill(nv, false)
	outside = fill(nv, false)
	for b in 0..f.blocks.len:
		looped = inside[b]
		for inst in f.blocks[b].insts:
			for v in inst.irReads():
				irNoteNamed(v, looped, inLoop, outside)
			if inst.dst >= 0:
				irNoteNamed(inst.dst, looped, inLoop, outside)
	(0..nv).filter(
		inLoop[it] and outside[it] and
			(f.classes[it] == irVec if vectors else f.classes[it] != irVec and
					(it >= remade.len or not remade[it]))
	)

fn irNoteNamed(v i64, looped bool, mut inLoop bool[], mut outside bool[]):
	if looped:
		inLoop[v] = true
	else:
		outside[v] = true

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

# the block put on the way from b to to joins each loop around loop li that holds both
fn irJoinLoops(mut f IrFn, li i64, b i64, to i64, put i64):
	for o in 0..f.loops.len:
		if o != li and b in f.loops[o].blocks and to in f.loops[o].blocks:
			f.loops[o].blocks.push(put)

# inst with each vreg own names (own[v] >= 0) read and written as that one
fn irRenamed(inst IrInst, own i64[]):
	r = inst.copy()
	if r.dst >= 0 and own[r.dst] >= 0: r.dst = own[r.dst]
	if r.a >= 0 and own[r.a] >= 0: r.a = own[r.a]
	if r.c >= 0 and own[r.c] >= 0: r.c = own[r.c]
	if irReadsBD(r.op):
		if r.b >= 0 and own[r.b] >= 0: r.b = own[r.b]
		if r.d >= 0 and own[r.d] >= 0: r.d = own[r.d]
	for i in 0..r.args.len:
		if own[r.args[i]] >= 0: r.args[i] = own[r.args[i]]
	r
