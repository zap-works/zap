# JSON read into a flat list of entries: a value is a Node, a place in that list, a
# container's values are a run of `children` (an object's members carry their keys), so the tree
# needs no recursive type. The tokens are read by the runtime's JSON reader (runtime/text/value.zap).
# A module of the standard library: `import json`, then `doc = json.parse(text) ?? fallback`,
# `doc.get(doc.root, "name")`, `doc[node].kind`.

# what a JSON value is
pub type Kind:
	Null
	Bool   # its number is 1 or 0
	Number
	Text
	List
	Object   # its children are the members, each with its key

# a value of a document: where its entry lies in the document's entries (doc[node])
pub type Node:
	at i64

# what a value holds
pub type Entry:
	kind Kind
	number f64   # a number's value; a bool's 1 or 0
	text str   # a string's text
	key str   # the key, when the value is an object's member
	first i64   # a container's first child in `children`
	count i64   # a container's children

pub type Doc:
	entries Entry[] = []
	children Node[] = []
	root Node = Node(at = 0)

	# doc[node]: what the value holds
	fn index(node Node) ref Entry:
		entries[node.at]

	# an object's member by its key
	fn get(node Node, key str) Node?:
		n = entries[node.at]
		if n.kind != .Object: return none
		for k in 0..n.count:
			c = children[n.first + k]
			if entries[c.at].key == key: return c
		none

	# an array's k-th value (an object's k-th member)
	fn at(node Node, k i64):
		children[entries[node.at].first + k]

	# how many values an array (or members an object) holds; 0 for others
	fn count(node Node):
		entries[node.at].count

	# a member's number (a bool's is 1 or 0); none when it is missing
	fn number(node Node, key str) f64?:
		match get(node, key):
			v: entries[v.at].number
			none: none

	# a member's string, or "" when it is missing
	fn textOf(node Node, key str):
		match get(node, key):
			v: entries[v.at].text
			none: ""

	# an array's numbers (a member's, missing: none)
	fn numbers(node Node, key str) f64[]?:
		match get(node, key):
			v: children[entries[v.at].first..entries[v.at].first + entries[v.at].count]
				.map(entries[.at].number)
			none: none

	# The document as JSON text (Python's `json.dumps`): compact, as the types' own `toJson` writes
	# it (`{"a":[1,2]}`), or with `indent` spaces a level, one value a line (`{"a": 1}` spread out).
	# Strings are escaped and numbers written as `toJson` does (the shortest digits that read back;
	# a whole number without a point, past 2^53 not exact: numbers are floats here).
	fn text(indent i64 = 0) str:
		out u8[] = []
		self.write(root, out, indent, 0)
		str(move out)

	# the value of the node, its members below it `depth + 1` levels in
	fn write(node Node, mut out u8[], indent i64, depth i64):
		e = entries[node.at]
		match e.kind:
			Null: rt.outStr(out, "null")
			Bool: rt.outBool(out, e.number != 0.0)
			Number: rt.outJsonFloat(out, e.number)
			Text: rt.outQuoted(out, e.text)
			List, Object:
				out.push('[' if e.kind == .List else '{')
				for k in 0..e.count:
					child = children[e.first + k]
					if k > 0: out.push(',')
					lineBreak(out, indent, depth + 1)
					if e.kind == .Object:
						rt.outQuoted(out, entries[child.at].key)
						rt.outStr(out, ": " if indent > 0 else ":")
					self.write(child, out, indent, depth + 1)
				if e.count > 0: lineBreak(out, indent, depth)
				out.push(']' if e.kind == .List else '}')

# a line break and the indentation of the depth, when the text is indented
fn lineBreak(mut out u8[], indent i64, depth i64):
	if indent > 0:
		out.push('\n')
		rt.outStr(out, " ".repeat(indent * depth))

# a container being read: its kind, its own key, an object's key waiting for its value, and the
# values read so far
type Open:
	kind Kind
	key str
	pending str = ""
	kids Node[] = []

# The JSON text read, or why it is not JSON: no text stops the program (`use noStops`), so the
# containers open are kept in a list rather than in calls of a reader.
pub fn parse(text str) Doc ? str:
	use noStops
	cur = Cursor(at = 0)
	j = Doc()
	open Open[] = []
	loop:
		# a value, the next of the innermost container (its key read), or the whole text's
		key = ""
		if not open.isEmpty:
			key = move open[len - 1].pending
		if rt.jsonEnd(text, cur): return "JSON: the text ends where a value was expected"
		v = Node(at = 0)
		if rt.jsonChar(text, cur, '{'):
			if rt.jsonChar(text, cur, '}'):
				v = j.container(.Object, move key, [])
			else:
				pending = memberKey(text, cur) ?? return "JSON: a bad key at byte {cur.at}"
				open.push(Open(kind = .Object, key = move key, pending))
				continue
		elif rt.jsonChar(text, cur, '['):
			if rt.jsonChar(text, cur, ']'):
				v = j.container(.List, move key, [])
			else:
				open.push(Open(kind = .List, key = move key))
				continue
		elif rt.jsonText(text, cur) is s:
			v = j.add(.Text, 0.0, s, move key)
		elif rt.jsonNull(text, cur):
			v = j.add(.Null, 0.0, "", move key)
		elif rt.jsonBool(text, cur) is b:
			v = j.add(.Bool, 1.0 if b else 0.0, "", move key)
		elif rt.jsonFloat(text, cur) is n:
			v = j.add(.Number, n, "", move key)
		else:
			return "JSON: unexpected byte at byte {cur.at}"
		# the value given to its container; each container it ends ends in turn
		loop:
			if open.isEmpty:
				if not rt.jsonEnd(text, cur): return "JSON: more after the value, at byte {cur.at}"
				j.root = v
				return j
			open[len - 1].kids.push(v)
			if rt.jsonChar(text, cur, ','):
				if open[len - 1].kind == .Object:
					open[len - 1].pending = memberKey(text, cur) ??
						return "JSON: a bad key at byte {cur.at}"
				break
			closer = '}' if open[len - 1].kind == .Object else ']'
			if not rt.jsonChar(text, cur, closer):
				return "JSON: expected byte {closer} at byte {cur.at}"
			done = open.pop() ?? return "JSON: no container open"
			v = j.container(done.kind, done.key, done.kids)
	"JSON: no value"

# an object's member's key and its colon; none when they are not there
fn memberKey(s str, mut cur Cursor) str?:
	key = try rt.jsonText(s, cur)
	if not rt.jsonChar(s, cur, ':'): return none
	key

# the integer written at `at` in s (after white space); none when there is none
pub fn intAt(s str, at i64) i64?:
	cur = Cursor(at)
	rt.jsonInt(s, cur)

# the string whose quote is at `at` in s (after white space), its escapes read; none when there is
# none
pub fn textAt(s str, at i64) str?:
	cur = Cursor(at)
	rt.jsonText(s, cur)

# where the value written at `at` in s ends; none when there is no JSON value there
pub fn valueEnd(s str, at i64) i64?:
	cur = Cursor(at)
	if not rt.jsonSkip(s, cur): return none
	cur.at

fn add(
	mut j Doc,
	kind Kind,
	number f64,
	move text str,
	move key str,
	first i64 = 0,
	count i64 = 0
):
	j.entries.push(Entry(kind, number, text = move text, key = move key, first, count))
	Node(at = j.entries.len - 1)

# a container's entry, its values put in the children in order
fn container(mut j Doc, kind Kind, move key str, kids Node[]) Node:
	first = j.children.len
	j.children.extend(kids)
	j.add(kind, 0.0, "", move key, first, kids.len)
