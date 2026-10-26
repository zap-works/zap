# The checked tree of a function lowered to the intermediate form (ir.zap). Only what it knows:
# any other node stops it (ok false, why naming the node) and the build fails naming the function.
# A value is a list of vregs, its leaves: one for an integer, a bool or an f64, one per number of
# a struct of numbers (nested structs flattened), a tag and a value for an optional scalar, none
# for (); a list, a str, or a struct holding them (a place struct), is one leaf, its address.
# A value that owns memory lives in a frame slot (zeroed when the function starts): a temporary
# is dropped when its statement ends unless a let or a return takes it; a local when its scope
# ends, or a break, continue or return leaves it. Moving one copies its bytes and zeroes them where
# they were, so a later drop there frees nothing. Small functions and methods are inlined (their bodies lowered in place, the parameters
# bound to the arguments' leaves); others are called when their values are scalars.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

type IrLower:
	f IrFn
	fnd NodeId?   # the function lowered (none: a lambda's body)
	rt TypeId = tyUnit   # its result type
	names str[]   # the names in scope, innermost last
	nameIndex NameIndex = NameIndex()   # where each name stands in names
	vals i64[,]   # their leaves
	floor i64 = 0   # the names below it belong to an inlined body's callers
	breaks i64[]   # per open loop: the block after it
	conts i64[]   # per open loop: the block continue goes to
	rets IrReturn[] = []   # the inlined bodies being lowered, innermost last
	proven IrProven[] = []   # known in bounds: a for over 0..xs.len
	owned IrOwned[] = []   # the values the code owns: locals (their name's index) and temporaries
	loopOwned i64[] = []   # per open loop: how many owned values there were before its body
	hidden i64 = -1   # the vreg of the address a non-scalar result is written to
	regResult bool = false   # the result's leaves given back in registers (irResultClasses)
	mutScalars IrMutScalar[] = []
	conditions i64 = 0   # conditions being lowered, nested
	literals i64[] = []   # the frame slots of str literals (they own nothing: copied freely)
	literalWords IrLiteralWords[] = []
	made i64[] = []   # the frame slots of values by address that own nothing, made here
	raw i64[] = []   # a map's or box's word read raw (__at): it goes where it is put, owning nothing here
	spills IrSpill[] = []   # locals of numbers a lambda changes through a pointer: in memory around each call
	checked NodeId[] = []   # index nodes checked before their loop (at its first and last step), and their indexes' + - *
	steady i64[] = []   # the addresses of lists a read parameter holds (irSteadyList)
	thisType TypeId? = none   # in a method's body: its struct (a bare name may be a field)
	armWrites IrArmWrite[] = []   # a variant's values the open arms assign (written back by a return)
	seqs IrSeq[] = []   # the generators whose bodies are being lowered into walks, innermost last
	arenas i64 = 0   # the `arena:` blocks open
	loopArenas i64[] = []   # per open loop: the arena blocks open at its start
	given IrGiven[] = []   # parameters a call gave a function to (irGiven.zap): the name's index, the lambda or the function's name
	site Subst = Subst(names = [], types = [])   # the substitution in force where the call being lowered is written
	ofRuntime bool = false   # the function is the runtime's
	mutNames i64[] = []   # the names (their indices) bound `mut`
	moveWritten bool = false   # the move being lowered is written `move`
	keepEmptied bool = false   # and it leaves the local it empties usable (a mut one)
	givenSlots {i64: i64} = {}   # by a local's word: the slot of the map it gave away
	places {i64: str} = {}   # by the address of a place's value that owns memory: the place's text
	wordPlaces {i64: i64} = {}   # by the word of a map or box read from a field: the field's address
	loopElems i64[] = []   # the addresses of the elements loops go over, by address
	choosing bool = false   # an arm's value put in its choice's slot
	keying i64 = 0   # the key lambdas being lowered (their values are only compared)
	borrowedKey NodeId? = none   # a key's struct literal whose strs borrow what outlives the sort
	keyParts i64 = 0   # the key parts being lowered where a sort compares (irKeyPartValue)
	errorOut i64 = 0   # lowering an error being returned (irReturn): its calls stay calls, made once on the way out
	fromBase i64[] = []   # the fields a struct's literal reads from its `..base`
	windows i64[] = []   # the slots of windows made here (a pointer and a length into a place)
	onceCaptures i64[] = []   # a lambda run once (spawn's): its captures, which its body may give
	borrowOf {i64: str} = {}   # by a name's index: the place the name is another name for
	exclusive {i64: str} = {}   # by a name's index: the place it changes, lent to it alone (a mut ref)
	firstLocal i64 = 0   # the names from here on are the body's (before: the parameters, self)
	lentTry i64 = -1   # the `x?` a binding borrows from (irLetBorrows): not given away
	localLambdas {i64: NodeId} = {}   # by a name's index: the lambda only called by it (flagLocalLambda)
	arenaLines i64[] = []   # the line of each open arena block
	nameLevel {i64: i64} = {}   # by a name's index: the arena blocks open where it was bound
	arenaWalk IrArenaStmt[] = []   # per statement being lowered in an arena: what it moves, where it stores
	held {i64: str[]} = {}   # by a name's index: the places its value borrows (irNotes.zap)
	borrowsNoted bool = false   # a borrow noted: field addresses are noted from here (notePart)
	keptInner IrKeptRef[] = []   # references a list keeps into locals bound after it (irKeepsRefs)
	namedBy {i64: i64} = {}   # by a leaf a name's value is in: the name's node, the last that read it
