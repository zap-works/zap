# The parsing of conditions, ifs and statements, destructuring, assignments and for loops (parse.zap).

# whether the condition starting here tests a pattern (`is`) before its block's `:`
fn isTestAhead(p Parser):
	depth = 0
	i = p.pos
	while i < p.toks.len:
		k = p.toks[i].kind
		if k in [tkLparen, tkLbracket, tkLbrace]:
			depth += 1
		elif k in [tkRparen, tkRbracket, tkRbrace]:
			depth -= 1
		elif k == tkColon and depth == 0:
			return false
		elif k == tkIs and depth == 0:
			return true
		elif k == tkEof or k == tkNewline and depth == 0:
			return false
		i += 1
	false

# The operands of a condition joined by && that tests a pattern in one of them at least: each a
# value and the pattern it is tested with (none: a condition of its own). `opt is x && x.hp > 0`.
fn parseCondParts(mut p Parser):
	parts (NodeId, NodeId?)[] = []
	loop:
		e = p.parseLevel(3)
		if p.accept(tkIs):
			t = p.here()
			pat = p.parsePattern()
			k = p.nodes[pat].ival
			if k == patWildcard:
				p.parseError(t, compileError("IsBlank", []))
			elif k == patNone:
				p.parseError(t, compileError("IsNone", []))
			p.nodes[pat].flags |= flagIsTest
			parts.push((e, pat))
		else:
			parts.push((e, none))
		if not p.accept(tkAnd): break
	if p.at(tkOr):
		p.parseError(p.cur(), compileError("IsJoinedByOr", []))
	parts

# `if` parts `{ yes } else { no }` as statements: a run of plain conditions is an if, a pattern
# test a match whose other arm runs `no` (each level that can fail gets a copy of it). The names
# a pattern binds are seen by the parts after it and by `yes`.
fn condChain(
	mut p Parser,
	parts (NodeId, NodeId?)[],
	from i64,
	yes NodeId,
	no NodeId,
	t Tok
) NodeId:
	value, pat = parts[from]
	next = from + 1
	cond = value
	if pat == none:
		while next < parts.len:
			more, morePat = parts[next]
			if morePat != none: break
			cond = p.binNode(binAnd, cond, more, t)
			next += 1
	guard NodeId? = none   # the plain conditions after a pattern: its arm's condition, so that `no` runs outside the arm
	while pat != none and next < parts.len:
		more, morePat = parts[next]
		if morePat != none: break
		guard = more if guard == none else p.binNode(binAnd, guard ?? more, more, t)
		next += 1
	inner = yes
	if next < parts.len:
		inner = p.mk(nBlock, t.line, t.col)
		again = cloneTree(p.nodes, p.kidIds, no)
		p.nodes[again].setText("$again")   # checked as `no` is: without what the parts before narrowed
		chained = p.condChain(parts, next, yes, again, t)
		p.nodes[inner].pushKid(p.kidIds, chained)
	pattern = pat ?? return p.ifStmt(cond, inner, no, t)
	if guard is g: p.nodes[pattern].nodePart(p.kidIds).sub.push(g)
	m = p.mk(nMatch, t.line, t.col)
	p.nodes[m].pushKid(p.kidIds, value)
	hit = p.mk(nArm, p.nodes[pattern].line, p.nodes[pattern].col)
	p.nodes[hit].pushKid(p.kidIds, pattern)
	p.nodes[hit].nodePart(p.kidIds).sub.push(inner)
	p.nodes[m].pushKid(p.kidIds, hit)
	other = p.mk(nArm, t.line, t.col)
	wild = p.mk(nPattern, t.line, t.col)
	p.nodes[wild].ival = patWildcard
	p.nodes[other].pushKid(p.kidIds, wild)
	p.nodes[other].nodePart(p.kidIds).sub.push(no)
	p.nodes[m].pushKid(p.kidIds, other)
	st = p.mk(nExprStmt, t.line, t.col)
	p.nodes[st].pushKid(p.kidIds, m)
	st

# `if cond: yes else: no` as a statement
fn ifStmt(mut p Parser, cond NodeId, yes NodeId, no NodeId, t Tok):
	s = p.mk(nIf, t.line, t.col)
	p.nodes[s].pushKid(p.kidIds, cond)
	p.nodes[s].nodePart(p.kidIds).sub.push(yes)
	p.nodes[s].nodePart(p.kidIds).sub.push(no)
	s

