# The language server, `zap lsp`: the Language Server Protocol over stdin and stdout, for an
# editor (tools/vscode-zap starts it). It reads sources as text: a declaration is a line that
# starts one (fn, type, test, a module binding), so it answers while a file is half written. It
# offers the outline of a file, the declarations of the project by name, go to definition, hover
# (the declaration and the comment above it, or what spec/ says of the name), what follows
# `orbit.` (the fields of its type, then the functions taking it first), the words' colours
# (lspTokens.zap) and the checker's errors, which come from `zap test --only check` run on the
# saved file.

import fs
import json

type Decl:
	name str
	kind i64   # the protocol's SymbolKind
	line i64   # 0-based, as the protocol counts
	col i64
	endLine i64
	detail str   # the declaration's line as written
	container str   # a method's type (the function takes `self` of it), or ""
	doc str   # the comment lines right above it

symFunction = 12
symMethod = 6
symStruct = 23
symEnum = 10
symConstant = 14
symVariable = 13
symInterface = 11

pub fn lspServe():
	docs {str: str} = {}
	root = "."
	going = true
	while going:
		match lspRead():
			body:
				method = jsonStrField(body, "method", 0) ?? ""
				id = jsonRawField(body, "id")
				uri = jsonStrField(body, "uri", 0) ?? ""
				if method == "initialize":
					given = uriPath(jsonStrField(body, "rootUri", 0) ?? "")
					if given != "":
						root = given
					lspReply(id, capabilities())
				elif method == "shutdown":
					lspReply(id, "null")
				elif method == "exit":
					going = false
				elif method == "textDocument/didOpen":
					publishDiagnostics(root, uri)   # from the saved file, so before the text is kept
					docs[uri] = jsonStrField(body, "text", 0) ?? ""
				elif method == "textDocument/didChange":
					changes = body.indexOf("\"contentChanges\"") ?? -1
					if changes >= 0:
						docs[uri] = jsonStrField(body, "text", changes) ?? ""
				elif method == "textDocument/didSave":
					publishDiagnostics(root, uri)
				elif method == "textDocument/didClose":
					docs.remove(uri)
					lspNotify(
						"textDocument/publishDiagnostics",
						"\{\"uri\":{jsonQuote(uri)},\"diagnostics\":[]}"
					)
				elif method == "textDocument/documentSymbol":
					lspReply(id, documentSymbols(textOf(docs, uri)))
				elif method == "workspace/symbol":
					lspReply(id, workspaceSymbols(docs, root, jsonStrField(body, "query", 0) ?? ""))
				elif method == "textDocument/references":
					lspReply(id, references(docs, root, uri, body))
				elif method == "textDocument/definition":
					lspReply(id, definition(docs, root, uri, body))
				elif method == "textDocument/hover":
					lspReply(id, hover(docs, root, uri, body))
				elif method == "textDocument/completion":
					lspReply(id, completion(docs, root, uri, body))
				elif method == "textDocument/semanticTokens/full":
					lspReply(id, semanticTokens(textOf(docs, uri), isMarkupFile(uri)))
				elif method == "textDocument/formatting":
					lspReply(id, formatting(textOf(docs, uri), uri))
				elif id != "":
					lspReply(id, "null")   # a request this server does not answer
			none: going = false

fn capabilities():
	"\{\"capabilities\":\{\"textDocumentSync\":\{\"openClose\":true,\"change\":1,\"save\":true},\"documentSymbolProvider\":true,\"workspaceSymbolProvider\":true,\"definitionProvider\":true,\"referencesProvider\":true,\"hoverProvider\":true,\"completionProvider\":\{\"triggerCharacters\":[\".\"]},\"documentFormattingProvider\":true,\"semanticTokensProvider\":\{\"legend\":{semanticLegend()},\"full\":true}},\"serverInfo\":\{\"name\":\"zap\"}}"

# ---------- messages ----------

# one message: the headers up to a blank line, then Content-Length bytes; none at the end
fn lspRead():
	length = -1
	going = true
	while going:
		match stdin.line():
			line:
				if line == "":
					going = false
				elif line.startsWith("Content-Length:"):
					length = i64.parse(line[15..].trimmed()) ?? -1
			none: return none
	if length < 0: return none
	stdin.text(length)

