# Type checker, part 2: expressions (operators, match, built-in methods, calls, closures).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

fn isNumLit(c Checker, e NodeId):
	k = nodes[e].kind
	if k == nInt or k == nFloat: return true
	if k == nUnary and nodes[e].ival == unNeg:
		ok = nodes[nodes[e].kids(kidIds)[0]].kind
		return ok == nInt or ok == nFloat
	false

fn numOrNone(c Checker, maybeT TypeId?) TypeId?:
	t = try maybeT
	if isDefined(tys, t): return t if typeIsNumeric(tys, t) else none
	if typeIsNumeric(tys, t): return rangeBase(tys, t)   # a literal next to a range type is its base's
	none

# what an operation on defined type t gives when its base's gives res: t where that is the base
# (Meters + Meters), else res (NodeId - NodeId is an i32, as n32 - n32 is)
fn keepDefined(c Checker, t TypeId, res TypeId):
	t if isDefined(tys, t) and isSameType(tys, res, tys[t].under) else res

# the error for operands of two types that do not mix (name); a defined type among them names
# its conversion
fn operandsError(c Checker, name str, lt TypeId, rt TypeId):
	if not isDefined(tys, lt) and not isDefined(tys, rt):
		return compileError(name, ["{c.showTy(lt)}", "{c.showTy(rt)}"])
	made = lt if isDefined(tys, lt) else rt
	compileError("DefinedMixed", ["{c.showTy(lt)}", "{c.showTy(rt)}", "{c.showTy(made)}"])

# what an error about an integer given where a narrower integer type, one of another sign or a
# range type is asked adds: how it gets there
fn rangeHint(c Checker, src TypeId, maybeDst TypeId?):
	dst = maybeDst ?? return ""
	if c.tKind(src) != tInt or c.tKind(dst) != tInt: return ""
	if not tys[dst].ranged:
		if isDefined(tys, src) or isDefined(tys, dst) or intWidensTy(tys, src, dst): return ""
		return " (its values are not proven inside it: convert it with {c.showTy(dst)}(x), which stops the program outside it)"
	if tys[dst].display == "" and dst != tyN32 and dst != tyN64:
		return " (a value goes into a range when it is proven inside, else through a range type's checked conversion: type R = {c.showTy(dst)}, then R(x))"
	" (convert it with {c.showTy(dst)}(x), which stops the program outside the range)"

# the type op on l (of type lt) and r (rt) gives, computed in res: the range their values give
# (carriedType); a defined type's own when that range lies in its base (NodeId + 1), else the
# base's (NodeId - NodeId is an i32)
fn arithResult(mut c Checker, op i64, l NodeId, lt TypeId, r NodeId, rt TypeId, res TypeId):
	if not isDefined(tys, res): return c.carriedType(op, l, lt, r, rt, res)
	u = underOf(tys, res)
	carried = c.carriedType(op, l, u, r, u, u)
	res if isAssignable(tys, carried, u) else c.keepDefined(res, rangeBase(tys, carried))

# the range type a call's callee names (`Percent(x)`, `geo.Percent(x)`, `n32(x)`), else none
fn rangeTypeNamed(mut c Checker, callee NodeId) TypeId?:
	if nodes[callee].kind == nIdent:
		name = nodes[callee].text
		if c.lookupVar(name) >= 0 or c.lookupDeclAsWritten(nFnDecl, "", name, 0, 0) != none:
			return none
		if name == "n32" or name == "n64": return tyN32 if name == "n32" else tyN64
	t = try c.aliasCalled(callee)
	t if tys[t].ranged and not isDefined(tys, t) else none

# the defined type a call's callee names (`Meters(x)`, `geo.Meters(x)`), else none
fn definedTypeNamed(mut c Checker, callee NodeId) TypeId?:
	t = try c.aliasCalled(callee)
	t if isDefined(tys, t) else none

