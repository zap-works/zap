# Zap's register convention on x64 (irArgPlan): the integer arguments in rcx, rdx, r8, r9 and
# the floats in xmm0..xmm5, each class in order, the rest on the stack (irArgPlaces); a small
# aggregate's result leaves in rax, rdx and xmm0..xmm3. No vreg lives in rcx or rdx, nor in r8 or
# r9 where a call meets it, so the integers go one by one; the floats may sit in xmm2..xmm5, so
# they move as one (irFloatsInto).

# the arguments vs put in their registers before a call (or a tail call's jump)
fn irRegArgsIn(mut g Gen, em IrEmit, vs i64[]):
	floats = vs.filter(em.f.classes[it] == irFloat)
	g.irFloatsInto(em, floats, (0..floats.len).map(it))
	ints = vs.filter(em.f.classes[it] != irFloat)
	for i, v in ints:
		g.irMov(regArgRegs()[i], g.irIntIn(em, v, regArgRegs()[i]))

# the parameters in registers from insts[ii] on put where they live, the floats at once (one may
# live in the register another comes in): how many they are
fn irParamsIn(mut g Gen, em IrEmit, insts IrInst[], ii i64):
	k = ii
	xs = []
	vs = []
	while k < insts.len and insts[k].op == irParam and insts[k].regArgs:
		v = insts[k].dst
		if em.f.classes[v] == irFloat:
			xs.push(insts[k].imm)
			vs.push(v)
		else:
			g.irIntDone(em, v, regArgRegs()[insts[k].imm])
		k += 1
	g.irFloatsFrom(em, xs, vs)
	k - ii

# a small aggregate's leaves vs given back: the integers in rax and rdx, the floats in xmm0 up
fn irResultIn(mut g Gen, em IrEmit, vs i64[]):
	floats = vs.filter(em.f.classes[it] == irFloat)
	g.irFloatsInto(em, floats, (0..floats.len).map(it))
	for i, v in vs.filter(em.f.classes[it] != irFloat):
		r = irResultInts[i]
		g.irMov(r, g.irIntIn(em, v, r))

irResultInts = [0, 2]   # rax, rdx

# the leaves of a call's result put where they live: dst (leaf 0) and each irCallOut's, the
# registers they came in read before any is written over
fn irResultOut(mut g Gen, em IrEmit, call IrInst, outs IrInst[]):
	dsts = [call.dst]
	regs = [0]
	dsts.extend(outs.map(.dst))
	regs.extend(outs.map(.imm))
	floatDsts = []
	floatRegs = []
	for k, v in dsts:
		if v < 0: continue
		if em.f.classes[v] == irFloat:
			floatDsts.push(v)
			floatRegs.push(regs[k])
		else:
			g.irIntDone(em, v, irResultInts[regs[k]])
	g.irFloatsFrom(em, floatRegs, floatDsts)

# xmm registers xs given the floats vs at once: those already in registers moved in an order that
# reads each before it is written over (irXmmMoves), then the others loaded
fn irFloatsInto(mut g Gen, em IrEmit, vs i64[], xs i64[]):
	moves = XmmMoves(froms = [], tos = [])
	for i, v in vs:
		if em.irInReg(v) and em.rs.reg[v] != xs[i]:
			moves.froms.push(em.rs.reg[v])
			moves.tos.push(xs[i])
	g.irXmmMoves(moves)
	for i, v in vs:
		if not em.irInReg(v): g.irFloatIn(em, v, xs[i])

# the floats in xmm registers xs put in vregs vs at once: the slots written first, then the
# registers (irXmmMoves; of two vregs given one register, the later one's is kept: the other is
# read nowhere)
fn irFloatsFrom(mut g Gen, em IrEmit, xs i64[], vs i64[]):
	moves = XmmMoves(froms = [], tos = [])
	for i, v in vs:
		if em.rs.spilled[v]:
			g.irFloatDone(em, v, xs[i])
		elif em.rs.reg[v] >= 0:
			if moves.tos.indexOf(em.rs.reg[v]) is k:
				moves.froms.remove(k)
				moves.tos.remove(k)
			if em.rs.reg[v] != xs[i]:
				moves.froms.push(xs[i])
				moves.tos.push(em.rs.reg[v])
	g.irXmmMoves(moves)

# xmm register moves, each to a register of its own, made as if at once
type XmmMoves:
	froms i64[]
	tos i64[]

fn irXmmMoves(mut g Gen, move moves XmmMoves):
	while not moves.tos.isEmpty:
		ready = -1
		for i, to in moves.tos:
			if ready < 0 and moves.froms.indexOf(to) == none: ready = i
		at = ready if ready >= 0 else 0
		from = moves.froms.remove(at)
		to = moves.tos.remove(at)
		if ready >= 0:
			g.irMovapd(to, from)
			continue
		# a cycle: the two registers swapped, so a move from to reads from instead
		g.irVexRR(0, 0, 0x57, to, to, from)   # vxorps to, to, from
		g.irVexRR(0, 0, 0x57, from, from, to)
		g.irVexRR(0, 0, 0x57, to, to, from)
		for k in 0..moves.froms.len:
			if moves.froms[k] == to: moves.froms[k] = from
		if moves.tos.indexOf(from) is k and moves.froms[k] == from:
			moves.froms.remove(k)   # (now where it goes)
			moves.tos.remove(k)
