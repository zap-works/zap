# TOML (1.0) read, not written: `import toml`, for config files (pyproject.toml, Cargo.toml). The
# document is turned into JSON, so it is read as JSON is: into the program's own types,
# `Config.fromJson(toml.json(text) ?? fail)` (a table is an object, an array of tables a list, a
# date or a time its text; `nan` and `inf` are null), checked once, or for a shape the program
# does not know as a `json.Doc`: `doc = toml.parse(text) ?? fail`, `doc.textOf(doc.root, "name")`.
# An error says the line. Tables, dotted keys, arrays of tables, inline tables, multi-line and
# literal strings, and the integer and float forms are read; a key given twice is an error.

import json

# what a value is
type Kind:
	Table   # keys and their values
	Array   # values
	Leaf   # a string, number, bool or date, already written as JSON

# a value of the document, in the reader's list: a table's values are its `kids`, named by `keys`
type Item:
	kind Kind
	text str = ""
	keys str[] = []
	kids i64[] = []

# why a document cannot be read, and the line it is at (0: none)
pub type Error:
	line i64
	message str

type Reader:
	source str
	at i64 = 0
	items Item[] = []

# The document as compact JSON text, or the line that cannot be read.
pub fn json(text str) str ? Error:
	r = Reader(source = text.copy())
	root = r.table()
	cur = root
	loop:
		r.skipBlank()
		if r.atEnd(): break
		if r.peek() == '[':
			array = r.at + 1 < text.len and text[r.at + 1] == '['
			r.at += 2 if array else 1
			path = try r.keyPath()
			try r.expect(']')
			if array: try r.expect(']')
			cur = try r.openTable(root, path, array)
		else:
			path = try r.keyPath()
			try r.expect('=')
			value = try r.value()
			try r.assign(cur, path, value)
		try r.endOfLine()
	out u8[] = []
	r.write(root, out)
	str(move out)

# The document as a `json.Doc`.
pub fn parse(text str) json.Doc ? Error:
	json.parse(try json(text)) ?? return Error(line = 0, message = error)

# ---------- reading ----------

fn atEnd(r Reader) bool:
	r.at >= r.source.len

# the byte at the cursor, 0 at the end
fn peek(r Reader) u8:
	r.source[r.at] if r.at < r.source.len else 0

fn error(r Reader, what str) Error:
	line = 1 + r.source[..r.at.min(len)].count('\n')
	Error(line, message = what.copy())

fn table(mut r Reader) i64:
	r.items.push(Item(kind = .Table))
	r.items.len - 1

fn leaf(mut r Reader, json str) i64:
	r.items.push(Item(kind = .Leaf, text = json.copy()))
	r.items.len - 1

# past spaces and tabs
fn skipSpace(mut r Reader):
	while r.peek() == ' ' or r.peek() == '\t':
		r.at += 1

# past white space, line breaks and comments
fn skipBlank(mut r Reader):
	while not r.atEnd():
		c = r.peek()
		if c == '#':
			while not r.atEnd() and r.peek() != '\n':
				r.at += 1
		elif c == ' ' or c == '\t' or c == '\n' or c == '\r':
			r.at += 1
		else:
			break

# the byte c next (after spaces), consumed
fn expect(mut r Reader, c u8) () ? Error:
	r.skipSpace()
	if r.peek() != c: return r.error("expected {str([c])}")
	r.at += 1

# what ends a line: spaces, a comment, a line break or the end
fn endOfLine(mut r Reader) () ? Error:
	r.skipSpace()
	if r.peek() == '#':
		while not r.atEnd() and r.peek() != '\n':
			r.at += 1
	if r.atEnd(): return
	if r.peek() == '\r': r.at += 1
	if r.peek() != '\n': return r.error("expected the end of the line")
	r.at += 1

