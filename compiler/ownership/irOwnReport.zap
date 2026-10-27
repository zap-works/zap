# The uses of a value after it is taken or moved (irOwn.zap).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# the errors the program's check reported: the build fails once every function went through
mut irOwnErrors = 0
mut irOwnSaid {str: bool} = {}   # each error once (a body inlined into several functions)

fn irOwnError(mut g Gen, file str, line i64, col i64, msg str):
	g.irOwnPending.push(IrOwnPending(file = file.copy(), line, col, msg = msg.copy()))

# an error at inst of the function of file: none for a body of another file inlined there, whose
# own lowering says it in its file
fn irOwnErrorAt(mut g Gen, file str, inst IrInst, col i64, msg str):
	if not inst.foreign:
		g.irOwnError(file, inst.line, col, msg)

# an error the check found in a function, said once the function is lowered for good (a decision
# it made, irOwnMarks, lowers it again)
type IrOwnPending:
	file str
	line i64
	col i64
	msg str

# the nodes marked (irApplyMarks), the traces kept printed, then the pending errors said, each once
fn irOwnSettle(mut g Gen):
	g.irApplyMarks()
	for line in g.irSaid:
		eprint(line)
	g.irSaid.clear()
	for p in g.irOwnPending:
		key = "{p.file}:{p.line}:{p.col}:{p.msg}"
		if key in irOwnSaid: continue
		irOwnSaid[key] = true
		errorAtFile(p.file, p.line, p.col, p.msg)
		irOwnErrors += 1
	g.irOwnPending.clear()

# The program's ownership checked on its lowered form (spec 4.1 to 4.4), the same states the
# verifier follows: where each local's value dies (irPlaceDrops), then each use of a local whose
# value may be gone there (irUsesAfterMove), an error at its line in file. The notes the lowering
# left for it are taken out.
fn irOwnProgram(mut g Gen, mut f IrFn, fnKey str, file str):
	if irLoweredWord().value() is which and which == "{fnKey}+notes":
		g.irSay("{fnKey} as lowered:")
		g.irSayForm(f)
	g.irDecideCopies(f, file)
	g.irPlaceDrops(f, fnKey)
	# (the form no longer changes: the checks after share its origins)
	moves = f.blocks.any(.insts.any(.op == irOwnEnd and .cond != ownDropped))
	takes = not fnKey.startsWith("rt__") and   # (the runtime manages its values by hand)
		f.blocks.any(.insts.any(.op == irMemCopy and .cond == 1 and .ty != none))
	origins = g.irOriginsOf(f) if moves or takes else IrOrigins()
	if moves: g.irUsesAfterMove(f, file, origins)
	g.irBorrowChecks(f, file)
	if takes: g.irUsesAfterTake(f, file, origins)
	f.irTakeNotesOut()

# A value moved out of a place that is no owner of its own (`saved = move h.idx`: a field, an
# element, a parameter's part) leaves the empty value there, its bytes zero. When the type holds a
# map or a box, zero is no value of it: a read of the place before it gets a value again is an
# error, and so is a return that leaves a part of the caller's value so.
fn irUsesAfterTake(mut g Gen, f IrFn, file str, mut origins IrOrigins):
	p = f.irPartsOf(origins)
	zero = fill(f.classes.len, false)
	for blk in f.blocks:
		for inst in blk.insts:
			if inst.op == irConst and inst.dst >= 0 and inst.imm == 0:
				zero[inst.dst] = true
	for b in 0..f.blocks.len:
		insts = f.blocks[b].insts
		for k, inst in insts:
			if inst.op != irMemCopy or inst.cond != 1: continue
			after = k + 1
			while after < insts.len and insts[after].op in [irConst, irStore, irMemSet] and
				(insts[after].op == irConst or insts[after].a == inst.b):
				after += 1   # (the source emptied)
			if after < insts.len and insts[after].op == irOwnEnd and insts[after].a == inst.b:
				continue   # an owner's whole value, consumed (irUsesAfterMove)
			t = inst.ty ?? continue
			hs = origins.points[inst.b]
			if hs.len != 1 or not g.irZeroIsNoValue(t): continue
			taken = g.irReachedBytes(p, inst, inst.b)
			match f.irTakenReached(g, origins, p, zero, hs[0], taken, b, k):
				(ub, uk):
					use = f.blocks[ub].insts[uk]
					if irLoweredWord().on():
						g.irSay("irown: taken at b{b}:{k} from v{inst.b} ({taken}), read at b{ub}:{uk} (op {use.op})")
						g.irSayForm(f)
					place = f.places.get(inst.b) ?? "the part"
					msg = compileError("TakenNotGivenBack", ["{place}", "{inst.line}"]) if use.op ==
						irRet
						else compileError(
							"UseAfterPartGiven",
							["{place}", "{place}", "{inst.line}"]
						)
					g.irOwnErrorAt(file, use, use.col, msg)
				none:
					pass