# the `else` of an if, taken: right after its block, or on the next line after a block of one
# line (`if c: x` / `else: y`)
fn elseFollows(mut p Parser):
	if p.accept(tkElse): return true
	if p.at(tkNewline) and p.kindAt(1) == tkElse:
		p.adv()
		p.adv()
		return true
	false

# the `elif` of an if, ahead (not taken: parseIf takes it as its first token): right after the
# block, or on the next line after a block of one line
fn elifFollows(mut p Parser):
	if p.at(tkElif): return true
	if p.at(tkNewline) and p.kindAt(1) == tkElif:
		p.adv()
		return true
	false

fn parseIf(mut p Parser) NodeId:
	t = p.adv()
	if p.isTestAhead():
		# if s is Circle(r) && r > 1.0 { A } else { B }: match s { Circle(r) => { if r > 1.0
		# { A } else { B } }  _ => { B } }
		parts = p.parseCondParts()
		yes = p.parseBlock()
		no NodeId = 0
		if p.elifFollows():
			no = p.mk(nBlock, t.line, t.col)
			madeKid = p.parseIf()
			p.nodes[no].pushKid(p.kidIds, madeKid)
		elif p.elseFollows():
			no = p.parseBlock()
		else:
			no = p.mk(nBlock, t.line, t.col)
		chain = p.condChain(parts, 0, yes, no, t)
		p.nodes[chain].setText("$chain")   # where its copies of `no` start widening (checkBlock)
		return chain
	cond = p.parseExpr()
	s = p.mk(nIf, t.line, t.col)
	p.nodes[s].pushKid(p.kidIds, cond)
	p.nodes[s].nodePart(p.kidIds).sub.push(p.parseBlock())
	if p.elifFollows():
		b = p.mk(nBlock, t.line, t.col)
		madeKid = p.parseIf()
		p.nodes[b].pushKid(p.kidIds, madeKid)
		p.nodes[s].nodePart(p.kidIds).sub.push(b)
	elif p.elseFollows():
		p.nodes[s].nodePart(p.kidIds).sub.push(p.parseBlock())
	s

fn parseStmt(mut p Parser):
	was = p.valueAt
	p.valueAt = false   # a statement's header ends in `:` (`if ready:`): no lambda starts it
	s = p.parseStmtAt()
	p.valueAt = was
	s

fn parseStmtAt(mut p Parser) NodeId:
	t = p.here()
	if p.useAhead():
		p.parseError(p.cur(), compileError("UseNotFirst", []))
	if p.aliasAhead():
		p.parseAlias()
		s = p.mk(nBlock, t.line, t.col)
		p.nodes[s].setText("$splice")   # nothing to run (parseBlock adds no statement)
		return s

	if p.at(tkIdent) and p.kindAt(1) in [tkEq, tkIdent] and p.cur().text in circleWords:
		p.parseError(p.cur(), compileError("LanguageConstant", [p.cur().text.copy()]))
	if p.at(tkIt) and p.kindAt(1) in [tkEq, tkOpAssign]:
		p.parseError(p.cur(), compileError("ItIsNoName", []))
	if p.at(tkIdent) and p.kindAt(1) == tkEq and p.aliasOf(p.cur().text) >= 0:
		p.parseError(p.cur(), compileError("AliasRebound", ["{p.cur().text}"]))   # `name = v` would set what it names
	if p.passAhead([tkNewline, tkDedent, tkEof]):
		p.adv()
		s = p.mk(nBlock, t.line, t.col)
		p.nodes[s].setText("$splice")   # a block with nothing in it
		return s
	if p.inTest and p.caseAhead(): return p.testCase(t.line, t.col)
	if p.at(tkReturn):
		p.adv()
		s = p.mk(nReturn, t.line, t.col)
		if not p.at(tkNewline) and not p.at(tkDedent) and not p.at(tkEof):
			madeKid = p.valueExpr()
			p.nodes[s].pushKid(p.kidIds, madeKid)
		return s
	if p.at(tkYield):
		p.adv()
		s = p.mk(nYield, t.line, t.col)
		madeKid = p.parseExpr()
		p.nodes[s].pushKid(p.kidIds, madeKid)
		return s
	if p.at(tkIf): return p.parseIf()
	if p.at(tkIdent) and p.cur().text == arenaWord and p.kindAt(1) == tkColon:
		# arena: ...  ==  if true: ... with its allocations in a region of its own
		p.adv()
		s = p.mk(nIf, t.line, t.col)
		c = p.mk(nBool, t.line, t.col)
		p.nodes[c].ival = 1
		p.nodes[s].pushKid(p.kidIds, c)
		p.nodes[s].nodePart(p.kidIds).sub.push(p.parseBlock())
		p.nodes[s].flags |= flagArena
		return s
	if p.at(tkLoop):
		p.adv()
		if not p.at(tkColon):
			# loop n: ...  ==  for _ in 0..n: ...
			return p.countedLoop(t)
		# loop: ...  ==  while true: ...
		s = p.mk(nWhile, t.line, t.col)
		c = p.mk(nBool, t.line, t.col)
		p.nodes[c].ival = 1
		p.nodes[s].pushKid(p.kidIds, c)
		p.nodes[s].nodePart(p.kidIds).sub.push(p.parseBlock())
		return s
	if p.at(tkWhile): return p.parseStmtWhile(t)
	if p.at(tkFor): return p.parseStmtFor(t)
	if p.at(tkBreak):
		p.adv()
		return p.mk(nBreak, t.line, t.col)
	if p.at(tkContinue):
		p.adv()
		return p.mk(nContinue, t.line, t.col)
	if p.wordStatementAhead(expectWord):
		w = p.adv()
		return p.expectStmt(w)
	if p.inTest and p.wordStatementAhead(printsWord):
		w = p.adv()
		return p.printsStmt(w, p.parseExpr())
	if p.typedLetAhead():
		n = p.adv()
		s = p.mk(nLet, t.line, t.col)
		p.nodes[s].setText(n.text)
		p.nodes[s].nodePart(p.kidIds).types.push(p.parseType())
		if p.bareArrayDecl(s):
			return s   # a T[N]: the elements come by assignment
		p.expectTok(tkEq)
		madeKid = p.valueExpr()
		p.nodes[s].pushKid(p.kidIds, madeKid)
		return s
	p.parseStmtExpr(t)

