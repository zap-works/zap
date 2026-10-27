# The checker's errors, empty-list inference, scopes and variables (check.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# an error, held until the body's round ends (a round checked again reports none of its own)
fn errorAt(mut c Checker, line i64, col i64, msg str):
	c.errorsMet += 1
	if c.pending.any(p:
		p.line == line and p.col == col and p.message == msg and
			p.file == (c.file if c.curFile == "" else c.curFile)
	):
		return   # the same place twice (an arm of several patterns)
	c.pending.push(
		PendingError(
			file = (c.file if c.curFile == "" else c.curFile).copy(),
			line,
			col,
			message = msg.copy()
		)
	)
	c.errors += 1

# the inner type of t (an option's, a list's element, a map's key...), or the error type when
# it is not known yet
fn innerOrError(c Checker, t TypeId):
	inner = tys[t].inner ?? return tyError
	inner

# the variable an expression names, or -1
fn varOfExpr(mut c Checker, e NodeId) i64:
	c.lookupVarNo(nameOf(nodes, e)) if nodes[e].kind == nIdent else -1

# whether a type is known to its leaves (no list or optional still waiting for its inner type)
fn typeTold(c Checker, maybeT TypeId?) bool:
	t = maybeT ?? return false
	if c.tKind(t) == tList: return c.typeTold(tys[t].inner)
	if c.tKind(t) == tOption: return tys[t].inner != none and c.typeTold(tys[t].inner)
	true

# A use of a binding made from `[]` that tells its element type (a push, a place of a list type):
# told fixes the binding's type in place, every expression typed with it included. For a binding
# written with its type, inferred (what the use would tell had the type not been written, -1 for
# nothing sure) fixes the shadow zap fmt compares with the written one; -1 gives the shadow up.
fn tellEmptyList(mut c Checker, v i64, told TypeId?, inferred TypeId?):
	if v < 0: return
	t = c.vars[v].emptyInfer ?? return
	if tys[t].inner != none: return
	shadow = t != c.vars[v].ty
	known = inferred if shadow else told
	if known is elem and c.tKind(elem) != tError and c.typeTold(elem):
		tys[t].inner = c.heldType(elem)
	elif shadow:
		c.vars[v].emptyInfer = none   # the written type stays

# whether the list obj names is a `[]` binding whose written type zap fmt may drop because this use
# tells it: the use keeps its conversions (`xs.push(i64(n))`), which would otherwise tell u8 alone
fn tellsEmptyListType(mut c Checker, obj NodeId):
	v = c.varOfExpr(obj)
	v >= 0 and c.vars[v].emptyInfer != none and c.vars[v].emptyInit != none

# a use of the list e names that tells nothing of its element type, where zap fmt would have
# needed one told: the binding's written type stays
fn giveUpEmptyList(mut c Checker, e NodeId):
	c.tellEmptyList(c.varOfExpr(e), none, none)

# the error of the list e read before its element type is told, naming the local
fn untoldList(mut c Checker, e NodeId, line i64, col i64) TypeId:
	v = c.varOfExpr(e)
	named = c.vars[v].name.copy() if v >= 0 else "list"
	c.errorTyped(line, col, compileError("UntoldList", [named]))

# the type a value of type t tells on its own: t, unless the value is a number literal (an i64, a
# u8 for a byte, an f64 then), a list literal (of its first element's) or takes its type from its
# place (none); a value its place widened tells its own type
fn inferredValueType(mut c Checker, e NodeId, t TypeId) TypeId?:
	plain = c.unwidened(e)
	if plain != e: return c.inferredValueType(plain, typeOf(nodes, plain))
	k = nodes[e].kind
	if k == nIdent:
		v = c.varOfExpr(e)
		if v >= 0 and (c.vars[v].flexLet != none or c.vars[v].fromUses): return none   # its type its uses
	if c.tKind(t) == tRef or c.isOptionOfRef(t): return none   # a borrow: the place may have asked for it
	if k == nInt and nodes[e].hasFlag(flagByte): return tyInt(8, false)
	if k == nInt or k == nFloat and not floatLiteralText(nodes[e].text): return tyInt(64, true)
	if k == nFloat: return tyFloat(64)
	if k == nArray:
		if nodes[e].kids(kidIds).isEmpty or c.tKind(t) != tList: return none
		first = c.inferredValueType(nodes[e].kids(kidIds)[0], innerOf(tys, t))
		return none if first == none else tyList(tys, first)
	if c.typeStandsAlone(e): return t
	none

# what a value of type t is as a list's element when pushed: a borrow of plain data is copied in
fn plainElement(mut c Checker, t TypeId):
	innerOf(tys, t) if c.tKind(t) == tRef and c.copiesFreely(innerOf(tys, t)) else t

# the element type a list value of type t tells on its own (inferredValueType), or none
fn inferredElemType(mut c Checker, e NodeId, t TypeId) TypeId?:
	inf = c.inferredValueType(e, t)
	innerOf(tys, inf) if c.tKind(inf) == tList else none

