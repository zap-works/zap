# The checking of a call (checkExpr.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

fn checkCall(mut c Checker, e NodeId, expected TypeId?) TypeId:
	if nodes[e].hasFlag(flagMethod):
		c.undoRuntimeMethod(e)
	callee = nodes[e].kids(kidIds)[0]
	line = nodes[e].line
	col = nodes[e].col
	nodes[e].flags &= ~flagClosure

	special = c.checkCallSpecialForm(e, callee, line, col, expected)
	if special is special: return special

	# qualified references: mod.fn(...), mod.Enum.Variant(...)
	if c.normalizeQualified(callee) < 0: return tyError
	if nodes[callee].kind == nField and c.normalizeQualified(nodes[callee].kids(kidIds)[0]) < 0:
		return tyError
	if nodes[callee].kind == nField and not nodes[e].hasFlag(flagParallelSort):
		par = c.parallelStep(e)
		if par is par: return c.checkParallelPipeline(e, par, expected)
		if c.isParallelStep(e) and c.parallelAlone(e): return tyError
	ck = nodes[callee].kind
	# a call the compiler wrote reaches the runtime's private functions, by their global name
	if ck == nIdent and nodes[callee].hasFlag(flagInternal):
		rd = c.findDeclInModule("rt", nFnDecl, nodes[callee].text, nameOf(nodes, callee))
		if rd is rd and not c.declIsPub(rd):
			nodes[callee].setText(nodes[rd].text.copy(), nodes[rd].name)
	# the name as written, of its own: checking the call changes c and may rename the callee
	# (to the declaration's qualified name) while the name is still compared and reported
	cname = nodes[callee].text.copy()
	cnameNumber = nameOf(nodes, callee)

	bare = c.checkCallBareName(e, callee, ck, cname, line, col, expected)
	if bare is bare: return bare
	# any other expression of type: xs[i](x), make()(x), (x => x)(1)
	if ck != nIdent and ck != nField:
		ft = c.checkExpr(callee, none)
		if c.tKind(ft) == tFn: return c.checkClosureCall(e, ft)
		if c.tKind(ft) != tError:
			c.errorAt(line, col, compileError("NotCallable", ["{c.showTy(ft)}"]))
		return tyError
	intrinsic = c.checkCallIntrinsic(e, ck, cname, line, col, expected)
	if intrinsic is intrinsic: return intrinsic
	# the function a bare name finds, looked up once: nothing below adds a declaration before
	# the call is checked
	fnNamed NodeId? = c.lookupDecl(
		nFnDecl,
		nodes[callee].text2() if nodes[callee].text2() == globalAlias else "",
		cname,
		nodes[callee].line,
		nodes[callee].col,
		cnameNumber
	) if ck ==
		nIdent
		else none
	builtin = c.checkCallBuiltin(e, callee, ck, cname, fnNamed, expected)
	if builtin is builtin: return builtin

	# print builtins
	if ck == nIdent and isPrintBuiltin(cname): return c.checkPrintCall(e, cname)

	wrapped = c.checkCallWrap(e, callee, ck, cname, line, col, expected)
	if wrapped is wrapped: return wrapped
	fromBits = c.checkCallFromBits(e, callee, ck, cname, line, col)
	if fromBits is fromBits: return fromBits
	typeOwn = c.checkCallTypeOwn(e, callee, ck, cname, line, col, expected)
	if typeOwn is typeOwn: return typeOwn
	decoded = c.checkCallDecode(e, callee, ck, cname, line, col)
	if decoded is decoded: return decoded
	fromValue = c.checkCallFromValue(e, callee, ck, cname, line, col)
	if fromValue is fromValue: return fromValue
	variant = c.checkCallVariant(e, callee, ck, cname, expected)
	if variant is variant: return variant

	boxed = c.checkCallBoxShared(e, ck, cname, expected)
	if boxed is boxed: return boxed
	strMade = c.checkCallStr(e, ck, cname, line, col, expected)
	if strMade is strMade: return strMade
	if ck == nIdent and cname == "bindExtern": return c.checkBindExtern(e)
	if ck == nIdent and cname == "bindExterns": return c.checkBindExterns(e)
	boxMade = c.checkCallBox(e, ck, cname, line, col)
	if boxMade is boxMade: return boxMade
	# top-level function call
	if ck == nIdent: return c.checkCallTopLevel(e, callee, move cname, fnNamed, line, col, expected)

	ranged = c.checkCallRange(e, callee, cname, line, col, expected)
	if ranged is ranged: return ranged

	c.checkCallOnReceiver(e, callee, cname, line, col, expected)

