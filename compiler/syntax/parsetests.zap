# The parsing of tests, uses, blocks and aliases (parse.zap).

# test "name": ... | test "name" for x in cases: ... (each element a case of its own) | test
# "name" refuses Name: ... (source the compiler must refuse with that error) | test "name" stops
# Name: ... (a program that must stop on that error). The body after refuses or stops is source
# kept as text (tkRawBlock); in a test's body, `refuses Name:` and `stops Name:` are such
# sources too, each a case of its own (the test's kids).
fn parseTestDecl(mut p Parser):
	t = p.adv()
	d = p.mk(nTestDecl, t.line, t.col)
	p.nodes[d].text = p.expectTok(tkStr).text
	word = p.cur().text.copy() if p.at(tkIdent) else ""
	if keepsSource(word):
		p.adv()
		p.sourceTest(d, word)
		return d
	outer = p.inTest
	p.inTest = true
	p.testPrints = false
	p.testDecl = d
	body = p.testCases(d) if p.at(tkFor) else p.optionsBody(d)
	p.inTest = outer
	if p.testPrints:
		p.nodes[d].ival = 1
	p.expandRegArrays(body, [])
	p.nodes[d].nodePart().sub.push(body)
	d

# whether a case of a test's body is ahead: `refuses Name:` or `stops Name:`
fn caseAhead(p Parser):
	p.at(tkIdent) and p.cur().text in caseWords and p.kindAt(1) == tkUident

# a case of the test being parsed, kept as its kid (its report names its line); nothing to run
fn testCase(mut p Parser, line i64, col i64):
	word = p.adv().text.copy()
	c = p.mk(nTestDecl, line, col)
	p.nodes[c].text = p.nodes[p.testDecl].text.copy()
	p.sourceTest(c, word)
	p.nodes[c].nodePart().names[1] = "{p.nodes[c].names()[1]}, line {line}"
	p.nodes[p.testDecl].kids.push(c)
	s = p.mk(nBlock, line, col)
	p.nodes[s].text = "$splice"
	s

# the error after the word (refuses, stops) and the source kept as text: names[0] the source,
# names[1] the header as written
fn sourceTest(mut p Parser, d NodeId, word str):
	shown = p.errorHeader(d, word)
	p.nodes[d].nodePart().names.push(p.expectTok(tkRawBlock).text)
	p.nodes[d].nodePart().names.push(shown)

# `Name`, or `Name("text")` with a part of its message, after refuses or stops: the kind (ival 2
# refused, 3 stops) and what the compiler or the program must say (text2); the header as written,
# for a failure's report
fn errorHeader(mut p Parser, d NodeId, word str):
	refuses = word == refusesWord
	name = p.expectTok(tkUident)
	said = ""
	if p.accept(tkLparen):
		said = p.expectTok(tkStr).text
		p.expectTok(tkRparen)
	shown = "{word} {name.text}" if said == "" else "{word} {name.text}(\"{said}\")"
	if refuses:
		if not isCompileError(name.text):
			p.parseError(
				name,
				compileError("UnknownCompileError", ["{name.text}", "{compileErrorNames()}"])
			)
		if said != "":
			p.nodes[d].nodePart().names2.push(said)
		p.nodes[d].ival = 2
		p.nodes[d].setText2("error[{kebabCase(name.text)}]")
		return shown
	known = runtimeErrors()
	for (errorName, code) in known:
		if errorName == name.text:
			if said != "" and name.text != "Failure":
				p.parseError(name, compileError("RuntimeErrorMessage", ["{name.text}"]))
			p.nodes[d].ival = 3
			p.nodes[d].setText2("error[{code}]" if said == "" else "error[{code}]: {said}")
			return shown
	names = []
	for (errorName, _) in known:
		names.push(errorName.copy())
	p.parseError(name, compileError("UnknownRuntimeError", ["{name.text}", "{names.join(", ")}"]))
	""

# ---------- use: a scope's options ----------
# `use name, name` as the first line of a file (after its imports), a function or a block sets
# the scope's options (options.zap: each name a flag) to the scope's end, blocks inside included;
# anywhere else it is an error, so a scope's options are read at its top. A block's flags are on
# its node, a function's on its declaration (the file's included).

fn useAhead(p Parser):
	p.at(tkIdent) and p.cur().text == useWord and p.kindAt(1) == tkIdent

# the flags of the option names after `use`, consumed
fn parseUse(mut p Parser):
	p.adv()   # use
	flags = 0
	more = true
	while more:
		t = p.expectTok(tkIdent)
		f = optionFlag(t.text)
		if f == 0:
			parseError(
				p,
				t,
				compileError("UnknownOption", ["{t.text}", "{options.join(", ")}"])
			)
		flags |= f
		more = p.accept(tkComma)
	flags

# a test's body of cases, `test "name": for ...` (d the test)
fn testCases(mut p Parser, d NodeId):
	at = p.here()
	cases = p.parseStmt()
	if p.nodes[cases].kind != nFor:
		p.parseError(at, compileError("TestCases", []))
	p.nodes[d].setText2("for")
	body = p.mk(nBlock, at.line, at.col)
	p.nodes[body].kids.push(cases)
	p.nodes[d].flags |= p.fileOptions
	body

# the body of function (or test) f: its options are the file's and its first line's, and
# flagOptionBlocks when a block inside it has a `use` line
fn optionsBody(mut p Parser, f NodeId):
	outer = p.blockOptions
	p.blockOptions = false
	body = p.parseBlock()
	flags = p.fileOptions | (p.nodes[body].flags & flagOptions)
	p.nodes[f].flags |= flags
	if p.blockOptions:
		p.nodes[f].flags |= flagOptionBlocks
	p.blockOptions = outer
	body

