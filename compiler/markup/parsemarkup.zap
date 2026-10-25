# The markup of a .zapx file parsed (spec 7.11): each element the call of std/zapx that builds
# it, a component the call of its function. A value in braces is the checker's to make a node
# or an attribute of, by its type (checkmarkup.zap).

markupModule = "zapx"
markupChildCall = "$markupChild"   # {value} among children: kids [callee, value]
markupAttrCall = "$markupAttr"   # name={value} of an element: kids [callee, name, value]

# a markup's body after `:` in braces (`{for x in xs: ...}`): an expression, or a block whose
# last expression is its value
type MarkupBody:
	node NodeId
	block bool

# the call of std/zapx's function name, by its global name (a local of that name hides nothing)
fn markupCall(mut p Parser, name str, line i64, col i64):
	g = p.mk(nIdent, line, col)
	p.nodes[g].text = globalAlias
	callee = p.mk(nField, line, col)
	p.nodes[callee].kids.push(g)
	p.nodes[callee].text = "{prefixFor(markupModule)}{name}"
	call = p.mk(nCall, line, col)
	p.nodes[call].kids.push(callee)
	call

# a value the checker makes a child or an attribute of (markupChildCall, markupAttrCall)
fn markupValue(mut p Parser, kind str, args NodeId[], line i64, col i64):
	callee = p.mk(nIdent, line, col)
	p.nodes[callee].text = kind.copy()
	call = p.mk(nCall, line, col)
	p.nodes[call].kids.push(callee)
	p.nodes[call].kids.extend(args)
	call

# `<tag ...>children</tag>`, `<tag ... />`, `<>children</>` or `<Component ... />`
fn parseMarkup(mut p Parser) NodeId:
	open = p.adv()
	if isComponent(open.text): return p.parseComponent(open)
	attrs = p.mk(nArray, open.line, open.col)
	names = []
	while p.at(tkMarkAttr):
		a = p.adv()
		p.noRepeat(names, a)
		p.nodes[attrs].kids.push(p.elementAttr(a))
	kids = p.markupKids()
	if open.text == "":
		call = p.markupCall("fragment", open.line, open.col)
		p.nodes[call].kids.push(kids)
		return call
	call = p.markupCall("element", open.line, open.col)
	p.nodes[call].kids.push(p.textNode(open, open.text))
	p.nodes[call].kids.push(attrs)
	p.nodes[call].kids.push(kids)
	call

# an attribute's name not given before in its tag
fn noRepeat(mut p Parser, mut names str[], a Tok):
	if a.text in names:
		p.parseError(a, compileError("MarkupDuplicateAttribute", [a.text.copy()]))
	names.push(a.text.copy())

# an element's attribute: bare (true), a string, or a value in braces
fn elementAttr(mut p Parser, a Tok) NodeId:
	name = p.textNode(a, a.text)
	if not p.accept(tkEq):
		call = p.markupCall("flag", a.line, a.col)
		on = p.mk(nBool, a.line, a.col)
		p.nodes[on].ival = 1
		p.nodes[call].kids.push(name)
		p.nodes[call].kids.push(on)
		return call
	if p.at(tkStr) or p.at(tkStrBegin):
		call = p.markupCall("attr", a.line, a.col)
		p.nodes[call].kids.push(name)
		p.nodes[call].kids.push(p.parsePrimary())
		return call
	p.markupValue(markupAttrCall, [name, p.attrBraced(a)], a.line, a.col)

# the value in braces after an attribute's `=`
fn attrBraced(mut p Parser, a Tok):
	p.expectTok(tkLbrace)
	p.skipNL()
	e = p.parseExpr()
	p.skipNL()
	p.expectTok(tkRbrace)
	e

