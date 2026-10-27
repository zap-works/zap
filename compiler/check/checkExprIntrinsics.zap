# The checking of builtin and intrinsic calls, struct and vector makers (checkExpr.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# each one's name, arity, parameters' code and result's code
type Signature:
	name str
	arity i64
	params i64
	result i64
	traits str

builtinSignatures = [Signature("sleepMs", 1, 1, 0, ""), Signature("exit", 1, 1, 0, "")]

intrinsicSignatures = [
	Signature("__ld64", 1, 2, 2, "S"),
	Signature("__ld32", 1, 2, 2, "S"),
	Signature("__ld16", 1, 2, 2, "S"),
	Signature("__ld8", 1, 2, 2, "S"),
	Signature("__st64", 2, 2, 0, "S"),
	Signature("__st32", 2, 2, 0, "S"),
	Signature("__st16", 2, 2, 0, "S"),
	Signature("__st8", 2, 2, 0, "S"),
	Signature("__memcpy", 3, 2, 0, ""),
	Signature("__memset", 3, 2, 0, ""),
	Signature("__globals", 0, 0, 2, "S"),
	Signature("__database", 0, 0, 2, ""),
	Signature("__strraw", 1, 3, 2, ""),
	Signature("__ftoi", 1, 5, 2, ""),
	Signature("__addr", 1, 2, 2, "ASP"),
	Signature("__sizeof", 1, 2, 2, "AKS"),
	Signature("__stride", 1, 2, 2, "AKS"),
	Signature("__tykind", 1, 2, 2, "AKS"),
	Signature("__tysigned", 1, 2, 2, "AKS"),
	Signature("__tylo", 1, 2, 2, "AKS"),
	Signature("__tyhi", 1, 2, 2, "AKS"),
	Signature("__owning", 1, 2, 2, "AKS"),
	Signature("__window", 1, 2, 2, "AKS"),
	Signature("__descriptor", 1, 2, 2, "A"),
	Signature("__strof", 3, 2, 4, ""),
	Signature("__at", 2, 2, 2, "PL"),
	Signature("__bytesAt", 3, 2, 2, "PL"),
	Signature("__setAt", 3, 2, 2, "P"),
	Signature("__zeroElem", 1, 2, 2, "PL"),
	Signature("__peek", 2, 2, 2, "PL"),
	Signature("__poke", 2, 2, 0, "P"),
	Signature("__cast", 1, 2, 2, "SL"),
	Signature("__lds32", 1, 2, 2, "S"),
	Signature("__lds16", 1, 2, 2, "S"),
	Signature("__lds8", 1, 2, 2, "S"),
	Signature("__drop", 1, 2, 0, "P"),
	Signature("__alias", 1, 2, 2, "PL"),
	Signature("__forget", 1, 2, 0, "P"),
	Signature("__xadd", 2, 2, 2, ""),
	Signature("__prefetch", 1, 2, 0, "S"),
	Signature("__pause", 0, 0, 0, ""),
	Signature("__cmpxchg", 3, 2, 2, ""),
	Signature("__osThreadEntry", 0, 0, 2, ""),
	Signature("__callback", 1, 2, 2, ""),
	Signature("__frameAddress", 0, 0, 2, ""),
	Signature("__callerSp", 0, 0, 2, ""),
	Signature("__sigreturn", 0, 0, 2, ""),
	Signature("__fence", 1, 2, 2, ""),
	Signature("__tlsGet", 1, 2, 2, "S"),
	Signature("__tlsSet", 2, 2, 0, ""),
	Signature(
		"__callRec",
		1,
		2,
		0,
		""
	), Signature("__fini", 0, 0, 0, ""), Signature("__returnAddress", 0, 0, 2, ""), Signature("__bswap", 1, 2, 2, "S")]

# whether intrinsic nm has trait t (intrinsicSignatures' last column): A one argument of any type,
# an i64 result; K known when compiling; P its arguments are places; S emitted in place, rax and
# rcx alone; L its result points into memory it does not own (never dropped)
fn intrinsicHas(nm str, t str):
	i = signatureAt(intrinsicSignatures, nm)
	i >= 0 and t in intrinsicSignatures[i].traits

# the place of builtin `name` in builtinSignatures, or -1
fn builtinAt(name str):
	builtinSignatures.findIndex(.name == name) ?? -1

# the place of `name` in a table of signatures, or -1
fn signatureAt(table Signature[], name str):
	table.findIndex(.name == name) ?? -1

