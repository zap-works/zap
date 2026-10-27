# The changes of a binding the text alone tells (spec 2.4): a node that assigns the name or a part
# of it, lends it `mut ref` or `out`, moves a part out of it, or binds a loop's or a match's `mut`
# name to a part of it. The checker adds the calls that change it, knowing the types
# (check/mutability.zap); the register arrays' pass, which runs before them, takes any call made
# on it or handed it as one (markMayChange).

# the node at the root of the place e: through its fields, elements and dereferences
pub fn placeRootOf(nodes Node[], kidIds NodeLists, e NodeId) NodeId:
	p = e
	while nodes[p].kind in [nField, nIndex, nDeref]:
		p = nodes[p].kids(kidIds)[0]
	p

# the variable's name at the root of the place e, "" when it is none's
pub fn rootNameOf(nodes Node[], kidIds NodeLists, e NodeId) ref str:
	x = placeRootOf(nodes, kidIds, e)
	nodes[x].text if nodes[x].kind == nIdent else ""

# the place a match's names point into: the matched value, or the receiver of the method call
# that gives it (`m.get(k) is mut v`)
pub fn matchedPlaceOf(nodes Node[], kidIds NodeLists, e0 NodeId) NodeId:
	e = e0
	loop:
		k = nodes[e].kind
		if k == nField or k == nIndex:
			e = nodes[e].kids(kidIds)[0]
		elif k == nCall and nodes[nodes[e].kids(kidIds)[0]].kind == nField:
			e = nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0]
		else:
			return e

# whether a pattern binds a `mut` name, its parts' included
pub fn bindsMutName(nodes Node[], kidIds NodeLists, pat NodeId) bool:
	nodes[pat].kind == nPattern and
		(
			nodes[pat].hasFlag(flagMut) or
				nodes[pat].kids(kidIds).any(bindsMutName(nodes, kidIds, it))
		)

# whether the node e itself (not its parts) changes name as the text tells
pub fn textChanges(nodes Node[], kidIds NodeLists, e NodeId, name str) bool:
	k = nodes[e].kind
	if k == nAssign: return rootNameOf(nodes, kidIds, nodes[e].kids(kidIds)[0]) == name
	if k == nLet:
		return nodes[e].text == name and nodes[e].canAssign(kidIds) and
			nodes[e].types(kidIds).isEmpty
	if k == nUnary:
		op = nodes[e].ival
		inner = nodes[e].kids(kidIds)[0]
		return rootNameOf(nodes, kidIds, inner) == name and
			(op == unMutRef or op == unOut or op == unMove and nodes[inner].kind != nIdent)
	if k == nFor:
		return nodes[e].hasFlag(flagMut) and
			rootNameOf(nodes, kidIds, nodes[e].kids(kidIds)[0]) == name
	if k == nMatch:
		return rootNameOf(nodes, kidIds, matchedPlaceOf(nodes, kidIds, nodes[e].kids(kidIds)[0])) ==
			name and
			nodes[e].kidsFrom(kidIds, 1).any(bindsMutName(nodes, kidIds, nodes[it].kids(kidIds)[0]))
	false

# Before the register arrays' pass (which reads an immutable let's value where it is used): each
# let of body without `mut` that what follows in its block may change is marked flagMayChange (an
# array declared without values is not: its elements are bound by assignment, and `mut` on it
# says they start from zeros). A call made on it or a part of it, or handed it, may change it (a
# `mut` parameter): the types that would tell are not known yet, and the mark only keeps the pass
# from reading a value.
pub fn markMayChange(mut nodes Node[], mut kidIds NodeLists, body NodeId):
	kids = nodes[body].kids(kidIds).copy()
	for i in 0..kids.len:
		st = kids[i]
		if nodes[st].kind == nLet and not nodes[st].hasFlag(flagMut) and
			not nodes[st].kids(kidIds).isEmpty and
			kids[i + 1..].any(mayChangeIn(nodes, kidIds, it, nodes[st].text)):
			nodes[st].flags |= flagMayChange
	for st in kids:
		markMayChangeUnder(nodes, kidIds, st)

