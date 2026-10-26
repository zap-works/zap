# The markup of a .zapx file (spec 7.11), lexed: a `<` that opens an expression starts it, and
# until its last tag closes the lexer reads tags, attributes and text instead of code, the code
# of `{...}` inside it read as any other.

import zapx

markTag = 0   # inside `<tag ...`: attributes up to `>` or `/>`
markKids = 1   # between an element's tags: text, elements and `{...}`
markExpr = 2   # code inside a `{...}` of a tag or of children

# a part of the markup left open
type MarkFrame:
	kind i64
	tag str   # the element's (markTag, markKids)
	line i64   # where it opened
	col i64
	braces i64 = 0   # markExpr: the brace depth outside its `{`
	nest i64 = 0   # markExpr: the brackets open inside its `{`
	interps i64 = 0   # the interpolations open when it opened (one opened after it is code)

# whether the file's markup is read: a .zapx file
pub fn isMarkupFile(path str) bool:
	path.endsWith(".zapx")

# whether the lexer reads markup now: a tag or children open, and no string interpolation
# opened inside them
fn inMarkup(lx Lexer):
	if lx.marks.isEmpty: return false
	top = lx.marks[len - 1]
	top.kind != markExpr and lx.interp.len == top.interps

# whether the `<` here opens markup: in a .zapx file, where an expression starts (not after a
# value, where it compares or opens type arguments), before a tag's name or a fragment's `>`
fn markupStarts(lx Lexer):
	if not lx.markup: return false
	next = lx.peek2()
	if not (next.isAlpha() or next == '>'): return false
	not (lx.lastKind in valueEnds)

# the tokens a value ends with
valueEnds = [
	tkIdent,
	tkUident,
	tkInt,
	tkFloat,
	tkStr,
	tkStrEnd,
	tkByte,
	tkRparen,
	tkRbracket,
	tkRbrace,
	tkTrue,
	tkFalse,
	tkNone,
	tkThis,
	tkIt,
	tkQuestion,
	tkMarkClose,
	tkMarkSelfClose
]

# `<tag` (or the `<` of a fragment `<>`): a tag opens
fn openTag(mut lx Lexer):
	line = lx.line
	col = lx.col
	lx.lxAdv()
	tag = lx.markName()
	lx.addTok(tkMarkOpen, tag.copy(), line, col)
	fragment = tag == ""
	lx.marks.push(MarkFrame(markTag, tag, line, col, interps = lx.interp.len))
	if fragment:
		lx.lxAdv()   # a fragment's `>`: its children follow
		lx.addTok(tkMarkTagEnd, "", line, col)
		lx.marks[len - 1].kind = markKids

# a tag's or an attribute's name: letters, digits, `-`, `_`, `:` and `.`
fn markName(mut lx Lexer):
	start = lx.pos
	while lx.peekc().isWordByte() or lx.peekc() in ['-', ':', '.']:
		lx.lxAdv()
	lx.src[start..lx.pos].copy()

# `{` in a tag or among children: code up to its `}`
fn openMarkupExpr(mut lx Lexer):
	lx.opN(tkLbrace, 1)
	lx.marks.push(
		MarkFrame(
			markExpr,
			"",
			lx.line,
			lx.col,
			braces = lx.braceDepth,
			nest = lx.nest,
			interps = lx.interp.len
		)
	)
	lx.braceDepth += 1

# whether the `}` here closes the `{...}` of markup
fn closesMarkupExpr(lx Lexer):
	not lx.marks.isEmpty and lx.marks[len - 1].kind == markExpr and
		lx.braceDepth == lx.marks[len - 1].braces + 1

# the `}` of markup's code: the blocks opened inside it end, and the markup goes on
fn closeMarkupExpr(mut lx Lexer):
	frame = lx.marks.pop() ?? return
	while lx.blockNest.len > 1 and lx.blockNest[len - 1] >= frame.nest:
		lx.levels.pop()
		lx.blockNest.pop()
		lx.addTok(tkDedent, "", lx.line, lx.col)
	lx.opN(tkRbrace, 1)
	lx.braceDepth -= 1

# one step of markup: a tag's next part, or the children's
fn lexMarkupStep(mut lx Lexer):
	if lx.marks[len - 1].kind == markTag:
		lx.lexTagPart()
	else:
		lx.lexChildren()

fn markupError(mut lx Lexer, line i64, col i64, msg str):
	lx.lexErrorAt(line, col, msg)