# Intrinsics whose type depends on their arguments (the typed runtime is written over them).
# None when the name is an ordinary intrinsic.
fn rawIntrinsicType(mut c Checker, e NodeId, name str, expected TypeId?) TypeId?:
	nargs = c.argCount(e)
	line = nodes[e].line
	col = nodes[e].col
	if name == "__callback" and nargs == 1:
		# the address of the entry with the system's convention that calls a top-level function
		# (a signal's handler): what an extern fn is given for a callback, as a word
		a = c.argAt(e, 0)
		ft = c.checkExpr(a, none)
		if nodes[a].kind != nIdent or not nodes[a].hasFlag(flagFnRef) or c.tKind(ft) != tFn or
			not c.isCallbackType(ft):
			c.errorAt(line, col, compileError("CallbackNotFunction", ["1", "{name}"]))
		return tyInt(64, true)
	if intrinsicHas(name, "A"):
		if nargs != 1:
			c.errorAt(line, col, compileError("ArgumentCount", ["{name}", "1", "{nargs}"]))
			return tyError
		c.checkExpr(c.argAt(e, 0), none)
		return tyInt(64, true)
	if name in ["__at", "__zeroElem", "__setAt"]:
		want = 2
		if name == "__zeroElem":
			want = 1
		if name == "__setAt":
			want = 3
		if nargs != want:
			c.errorAt(line, col, compileError("ArgumentCount", ["{name}", "{want}", "{nargs}"]))
			return tyError
		lt = c.checkExpr(c.argAt(e, 0), none)
		if c.tKind(lt) != tList:
			c.errorAt(line, col, compileError("IntrinsicNeedsList", ["{name}", "{c.showTy(lt)}"]))
			return tyError
		elem = innerOf(tys, lt)
		if nargs >= 2:
			c.checkExpr(c.argAt(e, 1), tyInt(64, true))
		if nargs == 3:
			vt = c.checkExpr(c.argAt(e, 2), elem)
			# (a value carrying a range a comparison proved is of its plain type)
			if not isSameType(tys, vt, elem) and
				(tys[elem].ranged or not isSameType(tys, rangeBase(tys, vt), elem)):
				c.errorAt(
					line,
					col,
					compileError("IntrinsicType", ["{c.showTy(elem)}", "{c.showTy(vt)}"])
				)
			return tyUnit
		return elem
	if name == "__bytesAt":
		# __bytesAt(b, at, n): the address of n bytes of a u8[] or a u8[N] from at, checked
		if nargs != 3:
			c.errorAt(line, col, compileError("ArgumentCount", ["__bytesAt", "3", "{nargs}"]))
			return tyError
		bt = c.checkExpr(c.argAt(e, 0), none)
		if c.tKind(bt) != tList and c.tKind(bt) != tArray:
			c.errorAt(
				line,
				col,
				compileError("IntrinsicNeedsList", ["__bytesAt", "{c.showTy(bt)}"])
			)
			return tyError
		c.checkExpr(c.argAt(e, 1), tyInt(64, true))
		c.checkExpr(c.argAt(e, 2), tyInt(64, true))
		return tyInt(64, true)
	if name == "__peek":
		if nargs != 2:
			c.errorAt(line, col, compileError("ArgumentCount", ["__peek", "2", "{nargs}"]))
			return tyError
		c.checkExpr(c.argAt(e, 0), tyInt(64, true))
		return c.checkExpr(c.argAt(e, 1), none)
	if name == "__poke":
		if nargs != 2:
			c.errorAt(line, col, compileError("ArgumentCount", ["__poke", "2", "{nargs}"]))
			return tyError
		c.checkExpr(c.argAt(e, 0), tyInt(64, true))
		c.checkExpr(c.argAt(e, 1), none)
		return tyUnit
	if name == "__drop" or name == "__forget":
		if nargs != 1:
			c.errorAt(line, col, compileError("ArgumentCount", ["{name}", "1", "{nargs}"]))
			return tyError
		c.checkExpr(c.argAt(e, 0), none)
		return tyUnit
	if name == "__alias":
		if nargs != 1:
			c.errorAt(line, col, compileError("ArgumentCount", ["__alias", "1", "{nargs}"]))
			return tyError
		return c.checkExpr(c.argAt(e, 0), expected)
	if name == "__cast":
		if nargs != 1:
			c.errorAt(line, col, compileError("ArgumentCount", ["__cast", "1", "{nargs}"]))
			return tyError
		c.checkExpr(c.argAt(e, 0), tyInt(64, true))
		return expected ?? c.errorTyped(line, col, compileError("IntrinsicNeedsType", []))
	none

fn codeType(mut c Checker, code i64):
	if code == 1: return tyInt(64, true)
	if code == 2: return tyInt(64, true)
	if code == 3: return tyFloat(64)
	if code == 4: return tyStr
	if code == 5: return tyBool
	if code == 6: return tyList(tys, tyStr)
	if code == 7: return tyOption(tys, tyStr)
	tyUnit