fn checkCallSpecialForm(
	mut c Checker,
	e NodeId,
	callee NodeId,
	line i64,
	col i64,
	expected TypeId?
) TypeId?:
	if nodes[callee].kind == nField and readsAsField(nodes[callee].text) and
		not nodes[callee].hasFlag(flagSize):
		what = "a size" if nodes[callee].text in sizeWords else "a list's end"
		c.errorAt(line, col, compileError("SizeIsField", ["{what}", "{nodes[callee].text}"]))
		c.checkArgsAlone(e)
		return tyError
	if nodes[callee].kind == nIdent and nodes[callee].text == argsWord and
		not c.lookupVarQuiet(argsWord) and
		c.lookupDecl(nFnDecl, "", argsWord, line, col) == none:
		c.errorAt(line, col, compileError("ArgsIsValue", []))
		c.checkArgsAlone(e)
		return tyError
	if nodes[callee].kind == nField and nodes[callee].hasFlag(flagSafe): return c.checkSafeCall(e)
	if c.isGradCall(e): return c.checkGradRef(e)
	if c.planePointCall(e): return c.checkExpr(e, expected)
	if c.rangeTypeNamed(callee) is ranged: return c.checkRangeConversion(e, ranged)
	defined = c.definedTypeNamed(callee)
	if defined is defined and c.bitsDecl(defined) is bd and c.bitsLiteral(e, bd, defined):
		return c.checkDefinedConversion(e, defined)
	if defined is defined and c.isDefinedConversion(e, defined):
		return c.checkDefinedConversion(e, defined)
	if nodes[callee].kind == nField and nodes[callee].hasFlag(flagDotVariant):
		# `.Circle(2.0)`: a variant of the enum the place expects
		if c.dotEnum(callee, e, expected) is enumd:
			return c.checkVariantArgs(e, enumd, nodes[callee].text.copy())
		for i in 0..argCount(c, e):
			c.checkExpr(c.argAt(e, i), none)
		return tyError
	if nodes[callee].kind == nIdent and nodes[callee].text == "Table" and
		not c.lookupVarQuiet("Table"):
		return c.checkNewTable(e, expected)
	# a struct made by its type's name: Point(x, y), Point(x = 1, y = 2), geo.Point(1, 2)
	sd = c.constructedStruct(callee)
	if sd is sd and (c.matrixMaker(e, sd) or c.vectorMaker(e, sd) or c.gridMaker(e, sd, expected)):
		made = c.checkExpr(e, expected)
		if defined is defined and isSameType(tys, made, tys[defined].under):
			return c.typed(e, defined)
		return made
	if sd is sd and defined == none:
		bt = c.definedOverStruct(e, sd)
		if bt is bt:
			nodes[e].flags |= flagRangeConversion   # Color(paint): the value read back as its base
			return c.typed(e, bt)
	if sd is sd:
		if not c.asStructLiteral(e, sd): return tyError
		return c.checkExpr(e, expected)
	none

fn checkCallBareName(
	mut c Checker,
	e NodeId,
	callee NodeId,
	ck i64,
	cname str,
	line i64,
	col i64,
	expected TypeId?
) TypeId?:
	# a local variable of fn type shadows functions and builtins of the same name
	if ck == nIdent:
		v = c.lookupVar(cname)
		if v >= 0:
			c.vars[v].used = true
			vt = c.vars[v].ty
			nodes[callee].ty = vt
			if c.tKind(vt) == tFn: return c.checkClosureCall(e, vt)
			if c.tKind(vt) != tError:
				c.errorAt(line, col, compileError("NotAFunction", ["{cname}", "{c.showTy(vt)}"]))
			return tyError
		if c.implType is impl and c.findMethod(tys[impl].name, cname) != none:
			# inside an impl a bare call may mean a sibling method or a top-level or built-in
			# function: the reader cannot tell which, so neither is picked
			fd = c.lookupDecl(nFnDecl, "", cname, nodes[callee].line, nodes[callee].col)
			if fd != none or builtinAt(cname) >= 0 or isPrintBuiltin(cname) or cname == "str":
				c.errorAt(line, col, c.ambiguousCallMessage(cname, fd))
				return tyError
		if isSimdName(cname) and c.findFunc(cname) == none: return c.checkSimdCtor(e, expected)
		if isVecLitName(cname) and c.findFunc(cname) == none and
			nodes[callee].hasFlag(flagInternal):
			return c.checkVecLiteral(e, cname)
	none

fn checkCallIntrinsic(
	mut c Checker,
	e NodeId,
	ck i64,
	cname str,
	line i64,
	col i64,
	expected TypeId?
) TypeId?:
	if ck == nIdent and cname.startsWith("__"):
		idx = signatureAt(intrinsicSignatures, cname)
		if idx < 0:
			c.errorAt(line, col, compileError("UnknownIntrinsic", ["{cname}"]))
			return tyError
		if c.curMod < 0 or c.modules[c.curMod].id != "rt":
			c.errorAt(line, col, compileError("RuntimeIntrinsic", ["{cname}"]))
			return tyError
		if c.rawIntrinsicType(e, cname, expected) is special: return c.typed(e, special)
		sig = intrinsicSignatures[idx]
		return c.checkBuiltinCall(e, cname, sig.arity, sig.params, sig.result)
	none

fn checkCallBuiltin(
	mut c Checker,
	e NodeId,
	callee NodeId,
	ck i64,
	cname str,
	fnNamed NodeId?,
	expected TypeId?
) TypeId?:
	if ck == nIdent and cname == "random" and c.argCount(e) == 1 and fnNamed == none:
		return c.checkRandomDraw(e, none, expected)
	if ck == nField and cname == "next" and c.argCount(e) == 1 and
		nodes[c.argAt(e, 0)].kind == nRange and c.isRuntimeType(
			c.derefIfRef(nodes[callee].kids(kidIds)[0], c.checkExpr(nodes[callee].kids(kidIds)[0], none)),
			"Random"
		):
		return c.checkRandomDraw(e, nodes[callee].kids(kidIds)[0], expected)
	if ck == nIdent and cname == "arg" and fnNamed == none: return c.checkArg(e, expected)
	if ck == nIdent and (cname == "zeros" or cname == "fill") and fnNamed == none:
		return c.checkZerosFill(e, cname, expected)
	if ck == nIdent and cname == "exit" and c.argCount(e) == 2 and fnNamed == none:
		# exit(code, message): the line to stderr first, then the end
		nodes[callee].setText("exitSaying")
		nodes[callee].flags |= flagInternal
		return c.checkCall(e, expected)
	if ck == nIdent and fnNamed == none:
		idx = builtinAt(cname)
		if idx >= 0:
			sig = builtinSignatures[idx]
			return c.checkBuiltinCall(e, cname, sig.arity, sig.params, sig.result)
	none

