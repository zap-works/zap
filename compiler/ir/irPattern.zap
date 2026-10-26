# Patterns in the intermediate form: a match reads its value once, then tries each arm's pattern
# in turn (a test that fails goes on to the next arm) and binds the names of the one that holds
# where the parts are. A value is reached by its address (at), or, when it travels in registers,
# by its leaves (vals, at -1).

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# A walk over an arm's pattern: its tests (fail: the block a failed one goes on to), or once they
# passed (fail -1) its names bound. The tests note what they found for a name (a list's rest, a
# string's capture, a map's lookup: the pattern and the leaves) in made; binding notes the parts'
# names the arm's body assigns (written: the name, its address and type), written back after it.
# a test's find for a pattern: the pattern and the leaves
type PatMade:
	pat NodeId
	leaves i64[]

type PatWalk:
	fail i64
	body NodeId
	made PatMade[] = []
	written IrArmWrite[] = []
	roots str[] = []   # the places the scrutinee is or points into: its names borrow them
	scrut NodeId? = none   # the scrutinee read as leaves: where a `mut` name's word was

# match e: each arm's pattern tested, its names bound, then its condition and body (irArmRest);
# with want, the arms' values are its value
fn irMatchPatterns(mut g Gen, mut lw IrLower, e NodeId, want bool) i64[]:
	scrut = nodes[e].kids(kidIds)[0]
	st = g.ty(scrut)
	at = -1
	vals = []
	if g.irByAddress(st):
		at = g.irAddressOf(lw, scrut)
	else:
		vals = g.irValue(lw, scrut)
	if not lw.ok: return []
	if vals.len == 1 and g.irSwitchValues(e, st) is values:
		return g.irMatchSwitch(lw, e, want, st, vals[0], values, [])
	if at >= 0 and g.irSwitchTexts(e, st) is texts:
		return g.irMatchSwitch(lw, e, want, st, g.irTextAsStr(lw, st, at), [], texts)
	# a temporary: its parts move to the names; a name never is one, though an inlined parameter
	# may stand for the caller's temporary, which the rest of the caller still reads
	owner = at >= 0 and not g.irIsPlaceNode(scrut) and lw.owned.any(.slot == at and .name < 0)
	lent = want and g.irMatchLentWhole(lw, e)   # its value the address of the part an arm picks
	result, end, before = g.irMatchOpen(lw, e, want and not lent)
	if lent:
		result = [lw.f.irVreg(irInt)]
	ends = []
	for arm in nodes[e].kidsFrom(kidIds, 1).copy():
		pat = nodes[arm].kids(kidIds)[0]
		armB = lw.f.irBlock()
		nextB = lw.f.irBlock()
		body = nodes[arm].kids(kidIds)[1] if nodes[arm].kids(kidIds).len > 1
			else nodes[arm].sub()[0]
		w = PatWalk(fail = nextB, body, roots = g.irScrutRoots(lw, scrut), scrut = scrut if at < 0 else none)
		g.irPattern(lw, w, pat, st, at, vals, true, false)
		if not lw.ok: return []
		lw.f.irJoin(armB)
		mark = lw.names.len
		w.fail = -1
		guarded = not nodes[pat].sub().isEmpty   # its condition may fail: the next arm sees the value whole
		g.irPattern(lw, w, pat, st, at, vals, true, owner and not guarded)
		if not lw.ok: return []
		aw = lw.armWrites.len
		lw.armWrites.extend(w.written.copy())   # a return inside the arm writes them back first
		g.irArmRest(lw, e, arm, mark, nextB, before, ends, result, want, w.written, lent)
		lw.armWrites.truncate(aw)
	g.irMatchClose(lw, e, before, ends, end, result, lent)

irSwitchLeast = 4   # the fewest cases a match is a switch for (fewer are a compare each anyway)