fn paramCodeType(mut c Checker, code i64):
	if code == 1: return tyInt(64, true)
	if code == 2: return tyInt(64, true)
	if code == 3: return tyStr
	if code == 4: return tyList(tys, tyInt(64, true))
	tyFloat(64)

fn isPrintBuiltin(n str):
	n == "print" or n == "eprint"

fn checkBuiltinCall(mut c Checker, e NodeId, name str, arity i64, pcode i64, rcode i64) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	nargs = c.argCount(e)
	if nargs != arity:
		c.errorAt(line, col, compileError("ArgumentCount", ["{name}", "{arity}", "{nargs}"]))
		return tyError
	for i in 0..nargs:
		pt = c.paramCodeType(pcode)
		at = c.checkExpr(c.argAt(e, i), pt)
		c.noteWidenedAt(c.argAt(e, i), pt)
		c.noteNarrowedAt(c.argAt(e, i), pt)
		if intWidensTy(tys, at, pt):
			c.setArg(e, i, c.numWiden(c.argAt(e, i), pt))
			at = typeOf(nodes, c.argAt(e, i))
		elif not isSameType(tys, at, pt) and c.narrowsProven(c.argAt(e, i), pt):
			c.setArg(e, i, c.narrowProven(c.argAt(e, i), pt))
			at = typeOf(nodes, c.argAt(e, i))
		if not isSameType(tys, at, pt) and not c.retypeFlex(c.argAt(e, i), pt):
			errorAt(
				c,
				line,
				col,
				compileError(
					"ArgumentTypeAt",
					["{i + 1}", "{name}", "{c.showTy(pt)}", "{c.showTy(at)}"]
				)
			)
	res = c.codeType(rcode)
	c.typed(e, res)

# `opt?.method(args)`: desugared into `match opt { v => Some(v.method(args))  none => none }`.
# The result is `R?` where R is the method's result; a method that gives nothing makes it a
# statement, `match opt { v => v.method(args)  none => pass }`. The name points into the optional,
# which the method may change in place when it is a place that may change.
fn checkSafeCall(mut c Checker, e NodeId) TypeId:
	callee = nodes[e].kids(kidIds)[0]
	obj = nodes[callee].kids(kidIds)[0]
	line = nodes[e].line
	col = nodes[e].col
	ot = c.checkExpr(obj, none)
	if c.tKind(ot) != tOption:
		if c.tKind(ot) != tError:
			c.errorAt(line, col, compileError("OptionalCallNotOptional", ["{c.showTy(ot)}"]))
		return c.typed(e, tyError)
	inner = c.innerOrError(ot)
	tmpName = "_sc{c.safeCallCount}"
	c.safeCallCount += 1
	recv = newNode(   # the receiver and the arm's pattern each name it
		nodes,
		kidIds,
		nIdent,
		nodes[callee].line,
		nodes[callee].col,
		text = tmpName.copy()
	)
	innerCallee = newNode(nodes, kidIds, nField, nodes[callee].line, nodes[callee].col)
	nodes[innerCallee].pushKid(kidIds, recv)
	nodes[innerCallee].setText(nodes[callee].text.copy(), nodes[callee].name)   # the desugared call names the method too
	nodes[innerCallee].flags = nodes[callee].flags & flagSize
	innerCall = newNode(nodes, kidIds, nCall, line, col)
	nodes[innerCall].pushKid(kidIds, innerCallee)
	for i in 0..argCount(c, e):
		madeKid = c.argAt(e, i)
		nodes[innerCall].pushKid(kidIds, madeKid)
	valuePat = newNode(nodes, kidIds, nPattern, line, col)
	nodes[valuePat].ival = patBind
	nodes[valuePat].setText(tmpName)
	nodes[valuePat].flags = flagSafe
	c.enterScope()
	c.bindSafeName(valuePat, obj, inner, line, col)
	rt = c.checkExpr(innerCall, none)
	c.exitScope()
	payload = innerCall
	if c.tKind(rt) == tRef:
		# a window into the matched temporary would dangle once the match ends: plain data is
		# copied out, anything else must be kept by the program
		if not c.copiesFreely(rt):
			c.errorAt(line, col, compileError("OptionalCallBorrow", []))
		payload = c.derefNode(innerCall)
		nodes[payload].flags |= flagAutoCopy
		rt = typeOf(nodes, payload)
	res = tyUnit
	some = payload
	non = newNode(nodes, kidIds, nBlock, line, col)   # pass
	if c.tKind(rt) != tUnit:
		res = tyOption(tys, rt)
		some = newNode(nodes, kidIds, nSome, line, col)
		nodes[some].pushKid(kidIds, payload)
		nodes[some].ty = res
		non = newNode(nodes, kidIds, nNone, line, col)
	nodes[non].ty = res
	valueArm = newNode(nodes, kidIds, nArm, line, col)
	nodes[valueArm].pushKid(kidIds, valuePat)
	nodes[valueArm].pushKid(kidIds, some)
	nonePat = newNode(nodes, kidIds, nPattern, line, col)
	nodes[nonePat].ival = patNone
	noneArm = newNode(nodes, kidIds, nArm, line, col)
	nodes[noneArm].pushKid(kidIds, nonePat)
	nodes[noneArm].pushKid(kidIds, non)
	nodes[e].kind = nMatch
	nodes[e].setKids(kidIds, [obj, valueArm, noneArm])
	nodes[e].setText2(kidIds, "")
	nodes[e].flags = 0
	c.typed(e, res)

