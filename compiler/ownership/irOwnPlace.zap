# The drops placed where a value dies: deaths, liveness and redundant drops (irOwn.zap).

# The deaths: an owner a local names (irOwn with a key), without a drop function and never set
# aside by a walk, whose memory nothing outside the function may point into, is dropped right
# after its last use on each path (Mojo's ASAP destruction), a use being an instruction that
# reads or writes through an address that may point into it (IrOrigins), its own drops and
# markers aside. A value no statement after the one that made it uses lives to its scope's end,
# as one with a drop function does (spec 4.1); a drop the lowering put where the value is gone on
# every path (moved, dropped already, never made) goes.
fn irPlaceDrops(mut g Gen, mut f IrFn, fnKey str):
	if not f.blocks.any(.insts.any(.op == irOwn and .key != "")): return
	order = f.irLayout()
	owners = f.irOwnersOf(order)
	origins = g.irOriginsOf(f)
	d = g.irDeathsOf(f, owners, origins)
	if d.owners.isEmpty: return
	nb = f.blocks.len
	# each block's uses: flat (instruction, candidate) pairs in order
	uses = []
	for b in 0..nb:
		uses.push(g.irBlockUses(f, b, d, owners, origins))
	words = (d.owners.len + 63) / 64
	liveIn, liveOut = f.irDeathLiveness(order, d, owners, uses, words)
	_ = liveIn
	entry = f.irOwnEntries(order, owners)
	ownerWords = (owners.vregs.len + 7) / 8
	preds i64[,] = []
	loop nb:
		preds.push([])
	for b in order:
		for s in f.irBlockSuccessors(b):
			preds[s].push(b)
	placed = 0
	for b in order:
		# the deaths in b, backward from its way out: (position, candidate)
		deaths = []
		live = liveOut[b].copy()
		insts = f.blocks[b].insts
		u = uses[b].len - 2
		k = insts.len - 1
		while k >= 0:
			inst = insts[k]
			if irIsMarker(inst.op) and d.irDeathCandidate(owners, inst.a) is ci:
				live[ci >> 6] &= ~(1 << (ci & 63))
			while u >= 0 and uses[b][u] == k:
				ci = uses[b][u + 1]
				if live[ci >> 6] & (1 << (ci & 63)) == 0:
					live[ci >> 6] |= 1 << (ci & 63)
					if not isTerminator(inst.op) and inst.line not in d.bornLines[ci]:
						deaths.push(k + 1 + insts.irCallOutsAt(k).len)   # (past a call's result)
						deaths.push(ci)
				u -= 2
			k -= 1
		# dead on entry here, living on along another way out of a block before
		for ci in 0..d.owners.len:
			if live[ci >> 6] & (1 << (ci & 63)) != 0: continue
			if preds[b].any(p:
				liveOut[p][ci >> 6] & (1 << (ci & 63)) != 0 or
					uses[p].irUsedByTerminator(f.blocks[p].insts, ci)
			):
				deaths.push(0)
				deaths.push(ci)
		if deaths.isEmpty: continue
		st = entry[b * ownerWords..(b + 1) * ownerWords].copy()
		placed += f.irDropAt(g, b, deaths, d, owners, st, fnKey)
	if placed > 0:
		f.irDropRedundant(owners, d)

# the owners whose deaths the check places
type IrDeaths:
	owners i64[]   # each candidate's owner
	of i64[]   # per owner: its candidate, or -1
	ofHolder i64[]   # per holder: the candidate whose slot it is, or -1
	bornLines i64[,]   # per candidate: the lines of the statements that make its values
	names str[]   # per candidate: its local's name