fn lspSend(json str):
	stdout.write("Content-Length: {json.len}\r\n\r\n")
	stdout.write(json)

fn lspReply(id str, result str):
	lspSend("\{\"jsonrpc\":\"2.0\",\"id\":{id},\"result\":{result}}")

fn lspNotify(method str, params str):
	lspSend("\{\"jsonrpc\":\"2.0\",\"method\":{jsonQuote(method)},\"params\":{params}}")

# ---------- the JSON the server reads: fields found by name ----------

# the position right after "key": in body, searching from `start`; -1 when absent
fn jsonAt(body str, key str, start i64):
	k = body.indexOf("\"{key}\":", start) ?? return -1
	i = k + key.len + 3
	while i < body.len and body[i] == ' ':
		i += 1
	i

fn jsonStrField(body str, key str, start i64) str?:
	i = jsonAt(body, key, start)
	if i < 0 or i >= body.len or body[i] != '"': return none
	jsonStrAt(body, i)

fn jsonIntField(body str, key str, start i64):
	i = jsonAt(body, key, start)
	if i < 0: return 0
	json.intAt(body, i) ?? 0

# a field's value as written (a number or a quoted string), "" when absent: a request's id
fn jsonRawField(body str, key str) ref str:
	i = jsonAt(body, key, 0)
	if i < 0: return body[..0]
	body[i..json.valueEnd(body, i) ?? i]

# the JSON string starting at the quote at `at`, its escapes read
fn jsonStrAt(body str, at i64):
	json.textAt(body, at) ?? ""

# ---------- files ----------

# the path a file: URI names (file:///c%3A/x/y.zap is c:/x/y.zap)
fn uriPath(uri str) str:
	start = 0
	if uri.startsWith("file:///"):
		start = 8
	s = uri[start..]
	out = []
	i = 0
	while i < s.len:
		if s[i] == '%' and i + 2 < s.len:
			out.push(u8(s[i + 1].hexValue() * 16 + s[i + 2].hexValue()))
			i += 3
		else:
			out.push(s[i])
			i += 1
	str(move out)

fn pathUri(path str):
	"file:///{path.replace("\\", "/")}"

# the text of an open document, else the file on disk
fn textOf(docs {str: str}, uri str):
	match docs.get(uri):
		text: text.copy()
		none: fs.readFile(uriPath(uri)) ?? ""

# every file a name is looked for in: the project's, then the runtime's and the standard library's
fn searchFiles(root str):
	files = fs.walk(root, sources = true)
	rt = runtimeDir()
	if not rt.replace("\\", "/").lower().startsWith(root.replace("\\", "/").lower()):
		files.extend(fs.walk(rt[..len - 1], sources = true))
		files.extend(fs.walk(stdDir()[..stdDir().len - 1], sources = true))
	files

# ---------- declarations ----------

# the identifier starting at i of s
fn nameAt(s str, i i64) ref str:
	j = i
	while j < s.len and s[j].isWordByte():
		j += 1
	s[i..j]

fn dropPrefix(s str, prefix str) ref str:
	if s.startsWith(prefix): return s[prefix.len..]
	s

# s from its `fn` on when it is an extern declaration (extern "dll" fn name...), else s
fn dropExtern(s str) ref str:
	if s.startsWith("extern "): return s[(s.indexOf("fn ") ?? 0)..]
	s

