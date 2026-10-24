# The unifying of generic types and the checking of generic calls (checkexpr.zap).

alias nodes = c.nodes
alias tys = c.types

fn isGenericParam(c Checker, fnd NodeId, name str):
	name in nodes[fnd].names

# Binds type parameters by matching the parameter's syntactic type against the argument's type.
fn unify(
	mut c Checker,
	fnd NodeId,
	maybeTe NodeId?,
	at0 TypeId?,
	mut sub Subst,
	nested bool = false
):
	te = maybeTe ?? return
	at = at0 ?? return
	tk = nodes[te].kind
	if c.tKind(at) == tRef and tk != nTyRef and not nested:
		at = innerOf(tys, at)   # a reference where the value is expected: its target
	ak = c.tKind(at)
	if tk == nTyArray and ak == tArray:
		size = nodes[te].text.copy()
		if c.isGenericParam(fnd, size) and size not in sub.names:
			# T[N] given a T[3]: N is 3 (the caller's own N at a generic's definition)
			given = tyNum(tys, tys[at].bits, none) if tys[at].bits >= 0 else valOf(tys, at)
			sub.names.push(size)
			sub.types.push(given)
		c.unify(fnd, nodes[te].types[0], tys[at].inner, sub, nested = true)
	elif tk == nTyName:
		name = nodes[te].text
		if c.isGenericParam(fnd, name):
			if sub.names.indexOf(name) is i:
				# a value's range bound its base; a type that names the range itself (a function's
				# parameter) binds the range
				if nested and at != sub.types[i] and c.heldType(at) == sub.types[i]:
					sub.types[i] = at
				return
			sub.names.push(name.copy())   # the binding outlives this node's borrow
			sub.types.push(at if nested else c.heldType(at))   # a value's range: its base
			return
		# unify changes c: what is compared is decided before it, and the argument type
		# expressions are read from te at each use
		nargs = nodes[te].types.len
		isList = name == "List"
		isMap = name == "Map"
		if isList and nargs == 1 and ak == tList:
			c.unify(fnd, nodes[te].types[0], tys[at].inner, sub, nested = true)
		if isMap and nargs == 2 and ak == tMap:
			c.unify(fnd, nodes[te].types[0], tys[at].inner, sub, nested = true)
			c.unify(fnd, nodes[te].types[1], tys[at].val, sub, nested = true)
		if isSimdName(name) and nargs == 2 and c.isSimdType(at):
			# Simd<N, T> given a Simd<8, f32>: N is 8, T f32
			elem, lanes = c.simdShape(at)
			c.unify(
				fnd,
				nodes[te].types[0],
				tyNum(tys, lanes, none) if lanes >= 0 else valOf(tys, at),
				sub,
				nested = true
			)
			c.unify(fnd, nodes[te].types[1], elem, sub, nested = true)
		if nargs > 0 and ak == tBox and tys[at].counted:
			at = innerOf(tys, at)   # a shared value: written as its struct's name
		if nargs > 0 and (c.tKind(at) == tStruct or c.tKind(at) == tEnum):
			d = declOf(tys, at)
			origin = nodes[d].origin
			if origin is origin and nodes[d].ints().len == nargs and
				(
					nodes[te].text == nodes[origin].text or
						(nodes[origin].text2 != "" and nodes[te].text == nodes[origin].text2)
				):
				for i in 0..nargs:
					c.unify(fnd, nodes[te].types[i], nodes[d].ints()[i], sub, nested = true)
	elif tk == nTyFn and ak == tFn and nodes[te].types.len == tys[at].params.len:
		for i in 0..c.nodes[te].types.len:
			c.unify(fnd, nodes[te].types[i], tys[at].params[i], sub, nested = true)
		if not nodes[te].sub.isEmpty:
			c.unify(fnd, nodes[te].sub[0], tys[at].ret, sub, nested = true)
	elif tk == nTyOpt and ak == tOption:
		c.unify(fnd, nodes[te].types[0], tys[at].inner, sub, nested = true)
	elif tk == nTyResult and ak == tResult:
		c.unify(fnd, nodes[te].types[0], tys[at].inner, sub, nested = true)
		c.unify(fnd, nodes[te].types[1], tys[at].err, sub, nested = true)

