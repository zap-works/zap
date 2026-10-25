# Checks against a length (spec 2.6): a condition that compares an index with a list's or a text's
# length (`i < xs.len`, `at + 4 <= d.len`, `not xs.isEmpty`, `n` bound to `xs.len`) proves the
# indexes it bounds inside, where it holds: in the block an `if` runs, after an `if` whose block
# leaves, in a `while`'s body and on the right of `and`. A fact ends where its index or its
# list's length may change: each statement that may change them (an assignment, a `mut` argument
# or borrow, a method that changes the list or what holds it, a call of a function value), a loop
# whose body may, a lambda's body for a `mut` one. Writing an element keeps the length. The xs[i]
# proven are marked flagInBounds: no check is made.

alias nodes = c.nodes
alias tys = c.types

# index + below < the length of the list at root's path
type LenFact:
	index i64   # the index's variable (Checker.vars), -1 for none (below < the length)
	root i64   # the list's variable (Checker.vars)
	path str   # the list below it (".items")
	below i64
	scope i64   # the scope it was found in (Checker.scopeStarts.len): it ends with it

# a sum of a list's length, an index's variable and a number, each length and variable taken
# once, added (1) or subtracted (-1) or absent (0)
type Linear:
	root i64   # the list's variable (Checker.vars), -1 for none
	path str
	rootSign i64
	index i64   # the index's variable, -1 for none
	indexSign i64
	plus i64

# the literals a fact adds or compares stay this small, so no sum of them overflows
smallTerm = 1_099_511_627_776

fn small(n i64):
	n >= -smallTerm and n <= smallTerm

# the variable a name binds where it is read (the binding a narrowed copy stands for), else -1
fn bindingOf(c Checker, name str):
	i = c.vars.len - 1
	while i >= 0:
		if c.vars[i].name == name and not c.vars[i].narrowed: return i
		i -= 1
	-1

# the type variable v is read as here: a narrower range a check just made proves (ranges.zap)
fn readType(mut c Checker, v i64) TypeId:
	i = c.vars.len - 1
	while i > v:
		if c.vars[i].narrowed and c.vars[i].name == c.vars[v].name: return c.derefType(c.vars[i].ty)
		i -= 1
	c.derefType(c.vars[v].ty)

# the local variable at the root of place e (self for a field named bare) and the path below it,
# else -1
fn fixedPlace(c Checker, e NodeId):
	found, under = c.placePath(e)
	r = found ?? return (-1, "")
	if nodes[r].kind != nIdent or nodes[r].hasFlag(flagModuleVar): return (-1, "")
	name, path = c.selfPlace(nodes[r].text, under)
	v = c.bindingOf(name)
	if v < 0 or c.vars[v].isField: return (-1, "")
	(v, path)

# e as a Linear: a number, an integer variable, a length (`xs.len`, a name bound to one), and
# sums and differences of those; none for any other
fn linearOf(mut c Checker, e NodeId) Linear?:
	x = c.unreferenced(c.unwidened(e))
	if foldedInt(nodes, x, x: none) is n: return Linear(-1, "", 0, -1, 0, n) if small(n) else none
	k = nodes[x].kind
	if k == nBinary and (nodes[x].ival == binAdd or nodes[x].ival == binSub):
		a = try c.linearOf(nodes[x].kids[0])
		b = try c.linearOf(nodes[x].kids[1])
		return a.sumOf(b, 1 if nodes[x].ival == binAdd else -1)
	if k == nIdent and not nodes[x].hasFlag(flagModuleVar):
		v = c.bindingOf(nodes[x].text)
		if v < 0 or c.vars[v].isField or c.tKind(c.derefType(c.vars[v].ty)) != tInt: return none
		r = c.vars[v].lenRoot
		if r >= 0 and not (c.vars[r].isMut and c.isCapturedVar(v)):   # (a lambda runs later)
			return Linear(r, c.vars[v].lenPath.copy(), 1, -1, 0, c.vars[v].lenPlus)
		return Linear(-1, "", 0, v, 1, 0)
	place = try c.lenReceiver(x)
	if c.tKind(c.derefType(typeOf(nodes, place))) not in [tList, tStr]: return none
	root, path = c.fixedPlace(place)
	none if root < 0 else Linear(root, path, 1, -1, 0, 0)