fn parseStmtWhile(mut p Parser, t Tok):
	p.adv()
	s = p.mk(nWhile, t.line, t.col)
	if p.isTestAhead():
		# while q.pop() is v && v > 0 { A }  ==  loop { if q.pop() is v && v > 0 { A } else { break } }
		parts = p.parseCondParts()
		body = p.parseBlock()
		stop = p.mk(nBlock, t.line, t.col)
		madeKid = p.mk(nBreak, t.line, t.col)
		p.nodes[stop].pushKid(p.kidIds, madeKid)
		always = p.mk(nBool, t.line, t.col)
		p.nodes[always].ival = 1
		p.nodes[s].pushKid(p.kidIds, always)
		chained = p.condChain(parts, 0, body, stop, t)
		loopBody = p.mk(nBlock, t.line, t.col)
		p.nodes[loopBody].pushKid(p.kidIds, chained)
		p.nodes[s].nodePart(p.kidIds).sub.push(loopBody)
		return s
	cond = p.parseExpr()
	p.nodes[s].pushKid(p.kidIds, cond)
	p.nodes[s].nodePart(p.kidIds).sub.push(p.parseBlock())
	s

fn parseStmtFor(mut p Parser, t Tok):
	p.adv()
	s = p.mk(nFor, t.line, t.col)
	if p.accept(tkMut):
		p.nodes[s].flags |= flagMut   # `for mut x in xs`: x is the element, changed in place
	if not p.at(tkIdent) and not p.at(tkIt):
		# for (a, b) in xs, for Point(x, y) in ps: each element under a hidden name, its
		# parts read from it at the start of the body
		pattern = p.parsePostfix()
		if p.accept(tkComma): return p.forCells(s, pattern)
		p.nodes[s].setText("$elem{pattern}")
		p.expectTok(tkIn)
		madeKid = p.steppedRange(p.parseExpr())
		p.nodes[s].pushKid(p.kidIds, madeKid)
		body = p.parseBlock()
		p.readParts(t, pattern, p.nodes[s].text.copy(), body, 0)
		p.nodes[s].nodePart(p.kidIds).sub.push(body)
		return s
	fv = p.expectTok(tkIdent)
	p.notAlias(fv)
	p.nodes[s].setText(fv.text)
	if p.accept(tkComma):
		if p.nodes[s].hasFlag(flagMut):
			p.parseError(fv, compileError("MutLoopIndex", []))
		if not p.at(tkIdent) and not p.at(tkIt) and not p.at(tkMut):
			pattern = p.parsePostfix()
			hidden = Tok(kind = tkIdent, text = "$elem{pattern}", line = t.line, col = t.col)
			f = p.forIndexed(t, s, hidden)
			p.readParts(t, pattern, "$elem{pattern}", p.nodes[f].sub(p.kidIds)[0], 1)   # after the element's own binding
			return f
		changes = p.accept(tkMut)
		return p.forIndexed(t, s, p.expectTok(tkIdent), changes)
	p.expectTok(tkIn)
	range = p.steppedRange(p.parseExpr())
	if p.nodes[s].text == "_" and p.nodes[range].kind == nRange and
		p.nodes[range].kids(p.kidIds).len == 2 and
		p.nodes[p.nodes[range].kids(p.kidIds)[0]].kind == nInt and
		p.nodes[p.nodes[range].kids(p.kidIds)[0]].text == "0":
		p.parseError(t, compileError("LoopVariable", []))
	p.nodes[s].pushKid(p.kidIds, range)
	p.nodes[s].nodePart(p.kidIds).sub.push(p.parseBlock())
	s