# The name pat (flagSafe) a `?.` call gives the value of the optional obj: it points into the
# optional, `mut` when that is a place that may change (else a change names the optional)
fn bindSafeName(mut c Checker, pat NodeId, obj NodeId, t TypeId, line i64, col i64):
	changes = c.scrutRootIsMut(obj, lowered = true)
	nodes[pat].flags = flagSafe | (flagMut if changes else 0)
	v = c.addVar(nodes[pat].text, t, changes, true, line, col)
	c.vars[v].lentFrom = c.lookupCall(obj)
	c.vars[v].placeOf = obj

# whether a value of type t can be encoded; `open` holds the declarations of the structs and
# enums looked into: one met again is a recursion through a box or a list, decided where it
# began (a declaration, not a type id: resolving a field's type may give a new id each time).
# The walk is linear in the declarations, not exponential in the recursive fields.
fn serializableIn(mut c Checker, maybeT TypeId?, mut open NodeId[], binary bool) bool:
	t = maybeT ?? return true
	k = tys[t].kind
	if (k == tStruct or k == tEnum) and declOf(tys, t) in open: return true
	if k == tArray and binary: return c.serializableIn(innerOf(tys, t), open, binary)   # its N values
	if k in [tFn, tResult, tUnit, tRef, tArray]: return false
	if k == tBox and tys[t].counted:
		return false   # a shared value is one place, not data to send
	if k in [tOption, tList, tBox]: return c.serializableIn(tys[t].inner, open, binary)
	if k == tMap:
		return typeIsMapKey(tys, tys[t].inner) and c.serializableIn(tys[t].val, open, binary)
	if k == tStruct or k == tEnum:
		open.push(declOf(tys, t))
		fields = []
		if k == tStruct:
			fields = nodes[declOf(tys, t)].kids(kidIds).copy()
		else:
			for v in nodes[declOf(tys, t)].kids(kidIds):
				fields.extend(nodes[v].kids(kidIds))
		if fields.any(
			not c.serializableIn(c.resolveType(nodes[it].types(kidIds)[0]), open, binary)
		):
			return false
	true

fn isSerializable(mut c Checker, t TypeId, binary bool = false) bool:
	open = []
	c.serializableIn(t, open, binary)

# A type name used as a receiver (Type.fromJson, Enum.Variant): the declaration, with a generic
# template instantiated from the written type arguments. Returns (named, resolved).
fn namedTypeOf(mut c Checker, obj NodeId) (NodeId?, NodeId?):
	td = c.lookupTypeDecl("", nodes[obj].text, nodes[obj].line, nodes[obj].col) ??
		return (none, none)
	if c.isGenericTemplate(td):
		return (td, c.instantiateFromNode(td, obj, nodes[obj].line, nodes[obj].col))
	(td, td)

# argument i checked against its parameter's type pt (checked: its type, when it already is),
# widened to it when a number is narrower (noted for zap fmt where a conversion written there is
# that widening): its type
fn checkWidenedArg(mut c Checker, e NodeId, i i64, pt TypeId, checked TypeId? = none) TypeId:
	at = checked ?? c.checkExpr(c.argAt(e, i), pt)
	c.noteWidenedAt(c.argAt(e, i), pt, true)
	if not isAssignable(tys, at, pt):
		c.setArg(e, i, c.numWiden(c.argAt(e, i), pt))
		at = typeOf(nodes, c.argAt(e, i))
	c.narrowArg(e, i, at, pt)

# argument i, of type at, given to its parameter's type pt: narrowed to it where proven inside
# (narrowProven; noted for zap fmt where a conversion written there does it): its type
fn narrowArg(mut c Checker, e NodeId, i i64, at TypeId, pt TypeId):
	c.noteNarrowedAt(c.argAt(e, i), pt)
	if isAssignable(tys, at, pt) or not c.narrowsProven(c.argAt(e, i), pt): return at
	c.setArg(e, i, c.narrowProven(c.argAt(e, i), pt))
	typeOf(nodes, c.argAt(e, i))

