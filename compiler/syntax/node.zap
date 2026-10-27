# The syntax tree's node: kind, place and flags in narrow fields, its children a span of the
# arena's one list of ids and the parts most nodes lack an entry of its list of parts (NodeLists),
# as a large program holds millions of nodes.

# a node's index in the program's nodes (`NodeId?` where there may be none)
pub type NodeId = n32

# The lists kept beside an arena of nodes (kidIds, one for all its nodes): each node's children
# a span of ids, the parts some nodes hold an entry of parts, past the first, the empty part of
# every other node (so a node of zero bytes has none, and reading one never tests for it).
pub type NodeLists:
	ids NodeId[] = []
	parts NodePart[] = [NodePart()]

	# the part put at the end of parts, its number
	pub mut fn pushPart(move made NodePart) n32:
		parts.push(made)
		n32(self.parts.len - 1)

# A node's children are kidsLen ids from kidsAt in its arena's ids, read by kids(kidIds). A span
# is never written once made: a change of the children writes them anew at the list's end (a push
# only appends when the span ends there), so a node copied shares its children with the original
# safely and the list only grows. Its part (NodePart) is its own: a copy is given one of its own
# (copied).
pub type Node:
	kind u8
	col i16   # past 30,000 that column (nodeCol)
	line i32
	text str   # name, literal text, type name, op name
	part n32 = 0   # its entry of the arena's parts, 0 (the empty one) for a node without one
	flags i64   # bit 1 mut, 2 pub, 4 safe access, 8 fn reference, 16 closure call, 32 shared, 64 isEnum
	ival i32   # operators, pattern kinds, resKind, lambda id, param mode
	kidsAt i32 = 0
	kidsLen i32 = 0
	ty TypeId?   # resolved type id (the checker fills it)
	name i32 = -1   # the number of the name text holds (interned), -1 when not numbered: nameOf

	# the text t, of number n when known (another node's name, copied with its text)
	pub mut fn setText(move t str, n i32 = -1):
		text = t
		name = n

	# the text, moved out (an empty one left, numbered as none)
	pub mut fn takeText() str:
		name = -1
		move text

	# the i-th of names(), moved out (an empty one left)
	pub mut fn takeName(mut kidIds NodeLists, i i64) str:
		kidIds.parts[self.part].takeName(i)

	# a copy of the node with a part of its own, so a change of the copy's leaves the original's
	pub fn copied(mut kidIds NodeLists) Node:
		n = self.copy()
		if self.part != 0: n.part = kidIds.pushPart(kidIds.parts[self.part].copy())
		n

	# a copy of the node for another arena, its part copied from this one's lists into that one's
	pub fn copiedTo(from NodeLists, mut to NodeLists) Node:
		n = self.copy()
		if self.part != 0: n.part = to.pushPart(from.parts[self.part].copy())
		n

	# the node's part moved from the lists of the arena it leaves to those of the one it joins
	pub mut fn movePart(mut from NodeLists, mut to NodeLists):
		if self.part != 0: part = to.pushPart(move from.parts[self.part])

	# children (expressions, statements, arms, params, fields, methods)
	pub fn kids(kidIds NodeLists) ref NodeId[]:
		kidIds.ids[self.kidsAt..self.kidsAt + self.kidsLen]

	# the children from the i-th on
	pub fn kidsFrom(kidIds NodeLists, i i64) ref NodeId[]:
		kidIds.ids[self.kidsAt + i..self.kidsAt + self.kidsLen]

	pub mut fn setKids(mut kidIds NodeLists, ks NodeId[]):
		kidsAt = i32(kidIds.ids.len)
		kidsLen = i32(ks.len)
		kidIds.ids.extend(ks)

	pub mut fn setKid(mut kidIds NodeLists, i i64, k NodeId):
		if self.kids(kidIds)[i] == k: return
		ks = self.kids(kidIds).copy()
		ks[i] = k
		self.setKids(kidIds, ks)

	pub mut fn pushKid(mut kidIds NodeLists, k NodeId):
		if self.kidsLen == 0:
			kidsAt = i32(kidIds.ids.len)
		elif self.kidsAt + self.kidsLen != kidIds.ids.len:
			self.setKids(kidIds, self.kids(kidIds).copy())
		kidIds.ids.push(k)
		kidsLen += 1

	pub mut fn extendKids(mut kidIds NodeLists, ks NodeId[]):
		for k in ks:
			self.pushKid(kidIds, k)

	pub mut fn insertKid(mut kidIds NodeLists, i i64, k NodeId):
		ks = self.kids(kidIds).copy()
		ks.insert(i, k)
		self.setKids(kidIds, ks)

	pub mut fn removeKid(mut kidIds NodeLists, i i64):
		ks = self.kids(kidIds).copy()
		ks.remove(i)
		self.setKids(kidIds, ks)

	pub mut fn dropLastKid():
		if self.kidsLen == 0: exit(1, "zap: a node's last child taken from none")
		kidsLen -= 1

	# module alias, local name, mangle
	pub fn text2(kidIds NodeLists) ref str:
		if kidIds.parts[self.part].more is m: return m.text2
		""

	# instances of a generic type or impl: the template declaration; the name of a method's
	# runtime function: the method's callee; a name of a known value: that value
	pub fn origin(kidIds NodeLists) NodeId?:
		if kidIds.parts[self.part].more is m: return m.origin
		none

	# secondary children (blocks, map values, enum variants, lambda block)
	pub fn sub(kidIds NodeLists) ref NodeId[]:
		kidIds.parts[self.part].sub

	# type expression nodes; a bindExterns call: the functions it binds
	pub fn types(kidIds NodeLists) ref NodeId[]:
		kidIds.parts[self.part].types

	# parameter names, field names, bind names, generics
	pub fn names(kidIds NodeLists) ref str[]:
		if kidIds.parts[self.part].more is m: return m.names
		noTexts

	pub fn file(kidIds NodeLists) ref str:
		if kidIds.parts[self.part].more is m: return m.file
		""

	# the integer an enum's variant was given (`Add = 1`, kept in text2), none for one without
	pub fn value(kidIds NodeLists) i64?:
		if self.text2(kidIds) == "": return none
		i64.parse(self.text2(kidIds))

	pub fn mod(kidIds NodeLists) ref str:
		if kidIds.parts[self.part].more is m: return m.mod
		""

	pub fn bounds(kidIds NodeLists) ref str[]:
		if kidIds.parts[self.part].more is m: return m.bounds
		noTexts

	pub fn names2(kidIds NodeLists) ref str[]:
		if kidIds.parts[self.part].more is m: return m.names2
		noTexts

	# the symbol an extern is found by: the one written after its library, else its own name
	pub fn externSymbol(kidIds NodeLists) str:
		named = self.names2(kidIds)
		named[1].copy() if named.len > 1 else self.text2(kidIds).copy()

	pub fn ints(kidIds NodeLists) ref TypeId[]:
		if kidIds.parts[self.part].more is m: return m.ints
		noTypes

	pub mut fn setText2(mut kidIds NodeLists, move t str):
		if t != "" or self.text2(kidIds) != "": self.nodeMore(kidIds).text2 = t

	pub mut fn setOrigin(mut kidIds NodeLists, o NodeId?):
		if o != none or self.origin(kidIds) != none: self.nodeMore(kidIds).origin = o

	# the node's NodePart to change, made when it has none
	pub mut fn nodePart(mut kidIds NodeLists) mut ref NodePart:
		if self.part == 0: part = kidIds.pushPart(NodePart())
		mut ref kidIds.parts[self.part]

	# the node's NodeMore to change, made when it has none
	pub mut fn nodeMore(mut kidIds NodeLists) mut ref NodeMore:
		self.nodePart(kidIds).rarer()

