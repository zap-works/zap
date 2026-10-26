# `expect condition`, a statement: when the condition does not hold, testFail reports the place,
# the condition as written and what its form says it was. The parts of a condition joined by
# `and` are checked one after the other, as `and` runs them, and the report names the part that
# failed; a part that tests a pattern (`r is Ok(v)`) binds its names for the parts after it. By
# its form a part shows: a comparison both sides; `x in xs` the value and the list (`x in lo..hi`
# its ends); `a.isClose(b, t)` both sides, their difference and the tolerance; another method its
# receiver and its arguments; `v is Pattern` the value. A value shown that calls or moves is
# evaluated once, bound first to a local of the check; the others (names, fields, literals, whose
# type may come from where they stand) are read again. A value without a text shows as
# "(no text)" (flagShownIfAny).

import fs

fn expectStmt(mut p Parser, t Tok):
	first = p.pos
	parts = []
	if p.isTestAhead():
		parts = p.parseCondParts()
	else:
		for part in p.andParts(p.parseExpr()):
			parts.push((part, none))
	text = p.writtenText(first)
	table = p.expectTable(t, parts)
	inner = p.mk(nBlock, t.line, t.col)
	k = parts.len - 1
	while k >= 0:
		value, pattern = parts[k]
		inner = p.expectPart(t, text, k, parts.len, value, pattern, inner)
		k -= 1
	always = p.mk(nBool, t.line, t.col)
	p.nodes[always].ival = 1
	outer = p.mk(nIf, t.line, t.col)
	p.nodes[outer].pushKid(p.kidIds, always)
	p.nodes[outer].nodePart().sub.push(table ?? inner)
	outer

# `expect f == {input: output}` (a map has no ==): f called with each key (a tuple's parts the
# arguments) and compared with its value, each a check of its own whose report names the call;
# none when the condition has another form
fn expectTable(mut p Parser, t Tok, parts (NodeId, NodeId?)[]) NodeId?:
	if parts.len != 1: return none
	value, pattern = parts[0]
	if pattern != none: return none
	if p.nodes[value].kind != nBinary or p.nodes[value].ival != binEq: return none
	left = p.nodes[value].kids(p.kidIds)[0]
	right = p.nodes[value].kids(p.kidIds)[1]
	if p.nodes[right].kind != nMapLit or p.nodes[right].kids(p.kidIds).isEmpty: return none
	checks = p.mk(nBlock, t.line, t.col)
	keys = p.nodes[right].kids(p.kidIds).copy()
	for i, key in keys:
		want = p.nodes[right].sub()[i]
		tuple = p.nodes[key].kind == nStructLit and p.nodes[key].text2() == "$rt"
		args = p.nodes[key].kids(p.kidIds).copy() if tuple else [key]
		call = p.mk(nCall, p.nodes[key].line, p.nodes[key].col)
		madeKid = cloneTree(p.nodes, p.kidIds, left)
		p.nodes[call].pushKid(p.kidIds, madeKid)
		shown = []
		for arg in args:
			madeKid = cloneTree(p.nodes, p.kidIds, arg)
			p.nodes[call].pushKid(p.kidIds, madeKid)
			shown.push(exprText(p.nodes, p.kidIds, arg))
		cond = p.mk(nBinary, p.nodes[key].line, p.nodes[key].col)
		p.nodes[cond].ival = binEq
		p.nodes[cond].pushKid(p.kidIds, call)
		madeKid = cloneTree(p.nodes, p.kidIds, want)
		p.nodes[cond].pushKid(p.kidIds, madeKid)
		said = "{exprText(p.nodes, p.kidIds, left)}({shown.join(", ")}) == {exprText(p.nodes, p.kidIds, want)}"
		place = Tok(kind = t.kind, text = t.text.copy(), line = p.nodes[key].line, col = t.col)
		done = p.mk(nBlock, t.line, t.col)
		check = p.expectPart(place, said, i, 1, cond, none, done)
		p.nodes[checks].extendKids(p.kidIds, p.nodes[check].kids(p.kidIds).copy())
	checks

# the operands of a chain of `and`, in order
fn andParts(p Parser, e NodeId) NodeId[]:
	if p.nodes[e].kind != nBinary or p.nodes[e].ival != binAnd: return [e]
	parts = p.andParts(p.nodes[e].kids(p.kidIds)[0])
	parts.extend(p.andParts(p.nodes[e].kids(p.kidIds)[1]))
	parts

# the source of the tokens from `first` to the last one read, as written (its lines joined), or
# "" when the file cannot be read (read once, at the first)
fn writtenText(mut p Parser, first i64):
	head = p.toks[first]
	last = p.toks[p.pos - 1]
	if p.written == none: p.written = fs.readFile(p.file) ?? ""
	whole = p.written ?? ""
	lines = []
	for line in head.line..=last.line:
		source = textLine(whole, line) ?? ""
		code = codeOf(source)
		start = (head.col - 1).clamp(0, code.len) if line == head.line else 0
		lines.push(code[start..].trimmed().copy())
	lines.join(" ").trimmed().copy()