# a call of the function fd, its arguments from firstMut on checked against its mut parameters
fn checkCallTo(mut c Checker, e NodeId, fd NodeId, expected TypeId?, firstMut i64) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	if not nodes[fd].names(kidIds).isEmpty:
		rt = c.checkGenericCall(e, fd, expected)
		c.checkMutArgs(e, fd, firstMut)
		return rt
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind == nIdent and not nodes[callee].types(kidIds).isEmpty:
		c.typeArgCountOk(fd, nodes[callee].types(kidIds).len, line, col)   # a function with none
	c.fillArguments(e, fd, 0)
	# the parameters and the name are read from fd at each use: checking the arguments changes c
	nparams = nodes[fd].kids(kidIds).len
	nargs = c.argCount(e)
	if nargs != nparams:
		c.errorAt(
			line,
			col,
			compileError("ArgumentCount", ["{nodes[fd].text}", "{nparams}", "{nargs}"])
		)
	n = nargs
	if nparams < n:
		n = nparams
	for i in 0..n:
		if nodes[nodes[fd].kids(kidIds)[i]].ival == modeOut:
			c.checkOutArg(e, fd, i)
			continue
		pt = c.resolveType(nodes[nodes[fd].kids(kidIds)[i]].types(kidIds)[0])
		c.inferRefArg(e, i, pt)
		at = c.checkWidenedArg(e, i, pt)
		if nodes[fd].hasFlag(flagExtern) and c.listOfBytes(at, pt):
			continue   # the bytes of a list of plain values: its buffer, as is
		if not isAssignable(tys, at, pt) and not c.retypeFlex(c.argAt(e, i), pt):
			errorAt(
				c,
				line,
				col,
				compileError(
					"ArgumentType",
					[
						"{c.argumentOf(e, i, nodes[fd].text)}",
						"{c.showTy(pt)}",
						"{c.showTy(at)}",
						"{c.mismatchHint(at, pt)}"
					]
				)
			)
		c.setArg(e, i, c.coerceTo(c.argAt(e, i), pt))
	c.checkMutArgs(e, fd, firstMut)
	if nodes[fd].hasFlag(flagExtern):
		c.checkCallbackArgs(e, fd)
	res = c.fnRetType(fd)
	c.typed(e, res)

# The argument of out parameter i: `out x`, x a mut local of the parameter's type or a new
# name, declared here with that type (`_` is a value no one reads). The argument is the word
# that carries x's address.
fn checkOutArg(mut c Checker, e NodeId, fd NodeId, i i64):
	a = c.argAt(e, i)
	line = nodes[a].line
	col = nodes[a].col
	if nodes[a].kind != nUnary or nodes[a].ival != unOut:
		errorAt(
			c,
			line,
			col,
			compileError("OutArgumentSpelling", ["{c.argumentOf(e, i, nodes[fd].text)}"])
		)
		c.checkExpr(a, none)
		return
	t = c.resolveType(nodes[nodes[fd].kids(kidIds)[i]].sub(kidIds)[0])
	x = nodes[a].kids(kidIds)[0]
	if nodes[x].text == "_":
		nodes[x].setText("$out{a}")
	v = c.lookupVarNo(nameOf(nodes, x))
	if v < 0:
		nv = c.addVar(nodes[x].text, t, false, false, line, col)
		if nodes[x].text.startsWith("$"):
			c.vars[nv].used = true
	elif not c.receiverChange(v, line, col) and not c.vars[v].isMut:
		errorAt(
			c,
			line,
			col,
			compileError("OutTargetImmutable", ["{nodes[x].text}"])
		)
	elif not isSameType(tys, c.vars[v].ty, t):
		c.errorAt(
			line,
			col,
			compileError(
				"OutTargetType",
				["{nodes[x].text}", "{c.showTy(t)}", "{c.showTy(c.vars[v].ty)}"]
			)
		)
	c.typed(x, t)
	c.typed(a, tyInt(64, true))

# The struct declaration a callee names (`Point`, `geo.Point`, `Pair<i64, str>`), or none: a
# call of it makes one of its values.
fn constructedStruct(mut c Checker, callee NodeId):
	k = nodes[callee].kind
	name = nodes[callee].text.copy()
	if name == "" or not (name[0].isUpper() or name.startsWith("$Ty")):   # a type, or one the derived code names
		return none
	if k == nIdent and c.lookupVarQuiet(name): return none
	if k == nIdent:
		return c.lookupDecl(nStructDecl, "", name, nodes[callee].line, nodes[callee].col)
	if k == nField and nodes[nodes[callee].kids(kidIds)[0]].kind == nIdent and
		not c.lookupVarQuiet(nodes[nodes[callee].kids(kidIds)[0]].text):
		imp = c.findImportByAlias(c.curMod, nodes[nodes[callee].kids(kidIds)[0]].text)
		if imp is imp and c.findDeclInModule(nodes[imp].text, nStructDecl, name) != none:
			return lookupDecl(
				c,
				nStructDecl,
				nodes[nodes[callee].kids(kidIds)[0]].text,
				name,
				nodes[callee].line,
				nodes[callee].col
			)
	none

