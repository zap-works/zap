# The changes of a binding the text alone tells (spec 2.4): a node that assigns the name or a part
# of it, lends it `mut ref` or `out`, moves a part out of it, or binds a loop's or a match's `mut`
# name to a part of it. The checker adds the calls that change it, knowing the types
# (check/mutability.zap); the register arrays' pass, which runs before them, takes any call made
# on it or handed it as one (markMayChange).

# the node at the root of the place e: through its fields, elements and dereferences
pub fn placeRootOf(nodes Node[], e NodeId) NodeId:
	p = e
	while nodes[p].kind in [nField, nIndex, nDeref]:
		p = nodes[p].kids[0]
	p

# the variable's name at the root of the place e, "" when it is none's
pub fn rootNameOf(nodes Node[], e NodeId) ref str:
	x = placeRootOf(nodes, e)
	nodes[x].text if nodes[x].kind == nIdent else ""

# the place a match's names point into: the matched value, or the receiver of the method call
# that gives it (`m.get(k) is mut v`)
pub fn matchedPlaceOf(nodes Node[], e0 NodeId) NodeId:
	e = e0
	loop:
		k = nodes[e].kind
		if k == nField or k == nIndex:
			e = nodes[e].kids[0]
		elif k == nCall and nodes[nodes[e].kids[0]].kind == nField:
			e = nodes[nodes[e].kids[0]].kids[0]
		else:
			return e

# whether a pattern binds a `mut` name, its parts' included
pub fn bindsMutName(nodes Node[], pat NodeId) bool:
	nodes[pat].kind == nPattern and
		(nodes[pat].hasFlag(flagMut) or nodes[pat].kids.any(bindsMutName(nodes, it)))

# whether the node e itself (not its parts) changes name as the text tells
pub fn textChanges(nodes Node[], e NodeId, name str) bool:
	k = nodes[e].kind
	if k == nAssign: return rootNameOf(nodes, nodes[e].kids[0]) == name
	if k == nLet: return nodes[e].text == name and nodes[e].canAssign() and nodes[e].types().isEmpty
	if k == nUnary:
		op = nodes[e].ival
		inner = nodes[e].kids[0]
		return rootNameOf(nodes, inner) == name and
			(op == unMutRef or op == unOut or op == unMove and nodes[inner].kind != nIdent)
	if k == nFor: return nodes[e].hasFlag(flagMut) and rootNameOf(nodes, nodes[e].kids[0]) == name
	if k == nMatch:
		return rootNameOf(nodes, matchedPlaceOf(nodes, nodes[e].kids[0])) == name and
			nodes[e].kids[1..].any(bindsMutName(nodes, nodes[it].kids[0]))
	false

# Before the register arrays' pass (which reads an immutable let's value where it is used): each
# let of body without `mut` that what follows in its block may change is marked flagMayChange (an
# array declared without values is not: its elements are bound by assignment, and `mut` on it
# says they start from zeros). A call made on it or a part of it, or handed it, may change it (a
# `mut` parameter): the types that would tell are not known yet, and the mark only keeps the pass
# from reading a value.
pub fn markMayChange(mut nodes Node[], body NodeId):
	kids = nodes[body].kids.copy()
	for i in 0..kids.len:
		st = kids[i]
		if nodes[st].kind == nLet and not nodes[st].hasFlag(flagMut) and
			not nodes[st].kids.isEmpty and
			kids[i + 1..].any(mayChangeIn(nodes, it, nodes[st].text)):
			nodes[st].flags |= flagMayChange
	for st in kids:
		markMayChangeUnder(nodes, st)

fn markMayChangeUnder(mut nodes Node[], e NodeId):
	if nodes[e].kind == nBlock:
		markMayChange(nodes, e)
		return
	for k in nodes[e].kids.copy():
		markMayChangeUnder(nodes, k)
	for k in nodes[e].sub().copy():
		markMayChangeUnder(nodes, k)

fn mayChangeIn(nodes Node[], e NodeId, name str) bool:
	if textChanges(nodes, e, name): return true
	if nodes[e].kind == nCall:
		callee = nodes[e].kids[0]
		if nodes[callee].kind == nField and rootNameOf(nodes, nodes[callee].kids[0]) == name:
			return true
		for a in nodes[e].kids[1..]:
			if nodes[a].kind in [nIdent, nField, nIndex] and rootNameOf(nodes, a) == name:
				return true
	nodes[e].kids.any(mayChangeIn(nodes, it, name)) or
		nodes[e].sub().any(mayChangeIn(nodes, it, name))

# An array declared without values (spec 3.5) starts from zeros unless the first statement after
# it in its block that names it only binds its elements (`a[i] = v`): each is then bound once.
# Zeros mark it mutable (flagMut).
pub fn markZeroedArrays(mut nodes Node[], body NodeId):
	kids = nodes[body].kids.copy()
	for i, st in kids:
		if not isBareArray(nodes, st): continue
		name = nodes[st].text.copy()
		bound = match kids[i + 1..].find(namesIn(nodes, it, name)):
			first: bindsOnly(nodes, first, name)
			none: false
		if bound: continue
		nodes[st].flags |= flagMut
	for st in kids:
		markZeroedUnder(nodes, st)

fn markZeroedUnder(mut nodes Node[], e NodeId):
	if nodes[e].kind == nBlock:
		markZeroedArrays(nodes, e)
		return
	for k in nodes[e].kids.copy():
		markZeroedUnder(nodes, k)
	for k in nodes[e].sub().copy():
		markZeroedUnder(nodes, k)

# whether e is a let of an array declared without values
fn isBareArray(nodes Node[], e NodeId):
	nodes[e].kind == nLet and nodes[e].kids.isEmpty and not nodes[e].types().isEmpty and
		nodes[nodes[e].types()[0]].kind == nTyArray

# whether e or a part of it names name
fn namesIn(nodes Node[], e NodeId, name str) bool:
	nodes[e].kind == nIdent and nodes[e].text == name or
		nodes[e].kids.any(namesIn(nodes, it, name)) or nodes[e].sub().any(namesIn(nodes, it, name))

# whether every place e names name is the target of a plain assignment of a whole element of it
# (`a[i] = v`, no part of one), its index and the value naming it not
fn bindsOnly(nodes Node[], e NodeId, name str) bool:
	if nodes[e].kind == nAssign and nodes[nodes[e].kids[0]].kind == nIndex and
		rootNameOf(nodes, nodes[e].kids[0]) == name:
		target = nodes[e].kids[0]
		return nodes[nodes[target].kids[0]].kind == nIdent and
			not namesIn(nodes, nodes[target].kids[1], name) and
			not namesIn(nodes, nodes[e].kids[1], name)
	if nodes[e].kind == nIdent and nodes[e].text == name: return false
	nodes[e].kids.all(bindsOnly(nodes, it, name)) and nodes[e].sub().all(bindsOnly(nodes, it, name))