# the type a `type Name = T` a call's callee names (`Name(x)`, `geo.Name(x)`) gives, else none
fn aliasCalled(mut c Checker, callee NodeId) TypeId?:
	if nodes[callee].kind == nIdent and nodes[callee].text2() == globalAlias and
		c.lookupDeclAsWritten(nStructDecl, globalAlias, nodes[callee].text, 0, 0) is d and
		nodes[d].hasFlag(flagTypeAlias):
		return c.aliasedType(d)   # a callee the checker wrote, by the type's global name
	module = ""
	if nodes[callee].kind == nField and nodes[callee].kids(kidIds).len == 1 and
		nodes[nodes[callee].kids(kidIds)[0]].kind == nIdent:
		module = nodes[nodes[callee].kids(kidIds)[0]].text.copy()
		if c.lookupVarQuiet(module): return none   # a variable's method
		imp = try c.findImportByAlias(c.curMod, module)
		if c.findDeclInModule(nodes[imp].text, nStructDecl, nodes[callee].text) == none:
			return none   # a function of the module (win.CreateEventA)
	elif nodes[callee].kind != nIdent:
		return none
	name = nodes[callee].text
	if name.isEmpty or (name[0] < 'A' or name[0] > 'Z') and not name.startsWith("$Ty") or
		module == "" and c.lookupVarQuiet(name):
		return none   # ($Ty3: a defined type the derived functions make, derive.zap)
	d = c.lookupDeclAsWritten(nStructDecl, module, name, nodes[callee].line, nodes[callee].col) ??
		return none
	if not nodes[d].hasFlag(flagTypeAlias): return none
	c.aliasedType(d)

# whether the call e of defined type t's name is a conversion (`Meters(x)`), not a literal of its
# struct (`Color(1.0, 0.5, 0.0, 1.0)`): one value, not named, and of a type over t's base where
# the struct has one field
fn isDefinedConversion(mut c Checker, e NodeId, t TypeId):
	if c.tKind(t) != tStruct: return true
	if c.argCount(e) != 1 or nodes[c.argAt(e, 0)].kind == nNamedArg: return false
	if nodes[declOf(tys, t)].kids(kidIds).len != 1: return true
	at = c.derefIfRef(c.argAt(e, 0), c.checkExpr(c.argAt(e, 0), none))
	isSameType(tys, underlying(tys, at), underlying(tys, t))

# the struct type of declaration sd when the call e of its name is given one value of a type
# defined over it (`Color(paint)`), else none
fn definedOverStruct(mut c Checker, e NodeId, sd NodeId) TypeId?:
	if c.argCount(e) != 1 or nodes[sd].kids(kidIds).len == 1 or c.isGenericTemplate(sd): return none
	a = c.argAt(e, 0)
	if nodes[a].kind not in [nIdent, nField, nCall, nIndex] or
		c.fillsNamedField(a, nodes[sd].kids(kidIds).map(nodes[it].text.copy())):
		return none
	at = c.derefIfRef(a, c.checkExpr(a, none))
	st = tyOfDecl(tys, nodes, sd)
	st if isDefined(tys, at) and isSameType(tys, underlying(tys, at), st) else none

# `Meters(x)`: x as the defined type t, from a value of a type over the same type as t (its base,
# another defined type), or converted to the base first as a number is (`NodeId(i)` checks i as
# n32(i) does)
fn checkDefinedConversion(mut c Checker, e NodeId, t TypeId) TypeId:
	name = c.showTy(t)
	if not c.expectArgs(e, name, 1): return tyError
	base = underOf(tys, t)
	arg = c.argAt(e, 0)
	at = c.derefIfRef(arg, c.checkExpr(arg, base))
	if c.tKind(at) == tError: return tyError
	line = nodes[e].line
	col = nodes[e].col
	if isSameType(tys, at, t):
		c.errorAt(line, col, compileError("NeedlessConversion", ["{name}"]))
	elif isSameType(tys, underlying(tys, at), underlying(tys, base)) or
		c.tKind(at) == tInt and c.tKind(base) == tInt:
		# the same value, or an integer checked into the base's range (irConverted)
		pass
	elif typeIsNumeric(tys, at) and typeIsNumeric(tys, base) and
		conversionMethod(c.showTy(base)) != "":
		conversion = newNode(
			nodes,
			kidIds,
			nField,
			line,
			col,
			text = conversionMethod(c.showTy(base)),
			kids = [arg]
		)
		c.setArg(e, 0, newNode(nodes, kidIds, nCall, line, col, kids = [conversion]))
		c.checkExpr(c.argAt(e, 0), base)
	else:
		c.errorAt(
			line,
			col,
			compileError("DefinedConversion", ["{name}", "{c.showTy(base)}", "{c.showTy(at)}"])
		)
		return tyError
	nodes[e].flags |= flagRangeConversion
	c.typed(e, t)

# the type a receiver read as its defined type's base (flagBaseView) has: the base, or a
# reference to it
fn baseView(mut c Checker, e NodeId, t TypeId) TypeId:
	res = t
	if isDefined(tys, t):
		res = underOf(tys, t)
	elif c.tKind(t) == tRef and isDefined(tys, tys[t].inner):
		res = tyRef(tys, underOf(tys, tys[t].inner), tys[t].bits == 1)
	c.typed(e, res)

