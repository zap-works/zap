# A translated function's dispatcher: a loop whose top only switches on a variable, the arms
# jumping back with it set to the next arm's key (a state machine).

# Each jump back from a block that leaves the switch's variable a known constant goes straight to
# that constant's case, the switch skipped; a top nothing reaches then is left a jump to itself,
# so the constants written for it are pruned. True when a jump moved.
fn irEnterArms(mut f IrFn):
	consts = f.irFacts().consts
	loopsOf = f.irLoopsOf()
	pres = f.loops.map(.pre)
	tops i64[] = []
	for b in 0..f.blocks.len:
		n = f.blocks[b].insts.len
		if n == 0 or f.blocks[b].insts[n - 1].op != irJmp: continue
		top = f.irJumpEnd(f.blocks[b].insts[n - 1].target, loopsOf, b, pres)
		sw = f.blocks[top].insts
		if sw.len != 1 or sw[0].op != irSwitch or top == b: continue
		key = irKnownAt(irSetConsts(f.blocks[b].insts), consts, sw[0].a) ?? continue
		cases = f.switches[sw[0].imm]
		to = sw[0].other
		if cases.values.indexOf(key) is at: to = cases.targets[at]
		if to < 0 or to == top: continue
		f.blocks[b].insts[n - 1].target = to
		if top not in tops: tops.push(top)
	if tops.isEmpty: return false
	reached = f.irReachedAvoiding([0], -1)
	for top in tops:
		if not reached[top]:
			f.blocks[top].insts = [IrInst(op = irJmp, target = top)]
	true

# A sparse switch whose cases fall in a dense run of pages of 2^s keys (one bank's addresses, a
# function's labels): a switch on the page (key >> s, by a table), each page's block then
# switching on the key's low s bits. Taken when a case is reached by fewer tests on average, by
# one at least, a page's block counted as one more (its code), its tables no more than
# irSwitchDensity entries a case. True when one was.
fn irSwitchPages(mut f IrFn):
	changed = false
	for b in 0..f.blocks.len:
		n = f.blocks[b].insts.len
		if n == 0 or f.blocks[b].insts[n - 1].op != irSwitch: continue
		sw = f.blocks[b].insts[n - 1]
		s = irPageBits(f.switches[sw.imm].values, sw.uns) ?? continue
		f.irSplitPages(b, s)
		changed = true
	changed

irPagedFewest = 8   # the fewest cases a switch split in pages has

# the page bits that reach a case by the fewest tests, if any beats the cases searched whole
fn irPageBits(values i64[], uns bool) i64?:
	n = values.len
	if n < irPagedFewest: return none
	flip = 1 << 63 if uns else 0
	whole = irSwitchCost(values.sortedBy(it ^ flip), 0, n)
	keys = values.map(u64.wrap(it)).sorted()
	best i64? = none
	fewest = whole.tests - n
	for s in 1..64:
		pages i64[] = []
		for k in keys:
			if pages.isEmpty or pages[len - 1] != i64(k >> u64(s)): pages.push(i64(k >> u64(s)))
		if pages.len < 2: break
		top = irSwitchPlan(pages, 0, pages.len)
		if top.kind != irSwitchTable: continue
		tests = n + pages.len
		entries = top.span
		at = 0
		for page in pages:
			end = at
			while end < n and i64(keys[end] >> u64(s)) == page:
				end += 1
			lows = keys[at..end].map(i64(it & irLowMask(s)))
			cost = irSwitchCost(lows, 0, lows.len)
			tests += cost.tests
			entries += cost.entries
			at = end
		if entries <= irSwitchDensity * n and tests < fewest:
			best = s
			fewest = tests
	best

# block b's closing switch made a switch on its key's page (key >> s), each page's block a switch
# on the key's low s bits to the cases' blocks (the default the same)
fn irSplitPages(mut f IrFn, b i64, s i64):
	sw = f.blocks[b].insts.pop() ?? return
	cases = f.switches[sw.imm]
	mask = i64(irLowMask(s))
	page = f.irVreg(irInt)
	shift = f.irVreg(irInt)
	f.blocks[b].insts.push(IrInst(op = irConst, dst = shift, imm = s))
	f.blocks[b].insts.push(IrInst(op = irShr, dst = page, a = sw.a, b = shift, uns = true))
	top = IrSwitch(values = [], targets = [])
	lows IrSwitch[] = []
	for i in 0..cases.values.len:
		v = cases.values[i]
		p = i64(u64.wrap(v) >> u64(s))
		k = top.values.indexOf(p) ?? -1
		if k < 0:
			k = top.values.len
			top.values.push(p)
			top.targets.push(f.irBlock())
			lows.push(IrSwitch(values = [], targets = []))
		lows[k].values.push(v & mask)
		lows[k].targets.push(cases.targets[i])
	for k, pb in top.targets:
		bits = f.irVreg(irInt)
		low = f.irVreg(irInt)
		f.blocks[pb].insts = [
			IrInst(op = irConst, dst = bits, imm = mask),
			IrInst(op = irAnd, dst = low, a = sw.a, b = bits),
			IrInst(
				op = irSwitch,
				a = low,
				imm = f.switches.len,
				other = sw.other,
				uns = true,
				cond = sw.cond
			)
		]
		f.switches.push(lows[k].copy())
	f.blocks[b].insts.push(
		IrInst(
			op = irSwitch,
			a = page,
			imm = f.switches.len,
			other = sw.other,
			uns = true,
			cond = sw.cond
		)
	)
	for lj in 0..f.loops.len:
		if b in f.loops[lj].blocks: f.loops[lj].blocks.extend(top.targets)
	f.switches.push(top)

# the low s bits of a key
fn irLowMask(s i64):
	(u64(1) << u64(s)) - 1