# The case of each arm of match e on a value of type t when a switch can take them: an integer
# literal (or a plain enum's variant) each, no condition, and only the last arm may take any
# value (`_` or a name); none for any other match, or one of fewer arms than irSwitchLeast.
fn irSwitchValues(mut g Gen, e NodeId, t TypeId) i64[]?:
	plain = g.irIsPlainEnum(t)
	if not plain and g.tyK(t) != tInt: return none
	arms = nodes[e].kids(kidIds).len - 1
	values = []
	for i in 0..arms:
		pat = nodes[nodes[e].kids(kidIds)[i + 1]].kids(kidIds)[0]
		k = nodes[pat].ival
		if not nodes[pat].sub().isEmpty: return none
		if i == arms - 1 and (k == patWildcard or k == patBind and nodes[pat].kids(kidIds).isEmpty):
			break
		if k == patLit and not plain and nodes[nodes[pat].kids(kidIds)[0]].kind == nInt:
			values.push(g.intLitValue(nodes[pat].kids(kidIds)[0]))
		elif k == patCtor and plain and nodes[pat].kids(kidIds).isEmpty:
			vi = nodes[declOf(tys, t)].kids(kidIds).findIndex(nodes[it].text == nodes[pat].text) ??
				-1
			if vi < 0: return none
			values.push(vi)
		else:
			return none
	none if values.len < irSwitchLeast else values

# Match e as a switch on the integer x of type t (values), or on the text at x (texts): each arm
# a block of its own (the arms one arm of several patterns became share the first's), a case for
# each value (the first arm of a value takes it), the last arm the default when it takes any value
fn irMatchSwitch(
	mut g Gen,
	mut lw IrLower,
	e NodeId,
	want bool,
	t TypeId,
	x i64,
	values i64[],
	texts str[]
) i64[]:
	result, end, before = g.irMatchOpen(lw, e, want)
	arms = nodes[e].kidsFrom(kidIds, 1).copy()
	unmatched = lw.f.irBlock()   # no arm takes the value (the checker saw every case covered)
	indexOf {i64: i64} = {}   # an arm's node to its index
	blocks i64[] = []   # each arm's block, or that of the first of the arms of its patterns
	sharing = []
	for i, arm in arms:
		indexOf[i64(arm)] = i
		first = indexOf.get(i64(nodes[arm].ival)) ?? i
		sharing.push(first != i)
		blocks.push(blocks[first] if first != i else lw.f.irBlock())
	cases = values.len.max(texts.len)
	other = blocks[arms.len - 1] if cases < arms.len else unmatched
	if texts.isEmpty:
		lw.irIntSwitch(g, x, t, values, blocks, other)
	else:
		g.irStrSwitch(lw, x, texts, blocks, other)
	ends = []
	for i, arm in arms:
		if sharing[i]: continue   # lowered with the first of its patterns' arms
		lw.f.irEnter(blocks[i])
		mark = lw.names.len
		if i >= cases and texts.isEmpty:
			body = nodes[arm].kids(kidIds)[1] if nodes[arm].kids(kidIds).len > 1
				else nodes[arm].sub()[0]
			w = PatWalk(fail = -1, body)
			g.irPattern(lw, w, nodes[arm].kids(kidIds)[0], t, -1, [x], true, false)
			if not lw.ok: return []
		g.irArmRest(lw, e, arm, mark, unmatched, before, ends, result, want, [])
	lw.f.irEnter(unmatched)
	g.irMatchClose(lw, e, before, ends, end, result)

# a jump to blocks[i] when the integer x of type t is values[i] (the first of equal values taking
# it), else to other
fn irIntSwitch(mut lw IrLower, g Gen, x i64, t TypeId, values i64[], blocks i64[], other i64):
	sw = IrSwitch(values = [], targets = [])
	taken {i64: bool} = {}
	for i, v in values:
		if v not in taken:
			taken[v] = true
			sw.values.push(v)
			sw.targets.push(blocks[i])
	# every variant of a plain enum is a case: the value is one of them, and no default is searched
	every = g.irIsPlainEnum(t) and sw.values.len == nodes[declOf(tys, t)].kids(kidIds).len
	lw.irPut(
		IrInst(
			op = irSwitch,
			a = x,
			imm = lw.f.switches.len,
			other,
			cond = 1 if every else 0,
			uns = g.irUnsigned(t)
		)
	)
	lw.f.switches.push(sw)

