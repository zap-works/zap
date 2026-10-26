# The optimizer's small frame slots (irOpt.zap): a struct made in the frame only to be copied
# whole to another address (a list's new element) is stored there directly, and one copied into
# the frame only to be read is read in registers.

# What each frame slot's instructions do with it: stores at a constant offset, loads from one, a
# copy of it whole to another address and one from another address into it whole (the sites, block
# << 32 | index; -1 none, -2 more than one); a slot read otherwise is mixed.
type IrSlotUses:
	size i64[]   # each frame slot's bytes, -1 for another vreg
	stores i64[,]
	loads i64[,]
	copyOut i64[]
	copyIn i64[]
	mixed bool[]

fn irSlotUses(f IrFn):
	nv = f.classes.len
	u = IrSlotUses(
		size = fill(nv, -1),
		stores = [],
		loads = [],
		copyOut = fill(nv, -1),
		copyIn = fill(nv, -1),
		mixed = zeros(nv)
	)
	loop nv:
		u.stores.push([])
		u.loads.push([])
	for b in f.blocks:
		for inst in b.insts:
			if inst.op == irFrameSlot and inst.dst >= 0: u.size[inst.dst] = inst.imm
	for bi, block in f.blocks:
		for k, inst in block.insts:
			site = (bi << 32) | k
			role = irSlotRole(inst, u.size)
			if role < 0:
				pass
			elif inst.op == irStore:
				u.stores[role].push(site)
			elif inst.op == irLoad:
				u.loads[role].push(site)
			elif inst.b == role:
				u.copyOut[role] = site if u.copyOut[role] == -1 else -2
			else:
				u.copyIn[role] = site if u.copyIn[role] == -1 else -2
			for v in inst.irReads():
				if v != role and u.size[v] >= 0: u.mixed[v] = true
	u

# the slot an instruction stores into or loads from (at a constant offset, within it) or copies
# whole (cond 0: the source keeps its bytes) from or to another address, else -1
fn irSlotRole(inst IrInst, size i64[]):
	if (inst.op == irStore or inst.op == irLoad) and inst.a >= 0 and size[inst.a] >= 0 and
		inst.b < 0 and inst.c != inst.a and inst.imm >= 0 and inst.imm + inst.size <= size[inst.a]:
		return inst.a
	if inst.op != irMemCopy or inst.cond != 0 or inst.a == inst.b: return -1
	if inst.b >= 0 and size[inst.b] >= 0 and inst.imm == size[inst.b]: return inst.b
	if inst.a >= 0 and size[inst.a] >= 0 and inst.imm == size[inst.a]: return inst.a
	-1

# A frame slot filled by stores that cover it and read once, whole, by a copy: the copy becomes
# the stores at the copy's address (one store when they are constants of 8 bytes or fewer), so the
# slot's stores go (irDeadSlots, after) and no narrow stores are read back as one wider load,
# which the processor cannot forward. Each store dominates the copy and its value is not assigned
# again on a way from it to the copy. A slot filled once by a copy and only loaded from: each word
# is loaded where the copy was, from the copy's source, into a vreg the loads read (a list's
# element taken apart in registers). The slot then goes.
fn irSlotWords(mut f IrFn):
	u = f.irSlotUses()
	nv = f.classes.len
	if not (0..nv).any(not u.mixed[it] and (u.copyOut[it] >= 0 or u.copyIn[it] >= 0)): return
	order = f.irLayout()
	dom = f.irDomTree(order)
	consts = f.irFacts().consts
	rewrites = []
	for s in 0..nv:
		if u.mixed[s] or not u.loads[s].isEmpty and not u.stores[s].isEmpty: continue
		if u.copyOut[s] >= 0 and u.copyIn[s] == -1 and u.loads[s].isEmpty:
			if f.irSlotFilling(dom, u.stores[s], u.copyOut[s], u.size[s]) is filling:
				rewrites.push(
					IrSlotCopy(
						site = u.copyOut[s],
						insts = f.irStoresAtCopy(filling, u.copyOut[s], consts)
					)
				)
		elif u.copyIn[s] >= 0 and u.copyOut[s] == -1 and u.stores[s].isEmpty and
			u.loads[s].len <= 8 and u.loads[s].all(f.irSiteDominated(dom, u.copyIn[s], it)):
			rewrites.extend(f.irLoadsAtCopy(u.loads[s], u.copyIn[s]))
	if rewrites.isEmpty: return
	for r in rewrites.sortedBy(-.site):   # the last first: the sites before it stay where they are
		b = r.site >> 32
		k = r.site & 0xFFFF_FFFF
		insts = []
		for i in 0..f.blocks[b].insts.len:
			if i == k:
				insts.extend(r.insts.copy())
			else:
				insts.push(f.blocks[b].insts[i].copy())
		f.blocks[b].insts = move insts

# whether the instruction at site `at` runs before the one at `site` on every way there
fn irSiteDominated(f IrFn, dom IrDom, at i64, site i64):
	ab = at >> 32
	sb = site >> 32
	(at & 0xFFFF_FFFF) < (site & 0xFFFF_FFFF) if ab == sb else dom.irDominates(ab, sb)

