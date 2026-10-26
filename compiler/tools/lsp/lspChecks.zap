# The language server's answers from the checker (lspFacts.zap): the errors of the program a
# saved file belongs to, the types the checker inferred shown after the bindings written without
# one (inlay hints), a name's type on hover and what follows `x.` by x's checked type. A file's
# facts come from its program's check, made when it is saved, or when one of these answers first
# needs the facts of a file just opened. An editor may run a second server for the text's answers
# alone (`"checks": false` in initialize's initializationOptions), which never waits for a check.

type LspChecks:
	on bool = true
	names {str: NameFact[]} = {}   # the open files' names, by notePath
	unchecked {str: bool} = {}   # the open files no check has given names yet
	published {str: str} = {}   # the files errors were sent for -> the target whose check said them

# the program of the document at uri checked, its names kept for the open documents and its errors
# sent, those its last check said and this one no longer does cleared
fn check(mut k LspChecks, docs {str: str}, root str, uri str):
	texts {str: str} = {}
	wanted {str: bool} = {}
	openUris {str: str} = {}
	for u, text in docs:
		path = uriPath(u)
		texts[path.copy()] = text.copy()
		wanted[notePath(path)] = true
		openUris[notePath(path)] = u.copy()
	facts = checkFacts(root, uriPath(uri), texts, wanted)
	target = facts.target
	for key in wanted.keys():
		if not facts.names.isEmpty:   # (a program that did not load keeps the names it had)
			k.names[key.copy()] = facts.names.get(key)?.copy() ?? []
		k.unchecked.remove(key)
	for key in k.published.keys():
		if (k.published.get(key) ?? "") == target and facts.errors.get(key) == none:
			publish(openUris.get(key)?.copy() ?? pathUri(key), "")
			k.published.remove(key)
	for key, errors in facts.errors:
		said = openUris.get(key)?.copy() ?? pathUri(fullPath(errors[0].file))
		text = textOf(docs, said)
		publish(said, errors.map(diagnosticJson(text, it)).join(","))
		k.published[key.copy()] = target.copy()

# the facts of the document at uri, its program checked first when no check gave them yet
fn namesOf(mut k LspChecks, docs {str: str}, root str, uri str) ref NameFact[]:
	key = notePath(uriPath(uri))
	if k.unchecked.get(key) != none: k.check(docs, root, uri)
	k.names.get(key) ?? noNames

noNames NameFact[] = []

fn publish(uri str, items str):
	lspNotify(
		"textDocument/publishDiagnostics",
		"\{\"uri\":{jsonQuote(uri)},\"diagnostics\":[{items}]}"
	)

# an error over the word at its place (one character where none stands)
fn diagnosticJson(text str, e ErrorFact):
	lines = text.replace("\r", "").lines()
	width = 1
	if e.line < lines.len and e.col < lines[e.line].len:
		width = nameAt(lines[e.line], e.col).len.max(1)
	"\{\"range\":{rangeJson(e.line, e.col, e.line, e.col + width)},\"severity\":1,\"source\":\"zap\",\"message\":{jsonQuote(e.message)}}"

# where a fact's name stands in the line as it is now: a use at its own column, a binding at or
# after it (a let's place is its `mut`, a loop's its `for`); -1 when the text no longer has it
fn factColumn(line str, f NameFact):
	if f.col >= line.len: return -1
	if not f.binding: return f.col if findWord(line, f.name, f.col) == f.col else -1
	for at in wordColumns(line, f.name):
		if at >= f.col: return at
	-1

# whether a binding whose name ends at `end` is written without its type: what follows is `=`,
# `,`, `:`, `)` or `in`
fn untypedAt(line str, end i64):
	rest = line[end..].trimmedStart()
	not rest.isEmpty and (rest[0] in ['=', ',', ':', ')'] or rest.startsWith("in "))

# the inferred types of the bindings written without one, in the request's lines: after the name
# (`bits bool[] = ...`)
fn inlayHints(mut k LspChecks, docs {str: str}, root str, uri str, body str):
	range = body.indexOf("\"range\"") ?? -1
	first = jsonIntField(body, "line", range)
	last = jsonIntField(body, "line", body.indexOf("\"end\"", range.max(0)) ?? -1)
	lines = textOf(docs, uri).replace("\r", "").lines()
	shown {str: str} = {}   # by place: a body checked again says its bindings again, the last right
	for f in k.namesOf(docs, root, uri):
		if not f.binding or f.line < first or f.line > last or f.line >= lines.len: continue
		col = factColumn(lines[f.line], f)
		end = col + f.name.len
		if col < 0 or not untypedAt(lines[f.line], end) or "<error>" in f.ty: continue
		shown["{f.line}:{end}"] = "\{\"position\":\{\"line\":{f.line},\"character\":{end}},\"label\":{jsonQuote(hintLabel(f.ty))},\"kind\":1,\"paddingLeft\":true}"
	"[{shown.values().join(",")}]"

# a type as a hint shows it: a range whose bounds are the type's own limits as its type alone
# (`i64 in 0..=9223372036854775806` is i64; `u8 in 0..=9` stays)
fn hintLabel(ty str):
	at = ty.indexOf(" in ") ?? return ty.copy()
	bounds = ty[at + 4..].replace("..=", " ").replace("..", " ").split(" ")
	if bounds.any(.trimmedStart("-").len > 6): return ty[..at].copy()
	ty.copy()

# the checked name under the request's position, `name Type` (none when the checker typed none
# there), and whether it is the file's own (a binding of the file, a field), which no
# declaration elsewhere describes
fn typeAtPosition(mut k LspChecks, docs {str: str}, root str, uri str, body str) (str, bool)?:
	pos = body.indexOf("\"position\"") ?? -1
	line = jsonIntField(body, "line", pos)
	char = jsonIntField(body, "character", pos)
	lines = textOf(docs, uri).replace("\r", "").lines()
	if line < 0 or line >= lines.len: return none
	names = k.namesOf(docs, root, uri)
	found NameFact? = none
	for f in names:
		if f.line != line or "<error>" in f.ty: continue
		col = factColumn(lines[line], f)
		if col >= 0 and col <= char and char <= col + f.name.len:
			found = f.copy()   # the last: a body checked again
	f = try found
	col = factColumn(lines[line], f)
	field = col > 0 and lines[line][col - 1] == '.'
	own = field or names.any(.binding and .name == f.name and .line <= line)
	("{f.name} {f.ty}", own)

# the name of the type the checker gave the name before a `.` at line:col, for completion: a
# struct's, an enum's or a built-in's (`str`, `u8`), "" for a list, a map, a function or none
fn checkedTypeName(mut k LspChecks, docs {str: str}, root str, uri str, line i64, col i64):
	lines = textOf(docs, uri).replace("\r", "").lines()
	if line < 0 or line >= lines.len: return ""
	name = nameAt(lines[line], col)
	ty = ""
	for f in k.namesOf(docs, root, uri):
		if f.name != name: continue
		if f.line == line and factColumn(lines[line], f) == col:
			ty = f.ty.copy()
		elif f.binding and f.line <= line and ty == "":
			ty = f.ty.copy()   # the binding nearest above when the use is new
	t = dropPrefix(dropPrefix(ty, "mut ref "), "ref ").copy()
	if t.endsWith("?"): t = t[..len - 1].copy()
	if t.isEmpty or not (0..t.len).all(t[it].isWordByte() or t[it] == '.'): return ""
	dot = t.lastIndexOf(".") ?? -1
	t[dot + 1..].copy()