# a + sign * b, none when a length or a variable would be taken twice or the number grows big
fn sumOf(a Linear, b Linear, sign i64) Linear?:
	if a.rootSign != 0 and b.rootSign != 0 or a.indexSign != 0 and b.indexSign != 0: return none
	plus = a.plus + sign * b.plus
	if not small(plus): return none
	out = Linear(a.root, a.path.copy(), a.rootSign, a.index, a.indexSign, plus)
	if b.rootSign != 0:
		out.root = b.root
		out.path = b.path.copy()
		out.rootSign = sign * b.rootSign
	if b.indexSign != 0:
		out.index = b.index
		out.indexSign = sign * b.indexSign
	out

# what `l op r` holding says of a length, noted: l - r op 0 written length - index + plus op 0,
# so the index plus -plus (or less) lies below the length
fn noteLengthCheck(mut c Checker, op i64, l NodeId, r NodeId):
	a = c.linearOf(l) ?? return
	b = c.linearOf(r) ?? return
	d = a.sumOf(b, -1) ?? return
	held = op
	if d.rootSign == -1:
		d = sumOf(Linear(-1, "", 0, -1, 0, 0), d, -1) ?? return
		held = mirroredComparison(op)
	if d.rootSign != 1 or d.indexSign == 1: return
	below = -d.plus
	if held == binGe or held == binEq:
		below -= 1
	elif held == binNe and d.indexSign == 0 and d.plus == 0:
		below = 0   # a length not 0 is at least 1
	elif held != binGt:
		return
	c.lenFacts.push(LenFact(d.index, d.root, d.path.copy(), below, c.scopeStarts.len))

# `for v in lo..hi`, hi a length (`xs.len - 1`, `n.min(xs.len)`): v below it, while the body
# leaves the length alone (checkLoopBody forgets it where it may not)
fn noteLoopLength(mut c Checker, iter NodeId, v i64):
	if nodes[iter].kind != nRange or nodes[iter].kids.len != 2 or nodes[iter].ival == 2: return
	his = [nodes[iter].kids[1]]
	hi = c.unwidened(his[0])
	if nodes[hi].kind == nCall and nodes[hi].kids.len == 2 and
		nodes[nodes[hi].kids[0]].kind == nField and
		nodes[nodes[hi].kids[0]].text == "min":
		his = [nodes[nodes[hi].kids[0]].kids[0], nodes[hi].kids[1]]   # below either
	for h in his:
		l = c.linearOf(h) ?? continue
		if l.rootSign != 1 or l.indexSign != 0: continue
		below = -l.plus - (1 if nodes[iter].ival == 1 else 0)
		c.lenFacts.push(LenFact(v, l.root, l.path.copy(), below, c.scopeStarts.len))

# `xs.isEmpty` failing (truth false): xs has an element
fn noteEmptyCheck(mut c Checker, e NodeId, truth bool):
	if truth or nodes[e].kind != nCall or nodes[e].kids.len != 1: return
	callee = nodes[e].kids[0]
	if nodes[callee].kind != nField or nodes[callee].text != "isEmpty" or
		nodes[callee].kids.len != 1:
		return
	place = nodes[callee].kids[0]
	if c.tKind(c.derefType(typeOf(nodes, place))) not in [tList, tStr]: return
	root, path = c.fixedPlace(place)
	if root >= 0: c.lenFacts.push(LenFact(-1, root, path, 0, c.scopeStarts.len))

# `n = xs.len` (or `last = xs.len - 1`), n immutable: n reads as xs's length (plus the number);
# `xs = zeros(k)` or `fill(k, x)`, k a number: xs holds k elements (while nothing changes its length)
fn noteLengthBinding(mut c Checker, v i64, value NodeId):
	if c.madeLength(value) is n and n > 0:
		c.lenFacts.push(LenFact(-1, v, "", n - 1, c.scopeStarts.len))
	if c.vars[v].isMut: return
	l = c.linearOf(value) ?? return
	if l.rootSign != 1 or l.indexSign != 0: return
	c.vars[v].lenRoot = l.root
	c.vars[v].lenPath = l.path.copy()
	c.vars[v].lenPlus = l.plus
	c.lengthNames += 1

