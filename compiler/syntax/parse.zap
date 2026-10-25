# Recursive-descent parser: tokens to nodes in the shared arena (a port of parser.c).

# an alias in scope: its name and its expression
type ParsedAlias:
	name str
	expr NodeId

type Parser:
	toks Tok[]
	pos i64
	file str
	nodes Node[]
	aliases ParsedAlias[] = []   # the aliases in scope, the innermost last
	fileOptions i64 = 0   # the flags of the file's `use` line
	blockOptions bool = false   # a block of the function being parsed has a `use` line
	indexDepth i64 = 0   # how many indexes' brackets are open: inside them a bare `length` is the list's length
	inTest bool = false   # parsing a test's body: `prints text` is a statement there
	testPrints bool = false   # the test being parsed has a `prints`
	testDecl NodeId = 0   # the test being parsed, whose kids its cases (`refuses Name:`) are
	modules str[] = []   # the names of the modules the file imports whole (`import fs`)
	valueAt bool = false   # the expression parsed is a value given (an argument, a binding's):
#   a lambda may be written there without `fn` (`p: body`), never in a statement's header
	inBound bool = false   # parsing a bound's signatures, which take `self` first
	blockMethods NodeId[] = []   # the methods of the type block just parsed: declarations after it
	stopped bool = false   # an error was said: the file is not parsed further

# The error said, once, and the parsing stopped: the tokens left are skipped to the end of file,
# where every loop of the parser ends, and parseProgram gives none.
fn parseError(mut p Parser, t Tok, msg str):
	p.stopParsing(t.line, t.col, msg)

fn stopParsing(mut p Parser, line i64, col i64, msg str):
	if p.stopped: return
	errorAtFile(p.file, line, col, msg)
	p.stopped = true
	p.pos = p.toks.len - 1

# the identifier `word` where a construct gives it a meaning (`from`), consumed when there
fn acceptWord(mut p Parser, word str):
	if p.at(tkIdent) and p.cur().text == word:
		p.adv()
		return true
	false

fn cur(p Parser) ref Tok:
	p.toks[p.pos]

# where the current token is: its kind, line and column without its text (what a construct
# keeps of its first token while the tokens after it are consumed)
fn here(p Parser):
	t = p.cur()
	Tok(kind = t.kind, text = "", line = t.line, col = t.col)

fn kind(p Parser):
	p.toks[p.pos].kind

fn kindAt(p Parser, off i64):
	i = p.pos + off
	if i >= p.toks.len:
		i = p.toks.len - 1
	p.toks[i].kind

fn at(p Parser, k i64):
	p.kind() == k

# whether the elements of a list, a map, a pattern or markup go on before their closer k: not
# there yet, and the parsing not stopped (at the end of file, where the closer never comes)
fn before(p Parser, k i64):
	not p.at(k) and not p.stopped

# The token at the position, moved out: each token is consumed once, so its text is taken (a
# look back reads only the kind and the line, which stay). The last token (end of file) is
# never passed, so it is handed out as a copy of its own (its text is empty).
fn adv(mut p Parser):
	i = p.pos
	if p.pos < p.toks.len - 1:
		p.pos += 1
		k = p.toks[i].kind
		line = p.toks[i].line
		col = p.toks[i].col
		return Tok(kind = k, text = move p.toks[i].text, line, col)
	p.toks[i].copy()

fn accept(mut p Parser, k i64):
	if p.at(k):
		p.adv()
		return true
	false

fn expectTok(mut p Parser, k i64) Tok:
	if k == tkIdent and p.at(tkIt): p.parseError(p.cur(), compileError("ItIsNoName", []))
	if not p.at(k):
		p.parseError(
			p.cur(),
			compileError("Expected", ["{tokKindName(k)}", "{tokKindName(p.kind())}"])
		)
	p.adv()

fn skipNL(mut p Parser):
	while p.at(tkNewline):
		p.adv()

# the '>' that closes type arguments: `>>` (Pool<Handle<i64>>) is split into two
fn expectGt(mut p Parser):
	if p.at(tkShr):
		p.toks[p.pos].kind = tkGt
		p.toks[p.pos].col += 1
		return
	p.expectTok(tkGt)

fn mk(mut p Parser, k i64, line i64, col i64) NodeId:
	newNode(p.nodes, k, line, col)

# ---------- types ----------

