# Tokenizer: bytes of the source to tokens, newline tokens as statement separators, indent and
# dedent tokens where a block (the lines indented after one ending in `:`) opens and ends,
# string interpolation split into begin/mid/end parts.

type Lexer:
	src str
	file str
	pos i64
	line i64
	col i64
	toks Tok[]
	lastKind i64
	interp i64[]   # brace depth at each open interpolation
	interpNest i64[]   # per open interpolation, the brackets open where it opened (a format's colon is at that depth)
	indents i64[]   # per open interpolation, its string's dedent (-1: a one-line string)
	braceDepth i64
	nest i64   # the brackets open: inside them a newline separates, the indentation is free
	levels i64[]   # the indentation (tabs) of each open block, the file's own first
	blockNest i64[]   # per open block, the brackets open where it opened
	tight bool   # the last operator was written right after what precedes it (`u8[]`, not `a > b`)
	internal bool   # source the compiler wrote: names may hold `$` (no program can name them)
	markup bool = false   # a .zapx file: a `<` that opens an expression starts markup (lexMarkup.zap)
	marks MarkFrame[] = []   # the markup open, the innermost last
	stopped bool = false   # an error was said: the source is not lexed further

# the error at the current place said, and the lexing stopped there
fn lexError(mut lx Lexer, msg str):
	lx.lexErrorAt(lx.line, lx.col, msg)

# The error said, once, and the lexing stopped: the rest of the source skipped, so that every
# loop reading it ends (the source's end reads as 0) and lexWith gives none.
fn lexErrorAt(mut lx Lexer, line i64, col i64, msg str):
	if lx.stopped: return
	errorAtFile(lx.file, line, col, msg)
	lx.stopped = true
	lx.pos = lx.src.len
	lx.marks.clear()

fn peekc(lx Lexer) u8:
	if lx.pos >= lx.src.len: return 0
	lx.src[lx.pos]

fn peek2(lx Lexer) u8:
	if lx.pos + 1 >= lx.src.len: return 0
	lx.src[lx.pos + 1]

# whether the source here starts the word followed by a blank
fn wordAhead(lx Lexer, word str):
	if lx.pos + word.len >= lx.src.len or lx.src[lx.pos + word.len] != ' ': return false
	for k in 0..word.len:
		if lx.src[lx.pos + k] != word[k]: return false
	true

fn lxAdv(mut lx Lexer) i64:
	c = lx.peekc()
	if c == 0: return 0
	lx.pos += 1
	if c == 10:
		lx.line += 1
		lx.col = 1
	else:
		lx.col += 1
	c

fn addTok(mut lx Lexer, kind i64, move text str, line i64, col i64):
	lx.toks.push((kind, text, line, col))
	lx.lastKind = kind
	if kind in [tkLparen, tkLbracket, tkLbrace]:
		lx.nest += 1
	elif kind in [tkRparen, tkRbracket, tkRbrace]:
		lx.nest -= 1

# tokens after which a newline does not end the statement
fn suppressNewlineAfter(k i64):
	k in [tkPlus, tkMinus, tkStar, tkSlash, tkPercent, tkStarstar, tkAt, tkEq] or
		k == tkEqeq or k == tkBangeq or k == tkLt or k == tkGt or k == tkLe or k == tkGe or
		k == tkQq or k == tkQdot or k == tkPipe or k == tkComma or k == tkDot or
		k == tkAnd or k == tkOr or k == tkNot or
		k == tkLparen or k == tkLbracket or k == tkLbrace or k == tkOpAssign

# the operator of a compound assignment when the token just lexed is one and ends right before
# the '=' being read (x += y), else ""
fn compoundOp(lx Lexer):
	if lx.toks.isEmpty or lx.pos == 0 or lx.src[lx.pos - 1] == 32 or lx.src[lx.pos - 1] == 9:
		return ""
	k = lx.toks[len - 1].kind
	if binaryOperators.find(.compound and .token == k) is o: return o.text.copy()
	""

