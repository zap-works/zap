# The syntax tree's node: kind, place and flags in narrow fields, its children a span of the
# arena's one list of ids, the parts most nodes lack apart (NodePart), as a large program holds
# millions of nodes.

# a node's index in the program's nodes (`NodeId?` where there may be none)
pub type NodeId = n32

# A node's children are kidsLen ids from kidsAt in the list kept beside its arena (kidIds, one
# for all its nodes), read by kids(kidIds). A span is never written once made: a change of the
# children writes them anew at the list's end (a push only appends when the span ends there), so
# a node copied shares its children with the original safely and the list only grows.
pub type Node:
	kind u8
	col i16   # past 30,000 that column (nodeCol)
	line i32
	text str   # name, literal text, type name, op name
	part Box<NodePart>? = none   # the parts the other nodes lack
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
	pub mut fn takeName(i i64) str:
		if self.part is mut p: return move p.names[i]
		""

	# children (expressions, statements, arms, params, fields, methods)
	pub fn kids(kidIds NodeId[]) ref NodeId[]:
		kidIds[self.kidsAt..self.kidsAt + self.kidsLen]

	# the children from the i-th on
	pub fn kidsFrom(kidIds NodeId[], i i64) ref NodeId[]:
		kidIds[self.kidsAt + i..self.kidsAt + self.kidsLen]

	pub mut fn setKids(mut kidIds NodeId[], ks NodeId[]):
		kidsAt = i32(kidIds.len)
		kidsLen = i32(ks.len)
		kidIds.extend(ks)

	pub mut fn setKid(mut kidIds NodeId[], i i64, k NodeId):
		if self.kids(kidIds)[i] == k: return
		ks = self.kids(kidIds).copy()
		ks[i] = k
		self.setKids(kidIds, ks)

	pub mut fn pushKid(mut kidIds NodeId[], k NodeId):
		if self.kidsLen == 0:
			kidsAt = i32(kidIds.len)
		elif self.kidsAt + self.kidsLen != kidIds.len:
			self.setKids(kidIds, self.kids(kidIds).copy())
		kidIds.push(k)
		kidsLen += 1

	pub mut fn extendKids(mut kidIds NodeId[], ks NodeId[]):
		for k in ks:
			self.pushKid(kidIds, k)

	pub mut fn insertKid(mut kidIds NodeId[], i i64, k NodeId):
		ks = self.kids(kidIds).copy()
		ks.insert(i, k)
		self.setKids(kidIds, ks)

	pub mut fn removeKid(mut kidIds NodeId[], i i64):
		ks = self.kids(kidIds).copy()
		ks.remove(i)
		self.setKids(kidIds, ks)

	pub mut fn dropLastKid():
		if self.kidsLen == 0: exit(1, "zap: a node's last child taken from none")
		kidsLen -= 1

	# module alias, local name, mangle
	pub fn text2() ref str:
		if self.part is p: return p.text2
		""

	# instances of a generic type or impl: the template declaration; the name of a method's
	# runtime function: the method's callee; a name of a known value: that value
	pub fn origin() NodeId?:
		if self.part is p: return p.origin
		none

	# secondary children (blocks, map values, enum variants, lambda block)
	pub fn sub() ref NodeId[]:
		if self.part is p: return p.sub
		noIds

	# type expression nodes; a bindExterns call: the functions it binds
	pub fn types() ref NodeId[]:
		if self.part is p: return p.types
		noIds

	# parameter names, field names, bind names, generics
	pub fn names() ref str[]:
		if self.part is p: return p.names
		noTexts

	pub fn file() ref str:
		if self.part is p: return p.file
		""

	# the integer an enum's variant was given (`Add = 1`, kept in text2), none for one without
	pub fn value() i64?:
		if self.text2() == "": return none
		i64.parse(self.text2())

	pub fn mod() ref str:
		if self.part is p: return p.mod
		""

	pub fn bounds() ref str[]:
		if self.part is p: return p.bounds
		noTexts

	pub fn names2() ref str[]:
		if self.part is p: return p.names2
		noTexts

	# the symbol an extern is found by: the one written after its library, else its own name
	pub fn externSymbol() str:
		named = self.names2()
		named[1].copy() if named.len > 1 else self.text2().copy()

	pub fn ints() ref TypeId[]:
		if self.part is p: return p.ints
		noTypes

	pub mut fn setText2(move t str):
		if t != "" or self.part != none: self.nodePart().text2 = t

	pub mut fn setOrigin(o NodeId?):
		if o != none or self.part != none: self.nodePart().origin = o

	# the node's NodePart to change, made when it has none
	pub mut fn nodePart() mut ref NodePart:
		if self.part is mut p: return mut ref p
		self.part = Box(NodePart())
		self.nodePart()

# What some nodes hold that most do not, kept apart from the node (Node.part) so a node is
# smaller by these texts and lists: read by the functions of their names (`nodes[d].mod()`),
# changed through nodePart (`nodes[d].nodePart().mod = m`).
pub type NodePart:
	text2 str = ""
	origin NodeId? = none
	sub NodeId[] = []
	types NodeId[] = []
	names str[] = []
	file str = ""   # a declaration's source file
	mod str = ""   # a declaration's module id ("" = main module)
	bounds str[] = []   # generic declarations: each type parameter's bounds ("Ord+Hash", "" = none);
	# a lambda: the captured variables its body changes
	names2 str[] = []   # captures, impl substitution names, import names
	ints TypeId[] = []   # capture types, impl substitution types, instance arguments

noIds NodeId[] = []
noTexts str[] = []
noTypes TypeId[] = []
