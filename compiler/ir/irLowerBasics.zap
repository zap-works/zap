# The lowering's helpers: emitting, the kinds of a type, options, niches, leaves and names (irLower.zap).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# where an inlined body's return goes
type IrReturn:
	leaves i64[]
	end i64
	t TypeId   # the body's result type
	owned i64   # the owned values before the body (a return drops those after)
	arenas i64 = 0   # the arena blocks open before the body (a return closes those after)
	runtime bool = false   # a body of the runtime's (irInlinesAs)
	written bool = false   # inlined for a call the program's own code wrote
	lambda bool = false   # a lambda's body in place, not a function's (it takes the two above from where it is)

irInlineNodes = 24   # the largest body inlined, in nodes
irProgramInlineNodes = 40   # the largest body a program's code inlines, a runtime one only outside a loop (in one it grows the loop: brainfudge's push)
irInlineDepth = 1
irLoopInlineNodes = 48   # a program's body with no loop, called in a loop of the program's (irInlinesAs)
# the runtime's bodies inlined into each other: larger, and a small one into an inlined one too
irRuntimeInlineNodes = 48
irRuntimeInlineDepth = 3
irRuntimeNestedNodes = 16
irHotInlineNodes = 240   # a runtime body with a loop, called in a loop of the program's (irInlinesAs)
irHotInlineDepth = 3
irTinyNodes = 28   # a body inlined at any depth when it calls nothing (irInlinesAs)
irInlineBlocks = 200   # once the bodies inlined into a function made this many blocks, only the small
# ones that call nothing are: bodies nest geometrically

fn irFail(mut lw IrLower, why str):
	if lw.ok:
		lw.ok = false
		lw.why = "{why} (line {lw.line})"

# irFail for a Seq's walk no generator's call makes, and the walk
fn irWalkRefused(mut lw IrLower, move each IrEach):
	lw.irFail("a walk of a Seq no generator's call makes")
	each

# no leaves, typed (a unit's value, a failed lowering's) where an optional's is given
fn irNoLeaves() i64[]:
	[]

# irFail, and no leaves (`f = find() ?? return lw.irRefused("...")`)
fn irRefused(mut lw IrLower, why str) i64[]:
	lw.irFail(why)
	[]

fn irPut(mut lw IrLower, move inst IrInst):
	i = inst
	i.line = i32(lw.line)
	i.col = i32(lw.col)
	i.foreign = lw.foreign > 0
	lw.f.irAppend(i)

# inst put with a fresh vreg of class as its dst: the vreg
fn irDef(mut lw IrLower, class i64, move inst IrInst):
	v = lw.f.irVreg(class)
	i = inst
	i.dst = v
	lw.irPut(i)
	v

# the address of bytes of the frame (zeroed when the function starts)
fn irNewSlot(mut lw IrLower, bytes i64) i64:
	lw.irDef(irInt, IrInst(op = irFrameSlot, imm = bytes))

# a branch to yes when a cond b, else to no
fn irBranchIf(mut lw IrLower, a i64, cond i64, b i64, yes i64, no i64, uns bool = false):
	lw.irPut(IrInst(op = irBranch, a, b, cond = i32(cond), uns, target = yes, other = no))

# a branch to yes when v is not zero, else to no
fn irBranchNZ(mut lw IrLower, v i64, yes i64, no i64):
	lw.irBranchIf(v, irNe, lw.irConstOf(irInt, 0), yes, no)

# a choice on whether v is not zero, filling its yes way; with both false, no way but the end
fn irSplitNZ(mut lw IrLower, v i64, both bool = true):
	way = lw.f.irSplit(both)
	lw.irBranchNZ(v, way.yes, way.no if both else way.end)
	lw.f.irEnter(way.yes)
	way

# a choice on the condition e, filling its yes way
fn irSplitIf(mut g Gen, mut lw IrLower, e NodeId):
	way = lw.f.irSplit(true)
	g.irCond(lw, e, way.yes, way.no)
	lw.f.irEnter(way.yes)
	way

# ---------- types ----------

