# `it` and `.hp` in a call's argument: the argument as a function of the value it stands for
# (`people.filter(.age > 30)`, `names.map("w{k}-{it}")`). The parser reads both as a placeholder,
# an identifier isFlagged flagPlaceholder whose text says how it was written. Where a call's
# argument is checked against a function of one parameter, an argument that holds a placeholder
# is made the lambda `fn $itN: argument`, the placeholders its parameter (itLambda). The innermost
# such argument wins: an argument wrapped by an outer one is wrapped again when its own call asks
# for a function, its placeholders renamed to its own parameter. A lambda written inside names its
# parameter: a placeholder in it is unbound. For zap fmt, a lambda `x: body` that could have
# been written so is noted as the body alone (noteItForm), and `it.hp` as `.hp` (noteItFields).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# whether e holds a placeholder no lambda inside e binds
fn hasPlaceholder(c Checker, e NodeId) bool:
	if nodes[e].hasFlag(flagPlaceholder): return true
	if nodes[e].kind == nLambda: return false
	nodes[e].kids(kidIds).any(c.hasPlaceholder(it)) or
		nodes[e].sub(kidIds).any(c.hasPlaceholder(it))

# the placeholders of e (not those of a lambda inside) named name
fn namePlaceholders(mut c Checker, e NodeId, name str):
	if nodes[e].hasFlag(flagPlaceholder):
		nodes[e].setText(name.copy())
	if nodes[e].kind == nLambda: return
	for i in 0..nodes[e].kids(kidIds).len:
		c.namePlaceholders(nodes[e].kids(kidIds)[i], name)
	for i in 0..nodes[e].sub(kidIds).len:
		c.namePlaceholders(nodes[e].sub(kidIds)[i], name)

# the call argument e, where a function of one value is expected, made the lambda of its
# placeholders when it holds one; whether it was
fn itLambda(mut c Checker, e NodeId):
	if nodes[e].kind == nLambda or not c.hasPlaceholder(e): return false
	line = nodes[e].line
	col = nodes[e].col
	name = "$it{e}"
	c.namePlaceholders(e, name)
	body = newNode(nodes, kidIds, nIdent, line, col)
	nodes[body] = nodes[e].copied(kidIds)
	lam = newNode(nodes, kidIds, nLambda, line, col, kids = [body])
	nodes[lam].nodeMore(kidIds).names.push(name)
	nodes[lam].nodePart(kidIds).types.push(newNode(nodes, kidIds, nTyAbsent, line, col))
	nodes[e] = nodes[lam].copied(kidIds)
	c.noteItFields(line)
	true

# how an unbound placeholder was written: `it`, or `.hp`
fn placeholderForm(text str):
	"it" if text == "$it" else text[3..].copy()

# ---------- the forms zap fmt writes ----------

# `it.hp` on the line (a lowercase field): noted as `.hp`, the same placeholder written short
fn noteItFields(mut c Checker, line i64):
	if not noting: return
	text = sourceLineOf(c.noteSource(), line)
	k = findWord(text, "it", 0)
	while k >= 0:
		if k + 3 < text.len and text[k + 2] == '.' and isLowerStart(text[k + 3]) and
			textPlace(text, k) != 1 and (k == 0 or text[k - 1] != '.'):
			c.canonNote(noteReplace, line, k + 1, 2, "", syntax = true)
		k = findWord(text, "it", k + 1)

fn isLowerStart(b u8):
	b >= 'a' and b <= 'z' or b == '_'

# the file whose line is being checked
fn noteSource(c Checker) ref str:
	c.file if c.curFile == "" else c.curFile

# A lambda `x: body` passed as a call's argument, x a value (not a function) read only at the
# body's own level: noted as the body alone, `it` for x, since the argument reads the same.
# Not when the body only hands x to a function by name (`x: churn(x)` is `churn`, fmt.zap);
# `x: x.churn()` is `.churn()`. Of a parameter whose type is not known yet (-1), only a body
# that reads x through its fields and methods alone.
fn noteItForm(mut c Checker, maybeLam NodeId?, paramType TypeId?):
	lam = maybeLam ?? return
	if not noting or nodes[lam].kind != nLambda or nodes[lam].names(kidIds).len != 1 or
		not nodes[lam].sub(kidIds).isEmpty or c.tKind(paramType) == tFn:
		return
	x = nodes[lam].names(kidIds)[0]
	body = nodes[lam].kids(kidIds)[0]
	if x.startsWith("$") or not mentionsAny(nodes, kidIds, body, [x.copy()]) or
		not c.valueUsesOnly(body, x):
		return
	line = nodes[lam].line
	text = sourceLineOf(c.noteSource(), line)
	at = nodes[lam].col - 1
	if at < 0 or at > text.len: return   # a line of another file (a generic checked at its definition)
	rest = text[at..]
	head = "({x}): " if rest.startsWith("({x}): ") else "{x}: "
	if not rest.startsWith(head) or argumentOpener(text, at) != '(': return
	# `x.f()` is written through the field-like `.f()`; `f(x)` stays for fmt.zap
	if c.handsOver(body, x) and not rest[head.len..].startsWith("{x}."): return
	start = at + head.len
	end = argumentEnd(text, start)
	if end < 0 or paramType == none and not fieldsOnly(text, start, end, x): return
	file = notePath(c.noteSource())
	if formNotes.any(.file == file and .line == line and .col == at + 1): return   # checked again
	shown, shownEnd = foldedNotes(file, line, at, end, text)
	c.canonNote(
		noteReplace, line, at + 1, end - at, itForm(shown, start, shownEnd, x), syntax = true
	)

