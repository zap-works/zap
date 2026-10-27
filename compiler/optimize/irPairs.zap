# Pairs of f64 operations made one operation on both lanes of an xmm register, an SLP
# vectorization (as LLVM's) of the code structs of f64 fields make (a Vec3's x and y): in a loop's
# straight runs of blocks (each entered only by a jump from the one before), two loads of
# adjacent words become one 16-byte load, and two operations alike on the lanes of a pair, their
# other operands a pair too (a constant in both lanes, a value in both, two values put
# together), one vaddpd, vsubpd, vmulpd or vdivpd. Each lane computes what the scalar code did, in
# the same order: the result is exact. The pairs grown from one pair of loads are made when they
# save more operations than the shuffles they add: two values that change in the loop put
# together, a lane taken out for a scalar's other uses (lane 0 is read in place by arithmetic).
# Before irHoist, which takes out of the loop what puts values from before it together.

# an operand of a pair's operation: a pair's vector (x the pair), zeros, x in both lanes, or x
# and y side by side
type IrPairArg:
	kind i64
	x i64 = -1
	y i64 = -1

irArgPair = 0
irArgZero = 1
irArgDup = 2
irArgMix = 3

# two f64 vregs of a run made as one vector: by two loads, or by an operation alike on the lanes
# of its operands; made at the flat position at (the earlier load's, the later operation's)
type IrPair:
	lo i64   # lane 0's vreg
	hi i64   # lane 1's
	op i64   # irLoad, or the lanes' operation
	first i64   # the flat positions of the run of the two instructions, in order
	second i64
	at i64
	args IrPairArg[] = []   # an operation's two operands
	vec i64 = -1   # the vector, once made

# a loop's straight run of blocks: each flat position's block and index there, the innermost
# loop around it
type IrRun:
	bs i64[]
	ks i64[]
	inner i64

irPairRunMost = 2000   # a longer run is left as it is

fn irPairs(mut f IrFn):
	if f.loops.isEmpty or not f.merges.isEmpty: return
	nb = f.blocks.len
	preds = zeros(nb)
	for b in 0..nb:
		for s in f.irBlockSuccessors(b):
			preds[s] += 1
	loopsOf = f.irLoopsOf()
	# the block a run goes on to after each: the one its jump ends in, entered only from it
	next = fill(nb, -1)
	goesOn = fill(nb, false)
	for b in 0..nb:
		insts = f.blocks[b].insts
		if insts.isEmpty or loopsOf[b].isEmpty: continue
		t = insts[len - 1].target
		if insts[len - 1].op == irJmp and t != b and t != 0 and preds[t] == 1 and
			not f.blocks[t].loopTop and loopsOf[t] == loopsOf[b]:
			next[b] = t
			goesOn[t] = true
	facts = f.irFacts()
	defBlock = fill(f.classes.len, -1)
	for b in 0..nb:
		for inst in f.blocks[b].insts:
			if inst.dst >= 0:
				defBlock[inst.dst] = b
	for b in 0..nb:
		if goesOn[b] or loopsOf[b].isEmpty: continue
		run = IrRun(bs = [], ks = [], inner = loopsOf[b][0])
		at = b
		steps = 0
		while at >= 0 and steps < nb:
			for k in 0..f.blocks[at].insts.len:
				run.bs.push(at)
				run.ks.push(k)
			at = next[at]
			steps += 1
		if run.bs.len <= irPairRunMost:
			f.irPairRun(run, facts, defBlock)

# the instruction at flat position i of a run
fn irRunInst(f IrFn, run IrRun, i i64) ref IrInst:
	f.blocks[run.bs[i]].insts[run.ks[i]]

# the flat positions of a run that read v, in order
fn irRunUses(f IrFn, run IrRun, v i64):
	(0..run.bs.len).filter(f.irRunInst(run, it).irReadsVreg(v))

# whether an f64 vreg is assigned once
fn irPairable(f IrFn, facts IrFacts, v i64):
	v >= 0 and f.classes[v] == irFloat and facts.defs[v] == 1

