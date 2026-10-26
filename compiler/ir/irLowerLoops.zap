# The lowering of while and for loops (irLower.zap).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# while c { body }: the test before the loop and again at its end (one jump an iteration)
fn irWhile(mut g Gen, mut lw IrLower, s NodeId):
	if not nodes[s].names().isEmpty or g.irClassOf(g.ty(nodes[s].kids(kidIds)[0])) != irInt:
		lw.irFail("while over a pattern")
		return
	l = lw.f.irShell()
	g.irCond(lw, nodes[s].kids(kidIds)[0], l.body, l.end)
	lw.f.blocks[l.body].loopTop = true
	g.irLoopBody(lw, nodes[s].sub()[0], l.body, l)
	lw.f.irEnter(l.cont)
	g.irCond(lw, nodes[s].kids(kidIds)[0], l.body, l.end)
	lw.irLoopDone(l)

# the loop l noted (its body, its step and the blocks made after its end until now), filling
# continuing after it
fn irLoopDone(mut lw IrLower, l IrShell):
	blocks = [l.body, l.cont]
	blocks.extend(((l.end + 1)..lw.f.blocks.len).map(it))
	lw.f.loops.push(IrLoop(l.pre, blocks))
	lw.f.irEnter(l.end)

# the body of the loop l lowered in block at (its body's, or one the loop's code reaches first)
fn irLoopBody(mut g Gen, mut lw IrLower, body NodeId, at i64, l IrShell):
	lw.breaks.push(l.end)
	lw.conts.push(l.cont)
	lw.loopOwned.push(lw.owned.len)
	lw.loopArenas.push(lw.arenas)
	lw.f.irEnter(at)
	g.irBlockValue(lw, body, false)
	lw.f.irJumpTo(l.cont)
	lw.breaks.pop()
	lw.conts.pop()
	lw.loopOwned.pop()
	lw.loopArenas.pop()

# for i in lo..hi (by step): the end and step read once, the start after them unless it calls
# and they call too (the order written); a step that is not a literal is checked to be positive
fn irFor(mut g Gen, mut lw IrLower, s NodeId):
	spans = g.irForSpans(lw, s)
	g.irForAt(lw, s)
	for id in spans:
		lw.irNoted(noteReadTo, id, "")