# True when a parameter's written type names one of the function's type parameters.
fn teMentionsGeneric(c Checker, fnd NodeId, te NodeId):
	c.teMentionsOpen(fnd, te, [])

# whether the type expression names a type parameter of fnd that is not among the known ones
fn teMentionsOpen(c Checker, fnd NodeId, maybeTe NodeId?, known str[]) bool:
	te = maybeTe ?? return false
	k = nodes[te].kind
	if (k == nTyName and nodes[te].text2 == "" or k == nTyArray) and
		c.isGenericParam(fnd, nodes[te].text) and nodes[te].text not in known:
		return true
	nodes[te].types.any(c.teMentionsOpen(fnd, it, known)) or
		nodes[te].sub.any(c.teMentionsOpen(fnd, it, known))

fn substTypeFor(gn str, sub Subst) TypeId?:
	if sub.names.indexOf(gn) is j: return sub.types[j]
	none

fn substMangle(c Checker, fnd NodeId, sub Subst):
	b = nodes[fnd].names.map(g:
		match substTypeFor(g, sub):
			t: typeMangled(tys, t)
			none: "?"
	).join(", ")
	"inst" if b == "" else identChars(b)

# a value of type t is printed: anything but a number, a bool or a str goes through the
# printing function the compiler writes for its type
fn noteFormat(mut c Checker, t TypeId):
	u = t
	while c.tKind(u) == tRef:
		u = innerOf(tys, u)
	k = c.tKind(u)
	if k in [tStr, tInt, tFloat, tBool, tError, tUnit, tFn]: return
	c.noteDerive(u, deriveFmt)

# whether an argument of the call e has a type that is unknown (an error already reported, or
# a type parameter of a template being checked)
fn anyArgUnknown(c Checker, e NodeId):
	for i in 0..argCount(c, e):
		t = nodes[c.argAt(e, i)].ty
		if t is t and tys[t].kind == tError: return true
	false

# the name the program called fnd by at the call site: a method made a call of its runtime
# function is the method (xs.sorted() is listSort)
fn calledAs(c Checker, fnd NodeId, site NodeId) ref str:
	if nodes[site].kind == nCall and nodes[site].hasFlag(flagMethod):
		callee = nodes[site].kids[0]
		if not nodes[callee].names.isEmpty: return nodes[callee].names[0]
	nodes[fnd].text2

fn recordInstance(mut c Checker, fnd NodeId, sub Subst, site NodeId):
	# the arguments' ids find the instance made for them; else the name made of them finds one
	# made for arguments of other ids but the same name
	asked = nodes[fnd].names.map(substTypeFor(it, sub) ?? tyError)
	key = instanceKey(fnd, asked) if nodes[fnd].names.all(substTypeFor(it, sub) != none) else -1
	if key >= 0:
		for i in c.instancesAsked.get(key) ?? []:
			if c.instances[i].fnDecl == fnd and sameIds(c.instances[i].asked, asked):
				return c.instances[i].mangle.copy()
	mangle = c.substMangle(fnd, sub)
	if c.findInstance(fnd, mangle) != none:
		return mangle   # the same name as the recorded one
	# the instance keeps its own list of the type parameter names: the declaration keeps its
	names = nodes[fnd].names.copy()
	types = c.numberArgs(fnd, names.map(substTypeFor(it, sub) ?? tyError))
	line = nodes[site].line
	col = nodes[site].col
	where = "{c.curFile}:{line}:{col}"
	if c.curFile == "":
		where = "{c.file}:{line}:{col}"
	failures = c.instanceBoundFailures(fnd, types)
	for failure in failures:
		c.errorAt(line, col, compileError("BoundNotMet", ["{failure}", "{c.calledAs(fnd, site)}"]))
	if not failures.isEmpty:
		return mangle   # not checked: its body would only repeat the error
	decl = c.instanceDecl(fnd, names, types)
	end = nodes.len if decl != fnd else 0
	# two names: the instance list keeps one and the caller names the call with the other
	c.instances.push(
		GenInst(
			fnDecl = fnd,
			decl,
			mangle = mangle.copy(),
			sub = Subst(names, types),
			site = where,
			asked = asked if key >= 0 else [],
			end
		)
	)
	c.indexInstance(c.instances.len - 1)
	mangle

