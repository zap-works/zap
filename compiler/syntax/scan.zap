# The line scanner: what the text of a source line is, for the tools that read a file as lines
# and keep its layout (zap fmt and its rewrites, the notes of canon.zap, the language server).
# The lexer cannot serve them: it stops at the first error, drops comments and reads the source
# of a refuses or stops test as one token, while they read half-written files and lay out every
# line. Its rules are the lexer's: a string's interpolation is code (a string inside it is text
# again), a character literal is code, `#` outside strings starts a comment, `"""` opens a string
# that goes on below, and the source of a refuses or stops test is the lines indented after its `:`.

# ---------- the bytes of one line ----------

byteCode = 0   # code
byteText = 1   # a literal's: a character's, or a string's quotes, text, escapes and interpolation braces
byteInner = 2   # code in a string's interpolation
byteComment = 3   # a # comment, to the end of the line
byteLong = 4   # a """ string's opening quotes and the rest of the line (its text goes on below)

# what each byte of the line is (one of the byte kinds)
pub fn byteKinds(s str) u8[]:
	kinds = []
	k = 0
	while k < s.len:
		b = s[k]
		if b == '#':
			markTo(kinds, s.len, byteComment)
			break
		if isTripleQuote(s, k):
			markTo(kinds, s.len, byteLong)
			break
		if b == '"':
			k = markString(s, k, kinds)
			if k < 0: break
			continue
		if b == '\'':
			end = charEnd(s, k)
			k = s.len if end < 0 else end
			markTo(kinds, k, byteText)
			continue
		kinds.push(byteCode)
		k += 1
	kinds

# kinds filled with kind up to `to` bytes
fn markTo(mut kinds u8[], to i64, kind u8):
	while kinds.len < to:
		kinds.push(kind)

fn isTripleQuote(s str, k i64):
	k + 2 < s.len and s[k] == '"' and s[k + 1] == '"' and s[k + 2] == '"'

# The string literal at k (its opening quote) marked: the index after it, or -1 when it does not
# close on the line (the rest of the line marked as its)
fn markString(s str, k i64, mut kinds u8[]) i64:
	kinds.push(byteText)
	raw = k > 0 and s[k - 1] == 'r' and (k == 1 or not s[k - 2].isWordByte())   # r"...": no escape, no interpolation
	j = k + 1
	while j < s.len:
		c = s[j]
		if raw:
			kinds.push(byteText)
			j += 1
			if c == '"': return j
			continue
		if c == '\\':
			j = (j + 2).min(s.len)
			markTo(kinds, j, byteText)
			continue
		kinds.push(byteText)
		j += 1
		if c == '"': return j
		if c == '{':
			j = markInterpolation(s, j, kinds)
			if j < 0: return -1
	-1

# The code of an interpolation from k up to the brace that closes it marked: the index after
# that brace, or -1 when it does not close on the line
fn markInterpolation(s str, k i64, mut kinds u8[]) i64:
	depth = 0   # the braces its own code opened
	j = k
	while j < s.len:
		c = s[j]
		if c == '"':
			j = markString(s, j, kinds)
			if j < 0: return -1
			continue
		if c == '\'':
			end = charEnd(s, j)
			j = s.len if end < 0 else end
			markTo(kinds, j, byteText)
			continue
		if c == '}' and depth == 0:
			kinds.push(byteText)
			return j + 1
		if c == '{':
			depth += 1
		elif c == '}':
			depth -= 1
		kinds.push(byteInner)
		j += 1
	-1

# the index after the character literal at k, or -1 when it does not close on the line
fn charEnd(s str, k i64):
	j = k + 1
	while j < s.len and s[j] != '\'':
		j += 2 if s[j] == '\\' else 1
	j + 1 if j < s.len else -1

# the index after the string literal that starts at i (its interpolations skipped), or -1
fn stringEnd(s str, i i64) i64:
	skipped = []
	markString(s, i, skipped)

# the index after the literal at k, a string's or a character's, or -1 when it does not close
# on the line
fn literalEnd(s str, k i64):
	stringEnd(s, k) if s[k] == '"' else charEnd(s, k)

# where the line's comment starts, or its length
fn commentStart(s str):
	kinds = byteKinds(s)
	kinds.indexOf(byteComment) ?? s.len

