# The parsing of lambdas, text, arrays, maps, patterns, matches and type arguments (parse.zap).

# `x: body`, `(a, b T): body` (and `x: body`): a lambda, its body an expression on the line
# or the lines indented after the `:`
fn parseLambda(mut p Parser) NodeId:
	start = p.cur().copy()
	e = p.mk(nLambda, start.line, start.col)
	if p.accept(tkLparen):
		going = not p.at(tkRparen)
		while going:
			n = p.expectTok(tkIdent)
			p.notAlias(n)
			p.nodes[e].nodeMore(p.kidIds).names.push(n.text)
			if p.at(tkComma) or p.at(tkRparen):
				p.nodes[e].nodePart(p.kidIds).types.push(p.mk(nTyAbsent, n.line, n.col))
			else:
				p.nodes[e].nodePart(p.kidIds).types.push(p.parseType())
			going = p.accept(tkComma) and not p.at(tkRparen)
		p.expectTok(tkRparen)
	else:
		n = p.expectTok(tkIdent)
		p.notAlias(n)
		p.nodes[e].nodeMore(p.kidIds).names.push(n.text)
		p.nodes[e].nodePart(p.kidIds).types.push(p.mk(nTyAbsent, n.line, n.col))
	c = p.expectTok(tkColon)
	if p.at(tkNewline):
		body = p.parseBody(c.line, c.col)
		# the block form of one expression (zap fmt's for a long lambda) is the expression's
		if p.nodes[body].kids(p.kidIds).len == 1 and
			p.nodes[p.nodes[body].kids(p.kidIds)[0]].kind == nExprStmt and
			p.nodes[p.nodes[body].kids(p.kidIds)[0]].kids(p.kidIds).len == 1:
			p.nodes[e].pushKid(p.kidIds, p.nodes[p.nodes[body].kids(p.kidIds)[0]].kids(p.kidIds)[0])
		else:
			p.nodes[e].nodePart(p.kidIds).sub.push(body)
	elif p.passAhead([tkRparen, tkComma, tkNewline, tkDedent, tkEof]):
		p.adv()
		p.nodes[e].nodePart(p.kidIds).sub.push(p.mk(nBlock, c.line, c.col))   # `(): pass`: does nothing
	else:
		madeKid = p.parseExpr()
		p.nodes[e].pushKid(p.kidIds, madeKid)
	e

fn strNode(mut p Parser, move t Tok):
	s = p.mk(nStr, t.line, t.col)
	p.nodes[s].setText(t.text)
	s

fn parseInterp(mut p Parser):
	begin = p.adv()
	e = p.mk(nInterp, begin.line, begin.col)
	madeKid = p.strNode(begin)
	p.nodes[e].pushKid(p.kidIds, madeKid)
	going = true
	while going:
		value = p.parseExpr()
		if p.at(tkFormatSpec):
			madeKid = p.formatted(value, p.adv())
			p.nodes[e].pushKid(p.kidIds, madeKid)
		else:
			p.nodes[e].pushKid(p.kidIds, value)
		if p.at(tkStrMid):
			madeKid = p.strNode(p.adv())
			p.nodes[e].pushKid(p.kidIds, madeKid)
		elif p.at(tkStrEnd):
			madeKid = p.strNode(p.adv())
			p.nodes[e].pushKid(p.kidIds, madeKid)
			going = false
		else:
			p.parseError(p.cur(), compileError("MalformedInterpolation", []))
			going = false
	e

# `{x:.N}` or `{x:x}`: x.toFixed(N) or x.toHex(upper)
fn numberText(mut p Parser, value NodeId, decimals i64, hex i64):
	line = p.nodes[value].line
	col = p.nodes[value].col
	f = p.mk(nField, line, col)
	p.nodes[f].setText("toFixed" if decimals >= 0 else "toHex")
	p.nodes[f].pushKid(p.kidIds, value)
	text = p.mk(nCall, line, col)
	p.nodes[text].pushKid(p.kidIds, f)
	if decimals >= 0:
		n = p.mk(nInt, line, col)
		p.nodes[n].setText("{decimals}")
		p.nodes[text].pushKid(p.kidIds, n)
	else:
		upper = p.mk(nBool, line, col)
		p.nodes[upper].ival = 1 if hex == 2 else 0
		p.nodes[text].pushKid(p.kidIds, upper)
	p.nodes[text].flags |= flagInternal
	text

