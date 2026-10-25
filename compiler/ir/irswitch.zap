# A switch's search, the same on every machine: its cases in order (as uns orders them), split in
# halves down to a run dense enough for a jump table (holes going to the default) or a few cases,
# compared one by one. The tables go after the function (FnState's switchTables): each entry a
# case's distance from its table.

irSwitchDensity = 3   # a jump table spans at most this many entries a case

irSwitchCompare = 0
irSwitchTable = 1
irSwitchSplit = 2

# how cases lo..hi are found: compared one by one, by a table of span entries (their
# differences multiples of 2^shift), or split at mid
type IrSwitchPlan:
	kind i64
	shift i64 = 0
	span i64 = 0
	mid i64 = 0

fn irSwitchPlan(values i64[], lo i64, hi i64):
	n = hi - lo
	if n <= 3: return IrSwitchPlan(irSwitchCompare)
	steps u64 = 0   # the differences from the first case, or-ed: their common power of two
	for i in lo + 1..hi:
		steps |= u64.wrap(values[i]) - u64.wrap(values[lo])
	shift = steps.trailingZeros()
	span = i64((u64.wrap(values[hi - 1]) - u64.wrap(values[lo])) >> u64(shift)) + 1
	if span <= irSwitchDensity * n: return IrSwitchPlan(irSwitchTable, shift, span)
	IrSwitchPlan(irSwitchSplit, mid = (lo + hi) / 2)

# the switch's values in order and their blocks' labels
fn irSwitchCases(em IrEmit, inst IrInst):
	sw = em.f.switches[inst.imm]
	flip = 1 << 63 if inst.uns else 0   # unsigned order as signed
	order = (0..sw.values.len).sortedBy(sw.values[it] ^ flip)
	(order.map(sw.values[it]), order.map(em.labels[sw.targets[it]]))

# the table of cases lo..hi: its label, then each entry's label (other for a hole)
fn irTableEntries(
	table i64,
	values i64[],
	labels i64[],
	lo i64,
	hi i64,
	shift i64,
	span i64,
	other i64
):
	entries = [table]
	entries.extend(fill(span, other))
	first = values[lo]
	for i in lo..hi:
		entries[1 + i64((u64.wrap(values[i]) - u64.wrap(first)) >> u64(shift))] = labels[i]
	entries

# the function's jump tables, after its code
fn irPlaceSwitchTables(mut g Gen):
	for t in g.f.switchTables:
		g.a.asmPlace(t[0])
		for l in t[1..]:
			g.a.asmTableEntry(l, t[0])
	g.f.switchTables.clear()

# what irSwitchPlan's search of cases lo..hi costs: the tests on the way to each case, summed (a
# table one, a split one more), and its tables' entries
type IrSwitchCost:
	tests i64
	entries i64

fn irSwitchCost(values i64[], lo i64, hi i64) IrSwitchCost:
	plan = irSwitchPlan(values, lo, hi)
	n = hi - lo
	if plan.kind == irSwitchCompare: return IrSwitchCost(n * (n + 1) / 2, 0)
	if plan.kind == irSwitchTable: return IrSwitchCost(n, plan.span)
	low = irSwitchCost(values, lo, plan.mid)
	high = irSwitchCost(values, plan.mid, hi)
	IrSwitchCost(low.tests + high.tests + n, low.entries + high.entries)
