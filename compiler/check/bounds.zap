# Bounds of type parameters: `fn max<T Ord + Copy>(a T, b T) T`. The built-in bounds are Eq (== and
# !=), Ord (Eq and the orderings), Hash (Eq and a map key, hash()), Num (Ord, Show, arithmetic,
# unary minus, number literals, Copy), Show (print and interpolation) and Copy (plain data: a
# value copies where it is used, as an i64 does; a T without it owns memory); a program declares others,
# each a list of functions taking the type first (`bound Drawable` with `fn draw(mut self
# Drawable, mut r Renderer)` and `fn bounds(self Drawable) Rect` on its lines): a type has the
# bound when it has those functions (its methods, or functions taking it first that its module
# or the caller's imports hold), with those parameters and results, and a generic calls on a
# parameter with such a bound those only (monomorphized: each instance calls its type's own). A bound is written by its name, or a module's by alias.Name. A type parameter
# is used only through its bounds, checked on both sides of a generic:
#   - at the definition, before anything instantiates it, the body is checked once with each
#     type parameter standing for an opaque type of its own (a copy of i64 that equals no other
#     type) with only what its bounds give, and copy() and move; any other use is an error there.
#     The ownership analysis runs there too, a T owning memory unless it is Copy, so what a T
#     copies or moves is decided once: an instance, a copy of the body of its own,
#     is checked once with its types and reports nothing;
#   - at every instance, the types given must satisfy the bounds: the error is at the call,
#     not inside the body. The instances of a generic whose definition failed are not checked.

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

pub boundNames = ["Eq", "Ord", "Hash", "Num", "Show", "Copy"]

# the bounds written for a type parameter ("Ord+Hash") as a list
fn boundList(text str):
	if text == "": return []
	text.split("+")

# whether a parameter declared with `have` may be used where `need` is required
fn boundImplies(have str[], need str):
	for b in have:
		if b == need: return true
		if need == "Eq" and (b in ["Ord", "Hash", "Num"]): return true
		if need == "Ord" and b == "Num": return true
		if (need == "Show" or need == "Copy") and b == "Num": return true
	false

# the stand-in of a type parameter in the definition check, or -1
fn standInIndex(c Checker, maybeT TypeId?):
	t = maybeT ?? return -1
	if tys[t].param == "": return -1
	(c.aliasTy.indexOf(t) ?? -1)

# the types == compares with the operator itself: numbers, bool, str, enums without values
pub fn isEqNative(c Checker, t TypeId) bool:
	k = c.tKind(t)
	if k == tRef:
		return c.isEqNative(innerOf(tys, t))   # == compares what the references point to
	if k == tEnum: return not c.enumCarries(t)
	k in [tInt, tFloat, tBool, tStr, tError, tUnit]

# whether some variant of enum t carries values
pub fn enumCarries(c Checker, t TypeId) bool:
	nodes[declOf(tys, t)].kids(kidIds).any(not nodes[it].kids(kidIds).isEmpty)

# whether == compares values of type t: the native ones, and structs, tuples, enums, lists,
# arrays and optionals made of such parts (part by part, $eqN)
pub fn typeHasEq(mut c Checker, t TypeId) bool:
	open = []
	c.hasEqIn(t, open)

fn hasEqIn(mut c Checker, maybeT TypeId?, mut open NodeId[]) bool:
	t = maybeT ?? return true
	if c.isEqNative(t): return true
	k = c.tKind(t)
	if k in [tRef, tList, tArray, tOption]: return c.hasEqIn(tys[t].inner, open)
	if k == tStruct or k == tEnum:
		d = declOf(tys, t)
		if d in open: return true
		open.push(d)
		holders NodeId[] = [d]
		if k == tEnum:
			holders = nodes[d].kids(kidIds).copy()
		for h in holders:
			for f in nodes[h].kids(kidIds).copy():
				if not c.hasEqIn(c.resolveType(nodes[f].types(kidIds)[0]), open): return false
		return true
	false

