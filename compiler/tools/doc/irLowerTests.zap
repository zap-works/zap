# The lowering of choices, matches and conditions (irLower.zap).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# a choice of a value that owns memory, by address: each arm's value moved into one slot (a
# temporary of the statement); both literals: their headers copied (the slot a literal too). An
# arm that lends a place is not taken.
# whether the choice e only lends the place its condition picks (both arms places, marked by the
# ownership pass): its value is the place's own, never owned or freed by the reader
fn irLentChoice(mut g Gen, lw IrLower, e NodeId):
	arms = [
		nodes[nodes[e].kids(kidIds)[1]].kids(kidIds)[1],
		nodes[nodes[e].kids(kidIds)[2]].kids(kidIds)[1]
	]
	(g.irMatchLends(lw, e) or g.irPlaceChoice(lw, e)) and arms.all(g.irIsPlaceNode(it))

fn irOwnedChoice(mut g Gen, mut lw IrLower, e NodeId, t TypeId):
	arms = [
		nodes[nodes[e].kids(kidIds)[1]].kids(kidIds)[1],
		nodes[nodes[e].kids(kidIds)[2]].kids(kidIds)[1]
	]
	literals = arms.all(nodes[it].kind == nStr)
	if not literals and (g.irMatchLends(lw, e) or g.irPlaceChoice(lw, e)) and
		arms.all(g.irIsPlaceNode(it)):
		# both arms places, lent: the address of the one chosen
		at = lw.f.irVreg(irInt)
		yes = lw.f.irBlock()
		no = lw.f.irBlock()
		done = lw.f.irBlock()
		g.irCond(lw, nodes[e].kids(kidIds)[0], yes, no)
		for i in 0..2:
			lw.f.irEnter(yes if i == 0 else no)
			lw.irPut(IrInst(op = irCopy, dst = at, a = g.irListAddr(lw, arms[i])))
			lw.f.irJumpTo(done)
		lw.f.irEnter(done)
		return [at]
	slot = -1
	if literals:
		# a literal's header (room 0): a slot that owns nothing, named by a let as literals are
		slot = lw.irNewSlot(g.sizeOf(t))
	else:
		slot = g.irTemporary(lw, t)
	yesB = lw.f.irBlock()
	noB = lw.f.irBlock()
	endB = lw.f.irBlock()
	g.irCond(lw, nodes[e].kids(kidIds)[0], yesB, noB)
	before = lw.owned.copy()
	ends = []
	for i in 0..2:
		lw.owned = before.copy()
		lw.f.irEnter(yesB if i == 0 else noB)
		value = g.irValue(lw, arms[i])
		if not lw.f.irEnded() and value.len == 1 and g.irIsPlaceNode(arms[i]):
			lw.irPut(IrInst(op = irDeepCopy, a = slot, b = value[0], ty = t))   # the place keeps its own
		elif not lw.f.irEnded() and not g.irNever(arms[i]):   # (an arm that fails gives no value)
			lw.choosing = true   # a choice read where it is: a window copied into it is no value given
			g.irPutOwned(lw, slot, t, value, false)
			lw.choosing = false
		lw.irBranchEnd(ends)
	g.irJoinOwned(lw, before, ends, endB)
	lw.f.irEnter(endB)
	if literals:
		lw.literals.push(slot)
	[slot]

# the index of the variant of enum type et the field e names (`Enum.Variant`, `.Variant`), or -1
# when e is no variant
fn irVariantOf(mut g Gen, e NodeId, et TypeId):
	if nodes[e].kind != nField or g.tyK(et) != tEnum: return -1
	if not nodes[e].hasFlag(flagDotVariant) and
		(nodes[e].kids(kidIds).isEmpty or g.enumNamed(nodes[e].kids(kidIds)[0], et) == none):
		return -1
	nodes[declOf(tys, et)].kids(kidIds).findIndex(nodes[it].text == nodes[e].text) ?? -1