fn startsType(p Parser):
	p.at(tkIdent) or p.at(tkUident) or p.at(tkFn) or p.at(tkTernary) or p.at(tkLbrace) or
		(p.at(tkLparen) and p.kindAt(1) == tkRparen) or p.at(tkRef) or
		(p.at(tkMut) and p.kindAt(1) == tkRef)

fn parseTypePrimary(mut p Parser) NodeId:
	p.typeSuffixes(p.parseTypeBase())

# `{K: V}`, the map type
fn parseMapType(mut p Parser):
	lb = p.expectTok(tkLbrace)
	te = p.mk(nTyName, lb.line, lb.col)
	p.nodes[te].text = "Map"
	p.nodes[te].types.push(p.parseType())
	p.expectTok(tkColon)
	p.nodes[te].types.push(p.parseType())
	p.expectTok(tkRbrace)
	te

# the brackets and optionals after a type: `T?[]` a list of optionals, `T[]?` an optional list;
# the ? after the last bracket stay for optionalsOf
fn typeSuffixes(mut p Parser, base NodeId):
	t = base
	going = true
	while going:
		q = 0
		while p.kindAt(q) == tkQuestion or p.kindAt(q) == tkQq:
			q += 1
		if p.kindAt(q) == tkLbracket and (q > 0 or t == base):
			t = p.typeSizes(p.optionalsOf(t))
		else:
			going = false
	t

# `[3, 4]` after a type, its sizes outer first, an empty place a list: `[, 4]` a list of arrays
# of four, `[2, ]` two lists, `[,]` a list of lists
fn typeSizes(mut p Parser, elem NodeId):
	lb = p.expectTok(tkLbracket)
	sizes = []   # -1 for a list
	names = []   # a number parameter's name for its size (`f32[N]`), else ""
	going = true
	while going:
		if p.at(tkInt):
			n = p.adv()
			sizes.push(i64.parse(n.text) ?? 0)
			names.push("")
		elif p.at(tkUident):
			sizes.push(0)
			names.push(p.adv().text)   # T[N]: a number parameter's value
		elif p.at(tkComma) or p.at(tkRbracket):
			sizes.push(-1)
			names.push("")
		else:
			p.parseError(
				p.cur(),
				compileError("TypeSize", [])
			)
		going = p.accept(tkComma)
	p.expectTok(tkRbracket)
	t = elem
	i = sizes.len - 1
	while i >= 0:
		layer = p.mk(nTyName if sizes[i] < 0 else nTyArray, lb.line, lb.col)
		if sizes[i] < 0:
			p.nodes[layer].text = "List"
		elif names[i] != "":
			p.nodes[layer].text = names[i].copy()
		else:
			p.nodes[layer].ival = i32(sizes[i])
		p.nodes[layer].types.push(t)
		t = layer
		i -= 1
	t

fn parseTypeBase(mut p Parser):
	t = p.here()
	if p.at(tkLbrace): return p.parseMapType()
	if p.at(tkRef) or (p.at(tkMut) and p.kindAt(1) == tkRef):
		isMut = p.accept(tkMut)
		p.adv()
		te = p.mk(nTyRef, t.line, t.col)
		if isMut:
			p.nodes[te].ival = 1
		p.nodes[te].types.push(p.parseTypePrimary())
		return te
	if p.at(tkFn):
		p.adv()
		te = p.mk(nTyFn, t.line, t.col)
		p.expectTok(tkLparen)
		going = not p.at(tkRparen)
		while going:
			p.nodes[te].types.push(p.parseType())
			going = p.accept(tkComma) and not p.at(tkRparen)
		p.expectTok(tkRparen)
		if p.startsType():
			p.nodes[te].sub.push(p.parseType())
		return te
	if p.at(tkLparen):
		p.adv()
		te = p.mk(nTyName, t.line, t.col)
		if p.accept(tkRparen):
			p.nodes[te].text = "()"
			return te
		# (A, B): the tuple type Tuple2<A, B>; (A) alone groups, as in (i64[2])?
		going = true
		while going:
			p.nodes[te].types.push(p.parseType())
			going = p.accept(tkComma) and not p.at(tkRparen)
		p.expectTok(tkRparen)
		n = p.nodes[te].types.len
		if n == 1: return p.nodes[te].types[0]
		if n < 2 or n > 8:
			p.parseError(t, compileError("TupleTypeSize", []))
		p.nodes[te].text = "Tuple{n}"
		p.nodes[te].text2 = "$rt"   # the runtime's, whatever the program declares
		return te
	if not p.at(tkIdent) and not p.at(tkUident):
		p.parseError(t, compileError("ExpectedType", ["{tokKindName(p.kind())}"]))
	nameT = p.adv()
	te = p.mk(nTyName, nameT.line, nameT.col)
	if nameT.kind == tkIdent and p.at(tkDot) and p.kindAt(1) == tkUident:
		p.adv()
		p.nodes[te].text2 = nameT.text   # module.Type: the module, then the type's name
		p.nodes[te].text = p.adv().text
	else:
		p.nodes[te].text = nameT.text
	if p.at(tkLt) and p.nodes[te].text2 == "":
		p.refuseCollectionName(te)
	p.nodes[te].types = p.parseTypeArgs()
	te