# `mut xs T[] = []` whose first use tells T: noted for zap fmt as `mut xs = []`
fn noteEmptyListType(mut c Checker, v Var):
	if not noting: return
	at = v.emptyLet ?? return
	line = nodes[at].line
	src = c.file if c.curFile == "" else c.curFile
	text = sourceLineOf(src, line)
	code = codeOf(text)
	eq = code.indexOf(" = []") ?? -1
	if eq < 0 or code[eq..].trimmed() != "= []": return
	before = code[..eq]
	p = before.len - before.trimmedStart().len
	if before.trimmedStart().startsWith("mut "):
		p += 4
	start = p + v.name.len
	if start >= eq or text[p..start] != v.name or text[start] != ' ' or
		not text[start..eq].trimmed().endsWith("]"):
		return
	c.canonNote(noteReplace, line, start + 1, eq - start, "")

# whether e builds a struct by its name (`Pokemon("Zapdos", 50)`), or a list whose first element
# does: a value that tells its own type
fn namesItsType(c Checker, e NodeId) bool:
	k = nodes[e].kind
	if k == nArray:
		return not nodes[e].kids(kidIds).isEmpty and c.namesItsType(nodes[e].kids(kidIds)[0])
	k == nStructLit and not nodes[e].hasFlag(flagFromTuple) and
		not nodes[e].hasFlag(flagInternal) and
		nodes[e].text2(kidIds) != "$rt" and nodes[e].text2(kidIds) != "$named" and
		not c.isTupleLiteral(e)

# `mut team Pokemon[] = [Pokemon("Zapdos", 50)]`: the type written is the one the value tells,
# noted for zap fmt as `mut team = [...]`
fn noteToldType(mut c Checker, s NodeId, value NodeId, maybeT TypeId?):
	declT = maybeT ?? return
	if not noting or not c.namesItsType(value): return
	vt = typeOf(nodes, value)
	if c.tKind(declT) not in [tStruct, tList] or not isSameType(tys, vt, declT): return
	line = nodes[s].line
	src = c.file if c.curFile == "" else c.curFile
	text = sourceLineOf(src, line)
	code = codeOf(text)
	name = nodes[s].text
	p = code.len - code.trimmedStart().len
	if code[p..].startsWith("mut "):
		p += 4
	start = p + name.len
	eq = code.indexOf(" = ") ?? -1
	if eq < start or text[p..start] != name or text[start] != ' ' or eq == start: return
	# a generic's arguments may come from the annotation; the value is written, not made by the checker
	if "<" in code[start..eq]: return
	rest = code[eq + 3..].trimmedStart()
	written = rest[1..] if rest.startsWith("[") else rest
	if written.isEmpty or not (written[0] >= 'A' and written[0] <= 'Z'): return
	c.canonNote(noteReplace, line, start + 1, eq - start, "")

# t stamped on the expression e, and returned
fn typed(mut c Checker, e NodeId, t TypeId):
	nodes[e].ty = t
	t

fn showTy(c Checker, t TypeId?):
	typeStr(tys, t)

fn tKind(c Checker, maybeT TypeId?):
	t = maybeT ?? return -1
	tys[t].kind

# ---------- scopes ----------

fn enterScope(mut c Checker):
	c.scopeStarts.push(c.vars.len)

fn exitScope(mut c Checker):
	start = c.scopeStarts[len - 1]
	for i in start..c.vars.len:
		v = c.vars[i]
		if bindingsNoted and c.recording < 0: c.noteBinding(v)   # (lspFacts.zap)
		if not v.used and not v.isParam and v.name != "_" and "[" not in v.name and
			"#" not in v.name:
			# (an element of a register array is not a binding of its own, and a local of a
			# loop unrolled for one may be read in some copies only)
			name = "UnreadTest" if v.isTest else "UnusedVariable"
			if c.reportsUnused(name):
				c.errorAt(v.line, v.col, compileError(name, [v.name.copy()]))
		elif tys[v.ty].kind == tOption and tys[v.ty].inner == none and v.noneInit != none:
			c.errorAt(v.line, v.col, compileError("UntypedNone", ["{v.name}"]))
		elif v.emptyInit != none and v.emptyInfer is inf and inf == v.ty and
			tys[v.ty].inner == none:
			c.errorAt(v.line, v.col, compileError("UntypedEmptyList", ["{v.name}"]))
		elif v.emptyInit != none and v.emptyInfer is inf and inf != v.ty and c.typeTold(inf) and
			isSameType(tys, tys[inf].inner, tys[v.ty].inner):
			c.noteEmptyListType(v)
	c.truncateVars(start)
	c.forgetScope()
	c.forgetLengths()
	c.scopeStarts.pop()

# the variables from start on gone, with their places in varIndex
fn truncateVars(mut c Checker, start i64):
	i = c.vars.len - 1
	while i >= start:
		c.varIndex.forgetName(c.vars[i].nameNo)
		i -= 1
	c.vars.truncate(start)

