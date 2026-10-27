# The lowering of blocks, statements, regions, try, return and let (irLower.zap).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# the statements of block b; with want, its last one is an expression whose leaves are returned
fn irBlockValue(mut g Gen, mut lw IrLower, b NodeId, want bool) i64[]:
	if nodes[b].kind != nBlock:
		if want and nodes[b].kind != nReturn and nodes[b].kind != nBreak and
			nodes[b].kind != nContinue:
			return g.irValue(lw, b)
		g.irStmt(lw, b)
		return []
	mark = lw.names.len
	stmts = nodes[b].kids(kidIds).copy()
	if irBlocksWord().on():
		g.irSay(
			"ir block want {want}: kinds {stmts.map(nodes[it].kind)} types {stmts.map(g.ty(it))}"
		)
	value = []
	for i in 0..stmts.len:
		if not lw.ok: return []
		s = stmts[i]
		m = nodes[s].kids(kidIds)[0] if nodes[s].kind == nExprStmt else s
		if want and i == stmts.len - 1 and nodes[m].kind == nMatch and
			(g.irTyped(m) == none or g.tyK(g.ty(m)) == tUnit):
			g.irSetTailType(m, lw.rets[len - 1].t if not lw.rets.isEmpty else lw.rt)   # a statement match as the tail (its arms return): the value wanted
		if want and i == stmts.len - 1 and (nodes[s].kind in [nExprStmt, nIf, nMatch]) and
			not nodes[s].hasFlag(flagArena):
			g.irArenaPause(lw, s)
			if lw.fnd is fd and b == nodes[fd].sub(kidIds)[0]:
				g.irReturnedRefs(lw, m)   # the function's value
			value = g.irValue(lw, nodes[s].kids(kidIds)[0] if nodes[s].kind == nExprStmt else s)   # a match of block arms is a statement node
			g.irArenaResume(lw, s)
		else:
			g.irStmt(lw, s)   # the last a return: the value never comes out
	# a local of this block that is its value outlives it: a temporary now, moved by the taker
	if value.len == 1 and
		lw.owned.findIndex(o:
			(o.slot == value[0] or o.word == value[0]) and o.name >= mark
		) is vi:
		lw.owned[vi].name = -1
	g.irScopeEndDropping(lw, mark)
	value

fn irStmt(mut g Gen, mut lw IrLower, s NodeId):
	if not lw.ok: return
	g.irArenaPause(lw, s)
	# (not in the runtime, whose loops serve the allocator, nor in a body inlined here)
	region = not lw.breaks.isEmpty and lw.arenas == 0 and lw.rets.isEmpty and not lw.inRegion and
		not g.irLowersRuntime(lw) and g.irRegionStatement(s)
	if irDropsWord().on() and not lw.breaks.isEmpty:
		g.irSay("ir: line {nodes[s].line}: {"a region" if region else "no region"} ({g.irRegionSafe(s)})")
	if region:
		g.irCallRt(lw, "regionOpen", [])
		lw.inRegion = true
	at = lw.owned.len
	keeps = nodes[s].kind == nLet and not nodes[s].kids(kidIds).isEmpty and
		not lw.irInRuntimeCode() and
		g.irMayBorrow(typeOf(nodes, nodes[s].kids(kidIds)[0]))
	walking = lw.arenas > 0 and lw.floor == 0 and not lw.irInRuntimeCode()
	if walking:
		lw.arenaWalk.push(IrArenaStmt())
	clean = lw.arenaClean
	# (an explicit region never runs out, so what such a statement makes is all the region's)
	lw.arenaClean = lw.arenas > 0 and not lw.irInRuntimeCode() and not lw.inRegion and
		not g.irFlagged(s, flagArenaPause) and
		g.irRegionSafe(s) >= 0
	g.irStmtOnly(lw, s)
	if keeps:
		lw.irKeepTemporaries(at)
	if walking:
		g.irArenaEscapes(lw, lw.arenaWalk.pop() ?? IrArenaStmt())
	g.irDropTemporaries(lw, at)
	lw.arenaClean = clean
	if region:
		lw.inRegion = false
		if lw.ok and not lw.f.irEnded():
			g.irCallRt(lw, "regionClose", [])
	g.irArenaResume(lw, s)