fn skipInlineTrivia(mut lx Lexer):
	going = true
	while going:
		c = lx.peekc()
		if c in [32, 9, 13]:
			lx.lxAdv()
		elif c == '#':
			while lx.peekc() != 0 and lx.peekc() != 10:
				lx.lxAdv()
		else:
			going = false

# the tokens of the language's words (syntax.zap's keywords, in their order)
keywordTokens = [
	tkFn,
	tkType,
	tkMut,
	tkMove,
	tkReturn,
	tkIf,
	tkElse,
	tkMatch,
	tkImport,
	tkPub,
	tkTrue,
	tkFalse,
	tkNone,
	tkShared,
	tkThis, tkWhile, tkFor, tkIn, tkBreak, tkContinue, tkRef, tkIs, tkLoop, tkExtern, tkElif, tkAnd, tkOr, tkNot, tkTry, tkIt, tkYield]

# the operators and punctuation other than the binary operators (binaryOperators), and their tokens
punctuation = [
	TokenText("..=", tkDotdotEq),
	TokenText("..", tkDotdot),
	TokenText("?.", tkQdot),
	TokenText("(", tkLparen),
	TokenText(")", tkRparen),
	TokenText("[", tkLbracket),
	TokenText("]", tkRbracket),
	TokenText(",", tkComma), TokenText(":", tkColon), TokenText(".", tkDot), TokenText("=", tkEq), TokenText("~", tkTilde), TokenText(
		"?",
		tkQuestion
)]

# the keywords' tokens by their text, made once at the start (a constant map would be made again
# at each use)
mut keywordsByText = keywordMap()

fn keywordMap():
	by {str: i64} = {}
	for i, k in keywords:
		by[k.copy()] = keywordTokens[i]
	by

fn keywordKind(text str):
	if text.len < 2 or text.len > 8 or text[0] < 'a' or text[0] > 'z':
		return -1   # every keyword: 2 to 8 lowercase letters
	keywordsByText.get(text) ?? -1

# the operator that starts here, by the tables, the longer first; false when none does
fn lexOperator(mut lx Lexer):
	if lx.pos >= lx.src.len: return false
	for o in operatorsByByte[lx.src[lx.pos]]:
		n = o.text.len
		if lx.pos + n <= lx.src.len and lx.src[lx.pos..lx.pos + n] == o.text:
			lx.opN(o.token, n)
			return true
	false

# the operators and the punctuation by their first byte, the longest first (an operator before
# punctuation written the same): what lexOperator tries
operatorsByByte = operatorsByFirstByte()

fn operatorsByFirstByte():
	all = binaryOperators.map(TokenText(.text.copy(), .token))
	all.extend(punctuation.map(TokenText(.text.copy(), .token)))
	by TokenText[,] = []
	loop 256:
		by.push([])
	for n in [3, 2, 1]:
		for o in all:
			if o.text.len == n:
				by[o.text[0]].push(o.copy())
	by

fn lexIdent(mut lx Lexer):
	line = lx.line
	col = lx.col
	start = lx.pos
	while lx.peekc().isWordByte() or (lx.internal and lx.peekc() == 36):
		lx.lxAdv()
	# the token owns its text: the source is the lexer's and goes away with it
	text = lx.src[start..lx.pos].copy()
	# module__name is a global name: written in the source it would skip the module's privacy
	if not lx.internal and (text.indexOf("__") ?? 0) > 0:
		lx.lexErrorAt(line, col, compileError("DoubleUnderscore", ["{text}"]))
		return
	kw = keywordKind(text)
	if kw >= 0:
		lx.addTok(kw, text, line, col)
		return
	if text[0].isUpper() or (text[0] == 36 and text.len > 1 and text[1].isUpper()):
		lx.addTok(tkUident, text, line, col)
	else:
		lx.addTok(tkIdent, text, line, col)

# the value of the digit c in the base (16 or 2), or -1
fn digitValue(c i64, base i64):
	if base == 2: return c - 48 if c == 48 or c == 49 else -1
	u8(c).hexValue()

