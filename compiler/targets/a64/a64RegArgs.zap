# Zap's register convention on AArch64 (irArgPlan): the integer arguments in x0..x3 and the
# floats in d0..d5, each class in order, the rest on the stack; a small aggregate's result leaves
# in x0, x1 and d0..d3. These are the code's own scratch, where no vreg lives, so each value goes
# one by one.

# the values vs put in x0 up and d0 up, each class in order: a call's arguments (or a tail call's),
# or a result's leaves
fn a64LeavesIn(mut g Gen, em IrEmit, vs i64[]):
	at = irRegIndexes(vs.map(irFloat if em.f.classes[it] == irFloat else irInt))
	for i, v in vs:
		if em.f.classes[v] == irFloat:
			x = g.a64FloatIn(em, v, at[i])
			if x != at[i]: g.a.a64Op2(a64Fmov, at[i], x)
		else:
			g.a.a64Mov(at[i], g.a64IntOrZero(em, v, a64T0))

# the leaves of a call's result put where they live: dst (leaf 0, from x0 or d0) and each
# irCallOut's (from its register)
fn a64ResultOut(mut g Gen, em IrEmit, call IrInst, outs IrInst[]):
	if call.dst >= 0:
		g.a64LeafDone(em, call.dst, 0)
	for out in outs:
		g.a64LeafDone(em, out.dst, out.imm)

fn a64LeafDone(mut g Gen, em IrEmit, v i64, r i64):
	if v < 0: return
	if em.f.classes[v] == irFloat:
		g.a64FloatDone(em, v, r)
	else:
		g.a64IntDone(em, v, r)