# The pairs of one run, each group grown from a pair of loads and kept when it pays, then made.
fn irPairRun(mut f IrFn, run IrRun, facts IrFacts, defBlock i64[]):
	n = run.bs.len
	claimed = fill(n, false)   # the positions a kept pair takes
	pairs = []
	for i in 0..n:
		if claimed[i]: continue
		seed = f.irLoadPair(run, facts, claimed, i) ?? continue
		start = pairs.len
		tried = claimed.copy()
		tried[seed.first] = true
		tried[seed.second] = true
		pairs.push(seed)
		f.irPairGrow(run, facts, tried, pairs, start)
		if f.irPairPays(run, facts, defBlock, tried, pairs, start):
			claimed = tried
		else:
			pairs.truncate(start)
	if not pairs.isEmpty:
		f.irPairsMade(run, facts, claimed, pairs)

# the load at position i paired with a later one of the next or the word before, at the same
# base and index, nothing written to memory nor the address changed in between
fn irLoadPair(f IrFn, run IrRun, facts IrFacts, claimed bool[], i i64) IrPair?:
	ld = f.irRunInst(run, i)
	if ld.op != irLoad or ld.size != 8 or not f.irPairable(facts, ld.dst): return none
	for j in i + 1..run.bs.len:
		other = f.irRunInst(run, j)
		if irWritesMemory(other.op) or other.dst >= 0 and (other.dst == ld.a or other.dst == ld.b):
			return none
		if claimed[j] or other.op != irLoad or other.size != 8 or other.a != ld.a or
			other.b != ld.b or other.scale != ld.scale or other.frame != ld.frame or
			not f.irPairable(facts, other.dst):
			continue
		if other.imm == ld.imm + 8:
			return IrPair(lo = ld.dst, hi = other.dst, op = irLoad, first = i, second = j, at = i)
		if other.imm == ld.imm - 8:
			return IrPair(lo = other.dst, hi = ld.dst, op = irLoad, first = i, second = j, at = i)
	none

# the pair whose lanes are x and y
fn irPairIndex(pairs IrPair[], x i64, y i64) i64?:
	for k, p in pairs:
		if p.lo == x and p.hi == y: return k
	none

# The group grown from pairs[start]: for each pair's lanes x and y, an operation reading x and one
# alike reading y in the same place, their results not read between the two and nothing they
# read changed between, made a pair.
fn irPairGrow(f IrFn, run IrRun, facts IrFacts, mut claimed bool[], mut pairs IrPair[], start i64):
	g = start
	while g < pairs.len:
		x = pairs[g].lo
		y = pairs[g].hi
		ys = f.irRunUses(run, y)
		for i in f.irRunUses(run, x):
			if claimed[i]: continue
			one = f.irRunInst(run, i)
			if one.op not in [irFAdd, irFSub, irFMul, irFDiv] or one.imm != 64 or
				not f.irPairable(facts, one.dst):
				continue
			for j in ys:
				if j == i or claimed[j]: continue
				two = f.irRunInst(run, j)
				if two.op != one.op or two.imm != 64 or not f.irPairable(facts, two.dst) or
					two.dst == one.dst:
					continue
				args = f.irPairArgs(pairs, facts, one, two, x, y, g) ?? continue
				first = i.min(j)
				second = i.max(j)
				if f.irPairSplits(run, first, second, [one.dst, two.dst]): continue
				pairs.push(
					IrPair(
						lo = one.dst,
						hi = two.dst,
						op = one.op,
						first,
						second,
						at = second,
						args
					)
				)
				claimed[i] = true
				claimed[j] = true
				break
		g += 1

# whether making the instruction at first at second instead breaks it: a result read between
# them, or something the earlier one reads assigned between
fn irPairSplits(f IrFn, run IrRun, first i64, second i64, results i64[]):
	early = f.irRunInst(run, first)
	for p in first + 1..second:
		inst = f.irRunInst(run, p)
		if results.any(inst.irReadsVreg(it)): return true
		if inst.dst >= 0 and early.irReadsVreg(inst.dst): return true
	false