fn lexNumber(mut lx Lexer):
	line = lx.line
	col = lx.col
	start = lx.pos
	isFloat = false
	if lx.peekc() == 48 and
		(lx.peek2() == 120 or lx.peek2() == 88 or lx.peek2() == 98 or lx.peek2() == 66):
		# hexadecimal (0x) or binary (0b) literal, `_` allowed between digits: the token carries the
		# decimal digits so the rest of the compiler sees one form
		base = 16 if lx.peek2() == 120 or lx.peek2() == 88 else 2
		lx.lxAdv()
		lx.lxAdv()
		v = 0
		bits = 0
		digits = 0
		afterDigit = false
		while digitValue(lx.peekc(), base) >= 0 or
			lx.peekc() == 95 and afterDigit and digitValue(lx.peek2(), base) >= 0:
			if lx.peekc() != 95:
				bits += 4 if base == 16 else 1
				if bits > 64:
					lx.lexError(
						compileError(
							"LiteralTooLarge",
							["{"hexadecimal" if base == 16 else "binary"}"]
						)
					)
				v = v * u64(base) + u64(digitValue(lx.peekc(), base))
				digits += 1
			afterDigit = lx.peekc() != 95
			lx.lxAdv()
		if digits == 0 or lx.peekc().isWordByte():
			lx.lexError(
				compileError("InvalidLiteral", ["{"hexadecimal" if base == 16 else "binary"}"])
			)
		lx.addTok(tkInt, "{v}", line, col)
		return
	while lx.peekc().isDigit() or lx.peekc() == 95 and lx.peek2().isDigit() and lx.pos > start:
		lx.lxAdv()   # digits, `_` between them
	if lx.peekc() == 46 and lx.peek2().isDigit():
		isFloat = true
		lx.lxAdv()
		while lx.peekc().isDigit():
			lx.lxAdv()
	if lx.peekc() == 101 or lx.peekc() == 69:
		isFloat = true
		lx.lxAdv()
		if lx.peekc() == 43 or lx.peekc() == 45:
			lx.lxAdv()
		while lx.peekc().isDigit():
			lx.lxAdv()
	if lx.peekc().isWordByte():
		lx.lexError(compileError("InvalidNumber", []))
	text = lx.src[start..lx.pos].replace("_", "")
	if isFloat:
		lx.addTok(tkFloat, text, line, col)
	else:
		lx.addTok(tkInt, text, line, col)

# Reads literal text until a closing quote (returns 1) or an opening brace (returns 2); the
# decoded bytes accumulate in the lexer's scratch list.
# the characters of a string up to its end (1) or to an interpolation's `{` (2); indent >= 0
# for a multi-line string: a newline is kept, the next line's first `indent` spaces are not,
# and the newline before the closing quotes ends it
# (raw: `r"..."`, no escape and no interpolation, `{` and `\` themselves)
fn scanLiteral(mut lx Lexer, mut out u8[], indent i64, raw bool = false):
	loop:
		c = lx.peekc()
		if c == 13 and lx.peek2() == 10 and indent >= 0:
			lx.lxAdv()   # a CRLF line end is one newline
			continue
		if c == 10 and indent >= 0:
			lx.lxAdv()
			lead = []   # the line's indentation: spaces or tabs
			while lx.peekc() == ' ' or lx.peekc() == 9:
				lead.push(lx.peekc())
				lx.lxAdv()
			if lx.peekc() == '"' and lx.peek2() == '"' and lx.peekAt(2) == '"':
				lx.lxAdv()
				lx.lxAdv()
				lx.lxAdv()
				return 1   # the closing quotes, on their own line
			out.push(10)
			for k in indent..lead.len:
				out.push(lead[k])   # indentation past the closing quotes' is kept
			continue
		if c == 0 or c == 10:
			lx.lexError(compileError("UnterminatedString", []))
			return 1
		if c == 34 and indent < 0:
			lx.lxAdv()
			return 1
		if c == 123 and not raw:
			lx.lxAdv()
			return 2
		if c == 92 and not raw:
			lx.lxAdv()
			e = lx.lxAdv()
			if e == 110:
				out.push(10)
			elif e == 116:
				out.push(9)
			elif e == 114:
				out.push(13)
			elif e == 92:
				out.push(92)
			elif e == 34:
				out.push(34)
			elif e == 123:
				out.push(123)
			elif e == 125:
				out.push(125)
			elif e == 48:
				out.push(0)
			else:
				lx.lexError(compileError("InvalidEscape", ["{str.fromCode(i32(e))}"]))
		else:
			out.push(u8(lx.lxAdv()))
	0

