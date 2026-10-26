# The editor's colours in a file the server reads, over the grammar's (tools/vscode-zap, which a
# diff keeps): `zap lsp`'s semantic tokens, read from the text as the language's own tables say
# it (the keywords, the contextual words, the options and the built-in types), so the editor
# follows the language as it changes. Code inside a string's interpolations is read too.

# the token types and modifiers, in the legend's order (capabilities)
tokenTypes = [
	"keyword",
	"type",
	"function",
	"method",
	"property",
	"namespace",
	"enumMember",
	"number"
]
tokenModifiers = ["declaration", "defaultLibrary"]

tokKeyword = 0
tokType = 1
tokFunction = 2
tokMethod = 3
tokProperty = 4
tokNamespace = 5
tokEnumMember = 6
tokNumber = 7
modDeclaration = 1
modDefaultLibrary = 2

# the legend the server announces
fn semanticLegend():
	types = tokenTypes.map(jsonQuote(it)).join(",")
	mods = tokenModifiers.map(jsonQuote(it)).join(",")
	"\{\"tokenTypes\":[{types}],\"tokenModifiers\":[{mods}]}"

# a word of code and what is around it on its line
type WordAt:
	text str
	first bool   # the line's first word of code
	before str   # the code before it on its line, trimmed
	next u8   # the first byte after it that is not a space (0 at the line's end)
	nextWord str   # the word that follows it, "" when a word does not

# the semantic tokens of a text, as the protocol encodes them: five numbers a token (the lines
# and the columns from the one before, its length, its type, its modifiers). Its lines are read as
# zap fmt reads them (scan.zap): code, and the code of a string's interpolations, has words; a
# .zapx file's lines holding markup are left to the grammar.
fn semanticTokens(text str, markup bool):
	lines = text.replace("\r", "").lines()
	scans = scanLines(lines, markup)
	data = []
	lastLine = 0
	lastCol = 0
	for li, line in lines:
		if scans[li].kind == lineMarkup: continue
		start = 0
		if scans[li].kind == lineText:
			# inside a """ string: code only after its closing quotes
			start = (line.indexOf("\"\"\"") ?? line.len - 3) + 3
		kinds = byteKinds(line[start..])
		first = true
		prevWord = ""
		useLine = false
		i = start
		while i < line.len:
			kind = kinds[i - start]
			c = line[i]
			if kind != byteCode and kind != byteInner or not c.isWordByte():
				if kind != byteCode or c != ' ' and c != '\t':
					first = false
				i += 1
				continue
			end = wordEnd(line, i)
			if c.isDigit():
				i = end
				first = false
				continue
			w = WordAt(
				text = line[i..end].copy(),
				first,
				before = line[..i].trimmed().copy(),
				next = nextByte(line, end),
				nextWord = nextWordOf(line, end)
			)
			if first:
				useLine = w.text == useWord
			token, mods = w.wordToken(prevWord, useLine)
			if token >= 0:
				col = utf16Column(line, i)
				data.extend(
					[
						li - lastLine,
						col - lastCol if li == lastLine else col,
						end - i,
						token,
						mods
					]
				)
				lastLine = li
				lastCol = col
			prevWord = w.text.copy()
			first = false
			i = end
	"\{\"data\":[{data.map(str(it)).join(",")}]}"

fn wordEnd(line str, i i64):
	j = i
	while j < line.len and line[j].isWordByte():
		j += 1
	j

fn nextByte(line str, from i64):
	j = from
	while j < line.len and (line[j] == ' ' or line[j] == '\t'):
		j += 1
	line[j] if j < line.len else 0

fn nextWordOf(line str, from i64):
	j = from
	while j < line.len and (line[j] == ' ' or line[j] == '\t' or line[j] == ','):
		j += 1
	line[j..wordEnd(line, j)].copy()

# the column of byte i of the line in UTF-16 units, as the protocol counts
fn utf16Column(line str, i i64):
	col = 0
	for k in 0..i:
		b = line[k]
		if b < 0x80 or b >= 0xC0:
			col += 1
		if b >= 0xF0:
			col += 1   # a character past the first plane is two units
	col

# a word's token type and modifiers, (-1, 0) for a word the editor leaves as it is (a variable)
fn wordToken(w WordAt, prevWord str, useLine bool):
	t = w.text
	if t in keywords: return (tokKeyword, 0)
	if t in circleWords and w.next != '=': return (tokNumber, 0)
	if w.contextualKeyword(prevWord): return (tokKeyword, 0)
	if useLine and t in options: return (tokEnumMember, 0)
	if prevWord == "fn" and (w.next == '(' or w.next == '<'): return (tokFunction, modDeclaration)
	if prevWord == "type" or prevWord == boundWord: return (tokType, modDeclaration)
	if w.before == "import" or w.before.startsWith("import ") or
		prevWord == fromWord and w.first == false:
		return (tokNamespace, 0)
	dotted = w.before.endsWith(".") and not w.before.endsWith("..")
	if t[0].isUpper(): return (tokEnumMember if dotted else tokType, 0)
	if primTypes.any(.name == t): return (tokType, modDefaultLibrary)
	if w.next == '(': return (tokMethod if dotted else tokFunction, 0)
	if dotted: return (tokProperty, 0)
	(-1, 0)

# whether a contextual word stands where it is a word of the language, not a name
fn contextualKeyword(w WordAt, prevWord str):
	t = w.text
	statement = w.first and w.next != '=' and w.next != '.' and w.next != '(' and w.next != 0
	if t == testWord: return w.first and w.next == '"'
	if t == expectWord or t == printsWord: return statement
	if t in sourceTestWords:
		return (w.before.endsWith("\"") or w.first and t in caseWords) and w.next.isUpper()
	if t == passWord: return (w.first or w.before.endsWith(":")) and w.next == 0
	if t == useWord: return w.first and w.nextWord in options
	if t == arenaWord: return w.first and w.next == ':'
	if t == fromWord: return w.first and w.next.isWordByte()
	if t == boundWord: return (w.first or prevWord == "pub") and w.next.isUpper()
	if t == loadedWord: return prevWord == "extern"
	if t == stepWord: return ".." in w.before and w.next != '=' and w.next != 0
	false