fn irForAt(mut g Gen, mut lw IrLower, s NodeId):
	if g.irUnrolledFor(lw, s): return
	iter = nodes[s].kids(kidIds)[0]
	if g.tyK(g.ty(iter)) == tSeq:
		g.irForSeq(lw, s)
		return
	if g.irIsList(g.irListType(iter)) or g.tyK(g.irListType(iter)) == tArray:
		g.irForList(lw, s)
		return
	if g.c.isSplitLoop(iter):
		g.irForSplit(lw, s)
		return
	if g.c.isLinesCall(iter) and g.tyK(g.ty(iter)) == tStr:
		g.irForLines(lw, s)
		return
	if nodes[iter].kind != nRange or g.tyK(g.ty(iter)) != tInt:
		lw.irFail("for over a collection of {typeStr(tys, g.ty(iter))} (kind {nodes[iter].kind})")
		return
	stepped = nodes[iter].kids(kidIds).len > 2
	loE = nodes[iter].kids(kidIds)[0]
	loFirst = g.exprMayCall(loE) and
		(
			g.exprMayCall(nodes[iter].kids(kidIds)[1]) or
				(stepped and g.exprMayCall(nodes[iter].kids(kidIds)[2]))
		)
	lo = -1
	if loFirst:
		lo = g.irExpr(lw, loE)
	hi = g.irExpr(lw, nodes[iter].kids(kidIds)[1])
	step = -1
	if stepped:
		step = g.irExpr(lw, nodes[iter].kids(kidIds)[2])
		stepLeast, _ = intBounds(tys, g.ty(nodes[iter].kids(kidIds)[2]))
		if nodes[nodes[iter].kids(kidIds)[2]].kind != nInt and stepLeast <= 0:   # (a range's counter may be above 0)
			zero = lw.irConstOf(irInt, 0)
			lw.irPut(IrInst(op = irFailIf, a = step, b = zero, cond = irLe, imm = g.failStep))
	if not loFirst:
		lo = g.irExpr(lw, loE)
	i0 = lo
	down = stepped and nodes[nodes[iter].kids(kidIds)[2]].kind == nInt and   # n..0 step -1: while above hi
		nodes[nodes[iter].kids(kidIds)[2]].text.startsWith("-")
	uns = g.irUnsigned(g.ty(iter))
	if not stepped and not uns and g.irJammed(lw, s, lo, hi) is rest:
		lo = rest   # turns two at a time first (irJam.zap)
	if not stepped and not uns:
		lo = g.irVectorLoop(lw, s, lo, hi)   # the scalar loop goes on where the vector steps end
	i = lw.f.irVreg(irInt)   # (lo copied in once the checks ahead are made: a loop not run needs no counter)
	# i in 0..xs.len of an xs the body does not grow or shrink: xs[i] needs no check, and its
	# address is a pointer stepped with i
	list = g.irLengthOf(lw, nodes[iter].kids(kidIds)[1])
	mark = lw.proven.len
	steps = []
	if list >= 0 and nodes[loE].kind == nInt and g.intLitValue(loE) >= 0 and lo == i0 and
		(not stepped or nodes[nodes[iter].kids(kidIds)[2]].kind == nInt) and not down and
		not g.irResizes(
			nodes[s].sub()[0],
			nodes[nodes[nodes[iter].kids(kidIds)[1]].kids(kidIds)[0]].kids(kidIds)[0]
		):
		stride = elemStride(
			g.c,
			innerOf(
				tys,
				g.ty(nodes[nodes[nodes[iter].kids(kidIds)[1]].kids(kidIds)[0]].kids(kidIds)[0])
			)
		)
		items = lw.irHeader(list, 0)
		ptr = lw.f.irVreg(irInt)
		irPut(
			lw,
			IrInst(
				op = irAdd,
				dst = ptr,
				a = items,
				b = lw.irConstOf(irInt, g.intLitValue(loE) * stride)
			)
		)
		lw.proven.push(IrProven(list, i, ptr))
		steps.push((ptr, stride * (g.intLitValue(nodes[iter].kids(kidIds)[2]) if stepped else 1)))
	checks = lw.checked.len
	skip = -1
	if not uns and not down:
		skip = g.irCheckAhead(lw, s, lo, hi, step if stepped else -1)   # in an inlined body too: its loops are the caller's now
	lw.irPut(IrInst(op = irCopy, dst = i, a = lo))
	irCountedLoop(
		g,
		lw,
		s,
		i,
		hi,
		step if stepped else lw.irConstOf(irInt, 1),
		uns,
		[i],
		-1,
		none,
		steps,
		irGt if down else irLt,
		skip
	)
	lw.proven.truncate(mark)
	lw.checked.truncate(checks)

