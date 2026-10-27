# Checks a loop's counter proves, behind a guard (LLVM's IRCE, RyuJIT's loop cloning). A loop
# counted by a vreg i, stepped by a constant s in one block of each turn, the one block that goes
# back to its top doing so while i < n (n not assigned in it), holds i within i0..last over its
# turns: i0 its value on entry, last the greatest i0 + k * s below n. A check that reads i plus a constant c against a
# bound the loop does not assign (xs[i + c] of a list it does not resize), an overflow check of
# i + c, and a counter's x += k (x assigned there alone, at most once a turn) then hold when a few
# comparisons of i0, n, the bounds and x on entry do. Those the whole function's spans prove go in
# place; for the others a small loop that calls nothing is copied without them behind a guard
# making the comparisons once, the loop as written running when one fails (it then stops where it
# would).

irGuardMost = 64   # the most instructions a loop copied behind a guard holds
irGuardScan = 400   # the most a loop whose checks are looked at holds

# a loop counted by i from its value on entry, by step while i < n; top its entry, latch the
# block that goes back
type IrCounted:
	top i64
	latch i64
	i i64
	n i64
	step i64
	after bool[]   # the blocks a turn reaches after i was stepped

# a vreg that is i plus c in a turn, the sums on its way from i between lo and hi (each of which
# must not wrap for it to be i + c)
type IrOffset:
	v i64
	c i64
	lo i64
	hi i64

irGuardIndex = 0   # an index i + c below a bound, unsigned
irGuardSum = 1   # i + c, which must not overflow
irGuardCount = 2   # x += c once a turn at most

# a check the counter's range may prove: instruction k of block b, its kind, the offset (a counter's
# step), and the bound vreg (a counter's x)
type IrGuarded:
	b i64
	k i64
	kind i64
	off IrOffset
	bound i64

# whether a check of a loop went or a loop was copied behind a guard
fn irGuardLoops(mut f IrFn):
	if not f.merges.isEmpty or not f.blocks.any(.insts.any(.trap or .op == irFailIf)): return false
	known = f.irFacts().consts
	whole = []   # the spans, found once a loop has checks its counter may prove
	any = false
	li = 0
	while li < f.loops.len:
		copied = f.irGuardLoop(li, known, whole)
		if copied >= 0: any = true
		if copied > 0:
			li += 2   # (the copy went before it)
			known = f.irFacts().consts   # (of the new vregs too)
			whole.clear()
		else:
			li += 1
	any

# a + b, held at the i64's ends
fn irSatAdd(a i64, b i64):
	if b > 0 and a > spanUp - b: return spanUp
	if b < 0 and a < spanDown - b: return spanDown
	a + b

fn irSatSub(a i64, b i64):
	if b == spanDown: return spanUp if a >= 0 else a - b
	irSatAdd(a, -b)

# loop li's checks its counter proves: those the spans prove taken out, the others by a copy of
# the loop behind a guard; -1 when nothing changed, 0 taken out in place only, 1 copied
fn irGuardLoop(mut f IrFn, li i64, known i64?[], mut whole Span[]):
	blocks = f.loops[li].blocks.copy()
	if blocks.isEmpty: return -1
	size = 0
	for b in blocks:
		size += f.blocks[b].insts.len
	if size > irGuardScan or not blocks.any(f.blocks[it].insts.any(.trap or .op == irFailIf)):
		return -1
	inside = f.irInside(blocks)
	lp = f.irCountedShape(blocks, inside, known) ?? return -1
	items = f.irGuardedChecks(blocks, inside, lp, known)
	if items.isEmpty: return -1
	if whole.isEmpty: whole.extend(f.irValueSpans())
	reentered = f.irReentered(inside)
	i0 = f.irEntrySpan(lp.i, inside, whole, reentered)
	ns = whole[lp.n]
	proven = []
	left = []
	for item in items:
		x0 = irSpanAny()
		if item.kind == irGuardCount: x0 = f.irEntrySpan(item.bound, inside, whole, reentered)
		if item.irGuardProven(lp, i0, ns, whole, x0): proven.push(item)
		else: left.push(item)
	for item in proven:
		f.irDropCheck(item.b, item.k)
	copied = not left.isEmpty and f.irSmallLoop(blocks, inside, lp.top) and
		f.irCopyGuarded(li, blocks, inside, lp, left, i0, ns)
	if copied: return 1
	if proven.isEmpty: return -1
	for b in blocks:
		f.irDropTakenOut(b)
	0

