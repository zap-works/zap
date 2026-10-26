# Type checker, patterns: a match's arms, each pattern checked against the value it tests (its
# names bound, each part a pattern of its own), and whether the arms cover every value.

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# A match on a value of type scrutT: each arm's pattern checked and its names bound, then its
# condition and body (checkArmRest); the arms without a condition must cover every value.
fn checkMatchArms(mut c Checker, e NodeId, scrutT TypeId, expected TypeId?) TypeId:
	isStmt = c.matchStmt
	c.matchStmt = false
	sk = c.tKind(scrutT)
	# a name written `mut` points into the matched value and may change it when the value is a
	# mutable place
	bm = sk in [tEnum, tOption, tStruct, tList] and not nodes[e].hasFlag(flagInternal) and
		c.bindMut(e, scrutT)
	lent = c.lookupCall(nodes[e].kids(kidIds)[0]) if sk == tOption else none
	literal = sk in [tInt, tFloat, tStr, tBool]
	resultT = expected
	alts {i64: str} = {}
	rows NodeId?[,] = []
	catchAll = false
	takenOk = false
	takenErr = false
	patternErrors = 0
	boolArms = []   # the truths the arms before took (a bool's match)
	for arm in c.matchArms(e):
		pat = c.armPattern(arm)
		pk = nodes[pat].ival
		aline = nodes[arm].line
		acol = nodes[arm].col
		guarded = c.armGuard(arm) != none   # an arm with a condition may not run: it covers nothing
		whole = pk == patWildcard or pk == patBind and nodes[pat].kids(kidIds).isEmpty
		c.enterScope()
		if literal and catchAll:
			c.errorAt(
				aline,
				acol,
				compileError("UnreachableArm", ["a catch-all arm comes before it"])
			)
		if sk == tResult and pk == patBind:
			isErr = nodes[pat].bindsError()
			taken = takenErr if isErr else takenOk
			if taken:
				side = "error" if isErr else "value"
				c.errorAt(
					aline,
					acol,
					compileError(
						"UnreachableArm",
						["an arm before it takes the {side} (a match on a result names its error's arm error:, any other name takes the value)"]
					)
				)
			if not guarded and nodes[pat].kids(kidIds).isEmpty:
				if isErr:
					takenErr = true
				else:
					takenOk = true
		before = c.errors
		c.checkPat(e, pat, scrutT, true, bm, lent, aline, acol)
		patternErrors += c.errors - before
		if not guarded:
			rows.push([pat])
			catchAll = catchAll or whole
		if sk == tBool and not guarded:
			c.narrowByArm(e, pat, whole, boolArms)
		resultT = c.checkArmRest(e, arm, resultT, expected, isStmt, alts)
		c.exitScope()
	missing = ""
	if patternErrors == 0 and sk != tError:
		if c.patMissing(rows, [scrutT], true) is w:
			missing = c.missingMessage(scrutT, w[0])
	c.matchEnd(e, resultT, isStmt, missing)

# An arm of a match on a bool (`a if c else b`) runs knowing its truth: the scrutinee's
# comparisons narrow its variables there (ranges.zap) as an `if` statement's do, the catch-all
# arm after one truth knowing the other.
fn narrowByArm(mut c Checker, e NodeId, pat NodeId, whole bool, mut boolArms i64[]):
	if nodes[pat].ival == patLit and nodes[nodes[pat].kids(kidIds)[0]].kind == nBool:
		truth = nodes[nodes[pat].kids(kidIds)[0]].ival
		c.narrowBy(nodes[e].kids(kidIds)[0], truth == 1)
		boolArms.push(truth)
	elif whole and boolArms.len == 1:
		c.narrowBy(nodes[e].kids(kidIds)[0], boolArms[0] != 1)

# the type whose values a match takes patterns of
fn isMatchable(c Checker, t TypeId):
	c.tKind(t) in [tEnum, tOption, tResult, tInt, tFloat, tStr, tBool, tStruct, tList, tMap]

# the error for a match whose arms leave the value w (a pattern's text) out
fn missingMessage(c Checker, scrutT TypeId, w str):
	compileError("NonExhaustiveMatch", [c.missingPart(scrutT, w)])