# whether the function lowered is the runtime's (a lambda's body is not)
fn irLowersRuntime(g Gen, lw IrLower):
	if lw.fnd is f: return nodes[f].text.startsWith("rt__")
	false

# Escape analysis: whether statement s of a loop runs in an implicit region
# (runtime/core/core.zap's regionOpen). Nothing it allocates can outlive it: it keeps no value that owns
# memory (a plain result, target or binding), gives nothing away (no lambda, return, break,
# continue, yield, try or arena), every call in it changes no module variable, calls no function
# value, reaches no runtime state and waits for no thread, no argument it hands a `mut` or `move`
# parameter owns memory but a value made here, and no literal in it takes in a value that owns
# memory from a place; so every value it makes is made of the region's blocks. And it calls a
# function of the program that allocates in a loop or a recursion: a region costs a few calls, so
# a statement that makes a block or two (the runtime's methods, a literal) runs without one.
fn irRegionStatement(mut g Gen, s NodeId):
	k = nodes[s].kind
	kept TypeId = tyUnit
	if k == nExprStmt or k == nLet:
		kept = g.ty(nodes[s].kids(kidIds)[0])
	elif k == nAssign:
		kept = g.ty(nodes[s].kids(kidIds)[0])
	else:
		return false
	if g.tyK(kept) != tUnit and not g.c.isPlainType(kept): return false
	g.irRegionSafe(s) == 1

# irRegionStatement's walk of e: -1 when something keeps or gives away what it makes, else 1 when
# something allocates, 0 when nothing does
fn irRegionSafe(mut g Gen, e NodeId) i64:
	k = nodes[e].kind
	if k in [nLambda, nReturn, nBreak, nContinue, nYield, nTry, nWhile, nFor] or
		k == nIf and nodes[e].hasFlag(flagArena) or
		k == nUnary and nodes[e].ival == unMove:
		return -1
	allocates = 0
	if k in [nStructLit, nArray, nSome, nMapLit, nInterp]:
		if k != nInterp:
			for kidAt in 0..nodes[e].kids(kidIds).len:
				kid = nodes[e].kids(kidIds)[kidAt]
				if g.irIsPlaceNode(kid) and not g.c.isPlainType(g.ty(kid)):
					return -1   # a value that owns memory taken in from a place
	if k == nCall:
		does, d = g.c.nodeDoes(e)
		unsafe = doesChange | doesCallValue | doesRaw | doesWait
		if does & unsafe != 0: return -1
		callee = nodes[e].kids(kidIds)[0]
		if d == none and not (nodes[callee].kind == nIdent and
				(isPrintBuiltin(nodes[callee].text) or nodes[callee].text.startsWith("__"))):
			return -1   # a function this cannot follow (one the lowering renamed, a conversion)
		if d is fd:
			if g.c.fnDoes(fd) & unsafe != 0: return -1
			many = doesAllocate | doesEndless
			if g.c.fnDoes(fd) & many == many and nodes[fd].mod(kidIds) != "rt":
				allocates = 1
		for changed in g.c.placesChanged(e).copy():
			p = g.c.placeUnder(changed)   # (below `mut ref`, `move` and a parameter's name)
			if not g.c.isPlainType(g.ty(p)) and g.irIsPlaceNode(p): return -1
	for kidAt in 0..nodes[e].kids(kidIds).len:
		kid = nodes[e].kids(kidIds)[kidAt]
		r = g.irRegionSafe(kid)
		if r < 0: return -1
		allocates = allocates.max(r)
	for kidAt in 0..nodes[e].sub(kidIds).len:
		kid = nodes[e].sub(kidIds)[kidAt]
		r = g.irRegionSafe(kid)
		if r < 0: return -1
		allocates = allocates.max(r)
	allocates