# the check at instruction k of block b dropped: an overflow check's operation kept, a check
# taken out (irDropTakenOut then filters it)
fn irDropCheck(mut f IrFn, b i64, k i64):
	if f.blocks[b].insts[k].op == irFailIf: f.irTakeOut(b, k)
	else: f.blocks[b].insts[k].trap = false

# the loop's counter, when it is counted (the file's comment): assigned in one block of each turn,
# the blocks after it in the turn seeing it stepped
fn irCountedShape(f IrFn, blocks i64[], inside bool[], known i64?[]) IrCounted?:
	top = try f.irLoopEntry(inside)
	latches = blocks.filter(f.irBlockSuccessors(it).any(it == top))
	if latches.len != 1: return none
	latch = latches[0]
	tail = f.blocks[latch].insts
	if tail.isEmpty: return none
	br = tail[len - 1]
	if br.op != irBranch or br.cond != irLt or br.uns or br.target != top or br.other < 0 or
		inside[br.other] or br.a < 0 or br.b < 0 or br.a == br.b or f.classes[br.a] != irInt:
		return none
	i = br.a
	n = br.b
	at = -1   # the block assigning i
	for b in blocks:
		for inst in f.blocks[b].insts:
			if inst.dst == n: return none
			if inst.dst == i:
				if at >= 0: return none
				at = b
	if at < 0 or f.irOnInnerCycle(at, inside, top): return none
	before = f.irReach([top], inside, at)
	next = []
	for s in f.irBlockSuccessors(at):
		next.push(s)
	after = f.irReach(next, inside, top)
	if before[at] or after[at] or blocks.any(before[it] and after[it]): return none
	if latch != at and not after[latch]: return none
	# the step: what the assignment adds to i, from its block's start
	offs = [IrOffset(i, 0, 0, 0)]
	step = 0
	for inst in f.blocks[at].insts:
		if inst.dst < 0: continue
		got = inst.irOffsetOf(offs, known)
		if inst.dst == i:
			o = try got
			step = o.c
			break
		irForget(offs, inst.dst)
		if got is o: offs.push(o)
	if step <= 0 or step > 1 << 20: return none
	IrCounted(top, latch, i, n, step, after)

# the loop's blocks reached from these without passing block stop (each of these reached)
fn irReach(f IrFn, from i64[], inside bool[], stop i64):
	seen = fill(f.blocks.len, false)
	work = from.copy()
	while not work.isEmpty:
		x = work.pop() ?? break
		if x == stop or not inside[x] or seen[x]: continue
		seen[x] = true
		for s in f.irBlockSuccessors(x):
			work.push(s)
	seen

# the checks of the loop that read its counter plus a constant, and its counters' overflow checks
fn irGuardedChecks(f IrFn, blocks i64[], inside bool[], lp IrCounted, known i64?[]):
	assigned = []   # the vregs the loop assigns, once for each assignment
	for b in blocks:
		for inst in f.blocks[b].insts:
			if inst.dst >= 0: assigned.push(inst.dst)
	found = []
	for b in blocks:
		base = lp.step if lp.after[b] else 0
		offs = [IrOffset(lp.i, base, 0, base)]
		for k in 0..f.blocks[b].insts.len:
			alias inst = f.blocks[b].insts[k]
			if inst.op == irFailIf and inst.uns and inst.a >= 0 and inst.b >= 0:
				x = inst.a if inst.cond == irGe else inst.b if inst.cond == irLe else -1
				bound = inst.b if inst.cond == irGe else inst.a
				if x >= 0 and bound not in assigned and f.classes[bound] == irInt and
					offs.find(.v == x) is o:
					found.push(IrGuarded(b, k, kind = irGuardIndex, off = o, bound))
			elif inst.trap and inst.size == 8 and inst.dst >= 0:
				if inst.irOffsetOf(offs, known) is o:
					found.push(IrGuarded(b, k, kind = irGuardSum, off = o, bound = -1))
				elif inst.op == irAdd and inst.a == inst.dst and inst.b >= 0 and
					inst.dst != lp.i and assigned.count(it == inst.dst) == 1 and
					not f.irOnInnerCycle(b, inside, lp.top):
					by = known[inst.b] ?? 0
					if by > 0:
						found.push(
							IrGuarded(
								b,
								k,
								kind = irGuardCount,
								off = IrOffset(inst.dst, by, 0, 0),
								bound = inst.dst
							)
						)
			if inst.dst >= 0:
				got = inst.irOffsetOf(offs, known)
				irForget(offs, inst.dst)
				if got is o: offs.push(o)
	found

