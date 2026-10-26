# Scalars in vregs: a module variable's scalar (a number, a bool, a field of a module struct, a
# module list's header word), or a frame slot's, that a function only loads and stores at its
# address is kept in a vreg of its own between calls. A load reads the vreg once it holds the value (loaded
# or stored since the last call on every way here), a store sets the vreg; the vreg is stored back
# before a call, a return, and the end of a block a way goes on from to where it is not held. A
# store into a list's elements or through any other address cannot write a module scalar (the
# ownership rules), so only calls make the vregs stale. A scalar whose address is used otherwise
# (passed, copied, indexed), or read in overlapping parts, stays in memory. A frame slot's address
# may also be handed to a call, a drop or a copy of memory, which then act as a call does: the
# vregs stored back before it and read again after (a reference into the slot a call gives back
# is not read or written while the slot is: the borrow rules). A frame slot's scalar is held
# through a loop that calls too, read again at the end of each block of the loop's rounds that
# calls, unless the loop hands the slot to a call or makes the slot itself. On x64 a list's growth
# stores back and reads again only its own header and the module scalars (irSyncSet).

# a scalar: its place (irPlaceOf), its displacement and size, and how its loads extend it
type IrScalar:
	data i64
	disp i64
	size i64
	class i64
	uns bool
	vreg i64 = -1

# the place a vreg's only assignment takes the address of: a module variable's data offset, or
# -2 - v for the frame slot v; -1 for none
fn irPlaceOf(inst IrInst):
	if inst.op == irDataAddr: return inst.imm
	if inst.op == irFrameSlot: return -2 - inst.dst
	-1

# what acts as a call for a frame slot's scalars, handed the slot's address
irSlotSyncs = [irCall, irCallPtr, irDrop, irDeepCopy, irMemCopy, irMemCopyN, irMemSet]
# what names a frame slot and makes no code (the ownership's markers)
irSlotMarks = [irOwn, irOwnEnd, irNote]

# whether the scalars are stored back before inst and read again after it: a call, or an
# instruction handed a frame slot's address
fn irSyncs(sc IrScalars, inst IrInst):
	irCalls(inst.op) or inst.op in irSlotSyncs and inst.irReads().any(sc.dataAt[it] < -1)

# the scalars a sync (irSyncs) stores back and reads again, a bit each in words: on x64 a list's
# growth handed a frame slot rewrites only that slot's header, so the module scalars and that
# slot's alone; any other, all of them. (On AArch64 a vreg across a call has no register calls lose
# kept in its slot around them, irRegs.zap: read again after the growth, the other headers take
# such registers, which havlak's predecessors needs for its twelve.)
fn irSyncSet(sc IrScalars, inst IrInst, words i64):
	list = -1 if sc.arm or inst.op != irCall or inst.key not in irGrowKeys or inst.args.isEmpty
		else inst.args[0]
	if list < 0 or list >= sc.dataAt.len or sc.dataAt[list] >= -1: return fill(words, -1)
	set = zeros(words)
	for k, s in sc.of:
		if s.data >= 0 or s.data == sc.dataAt[list]:
			set[k >> 6] |= 1 << (k & 63)
	set