# a temporary of a region statement dropped: while the region holds every block, it is made of
# the region's blocks alone and nothing is done (regionClose gives them back whole); else dropped
# (runtime/core/core.zap's regionDropped)
fn irRegionDrop(mut g Gen, mut lw IrLower, o IrOwned):
	g.irRtInstanceValues(lw, "regionDropped", [o.t], [o.slot])
	lw.irZeroGap(o.slot, -1, 1, 0, g.sizeOf(o.t).alignUp(8), lw.irConstOf(irInt, 0))
	lw.irConsumed(o.slot, ownDropped)

# whether a value of type t made in a region is the region's blocks and nothing else to undo: no
# drop function, no shared value (counted), no closure
fn irOfRegionOnly(mut g Gen, t TypeId) bool:
	seen = []
	g.irRegionOnlySeen(t, seen)

fn irRegionOnlySeen(mut g Gen, t TypeId, mut seen TypeId[]) bool:
	if seen.any(isSameType(tys, it, t)) or g.c.isPlainType(t): return true
	if seen.len > 16: return false   # (deep enough: not followed)
	seen.push(t)
	k = g.tyK(t)
	if k == tStr: return true
	if not (k in [tStruct, tEnum, tOption, tBox, tResult, tMap, tList, tArray]) or
		k == tBox and tys[t].counted:
		return false
	if k == tStruct and
		(nodes[declOf(tys, t)].hasFlag(flagDrop) or nodes[declOf(tys, t)].hasFlag(flagShared)):
		return false
	offs = []
	types = []
	tags = []
	g.typeParts(t, offs, types, tags)
	types.all(g.irRegionOnlySeen(it, seen))

# An `arena:` block: the thread allocates from a region of its own until the block ends, frees
# of the region's blocks doing nothing, and the region goes whole at the end (a jump out of the
# block, break, continue or return, ends it too, after the drops).
fn irArena(mut g Gen, mut lw IrLower, s NodeId):
	g.irCallRt(lw, "arenaEnter", [])
	lw.arenas += 1
	lw.arenaLines.push(nodes[s].line)
	g.irBlockValue(lw, nodes[s].sub(kidIds)[0], false)
	lw.arenaLines.pop()
	lw.arenas -= 1
	if lw.ok and not lw.f.irEnded():
		g.irCallRt(lw, "arenaExit", [])

# the arena blocks opened since `down` were open, ended on a jump out of them
fn irArenaExits(mut g Gen, mut lw IrLower, down i64):
	for _ in down..lw.arenas:
		g.irCallRt(lw, "arenaExit", [])

# a statement of an arena block that stores outside it (irDecide.zap): what it allocates comes
# from the heap
fn irArenaPause(mut g Gen, mut lw IrLower, s NodeId):
	if g.irFlagged(s, flagArenaPause):
		g.irCallRt(lw, "arenaPause", [])

fn irArenaResume(mut g Gen, mut lw IrLower, s NodeId):
	if g.irFlagged(s, flagArenaPause) and lw.ok and not lw.f.irEnded():
		g.irCallRt(lw, "arenaResume", [])

# the place errors of the code lowered next are said at: node n's, when it has one
fn irPlaceAt(g Gen, mut lw IrLower, n NodeId):
	if nodes[n].line > 0:
		lw.line = nodes[n].line
		lw.col = nodes[n].col

