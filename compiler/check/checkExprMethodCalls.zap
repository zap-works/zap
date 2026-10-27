# The checking of calls of bound functions, type functions and methods, variants and swizzles (checkExpr.zap).

import shader

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# x.f(a) in an instance of a generic, x of its type parameter's type t, where a function taking
# t first met the bound's f (boundFailure noted it): the call f(x, a) made and checked aside, in
# boundCalls for the backend, as the node is the instances' own. none when t has the method.
fn checkBoundFunctionCall(mut c Checker, e NodeId, t TypeId, expected TypeId?) TypeId?:
	callee = nodes[e].kids(kidIds)[0]
	fd = try c.boundFns.get("{typeMangled(tys, t)}.{nodes[callee].text}")
	f = newNode(
		nodes,
		kidIds,
		nIdent,
		nodes[callee].line,
		nodes[callee].col,
		text = nodes[fd].text.copy()
	)
	kids = [f, nodes[callee].kids(kidIds)[0]]
	kids.extend(nodes[e].kidsFrom(kidIds, 1))
	call = newNode(nodes, kidIds, nCall, nodes[e].line, nodes[e].col, kids = kids)
	res = c.checkCallTo(call, fd, expected, 0)
	c.boundCalls["{e} {typeMangled(tys, t)}"] = call
	c.typed(e, res)

# T.f(a), T a struct's name: the call f(a) of the function of T (typeFunctions) the caller sees,
# Mat4.perspective(...). none when T names no struct.
fn checkTypeFunctionCall(mut c Checker, e NodeId, expected TypeId?) TypeId?:
	callee = nodes[e].kids(kidIds)[0]
	obj = nodes[callee].kids(kidIds)[0]
	if nodes[obj].kind != nIdent or c.lookupVarNo(nameOf(nodes, obj)) >= 0: return none
	_, made = c.namedTypeOf(obj)
	td = try made
	if nodes[td].kind != nStructDecl: return none
	t = tyOfDecl(tys, nodes, kidIds, td)
	name = nodes[callee].text.copy()
	found = c.typeFunctions(t, name, false)
	if found.len > 1:
		c.errorAt(
			nodes[e].line,
			nodes[e].col,
			compileError(
				"AmbiguousFunction",
				[
					"{c.showTy(t)}",
					"{name}",
					"{c.moduleShown(nodes[found[0]].mod(kidIds))}",
					"{c.moduleShown(nodes[found[1]].mod(kidIds))}"
				]
			)
		)
		return tyError
	if found.isEmpty:
		c.errorAt(
			nodes[e].line,
			nodes[e].col,
			compileError("NoTypeFunction", ["{c.showTy(t)}", "{name}"])
		)
		c.checkArgsAlone(e)
		return tyError
	madeKid = newNode(
		nodes,
		kidIds,
		nIdent,
		nodes[callee].line,
		nodes[callee].col,
		text = nodes[found[0]].text.copy()
	)
	nodes[e].setKid(kidIds, 0, madeKid)
	nodes[nodes[e].kids(kidIds)[0]].flags |= flagInternal   # the type's form, written so
	c.checkCall(e, expected)

# How a call of the standard library's function fd is written when its type's form serves, or
# none: one that gives a language type T and takes no T makes one, the type's (`Mat4.perspective(...)`,
# `Quat.about(axis, angle)`); another taking first a type of its module or of the language's is a
# method of it (`q.rotate(v)`, `img.crop(...)`). A method before a free function.
fn typeForm(mut c Checker, fd NodeId) str?:
	std = (try c.modules.find(.id == nodes[fd].mod(kidIds))).std
	if not std or nodes[fd].hasFlag(flagExtern) or not c.declIsPub(fd) or
		not nodes[fd].names(kidIds).isEmpty:
		return none
	name = nodes[fd].text2(kidIds).copy()
	params = []
	for k in nodes[fd].kids(kidIds).copy():
		params.push(c.resolveType(nodes[k].types(kidIds)[0]))
	given = c.fnRetType(fd)
	if c.tKind(given) == tStruct and not isDefined(tys, given) and
		nodes[declOf(tys, given)].mod(kidIds) == "rt" and
		not params.any(isSameType(tys, it, given)):
		return "{nodes[declOf(tys, given)].text2(kidIds)}.{name}(...)"
	if params.isEmpty: return none
	ft = params[0]
	if isDefined(tys, ft) or (c.tKind(ft) == tStruct or c.tKind(ft) == tEnum) and
		nodes[declOf(tys, ft)].mod(kidIds) in [nodes[fd].mod(kidIds), "rt"]:
		return "{nodes[nodes[fd].kids(kidIds)[0]].text}.{name}(...)"
	none