# `Percent(x)`: the integer x as range type t, the program stopped when it lies outside
fn checkRangeConversion(mut c Checker, e NodeId, t TypeId) TypeId:
	name = c.showTy(t)
	if not c.expectArgs(e, name, 1): return tyError
	at = c.checkExpr(c.argAt(e, 0), rangeBase(tys, t))
	if c.tKind(at) == tError: return tyError
	if c.tKind(at) != tInt:
		errorAt(
			c,
			nodes[e].line,
			nodes[e].col,
			compileError("ConversionNeedsInteger", ["{name}", "{c.showTy(at)}"])
		)
		return tyError
	if isSameType(tys, at, t):
		c.errorAt(nodes[e].line, nodes[e].col, compileError("NeedlessConversion", ["{name}"]))
	elif c.gpuCode and not intWidensTy(tys, at, t):
		c.errorAt(nodes[e].line, nodes[e].col, compileError("GpuRangeConversion", ["{name}"]))   # a shader cannot stop
	nodes[e].flags |= flagRangeConversion
	c.typed(e, t)

# A + of texts with a literal among its pieces, `"(" + a + ", " + b + ")"`, is written as the
# interpolation "({a}, {b})" (`str(n)` as a piece is n): noted for zap fmt while it checks, an
# error otherwise. Its pieces are the chain's, through parentheses and over lines; the + of a `+=`
# is none of it, and the runtime's and the derived code keep theirs.
fn literalJoin(mut c Checker, e NodeId):
	if nodes[e].hasFlag(flagCompound) or
		c.inRuntimeOrDerived():
		return
	src = c.file if c.curFile == "" else c.curFile
	leaves = []
	pluses = []
	c.joinLeaves(e, leaves, pluses)
	literal = leaves.find(c.writtenLiteral(src, it)) ?? return
	form = c.joinedForm(src, leaves, pluses)
	if noting:
		if form.text == "": return
		file = notePath(src)
		formNotes = formNotes.filter(n:   # the pieces' own notes
			n.file != file or placeBefore(n.line, n.col, form.line, form.col) or
				not placeBefore(n.line, n.col, form.endLine, form.endCol)
		)
		c.canonNote(noteReplace, form.line, form.col, form.cut, form.text)
		return
	shown = "\"...\{x}...\"" if form.text == "" else form.text
	line = nodes[literal].line
	col = nodes[literal].col
	# an inner chain's error is the outer's: one per place
	before = c.pending.len
	c.pending = c.pending.filter(p:
		not (p.line == line and p.col == col and p.message.startsWith(joinMessage))
	)
	c.errors -= before - c.pending.len
	c.errorAt(line, col, compileError("InterpolationNotConcat", ["{joinMessage}", "{shown}"]))

joinMessage = "a text with a literal in it is written as an interpolation: "

# the pieces of a + of texts, left to right, and the + between them
fn joinLeaves(c Checker, n NodeId, mut leaves NodeId[], mut pluses NodeId[]):
	if nodes[n].kind == nBinary and nodes[n].ival == binAdd and typeOf(nodes, n) == tyStr and
		not nodes[n].hasFlag(flagCompound):
		c.joinLeaves(nodes[n].kids(kidIds)[0], leaves, pluses)
		pluses.push(n)
		c.joinLeaves(nodes[n].kids(kidIds)[1], leaves, pluses)
		return
	leaves.push(n)

# whether a piece is a string's literal written in the source (not one the parser made)
fn writtenLiteral(c Checker, src str, n NodeId):
	if nodes[n].kind != nStr and nodes[n].kind != nInterp: return false
	text = sourceLineOf(src, nodes[n].line)
	at = nodes[n].col - 1
	at >= 0 and at < text.len and
		(text[at] == '"' or text[at] == 'r' and at + 1 < text.len and text[at + 1] == '"')

# where a node's text starts: the first line and column among its own and its parts'
fn firstPlace(c Checker, n NodeId) (i64, i64):
	line i64 = nodes[n].line
	col i64 = nodes[n].col
	for k in nodes[n].kids(kidIds):
		l, cl = c.firstPlace(k)
		if l > 0 and (l < line or l == line and cl < col):
			line = l
			col = cl
	(line, col)

# where a join stands in its file (from line:col up to endLine:endCol, cut bytes) and the
# interpolation it is written as
type JoinForm:
	line i64
	col i64
	cut i64
	endLine i64
	endCol i64
	text str