fn irStmtOnly(mut g Gen, mut lw IrLower, s NodeId):
	# a runtime body inlined keeps its call's place: its lines are of another file
	if lw.rets.isEmpty or not lw.rets[len - 1].runtime:
		g.irPlaceAt(lw, s)
	if lw.f.irEnded():
		lw.f.irEnter(lw.f.irBlock())   # code after a jump: a block nothing reaches
	k i64 = nodes[s].kind
	if k == nExprStmt and nodes[nodes[s].kids(kidIds)[0]].kind == nMatch and
		g.irMatchesAsOption(g.ty(nodes[nodes[s].kids(kidIds)[0]].kids(kidIds)[0])):
		g.irMatchPatterns(lw, nodes[s].kids(kidIds)[0], false)
	elif k == nExprStmt:
		g.irValue(lw, nodes[s].kids(kidIds)[0])
	elif k == nLet:
		g.irLet(lw, s)
	elif k == nAssign:
		g.irAssign(lw, s)
	elif k == nIf and nodes[s].hasFlag(flagArena):
		g.irArena(lw, s)
	elif k == nIf and g.irWindowTest(nodes[s].kids(kidIds)[0]) is taken:
		# a branch the key's type decides (the runtime's maps): only that one lowered
		if taken or nodes[s].sub(kidIds).len > 1:
			g.irBlockValue(lw, nodes[s].sub(kidIds)[0 if taken else 1], false)
	elif k == nIf:
		g.irIf(lw, s, false)
	elif k == nWhile or k == nFor:
		mark = lw.names.len
		kept = g.irKeptBlocks(lw, s)
		if k == nWhile:
			g.irWhile(lw, s)
		else:
			g.irFor(lw, s)
		if kept:
			g.irScopeEndDropping(lw, mark)   # the kept blocks freed as the loop ends
			if lw.ok and not lw.f.irEnded():
				after = lw.f.irBlock()   # an empty block after them, as after a loop
				lw.f.irJumpTo(after)
				lw.f.irEnter(after)
	elif k == nBreak or k == nContinue:
		if nodes[s].text != "" or lw.breaks.isEmpty:
			lw.irFail("labelled break")
			return
		g.irDropFrom(lw, lw.loopOwned[len - 1])   # what the loop body owns
		g.irArenaExits(lw, lw.loopArenas[len - 1])
		lw.f.irJumpTo(lw.breaks[len - 1] if k == nBreak else lw.conts[len - 1])
	elif k == nReturn:
		g.irReturn(lw, s)
	elif k == nYield:
		g.irYield(lw, s)
	elif k == nBlock:
		g.irBlockValue(lw, s, false)
	elif k in [nCall, nMatch, nBinary, nUnary, nIdent, nField, nIndex, nTry]:
		g.irValue(lw, s)   # an expression where a statement goes (a match arm's)
	else:
		lw.irFail("statement kind {k}")

# x?: x's value when it has one, else the function's result is none (its result an optional too)
fn irTry(mut g Gen, mut lw IrLower, e NodeId):
	kid = nodes[e].kids(kidIds)[0]
	if lw.lentTry != i64(e) and not lw.irInRuntimeCode() and lw.floor == 0 and
		g.irNamesPlace(lw, kid) and not g.irNamesOwnedLocal(lw, kid) and
		not g.c.copiesFreely(typeOf(nodes, kid)):
		# the value inside belongs to the place: unwrapping it would give it away
		path = g.irPathOf(lw, kid)
		head = pathHead(path)
		belongs = "the value behind this reference belongs to someone else" if path == ""
			else "'{path}' is borrowed" if head == path
			else "'{path}' belongs to '{head}'"
		g.irOwnError(
			g.irFileNow,
			nodes[e].line,
			nodes[e].col,
			compileError("TryMovesBorrowed", ["{belongs}"])
		)
	ot = g.ty(kid)
	if g.tyK(ot) == tResult: return g.irTryResult(lw, kid)
	rt = lw.rt
	if g.tyK(ot) != tOption or g.tyK(rt) != tOption or not lw.rets.isEmpty:
		return lw.irRefused("try on {typeStr(tys, ot)}")
	tag = -1
	payload = []
	if g.irIsOption(ot):
		o = g.irValue(lw, kid)
		if not lw.ok or o.len != 2: return []
		tag = o[0]
		payload = [o[1]]
	elif g.irIsTaggedOption(ot):
		a = g.irAddressOf(lw, kid)
		if not lw.ok: return []
		tag, at = g.irOptionAt(lw, ot, a)
		inner = innerOf(tys, ot)
		payload = [at] if g.irByAddress(inner) else g.irLoadValue(lw, inner, at, -1, 0)
		if g.irByAddress(inner) and not g.isOwningType(inner):
			lw.made.push(at)   # plain bytes in the optional's slot: bound where they are
		elif g.irOwnedByAddress(inner) and not g.irIsPlaceNode(kid) and
			lw.owned.any(.slot == a and .name < 0):
			taken = g.irTemporary(lw, inner)   # moved out of the temporary, which keeps an empty value
			lw.irPut(IrInst(op = irMemCopy, a = taken, b = at, imm = g.sizeOf(inner)))
			g.irEmptyAt(lw, at, inner)
			payload = [taken]
	elif g.c.isNicheOption(ot):
		word = g.irExpr(lw, kid)   # the word without a tag: the value, or the absent word
		tag = g.irTagOf(lw, ot, word)
		payload = [word]
	else:
		return lw.irRefused("try on {typeStr(tys, ot)}")
	some = lw.f.irBlock()
	noneB = lw.f.irBlock()
	lw.irBranchNZ(tag, some, noneB)
	lw.f.irEnter(noneB)
	if g.irIsOption(rt):
		irFunctionResult(
			g,
			lw,
			[lw.irConstOf(irInt, 0), lw.irConstOf(g.irClassOf(tys[rt].inner), 0)],
			rt
		)
	elif g.c.isNicheOption(rt):
		g.irFunctionResult(lw, [g.irNoneWord(lw, rt)], rt)
	elif lw.hidden >= 0:
		spot = g.c.optionTag(rt)
		lw.irSetSpot(spot, lw.hidden, spot.absent)   # its tag none, or its niche the absent value
		g.irLeave(lw, -1)
	else:
		return lw.irRefused("try returning {typeStr(tys, rt)}")
	lw.f.irEnter(some)
	if g.irIsOption(ot) and g.irIsOwnedWord(tys[ot].inner) and payload.len == 1:
		payload = [g.irWordTaken(lw, innerOf(tys, ot), payload[0])]
		g.irOwnedWord(lw, innerOf(tys, ot), payload[0])
	payload

