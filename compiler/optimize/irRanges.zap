# Range facts: the values each integer vreg may hold, a Span (ranges.zap) whose ends are the i64's
# own when nothing bounds them (never `below` or `above`: opSpan then marks an end an operation
# passes). irValueSpans finds them for the whole function at once, from every assignment of each
# vreg, for a settle round (irOptNarrow.zap); irRangeFacts follows them through the flow: what
# holds at a block's start is what every way into it gives, narrowed by the branch it is entered
# by, then by each check passed in it (a fact from a comparison: `i < n` bounds i below n's most,
# and is kept as a comparison of the two vregs while neither is assigned). An overflow check or a
# check that stops the program they prove never fails goes, and a narrow value's check that it
# fits (an i8's sum) compares it with the one end it may pass.

# a span of any i64
fn irSpanAny():
	Span(spanDown, spanUp)

# the values of an integer of `bits` bits, unsigned or signed
fn irWidthSpan(bits i64, uns bool):
	if bits >= 64: return irSpanAny()
	if uns: return Span(0, (1 << bits) - 1)
	Span(-(1 << (bits - 1)), (1 << (bits - 1)) - 1)

fn irSpanWithin(s Span, t Span):
	s.lo >= t.lo and s.hi <= t.hi

fn irSpanHull(a Span, b Span):
	Span(a.lo.min(b.lo), a.hi.max(b.hi))

# the values both spans hold, none when they share none
fn irSpanMeet(a Span, b Span) Span?:
	lo = a.lo.max(b.lo)
	hi = a.hi.min(b.hi)
	if lo > hi: return none
	Span(lo, hi)

# s without the value k at one of its ends
fn irSpanWithout(s Span, k i64):
	if s.lo == k and s.hi > k: return Span(k + 1, s.hi)
	if s.hi == k and s.lo < k: return Span(s.lo, k - 1)
	s

# the condition that holds when cond does not
fn irNegatedCond(cond i64):
	irNe if cond == irEq
		else irEq if cond == irNe
		else irGe if cond == irLt
		else irLt if cond == irGe
		else irGt if cond == irLe
		else irLe

# the operation of ranges.zap's opSpan an instruction's is, -1 for none
fn irSpanOp(op i64):
	if op == irAdd: return binAdd
	if op == irSub: return binSub
	if op == irMul: return binMul
	if op == irDiv: return binDiv
	if op == irRem: return binMod
	if op == irAnd: return binBand
	if op == irOr: return binBor
	if op == irXor: return binBxor
	if op == irShl: return binShl
	if op == irShr: return binShr
	-1

# the exact values a + b, a - b, a * b, a << b or -a give from their operands', an end marked where
# the operation leaves 64 bits; none when nothing is known
fn irExactSpan(inst IrInst, spans Span[]) Span?:
	if inst.op == irNeg: return spans[inst.a].negSpan()
	if inst.op == irNot: return Span(~spans[inst.a].hi, ~spans[inst.a].lo)
	op = irSpanOp(inst.op)
	if op < 0 or inst.a < 0 or inst.b < 0: return none
	a = spans[inst.a]
	b = spans[inst.b]
	if inst.uns and (inst.op in [irDiv, irRem, irShr]) and (a.lo < 0 or b.lo < 0):
		# unsigned: a logical shift right by at least one is below 2^63
		if inst.op == irShr and a.lo < 0 and b.lo >= 1 and b.hi <= 63:
			return Span(0, spanUp >> (b.lo - 1))
		return none
	opSpan(op, a, b)

# whether an operation that stops the program on an overflow may overflow: an i32's when either
# operand or the result leaves 32 bits (its operation reads the low halves)
fn irOverflows(inst IrInst, spans Span[]):
	r = inst.irExactSpan(spans) ?? return true
	if r.below or r.above: return true
	if inst.size != 4: return false
	t = irWidthSpan(32, false)
	not r.irSpanWithin(t) or not spans[inst.a].irSpanWithin(t) or
		inst.b >= 0 and not spans[inst.b].irSpanWithin(t)