# the declarations of a source text, each with its extent and the comment above it
fn scanDecls(text str):
	lines = text.replace("\r", "").lines()
	scans = scanLines(lines)
	out = []
	block = ""   # the type whose block the line is in ...
	blockEnds = -1
	members = -1   # ... and its members' indentation
	for i, raw in lines:
		ind = leadingSpaces(raw)
		t = raw.trimmed()
		if t == "" or t.startsWith("#") or scans[i].kind != lineCode:
			continue
		name = ""
		kind = -1
		container = ""
		detail = signatureOf(codeOf(t))
		# name and container are the Decl's own (copies of the line's text, which goes away)
		noPub = dropPrefix(t, "pub ")   # each step a window into t
		if ind > 0 and i <= blockEnds:
			if members < 0:
				members = ind
			if ind == members and blockMethodLine(noPub):
				name = nameAt(noPub, (noPub.indexOf("fn ") ?? 0) + 3).copy()
				kind = symMethod
				container = block.copy()
				detail = loneMethodForm(detail, block)
		if ind == 0:
			bare = dropPrefix(noPub, "shared ")
			s = dropExtern(bare)
			if s.startsWith("fn "):
				name = nameAt(s, 3).copy()
				kind = symFunction
			elif s.startsWith("type "):
				name = nameAt(s, 5).copy()
				kind = symEnum if firstMemberIsVariant(lines, i) else symStruct
				block = name.copy()
				blockEnds = blockEnd(lines, i)
				members = -1
			elif s.startsWith("bound "):
				name = nameAt(s, 6).copy()
				kind = symInterface
			elif s.startsWith("{testWord} \""):
				close = s.indexOf("\"", testWord.len + 2) ?? -1
				if close > 0:
					name = s[..close + 1].copy()
					kind = symFunction
			elif s.startsWith("mut ") and s[4].isWordByte():
				name = nameAt(s, 4).copy()
				kind = symVariable
			elif s[0] >= 'a' and s[0] <= 'z' and " = " in s and not s.startsWith("import "):
				word = nameAt(s, 0)
				if not word.isEmpty and
					(
						s[word.len..].startsWith(" = ") or
							s[word.len..].startsWith(" ")
					):
					name = word.copy()
					kind = symConstant
		if kind >= 0 and name != "":
			col = (raw.indexOf(name) ?? -1).max(0)
			out.push(
				Decl(
					name,
					kind,
					line = i,
					col,
					endLine = blockEnd(lines, i),
					detail,
					container,
					doc = commentAbove(lines, i)
				)
			)
	out

# whether a line of a type's block, `pub ` left out, declares a method: `fn`, `mut fn`
fn blockMethodLine(s str):
	s.startsWith("fn ") or s.startsWith("mut fn ")

# a block method's signature as the function taking its type first would be written (`fn
# grow(by f32) f32` of Orbit is `fn grow(self Orbit, by f32) f32`), as the callers read them
fn loneMethodForm(sig str, block str):
	changes = sig.startsWith("mut fn ") or sig.startsWith("pub mut fn ")
	plain = sig.replace("mut fn ", "fn ")
	open = plain.indexOf("(") ?? return plain.copy()
	receiver = "{"mut " if changes else ""}self {block}"
	empty = open + 1 < plain.len and plain[open + 1] == ')'
	"{plain[..open + 1]}{receiver}{"" if empty else ", "}{plain[open + 1..]}"

# a function's line's first parameter as written ("" for none)
fn firstParam(sig str) ref str:
	end = firstParamEnd(sig)
	if end < 0: return ""
	sig[(sig.indexOf("(") ?? 0) + 1..end].trimmed()

# where a function's line's first parameter ends: the `,` or `)` after it (outside its type's
# brackets), the line's end when it goes on below, -1 when the line lists no parameters
fn firstParamEnd(sig str):
	open = sig.indexOf("(") ?? -1
	if open < 0: return -1
	depth = 0
	for i in open + 1..sig.len:
		b = sig[i]
		if b in ['<', '(', '[']:
			depth += 1
		elif depth == 0 and (b == ',' or b == ')'):
			return i
		elif b in ['>', ']', ')']:
			depth -= 1
	sig.len

# a call's form of a function's line: name, then the parameters after the first
# (`fn top<T>(self Stack<T>) ref T?` with name top is `top() ref T?`)
fn afterFirstParam(name str, sig str):
	end = firstParamEnd(sig)
	if end < 0: return name.copy()
	rest = end + 2 if end < sig.len and sig[end] == ',' else end
	"{name}({sig[rest..]}"

# the name of the type of a function's first parameter (`o Orbit`, `mut self Orbit`,
# `o engine.Orbit`), "" when it takes none
fn firstParamType(sig str):
	words = firstParam(sig).split(" ")
	if words.len < 2: return ""
	t = words[len - 1]
	dot = t.lastIndexOf(".") ?? -1
	nameAt(t, dot + 1).copy()

# a declaration's line up to the `:` that opens its body (a body on the same line left out)
fn signatureOf(code str):
	k = topColon(code)
	(code[..k] if k >= 0 else code).trimmed().copy()