# whether any was kept
fn irPlaceScalars(mut f IrFn, arm bool):
	nv = f.classes.len
	dataAt = fill(nv, -1)   # the place a vreg's only assignment takes the address of
	defs = zeros(nv)
	for b in f.blocks:
		for inst in b.insts:
			if inst.dst >= 0:
				defs[inst.dst] += 1
				dataAt[inst.dst] = inst.irPlaceOf()
	any = false
	for v in 0..nv:
		if defs[v] != 1:
			dataAt[v] = -1
		any = any or dataAt[v] != -1
	if not any: return false
	scalars IrScalar[] = []
	refused {i64: bool} = {}   # the data offsets whose address is used otherwise
	keys {i64: i64} = {}   # irScalarKey to the scalar's index
	for b in f.blocks:
		for inst in b.insts:
			base = f.irScalarBase(inst, dataAt)
			for v in inst.irReads():
				if dataAt[v] != -1 and not (base != -1 and v == inst.a and inst.c != v) and
					not (dataAt[v] < -1 and (inst.op in irSlotSyncs or inst.op in irSlotMarks)):
					refused[dataAt[v]] = true
			if base != -1:
				class = f.irScalarClass(inst)
				fits = (class == irInt and inst.size in [1, 2, 4, 8] or class == irFloat and
						inst.size == 8) and fitsImm32(inst.imm)
				if not fits:
					refused[base] = true
				elif keys.get(irScalarKey(base, inst.imm)) is k:
					alias s = scalars[k]
					if s.size != inst.size or s.class != class or
						inst.op == irLoad and inst.size < 8 and s.uns != inst.uns:
						refused[base] = true
				else:
					keys[irScalarKey(base, inst.imm)] = scalars.len
					scalars.push(
						IrScalar(
							data = base,
							disp = inst.imm,
							size = inst.size,
							class,
							uns = inst.uns
						)
					)
	# overlapping parts of one variable: it stays in memory
	parts {i64: i64[]} = {}   # each variable's scalars
	for k, s in scalars:
		if s.data not in parts: parts[s.data] = []
		parts[s.data].push(k)
	for data, ks in parts:
		order = ks.sortedBy(scalars[it].disp)
		reach = scalars[order[0]].disp   # where the parts before end
		for k in order:
			if scalars[k].disp < reach: refused[data] = true
			reach = reach.max(scalars[k].disp + scalars[k].size)
	scalars = scalars.filter(.data not in refused)
	# a frame slot's only where a loop that never calls reaches it (elsewhere memory serves)
	empty = f.irEmptySlots()
	calm = f.irCalmUses(
		IrScalars(
			of = scalars.copy(),
			keys = irScalarKeys(scalars),
			dataAt = dataAt.copy(),
			empty = empty.copy(),
			arm
		)
	)
	scalars = (0..scalars.len).filter(scalars[it].data >= 0 or calm[it]).map(scalars[it])
	if scalars.isEmpty: return false
	for mut scalar in scalars:
		scalar.vreg = f.irVreg(scalar.class)
	sc = IrScalars(of = scalars, keys = irScalarKeys(scalars), dataAt, empty, arm)
	f.irPreload(sc)
	f.irKeepScalars(sc)
	true

# each scalar's index by its place (irScalarKey)
fn irScalarKeys(scalars IrScalar[]):
	keys {i64: i64} = {}
	for k, scalar in scalars:
		keys[irScalarKey(scalar.data, scalar.disp)] = k
	keys

# whether loop l never calls, and the block before it is known
fn irCalm(f IrFn, sc IrScalars, l IrLoop):
	l.pre >= 0 and not l.blocks.any(f.blocks[it].insts.any(sc.irSyncs(it)))

# the scalars loop l holds in their vregs from the block before it: those it reads or writes; a
# module scalar only when the loop never calls, a frame slot's when nothing in the loop's rounds is
# handed its address (a call that may drop or move it): a block of the loop that calls reads them
# again at its end (irReloads)
fn irLoopHolds(f IrFn, sc IrScalars, l IrLoop) bool[]:
	if l.pre < 0: return zeros(sc.of.len)
	inside = f.irSlotsMadeIn(l.blocks)
	usedIn = f.irUsedIn(sc, l.blocks)
	used = (0..sc.of.len).map(
		usedIn[it] and -2 - sc.of[it].data not in inside and
			irScalarKey(l.pre, sc.of[it].data) not in sc.empty
	)
	if f.irCalm(sc, l): return used
	handed = f.irLoopHanded(sc, l)
	(0..sc.of.len).map(used[it] and sc.of[it].data < -1 and sc.of[it].data not in handed)

# the frame slots that own nothing for certain on entry to a loop, by irScalarKey(the block before
# the loop, the slot's place): moved out or dropped on every way there, so the ownership check
# refuses any read of them, and a vreg holding one through the loop would be read again
fn irEmptySlots(f IrFn):
	empty {i64: bool} = {}
	if not f.blocks.any(.insts.any(.op == irOwn)): return empty
	order = f.irLayout()
	o = f.irOwnersOf(order)
	entry = f.irOwnEntries(order, o)
	words = (o.vregs.len + 7) / 8
	for l in f.loops:
		if l.pre < 0: continue
		st = entry[l.pre * words..(l.pre + 1) * words].copy()
		for inst in f.blocks[l.pre].insts:
			if irIsMarker(inst.op) and o.irOwnerOf(inst.a) is i:
				st.irOwnSet(i, inst.irOwnAfterMarker())
		for i, v in o.vregs:
			was = st.irOwnGet(i)
			if was & (ownLive | ownSetAside) == 0 and was & ownEnded != 0:
				empty[irScalarKey(l.pre, -2 - v)] = true
	empty

# the frame slots made in the blocks (a slot of a round's own: no value to hold from before it)
fn irSlotsMadeIn(f IrFn, blocks i64[]):
	made {i64: bool} = {}
	for b in blocks:
		for inst in f.blocks[b].insts:
			if inst.op == irFrameSlot and inst.dst >= 0:
				made[inst.dst] = true
	made