# whether line:col comes before the other place
fn placeBefore(line i64, col i64, otherLine i64, otherCol i64):
	line < otherLine or line == otherLine and col < otherCol

# The interpolation a join's pieces make, with where the join stands (line, column, the bytes it
# covers, over lines when it goes on below), or "" when its text is not as the tree says or a
# piece cannot stand in braces (a comment inside, a """ string, a piece over several lines)
fn joinedForm(c Checker, src str, leaves NodeId[], pluses NodeId[]):
	failed = JoinForm(line = 0, col = 0, cut = 0, endLine = 0, endCol = 0, text = "")
	first, firstCol = c.firstPlace(leaves[0])
	last i64 = nodes[pluses[len - 1]].line
	if first < 1 or first > nodes[pluses[0]].line: return failed
	text = ""
	starts = []   # where each line starts in text
	for l in first..=last + 1:
		starts.push(text.len)
		text += sourceLineOf(src, l)
		text += "\n"
	cuts = pluses.map(starts[nodes[it].line - first] + nodes[it].col - 1)
	if cuts.any(it < 0 or it >= text.len or text[it] != '+'): return failed
	start = firstCol - 1
	while start > 0 and (text[start - 1].isWordByte() or text[start - 1] == '.'):
		start -= 1   # a module's name before its member (the tree names the member alone)
	end = pieceEnd(text, cuts[len - 1] + 1)
	if start < 0 or start >= cuts[0] or end < 0: return failed
	# parentheses opened before the first piece and closed inside the join are its own
	depth = bracketDelta(text[start..cuts[0]])
	while depth < 0 and start > 0 and text[start - 1] == '(':
		start -= 1
		depth += 1
	out = "\""
	open = 0   # parentheses a piece opened that a later one closes
	from = start
	for k in 0..=cuts.len:
		to = cuts[k] if k < cuts.len else end
		piece = text[from..to].trimmed().copy()
		from = to + 1
		if "\n" in piece or commentStart(piece) < piece.len: return failed
		while piece.startsWith("(") and bracketDelta(piece) > 0:
			piece = piece[1..].trimmed().copy()
			open += 1
		while open > 0 and piece.endsWith(")") and bracketDelta(piece) < 0:
			piece = piece[..len - 1].trimmed().copy()
			open -= 1
		if piece.isEmpty or bracketDelta(piece) != 0 or piece.startsWith("\"\"\"") or
			piece.startsWith("r\"\"\""):
			return failed
		out += piecePart(piece)
	if open != 0: return failed
	out += "\""
	endLine = starts.len - 1
	while starts[endLine] > end:
		endLine -= 1
	JoinForm(
		line = first,
		col = start + 1,
		cut = end - start,
		endLine = first + endLine,
		endCol = end - starts[endLine] + 1,
		text = out
	)

# a piece of a join as it stands in an interpolation: a literal's text (a raw one's escaped), a
# value in braces
fn piecePart(piece str):
	if piece[0] == '"' and stringEnd(piece, 0) == piece.len: return piece[1..len - 1].copy()
	if piece.startsWith("r\"") and stringEnd(piece, 1) == piece.len:
		return piece[2..len - 1].replace("\\", "\\\\").replace(r"{", r"\{").replace(
			"}",
			"\\}"
		)
	v = piece.copy()
	if v.startsWith("str(") and closingOf(v, 3) == v.len:
		v = v[4..len - 1].trimmed().copy()
	if v.startsWith("(") and closingOf(v, 0) == v.len and
		topColon(v[1..len - 1]) < 0:
		v = v[1..len - 1].trimmed().copy()
	"\{({v})}" if topColon(v) >= 0 else "\{{v}}"

# the end (the index past it) of a comparison's value starting at from: the top-level `,`, `)`,
# `]`, `:` (a block's), `#`, ` and `, ` or ` (also ending the line, the condition going on
# below) or ` ? ` after it, or the line's end (a binary operator inside the value, as `r - row`,
# continues it)
fn valueEnd(text str, from i64):
	depth = 0
	i = from
	while i < text.len:
		b = text[i]
		if b == '\'' and i + 2 < text.len:
			i += 4 if text[i + 1] == '\\' else 3
			continue
		if b == '"':
			i += 1
			while i < text.len and text[i] != '"':
				if text[i] == '\\':
					i += 1
				i += 1
		elif b in ['(', '[', '{']:
			depth += 1
		elif b in [')', ']', '}']:
			if depth == 0: return i
			depth -= 1
		elif depth == 0 and
			(b == ',' or b == '#' or b == ':' and (i + 1 == text.len or text[i + 1] == ' ')):
			return i
		elif depth == 0 and b == ' ':
			rest = text[i..]
			if rest.startsWith(" and ") or rest.startsWith(" or ") or rest.startsWith(" ? ") or
				rest.startsWith(" #") or rest == " and" or rest == " or" or
				rest.startsWith(" else ") or
				rest.startsWith(" if "):
				return i
		i += 1
	i

