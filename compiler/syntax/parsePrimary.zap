# The parsing of expressions: primaries, postfix forms, indexes and operator levels (parse.zap).

import fs

fn parsePrimary(mut p Parser) NodeId:
	k = p.kind()
	if k == tkIdent and p.cur().text == lenWord and p.indexDepth > 0 and
		p.kindAt(1) != tkLparen:
		# `length` inside an index's brackets: the indexed list's length (indexNode fills it)
		t = p.adv()
		e = p.mk(nIdent, t.line, t.col)
		p.nodes[e].setText("$len")
		return e
	if k == tkIt: return p.placeholder(p.adv(), "$it")
	if k == tkDot and p.kindAt(1) == tkIdent:
		# `.hp`: `it.hp`, a field of the call argument's value (parsePostfix goes on with `.pos.x`)
		d = p.adv()
		n = p.adv()
		f = p.mk(nField, n.line, n.col)
		madeKid = p.placeholder(d, "$it.{n.text}")
		p.nodes[f].pushKid(p.kidIds, madeKid)
		p.nodes[f].setText(n.text)
		return f
	if k == tkDot and p.kindAt(1) == tkUident:
		# `.Circle`, `.Circle(2.0)`: a variant of the enum the place expects (its type from there)
		d = p.adv()
		n = p.adv()
		e = p.mk(nField, n.line, n.col)
		p.nodes[e].setText(n.text)
		p.nodes[e].flags = flagDotVariant
		madeKid = p.mk(nIdent, d.line, d.col)
		p.nodes[e].pushKid(p.kidIds, madeKid)
		return e
	if k in [tkReturn, tkBreak, tkContinue]: return p.parsePrimaryJump(k)
	if k == tkInt or k == tkByte:
		t = p.adv()
		e = p.mk(nInt, t.line, t.col)
		p.nodes[e].setText(t.text)
		if t.kind == tkByte:
			p.nodes[e].flags = flagByte
		return e
	if k == tkFloat:
		t = p.adv()
		e = p.mk(nFloat, t.line, t.col)
		p.nodes[e].setText(t.text)
		return e
	if k == tkStr:
		t = p.adv()
		return p.strNode(t)
	if k == tkStrBegin: return p.parseInterp()
	if k == tkMarkOpen: return p.parseMarkup()
	if k == tkTrue or k == tkFalse:
		t = p.adv()
		e = p.mk(nBool, t.line, t.col)
		if t.kind == tkTrue:
			p.nodes[e].ival = 1
		return e
	if k == tkNone:
		t = p.adv()
		return p.mk(nNone, t.line, t.col)
	if k == tkThis:
		t = p.adv()
		e = p.mk(nIdent, t.line, t.col)
		p.nodes[e].setText("self")
		return e
	if k == tkIdent and p.cur().text in circleWords:
		# a constant of the language: its literal, of the float type its place asks for
		t = p.adv()
		e = p.mk(nFloat, t.line, t.col)
		p.nodes[e].setText("3.141592653589793" if t.text == "pi" else "6.283185307179586")
		return e
	if k == tkIdent: return p.parsePrimaryName()
	if k == tkUident: return p.parsePrimaryTypeName()
	if k == tkLparen:
		t = p.adv()
		if p.at(tkIdent) and p.kindAt(1) == tkEq: return p.parseNamedTuple(t)
		e = p.parseExpr()
		if p.at(tkComma): return p.parseTupleRest(t, e)
		p.expectTok(tkRparen)
		return e
	if k == tkLbracket: return p.parseArray()
	if k == tkLbrace and p.mapTypeReceiverAhead(): return p.typeReceiver(none)
	if k == tkLbrace: return p.parseMapLit()
	if k == tkMatch: return p.parseMatch()
	p.parseError(p.cur(), compileError("ExpectedExpression", ["{tokKindName(k)}"]))
	0

fn parsePrimaryJump(mut p Parser, k i64):
	# as a value (`x ?? return`): it leaves, so it stands for a value of any type
	t = p.adv()
	e = mk(
		p,
		nReturn if k == tkReturn else nBreak if k == tkBreak else nContinue,
		t.line,
		t.col
	)
	if k == tkReturn and not p.at(tkNewline) and not p.at(tkDedent) and
		not p.at(tkRparen) and not p.at(tkComma) and not p.at(tkEof):
		madeKid = p.parseExpr()
		p.nodes[e].pushKid(p.kidIds, madeKid)
	e