# the blocks of loop l that go on to another round: those that reach its top inside the loop (none
# when the top is not marked), found by a walk back from the tops over the loop's own ways
fn irLoopCycle(f IrFn, l IrLoop):
	inside {i64: i64} = {}   # each block of the loop, by its place in l.blocks
	for i, b in l.blocks:
		inside[b] = i
	preds i64[,] = []
	loop l.blocks.len:
		preds.push([])
	for i, b in l.blocks:
		for k in 0..f.irNextCount(b):
			if inside.get(f.irNextAt(b, k)) is s: preds[s].push(i)
	back = fill(l.blocks.len, false)
	todo = (0..l.blocks.len).filter(f.blocks[l.blocks[it]].loopTop)
	for i in todo:
		back[i] = true
	while todo.pop() is i:
		for p in preds[i]:
			if not back[p]:
				back[p] = true
				todo.push(p)
	(0..l.blocks.len).filter(back[it]).map(l.blocks[it])

# the frame slots an instruction of loop l that acts as a call is handed, except those only
# dropped on a way out of the loop or only grown (irGrowKeys: the list stays alive in its slot): a
# slot a call or a move gives a value to or takes it from in the loop is not alive all through it
fn irLoopHanded(f IrFn, sc IrScalars, l IrLoop):
	handed {i64: bool} = {}
	round {i64: bool} = {}
	for b in f.irLoopCycle(l):
		round[b] = true
	for b in l.blocks:
		for inst in f.blocks[b].insts:
			if not sc.irSyncs(inst) or inst.op == irDrop and b not in round or
				inst.op == irCall and inst.key in irGrowKeys:
				continue
			for v in inst.irReads():
				if sc.dataAt[v] < -1:
					handed[sc.dataAt[v]] = true
	handed

# each block's scalars (a bit each, in words) to read again at its end: those a loop holds, in a
# block of the loop's rounds that calls
fn irReloads(f IrFn, sc IrScalars, words i64):
	n = f.blocks.len
	reload = zeros(n * words)
	for l in f.loops:
		holds = f.irLoopHolds(sc, l)
		if not holds.any(it): continue
		for b in f.irLoopCycle(l):
			synced = f.irReloadsIn(sc, b, words)
			for k, h in holds:
				if h and sc.of[k].data < -1:
					reload[b * words + (k >> 6)] |= synced[k >> 6] & (1 << (k & 63))
	reload

# the scalars block b's syncs store back (irSyncSet) when it goes on (a return stores the scalars
# back and ends)
fn irReloadsIn(f IrFn, sc IrScalars, b i64, words i64):
	synced = zeros(words)
	insts = f.blocks[b].insts
	if insts.isEmpty or insts[len - 1].op == irRet: return synced
	for inst in insts:
		if sc.irSyncs(inst):
			for w, bits in sc.irSyncSet(inst, words):
				synced[w] |= bits
	synced

# which scalars the blocks read or write
fn irUsedIn(f IrFn, sc IrScalars, blocks i64[]):
	used = fill(sc.of.len, false)
	for b in blocks:
		for inst in f.blocks[b].insts:
			k = sc.irScalarAt(f, inst)
			if k >= 0:
				used[k] = true
	used

# which scalars a loop that never calls reads or writes
fn irCalmUses(f IrFn, sc IrScalars):
	used = fill(sc.of.len, false)
	for l in f.loops:
		for k, u in f.irLoopHolds(sc, l):
			used[k] = used[k] or u
	used

# each scalar a loop that never calls reads or writes, loaded at the end of the block before it:
# held from there, the loop reads and writes its vreg alone (a list's length a loop pushes to)
fn irPreload(mut f IrFn, mut sc IrScalars):
	for l in f.loops.copy():
		used = f.irLoopHolds(sc, l)
		insts = move f.blocks[l.pre].insts
		out = insts[..len - 1].copy()
		at = insts[len - 1].copy()
		for k, s in sc.of:
			if not used[k]: continue
			addr = -2 - s.data   # a frame slot's own vreg
			if s.data >= 0:
				addr = f.irVreg(irInt)
				out.push(
					IrInst(op = irDataAddr, dst = addr, imm = s.data, line = at.line, col = at.col)
				)
			dst = f.irVreg(s.class)
			while sc.dataAt.len < f.classes.len:
				sc.dataAt.push(-1)   # (the new vregs')
			if s.data >= 0:
				sc.dataAt[addr] = s.data   # a load the scalar's
			out.push(
				IrInst(
					op = irLoad,
					dst,
					a = addr,
					imm = s.disp,
					size = s.size,
					uns = s.uns,
					line = at.line,
					col = at.col
				)
			)
		out.push(at)
		f.blocks[l.pre].insts = move out