# a return: out of the inlined body being lowered, else out of the function
fn irReturn(mut g Gen, mut lw IrLower, s NodeId):
	target = lw.rets[len - 1].t if not lw.rets.isEmpty else lw.rt
	lw.irArenaStore(-1)   # the value outlives every arena
	if lw.rets.isEmpty and not nodes[s].kids(kidIds).isEmpty:
		g.irReturnedRefs(lw, nodes[s].kids(kidIds)[0])
	if irBlocksWord().on() and not nodes[s].kids(kidIds).isEmpty:
		g.irSay("ir return of kind {nodes[nodes[s].kids(kidIds)[0]].kind} type {g.ty(nodes[s].kids(kidIds)[0])} target {target}")
	if not nodes[s].kids(kidIds).isEmpty and nodes[nodes[s].kids(kidIds)[0]].kind == nMatch and
		g.tyK(target) != tUnit and
		(
			nodes[nodes[s].kids(kidIds)[0]].ty == none or
				g.tyK(g.ty(nodes[s].kids(kidIds)[0])) == tUnit
		):
		nodes[nodes[s].kids(kidIds)[0]].ty = target   # a returned match the checker left as a statement (its arms return)
	# a bare return in a `? E` function: the ok side
	value = []
	if nodes[s].kids(kidIds).isEmpty:
		value = g.irAsResult(lw, target, tyUnit, [])
	else:
		out = g.irReturnsError(target, nodes[s].kids(kidIds)[0])
		if out: lw.errorOut += 1
		made = g.irValue(lw, nodes[s].kids(kidIds)[0])
		if out: lw.errorOut -= 1
		value = g.irAsResult(lw, target, g.ty(nodes[s].kids(kidIds)[0]), made)
	if not lw.ok or lw.f.irEnded(): return   # ended: every path of the value returned already
	for w in lw.armWrites.copy():
		if lw.irLookup(w.name) is leaves:
			g.irStoreLeaves(lw, w.t, w.at, -1, 1, 0, leaves)
	if not lw.rets.isEmpty:
		r = lw.rets[len - 1].copy()
		g.irResultTo(lw, r.leaves, r.t, value)
		g.irDropFrom(lw, r.owned)   # what the inlined body owns
		g.irArenaExits(lw, r.arenas)
		lw.f.irJumpTo(r.end)
		return
	irFunctionResult(
		g,
		lw,
		value,
		target if not nodes[s].kids(kidIds).isEmpty or not value.isEmpty else tyUnit
	)