fn parsePrimaryName(mut p Parser):
	t = p.adv()
	at = p.aliasOf(t.text)
	if at >= 0: return p.expandAlias(at, t)
	e = p.mk(nIdent, t.line, t.col)
	typeArgs = p.callTypeArgsAhead(t)
	p.nodes[e].setText(t.text)
	if typeArgs:
		p.nodes[e].nodePart().types = p.parseTypeArgs()   # zeros<3>(): the call gives them
	e

fn parsePrimaryTypeName(mut p Parser):
	t = p.adv()
	e = p.mk(nIdent, t.line, t.col)
	p.nodes[e].setText(t.text)
	if p.typeArgsAhead():
		p.refuseCollectionName(e)
		p.nodes[e].nodePart().types = p.parseTypeArgs()
	e

# whether `{K: V}` here is a map type a constructor is called on: `{str: i64}.fromJson(text)`
fn mapTypeReceiverAhead(p Parser):
	i = p.closerOf(p.pos)
	i >= 0 and i + 2 < p.toks.len and p.toks[i + 1].kind == tkDot and
		p.toks[i + 2].text in ["fromJson", "fromBytes"]

# the place of the bracket closing the one at `open`, on its line, or -1
fn closerOf(p Parser, open i64):
	depth = 0
	i = open
	while i < p.toks.len:
		k = p.toks[i].kind
		if k in [tkLparen, tkLbracket, tkLbrace]:
			depth += 1
		elif k in [tkRparen, tkRbracket, tkRbrace]:
			depth -= 1
			if depth == 0: return i
		elif k in [tkNewline, tkEof]:
			return -1
		i += 1
	-1

# `Item[]`, `{str: i64}` or `i64[,]` before a constructor (`.fromJson(text)`): the name List or
# Map with the type's arguments, as the checker reads a receiver; base is the name already read
# (none for a map type here)
fn typeReceiver(mut p Parser, base NodeId?):
	head = match base:
		base: p.namedReceiver(base)
		none: p.parseMapType()
	te = p.typeSuffixes(head)
	if p.nodes[te].kind != nTyName or p.nodes[te].text not in ["List", "Map"]:
		p.parseError(
			p.cur(),
			compileError("ConstructorReceiver", [])
		)
	e = p.mk(nIdent, p.nodes[te].line, p.nodes[te].col)
	p.nodes[e].setText(p.nodes[te].text.copy(), p.nodes[te].name)
	p.nodes[e].nodePart().types = p.nodes[te].types().copy()
	e

# a receiver's type named by the name already read
fn namedReceiver(mut p Parser, base NodeId):
	te = p.mk(nTyName, p.nodes[base].line, p.nodes[base].col)
	p.nodes[te].setText(p.nodes[base].text.copy(), p.nodes[base].name)
	p.nodes[te].nodePart().types = p.nodes[base].types().copy()
	qualified = p.nodes[base].kind == nField and p.nodes[base].kids(p.kidIds).len == 1 and
		p.nodes[p.nodes[base].kids(p.kidIds)[0]].kind == nIdent
	if qualified:
		p.nodes[te].setText2(p.nodes[p.nodes[base].kids(p.kidIds)[0]].text.copy())   # module.Type[]
	elif p.nodes[base].kind != nIdent:
		p.parseError(p.cur(), compileError("ConstructorListType", []))
	te

# (a, b, ...) after its first value: the struct Tuple2(_0 = a, _1 = b) of the runtime's
# tuple types (2 to 8 values)
fn parseTupleRest(mut p Parser, open Tok, first NodeId):
	e = p.mk(nStructLit, open.line, open.col)
	p.nodes[e].pushKid(p.kidIds, first)
	while p.accept(tkComma) and not p.at(tkRparen):
		madeKid = p.parseExpr()
		p.nodes[e].pushKid(p.kidIds, madeKid)
	p.expectTok(tkRparen)
	n = p.nodes[e].kids(p.kidIds).len
	if n > 8:
		p.parseError(open, compileError("TupleTooLarge", []))
	p.nodes[e].setText("Tuple{n}")
	p.nodes[e].setText2("$rt")   # the runtime's, whatever the program declares
	p.nodes[e].nodePart().names = (0..n).map("_{it}")
	e