# the copy into a slot replaced by loads of the words its loads read, from the copy's source, and
# each load by a copy of its word
fn irLoadsAtCopy(mut f IrFn, loads i64[], copy i64):
	cp = f.blocks[copy >> 32].insts[copy & 0xFFFF_FFFF].copy()
	words IrInst[] = []
	out = []
	for site in loads:
		ld = f.blocks[site >> 32].insts[site & 0xFFFF_FFFF].copy()
		w = words.findIndex(.imm == ld.imm and .size == ld.size and .uns == ld.uns and
				f.classes[it.dst] == f.classes[ld.dst]) ?? -1
		if w < 0:
			words.push(IrInst(
				op = irLoad,
				dst = f.irVreg(f.classes[ld.dst]),
				a = cp.b,
				imm = ld.imm,
				size = ld.size,
				uns = ld.uns,
				line = cp.line,
				col = cp.col
			))
			w = words.len - 1
		out.push(
			IrSlotCopy(
				site,
				insts = [
					IrInst(
						op = irCopy,
						dst = ld.dst,
						a = words[w].dst,
						line = ld.line,
						col = ld.col
					)
				]
			)
		)
	out.push(IrSlotCopy(site = copy, insts = words))
	out

# an instruction of a slot (its site: block << 32 | index) and the instructions that replace it
type IrSlotCopy:
	site i64
	insts IrInst[]

# the stores whose bytes the copy reads (one a later store of its block covers is not one), or
# none when they do not cover the slot or one does not dominate the copy with its value held to it
fn irSlotFilling(f IrFn, dom IrDom, sites i64[], copy i64, size i64) i64[]?:
	if sites.isEmpty or sites.len > 8: return none
	owner = fill(size, -1)   # the store that wrote each byte last
	for site in sites.sortedBy(it):
		st = f.blocks[site >> 32].insts[site & 0xFFFF_FFFF]
		for i in st.imm..st.imm + st.size:
			if owner[i] >= 0 and owner[i] >> 32 != site >> 32: return none
			owner[i] = site
	if owner.any(it < 0): return none
	filling = []
	for site in sites:
		st = f.blocks[site >> 32].insts[site & 0xFFFF_FFFF]
		owned = (st.imm..st.imm + st.size).count(owner[it] == site)
		if owned == 0: continue
		if owned < st.size or not f.irHeldTo(dom, site, copy, st.c): return none
		filling.push(site)
	filling

# whether vreg v keeps its value from the instruction at site `from` to the one at `to`: from's
# block dominates to's and no way between assigns v
fn irHeldTo(f IrFn, dom IrDom, from i64, to i64, v i64):
	fb = from >> 32
	fk = from & 0xFFFF_FFFF
	tb = to >> 32
	tk = to & 0xFFFF_FFFF
	if fb == tb: return fk < tk and not f.irAssignsIn(tb, fk + 1, tk, v)
	if not dom.irDominates(fb, tb) or f.irAssignsIn(fb, fk + 1, f.blocks[fb].insts.len, v):
		return false
	between = f.irReachedAvoiding(f.irBlockSuccessors(fb), fb)
	leading = f.irLeadingAvoiding(tb, fb)   # (a block past from's that never reaches to's is no way between)
	for b in 0..f.blocks.len:
		if between[b] and leading[b] and b != tb and f.irAssignsIn(b, 0, f.blocks[b].insts.len, v):
			return false
	# the copy's block run again before the store: all of it lies between
	again = f.irReachedAvoiding(f.irBlockSuccessors(tb), fb)[tb]
	not f.irAssignsIn(tb, 0, f.blocks[tb].insts.len if again else tk, v)

# whether instructions from..to of block b assign v
fn irAssignsIn(f IrFn, b i64, from i64, to i64, v i64):
	(from..to).any(f.blocks[b].insts[it].dst == v)

# the blocks from which block target is reached without passing block avoid
fn irLeadingAvoiding(f IrFn, target i64, avoid i64):
	preds i64[,] = []
	loop f.blocks.len:
		preds.push([])
	for b in 0..f.blocks.len:
		for t in f.irBlockSuccessors(b):
			preds[t].push(b)
	seen = fill(f.blocks.len, false)
	work = [target]
	while not work.isEmpty:
		b = work.pop() ?? break
		for p in preds[b]:
			if p != avoid and not seen[p]:
				seen[p] = true
				work.push(p)
	seen

# the blocks reached from starts without passing block avoid
fn irReachedAvoiding(f IrFn, starts i64[], avoid i64):
	seen = fill(f.blocks.len, false)
	work = []
	for s in starts:
		if s != avoid and not seen[s]:
			seen[s] = true
			work.push(s)
	while not work.isEmpty:
		b = work.pop() ?? break
		for s in f.irBlockSuccessors(b):
			if s != avoid and not seen[s]:
				seen[s] = true
				work.push(s)
	seen

# the stores at the copy's address that replace the copy at site `copy` (constants joined only
# when integers: a float stored in 4 bytes is the f64 of its value until the store narrows it)
fn irStoresAtCopy(mut f IrFn, sites i64[], copy i64, consts i64?[]):
	cp = f.blocks[copy >> 32].insts[copy & 0xFFFF_FFFF].copy()
	words = sites.map(f.blocks[it >> 32].insts[it & 0xFFFF_FFFF].copy()).sortedBy(.imm)
	line = cp.line
	col = cp.col
	if cp.imm <= 8 and (cp.imm & (cp.imm - 1)) == 0 and
		words.all(consts[.c] != none and f.classes[.c] == irInt):
		joined = 0
		for w in words:
			bits = (consts[w.c] ?? 0) & (-1 if w.size == 8 else (1 << (w.size * 8)) - 1)
			joined |= bits << (w.imm * 8)
		k = f.irVreg(irInt)
		return [
			IrInst(op = irConst, dst = k, imm = joined, line, col),
			IrInst(op = irStore, a = cp.a, c = k, size = cp.imm, line, col)
		]
	words.map(IrInst(op = irStore, a = cp.a, c = .c, imm = .imm, size = .size, line, col))
