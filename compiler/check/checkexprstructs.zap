# The checking of fields, struct literals and integer literals (checkexpr.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

fn checkField(mut c Checker, e NodeId, expected TypeId?) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	if nodes[e].hasFlag(flagDotVariant):
		# `.Point`: a variant without values of the enum the place expects
		enumd = c.dotEnum(e, e, expected) ?? return tyError
		if c.kidNamed(enumd, nodes[e].text) is v and not nodes[v].kids(kidIds).isEmpty:
			c.errorAt(line, col, compileError("VariantNeedsArguments", ["{nodes[e].text}"]))
		res = tyOfDecl(tys, nodes, enumd)
		return c.typed(e, res)
	# qualified references: mod.constant, mod.Enum.Variant
	q = c.normalizeQualified(e)
	if q < 0: return tyError
	if q > 0: return c.checkExpr(e, expected)
	if c.normalizeQualified(nodes[e].kids(kidIds)[0]) < 0: return tyError
	obj = nodes[e].kids(kidIds)[0]
	# the field's name is read from e at each use: checking the object changes c
	if nodes[e].text2() != "" or nodes[e].text.startsWith("#"):
		if not c.patternField(e): return tyError

	# EnumType.Variant without payload
	named = c.enumNamedBy(obj)
	if named is EnumUnmade: return tyError
	if named is NamedEnum(enumd):
		v = c.kidNamed(enumd, nodes[e].text) ??
			return c.errorTyped(
				line,
				col,
				compileError("NotAVariant", ["{nodes[e].text}", "{nodes[enumd].text}"])
			)
		if not nodes[v].kids(kidIds).isEmpty:
			c.errorAt(line, col, compileError("VariantNeedsArguments", ["{nodes[v].text}"]))
		c.qualifiedVariant(e, e, enumd, expected)
		res = tyOfDecl(tys, nodes, enumd)
		return c.typed(e, res)

	if readsAsField(nodes[e].text) and not nodes[e].hasFlag(flagSize):
		c.sizeCall(e)
		return c.checkExpr(e, expected)
	if c.tableField(e): return c.checkExpr(e, expected)
	objT = c.derefIfRef(obj, c.checkExpr(obj, none))
	base = objT
	safe = nodes[e].hasFlag(flagSafe)
	if safe and c.tKind(objT) == tOption:
		base = tys[objT].inner ?? tyError
		if c.tKind(base) == tRef or c.tKind(base) == tBox:
			base = innerOf(tys, base)   # a reference or a box: what it holds
	if c.isMethodWithoutCall(e, base, safe): return tyError
	if c.standInIndex(base) >= 0:
		c.errorAt(
			line,
			col,
			compileError("FieldOfTypeParameter", ["{tys[base].param}", "{nodes[e].text}"])
		)
		return tyError
	if c.tKind(base) == tEnum and nodes[e].text == "value" and not safe and
		c.enumHasValues(declOf(tys, base)) and c.findMethod(tys[base].name, "value") == none:
		c.fieldAsCall(e, 0)   # op.value: the variant's integer
		return c.checkExpr(e, expected)
	if c.tKind(base) == tEnum and c.kidNamed(declOf(tys, base), nodes[e].text) is variant:
		return c.checkVariantValue(e, variant)
	if c.bitsDecl(base) is bd and not safe: return c.checkBitsField(e, bd, base, expected)
	if c.tKind(base) != tStruct:
		if c.tKind(base) != tError:
			c.errorAt(line, col, compileError("TypeHasNoFields", ["{c.showTy(base)}"]))
		return tyError
	nodes[e].text = c.vectorLetters(declOf(tys, base), move nodes[e].text)
	f = c.kidNamed(declOf(tys, base), nodes[e].text) ?? return c.notAField(e, base, safe, expected)
	ft = c.resolveType(nodes[f].types()[0])
	if c.isExternType(declOf(tys, base)) and c.isCPointer(ft):
		c.errorAt(line, col, compileError("CPointerField", ["{nodes[e].text}", "{tys[base].name}"]))
		return tyError
	res = ft
	if safe:
		res = tyOption(tys, ft)
	c.typed(e, res)