# on to the walk's fail block unless `a cond b` holds; nothing once the tests passed
fn irPatBranch(mut lw IrLower, w PatWalk, a i64, b i64, cond i64, uns bool):
	if w.fail < 0: return
	ok = lw.f.irBlock()
	lw.irBranchIf(a, cond, b, ok, w.fail, uns = uns)
	lw.f.irEnter(ok)

# a value of type t's leaves: its own, or read from where it is (its address, for a value
# reached by address)
fn irPatLeaves(mut g Gen, mut lw IrLower, t TypeId, at i64, vals i64[]) i64[]:
	if not vals.isEmpty: return vals.copy()
	if g.irByAddress(t): return [at]
	g.irLoadValue(lw, t, at, -1, 0)

# whether a part's pattern takes part in the walk: one that tests something, or (binding) one that
# binds a name
fn irPatWalks(g Gen, w PatWalk, maybePat NodeId?):
	pat = maybePat ?? return false
	k = nodes[pat].ival
	if k == patWildcard: return false
	w.fail < 0 or not (k == patRest or k == patBind and nodes[pat].kids(kidIds).isEmpty)

# an optional's test for a value (some) or for none; where its value is: the word itself (no
# tag), its leaf after the tag, or its address (after the tag, if it has one)
fn irPatPresent(
	mut g Gen,
	mut lw IrLower,
	w PatWalk,
	t TypeId,
	at i64,
	vals i64[],
	some bool
):
	if w.fail >= 0 and vals.isEmpty:
		lw.irPatBranch(
			w,
			g.irTagAt(lw, t, at),
			lw.irConstOf(irInt, 0),
			irNe if some else irEq,
			false
		)
	elif w.fail >= 0:
		lw.irPatBranch(w, vals[0], g.irAbsent(lw, t), irNe if some else irEq, false)   # the tag, or the word
	if g.c.isNicheOption(t):
		return (-1, g.irLoadValue(lw, t, at, -1, 0) if vals.isEmpty else [vals[0]])
	if not vals.isEmpty: return (-1, vals[1..].copy())
	(g.irPayloadAt(lw, t, at), [])

# a side (ok, or the error) of the result t at at tested; its address
fn irPatSide(mut g Gen, mut lw IrLower, w PatWalk, t TypeId, at i64, ok bool) i64:
	if w.fail >= 0:
		tag = lw.irSpotAt(resultTag(), at)
		lw.irPatBranch(w, tag, lw.irConstOf(irInt, 0), irNe if ok else irEq, false)
	lw.irElementAddr(at, -1, 0, g.c.resultPayload(t))

# the side of result t a pattern under it tests (top: the arm's own pattern): whether it is ok
fn irPatOkSide(g Gen, t TypeId, pat NodeId, top bool):
	k = nodes[pat].ival
	if k == patBind and top: return not nodes[pat].bindsError()
	if k == patCtor and nodes[pat].text in ["Ok", "Err"]: return nodes[pat].text == "Ok"
	not g.c.testsError(t, pat)

# the pattern of an optional's value or a result's side: Some(p), Ok(p) and Err(p) give p, any
# other pattern is its own
fn irPatInner(g Gen, pat NodeId) NodeId?:
	if nodes[pat].ival == patCtor and nodes[pat].text in ["Some", "Ok", "Err"]:
		return nodes[pat].kids(kidIds).first
	pat

# field i of struct t: where it is
fn irPatField(mut g Gen, mut lw IrLower, t TypeId, at i64, vals i64[], i i64):
	if not vals.isEmpty:
		start, n = g.irFieldSpan(t, i)
		return (-1, vals[start..start + n].copy())
	(lw.irElementAddr(at, -1, 0, g.c.structFieldOffsetAt(declOf(tys, t), i)), [])

# a list's element i of n (its pattern's parts around the rest r, -1 without one): its address
fn irPatElement(
	mut lw IrLower,
	items i64,
	length i64,
	stride i64,
	i i64,
	n i64,
	r i64
) i64:
	if r < 0 or i < r: return lw.irElementAddr(items, -1, 0, i * stride)
	lw.irElementAddr(items, lw.irPatLess(length, n - i), stride, 0)   # counted from the end