# a variant's value: a plain enum's number; a carrying one in a slot (a temporary when it owns),
# its number then each value at its offset
fn irVariant(mut g Gen, mut lw IrLower, field NodeId, t TypeId, args NodeId[]):
	ed = declOf(tys, t)
	vi = nodes[ed].kids(kidIds).findIndex(nodes[it].text == nodes[field].text) ?? -1
	if vi < 0: return lw.irRefused("variant {nodes[field].text}")
	if g.irIsPlainEnum(t): return [lw.irConstOf(irInt, vi)]
	v = nodes[ed].kids(kidIds)[vi]
	if args.len != nodes[v].kids(kidIds).len or args.any(nodes[it].kind == nNamedArg):
		return lw.irRefused("the values of variant {nodes[v].text}")
	values = args.map(g.irValue(lw, it))   # read in the order written, before the slot fills
	if not lw.ok: return []
	slot = g.irZeroedSlot(lw, t)
	lw.irSetSpot(g.c.enumTag(ed), slot, vi)
	offs = g.c.variantFieldOffsets(ed, v)
	for i, value in values:
		ft = g.c.resolveType(nodes[nodes[v].kids(kidIds)[i]].types()[0])
		g.irPutValue(lw, lw.irElementAddr(slot, -1, 0, offs[i]), ft, value)
	[slot]

# a match's result slot (when its value is wanted), its end block and what the function owned
# before its arms
# a match's type: the checker's, or (a body's tail it left untyped) what the body gives
fn irMatchType(mut g Gen, lw IrLower, e NodeId):
	if g.irTyped(e) != none: return g.ty(e)
	lw.rets[len - 1].t if not lw.rets.isEmpty else lw.rt

fn irMatchOpen(mut g Gen, mut lw IrLower, e NodeId, want bool):
	result = g.irNewResult(lw, g.irMatchType(lw, e)) if want else []
	(result, lw.f.irBlock(), lw.owned.copy())

# a match once every arm is lowered: no arm taken falls to end (the checker saw every case
# covered), the arms' ownership joined there; its result (lent: the part of the place it picks,
# owned by the place)
fn irMatchClose(
	mut g Gen,
	mut lw IrLower,
	e NodeId,
	before IrOwned[],
	ends (IrOwned[], i64, bool)[],
	end i64,
	move result i64[],
	lent bool = false
):
	lw.f.irJumpTo(end)
	g.irJoinOwned(lw, before, ends, end)
	lw.f.irEnter(end)
	if not lent:
		g.irArmsOwn(lw, g.irMatchType(lw, e), result)
	result

# the arms' value of type t in result, a box (a map) each arm gave (irArmInto): owned here from now on
fn irArmsOwn(mut g Gen, mut lw IrLower, t TypeId, result i64[]):
	if result.len == 1 and g.irIsOwnedWord(t):
		g.irOwnedWord(lw, t, result[0])

# an arm once its names are bound (from mark): its condition (to nextB when false), its body's value
# into the match's result (lent: the address of the part it lends), the names of a mutable value's
# fields written back (written: name, address, type), its names dropped, what it owns kept for the
# join (irJoinOwned); filling continues at nextB, owning what the match owned before its arms
# (before)
fn irArmRest(
	mut g Gen,
	mut lw IrLower,
	e NodeId,
	arm NodeId,
	mark i64,
	nextB i64,
	before IrOwned[],
	mut ends (IrOwned[], i64, bool)[],
	result i64[],
	want bool,
	written IrArmWrite[],
	lent bool = false
):
	pat = nodes[arm].kids(kidIds)[0]
	guard NodeId? = nodes[pat].sub()[0] if not nodes[pat].sub().isEmpty else none
	if guard is guard:
		bodyB = lw.f.irBlock()
		g.irCond(lw, guard, bodyB, nextB)
		lw.f.irEnter(bodyB)
	body = nodes[arm].kids(kidIds)[1] if nodes[arm].kids(kidIds).len > 1 else nodes[arm].sub()[0]
	value = g.irBlockValue(lw, body, want)
	if want and not lw.f.irEnded() and not (value.isEmpty and g.irNever(body)):
		if not lent:
			g.irArmInto(lw, g.irMatchType(lw, e), result, value)
		elif value.len != 1 or lw.irOwns(value[0]):
			lw.irFail("a lent match's arm owns its value")
		else:
			lw.irPut(IrInst(op = irCopy, dst = result[0], a = value[0]))   # the part it lends
	if not lw.f.irEnded():
		for w in written:
			g.irStoreLeaves(lw, w.t, w.at, -1, 1, 0, g.irFind(lw, w.name) ?? [])
	g.irScopeEndDropping(lw, mark)
	lw.irBranchEnd(ends)
	lw.f.irEnter(nextB)
	lw.owned = before.copy()