# the class of a scalar of type t, or -1 when the intermediate form does not take it
fn irClassOf(g Gen, maybeT TypeId?):
	t = maybeT ?? return -1
	k = tys[t].kind
	if k in [tBool, tInt, tMap, tBox]: return irInt   # a map (a box) is a pointer to its table (value)
	if k == tRef and not g.c.refIsWindow(t): return irInt   # a reference: the address of its target
	if k == tFloat: return irFloat   # an f32 travels as the f64 of its value
	if k == tOption and g.c.isNicheOption(t): return irInt   # an address, 0 for none
	if k in [tSimd, tBytes, tVec]: return irVec
	-1

fn irIsF32(g Gen, maybeT TypeId?):
	t = maybeT ?? return false
	tys[t].kind == tFloat and tys[t].bits == 32

# v as a value of type t: rounded to single when t is an f32 (an f32 travels as its f64)
fn irRounded(mut g Gen, mut lw IrLower, v i64, t TypeId) i64:
	if not g.irIsF32(t): return v
	lw.irDef(irFloat, IrInst(op = irRoundF32, a = v))

# v as a call's argument for a parameter of type t: an f32's slot holds the single's bits
fn irArgBits(mut g Gen, mut lw IrLower, v i64, t TypeId) i64:
	if not g.irIsF32(t): return v
	lw.irDef(irInt, IrInst(op = irF32Bits, a = v))

fn irSigned(g Gen, t TypeId):
	tys[t].kind == tInt and tys[t].isSigned

fn irUnsigned(g Gen, t TypeId):
	tys[t].kind == tInt and not tys[t].isSigned

# whether t is a list: of values the form reads as leaves, or of things it reaches by address
fn irIsList(mut g Gen, maybeT TypeId?):
	t = maybeT ?? return false
	tys[t].kind == tList and (g.irTakes(tys[t].inner) or g.irByAddress(tys[t].inner))

# whether t is a struct of numbers and bools (structs of them nested), small
fn irIsAggregate(mut g Gen, maybeT TypeId?) bool:
	t = maybeT ?? return false
	if g.aggregate.get(t) is known: return known
	aggregate = g.irIsAggregateOf(t)
	if g.c.subst.names.isEmpty:
		g.aggregate[t] = aggregate
	aggregate

fn irIsAggregateOf(mut g Gen, t TypeId) bool:
	if g.irIsPlainEnum(t): return true   # its leaf the variant's number
	if g.irIsVector(t): return true   # its leaf the vector (irVec.zap)
	if tys[t].kind != tStruct or not g.smallPlain(t) or
		nodes[declOf(tys, t)].hasFlag(flagShared):
		return false
	sd = declOf(tys, t)
	(0..g.c.nodes[sd].kids(g.c.kidIds).len).all(i:
		g.irClassOf(g.c.structFieldTypeAt(sd, i)) >= 0 or
			g.irIsAggregate(g.c.structFieldTypeAt(sd, i))
	)

# whether t is a struct the form reaches by its address: one that is not all numbers (not
# copied: its fields read and written in memory, those that own memory as places)
fn irIsPlaceStruct(mut g Gen, maybeT TypeId?):
	t = maybeT ?? return false
	tys[t].kind == tStruct and not g.irIsAggregate(t)

# whether values of type t are an address: a list, a str, a place struct, a str's window
fn irByAddress(mut g Gen, maybeT TypeId?) bool:
	t = maybeT ?? return false
	k = tys[t].kind
	k in [tList, tStr, tFn, tArray] or g.irIsPlaceStruct(t) or g.irIsCarryingEnum(t) or
		g.irIsWindow(t) or g.irIsTaggedOption(t) or g.irIsResult(t)

# whether a value of type t is a pointer to what it holds (a box, a reference): the place of
# what it holds is the pointer, never where the value itself is kept
fn irPointsAway(g Gen, maybeT TypeId?):
	g.tyK(maybeT) == tBox or g.tyK(maybeT) == tRef

# whether t is an enum whose variants carry no values: one leaf, the variant's number (its tag,
# enumTagSize bytes)
fn irIsPlainEnum(g Gen, maybeT TypeId?):
	t = maybeT ?? return false
	tys[t].kind == tEnum and not g.c.enumCarries(t)

# whether t is an enum some variant of which carries values: in memory, the variant's number then
# its values (variantFieldOffsets), reached by address
fn irIsCarryingEnum(g Gen, maybeT TypeId?):
	t = maybeT ?? return false
	tys[t].kind == tEnum and not g.irIsPlainEnum(t)