# the line without its trailing comment
fn codeOf(t str) ref str:
	at = commentStart(t)
	t[..at].trimmedEnd() if at < t.len else t

# Where byte pos of the line lies: 0 code, 1 a literal's text or a comment, 2 code that an
# interpolation's `{` opens right before it
fn textPlace(s str, pos i64):
	kinds = byteKinds(s)
	if pos >= kinds.len: return 0
	kind = kinds[pos]
	if kind == byteInner and pos > 0 and kinds[pos - 1] == byteText and s[pos - 1] == '{': return 2
	0 if kind == byteCode or kind == byteInner else 1

# The brackets of a line's code (outside strings, characters and comments): an opener is pushed
# with the line's indentation (two on one line give one level inside), a closer pops it and the
# blocks opened inside it. True when the line opens a """ string that goes on below it.
fn scanLine(t str, indent i64, chain i64, mut open Opener[]):
	kinds = byteKinds(t)
	for k, kind in kinds:
		if kind == byteCode:
			b = t[k]
			if b in ['{', '(', '[']:
				open.push(Opener(ch = b, base = indent, chain))
			elif b in ['}', ')', ']']:
				while not open.isEmpty and open[len - 1].ch == ':':
					open.pop()
				if not open.isEmpty:
					open.pop()
	not kinds.isEmpty and kinds[len - 1] == byteLong

# the brackets a line of code opens less those it closes (strings, characters and comments
# skipped)
fn bracketDelta(t str):
	kinds = byteKinds(t)
	n = 0
	for k, kind in kinds:
		if kind == byteCode:
			b = t[k]
			if b in ['{', '(', '[']:
				n += 1
			elif b in ['}', ')', ']']:
				n -= 1
	n

# the line's indentation in levels: a tab each, or four spaces (what fmt writes as a tab)
fn indentOf(raw str):
	width = 0
	n = 0
	while n < raw.len and (raw[n] == ' ' or raw[n] == 9):
		width += 4 if raw[n] == 9 else 1
		n += 1
	width / 4

# ---------- walking code from a place in it ----------

# the index after the block (or bracket) that opens at i, or -1
fn closingOf(s str, i i64):
	depth = 0
	j = i
	while j < s.len:
		c = s[j]
		if c == '"' or c == '\'':
			j = literalEnd(s, j)
			if j < 0: return -1
			continue
		if c in ['(', '[', '{']:
			depth += 1
		elif c in [')', ']', '}']:
			depth -= 1
			if depth == 0: return j + 1
		j += 1
	-1

# where `word` starts at or after `start`, not inside a longer name (a name's byte neither right
# before it nor, when it ends with one, right after it)
fn findWord(s str, word str, start i64):
	at = start
	while at < s.len:
		k = s.indexOf(word, at) ?? -1
		if k < 0: return -1
		end = k + word.len
		before = k == 0 or not s[k - 1].isWordByte()
		after = end >= s.len or not word[len - 1].isWordByte() or not s[end].isWordByte()
		if before and after: return k
		at = k + 1
	-1

# whether the code ends with a binary operator (written with a space before it), `=`, `..`,
# `=>` or a dot: the expression goes on on the next line
fn endsWithOperator(code str):
	if code.endsWith(".") and not code.endsWith(".."): return true
	["=", "..", "=>"].any(code.endsWith(" {it}")) or
		binaryOperators.any(code.endsWith(" {.text}"))

# whether the code ends with the `:` that opens a block (a ternary's is written between spaces)
fn opensBlock(code str):
	code.endsWith(":") and not code.endsWith(" :")

# whether a sentence of prose ends at byte i: a period before a space or the end, not one of
# the dots of `..`
fn sentenceEndsAt(t str, i i64):
	t[i] == '.' and (i + 1 == t.len or t[i + 1] == ' ') and (i == 0 or t[i - 1] != '.')

# ---------- the lines of a file ----------

lineCode = 0   # code (a line of a comment of its own too)
lineText = 1   # the text of a """ string (the line of its closing quotes included)
lineRaw = 2   # the source of a refuses or stops test
lineMarkup = 3   # a line of a .zapx file that starts inside markup (scanMarkup.zap)