# a call of no function named cname
fn unknownFunction(mut c Checker, cname str, line i64, col i64) TypeId:
	c.errorTyped(line, col, compileError("UnknownFunction", ["{cname}"]))

# the name `name` where the node at stands
fn namedLike(mut c Checker, name str, at NodeId) NodeId:
	newNode(nodes, kidIds, nIdent, nodes[at].line, nodes[at].col, text = name.copy())

# whether t is the runtime's type of that name
fn isRuntimeType(c Checker, t TypeId, name str):
	c.tKind(t) == tStruct and nodes[declOf(tys, t)].mod(kidIds) == "rt" and
		nodes[declOf(tys, t)].text2(kidIds) == name

# random(lo..hi) and rng.next(lo..hi) (rng a Random, -1 for the program's own sequence): a number
# of [lo, hi) of the range's type, an integer's or a float's; lo..=hi is lo..hi + 1. Checked as
# the runtime's draw of an i64 or an f64, converted back to the range's type.
fn checkRandomDraw(mut c Checker, e NodeId, rng NodeId?, expected TypeId?) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	r = c.argAt(e, 0)
	if nodes[r].kind != nRange or nodes[r].kids(kidIds).len != 2 or nodes[r].hasFlag(flagOpenEnd):
		c.errorAt(line, col, compileError("RandomRange", []))
		return tyError
	lo = nodes[r].kids(kidIds)[0]
	hi = nodes[r].kids(kidIds)[1]
	want TypeId? = expected if c.tKind(expected) == tInt or c.tKind(expected) == tFloat else none
	t = c.heldType(c.derefIfRef(lo, c.checkExpr(lo, want)))   # a range's ends: its base
	k = c.tKind(t)
	if k == tError: return tyError
	if k != tInt and k != tFloat:
		c.errorAt(line, col, compileError("RandomNotNumbers", ["{c.showTy(t)}"]))
		return tyError
	ht = c.derefIfRef(hi, c.checkExpr(hi, t))
	if not isSameType(tys, c.heldType(ht), t) and c.tKind(ht) != tError:
		c.errorAt(line, col, compileError("RandomEndsDiffer", ["{c.showTy(t)}", "{c.showTy(ht)}"]))
		return tyError
	kind = "Int" if k == tInt else "Float"
	callee = match rng:
		rng: newNode(nodes, kidIds, nField, line, col, text = "next{kind}", kids = [rng])
		none: c.internalName("randomIn" if k == tInt else "randomFloatIn", line, col)
	draw = newNode(nodes, kidIds, nCall, line, col, kids = [callee, lo, hi])
	wide = tyInt(64, true) if k == tInt else tyFloat(64)
	conversion = conversionMethod(c.showTy(t))
	if isSameType(tys, t, wide) or conversion == "":
		nodes[e] = nodes[draw].copied(kidIds)
	else:
		back = newNode(nodes, kidIds, nField, line, col, text = conversion, kids = [draw])
		nodes[e].setKids(kidIds, [back])
	c.checkExpr(e, expected)