# the end (the index past it) of the last piece of a join, which starts at from or on the line
# below (a `move` or `try` before it, a blank after it ends it): a top-level blank, comma, closing bracket, colon or
# line break, with strings and brackets skipped; -1 when there is none or a string does not close
fn pieceEnd(text str, from i64):
	i = from
	while i < text.len and (text[i] in [' ', '\t', '\n']):
		i += 1
	for word in ["move ", "try "]:
		if text[i..].startsWith(word):
			i += word.len
	begin = i
	depth = 0
	while i < text.len:
		b = text[i]
		if b == '"' or b == '\'':
			i = literalEnd(text, i)
			if i < 0: return -1
			continue
		if b in ['(', '[', '{']:
			depth += 1
		elif b in [')', ']', '}']:
			if depth == 0: break
			depth -= 1
		elif b == '\n' and depth > 0:
			return -1
		elif depth == 0 and (b in [' ', '\t', ',', ':', '\n', '#']):
			break
		i += 1
	-1 if i == begin else i

# x in xs: xs.contains(x) for a list, a str or a type with a contains method, the map's own test
# for a map (its keys); with a list literal
# on the right (x in [a, b, c]) the comparisons x == a or x == b or x == c, no list made, when x
# is a name, a field or a literal (read once per comparison; a call's value asks the list); with
# a range on the right (x in lo..hi) lo <= x and x < hi, x as simple. Checked as the form it
# stands for.
# operands of no common type: checked again when a binding retypes to the other's, else reported
fn mixedOperands(mut c Checker, e NodeId, lhs NodeId, lt TypeId, rhs NodeId, rt TypeId) TypeId:
	if c.retypeFlex(lhs, rt): return c.typed(e, rt)   # checked again with the binding of type rt
	if c.retypeFlex(rhs, lt): return c.typed(e, lt)
	c.errorTyped(nodes[e].line, nodes[e].col, c.operandsError("MixedTypes", lt, rt))

# for k counting over src (lo..hi or a list named), the count of its elements and the element k
# stands for; none after the error
fn parallelCounted(mut c Checker, src NodeId, k NodeId, line i64, col i64) (NodeId, NodeId)?:
	sk = nodes[src].kind
	if sk == nRange and nodes[src].kids(kidIds).len == 2:
		lo = nodes[src].kids(kidIds)[0]
		if not c.readsAgain(lo) or not c.readsAgain(nodes[src].kids(kidIds)[1]):
			c.errorAt(line, col, compileError("ParallelRangeBounds", []))
			return none
		count = c.binaryNode(
			binSub,
			cloneTree(nodes, kidIds, nodes[src].kids(kidIds)[1]),
			cloneTree(nodes, kidIds, lo),
			line,
			col
		)
		return (count, c.binaryNode(binAdd, cloneTree(nodes, kidIds, lo), k, line, col))
	if sk == nIdent or sk == nField:
		count = lenOf(nodes, kidIds, line, col, cloneTree(nodes, kidIds, src))
		return (
			count,
			newNode(nodes, kidIds, nIndex, line, col, kids = [cloneTree(nodes, kidIds, src), k])
		)
	c.errorAt(line, col, compileError("ParallelSourceUnbound", []))
	none

# what a value expected of type t is checked against: an integer's range base, else t
fn baseExpected(c Checker, maybeT TypeId?) TypeId?:
	t = try maybeT
	rangeBase(tys, t) if c.tKind(t) == tInt else t

# `x == v` for `x in [..., v, ...]`, x written again
fn equalityOf(mut c Checker, x NodeId, v NodeId):
	eq = newNode(
		nodes,
		kidIds,
		nBinary,
		nodes[v].line,
		nodes[v].col,
		kids = [cloneTree(nodes, kidIds, x), v]
	)
	nodes[eq].ival = binEq
	eq

