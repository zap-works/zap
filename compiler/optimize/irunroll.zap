# Affine recurrences and carry chains unrolled (iropt.zap): a loop of one way through its blocks
# (no call, at most irUnrollMost instructions) that counts c up by one while c < n and carries an
# integer x = x * A + C (A a constant other than 1, in 32 bits or 64 wrapping: a generator of
# random numbers) or a sum's carry (multiword arithmetic) runs irUnrollBy turns a step. The step is the body written that many times in one
# block, and each integer the turns compute as A * v + C of a value v the step began with is
# computed from v (the multiplier and the sum composed), so a turn no longer waits on the turn
# before it. A guard runs a step while n - c >= irUnrollBy; the turns left run in the loop as it
# was. The values, the checks and the order of the stores are the loop's own.

irUnrollBy = 8
irUnrollMost = 32

# an integer as mul * root + add, modulo 2^bits (32 or 64; 0: root itself), made by depth
# operations on root
type IrAffine:
	root i64
	mul u64
	add u64
	bits i64
	depth i64

# whether a loop was unrolled
fn irUnrollAffine(mut f IrFn):
	known = f.irFacts().consts
	preds = f.irPredecessors()
	any = false
	li = 0
	while li < f.loops.len:
		if f.irUnrollLoop(li, known, preds):
			any = true
			preds = f.irPredecessors()
			li += 1   # (its step's loop went before it)
		li += 1
	any

# the loop's blocks from its top in the order they run, when they are one way through that ends in
# a branch back to the top; empty otherwise
fn irLoopChain(f IrFn, l IrLoop) i64[]:
	if l.blocks.isEmpty: return []
	top = l.blocks[0]
	chain = [top]
	b = top
	loop:
		insts = f.blocks[b].insts
		if insts.isEmpty: return []
		t = insts[len - 1]
		if t.op == irBranch and t.target == top and t.other not in l.blocks:
			return chain if chain.len == l.blocks.len else []
		if t.op != irJmp or t.target == top or t.target not in l.blocks or t.target in chain:
			return []
		b = t.target
		chain.push(b)
	[]

# the instructions a step copies: the chain's but its blocks' last
fn irChainBody(f IrFn, chain i64[]):
	body = []
	for b in chain:
		insts = f.blocks[b].insts
		for inst in insts[..len - 1]:
			body.push(inst.copy())
	body

# whether loop li was unrolled: its step's loop put before it
fn irUnrollLoop(mut f IrFn, li i64, mut known i64?[], preds i64[,]):
	l = f.loops[li].copy()
	chain = f.irLoopChain(l)
	if chain.isEmpty: return false
	top = chain[0]
	body = f.irChainBody(chain)
	last = f.blocks[chain[len - 1]].insts
	branch = last[len - 1].copy()
	if body.len > irUnrollMost or branch.cond != irLt or branch.a < 0 or branch.b < 0: return false
	if body.any(.op in [irCall, irCallPtr, irDrop, irDeepCopy, irOwn, irOwnEnd, irNote]):
		return false
	c = branch.a
	n = branch.b
	counted = body.filter(.dst == c)
	if counted.len != 1 or counted[0].op != irAdd or counted[0].a != c or
		(known[counted[0].b] ?? 0) != 1 or counted[0].trap or body.any(.dst == n):
		return false
	carried = irCarried(body)
	affine = f.irMultiplies(body, carried, known)
	if not affine and not irCarriesCarry(body, carried): return false
	ways = f.irWaysIntoOf(top, chain, preds) ?? return false
	guard = f.irBlock()
	step = f.irBlock()
	for (b, k) in ways:
		f.irSendWay(b, k, guard)
	f.irFillStep(step, body, carried, known, branch, guard)
	if not affine:
		f.irRenameRun(step, f.irLeaving(carried, chain), known)
	f.irFillGuard(guard, n, c, step, top, known)
	f.blocks[step].loopTop = true
	for o in 0..f.loops.len:
		if o != li and top in f.loops[o].blocks:
			f.loops[o].blocks.extend([guard, step])
	f.loops[li].pre = guard
	f.loops.insert(li, IrLoop(pre = l.pre, blocks = [guard, step]))
	true

# the ways into top from outside the chain: each block and which of its targets (0 target, 1
# other) goes there; none when one comes otherwise (falling into it, a switch)
fn irWaysInto(f IrFn, top i64, chain i64[]) (i64, i64)[]?:
	ways = []
	for b in 0..f.blocks.len:
		if b not in chain and not f.irWayInto(b, top, ways): return none
	ways