# e (`x.name`) names no field of x's struct base: a swizzle, else reported
fn notAField(mut c Checker, e NodeId, base TypeId, safe bool, expected TypeId?):
	swizzled = 0 if safe else c.asSwizzle(e, base)
	if swizzled > 0: return c.checkExpr(e, expected)
	if swizzled == 0:
		c.errorAt(
			nodes[e].line,
			nodes[e].col,
			compileError("NoField", ["{tys[base].name}", "{nodes[e].text}"])
		)
	tyError

# a method that takes nothing written as a field: a size, or a list's end
fn readsAsField(name str):
	name in sizeWords or name in endWords

# `xs.len`, `q.isEmpty` (or `x?.len`): a size read as a field, made the call of its method (a
# struct's own field of that name is read back as the field, see sizeField)
fn sizeCall(mut c Checker, e NodeId):
	c.fieldAsCall(e, flagSize)

# the field e (`x.name`) made the call of the method of that name, its callee marked with extra
fn fieldAsCall(mut c Checker, e NodeId, extra i64):
	f = newNode(
		nodes,
		kidIds,
		nField,
		nodes[e].line,
		nodes[e].col,
		text = nodes[e].text.copy(),
		kids = [nodes[e].kids(kidIds)[0]]
	)
	nodes[f].flags = extra | (nodes[e].flags & flagSafe)
	nodes[e].kind = nCall
	nodes[e].text = ""
	nodes[e].setKids(kidIds, [f])
	nodes[e].flags = 0

# the size's call e on a struct that has a field of the size's name: e read as that field. Whether it is.
fn sizeField(mut c Checker, e NodeId, t TypeId):
	callee = nodes[e].kids(kidIds)[0]
	if not nodes[callee].hasFlag(flagSize) or c.tKind(t) != tStruct or
		c.kidNamed(declOf(tys, t), nodes[callee].text) == none:
		return false
	nodes[e].kind = nField
	nodes[e].text = nodes[callee].text.copy()
	nodes[e].setKids(kidIds, [nodes[callee].kids(kidIds)[0]])
	nodes[e].flags = nodes[callee].flags & flagSafe | flagSize   # decided: not made a call again
	true

# `xs.parallel` without parentheses: a method is always called with them; the error says so
# when the value has no field of that name. Whether it reported one.
fn isMethodWithoutCall(mut c Checker, e NodeId, base TypeId, safe bool):
	name = nodes[e].text.copy()
	if safe or name != "parallel": return false
	if c.tKind(base) == tStruct and c.kidNamed(declOf(tys, base), name) != none or
		c.tKind(base) == tError:
		return false
	errorAt(
		c,
		nodes[e].line,
		nodes[e].col,
		compileError("MethodNeedsCall", ["{name}"])
	)
	true

# A function handed to the system must be a top-level function: the system keeps a code
# address, never a closure's environment.
fn checkCallbackArgs(mut c Checker, e NodeId, fd NodeId):
	params = nodes[fd].kids(kidIds).copy()   # (resolving a type changes c.nodes)
	for i in 0..argCount(c, e):
		if i >= params.len or c.tKind(c.resolveType(nodes[params[i]].types()[0])) != tFn: continue
		a = c.argAt(e, i)
		if nodes[a].kind != nIdent or not nodes[a].hasFlag(flagFnRef):
			c.errorAt(
				nodes[a].line,
				nodes[a].col,
				compileError("CallbackNotFunction", ["{i + 1}", "{nodes[fd].text2()}"])
			)