# the offset of v forgotten (v assigned anew)
fn irForget(mut offs IrOffset[], v i64):
	for j in 0..offs.len:
		if offs[j].v == v:
			offs[j] = offs[len - 1]
			offs.truncate(offs.len - 1)
			return

# inst's result as the counter plus a constant, from the offsets known (a copy, a constant added
# or subtracted); none otherwise
fn irOffsetOf(inst IrInst, offs IrOffset[], known i64?[]) IrOffset?:
	if inst.op == irCopy:
		o = try offs.find(.v == inst.a)
		return IrOffset(inst.dst, o.c, o.lo, o.hi)
	if inst.op != irAdd and inst.op != irSub or inst.a < 0 or inst.b < 0: return none
	from = inst.a
	by = known[inst.b]
	if inst.op == irAdd and offs.any(.v == inst.b):
		from = inst.b
		by = known[inst.a]
	o = try offs.find(.v == from)
	k = try by
	if k > 1 << 30 or k < -(1 << 30): return none
	c = o.c + k if inst.op == irAdd else o.c - k
	IrOffset(inst.dst, c, o.lo.min(c), o.hi.max(c))

# whether block b lies on a way around inside the loop that does not pass its top (an inner loop)
fn irOnInnerCycle(f IrFn, b i64, inside bool[], top i64):
	seen = fill(f.blocks.len, false)
	work = []
	for s in f.irBlockSuccessors(b):
		if inside[s] and s != top: work.push(s)
	while not work.isEmpty:
		x = work.pop() ?? break
		if x == b: return true
		if seen[x]: continue
		seen[x] = true
		for s in f.irBlockSuccessors(x):
			if inside[s] and s != top: work.push(s)
	false

# whether a way leads from the loop's exits back into it (a loop around it)
fn irReentered(f IrFn, inside bool[]):
	seen = fill(f.blocks.len, false)
	work = []
	for b in 0..f.blocks.len:
		if inside[b]:
			for s in f.irBlockSuccessors(b):
				if not inside[s]: work.push(s)
	while not work.isEmpty:
		x = work.pop() ?? break
		if inside[x]: return true
		if seen[x]: continue
		seen[x] = true
		for s in f.irBlockSuccessors(x):
			work.push(s)
	false

# the values v may hold when the loop is entered: what its assignments outside it give when no
# way leads back into it, else the whole function's
fn irEntrySpan(f IrFn, v i64, inside bool[], whole Span[], reentered bool):
	if reentered: return whole[v]
	got Span? = none
	for b in 0..f.blocks.len:
		if inside[b]: continue
		for inst in f.blocks[b].insts:
			if inst.dst == v:
				s = inst.irSpanOf(whole)
				got = irSpanHull(got ?? s, s)
	got ?? irSpanAny()

# the greatest value the counter may hold in a turn, by the spans (none: no bound); a turn
# entered with i0 at or past n is the one with i0
fn irCounterTop(lp IrCounted, i0 Span, ns Span) i64?:
	hi = i0.hi.max(irSatAdd(ns.hi, -1))
	if hi > spanUp - lp.step: return none   # (the step may wrap)
	hi

# whether the spans prove check it over every turn
fn irGuardProven(check IrGuarded, lp IrCounted, i0 Span, ns Span, whole Span[], x0 Span):
	hi = lp.irCounterTop(i0, ns) ?? return false
	o = check.off
	if check.kind == irGuardCount:
		turns = irSatSub(ns.hi, i0.lo).max(1)
		if turns == spanUp or turns > spanUp / o.c: return false
		return irSatAdd(x0.hi, turns * o.c) < spanUp
	if i0.lo < spanDown - o.lo or hi > spanUp - o.hi: return false
	if check.kind == irGuardSum: return true
	irSatAdd(i0.lo, o.c) >= 0 and irSatAdd(hi, o.c) < whole[check.bound].lo