# whether zero bytes are no value of type t: it holds a map or a box in place
fn irZeroIsNoValue(mut g Gen, t TypeId) bool:
	k = g.tyK(t)
	if k == tMap or k == tBox: return true
	if k == tArray: return g.irZeroIsNoValue(innerOf(tys, t))
	if k != tStruct: return false
	sd = declOf(tys, t)
	(0..g.c.nodes[sd].kids(g.c.kidIds).len).any(g.irZeroIsNoValue(g.c.structFieldTypeAt(sd, it)))

# the first instruction after the take at k of block b that reads the taken bytes of holder h,
# or a return while h is the caller's memory; a path ends where the bytes get a value again
fn irTakenReached(
	f IrFn,
	mut g Gen,
	origins IrOrigins,
	p IrParts,
	zero bool[],
	h i64,
	taken (i64, i64),
	b i64,
	k i64
) (i64, i64)?:
	seen = fill(f.blocks.len, false)
	todo = [(b, k + 1)]
	while not todo.isEmpty:
		blk, from = todo.remove(0)
		insts = f.blocks[blk].insts
		j = from
		ends = false
		while j < insts.len:
			inst = insts[j]
			if irIsMarker(inst.op) and inst.a >= 0 and origins.holder[inst.a] == h:
				ends = true   # an owner's value made or gone: the taken part with it
				break
			if irIsMarker(inst.op) or inst.op in [irNote, irDrop, irCopy, irAdd, irSub, irSelect]:
				j += 1   # (the drop of the empty value frees nothing; an address made reaches nothing yet)
				continue
			writes = inst.op in [irStore, irMemSet, irMemCopy, irDeepCopy] and inst.a >= 0 and
				origins.points[inst.a].any(it == h) and
				irBytesMeet(g.irReachedBytes(p, inst, inst.a), taken)
			if writes and not (inst.op == irStore and inst.c >= 0 and zero[inst.c]) and
				not (inst.op == irMemSet and inst.b >= 0 and zero[inst.b]):
				ends = true
				break
			for v in inst.irReads():
				if writes and v == inst.a or
					(inst.op == irCall or inst.op == irCallPtr) and v == inst.c:
					continue   # (where it writes, a call's result too)
				if p.exact[v] >= 0 and origins.points[v].any(it == h) and
					irBytesMeet(g.irReachedBytes(p, inst, v), taken):
					return (blk, j)   # (a read of the whole holder, or at an offset not known, is not judged)
			j += 1
		if ends: continue
		for s in f.irBlockSuccessors(blk):
			if not seen[s]:
				seen[s] = true
				todo.push((s, 0))
	none

fn irTakeNotesOut(mut f IrFn):
	for b in 0..f.blocks.len:
		if not f.blocks[b].insts.any(.op == irNote): continue
		for k in 0..f.blocks[b].insts.len:
			if f.blocks[b].insts[k].op == irNote:
				f.irTakeOut(b, k)
		f.irDropTakenOut(b)

# A local read or changed where its value may be gone on some path there: moved, given away,
# returned or taken by a closure (a local's irOwnEnd other than a drop), an error naming it and
# the line its value went at: given away inside a loop whose next turn reads it, taken by a
# closure, moved by a written `move`, or given away.
fn irUsesAfterMove(mut g Gen, f IrFn, file str, mut origins IrOrigins):
	order = f.irLayout()
	owners = f.irOwnersOf(order)
	n = owners.vregs.len
	keys = fill(n, "")
	for b in f.blocks:
		for inst in b.insts:
			if inst.op == irOwn and inst.key() != "" and owners.irOwnerOf(inst.a) is i:
				keys[i] = inst.key().copy()
	ofHolder = fill(origins.outside.len, -1)
	for i in 0..n:
		h = origins.holder[owners.vregs[i]]
		if keys[i] != "" and h >= 0:
			ofHolder[h] = i
	entry = f.irOwnEntries(order, owners)
	words = (n + 7) / 8
	reported = fill(n, false)
	constant = f.irConstantVregs()
	for b in order:
		st = entry[b * words..(b + 1) * words].copy()
		zeroing = -1   # the local whose dropped slot is being zeroed
		insts = f.blocks[b].insts
		for k, inst in insts:
			if irIsMarker(inst.op):
				if owners.irOwnerOf(inst.a) is o:
					st.irOwnSet(o, inst.irOwnAfterMarker())
				if inst.op == irOwnEnd:
					zeroing = -1
				continue
			if inst.op == irDrop and inst.a >= 0 and origins.holder[inst.a] >= 0 and
				ofHolder[origins.holder[inst.a]] >= 0 and
				g.irSameType(inst.ty, owners.types[ofHolder[origins.holder[inst.a]]]):
				zeroing = ofHolder[origins.holder[inst.a]]
				continue
			if irRecyclesList(inst) and not inst.args().isEmpty and
				origins.holder[inst.args()[0]] >= 0 and
				ofHolder[origins.holder[inst.args()[0]]] >= 0:
				zeroing = ofHolder[origins.holder[inst.args()[0]]]   # a kept list's drop: its block back to the loop
				continue
			if zeroing >= 0 and inst.op not in [irStore, irConst, irMemSet]:
				zeroing = -1
			for v in inst.irReads():
				# (what points into the local itself; a value its bytes moved to may hold what
				# it borrowed: that value is not it)
				for h in origins.points[v]:
					i = ofHolder[h]
					if i < 0 or i == zeroing or reported[i] or st.irOwnGet(i) & ownMovedOut == 0:
						continue
					if inst.a == owners.vregs[i] and v == inst.a and
						inst.op in [irMemCopy, irDeepCopy] and inst.b != inst.a:
						continue   # a new value made in its slot (a choice's arm), owned again after
					if inst.a == owners.vregs[i] and (inst.op == irStore and constant[inst.c] or
							inst.op == irMemSet and constant[inst.b]):
						continue   # its slot emptied, its value gone
					reported[i] = true
					writes = inst.op in [irStore, irMemCopy, irMemCopyN, irMemSet, irUpdate] and
						v == inst.a
					g.irReportMoved(f, order, owners, i, keys[i], b, k, writes, file)