# the value's own text, its interpolation
fn interpolated(mut nodes Node[], mut kidIds NodeLists, value NodeId) NodeId:
	line = nodes[value].line
	col = nodes[value].col
	before = newNode(nodes, kidIds, nStr, line, col)
	after = newNode(nodes, kidIds, nStr, line, col)
	newNode(nodes, kidIds, nInterp, line, col, kids = [before, value, after])

# `"{x:spec}"`: the value made the text its format asks for, by the formatting the compiler
# calls on the program's behalf (a program writes the format, not the calls):
#   .N       x.toFixed(N)                  a float with N decimals
#   x, X     x.toHex(upper)                an integer in hexadecimal
#   0W       formatZeroPad(text, W)        a number's text widened to W with zeros after its sign
#   [c]<W    formatAlign(text, W, c, true) the text padded to W with c (a space) after it
#   [c]>W    formatAlign(text, W, c, false) ... before it
#   #...     formatLiteral(text, hex)      an integer as zap fmt writes its literal (`#08X`)
# W is digits or, after < or >, a name (`{s:<width}`); the text is the value's own (its
# interpolation) unless .N or x made it. They combine as `>8.2`, `08x`, `#08X`.
fn formatted(mut p Parser, value NodeId, spec Tok):
	s = spec.text
	line = p.nodes[value].line
	col = p.nodes[value].col
	literal = s.len >= 1 and s[0] == '#'
	i = 1 if literal else 0
	fill = " "
	align = 0   # 1 left (<), 2 right (>)
	if literal:
		pass
	elif s.len >= 2 and (s[1] == '<' or s[1] == '>') and s[0] != '<' and s[0] != '>':
		fill = s[..1].copy()
		align = 1 if s[1] == '<' else 2
		i = 2
	elif s.len >= 1 and (s[0] == '<' or s[0] == '>'):
		align = 1 if s[0] == '<' else 2
		i = 1
	zero = false
	if align == 0 and i + 1 < s.len and s[i] == '0' and s[i + 1].isDigit():
		zero = true
		i += 1
	width NodeId? = none
	start = i
	while i < s.len and s[i].isDigit():
		i += 1
	if i > start:
		digits = p.mk(nInt, line, col)
		p.nodes[digits].setText(s[start..i].copy())
		width = digits
	elif align != 0 and i < s.len and s[i].isAlpha():
		while i < s.len and s[i].isWordByte():
			i += 1
		name = p.mk(nIdent, line, col)
		p.nodes[name].setText(s[start..i].copy())
		width = name
	decimals = -1
	if i < s.len and s[i] == '.':
		i += 1
		from = i
		while i < s.len and s[i].isDigit():
			i += 1
		decimals = (i64.parse(s[from..i]) ?? -1) if i > from else -1
		if decimals < 0:
			i = -1
	hex = 0   # 1 lower case, 2 upper case
	if i >= 0 and i < s.len and (s[i] == 'x' or s[i] == 'X'):
		hex = 1 if s[i] == 'x' else 2
		i += 1
	if i != s.len or align != 0 and width == none or (hex > 0 or literal) and decimals >= 0:
		p.parseError(spec, compileError("UnknownFormat", ["{s}"]))
	if width != none and align == 0 and not zero:
		p.parseError(spec, compileError("WidthAligned", ["{s}"]))
	text = p.numberText(value, decimals, hex) if decimals >= 0 or hex > 0
		else p.nodes.interpolated(p.kidIds, value)
	if zero or align != 0: text = p.padded(text, width, zero, fill, align == 1)
	if not literal: return text
	call = p.internalCall("formatLiteral", text)
	isHex = p.mk(nBool, line, col)
	p.nodes[isHex].ival = 1 if hex > 0 else 0
	p.nodes[call].pushKid(p.kidIds, isHex)
	call

