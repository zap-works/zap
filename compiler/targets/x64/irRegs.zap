# Registers for the intermediate form's vregs (ir.zap): the blocks laid out in reverse postorder,
# liveness by the flow between them, one interval per vreg (from its first to its last live
# point) and a linear scan over the intervals. A vreg that lives past a block lives only in the
# stretches of the blocks it is live in (IrRanges): another vreg takes its register in the holes
# between them, so a module scalar reloaded after each call, or a value of one arm of a large
# match, holds its register only where it is used. A vreg live across a call takes a register calls
# keep (rbx, rbp, r12..r15, xmm6..xmm15) or a frame slot; on x64 an integer across calls may instead
# take a register calls lose, kept in its slot around each of them (saved), when those calls are
# fewer than its uses (a list's growth in a loop that reads it each turn); a vector across a call a
# slot (calls keep only an xmm register's low half); a constant takes none (each use writes it).
# rax, rcx, rdx, xmm0 and xmm1 stay free for the code of each instruction; r8 and r9 hold a
# vreg only where no call or division sets them and after the arguments came in. AArch64 has a set
# of its own, by its own numbers (irArmPools).

type IrRegs:
	order i64[]   # the blocks in their layout order (those reached)
	reg i64[]   # each vreg's register (x64 number, or xmm number; AArch64's x or v), -1 for none
	spilled bool[]   # in a frame slot instead
	isConst bool[]   # its one definition is a constant: written where it is read
	isFrame bool[]   # its one definition is an address in the frame: constVal as rbp saw it (irDisp)
	isData bool[]   # its one definition is the address of data (irDataAddr): constVal its offset,
#   reached rip-relative
	constVal i64[]
	weight i64[]   # what a slot instead of a register costs: each read and write, eight times as
#   much a loop deeper
	saved bool[]   # in a register calls lose: written to its frame slot before each call it lives
#   across, read back after
	saveAt {i64: i64[]} = {}   # by irInstKey: the saved vregs a call is made between
	arm bool = false   # for AArch64 (irKept: told, as the passes run as jobs)
	slotOf i64[] = []   # a spilled vreg's: the vreg whose slot it shares (irShareSlots), itself for most