# whether < orders values of type t: numbers and str, and tuples, lists and arrays of such
# (lexicographic, $cmpN)
pub fn typeHasOrd(mut c Checker, maybeT TypeId?) bool:
	k = c.tKind(maybeT)
	t = maybeT ?? return true
	if k in [tInt, tFloat, tStr, tError]: return true
	if k in [tRef, tList, tArray]: return c.typeHasOrd(tys[t].inner)
	if k == tStruct and tupleShown(tys[t].display) != tys[t].display:
		for f in nodes[declOf(tys, t)].kids(kidIds).copy():
			if not c.typeHasOrd(c.resolveType(nodes[f].types(kidIds)[0])): return false
		return true
	false

# whether the concrete type t has what the bound asks (a declared bound: see boundFailure)
fn typeSatisfies(mut c Checker, t TypeId, need str) bool:
	si = c.standInIndex(t)
	if si >= 0: return boundImplies(boundList(c.aliasBounds[si]), need)
	k = c.tKind(t)
	if k == tError: return true
	if need not in boundNames:
		return c.boundFailure(t, c.findDeclByGlobalName(nBoundDecl, need)) == ""
	if need == "Num": return k == tInt or k == tFloat
	if need == "Ord": return c.typeHasOrd(t)
	if need == "Hash": return c.isHashKey(t)
	if need == "Show": return c.isPrintable(t)
	if need == "Copy": return c.copiesFreely(t)
	c.typeHasEq(t)

# whether values of type t are map keys (Hash): integers, strings, a ref str, and structs of
# those and bools (hashed field by field, $hashN); not floats, whose == is not their bits'
pub fn isHashKey(mut c Checker, t TypeId) bool:
	if typeIsMapKey(tys, t): return true
	if c.tKind(t) != tStruct: return false
	c.fieldTypes(declOf(tys, t)).all(c.tKind(it) == tBool or c.isHashKey(it))

# a composite type compared or ordered in a generic instance: its $eqN / $cmpN written
fn noteComparison(mut c Checker, t0 TypeId, need str):
	t = t0
	while c.tKind(t) == tRef:
		t = innerOf(tys, t)   # references are compared by what they point to
	if need == "Ord" and not (c.tKind(t) == tInt or c.tKind(t) == tFloat or c.tKind(t) == tStr):
		c.noteDerive(t, deriveCmp | deriveEq)
	elif (need == "Eq" or need == "Ord") and not c.isEqNative(t):
		c.noteDerive(t, deriveEq)
	elif need == "Hash":
		c.noteHashKey(t)

# a struct used as a map key: its $hashN and $eqN written (the map's code calls hash() and ==)
pub fn noteHashKey(mut c Checker, t TypeId):
	if c.tKind(t) == tStruct:
		c.noteDerive(t, deriveHash | deriveEq)

# An operation that needs `need` on a value of type t: when t stands for a type parameter whose
# bounds do not give it, the error at the definition. A list, array, optional or reference of T
# asks it of T.
fn requireBound(mut c Checker, maybeT TypeId?, need str, what str, line i64, col i64):
	t0 = maybeT ?? return
	if c.hasBound(t0, need): return
	t = c.boundAskedOf(t0)
	si = c.standInIndex(t)
	nm = tys[t].param
	errorAt(
		c,
		line,
		col,
		compileError("NeedsBound", ["{what}", "{nm}", "{need}", "{c.aliasFn[si]}"])
	)

# whether a value of type t meets the bound: any type but a type parameter whose bounds do not
# give it (a list, array, optional or reference of T as T)
fn hasBound(c Checker, t0 TypeId, need str):
	si = c.standInIndex(c.boundAskedOf(t0))
	si < 0 or boundImplies(boundList(c.aliasBounds[si]), need)

# the type a bound is asked of: T for a list, array, optional or reference of T
fn boundAskedOf(c Checker, t0 TypeId):
	t = t0
	while c.tKind(t) in [tRef, tList, tArray, tOption] and tys[t].param == "":
		t = innerOf(tys, t)
	t

# the integer type a number parameter is declared with (<N n64>: its bound is n64), else none
fn numberBound(c Checker, bound str) TypeId?:
	t = primType(bound)
	t if c.tKind(t) == tInt else none