# the text widened as `04` or `>8` asks: formatZeroPad(text, W), formatAlign(text, W, c, left)
fn padded(mut p Parser, text NodeId, width NodeId?, zero bool, fill str, left bool):
	call = p.internalCall("formatZeroPad" if zero else "formatAlign", text)
	if width is width: p.nodes[call].pushKid(p.kidIds, width)
	if not zero:
		padding = p.mk(nStr, p.nodes[text].line, p.nodes[text].col)
		p.nodes[padding].setText(fill.copy())
		p.nodes[call].pushKid(p.kidIds, padding)
		isLeft = p.mk(nBool, p.nodes[text].line, p.nodes[text].col)
		p.nodes[isLeft].ival = 1 if left else 0
		p.nodes[call].pushKid(p.kidIds, isLeft)
	call

# the call of the runtime's function `name` a format makes, on the text
fn internalCall(mut p Parser, name str, text NodeId):
	line = p.nodes[text].line
	col = p.nodes[text].col
	callee = p.mk(nIdent, line, col)
	p.nodes[callee].setText(name.copy())
	p.nodes[callee].flags = flagInternal
	call = p.mk(nCall, line, col)
	p.nodes[call].pushKid(p.kidIds, callee)
	p.nodes[call].pushKid(p.kidIds, text)
	call

fn parseArray(mut p Parser):
	lb = p.adv()
	e = p.mk(nArray, lb.line, lb.col)
	p.skipNL()
	while p.before(tkRbracket):
		madeKid = p.valueExpr()
		p.nodes[e].pushKid(p.kidIds, madeKid)
		p.accept(tkComma)
		p.skipNL()
	p.expectTok(tkRbracket)
	e

fn parseMapLit(mut p Parser):
	lb = p.adv()
	e = p.mk(nMapLit, lb.line, lb.col)
	p.skipNL()
	while p.before(tkRbrace):
		madeKid = p.plainExpr()
		p.nodes[e].pushKid(p.kidIds, madeKid)
		p.expectTok(tkColon)
		p.nodes[e].nodePart(p.kidIds).sub.push(p.valueExpr())
		p.accept(tkComma)
		p.skipNL()
	p.expectTok(tkRbrace)
	e

# A pattern, written as its value is built: none, _, a name (`name is pattern` binds the whole
# and tests it), a variant or a struct with patterns for its parts (by position, then `field =
# pattern`), a tuple, a list (`..rest` the elements between), a string whose interpolations are
# names (`"GET {path}"`), a map's entries, a literal or a range of numbers.
fn parsePattern(mut p Parser) NodeId:
	t = p.here()
	pat = p.mk(nPattern, t.line, t.col)
	if p.at(tkNone):
		p.adv()
		p.nodes[pat].ival = patNone
		return pat
	if p.at(tkUident): return p.parsePatternCtor(pat)
	if p.at(tkIdent): return p.parsePatternBind(pat)
	if p.at(tkMut) and p.kindAt(1) == tkIdent:
		# `mut name`: the name is the matched place's part, changed in place
		p.adv()
		p.nodes[pat].line = i32(p.cur().line)
		p.nodes[pat].col = nodeCol(p.cur().col)
		p.nodes[pat].flags |= flagMut
		return p.parsePatternBind(pat)
	if p.accept(tkLparen): return p.parsePatternTuple(pat, t)
	if p.accept(tkLbracket): return p.parsePatternList(pat)
	if p.accept(tkLbrace): return p.parsePatternMap(pat)
	if p.at(tkStrBegin): return p.parsePatternStr(pat)
	if p.startsLiteral(): return p.parsePatternLit(pat, t)
	p.parseError(p.cur(), compileError("ExpectedPattern", ["{tokKindName(p.kind())}"]))
	pat

fn parsePatternCtor(mut p Parser, pat NodeId) NodeId:
	c = p.adv()
	p.nodes[pat].ival = patCtor
	p.nodes[pat].setText(c.text)
	if p.accept(tkLparen):
		p.nodes[pat].flags |= flagWritten   # Variant(a, b) tests its values; Variant alone any
		p.skipNL()
		while p.before(tkRparen):
			field = ""
			if p.at(tkIdent) and p.kindAt(1) == tkEq:
				field = p.adv().text
				p.adv()
			elif not p.nodes[pat].names(p.kidIds).all(it == ""):
				parseError(
					p,
					p.cur(),
					compileError("PositionalAfterNamed", [])
				)
			p.nodes[pat].nodeMore(p.kidIds).names.push(field)
			madeKid = p.parsePattern()
			p.nodes[pat].pushKid(p.kidIds, madeKid)
			p.skipNL()
			if not p.accept(tkComma): break
			p.skipNL()
		p.expectTok(tkRparen)
	pat