fn parseStmtExpr(mut p Parser, t Tok):
	# a lambda alone on its line is a value (a function's result): `x: x + n`, `(): pass`
	e = p.parseLambda() if p.bareLambdaAhead() else p.parseExpr()
	if p.at(tkComma):
		e = p.bareTuple(t, e)   # a, b = ...: the names taken apart
	if (p.at(tkOpAssign) or p.at(tkEq)) and p.isBitPlace(e): return p.bitPlaceAssign(t, e)
	if p.at(tkOpAssign):
		op = p.adv()
		return p.compoundAssign(t, e, op, p.parseExpr())
	if p.accept(tkEq):
		val = p.tupleValue(t)
		ek = p.nodes[e].kind
		if ek == nIdent:
			s = p.mk(nLet, t.line, t.col)
			p.nodes[s].setText(p.nodes[e].takeText())   # the target node is dropped: the let replaces it
			p.nodes[s].pushKid(p.kidIds, val)
			return s
		if ek == nField or ek == nIndex:
			# the value is computed before the place's address: an index that calls a function
			# is computed first when the value calls one too, so they run as written
			first = []
			if nodeCalls(p.nodes, p.kidIds, e) and nodeCalls(p.nodes, p.kidIds, val):
				p.hoistIndexes(e, first)
			s = p.mk(nAssign, t.line, t.col)
			p.nodes[s].pushKid(p.kidIds, e)
			p.nodes[s].pushKid(p.kidIds, val)
			return p.spliceAfter(t, first, s)
		if ek == nStructLit and p.nodes[e].text.startsWith("Tuple") and
			not p.nodes[e].names(p.kidIds).isEmpty and p.nodes[e].names(p.kidIds)[0] == "_0":
			if not p.nodes[e].hasFlag(flagInternal):
				p.parseError(t, compileError("TupleTargetParentheses", []))
			return p.destructure(t, e, val)
		if p.isStructPattern(e): return p.destructure(t, e, val)
		p.parseError(t, compileError("InvalidTarget", []))
	s = p.mk(nExprStmt, t.line, t.col)
	p.nodes[s].pushKid(p.kidIds, e)
	s

# (a, b) = value: the value in a hidden mutable local, then a = move it._0, b = move it._1 (a
# `_` binds nothing); the statements are spliced into the enclosing block
# a value, or values with commas between them (a, b: a tuple without parentheses)
fn tupleValue(mut p Parser, t Tok):
	v = p.valueExpr()
	v = p.bareTuple(t, v) if p.at(tkComma) else v
	if p.at(tkEq): p.parseError(p.cur(), compileError("ChainedAssignment", []))
	v

# first, b, c: the tuple of the values (the parentheses left out), up to the end of the statement
fn bareTuple(mut p Parser, t Tok, first NodeId):
	e = p.mk(nStructLit, t.line, t.col)
	p.nodes[e].pushKid(p.kidIds, first)
	while p.accept(tkComma):
		madeKid = p.parseExpr()
		p.nodes[e].pushKid(p.kidIds, madeKid)
	n = p.nodes[e].kids(p.kidIds).len
	if n > 8:
		p.parseError(t, compileError("TupleTooLarge", []))
	p.nodes[e].setText("Tuple{n}")
	p.nodes[e].setText2(p.kidIds, "$rt")
	p.nodes[e].nodeMore(p.kidIds).names = (0..n).map("_{it}")
	p.nodes[e].flags |= flagInternal   # written bare: the form kept
	e