# whether the type declared at line i lists variants (a capital first member) rather than fields
fn firstMemberIsVariant(lines str[], i i64):
	j = i + 1
	while j < lines.len:
		t = lines[j].trimmed()
		if t != "" and not t.startsWith("#"):
			return t[0] >= 'A' and t[0] <= 'Z'
		j += 1
	false

# the line where the brackets opened on line i close (i itself when it leaves none open), the
# lines as the line scanner read them
fn blockEnd(lines str[], i i64):
	tabs = indentOf(lines[i])
	j = i + 1
	while j < lines.len:
		if lines[j].trimmed() != "" and indentOf(lines[j]) <= tabs: return j
		j += 1
	lines.len - 1

# the comment lines right above line i, at its indentation, as one text
fn commentAbove(lines str[], i i64):
	first = i
	while first > 0 and lines[first - 1].trimmed().startsWith("#"):
		first -= 1
	out = ""
	for j in first..i:
		if j > first:
			out += "\n"
		t = lines[j].trimmed()
		out += dropPrefix(t[2..], " ")
	out

# ---------- answers ----------

fn rangeJson(line0 i64, col0 i64, line1 i64, col1 i64):
	"\{\"start\":\{\"line\":{line0},\"character\":{col0}},\"end\":\{\"line\":{line1},\"character\":{col1}}}"

fn declJson(d Decl, children str):
	kids = ""
	if children != "":
		kids = ",\"children\":[{children}]"
	"\{\"name\":{jsonQuote(d.name)},\"detail\":{jsonQuote(d.detail)},\"kind\":{d.kind},\"range\":{rangeJson(d.line, 0, d.endLine, 1000)},\"selectionRange\":{rangeJson(d.line, d.col, d.line, d.col + d.name.len)}{kids}}"

# the outline: the declarations, a type's methods in the file under it
fn documentSymbols(text str):
	decls = scanDecls(text)
	types = decls.filter(.kind == symStruct or .kind == symEnum).map(.name.copy())
	items = []
	for d in decls:
		if d.container != "" and d.container in types: continue
		children = []
		if d.kind == symStruct or d.kind == symEnum:
			children = decls.filter(.container == d.name).map(.declJson(""))
		items.push(d.declJson(children.join(",")))
	"[{items.join(",")}]"

fn locationJson(path str, d Decl):
	"\{\"uri\":{jsonQuote(pathUri(path))},\"range\":{rangeJson(d.line, d.col, d.line, d.col + d.name.len)}}"

# the project's declarations whose names contain the query (any case)
fn workspaceSymbols(docs {str: str}, root str, query str):
	q = query.lower()
	items = []
	for path in searchFiles(root):
		for d in scanDecls(textOf(docs, pathUri(path))):
			if items.len < 500 and q in d.name.lower():
				items.push("\{\"name\":{jsonQuote(d.name)},\"kind\":{d.kind},\"containerName\":{jsonQuote(d.container)},\"location\":{locationJson(path, d)}}")
	"[{items.join(",")}]"

# the identifier under the cursor and whether a dot comes before it (a method or field)
fn wordAt(text str, line i64, col i64):
	lines = text.replace("\r", "").lines()
	if line < 0 or line >= lines.len: return ("", false)
	l = lines[line]
	a = col.min(l.len)
	while a > 0 and l[a - 1].isWordByte():
		a -= 1
	(nameAt(l, a).copy(), a > 0 and l[a - 1] == '.')   # its own: the lines go away

# the declarations named by the word at the request's position: this file's first, then the
# project's; a method of a list, str or map is also its runtime function (xs.push is listPush)
type LspHit:
	file str
	decl Decl

fn lookup(docs {str: str}, root str, uri str, body str):
	pos = body.indexOf("\"position\"") ?? -1
	word, method = wordAt(
		textOf(docs, uri),
		jsonIntField(body, "line", pos),
		jsonIntField(body, "character", pos)
	)
	found = []
	if word == "": return found
	names = []
	if method and not word.isEmpty:
		names.extend(rtMethodNames(word))
	names.push(word)
	# this file first, then the ones it sees (its module, its parts, its imports), then the others
	# (any spelling of a path once)
	here = uriPath(uri)
	seen = seenFiles(root, here, textOf(docs, uri).replace("", "").lines())
	files = [here]
	candidates = seen.copy()
	candidates.extend(searchFiles(root))
	for f in candidates:
		if not files.any(.replace("\\", "/").lower() == f.replace("\\", "/").lower()):
			files.push(f.copy())
	for fi, f in files:
		decls = scanDecls(textOf(docs, pathUri(f)))
		for k in 0..decls.len:
			if decls[k].name in names and (method or decls[k].kind != symMethod):
				found.push(LspHit(f.copy(), move decls[k]))   # a file can have several hits
		if not found.isEmpty and (fi == 0 or fi < seen.len):
			return found   # a declaration in the same file wins, then one the file sees
	found