# The values an instruction's integer result may hold, from its operands' spans: a list's length,
# a narrow load's or a wrap's width, a constant, a set's 0 or 1, arithmetic's exact values (cut at the end an
# overflow check stops at; any when one that wraps may pass an end), an operation on 32 bits's below
# 2^32; any for the rest.
fn irSpanOf(inst IrInst, spans Span[]):
	op = inst.op
	if op == irConst: return spanAt(inst.imm)
	if op == irCopy: return spans[inst.a]
	if op == irSet: return Span(0, 1)
	if op == irTzcnt: return Span(0, 64)
	if op == irLoad and inst.header and inst.imm == 8: return Span(0, spanUp)   # a length (irHeader)
	if op == irLoad or op == irVecLaneOf:
		return irWidthSpan(8 * inst.size, inst.uns) if inst.size < 8 else irSpanAny()
	if op == irTrunc:
		t = irWidthSpan(inst.imm, inst.uns)
		return spans[inst.a] if spans[inst.a].irSpanWithin(t) else t
	if op == irSelect: return inst.irSelectSpan(spans)
	if irSpanOp(op) < 0 and op != irNeg and op != irNot: return irSpanAny()
	r = inst.irExactSpan(spans)
	if inst.irIs32():
		t = irWidthSpan(32, true)
		if r is s and not s.below and not s.above and s.irSpanWithin(t): return s
		return t
	if inst.trap:
		t = irWidthSpan(32, false) if inst.size == 4 else irSpanAny()
		if r is s: return irSpanMeet(Span(s.lo, s.hi), t) ?? t
		return t
	if r is s and not s.below and not s.above: return s
	irSpanAny()

irSpanRounds = 2   # the times a vreg's span may grow before the side that grows goes to its end

# The span of each vreg in the whole function: the hull of what each assignment gives it from its
# operands', from none, raised until every assignment fits (a side still growing after a few
# rounds goes to the i64's end); any for a vreg of another class or assigned nowhere.
fn irValueSpans(f IrFn):
	nv = f.classes.len
	spans = fill(nv, irSpanAny())
	known = fill(nv, true)   # whether spans[v] holds a value yet
	for b in f.blocks:
		for inst in b.insts:
			if inst.dst >= 0 and f.classes[inst.dst] == irInt: known[inst.dst] = false
	grew = zeros(nv)
	again = true
	while again:
		again = false
		for b in f.blocks:
			for inst in b.insts:
				v = inst.dst
				if v < 0 or f.classes[v] != irInt or not inst.irReads().all(known[it]): continue
				s = inst.irSpanOf(spans)
				if not known[v]:
					known[v] = true
					spans[v] = s
					again = true
				elif not s.irSpanWithin(spans[v]):
					h = spans[v].irSpanHull(s)
					grew[v] += 1
					if grew[v] > irSpanRounds:
						h = Span(
							spanDown if h.lo < spans[v].lo else h.lo,
							spanUp if h.hi > spans[v].hi else h.hi
						)
					spans[v] = h
					again = true
		if not again:
			# assigned only from vregs found nowhere (copies of each other): any value
			for v in 0..nv:
				if not known[v]:
					known[v] = true
					again = true
	spans

# whether a cond b never holds for values in spans a and b (uns: compared unsigned, which orders
# them as signed when neither span holds values of both signs)
fn irNeverHolds(cond i64, uns bool, a Span, b Span):
	x = a
	y = b
	if uns:
		if a.lo < 0 and a.hi >= 0 or b.lo < 0 and b.hi >= 0: return false
		x = Span(a.lo ^ spanDown, a.hi ^ spanDown)
		y = Span(b.lo ^ spanDown, b.hi ^ spanDown)
	if cond == irEq: return x.hi < y.lo or y.hi < x.lo
	if cond == irNe: return x.lo == x.hi and y.lo == y.hi and x.lo == y.lo
	if cond == irLt: return x.lo >= y.hi
	if cond == irLe: return x.lo > y.hi
	if cond == irGt: return x.hi <= y.lo
	x.hi < y.lo

# ---------- through the flow ----------

# a comparison that holds between two vregs: a < b when strict, else a <= b
type IrRel:
	a i64
	b i64
	strict bool

# what holds at a point: the vregs whose span is narrower there than in the whole function (vs,
# with spans), and the comparisons
type IrRangeState:
	vs i64[]
	spans Span[]
	rels IrRel[]