# a bracket open at some point of a line, and the indentation of the line that opened it; or,
# with ch ':', a block opened inside a bracket (a lambda's body), ended by a line indented no
# more than its opener
type Opener:
	ch u8
	base i64
	chain i64   # the chain base (LineScanner) of the line that opened it

# what the lines read so far leave open
type LineScanner:
	open Opener[] = []
	inText bool = false   # a """ string
	textBase i64 = 0   # the indentation of the line that opened it
	raw bool = false   # inside a refuses or stops test's source
	rawIndent i64 = 0   # the indentation of the test's line: the source is indented more
	rawOpen i64 = 0   # the openers outside it
	# the expression goes on: the last line ends with an operator, or this one starts with `.`
	continues bool = false
	stmtIndent i64 = 0   # the indentation of the last statement's first line
	# the indentation a chain's steps (lines starting with `.`) stand one past: the last line's that
	# is neither a step nor led by a closing bracket, or the one such a bracket's line matches
	chainBase i64 = 0
	markup bool = false   # a .zapx file: its markup is read (scanMarkup.zap)
	marks MarkOpen[] = []   # the parts of markup open
	markBase i64 = 0   # the indentation of the line that opened the markup open
	line MarkLine = MarkLine()   # the last line entered, to markup

# The kind of the next line (raw: as written). A line of code or source goes on to leaveLine
# once its caller has read it; a string's closing line has its brackets after the quotes read here.
fn enterLine(mut sc LineScanner, raw str):
	sc.line = MarkLine()
	tabs = indentOf(raw)
	blank = raw.trimmed() == ""
	if sc.raw:
		if blank or tabs > sc.rawIndent: return lineRaw
		sc.raw = false
		sc.open.truncate(sc.rawOpen)   # what the source left open ends with it
		sc.continues = false
		sc.inText = false
	if sc.inText:
		at = raw.indexOf("\"\"\"") ?? -1
		if at >= 0:
			sc.inText = false
			scanLine(raw[at + 3..], sc.textBase, sc.chainBase, sc.open)
		return lineText
	if sc.markup:
		sc.enterMarkupLine(raw.trimmed(), tabs)
		if sc.line.inside: return lineMarkup
	if not blank:
		# a block opened inside a bracket ends where a line is indented no more than its opener
		while not sc.open.isEmpty and sc.open[len - 1].ch == ':' and
			tabs <= sc.open[len - 1].base:
			sc.open.pop()
		if isChainStep(raw.trimmed()): sc.continues = true
	lineCode

# whether a line is a step of a chain of calls going on from the line above (`.filter(...)`)
fn isChainStep(t str):
	t.len > 1 and t[0] == '.' and (t[1].isWordByte() and not (t[1] >= 'A' and t[1] <= 'Z'))   # not a variant (.Quit), not a range (..)

# how many closing brackets the line starts with (}) closes two)
fn leadingClosers(t str):
	n = 0
	while n < t.len and (t[n] == '}' or t[n] == ')' or t[n] == ']'):
		n += 1
	n

# the index in sc.open of the bracket the n-th leading closer of a line matches (blocks opened
# inside brackets skipped), or none when n is 0 or the line closes more than is open
fn closedOpener(sc LineScanner, n i64) i64?:
	left = n
	k = sc.open.len - 1
	while k >= 0:
		if sc.open[k].ch != ':':
			left -= 1
			if left == 0: return k
		k -= 1
	none

# whether the next line of code is free: its indentation is what it means (a statement's own
# line), not computed from the brackets open around it
fn freeLine(sc LineScanner):
	sc.open.isEmpty or sc.open[len - 1].ch == ':'

# whether the line entered holds markup: its text stays as written
fn keepsText(sc LineScanner):
	sc.markup and sc.line.touched

# after a line of code or source (t: its text trimmed, not empty, laid out at indentation base):
# the string or test source it opens, its brackets, the block it opens inside a bracket, and
# whether its expression goes on; a line holding markup by its code only, the markup's own
# indentation taken from the line that opens it
fn leaveLine(mut sc LineScanner, t str, base i64):
	if not sc.keepsText(): return sc.leaveCode(t, base)
	if sc.line.opens:
		sc.markBase = base
	code = sc.line.code.copy()
	if not sc.line.inside: return sc.leaveCode(code, base)
	sc.inText = scanLine(code, base, sc.chainBase, sc.open)
	if sc.inText:
		sc.textBase = base
	sc.continues = not sc.inText and endsWithOperator(codeOf(code))