# m.applyPoint(p) of a Mat4 m and a Vec2 p made the call of the runtime's point of the plane moved
# (vectors.zap), a Vec2: whether e was. A Vec3 p calls the method.
fn planePointCall(mut c Checker, e NodeId):
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind != nField or nodes[callee].text != "applyPoint" or c.argCount(e) != 1:
		return false
	obj = nodes[callee].kids(kidIds)[0]
	if nodes[obj].kind == nIdent and not c.lookupVarQuiet(nodes[obj].text): return false
	if not c.isRuntimeType(c.derefIfRef(obj, c.checkExpr(obj, none)), "Mat4"): return false
	p = c.argAt(e, 0)
	if not c.isRuntimeType(c.derefIfRef(p, c.checkExpr(p, none)), "Vec2"): return false
	line = nodes[e].line
	col = nodes[e].col
	rt = newNode(nodes, kidIds, nIdent, line, col, text = "$rt")
	maker = newNode(nodes, kidIds, nField, line, col, text = "mat4ApplyPoint2", kids = [rt])
	nodes[e].setKids(kidIds, [maker, obj, p])
	true

# A language matrix made as a shader makes it: MatN(n * n numbers, column by column) is its
# array; MatN(c0, ..) takes n columns, MatN(k) has k on its diagonal, MatN(o) of another size
# keeps o's upper left corner (the rest the identity's). The array form stays a literal, the
# others are made a call of the runtime's maker (vectors.zap): whether e was.
fn matrixMaker(mut c Checker, e NodeId, d NodeId):
	written = nodes[d].text2(kidIds).copy()
	if nodes[d].mod(kidIds) != "rt" or written not in ["Mat2", "Mat3", "Mat4"]: return false
	n = i64.parse(written[3..4]) ?? 0
	args = nodes[e].kidsFrom(kidIds, 1).copy()
	if args.isEmpty or args.any(nodes[it].kind == nNamedArg): return false
	if args.len == n * n:
		madeKids = [
			nodes[e].kids(kidIds)[0],
			newNode(nodes, kidIds, nArray, nodes[e].line, nodes[e].col, kids = args)
		]
		nodes[e].setKids(kidIds, madeKids)
		return false
	maker = ""
	if args.len == n:
		maker = "mat{n}Columns"
	elif args.len == 1:
		t = derefIfRef(
			c,
			args[0],
			c.checkExpr(args[0], tyFloat(32) if c.isNumLit(args[0]) else none)
		)
		other = nodes[declOf(tys, t)] if c.tKind(t) == tStruct else nodes[d]
		if isSameType(tys, t, tyFloat(32)):
			maker = "mat{n}Diagonal"
		elif c.tKind(t) == tStruct and other.mod(kidIds) == "rt" and
			other.text2(kidIds) in ["Mat2", "Mat3", "Mat4"] and other.text2(kidIds) != written:
			maker = "mat{n}Of{other.text2(kidIds)}"
	if maker == "": return false
	rt = newNode(nodes, kidIds, nIdent, nodes[e].line, nodes[e].col, text = "$rt")
	madeKid = newNode(
		nodes,
		kidIds,
		nField,
		nodes[e].line,
		nodes[e].col,
		text = maker,
		kids = [rt]
	)
	nodes[e].setKid(kidIds, 0, madeKid)
	true

# Vec3(xs, at = 0), Vec2, Vec4 and Quat of a list of floats: the call e made the runtime's
# vec3Of(xs, at) (a vector of numbers is the struct's literal)
fn vectorMaker(mut c Checker, e NodeId, d NodeId):
	written = nodes[d].text2(kidIds).copy()
	if nodes[d].mod(kidIds) != "rt" or written not in ["Vec2", "Vec3", "Vec4", "Quat"]: return false
	args = nodes[e].kidsFrom(kidIds, 1).copy()
	if args.isEmpty or args.len > 2 or nodes[args[0]].kind not in [nIdent, nField, nIndex]:
		return false
	if args.len == 2 and nodes[args[1]].kind == nNamedArg and nodes[args[1]].text != "at":
		return false
	t = c.derefIfRef(args[0], c.checkExpr(args[0], none))
	if c.tKind(t) != tList or not isSameType(tys, innerOf(tys, t), tyFloat(32)): return false
	rt = newNode(nodes, kidIds, nIdent, nodes[e].line, nodes[e].col, text = "$rt")
	maker = "{written[..1].lower()}{written[1..]}Of"
	madeKid = newNode(
		nodes,
		kidIds,
		nField,
		nodes[e].line,
		nodes[e].col,
		text = maker,
		kids = [rt]
	)
	nodes[e].setKid(kidIds, 0, madeKid)
	true