fn markMayChangeUnder(mut nodes Node[], mut kidIds NodeLists, e NodeId):
	if nodes[e].kind == nBlock:
		markMayChange(nodes, kidIds, e)
		return
	for k in nodes[e].kids(kidIds).copy():
		markMayChangeUnder(nodes, kidIds, k)
	for k in nodes[e].sub(kidIds).copy():
		markMayChangeUnder(nodes, kidIds, k)

fn mayChangeIn(nodes Node[], kidIds NodeLists, e NodeId, name str) bool:
	if textChanges(nodes, kidIds, e, name): return true
	if nodes[e].kind == nCall:
		callee = nodes[e].kids(kidIds)[0]
		if nodes[callee].kind == nField and
			rootNameOf(nodes, kidIds, nodes[callee].kids(kidIds)[0]) == name:
			return true
		for a in nodes[e].kidsFrom(kidIds, 1):
			if nodes[a].kind in [nIdent, nField, nIndex] and rootNameOf(nodes, kidIds, a) == name:
				return true
	nodes[e].kids(kidIds).any(mayChangeIn(nodes, kidIds, it, name)) or
		nodes[e].sub(kidIds).any(mayChangeIn(nodes, kidIds, it, name))

# An array declared without values (spec 3.5) starts from zeros unless the first statement after
# it in its block that names it only binds its elements (`a[i] = v`): each is then bound once.
# Zeros mark it mutable (flagMut).
pub fn markZeroedArrays(mut nodes Node[], mut kidIds NodeLists, body NodeId):
	kids = nodes[body].kids(kidIds).copy()
	for i, st in kids:
		if not isBareArray(nodes, kidIds, st): continue
		name = nodes[st].text.copy()
		bound = match kids[i + 1..].find(namesIn(nodes, kidIds, it, name)):
			first: bindsOnly(nodes, kidIds, first, name)
			none: false
		if bound: continue
		nodes[st].flags |= flagMut
	for st in kids:
		markZeroedUnder(nodes, kidIds, st)

fn markZeroedUnder(mut nodes Node[], mut kidIds NodeLists, e NodeId):
	if nodes[e].kind == nBlock:
		markZeroedArrays(nodes, kidIds, e)
		return
	for k in nodes[e].kids(kidIds).copy():
		markZeroedUnder(nodes, kidIds, k)
	for k in nodes[e].sub(kidIds).copy():
		markZeroedUnder(nodes, kidIds, k)

# whether e is a let of an array declared without values
fn isBareArray(nodes Node[], kidIds NodeLists, e NodeId):
	nodes[e].kind == nLet and nodes[e].kids(kidIds).isEmpty and
		not nodes[e].types(kidIds).isEmpty and
		nodes[nodes[e].types(kidIds)[0]].kind == nTyArray

# whether e or a part of it names name
fn namesIn(nodes Node[], kidIds NodeLists, e NodeId, name str) bool:
	nodes[e].kind == nIdent and nodes[e].text == name or
		nodes[e].kids(kidIds).any(namesIn(nodes, kidIds, it, name)) or
		nodes[e].sub(kidIds).any(namesIn(nodes, kidIds, it, name))

# whether every place e names name is the target of a plain assignment of a whole element of it
# (`a[i] = v`, no part of one), its index and the value naming it not
fn bindsOnly(nodes Node[], kidIds NodeLists, e NodeId, name str) bool:
	if nodes[e].kind == nAssign and nodes[nodes[e].kids(kidIds)[0]].kind == nIndex and
		rootNameOf(nodes, kidIds, nodes[e].kids(kidIds)[0]) == name:
		target = nodes[e].kids(kidIds)[0]
		return nodes[nodes[target].kids(kidIds)[0]].kind == nIdent and
			not namesIn(nodes, kidIds, nodes[target].kids(kidIds)[1], name) and
			not namesIn(nodes, kidIds, nodes[e].kids(kidIds)[1], name)
	if nodes[e].kind == nIdent and nodes[e].text == name: return false
	nodes[e].kids(kidIds).all(bindsOnly(nodes, kidIds, it, name)) and
		nodes[e].sub(kidIds).all(bindsOnly(nodes, kidIds, it, name))