fn destructure(mut p Parser, t Tok, pattern NodeId, val NodeId):
	tmp = "$tuple{pattern}"
	out = p.mk(nBlock, t.line, t.col)
	p.nodes[out].setText("$splice")
	vk = p.nodes[val].kind
	if (vk == nField or vk == nIndex) and not nodeCalls(p.nodes, p.kidIds, val):
		# a part of a place, which naming again evaluates nothing: each name takes its part
		# from it as a binding of that part would (lent, or copied when plain); a variable is
		# taken apart below, its parts moved out
		for part in p.patternParts(t, pattern):
			bind = p.mk(nLet, t.line, t.col)
			p.nodes[bind].setText(part.name.copy())
			madeKid = p.partOf(t, cloneTree(p.nodes, p.kidIds, val), part)
			p.nodes[bind].pushKid(p.kidIds, madeKid)
			p.nodes[out].pushKid(p.kidIds, bind)
		return out
	hold = p.mk(nLet, t.line, t.col)
	p.nodes[hold].flags = flagMut
	p.nodes[hold].pushKid(p.kidIds, val)
	p.nodes[out].pushKid(p.kidIds, hold)
	parts = p.patternParts(t, pattern)
	for part in parts:
		base = p.mk(nIdent, t.line, t.col)
		p.nodes[base].setText(tmp.copy())   # each use of the hidden local names it
		field = p.partOf(t, base, part)
		taken = p.mk(nUnary, t.line, t.col)   # move tmp.k: the part leaves the hidden local
		p.nodes[taken].ival = unMove
		p.nodes[taken].pushKid(p.kidIds, field)
		bind = p.mk(nLet, t.line, t.col)
		p.nodes[bind].setText(part.name.copy())
		p.nodes[bind].pushKid(p.kidIds, taken)
		p.nodes[out].pushKid(p.kidIds, bind)
	p.nodes[hold].setText(tmp)
	out

# A part a pattern takes out: the name it binds, and where it is: a tuple's position or a
# struct's field, by name or by position (field "#k", resolved by the checker, which also checks
# that the value is of the pattern's type).
type Part:
	name str
	field str
	typeName str

# `Point(...)`, `geo.Point(...)`: a pattern of a struct, in front of `=` or after `for`
fn isStructPattern(p Parser, e NodeId):
	if p.nodes[e].kind != nCall: return false
	callee = p.nodes[e].kids(p.kidIds)[0]
	k = p.nodes[callee].kind
	if k != nIdent and k != nField: return false
	name = p.nodes[callee].text
	not name.isEmpty and name[0] >= 'A' and name[0] <= 'Z'

# the parts of a pattern: (a, b) a tuple's, Point(x, y) or Point(x = px) a struct's; `_` binds
# nothing
fn patternParts(mut p Parser, t Tok, pattern NodeId):
	out = []
	k = p.nodes[pattern].kind
	if k == nStructLit and p.nodes[pattern].text.startsWith("Tuple"):
		for i in 0..p.nodes[pattern].kids(p.kidIds).len:
			name = p.nodes[pattern].kids(p.kidIds)[i]
			if p.nodes[name].kind != nIdent:
				p.parseError(t, compileError("TupleTargetNames", []))
			if p.nodes[name].text != "_":
				out.push(Part(name = p.nodes[name].text.copy(), field = "_{i}", typeName = ""))
		return out
	if not p.isStructPattern(pattern):
		p.parseError(t, compileError("TargetPattern", []))
		return out
	callee = p.nodes[pattern].kids(p.kidIds)[0]
	typeName = p.nodes[callee].text.copy()
	for i in 1..p.nodes[pattern].kids(p.kidIds).len:
		arg = p.nodes[pattern].kids(p.kidIds)[i]
		if p.nodes[arg].kind == nNamedArg:
			# Point(x = px): the field x into px
			inner = p.nodes[arg].kids(p.kidIds)[0]
			if p.nodes[inner].kind != nIdent:
				p.parseError(t, compileError("StructTargetNames", []))
			if p.nodes[inner].text != "_":
				out.push(
					Part(
						name = p.nodes[inner].text.copy(),
						field = p.nodes[arg].text.copy(),
						typeName = typeName.copy()
					)
				)
			continue
		if p.nodes[arg].kind != nIdent:
			p.parseError(t, compileError("StructTargetPositions", []))
		if p.nodes[arg].text != "_":
			out.push(
				Part(
					name = p.nodes[arg].text.copy(),
					field = "#{i - 1}",
					typeName = typeName.copy()
				)
			)
	out

