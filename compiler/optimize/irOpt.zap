# Simplifications of the intermediate form (ir.zap) before registers are given: an operation
# on constants becomes its constant, and a copy of a vreg assigned once into one assigned once
# (an inlined body's parameter, its result) makes the two one vreg. Then what nothing reads goes,
# what a loop computes the same each time moves before it, short blocks where branches meet
# are copied into the jumps to them (a branch on a value known there folds), and a jump to a
# block that only jumps on goes where that one goes.

fn irSimplify(mut f IrFn, arm bool):
	f.irSettle()
	f.irPrune()
	f.irOwnAfter("prune")
	f.irDeadSlots()   # (a slot only written keeps no vregs)
	f.irOwnAfter("deadSlots")
	if f.irPlaceScalars(arm):
		f.irOwnAfter("placeScalars")
		f.irSettle()
		f.irDropDead()   # a scalar's vreg written again before it is read
		f.irPrune()
	f.irSlotWords()
	f.irDeadSlots()
	f.irOwnAfter("deadSlots")
	f.irPairs()
	f.irOwnAfter("pairs")
	f.irHoist()
	f.irOwnAfter("hoist")
	f.irSettle()   # what was hoisted meets its twins before the loop
	f.irPrune()
	f.irOwnAfter("prune")
	if f.irDominatedWork():
		f.irOwnAfter("dominatedWork")
		f.irSettle()
	copied = false
	rounds = 0
	while rounds < irTailRounds and f.irTailCopy():
		f.irOwnAfter("tailCopy")
		f.irBranchFold()   # a folded branch is a jump that may meet another such block
		f.irOwnAfter("branchFold")
		copied = true
		rounds += 1
	if copied:
		f.irSettle()
		f.irDropDead()
		f.irOwnAfter("dropDead")
		f.irPrune()
		f.irOwnAfter("prune")
	f.irThreadJumps()
	f.irOwnAfter("threadJumps")
	if f.irRangeFacts():
		f.irOwnAfter("rangeFacts")
		f.irSettle()
		f.irPrune()
	if f.irGuardLoops():
		f.irOwnAfter("guardLoops")
		f.irSettle()
		f.irPrune()
	if f.irCarryDivisions():
		f.irOwnAfter("carryDivisions")
		f.irSettle()
		f.irPrune()
	if f.irUnrollAffine():
		f.irOwnAfter("unrollAffine")
		f.irSettle()
		f.irDropDead()
		f.irPrune()
		f.irOwnAfter("prune")
	f.irKnownVecMasks()
	f.irHeldConstants(arm)   # last: a settling pass would fold the copies back
	f.irOwnAfter("heldConstants")
	if f.irDispatchCopies():   # (after the settling passes: its blocks enter the loop's arms)
		f.irOwnAfter("dispatchCopies")
	if f.irSplitLoops():   # a settle would make the copies one vreg again
		f.irOwnAfter("splitLoops")
	if f.irEnterArms():   # last: the jumps it moves enter loops past their tops
		f.irOwnAfter("enterArms")
		f.irPrune()
	if f.irSwitchPages():   # (after enterArms, which finds a dispatcher's switch alone in its block)
		f.irOwnAfter("switchPages")

irTailRounds = 4   # an `and` chain of inlined bools folds one link a round

# a frame slot only written (its words known where they were read): its stores and ownership
# markers dropped, the slot then pruned
fn irDeadSlots(mut f IrFn):
	slot = fill(f.classes.len, false)
	for b in f.blocks:
		for inst in b.insts:
			if inst.op == irFrameSlot and inst.dst >= 0:
				slot[inst.dst] = true
	for b in f.blocks:
		for inst in b.insts:
			# read, or its address taken: not a store into it alone
			if inst.op == irStore and inst.a >= 0 and slot[inst.a] and inst.b != inst.a and
				inst.c != inst.a:
				if inst.b >= 0: slot[inst.b] = false
				if inst.c >= 0: slot[inst.c] = false
				if inst.d >= 0: slot[inst.d] = false
			elif not irIsMarker(inst.op):
				for v in inst.irReads():
					slot[v] = false
	for bi in 0..f.blocks.len:
		any = false
		for k in 0..f.blocks[bi].insts.len:
			op = f.blocks[bi].insts[k].op
			if (op == irStore or irIsMarker(op)) and f.blocks[bi].insts[k].a >= 0 and
				slot[f.blocks[bi].insts[k].a]:
				f.irTakeOut(bi, k)
				any = true
		if any:
			f.irDropTakenOut(bi)
	f.irPrune()