fn irNoRanges():
	IrRangeState(vs = [], spans = [], rels = [])

irRangesMost = 64   # the most spans a state keeps (dropping one only forgets a fact)
irRelsMost = 16
irRangePasses = 6   # the walks of the flow before giving up on settling

# A walk through a block: each vreg's span where the walk is (the whole function's for those not
# touched), the vregs touched since the walk entered the block, the comparisons holding.
type IrRangeWalk:
	whole Span[]
	cur Span[]
	touched i64[]
	marked bool[]
	rels IrRel[]

fn irRangeSet(mut w IrRangeWalk, v i64, s Span):
	if s == w.cur[v]: return
	w.cur[v] = s
	if not w.marked[v]:
		w.marked[v] = true
		w.touched.push(v)

# the walk at a point where st holds
fn irRangeEnter(mut w IrRangeWalk, st IrRangeState):
	for v in w.touched:
		w.cur[v] = w.whole[v]
		w.marked[v] = false
	w.touched.truncate(0)
	for i, v in st.vs:
		w.irRangeSet(v, st.spans[i])
	w.rels = st.rels.copy()

# what holds where the walk is
fn irRangeHere(w IrRangeWalk):
	st = irNoRanges()
	for v in w.touched:
		if w.cur[v] != w.whole[v] and st.vs.len < irRangesMost:
			st.vs.push(v)
			st.spans.push(w.cur[v])
	st.rels = w.rels.copy()
	st

fn irRangeRel(mut w IrRangeWalk, a i64, b i64, strict bool):
	if w.rels.any(.a == a and .b == b and (.strict or not strict)): return
	if w.rels.len < irRelsMost: w.rels.push(IrRel(a, b, strict))

# what a cond b holding tells (uns: compared unsigned): the spans it narrows, and a < b (a <= b)
# kept as a comparison; a way no values take tells nothing
fn irRangeAssume(mut w IrRangeWalk, cond i64, uns bool, a i64, b i64):
	if a < 0 or b < 0 or a == b: return
	if cond == irGt or cond == irGe:
		w.irRangeAssume(irSwappedCond(cond), uns, b, a)
		return
	na, nb = irSpansUnder(cond, uns, w.cur[a], w.cur[b]) ?? return
	w.irRangeSet(a, na)
	w.irRangeSet(b, nb)
	if (cond == irLt or cond == irLe) and (not uns or w.cur[b].lo >= 0):
		w.irRangeRel(a, b, cond == irLt)

# the spans of a and b where a cond b holds (uns: compared unsigned, read as signed when b is
# never negative, a then neither); none for a way no values take
fn irSpansUnder(cond i64, uns bool, sa Span, sb Span) (Span, Span)?:
	if cond == irGt or cond == irGe:
		y, x = try irSpansUnder(irSwappedCond(cond), uns, sb, sa)
		return (x, y)
	if cond == irEq:
		m = try sa.irSpanMeet(sb)
		return (m, m)
	if cond == irNe:
		return (
			sa.irSpanWithout(sb.lo) if sb.lo == sb.hi else sa,
			sb.irSpanWithout(sa.lo) if sa.lo == sa.hi else sb
		)
	x = sa
	if uns:
		if sb.lo < 0: return (sa, sb)
		x = try sa.irSpanMeet(Span(0, spanUp))
	strict = cond == irLt
	if strict and (sb.hi == spanDown or x.lo == spanUp): return none
	gap = 1 if strict else 0
	na = try x.irSpanMeet(Span(spanDown, sb.hi - gap))
	nb = try sb.irSpanMeet(Span(x.lo + gap, spanUp))
	(na, nb)

# a select's values: each arm that is one of the compared vregs, narrowed by the comparison (a
# max's `x < 1 ? 1 : x` is at least 1)
fn irSelectSpan(inst IrInst, spans Span[]):
	c = spans[inst.c]
	d = spans[inst.d]
	if inst.a >= 0 and inst.b >= 0:
		if irSpansUnder(inst.cond, inst.uns, spans[inst.a], spans[inst.b]) is yes:
			ya, yb = yes
			if inst.c == inst.a: c = ya
			elif inst.c == inst.b: c = yb
		if irSpansUnder(irNegatedCond(inst.cond), inst.uns, spans[inst.a], spans[inst.b]) is no:
			na, nb = no
			if inst.d == inst.a: d = na
			elif inst.d == inst.b: d = nb
	c.irSpanHull(d)