# the number parameter name stands for in the substitution in force (its tNum), or none
fn numberParam(c Checker, name str) TypeId?:
	t = c.substLookup(name)
	t if c.tKind(t) == tNum else none

# The type of number parameter t read as a value in a body: its integer type. An instance's
# value also gets the literal the backend reads it as (intLitOf).
fn numberValue(mut c Checker, t TypeId, line i64, col i64):
	of = innerOf(tys, t) if tys[t].inner != none else tyN64
	if tys[t].bits >= 0 and tys[t].decl == none:
		lit = newNode(nodes, kidIds, nInt, line, col, text = str(tys[t].bits))
		nodes[lit].ty = of
		tys[t].decl = lit
	of

# the number T[N]'s N names: the value of the number parameter in force (a tNum), or none after
# the error
fn arraySizeNamed(mut c Checker, te NodeId):
	name = nodes[te].text.copy()
	t TypeId? = none
	if name.startsWith("$param"):
		t = TypeId(i64.parse(name[6..]) ?? i64(tyError))
	else:
		t = c.substLookup(name)
	if c.tKind(t) == tNum: return t
	if c.tKind(t) == tError: return none   # a signature resolved before its parameters are known
	c.errorAt(
		nodes[te].line,
		nodes[te].col,
		compileError("LengthNotNumberParameter", ["{name}"])
	)
	none

# the arguments of generic tmpl with each number given a number parameter of its type (the type
# its value reads as in the instance's body)
fn numberArgs(mut c Checker, tmpl NodeId, args TypeId[]):
	out = args.copy()
	for i in 0..args.len:
		if i >= nodes[tmpl].bounds(kidIds).len: continue
		nb = c.numberBound(nodes[tmpl].bounds(kidIds)[i])
		if nb != none and c.tKind(args[i]) == tNum and tys[args[i]].param == "" and
			innerOf(tys, args[i]) != nb:
			out[i] = tyNum(tys, tys[args[i]].bits, nb)
	out

# why type argument t does not fit a parameter of bound (a number parameter's value that is no
# number or out of its type, a number for a type parameter), else ""
fn numberArgFailure(mut c Checker, bound str, t TypeId):
	isNum = c.tKind(t) == tNum
	nb = c.numberBound(bound) ?? return "the number {c.showTy(t)} is no type" if isNum else ""
	if c.tKind(t) == tError or isNum and tys[t].param != "": return ""
	if not isNum: return "{c.showTy(t)} is no {c.showTy(nb)} value"
	lo, hi = intBounds(tys, nb)
	if tys[t].bits < lo or tys[t].bits > hi: return "{tys[t].bits} is no {c.showTy(nb)}"
	""

# the instance's types against the template's bounds; false (an error at the site) when one
# does not satisfy them
# The bounds the type arguments of tmpl fail, each "i64 is not Eq, required by T" (the caller
# names the template when it reports them); a bound met notes the comparisons it needs.
fn instanceBoundFailures(mut c Checker, tmpl NodeId, types TypeId[]):
	out = []
	for i in 0..types.len:
		if i >= nodes[tmpl].bounds(kidIds).len: continue
		numberWhy = c.numberArgFailure(nodes[tmpl].bounds(kidIds)[i], types[i])
		if numberWhy != "":
			out.push("{numberWhy}, required by {nodes[tmpl].names(kidIds)[i]}")
			continue
		if c.numberBound(nodes[tmpl].bounds(kidIds)[i]) != none: continue
		for need in boundList(nodes[tmpl].bounds(kidIds)[i]):
			if need not in boundNames and c.standInIndex(types[i]) < 0:
				bd = c.findDeclByGlobalName(nBoundDecl, need)
				why = c.boundFailure(types[i], bd)
				if why != "":
					out.push("{c.showTy(types[i])} is not {c.shownBound(need)} ({why}), required by {nodes[tmpl].names(kidIds)[i]}")
			elif not c.typeSatisfies(types[i], need):
				out.push("{c.showTy(types[i])} is not {need}, required by {nodes[tmpl].names(kidIds)[i]}")
			elif c.standInIndex(types[i]) < 0:
				c.noteComparison(types[i], need)
	out