fn leaveCode(mut sc LineScanner, t str, base i64):
	if not sc.continues and sc.freeLine():
		sc.stmtIndent = base
	if not sc.raw and opensTestSource(t):
		sc.raw = true
		sc.rawIndent = base
		sc.rawOpen = sc.open.len
		return
	if not isChainStep(t):
		sc.chainBase = base
		if sc.closedOpener(leadingClosers(t)) is k: sc.chainBase = sc.open[k].chain
	sc.inText = scanLine(t, base, sc.chainBase, sc.open)
	if sc.inText:
		sc.textBase = base
	code = codeOf(t)
	sc.continues = not sc.inText and endsWithOperator(code)
	if not sc.inText and not sc.open.isEmpty and opensBlock(code):
		sc.open.push(Opener(ch = ':', base, chain = sc.chainBase))

# whether a line opens the source of a test that refuses or stops: a word of sourceTestWords
# after the test's name, or a case of a test's body (a word of caseWords and an error's name)
fn opensTestSource(t str):
	if caseWords.any(t.startsWith("{it} ") and t.len > .len + 1 and t[.len + 1].isUpper()):
		return opensBlock(codeOf(t))
	if not t.startsWith("{testWord} \""): return false
	k = testWord.len + 2
	while k < t.len and t[k] != '"':
		k += 2 if t[k] == '\\' else 1
	rest = t[(k + 2).min(len)..]
	sourceTestWords.any(rest.startsWith("{it} ")) and opensBlock(codeOf(t))

# what a line of a file is: its kind, whether it starts a statement (code in a block on a line of
# its own, not going on from the line before nor inside a bracket), and the brackets open after it
type LineScan:
	kind i64
	stmt bool
	depth i64

# whether a top-level line is a statement of the program (a binding among them): not a declaration
fn topStatement(raw str):
	code = codeOf(raw.trimmed())
	if code == "" or code.startsWith("#"): return false
	for word in [
		"fn ",
		"pub ",
		"type ",
		"import ",
		"parts ",
		"{fromWord} ",
		"extern ",
		"shared ",
		"bound ",
		"alias ",
		"use ",
		"{testWord} \""
	]:
		if code.startsWith(word): return false
	true

# whether a top-level line of code binds a name: `name = v`, `name T = v` (T a list, tuple or map
# type too), `mut name ...`
fn bindingLine(code str):
	i = 4 if code.startsWith("mut ") else 0
	start = i
	while i < code.len and code[i].isWordByte():
		i += 1
	if i == start: return false
	rest = code[i..]
	if rest.startsWith(" = "): return true
	rest.len > 1 and rest[0] == ' ' and
		(rest[1].isWordByte() or rest[1] == '[' or rest[1] == '(' or rest[1] == '{') and
		" = " in rest

# whether a file's top level holds a statement: a program of its own, main made of them
fn hasTopStatement(text str):
	lines = text.lines()
	scans = scanLines(lines)
	for i, raw in lines:
		if scans[i].kind == lineCode and indentOf(raw) == 0 and raw.trimmed() != "" and
			topStatement(raw) and not bindingLine(codeOf(raw.trimmed())) and scans[i].stmt:
			return true
	false

# the lines of a file scanned as zap fmt reads them (a .zapx file's with markup: a line holding
# markup is lineMarkup)
fn scanLines(lines str[], markup bool = false):
	sc = LineScanner(markup)
	out = []
	for raw in lines:
		kind = sc.enterLine(raw)
		if sc.keepsText(): kind = lineMarkup
		stmt = kind == lineCode and sc.freeLine() and not sc.continues and
			(indentOf(raw) > 0 or topStatement(raw))
		t = raw.trimmed()
		if kind in [lineCode, lineRaw, lineMarkup] and t != "":
			sc.leaveLine(t, indentOf(raw))
		out.push(LineScan(kind, stmt, depth = sc.open.len))
	out