fn parsePatternBind(mut p Parser, pat NodeId) NodeId:
	n = p.adv()
	p.notAlias(n)
	if n.text == "_":
		p.nodes[pat].ival = patWildcard
	else:
		p.nodes[pat].ival = patBind
		p.nodes[pat].setText(n.text)
		if p.accept(tkIs):
			madeKid = p.parsePattern()
			p.nodes[pat].pushKid(p.kidIds, madeKid)
	pat

fn parsePatternTuple(mut p Parser, pat NodeId, t Tok) NodeId:
	p.skipNL()
	first = p.parsePattern()
	p.skipNL()
	if p.accept(tkRparen): return first   # parentheses around one pattern group it
	p.nodes[pat].ival = patTuple
	p.nodes[pat].pushKid(p.kidIds, first)
	while p.accept(tkComma):
		p.skipNL()
		if p.at(tkRparen): break
		madeKid = p.parsePattern()
		p.nodes[pat].pushKid(p.kidIds, madeKid)
		p.skipNL()
	p.expectTok(tkRparen)
	if p.nodes[pat].kids(p.kidIds).len > 8:
		p.parseError(t, compileError("TupleSize", []))
	pat

fn parsePatternList(mut p Parser, pat NodeId) NodeId:
	p.nodes[pat].ival = patList
	p.skipNL()
	while p.before(tkRbracket):
		if p.at(tkDotdot):
			d = p.adv()
			rest = p.mk(nPattern, d.line, d.col)
			p.nodes[rest].ival = patRest
			if p.at(tkIdent):
				n = p.adv()
				p.notAlias(n)
				if n.text != "_":
					p.nodes[rest].setText(n.text)
			if p.nodes[pat].kids(p.kidIds).any(p.nodes[it].ival == patRest):
				p.parseError(d, compileError("ListPatternRests", []))
			p.nodes[pat].pushKid(p.kidIds, rest)
		else:
			madeKid = p.parsePattern()
			p.nodes[pat].pushKid(p.kidIds, madeKid)
		p.skipNL()
		if not p.accept(tkComma): break
		p.skipNL()
	p.expectTok(tkRbracket)
	pat

fn parsePatternMap(mut p Parser, pat NodeId) NodeId:
	p.nodes[pat].ival = patMap
	p.skipNL()
	while p.before(tkRbrace):
		if not p.startsLiteral():
			parseError(
				p,
				p.cur(),
				compileError("MapPatternKeys", [])
			)
		madeKid = p.patternLiteral()
		p.nodes[pat].pushKid(p.kidIds, madeKid)
		p.expectTok(tkColon)
		p.skipNL()
		madeKid = p.parsePattern()
		p.nodes[pat].pushKid(p.kidIds, madeKid)
		p.skipNL()
		if not p.accept(tkComma): break
		p.skipNL()
	p.expectTok(tkRbrace)
	pat

fn parsePatternStr(mut p Parser, pat NodeId):
	# "GET {path} HTTP": the text around each capture must be there, each capture a name
	p.nodes[pat].ival = patStr
	p.nodes[pat].nodeMore(p.kidIds).names.push(p.adv().text)
	loop:
		n = p.expectTok(tkIdent)
		p.notAlias(n)
		capture = p.mk(nPattern, n.line, n.col)
		if n.text == "_":
			p.nodes[capture].ival = patWildcard
		else:
			p.nodes[capture].ival = patBind
			p.nodes[capture].setText(n.text)
		p.nodes[pat].pushKid(p.kidIds, capture)
		if not p.at(tkStrMid) and not p.at(tkStrEnd):
			parseError(
				p,
				p.cur(),
				compileError("StrPatternCaptures", [])
			)
		last = p.at(tkStrEnd)
		piece = p.adv()
		if not last and piece.text == "":
			parseError(
				p,
				piece,
				compileError("StrPatternAdjacentCaptures", [])
			)
		p.nodes[pat].nodeMore(p.kidIds).names.push(piece.text)
		if last or p.stopped: break
	pat