# whether e, returned from a function whose result is target, is the result's error
fn irReturnsError(mut g Gen, target TypeId, e NodeId):
	vt = nodes[e].ty ?? return false
	g.irIsResult(target) and isSameType(tys, vt, tys[target].err)

# the function's result given back: a scalar in rax, any other through the hidden address; the
# owned values dropped first
fn irFunctionResult(mut g Gen, mut lw IrLower, value i64[], vt TypeId?):
	rt = lw.rt
	if irBlocksWord().on():
		g.irSay("ir function result: {value.len} leaves of type {vt}, rt {rt}, line {lw.line}")
	out = -1

	if value.isEmpty and g.tyK(rt) != tUnit and
		(
			vt == none or g.tyK(vt) == tUnit or
				(lw.f.cur != 0 and lw.f.blocks[lw.f.cur].insts.isEmpty)
		):
		# a value every path of which returned already (a match of returning arms, the block
		# after it empty): the code here runs never (the checker saw every case covered)
		lw.irPut(IrInst(op = irRet))
		return
	if lw.hidden >= 0:
		g.irResultTo(lw, [lw.hidden], rt, value)
	elif lw.regResult:
		g.irLeaveWith(lw, g.irAs(lw, value, rt))   # its leaves in registers
		return
	elif value.len > 1 or (value.isEmpty and g.tyK(rt) != tUnit):
		lw.irFail("return of a value of {value.len} leaves")
		return
	elif value.len == 1:
		out = value[0]
		if g.irIsOwnedWord(rt):
			out = g.irGiveWordOf(lw, rt, value[0])
			if out < 0:
				lw.irFail("a map returned, not owned here")
				return
	g.irLeave(lw, out)

# out of the function: what it owns dropped, the mut structs of numbers written back, out (-1:
# nothing, or the result already written) returned
fn irLeave(mut g Gen, mut lw IrLower, out i64):
	g.irLeaveWith(lw, [] if out < 0 else [out])

# the same with the result's leaves (none, a scalar, or a small aggregate's in registers)
fn irLeaveWith(mut g Gen, mut lw IrLower, outs i64[]):
	g.irDropFrom(lw, 0)
	g.irArenaExits(lw, 0)
	for IrMutScalar(addr, leaves, t) in lw.mutScalars:
		g.irStoreLeaves(lw, t, addr, -1, 1, 0, leaves)
	if outs.isEmpty:
		lw.irPut(IrInst(op = irRet))
	else:
		lw.irPut(IrInst(op = irRet, a = outs[0], part = instPartOf(outs[1..].copy())))

# a body's result put where it goes (dst: leaves, or the address of an owned result): leaves
# copied (a plain value made optional where one is wanted), an owned value moved from the slot
# the code owns it in
fn irResultTo(mut g Gen, mut lw IrLower, dst i64[], t TypeId, value i64[]):
	if g.irTakes(t):
		# a map (a box) given back as or inside the result (an optional of it): the result's now,
		# not dropped
		given = value.map(v:
			w = g.irGiveWord(lw, v)
			w if w >= 0 else v
		)
		if lw.hidden >= 0 and dst.len == 1 and dst[0] == lw.hidden and lw.rets.isEmpty:
			g.irStoreLeaves(lw, t, lw.hidden, -1, 1, 0, g.irAs(lw, given, t))
			return
		lw.irCopyValue(dst, g.irAs(lw, given, t))
		return
	if value.len == 1 and (value[0] in lw.literals or not g.isOwningType(t)):
		lw.irPut(IrInst(op = irMemCopy, a = dst[0], b = value[0], imm = g.sizeOf(t)))   # owns nothing
		return
	if value.len != 1:
		lw.irFail("a result of {typeStr(tys, t)} ({value.len} leaves, {lw.rets.len} bodies open, hidden {lw.hidden})")
		return
	g.irMoveTo(lw, dst[0], g.irOwnedCopy(lw, t, value[0]), t)