# for i in a..b of literals, of irUnrollTurns turns at most (a fixed array's four elements), its
# body small, calling nothing (a value given away stays the loop's error) and without a loop, a
# break, a continue, a return, a yield or a lambda: the body once
# for each value of i, one after the other, so the counter, its test and its jump go (as LLVM
# unrolls a short loop of a known count)
fn irUnrolledFor(mut g Gen, mut lw IrLower, s NodeId) bool:
	iter = nodes[s].kids(kidIds)[0]
	if nodes[iter].kind != nRange or nodes[iter].kids(kidIds).len != 2 or
		not nodes[s].names().isEmpty or
		g.tyK(g.ty(iter)) != tInt:
		return false
	loE = nodes[iter].kids(kidIds)[0]
	hiE = nodes[iter].kids(kidIds)[1]
	if nodes[loE].kind != nInt or nodes[hiE].kind != nInt: return false
	lo = g.intLitValue(loE)
	hi = g.intLitValue(hiE)
	body = nodes[s].sub()[0]
	if hi - lo < 1 or hi - lo > irUnrollTurns or g.holdsKind(body, nWhile, nFor, true) or
		g.holdsKind(body, nBreak, nContinue, true) or g.holdsKind(body, nReturn, nYield, true) or
		g.holdsKind(body, nLambda, -1, true) or not g.irCallFree(body) or
		g.irNodeCount(body, irUnrollNodes + 1) > irUnrollNodes:
		return false
	for k in lo..hi:
		mark = lw.names.len
		lw.irDeclare(nodes[s].text, [lw.irConstOf(irInt, k)])
		g.irBlockValue(lw, body, false)
		g.irScopeEnd(lw, mark)
	true

irUnrollTurns = 4
irUnrollNodes = 40   # the body's nodes (irNodeCount), each written irUnrollTurns times at most

# the checks ahead (risingIndexes): the
# elements the loop reads or writes every step at an index rising with the counter are checked,
# when the loop runs, at its first and last step (lo + a whole number of steps), the error a
# step would stop at, and not inside it; so is their indexes' arithmetic. Filling goes on where
# lo < hi held; the block the other way goes to (-1: no test made)
fn irCheckAhead(mut g Gen, mut lw IrLower, s NodeId, lo i64, hi i64, step i64):
	body = nodes[s].sub()[0]
	v = nodes[s].text.copy()
	found = []
	names = g.irLoopLocals(lw, body)
	for st in nodes[body].kids(kidIds).copy():
		if g.leavesEarly(st): break
		g.risingIndexes(st, v, body, names, found)
	if found.isEmpty: return -1
	runB = lw.f.irBlock()
	skipB = lw.f.irBlock()
	lw.irBranchIf(lo, irLt, hi, runB, skipB)
	lw.f.irEnter(runB)
	one = lw.irConstOf(irInt, 1)
	last = lw.irDef(irInt, IrInst(op = irSub, a = hi, b = one))
	if step >= 0:
		# hi - 1 - (hi - 1 - lo) % step
		span = lw.irDef(irInt, IrInst(op = irSub, a = last, b = lo))
		rest = lw.irDef(irInt, IrInst(op = irRem, a = span, b = step))
		lw.irPut(IrInst(op = irSub, dst = last, a = last, b = rest))
	for at in [lo, last]:
		mark = lw.names.len
		lw.irDeclare(v, [at])
		for e in found:
			items, idx, elem = g.irElement(lw, e)
			_ = items
			_ = idx
			_ = elem
		g.irScopeEnd(lw, mark)
	lw.checked.extend(found)
	for e in found:
		g.indexArithmetic(nodes[e].kids(kidIds)[1], lw.checked)
	skipB

# the form's: its names, by the types the checker gave
fn irLoopLocals(mut g Gen, mut lw IrLower, body NodeId):
	out = LoopLocals(lists = [], ints = [])
	idents = []
	g.identsIn(body, idents)
	for e in idents:
		nm = nodes[e].text.copy()
		if nm in out.lists or nm in out.ints: continue
		if not lw.irInScope(nm): continue
		t = g.ty(e)
		k = g.tyK(tys[t].inner) if g.tyK(t) == tRef else g.tyK(t)
		if k == tList or k == tStr:
			out.lists.push(nm)
		elif k == tInt and g.tyK(t) != tRef:   # (a reference's number may change by a store elsewhere)
			out.ints.push(nm)
	out