fn parsePatternLit(mut p Parser, pat NodeId, t Tok):
	lit = p.patternLiteral()
	p.nodes[pat].ival = patLit
	p.nodes[pat].pushKid(p.kidIds, lit)
	lk = p.nodes[lit].kind
	if p.at(tkDotdot) or p.at(tkDotdotEq):
		# lo..hi: a number from lo up to, not including, hi (as a range elsewhere); lo..=hi
		# includes hi; lo.. has no end
		dd = p.adv()
		if lk != nInt and lk != nFloat:
			p.parseError(dd, compileError("RangePatternSpelling", []))
		p.nodes[pat].ival = patRange
		if dd.kind == tkDotdotEq:
			p.nodes[pat].setText2(p.kidIds, "=")
		if p.startsLiteral():
			hi = p.patternLiteral()
			if p.nodes[hi].kind != lk:
				p.parseError(dd, compileError("RangePatternEnds", []))
			p.nodes[pat].pushKid(p.kidIds, hi)
		elif dd.kind == tkDotdotEq:
			p.parseError(dd, compileError("RangePatternInclusiveEnd", []))
	elif lk == nFloat:
		parseError(
			p,
			t,
			compileError("FloatPattern", [])
		)
	pat

# whether a literal of a pattern starts here
fn startsLiteral(p Parser):
	p.at(tkInt) or p.at(tkByte) or p.at(tkFloat) or p.at(tkStr) or p.at(tkTrue) or
		p.at(tkFalse) or (p.at(tkMinus) and (p.kindAt(1) == tkInt or p.kindAt(1) == tkFloat))

# a literal of a pattern: a number (negative too), a byte, a string or a bool
fn patternLiteral(mut p Parser):
	neg = p.accept(tkMinus)
	lt = p.adv()
	lit NodeId = 0
	if lt.kind == tkByte:
		lit = p.mk(nInt, lt.line, lt.col)
		p.nodes[lit].setText(lt.text)
		p.nodes[lit].flags = flagByte
	elif lt.kind == tkInt or lt.kind == tkFloat:
		lit = p.mk(nInt if lt.kind == tkInt else nFloat, lt.line, lt.col)
		if neg:
			p.nodes[lit].setText("-{lt.text}")
		else:
			p.nodes[lit].setText(lt.text)
	elif lt.kind == tkStr:
		lit = p.strNode(lt)
	else:
		lit = p.mk(nBool, lt.line, lt.col)
		if lt.kind == tkTrue:
			p.nodes[lit].ival = 1
	lit

# An arm's patterns, one or several separated by commas (`0x04, 0x0A:`), then its condition
# (`and cond`, kept as the sub of each pattern: the arm runs when a pattern matches and the
# condition holds)
fn parseArmPatterns(mut p Parser):
	pats = [p.parsePattern()]
	while p.accept(tkComma):
		p.skipNL()
		pats.push(p.parsePattern())
	if p.accept(tkAnd):
		guard = p.parseLevel(4)
		if p.at(tkOr):
			parseError(
				p,
				p.cur(),
				compileError("ArmConditionOr", [])
			)
		for i, pat in pats:
			g = guard if i == 0 else cloneTree(p.nodes, p.kidIds, guard)
			p.nodes[pat].nodePart(p.kidIds).sub.push(g)
	pats

fn parseMatch(mut p Parser):
	was = p.valueAt
	p.valueAt = false   # its header and its arms' patterns end in `:`, as a statement's do
	e = p.parseMatchAt()
	p.valueAt = was
	e