# (the one a local's value goes by, irConsumed)
	keptBlocks IrKeptBlock[] = []   # the bindings whose list a loop keeps from turn to turn
	recycleInto i64 = -1   # while a recycled binding's value is lowered: the slot of its kept block
	inRegion bool = false   # lowering a statement that runs in an implicit region (irRegionStatement)
	resultAt i64 = -1   # where the next call's result goes instead of a slot (irBox), -1 for none
	placed i64 = -1   # the resultAt the last call took
	arenaClean bool = false   # lowering a statement of an arena block that makes only the region's
	# blocks: its temporaries, and an immutable binding of one, are not dropped one by one
	inlined i64 = 0   # the blocks the bodies inlined so far made (irInlineBlocks)
	bodies {str: IrBody} = {}   # the bodies inlined here, by the state they were lowered in (irBodies.zap)
	sharedParams i64 = 0   # the parameters irBindParams bound to the caller's places, not values of their own
	foreign i64 = 0   # the bodies of another file inlined around the code being lowered
	ok bool = true
	why str = ""
	line i64 = 0
	col i64 = 0

# a list (the name at index holder) keeping a reference into the local at index root: refused
# when the root's block ends before the list's (RefOutlivesLocal)
type IrKeptRef:
	holder i64
	root i64
	line i64
	col i64

# a binding of a loop's body and the slot its list's block waits in between turns (irKeptBlocks)
type IrKeptBlock:
	let NodeId
	slot i64

# an element known in bounds: the list, the index, the element's address
type IrProven:
	list i64
	index i64
	addr i64

# a mut struct of numbers: its address, its leaves, its type
type IrMutScalar:
	addr i64
	leaves i64[]
	ty TypeId

# a literal's slot, its bytes' address, its length
type IrLiteralWords:
	slot i64
	bytes i64
	length i64

# a list's header word at off (0 items, 8 length, 16 room)
fn irHeader(mut lw IrLower, list i64, off i64) i64:
	if off < 16 and lw.literalWords.find(.slot == list) is w:
		return w.bytes if off == 0 else w.length   # a literal's words, known: no load
	lw.irDef(
		irInt,
		IrInst(op = irLoad, a = list, imm = off, header = true, steady = list in lw.steady)
	)

# The bytes' address and length of the str at a, read as runtime/core/core.zap's textPtrAt and
# textLenAt read them: a short str keeps its bytes in its own header, its cap word negative and its
# last byte 128 + its length. A literal's (or a window's copy's) words are known.
fn irStrWords(mut lw IrLower, a i64):
	if lw.literalWords.find(.slot == a) is w: return (w.bytes, w.length)
	room = lw.irHeader(a, 16)
	zero = lw.irConstOf(irInt, 0)
	ptr = lw.f.irVreg(irInt)
	irPut(
		lw,
		IrInst(
			op = irSelect,
			dst = ptr,
			a = room,
			b = zero,
			c = a,
			d = lw.irHeader(a, 0),
			cond = irLt
		)
	)
	top = lw.f.irVreg(irInt)
	lw.irPut(IrInst(op = irShr, dst = top, a = room, b = lw.irConstOf(irInt, 56), uns = true))
	short = lw.f.irVreg(irInt)
	lw.irPut(IrInst(op = irAnd, dst = short, a = top, b = lw.irConstOf(irInt, 127)))
	n = lw.f.irVreg(irInt)
	irPut(
		lw,
		IrInst(
			op = irSelect,
			dst = n,
			a = room,
			b = zero,
			c = short,
			d = lw.irDef(irInt, IrInst(op = irLoad, a, imm = 8)),   # (a short str's bytes: no length)
			cond = irLt
		)
	)
	(ptr, n)