# `List` and `Map` name the types `T[]` and `{K: V}` are made of: a program writing them names no type
fn refuseCollectionName(mut p Parser, named NodeId):
	name = p.nodes[named].text
	if name == "List" or name == "Map":
		at = Tok(kind = tkUident, text = "", line = p.nodes[named].line, col = p.nodes[named].col)
		p.parseError(at, compileError("UnknownType", [name.copy()]))

# the ? suffixes after a type: T? and T??, whose `??` the lexer reads as the one operator, so it
# counts as two
fn optionalsOf(mut p Parser, t NodeId):
	base = t
	while p.at(tkQuestion) or p.at(tkQq):
		q = p.adv()
		loop 2 if q.kind == tkQq else 1:
			opt = p.mk(nTyOpt, q.line, q.col)
			p.nodes[opt].types.push(base)
			base = opt
	base

# a type, or a result: `T ? E` (a T or an error E), `? E` when there is no value; an optional on
# the value's side is written in parentheses, `(T?) ? E`
# `T in a..b` (`..=` and an open end `a..` too): T's values in the range, else base
fn rangeOf(mut p Parser, base NodeId):
	if not p.at(tkIn): return base
	t = p.adv()
	te = p.mk(nTyRange, t.line, t.col)
	p.nodes[te].types.push(base)
	p.nodes[te].kids.push(p.parseRangeBound())
	if p.accept(tkDotdotEq):
		p.nodes[te].ival = 1
		p.nodes[te].kids.push(p.parseRangeBound())
	elif p.accept(tkDotdot):
		if p.at(tkInt) or p.at(tkMinus) or p.at(tkIdent):
			p.nodes[te].kids.push(p.parseRangeBound())
		else:
			p.nodes[te].ival = 2
	else:
		p.parseError(p.cur(), compileError("RangeTypeSpelling", []))
	te

# a range type's bound: an integer literal, negative too, or a constant's name
fn parseRangeBound(mut p Parser) NodeId:
	t = p.here()
	neg = p.accept(tkMinus)
	if p.at(tkInt):
		lit = p.adv()
		e = p.mk(nInt, lit.line, lit.col)
		p.nodes[e].text = "-{lit.text}" if neg else lit.text
		return e
	if p.at(tkIdent) and not neg:
		name = p.adv()
		e = p.mk(nIdent, name.line, name.col)
		p.nodes[e].text = name.text
		return e
	p.parseError(t, compileError("RangeTypeBound", []))
	p.mk(nInt, t.line, t.col)

fn parseType(mut p Parser):
	base = p.unitOkSide() if p.at(tkTernary) else p.optionalHead()
	if p.at(tkTernary):
		q = p.adv()
		res = p.mk(nTyResult, q.line, q.col)
		p.nodes[res].types.push(base)
		p.nodes[res].types.push(p.optionalsOf(p.parseTypePrimary()))
		base = res
	base

# `? E` (a result of no value): its ok side, ()
fn unitOkSide(mut p Parser):
	unit = p.mk(nTyName, p.cur().line, p.cur().col)
	p.nodes[unit].text = "()"
	unit

# a type's primary with its range and its optionals (an optional's result needs parentheses)
fn optionalHead(mut p Parser):
	primary = p.rangeOf(p.parseTypePrimary())
	head = p.optionalsOf(primary)
	if head != primary and p.at(tkTernary):
		p.parseError(p.cur(), compileError("OptionalResultParentheses", []))
	head

# ---------- expressions ----------

# `it`, or the `.` of `.hp`: a placeholder for the value of the call argument it stands in, which
# the checker makes a function of that value (placeholder.zap); the text says how it was written,
# for the message when no call argument holds it
fn placeholder(mut p Parser, t Tok, written str):
	e = p.mk(nIdent, t.line, t.col)
	p.nodes[e].text = written.copy()
	p.nodes[e].flags = flagPlaceholder
	e