# base.field for a part (the struct's name noted on a positional field for the checker)
fn partOf(mut p Parser, t Tok, base NodeId, part Part):
	field = p.mk(nField, t.line, t.col)
	p.nodes[field].pushKid(p.kidIds, base)
	p.nodes[field].setText(part.field.copy())
	p.nodes[field].setText2(p.kidIds, part.typeName.copy())
	field

# The parts of a loop's element (named `elem`) bound at the start of the body (from statement
# `first`), read from it:
# a borrowed element lends its parts, plain data copies.
fn readParts(mut p Parser, t Tok, pattern NodeId, elem str, body NodeId, first i64):
	parts = p.patternParts(t, pattern)
	for i in 0..parts.len:
		base = p.mk(nIdent, t.line, t.col)
		p.nodes[base].setText(elem.copy())
		bind = p.mk(nLet, t.line, t.col)
		p.nodes[bind].setText(parts[i].name.copy())
		madeKid = p.partOf(t, base, parts[i])
		p.nodes[bind].pushKid(p.kidIds, madeKid)
		p.nodes[body].insertKid(p.kidIds, first + i, bind)

# `x.bit(n)` or `x.bits(from, count)` as an assignment's target
fn isBitPlace(p Parser, e NodeId):
	if p.nodes[e].kind != nCall: return false
	callee = p.nodes[e].kids(p.kidIds)[0]
	p.nodes[callee].kind == nField and p.nodes[callee].kids(p.kidIds).len == 1 and
		(p.nodes[callee].text == "bit" and p.nodes[e].kids(p.kidIds).len == 2 or
				p.nodes[callee].text == "bits" and p.nodes[e].kids(p.kidIds).len == 3)

# x.bit(n) = on is x = x.withBit(n, on), x.bits(from, count) = v is x = x.withBits(from, count, v)
# (op= reads them first): x is written twice, so an index in it that calls a function is
# computed once first, as for op=
fn bitPlaceAssign(mut p Parser, t Tok, place NodeId) NodeId:
	callee = p.nodes[place].kids(p.kidIds)[0]
	first = []
	if nodeCalls(p.nodes, p.kidIds, p.nodes[callee].kids(p.kidIds)[0]):
		p.hoistIndexes(p.nodes[callee].kids(p.kidIds)[0], first)
	val = NodeId(0)
	if p.at(tkOpAssign):
		op = p.adv()
		val = p.mk(nBinary, op.line, op.col)
		p.nodes[val].ival = i32(binaryCode(op.text))
		madeKid = cloneTree(p.nodes, p.kidIds, place)
		p.nodes[val].pushKid(p.kidIds, madeKid)
		madeKid = p.parseExpr()
		p.nodes[val].pushKid(p.kidIds, madeKid)
	else:
		p.expectTok(tkEq)
		val = p.parseExpr()
	x = p.nodes[callee].kids(p.kidIds)[0]
	k = p.nodes[x].kind
	if k != nIdent and k != nField and k != nIndex or nodeCalls(p.nodes, p.kidIds, x):
		p.parseError(t, compileError("InvalidTarget", []))
	p.nodes[callee].setText("withBit" if p.nodes[callee].text == "bit" else "withBits")
	p.nodes[place].pushKid(p.kidIds, val)
	p.nodes[place].flags |= flagInternal   # the value first (irBitField)
	s = p.mk(nLet if k == nIdent else nAssign, t.line, t.col)
	if k == nIdent:
		p.nodes[s].setText(p.nodes[x].text.copy(), p.nodes[x].name)
	else:
		madeKid = cloneTree(p.nodes, p.kidIds, x)
		p.nodes[s].pushKid(p.kidIds, madeKid)
	p.nodes[s].pushKid(p.kidIds, place)
	p.spliceAfter(t, first, s)