# The call e of struct d's name made the struct literal it stands for: positional arguments
# `field = field` in a struct's literal, the value a local of the field's name: noted for zap fmt
# as the name alone, which fills that field wherever it stands
fn noteFieldFromName(mut c Checker, a NodeId):
	if not noting: return
	v = nodes[a].kids(kidIds)[0]
	if nodes[v].kind != nIdent or nodes[v].text != nodes[a].text or
		c.lookupVarNo(nameOf(nodes, v)) < 0:
		return
	src = c.file if c.curFile == "" else c.curFile
	text = sourceLineOf(src, nodes[a].line)
	at = nodes[a].col - 1
	cut = "{nodes[a].text} = {nodes[a].text}"
	if at < 0 or at + cut.len > text.len or text[at..at + cut.len] != cut: return
	c.canonNote(noteReplace, nodes[a].line, at + 1, nodes[a].text.len + 3, "")

# whether a value given by position is a local named like a field: it fills that field
fn fillsNamedField(mut c Checker, a NodeId, fields str[]):
	nodes[a].kind == nIdent and nodes[a].text in fields and c.lookupVarNo(nameOf(nodes, a)) >= 0

# give the fields in their order, named ones the field of that name (positional ones first).
# `Params(..base, lit = false)`: the fields not named are base's, which is evaluated once: a
# named place is read field by field (a local not used again gives its fields away, plain data
# copies), any other value is bound first by a match the compiler writes (the literal its arm).
# The literal notes (ival) where the fields from base begin, plus one.
fn asStructLiteral(mut c Checker, e NodeId, d NodeId):
	callee = nodes[e].kids(kidIds)[0]
	c.baseForm(e, d)
	names = []
	values = []
	named = false
	base NodeId? = none
	fields = nodes[d].kids(kidIds).map(nodes[it].text.copy())
	# a local named like a field fills that field wherever it stands; the other positional values
	# fill the fields left, in order
	claimed = nodes[e]
		.kidsFrom(kidIds, 1)
		.filter(c.fillsNamedField(it, fields))
		.map(nodes[it].text.copy())
	for i in 1..c.nodes[e].kids(c.kidIds).len:
		a = nodes[e].kids(kidIds)[i]
		if nodes[a].kind == nNamedArg and nodes[a].text == "..":
			if i != 1:
				c.errorAt(
					nodes[a].line,
					nodes[a].col,
					compileError("BaseFirst", ["{c.shownName(d)}"])
				)
				return false
			base = nodes[a].kids(kidIds)[0]
			named = true
			continue
		if nodes[a].kind == nNamedArg:
			named = true
			c.noteFieldFromName(a)
			names.push(nodes[a].text.copy())
			values.push(nodes[a].kids(kidIds)[0])
			continue
		if c.fillsNamedField(a, fields):
			if nodes[a].text in names:
				errorAt(
					c,
					nodes[a].line,
					nodes[a].col,
					compileError("FieldGivenTwice", ["{nodes[a].text}"])
				)
				return false
			names.push(nodes[a].text.copy())
			values.push(a)
			continue
		if named:
			msg = compileError("NamedAfterBase", []) if base != none
				else compileError("ValueAfterNamed", [])
			c.errorAt(nodes[a].line, nodes[a].col, msg)
			return false
		slot = fields.findIndex(it not in names and it not in claimed) ?? -1
		if slot < 0:
			errorAt(
				c,
				nodes[a].line,
				nodes[a].col,
				compileError("TooManyValues", ["{c.shownName(d)}", "{fields.len}", "{i}"])
			)
			return false
		names.push(fields[slot].copy())
		values.push(a)
	explicit = names.len
	temp = ""
	if base is base and not c.isNamedPlace(base):
		temp = "$base{e}"   # the value bound once, by the match below
	if base is base: c.fieldsFromBase(base, temp, fields, names, values)
	module = nodes[nodes[callee].kids(kidIds)[0]].text.copy() if nodes[callee].kind == nField
		else ""
	lit = e
	if temp != "":
		lit = newNode(nodes, kidIds, nStructLit, nodes[e].line, nodes[e].col)
	nodes[lit].kind = nStructLit
	nodes[lit].setText(nodes[callee].text.copy(), nodes[callee].name)
	nodes[lit].setText2(kidIds, module)
	nodes[lit].nodePart(kidIds).types = nodes[callee].types(kidIds).copy()
	nodes[lit].nodeMore(kidIds).names = names
	nodes[lit].setKids(kidIds, values)
	nodes[lit].ival = i32(explicit + 1 if base != none else 0)
	if temp != "" and base is base:
		pat = newNode(nodes, kidIds, nPattern, nodes[base].line, nodes[base].col, text = temp)
		nodes[pat].ival = patBind
		arm = newNode(nodes, kidIds, nArm, nodes[e].line, nodes[e].col, kids = [pat, lit])
		nodes[e].kind = nMatch
		nodes[e].setKids(kidIds, [base, arm])
		nodes[e].flags |= flagInternal
		nodes[e].nodePart(kidIds).types = []
		nodes[e].setText("")
	true