# What some nodes hold that most do not, kept apart from the node (Node.part) so a node is
# smaller by these lists: read by the functions of their names (`nodes[d].sub(kidIds)`), changed
# through nodePart (`nodes[d].nodePart(kidIds).sub = ks`). Most parts hold one list (a block's
# statements, a declaration's types), so the rarer parts are apart again (NodeMore).
pub type NodePart:
	sub NodeId[] = []
	types NodeId[] = []
	more Box<NodeMore>? = none

	# the NodeMore to change, made when it has none
	pub mut fn rarer() mut ref NodeMore:
		if self.more is mut m: return mut ref m
		self.more = Box(NodeMore())
		self.rarer()

	pub mut fn takeName(i i64) str:
		if self.more is mut m: return move m.names[i]
		""

# What fewer nodes still hold (declarations, names, captures): read as NodePart's are, changed
# through nodeMore (`nodes[d].nodeMore(kidIds).mod = m`).
pub type NodeMore:
	text2 str = ""
	origin NodeId? = none
	names str[] = []
	file str = ""   # a declaration's source file
	mod str = ""   # a declaration's module id ("" = main module)
	bounds str[] = []   # generic declarations: each type parameter's bounds ("Ord+Hash", "" = none);
	# a lambda: the captured variables its body changes
	names2 str[] = []   # captures, impl substitution names, import names
	ints TypeId[] = []   # capture types, impl substitution types, instance arguments

noTexts str[] = []
noTypes TypeId[] = []