# a window { ptr + from, to - from } over a str's bytes or a list's elements (from scaled by stride)
fn irPatWindow(mut lw IrLower, ptr i64, from i64, to i64, stride i64):
	start = lw.irDef(irInt, IrInst(op = irAdd, a = ptr, b = lw.irScaled(from, stride)))
	n = lw.irDef(irInt, IrInst(op = irSub, a = to, b = from))
	slot = lw.irNamedWindowSlot()
	lw.irPut(IrInst(op = irStore, a = slot, c = start, header = true))
	lw.irPut(IrInst(op = irStore, a = slot, c = n, imm = 8, header = true))
	slot

# n - k, of n a value
fn irPatLess(mut lw IrLower, n i64, k i64) i64:
	lw.irDef(irInt, IrInst(op = irSub, a = n, b = lw.irConstOf(irInt, k)))

# whether the runtime's test name of the str at s and the literal text holds
fn irPatStrTest(mut g Gen, mut lw IrLower, w PatWalk, name str, s i64, text str):
	r = g.irCallRt(lw, name, [s, g.irStrLiteral(lw, text)])
	if lw.ok:
		lw.irPatBranch(w, r[0], lw.irConstOf(irInt, 0), irNe, false)

# what a test noted for a pattern, or none
fn irPatMade(w PatWalk, pat NodeId) i64[]?:
	if w.made.find(.pat == pat) is m: return m.leaves.copy()
	none

# a name a test found the value of (a list's rest, a string's capture), declared
fn irPatDeclareMade(g Gen, mut lw IrLower, w PatWalk, pat NodeId):
	if nodes[pat].ival == patWildcard or nodes[pat].text == "": return
	if w.irPatMade(pat) is leaves:
		lw.irDeclare(nodes[pat].text, leaves)

# A name the pattern binds declared, the value of type t where it is: a temporary's part moved
# out to one of its own (owner), a part reached by address lent there, plain data read (and
# written back at the arm's end when the arm assigns it or the name is written `mut`); a name
# an `is` test binds (tested) is a local of its own, so the ownership check sees it given away
fn irPatDeclare(
	mut g Gen,
	mut lw IrLower,
	mut w PatWalk,
	name str,
	t TypeId,
	at i64,
	vals i64[],
	owner bool,
	changes bool,
	tested bool
):
	if not vals.isEmpty:
		lw.irDeclare(name, vals.copy())
		if g.c.isRefLike(t) or g.irByAddress(t) or g.irIsOwnedWord(t) and not owner:
			lw.irNoteBorrow(vals[0], true, w.roots.copy())   # (a box or a map: lent where it is)
		if changes and vals.len == 1 and g.irIsOwnedWord(t) and w.scrut is s and
			g.irMemPlace(lw, s) is mem:
			addr, _ = mem
			lw.wordAt[vals[0]] = addr   # (`mut ref` of the name: the place it was read from)
		return
	if owner and g.irOwnedByAddress(t):
		own = g.irTemporary(lw, t)
		g.irMoveTo(lw, own, at, t)
		if tested: lw.irNameOwned(lw.owned.len - 1, lw.names.len, name)
		lw.irDeclare(name, [own])
		return
	if owner and g.irIsOwnedWord(t):
		word = g.irWordMovedOut(lw, t, at)   # a map or a box: the temporary keeps an empty word
		g.irOwnedWord(lw, t, word)
		if tested: lw.irNameOwned(lw.owned.len - 1, lw.names.len, name)
		lw.irDeclare(name, [word])
		return
	if g.irByAddress(t):
		lw.irDeclare(name, [at])   # where it is: a borrow
		lw.irNoteBorrow(at, true, w.roots.copy())
		if w.roots.first is root and root != "" and at not in lw.places:
			lw.places[at] = root.copy()   # the ownership check names the scrutinee's place
			lw.f.places[at] = root.copy()
		return
	held = g.irLoadValue(lw, t, at, -1, 0)
	lw.irDeclare(name, held.copy())
	if g.irIsOwnedWord(t) and not held.isEmpty:
		lw.irNoteBorrow(held[0], true, w.roots.copy())
		if changes: lw.wordAt[held[0]] = at
	if changes:
		w.written.push((name.copy(), at, t))