fn definition(docs {str: str}, root str, uri str, body str):
	items = lookup(docs, root, uri, body).map(locationJson(.file, .decl))
	"[{items.join(",")}]"

# Every use of the identifier at the request's position in the project (the open documents as
# they are): whole words outside strings and comments, inside {} of an interpolation too. The
# declaration itself is left out when the request asks so (a count of references).
fn references(docs {str: str}, root str, uri str, body str):
	pos = body.indexOf("\"position\"") ?? -1
	word, _ = wordAt(
		textOf(docs, uri),
		jsonIntField(body, "line", pos),
		jsonIntField(body, "character", pos)
	)
	if word == "": return "[]"
	flag = jsonAt(body, "includeDeclaration", 0)
	withDecl = flag < 0 or not body[flag..].startsWith("false")
	hits = lookup(docs, root, uri, body)
	scope = [uriPath(uri)]
	if not hits.isEmpty:
		scope = filesSeeing(docs, root, hits[0].file)
	items = []
	for f in scope:
		text = textOf(docs, pathUri(f))
		if word not in text: continue
		declared = []   # line * 100000 + column of each declaration of it
		if not withDecl:
			declared = scanDecls(text)
				.filter(.name == word)
				.map(.line * 100_000 + .col)
		lines = text.replace("\r", "").lines()
		scans = scanLines(lines)
		for i, l in lines:
			if scans[i].kind != lineCode and scans[i].kind != lineRaw:
				continue   # the text of a string or a comment
			for c in wordColumns(l, word):
				if i * 100_000 + c not in declared:
					items.push("\{\"uri\":{jsonQuote(pathUri(f))},\"range\":{rangeJson(i, c, i, c + word.len)}}")
	"[{items.join(",")}]"

# the files a declaration of `file` can be used from: the whole project for the runtime's;
# the dir and the files that import it for a module's (a dir some file imports); the file
# alone for a program's
fn filesSeeing(docs {str: str}, root str, file str):
	all = searchFiles(root)
	dir = dirPrefix(file).replace("\\", "/").lower()
	if dir == runtimeDir().replace("\\", "/").lower(): return all
	parts = dir[..len - 1].split("/")
	module = parts[len - 1]
	importers = (0..all.len).filter(imports(textOf(docs, pathUri(all[it])), module))   # indices into all
	if importers.isEmpty:
		ownFiles = moduleOfPart(root, file)
		if ownFiles.len > 1: return all.filter(.replace("\\", "/").lower() in ownFiles)
		return [file.copy()]   # the caller keeps its own
	out = []
	for k in 0..all.len:
		if dirPrefix(all[k]).replace("\\", "/").lower() == dir or k in importers:
			out.push(move all[k])
	out

# the columns where word stands whole in the line's code: a string's interpolations are code,
# its text and a comment are not (scan.zap)
fn wordColumns(l str, word str):
	cols = []
	kinds = byteKinds(l)
	at = findWord(l, word, 0)
	while at >= 0:
		if kinds[at] == byteCode or kinds[at] == byteInner:
			cols.push(at)
		at = findWord(l, word, at + 1)
	cols