fn checkMembership(mut c Checker, e NodeId) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	lhs = nodes[e].kids(kidIds)[0]
	rhs = nodes[e].kids(kidIds)[1]
	simple = nodes[lhs].kind in [nIdent, nField, nInt, nFloat, nStr]
	if nodes[rhs].kind == nArray and not nodes[rhs].kids(kidIds).isEmpty and simple:
		values = nodes[rhs].kids(kidIds).copy()
		chain = c.equalityOf(lhs, values[0])
		for v in values[1..]:
			eq = c.equalityOf(lhs, v)
			chain = newNode(nodes, kidIds, nBinary, line, col, kids = [chain, eq])
			nodes[chain].ival = binOr
		nodes[e] = nodes[chain].copy()
		nodes[e].flags |= flagInternal
		return c.checkExpr(e, tyBool)
	if nodes[rhs].kind == nRange and nodes[rhs].kids(kidIds).len == 2 and
		not nodes[rhs].hasFlag(flagOpenEnd):
		if not simple:
			c.errorAt(line, col, compileError("InRangeNeedsName", []))
			return c.typed(e, tyError)
		low = newNode(
			nodes,
			kidIds,
			nBinary,
			line,
			col,
			kids = [nodes[rhs].kids(kidIds)[0], cloneTree(nodes, kidIds, lhs)]
		)
		nodes[low].ival = binLe
		high = newNode(nodes, kidIds, nBinary, line, col, kids = [lhs, nodes[rhs].kids(kidIds)[1]])
		nodes[high].ival = binLt
		nodes[low].flags |= flagInternal   # (`a in 0..n` of a natural: its 0 <= a is no test written)
		nodes[high].flags |= flagInternal
		nodes[e].ival = binAnd
		nodes[e].setKids(kidIds, [low, high])
		nodes[e].flags |= flagInternal
		return c.checkExpr(e, tyBool)
	rt = c.derefIfRef(rhs, c.checkExpr(rhs, none))
	rk = c.tKind(rt)
	if rk == tError: return c.typed(e, tyError)
	# a type of its own answers by its contains method (h in pool)
	own = (rk == tStruct or rk == tEnum) and c.findMethod(tys[rt].name, "contains") != none
	if rk != tList and rk != tStr and rk != tMap and not own:
		errorAt(
			c,
			line,
			col,
			compileError("InNotSupported", ["{c.showTy(rt)}"])
		)
		return c.typed(e, tyError)
	callee = newNode(
		nodes,
		kidIds,
		nField,
		line,
		col,
		text = "has" if rk == tMap else "contains",
		kids = [rhs]
	)
	nodes[e].kind = nCall
	nodes[e].setKids(kidIds, [callee, lhs])
	nodes[e].flags |= flagInternal
	c.checkExpr(e, tyBool)

# `xs.contains(x)` written by a program (the checker makes the call for `x in xs`, and the runtime
# implements it): no method
fn containsCallWritten(mut c Checker, e NodeId, shown str):
	if nodes[e].hasFlag(flagInternal) or c.inRuntimeOrDerived(): return false
	c.errorAt(nodes[e].line, nodes[e].col, compileError("NoMethod", ["contains", shown.copy()]))
	true

# `f(x, a)` (or `module.f(x, a)`) where f takes x's type first and x.f(a) calls it, x a struct,
# an enum or the byte of the runtime's byte tests: the method's form, when x is a name, a field,
# an element or a call written on the call's line
fn noteReceiverCall(mut c Checker, e NodeId, fd NodeId):
	if not noting or nodes[e].hasFlag(flagInternal) or c.argCount(e) < 1: return
	arg = c.argAt(e, 0)
	if nodes[arg].kind not in [nIdent, nField, nCall, nIndex] or nodes[arg].ty == none or
		not c.callsAsMethod(fd, typeOf(nodes, arg)):
		return
	name = nodes[fd].text2().copy()
	callee = nodes[e].kids(kidIds)[0]
	line = nodes[callee].line
	text = sourceLineOf(c.file if c.curFile == "" else c.curFile, line)
	at = nodes[callee].col - 1
	if at < 0 or at + name.len >= text.len or text[at..at + name.len + 1] != "{name}(": return
	start = at
	if at >= 2 and text[at - 1] == '.':
		# module.f(x): the module's alias (a value before the name is a method's call already)
		start = at - 1
		while start > 0 and text[start - 1].isWordByte():
			start -= 1
		if start == at - 1 or c.findImportByAlias(c.curMod, text[start..at - 1]) == none: return
	if start > 0 and (text[start - 1].isWordByte() or text[start - 1] == '.'): return
	open = at + name.len
	end = firstArgumentEnd(text, open + 1)
	# the argument written there (not a self a method's bare call passes)
	if end < 0 or nodes[arg].line != line or nodes[arg].col - 1 <= open or
		nodes[arg].col - 1 >= end:
		return
	recv = text[open + 1..end].trimmed()
	if recv.isEmpty or not recv[0].isWordByte() or recv.startsWith("move ") or
		recv.startsWith("mut "):
		return
	if text[end] == ',' and (end + 1 >= text.len or text[end + 1] != ' '): return
	cut = end + 2 - start if text[end] == ',' else end - start
	# an operator's value (a + b of tensors or grids, made a call) is the receiver in parentheses
	receiver = recv.copy() if spaceAtTop(recv) < 0 else "({recv})"
	c.canonNote(noteReplace, line, start + 1, cut, "{receiver}.{name}(")