# whether a cond b never holds where the walk is: by the spans, or by a comparison known (a < b
# rules out a >= b, and unsigned too when a is never negative)
fn irRangeNever(w IrRangeWalk, cond i64, uns bool, a i64, b i64) bool:
	if irNeverHolds(cond, uns, w.cur[a], w.cur[b]): return true
	if cond == irLt or cond == irLe:
		return w.irRangeNever(irGt if cond == irLt else irGe, uns, b, a)
	if cond != irGt and cond != irGe or uns and w.cur[a].lo < 0: return false
	w.rels.any(.a == a and .b == b and (.strict or cond == irGt))

# what assigning v tells: its comparisons end, its span is what the instruction gives
fn irRangeDef(mut w IrRangeWalk, f IrFn, inst IrInst):
	v = inst.dst
	if w.rels.any(.a == v or .b == v): w.rels = w.rels.filter(.a != v and .b != v)
	if f.classes[v] != irInt: return
	w.irRangeSet(v, inst.irSpanOf(w.cur).irSpanMeet(w.whole[v]) ?? w.whole[v])

# what the way from block p to block b tells: its branch's comparison, or its negation
fn irRangeEdge(f IrFn, mut w IrRangeWalk, p i64, b i64):
	alias insts = f.blocks[p].insts
	if insts.isEmpty: return
	t = insts.len - 1
	if insts[t].op != irBranch or insts[t].target == insts[t].other or insts[t].a < 0 or
		insts[t].b < 0 or f.classes[insts[t].a] != irInt:
		return
	cond = i64(insts[t].cond) if insts[t].target == b else irNegatedCond(insts[t].cond)
	w.irRangeAssume(cond, insts[t].uns, insts[t].a, insts[t].b)

# what holds at both points: the spans both narrow, made their hull, and the comparisons of both
fn irJoinRanges(x IrRangeState, y IrRangeState):
	st = irNoRanges()
	for i, v in x.vs:
		if y.vs.indexOf(v) is j:
			st.vs.push(v)
			st.spans.push(x.spans[i].irSpanHull(y.spans[j]))
	st.rels = x.rels.filter(r: y.rels.any(it == r))
	st

# a loop's top seen again: a span that changed since is the whole function's, then narrowed by
# the comparisons that hold (so the walks settle)
fn irWidenRanges(mut w IrRangeWalk, old IrRangeState, now IrRangeState):
	st = irNoRanges()
	for i, v in now.vs:
		if old.vs.indexOf(v) is j and old.spans[j] == now.spans[i]:
			st.vs.push(v)
			st.spans.push(now.spans[i])
	st.rels = now.rels.copy()
	w.irRangeEnter(st)
	for r in now.rels:
		w.irRangeAssume(irLt if r.strict else irLe, false, r.a, r.b)
	w.irRangeHere()

# what holds at block b's start: what every way from a block walked gives (the entry: nothing)
fn irRangeInto(f IrFn, mut w IrRangeWalk, b i64, preds i64[], outs IrRangeState[], seen bool[]):
	acc = irNoRanges()
	if b == 0: return acc
	first = true
	for p in preds:
		if not seen[p]: continue
		w.irRangeEnter(outs[p])
		f.irRangeEdge(w, p, b)
		e = w.irRangeHere()
		acc = e if first else acc.irJoinRanges(e)
		first = false
	acc