# the length of `zeros(k)` or `fill(k, x)` (k a number; checked, written as the runtime's listRepeat
# of the one-element list [x]), none for any other value
fn madeLength(c Checker, e NodeId) i64?:
	kids = nodes[e].kids
	if nodes[e].kind != nCall or kids.len != 3 or nodes[kids[1]].kind != nArray or
		nodes[kids[1]].kids.len != 1 or nodes[kids[0]].text != "rt__listRepeat" or
		nodes[kids[0]].kind != nIdent:
		return none
	k = try foldedInt(nodes, c.unwidened(kids[2]), x: none)
	k if small(k) and k >= 0 else none

# whether the facts prove the index of xs[i] (e, a list's or a text's) inside: marked so
fn proveIndexByLength(mut c Checker, e NodeId):
	if nodes[e].hasFlag(flagInternal): return
	nodes[e].flags &= ~flagInBounds
	if c.insideByLength(nodes[e].kids[0], nodes[e].kids[1], 1) or
		c.insideConstant(nodes[e].kids[0], nodes[e].kids[1]):
		nodes[e].flags |= flagInBounds

# whether list is a module's constant list literal (`table = [3, 4, 5]`), which keeps its length,
# and index's range lies inside it
fn insideConstant(mut c Checker, list NodeId, index NodeId):
	if nodes[list].kind != nIdent or c.bindingOf(nodes[list].text) >= 0: return false
	d = c.lookupDecl(nConstDecl, "", nodes[list].text, nodes[list].line, nodes[list].col) ??
		return false
	if nodes[d].hasFlag(flagMut) or nodes[d].kids.isEmpty or
		nodes[nodes[d].kids[0]].kind != nArray:
		return false
	r = c.spanOf(index) ?? return false
	r.lo >= 0 and r.hi < nodes[nodes[d].kids[0]].kids.len

# whether the facts prove xs.loadWord(i) (e) reads inside xs: marked so
fn proveWordByLength(mut c Checker, e NodeId, list NodeId, index NodeId):
	nodes[e].flags &= ~flagInBounds
	if c.insideByLength(list, index, 8): nodes[e].flags |= flagInBounds

# whether the facts prove the slice of list from lo to hi (e, the checker's call) inside it:
# marked so, no check is made
fn proveSliceByLength(mut c Checker, e NodeId, list NodeId, lo NodeId, hi NodeId):
	nodes[e].flags &= ~flagInBounds
	root, path = c.fixedPlace(list)
	if root < 0: return
	a = c.linearOf(lo) ?? return
	b = c.linearOf(hi) ?? return
	if c.atMostLength(a, root, path) and c.atMostLength(b, root, path) and
		c.atLeast(a, 0, root, path) and
		c.notAbove(a, b, root, path):
		nodes[e].flags |= flagInBounds

# whether t is at most the length of the list at root's path
fn atMostLength(mut c Checker, t Linear, root i64, path str):
	if t.rootSign == 1:
		return t.root == root and t.path == path and t.indexSign == 0 and t.plus <= 0
	if t.rootSign != 0 or t.indexSign == -1: return false
	if t.index < 0: return t.plus <= c.knownLength(root, path)
	c.lenFacts.any(.root == root and .path == path and .index == t.index and .below >= t.plus - 1)

# the least length the facts prove the list at root's path holds (an index below it, of a range
# that starts at lo, proves lo + 1)
fn knownLength(mut c Checker, root i64, path str):
	most = 0
	for f in c.lenFacts:
		if f.root != root or f.path != path: continue
		lo = 0
		if f.index >= 0:
			lo, _ = intBounds(tys, c.readType(f.index))
		if small(lo): most = most.max(lo + f.below + 1)
	most

# whether t is at least least (the list at root's path giving a length's)
fn atLeast(mut c Checker, t Linear, least i64, root i64, path str):
	if t.indexSign == -1: return false
	if t.rootSign == 1:
		return t.root == root and t.path == path and t.indexSign == 0 and
			(t.plus >= least or c.knownLength(root, path) + t.plus >= least)
	if t.rootSign != 0: return false
	if t.index < 0: return t.plus >= least
	lo, _ = intBounds(tys, c.readType(t.index))
	lo >= least - t.plus

# whether a is at most b (each at most the list's length)
fn notAbove(mut c Checker, a Linear, b Linear, root i64, path str):
	if a.rootSign == b.rootSign and a.root == b.root and a.indexSign == b.indexSign and
		a.index == b.index:
		return a.plus <= b.plus
	if a.rootSign == 0 and a.indexSign == 0: return c.atLeast(b, a.plus, root, path)
	b.rootSign == 1 and b.indexSign == 0 and b.plus == 0 and c.atMostLength(a, root, path)

