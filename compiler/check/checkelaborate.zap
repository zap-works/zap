# The checker's resolving of written types and instantiating of generics (check.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

fn teName(mut c Checker, move name str):
	te = newNode(nodes, kidIds, nTyName, 0, 0, text = name)
	te

# A syntactic type that resolves to `t` (every semantic type can be written down).
fn typeToTE(mut c Checker, t TypeId) NodeId:
	k = c.tKind(t)
	if k == tError:
		return c.teName("$unknown")   # resolves back to the error type
	if tys[t].param != "" or tys[t].ranged or isDefined(tys, t):
		return c.teName("$param{t}")   # resolves back to the stand-in (bounds.zap), the range type
	if k in [tInt, tFloat, tBool, tStr, tUnit]: return c.teName(c.showTy(t))
	if k == tNum: return c.teName(str(tys[t].bits))
	if k == tArray:
		te = newNode(nodes, kidIds, nTyArray, 0, 0)
		if tys[t].bits >= 0:
			nodes[te].ival = i32(tys[t].bits)
		else:
			nodes[te].text = "$param{valOf(tys, t)}"   # the length a number parameter's stand-in
		nodes[te].nodePart().types.push(c.typeToTE(innerOf(tys, t)))
		return te
	if k == tStruct or k == tEnum:
		te = c.teName(tys[t].name.copy())
		nodes[te].setText2(globalAlias)   # by its global name, from any module
		return te
	if c.isSimdType(t):
		elem, lanes = c.simdShape(t)
		te = c.teName("Simd")
		nodes[te].nodePart().types.push(c.teName(str(lanes)))
		nodes[te].nodePart().types.push(c.typeToTE(elem))
		return te
	if k == tList:
		te = c.teName("List")
		nodes[te].nodePart().types.push(c.typeToTE(innerOf(tys, t)))
		return te
	if k == tBox and tys[t].counted:
		return c.typeToTE(innerOf(tys, t))   # the struct's name resolves to its shared value
	if k == tBox:
		te = c.teName("Box")
		nodes[te].nodePart().types.push(c.typeToTE(innerOf(tys, t)))
		return te
	if k == tMap:
		te = c.teName("Map")
		nodes[te].nodePart().types.push(c.typeToTE(innerOf(tys, t)))
		nodes[te].nodePart().types.push(c.typeToTE(valOf(tys, t)))
		return te
	if k == tOption:
		te = newNode(nodes, kidIds, nTyOpt, 0, 0)
		nodes[te].nodePart().types.push(c.typeToTE(innerOf(tys, t)))
		return te
	if k == tResult:
		te = newNode(nodes, kidIds, nTyResult, 0, 0)
		nodes[te].nodePart().types.push(c.typeToTE(innerOf(tys, t)))
		nodes[te].nodePart().types.push(c.typeToTE(errOf(tys, t)))
		return te
	if k == tRef:
		te = newNode(nodes, kidIds, nTyRef, 0, 0)
		nodes[te].nodePart().types.push(c.typeToTE(innerOf(tys, t)))
		nodes[te].ival = 1 if tys[t].bits == 1 else 0
		return te
	if k == tFn:
		te = newNode(nodes, kidIds, nTyFn, 0, 0)
		for p in tys[t].params:
			nodes[te].nodePart().types.push(c.typeToTE(p))
		if c.tKind(tys[t].ret) != tUnit:
			nodes[te].nodePart().sub.push(c.typeToTE(retOf(tys, t)))
		return te
	c.teName("()")

