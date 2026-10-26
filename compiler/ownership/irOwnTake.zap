# The copies the ownership pass decides to keep or take instead (irOwn.zap).

# The copies of values that own memory the program did not write (irDeepCopy, cond 1 to 4): a
# place given away (to a move parameter, a list, a field, the result), bound mut or taken apart,
# that this code does not own; and any copy of a value with a drop function. A local's or a temporary's part (a field, an element) that no later
# instruction reaches, on any path, is taken out of its place instead, the place left its type's
# empty value (spec 4.1: no copy is hidden); any other is an error at its line in file: the place
# belongs to someone else, or is read again (in a loop's next turn: it would be gone).
fn irDecideCopies(mut g Gen, mut f IrFn, file str):
	if not f.blocks.any(.insts.any(.op == irDeepCopy and g.irCopyDecided(it))): return
	order = f.irLayout()
	owners = f.irOwnersOf(order)
	origins = g.irOriginsOf(f)
	p = f.irPartsOf(origins)
	ownerOfHolder = fill(origins.outside.len, -1)
	for i in 0..owners.vregs.len:
		h = origins.holder[owners.vregs[i]]
		if h >= 0:
			ownerOfHolder[h] = i
	pos = fill(f.blocks.len, -1)
	for at, x in order:
		pos[x] = at
	takes = []   # (block, index) of each copy taken out of its place
	for b in order:
		insts = f.blocks[b].insts
		for k, inst in insts:
			if inst.op != irDeepCopy or inst.ty == none or not g.irCopyDecided(inst): continue
			if inst.cond == 5:
				takes.push(b)   # a capture of a lambda run once: its environment's to give
				takes.push(k)
				continue
			hs = origins.points[inst.b]
			owner = ownerOfHolder[hs[0]] if hs.len == 1 else -1
			if irLoweredWord().on():
				g.irSay("irown: copy at b{b}:{k} from v{inst.b}: holders {hs}, owner {owner}")
			if owner >= 0:
				taken = g.irReachedBytes(p, inst, inst.b)
				match f.irReachedAfter(g, order, pos, owners, origins, p, owner, b, k, taken):
					(ub, uk, again, v):
						if irLoweredWord().on():
							g.irSay("irown: reached again at b{ub}:{uk} (op {f.blocks[ub].insts[uk].op}), a later turn {again}")
						g.irRefuseCopy(f,
							inst,
							f.blocks[ub].insts[uk],
							again,
							f.places.get(v) ?? "",
							file
						)
					none:
						takes.push(b)
						takes.push(k)
			else:
				g.irRefuseCopy(f, inst, inst, false, "", file)
	i = takes.len - 2
	while i >= 0:
		f.irTakeInstead(g, takes[i], takes[i + 1])
		i -= 2

# whether the deep copy inst is one this pass decides: one the program did not write, or any of a
# value with a drop function, which the compiler never copies (it would be dropped twice)
fn irCopyDecided(mut g Gen, inst IrInst):
	inst.cond > 0 or g.c.holdsDrop(inst.ty ?? tyError)