fn openInterp(mut lx Lexer, indent i64):
	if lx.interp.len >= 64:
		lx.lexError(compileError("InterpolationTooDeep", []))
	lx.interp.push(lx.braceDepth)
	lx.interpNest.push(lx.nest)
	lx.indents.push(indent)

# a piece of a string literal up to its closing quote (a token of kind closed) or up to an
# interpolation (a token of kind open, and the interpolation is entered)
fn lexStringPart(
	mut lx Lexer,
	line i64,
	col i64,
	indent i64,
	closed i64,
	open i64,
	raw bool = false
):
	out = []
	stop = lx.scanLiteral(out, indent, raw)
	text = str(move out)
	if stop == 1:
		lx.addTok(closed, text, line, col)
	else:
		lx.addTok(open, text, line, col)
		lx.openInterp(indent)

# `"""` then a newline: a string of the following lines up to the line holding the closing
# `"""`, whose indentation is taken off every line (Swift's and Kotlin's raw blocks)
fn lexMultiline(mut lx Lexer, line i64, col i64, raw bool = false):
	loop 3:
		lx.lxAdv()
	if lx.peekc() == 13:
		lx.lxAdv()
	if lx.peekc() != 10:
		lx.lexError(compileError("MultilineStringStart", []))
	lx.lxAdv()
	indent = lx.closingIndent()
	loop indent:
		if lx.peekc() == ' ' or lx.peekc() == 9:
			lx.lxAdv()
	if lx.peekc() == '"' and lx.peek2() == '"' and lx.peekAt(2) == '"':
		loop 3:
			lx.lxAdv()
		lx.addTok(tkStr, "", line, col)   # no lines: the empty string
		return
	lx.lexStringPart(line, col, indent, tkStr, tkStrBegin, raw)

# the indentation of the line holding the closing `"""` of the string starting here
fn closingIndent(mut lx Lexer):
	p = lx.pos
	while p < lx.src.len:
		q = p
		while q < lx.src.len and (lx.src[q] == ' ' or lx.src[q] == 9):
			q += 1
		if q + 2 < lx.src.len and lx.src[q] == '"' and lx.src[q + 1] == '"' and
			lx.src[q + 2] == '"':
			return q - p
		nl = lx.src.indexOf('\n', p) ?? -1
		if nl < 0: break
		p = nl + 1
	lx.lexError(compileError("UnterminatedMultilineString", []))
	0

fn peekAt(lx Lexer, k i64) i64:
	if lx.pos + k >= lx.src.len: return 0
	lx.src[lx.pos + k]

# the operator token k of n bytes starting here
fn opN(mut lx Lexer, k i64, n i64):
	line = lx.line
	col = lx.col
	lx.tight = lx.pos > 0 and not isBlank(lx.src[lx.pos - 1])
	loop n:
		lx.lxAdv()
	lx.addTok(k, "", line, col)

# 'a' or an escape ('\n', '\t', '\r', '\0', '\\', '\'', '\"', '\x41'): one ASCII byte
fn lexByte(mut lx Lexer):
	line = lx.line
	col = lx.col
	lx.lxAdv()
	v = i64(lx.peekc())
	if v == 92:
		lx.lxAdv()
		e = lx.peekc()
		escapes = [110, 116, 114, 48, 92, 39, 34]
		values = [10, 9, 13, 0, 92, 39, 34]
		if e in escapes:
			v = values[escapes.indexOf(e) ?? -1]
		elif e == 120:
			lx.lxAdv()
			h = lx.peekc().hexValue() * 16 + lx.peek2().hexValue()
			if lx.peekc().hexValue() < 0 or lx.peek2().hexValue() < 0:
				lx.lexError(compileError("ByteHexEscape", []))
			lx.lxAdv()
			v = h
		else:
			lx.lexError(compileError("ByteEscape", []))
	elif v in [39, 10, 0]:
		lx.lexError(compileError("EmptyByte", []))
	elif v >= 128:
		lx.lexError(compileError("ByteNotAscii", []))
	lx.lxAdv()
	if lx.peekc() != 39:
		lx.lexError(compileError("ByteUnclosed", []))
	lx.lxAdv()
	lx.addTok(tkByte, "{v}", line, col)