fn checkCallWrap(
	mut c Checker,
	e NodeId,
	callee NodeId,
	ck i64,
	cname str,
	line i64,
	col i64,
	expected TypeId?
) TypeId?:
	# u8.wrap(x): the integer x wrapped to the type, where the wrap is meant (a hash, a checksum):
	# the conversion x.toU8() that never stops the program
	if ck == nField and cname == "wrap":
		obj = nodes[callee].kids(kidIds)[0]
		m = conversionMethod(nodes[obj].text) if nodes[obj].kind == nIdent and
			c.lookupVarNo(nameOf(nodes, obj)) < 0
			else ""
		if m in intConversions:
			if not c.expectArgs(e, "{nodes[obj].text}.wrap", 1): return tyError
			arg = nodes[e].kids(kidIds)[1]
			if c.tKind(c.checkExpr(arg, none)) != tInt:
				errorAt(
					c,
					line,
					col,
					compileError(
						"WrapNeedsInteger",
						["{nodes[obj].text}", "{c.showTy(typeOf(nodes, arg))}"]
					)
				)
				return tyError
			madeKids = [newNode(nodes, kidIds, nField, line, col, text = m, kids = [arg])]
			nodes[e].setKids(kidIds, madeKids)
			nodes[e].flags |= flagWrap
			return c.checkCall(e, expected)
	none

fn checkCallFromBits(
	mut c Checker,
	e NodeId,
	callee NodeId,
	ck i64,
	cname str,
	line i64,
	col i64
) TypeId?:
	# f32.fromBits(u32), f64.fromBits(u64): the float whose bits these are (the reverse of bits())
	if ck == nField and cname == "fromBits":
		obj = nodes[callee].kids(kidIds)[0]
		named = primTypes.find(.name == nodes[obj].text)?.id
		if nodes[obj].kind == nIdent and c.tKind(named) == tFloat and named is floatT and
			c.lookupVarNo(nameOf(nodes, obj)) < 0:
			width = tys[floatT].bits
			if not c.expectArgs(e, "{nodes[obj].text}.fromBits", 1): return tyError
			bitsT = tyInt(width, false)
			at = c.checkExpr(c.argAt(e, 0), bitsT)
			if c.tKind(at) != tError and not isSameType(tys, at, bitsT):
				c.errorAt(
					line,
					col,
					compileError("FromBitsType", ["{width}", "{c.showTy(at)}"])
				)
			return c.typed(e, floatT)
		if nodes[obj].kind == nIdent and named == none and c.lookupVarNo(nameOf(nodes, obj)) < 0:
			declared, made = c.namedTypeOf(obj)
			if declared != none and made == none: return tyError
			if declared is declared and made is made and nodes[made].kind == nStructDecl:
				nodes[obj].setText(nodes[declared].text.copy(), nodes[declared].name)   # the type's qualified name
				t = tyOfDecl(tys, nodes, made)
				if not c.expectArgs(e, "{nodes[obj].text}.fromBits", 1): return tyError
				bitsT = c.packedType(t, line, col) ?? return tyError
				at = c.checkExpr(c.argAt(e, 0), bitsT)
				if c.tKind(at) != tError and not isAssignable(tys, at, bitsT):
					c.errorAt(
						line,
						col,
						compileError(
							"FromBitsWord",
							["{c.showTy(t)}", "{c.showTy(bitsT)}", "{c.showTy(at)}"]
						)
					)
				madeKid = c.coerceTo(c.argAt(e, 0), bitsT)
				nodes[e].setKid(kidIds, 1, madeKid)
				c.noteDerive(t, deriveUnbits)
				return c.typed(e, t)
	none

fn checkCallTypeOwn(
	mut c Checker,
	e NodeId,
	callee NodeId,
	ck i64,
	cname str,
	line i64,
	col i64,
	expected TypeId?
) TypeId?:
	# str.fromCode(cp), i64.parse(s), Process.start(cmd): a function of a type the language or the
	# runtime declares, the runtime's function named after the type (strFromCode, i64Parse,
	# processStart); with a list as its first argument, the one whose name ends in List when there
	# is one (Process.output(words) is processOutputList)
	if ck == nField:
		fd = c.typeOwnFunction(nodes[callee].kids(kidIds)[0], cname)
		if fd is plain:
			fd = c.listVariant(e, plain) ?? plain
		if fd is fd:
			typeName = nodes[nodes[callee].kids(kidIds)[0]].text.copy()
			f = newNode(nodes, kidIds, nIdent, line, col, text = nodes[fd].text.copy())
			if nodes[fd].text == "rt__intParse":
				nodes[f].nodePart().types = [
					newNode(nodes, kidIds, nTyName, line, col, text = typeName)
				]
			nodes[e].setKid(kidIds, 0, f)
			return c.checkCall(e, expected)
		obj = nodes[callee].kids(kidIds)[0]
		if nodes[obj].kind == nIdent and nodes[obj].text == "str" and not c.lookupVarQuiet("str"):
			c.errorAt(
				line,
				col,
				compileError("NoTypeFunction", ["str", cname.copy()])
			)
			return c.typed(e, tyError)
	none