# a choice of values by address that own nothing (windows, optionals of leaves): each arm's bytes
# copied into a slot of the statement
fn irWindowChoice(mut g Gen, mut lw IrLower, e NodeId, t TypeId):
	arms = [
		nodes[nodes[e].kids(kidIds)[1]].kids(kidIds)[1],
		nodes[nodes[e].kids(kidIds)[2]].kids(kidIds)[1]
	]
	slot = g.irResultSlot(lw, t)
	yesB = lw.f.irBlock()
	noB = lw.f.irBlock()
	endB = lw.f.irBlock()
	g.irCond(lw, nodes[e].kids(kidIds)[0], yesB, noB)
	for i in 0..2:
		lw.f.irEnter(yesB if i == 0 else noB)
		value = g.irValue(lw, arms[i])
		if not lw.ok: return []
		if value.len != 1: return lw.irRefused("a window of {value.len} leaves")
		if not lw.f.irEnded():
			lw.irPut(IrInst(op = irMemCopy, a = slot, b = value[0], imm = g.sizeOf(t)))
		lw.f.irJumpTo(endB)
	lw.f.irEnter(endB)
	[slot]

# whether match e is a choice by a bool (`c ? a : b`, an if used as a value): its arms true and
# anything else
# whether the match e has one arm, a name bound to the whole scrutinee and no condition: the
# checker's form for a temporary used twice (`T(..f(), x = 1)`, `f().zy`)
fn irIsBindMatch(mut g Gen, e NodeId):
	if nodes[e].kids(kidIds).len != 2: return false
	pat = nodes[nodes[e].kids(kidIds)[1]].kids(kidIds)[0]
	nodes[pat].ival == patBind and nodes[pat].text != "_" and nodes[pat].sub().isEmpty and
		nodes[pat].kids(kidIds).isEmpty

# that match: the name bound to the scrutinee as a let binds it, the arm's body the value, the
# name's scope the match
fn irBindMatch(mut g Gen, mut lw IrLower, e NodeId, want bool):
	arm = nodes[e].kids(kidIds)[1]
	pat = nodes[arm].kids(kidIds)[0]
	value = g.irValue(lw, nodes[e].kids(kidIds)[0])
	if not lw.ok: return []
	mark = lw.names.len
	g.irBindName(lw, pat, nodes[pat].text.copy(), nodes[e].kids(kidIds)[0], value)
	if not lw.ok: return []
	body = nodes[arm].kids(kidIds)[1] if nodes[arm].kids(kidIds).len > 1 else nodes[arm].sub()[0]
	v = g.irBlockValue(lw, body, want)
	if not lw.ok: return []
	out = v.copy()
	g.irScopeEndDropping(lw, mark)
	out

fn irIsChoice(g Gen, e NodeId):
	if nodes[e].kids(kidIds).len != 3 or nodes[e].text != "": return false
	yes = nodes[nodes[e].kids(kidIds)[1]].kids(kidIds)[0]
	no = nodes[nodes[e].kids(kidIds)[2]].kids(kidIds)[0]
	nodes[yes].ival == patLit and nodes[yes].kids(kidIds).len == 1 and
		nodes[nodes[yes].kids(kidIds)[0]].kind == nBool and
		nodes[nodes[yes].kids(kidIds)[0]].ival == 1 and
		nodes[no].ival == patWildcard