# (name = a, level = b) after its open parenthesis: the fields of the struct the place expects,
# named (checkTupleAsStruct); alone it has no type
fn parseNamedTuple(mut p Parser, open Tok):
	e = p.mk(nStructLit, open.line, open.col)
	p.nodes[e].setText("Named")
	p.nodes[e].setText2("$named")
	going = true
	while going:
		n = p.expectTok(tkIdent)
		p.expectTok(tkEq)
		p.nodes[e].nodePart().names.push(n.text.copy())
		madeKid = p.parseExpr()
		p.nodes[e].pushKid(p.kidIds, madeKid)
		going = p.accept(tkComma) and not p.at(tkRparen)
	p.expectTok(tkRparen)
	e

fn parseArgs(mut p Parser, callee NodeId):
	e = p.mk(nCall, p.nodes[callee].line, p.nodes[callee].col)
	p.nodes[e].pushKid(p.kidIds, callee)
	p.expectTok(tkLparen)
	going = not p.at(tkRparen)
	while going:
		if p.isOutAhead(false):
			# out x: the argument of an out parameter (x declared here when it is a new name)
			o = p.adv()
			arg = p.mk(nUnary, o.line, o.col)
			p.nodes[arg].ival = unOut
			n = p.adv()
			name = p.mk(nIdent, n.line, n.col)
			p.nodes[name].setText(n.text)
			p.nodes[arg].pushKid(p.kidIds, name)
			p.nodes[e].pushKid(p.kidIds, arg)
		elif p.at(tkDotdot):
			# ..base: the fields a struct's literal does not name, from base
			t = p.adv()
			rest = p.mk(nNamedArg, t.line, t.col)
			p.nodes[rest].setText("..")
			madeKid = p.parseExpr()
			p.nodes[rest].pushKid(p.kidIds, madeKid)
			p.nodes[e].pushKid(p.kidIds, rest)
		elif p.at(tkIdent) and p.kindAt(1) == tkEq:
			# name = value: the argument of the parameter so named
			t = p.adv()
			p.adv()
			named = p.mk(nNamedArg, t.line, t.col)
			p.nodes[named].setText(t.text)
			madeKid = p.valueExpr()
			p.nodes[named].pushKid(p.kidIds, madeKid)
			p.nodes[e].pushKid(p.kidIds, named)
		else:
			madeKid = p.valueExpr()
			p.nodes[e].pushKid(p.kidIds, madeKid)
		going = p.accept(tkComma) and not p.at(tkRparen)
	close = p.expectTok(tkRparen)
	p.sortKeys(e)
	if p.nodes[callee].kind == nIdent and p.nodes[callee].text == "embed":
		return p.embedFile(e, close)
	if p.nodes[callee].kind == nIdent and
		(p.nodes[callee].text == "shader" or p.nodes[callee].text == "compute"):
		# shader(lit.vertex, lit.pixel), compute(kernels.sum, 64): compiled once every module is
		# loaded (gpu.zap)
		p.notes.shaderCalls.push(e)
	if p.nodes[callee].kind == nIdent and conversionMethod(p.nodes[callee].text) != "" and
		p.nodes[e].kids(p.kidIds).len == 2 and
		p.nodes[p.nodes[e].kids(p.kidIds)[1]].kind != nNamedArg:
		return p.numberConversion(e)
	e

# `xs.sortedBy(-.level, .name)`: the keys of a sort, a minimum or a maximum, the first deciding
# and each next one breaking its ties, are one key, the tuple of them (`sortedBy((-.level, .name))`)
fn sortKeys(mut p Parser, call NodeId):
	callee = p.nodes[call].kids(p.kidIds)[0]
	keys = p.nodes[call].kidsFrom(p.kidIds, 1).copy()
	if p.nodes[callee].kind != nField or p.nodes[callee].text not in sortSteps or keys.len < 2 or
		keys.any(p.nodes[it].kind == nNamedArg):
		return
	first = p.nodes[keys[0]]
	tuple = p.mk(nStructLit, first.line, first.col)
	n = keys.len
	p.nodes[tuple].setKids(p.kidIds, move keys)
	p.nodes[tuple].setText("Tuple{n}")
	p.nodes[tuple].setText2("$rt")
	p.nodes[tuple].nodePart().names = (0..n).map("_{it}")
	p.nodes[call].setKids(p.kidIds, [callee, tuple])

