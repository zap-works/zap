# A switch on texts: a match whose arms are string literals, and `x in [...]` of them, jump once
# on the text's length and once on its bytes instead of comparing it with each literal in turn.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds

# The texts of the arms of match e on a text of type t when a switch can take them: a string
# literal each, no condition, and only the last arm `_`; none for any other match, or one of
# fewer arms than irSwitchLeast.
fn irSwitchTexts(g Gen, e NodeId, t TypeId) str[]?:
	if not g.irIsStr(t): return none
	arms = nodes[e].kids(kidIds).len - 1
	texts = []
	for i in 0..arms:
		pat = nodes[nodes[e].kids(kidIds)[i + 1]].kids(kidIds)[0]
		k = nodes[pat].ival
		if not nodes[pat].sub().isEmpty: return none
		if i == arms - 1 and k == patWildcard: break
		if k != patLit or nodes[nodes[pat].kids(kidIds)[0]].kind != nStr: return none
		texts.push(nodes[nodes[pat].kids(kidIds)[0]].text.copy())
	none if texts.len < irSwitchLeast else texts

# The values of `x in [...]` (the chain of x == v or-ed that the checker made of it, e) when a
# switch can take them: string literals, or integer ones, at least irSwitchLeast; none otherwise.
fn irMembershipValues(g Gen, e NodeId) NodeId[]?:
	if not nodes[e].hasFlag(flagInternal): return none
	values = []
	at = e
	while nodes[at].kind == nBinary and nodes[at].ival == binOr:
		values.push(nodes[at].kids(kidIds)[1])
		at = nodes[at].kids(kidIds)[0]
	values.push(at)
	values.reverse()
	if values.len < irSwitchLeast: return none
	for v in values:
		if nodes[v].kind != nBinary or nodes[v].ival != binEq: return none
	kind = nodes[nodes[values[0]].kids(kidIds)[1]].kind
	if kind != nStr and kind != nInt: return none
	x = nodes[values[0]].kids(kidIds)[0]
	for v in values:
		if nodes[nodes[v].kids(kidIds)[1]].kind != kind: return none
		if not g.irSameName(nodes[v].kids(kidIds)[0], x): return none
	values

# whether a and b name the same thing: one name, or the same fields of it
fn irSameName(g Gen, a NodeId, b NodeId) bool:
	k = nodes[a].kind
	if k != nodes[b].kind or nodes[a].text != nodes[b].text: return false
	if k == nIdent: return true
	k == nField and nodes[a].kids(kidIds).len == 1 and nodes[b].kids(kidIds).len == 1 and
		g.irSameName(nodes[a].kids(kidIds)[0], nodes[b].kids(kidIds)[0])

# `x in [...]` of literals: one switch to yes for each literal, else to no; false when e is none
fn irCondInMembership(mut g Gen, mut lw IrLower, e NodeId, yes i64, no i64):
	eqs = g.irMembershipValues(e) ?? return false
	x = nodes[eqs[0]].kids(kidIds)[0]
	literals = eqs.map(nodes[it].kids(kidIds)[1])
	if nodes[literals[0]].kind == nStr:
		s = g.irStrAddr(lw, x)
		if not lw.ok: return true
		g.irStrSwitch(lw, s, literals.map(nodes[it].text.copy()), literals.map(l: yes), no)
		return true
	v = g.irExpr(lw, x)
	if not lw.ok: return true
	lw.irIntSwitch(g, v, g.ty(x), literals.map(g.intLitValue(it)), literals.map(l: yes), no)
	true

# A jump to blocks[i] when the text at s is texts[i] (the first of equal texts taking it), else
# to other: a switch on its length, then, for each length, one on its bytes read as a
# little-endian integer, or for texts past eight bytes a comparison with each.
fn irStrSwitch(mut g Gen, mut lw IrLower, s i64, texts str[], blocks i64[], other i64):
	ptr, n = lw.irStrWords(s)
	lengths = IrSwitch(values = [], targets = [])
	cases = []   # the texts of each length, by their index
	seen {str: bool} = {}
	for i, text in texts:
		if text in seen: continue
		seen[text.copy()] = true
		j = lengths.values.indexOf(text.len) ?? -1
		if j < 0:
			lengths.values.push(text.len)
			lengths.targets.push(lw.f.irBlock())
			cases.push([i])
		else:
			cases[j].push(i)
	lw.irPut(IrInst(op = irSwitch, a = n, imm = lw.f.switches.len, other))
	lw.f.switches.push(lengths.copy())
	for j, length in lengths.values:
		lw.f.irEnter(lengths.targets[j])
		if length > 8:
			g.irStrCompares(lw, s, texts, blocks, cases[j], other)
			continue
		key = lw.irBytesKey(ptr, length)
		lw.irPut(IrInst(op = irSwitch, a = key, imm = lw.f.switches.len, other, uns = true))
		lw.f.switches.push(
			IrSwitch(
				values = cases[j].map(irTextKey(texts[it])),
				targets = cases[j].map(blocks[it])
			)
		)

# the length bytes at ptr (eight at most) as a little-endian integer, read eight, four, two and
# one at a time
fn irBytesKey(mut lw IrLower, ptr i64, length i64):
	key = lw.irConstOf(irInt, 0)
	off = 0
	for size in [8, 4, 2, 1]:
		if length - off < size: continue
		part = lw.irDef(
			irInt,
			IrInst(op = irLoad, a = ptr, imm = off, size = i32(size), uns = true)
		)
		if off == 0:
			key = part
		else:
			high = lw.irDef(irInt, IrInst(op = irShl, a = part, b = lw.irConstOf(irInt, 8 * off)))
			key = lw.irDef(irInt, IrInst(op = irOr, a = key, b = high))
		off += size
	key

# a text's bytes (eight at most) as a little-endian integer, as irBytesKey reads them
fn irTextKey(text str) i64:
	key u64 = 0
	for i, b in text.bytes():
		key |= u64(b) << u64(8 * i)
	i64.wrap(key)

# the text at s compared with each of the cases' texts (one length, past eight bytes)
fn irStrCompares(
	mut g Gen,
	mut lw IrLower,
	s i64,
	texts str[],
	blocks i64[],
	cases i64[],
	other i64
):
	for i in cases:
		r = g.irCallRt(lw, "strEq", [s, g.irStrLiteral(lw, texts[i])])
		if not lw.ok: return
		next = lw.f.irBlock()
		lw.irBranchIf(r[0], irNe, lw.irConstOf(irInt, 0), blocks[i], next)
		lw.f.irEnter(next)
	lw.f.irJumpTo(other)