# Pattern pat on a value of type t (top: the match's own, whose optional a name takes the value
# of, and whose result a name the value or, as `error`, the error): its tests, or its names bound
# (owner: what they take may move out to them).
fn irPattern(
	mut g Gen,
	mut lw IrLower,
	mut w PatWalk,
	maybePat NodeId?,
	t TypeId,
	at i64,
	vals i64[],
	top bool,
	owner bool
):
	pat = maybePat ?? return
	if not lw.ok: return
	k = nodes[pat].ival
	if k == patWildcard: return
	sk = g.tyK(t)
	if k == patBind:
		g.irPatternBind(lw, w, pat, t, sk, at, vals, top, owner)
		return
	if sk == tRef and not g.irIsWindow(t):
		ptr = g.irPatLeaves(lw, t, at, vals)   # the address of what it points to
		g.irPattern(lw, w, pat, innerOf(tys, t), ptr[0], [], top, false)
		return
	if sk == tOption:
		absent = k == patNone or k == patCtor and nodes[pat].text == "None"
		inAt, inVals = g.irPatPresent(lw, w, t, at, vals, not absent)
		if not absent:
			g.irPattern(lw, w, g.irPatInner(pat), innerOf(tys, t), inAt, inVals, false, owner)
		return
	if sk == tResult:
		ok = g.irPatOkSide(t, pat, false)
		side = g.irPatSide(lw, w, t, at, ok)
		g.irPattern(lw, w, g.irPatInner(pat), g.irSideType(t, ok), side, [], false, owner)
		return
	if k == patCtor and sk == tEnum:
		g.irPatternEnum(lw, w, pat, t, at, vals, owner)
		return
	if (k == patCtor or k == patTuple) and sk == tStruct:
		sd = declOf(tys, t)
		parts = g.c.patParts(pat, sd)
		for i, part in parts:
			if g.irPatWalks(w, part):
				fAt, fVals = g.irPatField(lw, t, at, vals, i)
				g.irPattern(lw, w, part, g.c.structFieldTypeAt(sd, i), fAt, fVals, false, owner)
		return
	if k == patList:
		g.irListPattern(lw, w, pat, innerOf(tys, t) if sk == tRef else t, at)
		return
	if k == patMap:
		g.irMapPattern(lw, w, pat, t, at, vals)
		return
	if k == patStr and w.fail < 0:
		for cAt in 0..nodes[pat].kids(kidIds).len:
			c = nodes[pat].kids(kidIds)[cAt]
			g.irPatDeclareMade(lw, w, c)
		return
	if k == patStr:
		g.irStrPattern(lw, w, pat, g.irTextAsStr(lw, t, at))
		return
	if w.fail < 0: return   # a literal, a range, none: nothing to bind
	if k == patLit:
		g.irPatternLit(lw, w, pat, t, at, vals)
		return
	if k == patRange:
		g.irPatternRange(lw, w, pat, t, at, vals)
		return
	lw.irFail("a pattern of {typeStr(tys, t)}")

fn irPatternBind(
	mut g Gen,
	mut lw IrLower,
	mut w PatWalk,
	pat NodeId,
	t TypeId,
	sk i64,
	at i64,
	vals i64[],
	top bool,
	owner bool
):
	sub NodeId? = none if nodes[pat].kids(kidIds).isEmpty else nodes[pat].kids(kidIds)[0]
	name = nodes[pat].text.copy()
	wt = t
	wAt = at
	wVals = vals.copy()
	if top and sk == tOption:
		wt = innerOf(tys, t)
		wAt, wVals = g.irPatPresent(lw, w, t, at, vals, true)
		if w.fail < 0 and owner and wVals.isEmpty and g.isOwningType(wt) and
			not g.irByAddress(wt):
			lw.irFail("an owned optional value of {typeStr(tys, wt)}")
			return
	elif top and sk == tResult:
		ok = g.irPatOkSide(t, pat, true)
		wt = g.irSideType(t, ok)
		wAt = g.irPatSide(lw, w, t, at, ok)
		wVals = []
	if w.fail < 0:
		g.irPatDeclare(
			lw,
			w,
			name,
			wt,
			wAt,
			wVals,
			owner and sub == none,
			nodes[pat].hasFlag(flagMut),
			nodes[pat].hasFlag(flagIsTest)
		)
	g.irPattern(lw, w, sub, wt, wAt, wVals, false, false)   # what the name holds stays whole
	return