fn irChoice(mut g Gen, mut lw IrLower, e NodeId):
	t = g.ty(e)
	if g.irOwnedByAddress(t): return g.irOwnedChoice(lw, e, t)
	if g.irByAddress(t) and not g.isOwningType(t): return g.irWindowChoice(lw, e, t)
	if not g.irTakes(t): return lw.irRefused("choice of type {typeStr(tys, t)}")
	cond = nodes[e].kids(kidIds)[0]
	yes = nodes[nodes[e].kids(kidIds)[1]].kids(kidIds)[1]
	no = nodes[nodes[e].kids(kidIds)[2]].kids(kidIds)[1]
	ct = g.ty(nodes[cond].kids(kidIds)[0]) if nodes[cond].kind == nBinary and
		isCompareOp(nodes[cond].ival)
		else tyError
	if g.irClassOf(t) == irInt and g.irClassOf(ct) == irInt and g.irPlainOperand(yes) and
		g.irPlainOperand(no) and g.tyK(g.ty(yes)) != tRef and g.tyK(g.ty(no)) != tRef:
		# both sides cost nothing to read: both read, the comparison picks one (no branch)
		a = g.irExpr(lw, nodes[cond].kids(kidIds)[0])
		b = g.irExpr(lw, nodes[cond].kids(kidIds)[1])
		v = lw.f.irVreg(irInt)
		if g.irIsLiteral(yes, 1) and g.irIsLiteral(no, 0):
			# c ? 1 : 0 is the comparison's bool
			irPut(
				lw,
				IrInst(
					op = irSet,
					dst = v,
					a,
					b,
					cond = irCondOf(nodes[cond].ival),
					uns = g.irUnsigned(ct)
				)
			)
			return [v]
		y = g.irExpr(lw, yes)
		n = g.irExpr(lw, no)
		irPut(
			lw,
			IrInst(
				op = irSelect,
				dst = v,
				a,
				b,
				c = y,
				d = n,
				cond = irCondOf(nodes[cond].ival),
				uns = g.irUnsigned(ct)
			)
		)
		return [v]
	result = g.irNewValue(lw, t)
	yesB = lw.f.irBlock()
	noB = lw.f.irBlock()
	endB = lw.f.irBlock()
	g.irCond(lw, nodes[e].kids(kidIds)[0], yesB, noB)
	before = lw.owned.copy()
	ends = []
	for (block, arm) in [(yesB, nodes[e].kids(kidIds)[1]), (noB, nodes[e].kids(kidIds)[2])]:
		lw.owned = before.copy()
		lw.f.irEnter(block)
		armValue = nodes[arm].kids(kidIds)[1]
		# a reference to plain data (a for's `v` of `i, v`) read as the value it points to
		value = g.irDeref(lw, armValue) if nodes[armValue].kind != nBlock and
			g.tyK(g.ty(armValue)) == tRef and g.tyK(t) != tRef
			else g.irBlockValue(lw, armValue, true)
		if not lw.f.irEnded():
			g.irArmInto(lw, t, result, value)   # a box made in the arm: the result's
		lw.irBranchEnd(ends)
	g.irJoinOwned(lw, before, ends, endB)
	lw.f.irEnter(endB)
	if not g.irLentChoice(lw, e): g.irArmsOwn(lw, t, result)   # a lent place's box stays its own
	result

fn irIsLiteral(mut g Gen, e NodeId, value i64):
	nodes[e].kind == nInt and g.intLitValue(e) == value

# whether e names a place without making anything: a name, a field, an element, a borrow of one
fn irIsPlaceNode(g Gen, e NodeId) bool:
	k = nodes[e].kind
	if k == nIdent: return true
	if k == nDeref and nodes[e].hasFlag(flagInternal) and
		nodes[nodes[e].kids(kidIds)[0]].kind == nCall:
		return true   # g[x, y] of a grid: the cell its index lends
	if k in [nField, nIndex, nDeref]: return g.irIsPlaceNode(nodes[e].kids(kidIds)[0])
	k == nUnary and nodes[e].ival == unRef and g.irIsPlaceNode(nodes[e].kids(kidIds)[0])

# whether e is read with no work worth a branch: a literal, a name, a name plus a literal
fn irPlainOperand(g Gen, e NodeId):
	k = nodes[e].kind
	if k in [nInt, nBool, nIdent]: return true
	k == nBinary and (nodes[e].ival == binAdd or nodes[e].ival == binSub) and
		nodes[nodes[e].kids(kidIds)[0]].kind == nIdent and
		nodes[nodes[e].kids(kidIds)[1]].kind == nInt

# the type and offset, within the element of type elem at node at, of the place target (at
# itself, or fields of it)
fn irFieldPath(mut g Gen, target NodeId, at NodeId, elem TypeId) (TypeId, i64):
	if target == at: return (elem, 0)
	t, base = g.irFieldPath(nodes[target].kids(kidIds)[0], at, elem)
	sd = declOf(tys, t)
	fi = g.c.fieldIndexOf(sd, nodes[target].text)
	(g.c.structFieldTypeAt(sd, fi), base + g.c.structFieldOffsets(sd)[fi])