fn parseMatchAt(mut p Parser):
	m = p.adv()
	e = p.mk(nMatch, m.line, m.col)
	arms = [p.parseExpr()]   # the matched value, then the arms: set at the end (Node)
	p.expectTok(tkColon)
	p.openIndented()
	while not p.at(tkDedent) and not p.at(tkEof):
		armT = p.here()
		arm = p.mk(nArm, armT.line, armT.col)
		pats = p.parseArmPatterns()
		p.nodes[arm].pushKid(p.kidIds, pats[0])
		c = p.expectTok(tkColon)
		if p.at(tkNewline):
			p.nodes[arm].nodePart(p.kidIds).sub.push(p.parseBody(c.line, c.col))
		else:
			s = p.parseStmt()
			if p.nodes[s].kind == nExprStmt:
				p.nodes[arm].pushKid(p.kidIds, p.nodes[s].kids(p.kidIds)[0])
			elif p.nodes[s].kind == nBlock and p.nodes[s].text == "$splice":
				p.nodes[s].setText("")   # statements to splice: the arm's block
				p.nodes[arm].nodePart(p.kidIds).sub.push(s)
			else:
				blk = p.mk(nBlock, armT.line, armT.col)
				p.nodes[blk].pushKid(p.kidIds, s)
				p.nodes[arm].nodePart(p.kidIds).sub.push(blk)
		arms.push(arm)
		# `A, B => body` is an arm per pattern, each with the body of its own; they note the
		# first (ival) so the checker holds them to binding the same names
		for i in 1..pats.len:
			p.nodes[arm].ival = i64(arm)
			again = cloneTree(p.nodes, p.kidIds, arm)
			p.nodes[again].setKid(p.kidIds, 0, pats[i])
			arms.push(again)
		p.skipNL()
	p.expectTok(tkDedent)
	p.nodes[e].setKids(p.kidIds, arms)
	e

# a value picked by a condition: a match on it, true giving `yes`, anything else `no`
fn ifValueNode(mut p Parser, cond NodeId, yes NodeId, no NodeId, line i64, col i64):
	m = p.mk(nMatch, line, col)
	p.nodes[m].pushKid(p.kidIds, cond)
	armYes = p.mk(nArm, line, col)
	pat = p.mk(nPattern, line, col)
	p.nodes[pat].ival = patLit
	lit = p.mk(nBool, line, col)
	p.nodes[lit].ival = 1
	p.nodes[pat].pushKid(p.kidIds, lit)
	p.nodes[armYes].pushKid(p.kidIds, pat)
	p.nodes[armYes].pushKid(p.kidIds, yes)
	p.nodes[m].pushKid(p.kidIds, armYes)
	armNo = p.mk(nArm, line, col)
	wild = p.mk(nPattern, line, col)
	p.nodes[wild].ival = patWildcard
	p.nodes[armNo].pushKid(p.kidIds, wild)
	p.nodes[armNo].pushKid(p.kidIds, no)
	p.nodes[m].pushKid(p.kidIds, armNo)
	m

# `<A, B>` after a type's name, if there
fn parseTypeArgs(mut p Parser):
	typeArgs = []
	if p.at(tkLt):
		p.adv()
		going = true
		while going:
			if p.at(tkInt):
				n = p.adv()
				typeArgs.push(p.mk(nTyName, n.line, n.col))
				p.nodes[typeArgs[len - 1]].setText(n.text)   # a number parameter's value
			else:
				typeArgs.push(p.parseType())
			going = p.accept(tkComma)
		p.expectGt()
	typeArgs

# whether the `<` after a type's name in an expression opens type arguments (Mat<2, 3>(...)) and
# is no comparison (N < 3): only what a type is written with up to the `>` that closes it
fn typeArgsAhead(p Parser):
	p.typeArgsEnd() >= 0

# whether a function's name t is followed by the type arguments of its call: `zeros<3>()`, the
# `<` written against the name (a comparison is spaced) and a `(` after the `>`
fn callTypeArgsAhead(p Parser, t Tok):
	if not p.at(tkLt) or p.cur().line != t.line or p.cur().col != t.col + t.text.len: return false
	end = p.typeArgsEnd()
	end >= 0 and end + 1 < p.toks.len and p.toks[end + 1].kind == tkLparen

# the place of the `>` closing the type arguments that open here, or -1 when what follows the
# `<` is no type arguments
fn typeArgsEnd(p Parser):
	if not p.at(tkLt): return -1
	inType = [
		tkIdent,
		tkUident,
		tkInt,
		tkComma,
		tkDot,
		tkLparen,
		tkRparen,
		tkLbracket,
		tkRbracket,
		tkQuestion,
		tkTernary,
		tkFn,
		tkRef,
		tkMut,
		tkIn,
		tkDotdot,
		tkDotdotEq,
		tkMinus
	]
	depth = 1
	i = p.pos + 1
	while i < p.toks.len:
		k = p.toks[i].kind
		if k == tkLt:
			depth += 1
		elif k == tkGt or k == tkShr:
			depth -= 1 if k == tkGt else 2
			if depth <= 0: return i if depth == 0 else -1
		elif k not in inType:
			return -1
		i += 1
	-1