# Copies the type expression, replacing the type parameters of the template tmpl (its names)
# with the concrete types. The names are read from the template each time: copying grows nodes.
fn substTE(mut c Checker, te NodeId, tmpl NodeId, types TypeId[]) NodeId:
	k = nodes[te].kind
	if k == nTyName and nodes[te].text2() == "" and nodes[te].types().isEmpty:
		for i in 0..c.nodes[tmpl].names().len:
			if nodes[tmpl].names()[i] == nodes[te].text: return c.typeToTE(types[i])
	o = newNode(nodes, kidIds, k, nodes[te].line, nodes[te].col)
	# the copy holds names of its own
	nodes[o].text = nodes[te].text.copy()
	nodes[o].setText2(nodes[te].text2().copy())
	for aAt in 0..nodes[te].types().len:
		a = nodes[te].types()[aAt]
		nodes[o].nodePart().types.push(c.substTE(a, tmpl, types))
	for sAt in 0..nodes[te].sub().len:
		s = nodes[te].sub()[sAt]
		nodes[o].nodePart().sub.push(c.substTE(s, tmpl, types))
	if k == nTyRange:
		nodes[o].ival = nodes[te].ival   # its bounds are constants, shared
		nodes[o].setKids(kidIds, nodes[te].kids(kidIds).copy())
	if k == nTyArray:
		nodes[o].ival = nodes[te].ival
		for i in 0..c.nodes[tmpl].names().len:
			if nodes[tmpl].names()[i] == nodes[te].text:
				nodes[o].text = "$param{types[i]}"   # T[N]: the number given for N
	o

fn isGenericTemplate(c Checker, d NodeId):
	isTypeDeclKind(nodes[d].kind) and not nodes[d].names().isEmpty

# s as letters, digits and '_': every other byte as '_' and a letter of its own ('_' itself as
# "__"), so two strings never give the same name (i64[]? and i64?[] are two instances)
pub fn identChars(s str) str:
	marks = "_<>, ()?|[]#.$-:"
	codes = "_LGCSPQOVABHDXMK"
	out = []
	for b in s:
		if b.isAlnum():
			out.push(b)
			continue
		out.push('_')
		at = marks.indexOf(b) ?? -1
		if at >= 0:
			out.push(codes[at])
		else:
			out.push('Z')   # any other byte: Z and its two hex digits
			out.push("0123456789abcdef"[i64(b) >> 4])
			out.push("0123456789abcdef"[b & 15])
	str(move out)

# Stack<i64, str> -> ["Stack_i64_C_Sstr", "Stack<i64, str>"]: the global name and the display name.
fn instanceNames(c Checker, tmpl NodeId, args TypeId[]):
	written = args.map(typeMangled(tys, it)).join(", ")
	shown = args.map(c.showTy(it)).join(", ")
	["{nodes[tmpl].text}_{identChars(written)}", "{c.shownName(tmpl)}<{shown}>"]

# the name a declaration is shown by: as written (text2), or its global name when none was
fn shownName(c Checker, d NodeId) ref str:
	if nodes[d].text2() == "": return nodes[d].text
	nodes[d].text2()

fn copyFieldDecl(mut c Checker, f NodeId, tmpl NodeId, args TypeId[]):
	nf = newNode(nodes, kidIds, nFieldDecl, nodes[f].line, nodes[f].col)
	nodes[nf].text = nodes[f].text.copy()
	nodes[nf].nodePart().types.push(c.substTE(nodes[f].types()[0], tmpl, args))
	if not nodes[f].kids(kidIds).isEmpty: nodes[nf].pushKid(kidIds, nodes[f].kids(kidIds)[0])   # the default: copied into each literal that uses it
	nf