# ---------- conditions ----------

# a branch to yes when the bool e holds, else to no; && and || go by their own branches
fn irCond(mut g Gen, mut lw IrLower, e NodeId, yes i64, no i64):
	outer = lw.conditions == 0
	at = lw.owned.len
	from = lw.f.cur
	fromInst = lw.f.blocks[from].insts.len
	newBlocks = lw.f.blocks.len
	lw.conditions += 1
	g.irCondIn(lw, e, yes, no)
	lw.conditions -= 1
	if not outer or not lw.ok or lw.owned.len == at: return
	# the temporaries the condition made, dropped as it is left: its jumps to yes and no go
	# through a block that drops them first
	yesD = lw.f.irBlock()
	noD = lw.f.irBlock()
	made = [from]
	made.extend((newBlocks..yesD).map(it))
	for b in made:
		start = fromInst if b == from else 0
		for i in start..lw.f.blocks[b].insts.len:
			if isTerminator(lw.f.blocks[b].insts[i].op):
				lw.f.blocks[b].insts[i].target = irRetarget(
					lw.f.blocks[b].insts[i].target,
					yes,
					no,
					yesD,
					noD
				)
				lw.f.blocks[b].insts[i].other = irRetarget(
					lw.f.blocks[b].insts[i].other,
					yes,
					no,
					yesD,
					noD
				)
				if lw.f.blocks[b].insts[i].op == irSwitch:
					k = lw.f.blocks[b].insts[i].imm
					cases = lw.f.switches[k].targets.map(irRetarget(it, yes, no, yesD, noD))
					lw.f.switches[k].targets = cases
	for (d, to) in [(yesD, yes), (noD, no)]:
		lw.f.irEnter(d)
		g.irDropFrom(lw, at)
		lw.f.irJumpTo(to)
	lw.owned.truncate(at)

fn irRetarget(b i64, yes i64, no i64, yesD i64, noD i64):
	yesD if b == yes else noD if b == no else b

fn irCondIn(mut g Gen, mut lw IrLower, e NodeId, yes i64, no i64):
	if not lw.ok: return
	k = nodes[e].kind
	if g.irCondInLogic(lw, e, k, yes, no): return
	if g.irCondInPresence(lw, e, k, yes, no): return
	if g.irCondInCompare(lw, e, k, yes, no): return
	v = g.irExpr(lw, e)
	zero = lw.irConstOf(irInt, 0)
	lw.irBranchIf(v, irNe, zero, yes, no)

# not, and, or and a single bit test; true when e was lowered
fn irCondInLogic(mut g Gen, mut lw IrLower, e NodeId, k i64, yes i64, no i64) bool:
	if k == nUnary and nodes[e].ival == unNot:
		g.irCond(lw, nodes[e].kids(kidIds)[0], no, yes)
		return true
	if k == nBinary and nodes[e].ival == binOr and g.irCondInMembership(lw, e, yes, no): return true
	if k == nBinary and (nodes[e].ival == binAnd or nodes[e].ival == binOr):
		mid = lw.f.irBlock()
		if nodes[e].ival == binAnd:
			g.irCond(lw, nodes[e].kids(kidIds)[0], mid, no)
		else:
			g.irCond(lw, nodes[e].kids(kidIds)[0], yes, mid)
		lw.f.irEnter(mid)
		g.irCond(lw, nodes[e].kids(kidIds)[1], yes, no)
		return true
	if g.irBitTested(e):
		# (x & (1 << k)) != 0 or == 0: the bit tested itself
		mask = nodes[e].kids(kidIds)[0]
		shift = nodes[mask].kids(kidIds)[1]
		x = g.irExpr(lw, nodes[mask].kids(kidIds)[0])
		bit = g.irExpr(lw, g.irBitIndex(nodes[shift].kids(kidIds)[1]) ?? return true)   # bt takes it modulo 64
		if not lw.ok: return true
		irPut(
			lw,
			IrInst(
				op = irBranchBit,
				a = x,
				b = bit,
				cond = irNe if nodes[e].ival == binNe else irEq,
				target = yes,
				other = no
			)
		)
		return true
	false