# Rewrites the literal e of the shared struct type st in place into Box(literal) marked
# shared: the backend puts the struct on the heap under a count of one. Returns its type.
fn shareLiteral(mut c Checker, e NodeId, st TypeId):
	line = nodes[e].line
	col = nodes[e].col
	lit = newNode(nodes, kidIds, nIdent, line, col)
	# the literal moves to lit; e is left empty and rebuilt below as the call. An expression
	# node has no file, module or bounds, so the empty ones are its own; origin and position
	# are put back.
	nodes[lit] = move nodes[e]
	nodes[lit].ty = st
	nodes[e].line = line
	nodes[e].col = col
	nodes[e].part = []
	callee = newNode(nodes, kidIds, nIdent, line, col, text = "Box")
	nodes[e].kind = nCall
	nodes[e].setKids(kidIds, [callee, lit])
	nodes[e].text = ""
	nodes[e].flags = flagShared
	nodes[e].ival = 0
	nodes[e].ty = tyShared(tys, st)
	typeOf(nodes, e)

# The instance a literal of a generic struct written without type arguments makes: the expected
# type's when it is an instance of the template, otherwise each parameter from the field
# declared with that type (Pair(a = 1, b = "x") is a Pair<i64, str>); -1 after an error.
# the name a template is shown by: as written where it is used (text2), else its own
fn shownTemplate(c Checker, tmpl NodeId) ref str:
	if nodes[tmpl].text2() != "": return nodes[tmpl].text2()
	nodes[tmpl].text

fn inferStructInstance(mut c Checker, e NodeId, tmpl NodeId, expected TypeId?) NodeId?:
	line = nodes[e].line
	col = nodes[e].col
	if c.isInstanceOfTemplate(expected, tmpl): return declOf(tys, expected ?? tyError)
	# the template's names and fields are read from tmpl at each use: checking the field
	# values changes c
	args = []
	for ti in 0..c.nodes[tmpl].names().len:
		at TypeId? = none
		for fi in 0..c.nodes[tmpl].kids(c.kidIds).len:
			f = nodes[tmpl].kids(kidIds)[fi]
			te = nodes[f].types()[0]
			if at == none and nodes[te].kind == nTyName and
				nodes[te].text == nodes[tmpl].names()[ti] and
				nodes[te].types().isEmpty:
				i = nodes[e].names().indexOf(nodes[f].text) ?? -1
				if i >= 0:
					val = nodes[e].kids(kidIds)[i]
					at = c.derefIfRef(val, c.checkExpr(val, none))
		if at == none:
			at = c.lengthFromFields(e, tmpl, ti)
		found = at ??
			return c.noneReported(
				line,
				col,
				compileError(
					"CannotInferTypeParameterHint",
					["{nodes[tmpl].names()[ti]}", "{c.shownTemplate(tmpl)}"]
				)
			)
		if c.tKind(found) == tError: return none
		args.push(c.heldType(found))
	numbers = c.numberArgs(tmpl, args)
	for failure in c.instanceBoundFailures(tmpl, numbers):
		c.errorAt(line, col, compileError("BoundNotMet", ["{failure}", "{c.shownTemplate(tmpl)}"]))
	c.programInstantiate(tmpl, numbers)

# whether the place's type is an instance of the generic struct tmpl
fn isInstanceOfTemplate(c Checker, expected TypeId?, tmpl NodeId):
	c.tKind(expected) == tStruct and nodes[declOf(tys, expected ?? tyError)].origin() == tmpl

# the value the literal e gives type parameter ti of struct template tmpl through a fixed array's
# field (`cells f32[R, C]` given a f32[2, 3]: R is 2), or none
fn lengthFromFields(mut c Checker, e NodeId, tmpl NodeId, ti i64):
	for fi in 0..c.nodes[tmpl].kids(c.kidIds).len:
		f = nodes[tmpl].kids(kidIds)[fi]
		i = nodes[e].names().indexOf(nodes[f].text) ?? -1
		if i < 0 or nodes[nodes[f].types()[0]].kind != nTyArray: continue
		val = nodes[e].kids(kidIds)[i]
		at = c.derefIfRef(val, c.checkExpr(val, none))
		sub = Subst(names = [], types = [])
		c.unify(tmpl, nodes[f].types()[0], at, sub)
		given = substTypeFor(nodes[tmpl].names()[ti], sub)
		if given != none: return given
	none