# what missingMessage says after "non-exhaustive match"
fn missingPart(c Checker, scrutT TypeId, w str):
	sk = c.tKind(scrutT)
	if sk == tEnum and "(" not in w: return ": variant '{w}' not handled"
	if sk == tOption and w in ["none", "_"]: return " on optional (need a value arm and 'none')"
	if sk == tResult and w in ["error", "_"]: return " on result (need an ok arm and an error arm)"
	if sk in [tInt, tFloat, tStr, tBool, tMap] or w == "_":
		return " on {c.showTy(scrutT)}: add a final '_' arm"
	": {w} not handled"

# the type a pattern reads a value of type t as: a reference's target
fn patType(c Checker, t TypeId):
	if c.tKind(t) == tRef: return innerOf(tys, t)
	t

# whether t is a tuple: the runtime's struct of fields _0, _1...
fn isTupleType(c Checker, t TypeId):
	c.tKind(t) == tStruct and not nodes[declOf(tys, t)].kids(kidIds).isEmpty and
		nodes[nodes[declOf(tys, t)].kids(kidIds)[0]].text == "_0"

# the name a struct's pattern calls its type by: its declaration's, without type arguments
fn structPatternName(c Checker, t TypeId):
	d = tys[t].display
	cut = d.indexOf("<") ?? d.len
	from = (d[..cut].lastIndexOf(".") ?? -1) + 1
	d[from..cut].copy()

# whether name is a variant of the enum t
fn isVariantOf(c Checker, t TypeId, name str):
	c.tKind(t) == tEnum and c.kidNamed(declOf(tys, t), name) != none

# the side of a result t a variant's pattern tests: the error's when its enum has the variant
# and the value's does not
fn testsError(c Checker, t TypeId, pat NodeId):
	nodes[pat].ival == patCtor and c.isVariantOf(errOf(tys, t), nodes[pat].text) and
		not c.isVariantOf(innerOf(tys, t), nodes[pat].text)

# the parts of a variant's or a struct's pattern by field of holder (its declaration, or the
# variant): each the pattern written for it, or none (anything)
fn patParts(c Checker, pat NodeId, holder NodeId):
	n = nodes[holder].kids(kidIds).len
	out NodeId?[] = zeros(n)
	for i in 0..nodes[pat].kids(kidIds).len:
		name = nodes[pat].names()[i] if i < nodes[pat].names().len else ""
		at = i if name == "" else c.fieldIndexOf(holder, name)
		if at >= 0 and at < n:
			out[at] = nodes[pat].kids(kidIds)[i]
	out

# The pattern pat checked against a value of type t0 (top: the matched value itself, whose
# optional a name takes the value of, and whose result a name the value or, as `error`, the
# error), the names it binds added (bm: changeable; lent: the lookup an optional came from).
fn checkPat(
	mut c Checker,
	e NodeId,
	pat NodeId,
	t0 TypeId,
	top bool,
	bm bool,
	lent NodeId?,
	line i64,
	col i64
):
	k = nodes[pat].ival
	t = c.patType(t0)
	sk = c.tKind(t)
	if sk == tError or k == patWildcard: return
	if k == patBind: return c.checkBindPat(e, pat, t0, top, bm, lent, line, col)
	if sk == tOption:
		inner = c.innerOrError(t)
		if k == patNone or k == patCtor and nodes[pat].text == "None": return
		if k == patCtor and nodes[pat].text == "Some":
			if nodes[pat].kids(kidIds).len == 1:
				c.checkPat(e, nodes[pat].kids(kidIds)[0], inner, false, bm, lent, line, col)
			return
		c.checkPat(e, pat, inner, false, bm, lent, line, col)   # any pattern of the value
		return
	if k == patNone:
		c.errorAt(line, col, compileError("NonePatternNotOptional", []))
		return
	if sk == tResult:
		okT = c.innerOrError(t)
		errT = tyError if tys[t].err == none else errOf(tys, t)
		if k == patCtor and nodes[pat].text in ["Ok", "Err"]:
			if nodes[pat].kids(kidIds).len == 1:
				checkPat(
					c,
					e,
					nodes[pat].kids(kidIds)[0],
					okT if nodes[pat].text == "Ok" else errT,
					false,
					bm,
					lent,
					line,
					col
				)
			return
		c.checkPat(e, pat, errT if c.testsError(t, pat) else okT, false, bm, lent, line, col)
		return
	if k == patCtor:
		c.checkPatCtor(e, pat, t0, t, sk, bm, lent, line, col)
		return
	if k == patTuple:
		n = nodes[pat].kids(kidIds).len
		if not c.isTupleType(t) or nodes[declOf(tys, t)].kids(kidIds).len != n:
			c.errorAt(line, col, compileError("TuplePatternDoesNotFit", ["{n}", "{c.showTy(t0)}"]))
			return
		c.checkParts(e, pat, declOf(tys, t), bm, lent, line, col)
		return
	if k == patLit:
		c.checkPatLit(pat, t, sk, line, col)
		return
	if k == patRange:
		c.checkPatRange(pat, t, sk, line, col)
		return
	if k == patList:
		c.checkPatList(e, pat, t0, t, sk, bm, lent, line, col)
		return
	if k == patStr:
		if sk != tStr:
			c.errorAt(line, col, compileError("StrPatternDoesNotFit", ["{c.showTy(t0)}"]))
			return
		for kid in nodes[pat].kids(kidIds).copy():
			if nodes[kid].ival == patBind:
				c.addVar(nodes[kid].text, tyRef(tys, tyStr, false), false, true, line, col)   # lent, as s.slice(a, b)
		return
	if k == patMap:
		if sk != tMap:
			c.errorAt(line, col, compileError("MapPatternDoesNotFit", ["{c.showTy(t0)}"]))
			return
		c.checkMapPat(e, pat, t, lent, line, col)
		return
	c.errorAt(line, col, compileError("PatternDoesNotFitValue", ["{c.showTy(t0)}"]))