# whether the facts prove the width elements of list from index on inside it
fn insideByLength(mut c Checker, list NodeId, index NodeId, width i64):
	if c.lenFacts.isEmpty: return false
	root, path = c.fixedPlace(list)
	if root < 0: return false
	if c.spanOf(index) is r and r.isSpanBounded() and r.lo >= 0 and small(r.hi) and
		r.hi + width - 1 < c.knownLength(root, path):
		return true   # (a byte's value into a table of 256)
	t = c.linearOf(index) ?? return false
	last = t.plus + width - 1
	if t.rootSign == 1 and t.root == root and t.path == path and t.indexSign == 0 and last < 0:
		# xs[xs.len - k]: below the length, and inside once xs holds k elements
		return c.knownLength(root, path) + t.plus >= 0
	if t.rootSign != 0 or t.indexSign == -1 or t.index < 0 and t.plus < 0: return false
	if t.index < 0: return last < c.knownLength(root, path)
	if t.index >= 0:
		lo, _ = intBounds(tys, c.readType(t.index))
		if lo < -t.plus: return false
	c.lenFacts.any(.root == root and .path == path and .index == t.index and last <= .below)

# A list's or a text's length is below 2^62 (each element takes a byte at least), so an index
# known below one plus or minus a small number stays inside a 64-bit integer: such a sum (e,
# `pos + 1` under `pos < d.len`) is marked flagInBounds, which no overflow check is made for.
fn proveSumByLength(mut c Checker, e NodeId):
	if nodes[e].kind != nBinary or nodes[e].hasFlag(flagInternal): return
	nodes[e].flags &= ~flagInBounds
	op = nodes[e].ival
	if op != binAdd and op != binSub or c.lenFacts.isEmpty: return
	t = c.derefType(typeOf(nodes, e))
	if c.tKind(t) != tInt or tys[rangeBase(tys, t)].bits != 64 or isDefined(tys, t): return
	if c.indexPlusSmall(nodes[e].kids[0], nodes[e].kids[1], op == binSub) or
		op == binAdd and c.indexPlusSmall(nodes[e].kids[1], nodes[e].kids[0], false):
		nodes[e].flags |= flagInBounds

# whether x is an index below a length plus a small number and y is small (a number, or of a
# small range), so x + y (x - y when minus) stays inside a 64-bit integer
fn indexPlusSmall(mut c Checker, x NodeId, y NodeId, minus bool):
	s = c.linearOf(x) ?? return false
	if s.rootSign != 0 or s.indexSign != 1 or not c.lenFacts.any(.index == s.index): return false
	yt = c.derefType(typeOf(nodes, y))
	if c.tKind(yt) != tInt or isDefined(tys, yt): return false
	r = c.operandSpan(y, yt, rangeBase(tys, yt))
	if not r.isSpanBounded() or not small(r.lo) or not small(r.hi): return false
	lo, _ = intBounds(tys, c.readType(s.index))
	least = s.plus + (-r.hi if minus else r.lo)   # the most taken from the index
	least >= 0 or lo >= spanDown - least

# the facts of the scope that ends now are forgotten
fn forgetLengths(mut c Checker):
	n = c.scopeStarts.len
	c.lenFacts = c.lenFacts.filter(.scope < n)

# a place a statement may change: a variable's (Checker.vars), at path below it ("" the whole of
# it, "[]" an element, which keeps a list's length)
type Change:
	root i64
	path str

# the facts about what e may change forgotten
fn forgetChangedIndexes(mut c Checker, e NodeId):
	if not c.tracking(): return
	changes = []
	c.changesUnder(e, changes)
	c.forgetChanges(changes)

fn forgetChanges(mut c Checker, changes Change[]):
	if changes.isEmpty: return
	kept = []
	for f in c.lenFacts:
		if not changes.any(c.changeEnds(it, f)): kept.push(f.copy())
	c.lenFacts = kept
	if c.lengthNames == 0: return
	for ch in changes:
		for i in 0..c.vars.len:
			r = c.vars[i].lenRoot
			if r >= 0 and (ch.root == r and c.vars[i].lenPath.startsWith(ch.path) or
					ch.root == -1 and c.vars[r].isMut):
				c.vars[i].lenRoot = -1   # bound to a length that may have changed since