# The declaration an instance of fnd checks and generates, checked once with its types and
# generated as checked: a copy of fnd of its own (its origin fnd, whose summaries it reads), or,
# given numbers for its number parameters, one of its body as parsed with them known
# (regarrays.zap numberInstance). At the definition check, whose instances are dropped, fnd itself.
fn instanceDecl(mut c Checker, fnd NodeId, names str[], types TypeId[]):
	if c.atDefinition: return fnd
	numbers = []
	values = []
	for i, t in types:
		if c.tKind(t) == tNum and tys[t].param == "" and tys[t].bits >= 0:
			numbers.push(names[i].copy())
			values.push(tys[t].bits)
	if not numbers.isEmpty and numberInstance(nodes, fnd, numbers, values) is d: return d
	d = cloneTree(nodes, fnd)
	nodes[d].origin = fnd
	d

# the type arguments the call e writes (`zeros<3>()`, `parse<i64>(s)`) bound in sub, in the order
# of fnd's parameters; false after an error
fn givenTypeArgs(mut c Checker, e NodeId, fnd NodeId, mut sub Subst):
	callee = nodes[e].kids[0]
	if nodes[callee].kind != nIdent or nodes[callee].types.isEmpty: return true
	given = nodes[callee].types.copy()
	if not c.typeArgCountOk(fnd, given.len, nodes[e].line, nodes[e].col): return false
	for i, te in given:
		t = c.resolveTypeOrNumber(te)
		if c.tKind(t) == tError: return false
		sub.names.push(nodes[fnd].names[i].copy())
		sub.types.push(t)
	true

fn checkGenericCall(mut c Checker, e NodeId, fnd NodeId, expected TypeId?) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	c.fillArguments(e, fnd, 0)
	# the declaration's parameters and name are read from fnd at each use: checking the
	# arguments changes c
	nargs = c.argCount(e)
	if nargs != nodes[fnd].kids.len:
		errorAt(
			c,
			line,
			col,
			compileError("ArgumentCount", ["{nodes[fnd].text}", "{nodes[fnd].kids.len}", "{nargs}"])
		)
		return tyError
	sub = Subst(names = [], types = [])
	if not c.givenTypeArgs(e, fnd, sub): return tyError
	if expected != none and not nodes[fnd].types.isEmpty and
		nodes[nodes[fnd].types[0]].text == "List" and nargs > 0 and
		nodes[c.argAt(e, 0)].kind == nArray:
		# a list literal first takes its type from the expected list: b u8[] = zeros(n)
		c.unify(fnd, nodes[fnd].types[0], expected, sub)
	for i in 0..nargs:
		sub = c.checkGenericCallArg(e, fnd, i, move sub)
	if expected != none and not nodes[fnd].types.isEmpty:
		# what the arguments left open, the expected result may fix: ch = Channel<i64>(8)
		c.unify(fnd, nodes[fnd].types[0], expected, sub)
	for g in nodes[fnd].names:
		if substTypeFor(g, sub) == none and c.anyArgUnknown(e):
			sub.names.push(g.copy())   # an argument's type is already unknown: so is this
			sub.types.push(tyError)
		elif substTypeFor(g, sub) == none:
			c.errorAt(
				line,
				col,
				compileError("CannotInferTypeParameter", ["{g}", "{nodes[fnd].text}"])
			)
			return tyError
	# the bindings are swapped into c while the parameter types are resolved, then taken back
	sav = move c.subst
	c.subst = move sub
	for i in 0..nargs:
		pt = c.resolveType(nodes[nodes[fnd].kids[i]].types[0])
		c.noteWidenedAt(c.argAt(e, i), pt)
		c.noteNarrowedAt(c.argAt(e, i), pt)
		if not isAssignable(tys, typeOf(nodes, c.argAt(e, i)), pt):
			c.setArg(e, i, c.narrowProven(c.argAt(e, i), pt))
		at = typeOf(nodes, c.argAt(e, i))
		if not isSameType(tys, at, pt) and not isRefAssignable(tys, at, pt) and
			not intWidensTy(tys, at, pt):
			if not c.retypeFlex(c.argAt(e, i), pt):
				c.errorAt(
					line,
					col,
					compileError(
						"ArgumentType",
						[
							"{c.argumentOf(e, i, nodes[fnd].text)}",
							"{c.showTy(pt)}",
							"{c.showTy(at)}",
							""
						]
					)
				)
		elif not isSameType(tys, at, pt):
			c.setArg(e, i, c.coerceTo(c.argAt(e, i), pt))   # a reference: the value it points to
	ret = c.fnRetType(fnd)
	sub = move c.subst
	c.subst = sav
	mangle = c.recordInstance(fnd, sub, e)
	if not c.atDefinition:
		nodes[e].text2 = mangle   # the definition check's stand-ins name no instance
	c.typed(e, ret)