# the declaration's line and the comment above it
# The declaration under the cursor and the comment above it; where there is no comment (an
# operation the compiler writes in line, such as map, reduce or parallelMap, or a function nobody
# described), what the language specification says of the name.
fn hover(docs {str: str}, root str, uri str, body str):
	hits = lookup(docs, root, uri, body)
	text = ""
	if not hits.isEmpty:
		d = hits[0].decl
		text = "```zap\n{d.detail}\n```"
		if d.container != "":
			text += "\na method of `{d.container}`"
		if d.doc != "": return hoverJson("{text}\n\n{d.doc}")
		if not inRuntime(hits[0].file):
			return hoverJson(text)   # the program's own: the specification is not about it
	pos = body.indexOf("\"position\"") ?? -1
	word, _ = wordAt(
		textOf(docs, uri),
		jsonIntField(body, "line", pos),
		jsonIntField(body, "character", pos)
	)
	notes = specDocs(root, word)
	if notes.isEmpty: return "null" if text == "" else hoverJson(text)
	if text != "":
		text += "\n\n"
	text += notes.map("- {it}").join("\n")
	hoverJson(text)

fn hoverJson(markdown str):
	"\{\"contents\":\{\"kind\":\"markdown\",\"value\":{jsonQuote(markdown)}}}"

# What the specification (spec/, beside the runtime) says of a name, at most three
# notes, the most precise first: a row of a table whose first cell names it, the comment of an
# example line that calls it, the sentence of a paragraph that names it. Read at every request,
# so the hover follows the specification as the language changes.
fn specDocs(root str, word str):
	out = []
	if word == "": return out
	notes = SpecNotes(
		rows = [],
		examples = [],
		sentences = [],
		para = "",
		inCode = false,
		lastExample = -1
	)
	read = ""
	for s in specSections():
		if s.file == read: continue
		read = s.file.copy()
		for line in specMarkdown(fs.readFile(s.file) ?? ""):
			notes.noteLine(line, word)
	notes.flushParagraph(word)
	out.extend(notes.rows.map(.copy()))
	out.extend(notes.examples.map(.copy()))
	out.extend(notes.sentences.map(.copy()))
	out.truncate(3)
	out

# the language's specification: beside the runtime the compiler reads (the repository's spec/)
fn specDir():
	rt = runtimeDir()
	"{dirPrefix(rt[..rt.len - 1])}spec/"

# a file of the spec as the markdown its comments write: a comment's text without its `# `, and
# its tests' code between fences, as an example
fn specMarkdown(text str):
	out = []
	inTest = false
	for line in text.replace("\r", "").lines():
		prose = line.startsWith("#")
		if line == "":
			out.push("")
			continue
		if prose and inTest:
			out.push("```")
		elif not prose and not inTest:
			out.push("```zap")
		inTest = not prose
		out.push(line.copy() if not prose else line[2..].copy() if line.startsWith("# ") else "")
	if inTest:
		out.push("```")
	out

# the notes found so far, and the paragraph being read
type SpecNotes:
	rows str[]
	examples str[]
	sentences str[]
	para str   # the prose read since the last paragraph break
	inCode bool
	lastExample i64   # the example noted from the previous line (-1 = none): a comment
	# alone on the next line continues it

fn noteLine(mut n SpecNotes, line str, word str):
	t = line.trimmed()
	if t.startsWith("```"):
		n.flushParagraph(word)
		n.inCode = not n.inCode
		n.lastExample = -1
		return
	if n.inCode:
		at = t.indexOf("#") ?? -1
		if at == 0 and n.lastExample >= 0:
			n.examples[n.lastExample] = "{n.examples[n.lastExample]} {t[2..].trimmed()}"
			return
		n.lastExample = -1
		if at > 0 and callMention(t[..at], word) >= 0:
			note = "`{t[..at].trimmed()}` : {t[at + 2..].trimmed()}"
			if note not in n.examples:
				n.examples.push(note)
				n.lastExample = n.examples.len - 1
		return
	if t.startsWith("|"):
		n.flushParagraph(word)
		cells = t.split("|")   # "", the name, what it gives, ""
		if cells.len >= 3 and cells[1].trimmed().startsWith("`") and
			callMention(cells[1], word) >= 0:
			n.rows.push("{cells[1].trimmed()} : {cells[2].trimmed()}")
		return
	if t == "" or t.startsWith("#") or t.startsWith("- "):
		n.flushParagraph(word)   # a blank line, a heading or a new item
	if t != "" and not t.startsWith("#"):
		n.para = dropPrefix(t, "- ").copy() if n.para == "" else "{n.para} {t}"

# the sentence of the paragraph read that names the word, if one does
fn flushParagraph(mut n SpecNotes, word str):
	para = move n.para
	at = callMention(para, word)
	if para == "" or at < 0: return
	note = sentenceAround(para, at)
	if note not in n.sentences:
		n.sentences.push(note)