# A name pat binds checked against a value of type t0, as checkPat checks a pattern
fn checkBindPat(
	mut c Checker,
	e NodeId,
	pat NodeId,
	t0 TypeId,
	top bool,
	bm bool,
	lent NodeId?,
	line i64,
	col i64
):
	t = c.patType(t0)
	sk = c.tKind(t)
	if nodes[pat].hasFlag(flagSafe):
		c.bindSafeName(pat, nodes[e].kids(kidIds)[0], c.innerOrError(t), line, col)   # a `?.` call checked again
		return
	bt = t0
	if top and sk == tOption:
		bt = c.innerOrError(t)
	elif top and sk == tResult:
		bt = errOf(tys, t) if nodes[pat].bindsError() else c.innerOrError(t)
	tested = top and nodes[pat].hasFlag(flagIsTest)
	if nodes[pat].hasFlag(flagMut) and not bm and
		not c.mutNameHasPlace(nodes[e].kids(kidIds)[0], line, col):
		c.errorAt(
			nodes[pat].line,
			nodes[pat].col,
			compileError("MutNameNoPlace", ["{nodes[pat].text}"])
		)
	if bm and nodes[pat].hasFlag(flagMut) and c.tKind(bt) == tRef and tys[bt].bits == 0:
		bt = tyRef(tys, innerOf(tys, bt), true)   # `is mut t`: the place it lends takes what t is assigned
	v = c.addVar(nodes[pat].text, bt, bm and nodes[pat].hasFlag(flagMut), not tested, line, col)
	c.vars[v].lentFrom = lent
	c.vars[v].isTest = tested
	if not nodes[pat].kids(kidIds).isEmpty:
		c.checkPat(e, nodes[pat].kids(kidIds)[0], bt, false, bm, lent, line, col)

fn checkPatCtor(
	mut c Checker,
	e NodeId,
	pat NodeId,
	t0 TypeId,
	t TypeId,
	sk i64,
	bm bool,
	lent NodeId?,
	line i64,
	col i64
):
	name = nodes[pat].text
	if sk == tEnum:
		match c.kidNamed(declOf(tys, t), name):
			v: c.checkParts(e, pat, v, bm, lent, line, col)
			none:
				c.errorAt(
					line,
					col,
					compileError("NotAVariant", ["{name}", "{nodes[declOf(tys, t)].text}"])
				)
		return
	if sk == tStruct and not c.isTupleType(t) and c.structPatternName(t) == name:
		c.checkParts(e, pat, declOf(tys, t), bm, lent, line, col)
		return
	c.errorAt(line, col, compileError("PatternDoesNotFit", ["{name}", "{c.showTy(t0)}"]))
	return