# the runtime's function `name` of the type obj names (`str`, a number type, or a type of the
# runtime no declaration of the program hides): the one named after the type, as str.fromCode is
# strFromCode; none when obj names no such type or the runtime has no such function
fn typeOwnFunction(mut c Checker, obj NodeId, name str) NodeId?:
	if nodes[obj].kind != nIdent or c.lookupVarNo(nameOf(nodes, obj)) >= 0: return none
	t = nodes[obj].text
	if t != "str" and t != "n32" and t != "n64" and conversionMethod(t) == "":
		if c.findDeclInModule("rt", nStructDecl, t) == none: return none
		if c.ownModules().any(c.findDeclInModule(it, nStructDecl, t) != none): return none
	if name == "parse" and t != "i64" and t != "u64" and (conversionBits(conversionMethod(t)) > 0 or
			t == "n32" or t == "n64"):
		whole = c.findDeclInModule("rt", nFnDecl, "intParse")
		if whole != none: return whole
	fd = c.findDeclInModule("rt", nFnDecl, "{t[..1].lower()}{t[1..]}{capital(name)}")
	if fd is fd and c.declIsPub(fd): fd else: none

# x.f(a) made f(x, a) and checked as that call, f the function taking x's type t first that the
# caller sees (receiverFunction): for a type without a method of the name, if any.
fn callReceiverFunction(mut c Checker, e NodeId, maybeT TypeId?, expected TypeId?) TypeId?:
	t = try maybeT
	callee = nodes[e].kids(kidIds)[0]
	found = c.receiverFunctions(t, nodes[callee].text.copy())
	if found.len > 1: return c.ambiguousMethod(e, t, found)
	if found.isEmpty: return none
	fd = found[0]
	f = newNode(nodes, kidIds, nIdent, nodes[callee].line, nodes[callee].col)
	nodes[f].setText(nodes[fd].text.copy(), nodes[fd].name)
	nodes[f].flags |= flagInternal   # the method's form, written so
	kids = [f, nodes[callee].kids(kidIds)[0]]
	kids.extend(nodes[e].kidsFrom(kidIds, 1))
	nodes[e].setKids(kidIds, kids)
	c.checkCallTo(e, fd, expected, 0)

# x.name(...) for an x of type t that has no such method, two functions found it may call:
# reported, naming both
fn ambiguousMethod(mut c Checker, e NodeId, t TypeId, found NodeId[]) TypeId:
	name = nodes[nodes[e].kids(kidIds)[0]].text
	c.errorTyped(
		nodes[e].line,
		nodes[e].col,
		compileError(
			"AmbiguousMethod",
			[
				"{name}",
				"{c.showTy(t)}",
				"{c.moduleShown(nodes[found[0]].mod(kidIds))}",
				"{c.moduleShown(nodes[found[1]].mod(kidIds))}"
			]
		)
	)

# The functions named name taking a t first that the caller sees: typeFunctions' receivers.
fn receiverFunctions(mut c Checker, t TypeId, name str) NodeId[]:
	c.typeFunctions(t, name, true)

# The functions named name of the type t that the caller sees: a method of t's (generic: a
# function of t's module taking self first) or, giving a t (T.f()), meeting a bound (typeHome) or
# called by the derived code, t's module's own; else those of
# the caller's own module and of the modules it imports, else the runtime's (spec 5.2). A
# receiver's take a t first (x.f()), the others give a t and take none first (T.f()).
fn typeFunctions(mut c Checker, t TypeId, name str, receiver bool, typeHome bool = false):
	owns = c.ownModules()
	if isDefined(tys, t):
		d = c.findFunc(definedMethodName(tys[t].definedName, name))
		if d is d and c.isTypeFunction(d, t, receiver) and
			(nodes[d].mod(kidIds) in owns or c.declIsPub(d)):
			return [d]
	if c.tKind(t) == tStruct or c.tKind(t) == tEnum:
		home = nodes[declOf(tys, t)].mod(kidIds).copy()
		d = c.findDeclInModule(home, nFnDecl, name)
		if d is d and c.isTypeFunction(d, t, receiver) and
			(
				home in owns or c.takesSelf(d) or
					(not receiver or typeHome or c.inDerived()) and c.declIsPub(d)
			):
			return [d]
	found NodeId[] = []
	mods = owns.copy()
	aliases = owns.map(_: "")   # an imported module's alias, for zap fmt's import lines
	for own in owns:
		mi = moduleIndex(c.modules, own)
		if c.curMod >= 0 and mi >= 0:
			for imp in c.modules[mi].imports:
				mods.push(nodes[imp].text.copy())
				aliases.push(nodes[imp].text2(kidIds).copy())
	for i, m in mods:
		f = c.findDeclInModule(m, nFnDecl, name)
		if f is f and f not in found and c.isTypeFunction(f, t, receiver) and
			(m in owns or c.declIsPub(f)):
			found.push(f)
			if aliases[i] != "": c.noteImportUse(aliases[i])
	if found.isEmpty and owns[0] != "rt":
		# the runtime's, which every program sees (c.isDigit())
		f = c.findDeclInModule("rt", nFnDecl, name)
		if f is f and c.isTypeFunction(f, t, receiver) and c.declIsPub(f):
			found.push(f)
	found