# The line's text with the notes made inside its bytes past `at` up to `end` (a lambda inside, its
# `it.hp`) applied, and where `end` went: a note over the span takes them in, so they go.
fn foldedNotes(file str, line i64, at i64, end i64, text str):
	inner = formNotes
		.filter(.file == file and .line == line and .col > at + 1 and .col <= end)
		.sortedBy(-.col)
	shown = text.copy()
	shownEnd = end
	for n in inner:
		k = n.col - 1
		shown = shown[..k] + n.text + shown[k + n.cut..]
		shownEnd += n.text.len - n.cut
	formNotes = formNotes.filter(.file != file or .line != line or .col <= at + 1 or .col > end)
	(shown, shownEnd)

# whether x is read in e only at e's own level: not in a lambda inside, not as a struct's field
# filled by its name (`Point(x)`, checked or still a call of the type's name: the name is the
# field's, and `it` would lose it)
fn valueUsesOnly(c Checker, e NodeId, x str) bool:
	k = nodes[e].kind
	if k == nLambda:
		return x not in nodes[e].names(kidIds) and not mentionsAny(nodes, kidIds, e, [x.copy()])
	if k == nCall and c.constructorName(nodes[e].kids(kidIds)[0]) and
		nodes[e].kidsFrom(kidIds, 1)
			.any(c.namesBare(it, x)):
		return false
	if k == nStructLit:
		for i in 0..nodes[e].names(kidIds).len:
			kid NodeId? = nodes[e].kids(kidIds)[i] if i < nodes[e].kids(kidIds).len else none
			if nodes[e].names(kidIds)[i] == x and kid is kid and c.namesBare(kid, x): return false
	nodes[e].kids(kidIds).all(c.valueUsesOnly(it, x)) and
		nodes[e].sub(kidIds).all(c.valueUsesOnly(it, x))

# whether e is the name x, or x lent (a reference field's value: the checker wraps it)
fn namesBare(c Checker, e NodeId, x str) bool:
	if nodes[e].kind == nUnary and nodes[e].ival in [unRef, unMutRef] and
		nodes[e].kids(kidIds).len == 1:
		return c.namesBare(nodes[e].kids(kidIds)[0], x)
	nodes[e].kind == nIdent and nodes[e].text == x

# whether a callee names a type (`Point`, `geo.Point`): a call of it makes a struct
fn constructorName(c Checker, callee NodeId):
	name = nodes[callee].text if nodes[callee].kind in [nIdent, nField] else ""
	not name.isEmpty and name[0] >= 'A' and name[0] <= 'Z'

# whether e is `f(x)`: a function named bare, given x alone
fn handsOver(c Checker, e NodeId, x str):
	nodes[e].kind == nCall and nodes[e].kids(kidIds).len == 2 and
		nodes[nodes[e].kids(kidIds)[0]].kind == nIdent and not nodes[e].hasFlag(flagMethod) and
		nodes[nodes[e].kids(kidIds)[1]].kind == nIdent and nodes[nodes[e].kids(kidIds)[1]].text == x

# the bracket left open before position at of the line (the one the lambda there is an argument
# of), or 0
fn argumentOpener(text str, at i64) i64:
	kinds = byteKinds(text)
	depth = 0
	k = at - 1
	while k >= 0:
		if kinds[k] == byteCode or kinds[k] == byteInner:
			b = text[k]
			if b in [')', ']', '}']:
				depth += 1
			elif b in ['(', '[', '{']:
				if depth == 0: return b
				depth -= 1
		k -= 1
	0

# where the call argument that starts at start ends on the line: its `,` or the call's `)`; -1
# when it goes on to another line or another bracket closes first
fn argumentEnd(text str, start i64):
	depth = 0
	k = start
	while k < text.len:
		b = text[k]
		if b == '"' or b == '\'':
			k = literalEnd(text, k)
			if k < 0: return -1
			continue
		if b == '#': return -1
		if b in ['(', '[', '{']:
			depth += 1
		elif b in [')', ']', '}']:
			if depth == 0: return k if b == ')' else -1
			depth -= 1
		elif b == ',' and depth == 0:
			return k
		k += 1
	-1

# whether the word at w is a field (`p.x`), not a range's end (`0..x`)
fn fieldOf(text str, w i64):
	text[w - 1] == '.' and (w < 2 or text[w - 2] != '.')

# whether every x in the body text from start to end reads a field or a method of it (`x.hp`)
fn fieldsOnly(text str, start i64, end i64, x str):
	w = findWord(text, x, start)
	while w >= 0 and w < end:
		after = w + x.len
		if textPlace(text, w) != 1 and not fieldOf(text, w) and
			not (after + 1 < end and text[after] == '.' and isLowerStart(text[after + 1])):
			return false
		w = findWord(text, x, after)
	true

# the body text from start to end with `it` for the parameter x (`.hp` for `x.hp`); a field or
# a named argument called x stays
fn itForm(text str, start i64, end i64, x str):
	out = ""
	k = start
	loop:
		w = findWord(text, x, k)
		if w < 0 or w >= end: break
		after = w + x.len
		out += text[k..w]
		k = after
		if textPlace(text, w) == 1 or fieldOf(text, w) or
			text[after..end].startsWith(" = "):
			out += x
		elif after + 1 < end and text[after] == '.' and isLowerStart(text[after + 1]):
			pass   # `x.hp`: `.hp`
		else:
			out += "it"
	out + text[k..end]