# The instance of a generic struct/enum for concrete type arguments (created on first use).
fn programInstantiate(mut c Checker, tmpl NodeId, args TypeId[]):
	kind = nodes[tmpl].kind
	key = instanceKey(tmpl, args)
	if c.madeInstanceAsked(tmpl, args) is d: return d
	if c.madeInstanceNamed(tmpl, args) is d:
		c.madeAsked.addMade(key, d)
		return d
	nm = c.instanceNames(tmpl, args)
	# the instance is a declaration of its own: it holds copies of the template's module and
	# file, and of the arguments, which the caller keeps
	inst = newNode(nodes, kidIds, kind, nodes[tmpl].line, nodes[tmpl].col)
	nodes[inst].nodePart().mod = nodes[tmpl].mod().copy()
	nodes[inst].nodePart().file = nodes[tmpl].file().copy()
	nodes[inst].text = move nm[0]
	nodes[inst].setText2(nm[1])
	nodes[inst].setOrigin(tmpl)
	nodes[inst].nodePart().ints = args.copy()
	nodes[inst].flags = nodes[tmpl].flags
	c.madeAsked.addMade(key, inst)
	if kind == nStructDecl:
		for f in nodes[tmpl].kids(kidIds).copy():
			madeKid = c.copyFieldDecl(f, tmpl, args)
			nodes[inst].pushKid(kidIds, madeKid)
	else:
		for v in nodes[tmpl].kids(kidIds).copy():
			nv = newNode(nodes, kidIds, nVariant, nodes[v].line, nodes[v].col)
			nodes[nv].text = nodes[v].text.copy()
			nodes[nv].setText2(nodes[v].text2().copy())
			for f in nodes[v].kids(kidIds).copy():
				madeKid = c.copyFieldDecl(f, tmpl, args)
				nodes[nv].pushKid(kidIds, madeKid)
			nodes[inst].pushKid(kidIds, nv)
	c.addDecl(inst)
	# every `impl Template<T>` gets an instance, its methods copies of the template's of its own,
	# checked once under the substitution
	impls = c.implsOf(nodes[tmpl].text).toList()
	for im in impls:
		if nodes[im].names().isEmpty: continue
		if nodes[im].names().len != args.len: continue
		ii = newNode(nodes, kidIds, nImplDecl, nodes[im].line, nodes[im].col)
		nodes[ii].nodePart().mod = nodes[im].mod().copy()
		nodes[ii].nodePart().file = nodes[im].file().copy()
		nodes[ii].setText2(nodes[inst].text2().copy())
		nodes[ii].setOrigin(im)
		nodes[ii].text = nodes[inst].text.copy()
		for k in 0..nodes[im].kids(kidIds).len:
			c.readBody(nodes[im].kids(kidIds)[k])
			m = cloneTree(nodes, kidIds, nodes[im].kids(kidIds)[k])   # by index: cloning grows nodes
			c.noteReceiverCopy(m, nodes[im].kids(kidIds)[k])
			nodes[ii].pushKid(kidIds, m)
		nodes[ii].nodePart().names2 = nodes[im].names().copy()
		nodes[ii].nodePart().ints = args.copy()
		c.addDecl(ii)
	inst

# the instance of the generic struct or enum tmpl made for args by their ids, when one was
fn madeInstanceAsked(c Checker, tmpl NodeId, args TypeId[]) NodeId?:
	for d in c.madeAsked.get(instanceKey(tmpl, args)) ?? []:
		if nodes[d].kind == nodes[tmpl].kind and nodes[d].origin() == tmpl and
			sameIds(nodes[d].ints(), args):
			return d
	none

# the instance made for arguments of other ids but the same names, when one was
fn madeInstanceNamed(c Checker, tmpl NodeId, args TypeId[]) NodeId?:
	name = c.instanceNames(tmpl, args)[0]
	for pos in c.declsByName.get(name) ?? []:
		d = c.decls[pos]
		if nodes[d].kind == nodes[tmpl].kind and nodes[d].origin() == tmpl and nodes[d].text == name:
			return d
	none

fn sameIds(a TypeId[], b TypeId[]):
	a.len == b.len and (0..a.len).all(a[it] == b[it])

fn addMade(mut index {i64: NodeId[]}, key i64, d NodeId):
	match index.get(key):
		mut at: at.push(d)
		none: index[key] = [d]

# instantiateFromTE for the type arguments written in the type expression te; they are read
# from the node one at a time, as resolving each may grow nodes
fn instantiateFromNode(mut c Checker, tmpl NodeId, te NodeId, line i64, col i64) NodeId?:
	if not c.typeArgCountOk(tmpl, nodes[te].types().len, line, col): return none
	args = (0..c.nodes[te].types().len).map(c.resolveTypeOrNumber(nodes[te].types()[it]))
	c.instantiateResolved(tmpl, args, line, col)