# whether the loop may be copied: small, of no call, inner loop or switch, each block ending in
# a jump, a branch or a return
fn irSmallLoop(f IrFn, blocks i64[], inside bool[], top i64):
	size = 0
	for b in blocks:
		insts = f.blocks[b].insts
		if insts.isEmpty or insts[len - 1].op not in [irJmp, irBranch, irBranchBit, irRet]:
			return false
		if insts.any(irCalls(.op) or irIsMarker(.op) or .op == irNote): return false
		size += insts.len
		if f.irOnInnerCycle(b, inside, top): return false
	size <= irGuardMost

# The loop copied without the checks left, behind a guard: a chain of blocks each testing one
# thing the checks need of the values on entry, on to the copy when all hold, else to the loop as
# written. False when the ways into the loop cannot be sent to the guard.
fn irCopyGuarded(
	mut f IrFn,
	li i64,
	blocks i64[],
	inside bool[],
	lp IrCounted,
	left IrGuarded[],
	i0 Span,
	ns Span
):
	ways = f.irWaysInto(lp.top, blocks) ?? return false
	keep = [lp.i, lp.n]
	for check in left:
		if check.bound >= 0: keep.push(check.bound)
	copy = f.irCopyLoop(blocks, inside, keep)
	for check in left:
		f.irDropCheck(copy[check.b], check.k)
	for b in blocks:
		f.irDropTakenOut(copy[b])
		f.irDropTakenOut(b)
	slow = f.irBlock()
	f.blocks[slow].insts = [IrInst(op = irJmp, target = lp.top)]
	first = f.irBlock()
	g = IrGuardChain(at = first, slow, made = [first])
	if not f.irEnteredBelow(ways, lp): f.irGuardTest(g, irLt, false, lp.i, lp.n)
	# the sums must not wrap: n - 1 plus the greatest offset, or the step past the last turn
	most = lp.step if lp.step > 1 else 0
	least = spanDown   # what i0 must reach
	for check in left:
		if check.kind == irGuardCount:
			least = least.max(0)
			continue
		most = most.max(check.off.hi)
		least = least.max(irSatSub(spanDown, check.off.lo))
		if check.kind == irGuardIndex: least = least.max(-check.off.c)
	power = (lp.step & (lp.step - 1)) == 0
	if lp.step > 1 and power: least = least.max(0)
	if most > 1 and ns.hi > spanUp - most + 1:
		f.irGuardTest(g, irLe, false, lp.n, f.irGuardConst(g, spanUp - most + 1))
	if least > spanDown and i0.lo < least:
		f.irGuardTest(g, irGe, false, lp.i, f.irGuardConst(g, least))
	if left.any(.kind == irGuardIndex):
		last = -1 if lp.step == 1 or not power else f.irGuardLast(g, lp)
		bounds i64[] = []
		for check in left:
			if check.kind == irGuardIndex and check.bound not in bounds: bounds.push(check.bound)
		for bound in bounds:
			c = 0
			for check in left:
				if check.kind == irGuardIndex and check.bound == bound: c = c.max(check.off.c)
			# (n - 1 bounds the last turn's counter for a step of one or not a power of two)
			from = lp.n if last < 0 else last
			by = c - 1 if last < 0 else c
			at = from if by == 0 else f.irGuardOp(g, irAdd, from, f.irGuardConst(g, by))
			f.irGuardTest(g, irLt, true, at, bound)
	for check in left:
		if check.kind != irGuardCount: continue
		# x + k * (n - i0) at most the i64's end (n > i0 >= 0)
		d = f.irGuardOp(g, irSub, lp.n, lp.i)
		if check.off.c > 1:
			f.irGuardTest(g, irLe, false, d, f.irGuardConst(g, spanUp / check.off.c))
			d = f.irGuardOp(g, irMul, d, f.irGuardConst(g, check.off.c))
		room = f.irGuardOp(g, irSub, f.irGuardConst(g, spanUp), d)
		f.irGuardTest(g, irLe, false, check.bound, room)
	f.blocks[g.at].insts.push(IrInst(op = irJmp, target = copy[lp.top]))
	for (b, k) in ways:
		f.irSendWay(b, k, first)
	made = g.made.copy()
	made.push(slow)
	copied = blocks.map(copy[it])
	for o in 0..f.loops.len:
		if o != li and lp.top in f.loops[o].blocks:
			f.loops[o].blocks.extend(made)
			f.loops[o].blocks.extend(copied)
	f.loops[li].pre = slow
	f.loops.insert(li, IrLoop(pre = g.at, blocks = copied))
	true