# the operands of the vector operation for one (reading x, lane 0's) and two (reading y in the
# same place, or the other place of one that commutes), pair g holding x and y; none when
# their other operands make no pair
fn irPairArgs(
	f IrFn,
	pairs IrPair[],
	facts IrFacts,
	one IrInst,
	two IrInst,
	x i64,
	y i64,
	g i64
) IrPairArg[]?:
	if one.a == x and one.b == x:
		if two.a == y and two.b == y:
			return [IrPairArg(kind = irArgPair, x = g), IrPairArg(kind = irArgPair, x = g)]
		return none
	if two.a == two.b: return none
	commutes = one.op == irFAdd or one.op == irFMul
	xFirst = one.a == x
	yFirst = two.a == y
	if xFirst != yFirst and not commutes: return none
	other = irPairOperand(pairs, facts, one.b if xFirst else one.a, two.b if yFirst else two.a)
	mine = IrPairArg(kind = irArgPair, x = g)
	if xFirst: return [mine, other]
	[other, mine]

# the vector of lanes u and w: a pair's, zeros, a constant or a value in both, or the two put
# together
fn irPairOperand(pairs IrPair[], facts IrFacts, u i64, w i64):
	if irPairIndex(pairs, u, w) is k: return IrPairArg(kind = irArgPair, x = k)
	if facts.consts[u] is bits and facts.consts[w] is other and bits == other:
		return IrPairArg(kind = irArgZero) if bits == 0 else IrPairArg(kind = irArgDup, x = u)
	if u == w: return IrPairArg(kind = irArgDup, x = u)
	IrPairArg(kind = irArgMix, x = u, y = w)

# Whether the group pairs[start..] pays: the operations it saves (one a pair of operations) more
# than the shuffles it adds in the loop (operands put together of values the loop makes, a lane
# 1 its other readers need, a lane 0 one that is not arithmetic needs). A group with a value put
# together that another pair makes does not pay: its scalar would be gone.
fn irPairPays(
	f IrFn,
	run IrRun,
	facts IrFacts,
	defBlock i64[],
	claimed bool[],
	pairs IrPair[],
	start i64
):
	lanes = []
	for p in pairs:
		lanes.push(p.lo)
		lanes.push(p.hi)
	for p in pairs:
		if p.args.any((.kind == irArgMix or .kind == irArgDup) and (.x in lanes or .y in lanes)):
			return false
	saved = 0
	added = 0
	for k in start..pairs.len:
		p = pairs[k]
		if p.op != irLoad:
			saved += 1
		for arg in p.args:
			if arg.kind == irArgMix or arg.kind == irArgDup:
				if not f.irLoopInvariant(run, facts, defBlock, arg.x) or
					arg.kind == irArgMix and not f.irLoopInvariant(run, facts, defBlock, arg.y):
					added += 1
		for lane in 0..2:
			v = p.lo if lane == 0 else p.hi
			if f.irLaneTaken(run, facts, claimed, v, lane == 0) != none:
				added += 1
	saved > added

# whether the loop around a run sets v nowhere: a constant, or a vreg assigned once outside it
fn irLoopInvariant(f IrFn, run IrRun, facts IrFacts, defBlock i64[], v i64):
	facts.consts[v] != none or
		facts.defs[v] == 1 and defBlock[v] >= 0 and defBlock[v] not in f.loops[run.inner].blocks

# how a lane's other readers (those of no pair, and any outside the run) get it: none when
# they need nothing, or when lane 0 is read in place by arithmetic alone; true when a shuffle
# takes it out (lane 1), false when a move does (lane 0)
fn irLaneTaken(f IrFn, run IrRun, facts IrFacts, claimed bool[], v i64, low bool) bool?:
	uses = f.irRunUses(run, v)
	inRun = 0
	for i in uses:
		reader = f.irRunInst(run, i)
		inRun += [reader.a, reader.b, reader.c, reader.d].count(v) + reader.args().count(v)
	rest = uses.filter(not claimed[it])
	outside = facts.reads[v] > inRun
	if rest.isEmpty and not outside: return none
	if not low: return true
	if not outside and rest.all(f.irRunInst(run, it).op in irLaneZeroReaders): return none
	false

# what reads a float's register as lane 0 of an xmm: the arithmetic the emitter does on any
# register (irEmitFloatArith, irFloatIn)
irLaneZeroReaders = [irFAdd, irFSub, irFMul, irFDiv, irFSqrt, irFNeg]