# whether the `:` being read opens source kept as text: the body of `test "name" refuses Name`
# (or another word of sourceTestWords), or a case in a test's body (`refuses Name:`, a word of
# caseWords): the line's tokens start so
fn testSourceNext(lx Lexer):
	n = lx.toks.len
	if n < 2: return false
	k = n - 1
	while k > 0 and lx.toks[k - 1].line == lx.toks[n - 1].line:
		k -= 1
	while k < n and lx.toks[k].kind in [tkIndent, tkDedent, tkNewline]:
		k += 1
	if k + 2 <= n and lx.toks[k].kind == tkIdent and lx.toks[k].text in caseWords and
		lx.toks[k + 1].kind == tkUident:
		return true
	k + 3 <= n and lx.toks[k].kind == tkIdent and lx.toks[k].text == testWord and
		lx.toks[k + 1].kind == tkStr and lx.toks[k + 2].kind == tkIdent and
		keepsSource(lx.toks[k + 2].text)

# the lines indented past the block the `:` is in, kept as text with that indentation and one
# tab more taken off each: code the compiler must reject is not lexed with the rest of the file.
# The lexer stops before the newline that ends the block, so the next line is read as any other.
fn lexRawBlock(mut lx Lexer):
	line = lx.line
	col = lx.col
	depth = lx.levels[len - 1] + 1
	lx.lxAdv()
	lx.skipInlineTrivia()
	if lx.peekc() != 10:
		lx.lexError(compileError("TestSourceIndent", []))
	text = []
	going = true
	while going:
		# at the newline before a line: taken when the line is indented past the block or blank
		q = lx.pos + 1
		while q < lx.src.len and (lx.src[q] == 32 or lx.src[q] == 13):
			q += 1
		tabs = 0
		while q + tabs < lx.src.len and lx.src[q + tabs] == 9 and tabs < depth:
			tabs += 1
		r = q
		while r < lx.src.len and lx.src[r] in [9, 32, 13]:
			r += 1
		blank = r < lx.src.len and lx.src[r] == 10
		if q >= lx.src.len or not (blank or tabs == depth):
			going = false
		else:
			lx.lxAdv()
			while lx.pos < q:
				lx.lxAdv()
			if not blank:
				loop depth:
					lx.lxAdv()
			start = lx.pos
			while lx.peekc() != 0 and lx.peekc() != 10:
				lx.lxAdv()
			text.push(lx.src[start..lx.pos].copy())
			going = lx.peekc() != 0
	while not text.isEmpty and text[len - 1].trimmed() == "":
		text.pop()
	if text.isEmpty:
		lx.lexError(compileError("TestSourceIndent", []))
	lx.addTok(tkRawBlock, "\n{text.join("\n")}\n", line, col)   # line 1 empty: the source's line n is the file's line of the `:` plus n

# whether the `>` (or `>>`) just lexed closes type arguments (`u8[]` ends the line: written
# close), not a comparison or a shift that goes on below (`a >`, written with a space)
fn closesTypeArgs(lx Lexer):
	(lx.lastKind == tkGt or lx.lastKind == tkShr) and lx.tight