# `mut x T` without a value: T's empty value (all zero), in leaves or in a slot of its own
fn irZeroLocal(mut g Gen, mut lw IrLower, name str, t TypeId):
	lw.mutNames.push(lw.names.len)
	if g.irTakes(t):
		lw.irDeclare(name, g.irEmptyLeaves(lw, t))
		return
	if not g.irByAddress(t) or g.irIsOwnedWord(t):
		lw.irFail("a {typeStr(tys, t)} without a value")
		return
	slot = lw.irNewSlot(g.sizeOf(t).alignUp(8))
	if g.isOwningType(t):
		lw.irOwnBegin(IrOwned(slot, t, name = lw.names.len, key = name.copy()))
	g.irEmptyAt(lw, slot, t)   # again each time it runs
	lw.irDeclare(name, [slot])

# `x = value`: a new local, or (bare, on a live one) a rebinding; `_ = value` only evaluates it
fn irLet(mut g Gen, mut lw IrLower, s NodeId):
	if nodes[s].names(kidIds).isEmpty and nodes[s].kids(kidIds).isEmpty and
		nodes[s].types(kidIds).len == 1:
		g.irZeroLocal(lw, nodes[s].text.copy(), g.c.resolveType(nodes[s].types(kidIds)[0]))
		return
	if not nodes[s].names(kidIds).isEmpty or nodes[s].kids(kidIds).len != 1:
		lw.irFail("destructuring let")
		return
	if g.irRebindsInPlace(lw, s): return
	kept = -1
	if lw.keptBlocks.find(.let == s) is k and lw.irLookupNo(nameOf(nodes, s)) == none and
		not g.irFieldOfThis(lw, nodes[s].text):
		kept = k.slot
		lw.recycleInto = kept
	if nodes[nodes[s].kids(kidIds)[0]].kind == nTry and
		g.irLetBorrows(lw, s, nodes[s].kids(kidIds)[0]):
		lw.lentTry = i64(nodes[s].kids(kidIds)[0])
	value = g.irValue(lw, nodes[s].kids(kidIds)[0])
	lw.lentTry = -1
	taken = kept >= 0 and lw.recycleInto < 0
	lw.recycleInto = -1
	if nodes[s].text == "_":
		for v in value:
			lw.irNoted(noteUsed, v, "")   # `_ = x` uses x (what it borrows lives to here)
		return
	g.irBindName(lw, s, nodes[s].text.copy(), nodes[s].kids(kidIds)[0], value)
	if taken and value.len == 1 and lw.owned.findIndex(.slot == value[0] and .name >= 0) is oi:
		lw.owned[oi].kept = kept   # its block goes back to the loop at its drop
		if lw.owned[oi].block >= 0:
			lw.f.blocks[lw.owned[oi].block].insts[lw.owned[oi].at].cond = 1   # (irOwn: kept)

# Recycling across a loop's turns: a binding in the loop's body (not in a loop or
# lambda inside it, nor in an arena) made of a list literal or of a map or filter takes, each turn,
# the block the same binding had the turn before, emptied; its capacity grows to the largest
# turn's, and the block is freed once, with the slot holding it, when the scope around the loop
# ends. Each binding's slot: a local of that scope, named after the binding.
fn irKeptBlocks(mut g Gen, mut lw IrLower, s NodeId):
	made = false
	lets = []
	g.irRecyclable(nodes[s].sub(kidIds)[0], lets)
	for let in lets:
		if lw.irLookupNo(nameOf(nodes, let)) != none or g.irFieldOfThis(lw, nodes[let].text):
			continue   # a name that exists: the binding gives it a value (an assignment)
		t = g.ty(nodes[let].kids(kidIds)[0])
		slot = lw.f.irVreg(irInt)
		lw.irPut(IrInst(op = irFrameSlot, dst = slot, imm = 24))
		lw.irZeroGap(slot, -1, 1, 0, 24, lw.irConstOf(irInt, 0))
		lw.irOwnBegin(IrOwned(slot, t, name = lw.names.len))
		lw.irDeclare("$kept{let}", [slot])
		lw.keptBlocks.push(IrKeptBlock(let, slot))
		made = true
	made