# The pairs made: each pair's vector by one instruction where it is made (its operands put
# together just before it), the scalar instructions it stands for taken out, its lanes taken
# out after it for their other readers, or lane 0 read in place.
fn irPairsMade(mut f IrFn, run IrRun, facts IrFacts, claimed bool[], mut pairs IrPair[]):
	n = run.bs.len
	made IrInst[,] = []
	loop n:
		made.push([])
	gone = fill(n, false)
	for mut pair in pairs:
		pair.vec = f.irVreg(irVec)
	for k in 0..pairs.len:
		p = pairs[k].copy()
		gone[p.first] = true
		gone[p.second] = true
		line = f.irRunInst(run, p.first).line
		col = f.irRunInst(run, p.first).col
		insts = []
		if p.op == irLoad:
			low = f.irRunInst(run, p.second if f.irRunInst(run, p.second).dst == p.lo else p.first)
			insts.push(
				IrInst(
					op = irLoad,
					dst = p.vec,
					a = low.a,
					b = low.b,
					imm = low.imm,
					scale = low.scale,
					size = 16,
					frame = low.frame,
					line,
					col
				)
			)
		else:
			ops = []
			for arg in p.args:
				ops.push(f.irPairArgMade(pairs, facts, arg, insts))
			insts.push(
				IrInst(
					op = irVecOp,
					dst = p.vec,
					a = ops[0],
					b = ops[1],
					imm = irVecCode(1, 1, 0, 0, irPairOpcode(p.op), -1),
					line,
					col
				)
			)
		for lane in 0..2:
			v = p.lo if lane == 0 else p.hi
			match f.irLaneTaken(run, facts, claimed, v, lane == 0):
				none:
					if lane == 0:
						for i in f.irRunUses(run, v):
							if not claimed[i]:
								alias reader = f.blocks[run.bs[i]].insts[run.ks[i]]
								if reader.a == v: reader.a = p.vec
								if reader.b == v: reader.b = p.vec
				shuffle:
					code = irVecCode(3, 1, 0, 0, 0x05, 1) if shuffle   # vpermilpd x, v, 1
						else irVecCode(1, 1, 0, 0, 0x28, -1)   # vmovapd x, v
					insts.push(IrInst(op = irVecOp, dst = v, a = p.vec, imm = code, line, col))
		made[p.at] = insts
	b = -1
	rebuilt = []
	for i in 0..n:
		if run.bs[i] != b:
			if b >= 0:
				f.blocks[b].insts = rebuilt
			b = run.bs[i]
			rebuilt = []
		if not gone[i]:
			rebuilt.push(f.irRunInst(run, i).copy())
		rebuilt.extend(made[i].copy())
	if b >= 0:
		f.blocks[b].insts = rebuilt

# vaddpd, vsubpd, vmulpd, vdivpd: the 66 0F opcode of an f64 operation
fn irPairOpcode(op i64):
	0x58 if op == irFAdd else 0x5C if op == irFSub else 0x59 if op == irFMul else 0x5E

# the vreg of an operand's vector, the instructions that put it together added to insts (lane 1's
# constant first in both lanes: an operand in memory is read whole, 16 bytes, and a constant's
# data is one word)
fn irPairArgMade(mut f IrFn, pairs IrPair[], facts IrFacts, arg IrPairArg, mut insts IrInst[]):
	if arg.kind == irArgPair: return pairs[arg.x].vec
	v = f.irVreg(irVec)
	if arg.kind == irArgZero:
		insts.push(IrInst(op = irConst, dst = v, imm = 0))
	elif arg.kind == irArgDup:
		insts.push(irPairDup(v, arg.x))
	else:
		high = arg.y
		if facts.consts[arg.y] != none:
			high = f.irVreg(irVec)
			insts.push(irPairDup(high, arg.y))
		insts.push(   # vunpcklpd
			IrInst(
				op = irVecOp,
				dst = v,
				a = arg.x,
				b = high,
				imm = irVecCode(1, 1, 0, 0, 0x14, -1)
			)
		)
	v

# dst = x in both lanes: vmovddup
fn irPairDup(dst i64, x i64):
	IrInst(op = irVecOp, dst, a = x, imm = irVecCode(1, 3, 0, 0, 0x12, -1))