# whether fd is a method with type parameters of its own (`fn map<U>(self T, ...)`), which the
# parser leaves a generic function: seen wherever its type is, as the type's other methods are
fn takesSelf(c Checker, fd NodeId):
	not nodes[fd].kids(kidIds).isEmpty and nodes[nodes[fd].kids(kidIds)[0]].text == "self"

# whether fd takes a t first (a receiver's), else gives a t and takes none first
fn isTypeFunction(mut c Checker, fd NodeId, t TypeId, receiver bool):
	if receiver: return c.takesFirst(fd, t)
	if nodes[fd].kind != nFnDecl or nodes[fd].hasFlag(flagExtern) or c.takesFirst(fd, t):
		return false
	c.fnRetType(fd)   # a result its body gives, known from here
	not nodes[fd].types(kidIds).isEmpty and c.writesType(fd, nodes[fd].types(kidIds)[0], t)

# a module as an error names it: the program's own (a together check's source's too) is main
fn moduleShown(c Checker, id str):
	"main" if id == "" or c.modules.any(.unit and .id == id) else id.copy()

# whether the function fd takes a value of type t first, read or changed: a struct or an enum by
# that type, or, a generic function, by the generic type t is an instance of; any other type as
# firstTypeMatches says
fn takesFirst(mut c Checker, fd NodeId, t TypeId) bool:
	if nodes[fd].kind != nFnDecl or nodes[fd].kids(kidIds).isEmpty or nodes[fd].hasFlag(flagExtern):
		return false
	p0 = nodes[fd].kids(kidIds)[0]
	if nodes[p0].ival != modeRead and nodes[p0].ival != modeMut: return false
	c.writesType(fd, nodes[p0].types(kidIds)[0], t)

# whether te, a type written in fd's signature, is t: a struct or an enum by that type's name, or,
# fd generic, by the generic type t is an instance of; any other type as firstTypeMatches says
fn writesType(mut c Checker, fd NodeId, te NodeId, t TypeId):
	k = c.tKind(t)
	if isDefined(tys, t): return nodes[te].kind == nTyName and c.namesAliasOf(fd, te, t)
	if k != tStruct and k != tEnum: return k != tError and c.firstTypeMatches(fd, te, t)
	if nodes[te].kind != nTyName: return false
	if nodes[fd].names(kidIds).isEmpty and c.namesAliasOf(fd, te, t): return true
	own = declOf(tys, t)
	generic = nodes[own].origin(kidIds) != none
	d = nodes[own].origin(kidIds) ?? own
	if generic and nodes[fd].names(kidIds).isEmpty or generic == nodes[te].types(kidIds).isEmpty:
		return false
	nodes[te].text == nodes[d].text or
		nodes[te].text == nodes[d].text2(kidIds) and nodes[te].text2(kidIds) == "" and
		nodes[fd].mod(kidIds) == nodes[d].mod(kidIds)