fn typeArgCountOk(mut c Checker, tmpl NodeId, n i64, line i64, col i64):
	want = nodes[tmpl].names().len
	if n != want:
		c.errorAt(
			line,
			col,
			compileError("TypeArgumentCount", ["{c.shownName(tmpl)}", "{want}", "{n}"])
		)
		return false
	true

# the instance for resolved type arguments (none when one is unknown, already reported)
fn instantiateResolved(mut c Checker, tmpl NodeId, args0 TypeId[], line i64, col i64) NodeId?:
	if args0.any(c.tKind(it) == tError):
		return none   # the unknown argument was reported already
	args = c.numberArgs(tmpl, args0)
	if nodes[tmpl].hasFlag(flagShared):
		if args.find(c.tKind(it) == tRef or c.holdsRefs(it) or c.isViewType(it)) is held:
			errorAt(
				c,
				line,
				col,
				compileError("SharedHoldsReference", ["{c.shownName(tmpl)}", "{c.showTy(held)}"])
			)
			return none
	for failure in c.instanceBoundFailures(tmpl, args):
		c.errorAt(line, col, compileError("BoundNotMet", ["{failure}", "{c.shownName(tmpl)}"]))
	if (0..args.len).any(it < nodes[tmpl].bounds().len and
			c.numberArgFailure(nodes[tmpl].bounds()[it], args[it]) != ""):
		return none   # a type for a number or a number for a type: no instance to make
	c.programInstantiate(tmpl, args)

# the type te writes; a number (a number parameter's value) is an error here
fn resolveType(mut c Checker, te NodeId):
	t = c.resolveTypeOrNumber(te)
	if c.tKind(t) != tNum: return t
	c.errorAt(nodes[te].line, nodes[te].col, compileError("NumberNotType", ["{c.showTy(t)}"]))
	tyError

# The type te writes, or the number a type argument gives a number parameter (a tNum). Where no
# type parameter is in force the node always writes the same type: it keeps the first one that
# met no error, read back from then on.
fn resolveTypeOrNumber(mut c Checker, maybeTe NodeId?):
	te = maybeTe ?? return tyUnit
	if not c.subst.names.isEmpty: return c.resolveWritten(te)
	if nodes[te].ty is known: return known
	met = c.errorsMet
	t = c.resolveWritten(te)
	if c.errorsMet == met and c.tKind(t) != tError:
		nodes[te].ty = t
	t

# the type te writes, resolved
fn resolveWritten(mut c Checker, te NodeId) TypeId:
	k = nodes[te].kind
	if k == nTyAbsent: return tyUnit
	if k == nTyOpt:
		inner = c.resolveType(nodes[te].types()[0])
		return tyOption(tys, inner)
	if k == nTyRange: return c.resolveRangeType(te)
	if k == nTyArray: return c.resolveWrittenArray(te)
	if k == nTyResult: return c.resolveWrittenResult(te)
	if k == nTyRef: return c.resolveWrittenRef(te)
	if k == nTyFn: return c.resolveWrittenFn(te)
	name = nodes[te].text
	line = nodes[te].line
	col = nodes[te].col
	if c.substLookup(name) is s: return s
	if primType(name) is prim: return prim
	if name == "$unknown": return tyError
	if name.startsWith("$param"): return TypeId(i64.parse(name[6..]) ?? i64(tyError))
	if name != "" and name[0].isDigit():
		return tyNum(tys, i64.parse(name) ?? -1, none)   # a type argument's number: Mat<2, 3>
	if name.startsWith("$Ty"):
		return c.derivedTypeNamed(name) ?? tyError   # a type the compiler's own code names (derive.zap)
	# name borrows nodes, which the steps below change (reporting, resolving a type argument),
	# so its last use is here; after this the name and the arguments are read from the node
	simd = isSimdName(name)
	if name == "Vector" or name == "Matrix":
		listForm = "f64[]" if name == "Vector" else "f64[,]"
		errorAt(
			c,
			line,
			col,
			compileError("NotAListOfNumbers", ["{name}", "{listForm}"])
		)
		return tyError
	if simd: return c.simdTypeNamed(te)
	nargs = nodes[te].types().len
	if nodes[te].text == "List":
		elem = c.resolveType(nodes[te].types()[0])
		c.rejectHeldRef(elem, line, col, "a list element")
		return tyList(tys, elem)
	if nodes[te].isSeqName():
		if nargs != 1:
			c.errorAt(line, col, compileError("SeqTypeArity", []))
			return tyError
		elem = c.resolveType(nodes[te].types()[0])
		c.rejectHeldRef(elem, line, col, "a Seq's element")
		return tySeq(tys, elem)
	if nodes[te].text == "Box":
		if nargs != 1:
			c.errorAt(line, col, compileError("BoxTypeArity", []))
			return tyError
		inner = c.resolveType(nodes[te].types()[0])
		c.rejectRef(inner, line, col, "a boxed value")
		return tyBox(tys, inner)
	if nodes[te].text == "Table":
		if nargs != 1:
			c.errorAt(line, col, compileError("TableTypeArity", []))
			return tyError
		return c.tableType(c.resolveType(nodes[te].types()[0]), line, col)
	if nodes[te].text == "Map":
		if nargs != 2:
			c.errorAt(line, col, compileError("MapTypeArity", []))
			return tyError
		key = c.resolveType(nodes[te].types()[0])
		c.requireBound(key, "Hash", "a map key", line, col)
		if not c.isHashKey(key):
			c.errorAt(line, col, compileError("MapKeyType", ["{c.showTy(key)}"]))
		else:
			c.noteHashKey(key)
		val = c.resolveType(nodes[te].types()[1])
		c.rejectHeldRef(val, line, col, "a map value")
		return tyMap(tys, key, val)
	c.resolveWrittenDeclared(te, nargs, line, col)