# Part k of n: a block that binds what it shows once, then tests the part, going on to `inner`
# when it holds and reporting it when it does not.
fn expectPart(
	mut p Parser,
	t Tok,
	text str,
	k i64,
	n i64,
	value NodeId,
	pattern NodeId?,
	inner NodeId
):
	blk = p.mk(nBlock, t.line, t.col)
	details = []
	if n > 1:
		details.push(p.textNode(t, "part {k + 1} of {n} failed"))
	fail = p.mk(nBlock, t.line, t.col)
	where = p.whereText(t)
	said = p.textNode(t, exprText(p.nodes, p.kidIds, value) if text == "" else text.copy())
	if pattern is pattern:
		v = p.boundOnce(blk, value, "$expect{k}")
		details.push(p.shownAs("value", p.again(v)))
		madeKid = p.testFailCall(t, where, said, details)
		p.nodes[fail].pushKid(p.kidIds, madeKid)
		m = p.mk(nMatch, t.line, t.col)
		p.nodes[m].pushKid(p.kidIds, v)
		hit = p.mk(nArm, p.nodes[pattern].line, p.nodes[pattern].col)
		p.nodes[hit].pushKid(p.kidIds, pattern)
		p.nodes[hit].nodePart().sub.push(inner)
		p.nodes[m].pushKid(p.kidIds, hit)
		other = p.mk(nArm, t.line, t.col)
		wild = p.mk(nPattern, t.line, t.col)
		p.nodes[wild].ival = patWildcard
		p.nodes[other].pushKid(p.kidIds, wild)
		p.nodes[other].nodePart().sub.push(fail)
		p.nodes[m].pushKid(p.kidIds, other)
		st = p.mk(nExprStmt, t.line, t.col)
		p.nodes[st].pushKid(p.kidIds, m)
		p.nodes[blk].pushKid(p.kidIds, st)
		return blk
	p.showParts(blk, value, k, details)
	madeKid = p.testFailCall(t, where, said, details)
	p.nodes[fail].pushKid(p.kidIds, madeKid)
	check = p.mk(nIf, t.line, t.col)
	p.nodes[check].pushKid(p.kidIds, value)
	p.nodes[check].nodePart().sub.push(inner)
	p.nodes[check].nodePart().sub.push(fail)
	p.nodes[blk].pushKid(p.kidIds, check)
	blk

# What a plain part shows by its form, pushed to details; the values it shows that call or move
# are bound in blk first and read through those names.
fn showParts(mut p Parser, blk NodeId, e NodeId, k i64, mut details NodeId[]):
	kind = p.nodes[e].kind
	op = p.nodes[e].ival
	if kind == nBinary and (isCompareOp(op) or op == binIn):
		left = p.boundOnce(blk, p.nodes[e].kids(p.kidIds)[0], "$expect{k}l")
		p.nodes[e].setKid(p.kidIds, 0, left)
		right = p.nodes[e].kids(p.kidIds)[1]
		if op == binIn and p.nodes[right].kind == nRange and
			p.nodes[right].kids(p.kidIds).len == 2 and
			not p.nodes[right].kids(p.kidIds).any(p.callsOrMoves(it)):
			details.push(p.shownAs("value", p.again(left)))
			lo = p.again(p.nodes[right].kids(p.kidIds)[0])
			hi = p.again(p.nodes[right].kids(p.kidIds)[1])
			details.push(p.shownParts(["range: ", "..", ""], [lo, hi]))
			return
		bound = p.boundOnce(blk, right, "$expect{k}r")
		p.nodes[e].setKid(p.kidIds, 1, bound)
		details.push(p.shownAs("value" if op == binIn else "left", p.again(left)))
		details.push(p.shownAs("in" if op == binIn else "right", p.again(bound)))
		return
	if kind == nCall and p.nodes[p.nodes[e].kids(p.kidIds)[0]].kind == nField:
		callee = p.nodes[e].kids(p.kidIds)[0]
		if p.namesModuleOrType(p.nodes[callee].kids(p.kidIds)[0]): return
		receiver = p.boundOnce(blk, p.nodes[callee].kids(p.kidIds)[0], "$expect{k}s")
		p.nodes[callee].setKid(p.kidIds, 0, receiver)
		args = p.nodes[e].kidsFrom(p.kidIds, 1).copy()
		if p.nodes[callee].text == "isClose" and args.len == 2 and
			args.all(p.nodes[it].kind != nNamedArg):
			other = p.boundOnce(blk, args[0], "$expect{k}o")
			p.nodes[e].setKid(p.kidIds, 1, other)
			details.push(p.shownAs("left", p.again(receiver)))
			details.push(p.shownAs("right", p.again(other)))
			difference = p.mk(nBinary, p.nodes[e].line, p.nodes[e].col)
			p.nodes[difference].ival = binSub
			madeKid = p.again(receiver)
			p.nodes[difference].pushKid(p.kidIds, madeKid)
			madeKid = p.again(other)
			p.nodes[difference].pushKid(p.kidIds, madeKid)
			details.push(p.shownAs("difference", difference))
			if not p.callsOrMoves(args[1]):
				details.push(p.shownAs("tolerance", p.again(args[1])))
			return
		if p.nodes[receiver].kind != nRange:
			details.push(p.shownAs("receiver", p.again(receiver)))
		for i, arg in args:
			named = p.nodes[arg].kind == nNamedArg
			value = p.nodes[arg].kids(p.kidIds)[0] if named else arg
			if p.plainValue(value):
				label = p.nodes[arg].text.copy() if named else "argument {i + 1}"
				details.push(p.shownAs(label, p.again(value)))
		return
	if kind == nField and not p.namesModuleOrType(p.nodes[e].kids(p.kidIds)[0]) and
		p.nodes[p.nodes[e].kids(p.kidIds)[0]].kind != nRange:
		receiver = p.boundOnce(blk, p.nodes[e].kids(p.kidIds)[0], "$expect{k}s")
		p.nodes[e].setKid(p.kidIds, 0, receiver)
		details.push(p.shownAs("receiver", p.again(receiver)))