# x op= v is x = x op v: the target is written twice, so an index that calls a function is
# computed once first, into a hidden local (`xs[f()] += 1` is `$i = f()` then `xs[$i] += 1`);
# a target whose place itself comes from a call (`f()[0] += 1`) is an error: it changes a
# temporary
fn compoundAssign(mut p Parser, t Tok, target NodeId, op Tok, val NodeId) NodeId:
	k = p.nodes[target].kind
	if k != nIdent and k != nField and k != nIndex:
		p.parseError(op, compileError("InvalidTarget", []))
	first = []
	if nodeCalls(p.nodes, p.kidIds, target):
		p.hoistIndexes(target, first)
		if nodeCalls(p.nodes, p.kidIds, target):
			parseError(
				p,
				op,
				compileError("CompoundOnCall", ["{op.text}"])
			)
	s = p.compoundAssignOnce(t, target, op, val, k)
	p.spliceAfter(t, first, s)

# the statement s after the statements `first`, spliced into the enclosing block; s alone when
# there are none
fn spliceAfter(mut p Parser, t Tok, first NodeId[], s NodeId):
	if first.isEmpty: return s
	out = p.mk(nBlock, t.line, t.col)
	p.nodes[out].setText("$splice")
	p.nodes[out].extendKids(p.kidIds, first)
	p.nodes[out].pushKid(p.kidIds, s)
	out

# each index along the place e that calls a function replaced by a hidden local bound to it,
# the binding pushed on `first`, outermost place first (`g[f()][h()]` computes f, then h)
fn hoistIndexes(mut p Parser, e NodeId, mut first NodeId[]):
	k = p.nodes[e].kind
	if k == nIndex or k == nField:
		p.hoistIndexes(p.nodes[e].kids(p.kidIds)[0], first)
	if k == nIndex:
		index = p.nodes[e].kids(p.kidIds)[1]
		if nodeCalls(p.nodes, p.kidIds, index):
			name = "$index{index}"
			bind = p.mk(nLet, p.nodes[index].line, p.nodes[index].col)
			p.nodes[bind].setText(name.copy())
			p.nodes[bind].pushKid(p.kidIds, index)
			first.push(bind)
			named = p.mk(nIdent, p.nodes[index].line, p.nodes[index].col)
			p.nodes[named].setText(name)
			p.nodes[e].setKid(p.kidIds, 1, named)

fn compoundAssignOnce(mut p Parser, t Tok, target NodeId, op Tok, val NodeId, k i64):
	b = p.mk(nBinary, op.line, op.col)
	p.nodes[b].ival = i32(binaryCode(op.text))
	p.nodes[b].flags = flagCompound
	madeKid = cloneTree(p.nodes, p.kidIds, target)
	p.nodes[b].pushKid(p.kidIds, madeKid)
	p.nodes[b].pushKid(p.kidIds, val)
	if k == nIdent:
		s = p.mk(nLet, t.line, t.col)
		p.nodes[s].setText(p.nodes[target].takeText())   # the target is dropped (b reads a clone of it)
		p.nodes[s].flags = flagCompound
		p.nodes[s].pushKid(p.kidIds, b)
		return s
	s = p.mk(nAssign, t.line, t.col)
	p.nodes[s].ival = 1   # compound: the place exists already
	p.nodes[s].flags = flagCompound
	p.nodes[s].pushKid(p.kidIds, target)
	p.nodes[s].pushKid(p.kidIds, b)
	s