# every written bound is one of the four or a declared one, which the declaration's bounds then
# name by its global name (found so from any module, as the instances check them)
fn checkBoundNames(mut c Checker):
	for decl in c.decls[c.freshDecls..]:
		d = decl
		if nodes[d].kind == nBoundDecl and nodes[d].text2(kidIds) in boundNames:
			c.enterModuleOf(d)
			errorAt(
				c,
				nodes[d].line,
				nodes[d].col,
				compileError("BuiltinBoundName", ["{nodes[d].text2(kidIds)}"])
			)
		for b in 0..c.nodes[d].bounds(c.kidIds).len:
			names = []
			for nm in boundList(nodes[d].bounds(kidIds)[b]):
				if nm in boundNames or c.numberBound(nm) != none:
					names.push(nm.copy())
					continue
				if nm != "" and nm[0].isLower() and "." not in nm:
					c.enterModuleOf(d)
					c.errorAt(
						nodes[d].line,
						nodes[d].col,
						compileError("NumberParameterNotInteger", ["{nm}"])
					)
					names.push(nm.copy())
					continue
				if c.boundDeclNamed(d, nm) is bd:
					names.push(nodes[bd].text.copy())
				else:
					c.enterModuleOf(d)
					c.errorAt(nodes[d].line, nodes[d].col, compileError("UnknownBound", ["{nm}"]))
					names.push(nm.copy())
			nodes[d].nodeMore(kidIds).bounds[b] = names.join("+")
	c.curMod = -1
	c.curFile = ""

# the bound declaration a bound written in declaration d names (its global name, a name of d's
# module or one it imports, alias.Name of a module it imports), or none
fn boundDeclNamed(mut c Checker, d NodeId, nm str) NodeId?:
	global = c.findDeclByGlobalName(nBoundDecl, nm)
	if global is global and nodes[global].text != nodes[global].text2(kidIds):
		return global   # named already by its global name
	c.enterModuleOf(d)
	parts = nm.split(".")
	if parts.len == 2:
		return c.lookupDecl(nBoundDecl, parts[0], parts[1], nodes[d].line, nodes[d].col)
	c.lookupDecl(nBoundDecl, "", nm, nodes[d].line, nodes[d].col)

# Why the type t does not have the declared bound bd ("" when it does): each function the bound
# asks for is a method of t's or a function taking t first that t's module or the caller's
# imports hold (receiverFunctions), taking it as `mut self` as the bound's does, with parameters
# of the same modes and types and the same result.
fn boundFailure(mut c Checker, t TypeId, maybeBd NodeId?):
	k = c.tKind(t)
	bd = maybeBd ?? return ""
	if k == tError: return ""
	for want in nodes[bd].kids(kidIds).copy():
		m = c.findMethod(tys[t].name, nodes[want].text) if k == tStruct or k == tEnum else none
		why = match m:
			m: c.methodFailure(t, m, want)
			none: c.functionFailure(t, want)
		if why != "": return why
	""

# why t's method m is not the bound's function want ("" when it is): a generic impl's methods
# read with the instance's types
fn methodFailure(mut c Checker, t TypeId, m NodeId, want NodeId):
	changes = c.receiverChanges(m)
	implDecl = c.findImplDecl(tys[t].name, m) ?? return c.signatureFailure(want, m, 0, changes)
	if nodes[implDecl].names2(kidIds).isEmpty: return c.signatureFailure(want, m, 0, changes)
	sav = move c.subst
	c.subst = Subst(names = nodes[implDecl].names2(kidIds).copy(), types = nodes[implDecl].ints(kidIds).copy())
	why = c.signatureFailure(want, m, 0, changes)
	c.subst = sav
	why