# whether te, written in fd, names the defined type t (`type Image = Grid<Rgba8>`), or t, not
# a defined type, itself once the name was read
fn namesAliasOf(mut c Checker, fd NodeId, te NodeId, t TypeId):
	if not nodes[te].types(kidIds).isEmpty: return false
	found = c.findDeclByGlobalName(
		nStructDecl,
		nodes[te].text,
		nameOf(nodes, te)
	) if nodes[te].text2(kidIds) ==
		globalAlias
		else c.findDeclInModule(nodes[fd].mod(kidIds), nStructDecl, nodes[te].text)
	named = found ?? return false
	if nodes[named].hasFlag(flagTypeAlias): return isSameType(tys, c.aliasedType(named), t)
	named == tys[t].decl and not isDefined(tys, t)   # the name already read as the type

# whether te, the written type of fd's first parameter, is t: fd's type parameters bound by t's
# parts (`fn sum<T Num>(xs T[])` takes a f64[]), a bare type parameter matching no type
fn firstTypeMatches(mut c Checker, fd NodeId, te NodeId, t TypeId):
	if nodes[te].kind == nTyName and c.isGenericParam(fd, nodes[te].text): return false
	if nodes[fd].names(kidIds).isEmpty: return isSameType(tys, c.resolveType(te), t)
	sub = Subst(names = [], types = [])
	c.unify(fd, te, t, sub)
	if c.teMentionsOpen(fd, te, sub.names): return false
	sav = move c.subst
	c.subst = move sub
	pt = c.resolveType(te)
	c.subst = sav
	isSameType(tys, pt, t)

# the arguments of the call e, whose method is not known (an unknown receiver's, or one the
# bounds do not give): still checked, so the names they read count as read
fn checkArgsAlone(mut c Checker, e NodeId):
	for i in 0..argCount(c, e):
		c.checkExpr(c.argAt(e, i), none)

# The call e of the method m: its arguments against m's parameters, read in the instance of the
# generic impl implDecl (when it has type parameters; -1: none), its result's type.
fn checkMethodCall(mut c Checker, e NodeId, m NodeId, implDecl NodeId?) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	obj = nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0]
	# the method's name and parameters are read from m at each use: checking changes c
	if c.receiverChanges(m) and not c.isSharedDeref(obj):
		c.changeVia = nodes[m].ival == methodInBlock and not nodes[m].hasFlag(flagPub)
		c.requireMutRoot(obj, line, col, nodes[m].text.copy())   # a shared value changes through its own methods
		c.changeVia = false
	c.fillArguments(e, m, 0)
	nparams = nodes[m].kids(kidIds).len
	nargs = c.argCount(e)
	if nargs != nparams:
		c.errorAt(
			line,
			col,
			compileError("ArgumentCount", ["method {nodes[m].text}", "{nparams}", "{nargs}"])
		)
	n = nargs
	if nparams < n:
		n = nparams
	# a method of an instantiated generic impl has its signature written in terms of the impl's
	# type parameters
	generic NodeId? = implDecl if c.implIsGenericOf(implDecl) else none
	for i in 0..n:
		pte = nodes[nodes[m].kids(kidIds)[i]].types(kidIds)[0]
		pt = match generic:
			impl: c.resolveInImpl(impl, pte, m)
			none: c.resolveType(pte)
		at = c.checkWidenedArg(e, i, pt)
		if not isAssignable(tys, at, pt) and not c.retypeFlex(c.argAt(e, i), pt):
			errorAt(
				c,
				line,
				col,
				compileError(
					"ArgumentTypeAt",
					["{i + 1}", "{nodes[m].text}", "{c.showTy(pt)}", "{c.showTy(at)}"]
				)
			)
		c.setArg(e, i, c.coerceTo(c.argAt(e, i), pt))
	c.checkMutArgs(e, m, 0)
	res = match generic:
		impl: c.resolveInImpl(impl, none, m)
		none: c.fnRetType(m)
	c.typed(e, res)