# the scalars kept, found by their place (irScalarKey), and each vreg's data offset (irDataAddr)
type IrScalars:
	of IrScalar[]
	keys {i64: i64}
	dataAt i64[]
	empty {i64: bool}   # irEmptySlots
	arm bool   # for AArch64 (irSyncSet)

# a scalar's place as one number: its variable's data offset, then its displacement (32 bits)
fn irScalarKey(data i64, disp i64):
	data << 32 | (disp & 0xFFFF_FFFF)

# the place (irPlaceOf) inst loads, stores or updates as a scalar (at its address plus a
# displacement, no index), -1 for any other instruction
fn irScalarBase(f IrFn, inst IrInst, dataAt i64[]):
	if not (inst.op in [irLoad, irStore, irUpdate]) or inst.b >= 0 or inst.frame or inst.a < 0:
		return -1
	dataAt[inst.a]

# the class of the scalar an access moves: its result's, its stored value's
fn irScalarClass(f IrFn, inst IrInst):
	f.classes[inst.dst] if inst.op == irLoad else f.classes[inst.c] if inst.op == irStore else irInt

# the scalar inst accesses, -1 for none
fn irScalarAt(sc IrScalars, f IrFn, inst IrInst):
	base = f.irScalarBase(inst, sc.dataAt)
	if base == -1: return -1
	sc.keys.get(irScalarKey(base, inst.imm)) ?? -1

# Where each scalar is held (a bit per scalar): on entry to each block on every way there (from
# none at the function's entry), and where it was stored but not stored back on some way. Then
# each block rewritten (irScalarBlock).
fn irKeepScalars(mut f IrFn, sc IrScalars):
	n = f.blocks.len
	words = (sc.of.len + 63) / 64
	order = f.irLayout()
	all = -1
	# each block's effect: the scalars accessed after the last call that syncs them (or in all of
	# it), those some call of it syncs, the scalars stored after the last call that syncs them
	after = zeros(n * words)
	stored = zeros(n * words)
	cut = zeros(n * words)
	for b in 0..n:
		for inst in f.blocks[b].insts:
			if sc.irSyncs(inst):
				for w, bits in sc.irSyncSet(inst, words):
					cut[b * words + w] |= bits
					after[b * words + w] &= ~bits
					stored[b * words + w] &= ~bits
			k = sc.irScalarAt(f, inst)
			if k >= 0:
				after[b * words + (k >> 6)] |= 1 << (k & 63)
				if inst.op != irLoad:
					stored[b * words + (k >> 6)] |= 1 << (k & 63)
	reload = f.irReloads(sc, words)
	for i in 0..n * words:
		after[i] |= reload[i]
	reached = fill(n, false)
	for b in order:
		reached[b] = true
	preds i64[,] = []
	loop n:
		preds.push([])
	for b in order:   # (a block nothing reaches holds nothing and must not stop the rest)
		for i in 0..f.irNextCount(b):
			preds[f.irNextAt(b, i)].push(b)
	held = fill(n * words, all)   # on entry
	for w in 0..words:
		held[w] = 0
	for b in 0..n:
		if not reached[b]:
			for w in 0..words:
				held[b * words + w] = 0
	changed = true
	while changed:
		changed = false
		for b in order:
			if b == 0: continue
			for w in 0..words:
				x = all
				for p in preds[b]:
					x &= held[p * words + w] & ~cut[p * words + w] | after[p * words + w]
				if preds[b].isEmpty:
					x = 0
				if x != held[b * words + w]:
					held[b * words + w] = x
					changed = true
	# the scalars stored and not stored back on some way into each block
	dirty = zeros(n * words)
	changed = true
	while changed:
		changed = false
		for b in order:
			for w in 0..words:
				out = dirty[b * words + w] & ~cut[b * words + w] | stored[b * words + w]
				out &= f.irHeldAfter(b, held, words, w)
				for i in 0..f.irNextCount(b):
					s = f.irNextAt(b, i)
					if dirty[s * words + w] | out != dirty[s * words + w]:
						dirty[s * words + w] |= out
						changed = true
	for b in 0..n:
		f.irScalarBlock(b, sc, held, dirty, reload, words)

# the scalars held on entry to every block b goes on to: those stored back at its end are the rest
fn irHeldAfter(f IrFn, b i64, held i64[], words i64, w i64):
	x = -1
	for i in 0..f.irNextCount(b):
		x &= held[f.irNextAt(b, i) * words + w]
	0 if f.irNextCount(b) == 0 else x