# copy (at instruction k of block b) of owner's bytes taken: the first later instruction that
# reaches them, and whether a loop's next turn does (none: nothing does); a path ends where the
# owner gets a new value or gives its own
fn irReachedAfter(
	f IrFn,
	mut g Gen,
	order i64[],
	pos i64[],
	owners IrOwners,
	origins IrOrigins,
	p IrParts,
	owner i64,
	b i64,
	k i64,
	taken (i64, i64)
) (i64, i64, bool, i64)?:
	copy = f.blocks[b].insts[k]
	slot = owners.vregs[owner]
	# a loop's element: what is made from its address (copied, offset, read through) is the
	# element each turn has, not the one given away
	element = fill(f.classes.len, false)
	if copy.cond == 4:
		element[copy.b] = true
		grew = true
		while grew:
			grew = false
			for blk in f.blocks:
				for inst in blk.insts:
					if inst.dst >= 0 and not element[inst.dst] and inst.a >= 0 and
						element[inst.a] and
						inst.op in [irCopy, irAdd, irLoad]:
						element[inst.dst] = true
						grew = true
					# what a call makes of the element (a window into it) is the element's too
					if (inst.op == irCall or inst.op == irCallPtr) and inst.args.any(element[it]):
						for out in [inst.dst, inst.c]:
							if out >= 0 and not element[out]:
								element[out] = true
								grew = true
	seen = fill(2 * f.blocks.len, false)
	todo = [(b, k + 1, false)]
	while not todo.isEmpty:
		blk, from, again = todo.remove(0)
		insts = f.blocks[blk].insts
		j = from
		ends = false
		zeroing = false
		while j < insts.len:
			inst = insts[j]
			if irIsMarker(inst.op):
				if (owners.irOwnerOf(inst.a) ?? -1) == owner:
					if inst.op == irOwnEnd and inst.cond == ownDropped and zeroing:
						zeroing = false
					else:
						ends = true
						break
				j += 1
				continue
			if inst.op == irDrop and inst.a == slot or
				inst.irRecyclesList() and (inst.args.first ?? -1) == slot:
				zeroing = true   # its own drop (a kept list's too): what is left of it
				j += 1
				continue
			if inst.op == irDrop:
				j += 1   # a part's old value dropped before it gets a new one: the taken bytes are empty
				continue
			if inst.op in [irStore, irMemSet, irMemCopy] and
				origins.points[inst.a].any(it == origins.holder[slot]) and
				irBytesCover(g.irReachedBytes(p, inst, inst.a), taken):
				ends = true   # the taken bytes written whole: they hold a value again
				break
			if zeroing or ((inst.op == irStore or inst.op == irMemSet) and inst.a == slot) or
				(copy.cond == 4 and inst.irReads().any(element[it])) or
				inst.op in [irAdd, irSub, irCopy, irSelect, irAnd, irOr]:
				j += 1   # its slot emptied; a loop's next element; an address made (its uses reach)
				continue
			for v in inst.irReads():
				if origins.points[v].any(it == origins.holder[slot]) and
					f.irPlacesMeet(v, copy) and irBytesMeet(g.irReachedBytes(p, inst, v), taken):
					return (blk, j, again, v)
			j += 1
		if ends: continue
		for s in f.irBlockSuccessors(blk):
			back = again or pos[s] <= pos[blk]
			at = s + (f.blocks.len if back else 0)
			if not seen[at]:
				seen[at] = true
				todo.push((s, 0, back))
	none

# the copy the program did not write refused: its place belongs to someone else (use is copy), or
# the use reads it again (in a later turn of a loop: again)
fn irRefuseCopy(mut g Gen, f IrFn, copy IrInst, use IrInst, again bool, usedPlace str, file str):
	parts = copy.key.split("\t")
	place = parts.last ?? ""
	name = parts.first ?? ""
	head = place.irPathHead()
	belongs = "the value behind this reference belongs to someone else" if place == ""
		else "'{place}' is borrowed" if head == place
		else "'{place}' belongs to '{head}'"
	whole = place != "" and head == place
	# a binding's whole name: a loop's element, a borrow given away
	given = name.copy() if copy.cond == 4 else place.copy() if whole else ""
	later = use.line != copy.line or use.col != copy.col
	msg = compileError("MutBindingOfBorrowed", ["{name}", "{belongs}"]) if copy.cond == 2
		else compileError("TakeApartBorrowed", ["{belongs}"]) if copy.cond == 3
		else compileError("UseAfterBase", ["{head}", "{copy.line}"]) if copy.cond == 6 and later and
			usedPlace == head
		else compileError("MoveOfBorrowed", ["{given}"]) if given != "" and (again or not later)
		else compileError("MoveOfPart", ["{belongs}"]) if again or not later
		else compileError("UseOfPartGiven", ["{head}", "{place}", "{copy.line}"]) if usedPlace !=
			"" and
			usedPlace == head
		else compileError(
			"UseAfterPartGiven",
			["{usedPlace if usedPlace != "" else place}", "{place}", "{copy.line}"]
		)
	at = copy if again or not later or copy.cond == 2 or copy.cond == 3 else use
	g.irOwnErrorAt(file, at, at.col, msg)

# a place's text up to its first field or element ("x" of "x.f[]")
fn irPathHead(path str):
	i = 0
	while i < path.len and path[i] != '.' and path[i] != '[':
		i += 1
	path[..i].copy()

# the copy at instruction k of block b made a move: its bytes copied, its place left its type's
# empty value
fn irTakeInstead(mut f IrFn, mut g Gen, b i64, k i64):
	copy = f.blocks[b].insts[k].copy()
	t = copy.ty ?? return
	out = []
	insts = f.blocks[b].insts
	for j, inst in insts:
		if j != k:
			out.push(inst.copy())
			continue
		out.push(
			IrInst(
				op = irMemCopy,
				a = copy.a,
				b = copy.b,
				imm = g.sizeOf(t),
				cond = 1,
				line = copy.line,
				col = copy.col
			)
		)
		out.extend(g.irEmptyingAt(f, copy.b, t, copy.line, copy.col))
	f.blocks[b].insts = out

# ---------- after each pass ----------