# `Shape.Circle(2.0)`, `.Circle(2.0)`: the call e makes the variant `name` of the enum enumd from
# its arguments, the payload's values in order
fn checkVariantArgs(mut c Checker, e NodeId, enumd NodeId, name str) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	v = c.kidNamed(enumd, name) ??
		return c.errorTyped(
			line,
			col,
			compileError("NotAVariant", ["{name}", "{nodes[enumd].text}"])
		)
	# the payload fields are read from the variant at each use: checking changes c
	npayload = nodes[v].kids(kidIds).len
	nargs = c.argCount(e)
	if nargs != npayload:
		c.errorAt(
			line,
			col,
			compileError("VariantArgumentCount", ["{nodes[v].text}", "{npayload}", "{nargs}"])
		)
	n = nargs
	if npayload < n:
		n = npayload
	for i in 0..n:
		f = nodes[v].kids(kidIds)[i]
		ft = c.resolveType(nodes[f].types(kidIds)[0])
		at = c.narrowArg(e, i, c.checkExpr(c.argAt(e, i), ft), ft)
		if not isAssignable(tys, at, ft):
			c.errorAt(
				line,
				col,
				compileError(
					"VariantFieldType",
					["{nodes[v].text}", "{nodes[f].text}", "{c.showTy(ft)}", "{c.showTy(at)}"]
				)
			)
		c.setArg(e, i, c.coerceTo(c.argAt(e, i), ft))
	res = tyOfDecl(tys, nodes, kidIds, enumd)
	c.typed(e, res)

# `Shape.Circle` (the node v: the variant's name) where the place expects a Shape, as `.Variant`
# would take it (at: the expression checked, v or its call): zap fmt writes `.Circle` (canon.zap)
fn qualifiedVariant(mut c Checker, v NodeId, at NodeId, enumd NodeId, expected TypeId?):
	if not noting: return
	t = innerOf(tys, expected) if c.tKind(expected) == tOption else expected ?? tyError
	if c.tKind(t) != tEnum or declOf(tys, t) != enumd or c.weakExpected == at: return
	line = nodes[v].line
	col = nodes[v].col
	start = qualifiedStart(c.file if c.curFile == "" else c.curFile, line, col)
	if start < 0: return
	c.canonNote(noteReplace, line, start + 1, col - 2 - start, "")
	if c.trialCopy == none and c.curFn is f: c.variantFns[f] = true

# The enum a `.Variant` (the node v, its name the variant's) belongs to: the type its place
# expects (an optional's value too), given only by where the value goes, not by a sibling (the
# expression `at` checked: v itself, or the call it is the callee of). The empty receiver gets
# the enum's name, by which the backend finds it. none after an error.
fn dotEnum(mut c Checker, v NodeId, at NodeId, expected TypeId?) NodeId?:
	name = nodes[v].text.copy()
	t = innerOf(tys, expected) if c.tKind(expected) == tOption else expected ?? tyError
	if c.tKind(t) != tEnum or c.weakExpected == at:
		typeName = c.showTy(t) if c.tKind(t) == tEnum else "Type"   # the enum a sibling asked for
		c.errorAt(
			nodes[v].line,
			nodes[v].col - 1,
			compileError("EnumUnknown", ["{name}", typeName])
		)
		return none
	d = declOf(tys, t)
	if c.kidNamed(d, name) == none:
		c.errorAt(
			nodes[v].line,
			nodes[v].col - 1,
			compileError("NotAVariant", ["{name}", "{c.showTy(t)}"])
		)
		return none
	obj = nodes[v].kids(kidIds)[0]
	nodes[obj].setText(nodes[d].text.copy(), nodes[d].name)
	d

# The type expression te (or, with te < 0, the result type of the function fnd) resolved with
# the type parameters of the instantiated impl implDecl bound. The checker's own bindings are
# set aside meanwhile and put back; c gets lists of its own, as the impl keeps its.
fn resolveInImpl(mut c Checker, implDecl NodeId, te NodeId?, fnd NodeId):
	sav = move c.subst
	c.subst = Subst(
		names = nodes[implDecl].names2(kidIds).copy(),
		types = nodes[implDecl].ints(kidIds).copy()
	)
	t = match te:
		te: c.resolveType(te)
		none: c.fnRetType(fnd)
	c.subst = sav
	t