# whether t is an optional of a value the form takes that is not a scalar: in memory, a tag byte
# (0 none, 1 some) then the value at its alignment, or without a tag the value alone (layout.zap)
fn irIsTaggedOption(mut g Gen, maybeT TypeId?) bool:
	t = maybeT ?? return false
	if tys[t].kind != tOption or g.c.isNicheOption(t) or g.irIsOption(t): return false
	inner = tys[t].inner ?? return false
	tys[inner].kind != tUnit and (g.irByAddress(inner) or g.irTakes(inner))

# whether t is a window over a str's bytes or a list's elements (`ref str`, `ref T[]`: { ptr,
# length }, read where a str's or a list's header is, owning nothing)
fn irIsWindow(g Gen, t TypeId):
	g.c.refIsWindow(t) and (tys[innerOf(tys, t)].kind == tStr or tys[innerOf(tys, t)].kind == tList)

# whether t is an optional scalar (a tag, then the value)
# whether a read parameter of type t gets the address of a copy of its leaves (the ABI passes
# what is not a scalar by address): a struct of numbers, an optional of a number or of a box
fn irLentAsCopy(mut g Gen, t TypeId?):
	g.irIsAggregate(t) or g.irIsOption(t) or g.c.isNicheOption(t)

# whether a match on a t is an optional's: an optional of a number, one in memory, a box's
fn irMatchesAsOption(mut g Gen, t TypeId?):
	g.irIsOption(t) or g.irIsTaggedOption(t) or g.c.isNicheOption(t)

fn irIsOption(mut g Gen, maybeT TypeId?):
	t = maybeT ?? return false
	tys[t].kind == tOption and not g.c.isNicheOption(t) and
		g.irClassOf(tys[t].inner) >= 0

# whether t is an optional the form holds in vregs: a tag and a scalar, or a word without a tag
fn irIsLeafOption(mut g Gen, t TypeId?):
	g.irIsOption(t) or g.c.isNicheOption(t)

# e's value as an optional's tag and value (irIsLeafOption): a word without a tag is the value,
# its tag whether it is not the absent word
fn irOptionParts(mut g Gen, mut lw IrLower, e NodeId):
	o = g.irValue(lw, e)
	if o.len == 1 and g.c.isNicheOption(g.ty(e)): return [g.irTagOf(lw, g.ty(e), o[0]), o[0]]
	o

# an optional's tag and value as a value of t: a word without a tag is the value or the absent word
fn irOptionOf(mut g Gen, mut lw IrLower, t TypeId, tag i64, value i64):
	if not g.c.isNicheOption(t): return [tag, value]
	[g.irNicheWord(lw, t, tag, value)]

# the first word of optional t when it is none (layout.zap's optionAbsent), a constant
fn irAbsent(mut g Gen, mut lw IrLower, t TypeId) i64:
	lw.irConstOf(irInt, g.c.optionAbsent(t))

# the tag (0 none) of optional t from its first word: the word itself where none is 0, else
# whether it is not the absent word
fn irTagOf(mut g Gen, mut lw IrLower, t TypeId, word i64):
	if g.c.optionAbsent(t) == 0: return word
	tag = lw.f.irVreg(irInt)
	g.irNicheTagOf(lw, t, word, tag)
	tag

# a leaf option's tag (a bool, stored as a byte) of a tag that is any word but 0 for some
fn irBoolOf(mut lw IrLower, tag i64):
	b = lw.f.irVreg(irInt)
	lw.irPut(IrInst(op = irSet, dst = b, a = tag, b = lw.irConstOf(irInt, 0), cond = irNe))
	b

# the bits of a value's tag spot (layout.zap's TagSpot) in memory at a, read unsigned
fn irSpotAt(mut lw IrLower, spot TagSpot, a i64) i64:
	lw.irDef(irInt, IrInst(op = irLoad, a, imm = spot.off, size = i32(spot.size), uns = true))

# a value's tag spot in memory at a set to v
fn irSetSpot(mut lw IrLower, spot TagSpot, a i64, v i64):
	lw.irPut(
		IrInst(op = irStore, a, c = lw.irConstOf(irInt, v), imm = spot.off, size = i32(spot.size))
	)