# `prints text` in a test: the output since the last check compared with text
fn printsStmt(mut p Parser, t Tok, text NodeId) NodeId:
	p.testPrints = true
	where = p.whereText(t)
	internalCallStmt(p.nodes, "testPrints", [text, where], t.line, t.col)

# "file:line" of t, a string literal
fn whereText(mut p Parser, t Tok):
	where = p.mk(nStr, t.line, t.col)
	p.nodes[where].text = "{p.file}:{t.line}"
	where

# whether the line is a statement led by the word (`expect cond`, `prints text`): something
# follows it on the line that a name would not take (not `expect = 1`, `prints(x)`, `expect.x`)
fn wordStatementAhead(p Parser, word str):
	if not (p.at(tkIdent) and p.cur().text == word) or p.pos + 1 >= p.toks.len: return false
	next = p.toks[p.pos + 1]
	if next.line != p.cur().line: return false
	if next.kind == tkLparen and next.col == p.cur().col + word.len: return false
	next.kind not in [
		tkEq,
		tkOpAssign,
		tkDot,
		tkComma,
		tkColon,
		tkNewline,
		tkDedent,
		tkEof,
		tkRparen
	]

# whether evaluating e calls something or gives a value away: it must happen once
fn callsOrMoves(p Parser, e NodeId) bool:
	k = p.nodes[e].kind
	k == nCall or k == nUnary and p.nodes[e].ival == unMove or
		p.nodes[e].kids.any(p.callsOrMoves(it))

# whether the word `pass` stands here as the empty block: alone, one of the tokens `ends` after it
# (a value named pass is read as any name)
fn passAhead(p Parser, ends i64[]):
	p.at(tkIdent) and p.cur().text == passWord and p.kindAt(1) in ends

# the rest of `loop n: ...` after its word: a for over 0..n with no variable
fn countedLoop(mut p Parser, t Tok):
	s = p.mk(nFor, t.line, t.col)
	p.nodes[s].text = "_"
	zero = p.mk(nInt, t.line, t.col)
	p.nodes[zero].text = "0"
	r = p.mk(nRange, t.line, t.col)
	p.nodes[r].kids.push(zero)
	p.nodes[r].kids.push(p.parseExpr())
	p.nodes[s].kids.push(r)
	p.nodes[s].nodePart().sub.push(p.parseBlock())
	s

# `:` then a block: the statements of the lines indented after it, or one statement on the line
fn parseBlock(mut p Parser) NodeId:
	c = p.expectTok(tkColon)
	p.parseBody(c.line, c.col)

# the block after a `:` already taken
fn parseBody(mut p Parser, line i64, col i64):
	b = p.mk(nBlock, line, col)
	scope = p.aliases.len   # the block's own aliases end with it
	if p.at(tkNewline):
		p.openIndented()
		if p.useAhead():
			flags = p.parseUse()
			p.nodes[b].flags |= flags
			p.blockOptions = true
			p.skipNL()
		while not p.at(tkDedent) and not p.at(tkEof):
			p.addStmt(b, p.parseStmt())
			p.skipNL()
		p.expectTok(tkDedent)
	else:
		p.addStmt(b, p.parseStmt())
	p.aliases.truncate(scope)
	b

# the line's end and the indent that start a block's lines (the lexer saw the `:` end a line)
fn openIndented(mut p Parser):
	if not p.at(tkNewline):
		parseError(
			p,
			p.cur(),
			compileError("ExpectedLineEnd", [])
		)
	p.adv()
	p.expectTok(tkIndent)
	p.skipNL()

# statement st added to block b (a `$splice` block gives its statements, maybe none)
fn addStmt(mut p Parser, b NodeId, st NodeId):
	if p.nodes[st].kind == nBlock and p.nodes[st].text == "$splice":
		p.nodes[b].kids.extend(p.nodes[st].kids)
	else:
		p.nodes[b].kids.push(st)

# ---------- aliases ----------
# `alias name = expr`, in a block (to its end) or at a file's top level (to the file's end, not
# the module's): every later `name` standing for a value is expr written again there, read where
# it is used (so `alias nodes = g.c.nodes` holds no borrow of g). Its name names nothing else.

fn aliasAhead(p Parser):
	p.at(tkIdent) and p.cur().text == "alias" and p.kindAt(1) == tkIdent and p.kindAt(2) == tkEq

fn parseAlias(mut p Parser):
	p.adv()
	n = p.adv()
	if p.aliasOf(n.text) >= 0:
		p.parseError(n, compileError("AlreadyAlias", ["{n.text}"]))
	p.adv()
	p.aliases.push(ParsedAlias(n.text.copy(), p.parseExpr()))

# the place of the alias named nm in p.aliases, the innermost, or -1
fn aliasOf(p Parser, nm str):
	i = p.aliases.len - 1
	while i >= 0:
		if p.aliases[i].name == nm: return i
		i -= 1
	-1

# alias i written again where t names it (its nodes placed at t, for the messages)
fn expandAlias(mut p Parser, i i64, t Tok):
	e = cloneTree(p.nodes, p.aliases[i].expr)
	p.placeAt(e, t.line, t.col)
	e

fn placeAt(mut p Parser, e NodeId, line i64, col i64):
	p.nodes[e].line = i32(line)
	p.nodes[e].col = nodeCol(col)
	for i in 0..p.nodes[e].kids.len:
		p.placeAt(p.nodes[e].kids[i], line, col)

# a name a statement or a parameter binds: one an alias has is an error
fn notAlias(mut p Parser, t Tok):
	if p.aliasOf(t.text) >= 0:
		p.parseError(t, compileError("AliasRebound", ["{t.text}"]))

# ---------- declarations ----------
