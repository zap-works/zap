# The borrow conflicts a function's values reach (irOwn.zap).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds

# where an irNote is
type IrNoteAt:
	b i64
	k i64

# The lowering's notes judged: a change of a place (noteChanged) where a name that borrows it is
# still used after (its vreg live there), not through that name, is an error (ChangeWhileBorrowed;
# ChangeWhileCaptured for a lambda that points at its captures), unless the binding copies
# freely: then it copies, the function lowered again (g.irOwnMarks). A change inside a loop or a
# pipeline that reads the place in place is ChangeWhileRead (ChangeWhileLooped for a for loop's
# own list). A change a call makes is judged by what the callee changes (effects.zap).
fn irBorrowChecks(mut g Gen, f IrFn, file str):
	borrows = []
	reads = []
	anyChange = false
	for b in 0..f.blocks.len:
		insts = f.blocks[b].insts
		for k, inst in insts:
			if inst.op != irNote: continue
			if inst.imm == noteBorrow:
				borrows.push(IrNoteAt(b, k))
			if inst.imm == noteReadFrom:
				reads.push(IrNoteAt(b, k))
			if inst.imm == noteChanged or inst.imm == noteRead:
				anyChange = true
	if not anyChange: return
	for at in borrows:
		g.irBorrowConflict(f, at, file)
	for at in reads:
		g.irReadConflict(f, at, file)

# A borrow's uses: the vregs that hold its value (s), the addresses of its fields (parts) and
# the calls that read only some of them (noteCallRead). A part is named by the vreg whose part it
# is, or past the vregs by its index in extra plus their count.
type IrBorrowUses:
	s bool[]
	part str[]   # per vreg: the field of the borrowed value it is the address of ("f", "f.g"), or ""
	zero bool[]
	extra str[] = []   # the parts calls read
	calls {i64: i64[]} = {}   # by a call's place (irPlaceKey): the parts it reads (-1 the whole)

fn irPlaceKey(b i64, k i64):
	b * 1_048_576 + k

# the path of part p, relative to the borrowed value
fn irPartPath(u IrBorrowUses, p i64) ref str:
	if p >= u.s.len: return u.extra[p - u.s.len]
	u.part[p]

# the parts of the borrowed value inst reads, by the vreg whose part it is (-1: the value as a
# whole), none when it uses the borrow not at all: it reads none of its vregs, or reads one to
# copy it (irCopy), to drop or empty what holds it (that frees its own memory, not what it
# borrows) or to state ownership
fn irUsedParts(inst IrInst, u IrBorrowUses) i64[]?:
	if inst.op == irNote and inst.imm == noteUsed:
		if inst.target < 0: return none
		if u.s[inst.target]: return [-1]
		return [inst.target] if u.part[inst.target] != "" else none
	if inst.op in [irCopy, irNote, irDrop, irMemSet] or irIsMarker(inst.op): return none
	if inst.op == irStore and inst.c >= 0 and u.zero[inst.c]: return none   # (emptied)
	out = []
	for r in inst.irReads():
		if u.s[r]:
			# a field's address made: a use of that field
			out.push(inst.dst if inst.dst >= 0 and u.part[inst.dst] != "" else -1)
		elif u.part[r] != "":
			out.push(r)
	none if out.isEmpty else out

# irUsedParts of the instruction k of block b: a call that reads parts of the borrowed value
# itself uses those
fn irUsedPartsAt(inst IrInst, u IrBorrowUses, b i64, k i64) i64[]?:
	parts = try inst.irUsedParts(u)
	read = u.calls.get(irPlaceKey(b, k)) ?? return parts
	out = parts.filter(it != -1)
	out.extend(read)
	none if out.isEmpty else out

fn irUsesBorrow(inst IrInst, u IrBorrowUses):
	inst.irUsedParts(u) != none