# the tag of the optional of type t in memory at a: 0 none (its tag, or whether its niche holds
# something but the absent value)
fn irTagAt(mut g Gen, mut lw IrLower, t TypeId, a i64):
	spot = g.c.optionTag(t)
	word = lw.irSpotAt(spot, a)
	if spot.absent == 0: return word
	tag = lw.f.irVreg(irInt)
	absent = lw.irConstOf(irInt, spotBits(spot.absent, spot.size))
	lw.irPut(IrInst(op = irSet, dst = tag, a = word, b = absent, cond = irNe))
	tag

# the optional t at slot, zeroed, made none: its niche's absent value where that is not 0
fn irMarkNone(mut g Gen, mut lw IrLower, t TypeId, slot i64):
	spot = g.c.optionTag(t)
	if spot.absent != 0:
		lw.irSetSpot(spot, slot, spot.absent)

# the optional t at slot made some, its value put after: its tag 1 (without a tag the value says it)
fn irMarkSome(mut g Gen, mut lw IrLower, t TypeId, slot i64):
	if not g.c.isTaglessOption(t):
		lw.irSetSpot(g.c.optionTag(t), slot, 1)

# irResultSlot zeroed
fn irZeroedSlot(mut g Gen, mut lw IrLower, t TypeId):
	slot = g.irResultSlot(lw, t)
	g.irZeroSlot(lw, slot, t)
	slot

# the optional t at slot made some: the address its value goes to
fn irSomeAt(mut g Gen, mut lw IrLower, t TypeId, slot i64) i64:
	g.irMarkSome(lw, t, slot)
	g.irPayloadAt(lw, t, slot)

# the tag of the optional t at a and its value's address
fn irOptionAt(mut g Gen, mut lw IrLower, t TypeId, a i64):
	(g.irTagAt(lw, t, a), g.irPayloadAt(lw, t, a))

# the address of the value of the optional t at a: where the value starts the optional (no tag)
# and owns, a register of its own, so the ownership pass tells a borrow of the value from its
# owner; plain bytes are bound where they are, a's own register
fn irPayloadAt(mut g Gen, mut lw IrLower, t TypeId, a i64) i64:
	off = g.c.optionPayload(t)
	if off != 0 or not g.isOwningType(innerOf(tys, t)): return lw.irElementAddr(a, -1, 0, off)
	lw.irDef(irInt, IrInst(op = irCopy, a))

# none of an optional in one word: its absent word, owned (its drop frees nothing) when t owns
fn irNoneWord(mut g Gen, mut lw IrLower, t TypeId):
	w = lw.irDef(irInt, IrInst(op = irConst, imm = g.c.optionAbsent(t)))
	if g.irIsOwnedWord(t):
		g.irOwnedWord(lw, t, w)   # bound or stored as any box
	w

# t's empty value (`move` leaves it, `mut x T` starts from it) in leaves: zeros, an optional's none
fn irEmptyLeaves(mut g Gen, mut lw IrLower, t TypeId):
	g.irLeafTypes(t).map(
		lw.irConstOf(g.irClassOf(it), g.c.optionAbsent(it) if g.tyK(it) == tOption else 0)
	)

# t's empty value at slot: zero bytes, but an optional's (or an array's optionals') absent value
fn irEmptyAt(mut g Gen, mut lw IrLower, slot i64, t TypeId):
	insts = g.irEmptyingAt(lw.f, slot, t, lw.line, lw.col)
	for i in 0..insts.len:
		lw.f.irAppend(insts[i].copy())

# the instructions that leave t's empty value at address slot (irEmptyAt), their constants made
# in f
fn irEmptyingAt(mut g Gen, mut f IrFn, slot i64, t TypeId, line i64, col i64):
	out = []
	zero = f.irVreg(irInt)
	out.push(IrInst(op = irConst, dst = zero, imm = 0, line = i32(line), col = i32(col)))
	at = 0
	end = g.sizeOf(t)
	while at < end:
		size = 8
		while at + size > end:
			size /= 2
		out.push(
			IrInst(
				op = irStore,
				a = slot,
				c = zero,
				imm = at,
				size,
				line = i32(line),
				col = i32(col)
			)
		)
		at += size
	array = g.tyK(t) == tArray
	elem = innerOf(tys, t) if array else t
	if g.tyK(elem) != tOption: return out
	spot = g.c.optionTag(elem)
	if spot.absent == 0: return out
	stride = g.c.elemStride(elem)
	absent = f.irVreg(irInt)
	out.push(
		IrInst(op = irConst, dst = absent, imm = spot.absent, line = i32(line), col = i32(col))
	)
	for i in 0..(tys[t].bits if array else 1):
		out.push(
			IrInst(
				op = irStore,
				a = slot,
				c = absent,
				imm = i * stride + spot.off,
				size = i32(spot.size),
				line = i32(line),
				col = i32(col)
			)
		)
	out