# rounds of the passes below until one changes nothing; a round ends at the first pass that
# changes something, so each pass reads the facts found at the round's start as they still are
fn irSettle(mut f IrFn):
	unseen = IrFacts(defs = [], reads = [], consts = [], roots = [])   # every vreg new
	settled = IrSettled(hashes = [], facts = unseen, clean = [])
	loop irLocalPasses:
		settled.clean.push([])
	again = true
	while again:
		again = f.irSettleRound(settled)

# The passes of a settle round before the spans each look at one block at a time, by the facts
# of the vregs it names: a block one found nothing in is not looked at again by it until the block
# changes or a fact it reads of a vreg the block names does (the constants and copies for most,
# whether a vreg is read once for irUpdates).
type IrSettled:
	hashes i64[]   # per block: its instructions' hash at the round's start
	facts IrFacts   # the facts found then
	clean bool[,]   # per such pass: per block, whether it found nothing there since

irLocalPasses = 10
irUpdatesPass = 4   # the one that reads how many times a vreg is read

# the blocks pass p looks at this round, each then taken as clean: one it changes is no longer
# at the next round's start
fn irVisit(mut st IrSettled, p i64):
	visit = st.clean[p].map(not it)
	for b in 0..st.clean[p].len:
		st.clean[p][b] = true
	visit

# the facts and the blocks at a round's start: a block whose instructions or whose vregs' facts
# changed since the last is no pass's clean one
fn irSettleStart(f IrFn, mut st IrSettled, facts IrFacts):
	nv = facts.defs.len
	old = st.facts
	valued = (0..nv).map(
		it >= old.defs.len or old.consts[it] != facts.consts[it] or
			old.roots[it] != facts.roots[it]
	)
	once = (0..nv).map(it >= old.defs.len or (old.reads[it] == 1) != (facts.reads[it] == 1))
	for b in 0..f.blocks.len:
		h = irBlockHash(f.blocks[b].insts)
		dirty = b >= st.hashes.len or st.hashes[b] != h
		if b >= st.hashes.len:
			st.hashes.push(h)
			for p in 0..irLocalPasses:
				st.clean[p].push(false)
		st.hashes[b] = h
		if not dirty:
			for inst in f.blocks[b].insts:
				if inst.irNames(valued):
					dirty = true
					break
		if dirty:
			for p in 0..irLocalPasses:
				st.clean[p][b] = false
		elif st.clean[irUpdatesPass][b] and f.blocks[b].insts.any(.irNames(once)):
			st.clean[irUpdatesPass][b] = false

# whether an instruction names a vreg marked in `marked` (any operand field, read or not)
fn irNames(inst IrInst, marked bool[]):
	if inst.dst >= 0 and marked[inst.dst]: return true
	if inst.a >= 0 and inst.a < marked.len and marked[inst.a]: return true
	if inst.b >= 0 and inst.b < marked.len and marked[inst.b]: return true
	if inst.c >= 0 and inst.c < marked.len and marked[inst.c]: return true
	if inst.d >= 0 and inst.d < marked.len and marked[inst.d]: return true
	inst.args().any(it < marked.len and marked[it])