# a window { ptr, n } in a slot of the statement
fn irWindowSlot(mut lw IrLower, ptr i64, n i64):
	slot = lw.f.irVreg(irInt)
	lw.irPut(IrInst(op = irFrameSlot, dst = slot, imm = 16))
	lw.irPut(IrInst(op = irStore, a = slot, c = ptr, header = true))
	lw.irPut(IrInst(op = irStore, a = slot, c = n, imm = 8, header = true))
	slot

# a slot for a window { ptr, n } a name reads as a str or a list: room 0 after the two words, so
# the runtime, which reads a header's third word, sees one that owns nothing
fn irNamedWindowSlot(mut lw IrLower):
	slot = lw.irNewSlot(24)
	lw.irPut(IrInst(op = irStore, a = slot, c = lw.irConstOf(irInt, 0), imm = 16, header = true))
	lw.made.push(slot)
	lw.windows.push(slot)
	slot

# the window at w as a str that owns nothing (room 0: never short), in a slot of the statement
fn irWindowAsStr(mut lw IrLower, w i64) i64:
	lw.irTextOwningNothing(lw.irHeader(w, 0), lw.irHeader(w, 8))

# the str at a, borrowed, as a str that owns nothing (room 0), in a slot of the statement
fn irBorrowedStr(mut lw IrLower, a i64) i64:
	ptr, n = lw.irStrWords(a)
	lw.irTextOwningNothing(ptr, n)

# a str { ptr, n, 0 } in a slot of the statement, its words known to irStrWords
fn irTextOwningNothing(mut lw IrLower, ptr i64, n i64):
	slot = lw.f.irVreg(irInt)
	lw.irPut(IrInst(op = irFrameSlot, dst = slot, imm = 24))
	lw.irPut(IrInst(op = irStore, a = slot, c = ptr, header = true))
	lw.irPut(IrInst(op = irStore, a = slot, c = n, imm = 8, header = true))
	lw.irPut(IrInst(op = irStore, a = slot, c = lw.irConstOf(irInt, 0), imm = 16, header = true))
	lw.literalWords.push((slot, ptr, n))
	lw.windows.push(slot)   # a borrow: given where an owned value is wanted, the check refuses it
	slot

# the lengths of the lists the region holds written to memory (out), or the headers read back
# a name an arm of a match assigns: the address and type of the value it is written back to
type IrArmWrite:
	name str
	at i64
	t TypeId

# a local of numbers a lambda reaches through a pointer: its leaves, written to the slot before a
# call (which may run the lambda) and read back after it
type IrSpill:
	leaves i64[]
	slot i64
	t TypeId

# the slot a local of numbers (its leaves) lives in from now on, kept in step with its leaves
# around calls (irSyncHeaders): made at its first need, then the same
fn irSpillSlot(mut g Gen, mut lw IrLower, leaves i64[], t TypeId):
	if lw.spills.find(.leaves == leaves) is sp: return sp.slot
	slot = lw.irNewSlot(g.sizeOf(t).alignUp(8))
	g.irStoreLeaves(lw, t, slot, -1, 1, 0, leaves)
	lw.spills.push(IrSpill(leaves = leaves.copy(), slot, t))
	slot

# inst put between the spilled locals written out and read back: a call, or what may run one
# (which may read or grow those lists)
fn irPutSynced(mut g Gen, mut lw IrLower, move inst IrInst):
	g.irSyncHeaders(lw, true)
	lw.irPut(inst)
	g.irSyncHeaders(lw, false)

fn irSyncHeaders(mut g Gen, mut lw IrLower, out bool):
	for sp in lw.spills.copy():
		if out:
			g.irStoreLeaves(lw, sp.t, sp.slot, -1, 1, 0, sp.leaves)
		else:
			leaves = g.irLeaves(sp.t, 0)
			for i, leaf in leaves:
				if g.irIsNicheTag(leaf.t): continue
				irPut(
					lw,
					IrInst(
						op = irLoad,
						dst = sp.leaves[i],
						a = sp.slot,
						imm = leaf.off,
						size = g.c.typeSize(leaf.t),
						uns = not g.irSigned(leaf.t)
					)
				)
				if i > 0 and g.irIsNicheTag(leaves[i - 1].t):
					g.irNicheTagOf(
						lw,
						innerOf(tys, leaves[i - 1].t),
						sp.leaves[i],
						sp.leaves[i - 1]
					)

# the names of lists e pushes onto
fn irPushedNames(g Gen, e NodeId, mut out str[]):
	if nodes[e].kind == nCall and nodes[nodes[e].kids(kidIds)[0]].kind == nField and
		nodes[nodes[e].kids(kidIds)[0]].text == "push":
		obj = nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0]
		if nodes[obj].kind == nIdent and nodes[obj].text not in out:
			out.push(nodes[obj].text.copy())
	for k in nodes[e].kids(kidIds):
		g.irPushedNames(k, out)
	for k in nodes[e].sub():
		g.irPushedNames(k, out)