sortSteps = ["sortedBy", "sortBy", "minBy", "maxBy"]

# `i64(x)`: a number converted, written with its type's name (a call of no value is a function's,
# a reader's `u16()`); the tree holds the method the checker and the GPU's lowering know (toI64
# on x) at the type's name
fn numberConversion(mut p Parser, e NodeId):
	callee = p.nodes[e].kids(p.kidIds)[0]
	f = p.mk(nField, p.nodes[callee].line, p.nodes[callee].col)
	p.nodes[f].setText(conversionMethod(p.nodes[callee].text))
	p.nodes[f].pushKid(p.kidIds, p.nodes[e].kids(p.kidIds)[1])
	p.nodes[e].setKids(p.kidIds, [f])
	e

# embed("world.txt"): the text of the file (beside the source that names it) as a string
# literal, read when compiling; the file is kept as it is (a shader, a table), no escapes
fn embedFile(mut p Parser, call NodeId, t Tok):
	if p.nodes[call].kids(p.kidIds).len != 2 or
		p.nodes[p.nodes[call].kids(p.kidIds)[1]].kind != nStr:
		p.parseError(t, compileError("EmbedPath", []))
	path = sourcePath(p.file, p.nodes[p.nodes[call].kids(p.kidIds)[1]].text)
	if not fs.exists(path):
		p.parseError(t, compileError("EmbedUnreadable", ["{path}"]))
	lit = p.mk(nStr, p.nodes[call].line, p.nodes[call].col)
	p.nodes[lit].setText(fs.readFile(path) ?? "")
	p.notes.embedded.push(Embedded(path = path.copy(), text = p.nodes[lit].text.copy()))   # (what the build rests on)
	lit

# whether `out` starts an out parameter (`out ids u32`) or an out argument (`out vbo`): the
# word followed by a name, then a type or the argument's end (`out` alone stays a name)
fn isOutAhead(p Parser, param bool):
	if not p.at(tkIdent) or p.toks[p.pos].text != "out" or p.kindAt(1) != tkIdent: return false
	next = p.kindAt(2)
	next in [tkIdent, tkUident, tkLbrace] if param else next == tkComma or next == tkRparen

fn parsePostfix(mut p Parser):
	e = p.parsePrimary()
	going = true
	while going:
		if (p.at(tkDot) or p.at(tkQdot)) and (p.kindAt(1) == tkInt or p.kindAt(1) == tkFloat):
			p.parseError(p.cur(), compileError("TuplePosition", []))   # t.0, opt?.0
		elif p.at(tkDot):
			p.adv()
			typeOfModule = p.nodes[e].kind == nIdent and not p.nodes[e].text[0].isUpper() and
				p.at(tkUident)
			n = p.adv() if p.at(tkUident) else p.expectTok(tkIdent)
			f = p.mk(nField, n.line, n.col)
			p.nodes[f].pushKid(p.kidIds, e)
			p.nodes[f].setText(n.text)
			if typeOfModule:
				p.nodes[f].nodePart().types = p.parseTypeArgs()   # heap.Heap<u64>(): a module's generic type
			e = f
		elif p.at(tkQdot):
			p.adv()
			n = p.adv() if p.at(tkUident) else p.expectTok(tkIdent)
			f = p.mk(nField, n.line, n.col)
			p.nodes[f].pushKid(p.kidIds, e)
			p.nodes[f].setText(n.text)
			p.nodes[f].flags = flagSafe
			e = f
		elif p.at(tkLparen):
			e = p.parseArgs(e)
		elif p.at(tkLbracket) and p.kindAt(1) in [tkRbracket, tkComma]:
			e = p.typeReceiver(e)
		elif p.at(tkLbracket):
			lb = p.adv()
			p.indexDepth += 1
			idx = p.parseIndexPart(lb)
			if p.at(tkComma):
				e = p.commaIndex(e, idx, lb)
			else:
				e = p.indexNode(e, idx, lb)
			while p.accept(tkComma):
				e = p.commaIndex(e, p.parseIndexPart(lb), lb)   # rows[i, j]: rows[i][j]
				p.nodes[e].flags |= flagComma
			p.indexDepth -= 1
			p.expectTok(tkRbracket)
		else:
			going = false
	e