fn checkPatLit(mut c Checker, pat NodeId, t TypeId, sk i64, line i64, col i64):
	if sk == tEnum:
		c.errorAt(
			line,
			col,
			compileError("EnumPatternLiteral", ["{nodes[declOf(tys, t)].text2()}"])
		)
		return
	lt = c.checkExpr(nodes[pat].kids(kidIds)[0], t)
	if not isSameType(tys, lt, t):
		errorAt(
			c,
			line,
			col,
			compileError("PatternType", ["{c.showTy(lt)}", "{c.showTy(t)}"])
		)
	return

fn checkPatRange(mut c Checker, pat NodeId, t TypeId, sk i64, line i64, col i64):
	if sk != tInt and sk != tFloat:
		errorAt(
			c,
			line,
			col,
			compileError("RangePatternNotNumber", ["{c.showTy(t)}"])
		)
		return
	for lit in nodes[pat].kids(kidIds).copy():
		lt = c.checkExpr(lit, t)
		if not isSameType(tys, lt, t):
			errorAt(
				c,
				line,
				col,
				compileError("PatternType", ["{c.showTy(lt)}", "{c.showTy(t)}"])
			)
	return

fn checkPatList(
	mut c Checker,
	e NodeId,
	pat NodeId,
	t0 TypeId,
	t TypeId,
	sk i64,
	bm bool,
	lent NodeId?,
	line i64,
	col i64
):
	if sk != tList:
		c.errorAt(line, col, compileError("ListPatternDoesNotFit", ["{c.showTy(t0)}"]))
		return
	elem = c.innerOrError(t)
	for kid in nodes[pat].kids(kidIds).copy():
		if nodes[kid].ival != patRest:
			c.checkPat(e, kid, elem, false, bm, lent, line, col)
		elif nodes[kid].text != "":
			c.addVar(nodes[kid].text, tyRef(tys, t, false), false, true, line, col)   # lent, as xs[1..]
	return

# the name a map's pattern looks its keys up in (the map matched, bound by the lowering)
mapPatternName = "$map"

# A map's pattern: each key a lookup `$map.get(key)` (made once, kept in place of the key), whose
# value, which must be there, the pattern after it tests.
fn checkMapPat(mut c Checker, e NodeId, pat NodeId, t TypeId, lent NodeId?, line i64, col i64):
	c.addVar(mapPatternName, t, false, true, line, col)
	for i in 0..nodes[pat].kids(kidIds).len / 2:
		lookup = nodes[pat].kids(kidIds)[2 * i]
		if nodes[lookup].kind != nCall:
			m = newNode(nodes, kidIds, nIdent, line, col, text = mapPatternName)
			get = newNode(nodes, kidIds, nField, line, col, text = "get", kids = [m])
			lookup = newNode(nodes, kidIds, nCall, line, col, kids = [get, lookup])
			nodes[pat].setKid(kidIds, 2 * i, lookup)
		found = c.checkExpr(lookup, none)
		if c.tKind(found) == tOption:
			checkPat(
				c,
				e,
				nodes[pat].kids(kidIds)[2 * i + 1],
				c.innerOrError(found),
				false,
				false,
				lent,
				line,
				col
			)

# the parts of a variant's or a struct's pattern checked against holder's fields: all of them by
# position, or some by name
fn checkParts(
	mut c Checker,
	e NodeId,
	pat NodeId,
	holder NodeId,
	bm bool,
	lent NodeId?,
	line i64,
	col i64
):
	name = nodes[pat].text.copy()   # (checking changes c.nodes)
	n = nodes[holder].kids(kidIds).len
	kids = nodes[pat].kids(kidIds).copy()
	byName = nodes[pat].names().copy()
	if nodes[pat].hasFlag(flagWritten) and byName.all(it == "") and kids.len != n and
		nodes[pat].ival == patCtor:
		c.errorAt(line, col, compileError("VariantBindingCount", ["{name}", "{n}", "{kids.len}"]))
		return
	for i, kid in kids:
		at = i
		if i < byName.len and byName[i] != "":
			at = c.fieldIndexOf(holder, byName[i])
			if at < 0:
				c.errorAt(line, col, compileError("NoField", ["{name}", "{byName[i]}"]))
				continue
		if at >= n: continue
		ft = c.resolveType(nodes[nodes[holder].kids(kidIds)[at]].types()[0])
		c.checkPat(e, kid, ft, false, bm, lent, line, col)

