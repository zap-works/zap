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