# the fields the literal does not name read from base (through temp, the name it is bound to, when
# not "")
fn fieldsFromBase(
	mut c Checker,
	base NodeId,
	temp str,
	fields str[],
	mut names str[],
	mut values NodeId[]
):
	for f in fields:
		if f in names: continue
		from = c.namedLike(temp, base) if temp != "" else c.cloneNamedPlace(base)
		part = newNode(
			nodes,
			kidIds,
			nField,
			nodes[base].line,
			nodes[base].col,
			text = f.copy(),
			kids = [from]
		)
		nodes[part].flags = flagFromBase
		values.push(part)
		names.push(f.copy())

# "argument 2 of f", or for a method made a call of its runtime function "argument 1 of m"
fn argumentOf(c Checker, e NodeId, i i64, fname str):
	if not nodes[e].hasFlag(flagMethod): return "argument {i + 1} of {fname}"
	m = nodes[nodes[e].kids(kidIds)[0]].names(kidIds)[0]
	if i == 0: return "the receiver of {m}"
	"argument {i} of {m}"

# A method of a built-in type the checker has no rule of its own for: the runtime function
# named after it, checked and compiled as a call to it with the receiver first. xs.reversed() is
# listReverse(xs), s.padLeft(4) would be strPadLeft(s, 4): a new method is one function in
# runtime/, written in Zap, with its bounds.
fn checkRuntimeMethod(mut c Checker, e NodeId, prefix str, shown str, expected TypeId?):
	line = nodes[e].line
	col = nodes[e].col
	m = c.calleeName(e)
	fd = c.findDeclInModule("rt", nFnDecl, prefix + capital(m))
	if fd is fd and (c.declIsPub(fd) or nodes[e].hasFlag(flagInternal)) and
		not nodes[fd].kids(kidIds).isEmpty:
		return c.callAsMethod(e, fd, m, expected)
	r = c.callReceiverFunction(
		e,
		c.receiverType(nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0]),
		expected
	)
	if r is r: return r
	c.errorAt(line, col, compileError("NoMethod", ["{m}", "{shown}"]))
	tyError

# The method call e (named m) made a call of the function fd, its receiver the first argument.
fn callAsMethod(mut c Checker, e NodeId, fd NodeId, m str, expected TypeId?) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	want = nodes[fd].kids(kidIds).len - 1
	defaulted = nodes[fd].kids(kidIds).count(not nodes[it].kids(kidIds).isEmpty)
	if c.argCount(e) > want or c.argCount(e) < want - defaulted:
		c.errorAt(line, col, compileError("ArgumentCount", ["{m}", "{want}", "{c.argCount(e)}"]))
		return tyError
	obj = c.calleeObj(e)
	if nodes[nodes[fd].kids(kidIds)[0]].ival == modeMut:
		c.requireMutRoot(obj, line, col, m)
	f = newNode(nodes, kidIds, nIdent, line, col)
	nodes[f].setText(nodes[fd].text.copy(), nodes[fd].name)   # the new name node keeps one, the declaration the other
	nodes[f].nodeMore(kidIds).names.push(m.copy())
	nodes[f].setOrigin(kidIds, nodes[e].kids(kidIds)[0])   # the method's callee, for undoing it
	nodes[e].setKid(kidIds, 0, f)
	nodes[e].flags |= flagMethod
	nodes[e].insertKid(kidIds, 1, obj)
	c.checkCallTo(e, fd, expected, 1)

# A method call made a call of its runtime function back to the method call: in a generic body,
# whose nodes every instance shares, the receiver's type (and so the method) is the instance's.
fn undoRuntimeMethod(mut c Checker, e NodeId):
	madeKid = c.undoneCallee(nodes[e].kids(kidIds)[0])
	nodes[e].setKid(kidIds, 0, madeKid)
	nodes[e].removeKid(kidIds, 1)
	nodes[e].flags &= ~flagMethod

# `T[]` or `{K: V}` written as a receiver (Point[].fromJson(text)): that type, else none
fn builtinGenericType(mut c Checker, obj NodeId) TypeId?:
	args = nodes[obj].types(kidIds).copy()
	name = nodes[obj].text
	if name == "List" and args.len == 1: return tyList(tys, c.resolveType(args[0]))
	if name == "Map" and args.len == 2:
		return tyMap(tys, c.resolveType(args[0]), c.resolveType(args[1]))
	none