# the guard's blocks as they are made: the one being filled, the loop as written, all of them
type IrGuardChain:
	at i64
	slow i64
	made i64[]

# a test of the guard: on to a new block when a cond b holds, else to the loop as written
fn irGuardTest(mut f IrFn, mut g IrGuardChain, cond i64, uns bool, a i64, b i64):
	next = f.irBlock()
	f.blocks[g.at].insts.push(
		IrInst(op = irBranch, a, b, cond = i32(cond), uns, target = next, other = g.slow)
	)
	g.at = next
	g.made.push(next)

fn irGuardConst(mut f IrFn, g IrGuardChain, value i64):
	v = f.irVreg(irInt)
	f.blocks[g.at].insts.push(IrInst(op = irConst, dst = v, imm = value))
	v

fn irGuardOp(mut f IrFn, g IrGuardChain, op i64, a i64, b i64):
	v = f.irVreg(irInt)
	f.blocks[g.at].insts.push(IrInst(op, dst = v, a, b))
	v

# the counter's value in the last turn (i0 < n, i0 >= 0, the step a power of two): i0 plus
# n - 1 - i0 rounded down to the step
fn irGuardLast(mut f IrFn, g IrGuardChain, lp IrCounted) i64:
	d = f.irGuardOp(g, irSub, lp.n, lp.i)
	t = f.irGuardOp(g, irSub, d, f.irGuardConst(g, 1))
	m = f.irGuardOp(g, irAnd, t, f.irGuardConst(g, -lp.step))
	f.irGuardOp(g, irAdd, lp.i, m)

# whether the one way into the loop is a branch taken when i < n
fn irEnteredBelow(f IrFn, ways (i64, i64)[], lp IrCounted):
	if ways.len != 1: return false
	b, k = ways[0]
	alias insts = f.blocks[b].insts
	t = insts[len - 1]
	t.op == irBranch and not t.uns and t.a == lp.i and t.b == lp.n and
		(k == 0 and t.cond == irLt or k == 1 and t.cond == irGe)

# The loop's blocks copied, each block's copy returned by the block's number: its jumps inside it
# go to the copies, those out of it where the loop's go; a vreg only the loop names (none of keep)
# is a vreg of its own in the copy (a constant stays assigned once).
fn irCopyLoop(mut f IrFn, blocks i64[], inside bool[], keep i64[]):
	nv = f.classes.len
	outside = fill(nv, false)   # named outside the loop
	for v in keep:
		outside[v] = true
	for b, mut block in f.blocks:
		if inside[b]: continue
		for inst in block.insts:
			for v in inst.irReads():
				outside[v] = true
			if inst.dst >= 0: outside[inst.dst] = true
	own = fill(nv, -1)
	for b in blocks:
		for inst in f.blocks[b].insts:
			if inst.dst >= 0 and not outside[inst.dst] and own[inst.dst] < 0:
				own[inst.dst] = f.irVreg(f.classes[inst.dst])
	copy = fill(f.blocks.len, -1)
	for b in blocks:
		copy[b] = f.irBlock()
	for b in blocks:
		insts = []
		for inst in f.blocks[b].insts:
			insts.push(inst.irRenamed(own))
		t = insts.len - 1
		if insts[t].target >= 0 and inside[insts[t].target]:
			insts[t].target = copy[insts[t].target]
		if insts[t].op != irJmp and insts[t].other >= 0 and inside[insts[t].other]:
			insts[t].other = copy[insts[t].other]
		f.blocks[copy[b]].insts = move insts
		f.blocks[copy[b]].loopTop = f.blocks[b].loopTop
		f.blocks[copy[b]].cold = f.blocks[b].cold
	copy
