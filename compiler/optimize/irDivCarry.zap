# Divisions of a counter carried (irOpt.zap): in a loop of one way through its blocks that counts
# c up by one from a constant at least 0, c / d and c % d by a divisor the loop does not assign
# (and no constant, which divConst.zap makes a multiply) are divided once before the loop, its
# check there, and then carried: each turn the remainder goes up by one, and when it meets |d| it
# is 0 again and the quotient goes on by d's sign. Nothing the loop calls runs before the
# division in a turn, so the check that stops the program stops it before the same work.

# whether a loop's divisions were carried
fn irCarryDivisions(mut f IrFn):
	known = f.irFacts().consts
	any = false
	for li in 0..f.loops.len:
		if f.irCarryLoop(li, known):
			any = true
	any

# the carried quotient and remainder of c by d, and |d| and d's sign (the step of the quotient)
type IrCarried:
	d i64
	quotient i64
	remainder i64
	size i64
	step i64

fn irCarryLoop(mut f IrFn, li i64, known i64?[]):
	l = f.loops[li].copy()
	chain = f.irLoopChain(l)
	if chain.isEmpty: return false
	top = chain[0]
	body = f.irChainBody(chain)
	done = false
	for c in f.irCountersFrom(body, chain, top, known):
		at = (0..body.len).find(body[it].dst == c) ?? continue   # the count, c = c + 1
		divs = (0..at).filter(f.irCarriable(body, it, c, known))
		if divs.isEmpty: continue
		pairs IrCarried[] = []
		for k in divs:
			d = body[k].b
			if not pairs.any(.d == d):
				pairs.push(f.irNewCarried(d))
		pad = f.irCarryPad(l, li, chain, body, divs, pairs) ?? continue
		f.irCarryInLoop(chain, c, pairs)
		f.loops[li].pre = pad
		done = true
		break   # the body changed: one counter a loop
	done

# the counters of the body: assigned once in it, by c = c + 1 (not checked), and a constant of at
# least 0 at the end of each block that enters the loop
fn irCountersFrom(f IrFn, body IrInst[], chain i64[], top i64, known i64?[]):
	ways = f.irWaysInto(top, chain) ?? return []
	if ways.isEmpty: return []
	found = []
	for inst in body:
		c = inst.dst
		if c < 0 or inst.op != irAdd or inst.a != c or inst.trap or body.filter(.dst == c).len != 1:
			continue
		enters = true
		for (b, _) in ways:
			enters = enters and f.irEntersNonNegative(b, c)
		if (known[inst.b] ?? 0) == 1 and enters:
			found.push(c)
	found

# whether the last assignment of c in block b is a constant of at least 0
fn irEntersNonNegative(f IrFn, b i64, c i64):
	insts = f.blocks[b].insts
	k = (0..insts.len).filter(insts[it].dst == c)
	if k.isEmpty: return false
	inst = insts[k[len - 1]]
	inst.op == irConst and inst.imm >= 0

# whether body[k] divides c by a divisor the body does not assign, nothing called before it
fn irCarriable(f IrFn, body IrInst[], k i64, c i64, known i64?[]):
	inst = body[k]
	(inst.op == irDiv or inst.op == irRem) and inst.a == c and inst.b >= 0 and inst.dst >= 0 and
		inst.dst != c and inst.dst != inst.b and known[inst.b] == none and
		body.all(.dst != inst.b) and
		not body[..k].any(.op in [irCall, irCallPtr, irDrop, irDeepCopy])

fn irNewCarried(mut f IrFn, d i64):
	IrCarried(
		d,
		quotient = f.irVreg(irInt),
		remainder = f.irVreg(irInt),
		size = f.irVreg(irInt),
		step = f.irVreg(irInt)
	)