fn checkCallDecode(
	mut c Checker,
	e NodeId,
	callee NodeId,
	ck i64,
	cname str,
	line i64,
	col i64
) TypeId?:
	# Type.fromJson(text) -> Type?
	if ck == nField:
		obj = nodes[callee].kids(kidIds)[0]
		if nodes[obj].kind == nIdent and c.lookupVarNo(nameOf(nodes, obj)) < 0 and
			(cname in ["fromJson", "fromBytes", "fromBytesAt", "fromCsv"]):
			t = c.builtinGenericType(obj)
			if t == none:
				named, made = c.namedTypeOf(obj)
				if named != none and made == none: return tyError
				if named is named and made is made:
					nodes[obj].setText(nodes[named].text.copy(), nodes[named].name)   # the type's qualified name
					t = c.aliasedType(made) if nodes[made].hasFlag(flagTypeAlias)
						else tyOfDecl(tys, nodes, made)
			bytesT = tyList(tys, tyInt(8, false))
			given TypeId? = none
			if t is t and cname == "fromBytes" and c.argCount(e) == 1:
				arg = c.argAt(e, 0)
				given = c.checkExpr(arg, bytesT)
				if c.isReader(given):
					# T.fromBytes(r): one value read with a Reader, which it advances
					if not c.isSerializable(t, true):
						c.errorAt(line, col, compileError("CannotDecode", ["{c.showTy(t)}"]))
					c.requireMutRoot(arg, line, col, "fromBytes")
					c.noteDerive(t, deriveRead)
					return c.typed(e, t)
			if t is t and cname == "fromBytesAt": return c.checkFromBytesAt(e, t, line, col)
			if t is t and cname == "fromCsv": return c.checkCsvRead(e, t)
			if t == none and cname == "fromCsv":
				c.errorAt(line, col, compileError("CsvRowType", [nodes[obj].text.copy()]))
				return tyError
			if t is t:
				if not c.isSerializable(t, cname == "fromBytes"):
					errorAt(
						c,
						line,
						col,
						compileError("CannotDecode", ["{c.showTy(t)}"])
					)
				if cname == "fromBytes":
					if c.argCount(e) != 1:
						c.errorAt(line, col, compileError("FromBytesArity", []))
					else:
						at = c.derefIfRef(c.argAt(e, 0), given ?? tyError)   # a borrowed list is read as it is
						if c.tKind(at) != tError and not isSameType(tys, at, bytesT):
							errorAt(
								c,
								line,
								col,
								compileError("FromBytesType", ["{c.showTy(at)}"])
							)
				elif c.argCount(e) != 1:
					c.errorAt(line, col, compileError("FromJsonArity", []))
				else:
					c.checkStrArg(e, 0, "fromJson expects a str")
				if cname == "fromBytes":
					c.noteDerive(t, deriveUnbin)
				else:
					c.noteDerive(t, deriveUnjson)
				res = tyOption(tys, t)
				return c.typed(e, res)
	none

fn checkCallFromValue(
	mut c Checker,
	e NodeId,
	callee NodeId,
	ck i64,
	cname str,
	line i64,
	col i64
) TypeId?:
	# Enum.from(n) -> Enum?: the variant whose integer is n (Add = 1)
	if ck != nField or cname != "from": return none
	named = c.enumNamedBy(nodes[callee].kids(kidIds)[0])
	if named is NamedEnum(enumd) and c.enumHasValues(enumd):
		t = tyOfDecl(tys, nodes, enumd)
		if not c.expectArgs(e, "{c.showTy(t)}.from", 1): return tyError
		i64T = tyInt(64, true)
		at = c.checkExpr(c.argAt(e, 0), i64T)
		if c.tKind(at) != tError and not isAssignable(tys, at, i64T):
			c.errorAt(
				line,
				col,
				compileError("ArgumentType", ["{c.showTy(t)}.from", "i64", "{c.showTy(at)}", ""])
			)
		madeKid = c.coerceTo(c.argAt(e, 0), i64T)
		nodes[e].setKid(kidIds, 1, madeKid)
		c.noteDerive(t, deriveFromValue)
		return c.typed(e, tyOption(tys, t))
	none

# T.fromBytesAt(bytes, at): one value read from the bytes at a position (T.fromBytes(r)'s layout), none
# when they end first
fn checkFromBytesAt(mut c Checker, e NodeId, t TypeId, line i64, col i64) TypeId:
	if c.argCount(e) != 2:
		c.errorAt(line, col, compileError("FromBytesArity", []))
		return tyError
	if not c.isSerializable(t, true):
		c.errorAt(line, col, compileError("CannotDecode", ["{c.showTy(t)}"]))
	bytesT = tyList(tys, tyInt(8, false))
	given = c.checkExpr(c.argAt(e, 0), bytesT)
	listT = c.derefIfRef(c.argAt(e, 0), given)
	if c.tKind(listT) != tError and not isSameType(tys, listT, bytesT):
		c.errorAt(line, col, compileError("FromBytesType", ["{c.showTy(listT)}"]))
	at = c.checkExpr(c.argAt(e, 1), tyInt(64, true))
	if c.tKind(at) != tInt and c.tKind(at) != tError:
		c.errorAt(line, col, compileError("FromBytesAtPosition", ["{c.showTy(at)}"]))
	c.noteDerive(t, deriveRead | deriveReadAt)
	c.typed(e, tyOption(tys, t))