# a value the code owns: in the frame slot at slot, of type t; name its local's index among the
# names (-1: a temporary of the statement being lowered)
type IrOwned:
	slot i64
	t TypeId
	name i64
	word i64 = -1   # a map: the vreg of the table's address; the slot holds a copy for the drop
	key str = ""   # the local's name, in its irOwn
	block i64 = -1   # where its irOwn is
	at i64 = -1
	kept i64 = -1   # a list a loop's turn made: the loop's slot its block goes back to (irKeptBlocks)
	region bool = false   # made by a statement of an arena block that makes only the region's blocks

# whether t is an owned value in one word (a map): the word is the value, its slot is for the drop
fn irIsOwnedWord(mut g Gen, maybeT TypeId?):
	t = maybeT ?? return false
	tys[t].kind == tMap or tys[t].kind == tBox or g.c.isNicheOption(t) and g.isOwningType(t)

# a map the code owns from now on, in word: its slot for the drop, a temporary of the statement
fn irOwnedWord(mut g Gen, mut lw IrLower, t TypeId, word i64):
	slot = lw.irNewSlot(8)
	lw.irOwnBegin(IrOwned(slot, t, name = -1, word))
	lw.irPut(IrInst(op = irStore, a = slot, c = word))

# the map (or box, or one inside an optional: 0 when there is none) a call or a body gave in
# leaves, of type rt: the statement's from now on
fn irOwnGivenWords(mut g Gen, mut lw IrLower, rt TypeId, leaves i64[]):
	if g.irIsOwnedWord(rt) and leaves.len == 1:
		g.irOwnedWord(lw, rt, leaves[0])
	elif g.irIsOption(rt) and g.irIsOwnedWord(tys[rt].inner) and leaves.len == 2:
		g.irOwnedWord(lw, innerOf(tys, rt), leaves[1])

# the owned map held in word, or -1
fn irOwnedWordAt(lw IrLower, word i64):
	lw.owned.findIndex(.word == word and word >= 0) ?? -1

# the map (or box) of type t in word made this code's to give away: a temporary's is taken (it
# drops nothing any more), a place's deep-copied (0, none, stays 0); the word to own (irOwnedWord)
fn irWordTaken(mut g Gen, mut lw IrLower, t TypeId, word i64) i64:
	oi = lw.irOwnedWordAt(word)
	if oi >= 0 and lw.owned[oi].name < 0: return g.irGiveWord(lw, word)
	g.irWordCopied(lw, t, word)

# the map (or box) of type t at address at, a temporary's, taken out of it: the temporary keeps
# the empty word (its drop frees nothing); the word, not yet owned (irOwnedWord)
fn irWordMovedOut(mut g Gen, mut lw IrLower, t TypeId, at i64):
	word = g.irLoadValue(lw, t, at, -1, 0)[0]
	g.irEmptyAt(lw, at, t)
	word

# a deep copy of the map (or box) of type t in word (0, none, stays 0): the copy's word, not
# yet owned
fn irWordCopied(mut g Gen, mut lw IrLower, t TypeId, word i64):
	v = lw.irDef(irInt, IrInst(op = irConst, imm = 0))
	way = lw.irSplitNZ(word, false)
	src = lw.irNewSlot(8)
	lw.irPut(IrInst(op = irStore, a = src, c = word))
	dst = lw.irNewSlot(8)
	irPut(   # an optional box's word is the box's
		lw,
		IrInst(
			op = irDeepCopy,
			a = dst,
			b = src,
			ty = innerOf(tys, t) if g.c.isNicheOption(t) else t
		)
	)
	lw.irPut(IrInst(op = irLoad, dst = v, a = dst))
	lw.f.irJoin(way.end)
	v

# the map in word given away (stored, returned, moved): no longer this code's to drop
# irGiveWord, or the word of a field's map (box) taken out of the field when nothing reads the
# field after (the ownership check decides: a copy the program did not write, irDeepCopy cond 1)
fn irGivenWord(mut g Gen, mut lw IrLower, t TypeId, word i64) i64:
	given = g.irGiveWordOf(lw, t, word)
	if given >= 0: return given
	at = lw.wordPlaces.get(word) ?? return -1
	slot = lw.irNewSlot(8)
	irPut(
		lw,
		IrInst(
			op = irDeepCopy,
			a = slot,
			b = at,
			ty = t,
			cond = 1,
			key = (lw.places.get(at) ?? "").copy()
		)
	)
	lw.irDef(irInt, IrInst(op = irLoad, a = slot))