fn irPatternEnum(
	mut g Gen,
	mut lw IrLower,
	mut w PatWalk,
	pat NodeId,
	t TypeId,
	at i64,
	vals i64[],
	owner bool
):
	ed = declOf(tys, t)
	vi = nodes[ed].kids(kidIds).findIndex(nodes[it].text == nodes[pat].text) ?? -1
	if vi < 0:
		lw.irFail("pattern {nodes[pat].text}")
		return
	plain = g.irIsPlainEnum(t)
	if w.fail >= 0:
		tag = g.irPatLeaves(lw, t, at, vals)[0] if plain else lw.irSpotAt(g.c.enumTag(ed), at)
		lw.irPatBranch(w, tag, lw.irConstOf(irInt, vi), irEq, false)
	if plain: return
	v = nodes[ed].kids(kidIds)[vi]
	offs = g.c.variantFieldOffsets(ed, v)
	parts = g.c.patParts(pat, v)
	for i, part in parts:
		if g.irPatWalks(w, part):
			ft = g.c.resolveType(nodes[nodes[v].kids(kidIds)[i]].types()[0])
			irPattern(
				g,
				lw,
				w,
				part,
				ft,
				lw.irElementAddr(at, -1, 0, offs[i]),
				[],
				false,
				owner
			)
	return

fn irPatternLit(
	mut g Gen,
	mut lw IrLower,
	mut w PatWalk,
	pat NodeId,
	t TypeId,
	at i64,
	vals i64[]
):
	lit = nodes[pat].kids(kidIds)[0]
	if g.irIsStr(t):
		r = g.irCallRt(lw, "strEq", [g.irTextAsStr(lw, t, at), g.irAddressOf(lw, lit)])
		if lw.ok:
			lw.irPatBranch(w, r[0], lw.irConstOf(irInt, 0), irNe, false)
		return
	v = g.irPatLeaves(lw, t, at, vals)
	if lw.ok and v.len == 1:
		lw.irPatBranch(w, v[0], g.irExpr(lw, lit), irEq, false)
	else:
		lw.irFail("a literal's pattern of {typeStr(tys, t)}")
	return

fn irPatternRange(
	mut g Gen,
	mut lw IrLower,
	mut w PatWalk,
	pat NodeId,
	t TypeId,
	at i64,
	vals i64[]
):
	v = g.irPatLeaves(lw, t, at, vals)
	if not lw.ok or v.len != 1:
		lw.irFail("a range's pattern of {typeStr(tys, t)}")
		return
	uns = g.irUnsigned(t)
	lw.irPatBranch(w, v[0], g.irExpr(lw, nodes[pat].kids(kidIds)[0]), irGe, uns)
	if nodes[pat].kids(kidIds).len > 1:
		hi = g.irExpr(lw, nodes[pat].kids(kidIds)[1])
		lw.irPatBranch(w, v[0], hi, irLe if nodes[pat].text2() == "=" else irLt, uns)
	return