# where `word` is first named as a call or a code span (`reduce(`, `.sum()`, `parallelMap`), or -1
fn callMention(t str, word str):
	at = findWord(t, word, 0)
	while at >= 0:
		end = at + word.len
		if end < t.len and (t[end] == '(' or t[end] == '`'): return at
		at = findWord(t, word, end)
	-1

# the sentence of a paragraph that holds byte `at` (from after the previous ". " to the next one)
fn sentenceAround(t str, at i64):
	start = 0
	i = 0
	while i + 1 < at:
		if sentenceEndsAt(t, i):
			start = i + 2
		i += 1
	end = t.len
	j = at
	while j + 1 < t.len:
		if sentenceEndsAt(t, j):
			end = j + 1
			break
		j += 1
	t[start..end].trimmed().copy()

# whether a file is part of the runtime (whose declarations the specification describes)
fn inRuntime(path str):
	p = path.replace("\\", "/")
	"/runtime/" in p

# zap fmt's layout of the document, as one edit over all of it (none when it is laid out)
fn formatting(text str, uri str):
	formatted = formatFile(text, isGpuFile(uri), [], isMarkupFile(uri))
	if formatted == text: return "[]"
	lines = text.lines().len
	"[\{\"range\":{rangeJson(0, 0, lines, 0)},\"newText\":{jsonQuote(formatted)}}]"

# ---------- diagnostics ----------

# `zap test --only check` on the saved file, its errors in this file sent to the editor
fn publishDiagnostics(root str, uri str):
	path = uriPath(uri)
	_ = fs.createDir("{root}/build")
	out = "{root}/build/lsp-check.txt"
	Process.run(
		shellLine("{quoteArg(exePath())} test --only check {quoteArg(path)} > {quoteArg(out)} 2>&1")
	)
	said = fs.readFile(out) ?? ""
	mine = path.replace("\\", "/").lower()
	items = []
	for line in said.lines():
		at = line.indexOf(": error") ?? -1
		if at < 0: continue
		after = line.indexOf(": ", at + 7) ?? -1
		if after < 0: continue
		place = line[..at].split(":")
		if place.len < 3: continue
		file = place[..len - 2].join(":").replace("\\", "/").lower()
		if not mine.endsWith(file) and not file.endsWith(mine): continue
		l = (i64.parse(place[len - 2]) ?? 1) - 1
		c = (i64.parse(place[len - 1]) ?? 1) - 1
		msg = line[after + 2..]
		items.push("\{\"range\":{rangeJson(l, c, l, c + 1)},\"severity\":1,\"source\":\"zap\",\"message\":{jsonQuote(msg)}}")
	list = items.join(",")
	lspNotify(
		"textDocument/publishDiagnostics",
		"\{\"uri\":{jsonQuote(uri)},\"diagnostics\":[{list}]}"
	)

# whether a file's text imports the module (`import m`)
fn imports(text str, module str):
	"import {module}" in text

# ---------- completion ----------

# What may follow `x.` at the request's position: the fields of x's type, then the functions
# taking it first that the file sees (its own, its module's, the modules it imports), of any
# type (`c u8` completes `c.isDigit`). x's type is read from the text above: a parameter or a
# binding written with it (`x Orbit`, `x = Orbit(...)`, `s = "..."`), or the type a method
# takes as self.
fn completion(docs {str: str}, root str, uri str, body str):
	pos = body.indexOf("\"position\"") ?? -1
	line = jsonIntField(body, "line", pos)
	col = jsonIntField(body, "character", pos)
	lines = textOf(docs, uri).replace("\r", "").lines()
	if line < 0 or line >= lines.len: return "[]"
	l = lines[line]
	a = col.min(l.len)
	while a > 0 and l[a - 1].isWordByte():
		a -= 1
	if a < 2 or l[a - 1] != '.': return "[]"
	b = a - 1
	while b > 0 and l[b - 1].isWordByte():
		b -= 1
	if b > 0 and l[b - 1] == '.': return "[]"   # a chain's step: its type is not read here
	t = typeOfName(lines, line, l[b..a - 1])
	if t == "": return "[]"
	fields = []
	functions = []
	named str[] = []
	for f in seenFiles(root, uriPath(uri), lines):
		text = textOf(docs, pathUri(f))
		for d in scanDecls(text):
			if (d.kind == symStruct or d.kind == symEnum) and d.name == t and fields.isEmpty:
				fields = fieldNames(text, d).map(completionItem(it, 5, ""))
			elif (d.kind == symMethod or d.kind == symFunction) and d.name not in named and
				firstParamType(d.detail) == t:
				named.push(d.name.copy())
				functions.push(completionItem(d.name, 2, d.detail))
	fields.extend(functions)
	"[{fields.join(",")}]"