# block b with its scalars in their vregs: a load from the vreg once held (else loaded into it),
# a store into the vreg, the vregs stored back before a call or a return, and at the end those a
# block it goes on to does not hold
fn irScalarBlock(
	mut f IrFn,
	b i64,
	sc IrScalars,
	held i64[],
	dirty i64[],
	reload i64[],
	words i64
):
	h = held[b * words..(b + 1) * words].copy()
	d = dirty[b * words..(b + 1) * words].copy()
	next = (0..words).map(f.irHeldAfter(b, held, words, it))   # read before the block is taken apart
	insts = move f.blocks[b].insts
	out = []
	for inst in insts:
		k = sc.irScalarAt(f, inst)
		if k < 0:
			if sc.irSyncs(inst) or inst.op == irRet:
				set = fill(words, -1) if inst.op == irRet else sc.irSyncSet(inst, words)
				f.irStoreBack(out, sc, (0..words).map(d[it] & set[it]), words, inst)
				for i in 0..words:
					d[i] &= ~set[i]
					h[i] &= ~set[i]
			elif isTerminator(inst.op):
				f.irStoreBackAt(out, sc, d, next, words, inst)
				f.irReloadAt(out, sc, h, reload[b * words..(b + 1) * words], inst)
			out.push(inst.copy())
			continue
		s = sc.of[k]
		bit = 1 << (k & 63)
		w = k >> 6
		line = inst.line
		col = inst.col
		if inst.op != irStore and (h[w] & bit) == 0:
			out.push(
				IrInst(
					op = irLoad,
					dst = s.vreg,
					a = inst.a,
					imm = inst.imm,
					size = s.size,
					uns = s.uns,
					line,
					col
				)
			)
			h[w] |= bit
		if inst.op == irLoad:
			out.push(IrInst(op = irCopy, dst = inst.dst, a = s.vreg, line, col))
		elif inst.op == irUpdate:
			out.push(IrInst(op = inst.cond, dst = s.vreg, a = s.vreg, b = inst.c, line, col))
			d[w] |= bit
		else:
			if s.class == irInt and s.size < 8:
				out.push(
					IrInst(
						op = irTrunc,
						dst = s.vreg,
						a = inst.c,
						imm = 8 * s.size,
						uns = s.uns,
						line,
						col
					)
				)
			else:
				out.push(IrInst(op = irCopy, dst = s.vreg, a = inst.c, line, col))
			h[w] |= bit
			d[w] |= bit
	if out.isEmpty or not isTerminator(out[len - 1].op):
		f.irStoreBackAt(out, sc, d, next, words, IrInst(op = irJmp))
		f.irReloadAt(out, sc, h, reload[b * words..(b + 1) * words], IrInst(op = irJmp))
	f.blocks[b].insts = move out

# the scalars of the set not held (h) read into their vregs (before at, its terminator)
fn irReloadAt(mut f IrFn, mut out IrInst[], sc IrScalars, h i64[], set i64[], at IrInst):
	for w in 0..set.len:
		bits = u64(set[w] & ~h[w])
		while bits != 0:
			k = w * 64 + bits.trailingZeros()
			bits &= bits - 1
			s = sc.of[k]
			out.push(
				IrInst(
					op = irLoad,
					dst = s.vreg,
					a = -2 - s.data,
					imm = s.disp,
					size = s.size,
					uns = s.uns,
					line = at.line,
					col = at.col
				)
			)

# the dirty scalars the blocks a block goes on to do not all hold (next) stored back (before at,
# its terminator)
fn irStoreBackAt(
	mut f IrFn,
	mut out IrInst[],
	sc IrScalars,
	d i64[],
	next i64[],
	words i64,
	at IrInst
):
	back = (0..words).map(d[it] & ~next[it])
	f.irStoreBack(out, sc, back, words, at)

# the scalars of the set stored from their vregs to their places
fn irStoreBack(mut f IrFn, mut out IrInst[], sc IrScalars, set i64[], words i64, at IrInst):
	for w in 0..words:
		bits = u64(set[w])
		while bits != 0:
			k = w * 64 + bits.trailingZeros()
			bits &= bits - 1
			s = sc.of[k]
			addr = -2 - s.data   # a frame slot's own vreg
			if s.data >= 0:
				addr = f.irVreg(irInt)
				out.push(
					IrInst(op = irDataAddr, dst = addr, imm = s.data, line = at.line, col = at.col)
				)
			out.push(
				IrInst(
					op = irStore,
					a = addr,
					c = s.vreg,
					imm = s.disp,
					size = s.size,
					header = true,
					line = at.line,
					col = at.col
				)
			)