# the word to give: a local's in a vreg of its own, typed as moved bytes (the ownership check
# reads a use of the local's name after this as a use of a value that went); -1 when this code
# does not own the map
fn irGiveWordOf(mut g Gen, mut lw IrLower, t TypeId, word i64) i64:
	given = g.irGiveWord(lw, word)
	if given >= 0 or not g.c.copiesFreely(t): return given
	if lw.namedBy.get(word) is n and nodes[NodeId(n)].kind == nIdent:
		lw.irArenaMovedName(lw.irLookupAt(nodes[NodeId(n)].text), t)
	g.irWordCopied(lw, t, word)   # a shared value: one more owner (its copy counts it)

fn irGiveWord(mut g Gen, mut lw IrLower, word i64):
	if word in lw.raw: return word
	oi = lw.irOwnedWordAt(word)
	if oi < 0: return -1
	given = word
	if lw.owned[oi].name >= 0:
		lw.givenSlots[word] = lw.owned[oi].slot
		given = lw.f.irVreg(irInt)
		lw.f.irLeafTyped(given, irMovedBytes)
		lw.irPut(IrInst(op = irCopy, dst = given, a = word))
	lw.irPut(IrInst(op = irStore, a = lw.owned[oi].slot, c = lw.irConstOf(irInt, 0)))
	namer = lw.namedBy.get(word) ?? -1
	if namer >= 0:
		lw.namedBy[lw.owned[oi].slot] = namer
	lw.irConsumed(lw.owned[oi].slot, ownGiven)
	lw.owned.remove(oi)
	given

# a new frame slot for a value of type t that owns memory, a temporary of the statement
fn irTemporary(mut g Gen, mut lw IrLower, t TypeId):
	slot = lw.irNewSlot(g.sizeOf(t))
	lw.irOwnBegin(IrOwned(slot, t, name = -1, region = lw.arenaClean))
	slot

# a value of leaves lent to a call by address: stored in a frame slot of its own, the slot's
# address
fn irLentCopy(mut g Gen, mut lw IrLower, t TypeId, value i64[]):
	slot = lw.irNewSlot(g.sizeOf(t))
	g.irStoreLeaves(lw, t, slot, -1, 1, 0, value)
	slot

# a frame slot for a result of type t: a temporary when it owns memory, else plain (a window, a
# value of leaves written through memory)
fn irResultSlot(mut g Gen, mut lw IrLower, t TypeId):
	if g.irOwnedByAddress(t): return g.irTemporary(lw, t)
	slot = lw.irNewSlot(g.sizeOf(t))
	lw.made.push(slot)
	if g.irIsWindow(t):
		lw.windows.push(slot)
	slot

# the owned value at slot dropped, its slot zeroed (dropping it again frees nothing)
fn irDropSlot(mut g Gen, mut lw IrLower, o IrOwned):
	if o.region and o.word < 0 and g.irByAddress(o.t) and g.irOfRegionOnly(o.t):
		# the region's blocks alone, given back whole at the block's end
		g.irZeroSlot(lw, o.slot, o.t)
		lw.irConsumed(o.slot, ownDropped)
		return
	if o.kept < 0 and o.word < 0 and g.irOfRegionOnly(o.t) and
		lw.irJustZeroed(o.slot, g.sizeOf(o.t).alignUp(8)):
		lw.irConsumed(o.slot, ownDropped)   # its value moved out: nothing to free
		return
	if lw.inRegion and o.name < 0 and o.word < 0 and g.irByAddress(o.t) and g.irOfRegionOnly(o.t):
		g.irRegionDrop(lw, o)
		return
	if o.kept >= 0:
		g.irRtInstanceValues(lw, "listRecycle", [innerOf(tys, o.t)], [o.slot, o.kept])
	else:
		lw.irPut(IrInst(op = irDrop, a = o.slot, ty = o.t))
	g.irZeroSlot(lw, o.slot, o.t)
	lw.irConsumed(o.slot, ownDropped)

# whether the last instructions lowered stored 0 over every word of the size bytes at slot (a
# value moved out of it), with nothing else between
fn irJustZeroed(lw IrLower, slot i64, size i64):
	insts = lw.f.blocks[lw.f.cur].insts
	zeros = []
	i = insts.len - 1
	while i >= 0 and (insts[i].op == irConst or
			insts[i].op == irStore and insts[i].a == slot and insts[i].b < 0 and
			insts[i].size == 8):
		if insts[i].op == irConst and insts[i].imm == 0:
			zeros.push(insts[i].dst)
		i -= 1
	words = 0
	at = 0
	while at < size:
		# the last store over the word (the first met going back)
		j = insts.len - 1
		while j > i and not (insts[j].op == irStore and insts[j].imm == at):
			j -= 1
		if j == i or insts[j].c not in zeros: return false
		words += 1
		at += 8
	words > 0