# A list's pattern on the list (or window) of type lt at `at`: its length tested (exactly its
# parts, or at least them with a rest), each part at its element (those after the rest counted
# from the end), the rest a window over the elements between.
fn irListPattern(mut g Gen, mut lw IrLower, mut w PatWalk, pat NodeId, lt TypeId, at i64):
	elem = innerOf(tys, lt)
	stride = g.c.elemStride(elem)
	kids = nodes[pat].kids(kidIds).copy()
	r = kids.findIndex(nodes[it].ival == patRest) ?? -1
	n = kids.len - 1 if r >= 0 else kids.len
	length = lw.irHeader(at, 8)
	lw.irPatBranch(w, length, lw.irConstOf(irInt, n), irGe if r >= 0 else irEq, false)
	items = lw.irHeader(at, 0)
	for i in 0..kids.len:
		if i == r and w.fail >= 0 and nodes[kids[i]].text != "":
			to = lw.irPatLess(length, n - r)
			w.made.push(
				PatMade(kids[i], [lw.irPatWindow(items, lw.irConstOf(irInt, r), to, stride)])
			)
		elif i == r:
			g.irPatDeclareMade(lw, w, kids[i])
		elif g.irPatWalks(w, kids[i]):
			ix = i - 1 if r >= 0 and i > r else i
			eAt = lw.irPatElement(items, length, stride, ix, n, r)
			g.irPattern(lw, w, kids[i], elem, eAt, [], false, false)

# the text of type t at `at` (a str, or a window) as a str's address
fn irTextAsStr(mut g Gen, mut lw IrLower, t TypeId, at i64) i64:
	at if tys[t].kind == tStr else lw.irWindowAsStr(at)

# A string's pattern on the str at s: the text before the first capture at its
# start, each capture up to the first place the text after it is found from there, the last one
# up to the text after it at the end; each capture a window over the bytes it took.
fn irStrPattern(mut g Gen, mut lw IrLower, mut w PatWalk, pat NodeId, s i64):
	pieces = nodes[pat].names().copy()
	caps = nodes[pat].kids(kidIds).copy()
	if pieces[0] != "":
		g.irPatStrTest(lw, w, "strStartsWith", s, pieces[0])
	ptr, length = lw.irStrWords(s)
	pos = lw.irConstOf(irInt, pieces[0].len)
	for i in 0..caps.len:
		piece = pieces[i + 1]
		to = length
		if i < caps.len - 1:
			found = g.irCallRt(lw, "findBytes", [s, pos, g.irStrLiteral(lw, piece)])
			if not lw.ok: return
			to = found[0]
			lw.irPatBranch(w, to, lw.irConstOf(irInt, 0), irGe, false)
		elif piece != "":
			g.irPatStrTest(lw, w, "strEndsWith", s, piece)
			to = lw.irPatLess(length, piece.len)
			lw.irPatBranch(w, to, pos, irGe, false)   # not into the text before it
		if nodes[caps[i]].ival == patBind:
			w.made.push((caps[i], [lw.irPatWindow(ptr, pos, to, 1)]))
		if i < caps.len - 1:
			pos = lw.irPatLess(to, -piece.len)

# A map's pattern on the map t (its word where at and vals say): each key looked up (the checker
# made the lookups, which read the map by the name mapPatternName), its value there, tested by
# the pattern after it.
fn irMapPattern(mut g Gen, mut lw IrLower, mut w PatWalk, pat NodeId, t TypeId, at i64, vals i64[]):
	mark = lw.names.len
	if w.fail >= 0:
		lw.irDeclare(mapPatternName, g.irPatLeaves(lw, t, at, vals))
	for i in 0..nodes[pat].kids(kidIds).len / 2:
		lookup = nodes[pat].kids(kidIds)[2 * i]
		found = w.irPatMade(lookup) ?? []
		if w.fail >= 0:
			found = g.irValue(lw, lookup)   # an optional of a reference to the value
			if not lw.ok: return
			w.made.push((lookup, found.copy()))
		ft = g.ty(lookup)
		byAddress = g.irByAddress(ft)
		inAt, inVals = irPatPresent(
			g,
			lw,
			w,
			ft,
			found[0] if byAddress else -1,
			[] if byAddress else found,
			true
		)
		g.irPattern(
			lw,
			w,
			nodes[pat].kids(kidIds)[2 * i + 1],
			innerOf(tys, ft),
			inAt,
			inVals,
			false,
			false
		)
	if w.fail >= 0:
		g.irForgetNames(lw, mark)