# the markup left open at the file's end: its innermost element is unclosed
fn unclosedTag(mut lx Lexer):
	k = lx.marks.len - 1
	while k > 0 and lx.marks[k].kind == markExpr:
		k -= 1
	top = lx.marks[k]
	lx.markupError(top.line, top.col, compileError("MarkupUnclosed", ["{top.tag}"]))

fn lexTagPart(mut lx Lexer):
	while lx.peekc() in [' ', 9, 10, 13]:
		lx.lxAdv()
	c = lx.peekc()
	line = lx.line
	col = lx.col
	tag = lx.marks[len - 1].tag.copy()
	if c == 0:
		lx.unclosedTag()
	elif c == '>':
		lx.lxAdv()
		if zapx.isVoid(tag):
			lx.addTok(tkMarkSelfClose, "", line, col)
			lx.marks.pop()
		else:
			lx.addTok(tkMarkTagEnd, "", line, col)
			lx.marks[len - 1].kind = markKids
	elif c == '/' and lx.peek2() == '>':
		lx.lxAdv()
		lx.lxAdv()
		lx.addTok(tkMarkSelfClose, "", line, col)
		lx.marks.pop()
	elif c.isAlpha() or c == '_':
		name = lx.markName()
		lx.addTok(tkMarkAttr, name, line, col)
	elif c == '=' and lx.peek2() in ['"', '{'] and lx.lastKind == tkMarkAttr:
		lx.opN(tkEq, 1)
	elif c == '=' and lx.lastKind == tkMarkAttr:
		name = lx.toks[len - 1].text.copy()
		lx.markupError(line, col, compileError("MarkupAttributeValue", [name]))
	elif c == '"':
		lx.lxAdv()
		lx.lexStringPart(line, col, -1, tkStr, tkStrBegin)
	elif c == '{':
		lx.openMarkupExpr()
	else:
		lx.markupError(
			line,
			col,
			compileError("MarkupTagCharacter", ["{str.fromCode(i32(c))}", tag])
		)

fn lexChildren(mut lx Lexer):
	c = lx.peekc()
	line = lx.line
	col = lx.col
	if c == 0:
		lx.unclosedTag()
	elif c == '<' and lx.peek2() == '/':
		lx.closeTag()
	elif c == '<' and (lx.peek2().isAlpha() or lx.peek2() == '>'):
		lx.openTag()
	elif c == '{':
		lx.openMarkupExpr()
	elif c == '}':
		lx.markupError(line, col, compileError("MarkupBrace", []))
	else:
		start = lx.pos
		while not (lx.peekc() in [0, '{', '}']) and
			not (lx.peekc() == '<' and (lx.peek2().isAlpha() or lx.peek2() in ['>', '/'])):
			lx.lxAdv()
		text = markupText(lx.src[start..lx.pos])
		if text != "":
			lx.addTok(tkMarkText, text, line, col)

# `</tag>`: it closes the element open, whose tag it must name
fn closeTag(mut lx Lexer):
	line = lx.line
	col = lx.col
	lx.lxAdv()
	lx.lxAdv()
	name = lx.markName()
	while lx.peekc() in [' ', 9]:
		lx.lxAdv()
	if lx.peekc() != '>':
		lx.markupError(line, col, compileError("MarkupCloseTag", [name.copy()]))
		return
	lx.lxAdv()
	top = lx.marks[len - 1]
	if name != top.tag:
		lx.markupError(
			line,
			col,
			compileError("MarkupMismatch", [name.copy(), top.tag.copy(), "{top.line}"])
		)
		return
	lx.addTok(tkMarkClose, name, line, col)
	lx.marks.pop()

# The text between tags as the page keeps it: within a line as written; across lines each line's
# indentation and trailing blanks taken off, blank lines dropped and the lines joined by a space
# (so laying the markup out changes no text)
fn markupText(raw str) str:
	if "\n" not in raw: return raw.copy()
	out = []
	start = 0
	loop:
		nl = raw.indexOf("\n", start) ?? raw.len
		a = start
		b = nl
		if start > 0:
			while a < b and raw[a] in [' ', 9, 13]:
				a += 1
		if nl < raw.len:
			while b > a and raw[b - 1] in [' ', 9, 13]:
				b -= 1
		if b > a:
			if not out.isEmpty:
				out.push(' ')
			out.extend(raw[a..b].bytes())
		if nl == raw.len: break
		start = nl + 1
	str(move out)