# the value given field f, the i-th named in the struct literal e (fromValues: its type comes from
# its values)
fn checkFieldValue(mut c Checker, e NodeId, i i64, f NodeId, fromValues bool):
	val = nodes[e].kids(kidIds)[i]
	ft = c.resolveType(nodes[f].types()[0])
	weak = c.weakExpected
	if fromValues:
		c.weakExpected = val
	vt = c.checkExpr(val, ft)
	c.weakExpected = weak
	if fromValues:
		c.keepConversion(val)
	else:
		c.noteNarrowedAt(val, ft)
		c.noteWidenedAt(val, ft, true)
		if not isAssignable(tys, vt, ft):
			val = c.fitValue(val, ft)   # widened, or narrowed where proven inside
			vt = typeOf(nodes, val)
	if not isAssignable(tys, vt, ft) and not c.retypeFlex(val, ft) and c.isTupleLiteral(e):
		errorAt(
			c,
			nodes[val].line,
			nodes[val].col,
			compileError(
				"TupleValueType",
				["{i + 1}", "{c.showTy(ft)}", "{c.showTy(vt)}", "{c.rangeHint(vt, ft)}"]
			)
		)
	elif not isAssignable(tys, vt, ft) and not c.retypeFlex(val, ft):
		errorAt(
			c,
			nodes[e].line,
			nodes[e].col,
			compileError(
				"FieldType",
				["{nodes[e].names()[i]}", "{c.showTy(ft)}", "{c.showTy(vt)}", "{c.rangeHint(vt, ft)}"]
			)
		)
	madeKid = c.coerceTo(val, ft)
	nodes[e].setKid(kidIds, i, madeKid)

# A tuple `(a, b)` or `(name = a, level = b)` where the place expects a struct is that struct's
# literal: positional values fill the fields in order. false after an error (a named tuple
# where no struct is expected has no type to take its fields from).
fn placeTuple(mut c Checker, e NodeId, expected TypeId?):
	named = nodes[e].text2() == "$named"
	if not named and not c.isTupleLiteral(e): return true
	line = nodes[e].line
	col = nodes[e].col
	if c.tKind(expected) != tStruct or c.isTupleType(expected ?? tyError):
		if named: c.errorAt(line, col, compileError("NamedTupleNeedsType", []))
		return not named
	d = declOf(tys, expected ?? tyError)
	if nodes[d].kind != nStructDecl:
		if named: c.errorAt(line, col, compileError("NamedTupleNeedsType", []))
		return not named
	if not named:
		fields = nodes[d].kids(kidIds)
		if nodes[e].kids(kidIds).len > fields.len:
			c.errorAt(
				line,
				col,
				compileError(
					"TooManyValues",
					["{c.shownName(d)}", "{fields.len}", "{fields.len + 1}"]
				)
			)
			return false
		nodes[e].nodePart().names = (0..nodes[e].kids(kidIds).len).map(nodes[fields[it]].text.copy())
	nodes[e].text = nodes[d].text.copy()
	nodes[e].setText2(globalAlias)
	nodes[e].flags |= flagFromTuple
	true