# the list whose length e reads (`xs.len` of a list parameter), or -1
fn irLengthOf(mut g Gen, mut lw IrLower, e NodeId):
	if nodes[e].kind != nCall or nodes[e].kids(kidIds).len != 1 or
		nodes[nodes[e].kids(kidIds)[0]].kind != nField or
		nodes[nodes[e].kids(kidIds)[0]].text != "len":
		return -1
	obj = nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0]
	if nodes[obj].kind != nIdent or not g.irIsList(g.ty(obj)): return -1
	if g.irFind(lw, nodes[obj].text.copy()) is v and v.len == 1: return v[0]
	-1

# whether code e may change the length of the list named by xs: a call given xs, or a method
# of xs other than length
fn irResizes(g Gen, e NodeId, xs NodeId) bool:
	if nodes[e].kind == nCall:
		callee = nodes[e].kids(kidIds)[0]
		if nodes[callee].kind == nField and nodes[callee].text != "len" and
			mentions(nodes, kidIds, nodes[callee].kids(kidIds)[0], true, nodes[xs].text):
			return true
		for a in nodes[e].kidsFrom(kidIds, 1):
			if mentions(nodes, kidIds, a, true, nodes[xs].text): return true
	nodes[e].kids(kidIds).any(g.irResizes(it, xs)) or nodes[e].sub().any(g.irResizes(it, xs))

# for x in seq: the body is the walk's turn (continue: the next element, break: the walk left)
fn irForSeq(mut g Gen, mut lw IrLower, s NodeId):
	each = g.irEachBegin(lw, nodes[s].kids(kidIds)[0])
	if not lw.ok: return
	mark = lw.names.len
	lw.irDeclare(nodes[s].text, g.irEachValue(lw, each))
	g.irLoopBody(lw, nodes[s].sub()[0], lw.f.cur, each.shell)
	g.irScopeEnd(lw, mark)
	g.irEachEnd(lw, each)

# for x in xs: the length and the items read once (the body cannot change xs), each element
# read in turn
fn irForList(mut g Gen, mut lw IrLower, s NodeId):
	iter = nodes[s].kids(kidIds)[0]
	elem = innerOf(tys, g.irListType(iter))
	array = g.tyK(g.irListType(iter)) == tArray   # its elements where it is, its length fixed
	list = g.irListAddr(lw, iter) if array else g.irReadListAddr(lw, iter)
	if not lw.ok: return
	n = lw.irConstOf(irInt, tys[g.irListType(iter)].bits) if array else lw.irHeader(list, 8)
	items = list if array else lw.irHeader(list, 0)
	i = lw.irConstOf(irInt, 0)
	counter = lw.irDef(irInt, IrInst(op = irCopy, a = i))
	ptr = lw.irDef(irInt, IrInst(op = irCopy, a = items))
	irCountedLoop(
		g,
		lw,
		s,
		counter,
		n,
		lw.irConstOf(irInt, 1),
		false,
		[],
		ptr,
		elem,
		[(ptr, g.c.elemStride(elem))]
	)

# a loop over pieces of a text (split, lines): the text's bytes and length read, the position
# reached (0 at first), a slot for the window the loop's name refers to, and the loop's blocks,
# the test `pos cond length` entering the body or leaving
type IrTextLoop:
	bytes i64
	length i64
	pos i64
	window i64
	l IrShell

fn irTextLoop(mut g Gen, mut lw IrLower, bytes i64, length i64, cond i64):
	pos = lw.irConstOf(irInt, 0)
	window = lw.irNamedWindowSlot()
	l = lw.f.irShell()
	lw.irBranchIf(pos, cond, length, l.body, l.end)
	lw.f.irEnterBody(l)
	IrTextLoop(bytes, length, pos, window, l)

# the byte at bytes + at, as an integer
fn irByteAt(mut lw IrLower, bytes i64, at i64) i64:
	lw.irDef(irInt, IrInst(op = irLoad, a = bytes, b = at, scale = 1, size = 1, uns = true))