fn isBare(c u8) bool:
	(c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or
		c == '-'

# a key, bare or quoted, and the keys after its dots
fn keyPath(mut r Reader) str[] ? Error:
	path str[] = []
	loop:
		r.skipSpace()
		c = r.peek()
		if c == '"' or c == 39:
			path.push(try r.quoted())
		else:
			from = r.at
			while isBare(r.peek()):
				r.at += 1
			if r.at == from: return r.error("expected a key")
			path.push(r.source[from..r.at].copy())
		r.skipSpace()
		if r.peek() != '.': break
		r.at += 1
	path

# whether the cursor is at three quotes q
fn atTriple(r Reader, q u8) bool:
	r.source[r.at..].startsWith(str([q, q, q]))

# The string at the cursor, its quotes (one or three, basic or literal) read. A basic string's
# escapes are read; a multi-line one drops its first line break and, after a backslash, the white
# space up to the next word.
fn quoted(mut r Reader) str ? Error:
	q = r.peek()
	multi = r.atTriple(q)
	r.at += 3 if multi else 1
	if multi and r.peek() == '\r': r.at += 1
	if multi and r.peek() == '\n': r.at += 1
	out u8[] = []
	loop:
		if r.atEnd(): return r.error("a string is never closed")
		c = r.peek()
		if c == q and (not multi or r.atTriple(q)):
			r.at += 3 if multi else 1
			if multi:
				while r.peek() == q:   # up to two more quotes are part of the text
					out.push(q)
					r.at += 1
			break
		if c == '\n' and not multi: return r.error("a string is never closed")
		if c == 92 and q == '"':
			r.at += 1
			try r.escape(out)
			continue
		out.push(c)
		r.at += 1
	str(move out)

# the escape after a backslash, as UTF-8
fn escape(mut r Reader, mut out u8[]) () ? Error:
	c = r.peek()
	r.at += 1
	if c == 'n': out.push('\n')
	elif c == 't': out.push('\t')
	elif c == 'r': out.push('\r')
	elif c == 'b': out.push(8)
	elif c == 'f': out.push(12)
	elif c == '"' or c == 92: out.push(c)
	elif c == 'u' or c == 'U':
		digits = 4 if c == 'u' else 8
		code = 0
		loop digits:
			d = hexValue(r.peek())
			if d < 0: return r.error("a bad unicode escape")
			code = code * 16 + d
			r.at += 1
		out.extend(rt.strFromCode(code).bytes())
	elif c == '\n' or c == ' ' or c == '\t' or c == '\r':   # a line ending backslash
		r.at -= 1
		while r.peek() == ' ' or r.peek() == '\t' or r.peek() == '\r' or r.peek() == '\n':
			r.at += 1
	else:
		return r.error("an unknown escape")

fn hexValue(c u8) i64:
	if c >= '0' and c <= '9': return i64(c) - 48
	if c >= 'a' and c <= 'f': return i64(c) - 87
	if c >= 'A' and c <= 'F': return i64(c) - 55
	-1

# whether c ends a bare value
fn endsValue(c u8) bool:
	c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == ',' or c == ']' or c == '}' or c == '#'

# the value at the cursor; its place in the items
fn value(mut r Reader) i64 ? Error:
	r.skipSpace()
	c = r.peek()
	if c == '"' or c == 39: return r.leaf(rt.jsonQuote(try r.quoted()))
	if c == '[': return try r.array()
	if c == '{': return try r.inlineTable()
	from = r.at
	while not r.atEnd() and not endsValue(r.peek()):
		r.at += 1
	# a date and a time apart by a space are one value
	if r.at - from == 10 and r.source[from + 4] == '-' and r.peek() == ' ' and
		r.at + 1 < r.source.len and r.source[r.at + 1] >= '0' and r.source[r.at + 1] <= '9':
		r.at += 1
		while not r.atEnd() and not endsValue(r.peek()):
			r.at += 1
	r.leaf(try r.scalar(r.source[from..r.at]))

# a bare word as JSON text: a bool, a date or time (quoted), an integer or a float
fn scalar(r Reader, word str) str ? Error:
	if word == "true" or word == "false": return word.copy()
	if word.len == 0: return r.error("expected a value")
	if word[0] >= '0' and word[0] <= '9' and
		(word.len > 4 and word[4] == '-' or word.len > 2 and word[2] == ':'):
		return rt.jsonQuote(word)
	digits = word.replace("_", "")
	sign = ""
	if digits.startsWith("-"):
		sign = "-"
		digits = digits[1..].copy()
	elif digits.startsWith("+"):
		digits = digits[1..].copy()
	if digits == "inf" or digits == "nan": return "null"
	if digits.len > 2 and digits[0] == '0' and
		(digits[1] == 'x' or digits[1] == 'o' or digits[1] == 'b'):
		base = 16 if digits[1] == 'x' else 8 if digits[1] == 'o' else 2
		n = 0
		for c in digits[2..].bytes():
			d = hexValue(c)
			if d < 0 or d >= base: return r.error("a bad number: {word}")
			n = n * base + d
		return "{sign}{n}"
	if json.parse(digits) is doc and doc.entries[0].kind == .Number: return "{sign}{digits}"
	r.error("a bad value: {word}")

fn array(mut r Reader) i64 ? Error:
	r.at += 1
	arr = r.items.len
	r.items.push(Item(kind = .Array))
	loop:
		r.skipBlank()
		if r.peek() == ']':
			r.at += 1
			break
		v = try r.value()
		r.items[arr].kids.push(v)
		r.skipBlank()
		if r.peek() == ',':
			r.at += 1
		elif r.peek() != ']':
			return r.error("expected , or ] in an array")
	arr

fn inlineTable(mut r Reader) i64 ? Error:
	r.at += 1
	t = r.table()
	r.skipSpace()
	if r.peek() == '}':
		r.at += 1
		return t
	loop:
		path = try r.keyPath()
		try r.expect('=')
		v = try r.value()
		try r.assign(t, path, v)
		r.skipSpace()
		if r.peek() == ',':
			r.at += 1
		elif r.peek() == '}':
			r.at += 1
			break
		else:
			return r.error("expected , or } in an inline table")
	t

# ---------- tables ----------

# the value named key in table t
fn member(r Reader, t i64, key str) i64?:
	k = r.items[t].keys.indexOf(key) ?? return none
	r.items[t].kids[k]

# the table to go on in under key in table t, made when there is none; an array of tables goes on
# in its last table
fn into(mut r Reader, t i64, key str) i64 ? Error:
	found = r.member(t, key)
	if found is at:
		if r.items[at].kind == .Table: return at
		if r.items[at].kind == .Array and not r.items[at].kids.isEmpty:
			last = r.items[at].kids[r.items[at].kids.len - 1]
			if r.items[last].kind == .Table: return last
		return r.error("{key} is not a table")
	made = r.table()
	r.items[t].keys.push(key.copy())
	r.items[t].kids.push(made)
	made

# the table a header names: [a.b], or the new table at the end of [[a.b]]'s array
fn openTable(mut r Reader, root i64, path str[], array bool) i64 ? Error:
	t = root
	for k in 0..path.len - 1:
		t = try r.into(t, path[k])
	last = path[len - 1]
	if not array: return try r.into(t, last)
	fresh = r.table()
	if r.member(t, last) is at:
		if r.items[at].kind != .Array: return r.error("{last} is not an array of tables")
		r.items[at].kids.push(fresh)
		return fresh
	list = r.items.len
	r.items.push(Item(kind = .Array, kids = [fresh]))
	r.items[t].keys.push(last.copy())
	r.items[t].kids.push(list)
	fresh

# key = value in table t, the key's dots naming tables below it
fn assign(mut r Reader, t i64, path str[], v i64) () ? Error:
	here = t
	for k in 0..path.len - 1:
		here = try r.into(here, path[k])
	last = path[len - 1]
	if r.member(here, last) != none: return r.error("{last} is given twice")
	r.items[here].keys.push(last.copy())
	r.items[here].kids.push(v)

# ---------- writing ----------

fn write(r Reader, i i64, mut out u8[]):
	item = r.items[i]
	match item.kind:
		Leaf: rt.outStr(out, item.text)
		Array:
			out.push('[')
			for k, kid in item.kids:
				if k > 0: out.push(',')
				r.write(kid, out)
			out.push(']')
		Table:
			out.push('{')
			for k, kid in item.kids:
				if k > 0: out.push(',')
				rt.outQuoted(out, item.keys[k])
				out.push(':')
				r.write(kid, out)
			out.push('}')