# a test against none and a string comparison; true when e was lowered
fn irCondInPresence(mut g Gen, mut lw IrLower, e NodeId, k i64, yes i64, no i64):
	if k == nBinary and (nodes[e].ival == binEq or nodes[e].ival == binNe) and
		(
			nodes[nodes[e].kids(kidIds)[0]].kind == nNone or
				nodes[nodes[e].kids(kidIds)[1]].kind == nNone
		):
		opt = nodes[e].kids(kidIds)[1] if nodes[nodes[e].kids(kidIds)[0]].kind == nNone
			else nodes[e].kids(kidIds)[0]
		ot = g.ty(opt)
		tag = -1
		if g.irIsOption(ot):
			tag = g.irValue(lw, opt).first ?? -1
		elif g.irIsTaggedOption(ot):
			a = g.irAddressOf(lw, opt)
			tag = g.irTagAt(lw, ot, a)
		elif g.c.isNicheOption(ot):
			tag = g.irTagOf(lw, ot, g.irExpr(lw, opt))   # the word without a tag
		else:
			lw.irFail("a presence test of {typeStr(tys, ot)}")
			return true
		if not lw.ok: return true
		# == none holds when the tag is 0
		lw.irBranchIf(
			tag,
			irEq if nodes[e].ival == binEq else irNe,
			lw.irConstOf(irInt, 0),
			yes,
			no
		)
		return true
	if k == nBinary and isCompareOp(nodes[e].ival) and g.irIsStr(g.ty(nodes[e].kids(kidIds)[0])) and
		g.irIsStr(g.ty(nodes[e].kids(kidIds)[1])):
		op = nodes[e].ival
		a = g.irStrAddr(lw, nodes[e].kids(kidIds)[0])
		b = g.irStrAddr(lw, nodes[e].kids(kidIds)[1])
		if not lw.ok: return true
		equality = op == binEq or op == binNe
		r = g.irCallRt(lw, "strEq" if equality else "strCmp", [a, b])[0]
		cond = (irNe if op == binEq else irEq) if equality else irCondOf(op)
		lw.irBranchIf(r, cond, lw.irConstOf(irInt, 0), yes, no)
		return true
	false

# comparisons of values by address, enums, optionals and numbers; true when e was lowered
fn irCondInCompare(mut g Gen, mut lw IrLower, e NodeId, k i64, yes i64, no i64):
	if k == nBinary and isCompareOp(nodes[e].ival) and
		g.derivedCompare(g.irListType(nodes[e].kids(kidIds)[0])) and
		not g.irIsOption(g.ty(nodes[e].kids(kidIds)[0])) and
		nodes[nodes[e].kids(kidIds)[0]].kind != nNone and
		nodes[nodes[e].kids(kidIds)[1]].kind != nNone:
		# $eqN (== and !=, a bool) or $cmpN (-1, 0, 1) written for the type, both values by address
		op = nodes[e].ival
		lt = g.irListType(nodes[e].kids(kidIds)[0])
		equality = op == binEq or op == binNe
		found = g.derivedFn("eq" if equality else "cmp", lt)
		if not g.irCallable(found, false):
			lw.irFail("comparison of {typeStr(tys, lt)}")
			return true
		fnd = found ?? return true
		a = g.irComparedAddr(lw, nodes[e].kids(kidIds)[0])
		b = g.irComparedAddr(lw, nodes[e].kids(kidIds)[1])
		if not lw.ok: return true
		r = g.irCallValues(lw, fnd, nodes[fnd].text.copy(), [a, b])
		if not lw.ok or r.len != 1: return true
		cond = (irNe if op == binEq else irEq) if equality else irCondOf(op)
		lw.irBranchIf(r[0], cond, lw.irConstOf(irInt, 0), yes, no)
		return true
	if k == nBinary and (nodes[e].ival == binEq or nodes[e].ival == binNe) and
		g.irIsPlainEnum(g.irListType(nodes[e].kids(kidIds)[0])):
		a = g.irValue(lw, nodes[e].kids(kidIds)[0])
		b = g.irValue(lw, nodes[e].kids(kidIds)[1])
		if not lw.ok or a.len != 1 or b.len != 1:
			lw.irFail("comparison of an enum")
			return true
		lw.irBranchIf(a[0], irCondOf(nodes[e].ival), b[0], yes, no)
		return true
	if k == nBinary and (nodes[e].ival == binEq or nodes[e].ival == binNe) and
		g.irIsOption(g.ty(nodes[e].kids(kidIds)[0])) and
		g.irIsOption(g.ty(nodes[e].kids(kidIds)[1])) and
		g.irClassOf(tys[g.ty(nodes[e].kids(kidIds)[0])].inner) >= 0:
		# two optionals of a number: equal when both are none, or both hold the same value
		a = g.irValue(lw, nodes[e].kids(kidIds)[0])
		b = g.irValue(lw, nodes[e].kids(kidIds)[1])
		if not lw.ok or a.len != 2 or b.len != 2:
			lw.irFail("comparison of optionals")
			return true
		same, differ = (yes, no) if nodes[e].ival == binEq else (no, yes)
		tagsMatch = lw.f.irBlock()
		bothSome = lw.f.irBlock()
		lw.irBranchIf(a[0], irEq, b[0], tagsMatch, differ)
		lw.f.irEnter(tagsMatch)
		lw.irBranchIf(a[0], irEq, lw.irConstOf(irInt, 0), same, bothSome)
		lw.f.irEnter(bothSome)
		lw.irBranchIf(a[1], irEq, b[1], same, differ)
		return true
	if k == nBinary and isCompareOp(nodes[e].ival):
		lt = g.ty(nodes[e].kids(kidIds)[0])
		if g.irClassOf(lt) < 0 or g.irClassOf(g.ty(nodes[e].kids(kidIds)[1])) != g.irClassOf(lt):
			lw.irFail("comparison of {typeStr(tys, lt)}")
			return true
		a = g.irExpr(lw, nodes[e].kids(kidIds)[0])
		b = g.irExpr(lw, nodes[e].kids(kidIds)[1])
		lw.irBranchIf(a, irCondOf(nodes[e].ival), b, yes, no, uns = g.irUnsigned(lt))
		return true
	false