# the owned locals from name index from on dropped (a scope left), innermost first
fn irDropLocals(mut g Gen, mut lw IrLower, from i64):
	i = lw.owned.len - 1
	while i >= 0:
		o = lw.owned[i].copy()
		if o.name >= from:
			g.irDropSlot(lw, o)
		i -= 1

# every owned value from position at on in the record dropped (a loop or a body left)
fn irDropFrom(mut g Gen, mut lw IrLower, at i64):
	i = lw.owned.len - 1
	while i >= at:
		g.irDropSlot(lw, lw.owned[i].copy())
		i -= 1

# the temporaries made since position at (a let's) kept: the binding may borrow from them (`w =
# line.trim()`, `n = parse(t).name`), so each is a hidden local, alive while what points into it
# is (irPlaceDrops)
fn irKeepTemporaries(mut lw IrLower, at i64):
	for i in at..lw.owned.len:
		if lw.owned[i].name < 0:
			held = lw.owned[i].word if lw.owned[i].word >= 0 else lw.owned[i].slot   # (a map's word)
			lw.irDeclare("$kept", [held])
			lw.irNameOwned(i, lw.names.len - 1, "$kept")

# the temporaries made since position at (a statement's) dropped and forgotten
fn irDropTemporaries(mut g Gen, mut lw IrLower, at i64):
	if not lw.f.irEnded():
		i = lw.owned.len - 1
		while i >= at:
			o = lw.owned[i].copy()
			if o.name < 0:
				g.irDropSlot(lw, o)
			i -= 1
	kept = []
	for i in 0..lw.owned.len:
		if i < at or lw.owned[i].name >= 0:
			kept.push(lw.owned[i].copy())
	lw.owned = kept

# whether a value of type t may point into what it was made from: a reference or a window, an
# optional or a result of one, a view, a list or map of them, an enum carrying one (a box owns
# its value: it borrows nothing). Such a value keeps the temporaries it was made from alive to
# the end of its statement. Recursive types are read a few levels deep.
fn irMayBorrow(mut g Gen, t TypeId):
	if g.mayBorrow.get(t) is known: return known
	borrows = g.irMayBorrowIn(t, 0)
	g.mayBorrow[t] = borrows
	borrows

fn irMayBorrowIn(mut g Gen, maybeT TypeId?, depth i64) bool:
	t = maybeT ?? return false
	if depth > 3: return false
	k = g.tyK(t)
	if k == tRef: return true
	if k == tOption: return g.irMayBorrowIn(tys[t].inner, depth + 1)
	if k == tResult:
		return g.irMayBorrowIn(tys[t].inner, depth + 1) or g.irMayBorrowIn(tys[t].err, depth + 1)
	if k == tEnum:
		for v in nodes[declOf(tys, t)].kids(kidIds).copy():
			for f in nodes[v].kids(kidIds).copy():
				if g.irMayBorrowIn(g.c.resolveType(nodes[f].types()[0]), depth + 1): return true
		return false
	g.c.isViewType(t) or g.c.holdsRefs(t)

# the temporaries made since `at` for a call's arguments (its receiver's too) dropped right after
# it, unless its value (in leaves) is one of them or may point into them: nothing outlives its
# last use
fn irDropArgTemps(mut g Gen, mut lw IrLower, at i64, t TypeId, leaves i64[]):
	if not lw.ok or g.irMayBorrow(t) or lw.owned.len <= at: return
	kept = []
	dropped = []
	for i in 0..lw.owned.len:
		o = lw.owned[i].copy()
		if i >= at and o.name < 0 and o.slot not in leaves and
			not (o.word >= 0 and o.word in leaves):
			dropped.push(o)
		else:
			kept.push(o)
	if not lw.f.irEnded():
		i = dropped.len - 1
		while i >= 0:
			g.irDropSlot(lw, dropped[i])
			i -= 1
	lw.owned = kept

# whether slot holds a value the code owns (a temporary or a local)
fn irOwns(lw IrLower, slot i64):
	lw.owned.any(.slot == slot)

# o's slot owns its value from here: in the record, and stated in the form (irOwn)
fn irOwnBegin(mut lw IrLower, move o IrOwned):
	owned = o
	owned.block = lw.f.cur
	owned.at = lw.f.blocks[lw.f.cur].insts.len
	if lw.irInRuntimeCode():
		owned.key = ""
	irPut(
		lw,
		IrInst(
			op = irOwn,
			a = owned.slot,
			b = owned.word,
			imm = i64(owned.t),
			key = owned.key.copy()
		)
	)
	lw.owned.push(owned)