# whether facts or names of lengths are known, which a change may end
fn tracking(c Checker):
	not c.lenFacts.isEmpty or c.lengthNames > 0

# whether a change of ch ends fact f: its index's, its list's length, or of any mut variable
fn changeEnds(c Checker, ch Change, f LenFact):
	ch.root == -1 and c.factIsMut(f) or ch.root == f.index or
		ch.root == f.root and f.path.startsWith(ch.path)

# whether a fact's index or list may change (a mut variable's)
fn factIsMut(c Checker, f LenFact):
	f.index >= 0 and c.vars[f.index].isMut or c.vars[f.root].isMut

# the statement s checked, the facts about what it may change forgotten: before it, but an
# assignment's (or a reassigning let's) own place after its value is read
fn checkForgetting(mut c Checker, s NodeId):
	k = nodes[s].kind
	if k != nAssign and k != nLet or nodes[s].kids.isEmpty:
		c.forgetChangedIndexes(s)
		c.checkStmtOfKind(s)
		return
	c.forgetChangedIndexes(nodes[s].kids[nodes[s].kids.len - 1])
	before = c.bindingOf(nodes[s].text) if k == nLet else -1
	c.checkStmtOfKind(s)
	if not c.tracking(): return
	changes = []
	if k == nAssign:
		c.changesOf(s, changes)
	else:
		# the one it assigns; a new binding has only the facts its value just gave
		v = c.bindingOf(nodes[s].text)
		if v >= 0 and v == before: changes.push((v, ""))
	c.forgetChanges(changes)

# what e and what is under it may change, onto out
fn changesUnder(mut c Checker, e NodeId, mut out Change[]):
	c.changesOf(e, out)
	for kid in nodes[e].kids:
		c.changesUnder(kid, out)
	for sb in nodes[e].sub():
		c.changesUnder(sb, out)

# what e itself may change, onto out: a let naming a variable reassigns it, a call of a function
# value may change any mut variable (root -1)
fn changesOf(mut c Checker, e NodeId, mut out Change[]):
	k = nodes[e].kind
	if k == nLet and not nodes[e].hasFlag(flagMut) and nodes[e].types().isEmpty:
		v = c.bindingOf(nodes[e].text)
		if v >= 0: out.push((v, ""))
	if k == nCall and nodes[e].hasFlag(flagClosure): out.push((-1, ""))
	places = c.placesChanged(e)
	if k == nUnary and nodes[e].ival == unOut: places.push(nodes[e].kids[0])
	for p in places:
		found, under = c.placePath(c.placeUnder(p))
		r = found ?? continue
		if nodes[r].kind != nIdent: continue
		name, path = c.selfPlace(nodes[r].text, under)
		v = c.bindingOf(name)
		if v >= 0: out.push((v, path))

# The facts hidden while a body that runs apart is checked (a lambda's, which runs when it is
# called, keeps the facts of immutable indexes; a function's none): the caller gives them back.
fn hideLengths(mut c Checker, lambda bool):
	hidden = move c.lenFacts
	c.lenFacts = hidden.filter(not c.factIsMut(it)) if lambda else []
	hidden

# A sum in a bounded loop: `mut sum = 0` then a `for` over a list, a text or a range of known size
# adding values of a small range to it (`for b in bytes: sum += b`) never overflows when nothing
# else changes it before or in the loop: each turn adds at most the most of each addition, and a
# loop over a list turns fewer than 2^48 times (each element takes a byte at least). The additions
# (the for s's, its body checked) are marked flagInBounds: no overflow check is made.
listTurns = 281_474_976_710_656