# e itself when it neither calls nor moves (read again where it is shown) or is a `.Variant(args)`
# or a list of one (whose enum only its place gives, shown as its text), else a name bound to it
# in blk first
fn boundOnce(mut p Parser, blk NodeId, e NodeId, name str):
	if not p.callsOrMoves(e) or p.placeTyped(e): return e
	line = p.nodes[e].line
	col = p.nodes[e].col
	bound = p.mk(nLet, line, col)
	p.nodes[bound].text = name.copy()
	p.nodes[bound].pushKid(p.kidIds, e)
	p.nodes[blk].pushKid(p.kidIds, bound)
	read = p.mk(nIdent, line, col)
	p.nodes[read].text = name.copy()
	read

# an argument shown as it is: no call, no move, no lambda, no `it` (which make it a lambda), no
# range (a for's or an index's alone)
fn plainValue(p Parser, e NodeId):
	not p.callsOrMoves(e) and not p.hasLambda(e) and p.nodes[e].kind != nRange

fn hasLambda(p Parser, e NodeId) bool:
	p.nodes[e].kind == nLambda or p.nodes[e].hasFlag(flagPlaceholder) or
		p.nodes[e].kids(p.kidIds).any(p.hasLambda(it))

# whether e names a module or a type (`fs.exists(p)`, `Color.Red`): not a value to show
fn namesModuleOrType(p Parser, e NodeId):
	if p.nodes[e].kind != nIdent: return false
	name = p.nodes[e].text
	(not name.isEmpty and name[0] >= 'A' and name[0] <= 'Z') or name in p.modules

# a second reading of a value shown: a copy of the tree, or the text of a `.Variant`, whose enum
# only its place gives
fn again(mut p Parser, e NodeId) NodeId:
	if p.placeTyped(e):
		s = p.mk(nStr, p.nodes[e].line, p.nodes[e].col)
		p.nodes[s].text = exprText(p.nodes, p.kidIds, e)
		return s
	cloneTree(p.nodes, p.kidIds, e)

# whether e is a `.Variant` or a list literal holding one: a value only its place types
fn placeTyped(p Parser, e NodeId):
	p.dotVariant(e) or p.nodes[e].kind == nArray and p.nodes[e].kids(p.kidIds).any(p.dotVariant(it))

# whether e is a `.Variant` (or `.Variant(args)`)
fn dotVariant(p Parser, e NodeId):
	v = p.nodes[e].kids(p.kidIds)[0] if p.nodes[e].kind == nCall else e
	p.nodes[v].kind == nField and p.nodes[v].hasFlag(flagDotVariant)

fn textNode(mut p Parser, t Tok, text str):
	s = p.mk(nStr, t.line, t.col)
	p.nodes[s].text = text.copy()
	s

# "label: {e}", e shown if it has a text
fn shownAs(mut p Parser, label str, e NodeId) NodeId:
	p.shownParts(["{label}: ", ""], [e])

# the texts with the values between them, each value shown if it has a text
fn shownParts(mut p Parser, texts str[], values NodeId[]):
	line = p.nodes[values[0]].line
	col = p.nodes[values[0]].col
	s = p.mk(nInterp, line, col)
	p.nodes[s].flags |= flagShownIfAny
	for i, text in texts:
		piece = p.mk(nStr, line, col)
		p.nodes[piece].text = text.copy()
		p.nodes[s].pushKid(p.kidIds, piece)
		if i < values.len:
			p.nodes[s].pushKid(p.kidIds, values[i])
	s

fn testFailCall(mut p Parser, t Tok, where NodeId, said NodeId, details NodeId[]) NodeId:
	list = p.mk(nArray, t.line, t.col)
	p.nodes[list].setKids(p.kidIds, details.copy())
	internalCallStmt(p.nodes, p.kidIds, "testFail", [where, said, list], t.line, t.col)