# whether the form takes a value of type t
fn irTakes(mut g Gen, maybeT TypeId?):
	t = maybeT ?? return false
	tys[t].kind == tUnit or g.irClassOf(t) >= 0 or g.irIsAggregate(t) or g.irIsOption(t)

# a scalar leaf of a value: its type and its offset in the value's memory
type IrLeaf:
	t TypeId
	off i64

# the leaves of a value of type t, their offsets from base
fn irLeaves(mut g Gen, t TypeId, base i64):
	out = []
	g.irLeavesInto(t, base, out)
	out

fn irLeavesInto(mut g Gen, t TypeId, base i64, mut out IrLeaf[]):
	if tys[t].kind == tUnit: return
	if g.c.scalarNicheAbsent(t) != none:
		out.push(IrLeaf(t = g.irNicheTag(t), off = base))   # the tag, read from the value's bytes
		out.push(IrLeaf(t = innerOf(tys, t), off = base))
		return
	if tys[t].kind == tOption and not g.c.isNicheOption(t):
		out.push(IrLeaf(t = tyBool, off = base))   # the tag: 1 when there is a value
		out.push(IrLeaf(t = innerOf(tys, t), off = base + g.c.optionPayload(t)))
		return
	if tys[t].kind == tEnum:
		bits = 8 * g.c.enumTagSize(declOf(tys, t))
		out.push(IrLeaf(t = tyInt(bits, false), off = base))   # the variant's number
		return
	if tys[t].kind != tStruct:
		out.push(IrLeaf(t, off = base))
		return
	sd = declOf(tys, t)
	fo = g.c.structFieldOffsets(sd)
	for i in 0..g.c.nodes[sd].kids(g.c.kidIds).len:
		g.irLeavesInto(g.c.structFieldTypeAt(sd, i), base + fo[i], out)

# the leaf type of the tag of t, an optional of a range (tyNicheTag), made once
fn irNicheTag(mut g Gen, t TypeId):
	key = "niche {t}"
	if g.c.rangeTypes.get(key) is tag:
		g.noteTypeAsk(keptNiche, [i64(t)], tag, false)
		return tag
	tag = tyNicheTag(tys, t)
	g.c.rangeTypes[key] = tag
	g.noteTypeAsk(keptNiche, [i64(t)], tag, true)
	tag

# whether leaf type t is the tag of an optional of a range or a bool, kept in its value's bytes
fn irIsNicheTag(g Gen, t TypeId):
	tys[t].kind == tBool and tys[t].inner != none

# the word the value of an optional without a tag (a range's or a bool's, opt) holds for none
fn irAbsentWord(mut g Gen, opt TypeId) i64:
	g.c.scalarNicheAbsent(opt) ?? g.c.optionAbsent(opt)

# the tag of an optional without a tag (a range's or a bool's, opt) read from its value's word: 1
# unless it is the absent word
fn irNicheTagOf(mut g Gen, mut lw IrLower, opt TypeId, word i64, dst i64):
	absent = lw.irConstOf(irInt, g.irAbsentWord(opt))
	lw.irPut(IrInst(op = irSet, dst, a = word, b = absent, cond = irNe))

# the word an optional without a tag (a range's or a bool's, opt) holds for its tag and value: the
# value, or the absent word
fn irNicheWord(mut g Gen, mut lw IrLower, opt TypeId, tag i64, value i64):
	absent = lw.irConstOf(irInt, g.irAbsentWord(opt))
	w = lw.f.irVreg(irInt)
	zero = lw.irConstOf(irInt, 0)
	lw.irPut(IrInst(op = irSelect, dst = w, a = tag, b = zero, c = value, d = absent, cond = irNe))
	w

fn irLeafTypes(mut g Gen, t TypeId):
	g.irLeaves(t, 0).map(.t)