# A line's end. Blank lines and lines of comments pass. When the statement goes on (after an
# operator, a comma, an open bracket) nothing is emitted. After a line ending in `:` a newline
# then tkIndent: the next line, indented more, starts a block. Else the blocks the next line's
# indentation ends (a tkDedent each) and then the newline that ends the statement. Inside
# brackets a newline only separates (a list over several lines) and the indentation is free.
fn lineBreak(mut lx Lexer):
	indent = 0
	spaces = false
	more = true
	while more:
		indent = 0
		while lx.peekc() == 9:
			lx.lxAdv()
			indent += 1
		spaces = lx.peekc() == 32
		lx.skipInlineTrivia()
		if lx.peekc() == 10:
			lx.lxAdv()
		else:
			more = false
	if lx.peekc() == 0 or (suppressNewlineAfter(lx.lastKind) and not lx.closesTypeArgs()): return
	if lx.lastKind == tkNewline:
		# the file's first line
		if indent > 0 or spaces: lx.lexError(compileError("FirstLineIndented", []))
		return
	if lx.lastKind == tkColon:
		lx.addTok(tkNewline, "", lx.line, lx.col)
		if indent <= lx.levels[len - 1]:
			lexError(
				lx,
				compileError("BlockNotIndented", [])
			)
		lx.levels.push(indent)
		lx.blockNest.push(lx.nest)
		lx.addTok(tkIndent, "", lx.line, lx.col)
		return
	inBrackets = lx.nest > lx.blockNest[len - 1]
	# a line starting with `.` (a chain's step, zap fmt's break) goes on from the line above:
	# indented deeper than its block, or anywhere inside brackets, where a closing bracket's own
	# line goes on too
	if lx.peekc() == '.' and (lx.peek2() == '_' or lx.peek2() >= 'a' and lx.peek2() <= 'z') and   # a chain's step; a variant (.Quit) starts a line of its own
		(inBrackets or indent > lx.levels[len - 1]):
		return
	# a line starting with `if` or `else`, indented deeper than its block, goes on a choice
	if indent > lx.levels[len - 1] and (lx.wordAhead("if") or lx.wordAhead("else")): return
	if inBrackets:
		c = lx.peekc()
		if c in [')', ']', '}']: return
		lx.addTok(tkNewline, "", lx.line, lx.col)   # inside brackets: a separator the parser may skip
		return
	if spaces: lx.lexError(compileError("SpaceIndent", []))
	if indent > lx.levels[len - 1]:
		lexError(
			lx,
			compileError("UnexpectedIndent", [])
		)
	# the blocks that end come first, then the newline that ends the statement they were part of
	while indent < lx.levels[len - 1]:
		lx.levels.pop()
		lx.blockNest.pop()
		lx.addTok(tkDedent, "", lx.line, lx.col)
	if lx.nest > lx.blockNest[len - 1]:
		return   # a lambda's block inside a call: the `)` goes on
	if indent != lx.levels[len - 1]:
		lx.lexError(compileError("IndentMismatch", []))
	lx.addTok(tkNewline, "", lx.line, lx.col)

pub fn lex(src str, file str) Tok[]?:
	lexWith(src, file, false)

# source the compiler wrote (derive.zap): `$` may start and continue a name
pub fn lexInternal(src str, file str) Tok[]?:
	lexWith(src, file, true)