# the block every way into the loop goes through first: each pair's division (its check), |d|
# and d's sign; the divisions in the loop read the carried ones. None when a division's way of
# dividing (signed, its bits) differs for one divisor.
fn irCarryPad(
	mut f IrFn,
	l IrLoop,
	li i64,
	chain i64[],
	body IrInst[],
	divs i64[],
	pairs IrCarried[]
) i64?:
	top = chain[0]
	ways = try f.irWaysInto(top, chain)
	insts = []
	for p in pairs:
		first = body[try divs.find(body[it].b == p.d)]
		if divs.any(body[it].b == p.d and (body[it].uns != first.uns or body[it].imm != first.imm)):
			return none
		insts.push(IrInst(op = irDiv, dst = p.quotient, a = first.a, b = p.d, imm = first.imm,
			uns = first.uns, line = first.line, col = first.col))
		insts.push(IrInst(op = irRem, dst = p.remainder, a = first.a, b = p.d, imm = first.imm,
			uns = first.uns, line = first.line, col = first.col))
		f.irSizeAndStep(insts, p, first.uns)
	insts.push(IrInst(op = irJmp, target = top))
	pad = f.irBlock()
	f.blocks[pad].insts = insts
	for (b, k) in ways:
		f.irSendWay(b, k, pad)
		f.irJoinLoops(li, b, top, pad)
	pad

# |d| (d itself unsigned, the smallest number wrapping to itself, which no remainder meets) and
# the quotient's step: 1, or -1 for a negative signed d
fn irSizeAndStep(mut f IrFn, mut insts IrInst[], p IrCarried, uns bool):
	zero = f.irVreg(irInt)
	one = f.irVreg(irInt)
	insts.push(IrInst(op = irConst, dst = zero, imm = 0))
	insts.push(IrInst(op = irConst, dst = one, imm = 1))
	if uns:
		insts.push(IrInst(op = irCopy, dst = p.size, a = p.d))
		insts.push(IrInst(op = irCopy, dst = p.step, a = one))
		return
	minus = f.irVreg(irInt)
	negated = f.irVreg(irInt)
	insts.push(IrInst(op = irConst, dst = minus, imm = -1))
	insts.push(IrInst(op = irNeg, dst = negated, a = p.d))
	insts.push(IrInst(op = irSelect, dst = p.size, a = p.d, b = zero, cond = irLt, c = negated,
		d = p.d))
	insts.push(IrInst(op = irSelect, dst = p.step, a = p.d, b = zero, cond = irLt, c = minus,
		d = one))

# the divisions of c in the chain read the carried pair; after the count, the pair moves on
fn irCarryInLoop(mut f IrFn, chain i64[], c i64, pairs IrCarried[]):
	for b in chain:
		out = []
		counted = false
		for inst in f.blocks[b].insts:
			if not counted and (inst.op == irDiv or inst.op == irRem) and inst.a == c and
				pairs.find(.d == inst.b) is p:
				from = p.quotient if inst.op == irDiv else p.remainder
				out.push(IrInst(op = irCopy, dst = inst.dst, a = from, line = inst.line,
					col = inst.col))
				continue
			out.push(inst.copy())
			if inst.dst == c and inst.op == irAdd:
				counted = true
				for p in pairs:
					f.irCarryTurn(out, p)
		f.blocks[b].insts = out
		if counted: return

# the pair one count on: the remainder up by one, and at |d| back to 0 with the quotient stepped
fn irCarryTurn(mut f IrFn, mut out IrInst[], p IrCarried):
	one = f.irVreg(irInt)
	zero = f.irVreg(irInt)
	up = f.irVreg(irInt)
	stepped = f.irVreg(irInt)
	out.push(IrInst(op = irConst, dst = one, imm = 1))
	out.push(IrInst(op = irConst, dst = zero, imm = 0))
	out.push(IrInst(op = irAdd, dst = up, a = p.remainder, b = one))
	out.push(IrInst(op = irAdd, dst = stepped, a = p.quotient, b = p.step))
	out.push(IrInst(op = irSelect, dst = p.quotient, a = up, b = p.size, cond = irEq,
		c = stepped, d = p.quotient))
	out.push(IrInst(op = irSelect, dst = p.remainder, a = up, b = p.size, cond = irEq, c = zero,
		d = up))