fn checkCallVariant(
	mut c Checker,
	e NodeId,
	callee NodeId,
	ck i64,
	cname str,
	expected TypeId?
) TypeId?:
	# variant construction: EnumType.Variant(args)
	if ck == nField:
		named = c.enumNamedBy(nodes[callee].kids(kidIds)[0])
		if named is EnumUnmade: return tyError
		if named is NamedEnum(enumd):
			c.qualifiedVariant(callee, e, enumd, expected)
			return c.checkVariantArgs(e, enumd, cname)
	if ck == nField:
		r = c.checkTypeFunctionCall(e, expected)
		if r is r: return r
	none

fn checkCallBoxShared(mut c Checker, e NodeId, ck i64, cname str, expected TypeId?) TypeId?:
	# Box(value): the value moves to a block of its own on the heap
	if ck == nIdent and cname == "Box" and nodes[e].hasFlag(flagShared):
		# a literal of a shared type, rewritten by the checker (see shareLiteral)
		lit = c.argAt(e, 0)
		want = expected
		if c.tKind(want) == tBox:
			want = innerOf(tys, want)
		st = c.checkStructLit(lit, want)
		nodes[lit].ty = st
		if c.tKind(st) == tError: return tyError
		res = tyShared(tys, st)
		return c.typed(e, res)
	none

fn checkCallStr(
	mut c Checker,
	e NodeId,
	ck i64,
	cname str,
	line i64,
	col i64,
	expected TypeId?
) TypeId?:
	if ck == nIdent and cname == "str" and not c.lookupVarQuiet("str"):
		# str(move bytes): the bytes of a u8[] become a str without a copy, the list's
		# place left empty (the intoStr the backend knows); str(bytes) of a place or a lent
		# list copies them
		if c.argCount(e) != 1:
			c.errorAt(line, col, compileError("StrOneValue", []))
			return c.typed(e, tyError)
		arg = c.argAt(e, 0)
		ak = nodes[arg].kind
		if not (ak == nUnary and nodes[arg].ival == unMove):
			written = cloneTree(nodes, kidIds, arg)
			raw = c.checkExpr(arg, none)
			at = c.derefIfRef(arg, raw)
			if c.tKind(at) == tError: return c.typed(e, tyError)
			if c.tKind(at) == tList and isSameType(tys, tys[at].inner, tyInt(8, false)) and
				(c.tKind(raw) == tRef or ak in [nIdent, nField, nIndex, nDeref]):
				copier = newNode(nodes, kidIds, nIdent, line, col, text = "strFromU8")
				nodes[copier].flags = flagInternal
				nodes[e].setKids(kidIds, [copier, written])
				nodes[e].flags |= flagInternal
				return c.checkRewrittenStr(e, expected)
			if not (c.tKind(at) == tList and isSameType(tys, tys[at].inner, tyInt(8, false))):
				# str(x): the text of a value, as "{x}" writes it
				shown = shownValue(nodes, kidIds, arg)
				nodes[e].kind = nInterp
				nodes[e].setKids(kidIds, nodes[shown].kids(kidIds).copy())
				nodes[e].nodeMore().names = []
				nodes[e].flags = 0
				return c.checkRewrittenStr(e, expected)
		if ak != nUnary and ak != nIdent and ak != nField and ak != nIndex and ak != nDeref:
			# a list made here (a call's, a copy): nobody else holds it, so its bytes move without
			# a word (the runtime's strBuildEnd takes the list as its own)
			builder = newNode(nodes, kidIds, nIdent, line, col, text = "strBuildEnd")
			nodes[builder].flags = flagInternal
			nodes[e].setKids(kidIds, [builder, arg])
			nodes[e].flags |= flagInternal
			return c.checkRewrittenStr(e, expected)
		if ak != nUnary or nodes[arg].ival != unMove:
			c.errorAt(line, col, compileError("StrOneValue", []))
			return c.typed(e, tyError)
		bytes = nodes[arg].kids(kidIds)[0]
		into = newNode(nodes, kidIds, nField, line, col, text = "intoStr", kids = [bytes])
		nodes[e].setKids(kidIds, [into])
		nodes[e].nodeMore().names = []
		nodes[e].flags |= flagInternal
		return c.checkExpr(e, expected)
	none

# e, str(x) rewritten to the call that builds it, checked again: the argument was checked as written
# (and its notes for zap fmt made), so the types this check gives it, a u8[] for the call, are no
# note: [u8(27)] stays a list of bytes
fn checkRewrittenStr(mut c Checker, e NodeId, expected TypeId?):
	was = noting
	noting = false
	t = c.checkExpr(e, expected)
	noting = was
	t