# why no function taking t first is the bound's function want ("" when one is: noted in
# boundFns, where an instance's call of it finds it)
fn functionFailure(mut c Checker, t TypeId, want NodeId):
	wname = nodes[want].text.copy()
	found = c.typeFunctions(t, wname, true, typeHome = true)   # the type's own module's too
	if found.isEmpty: return "no function {wname} takes it first"
	if found.len > 1:
		return "its {wname} could be {c.moduleShown(nodes[found[0]].mod(kidIds))}.{wname} or {c.moduleShown(nodes[found[1]].mod(kidIds))}.{wname}"
	fd = found[0]
	sub = Subst(names = [], types = [])
	c.unify(fd, nodes[nodes[fd].kids(kidIds)[0]].types(kidIds)[0], t, sub)
	if nodes[fd].kids(kidIds).any(c.teMentionsOpen(fd, nodes[it].types(kidIds)[0], sub.names)) or
		c.teMentionsOpen(
			fd,
			none if nodes[fd].types(kidIds).isEmpty else nodes[fd].types(kidIds)[0],
			sub.names
		):
		return "its {wname} has type parameters its first parameter does not fix"
	sav = move c.subst
	c.subst = move sub
	why = c.signatureFailure(want, fd, 1, nodes[nodes[fd].kids(kidIds)[0]].ival == modeMut)
	c.subst = sav
	if why == "":
		c.boundFns["{typeMangled(tys, t)}.{wname}"] = fd
	why

# why the function f, its parameters from the from-th on (read under the checker's substitution),
# is not the bound's function want ("" when it is); changes: whether f takes the value as mut self
fn signatureFailure(mut c Checker, want NodeId, f NodeId, from i64, changes bool):
	wname = nodes[want].text.copy()
	if changes != nodes[want].hasFlag(flagMut):
		return "its {wname} does not take it as mut self" if nodes[want].hasFlag(flagMut)
			else "its {wname} takes it as mut self"
	n = nodes[f].kids(kidIds).len - from
	if n != nodes[want].kids(kidIds).len:
		return "its {wname} takes {n} parameter(s), the bound's {nodes[want].kids(kidIds).len}"
	for i in 0..c.nodes[want].kids(c.kidIds).len:
		wp = nodes[want].kids(kidIds)[i]
		mp = nodes[f].kids(kidIds)[i + from]
		wt = c.resolveType(nodes[wp].types(kidIds)[0])
		mt = c.resolveType(nodes[mp].types(kidIds)[0])
		if nodes[wp].ival != nodes[mp].ival or not isSameType(tys, wt, mt):
			return "its {wname} takes {c.paramText(mp, mt)} where the bound's takes {c.paramText(wp, wt)}"
	wr = c.fnRetType(want)
	mr = c.fnRetType(f)
	if not isSameType(tys, wr, mr):
		return "its {wname} gives {c.showTy(mr)} where the bound's gives {c.showTy(wr)}"
	""

# a parameter as written: mut r Renderer
fn paramText(c Checker, p NodeId, t TypeId):
	mode = "mut " if nodes[p].ival == modeMut else "move " if nodes[p].ival == modeMove else ""
	"{mode}{nodes[p].text} {c.showTy(t)}"

# the declared bounds among those of a stand-in's parameter (its built-in ones left out)
fn declaredBounds(c Checker, si i64):
	boundList(c.aliasBounds[si]).filter(it not in boundNames)

# A method called on a value of a type parameter in the definition check: copy() (every type
# has it), hash() with Hash, or one its declared bounds declare; false after the error.
fn boundGivesMethod(mut c Checker, t TypeId, name str, line i64, col i64):
	si = c.standInIndex(t)
	if si < 0 or name == "copy" or name == "take": return true
	if name == "hash":
		c.requireBound(t, "Hash", "hash()", line, col)
		return true
	if c.boundMethodOf(si, name) != none: return true
	declared = c.declaredBounds(si)
	nm = tys[t].param
	if declared.isEmpty:
		c.errorAt(
			line,
			col,
			compileError("MemberNeedsBound", ["{name}", "{nm}", "{c.aliasFn[si]}"])
		)
		return false
	shown = declared.map(c.shownBound(it)).join(", ")
	c.errorAt(line, col, compileError("BoundLacksMethod", ["{nm}", "{shown}", "{name}"]))
	false

# the method name of the declared bounds of stand-in si (its declaration in the bound), or none
fn boundMethodOf(c Checker, si i64, name str) NodeId?:
	for b in c.declaredBounds(si):
		bd = c.findDeclByGlobalName(nBoundDecl, b) ?? continue
		if c.kidNamed(bd, name) is m: return m
	none