# the vregs that hold v's value: v and its copies (irCopy, not a field's address), each read a
# use of the borrow; and the addresses of its fields, each read a use of that field
fn irBorrowUsesOf(f IrFn, v i64, move zero bool[]):
	n = f.classes.len
	isPart = fill(n, false)
	for blk in f.blocks:
		for inst in blk.insts:
			if inst.op == irNote and inst.imm == notePart and inst.target >= 0:
				isPart[inst.target] = true
	s = fill(n, false)
	s[v] = true
	grew = true
	while grew:
		grew = false
		for blk in f.blocks:
			for inst in blk.insts:
				if inst.op == irCopy and inst.dst >= 0 and inst.a >= 0 and s[inst.a] and
					not s[inst.dst] and not isPart[inst.dst]:
					s[inst.dst] = true
					grew = true
	part = fill(n, "")
	for blk in f.blocks:
		for inst in blk.insts:
			if inst.op == irNote and inst.imm == notePart and inst.other >= 0 and inst.target >= 0:
				if s[inst.other]:
					part[inst.target] = inst.key().copy()
				elif part[inst.other] != "":
					part[inst.target] = "{part[inst.other]}.{inst.key()}"
			elif inst.op == irCopy and inst.dst >= 0 and inst.a >= 0 and part[inst.a] != "" and
				not isPart[inst.dst]:
				part[inst.dst] = part[inst.a].copy()
	u = IrBorrowUses(s, part, zero)
	for b, blk in f.blocks:
		for k, inst in blk.insts:
			if inst.op != irNote or inst.imm != noteCallRead or inst.target < 0 or
				not u.s[inst.target]:
				continue
			at = irCallBefore(blk.insts, k, u.s) ?? continue
			ids = []
			for p in inst.key().split("\t"):
				if p == "$":
					ids.push(-1)
				elif p != "":
					ids.push(n + u.extra.len)
					u.extra.push(p.copy())
			key = irPlaceKey(b, at)
			if u.calls.get(key) is had:
				ids.extend(had)
			u.calls[key] = ids
	u

# the index of the last call before instruction k that reads one of the vregs of s
fn irCallBefore(insts IrInst[], k i64, s bool[]) i64?:
	j = k - 1
	while j >= 0:
		if insts[j].op in [irCall, irCallPtr] and insts[j].irReads().any(s[it]): return j
		j -= 1
	none

# per block, whether one of the vregs of s is read at or after its start before v is assigned
fn irLiveIn(f IrFn, u IrBorrowUses, v i64, selfUses bool):
	n = f.blocks.len
	live = fill(n, false)
	kills = fill(n, false)
	for b in 0..n:
		for inst in f.blocks[b].insts:
			if inst.dst == v and not (selfUses and inst.irUsesBorrow(u)):
				kills[b] = true   # (an update of v, x = x + 8, reads the old borrow to drop it)
				break
			if inst.irUsesBorrow(u):
				live[b] = true
				break
	grew = true
	while grew:
		grew = false
		for b in 0..n:
			if live[b] or kills[b]: continue
			if f.irBlockSuccessors(b).any(live[it]):
				live[b] = true
				grew = true
	live

# the line of the first use of the borrow after instruction k of block b on some path (before v
# is assigned again), or -1 for none; with a change, only a use of a part it changes (roots the
# places the borrow points into)
fn irNextUse(
	mut g Gen,
	f IrFn,
	u IrBorrowUses,
	v i64,
	b i64,
	k i64,
	selfUses bool,
	change ref IrInst? = none,
	roots str[] = []
):
	seen = fill(f.blocks.len, false)
	todo = [(b, k + 1)]
	while not todo.isEmpty:
		blk, from = todo.remove(0)
		insts = f.blocks[blk].insts
		j = from
		ends = false
		while j < insts.len:
			inst = insts[j]
			if inst.dst == v and not (selfUses and inst.irUsesBorrow(u)):
				ends = true
				break
			if inst.irUsedPartsAt(u, blk, j) is parts and g.irPartsMet(u, parts, change, roots):
				return inst.line
			j += 1
		if ends: continue
		for x in f.irBlockSuccessors(blk):
			if not seen[x]:
				seen[x] = true
				todo.push((x, 0))
	-1

# whether the change (none: any) meets one of the parts used of a borrow of roots
fn irPartsMet(mut g Gen, u IrBorrowUses, parts i64[], change ref IrInst?, roots str[]):
	m = change ?? return true
	if -1 in parts: return true
	for p in parts:
		if roots.any(g.irChangeMeets(m, "{it}.{u.irPartPath(p)}", false)): return true
	false