fn checkCallBox(mut c Checker, e NodeId, ck i64, cname str, line i64, col i64) TypeId?:
	if ck == nIdent and cname == "Box":
		if c.argCount(e) != 1:
			c.errorAt(line, col, compileError("BoxArity", []))
			return tyError
		at = c.checkExpr(c.argAt(e, 0), none)
		c.keepConversion(c.argAt(e, 0))   # the box's type comes from it
		c.rejectRef(at, line, col, "a boxed value")
		held = c.heldType(at)
		if held != at:
			c.setArg(e, 0, c.coerceTo(c.argAt(e, 0), held))
		res = tyBox(tys, held)
		return c.typed(e, res)
	none

fn checkCallTopLevel(
	mut c Checker,
	e NodeId,
	callee NodeId,
	move cname str,
	fnNamed NodeId?,
	line i64,
	col i64,
	expected TypeId?
):
	fd = fnNamed
	if fd is fd:
		nodes[callee].setText(nodes[fd].text.copy(), nodes[fd].name)   # the callee names the declaration
	if fd is fd and c.implType is impl and c.takesFirst(fd, impl) and
		c.argCount(e) < nodes[fd].kids(kidIds).count(nodes[it].kids(kidIds).isEmpty):
		# a method's bare call to a function taking its type first, short of that argument,
		# passes self
		madeKid = newNode(nodes, kidIds, nIdent, line, col, text = "self")
		nodes[e].insertKid(kidIds, 1, madeKid)
	if fd == none and c.implType is impl and c.findMethod(tys[impl].name, cname) != none:
		# bare call to a sibling method inside an impl: rewrite to this.method(args)
		recv = newNode(nodes, kidIds, nIdent, nodes[callee].line, nodes[callee].col, text = "self")
		f = newNode(nodes, kidIds, nField, nodes[callee].line, nodes[callee].col)
		nodes[f].pushKid(kidIds, recv)
		nodes[f].setText(cname)
		nodes[e].setKid(kidIds, 0, f)
		return c.checkCall(e, expected)
	if fd == none and c.gpuCode and (cname == "discard" or cname == "barrier"):
		c.expectArgs(e, cname, 0)
		return c.typed(e, tyUnit)   # the pixel is not written; the group's lanes wait
	called = fd ?? return c.unknownFunction(cname, line, col)
	if nodes[called].hasFlag(flagGpu) and not c.gpuCode:
		errorAt(
			c,
			line,
			col,
			compileError("GpuFunction", ["{cname}"])
		)
		return tyError
	if c.rowCall(e, called): return c.checkCall(e, expected)
	if not nodes[callee].hasFlag(flagInternal) and not c.inDerived() and c.typeForm(called) is form:
		c.errorAt(line, col, compileError("TypeFormCall", ["{nodes[called].text2()}", "{form}"]))
	res = c.checkCallTo(e, called, expected, 0)
	c.noteReceiverCall(e, called)
	res

fn checkCallRange(
	mut c Checker,
	e NodeId,
	callee NodeId,
	cname str,
	line i64,
	col i64,
	expected TypeId?
) TypeId?:
	# a pipeline over a range: (lo..hi).map(f), (lo..hi).by(s).sum()
	rng = c.rangeReceiver(callee)
	if rng is rng:
		rt = c.heldType(c.checkRangeBounds(rng))
		if c.tKind(rt) == tError: return tyError
		c.mapExpected = innerOf(tys, expected) if c.tKind(expected) == tList else none
		res = c.checkPipeline(e, cname, rt, true)
		c.mapExpected = none
		return c.typed(
			e,
			res ?? c.errorTyped(line, col, compileError("RangeLacksMethod", ["{cname}"]))
		)
	none

fn checkCallOnReceiver(
	mut c Checker,
	e NodeId,
	callee NodeId,
	cname str,
	line i64,
	col i64,
	expected TypeId?
) TypeId:
	# built-in methods on lists, maps, numbers and strings
	obj = nodes[callee].kids(kidIds)[0]
	if c.tKind(expected) == tArray and expected is arrayT and cname == "repeat" and
		nodes[callee].hasFlag(flagInternal) and nodes[obj].kind == nArray and
		nodes[obj].kids(kidIds).len == 1 and c.argCount(e) == 1:
		return c.checkFixedRepeat(e, arrayT)
	recvWant TypeId? = none
	if nodes[obj].kind == nArray and c.tKind(expected) == tList and
		cname in ["repeat", "reverse", "reversed", "copy", "sort", "sorted", "filter"]:
		recvWant = expected   # zeros(n) where a u8[] is expected
	if c.rowMethodCall(e, obj, cname): return c.checkCall(e, expected)
	c.seqOk = obj
	written = c.checkExpr(obj, recvWant)
	if (cname == "copy" or (cname == "take" and nodes[e].hasFlag(flagInternal))) and
		c.tKind(written) == tBox and c.argCount(e) == 0:
		# the box itself, not what it holds: move leaves the place empty, copy() is a deep
		# copy of a Box and one more owner of a shared value
		if cname == "take":
			if c.lvalueRoot(obj) < 0:
				c.errorAt(line, col, compileError("TakeNeedsPlace", []))
			c.requireMutRoot(obj, line, col, "take")
		return c.typed(e, written)
	if cname == "copy" and c.tKind(written) == tRef and c.argCount(e) == 0 and
		c.subst.types.any(isSameType(tys, it, written)):
		# in an instance whose T is a reference, a copy of a T is a T: the reference itself
		return c.typed(e, written)
	peek = c.derefIfRef(obj, written)
	pk = c.tKind(peek)
	if isDefined(tys, peek) and cname != "copy" and cname != "take" and
		conversionMethod(conversionType(cname)) != cname:
		r = c.callReceiverFunction(e, peek, expected)   # a function of its own
		if r is r: return r
		nodes[obj].flags |= flagBaseView   # else its base's, giving the base
		return c.checkCall(e, expected)
	onValue = c.checkCallValueMethod(e, obj, peek, pk, cname, line, col, expected)
	if onValue is onValue: return onValue
	encoded = c.checkCallEncode(e, peek, pk, cname, line, col)
	if encoded is encoded: return encoded
	byKind = c.checkCallKindMethod(e, peek, pk, cname, line, col, expected)
	if byKind is byKind: return byKind

	c.checkCallMethod(e, callee, peek, pk, cname, line, col, expected)