fn irDeathsOf(mut g Gen, f IrFn, owners IrOwners, mut origins IrOrigins):
	n = owners.vregs.len
	named = fill(n, "")
	aside = fill(n, false)
	lines i64[,] = []
	loop n:
		lines.push([])
	for b in f.blocks:
		for inst in b.insts:
			if not irIsMarker(inst.op): continue
			i = owners.irOwnerOf(inst.a) ?? continue
			if inst.op == irOwn and inst.key != "":
				named[i] = inst.key.copy()
			if inst.op == irOwn and inst.line not in lines[i]:
				lines[i].push(inst.line)
			if inst.op == irOwnEnd and inst.cond == ownSuspended or
				inst.op == irOwn and inst.cond == 1:
				aside[i] = true   # set aside by a walk, or kept by a loop: its drop is the lowering's
	# what the memory outside the function may point into
	outside i64[] = []
	for h in 0..origins.outside.len:
		if origins.outside[h]:
			outside.irSetJoin(origins.holds[h])
	at = 0
	while at < outside.len:
		h = outside[at]
		at += 1
		for x in origins.holds[h].copy():
			outside.irSetPut(x)
	d = IrDeaths(
		owners = [],
		of = fill(n, -1),
		ofHolder = fill(origins.outside.len, -1),
		bornLines = [],
		names = []
	)
	for i in 0..n:
		h = origins.holder[owners.vregs[i]]
		if named[i] == "" or aside[i] or h < 0 or h in outside or
			g.c.holdsDrop(TypeId(owners.types[i])):
			continue
		d.of[i] = d.owners.len
		d.ofHolder[h] = d.owners.len
		d.owners.push(i)
		d.bornLines.push(lines[i].copy())
		d.names.push(named[i].copy())
	d

# the candidate whose owner's slot is v, or none
fn irDeathCandidate(d IrDeaths, owners IrOwners, v i64) i64?:
	i = try owners.irOwnerOf(v)
	if d.of[i] < 0: return none
	d.of[i]

# Block b's uses of the candidates, as flat (instruction, candidate) pairs in order: what each
# instruction reads or writes through, but a marker, a candidate's drop of its own slot, and the
# zeroing of its slot that follows its drop.
fn irBlockUses(
	mut g Gen,
	f IrFn,
	b i64,
	d IrDeaths,
	owners IrOwners,
	mut origins IrOrigins
):
	insts = f.blocks[b].insts
	out = []
	zeroing = -1   # the candidate whose dropped slot is being zeroed
	for k, inst in insts:
		if irIsMarker(inst.op):
			if inst.op == irOwnEnd and zeroing >= 0:
				zeroing = -1
			if inst.op == irOwnEnd and inst.cond != ownDropped and
				d.irDeathCandidate(owners, inst.a) is ci:
				out.push(k)   # its value goes here: no drop before
				out.push(ci)
			continue
		if inst.op == irDrop and d.irDeathCandidate(owners, inst.a) is ci and
			g.irSameType(inst.ty, owners.types[d.owners[ci]]):
			zeroing = ci   # its own drop (not a field's at its start)
			continue
		if zeroing >= 0 and inst.op not in [irStore, irConst, irMemSet]:
			zeroing = -1
		seen i64[] = []
		for v in inst.irReads():
			origins.irReachOf(v)
			for h in origins.reach[v]:
				ci = d.ofHolder[h]
				if ci >= 0 and ci != zeroing and ci not in seen:
					seen.push(ci)
		seen.sort()
		for ci in seen:
			out.push(k)
			out.push(ci)
	out

# whether the terminator of a block (insts) uses candidate ci
fn irUsedByTerminator(uses i64[], insts IrInst[], ci i64):
	if insts.isEmpty or not isTerminator(insts[len - 1].op): return false
	last = insts.len - 1
	u = uses.len - 2
	while u >= 0 and uses[u] == last:
		if uses[u + 1] == ci: return true
		u -= 2
	false

# the candidates live into and out of each block, as bits (word ci >> 6, bit ci & 63): used ahead
# before any marker of theirs (a value begun or consumed there)
fn irDeathLiveness(
	f IrFn,
	order i64[],
	d IrDeaths,
	owners IrOwners,
	uses i64[,],
	words i64
):
	n = f.blocks.len
	gen = []
	kill = []
	for b in 0..n:
		gb = zeros(words)
		kb = zeros(words)
		insts = f.blocks[b].insts
		u = 0
		for k, inst in insts:
			while u < uses[b].len and uses[b][u] == k:
				ci = uses[b][u + 1]
				if kb[ci >> 6] & (1 << (ci & 63)) == 0:
					gb[ci >> 6] |= 1 << (ci & 63)
				u += 2
			if irIsMarker(inst.op) and d.irDeathCandidate(owners, inst.a) is ci:
				kb[ci >> 6] |= 1 << (ci & 63)
		gen.push(gb)
		kill.push(kb)
	liveIn = []
	liveOut = []
	loop n:
		liveIn.push(zeros(words))
		liveOut.push(zeros(words))
	changed = true
	while changed:
		changed = false
		oi = order.len - 1
		while oi >= 0:
			b = order[oi]
			for s in f.irBlockSuccessors(b):
				for w in 0..words:
					liveOut[b][w] |= liveIn[s][w]
			for w in 0..words:
				x = gen[b][w] | (liveOut[b][w] & ~kill[b][w])
				if x != liveIn[b][w]:
					liveIn[b][w] = x
					changed = true
			oi -= 1
	(liveIn, liveOut)