# the children up to the closing tag (which the lexer matched), none after `/>`: a list
fn markupKids(mut p Parser) NodeId:
	t = p.here()
	kids = p.mk(nArray, t.line, t.col)
	if p.accept(tkMarkSelfClose): return kids
	p.expectTok(tkMarkTagEnd)
	while p.before(tkMarkClose):
		k = p.here()
		if p.at(tkMarkText):
			call = p.markupCall("text", k.line, k.col)
			tt = p.adv()
			p.nodes[call].kids.push(p.textNode(tt, tt.text))
			p.nodes[kids].kids.push(call)
		elif p.at(tkMarkOpen):
			p.nodes[kids].kids.push(p.parseMarkup())
		else:
			p.nodes[kids].kids.push(p.markupChild())
	p.adv()
	kids

# `{value}` among children: a value, a `for` giving a child for each element, an `if`
fn markupChild(mut p Parser) NodeId:
	lb = p.expectTok(tkLbrace)
	p.skipNL()
	was = p.valueAt
	p.valueAt = not (p.at(tkFor) or p.at(tkIf))   # (their headers end in `:`, as a statement's)
	e = p.markupFor() if p.at(tkFor) else p.markupIf() if p.at(tkIf) else p.parseExpr()
	p.valueAt = was
	p.skipNL()
	p.expectTok(tkRbrace)
	p.markupValue(markupChildCall, [e], lb.line, lb.col)

# `for x in xs: body`: xs.map(x: body), each body a node
fn markupFor(mut p Parser):
	t = p.adv()
	n = p.expectTok(tkIdent)
	if not p.at(tkIn): p.parseError(p.cur(), compileError("MarkupForName", []))
	p.adv()
	walked = p.parseExpr()
	body = p.markupBody()
	lam = p.mk(nLambda, t.line, t.col)
	p.nodes[lam].nodePart().names.push(n.text)
	p.nodes[lam].nodePart().types.push(p.mk(nTyAbsent, n.line, n.col))
	if body.block:
		p.nodes[lam].nodePart().sub.push(body.node)
	else:
		p.nodes[lam].kids.push(body.node)
	step = p.mk(nField, t.line, t.col)
	p.nodes[step].kids.push(walked)
	p.nodes[step].text = "map"
	call = p.mk(nCall, t.line, t.col)
	p.nodes[call].kids.push(step)
	p.nodes[call].kids.push(lam)
	call

# `if c: a`, `elif d: b`, `else: e`: a choice between nodes, nothing when no branch is taken;
# its condition as a statement's, a pattern's test among its parts (`if user is name:`)
fn markupIf(mut p Parser) NodeId:
	t = p.adv()
	parts = []
	if p.isTestAhead():
		parts = p.parseCondParts()
	else:
		parts.push((p.parseExpr(), none))
	yes = p.markupBody()
	p.skipNL()
	no = MarkupBody(node = p.markupCall("empty", t.line, t.col), block = false)
	if p.at(tkElif):
		no = MarkupBody(node = p.markupIf(), block = false)
	elif p.accept(tkElse):
		no = p.markupBody()
	p.choiceChain(parts, 0, yes, no, t)