fn resolveWrittenArray(mut c Checker, te NodeId) TypeId:
	size TypeId? = none if nodes[te].text == "" else c.arraySizeNamed(te)
	if size == none and nodes[te].text != "": return tyError
	n i64 = nodes[te].ival
	if size is s:
		n = tys[s].bits
	inner = c.resolveType(nodes[te].types()[0])
	if n == 0 or (n < 0 and size == none):
		c.errorAt(nodes[te].line, nodes[te].col, compileError("EmptyFixedArray", []))
		return tyError
	if c.tKind(inner) == tError: return tyError
	if size is s: return tyArrayOf(tys, inner, s)
	tyArray(tys, inner, n)

fn resolveWrittenResult(mut c Checker, te NodeId) TypeId:
	ok = c.resolveType(nodes[te].types()[0])
	er = c.resolveType(nodes[te].types()[1])
	if isSameType(tys, ok, er) and c.tKind(ok) != tError and c.subst.names.isEmpty:
		c.errorAt(
			nodes[te].line,
			nodes[te].col,
			compileError("ResultSidesAlike", ["{c.showTy(ok)}"])
		)
		return tyError
	tyResult(tys, ok, er)

fn resolveWrittenRef(mut c Checker, te NodeId) TypeId:
	inner = c.resolveType(nodes[te].types()[0])
	if c.tKind(inner) == tRef and not c.subst.names.isEmpty:
		return inner   # ref T of an instance whose T is a reference: that reference
	if c.tKind(inner) == tRef:
		c.errorAt(nodes[te].line, nodes[te].col, compileError("RefToRef", []))
		return tyError
	tyRef(tys, inner, nodes[te].ival == 1)

fn resolveWrittenFn(mut c Checker, te NodeId) TypeId:
	ps = []
	for pAt in 0..nodes[te].types().len:
		p = nodes[te].types()[pAt]
		ps.push(c.resolveType(p))
	r = tyUnit
	if not nodes[te].sub().isEmpty:
		r = c.resolveType(nodes[te].sub()[0])
	tyFn(tys, ps, r)

