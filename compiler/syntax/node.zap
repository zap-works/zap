# The syntax tree's node: kind, place and flags in narrow fields, the parts most nodes lack apart
# (NodePart), as a large program holds millions of nodes.

# a node's index in the program's nodes (`NodeId?` where there may be none)
pub type NodeId = n32

pub type Node:
	kind u8
	line i32
	col i16   # past 30,000 that column (nodeCol)
	text str   # name, literal text, type name, op name
	kids NodeId[]   # children (expressions, statements, arms, params, fields, methods)
	part NodePart[] = []   # the parts the other nodes lack: none or one
	flags i64   # bit 1 mut, 2 pub, 4 safe access, 8 fn reference, 16 closure call, 32 shared, 64 isEnum
	ival i32   # operators, pattern kinds, resKind, lambda id, param mode
	ty TypeId?   # resolved type id (the checker fills it)

	# module alias, local name, mangle
	pub fn text2() ref str:
		if self.part.isEmpty: return ""
		self.part[0].text2

	# instances of a generic type or impl: the template declaration; the name of a method's
	# runtime function: the method's callee; a name of a known value: that value
	pub fn origin() NodeId?:
		if self.part.isEmpty: return none
		self.part[0].origin

	# secondary children (blocks, map values, enum variants, lambda block)
	pub fn sub() ref NodeId[]:
		if self.part.isEmpty: return noIds
		self.part[0].sub

	# type expression nodes; a bindExterns call: the functions it binds
	pub fn types() ref NodeId[]:
		if self.part.isEmpty: return noIds
		self.part[0].types

	# parameter names, field names, bind names, generics
	pub fn names() ref str[]:
		if self.part.isEmpty: return noTexts
		self.part[0].names

	pub fn file() ref str:
		if self.part.isEmpty: return ""
		self.part[0].file

	# the integer an enum's variant was given (`Add = 1`, kept in text2), none for one without
	pub fn value() i64?:
		if self.text2() == "": return none
		i64.parse(self.text2())

	pub fn mod() ref str:
		if self.part.isEmpty: return ""
		self.part[0].mod

	pub fn bounds() ref str[]:
		if self.part.isEmpty: return noTexts
		self.part[0].bounds

	pub fn names2() ref str[]:
		if self.part.isEmpty: return noTexts
		self.part[0].names2

	pub fn ints() ref TypeId[]:
		if self.part.isEmpty: return noTypes
		self.part[0].ints

	pub mut fn setText2(move t str):
		if t != "" or not self.part.isEmpty: self.nodePart().text2 = t

	pub mut fn setOrigin(o NodeId?):
		if o != none or not self.part.isEmpty: self.nodePart().origin = o

	# the node's NodePart to change, made when it has none
	pub mut fn nodePart() mut ref NodePart:
		if self.part.isEmpty:
			self.part.push(NodePart())
		mut ref self.part[0]

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