# the registers a call loses: r10 and r11 first, which no function saves (a leaf that needs no
# more keeps no frame), then rsi and rdi, which the runtime's stubs use without saving them but
# this form's functions save, as the Windows convention wants
irScratchInt = [10, 11]
irCallerInt = [6, 7]
irCalleeInt = [3, 5, 12, 13, 14, 15]   # rbx, rbp, r12..r15
irCallerFloat = [2, 3, 4, 5]
irCalleeFloat = [6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

# the integer registers a call loses that a vreg across calls may take, saved around them (r8 and
# r9 carry the arguments)
fn irLostInts():
	lost = irScratchInt.copy()
	lost.extend(irCallerInt)
	lost

# AArch64's registers (a64Ir.zap): x9..x14 lost by calls, x0..x7 as well where none of the
# instructions whose code uses them meets the vreg (a64Clobbers) and after the arguments came in,
# x19..x28 kept; v16..v19 and v22..v31 lost, v8..v15 kept (their low halves, as AAPCS64's) and v20,
# v21 (Zap's calls keep them too). A function with a vector of 32 bytes leaves v22..v31 and v3..v6
# to those vectors' upper halves (a64VecHighRegs).
irArmLostInt = [9, 10, 11, 12, 13, 14]
irArmArgInt = [0, 1, 2, 3, 4, 5, 6, 7]
irArmKeptInt = [19, 20, 21, 22, 23, 24, 25, 26, 27, 28]
irArmLostFloat = [16, 17, 18, 19]
irArmHighFloat = [22, 23, 24, 25, 26, 27, 28, 29, 30, 31]
irArmKeptFloat = [8, 9, 10, 11, 12, 13, 14, 15, 20, 21]

# the blocks reached from the entry, in reverse postorder: a loop's body after its test, the
# way out after the loop
fn irLayout(f IrFn):
	n = f.blocks.len
	seen = fill(n, false)
	post = []
	stack = [(0, 0)]   # (block, successors visited)
	seen[0] = true
	while not stack.isEmpty:
		b, next = stack[len - 1]
		count = f.irNextCount(b)
		if next < count:
			stack[len - 1] = b, next + 1
			s = f.irNextAt(b, count - 1 - next)   # the last first: the first comes out first
			if not seen[s]:
				seen[s] = true
				stack.push((s, 0))
		else:
			post.push(b)
			stack.pop()
	post.reversed()

# f's registers; arm: for AArch64 (told, not read from the build's target: the passes run as jobs,
# irPipe.zap)
fn irAllocate(f IrFn, arm bool):
	order = f.irLayout()
	nv = f.classes.len
	isConst, isFrame, isData, constVal = f.irAllocateConstants()
	live = f.irLiveness(order, true)
	# positions: two per instruction in layout order
	start = fill(nv, 1 << 60)
	end = fill(nv, -1)
	hint = fill(nv, -1)   # the vreg a vreg is first made from (its register is wanted)
	weight = zeros(nv)
	ranges = live.irRangesFor()
	often = f.irBlockWeights(order)
	paramEnd = f.irAllocateIntervals(order, live, start, end, hint, weight, ranges, often)
	mirror = f.irMirrors()
	reg, spilled, saved = f.irAllocateScan(
		live,
		mirror,
		often,
		start,
		end,
		hint,
		weight,
		ranges,
		isConst,
		isFrame,
		isData,
		paramEnd,
		arm
	)
	saveAt {i64: i64[]} = {}
	if saved.any(it):
		f.irCallFacts(live, often, saved, saveAt, arm)
	slotOf = f.irShareSlots(live, mirror, start, end, ranges, spilled)
	IrRegs(
		order,
		reg,
		spilled,
		isConst,
		isFrame,
		isData,
		constVal,
		weight,
		saved,
		saveAt,
		arm,
		slotOf
	)

# Spill slots shared: a copy between two spilled vregs of a class, which never live at once (a
# loop's own vreg and the one outside it, irLoopSplit.zap), gives both one slot, the copy then no
# code. Each vreg's slot is its root's, its own for most.
fn irShareSlots(
	f IrFn,
	live IrLive,
	mirror i64[],
	start i64[],
	end i64[],
	ranges IrRanges,
	spilled bool[]
):
	nv = f.classes.len
	root = (0..nv).map(it)
	members = []
	for v in 0..nv:
		members.push([v])
	for blk in f.blocks:
		for inst in blk.insts:
			if inst.op != irCopy or inst.dst < 0 or inst.a < 0 or not spilled[inst.dst] or
				not spilled[inst.a] or f.classes[inst.dst] != f.classes[inst.a] or
				f.classes[inst.dst] == irVec:
				continue
			x = root[inst.dst]
			y = root[inst.a]
			if x == y or f.irClassesMeet(live, mirror, start, end, ranges, members[x], members[y]):
				continue
			for m in members[y]:
				root[m] = x
			moved = members[y].copy()
			members[x].extend(moved)
			members[y].clear()
	root

# whether a vreg of one class lives at once with one of the other (but its mirror)
fn irClassesMeet(
	f IrFn,
	live IrLive,
	mirror i64[],
	start i64[],
	end i64[],
	ranges IrRanges,
	xs i64[],
	ys i64[]
):
	for p in xs:
		for q in ys:
			if mirror[p] == q or mirror[q] == p: continue
			first = p if start[p] <= start[q] else q
			second = q if first == p else p
			if ranges.irLiveAtOnce(live, start, end, first, second): return true
	false

# How often each block runs, as the registers weigh it (block frequencies guessed, as LLVM's
# greedy allocator weighs its uses): the entry 256 times, a loop's first block eight times what
# enters it (up to a depth of six), a block's count split among its ways on (a rare one, a list's
# growth, taking 1/64 of a common one's share), and a loop's ways out sharing what entered it.
fn irBlockWeights(f IrFn, order i64[]):
	loopsOf = f.irLoopsOf()
	pos = f.irLayoutPos(order)
	header = fill(f.loops.len, -1)   # each loop's block first in the layout
	exitShares = zeros(f.loops.len)
	for li, l in f.loops:
		for b in l.blocks:
			if pos[b] >= 0 and (header[li] < 0 or pos[b] < pos[header[li]]): header[li] = b
			for s in f.irBlockSuccessors(b):
				if li not in loopsOf[s]: exitShares[li] += f.irWayShare(s)
	entered = zeros(f.loops.len)
	count = zeros(f.blocks.len)
	count[order[0]] = 256
	for b in order:
		at = count[b]
		for li in loopsOf[b]:
			if header[li] == b:
				entered[li] = at
				if loopsOf[b].len <= 6: count[b] *= 8
		shares = 0
		for s in f.irBlockSuccessors(b):
			shares += f.irWayShare(s)
		for s in f.irBlockSuccessors(b):
			if pos[s] <= pos[b]: continue   # back to a loop's top
			left = -1   # the outermost loop the way leaves
			for li in loopsOf[b]:
				if li not in loopsOf[s] and
					(left < 0 or f.loops[li].blocks.len > f.loops[left].blocks.len):
					left = li
			if left < 0:
				count[s] += count[b] * f.irWayShare(s) / shares
			elif exitShares[left] > 0:
				count[s] += entered[left] * f.irWayShare(s) / exitShares[left]
	count.map(.max(1))

# a way's share of its block's count: a rare block's 1/64 of a common one's
fn irWayShare(f IrFn, b i64):
	1 if f.blocks[b].cold else 64

# how many instructions assign each vreg (reached or not)
fn irDefCounts(f IrFn):
	defs = zeros(f.classes.len)
	for blk in f.blocks:
		for inst in blk.insts:
			if inst.dst >= 0:
				defs[inst.dst] += 1
	defs

# The vreg each vreg is a copy of when both are assigned once (a loop's own copy of a value the
# loop only reads, irLoopSplit.zap): the two hold one value, so they may share a register or a
# slot though they live at once; -1 for the others.
fn irMirrors(f IrFn):
	defs = f.irDefCounts()
	mirror = fill(f.classes.len, -1)
	for blk in f.blocks:
		for inst in blk.insts:
			v = inst.dst
			a = inst.a
			if inst.op == irCopy and v >= 0 and a >= 0 and defs[v] == 1 and defs[a] == 1 and
				f.classes[v] == f.classes[a] and f.classes[v] != irVec:
				mirror[v] = a
	mirror

fn irAllocateConstants(f IrFn):
	nv = f.classes.len
	# constants: a vreg whose only definition (reached or not: a copied block keeps its constants) is irConst
	defs = f.irDefCounts()
	constVal = zeros(nv)
	constDef = fill(nv, false)
	frameDef = fill(nv, false)
	dataDef = fill(nv, false)
	for blk in f.blocks:
		for inst in blk.insts:
			if inst.dst >= 0:
				constDef[inst.dst] = inst.op == irConst
				frameDef[inst.dst] = inst.op == irFrameAddr or inst.op == irFrameSlot
				dataDef[inst.dst] = inst.op == irDataAddr
				constVal[inst.dst] = inst.imm
	isConst = (0..nv).map(defs[it] == 1 and constDef[it])
	isFrame = (0..nv).map(defs[it] == 1 and frameDef[it])
	isData = (0..nv).map(defs[it] == 1 and dataDef[it])
	(isConst, isFrame, isData, constVal)

fn irAllocateIntervals(
	f IrFn,
	order i64[],
	live IrLive,
	mut start i64[],
	mut end i64[],
	mut hint i64[],
	mut weight i64[],
	mut ranges IrRanges,
	often i64[]
):
	paramEnd = -1   # r8 and r9 also carry arguments in, read by here
	pos = 0
	for b in order:
		w = often[b]
		for inst in f.blocks[b].insts:
			for v in inst.irReads():
				weight[v] += w
			if inst.dst >= 0:
				weight[inst.dst] += w
		bs = pos
		for g in live.liveIn[b]:
			v = live.vregs[g]
			start[v] = start[v].min(bs)
			end[v] = end[v].max(bs)
			ranges.irTouch(g, bs)
		for inst in f.blocks[b].insts:
			for v in inst.irReads():
				start[v] = start[v].min(pos)
				end[v] = end[v].max(pos)
				if live.number[v] >= 0: ranges.irTouch(live.number[v], pos)
			if inst.dst >= 0 and hint[inst.dst] < 0 and inst.a >= 0 and inst.op != irLoad:
				fma = inst.op == irVecOp and inst.cond == 1
				hint[inst.dst] = inst.c if fma else inst.a   # an FMA writes over its accumulator
			if inst.dst >= 0:
				start[inst.dst] = start[inst.dst].min(pos)
				end[inst.dst] = end[inst.dst].max(pos)
				if live.number[inst.dst] >= 0: ranges.irTouch(live.number[inst.dst], pos)
			if inst.op == irParam:
				paramEnd = pos
			pos += 2
		be = pos - 1   # past the block's last instruction: what it writes cannot take the register
		for g in live.liveOut[b]:
			v = live.vregs[g]
			start[v] = start[v].min(be)
			end[v] = end[v].max(be)
			ranges.irTouch(g, be)
		ranges.irFlush()
	f.irWeighCarried(live, weight)
	paramEnd

# A vector carried around a loop (live into the block it is entered at, assigned in it) weighs
# twice: in a slot, its store and its load join the chain of every turn.
fn irWeighCarried(f IrFn, live IrLive, mut weight i64[]):
	doubled = fill(f.classes.len, false)
	for l in f.loops:
		top = f.irLoopEntry(f.irInside(l.blocks)) ?? continue
		for b in l.blocks:
			for inst in f.blocks[b].insts:
				v = inst.dst
				if v < 0 or doubled[v] or f.classes[v] != irVec or live.number[v] < 0: continue
				if live.liveIn[top].irRowHas(live.number[v]):
					weight[v] *= 2
					doubled[v] = true

fn irAllocateScan(
	f IrFn,
	live IrLive,
	mirror i64[],
	often i64[],
	start i64[],
	end i64[],
	hint i64[],
	weight i64[],
	ranges IrRanges,
	isConst bool[],
	isFrame bool[],
	isData bool[],
	paramEnd i64,
	arm bool
):
	nv = f.classes.len
	noSaves {i64: i64[]} = {}
	facts = f.irCallFacts(live, often, [], noSaves, arm)
	narrow = f.irNarrowVectors()
	reg = fill(nv, -1)
	spilled = fill(nv, false)
	saved = fill(nv, false)
	todo = (0..nv)
		.filter(end[it] >= 0 and not isConst[it] and not isFrame[it] and not isData[it])
		.sortedBy(start[it])
	# the registers a vreg may take, by whether it crosses a call, is a float or vector, and may
	# hold r8 and r9 (irPool)
	pools = irPools(arm, (0..nv).any(f.classes[it] == irVec and not narrow[it]))
	active i64[] = []
	for v in todo:
		# an interval that ends where this one starts (its last read, this one's first write) frees
		# its register for it
		kept = 0
		for i in 0..active.len:
			if end[active[i]] > start[v]:
				active[kept] = active[i]
				kept += 1
		active.truncate(kept)
		bank = irBank(f.classes[v])
		class = irFloat if narrow[v] else f.classes[v]   # (a call keeps an xmm register's 16 bytes)
		pick = irPool(facts.across[v], class, start[v] > paramEnd and not facts.met[v])
		if arm and f.classes[v] == irVec and facts.across[v]:
			pick = 5   # (AArch64's calls keep only a vector register's low 8 bytes)
		pool = pools[pick]
		taken = 0   # the registers of the bank the active intervals live in v's ranges hold, a bit each
		blockers = []
		for a in active:
			if a == mirror[v]: continue   # (one value: the register is shared)
			if irBank(f.classes[a]) == bank and ranges.irLiveAtOnce(live, start, end, a, v):
				taken |= 1 << reg[a]
				blockers.push(a)
		h = hint[v]
		if h >= 0 and irBank(f.classes[h]) == bank and reg[h] >= 0 and reg[h] in pool and
			(taken >> reg[h]) & 1 == 0:
			reg[v] = reg[h]
			active.push(v)
			continue
		if pool.find((taken >> it) & 1 == 0) is r:
			reg[v] = r
			active.push(v)
			continue
		# none free: the register whose intervals in v's way are the cheapest to keep in slots for
		# the stretches they hold it gives them up (v, when it is): few reads over a long stretch
		# go first. One calls lose costs v its saves around them besides.
		costs = zeros(32)   # per register: what keeping its holders in v's way in slots costs
		for a in blockers:
			costs[reg[a]] += f.irSpillCost(weight, start, end, a)
		freed = -1
		for a in blockers:
			if reg[a] in pool and (freed < 0 or costs[reg[a]] < costs[freed]):
				freed = reg[a]
		best = f.irSpillCost(weight, start, end, v)
		if freed >= 0 and costs[freed] < best:
			best = costs[freed]
		else:
			freed = -1
		around = f.classes[v] == irInt and facts.across[v] and not arm
		saves = f.irScaledCost(facts.saveCost[v], start, end, v)
		for r in (irLostInts() if around else []):
			if costs[r] + saves < best:
				best = costs[r] + saves
				freed = r
		if freed >= 0:
			for a in blockers:
				if reg[a] == freed:
					reg[a] = -1
					spilled[a] = true
					saved[a] = false
			active = active.filter(reg[it] >= 0)
			reg[v] = freed
			saved[v] = freed not in pool
			active.push(v)
		else:
			spilled[v] = true
	(reg, spilled, saved)

# the vectors of 16 bytes: each of their assignments makes 16 bytes or fewer (a load, a splat, an
# AVX operation of 128 bits, a copy of such a vector, a constant)
fn irNarrowVectors(f IrFn):
	narrow = f.classes.map(it == irVec)
	again = true
	while again:
		again = false
		for b in f.blocks:
			for inst in b.insts:
				v = inst.dst
				if v < 0 or not narrow[v]: continue
				op = inst.op
				fits = op == irConst or
					(op == irLoad or op == irVecSplat) and inst.size <= 16 or
					op == irVecOp and (inst.imm >> 5) & 1 == 0 or
					op == irCopy and inst.a >= 0 and narrow[inst.a]
				if not fits:
					narrow[v] = false
					again = true
	narrow

# The stretches each vreg that lives past a block lives in, by its liveness number: a block's
# stretch from its start, or where the vreg is first met in it, to past its end, or where it is
# last met, those of blocks one after the other in the layout joined.
type IrRanges:
	of i64[,]   # per number: the stretches, a start and an end each, in rising order
	lo i64[]   # per number: its stretch in the block being walked, -1 for none yet
	hi i64[]
	met i64[]   # the numbers met in that block

fn irRangesFor(live IrLive):
	n = live.vregs.len
	of i64[,] = []
	loop n:
		of.push([])
	IrRanges(of, lo = fill(n, -1), hi = fill(n, -1), met = [])

# number g met at position p in the block being walked
fn irTouch(mut rr IrRanges, g i64, p i64):
	if rr.lo[g] < 0:
		rr.lo[g] = p
		rr.hi[g] = p
		rr.met.push(g)
	else:
		rr.lo[g] = rr.lo[g].min(p)
		rr.hi[g] = rr.hi[g].max(p)

# the block walked: its stretches added
fn irFlush(mut rr IrRanges):
	for g in rr.met:
		alias xs = rr.of[g]
		if not xs.isEmpty and xs[len - 1] + 1 >= rr.lo[g]:
			xs[len - 1] = xs[len - 1].max(rr.hi[g])
		else:
			xs.push(rr.lo[g])
			xs.push(rr.hi[g])
		rr.lo[g] = -1
	rr.met.clear()

fn irRangeCount(rr IrRanges, live IrLive, v i64):
	g = live.number[v]
	1 if g < 0 else rr.of[g].len / 2

fn irRangeStart(rr IrRanges, live IrLive, start i64[], v i64, i i64):
	g = live.number[v]
	start[v] if g < 0 else rr.of[g][2 * i]

fn irRangeEnd(rr IrRanges, live IrLive, end i64[], v i64, i i64):
	g = live.number[v]
	end[v] if g < 0 else rr.of[g][2 * i + 1]

# Whether a and v (a no later than v) live at once: a stretch of one starts within one of the
# other, so a write of one would land where the other is still read. Stretches that only touch,
# one ending where the other starts (its last read, the other's first write), do not meet.
fn irLiveAtOnce(rr IrRanges, live IrLive, start i64[], end i64[], a i64, v i64):
	if live.number[a] < 0 and live.number[v] < 0: return true   # one stretch each, a's past v's start
	na = rr.irRangeCount(live, a)
	nv = rr.irRangeCount(live, v)
	from = start[v]
	# the first of a's stretches that does not end before v's first starts
	lo = 0
	hi = na
	while lo < hi:
		mid = (lo + hi) / 2
		if rr.irRangeEnd(live, end, a, mid) < from:
			lo = mid + 1
		else:
			hi = mid
	i = lo
	j = 0
	while i < na and j < nv:
		s1 = rr.irRangeStart(live, start, a, i)
		e1 = rr.irRangeEnd(live, end, a, i)
		s2 = rr.irRangeStart(live, start, v, j)
		e2 = rr.irRangeEnd(live, end, v, j)
		if (s1 <= s2 and s2 < e1) or (s2 <= s1 and s1 < e2): return true
		if e1 <= e2:
			i += 1
		else:
			j += 1
	false

# what keeping v in a slot costs: its reads and writes, weighed by loop depth; a vector's for each
# position it would hold a register (vectors are many and short-lived where they are used), an
# integer's or a float's for each 64 (one that lives through a whole function and is read seldom
# gives its register to the temporaries of a loop, an unrolled carry chain's among them)
fn irSpillCost(f IrFn, weight i64[], start i64[], end i64[], v i64):
	f.irScaledCost(weight[v], start, end, v)

# a cost of v's (its reads and writes, or its saves around calls) for each stretch it holds a register
fn irScaledCost(f IrFn, cost i64, start i64[], end i64[], v i64):
	span = end[v] - start[v]
	cost * 4096 / (span + 2 if f.classes[v] == irVec else span / 64 + 1)

# the pools of irPool's choices: integers that cross no call (r8 and r9 among them or not),
# floats that cross none, integers and floats that cross one, vectors that cross one (none: a
# call keeps only an xmm register's low half); AArch64's (arm) by its own numbers, wide when the
# function has a vector of 32 bytes
fn irPools(arm bool, wide bool):
	if arm: return irArmPools(wide)
	kept = irCalleeInt.copy()
	free = irScratchInt.copy()
	free.extend([8, 9])   # the argument registers, where nothing sets them
	free.extend(irCallerInt)
	free.extend(kept)
	plain = irLostInts()
	plain.extend(kept)
	floats = irCallerFloat.copy()
	floats.extend(irCalleeFloat)
	[free, plain, floats, kept, irCalleeFloat.copy(), []]

fn irArmPools(wide bool):
	plain = irArmLostInt.copy()
	plain.extend(irArmKeptInt)
	free = irArmLostInt.copy()
	free.extend(irArmArgInt)
	free.extend(irArmKeptInt)
	floats = irArmLostFloat.copy()
	if not wide: floats.extend(irArmHighFloat)
	floats.extend(irArmKeptFloat)
	[free, plain, floats, irArmKeptInt.copy(), irArmKeptFloat.copy(), []]

# the pool (irPools) of a vreg of the class, crossing a call or not, r8 and r9 free for it or not
fn irPool(crosses bool, class i64, argRegs bool):
	if crosses: return 3 if class == irInt else 4 if class == irFloat else 5
	if class != irInt: return 2
	0 if argRegs else 1

# The vregs live across a call (read on some way on from it before they are written again: a
# value only read on the ways that do not call keeps a register calls lose, though its interval
# spans the call), and those a call or a division meets at all (read by it, or live across it),
# which r8 and r9 cannot hold: a call sets them, and a division by a constant uses r8 (on AArch64
# (arm), x0..x7 the same, by a64Clobbers, which also gives the vreg such an instruction writes).
# With the saved vregs given (irRegs.saved), each call's saved vregs live across it put in saveAt.
type IrCallFacts:
	across bool[]
	met bool[]
	saveCost i64[]   # a write and a read for each call it lives across, by how often its block runs

fn irCallFacts(
	f IrFn,
	live IrLive,
	often i64[],
	saved bool[],
	mut saveAt {i64: i64[]},
	arm bool
):
	nv = f.classes.len
	words = live.words
	across = zeros(words)   # the vregs liveness numbers, a bit each as its sets
	met = zeros(words)
	acrossV = fill(nv, false)
	metV = fill(nv, false)
	cost = zeros(nv)
	costOf = zeros(live.vregs.len)   # by liveness number
	walk = live.irWalkFor(nv)
	for b in 0..f.blocks.len:
		insts = f.blocks[b].insts
		if not insts.any(f.irClobbersArgs(it, arm)): continue
		walk.irWalkFrom(live, b)
		k = insts.len - 1
		while k >= 0:
			inst = insts[k]
			if inst.dst >= 0:
				walk.irWalkKill(live, inst.dst)
			if f.irClobbersArgs(inst, arm):
				call = irCalls(inst.op)
				if arm and inst.dst >= 0: metV[inst.dst] = true
				for w in walk.dirty:
					met[w] |= walk.set[w]
					if call: across[w] |= walk.set[w]
				walk.irWalkCompact()
				for v in walk.locals:
					metV[v] = true
					if call: acrossV[v] = true
				for v in inst.irReads():
					metV[v] = true
				if call:
					walk.irWalkCosts(2 * often[b], cost, costOf)
					if not saved.isEmpty:
						at = walk.irWalkSaved(live, saved)
						if not at.isEmpty: saveAt[irInstKey(b, k)] = at
			for v in inst.irReads():
				walk.irWalkGen(live, v)
			k -= 1
	for g, v in live.vregs:
		if (across[g >> 6] >> (g & 63)) & 1 != 0: acrossV[v] = true
		if (met[g >> 6] >> (g & 63)) & 1 != 0: metV[v] = true
		cost[v] = costOf[g]
	IrCallFacts(across = acrossV, met = metV, saveCost = cost)

# w added to the cost of each vreg live here
fn irWalkCosts(w IrLiveWalk, add i64, mut cost i64[], mut costOf i64[]):
	for v in w.locals:
		cost[v] += add
	for i in w.dirty:
		bits = u64(w.set[i])
		while bits != 0:
			costOf[i * 64 + bits.trailingZeros()] += add
			bits &= bits - 1

# the saved vregs live here
fn irWalkSaved(mut w IrLiveWalk, live IrLive, saved bool[]):
	out = w.locals.filter(saved[it])
	w.dirty.sort()
	for i in w.dirty:
		bits = u64(w.set[i])
		while bits != 0:
			v = live.vregs[i * 64 + bits.trailingZeros()]
			if saved[v]: out.push(v)
			bits &= bits - 1
	out

# whether an operation sets r8 or r9: a call, or a division (by a constant: through r8); on
# AArch64 (arm), whether it sets x0..x7
fn irClobbersArgs(f IrFn, inst IrInst, arm bool):
	if arm: return f.a64Clobbers(inst)
	irCalls(inst.op) or inst.op == irDiv or inst.op == irRem

# the registers a class takes: 0 the integer ones, 1 the xmm ones (floats and vectors share them)
fn irBank(class i64):
	0 if class == irInt else 1

# The vregs live into and out of each block. Only those that live past a block take part: a
# vreg met in one block only, written there before it is read, lives nowhere else; for the
# registers (remade), one remade where it is read (assigned once a constant or an address:
# irAllocateConstants) takes none and counts as live everywhere (a huge function's frame slots,
# one an inlined call, would each fill every block's set), and otherwise such a vreg read past
# its making (irReadPastMaking) does; the others are numbered compactly,
# and each block keeps the numbers live there in rising order, so a function of thousands of
# blocks and vregs keeps sets as small as what lives.
type IrLive:
	words i64   # the words of a walk's set: bit g & 63 of word g >> 6 for the vreg numbered g
	number i64[]   # each vreg's number, -1 for one of a single block, -2 for one remade
	vregs i64[]   # each number's vreg
	liveIn i64[,]   # block b's numbers, rising
	liveOut i64[,]

fn irLiveness(f IrFn, order i64[], remade bool):
	nv = f.classes.len
	n = f.blocks.len
	home = fill(nv, -1)   # the block each vreg was first met in
	crosses = fill(nv, false)
	for b in 0..n:
		for inst in f.blocks[b].insts:
			for v in inst.irReads():
				if home[v] != b: crosses[v] = true   # met elsewhere, or read before it is written
				home[v] = b
			if inst.dst >= 0:
				if home[inst.dst] >= 0 and home[inst.dst] != b: crosses[inst.dst] = true
				home[inst.dst] = b
	isConst, isFrame, isData, _ = f.irAllocateConstants()
	once = (0..nv).map(crosses[it] and (isConst[it] or isFrame[it] or isData[it]))
	if not remade: f.irReadPastMaking(order, once)
	number = fill(nv, -1)
	vregs = []
	for v in 0..nv:
		if once[v]:
			number[v] = -2
		elif crosses[v]:
			number[v] = vregs.len
			vregs.push(v)
	uses, defs = f.irUsesAndDefs(number, vregs.len)
	live = IrLive(words = (vregs.len + 63) / 64, number, vregs, liveIn = [], liveOut = [])
	live.irLiveFrom(f, order, uses, defs)
	live

# Of the vregs made once (once: a constant or an address, met in more than one block), those read
# past their making: in its block after it, or in a block its block dominates (a way from the
# making reaches that read). Liveness counts them live everywhere, so a pass that asks about one
# only where it is made (irDropDead) keeps it, as their sets would; the others are numbered.
fn irReadPastMaking(f IrFn, order i64[], mut once bool[]):
	d = f.irDomTree(order)
	madeIn = fill(once.len, -1)
	madeAt = zeros(once.len)
	for b in order:
		insts = f.blocks[b].insts
		for k, inst in insts:
			if inst.dst >= 0 and once[inst.dst]:
				madeIn[inst.dst] = b
				madeAt[inst.dst] = k
	read = fill(once.len, false)
	for b in order:
		insts = f.blocks[b].insts
		for k, inst in insts:
			for v in inst.irReads():
				m = madeIn[v] if once[v] else -1
				if m >= 0 and (b == m and k > madeAt[v] or b != m and d.irDominates(m, b)):
					read[v] = true
	for v in 0..once.len:
		once[v] = once[v] and (read[v] or madeIn[v] < 0)   # (one made where no walk goes: never asked)

# By number, the blocks that read it before they write it and those that write it, each once
fn irUsesAndDefs(f IrFn, number i64[], count i64):
	uses i64[,] = []
	defs i64[,] = []
	loop count:
		uses.push([])
		defs.push([])
	usedIn = fill(count, -1)   # the block that last read the number before writing it
	defIn = fill(count, -1)   # the block that last wrote it
	for b in 0..f.blocks.len:
		for inst in f.blocks[b].insts:
			for v in inst.irReads():
				g = number[v]
				if g >= 0 and defIn[g] != b and usedIn[g] != b:
					usedIn[g] = b
					uses[g].push(b)
			if inst.dst >= 0 and number[inst.dst] >= 0 and defIn[number[inst.dst]] != b:
				defIn[number[inst.dst]] = b
				defs[number[inst.dst]].push(b)
	uses, defs

# The sets found a number at a time: from each laid-out block reading it first, back through the
# laid-out ways to it until a block that writes it (the least solution of the flow's equations,
# a block's set growing only by what lives there)
fn irLiveFrom(mut live IrLive, f IrFn, order i64[], uses i64[,], defs i64[,]):
	n = f.blocks.len
	laid = fill(n, false)
	for b in order:
		laid[b] = true
	preds i64[,] = []
	loop n:
		live.liveIn.push([])
		live.liveOut.push([])
		preds.push([])
	for b in order:
		for i in 0..f.irNextCount(b):
			s = f.irNextAt(b, i)
			if laid[s]: preds[s].push(b)
	inMark = fill(n, -1)   # the number last put in each block's sets
	outMark = fill(n, -1)
	defMark = fill(n, -1)
	todo = []
	for g in 0..live.vregs.len:
		for b in defs[g]:
			defMark[b] = g
		for b in uses[g]:
			if laid[b]:
				inMark[b] = g
				live.liveIn[b].push(g)
				todo.push(b)
		while todo.pop() is x:
			for p in preds[x]:
				if outMark[p] == g: continue
				outMark[p] = g
				live.liveOut[p].push(g)
				if defMark[p] != g and inMark[p] != g:
					inMark[p] = g
					live.liveIn[p].push(g)
					todo.push(p)

# whether v lives into block b (a block made since the liveness was found: as if it did)
fn irLiveAt(live IrLive, b i64, v i64):
	g = live.number[v] if v < live.number.len else -1
	if g < 0: return g == -2
	b >= live.liveIn.len or live.liveIn[b].irRowHas(g)

# whether a block's set (its numbers, rising) holds g
fn irRowHas(row i64[], g i64):
	lo = 0
	hi = row.len
	while lo < hi:
		mid = (lo + hi) / 2
		if row[mid] < g: lo = mid + 1
		else: hi = mid
	lo < row.len and row[lo] == g

# A walk back through a block knowing the vregs live where it is: those liveness numbers by their
# bits (as its sets), the block's own one by one. Only the words set since the walk began its block
# (dirty, each once) can be nonzero, so a function of many numbers pays for what lives, not for
# its words.
type IrLiveWalk:
	set i64[]
	dirty i64[]   # the words of set that were set this block
	touched bool[]   # each word: whether it is in dirty
	on bool[]   # each vreg of a single block: whether it is live here
	locals i64[]   # those set live, some of them no longer

fn irWalkFor(live IrLive, nv i64):
	IrLiveWalk(
		set = zeros(live.words),
		dirty = [],
		touched = fill(live.words, false),
		on = zeros(nv),
		locals = []
	)

# bit g of the walk's set on
fn irWalkSet(mut w IrLiveWalk, g i64):
	i = g >> 6
	if not w.touched[i]:
		w.touched[i] = true
		w.dirty.push(i)
	w.set[i] |= 1 << (g & 63)

# the walk at block b's end: what lives out of it (no vreg of a single block does)
fn irWalkFrom(mut w IrLiveWalk, live IrLive, b i64):
	for i in w.dirty:
		w.set[i] = 0
		w.touched[i] = false
	w.dirty.clear()
	for g in live.liveOut[b]:
		w.irWalkSet(g)
	for v in w.locals:
		w.on[v] = false
	w.locals.clear()

fn irWalkHas(w IrLiveWalk, live IrLive, v i64):
	g = live.number[v]
	if g == -2: return true
	w.on[v] if g < 0 else (w.set[g >> 6] >> (g & 63)) & 1 != 0

# v written here: not live above
fn irWalkKill(mut w IrLiveWalk, live IrLive, v i64):
	g = live.number[v]
	if g == -1:
		w.on[v] = false
	elif g >= 0:
		w.set[g >> 6] &= ~(1 << (g & 63))

# v read here: live above
fn irWalkGen(mut w IrLiveWalk, live IrLive, v i64):
	g = live.number[v]
	if g >= 0:
		w.irWalkSet(g)
	elif g == -1 and not w.on[v]:
		w.on[v] = true
		w.locals.push(v)

# locals made the block's own vregs live here, each once
fn irWalkCompact(mut w IrLiveWalk):
	kept = 0
	for i in 0..w.locals.len:
		v = w.locals[i]
		if w.on[v]:
			w.on[v] = false   # kept once
			w.locals[kept] = v
			kept += 1
	w.locals.truncate(kept)
	for v in w.locals:
		w.on[v] = true

# the function's instructions with each vreg's place, for ZAP_RUN=irdump
fn irDump(f IrFn, rs IrRegs):
	for b in rs.order:
		eprint("b{b}{" (loop top)" if f.blocks[b].loopTop else ""}:")
		for inst in f.blocks[b].insts:
			eprint("  op {inst.op} dst {rs.irWhere(inst.dst)} a {rs.irWhere(inst.a)} b {rs.irWhere(inst.b)} c {rs.irWhere(inst.c)} imm {inst.imm} size {inst.size}{" uns" if inst.uns else ""}{" trap" if inst.trap else ""}{" frame" if inst.frame else ""}{" header" if inst.header else ""} cond {inst.cond} -> {inst.target}/{inst.other} {inst.key()}{inst.args()}")

fn irWhere(rs IrRegs, v i64):
	if v < 0: return "-"
	if rs.isConst[v]: return "v{v}=#{rs.constVal[v]}"
	if rs.isFrame[v]: return "v{v}=frame{rs.constVal[v]}"
	if rs.isData[v]: return "v{v}=data{rs.constVal[v]}"
	if rs.spilled[v]: return "v{v}=slot"
	"v{v}=r{rs.reg[v]}{" saved" if rs.saved[v] else ""}"