# A part of a struct pattern (`Point(x, y) = p`, parse.zap patternParts): the value must be a
# Point, and a field written by position (#k) becomes the k-th field's name. Whether it holds.
fn patternField(mut c Checker, e NodeId):
	obj = nodes[e].kids(kidIds)[0]
	ot = c.derefIfRef(obj, c.checkExpr(obj, none))
	if c.tKind(ot) == tError: return false
	want = nodes[e].text2(kidIds).copy()
	if c.tKind(ot) != tStruct:
		errorAt(
			c,
			nodes[e].line,
			nodes[e].col,
			compileError("PatternNotStruct", ["{want}", "{c.showTy(ot)}"])
		)
		return false
	sd = declOf(tys, ot)
	if want != "" and nodes[sd].text2(kidIds) != want and nodes[sd].text != want:
		errorAt(
			c,
			nodes[e].line,
			nodes[e].col,
			compileError("PatternTypeDiffers", ["{want}", "{c.showTy(ot)}"])
		)
		return false
	if nodes[e].text.startsWith("#"):
		k = i64.parse(nodes[e].text[1..nodes[e].text.len]) ?? 0
		if k >= nodes[sd].kids(kidIds).len:
			errorAt(
				c,
				nodes[e].line,
				nodes[e].col,
				compileError("PatternTooManyFields", ["{want}", "{nodes[sd].kids(kidIds).len}"])
			)
			return false
		nodes[e].setText(nodes[nodes[sd].kids(kidIds)[k]].text.copy())
	nodes[e].setText2(kidIds, "")
	true

# A language vector's letters written r g b a or s t p q (`c.rgb`, `Color(r = 1.0, ...)`), as
# x y z w; any other name as it is.
fn vectorLetters(c Checker, maybeDecl NodeId?, move name str):
	xyzw = shader.swizzleSets[0]
	decl = maybeDecl ?? return name
	if nodes[decl].mod(kidIds) != "rt" or
		not nodes[decl].kids(kidIds).all(nodes[it].text in xyzw and nodes[it].text.len == 1):
		return name
	for letters in shader.swizzleSets[1..]:
		if name.bytes().all(str([it]) in letters):
			return str(name.bytes().map(xyzw[letters.indexOf(str([it])) ?? 0]))
	name