# a block's instructions hashed: every field a pass may change
fn irBlockHash(insts IrInst[]) i64:
	h = u64(insts.len)
	for inst in insts:
		h = h * 1_099_511_628_211 ^ u64(inst.op + 1)
		h = h * 1_099_511_628_211 ^ u64(inst.dst + 1)
		h = h * 1_099_511_628_211 ^ u64(inst.a + 1)
		h = h * 1_099_511_628_211 ^ u64(inst.b + 1)
		h = h * 1_099_511_628_211 ^ u64(inst.c + 1)
		h = h * 1_099_511_628_211 ^ u64(inst.d + 1)
		h = h * 1_099_511_628_211 ^ u64(inst.imm)
		h = h *
			1_099_511_628_211 ^ u64(
				i64(inst.size) + 16 * i64(inst.scale) + 256 * i64(inst.cond) +
					65_536 * i64(inst.pure)
			)
		h = h * 1_099_511_628_211 ^ u64(inst.target + 1) ^ u64(inst.other + 1) << 32
		flags = 0
		if inst.uns: flags |= 1
		if inst.regArgs: flags |= 2
		if inst.header: flags |= 4
		if inst.frame: flags |= 8
		if inst.trap: flags |= 16
		h = h * 1_099_511_628_211 ^ u64(flags)
		if inst.key() != "": h ^= u64(inst.key().hash())
		for v in inst.args():
			h = h * 1_099_511_628_211 ^ u64(v + 1)
	i64(h)

fn irSettleRound(mut f IrFn, mut st IrSettled):
	facts = f.irFacts()
	f.irSettleStart(st, facts)
	changed = f.irSettlePasses(st, facts)
	st.facts = facts
	changed

fn irSettlePasses(mut f IrFn, mut st IrSettled, facts IrFacts):
	if f.irOwnAfterChange("fold", f.irFold(facts, st.irVisit(0))) or
		f.irOwnAfterChange("forwardCopies", f.irForwardCopies(facts, st.irVisit(1))) or
		f.irOwnAfterChange("localCopies", f.irLocalCopies(st.irVisit(2))) or
		f.irOwnAfterChange("common", f.irCommon(facts, st.irVisit(3))) or
		f.irOwnAfterChange("updates", f.irUpdates(facts, st.irVisit(4))) or
		f.irOwnAfterChange("shiftMasks", f.irShiftMasks(facts, st.irVisit(5))) or
		f.irOwnAfterChange("addressing", f.irAddressing(facts, st.irVisit(6))) or
		f.irOwnAfterChange("narrowings", f.irNarrowings(st.irVisit(7))) or
		f.irOwnAfterChange("setBranches", f.irSetBranches(facts, st.irVisit(8))) or
		f.irOwnAfterChange("storedLoads", f.irStoredLoads(facts, st.irVisit(9))):
		return true
	spans = f.irValueSpans()
	f.irOwnAfterChange("wideEnough", f.irWideEnough(spans)) or
		f.irOwnAfterChange("directResults", f.irDirectResults(facts)) or
		f.irOwnAfterChange("provenChecks", f.irProvenChecks(facts, spans))

# What the passes of a settle round read about the function, found in one walk.
type IrFacts:
	defs i64[]   # how many instructions assign each vreg
	reads i64[]   # how many operands read each vreg
	consts i64?[]   # each vreg's constant when its only assignment is one, else none
	roots i64[]   # the vreg each one is a copy of, through copies of vregs assigned once, else itself

fn irFacts(f IrFn):
	nv = f.classes.len
	defs = zeros(nv)
	reads = zeros(nv)
	lastConst = fill(nv, false)
	value = zeros(nv)
	copyOf = fill(nv, -1)   # the vreg a copy of one class assigns each from
	for b in f.blocks:
		for inst in b.insts:
			for v in inst.irReads():
				reads[v] += 1
			if inst.dst >= 0:
				defs[inst.dst] += 1
				lastConst[inst.dst] = inst.op == irConst
				value[inst.dst] = inst.imm
				copyOf[inst.dst] = inst.a if inst.op == irCopy and inst.a != inst.dst and
					f.classes[inst.dst] == f.classes[inst.a]
					else -1
	consts i64?[] = []
	for v in 0..nv:
		if defs[v] == 1 and lastConst[v]:
			consts.push(value[v])
		else:
			consts.push(none)
	roots = (0..nv).map(
		copyOf[it] if defs[it] == 1 and copyOf[it] >= 0 and defs[copyOf[it]] == 1 else it
	)
	for v in 0..nv:
		r = roots[v]
		while roots[r] != r:
			r = roots[r]
		roots[v] = r
	IrFacts(defs, reads, consts, roots)