# irWaysInto read from each block's predecessors (a huge function has many loops)
fn irWaysIntoOf(f IrFn, top i64, chain i64[], preds i64[,]) (i64, i64)[]?:
	ways = []
	for b in preds[top]:
		if b not in chain and not f.irWayInto(b, top, ways): return none
	ways

# block b's ways into top added to ways; false when it comes there otherwise
fn irWayInto(f IrFn, b i64, top i64, mut ways (i64, i64)[]):
	if f.irFallsOn(b): return b + 1 != top
	t = f.blocks[b].insts[len - 1]
	if t.op == irSwitch and (t.other == top or top in f.switches[t.imm].targets): return false
	if t.op in [irJmp, irBranch, irBranchBit]:
		if t.target == top: ways.push((b, 0))
		if t.op != irJmp and t.other == top: ways.push((b, 1))
	true

# the integers the body assigns that it reads before (a turn's value the next one starts from)
fn irCarried(body IrInst[]):
	assigned i64[] = []
	carried i64[] = []
	for inst in body:
		for v in inst.irReads():
			if v not in assigned and v not in carried and body.any(.dst == v): carried.push(v)
		if inst.dst >= 0: assigned.push(inst.dst)
	carried

# whether a carried integer is a sum's carry added to a word (multiword arithmetic: a carry
# tested right after its sum, irCarryTest), whose turns run apart but for that chain
fn irCarriesCarry(body IrInst[], carried i64[]):
	carries = []
	for k in 1..body.len:
		if body[k - 1].irCarryTest(body[k]): carries.push(body[k].dst)
	body.any(.op == irAdd and .dst in carried and (.a in carries or .b in carries))

# the vregs whose value a loop's turn leaves to what follows it: those the next turn reads (carried)
# and those read outside the loop's blocks (the chain) and the step's that come after it
fn irLeaving(f IrFn, carried i64[], chain i64[]):
	keep = fill(f.classes.len, false)
	for v in carried:
		keep[v] = true
	for b in 0..f.blocks.len - 2:
		if b in chain: continue
		for inst in f.blocks[b].insts:
			for v in inst.irReads():
				keep[v] = true
	keep

# Block b's instructions (a step's turns, one way through) with each assignment of a vreg given a
# vreg of its own, read as that one up to the next, but the last of one the step leaves (keep): the
# turns' values apart, so a value a turn reads once is read once (as the instructions' shapes ask)
# and the turns overlap
fn irRenameRun(mut f IrFn, b i64, keep bool[], mut known i64?[]):
	insts = f.blocks[b].insts.copy()
	nv = f.classes.len
	lastDef = fill(nv, -1)
	for k, inst in insts:
		if inst.dst >= 0: lastDef[inst.dst] = k
	cur = fill(nv, -1)
	for k in 0..insts.len:
		dst = insts[k].dst
		r = insts[k].irRenamed(cur)
		if dst >= 0 and (lastDef[dst] != k or not keep[dst]):
			r.dst = f.irVreg(f.classes[dst])
			known.push(known[dst])
			cur[dst] = r.dst
		elif dst >= 0:
			r.dst = dst
			cur[dst] = -1
		insts[k] = r
	f.blocks[b].insts = move insts

# whether a turn of the body leaves a carried integer at A * its value + C with A not 1
fn irMultiplies(f IrFn, body IrInst[], carried i64[], known i64?[]):
	forms {i64: IrAffine} = {}
	for x in carried:
		forms[x] = IrAffine(x, 1, 0, 0, 0)
	for inst in body:
		f.irAffineStep(inst, forms, known)
	for x in carried:
		if forms.get(x) is a and a.root == x and a.mul != 1: return true
	false

# inst's result as an affine function of a root (forms holds each integer's so far), noted in
# forms: a copy, or a constant multiplied, added or subtracted in 32 bits or wrapping 64
fn irAffineStep(f IrFn, inst IrInst, mut forms {i64: IrAffine}, known i64?[]):
	if inst.dst < 0: return none
	got = f.irAffineOf(inst, forms, known)
	if got is a:
		forms[inst.dst] = a.copy()
	else:
		forms.remove(inst.dst)
	got