# the names a pattern binds, its parts' included
pub fn patternNames(c Checker, pat NodeId, mut out str[]):
	if nodes[pat].kind != nPattern: return
	k = nodes[pat].ival
	if (k == patBind or k == patRest) and nodes[pat].text != "":
		out.push(nodes[pat].text.copy())
	for kid in nodes[pat].kids(kidIds):
		c.patternNames(kid, out)   # (a map's lookups are no patterns)

# ---------- exhaustiveness ----------

# What a pattern tests first of a value: key -1 nothing (it matches anything), -2 something no
# list of cases covers (a number, a text); else the case (a variant's index, a bool, an
# optional's 0 none and 1 a value, a result's 0 error and 1 value, a struct's 0, a list's length)
# and the patterns of its parts (-1: anything). A list's pattern with ..rest (atLeast) takes
# that length or more, the rest between parts[restAt - 1] and parts[restAt].
type PatHead:
	key i64
	parts NodeId?[] = []   # the patterns of the parts, none for any
	atLeast bool = false
	restAt i64 = 0

# a case of a type: its key, the types of its parts, whether it is a list's lengths from that
# many parts on
type PatCase:
	key i64
	types TypeId[]
	atLeast bool = false

fn headOf(c Checker, maybePat NodeId?, t0 TypeId, top bool) PatHead:
	pat = maybePat ?? return PatHead(key = -1)
	t = c.patType(t0)
	sk = c.tKind(t)
	k = nodes[pat].ival
	if k == patWildcard: return PatHead(key = -1)
	if k == patBind:
		sub = nodes[pat].kids(kidIds).first
		if top and sk == tOption: return PatHead(key = 1, parts = [sub])
		if top and sk == tResult:
			return PatHead(key = 0 if nodes[pat].bindsError() else 1, parts = [sub])
		return c.headOf(sub, t0, false)
	if sk == tOption:
		if k == patNone or k == patCtor and nodes[pat].text == "None": return PatHead(key = 0)
		if k == patCtor and nodes[pat].text == "Some":
			return PatHead(key = 1, parts = [nodes[pat].kids(kidIds).first])
		return PatHead(key = 1, parts = [pat])
	if sk == tResult:
		if k == patCtor and nodes[pat].text in ["Ok", "Err"]:
			return PatHead(
				key = 1 if nodes[pat].text == "Ok" else 0,
				parts = [nodes[pat].kids(kidIds).first]
			)
		return PatHead(key = 0 if c.testsError(t, pat) else 1, parts = [pat])
	if sk == tEnum and k == patCtor:
		vi = nodes[declOf(tys, t)].kids(kidIds).findIndex(nodes[it].text == nodes[pat].text) ?? -1
		if vi < 0: return PatHead(key = -2)
		return PatHead(key = vi, parts = c.patParts(pat, nodes[declOf(tys, t)].kids(kidIds)[vi]))
	if sk == tBool and k == patLit: return PatHead(key = nodes[nodes[pat].kids(kidIds)[0]].ival)
	if sk == tStruct and (k == patCtor or k == patTuple):
		return PatHead(key = 0, parts = c.patParts(pat, declOf(tys, t)))
	if sk == tList and k == patList:
		kids = nodes[pat].kids(kidIds)
		r = kids.findIndex(nodes[it].ival == patRest) ?? -1
		parts NodeId?[] = []
		for kid in kids:
			if nodes[kid].ival != patRest: parts.push(kid)
		return PatHead(key = parts.len, parts, atLeast = r >= 0, restAt = r)
	PatHead(key = -2)