# to `target` when the byte at bytes + at `cond` value holds; filling goes on in a new block for
# the other case
fn irByteBranch(mut lw IrLower, bytes i64, at i64, cond i64, value i64, target i64):
	byte = lw.irByteAt(bytes, at)
	other = lw.f.irBlock()
	lw.irBranchIf(byte, cond, lw.irConstOf(irInt, value), target, other)
	lw.f.irEnter(other)

# for part in text.split(sep): the parts between the separators as
# windows of the text, a window per turn in a slot of the statement; the text's end is a part
# too (a trailing separator gives an empty last part)
fn irForSplit(mut g Gen, mut lw IrLower, s NodeId):
	iter = nodes[s].kids(kidIds)[0]
	textBytes, textLength = g.irTextWords(lw, nodes[nodes[iter].kids(kidIds)[0]].kids(kidIds)[0])
	sepBytes, sepLen = g.irTextWords(lw, nodes[iter].kids(kidIds)[1])
	if not lw.ok: return
	tl = g.irTextLoop(lw, textBytes, textLength, irLe)
	bytes, length, pos, window, l = tl.bytes, tl.length, tl.pos, tl.window, tl.l
	# the part's end: the next separator, or the text's end
	found = g.irCallRt(lw, "findIn", [bytes, length, pos, sepBytes, sepLen])
	if not lw.ok: return
	end = lw.f.irVreg(irInt)
	irPut(
		lw,
		IrInst(
			op = irSelect,
			dst = end,
			a = found[0],
			b = lw.irConstOf(irInt, 0),
			c = length,
			d = found[0],
			cond = irLt
		)
	)
	start = lw.irDef(irInt, IrInst(op = irAdd, a = bytes, b = pos))
	lw.irPut(IrInst(op = irStore, a = window, c = start))
	count = lw.irDef(irInt, IrInst(op = irSub, a = end, b = pos))
	lw.irPut(IrInst(op = irStore, a = window, c = count, imm = 8))
	mark = lw.names.len
	lw.irDeclare(nodes[s].text, [window])
	g.irLoopBody(lw, nodes[s].sub()[0], l.body, l)
	g.irScopeEnd(lw, mark)
	lw.f.irEnter(l.cont)
	next = lw.irDef(irInt, IrInst(op = irAdd, a = end, b = sepLen))
	lw.irPut(IrInst(op = irCopy, dst = pos, a = next))
	lw.irBranchIf(pos, irLe, length, l.body, l.end)
	lw.irLoopDone(l)

# for line in text.lines(): the lines as windows of the text, split at
# newlines, a carriage return before one left out; nothing after a final newline
fn irForLines(mut g Gen, mut lw IrLower, s NodeId):
	iter = nodes[s].kids(kidIds)[0]
	textBytes, textLength = g.irTextWords(lw, nodes[nodes[iter].kids(kidIds)[0]].kids(kidIds)[0])
	if not lw.ok: return
	tl = g.irTextLoop(lw, textBytes, textLength, irLt)
	bytes, length, pos, window, l = tl.bytes, tl.length, tl.pos, tl.window, tl.l
	scanB = lw.f.irBlock()   # the loop's other blocks come after its end: irLoopDone counts them in
	stepB = lw.f.irBlock()
	foundB = lw.f.irBlock()
	# the scan for the newline, from the line's start
	cur = lw.irDef(irInt, IrInst(op = irCopy, a = pos))
	lw.f.irJoin(scanB)
	lw.irBranchIf(cur, irGe, length, foundB, stepB)
	lw.f.irEnter(stepB)
	lw.irByteBranch(bytes, cur, irEq, 10, foundB)   # a newline ends the line
	lw.irPut(IrInst(op = irAdd, dst = cur, a = cur, b = lw.irConstOf(irInt, 1)))
	lw.f.irJumpTo(scanB)
	lw.f.irEnter(foundB)
	start = lw.irDef(irInt, IrInst(op = irAdd, a = bytes, b = pos))
	lw.irPut(IrInst(op = irStore, a = window, c = start))
	count = lw.irDef(irInt, IrInst(op = irSub, a = cur, b = pos))
	# a carriage return before the newline is not the line's
	lastAt = lw.irDef(irInt, IrInst(op = irSub, a = cur, b = lw.irConstOf(irInt, 1)))
	lastB = lw.f.irBlock()
	setB = lw.f.irBlock()
	lw.irBranchIf(count, irGt, lw.irConstOf(irInt, 0), lastB, setB)
	lw.f.irEnter(lastB)
	lw.irByteBranch(bytes, lastAt, irNe, 13, setB)   # not a carriage return: the length stands
	lw.irPut(IrInst(op = irSub, dst = count, a = count, b = lw.irConstOf(irInt, 1)))
	lw.f.irJoin(setB)
	lw.irPut(IrInst(op = irStore, a = window, c = count, imm = 8))
	lw.irPut(IrInst(op = irAdd, dst = pos, a = cur, b = lw.irConstOf(irInt, 1)))   # past the newline before the body: continue goes on
	mark = lw.names.len
	lw.irDeclare(nodes[s].text, [window])
	g.irLoopBody(lw, nodes[s].sub()[0], setB, l)   # the body goes on in setB
	g.irScopeEnd(lw, mark)
	lw.f.irEnter(l.cont)
	lw.irBranchIf(pos, irLt, length, l.body, l.end)
	lw.irLoopDone(l)