# the index of the first space of text outside its brackets, -1 when it has none
fn spaceAtTop(text str):
	depth = 0
	for i, b in text:
		if b in ['(', '[', '{']:
			depth += 1
		elif b in [')', ']', '}']:
			depth -= 1
		elif b == ' ' and depth == 0:
			return i
	-1

# whether `x.f()` of an x of type t calls the function fd: x a struct, an enum or the byte of
# the runtime's byte tests (isDigit(c)), with no method, field or other function of f's name, and
# not a struct of one number type, whose method of a number's name is done field by field
fn callsAsMethod(mut c Checker, fd NodeId, t0 TypeId):
	t = innerOf(tys, t0) if c.tKind(t0) == tRef else t0
	k = c.tKind(t)
	byteTest = nodes[fd].mod() == "rt" and isSameType(tys, t, tyInt(8, false))
	if k != tStruct and k != tEnum and not byteTest: return false
	name = nodes[fd].text2().copy()
	if k == tStruct and c.fieldwiseArity(name) >= 0 and c.uniformNumberField(t) != none:
		return false
	not (
		c.findMethod(tys[t].name, name) != none or
			k == tStruct and c.kidNamed(declOf(tys, t), name) != none or
			c.receiverFunctions(t, name) != [fd]
	)

# the index of the `,` or `)` that ends the argument starting at k of a call written on one
# line, -1 when it goes on past the line or holds a string or a comment
fn firstArgumentEnd(text str, k i64):
	depth = 0
	for i in k..text.len:
		b = text[i]
		if b in ['"', '\'', '#']: return -1
		if b in ['(', '[', '{']:
			depth += 1
		elif b in [')', ']', '}']:
			if depth == 0: return i if b == ')' else -1
			depth -= 1
		elif b == ',' and depth == 0:
			return i
	-1

# the start of the receiver whose `.` is at dot: a chain of names, fields, indexes and calls, or
# a list literal, a group or a string literal with such a chain after it
fn receiverStart(text str, dot i64):
	k = dot
	while k > 0:
		b = text[k - 1]
		if b.isWordByte() or b == '.':
			k -= 1
		elif b == ')' or b == ']':
			open = openingAt(text, k - 1)
			if open < 0: return -1
			k = open
		elif b == '"':
			q = k - 2
			while q >= 0 and (text[q] != '"' or q > 0 and text[q - 1] == '\\'):
				q -= 1
			if q < 0: return -1
			k = q
			break
		else:
			break
	if k == dot or
		not (text[k].isWordStart() or text[k] == '[' or text[k] == '(' or text[k] == '"'):
		return -1
	if k > 0 and (text[k - 1].isWordByte() or text[k - 1] == '.'): return -1   # a call's or a field's bracket
	k

# the index past the `)` (or `]`) closing the bracket at open, strings skipped, or -1
fn closingAt(text str, open i64):
	depth = 0
	i = open
	while i < text.len:
		b = text[i]
		if b == '"':
			i += 1
			while i < text.len and text[i] != '"':
				if text[i] == '\\':
					i += 1
				i += 1
		elif b == '(' or b == '[':
			depth += 1
		elif b == ')' or b == ']':
			depth -= 1
			if depth == 0: return i + 1
		i += 1
	-1

# the index of the bracket that the `)` or `]` at close closes, or -1
fn openingAt(text str, close i64):
	depth = 0
	i = close
	while i >= 0:
		b = text[i]
		if b == ')' or b == ']':
			depth += 1
		elif b == '(' or b == '[':
			depth -= 1
			if depth == 0: return i
		i -= 1
	-1