# whether e is (x & (1 << (k & 63))) != 0 or == 0 on 64-bit integers (x64's bt takes k modulo
# 64 too)
fn irBitTested(g Gen, e NodeId):
	if nodes[e].kind != nBinary or not (nodes[e].ival == binNe or nodes[e].ival == binEq):
		return false
	zero = nodes[e].kids(kidIds)[1]
	mask = nodes[e].kids(kidIds)[0]
	if nodes[zero].kind != nInt or nodes[zero].text != "0" or nodes[mask].kind != nBinary or
		nodes[mask].ival != binBand:
		return false
	shift = nodes[mask].kids(kidIds)[1]
	if nodes[shift].kind != nBinary or nodes[shift].ival != binShl or
		nodes[nodes[shift].kids(kidIds)[0]].kind != nInt or
		nodes[nodes[shift].kids(kidIds)[0]].text != "1":
		return false
	t = g.ty(mask)
	tys[t].kind == tInt and tys[t].bits == 64 and g.irBitIndex(nodes[shift].kids(kidIds)[1]) != none

# k of a shift's count k & 63, through an integer conversion the checker put around it (the
# count is below 64 in any width)
fn irBitIndex(g Gen, count NodeId) NodeId?:
	k = count
	if nodes[k].kind == nCall and nodes[k].kids(kidIds).len == 1:
		callee = nodes[k].kids(kidIds)[0]
		if nodes[callee].kind == nField and nodes[callee].text in intConversions and
			nodes[callee].kids(kidIds).len == 1:
			k = nodes[callee].kids(kidIds)[0]
	masked = nodes[k].kind == nBinary and nodes[k].ival == binBand and
		nodes[nodes[k].kids(kidIds)[1]].kind == nInt and
		nodes[nodes[k].kids(kidIds)[1]].text == "63"
	nodes[k].kids(kidIds)[0] if masked else none

# the address a composite value is compared by: its place, or its leaves in a slot
fn irComparedAddr(mut g Gen, mut lw IrLower, e NodeId) i64:
	t = g.irListType(e)
	if g.irByAddress(t) or g.tyK(g.ty(e)) == tRef: return g.irAddressOf(lw, e)
	g.irLentCopy(lw, t, g.irAs(lw, g.irValue(lw, e), t))

fn irCondOf(op i64):
	if op == binEq: return irEq
	if op == binNe: return irNe
	if op == binLt: return irLt
	if op == binLe: return irLe
	if op == binGt: return irGt
	irGe

# ---------- expressions ----------