fn checkStructLit(mut c Checker, e NodeId, expected TypeId?) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	# the type's name and the field names are read from e at each use: checking changes c
	written = c.lookupDeclAsWritten(nStructDecl, nodes[e].text2(), nodes[e].text, line, col)
	found = c.declOfAlias(written)
	if found == none and nodes[e].text2() != "": return tyError
	d = found ?? return c.errorTyped(line, col, compileError("NotAStruct", ["{nodes[e].text}"]))
	if nodes[d].kind != nStructDecl:
		return c.errorTyped(line, col, compileError("NotAStruct", ["{nodes[e].text}"]))
	alias = written ?? d   # (d is the declaration it names)
	definedT TypeId? = c.aliasedType(alias) if d != alias else none
	named = alias if isDefined(tys, definedT) else d   # Color(r = 1.0...) is a Color
	# a generic literal with no type from its place (a tuple alone) takes its types from its own
	# values: checked again with them, they gave themselves nothing (a `.Variant` there needs Type.)
	fromValues = c.isGenericTemplate(d) and nodes[e].types().isEmpty and
		(c.weakExpected == e or not c.isInstanceOfTemplate(expected, d))
	if c.isGenericTemplate(d) and nodes[e].types().isEmpty:
		d = c.inferStructInstance(e, d, expected) ?? return tyError
	elif c.isGenericTemplate(d):
		d = c.instantiateFromNode(d, e, line, col) ?? return tyError
	elif not nodes[e].types().isEmpty:
		c.errorAt(line, col, compileError("NotGeneric", ["{nodes[e].text}"]))
	nodes[e].text = nodes[named].text.copy()   # the literal names the struct by its qualified name
	nodes[e].setText2(globalAlias)
	provided = nodes[e].names().len
	for i in 0..provided:
		val = nodes[e].kids(kidIds)[i]
		nodes[e].nodePart().names[i] = c.vectorLetters(d, move nodes[e].part[0].names[i])
		match c.kidNamed(d, nodes[e].names()[i]):
			f: c.checkFieldValue(e, i, f, fromValues)
			none:
				c.errorAt(
					line,
					col,
					compileError("NoField", ["{nodes[d].text}", "{nodes[e].names()[i]}"])
				)
				c.checkExpr(val, none)
	# a field left out takes its default (a copy of the expression its declaration gives), else
	# it is reported
	missing = []
	for fi in 0..c.nodes[d].kids(c.kidIds).len:
		f = nodes[d].kids(kidIds)[fi]
		if nodes[f].text in nodes[e].names(): continue
		ft = c.resolveType(nodes[f].types()[0])
		given NodeId? = none
		if not nodes[f].kids(kidIds).isEmpty:
			given = c.defaultOf(f, d, "field")
		elif c.isExternType(d):
			given = c.emptyArray(ft, line, col)
		if given == none:
			missing.push(nodes[f].text.copy())
			continue
		val = given ?? continue
		vt = c.checkExpr(val, ft)
		if not isAssignable(tys, vt, ft):
			c.errorAt(
				nodes[f].line,
				nodes[f].col,
				compileError(
					"FieldDefaultType",
					["{nodes[f].text}", "{c.showTy(vt)}", "{c.showTy(ft)}"]
				)
			)
		nodes[e].nodePart().names.push(nodes[f].text.copy())
		madeKid = c.coerceTo(val, ft)
		nodes[e].pushKid(kidIds, madeKid)
	if not missing.isEmpty:
		c.errorAt(
			line,
			col,
			compileError(
				"MissingFields",
				[
					"{nodes[d].text}",
					"{"field" if missing.len == 1 else "fields"}",
					"{missing.join(", ")}"
				]
			)
		)
	res = tyOfDecl(tys, nodes, d)
	from = nodes[e].ival - 1
	if from >= 0 and from < nodes[e].kids(kidIds).len and nodes[nodes[e].kids(kidIds)[from]].kind == nField:
		# Params(..base, ...): base is a Params (its fields were read as this one's)
		bt = nodes[nodes[nodes[e].kids(kidIds)[from]].kids(kidIds)[0]].ty
		if bt is bt and c.tKind(bt) != tError and not isSameType(tys, c.derefType(bt), res):
			c.errorAt(
				line,
				col,
				compileError("BaseTypeDiffers", ["{c.showTy(res)}", "{c.showTy(c.derefType(bt))}"])
			)
	if isDefined(tys, definedT) and definedT is shown: return c.typed(e, shown)
	c.typed(e, res)

# An integer literal must fit the type it was given (a plain literal is i64; annotate for wider).
# whether integer literal e is exact in float type t (2^24 for f32, 2^53 for f64), t a float
fn exactFloatLiteral(c Checker, e NodeId, maybeT TypeId?):
	t = maybeT ?? return false
	limit = 16_777_216 if tys[t].bits == 32 else 9_007_199_254_740_992
	(i64.parse(nodes[e].text) ?? limit + 1).abs() <= limit