fn checkCallValueMethod(
	mut c Checker,
	e NodeId,
	obj NodeId,
	peek TypeId,
	pk i64,
	cname str,
	line i64,
	col i64,
	expected TypeId?
) TypeId?:
	if pk == tSeq: return c.typed(e, c.checkSeqStep(e, cname, innerOf(tys, peek)))
	if c.isTable(peek): return c.checkTableMethod(e, peek, expected)
	if c.sizeField(e, peek): return c.checkField(e, expected)
	if not c.boundGivesMethod(peek, cname, line, col):
		c.checkArgsAlone(e)
		return tyError
	bm = c.boundMethodOf(c.standInIndex(peek), cname) if c.standInIndex(peek) >= 0 else none
	if bm is bm:
		nodes[e].flags |= flagBoundCall
		return c.checkMethodCall(e, bm, none)   # the bound's signature
	if nodes[e].hasFlag(flagBoundCall):
		r = c.checkBoundFunctionCall(e, peek, expected)
		if r is r: return r
	if cname == "copy" and pk != tError and
		not ((pk == tStruct or pk == tEnum) and c.findMethod(tys[peek].name, "copy") != none):
		if c.argCount(e) != 0:
			c.errorAt(line, col, compileError("CopyArity", []))
		if c.holdsDrop(peek):
			c.errorAt(line, col, compileError("DropTypeNotCopied", ["{c.showTy(peek)}"]))
		elif c.argCount(e) == 0:
			c.noteCopyDropped(e)
		return c.typed(e, c.derefType(peek) if c.isOptionOfRef(peek) else peek)   # (an optional reference: its target's optional)
	if cname == "intoStr" and pk == tList and isSameType(tys, tys[peek].inner, tyInt(8, false)) and
		nodes[e].hasFlag(flagInternal):
		# the bytes become a str without a copy: they move out of their place, which becomes []
		if c.argCount(e) != 0:
			c.errorAt(line, col, compileError("IntoStrArity", []))
		if c.lvalueRoot(obj) < 0:
			errorAt(
				c,
				line,
				col,
				compileError("IntoStrNeedsPlace", [])
			)
		c.requireMutRoot(obj, line, col, "intoStr")
		return c.typed(e, tyStr)
	if cname == "take" and pk != tError and pk != tUnit and pk != tFn and c.isMoveCall(e):
		# moves the value out of its place and leaves the empty value behind ("", [], none, a
		# struct of empty fields: all zero bytes); written `move place`
		if c.argCount(e) != 0:
			c.errorAt(line, col, compileError("TakeArity", []))
		if c.lvalueRoot(obj) < 0:
			c.errorAt(line, col, compileError("MoveNeedsPlace", []))
		if not nodes[e].hasFlag(flagTaken):
			c.requireMutRoot(obj, line, col, "move")
		return c.typed(e, peek)
	none

# whether the call e of a method `take` is `move place`, which the checker writes so (a type's own
# `take` is called as any method)
fn isMoveCall(c Checker, e NodeId):
	nodes[e].hasFlag(flagInternal) or nodes[e].hasFlag(flagTaken)

fn checkCallEncode(
	mut c Checker,
	e NodeId,
	peek TypeId,
	pk i64,
	cname str,
	line i64,
	col i64
) TypeId?:
	# stream.print(value): any printable value, formatted by the compiler
	if cname == "print" and pk == tStruct and nodes[declOf(tys, peek)].mod() == "rt" and
		nodes[declOf(tys, peek)].text2() == "Stream":
		return c.checkPrintCall(e, "print")
	if cname == "value" and pk == tEnum and c.enumHasValues(declOf(tys, peek)) and
		c.findMethod(tys[peek].name, cname) == none:
		if c.argCount(e) != 0:
			c.errorAt(line, col, compileError("NoArguments", ["{cname}"]))
		c.noteDerive(peek, deriveValue)
		return c.typed(e, tyInt(64, true))
	if cname == "toBits" and pk == tStruct and c.findMethod(tys[peek].name, cname) == none:
		if c.argCount(e) != 0:
			c.errorAt(line, col, compileError("NoArguments", ["{cname}"]))
		bitsT = c.packedType(peek, line, col) ?? return tyError
		c.noteDerive(peek, deriveBits)
		return c.typed(e, bitsT)
	if cname == "toCsv" and pk == tList: return c.checkCsvWrite(e, peek)
	if (cname == "toJson" or cname == "toBytes") and pk != tError and
		not ((pk == tStruct or pk == tEnum) and c.findMethod(tys[peek].name, cname) != none):
		if c.argCount(e) > (1 if cname == "toJson" else 0):
			c.errorAt(line, col, compileError("NoArguments", ["{cname}"]))
		elif c.argCount(e) == 1:
			c.checkIndentArg(e)
		if not c.isSerializable(peek, cname == "toBytes"):
			c.errorAt(line, col, compileError("CannotEncode", ["{c.showTy(peek)}"]))
		res = tyStr
		if cname == "toBytes":
			res = tyList(tys, tyInt(8, false))
			c.noteDerive(peek, deriveBin)
		else:
			c.noteDerive(peek, deriveJson | (deriveJsonIndent if c.argCount(e) == 1 else 0))
		return c.typed(e, res)
	none

