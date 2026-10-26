# A switch on AArch64, searched as irSwitch.zap plans: compares and b.eq, b.hs or b.ge to the
# upper half, or a jump table.

# cases lo..hi of a switch on the register x, the default other (fall: the label of the block
# after it, which needs no jump; every: x is one of the cases, so no test is made for the default)
fn a64SwitchSearch(
	mut g Gen,
	x i64,
	values i64[],
	labels i64[],
	lo i64,
	hi i64,
	other i64,
	fall i64,
	uns bool,
	every bool
):
	plan = irSwitchPlan(values, lo, hi)
	if plan.kind == irSwitchCompare:
		for i in lo..hi:
			if every and i == hi - 1:
				if labels[i] != fall: g.a.a64B(labels[i])
				return
			g.a.a64CmpValue(x, values[i], a64T1)
			g.a.a64BCond(a64Eq, labels[i])
		if other != fall: g.a.a64B(other)
	elif plan.kind == irSwitchTable:
		g.a64JumpTable(x, values, labels, lo, hi, plan, other, every)
	else:
		upper = g.a.asmNewLabel()
		g.a.a64CmpValue(x, values[plan.mid], a64T1)
		g.a.a64BCond(a64Hs if uns else a64Ge, upper)
		g.a64SwitchSearch(x, values, labels, lo, plan.mid, other, -1, uns, every)
		g.a.asmPlace(upper)
		g.a64SwitchSearch(x, values, labels, plan.mid, hi, other, fall, uns, every)

# A jump table for cases lo..hi of a switch on x: x less the first case in x6, its low bits
# tested, shifted, its range tested, then the entry's distance from the table (x7) added to it
fn a64JumpTable(
	mut g Gen,
	x i64,
	values i64[],
	labels i64[],
	lo i64,
	hi i64,
	plan IrSwitchPlan,
	other i64,
	every bool
):
	first = values[lo]
	if first > -4096 and first < 4096:
		g.a.a64AddImm(6, x, -first)
	else:
		g.a.a64MovImm(7, first)
		g.a.a64Op3(a64Sub, 6, x, 7)
	if plan.shift > 0:
		if not every:
			g.a.a64LogicalImm(a64Ands, a64Zr, 6, (1 << plan.shift) - 1, true)
			g.a.a64BCond(a64Ne, other)
		g.a.a64ShiftImm(1, 6, 6, plan.shift, true)
	if not every:
		g.a.a64CmpValue(6, plan.span - 1, 7)
		g.a.a64BCond(a64Hi, other)   # past the last case, or before the first
	table = g.a.asmNewLabel()
	g.a.a64AdrLabel(7, table)
	g.a.a64AccessIndexed(a64LoadOp(4, false), 6, 7, 6, true)   # ldrsw x6, [x7, x6, lsl 2]
	g.a.a64Op3(a64Add, 6, 7, 6)
	g.a.a64(0xD61F_0000 | 6 << 5)   # br x6
	g.f.switchTables.push(
		irTableEntries(table, values, labels, lo, hi, plan.shift, plan.span, other)
	)