# the bindings under e whose value irKeptBlocks recycles (a new local's, irLet finds)
fn irRecyclable(mut g Gen, e NodeId, mut out NodeId[]):
	k = nodes[e].kind
	if k in [nWhile, nFor, nLambda] or k == nIf and nodes[e].hasFlag(flagArena): return
	if k == nLet and nodes[e].kids(kidIds).len == 1 and nodes[e].names(kidIds).isEmpty and
		nodes[e].text != "_" and
		g.irIsList(g.ty(nodes[e].kids(kidIds)[0])) and g.irMakesList(nodes[e].kids(kidIds)[0]):
		out.push(e)
		return
	for kidAt in 0..nodes[e].kids(kidIds).len:
		kid = nodes[e].kids(kidIds)[kidAt]
		g.irRecyclable(kid, out)
	for kidAt in 0..nodes[e].sub(kidIds).len:
		kid = nodes[e].sub(kidIds)[kidAt]
		g.irRecyclable(kid, out)

# whether e makes a new list in a temporary of its own (irListLiteral, irGather), which can start
# from a kept block
fn irMakesList(g Gen, e NodeId):
	if nodes[e].kind == nArray: return true
	if nodes[e].kind != nCall or nodes[e].kids(kidIds).len != 2: return false
	callee = nodes[e].kids(kidIds)[0]
	nodes[callee].kind == nField and (nodes[callee].text == "map" or nodes[callee].text == "filter")

# a new list's temporary at slot made from the block a loop kept for it, when one is waiting
fn irTakeKept(mut lw IrLower, slot i64, t TypeId):
	if lw.recycleInto < 0: return
	kept = lw.recycleInto
	lw.irPut(IrInst(op = irMemCopy, a = slot, b = kept, imm = 24))
	lw.irZeroGap(kept, -1, 1, 0, 24, lw.irConstOf(irInt, 0))
	lw.irConsumed(kept, ownMoved)
	lw.irPut(IrInst(op = irOwn, a = kept, imm = i64(t)))   # the loop's slot owns nothing until the turn's end
	lw.recycleInto = -1

# name bound to value (the expression valueNode's) as a local: s holds the let's flags and type
# (a pattern's temporary has none). A window or a reference is its words; a literal a local will
# change gets a slot of its own; an owned value moved in or a temporary's becomes the local's;
# a borrow of a place is another name for it; numbers are copied into leaves of their own.
fn irBindName(mut g Gen, mut lw IrLower, s NodeId, name str, valueNode NodeId, value i64[]):
	at = lw.irLookupAt(name)
	reassign = nodes[s].canAssign(kidIds) and at >= 0
	if reassign or lw.irInRuntimeCode() or lw.floor > 0:
		g.irBindNameAt(lw, s, name, valueNode, value)
		if reassign:
			g.irReassigned(lw, s, name, at, valueNode)
		return
	roots, borrows = g.irBindingRoots(lw, s, valueNode)
	lam = g.irPointedCaptures(lw, valueNode) if nodes[valueNode].kind == nLambda and
		g.irFlagged(valueNode, flagLocalLambda)
		else []
	before = lw.names.len
	g.irBindNameAt(lw, s, name, valueNode, value)
	if lw.names.len != before + 1 or lw.vals[before].isEmpty: return
	if not lam.isEmpty:
		lw.localLambdas[before] = valueNode
		lw.irNoteBorrow(lw.vals[before][0], false, lam, 2)
		return
	vt = typeOf(nodes, valueNode)
	copies = borrows and not g.c.isRefLike(vt) and g.c.copiesFreely(vt)
	# a for loop's name over a mut place (forByIndex's `x = mut ref xs[$i]`): the element is its alone
	alone = borrows and nodes[s].hasFlag(flagInternal) and nodes[valueNode].kind == nUnary and
		nodes[valueNode].ival == unMutRef and not roots.isEmpty
	if alone and roots[0] != "":
		lw.exclusive[before] = roots[0].copy()
	lw.irNoteBorrow(
		lw.vals[before][0],
		borrows,
		roots,
		3 if alone else 1 if copies else 0,
		i64(valueNode)
	)