# whether the code being lowered is the runtime's (its function, or a body of its inlined): it
# keeps its ownership by hand, its owners left to the lowering's drops and its words untyped
fn irInRuntimeCode(lw IrLower):
	lw.ofRuntime if lw.rets.isEmpty else lw.rets[len - 1].runtime

# owned value oi becomes the local name (at its index among the names), its irOwn saying so
fn irNameOwned(mut lw IrLower, oi i64, at i64, name str):
	lw.owned[oi].name = at
	lw.owned[oi].region = false   # (kept by an immutable binding only: irBindNameAtBorrow)
	if lw.irInRuntimeCode(): return
	lw.owned[oi].key = name.copy()
	if lw.owned[oi].block >= 0:
		lw.f.blocks[lw.owned[oi].block].insts[lw.owned[oi].at].key = name.copy()

# a new vreg for a leaf of type t, its type kept for the ownership check
fn irLeafVreg(mut g Gen, mut lw IrLower, t TypeId):
	v = lw.f.irVreg(g.irClassOf(t))
	if not lw.irInRuntimeCode():   # its addresses are numbers
		lw.f.irLeafTyped(v, i64(t))
	v

# the value slot owns consumed (how: ownDropped...), stated in the form (irOwnEnd)
fn irConsumed(mut lw IrLower, slot i64, how i64):
	if how != ownDropped and how != ownSuspended:
		lw.irArenaMoved(slot)
	lw.irPut(IrInst(op = irOwnEnd, a = slot, cond = how, other = lw.namedBy.get(slot) ?? -1))

# an owned value of type t (by address) put at addr: the one there dropped first (replaces), then
# the value moved in from the temporary or local that owns it, or a literal's header copied
fn irPutOwned(mut g Gen, mut lw IrLower, addr i64, t TypeId, value0 i64[], replaces bool):
	if not lw.ok: return
	if value0.len != 1:
		lw.irFail("a store of {typeStr(tys, t)}")
		return
	value = g.irOwnedCopy(lw, t, value0[0])
	if replaces:
		lw.irPut(IrInst(op = irDrop, a = addr, ty = t))
		if lw.owned.find(.slot == addr and .name >= 0) is local:
			# a local's value replaced: the old one gone, the new one its own
			lw.irConsumed(addr, ownDropped)
			lw.irPut(
				IrInst(
					op = irOwn,
					a = addr,
					b = local.word,
					imm = i64(local.t),
					key = local.key.copy()
				)
			)
	if value in lw.literals and not lw.owned.any(.slot == value and .name >= 0):
		lw.irPut(IrInst(op = irMemCopy, a = addr, b = value, imm = g.sizeOf(t)))
	else:
		g.irMoveTo(lw, addr, value, t)

# a value of type t (owned, by address) at v as one this code owns or a literal: v itself, or,
# a borrow (a field read, a parameter, an element), a deep copy of it in a temporary
fn irOwnedCopy(mut g Gen, mut lw IrLower, t TypeId, v i64):
	if lw.irOwns(v) or v in lw.literals: return v
	copy = g.irTemporary(lw, t)
	irPut(   # one the program did not write: the ownership check decides it
		lw,
		IrInst(
			op = irDeepCopy,
			a = copy,
			b = v,
			ty = t,
			cond = 0 if lw.irInRuntimeCode() or lw.keying > 0 else 5 if v in lw.onceCaptures else 4 if v in lw.loopElems else 6 if v in lw.fromBase else 1 if (v in lw.places or v in lw.windows) and not lw.choosing else 0,   # (a value made here, the runtime's: copied)
			key = (lw.places.get(v) ?? "").copy()
		)
	)
	copy

# v, the leaves of the place e, kept with e's text when e owns memory and is reached by address
# (the ownership check names it)
fn irPlaced(mut g Gen, mut lw IrLower, e NodeId, move v i64[]):
	if not lw.exclusive.isEmpty:
		g.irNoteRead(lw, e)
	if v.len == 1 and v[0] in lw.loopElems: return v   # its loop knows where it is
	if v.len == 1 and g.irIsOwnedWord(g.ty(e)) and nodes[e].kind == nField and
		g.irIsPlaceNode(e) and
		lw.irOwnedWordAt(v[0]) < 0:
		# a field's map (box): where it is, should it be given away
		if g.irMemPlace(lw, e) is (at, _):
			lw.wordPlaces[v[0]] = at
			root, below = g.c.placePath(e)
			if root is r:
				lw.places[at] = "{nodes[r].text}{below}"
				lw.f.places[at] = "{nodes[r].text}{below}"
		return v
	if v.len == 1 and g.irOwnedByAddress(g.ty(e)):
		root, below = g.c.placePath(e)
		if nodes[e].hasFlag(flagFromBase):
			lw.fromBase.push(v[0])
		if root is r and v[0] not in lw.places:   # (a borrow's name: the place it borrows)
			lw.places[v[0]] = "{nodes[r].text}{below}"
			lw.f.places[v[0]] = "{nodes[r].text}{below}"
	v