# an integer literal's value, none past an i64
fn checkedLiteral(text str):
	i64.parse(text.replace("_", ""))

fn checkIntLiteralRange(mut c Checker, e NodeId):
	t = typeOf(nodes, e)
	if c.tKind(t) != tInt: return
	text = nodes[e].text
	neg = text.startsWith("-")
	i = 0
	if neg:
		i = 1
	maxU u64 = 18_446_744_073_709_551_615
	mag = 0
	overflow = false
	while i < text.len:
		b = text[i]
		if b < 48 or b > 57: break
		digit = u64(b - 48)
		if mag > (maxU - digit) / 10:
			overflow = true
		else:
			mag = mag * 10 + digit
		i += 1
	if tys[t].ranged and checkedLiteral(text) is v and (v < tys[t].lo or v > tys[t].hi):
		errorAt(
			c,
			nodes[e].line,
			nodes[e].col,
			compileError("LiteralOutsideRange", ["{text}", "{c.showTy(t)}"])
		)
		return
	bits = tys[t].bits
	one u64 = 1
	limit = 0
	if tys[t].isSigned:
		limit = (one << u64(bits - 1)) - 1
		if neg:
			limit += 1
	elif bits == 64:
		limit = maxU
	else:
		limit = (one << u64(bits)) - 1
	line = nodes[e].line
	col = nodes[e].col
	if not tys[t].isSigned and neg and mag != 0:
		c.errorAt(line, col, compileError("NegativeUnsigned", ["{text}", "{c.showTy(t)}"]))
	elif overflow or mag > limit:
		hint = ""
		if bits < 64:
			hint = " (annotate the binding with a wider type, e.g. i64)"
		elif tys[t].isSigned:
			hint = " (the largest i64 is 9_223_372_036_854_775_807; up to 18_446_744_073_709_551_615 fits where a u64 is expected)"
		c.errorAt(
			line,
			col,
			compileError("LiteralDoesNotFit", ["{text}", "{c.showTy(t)}", "{hint}"])
		)

# `shape.Circle`: the value a variant of one value holds, none when the enum holds another
# variant; desugared into `match shape { Circle(v) => some(v)  _ => none }`, a reference into
# the enum unless the value copies freely
fn checkVariantValue(mut c Checker, e NodeId, variant NodeId) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	if nodes[variant].kids(kidIds).len != 1:
		return c.errorTyped(line, col, compileError("VariantValueCount", ["{nodes[variant].text}"]))
	vt = c.resolveType(nodes[nodes[variant].kids(kidIds)[0]].types()[0])
	res = tyOption(tys, vt if c.copiesFreely(vt) else tyRef(tys, vt, false))
	name = "_sc{c.safeCallCount}"
	c.safeCallCount += 1
	bind = newNode(nodes, kidIds, nPattern, line, col, text = name.copy())
	nodes[bind].ival = patBind
	pat = newNode(nodes, kidIds, nPattern, line, col, text = nodes[variant].text.copy(), kids = [bind])
	nodes[pat].ival = patCtor
	nodes[pat].flags = flagWritten
	held = newNode(nodes, kidIds, nIdent, line, col, text = name)
	some = newNode(nodes, kidIds, nSome, line, col, kids = [held])
	nodes[some].ty = res
	non = newNode(nodes, kidIds, nNone, line, col)
	nodes[non].ty = res
	other = newNode(nodes, kidIds, nPattern, line, col)
	nodes[other].ival = patWildcard
	taken = newNode(nodes, kidIds, nArm, line, col, kids = [pat, some])
	rest = newNode(nodes, kidIds, nArm, line, col, kids = [other, non])
	nodes[e].kind = nMatch
	nodes[e].setKids(kidIds, [nodes[e].kids(kidIds)[0], taken, rest])
	nodes[e].text = ""
	nodes[e].setText2("")
	nodes[e].flags = 0
	c.checkExpr(e, res)