# the use at instruction k of block b of local i (named name), whose value may be gone there,
# reported with the line it went at (the nearest consumption on the way back): a consumption
# reached back across a loop's back edge is an earlier turn's
fn irReportMoved(
	mut g Gen,
	f IrFn,
	order i64[],
	owners IrOwners,
	i i64,
	name str,
	b i64,
	k i64,
	writes bool,
	file str
):
	use = f.blocks[b].insts[k]
	mb, mk, again = f.irConsumedBefore(order, owners, i, b, k)
	if irLoweredWord().on():
		g.irSay("irown: {name} used at b{b}:{k} (op {use.op}), gone at b{mb}:{mk}")
	if mb < 0: return
	m = f.blocks[mb].insts[mk]
	if m.imm != 1 and m.other >= 0 and m.cond != ownCaptured and
		owners.types[i] >= 0 and g.c.copiesFreely(TypeId(owners.types[i])) and
		nodes[m.other].kind == nIdent and nodes[m.other].text == name:
		# a shared value: the name that gave it copies it (one more owner), lowered again
		g.irMark(NodeId(m.other), flagAutoCopy)
		g.irOwnMarks.push(NodeId(m.other))
		return
	msg = compileError("ClosureTakesLoopValue", ["{name}"]) if m.cond == ownCaptured and again
		else compileError("UseAfterCapture", ["{name}", "{m.line}"]) if m.cond == ownCaptured
		else compileError("GivenAwayInLoop", ["{name}"]) if again
		else compileError("ChangeAfterMove", ["cannot change", "{name}", "{m.line}"]) if writes
		else compileError("UseAfterMove", ["{name}", "{m.line}"]) if m.imm == 1
		else compileError("UseAfterGiven", ["{name}", "{m.line}"])
	at = m if again and m.cond != ownCaptured else use
	site = f.irCallSiteOf(b, k) if at.foreign else -1   # read in another file's body inlined
	if site >= 0:
		g.irOwnErrorAt(file, f.blocks[b].insts[site], f.blocks[b].insts[site].col, msg)
	else:
		g.irOwnErrorAt(file, at, at.col, msg)

# the index of the nearest instruction before k of block b that is this file's (where a body of
# another file inlined at k was called), -1 for none
fn irCallSiteOf(f IrFn, b i64, k i64):
	j = k - 1
	while j >= 0 and (f.blocks[b].insts[j].foreign or f.blocks[b].insts[j].line <= 0):
		j -= 1
	j

# where owner i's value went on the way back from instruction k of block b: the block and index
# of the nearest consumption (an irOwnEnd other than a drop), (-1, -1) for none, and whether the
# way back to it crossed a back edge (a jump to a block laid out before, the loop's next turn)
fn irConsumedBefore(f IrFn, order i64[], owners IrOwners, i i64, b i64, k i64):
	n = f.blocks.len
	pos = fill(n, -1)
	for p, x in order:
		pos[x] = p
	preds i64[,] = []
	loop n:
		preds.push([])
	for x in order:
		for s in f.irBlockSuccessors(x):
			preds[s].push(x)
	seen = fill(2 * n, false)   # each block, before and after a back edge
	todo = [(b, k, false)]
	while not todo.isEmpty:
		blk, from, crossed = todo.remove(0)
		j = from - 1
		stops = false
		while j >= 0:
			inst = f.blocks[blk].insts[j]
			if irIsMarker(inst.op) and (owners.irOwnerOf(inst.a) ?? -1) == i:
				if inst.op == irOwnEnd and inst.cond != ownDropped: return (blk, j, crossed)
				stops = true
				break
			j -= 1
		if stops: continue
		for p in preds[blk]:
			back = crossed or pos[p] >= pos[blk]
			at = p + (n if back else 0)
			if not seen[at]:
				seen[at] = true
				todo.push((p, f.blocks[p].insts.len, back))
	(-1, -1, false)

