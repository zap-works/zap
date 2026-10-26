# Names numbered once (Zig's InternPool, Go's symbols): a name's number is its index in texts, so
# an index of declarations or scopes by name is a list by number. A file's names are numbered
# where it is parsed, apart (numberNames), then by the program's table as it is appended to the
# program (appendParsed); a node made or renamed later has none (Node.setText) and nameOf finds
# its text's.
pub type Interned:
	numbers {str: i64} = {}
	texts str[] = []

	# the number of name, given it now when it has none
	pub mut fn numbered(name str) i64:
		if numbers.get(name) is n: return n
		n = texts.len
		numbers[name.copy()] = n
		texts.push(name.copy())
		n

	# the number of name, -1 when it has none (nothing was ever numbered under it)
	pub fn numberOf(name str) i64:
		numbers.get(name) ?? -1

# the program's names (the main thread's: a job numbers a file's in a table of its own)
pub mut interned = Interned()

# a name's number not looked up yet (a lookup given it finds it; -1 is a name with none)
pub unnumbered = -2

# n, or when it is unnumbered the number of name
pub fn numberOr(n i64, name str) i64:
	n if n != unnumbered else interned.numberOf(name)

# the number of node e's text, -1 when no name was numbered so
pub fn nameOf(nodes Node[], e NodeId) i64:
	n = nodes[e].name
	if n >= 0: return n
	interned.numberOf(nodes[e].text)

# the number of node e's text, given it now when it has none
pub fn numberedName(nodes Node[], e NodeId) i64:
	n = nodes[e].name
	if n >= 0: return n
	interned.numbered(nodes[e].text)

# whether a node of kind k holds a name in its text (not a literal's or an operator's)
fn holdsName(k i64):
	k in [nIdent, nField, nCall, nStructLit, nLet, nPattern] or
		k == nTyName or k >= nParam and k <= nBoundDecl and k != nImportDecl and k != nTestDecl

# node n numbered by the program's table when it holds a name: a kept stage's node as it is read
# (the main thread's)
pub fn numberRead(mut n Node):
	if n.text != "" and holdsName(n.kind): n.name = i32(interned.numbered(n.text))

# the names of a file's nodes numbered in a table of its own, which appendParsed renumbers by the
# program's
pub fn numberNames(mut nodes Node[]) Interned:
	names = Interned()
	for mut node in nodes:
		if holdsName(node.kind): node.name = i32(names.numbered(node.text))
	names

# v pushed onto the list of number n, the lists grown to reach it
pub fn addAtNumber(mut index i64[,], n i64, v i64):
	while index.len <= n:
		index.push([])
	index[n].push(v)

# the list of number n, none past the lists' end
pub fn atNumber(index i64[,], n i64) ref i64[]:
	if n < 0 or n >= index.len: return noPositions
	index[n]

noPositions i64[] = []