fn resolveWrittenDeclared(mut c Checker, te NodeId, nargs i64, line i64, col i64) TypeId:
	found = c.lookupDeclAsWritten(nStructDecl, nodes[te].text2(), nodes[te].text, line, col)
	if found == none and nodes[te].text2() == "":
		c.errorAt(
			line,
			col,
			compileError("UnknownType", ["{nodes[te].text}"])
		)
	d = found ?? return tyError
	if nodes[d].hasFlag(flagTypeAlias):
		if nargs > 0:
			c.errorAt(line, col, compileError("NotGeneric", ["{nodes[te].text}"]))
			return tyError
		# by its global name, found wherever the node is resolved again
		nodes[te].text = nodes[d].text.copy()
		nodes[te].setText2(globalAlias)
		return c.aliasedType(d)
	# the node now names the declaration by its global name, a copy of its own, found by that
	# name wherever it is resolved again (a generic body checked from another module)
	nodes[te].text = nodes[d].text.copy()
	nodes[te].setText2(globalAlias)
	if c.isGenericTemplate(d):
		inst = c.instantiateFromNode(d, te, line, col) ?? return tyError
		return c.valueTypeOf(inst)
	if nargs > 0:
		c.errorAt(line, col, compileError("NotGeneric", ["{nodes[te].text}"]))
		return tyError
	c.valueTypeOf(d)

# `T in a..b` (ival 0), `a..=b` (1), `a..` (2): the integer type T's values in the range
fn resolveRangeType(mut c Checker, te NodeId):
	line = nodes[te].line
	col = nodes[te].col
	base = c.resolveType(nodes[te].types()[0])
	if c.tKind(base) == tError: return tyError
	if c.tKind(base) != tInt or tys[base].ranged:
		c.errorAt(line, col, compileError("RangeTypeNotInteger", ["{c.showTy(base)}"]))
		return tyError
	least, most = intBounds(tys, base)
	lo = c.rangeBound(nodes[te].kids(kidIds)[0]) ?? return tyError
	hi = most
	if nodes[te].ival != 2:
		hi = c.rangeBound(nodes[te].kids(kidIds)[1]) ?? return tyError
		if nodes[te].ival == 0: hi -= 1
	if lo < least or hi > most or lo > hi:
		c.errorAt(line, col, compileError("RangeTypeEmpty", ["{c.showTy(base)}"]))
		return tyError
	t = tyRange(tys, base, lo, hi)
	if t == tyN32 or t == tyN64: c.noteNaturalSpelling(te, t)
	t

# a range type's bound: an integer literal (negative too) or a constant's
fn rangeBound(mut c Checker, e NodeId) i64?:
	at NodeId? = e
	if nodes[e].kind == nIdent:
		at = none
		if c.lookupDecl(nConstDecl, "", nodes[e].text, nodes[e].line, nodes[e].col) is d:
			at = nodes[d].kids(kidIds)[0]
	if at is at and foldedInt(nodes, kidIds, at, x: none) is v: return v
	errorAt(
		c,
		nodes[e].line,
		nodes[e].col,
		compileError("RangeTypeBound", [])
	)
	none

# every type alias resolved before anything else is checked (lookupDecl reads them)
fn resolveTypeAliases(mut c Checker):
	for decl in c.decls[c.freshDecls..].copy():
		d = decl
		if nodes[d].kind == nStructDecl and nodes[d].hasFlag(flagTypeAlias): c.aliasedType(d)

# the methods of defined types (`fn half(self Meters)`, an impl the parser made) become functions
# taking the type first, by the global name `Meters_half` that typeFunctions finds: a defined type
# has no impl of its own, its value is its base's
fn definedTypeMethods(mut c Checker):
	for d in c.decls[c.freshDecls..].copy():
		if nodes[d].kind != nImplDecl or not nodes[d].names().isEmpty: continue
		td = c.findTypeDecl(nodes[d].text) ?? continue
		if not nodes[td].hasFlag(flagTypeAlias) or not isDefined(tys, c.aliasedType(td)): continue
		for m in nodes[d].kids(kidIds).copy():
			line = nodes[m].line
			col = nodes[m].col
			te = newNode(nodes, kidIds, nTyName, line, col, text = nodes[td].text.copy())
			nodes[te].setText2(globalAlias)
			self = newNode(nodes, kidIds, nParam, line, col, text = "self")
			nodes[self].nodePart().types.push(te)
			nodes[self].ival = modeMut if nodes[m].hasFlag(flagMut) else modeRead
			nodes[m].flags &= ~flagMut
			nodes[m].insertKid(kidIds, 0, self)
			nodes[m].text = definedMethodName(nodes[td].text, nodes[m].text)
			c.addDecl(m)
		nodes[d].setKids(kidIds, [])