fn proveLoopSums(mut c Checker, s NodeId):
	fnd = c.curFn ?? return
	if nodes[fnd].sub().isEmpty: return
	turns = c.loopTurns(nodes[s].kids[0]) ?? return
	adds = []
	c.loopAdds(nodes[s].sub()[0], adds)
	names str[] = []
	for a in adds:
		if nodes[a].text not in names: names.push(nodes[a].text.copy())
	if names.isEmpty: return
	block = c.blockHolding(nodes[fnd].sub()[0], s) ?? return
	for name in names:
		mine = adds.filter(nodes[it].text == name)
		start = c.sumStart(block, s, name) ?? continue
		if c.changesOfName(nodes[s].sub()[0], name) != mine.len: continue   # changed another way too
		most = 0   # what one turn adds at most
		fits = true
		for a in mine:
			e = nodes[nodes[a].kids[0]].kids[1]
			et = c.derefType(typeOf(nodes, e))
			if c.tKind(et) != tInt or isDefined(tys, et):
				fits = false
				continue
			r = c.operandSpan(e, et, rangeBase(tys, et))
			if not r.isSpanBounded() or r.lo < -65_536 or r.hi > 65_536:
				fits = false
				continue
			most += r.lo.abs().max(r.hi)
		t = typeOf(nodes, nodes[mine[0]].kids[0])
		if not fits or c.tKind(t) != tInt or most > 0 and turns > spanUp / most: continue
		lo, hi = intBounds(tys, rangeBase(tys, t))
		reach = turns * most
		if start - reach < lo or start > hi - reach: continue
		for a in mine:
			nodes[nodes[a].kids[0]].flags |= flagInBounds

# how many times a for over iter turns at most: a range's size by its bounds' values, a list's
# or a text's length (or a range to one) below 2^48; none when that is not known
fn loopTurns(mut c Checker, iter NodeId) i64?:
	if nodes[iter].kind == nRange and nodes[iter].kids.len == 2:
		hi = nodes[iter].kids[1]
		if c.linearOf(hi) is l and l.rootSign == 1 and l.indexSign == 0: return listTurns
		lt = c.derefType(typeOf(nodes, nodes[iter].kids[0]))
		ht = c.derefType(typeOf(nodes, hi))
		if c.tKind(lt) != tInt or c.tKind(ht) != tInt: return none
		a = c.operandSpan(nodes[iter].kids[0], lt, rangeBase(tys, lt))
		b = c.operandSpan(hi, ht, rangeBase(tys, ht))
		if not a.isSpanBounded() or not b.isSpanBounded() or not small(a.lo) or not small(b.hi):
			return none
		return (b.hi - a.lo + 1).max(0)
	if nodes[iter].kind == nRange: return none
	t = c.derefType(typeOf(nodes, iter))
	listTurns if c.tKind(t) in [tList, tStr] else none

# the `name += e` statements under e that run at most once a turn (not in a loop or a lambda of
# their own), onto out
fn loopAdds(c Checker, e NodeId, mut out NodeId[]):
	k = nodes[e].kind
	if k in [nFor, nWhile, nLambda]: return
	if k == nLet and nodes[e].hasFlag(flagCompound) and nodes[e].kids.len == 1 and
		nodes[nodes[e].kids[0]].kind == nBinary and nodes[nodes[e].kids[0]].ival == binAdd:
		out.push(e)
	for kid in nodes[e].kids:
		c.loopAdds(kid, out)
	for sb in nodes[e].sub():
		c.loopAdds(sb, out)

# how many statements under e change the variable name (a let of it, an assignment to it or into
# it, a `mut` borrow of it), lambdas' too
fn changesOfName(c Checker, e NodeId, name str) i64:
	k = nodes[e].kind
	n = 0
	if k == nLet and nodes[e].text == name or
		(k == nAssign or k == nUnary and nodes[e].ival in [unMutRef, unOut]) and
		nodes[c.placeRootNode(nodes[e].kids[0])].text == name:
		n += 1
	for kid in nodes[e].kids:
		n += c.changesOfName(kid, name)
	for sb in nodes[e].sub():
		n += c.changesOfName(sb, name)
	n

# the block under e whose statements hold s, else none
fn blockHolding(c Checker, e NodeId, s NodeId) NodeId?:
	if nodes[e].kind == nBlock and s in nodes[e].kids: return e
	for kid in nodes[e].kids:
		b = c.blockHolding(kid, s)
		if b != none: return b
	for sb in nodes[e].sub():
		b = c.blockHolding(sb, s)
		if b != none: return b
	none

# the value `mut name = v` before s in block gives name, when v is known and nothing between
# changes it; none for any other
fn sumStart(mut c Checker, block NodeId, s NodeId, name str):
	start i64? = none
	for st in nodes[block].kids:
		if st == s: return start
		if nodes[st].kind == nLet and nodes[st].text == name and nodes[st].hasFlag(flagMut) and
			not nodes[st].kids.isEmpty:
			start = c.knownInt(nodes[st].kids[0])
		elif c.changesOfName(st, name) > 0:
			start = none
	none