# the files whose declarations a file sees: itself first, then its dir's (its module's) and
# those of the modules its lines import, from the project, the runtime and the standard library
fn seenFiles(root str, file str, lines str[]):
	key = file.replace("\\", "/").lower()
	dir = dirPrefix(key)
	imported = []
	for l in lines:
		t = l.trimmed()
		if t.startsWith("import "):
			imported.push("/{nameAt(t, 7).copy()}/")
		elif t.startsWith("from ") and t[5].isWordByte():
			imported.push("/{nameAt(t, 5).copy()}/")
	module = moduleOfPart(root, file)
	out = [file.copy()]
	for f in searchFiles(root):
		k = f.replace("\\", "/").lower()
		if k != key and (dirPrefix(k) == dir or imported.any(it in k) or "/runtime/" in k or
				k in module):
			out.push(f.copy())
	out

# the files of the module a file is in through `parts` (its own parts, or, a part, its owner's
# dir and parts), lowercase with '/'
fn moduleOfPart(root str, file str):
	path = file.replace("\\", "/")
	first = [path.copy()]
	if partOwner(path, root.replace("\\", "/")) is owner:
		d = dirPrefix(owner)
		first = moduleFiles("." if d == "" else d).map(d + it)
	withParts(first).map(.lower())

fn completionItem(label str, kind i64, detail str):
	"\{\"label\":{jsonQuote(label)},\"kind\":{kind},\"detail\":{jsonQuote(detail)}}"

# the fields a struct's declaration lists, in order
fn fieldNames(text str, d Decl):
	lines = text.replace("\r", "").lines()
	out = []
	for i in d.line + 1..(d.endLine + 1).min(lines.len):
		t = lines[i].trimmed()
		if leadingSpaces(lines[i]) == 0 and t != "": break
		if blockMethodLine(dropPrefix(t, "pub ")): break   # the methods after the fields
		if t == "" or t.startsWith("#") or not t[0].isWordByte() or t[0] >= 'A' and t[0] <= 'Z':
			continue
		out.push(nameAt(t, 0).copy())
	out

# The type of the name as the lines up to `line` give it: the nearest above that declares it (a
# parameter or binding with its type, `name = Type(...)`, `name = module.Type(...)`), or for
# `self` the type whose block holds the line. "" when none does.
fn typeOfName(lines str[], line i64, name str):
	i = line
	while i >= 0:
		l = lines[i]
		if name == "self":
			t = dropPrefix(l.trimmed(), "pub ")
			if leadingSpaces(l) == 0 and t.startsWith("type "): return nameAt(t, 5).copy()
			if leadingSpaces(l) == 0 and t != "" and not t.startsWith("#"): return ""
		else:
			for at in wordColumns(l, name):
				rest = l[at + name.len..]
				skip = 3 if rest.startsWith(" = ") else 1 if rest.startsWith(" ") else 0
				written = rest[skip..]
				t = typeNamedAtStart(written)
				if t != "": return t
		i -= 1
	""

# the name of the type a text starts with (`Orbit`, `engine.Orbit(`, `i64[]` gives List, `u8`,
# a string literal str), "" when it starts with none
fn typeNamedAtStart(text str):
	t = dropPrefix(text, "mut ")
	if t.startsWith("\""): return "str"
	word = nameAt(t, 0)
	if word.isEmpty: return ""
	if word[0] >= 'A' and word[0] <= 'Z' or primType(word) != none: return word.copy()
	if word.len < t.len and t[word.len] == '.':
		after = nameAt(t, word.len + 1)
		if not after.isEmpty and after[0] >= 'A' and after[0] <= 'Z': return after.copy()
	""