# A swizzle: `v.xy`, `c.rgb` of a struct of one number type whose fields have one-letter
# names, 2 to 4 of them in any order, is the struct `Vec2`..`Vec4` of the same module (of the
# type's family: `IVec2`.. for an `IVec3`) made of those fields (v.zx is Vec2(v.z, v.x)), as a
# shader reads its vectors. e is made that struct's
# literal (1); 0 when the name is not a swizzle of the type, -1 when the error is reported.
fn asSwizzle(mut c Checker, e NodeId, base TypeId):
	name = nodes[e].text.copy()
	decl = tys[base].decl ?? return 0
	if name.len < 2 or name.len > 4 or nodes[decl].kind != nStructDecl: return 0
	fields = nodes[decl].kids(kidIds).copy()
	letters = []
	fieldTy TypeId? = none
	for fd in fields:
		if nodes[fd].text.len != 1: return 0
		t = c.resolveType(nodes[fd].types(kidIds)[0])
		if fieldTy != none and t != fieldTy or c.tKind(t) != tInt and c.tKind(t) != tFloat: return 0
		fieldTy = t
		letters.push(nodes[fd].text.copy())
	for i in 0..name.len:
		if name[i..i + 1] not in letters: return 0
	family = nodes[decl].text2(kidIds).trimmedEnd("0123456789")
	target = c.findDeclInModule(nodes[decl].mod(kidIds), nStructDecl, "{family}{name.len}") ??
		c.findDeclInModule(nodes[decl].mod(kidIds), nStructDecl, "Vec{name.len}") ?? return 0
	if nodes[target].kids(kidIds).len != name.len: return 0
	for fd in nodes[target].kids(kidIds).copy():
		if c.resolveType(nodes[fd].types(kidIds)[0]) != fieldTy: return 0
	# a named value is read once per field; any other (`(a - b).xz`, `make().xy`) is bound once
	# first, by a match of one name the compiler writes, whose arm is the literal
	obj = nodes[e].kids(kidIds)[0]
	named = c.isNamedPlace(obj)
	temp = "$swizzle{e}"
	parts = []
	for i in 0..name.len:
		from = c.cloneNamedPlace(obj) if named
			else newNode(nodes, kidIds, nIdent, nodes[e].line, nodes[e].col, temp.copy())
		part = newNode(
			nodes,
			kidIds,
			nField,
			nodes[e].line,
			nodes[e].col,
			name[i..i + 1].copy(),
			[from]
		)
		parts.push(part)
	lit = e if named else newNode(nodes, kidIds, nStructLit, nodes[e].line, nodes[e].col)
	nodes[lit].kind = nStructLit
	nodes[lit].setText(nodes[target].text.copy(), nodes[target].name)
	nodes[lit].setText2(kidIds, "")
	nodes[lit].nodeMore(kidIds).names = nodes[target].kids(kidIds).map(nodes[it].text.copy())
	nodes[lit].setKids(kidIds, parts)
	if not named:
		pat = newNode(nodes, kidIds, nPattern, nodes[e].line, nodes[e].col, temp)
		nodes[pat].ival = patBind
		arm = newNode(nodes, kidIds, nArm, nodes[e].line, nodes[e].col, kids = [pat, lit])
		nodes[e].kind = nMatch
		nodes[e].setKids(kidIds, [obj, arm])
		nodes[e].setText("")
		nodes[e].flags |= flagInternal
	1

# whether an expression names a place without computing anything (a name, its fields, an
# element at a literal or a named index): reading it again reads the same value
fn isNamedPlace(c Checker, e NodeId) bool:
	k = nodes[e].kind
	if k == nIdent: return true
	if k == nDeref: return c.isNamedPlace(nodes[e].kids(kidIds)[0])
	if k == nIndex:
		i = nodes[e].kids(kidIds)[1]
		return (nodes[i].kind == nInt or nodes[i].kind == nIdent) and
			c.isNamedPlace(nodes[e].kids(kidIds)[0])
	k == nField and nodes[e].text2(kidIds) == "" and c.isNamedPlace(nodes[e].kids(kidIds)[0])

# a named place written again (a reference read through as the checker reads it again)
fn cloneNamedPlace(mut c Checker, e NodeId) NodeId:
	n = nodes[e].copied(kidIds)
	if n.kind == nDeref: return c.cloneNamedPlace(n.kids(kidIds)[0])
	if n.kind == nIdent or n.kind == nInt:
		return newNode(nodes, kidIds, n.kind, n.line, n.col, n.text.copy(), [])
	inner = c.cloneNamedPlace(n.kids(kidIds)[0])
	if n.kind == nIndex:
		return newNode(
			nodes,
			kidIds,
			nIndex,
			n.line,
			n.col,
			n.text.copy(),
			[inner, c.cloneNamedPlace(n.kids(kidIds)[1])]
		)
	newNode(nodes, kidIds, nField, n.line, n.col, n.text.copy(), [inner])

# the runtime's function whose name is fd's and List, when the call e gives a list as its first
# argument and the runtime has one (Process.output(["git", "log"]) is processOutputList's)
fn listVariant(mut c Checker, e NodeId, fd NodeId) NodeId?:
	if c.argCount(e) == 0: return none
	first = c.argAt(e, 0)
	if nodes[first].kind in [nNamedArg, nStr, nInterp, nLambda]: return none
	variant = try c.findDeclInModule("rt", nFnDecl, "{nodes[fd].text[4..]}List")
	probe = cloneTree(nodes, kidIds, first)
	if c.tKind(c.derefType(c.checkExpr(probe, none))) == tList and
		c.declIsPub(variant): variant else: none