# for i, x in xs { ... } is for i in 0..xs.len { x = ref xs[i]  ... }: the list is a variable or
# a field of one, so naming it twice evaluates nothing twice; a list made there (a literal, a
# call's) is bound to a hidden name first, the loop in a block with it
# (changes: `for i, mut x in xs`, x lent `mut ref`)
fn forIndexed(mut p Parser, t Tok, s NodeId, move elemName Tok, changes bool = false):
	p.expectTok(tkIn)
	xs = p.parseExpr()
	root = xs
	while p.nodes[root].kind == nField:
		root = p.nodes[root].kids(p.kidIds)[0]
	made NodeId? = none
	if p.nodes[root].kind != nIdent:
		k = p.nodes[xs].kind
		if k in [nIndex, nField, nDeref]:
			p.parseError(t, compileError("ForIndexNeedsPlace", []))
		bound = p.mk(nLet, t.line, t.col)
		p.nodes[bound].setText("$each{t.line}_{t.col}")
		p.nodes[bound].pushKid(p.kidIds, xs)
		xs = p.mk(nIdent, t.line, t.col)
		p.nodes[xs].setText(p.nodes[bound].text.copy(), p.nodes[bound].name)
		made = bound
	zero = p.mk(nInt, t.line, t.col)
	p.nodes[zero].setText("0")
	lenC = lenOf(p.nodes, p.kidIds, t.line, t.col, cloneTree(p.nodes, p.kidIds, xs))
	r = p.mk(nRange, t.line, t.col)
	p.nodes[r].pushKid(p.kidIds, zero)
	p.nodes[r].pushKid(p.kidIds, lenC)
	p.nodes[s].pushKid(p.kidIds, r)
	body = p.parseBlock()
	idx = p.mk(nIdent, t.line, t.col)
	p.nodes[idx].setText(p.nodes[s].text.copy(), p.nodes[s].name)   # the loop keeps its variable's name too
	at = p.mk(nIndex, t.line, t.col)
	p.nodes[at].pushKid(p.kidIds, xs)
	p.nodes[at].pushKid(p.kidIds, idx)
	borrow = p.mk(nUnary, t.line, t.col)
	p.nodes[borrow].ival = unMutRef if changes else unRef
	p.nodes[borrow].pushKid(p.kidIds, at)
	bind = p.mk(nLet, elemName.line, elemName.col)
	p.nodes[bind].setText(elemName.text)
	p.nodes[bind].flags = flagInternal
	p.nodes[bind].pushKid(p.kidIds, borrow)
	p.nodes[body].insertKid(p.kidIds, 0, bind)
	p.nodes[s].nodePart(p.kidIds).sub.push(body)
	p.nodes[s].flags |= flagInternal
	hidden = made ?? return s
	# `if true { $each = list  for ... }`: the hidden name lives as long as the loop
	always = p.mk(nBool, t.line, t.col)
	p.nodes[always].ival = 1
	scope = p.mk(nBlock, t.line, t.col)
	p.nodes[scope].pushKid(p.kidIds, hidden)
	p.nodes[scope].pushKid(p.kidIds, s)
	wrap = p.mk(nIf, t.line, t.col)
	p.nodes[wrap].pushKid(p.kidIds, always)
	p.nodes[wrap].nodePart(p.kidIds).sub.push(scope)
	wrap

# for (x, y), v in g: the cells of a Grid with their coordinates, the names of x and y in the
# loop's names (the checker's forGridCells)
fn forCells(mut p Parser, s NodeId, pattern NodeId):
	kids = p.nodes[pattern].kids(p.kidIds).copy()
	if p.nodes[pattern].kind != nStructLit or p.nodes[pattern].text != "Tuple2" or
		kids.any(p.nodes[it].kind != nIdent):
		p.parseError(p.cur(), compileError("GridForSpelling", []))
		return s
	names = kids.map(p.nodes[it].text.copy())
	p.nodes[s].nodeMore(p.kidIds).names = names
	p.nodes[s].setText(p.expectTok(tkIdent).text)
	p.expectTok(tkIn)
	madeKid = p.parseExpr()
	p.nodes[s].pushKid(p.kidIds, madeKid)
	p.nodes[s].nodePart(p.kidIds).sub.push(p.parseBlock())
	s

# `(a..b).by(s)` in a for: the range a..b with the step s as its third child
fn steppedRange(mut p Parser, e NodeId):
	if p.nodes[e].kind != nCall or p.nodes[e].kids(p.kidIds).len != 2: return e
	callee = p.nodes[e].kids(p.kidIds)[0]
	if p.nodes[callee].kind != nField or p.nodes[callee].text != "by" or
		p.nodes[p.nodes[callee].kids(p.kidIds)[0]].kind != nRange:
		return e
	p.parseError(p.cur(), compileError("RangeStepWord", []))
	r = p.nodes[callee].kids(p.kidIds)[0]
	p.nodes[r].pushKid(p.kidIds, p.nodes[e].kids(p.kidIds)[1])
	r

# a register array declared without values: its type, then the end of the statement
fn bareArrayDecl(p Parser, s NodeId):
	# the statement ends at a newline, which a type closing with `>` has let the lexer swallow
	# (Simd<4, f64>): the next token is then on a later line
	ends = p.at(tkNewline) or p.at(tkDedent) or p.cur().line > p.toks[p.pos - 1].line
	not p.nodes[s].types(p.kidIds).isEmpty and
		p.nodes[p.nodes[s].types(p.kidIds)[0]].kind == nTyArray and ends