# a declared bound's name as written (its global name's declaration)
fn shownBound(c Checker, global str):
	match c.findDeclByGlobalName(nBoundDecl, global):
		bd: nodes[bd].text2(kidIds).copy()
		none: global.copy()

# an opaque copy of type base standing for the type parameter nm of the function fname
fn standIn(mut c Checker, base TypeId, move nm str, move bounds str, move fname str):
	t = tys[base].copy()
	t.param = nm
	id = tyFresh(tys, t)
	c.aliasTy.push(id)
	c.aliasBounds.push(bounds)
	c.aliasFn.push(fname)
	id

# The definition check (see the top of this file) over the program's generic functions and
# impls, before anything instantiates them; the ones that fail are noted, and their instances are
# not checked again. The declarations, instances and printing functions it makes are dropped. A
# generic that needs the result of a function whose body gives it, not checked yet, is checked
# again once those bodies are.
fn checkBoundsAtDefinition(mut c Checker):
	generics = c.decls[c.freshDecls..]
		.filter(not nodes[it].names(kidIds).isEmpty and nodes[it].mod(kidIds) != "derive")
	while not generics.isEmpty:
		generics = c.checkDefinitions(generics)
		early = move c.earlyResults
		c.earlyResults = []
		for f in early:
			if (c.resultState.get(f) ?? -1) == resultOpen or
				(c.receiverState.get(f) ?? -1) == receiverOpen:
				c.checkOpenBody(f)

# the definition check of the generics, those that must wait for results given back
fn checkDefinitions(mut c Checker, all NodeId[]):
	# (a file's own errors would blur them: its generics are checked by their instances)
	generics = all.filter(not c.hasErrorsIn(nodes[it].file(kidIds)))
	nd = c.decls.len
	ni = c.instances.len
	nderive = c.deriveTypes.len
	waiting = []
	c.atDefinition = true
	for d in generics:
		before = c.errors
		c.deferred = false
		if nodes[d].kind == nFnDecl:
			subT = c.standIns(d, d)
			c.enterScope()
			# c.subst.names holds the names while the body is checked: a list of its own
			c.subst = Subst(names = nodes[d].names(kidIds).copy(), types = subT)
			c.checkFnBody(d, none, false)
			if c.errors == before and not c.deferred:
				c.checkDefinitionGives(d)   # (lowered per instance only)
			c.exitScope()
		elif nodes[d].kind == nImplDecl and c.findTypeDecl(nodes[d].text, nameOf(nodes, d)) is td:
			subT = c.standIns(d, td)
			n0 = c.decls.len
			c.programInstantiate(td, subT)
			for k in n0..c.decls.len:
				im = c.decls[k]
				if nodes[im].kind == nImplDecl and nodes[im].origin(kidIds) == d:
					c.checkImplMethods(im)   # the instance of d over the stand-ins
		c.receiversTried(d)
		if c.deferred:
			waiting.push(d)
		elif c.errors > before:
			c.failedGenerics.push(d)
	c.deferred = false
	c.atDefinition = false
	c.subst = Subst(names = [], types = [])
	c.truncateDecls(nd)
	c.truncateInstances(ni)
	c.deriveTypes.truncate(nderive)
	c.deriveKinds.truncate(nderive)
	c.deriveDone.truncate(nderive)
	waiting

# The stand-ins of generic d's type parameters, whose bounds the declaration bounded declares:
# each an opaque copy of i64 that has only what its bounds give.
fn standIns(mut c Checker, d NodeId, bounded NodeId):
	names = nodes[d].names(kidIds).copy()
	out = []
	for p in 0..names.len:
		bounds = ""
		if p < nodes[bounded].bounds(kidIds).len:
			bounds = nodes[bounded].bounds(kidIds)[p].copy()
		# the stand-in records its parameter and generic's names apart from the declaration; a
		# number parameter's is a number not known (its length, where it sizes an array)
		nb = c.numberBound(bounds)
		base = tyNum(tys, -1, nb) if nb != none else tyInt(64, true)
		out.push(c.standIn(base, names[p].copy(), bounds, nodes[d].text2(kidIds).copy()))
	out