# The drops of block b's deaths (flat (position, candidate) pairs) put before the instructions at
# their positions, the last made first, each where its owner may own a value and its bytes are its
# own (not moved out as they are, not set aside); st the owners' states on entry. How many went in.
fn irDropAt(
	mut f IrFn,
	mut g Gen,
	b i64,
	deaths i64[],
	d IrDeaths,
	owners IrOwners,
	mut st u64[],
	fnKey str
):
	insts = f.blocks[b].insts.copy()
	out = []
	placed = 0
	for k in 0..=insts.len:
		here i64[] = []
		j = 0
		while j < deaths.len:
			if deaths[j] == k and d.owners[deaths[j + 1]] not in here:
				here.push(d.owners[deaths[j + 1]])
			j += 2
		here.sort()
		at = k if k < insts.len else k - 1 if k > 0 else -1
		line = insts[at].line if at >= 0 else 0
		col = insts[at].col if at >= 0 else 0
		i = here.len - 1
		while i >= 0:
			owner = here[i]
			s = st.irOwnGet(owner)
			if s & ownLive != 0 and s & (ownAsIs | ownSetAside) == 0:
				f.irDropTrio(g, out, owners.vregs[owner], owners.types[owner], line, col)
				st.irOwnSet(owner, u64(ownFreed))
				placed += 1
				if irDropsWord().on():
					g.irSay("irdrops: {fnKey}: {d.names[d.of[owner]]} dropped at line {line}")
			i -= 1
		if k < insts.len:
			inst = insts[k]
			if irIsMarker(inst.op) and owners.irOwnerOf(inst.a) is o:
				st.irOwnSet(o, inst.irOwnAfterMarker())
			out.push(inst.copy())
	f.blocks[b].insts = out
	placed

# the drop of the owner at slot, of type t: its value dropped, its bytes zeroed (a drop of them
# frees nothing), the owner owning nothing from there
fn irDropTrio(mut f IrFn, mut g Gen, mut out IrInst[], slot i64, t i64, line i64, col i64):
	zero = f.irVreg(irInt)
	out.push(IrInst(op = irConst, dst = zero, imm = 0, line, col))
	out.push(IrInst(op = irDrop, a = slot, ty = TypeId(t), line, col))
	size = g.sizeOf(TypeId(t)).alignUp(8)
	at = 0
	while at < size:
		out.push(IrInst(op = irStore, a = slot, c = zero, imm = at, line, col))
		at += 8
	out.push(IrInst(op = irOwnEnd, a = slot, cond = ownDropped, line, col))

# the drops of the candidates (an irDrop of the slot, its zeroing, irOwnEnd) where their owner is
# gone on every path taken out
fn irDropRedundant(mut f IrFn, owners IrOwners, d IrDeaths):
	order = f.irLayout()
	entry = f.irOwnEntries(order, owners)
	words = (owners.vregs.len + 7) / 8
	for b in order:
		st = entry[b * words..(b + 1) * words].copy()
		n = f.blocks[b].insts.len
		any = false
		k = 0
		while k < n:
			op = f.blocks[b].insts[k].op
			at = f.blocks[b].insts[k].a
			if op == irDrop and d.irDeathCandidate(owners, at) is ci:
				j = k + 1
				while j < n and f.blocks[b].insts[j].op in [irStore, irConst, irMemSet] and
					(f.blocks[b].insts[j].op == irConst or f.blocks[b].insts[j].a == at):
					j += 1
				ends = j < n and f.blocks[b].insts[j].op == irOwnEnd and
					f.blocks[b].insts[j].a == at and f.blocks[b].insts[j].cond == ownDropped
				s = st.irOwnGet(d.owners[ci])
				if ends and s & (ownLive | ownAsIs | ownSetAside) == 0:
					for x in k..=j:
						f.irTakeOut(b, x)
					any = true
					k = j + 1
					continue
			if irIsMarker(op) and owners.irOwnerOf(at) is o:
				st.irOwnSet(o, f.blocks[b].insts[k].irOwnAfterMarker())
			k += 1
		if any:
			f.irDropTakenOut(b)

# ---------- the program's check, right after lowering ----------