fn recordCapture(mut c Checker, lam NodeId, vi i64):
	name = c.vars[vi].name
	if nodes[lam].names2(kidIds).indexOf(name) is at:
		nodes[lam].nodeMore(kidIds).ints[at] = c.vars[vi].ty   # checked again: this round's type
		return
	# the lambda records the captured name apart from the variable
	nodes[lam].nodeMore(kidIds).names2.push(name.copy())
	nodes[lam].nodeMore(kidIds).ints.push(c.vars[vi].ty)

# Finds a variable by name (innermost scope first, the first of that scope). A variable found
# beyond a lambda's parameter scope is captured by that lambda (by value).
fn lookupVar(mut c Checker, name str) i64:
	c.lookupVarNo(interned.numberOf(name))

# lookupVar of the name numbered no (-1: one nothing was ever declared under)
fn lookupVarNo(mut c Checker, no i64):
	last = c.varIndex.lastOf(no)
	if last < 0: return -1
	# the scope holding it: the last that starts at or before it
	lo = 0
	hi = c.scopeStarts.len - 1
	while lo < hi:
		mid = (lo + hi + 1) / 2
		if c.scopeStarts[mid] <= last:
			lo = mid
		else:
			hi = mid - 1
	i = c.varIndex.firstFrom(no, c.scopeStarts[lo])
	# the lambdas whose parameters' scope lies inside it capture it
	crossed = c.lamStack.len
	while crossed > 0 and c.lamBounds[crossed - 1] > lo:
		crossed -= 1
	for k in crossed..c.lamStack.len:
		c.recordCapture(c.lamStack[k], i)
	i

# True when the variable lives outside the innermost lambda being checked (so the lambda holds a copy).
fn isCapturedVar(c Checker, vi i64):
	if c.lamStack.isEmpty: return false
	bound = c.lamBounds[len - 1]
	vi < c.scopeStarts[bound]

# a captured variable the innermost lambda changes, recorded on it: a lambda that borrows what
# it captures changes the caller's variable, and the ownership pass reports one that keeps
# copies; a variable from outside two lambdas cannot change
pub fn noteCapturedChange(mut c Checker, vi i64, line i64, col i64):
	n = c.lamStack.len
	name = c.vars[vi].name.copy()
	if n > 1 and vi < c.scopeStarts[c.lamBounds[n - 2]]:
		errorAt(
			c,
			line,
			col,
			compileError("NestedLambdaChange", ["{name}"])
		)
		return
	lam = c.lamStack[n - 1]
	if name not in nodes[lam].bounds(kidIds):
		nodes[lam].nodeMore(kidIds).bounds.push(name)

fn lookupVarCurrent(c Checker, no i64):
	i = c.varIndex.firstFrom(no, c.scopeStarts[len - 1])
	while i >= 0 and c.vars[i].narrowed:
		i = c.varIndex.firstFrom(no, i + 1)
	i

fn addVar(mut c Checker, name str, ty TypeId, isMut bool, isParam bool, line i64, col i64) i64:
	if name in circleWords:
		c.errorAt(line, col, compileError("LanguageConstant", [name.copy()]))
	if c.implType != none and name != "_" and c.vars.any(.isField and .name == name):
		# in a method a bare name is the field: a local or a parameter cannot take one's name
		c.errorAt(line, col, compileError("FieldNameTaken", ["{name}", "{c.showTy(c.implType)}"]))
	no = interned.numbered(name)
	c.varIndex.noteName(no, c.vars.len)
	c.vars.push(
		Var(
			name = name.copy(),
			nameNo = no,
			ty,
			isMut,
			used = false,
			isParam,
			noneInit = none,
			literal = none,
			flexLet = none,
			line,
			col
		)
	)
	v = c.vars.len - 1
	if name.startsWith("$ix"):
		c.addRowParam(name, line, col)
	v

# The variable e names, when it is a mut binding of float literals alone that met an f32 here
# (`mut m = 0.5` then `m * x` with x an f32): its let is noted to be checked again as an f32,
# and the mismatch is not an error. Whether it was.
fn retypeFlex(mut c Checker, e NodeId, other TypeId):
	if nodes[e].kind != nIdent: return false
	v = c.lookupVarNo(nameOf(nodes, e))
	if v < 0: return false
	flex = c.vars[v].flexLet ?? return false
	to = c.flexTarget(c.vars[v].ty, other) ?? return false
	if flex not in c.retypes:
		c.retypes.push(flex)
		c.retypeTo.push(to)
	true

# the type a mutable binding of number literals alone, of type t, takes where it meets a value or
# a place of type other (spec 2.4): an f64's an f32, an i64's any other integer type
fn flexTarget(c Checker, t TypeId, other TypeId) TypeId?:
	if c.tKind(t) == tFloat and c.tKind(other) == tFloat and tys[other].bits == 32: return other
	if c.tKind(t) == tInt and c.tKind(other) == tInt and not isSameType(tys, t, other) and
		not isDefined(tys, other) and not tys[other].ranged and tys[other].param == "":
		return other
	none