fn lexWith(src str, file str, internal bool) Tok[]?:
	# the lexer keeps its own source and file name: the caller only lends them
	lx = Lexer(
		src = src.copy(),
		file = file.copy(),
		pos = 0,
		line = 1,
		col = 1,
		toks = [],
		lastKind = tkNewline,
		interp = [],
		interpNest = [],
		indents = [],
		braceDepth = 0,
		nest = 0, levels = [0], blockNest = [
			0
		], tight = false, internal, markup = isMarkupFile(file))
	going = true
	while going:
		if lx.inMarkup():
			lx.lexMarkupStep()
			continue
		lx.skipInlineTrivia()
		c = lx.peekc()
		if c == 0:
			if not lx.marks.isEmpty: lx.unclosedTag()
			while lx.levels.len > 1:
				lx.levels.pop()
				lx.addTok(tkDedent, "", lx.line, lx.col)
			if lx.lastKind != tkNewline and not suppressNewlineAfter(lx.lastKind):
				lx.addTok(tkNewline, "", lx.line, lx.col)
			lx.addTok(tkEof, "", lx.line, lx.col)
			going = false
		elif c == 10:
			lx.lxAdv()
			lx.lineBreak()
		elif c == 'r' and lx.peek2() == 34:
			# r"..." and r"""...""": raw, no escape and no interpolation inside
			line = lx.line
			col = lx.col
			lx.lxAdv()
			if lx.peek2() == 34 and lx.peekAt(2) == 34:
				lx.lexMultiline(line, col, true)
			else:
				lx.lxAdv()
				lx.lexStringPart(line, col, -1, tkStr, tkStrBegin, true)
		elif c.isWordStart() or (lx.internal and c == 36):
			lx.lexIdent()
		elif c.isDigit():
			lx.lexNumber()
		elif c == 39:
			lx.lexByte()
		elif c == 34 and lx.peek2() == 34 and lx.peekAt(2) == 34:
			lx.lexMultiline(lx.line, lx.col)
		elif c == 34:
			line = lx.line
			col = lx.col
			lx.lxAdv()
			lx.lexStringPart(line, col, -1, tkStr, tkStrBegin)
		elif c == 125 and not lx.interp.isEmpty and lx.braceDepth == lx.interp[len - 1]:
			line = lx.line
			col = lx.col
			lx.lxAdv()
			lx.interp.pop()
			lx.interpNest.pop()
			lx.lexStringPart(line, col, lx.indents.pop() ?? -1, tkStrEnd, tkStrMid)
		elif c == ':' and lx.testSourceNext():
			lx.lexRawBlock()
		elif c == '<' and lx.markupStarts():
			lx.openTag()
		elif c == 125 and lx.closesMarkupExpr():
			lx.closeMarkupExpr()
		elif c == 123:
			lx.opN(tkLbrace, 1)
			lx.braceDepth += 1
		elif c == 125:
			lx.opN(tkRbrace, 1)
			lx.braceDepth -= 1
		elif c == 61 and lx.peek2() != 61 and lx.peek2() != 62 and lx.compoundOp() != "":
			last = lx.toks.len - 1
			lx.toks[last].text = lx.compoundOp()
			lx.toks[last].kind = tkOpAssign
			lx.lastKind = tkOpAssign
			lx.lxAdv()
		elif c == 63 and lx.pos > 0 and isBlank(lx.src[lx.pos - 1]) and isBlank(lx.peek2()):
			lx.opN(tkTernary, 1)   # a ? spaced on both sides: a result's, T ? E
		elif c == ':' and not lx.interp.isEmpty and lx.braceDepth == lx.interp[len - 1] and
			lx.nest == lx.interpNest[len - 1] and
			lx.pos > 0 and not isBlank(lx.src[lx.pos - 1]) and not isBlank(lx.peek2()):
			lx.lexFormatSpec()   # "{x:.2}": a colon written close ends the value (a lambda's `c:` is inside a call's brackets)
		elif lx.lexOperator():
			# an operator of the tables
			pass
		else:
			if not lx.interp.isEmpty:
				lx.lexError(compileError("InterpolationCharacter", ["{str.fromCode(i32(c))}"]))
			lx.lexError(compileError("UnexpectedCharacter", ["{str.fromCode(i32(c))}"]))
	if lx.stopped: return none
	lx.toks

# The format of an interpolated value: `"{x:.2}"`, `"{n:04}"`, `"{s:>8}"`. The colon is written
# right after the value (the ternary's ` : ` stands between spaces), and the spec runs to the
# interpolation's closing brace; the parser reads its parts.
fn lexFormatSpec(mut lx Lexer):
	line = lx.line
	col = lx.col
	lx.lxAdv()
	start = lx.pos
	while lx.peekc() != '}':
		c = lx.peekc()
		if c in [0, 10, '{', '"']:
			lx.lexError(compileError("FormatEnd", []))
			return
		lx.lxAdv()
	lx.addTok(tkFormatSpec, lx.src[start..lx.pos].copy(), line, col)

# a space or a tab (what tells the ternary ` ? ` from a try `x?`)
fn isBlank(c i64):
	c == 32 or c == 9