# whether the change note m changes root: the place itself, or what the callee changes through
# it (a mut parameter, the receiver, a module variable by its name)
fn irChangeMeets(mut g Gen, m IrInst, root str, headersKept bool):
	parts = m.key().split("\t")
	path = parts.first ?? ""
	param = parts[2] if parts.len > 2 else ""
	if root == "" or root == moduleOrigin: return false
	if m.other < 0: return path != "" and pathsOverlap(path, root)
	callee = NodeId(m.other)
	if path == "@":
		# a call: what it changes of the module variables
		head = pathHead(root).copy()
		if not g.irModuleVariable(head): return false
		return g.c
			.changedThrough(callee, "@{head}", head)
			.any(changeOverlaps(it, root, headersKept))
	if not pathsOverlap(path, root): return false
	if nodes[callee].mod(kidIds) == "rt" or nodes[callee].hasFlag(flagExtern) or
		g.c.opaqueFunction(callee):
		return true   # (its body works on raw memory: it changes the place as a whole)
	g.c.changedThrough(callee, param, path).any(changeOverlaps(it, root, headersKept))

# whether name is a module variable
fn irModuleVariable(mut g Gen, name str):
	cd = g.c.findDeclByGlobalName(nConstDecl, name) ?? return false
	nodes[cd].hasFlag(flagMut)

fn irBorrowConflict(mut g Gen, f IrFn, at IrNoteAt, file str):
	note = f.blocks[at.b].insts[at.k]
	parts = note.key().split("\t")
	name = parts.first ?? ""
	roots = parts[1..].filter(it != "")
	if roots.isEmpty: return
	v = note.target
	if irLoweredWord().on():
		g.irSay("irown: borrow '{note.key()}' v{v} at b{at.b}:{at.k}")
	zero = f.irZeroConstants() if note.scale == 2 else zeros(f.classes.len)   # (its slot emptied)
	u = f.irBorrowUsesOf(v, zero)
	liveAll = f.irLiveIn(u, v, true)   # (a walker's step reads where it points)
	readLine = -1
	readMsg = ""
	gone = f.irGivenKeys()   # (a local given away changes it as a whole)
	seen = fill(f.blocks.len, false)
	todo = [(at.b, at.k + 1)]
	while not todo.isEmpty:
		blk, from = todo.remove(0)
		insts = f.blocks[blk].insts
		j = from
		ends = false
		while j < insts.len:
			m = insts[j]
			if m.dst == v:
				ends = true
				break
			if m.op == irNote and m.imm == noteRead and note.cond == 3:
				rparts = m.key().split("\t")
				read = rparts.first ?? ""
				via = rparts[1] if rparts.len > 1 else ""
				if via != name and roots.any(pathsOverlap(it, read)):
					use = g.irNextUse(f, u, v, blk, j, false)
					if use >= 0 and readLine < 0:
						# (a change met later is told instead)
						readLine = m.line
						readMsg = compileError(
							"ReadWhileLent",
							["{read}", "{name}", "{note.line}", "{use}"]
						)
			if m.op == irOwnEnd and m.cond != ownDropped and m.cond != ownSuspended and
				gone.get(m.a) is key and key != name and roots.any(pathHead(it) == key):
				use = g.irNextUse(f, u, v, blk, j, false)
				if use >= 0:
					given = IrInst(op = irNote, line = m.line, part = instPartOf(key = "{key}		"))
					g.irReportBorrow(note, given, name, use, file)
					return
			if m.op == irNote and m.imm == noteChanged:
				mparts = m.key().split("\t")
				via = mparts[1] if mparts.len > 1 else ""
				if via != name and roots.any(g.irChangeMeets(m, it, false)):
					# a change of the list itself: a walker over its elements stepping on reads it
					whole = roots.any(.endsWith("[]") and g.irChangesList(m, it[..len - 2]))
					use = g.irNextUse(f, u, v, blk, j, whole, m, roots)
					if irLoweredWord().on():
						g.irSay(
							"irown: '{note.key()}' meets '{m.key()}' at b{blk}:{j}, next use line {use}"
						)
					if use >= 0:
						if irLoweredWord().on():
							g.irSayForm(f)
						g.irReportBorrow(note, m, name, use, file)
						return
			j += 1
		if ends: continue
		for x in f.irBlockSuccessors(blk):
			if not seen[x] and liveAll[x]:
				seen[x] = true
				todo.push((x, 0))
	if readLine >= 0:
		g.irOwnError(file, readLine, 0, readMsg)