fn checkGenericCallArg(mut c Checker, e NodeId, fnd NodeId, i i64, move sub Subst):
	pte = nodes[nodes[fnd].kids[i]].types[0]
	want TypeId? = none
	lit = c.argAt(e, i)
	if nodes[pte].kind == nTyArray and nodes[lit].kind == nArray and
		c.isGenericParam(fnd, nodes[pte].text) and nodes[pte].text not in sub.names:
		sub.names.push(nodes[pte].text.copy())   # T[N] given a literal: N is its length
		sub.types.push(tyNum(tys, nodes[lit].kids.len, none))
	if not c.teMentionsOpen(fnd, pte, sub.names):
		# a parameter type the earlier arguments settled guides literals: xs.contains(3)
		# with xs a u8[] makes the 3 a u8, as a concrete type does (0 as i64). The
		# bindings are swapped into c for resolveType and back, not copied.
		sav = move c.subst
		c.subst = move sub
		want = c.resolveType(pte)
		sub = move c.subst
		c.subst = sav
	a = c.argAt(e, i)
	if nodes[pte].kind == nTyFn and nodes[pte].types.len == 1:
		c.itLambda(a)
	if want == none and nodes[pte].kind == nTyFn and nodes[a].kind == nLambda and
		nodes[pte].types.len == nodes[a].names.len:
		# fn(i64) T, or fn(T) U with T given by an earlier argument: the lambda's parameters
		# take the concrete types, its body then tells U (outside a generic, whose types
		# differ by instance)
		if not nodes[pte].types.any(c.teMentionsOpen(fnd, it, sub.names)) and
			(c.subst.names.isEmpty or not nodes[pte].types.any(c.teMentionsGeneric(fnd, it))):
			sav = move c.subst
			c.subst = move sub
			for j in 0..c.nodes[pte].types.len:
				if nodes[nodes[a].types[j]].kind == nTyAbsent:
					nodes[a].types[j] = c.typeToTE(c.resolveType(nodes[pte].types[j]))
			sub = move c.subst
			c.subst = sav
	if want != none and not nodes[e].hasFlag(flagMethod) and c.teMentionsGeneric(fnd, pte):
		c.weakExpected = a   # the type an earlier argument gave, not the place's
	at = c.checkExpr(a, want)
	c.weakExpected = none
	c.unify(fnd, pte, at, sub)
	sub

# ---------- builtins and intrinsics ----------
# Parameter codes: 1 i64, 2 i64, 3 str, 4 i64[], 5 f64. Result codes: 0 unit, 1 i64,
# 2 i64, 3 f64, 4 str, 5 bool, 6 str[], 7 str?.