# field fi of struct t: its first leaf and how many it has
fn irFieldSpan(mut g Gen, t TypeId, fi i64):
	sd = declOf(tys, t)
	start = 0
	for i in 0..fi:
		start += g.irLeafTypes(g.c.structFieldTypeAt(sd, i)).len
	(start, g.irLeafTypes(g.c.structFieldTypeAt(sd, fi)).len)

# new vregs for a value of type t
fn irNewValue(mut g Gen, mut lw IrLower, t TypeId):
	g.irLeafTypes(t).map(g.irLeafVreg(lw, it))

# a value as one of type t: a plain value where an optional is wanted gets its tag
fn irAs(mut g Gen, mut lw IrLower, value i64[], t TypeId):
	if not g.irIsOption(t) or value.len != 1: return value.copy()
	some = [lw.irConstOf(irInt, 1)]
	some.extend(value)
	some

fn irCopyValue(mut lw IrLower, dst i64[], src i64[]):
	if dst.len != src.len:
		lw.irFail("a value of {src.len} leaves where {dst.len} are wanted")
		return
	for i in 0..dst.len:
		lw.irPut(IrInst(op = irCopy, dst = dst[i], a = src[i]))

# ---------- names ----------

# whether name is a local of the form in scope
fn irInScope(lw IrLower, name str):
	lw.irLookupAt(name) >= 0

fn irInScopeNo(lw IrLower, no i64):
	lw.irLookupAtNo(no) >= 0

fn irLookup(lw IrLower, name str):
	lw.irLookupNo(interned.numberOf(name))

# irLookup of the name numbered no
fn irLookupNo(lw IrLower, no i64) i64[]?:
	i = lw.irLookupAtNo(no)
	if i < 0: return none
	lw.vals[i].copy()

# the index of a name's innermost declaration in scope, or -1
fn irLookupAt(lw IrLower, name str):
	lw.irLookupAtNo(interned.numberOf(name))

# irLookupAt of the name numbered no
fn irLookupAtNo(lw IrLower, no i64):
	i = lw.nameIndex.lastOf(no)
	i if i >= lw.floor else -1

# a name's leaves: a local of the form
fn irFind(mut g Gen, mut lw IrLower, name str):
	lw.irLookup(name)

fn irDeclare(mut lw IrLower, name str, move leaves i64[]):
	lw.irDeclareNo(interned.numbered(name), leaves)

# irDeclare of the name numbered no
fn irDeclareNo(mut lw IrLower, no i64, move leaves i64[]):
	if lw.arenas > 0:
		lw.nameLevel[lw.names.len] = lw.arenas
	else:
		lw.nameLevel.remove(lw.names.len)
	if lw.held.remove(lw.names.len) != none:
		lw.borrowOf.remove(lw.names.len)   # (what an earlier name at the index borrowed)
		lw.exclusive.remove(lw.names.len)
	lw.nameIndex.noteName(no, lw.names.len)
	lw.names.push(no)
	lw.vals.push(leaves)

# a scope's end: its owned locals dropped (when the code still runs here), its names gone
fn irScopeEnd(mut g Gen, mut lw IrLower, mark i64):
	g.irForgetNames(lw, mark)

fn irScopeEndDropping(mut g Gen, mut lw IrLower, mark i64):
	if not lw.f.irEnded():
		g.irDropLocals(lw, mark)
	g.irForgetNames(lw, mark)

fn irForgetNames(mut g Gen, mut lw IrLower, mark i64):
	for k in lw.keptInner:
		if k.root >= mark and k.holder < mark:
			g.irOwnError(
				g.irFileNow.copy(),
				k.line,
				k.col,
				compileError(
					"RefOutlivesLocal",
					[
						interned.texts[lw.names[k.holder]].copy(),
						interned.texts[lw.names[k.root]].copy()
					]
				)
			)
	lw.keptInner = lw.keptInner.filter(.root < mark)
	lw.mutNames = lw.mutNames.filter(it < mark)
	i = lw.names.len - 1
	while i >= mark:
		lw.nameIndex.forgetName(lw.names[i])
		i -= 1
	lw.names.truncate(mark)
	lw.vals.truncate(mark)
	lw.owned = lw.owned.filter(.name < mark)
	lw.given = lw.given.filter(.at < mark)

fn irConstOf(mut lw IrLower, class i64, value i64) i64:
	lw.irDef(class, IrInst(op = irConst, imm = value))

# ---------- functions ----------