# the global name of defined type t's method m (definedTypeMethods)
fn definedMethodName(t str, m str):
	"{t}_{m}"

# the type the declaration `type Name = T` d gives, resolved once in its own module (a type of
# itself, through any chain, is an error): a range type (`i64 in 0..=100`) by that name, else a
# type of its own over T
fn aliasedType(mut c Checker, d NodeId):
	if nodes[d].ty is known and known != tyError: return known
	if nodes[d].ty == tyError:
		c.errorAt(
			nodes[d].line,
			nodes[d].col,
			compileError("TypeNamesItself", ["{nodes[d].text2()}"])
		)
		return tyError
	nodes[d].ty = tyError   # being resolved: a cycle meets this
	savedMod = c.curMod
	savedFile = move c.curFile
	c.enterModuleOf(d)
	t = c.resolveType(nodes[d].types()[0])
	c.curMod = savedMod
	c.curFile = savedFile
	named = t
	if tys[t].ranged and t != tyN32 and t != tyN64 and tys[t].display == "" and
		not isDefined(tys, t):
		tys[t].display = c.shownName(d).copy()   # its checked conversion is written by this name
	elif tys[t].kind != tError:
		shown = c.shownName(d).copy()
		named = tyDefined(tys, t, d, nodes[d].text.copy(), shown)
	nodes[d].ty = named
	named

# the type a value of the declared type d has: the struct or enum itself, or for a `shared type`
# the counted pointer to it
fn valueTypeOf(mut c Checker, d NodeId):
	t = tyOfDecl(tys, nodes, d)
	if nodes[d].hasFlag(flagShared): return tyShared(tys, t)
	t

# The type of a top-level constant, computed on first use (constants may reference each other).
fn constTypeOf(mut c Checker, d NodeId) TypeId:
	if nodes[d].ty != none: return typeOf(nodes, d)
	nodes[d].ty = tyError
	# the scopes of the code being checked move aside (move leaves them empty) and come back
	savedMod = c.curMod
	savedFile = move c.curFile
	savedVars = move c.vars
	savedIndex = move c.varIndex
	c.varIndex = NameIndex()   # a moved map's bytes are no map to read
	savedStarts = move c.scopeStarts
	savedLam = move c.lamStack
	savedBounds = move c.lamBounds
	savedGpu = c.gpuCode
	c.gpuCode = nodes[d].hasFlag(flagGpu)
	c.enterScope()
	c.enterModuleOf(d)
	declT TypeId? = none
	if not nodes[d].types().isEmpty:
		declT = c.resolveType(nodes[d].types()[0])
	# a compute group's memory has its type alone (a GPU file's `mut a T[N]`)
	vt = (declT ?? tyError) if nodes[d].kids(kidIds).isEmpty else c.checkExpr(nodes[d].kids(kidIds)[0], declT)
	if declT is declT and not isSameType(tys, vt, declT):
		if not nodes[d].kids(kidIds).isEmpty and isAssignable(tys, vt, declT):
			c.coerceKid(d, 0, declT)   # as a binding's: some(v), a wider integer
		else:
			errorAt(
				c,
				nodes[d].line,
				nodes[d].col,
				compileError(
					"ConstantTypeMismatch",
					["{nodes[d].text2()}", "{c.showTy(declT)}", "{c.showTy(vt)}"]
				)
			)
	c.exitScope()
	c.vars = savedVars
	c.varIndex = savedIndex
	c.scopeStarts = savedStarts
	c.lamStack = savedLam
	c.lamBounds = savedBounds
	c.curMod = savedMod
	c.curFile = savedFile
	c.gpuCode = savedGpu
	c.typed(d, declT ?? vt)