# one index between brackets or commas: a value, or a range whose start left out is 0 (xs[..b])
fn parseIndexPart(mut p Parser, lb Tok) NodeId:
	if not p.at(tkDotdot) and not p.at(tkDotdotEq): return p.parseExpr()
	zero = p.mk(nInt, lb.line, lb.col)
	p.nodes[zero].setText("0")
	p.parseRangeAfter(zero)

# base[idx] where a comma joins idx to another index: a range is kept as written (a Grid's slice,
# the checker's), a value is a layer's index as in indexNode
fn commaIndex(mut p Parser, base NodeId, idx NodeId, lb Tok):
	if p.nodes[idx].kind != nRange: return p.indexNode(base, idx, lb)
	p.fillLen(idx, base, lb)
	ix = p.mk(nIndex, p.nodes[base].line, p.nodes[base].col)
	p.nodes[ix].pushKid(p.kidIds, base)
	p.nodes[ix].pushKid(p.kidIds, idx)
	ix

# lo..hi, lo..=hi (which is lo..hi + 1), either with `step s` after it (kids [lo, hi, s]); the end
# left out before `]`, `,` or `step` (flagOpenEnd): a slice to the end, which indexNode fills (a
# Grid's coordinate: the checker). The end and the step are read at `level` (an operand of
# `x in lo..hi` stops before `and`).
fn parseRangeAfter(mut p Parser, lo NodeId, level i64 = 6):
	dd = p.adv()
	r = p.mk(nRange, dd.line, dd.col)
	p.nodes[r].pushKid(p.kidIds, lo)
	if dd.kind == tkDotdot and
		(p.at(tkRbracket) or p.at(tkComma) and p.indexDepth > 0 or p.stepAhead()):
		p.nodes[r].flags |= flagOpenEnd
	else:
		hi = p.parseLevel(level)
		if dd.kind == tkDotdotEq:
			one = p.mk(nInt, dd.line, dd.col)
			p.nodes[one].setText("1")
			# lo..=x is lo..x + 1, the end wrapping: x the type's largest gives no steps, as written
			# in the spec, rather than a stop on the end only a bound reads
			past = p.binNode(binAdd, hi, one, dd)
			p.nodes[past].flags |= flagWrap
			p.nodes[r].pushKid(p.kidIds, past)
		else:
			p.nodes[r].pushKid(p.kidIds, hi)
	if p.stepAhead():
		p.adv()
		madeKid = p.parseLevel(level)
		p.nodes[r].pushKid(p.kidIds, madeKid)
	r

# whether the word `step` follows with a value after it: a range's step (a name step before `:`
# or `]` is the range's end)
fn stepAhead(p Parser):
	next = p.kindAt(1)
	p.at(tkIdent) and p.cur().text == stepWord and
		next not in [tkColon, tkRparen, tkRbracket, tkComma, tkDot, tkNewline, tkDedent, tkEof]

# base[idx]: an index, or a slice when idx is a range (its end filled with base.len when left
# out; with a step, the elements picked into a new list: (lo..hi step s).map(fn $at: base[$at]))
# every `length` (the ident $length) inside an index's brackets replaced by the indexed list's length
fn fillLen(mut p Parser, e NodeId, base NodeId, lb Tok):
	for i in 0..p.nodes[e].kids(p.kidIds).len:
		k = p.nodes[e].kids(p.kidIds)[i]
		if p.nodes[k].kind == nIdent and p.nodes[k].text == "$len":
			if nodeCallsPastSizes(p.nodes, p.kidIds, base):
				parseError(
					p,
					lb,
					compileError("LenNeedsPlace", [])
				)
			madeKid = lenOf(
				p.nodes,
				p.kidIds,
				p.nodes[k].line,
				p.nodes[k].col,
				cloneTree(p.nodes, p.kidIds, base)
			)
			p.nodes[e].setKid(p.kidIds, i, madeKid)
		else:
			p.fillLen(k, base, lb)
	for b in p.nodes[e].sub().copy():
		p.fillLen(b, base, lb)