# the loop of a for: counter from its value while below hi, by step; the body's name bound to
# leaves, or (at >= 0) to the element at address at, of type elem; each pointer of steps moved
# on by its increment with the counter
fn irCountedLoop(
	mut g Gen,
	mut lw IrLower,
	s NodeId,
	counter i64,
	hi i64,
	step i64,
	uns bool,
	leaves i64[],
	at i64,
	elem TypeId?,
	steps (i64, i64)[],
	going i64 = irLt,
	skip i64 = -1,   # where the test `counter going hi` failed, already made (irCheckAhead): the loop entered
	body NodeId? = none,   # the body lowered (s's own when none)
	next str = ""   # a name declared counter + 1 in it (irJam.zap)
):
	l = lw.f.irShell()
	if skip >= 0:
		lw.f.irJumpTo(l.body)
	else:
		lw.irBranchIf(counter, going, hi, l.body, l.end, uns = uns)
	lw.f.irEnterBody(l)
	mark = lw.names.len
	if at >= 0:
		et = elem ?? tyError   # (an element at an address has its type)
		if g.irByAddress(et):
			lw.loopElems.push(at)
			root, below = g.c.placePath(nodes[s].kids(kidIds)[0])
			over = ""
			if root is r:
				over = "{nodes[r].text}{below}[]"
			lw.places[at] = "{nodes[s].text}\t{over}"   # the element's name, the place it is in
		lw.irDeclare(nodes[s].text, g.irLoadValue(lw, et, at, -1, g.c.elemStride(et)))
	else:
		lw.irDeclare(nodes[s].text, leaves.copy())
	if next != "":
		lw.irDeclare(
			next,
			[lw.irDef(irInt, IrInst(op = irAdd, a = counter, b = lw.irConstOf(irInt, 1)))]
		)
	g.irLoopBody(lw, body ?? nodes[s].sub()[0], l.body, l)
	g.irScopeEnd(lw, mark)
	lw.f.irEnter(l.cont)
	for (walker, by) in steps:
		lw.irPut(IrInst(op = irAdd, dst = walker, a = walker, b = lw.irConstOf(irInt, by)))
	lw.irPut(IrInst(op = irAdd, dst = counter, a = counter, b = step))
	lw.irBranchIf(counter, going, hi, l.body, l.end, uns = uns)
	lw.irLoopDone(l)
	if skip >= 0:
		lw.f.irEnter(skip)
		lw.f.irJoin(l.end)

# ---------- lists ----------