fn irReportBorrow(mut g Gen, note IrInst, m IrInst, name str, use i64, file str):
	if irLoweredWord().on():
		g.irSay("irown: borrow '{note.key()}' (line {note.line}) met change '{m.key()}' (line {m.line}, callee {m.other})")
		if m.other >= 0:
			mparts = m.key().split("	")
			g.irSay("  changes {g.c.changedThrough(NodeId(m.other), mparts[2], mparts[0])} of {g.c.effects.summaries()} summaries")
	if note.cond == 1 and note.other >= 0:
		# a value that copies freely: the binding copies it instead
		g.irMark(NodeId(note.other), flagAutoCopy)
		g.irOwnMarks.push(NodeId(note.other))
		return
	path = changedPlace(m.key().split("\t").first ?? "")
	msg = compileError(
		"ChangeWhileCaptured",
		["{path}", "{name}", "{note.line}", "{use}"]
	) if note.cond ==
		2
		else compileError("ChangeWhileBorrowed", ["{path}", "{name}", "{note.line}", "{use}"])
	g.irOwnErrorAt(file, m, 0, msg)

# A loop or a pipeline reading a place in place (noteReadFrom to its noteReadTo): a change of the
# place in between is an error; a for loop's own list only when changed itself (cond 1: pushed
# to, assigned), not its elements.
fn irReadConflict(mut g Gen, f IrFn, at IrNoteAt, file str):
	note = f.blocks[at.b].insts[at.k]
	parts = note.key().split("\t")
	root = parts.first ?? ""
	what = parts[1] if parts.len > 1 else ""
	if root == "": return
	seen = fill(f.blocks.len, false)
	todo = [(at.b, at.k + 1)]
	while not todo.isEmpty:
		blk, from = todo.remove(0)
		insts = f.blocks[blk].insts
		j = from
		ends = false
		while j < insts.len:
			m = insts[j]
			if m.op == irNote and m.imm == noteReadTo and m.target == note.target:
				ends = true
				break
			if m.op == irNote and m.imm == noteChanged:
				mparts = m.key().split("\t")
				path = mparts.first ?? ""
				via = mparts[1] if mparts.len > 1 else ""
				if note.cond == 1:
					head = pathHead(root).copy()
					whole = g.irModuleVariable(head) and
						g.c
							.changedThrough(NodeId(m.other), "@{head}", head)
							.any(changedPlace(it) == root) if path ==
						"@"
						else path == root and "[" not in root and via == "" and m.other < 0
					if whole:
						g.irOwnError(
							file,
							m.line,
							0,
							compileError("ChangeWhileLooped", ["{root}", "{note.line}"])
						)
						return
				elif g.irChangeMeets(m, root, note.cond == 3):
					g.irOwnError(
						file,
						m.line,
						0,
						compileError(
							"ChangeWhileRead",
							["{changedPlace(path)}", "{what}", "{root}"]
						)
					)
					return
			j += 1
		if ends: continue
		for x in f.irBlockSuccessors(blk):
			if not seen[x]:
				seen[x] = true
				todo.push((x, 0))

# per vreg: whether it is only ever the constant 0
fn irZeroConstants(f IrFn):
	zero = fill(f.classes.len, true)
	for blk in f.blocks:
		for inst in blk.insts:
			if inst.dst >= 0 and (inst.op != irConst or inst.imm != 0):
				zero[inst.dst] = false
	zero

# whether the change note m changes the list at place list itself (grows, empties or replaces it,
# not one of its elements)
fn irChangesList(mut g Gen, m IrInst, list str):
	parts = m.key().split("	")
	path = parts.first ?? ""
	if m.other < 0: return path == list
	callee = NodeId(m.other)
	if path == "@" or path != list: return false
	if nodes[callee].mod(kidIds) == "rt" or nodes[callee].hasFlag(flagExtern): return true
	param = parts[2] if parts.len > 2 else ""
	g.c.changedThrough(callee, param, path).any(changedPlace(it) == list)

# by an owner's slot: the local's name its irOwn gives it
fn irGivenKeys(f IrFn):
	out {i64: str} = {}
	for blk in f.blocks:
		for inst in blk.insts:
			if inst.op == irOwn and inst.key() != "" and inst.a >= 0:
				out[inst.a] = inst.key().copy()
	out
