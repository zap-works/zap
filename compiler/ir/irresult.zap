# `T ? E` in the intermediate form: a result is reached by address, a tag byte (1 ok, 0 an
# error) then the side it holds at resultPayload, as the layout has it. The checker wraps a value where a result is
# wanted (nSome: ival 1 ok, 2 an error) and turns `r ?? b` into a match; this code makes the
# value, matches it and lowers `r?`.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

fn irIsResult(mut g Gen, maybeT TypeId?) bool:
	t = maybeT ?? return false
	tys[t].kind == tResult and g.irSideOk(tys[t].inner) and g.irSideOk(tys[t].err)

fn irSideOk(mut g Gen, maybeT TypeId?) bool:
	t = maybeT ?? return false
	(tys[t].kind == tUnit or g.irTakes(t) or g.irByAddress(t))

# the side a result holds: its type, ok (tag 1) or the error
fn irSideType(g Gen, t TypeId, ok bool):
	innerOf(tys, t) if ok else errOf(tys, t)

# v (of the side ok) wrapped as the result t: a slot (a temporary when it owns), its tag then v
fn irWrapResult(mut g Gen, mut lw IrLower, t TypeId, ok bool, value i64[]):
	slot = g.irZeroedSlot(lw, t)
	lw.irSetSpot(resultTag(), slot, 1 if ok else 0)
	side = g.irSideType(t, ok)
	if tys[side].kind != tUnit:
		g.irPutValue(lw, lw.irElementAddr(slot, -1, 0, g.c.resultPayload(t)), side, value)
	slot

# value, of type vt, as a function's result of type rt: a value of either side wrapped (the
# checker leaves returns and a body's last value unwrapped)
fn irAsResult(mut g Gen, mut lw IrLower, rt TypeId, maybeVt TypeId?, move value i64[]):
	vt = maybeVt ?? return value
	if not lw.ok or not g.irIsResult(rt) or tys[vt].kind == tResult or lw.f.irEnded(): return value
	if tys[vt].kind == tUnit and value.isEmpty and tys[innerOf(tys, rt)].kind != tUnit: return value   # it left: no value
	[g.irWrapResult(lw, rt, not isSameType(tys, vt, tys[rt].err), value)]

# the type of a body's value: its last statement's expression
fn irTailType(g Gen, body NodeId) TypeId?:
	if nodes[body].kind != nBlock: return nodes[body].ty
	kids = nodes[body].kids(kidIds)
	if kids.isEmpty: return tyUnit
	last = kids[len - 1]
	nodes[nodes[last].kids(kidIds)[0]].ty if nodes[last].kind == nExprStmt else nodes[last].ty

# r? on a result: its ok side, or the function returns the error (moved out of a temporary,
# copied from anything else) as its own result's
fn irTryResult(mut g Gen, mut lw IrLower, kid NodeId) i64[]:
	ot = g.ty(kid)
	rt = lw.rt
	if not g.irIsResult(rt) or lw.hidden < 0 or not lw.rets.isEmpty:
		return lw.irRefused("try on {typeStr(tys, ot)} returning {typeStr(tys, rt)}")
	a = g.irAddressOf(lw, kid)
	if not lw.ok: return []
	owner = lw.owned.any(.slot == a and .name < 0)
	tag = lw.irSpotAt(resultTag(), a)
	at = lw.irElementAddr(a, -1, 0, g.c.resultPayload(ot))
	okB = lw.f.irBlock()
	errB = lw.f.irBlock()
	lw.irBranchNZ(tag, okB, errB)
	lw.f.irEnter(errB)
	err = errOf(tys, ot)
	lw.irSetSpot(resultTag(), lw.hidden, 0)
	to = lw.irElementAddr(lw.hidden, -1, 0, g.c.resultPayload(rt))
	if not g.isOwningType(err) or tys[err].kind == tUnit:
		if tys[err].kind != tUnit:
			lw.irPut(IrInst(op = irMemCopy, a = to, b = at, imm = g.sizeOf(err)))
	elif owner:
		g.irMoveTo(lw, to, at, err)
	else:
		lw.irPut(IrInst(op = irDeepCopy, a = to, b = at, ty = err))
	g.irLeave(lw, -1)
	lw.f.irEnter(okB)
	side = innerOf(tys, ot)
	if tys[side].kind == tUnit: return []
	if owner and g.isOwningType(side) and g.irByAddress(side):
		slot = g.irTemporary(lw, side)
		g.irMoveTo(lw, slot, at, side)
		return [slot]
	if owner and g.irIsOwnedWord(side):
		word = g.irWordMovedOut(lw, side, at)
		g.irOwnedWord(lw, side, word)
		return [word]
	if g.irByAddress(side) and not g.isOwningType(side):
		slot = lw.irNewSlot(g.sizeOf(side).alignUp(8))   # plain bytes: a slot of their own
		lw.irPut(IrInst(op = irMemCopy, a = slot, b = at, imm = g.sizeOf(side)))
		lw.made.push(slot)
		return [slot]
	[at] if g.irByAddress(side) else g.irLoadValue(lw, side, at, -1, 0)