fn checkCallKindMethod(
	mut c Checker,
	e NodeId,
	peek TypeId,
	pk i64,
	cname str,
	line i64,
	col i64,
	expected TypeId?
) TypeId?:
	if pk == tList:
		res = c.checkListMethod(e, peek, expected)
		return c.typed(e, res)
	if pk == tArray:
		if cname == "len" and c.argCount(e) == 0:
			n = tys[peek].bits   # its fixed length (-1: a number parameter's)
			return c.typed(
				e,
				tyN64 if n < 0 else spanType(tys, c.rangeTypes, tyInt(64, true), spanAt(n))
			)
		if cname == "sum" and c.argCount(e) == 0:
			c.sumAsReduce(e, innerOf(tys, peek))
			return c.typed(e, c.checkReduce(e, innerOf(tys, peek), tys[peek].inner))
		if stepFuses(cname):
			res = c.checkPipeline(e, cname, innerOf(tys, peek), false) ?? tyError   # (a step fuses)
			return c.typed(e, res)
		if c.findDeclInModule("rt", nFnDecl, "array{capital(cname)}") is fd and c.declIsPub(fd):
			return c.typed(e, c.checkRuntimeMethod(e, "array", c.showTy(peek), expected))   # a u8[N]'s bytes
		r = c.callReceiverFunction(e, peek, expected)
		if r is r: return r
		steps = pipelineSteps.filter(s: stepFuses(s)).join(", ")
		c.errorAt(
			line,
			col,
			compileError("FixedArrayLacksMethod", ["{c.showTy(peek)}", "{steps}", "{cname}"])
		)
		return tyError
	if pk == tMap:
		res = c.checkMapMethod(e, peek)
		return c.typed(e, res)
	if pk == tBool and c.gpuCode and cname in laneBoolMethods:
		c.expectArgs(e, cname, 0)
		return c.typed(e, tyBool)   # across the lanes that run together (gpuCheck.zap)
	if pk == tInt or pk == tFloat:
		res = c.checkNumMethod(e, peek)
		c.markWideningCall(e)
		return c.typed(e, res)
	if pk == tSimd:
		res = c.checkSimdMethod(e)
		return c.typed(e, res)
	if pk == tBytes:
		res = c.checkBytesMethod(e)
		return c.typed(e, res)
	if pk == tVec:
		res = c.checkVecMethod(e, peek)
		return c.typed(e, res)
	if pk == tStr:
		res = c.checkStrMethod(e)
		return c.typed(e, res)
	if pk == tError:
		c.checkArgsAlone(e)
		return c.typed(e, tyError)
	none

fn checkCallMethod(
	mut c Checker,
	e NodeId,
	callee NodeId,
	peek TypeId,
	pk i64,
	cname str,
	line i64,
	col i64,
	expected TypeId?
) TypeId:
	# method call: obj.method(args)
	objT = peek
	if c.gpuCode and pk == tStruct and c.gpuTexture(objT):
		return c.typed(e, c.checkTextureMethod(e, objT, cname.copy()))
	m NodeId? = none
	if pk == tStruct or pk == tEnum:
		m = c.findMethod(tys[objT].name, cname)
	if m != none and cname == "drop":
		c.errorAt(line, col, compileError("DropCalled", []))
		return tyError
	if m == none and pk == tStruct:
		# a struct field holding a function value: obj.handler(args)
		f = c.kidNamed(declOf(tys, objT), cname)
		if f is f:
			ft = c.resolveType(nodes[f].types()[0])
			if c.tKind(ft) == tFn:
				nodes[callee].ty = ft
				return c.checkClosureCall(e, ft)
	if m == none and pk == tStruct and c.fieldwiseArity(cname) >= 0 and
		c.uniformNumberField(objT) != none:
		return c.typed(e, c.checkFieldwise(e, objT, cname.copy()))
	if m == none and pk == tStruct and cname == "hash" and c.argCount(e) == 0 and c.isHashKey(objT):
		c.noteDerive(objT, deriveHash | deriveEq)   # $hashN, field by field
		return c.typed(e, tyInt(64, true))
	if m == none:
		r = c.callReceiverFunction(e, objT, expected)
		if r is r: return r
	if m == none:
		if pk != tError:
			errorAt(
				c,
				line,
				col,
				compileError(
					"NoMethod",
					["{cname}", "type {c.showTy(objT)}"]
				)
			)
		return tyError
	md = m ?? return tyError
	c.checkMethodCall(e, md, c.findImplDecl(tys[objT].name, md))