# ---------- the copies the program did not write ----------

# Where each address vreg lies in its holder (IrOrigins): at an offset known from the slot's start
# (exact), or in the memory a field of it owns (the field's offset: part); -1 not known, -3 not
# yet assigned. Only addresses made by adding constants and reading a field's items are followed.
type IrParts:
	exact i64[]
	part i64[]

fn irPartsOf(f IrFn, origins IrOrigins):
	nv = f.classes.len
	p = IrParts(exact = fill(nv, -3), part = fill(nv, -3))
	value = zeros(nv)
	constant = f.irConstantVregs()
	for b in f.blocks:
		for inst in b.insts:
			if inst.op == irConst and inst.dst >= 0:
				value[inst.dst] = inst.imm
	for v in 0..nv:
		if origins.holder[v] >= 0:
			p.exact[v] = 0
			p.part[v] = -1
	changed = true
	while changed:
		changed = false
		for b in f.blocks:
			for inst in b.insts:
				d = inst.dst
				if d < 0 or origins.holder[d] >= 0 or inst.a < 0: continue
				a = inst.a
				e = -1
				q = -1
				if inst.op == irCopy:
					e = p.exact[a]
					q = p.part[a]
				elif inst.op == irAdd and inst.b >= 0 and constant[inst.b] and p.exact[a] >= 0:
					e = p.exact[a] + value[inst.b]
				elif inst.op == irAdd or inst.op == irSub:
					q = p.exact[a] if p.exact[a] >= 0 else p.part[a]
				elif inst.op == irLoad and f.classes[d] == irInt:
					q = p.exact[a] + inst.imm if p.exact[a] >= 0 else p.part[a]
				else:
					continue
				if p.irPartsMeet(d, e, q):
					changed = true
	p

# vreg d found at (e, q) once more: unknown where its assignments disagree; whether it changed
fn irPartsMeet(mut p IrParts, d i64, e i64, q i64):
	ne = e if p.exact[d] == -3 or p.exact[d] == e else -1
	nq = q if p.part[d] == -3 or p.part[d] == q else -1
	if ne == p.exact[d] and nq == p.part[d]: return false
	p.exact[d] = ne
	p.part[d] = nq
	true

# the bytes [from, to) of its holder an access through v at inst reaches: a known offset and the
# access's size, the field whose memory v is in, or the whole holder (0, -1)
fn irReachedBytes(mut g Gen, p IrParts, inst IrInst, v i64):
	if v >= 0 and p.exact[v] >= 0:
		at = p.exact[v] +
			(inst.imm if (inst.op == irLoad or inst.op == irStore) and v == inst.a else 0)
		size = -1
		if inst.op == irLoad or inst.op == irStore:
			size = inst.size
		elif inst.op == irMemCopy:
			size = inst.imm
		elif inst.op == irDrop or inst.op == irDeepCopy:
			if inst.ty is t:
				size = g.sizeOf(t)
		if size < 0: return (0, -1) if at == 0 else (at, at + 1)
		return (at, at + size.max(1))
	if v >= 0 and p.part[v] >= 0: return (p.part[v], p.part[v] + 1)
	(0, -1)

# whether what v addresses may be the place copy takes, by their texts when both are known (x.f
# and x.g are apart, x and x.f not)
fn irPlacesMeet(f IrFn, v i64, copy IrInst):
	taken = copy.key().split("\t").last ?? ""
	used = f.places.get(v) ?? return true
	if taken == "" or used == "": return true
	irPathsMeet(used, taken)

fn irPathsMeet(a str, b str) bool:
	if a.len > b.len: return irPathsMeet(b, a)
	b == a or (b.startsWith(a) and (b[a.len] == '.' or b[a.len] == '['))

fn irBytesMeet(a (i64, i64), b (i64, i64)):
	alo, ahi = a
	blo, bhi = b
	(ahi < 0 or blo < ahi) and (bhi < 0 or alo < bhi)

# whether the known bytes a hold all of the known bytes b
fn irBytesCover(a (i64, i64), b (i64, i64)):
	alo, ahi = a
	blo, bhi = b
	ahi >= 0 and bhi >= 0 and alo <= blo and bhi <= ahi