# Range facts through the flow (the file's comment): the blocks walked in reverse postorder until
# what holds at each one's start settles (a loop's top widened), then once more taking out the
# checks proven. True when one went.
fn irRangeFacts(mut f IrFn):
	if not f.blocks.any(.insts.any(.trap or .op == irFailIf)): return false
	order = f.irLayout()
	pos = f.irLayoutPos(order)
	n = f.blocks.len
	preds i64[,] = []
	ins = []
	outs = []
	loop n:
		preds.push([])
		ins.push(irNoRanges())
		outs.push(irNoRanges())
	for b in order:
		for s in f.irBlockSuccessors(b):
			if b not in preds[s]: preds[s].push(b)
	whole = f.irValueSpans()
	w = IrRangeWalk(
		whole = whole.copy(),
		cur = whole,
		touched = [],
		marked = fill(f.classes.len, false),
		rels = []
	)
	seen = fill(n, false)
	settled = false
	loop irRangePasses:
		changed = false
		for b in order:
			st = f.irRangeInto(w, b, preds[b], outs, seen)
			if seen[b] and preds[b].any(pos[it] >= pos[b]):
				st = w.irWidenRanges(ins[b], st)
			if not seen[b] or st != ins[b]: changed = true
			ins[b] = st
			w.irRangeEnter(ins[b])
			f.irRangeBlock(w, b, false)
			outs[b] = w.irRangeHere()
			seen[b] = true
		if not changed:
			settled = true
			break
	if not settled: return false
	any = false
	for b in order:
		w.irRangeEnter(ins[b])
		if f.irRangeBlock(w, b, true): any = true
	for b in order:
		if f.irFuseBelow(b, preds[b], w.whole): any = true
	any

# The check `x >= n` unsigned that block b makes first (only quiet work before it) when every way
# into it is a branch taken when x < n signed, n never negative: each branch then compares
# unsigned, the check gone, and its other way goes through a block stopping the program where x
# is negative (x < n there) before it goes on. One comparison where two were (`while pc <
# ops.len: ops[pc]`, pc read from memory and so maybe negative). True when one was.
fn irFuseBelow(mut f IrFn, b i64, preds i64[], whole Span[]):
	if b == 0 or preds.isEmpty or not f.merges.isEmpty: return false
	alias insts = f.blocks[b].insts
	k = 0
	while k < insts.len and insts[k].op != irFailIf:
		if not insts[k].irQuiet(): return false
		k += 1
	if k == insts.len or not insts[k].uns: return false
	check = insts[k].copy()
	x = check.a if check.cond == irGe else check.b if check.cond == irLe else -1
	n = check.b if check.cond == irGe else check.a
	if x < 0 or n < 0 or x == n or f.classes[x] != irInt or whole[n].lo < 0: return false
	if (0..k).any(insts[it].dst == x or insts[it].dst == n): return false
	if not preds.all(f.irBranchBelow(it, b, x, n)): return false
	f.irTakeOut(b, k)
	f.irDropTakenOut(b)
	sides = []   # a block stopping the program for each way out, by the block it goes to
	outs i64[] = []
	for p in preds:
		last = f.blocks[p].insts.len - 1
		br = f.blocks[p].insts[last].copy()
		out = br.other if br.target == b else br.target
		if out not in outs:
			side = f.irBlock()
			f.blocks[side].insts = [
				IrInst(
					op = irFailIf,
					a = x,
					b = n,
					cond = irLt,
					imm = check.imm,
					line = check.line,
					col = check.col,
					foreign = check.foreign
				),
				IrInst(op = irJmp, target = out)
			]
			for o in 0..f.loops.len:
				if p in f.loops[o].blocks and out in f.loops[o].blocks: f.loops[o].blocks.push(side)
			outs.push(out)
			sides.push(side)
		f.blocks[p].insts[last] = IrInst(
			op = irBranch,
			a = x,
			b = n,
			cond = irLt,
			uns = true,
			target = b,
			other = sides[outs.indexOf(out) ?? 0],
			line = br.line,
			col = br.col
		)
	true

# whether block p ends in a branch to b taken when x < n signed, its other way elsewhere
fn irBranchBelow(f IrFn, p i64, b i64, x i64, n i64):
	alias insts = f.blocks[p].insts
	if insts.isEmpty: return false
	br = insts[len - 1]
	if br.op != irBranch or br.uns or br.target == br.other or br.target != b and br.other != b:
		return false
	cond = i64(br.cond) if br.target == b else irNegatedCond(br.cond)
	br.a == x and br.b == n and cond == irLt or br.a == n and br.b == x and cond == irGt

# whether an instruction only computes a value from others: no write, call, check or stop that
# running it or not could show
fn irQuiet(inst IrInst):
	not inst.trap and inst.op in [irConst, irCopy, irAdd, irSub, irMul, irAnd, irOr, irXor, irNeg,
		irNot, irSet, irLoad, irTrunc, irSelect, irDataAddr, irFrameAddr]