fn indexNode(mut p Parser, base NodeId, idx NodeId, lb Tok) NodeId:
	if p.nodes[idx].kind == nIdent and p.nodes[idx].text == "$len":
		holder = p.mk(nBlock, lb.line, lb.col)   # a bare `length` as the whole index
		p.nodes[holder].pushKid(p.kidIds, idx)
		p.fillLen(holder, base, lb)
		return p.indexNode(base, p.nodes[holder].kids(p.kidIds)[0], lb)
	p.fillLen(idx, base, lb)
	if p.nodes[idx].kind == nRange and p.nodes[idx].hasFlag(flagOpenEnd):
		if nodeCalls(p.nodes, p.kidIds, base):
			parseError(
				p,
				lb,
				compileError("SliceToEndNeedsPlace", [])
			)
		madeKid = lenOf(p.nodes, p.kidIds, lb.line, lb.col, cloneTree(p.nodes, p.kidIds, base))
		p.nodes[idx].insertKid(p.kidIds, 1, madeKid)
		p.nodes[idx].flags &= ~flagOpenEnd
	if p.nodes[idx].kind == nRange and p.nodes[idx].kids(p.kidIds).len == 3:
		lam = p.mk(nLambda, lb.line, lb.col)
		p.nodes[lam].nodePart().names.push("$at")
		p.nodes[lam].nodePart().types.push(p.mk(nTyAbsent, lb.line, lb.col))
		at = p.mk(nIdent, lb.line, lb.col)
		p.nodes[at].setText("$at")
		picked = p.mk(nIndex, lb.line, lb.col)
		p.nodes[picked].pushKid(p.kidIds, base)
		p.nodes[picked].pushKid(p.kidIds, at)
		p.nodes[lam].pushKid(p.kidIds, picked)
		callee = p.mk(nField, lb.line, lb.col)
		p.nodes[callee].setText("map")
		p.nodes[callee].pushKid(p.kidIds, idx)
		call = p.mk(nCall, lb.line, lb.col)
		p.nodes[call].pushKid(p.kidIds, callee)
		p.nodes[call].pushKid(p.kidIds, lam)
		return call
	ix = p.mk(nIndex, p.nodes[base].line, p.nodes[base].col)
	p.nodes[ix].pushKid(p.kidIds, base)
	p.nodes[ix].pushKid(p.kidIds, idx)
	ix

# a function's result after its parameters, nothing when the header ends there: `T` (a tuple
# too), `T ? E` or `? E`
fn parseFnResult(mut p Parser, f NodeId):
	if not p.at(tkColon) and not p.at(tkNewline) and not p.at(tkDedent) and not p.at(tkEof):
		p.nodes[f].nodePart().types.push(p.parseType())

# (a, b T, ...) of a function f: its parameters, a trailing comma allowed

fn parseParamList(mut p Parser, f NodeId):
	p.expectTok(tkLparen)
	going = not p.at(tkRparen)
	defaulted = false
	while going:
		at = p.here()
		prm = p.parseParam()
		if defaulted and p.nodes[prm].kids(p.kidIds).isEmpty:
			p.parseError(at, compileError("DefaultBeforePlain", ["{p.nodes[prm].text}"]))
		defaulted = not p.nodes[prm].kids(p.kidIds).isEmpty
		p.nodes[f].pushKid(p.kidIds, prm)
		going = p.accept(tkComma) and not p.at(tkRparen)
	p.expectTok(tkRparen)

fn binNode(mut p Parser, op i64, lhs NodeId, rhs NodeId, t Tok):
	b = p.mk(nBinary, t.line, t.col)
	p.nodes[b].ival = i32(op)
	p.nodes[b].pushKid(p.kidIds, lhs)
	p.nodes[b].pushKid(p.kidIds, rhs)
	b

fn parsePow(mut p Parser):
	base = p.parsePostfix()
	if p.at(tkStarstar):
		op = p.adv()
		rhs = p.parseUnary()
		return p.binNode(binPow, base, rhs, op)
	base