# `x == a or x == b or x == c` (three or more, one name or field on the left): noted for zap fmt
# as `x in [a, b, c]`
fn noteEqualsChain(mut c Checker, e NodeId):
	if not noting: return
	line = nodes[e].line
	eqs NodeId[] = []
	ors NodeId[] = []
	n = e
	while nodes[n].kind == nBinary and nodes[n].ival == binOr and nodes[n].line == line:
		ors.insert(0, n)
		eqs.insert(0, nodes[n].kids(kidIds)[1])
		n = nodes[n].kids(kidIds)[0]
	eqs.insert(0, n)
	if eqs.len < 3: return
	src = c.file if c.curFile == "" else c.curFile
	text = sourceLineOf(src, line)
	subject = ""
	for q in eqs:
		if nodes[q].kind != nBinary or nodes[q].ival != binEq or nodes[q].line != line: return
		l = nodes[q].kids(kidIds)[0]
		if nodes[l].kind != nIdent and nodes[l].kind != nField: return
		at = nodes[q].col - 1
		if at < 2 or at + 2 > text.len or text[at..at + 2] != "==": return
		lstart = receiverStart(text, at - 1)
		if lstart < 0: return
		name = text[lstart..at].trimmed()
		if subject.isEmpty:
			subject = name.copy()
		elif name != subject: return
	first = nodes[eqs[0]].col - 1
	start = receiverStart(text, first - 1)
	last = eqs[len - 1]
	end = valueEnd(text, nodes[last].col + 2)
	if start < 0 or end <= nodes[last].col + 2: return
	values = []
	for i in 0..eqs.len:
		vfrom = nodes[eqs[i]].col + 2
		vto = i64(nodes[ors[i]].col - 1) if i + 1 < eqs.len else end
		v = text[vfrom..vto].trimmed()
		if v.isEmpty or "\"" in v and r"{" in v: return
		values.push(v.copy())
	formNotes = formNotes.filter(n:
		n.file != notePath(src) or n.line != line or n.col <= start or n.col > end
	)
	c.canonNote(noteReplace, line, start + 1, end - start, "{subject} in [{values.join(", ")}]")

# `xs.len == 0` (or != 0, > 0) on a list, a str or a map, written as a place: noted for zap fmt
# as xs.isEmpty (or !xs.isEmpty)
fn noteEmptyTest(mut c Checker, e NodeId, op i64):
	if not noting: return
	lhs = nodes[e].kids(kidIds)[0]
	rhs = nodes[e].kids(kidIds)[1]
	if nodes[rhs].kind != nInt or nodes[rhs].text != "0" or nodes[lhs].kind != nCall: return
	# the call as written, or as checkRuntimeMethod rewrote it
	method = nodes[lhs].hasFlag(flagMethod)
	if nodes[lhs].kids(kidIds).len != (2 if method else 1): return
	callee = c.writtenCallee(lhs)
	if nodes[callee].kind != nField or nodes[callee].text != "len" or
		nodes[callee].kids(kidIds).len != 1:
		return
	rt = nodes[nodes[callee].kids(kidIds)[0]].ty ?? return
	k = c.tKind(tys[rt].inner if c.tKind(rt) == tRef else rt)
	if k != tList and k != tStr and k != tMap: return
	src = c.file if c.curFile == "" else c.curFile
	text = sourceLineOf(src, nodes[e].line)
	at = nodes[e].col - 1   # the operator
	if at < 4 or at >= text.len: return
	before = text[..at].trimmedEnd()
	if not before.endsWith(".len"): return
	start = before.len - 4
	end = start
	# the receiver as written: names, fields, indexes and calls (what is in brackets taken whole)
	going = true
	while going and start > 0:
		b = text[start - 1]
		if b.isWordByte() or b == '.':
			start -= 1
		elif b == ']' or b == ')':
			closer = b
			depth = 0
			back = start - 1
			while back >= 0 and (depth > 0 or text[back] == closer):
				if text[back] == closer: depth += 1
				if text[back] == ('[' if closer == ']' else '('): depth -= 1
				back -= 1
			if depth != 0 or back < 0: return
			start = back + 1
		else:
			going = false
	if start == end or not text[start].isWordStart() or ".." in text[start..end] or
		"\"" in text[start..end]:
		return
	j = at + (1 if op == binGt else 2)
	while j < text.len and text[j] == ' ':
		j += 1
	if j >= text.len or text[j] != '0' or (j + 1 < text.len and text[j + 1].isWordByte()): return
	place = text[start..end]
	canonNote(
		c,
		noteReplace,
		nodes[e].line,
		start + 1,
		j + 1 - start,
		"{("" if op == binEq else "not ")}{place}.isEmpty"
	)