# a value of type t kept elsewhere (its leaves, its address or its word) as a temporary of its
# own: a deep copy where it owns memory
fn irOwnedCopyOf(mut g Gen, mut lw IrLower, t TypeId, move value i64[]):
	if not g.isOwningType(t) or value.len != 1: return value
	if g.irIsOwnedWord(t):
		word = g.irWordCopied(lw, t, value[0])
		g.irOwnedWord(lw, t, word)
		return [word]
	if g.irOwnedByAddress(t): return [g.irOwnedCopy(lw, t, value[0])]
	value

# a value of type t put at addr (nothing there to drop): leaves stored, an owned value moved in,
# anything else that owns nothing copied
fn irPutValue(mut g Gen, mut lw IrLower, addr i64, t TypeId, value i64[]):
	if g.irIsOwnedWord(t):
		given = g.irGivenWord(lw, t, value[0]) if value.len == 1 else -1
		if given < 0:
			lw.irFail("a map stored, not owned here")
			return
		lw.irPut(IrInst(op = irStore, a = addr, c = given))
	elif g.irTakes(t):
		g.irStoreLeaves(lw, t, addr, -1, 1, 0, value)
	elif g.irOwnedByAddress(t):
		g.irPutOwned(lw, addr, t, value, false)
	elif g.irByAddress(t) and value.len == 1:
		lw.irPut(IrInst(op = irMemCopy, a = addr, b = value[0], imm = g.sizeOf(t)))
	else:
		lw.irFail("a value of {typeStr(tys, t)} put in memory")

# where the arms of a choice of type t leave their value: leaves, or a slot
fn irNewResult(mut g Gen, mut lw IrLower, t TypeId) i64[]:
	g.irNewValue(lw, t) if g.irTakes(t) else [g.irResultSlot(lw, t)]

# an arm's value as the choice's result (irNewResult's)
fn irArmInto(mut g Gen, mut lw IrLower, t TypeId, result i64[], value i64[]):
	if g.irTakes(t):
		if g.irIsOwnedWord(t) and value.len == 1:
			given = g.irGiveWord(lw, value[0])   # a box (a map) made in the arm: the result's (irArmsOwn)
			lw.irCopyValue(result, [given if given >= 0 else value[0]])
		else:
			lw.irCopyValue(result, value)
	else:
		lw.choosing = true   # (a place an arm picks is read through the choice)
		g.irPutValue(lw, result[0], t, value)
		lw.choosing = false

# whether t owns memory and is reached by address (a str, a list, a struct that owns)
fn irOwnedByAddress(mut g Gen, t TypeId):
	g.isOwningType(t) and g.irByAddress(t)

# the owned value at from moved to the address to: its bytes copied, zeroed where they were
# the value at from, which this code owns, moved to `to`, and left empty; a temporary made last
# is given up too (nothing drops it)
fn irMoveTo(mut g Gen, mut lw IrLower, to i64, from i64, t TypeId):
	g.irMoveAs(lw, to, from, t, ownReturned if to == lw.hidden else ownMoved)

# irMoveTo with how the value goes (ownMoved...): a local moved whole is consumed so (its drop
# then frees nothing), unless a written `move` leaves it usable, empty
fn irMoveAs(mut g Gen, mut lw IrLower, to i64, from i64, t TypeId, how i64):
	lw.irPut(IrInst(op = irMemCopy, a = to, b = from, imm = g.sizeOf(t), cond = 1, ty = t))
	n = lw.owned.len
	given = n > 0 and lw.owned[n - 1].slot == from and lw.owned[n - 1].name < 0 and
		lw.owned[n - 1].word < 0
	if given:
		lw.owned.pop()   # emptied below all the same: made again in a loop, the slot must hold no room to reuse
	local = -1 if given else lw.owned.findIndex(.slot == from and .name >= 0) ?? -1
	if local >= 0:
		# a local's value went with its bytes (a written `move` of a mut local leaves it its
		# type's empty value, its own again)
		lw.irArenaMoved(from)
		lw.irPut(IrInst(op = irOwnEnd, a = from, cond = how, imm = 1 if lw.moveWritten else 0))
	g.irEmptyAt(lw, from, t)
	if given:
		lw.irConsumed(from, how)
	elif local >= 0 and lw.keepEmptied:
		o = lw.owned[local].copy()
		lw.irPut(IrInst(op = irOwn, a = from, b = o.word, imm = i64(o.t), key = o.key.copy()))