# the parts of a condition from `from` on as a value: a run of plain conditions a choice, a
# pattern's test a match, `no` at each level that can fail (condChain's, as values)
fn choiceChain(
	mut p Parser,
	parts (NodeId, NodeId?)[],
	from i64,
	yes MarkupBody,
	no MarkupBody,
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
	inner = yes
	if next < parts.len:
		again = MarkupBody(..no, node = cloneTree(p.nodes, no.node))
		inner = MarkupBody(node = p.choiceChain(parts, next, yes, again, t), block = false)
	pattern = pat ?? return p.choice(cond, inner, no, t)
	m = p.mk(nMatch, t.line, t.col)
	p.nodes[m].kids.push(value)
	p.nodes[m].kids.push(p.armOf(pattern, inner))
	wild = p.mk(nPattern, t.line, t.col)
	p.nodes[wild].ival = patWildcard
	p.nodes[m].kids.push(p.armOf(wild, no))
	m

# `yes if cond else no`, either a block
fn choice(mut p Parser, cond NodeId, yes MarkupBody, no MarkupBody, t Tok):
	m = p.ifValueNode(cond, yes.node, no.node, t.line, t.col)
	p.blockArm(p.nodes[m].kids[1], yes)
	p.blockArm(p.nodes[m].kids[2], no)
	m

fn armOf(mut p Parser, pattern NodeId, body MarkupBody):
	arm = p.mk(nArm, p.nodes[pattern].line, p.nodes[pattern].col)
	p.nodes[arm].kids.push(pattern)
	p.nodes[arm].kids.push(body.node)
	p.blockArm(arm, body)
	arm

# an arm whose body is a block: the block is its sub, as a match's arm written so
fn blockArm(mut p Parser, arm NodeId, body MarkupBody):
	if not body.block: return
	p.nodes[arm].kids.pop()
	p.nodes[arm].nodePart().sub.push(body.node)

# `: body` of a markup `for` or `if`, its value made a node: on the line, or a block below
fn markupBody(mut p Parser):
	c = p.expectTok(tkColon)
	if not p.at(tkNewline):
		e = p.parseExpr()
		return MarkupBody(node = p.markupValue(markupChildCall, [e], c.line, c.col), block = false)
	b = p.parseBody(c.line, c.col)
	last = p.nodes[b].kids.last ?? return MarkupBody(node = b, block = true)
	if p.nodes[last].kind == nExprStmt and p.nodes[last].kids.len == 1:
		value = p.nodes[last].kids[0]
		wrapped = p.markupValue(markupChildCall, [value], p.nodes[value].line, p.nodes[value].col)
		if p.nodes[b].kids.len == 1: return MarkupBody(node = wrapped, block = false)
		p.nodes[last].kids[0] = wrapped
	MarkupBody(node = b, block = true)

# whether a tag names a component: a capital letter starts it, or its name after a module's
# (`ui.Card`)
fn isComponent(tag str):
	name = tag[(tag.lastIndexOf(".") ?? -1) + 1..]
	name != "" and name[0].isUpper()

# `<Stat s={x} />`: the call Stat(s = x), its attributes the named arguments and the content
# between its tags the argument children, a fragment; `<ui.Card>` the function of module ui
fn parseComponent(mut p Parser, open Tok) NodeId:
	dot = open.text.indexOf(".") ?? -1
	callee = p.mk(nIdent, open.line, open.col + 1)
	p.nodes[callee].text = open.text[dot + 1..].copy()
	if dot > 0:
		m = p.mk(nIdent, open.line, open.col + 1)
		p.nodes[m].text = open.text[..dot].copy()
		p.nodes[callee].kind = nField
		p.nodes[callee].kids.push(m)
	call = p.mk(nCall, open.line, open.col)
	p.nodes[call].kids.push(callee)
	names = []
	while p.at(tkMarkAttr):
		a = p.adv()
		p.noRepeat(names, a)
		arg = p.mk(nNamedArg, a.line, a.col)
		p.nodes[arg].text = a.text.copy()
		if not p.accept(tkEq):
			on = p.mk(nBool, a.line, a.col)
			p.nodes[on].ival = 1
			p.nodes[arg].kids.push(on)
		elif p.at(tkStr) or p.at(tkStrBegin):
			p.nodes[arg].kids.push(p.parsePrimary())
		else:
			p.nodes[arg].kids.push(p.attrBraced(a))
		p.nodes[call].kids.push(arg)
	kids = p.markupKids()
	if not p.nodes[kids].kids.isEmpty:
		arg = p.mk(nNamedArg, open.line, open.col)
		p.nodes[arg].text = "children"
		frag = p.markupCall("fragment", open.line, open.col)
		p.nodes[frag].kids.push(kids)
		p.nodes[arg].kids.push(frag)
		p.nodes[call].kids.push(arg)
	call

# a .zapx file imports zapx by itself, every name of it bare (checkimports.zap)
fn importMarkup(mut p Parser, mut items NodeId[]):
	if not isMarkupFile(p.file): return
	d = p.mk(nImportDecl, 1, 1)
	p.nodes[d].nodePart().file = p.file.copy()
	p.nodes[d].text = markupModule
	p.nodes[d].setText2("")
	p.nodes[d].flags |= flagInternal
	items.insert(0, d)