# Where each vreg was last assigned, for a walk forward through the blocks, so a pass that looks
# back at the instruction that made an operand finds it at once. Positions count the
# instructions of the whole walk: between blocks only the block's start moves.
type IrDefs:
	at i64[]   # each vreg's last assignment's position, -1 before any
	start i64   # the position of the block's first instruction

fn irDefsFor(f IrFn):
	IrDefs(at = fill(f.classes.len, -1), start = 0)

# instruction k of the block assigns dst (-1: nothing)
fn irNoteDef(mut d IrDefs, dst i64, k i64):
	if dst >= 0:
		d.at[dst] = d.start + k

# the index in the block of v's last assignment before the instruction walked, -1 when none is
# in this block (or v is -1)
fn irDefIn(d IrDefs, v i64):
	d.at[v] - d.start if v >= 0 and d.at[v] >= d.start else -1

# whether instruction j of the block is an operation of an operand a not assigned since (nor by
# j itself): what it computed from a still holds where the walk is
fn irFoldable(d IrDefs, insts IrInst[], j i64):
	x = insts[j].a
	x >= 0 and x != insts[j].dst and d.at[x] <= d.start + j

# what an instruction computes, hashed for finding it again: its operation and operands (a
# constant one by its value); two with the same hash are compared field by field (irSameWork)
fn irWorkHash(inst IrInst, consts i64?[]) i64:
	h = u64(inst.op) * 1_000_003 + u64(inst.imm) * 31 +
		u64(inst.size * 7 + inst.scale * 131 + inst.cond * 17)
	h = h * 1_099_511_628_211 ^ irOperandHash(inst.a, consts)
	h = h * 1_099_511_628_211 ^ irOperandHash(inst.b, consts)
	h = h * 1_099_511_628_211 ^ irOperandHash(inst.c, consts)
	h = h * 1_099_511_628_211 ^ irOperandHash(inst.d, consts)
	if inst.uns: h ^= 1 << 40
	if inst.header: h ^= 1 << 41
	if inst.frame: h ^= 1 << 42
	if inst.key() != "": h ^= u64(inst.key().hash())
	for v in inst.args():
		h = h * 1_099_511_628_211 ^ irOperandHash(v, consts)
	i64(h)

fn irOperandHash(v i64, consts i64?[]):
	if v >= 0 and consts[v] is c: return u64(c) * 2_654_435_761 + 1
	u64(v) * 40_503

# whether two instructions compute the same thing (irWorkHash agreed)
fn irSameWork(x IrInst, y IrInst, consts i64?[]):
	x.op == y.op and x.imm == y.imm and x.size == y.size and x.scale == y.scale and
		x.cond == y.cond and x.uns == y.uns and x.header == y.header and x.frame == y.frame and
		irSameOperand(x.a, y.a, consts) and irSameOperand(x.b, y.b, consts) and
		irSameOperand(x.c, y.c, consts) and irSameOperand(x.d, y.d, consts) and
		x.key() == y.key() and
		(x.trap or not y.trap) and x.args().len == y.args().len and
		(0..x.args().len).all(irSameOperand(x.args()[it], y.args()[it], consts))

fn irSameOperand(v i64, w i64, consts i64?[]):
	if v == w: return true
	if v < 0 or w < 0: return false
	if consts[v] is cv and consts[w] is cw: return cv == cw
	false