# the cases of type t, every value one of them (none: too many to list); a list's are its
# lengths up to the longest a pattern names, then any longer
fn patCases(mut c Checker, t0 TypeId, heads PatHead[]):
	t = c.patType(t0)
	sk = c.tKind(t)
	if sk == tBool: return [PatCase(key = 0, types = []), PatCase(key = 1, types = [])]
	if sk == tOption:
		return [PatCase(key = 0, types = []), PatCase(key = 1, types = [c.innerOrError(t)])]
	if sk == tResult:
		errT = tyError if tys[t].err == none else errOf(tys, t)
		return [PatCase(key = 0, types = [errT]), PatCase(key = 1, types = [c.innerOrError(t)])]
	if sk == tEnum:
		cases = []
		vs = nodes[declOf(tys, t)].kids(kidIds).copy()
		for i in 0..vs.len:
			types = []
			for f in nodes[vs[i]].kids(kidIds).copy():
				types.push(c.resolveType(nodes[f].types()[0]))
			cases.push(PatCase(key = i, types))
		return cases
	if sk == tStruct:
		sd = declOf(tys, t)
		types = []
		for i in 0..nodes[sd].kids(kidIds).len:
			types.push(c.structFieldTypeAt(sd, i))
		return [PatCase(key = 0, types)]
	if sk == tList:
		elem = c.innerOrError(t)
		longest = 0
		for h in heads:
			if h.key >= 0:
				longest = longest.max(h.parts.len)
		cases = []
		for n in 0..=longest:
			cases.push(PatCase(key = n, types = fill(n, elem)))
		cases.push(PatCase(key = longest + 1, types = fill(longest + 1, elem), atLeast = true))
		return cases
	[]

# a row whose head is h, its head replaced by the parts of case k (none: the row cannot match k)
fn specialized(row NodeId?[], h PatHead, k PatCase) NodeId?[]?:
	n = k.types.len
	out NodeId?[] = []
	if h.key == -1:
		out = zeros(n)
	elif h.atLeast:
		if n < h.parts.len: return none
		out = h.parts[..h.restAt].copy()
		out.extend(zeros(n - h.parts.len))
		out.extend(h.parts[h.restAt..])
	elif h.key != k.key or k.atLeast:
		return none
	else:
		out = h.parts.copy()
	out.extend(row[1..])
	out

# the text of case k of type t, its parts' texts given
fn caseText(c Checker, t0 TypeId, k PatCase, parts str[]):
	t = c.patType(t0)
	sk = c.tKind(t)
	inside = parts.join(", ")
	if sk == tBool: return "true" if k.key == 1 else "false"
	if sk == tOption: return "none" if k.key == 0 else parts[0].copy()
	if sk == tResult: return "error" if k.key == 0 and parts[0] == "_" else parts[0].copy()
	if sk == tEnum:
		name = nodes[nodes[declOf(tys, t)].kids(kidIds)[k.key]].text
		return name.copy() if parts.all(it == "_") else "{name}({inside})"
	if sk == tStruct and c.isTupleType(t): return "({inside})"
	if sk == tStruct: return "{c.structPatternName(t)}({inside})"
	if sk == tList: return "[{inside}, ..]" if k.atLeast else "[{inside}]"
	"_"

# A value of the types no row of patterns matches, as the text of a pattern per type; none when
# the rows cover every value (top: the rows' first patterns are a match's own).
fn patMissing(mut c Checker, rows NodeId?[,], types TypeId[], top bool) str[]?:
	if types.isEmpty:
		if not rows.isEmpty: return none
		found str[] = []
		return found
	t = types[0]
	rest = types[1..].copy()
	heads = rows.map(c.headOf(it[0], t, top))
	cases = c.patCases(t, heads)
	complete = not cases.isEmpty and
		(c.tKind(c.patType(t)) == tList and heads.any(.key >= 0) or
				cases.all(k: heads.any(.key == k.key)))
	if complete:
		for k in cases:
			sub = []
			for i, row in rows:
				if specialized(row, heads[i], k) is r:
					sub.push(r)
			subTypes = k.types.copy()
			subTypes.extend(rest)
			if c.patMissing(sub, subTypes, false) is w:
				n = k.types.len
				out = [c.caseText(t, k, w[..n].copy())]
				out.extend(w[n..].copy())
				return out
		return none
	others = []
	for i in 0..rows.len:
		if heads[i].key == -1:
			others.push(rows[i][1..rows[i].len].copy())
	w = try c.patMissing(others, rest, false)
	first = "_"
	for k in cases:
		if not heads.any(.key == k.key):
			first = c.caseText(t, k, fill(k.types.len, "_"))
			break
	out = [first]
	out.extend(w)
	out