# Block b walked from what holds at its start (w): what each instruction tells noted and, when
# `rewrite`, each check proven taken out or made one comparison (irFitCheck). True when one was.
fn irRangeBlock(mut f IrFn, mut w IrRangeWalk, b i64, rewrite bool):
	changed = false
	consts = []   # each a constant a check made one comparison reads, put before it
	before = []   # the position each goes before
	for k in 0..f.blocks[b].insts.len:
		op = f.blocks[b].insts[k].op
		a = f.blocks[b].insts[k].a
		if op == irFailIf and a >= 0 and f.classes[a] == irInt:
			if rewrite:
				if w.irRangeNever(
					f.blocks[b].insts[k].cond,
					f.blocks[b].insts[k].uns,
					a,
					f.blocks[b].insts[k].b
				):
					f.irTakeOut(b, k)
					changed = true
					continue
				if f.irFitCheck(w, b, k) is c:
					if c.dst >= 0:
						consts.push(c)
						before.push(k)
					changed = true
					if f.blocks[b].insts[k].op == irTakenOut: continue
			alias check = f.blocks[b].insts[k]
			w.irRangeAssume(irNegatedCond(check.cond), check.uns, check.a, check.b)
			continue
		if rewrite and f.blocks[b].insts[k].trap and
			not f.blocks[b].insts[k].irOverflows(w.cur):
			f.blocks[b].insts[k].trap = false
			f.blocks[b].insts[k].size = 8   # (an i32's operands and result within 32 bits)
			changed = true
		if f.blocks[b].insts[k].dst >= 0: w.irRangeDef(f, f.blocks[b].insts[k])
	if not changed: return false
	if not consts.isEmpty:
		alias insts = f.blocks[b].insts
		made = []
		at = 0
		for k in 0..insts.len:
			while at < consts.len and before[at] == k:
				made.push(consts[at].copy())
				at += 1
			made.push(insts[k].copy())
		f.blocks[b].insts = made
	f.irDropTakenOut(b)
	true

# the wrap a narrow value's check that it fits is (failif k of block b: w != v, w = v wrapped
# before it, w read and v assigned nowhere between, irFits), else -1
fn irFitWrap(f IrFn, b i64, k i64):
	alias insts = f.blocks[b].insts
	if insts[k].cond != irNe or insts[k].b < 0: return -1
	wrapped = insts[k].a
	v = insts[k].b
	j = k - 1
	while j >= 0 and insts[j].dst != wrapped:
		if insts[j].dst == v or insts[j].irReadsVreg(wrapped): return -1
		j -= 1
	if j < 0 or insts[j].op != irTrunc or insts[j].a != v: return -1
	j

# A narrow value's check that it fits (irFitWrap) where the walk knows the value's span: none when
# nothing changed; else the wrap is a copy of the value, and the check goes when the value fits
# its width, else is the value past the one end its span may pass, the constant of that end
# returned to be put before it (dst -1: none)
fn irFitCheck(mut f IrFn, mut w IrRangeWalk, b i64, k i64) IrInst?:
	j = f.irFitWrap(b, k)
	if j < 0: return none
	v = f.blocks[b].insts[k].b
	t = irWidthSpan(f.blocks[b].insts[j].imm, f.blocks[b].insts[j].uns)
	s = w.cur[v]
	if s.lo < t.lo and s.hi > t.hi: return none
	line = f.blocks[b].insts[j].line
	col = f.blocks[b].insts[j].col
	f.blocks[b].insts[j] = IrInst(op = irCopy, dst = f.blocks[b].insts[k].a, a = v, line, col)
	if s.irSpanWithin(t):
		f.irTakeOut(b, k)
		return IrInst(op = irConst)
	end = t.hi if s.lo >= t.lo else t.lo
	c = f.irVreg(irInt)
	w.whole.push(spanAt(end))
	w.cur.push(spanAt(end))
	w.marked.push(false)
	f.blocks[b].insts[k].cond = irGt if s.lo >= t.lo else irLt
	f.blocks[b].insts[k].uns = false
	f.blocks[b].insts[k].a = v
	f.blocks[b].insts[k].b = c
	IrInst(op = irConst, dst = c, imm = end, line, col)