fn parseUnary(mut p Parser) NodeId:
	if p.at(tkRef) or (p.at(tkMut) and p.kindAt(1) == tkRef):
		isMut = p.accept(tkMut)
		op = p.adv()
		e = p.mk(nUnary, op.line, op.col)
		p.nodes[e].ival = unRef
		if isMut:
			p.nodes[e].ival = unMutRef
		madeKid = p.parseUnary()
		p.nodes[e].pushKid(p.kidIds, madeKid)
		return e
	if p.at(tkMove):
		op = p.adv()
		e = p.mk(nUnary, op.line, op.col)
		p.nodes[e].ival = unMove
		madeKid = p.parseUnary()
		p.nodes[e].pushKid(p.kidIds, madeKid)
		return e
	if p.at(tkTry):
		t = p.adv()
		tr = p.mk(nTry, t.line, t.col)
		madeKid = p.parseUnary()
		p.nodes[tr].pushKid(p.kidIds, madeKid)
		return tr
	if p.at(tkMinus) or p.at(tkTilde) or p.at(tkNot):
		op = p.adv()
		e = p.mk(nUnary, op.line, op.col)
		u = unBnot
		if op.kind == tkMinus:
			u = unNeg
		elif op.kind == tkNot:
			u = unNot
		p.nodes[e].ival = i32(u)
		madeKid = p.parseUnary()
		p.nodes[e].pushKid(p.kidIds, madeKid)
		return e
	p.parsePow()

# the binary operator of the token here at a precedence level (binaryOperators), or -1
fn binOpAt(p Parser, level i64):
	k = p.kind()
	if k == tkNot and p.kindAt(1) == tkIn and level == 3: return binIn   # x not in xs
	binaryOperators.findIndex(.token == k and .level == level) ?? -1

fn parseLevel(mut p Parser, level i64) NodeId:
	e NodeId = 0
	if level == 0:
		e = p.parseUnary()
	elif level == 6:
		e = p.parseChoice()
	else:
		e = p.parseLevel(level - 1)
	op = p.binOpAt(level)
	while op >= 0:
		t = p.adv()
		negated = op == binIn and t.kind == tkNot
		if negated:
			p.adv()   # the `in` of `not in`
		rhs NodeId = 0
		if level == 0:
			rhs = p.parseUnary()
		elif level == 6:
			rhs = p.parseChoice()
		else:
			rhs = p.parseLevel(level - 1)
		if op == binIn and (p.at(tkDotdot) or p.at(tkDotdotEq)):
			rhs = p.parseRangeAfter(rhs, level - 1)   # x in lo..hi
		e = p.binNode(op, e, rhs, t)
		if negated:
			n = p.mk(nUnary, t.line, t.col)
			p.nodes[n].ival = unNot
			p.nodes[n].pushKid(p.kidIds, e)
			e = n
		op = p.binOpAt(level)
	e

# `a if c else b`: the value the condition picks, looser than every operator but `??`; a chain
# `a if c else b if d else e` nests to the right, and the else branch takes a `??` after it
fn parseChoice(mut p Parser) NodeId:
	yes = p.parseLevel(5)
	if not p.at(tkIf): return yes
	t = p.adv()
	cond = p.parseLevel(5)
	if not p.accept(tkElse):
		p.parseError(p.cur(), compileError("IfValueNeedsElse", []))
	no = p.parseLevel(6)
	p.ifValueNode(cond, yes, no, t.line, t.col)

fn parseExpr(mut p Parser) NodeId:
	if p.valueAt and p.bareLambdaAhead(): return p.parseLambda()
	e = p.parseLevel(6)
	if p.at(tkDotdot) or p.at(tkDotdotEq): return p.parseRangeAfter(e)
	e

# ---------- statements ----------

# an expression where a value is given (valueAt): a lambda may be written there without `fn`
fn valueExpr(mut p Parser):
	was = p.valueAt
	p.valueAt = true
	e = p.parseExpr()
	p.valueAt = was
	e

# an expression where a value is not a lambda's start: a map literal's key
fn plainExpr(mut p Parser):
	was = p.valueAt
	p.valueAt = false
	e = p.parseExpr()
	p.valueAt = was
	e

# whether a lambda without `fn` starts here: `name:`, or parentheses whose close is followed by
# `:` (`(a, b):`, `(a i64):`, `():`), on one line
fn bareLambdaAhead(p Parser):
	if p.at(tkIdent) and p.kindAt(1) == tkColon: return true
	if not p.at(tkLparen): return false
	q = 1
	depth = 1
	while depth > 0:
		k = p.kindAt(q)
		if k == tkLparen:
			depth += 1
		elif k == tkRparen:
			depth -= 1
		elif k in [tkNewline, tkEof, tkIndent, tkDedent]:
			return false
		q += 1
	p.kindAt(q) == tkColon