fn irAffineOf(f IrFn, inst IrInst, forms {i64: IrAffine}, known i64?[]) IrAffine?:
	if f.classes[inst.dst] != irInt: return none
	if inst.op == irCopy:
		if forms.get(inst.a) is a: return a.copy()
		return none
	op = inst.op
	if op != irMul and op != irAdd and op != irSub or inst.a < 0 or inst.b < 0: return none
	bits = 32 if inst.irIs32() else 64 if inst.size == 8 and not inst.trap else 0
	if bits == 0: return none
	s = inst.a
	k = known[inst.b]
	if k == none and op != irSub:
		s = inst.b
		k = known[inst.a]
	kv = u64.wrap(try k)
	from = try forms.get(s)
	if from.bits == 32 and bits == 64: return none   # (the high bits a 32-bit value dropped)
	if op == irMul: return IrAffine(from.root, from.mul * kv, from.add * kv, bits, from.depth + 1)
	IrAffine(
		from.root,
		from.mul,
		from.add + kv if op == irAdd else from.add - kv,
		bits,
		from.depth + 1
	)

# a constant's vreg, assigned once (written where it is read)
fn irConstVreg(mut f IrFn, mut known i64?[], value i64):
	v = f.irVreg(irInt)
	known.push(value)
	(v, IrInst(op = irConst, dst = v, imm = value))

# a number of bits bits as the instruction's constant: its low 32 bits, sign-extended, for 32
fn irBitsConst(x u64, bits i64) i64:
	if bits != 32: return i64.wrap(x)
	low = i64.wrap(x & 0xFFFF_FFFF)
	low - (1 << 32) if low >= 1 << 31 else low

# the step: each carried integer's value copied at its start, then irUnrollBy turns of the body,
# each integer composed from those copies computed from them, then on to the guard while c < n
fn irFillStep(
	mut f IrFn,
	step i64,
	body IrInst[],
	carried i64[],
	mut known i64?[],
	branch IrInst,
	guard i64
):
	out = []
	forms {i64: IrAffine} = {}
	for x in carried:
		if f.classes[x] != irInt: continue
		e = f.irVreg(irInt)
		known.push(none)
		out.push(IrInst(op = irCopy, dst = e, a = x))
		forms[x] = IrAffine(e, 1, 0, 0, 0)
	loop irUnrollBy:
		for inst in body:
			if inst.op == irConst and known[inst.dst] != none or inst.op == irFrameSlot or
				inst.op == irFrameAddr:
				continue   # (written where it is read, its value where it is)
			a = f.irAffineStep(inst, forms, known)
			if a is a and a.depth >= 2 and inst.op != irCopy:
				f.irAffineFrom(out, inst, a, known)
			else:
				out.push(inst.copy())
	out.push(
		IrInst(
			op = irBranch,
			a = branch.a,
			b = branch.b,
			cond = irLt,
			uns = branch.uns,
			target = guard,
			other = branch.other,
			line = branch.line,
			col = branch.col
		)
	)
	f.blocks[step].insts = move out

# inst's result computed as a.mul * a.root + a.add
fn irAffineFrom(mut f IrFn, mut out IrInst[], inst IrInst, a IrAffine, mut known i64?[]):
	size = 4 if a.bits == 32 else 8
	at = a.root
	if a.mul != 1:
		m, mk = f.irConstVreg(known, irBitsConst(a.mul, a.bits))
		out.push(mk)
		at = f.irVreg(irInt)
		known.push(none)
		out.push(
			IrInst(
				op = irMul,
				dst = at,
				a = a.root,
				b = m,
				size,
				imm = inst.imm,
				line = inst.line,
				col = inst.col
			)
		)
	if a.add == 0 and a.mul != 1:
		out.push(IrInst(op = irCopy, dst = inst.dst, a = at, line = inst.line, col = inst.col))
		return
	p, pk = f.irConstVreg(known, irBitsConst(a.add, a.bits))
	out.push(pk)
	out.push(
		IrInst(
			op = irAdd,
			dst = inst.dst,
			a = at,
			b = p,
			size,
			imm = inst.imm,
			line = inst.line,
			col = inst.col
		)
	)

# the guard: a step when n - c (unsigned: c < n here) holds irUnrollBy turns, else the loop
fn irFillGuard(mut f IrFn, guard i64, n i64, c i64, step i64, top i64, mut known i64?[]):
	left = f.irVreg(irInt)
	known.push(none)
	most, mk = f.irConstVreg(known, irUnrollBy - 1)
	f.blocks[guard].insts = [
		mk,
		IrInst(op = irSub, dst = left, a = n, b = c),
		IrInst(
			op = irBranch,
			a = left,
			b = most,
			cond = irGt,
			uns = true,
			target = step,
			other = top
		)
	]
