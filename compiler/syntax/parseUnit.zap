# The parsing of declarations and of a whole file (parse.zap).

fn parseGenerics(mut p Parser, d NodeId):
	if not p.at(tkLt): return
	p.adv()
	going = true
	while going:
		n = p.expectTok(tkUident)
		p.nodes[d].nodeMore(p.kidIds).names.push(n.text)
		bounds = ""
		if p.at(tkIdent) and p.kindAt(1) != tkDot:
			bounds = p.adv().text   # <N n64>: a number parameter, of that integer type
		elif p.at(tkUident) or p.at(tkIdent) and p.kindAt(1) == tkDot and p.kindAt(2) == tkUident:
			bounds = p.boundName()
			while p.accept(tkPlus):
				bounds = "{bounds}+{p.boundName()}"
		p.nodes[d].nodeMore(p.kidIds).bounds.push(bounds)
		going = p.accept(tkComma)
	p.expectGt()

# a bound as written after a type parameter: Ord, Drawable, or a module's (engine.Drawable)
fn boundName(mut p Parser):
	if p.at(tkIdent):
		alias = p.adv().text
		p.expectTok(tkDot)
		return "{alias}.{p.expectTok(tkUident).text}"
	p.expectTok(tkUident).text

fn parseParam(mut p Parser):
	mode = modeRead
	if p.isOutAhead(true):
		# out x T: the system writes a T at the address the word carries; the type the
		# call's argument has is kept in sub[0]
		p.adv()
		n = p.expectTok(tkIdent)
		prm = p.mk(nParam, n.line, n.col)
		p.nodes[prm].setText(n.text)
		p.nodes[prm].ival = modeOut
		p.nodes[prm].nodePart(p.kidIds).sub.push(p.parseType())
		word = p.mk(nTyName, n.line, n.col)
		p.nodes[word].setText("i64")
		p.nodes[prm].nodePart(p.kidIds).types.push(word)
		return prm
	if p.accept(tkMut):
		mode = modeMut
	elif p.accept(tkMove):
		mode = modeMove
	n = p.adv() if p.inBound and p.at(tkThis) else p.expectTok(tkIdent)   # self: boundSelf places it
	p.notAlias(n)
	prm = p.mk(nParam, n.line, n.col)
	p.nodes[prm].setText(n.text)
	p.nodes[prm].ival = i32(mode)
	p.nodes[prm].nodePart(p.kidIds).types.push(p.parseType())
	if p.accept(tkEq):
		madeKid = p.parseExpr()
		p.nodes[prm].pushKid(p.kidIds, madeKid)   # the default a call that leaves it out gives
	prm

fn parseFnDecl(mut p Parser, isPub bool, isMut bool, isExtern bool):
	fnT = p.expectTok(tkFn)
	f = p.mk(nFnDecl, fnT.line, fnT.col)
	flags = 0
	if isPub:
		flags |= flagPub
	if isMut:
		flags |= flagMut
	if isExtern:
		flags |= flagExtern
	p.nodes[f].flags = flags
	# the system spells its functions in PascalCase, and a .zapx file its components
	n = p.adv() if (isExtern or isMarkupFile(p.file)) and p.at(tkUident) else p.expectTok(tkIdent)
	if n.text == "main" and not isExtern:
		parseError(
			p,
			n,
			compileError("MainDeclared", [])
		)
	p.nodes[f].setText(n.text)
	p.nodes[f].nodeMore(p.kidIds).file = p.file.copy()
	p.parseGenerics(f)
	p.parseParamList(f)
	p.parseFnResult(f)
	if p.at(tkNewline) or p.at(tkEof):
		return f   # an extern function has no body
	body = p.optionsBody(f)
	if not isGpuFile(p.file):
		p.keepNumberBody(f, body)
	p.finishFnBody(f, body, [], [])
	p.nodes[f].nodePart(p.kidIds).sub.push(body)
	f

# The passes a function's body goes through once parsed: its register arrays (sized by the
# values of its number parameters, when an instance knows them) and its implicit return.
fn finishFnBody(mut p Parser, f NodeId, body NodeId, numbers str[], values i64[]):
	if not isGpuFile(p.file):
		p.expandArrays(body, p.paramNames(f), numbers, values)   # a GPU function's arrays are the shader compiler's
	else:
		p.zeroBareArrays(body)
	if not p.nodes[f].types(p.kidIds).isEmpty and
		not p.unitThrows(p.nodes[f].types(p.kidIds)[0]) and
		not p.nodes[p.nodes[f].types(p.kidIds)[0]].isSeqName():
		markImplicitReturns(p.nodes, p.kidIds, body)   # a function that gives no value (? E alone, a Seq) ends on a statement

# A function that declares a result returns its trailing expression: the last statement of
# the body, when it is an expression, becomes a return; a trailing if/else or a match with
# block arms gets the same in every branch. `return` stays available for early exits. The
# checker marks a body whose result it infers the same way (results.zap).
fn markImplicitReturns(mut nodes Node[], mut kidIds NodeLists, blk NodeId):
	n = nodes[blk].kids(kidIds).len
	if n == 0: return
	last = nodes[blk].kids(kidIds)[n - 1]
	k = nodes[last].kind
	if k == nIf:
		if nodes[last].sub(kidIds).len > 1:
			for i in 0..nodes[last].sub(kidIds).len:
				markImplicitReturns(nodes, kidIds, nodes[last].sub(kidIds)[i])
		return
	if k != nExprStmt: return
	e = nodes[last].kids(kidIds)[0]
	if nodes[e].kind == nMatch:
		if nodes[e].kidsFrom(kidIds, 1).all(not nodes[it].sub(kidIds).isEmpty):
			for i in 1..nodes[e].kids(kidIds).len:
				markImplicitReturns(nodes, kidIds, nodes[nodes[e].kids(kidIds)[i]].sub(kidIds)[0])
			return
	r = newNode(nodes, kidIds, nReturn, nodes[last].line, nodes[last].col, kids = [e])
	nodes[r].ival = 2   # implicit: not written as a return
	nodes[blk].setKid(kidIds, n - 1, r)

# a field: its name, its type, and the value a literal that leaves it out gives it (`= expr`)
fn parseFieldDecl(mut p Parser):
	fn0 = p.expectTok(tkIdent)
	f = p.mk(nFieldDecl, fn0.line, fn0.col)
	p.nodes[f].setText(fn0.text)
	p.nodes[f].nodePart(p.kidIds).types.push(p.parseType())
	if p.accept(tkEq):
		madeKid = p.parseExpr()
		p.nodes[f].pushKid(p.kidIds, madeKid)
	f

# a declaration of kind k named name, in the file being parsed
fn mkNamedDecl(mut p Parser, k i64, line i64, col i64, name str):
	d = p.mk(k, line, col)
	p.nodes[d].setText2(p.kidIds, name.copy())   # the declared name, kept as written
	p.nodes[d].setText(name.copy())
	p.nodes[d].nodeMore(p.kidIds).file = p.file.copy()
	d

fn parseTypeDecl(mut p Parser, isPub bool):
	start = p.here()
	isShared = p.accept(tkShared)
	p.expectTok(tkType)
	name = p.expectTok(tkUident)
	d = p.mkNamedDecl(nStructDecl, start.line, start.col, name.text)
	flags = 0
	if isPub:
		flags |= flagPub
	if isShared:
		flags |= flagShared
	p.nodes[d].flags = flags
	p.parseGenerics(d)
	if p.accept(tkEq):
		# `type Name = T`: another name for T, the same type
		if not p.nodes[d].names(p.kidIds).isEmpty:
			p.parseError(start, compileError("GenericDefinedType", []))
		p.nodes[d].nodePart(p.kidIds).types.push(p.parseType())
		p.nodes[d].flags |= flagTypeAlias
		return d
	if p.at(tkIdent) and p.cur().text == "bits" and p.nodes[d].names(p.kidIds).isEmpty:
		return p.parseBitsDecl(d)
	p.expectTok(tkColon)
	p.openIndented()
	if p.at(tkUident):
		p.nodes[d].kind = nEnumDecl
		while not p.at(tkDedent) and not p.at(tkEof):
			vn = p.expectTok(tkUident)
			v = p.mk(nVariant, vn.line, vn.col)
			p.nodes[v].setText(vn.text)
			if p.accept(tkLparen):
				going = not p.at(tkRparen)
				while going:
					madeKid = p.parseFieldDecl()
					p.nodes[v].pushKid(p.kidIds, madeKid)
					going = p.accept(tkComma) and not p.at(tkRparen)
				p.expectTok(tkRparen)
			if p.accept(tkEq):
				p.parseVariantValue(v)
			p.nodes[d].pushKid(p.kidIds, v)
			p.skipNL()
			p.blockMethodsOf(d)
		p.checkVariantValues(d)
	else:
		while not p.at(tkDedent) and not p.at(tkEof):
			madeKid = p.parseFieldDecl()
			p.nodes[d].pushKid(p.kidIds, madeKid)
			p.skipNL()
			p.blockMethodsOf(d)
	p.expectTok(tkDedent)
	d

# `type Status bits u8:` then `n bool = 7`, `mode u8 = 0..3` on its lines: a type defined over
# the integer whose fields name its bits (check/bitsTypes.zap); `bits` is a word only here
fn parseBitsDecl(mut p Parser, d NodeId):
	p.adv()
	p.nodes[d].nodePart(p.kidIds).types.push(p.parseType())
	p.nodes[d].flags |= flagTypeAlias
	p.expectTok(tkColon)
	p.openIndented()
	while not p.at(tkDedent) and not p.at(tkEof):
		f = p.parseFieldDecl()
		if p.nodes[f].kids(p.kidIds).isEmpty:
			p.parseError(p.cur(), compileError("BitsField", [p.nodes[f].text.copy()]))
		p.nodes[d].pushKid(p.kidIds, f)
		p.skipNL()
		p.blockMethodsOf(d)
	p.expectTok(tkDedent)
	d

# The integer after `=` in a variant (`Add = 1`, negative or in hex too), kept as text in the
# variant's text2 and read back by Node.value
fn parseVariantValue(mut p Parser, v NodeId):
	neg = p.accept(tkMinus)
	lit = p.expectTok(tkInt)
	p.nodes[v].setText2(p.kidIds, "-{lit.text}" if neg else lit.text)
	if p.nodes[v].value(p.kidIds) == none:
		p.stopParsing(lit.line, lit.col, compileError("EnumValueNumber", [p.nodes[v].text.copy()]))

# An enum either gives every variant an integer and no payload, or none of them one; the
# integers are distinct.
fn checkVariantValues(mut p Parser, d NodeId):
	kids = p.nodes[d].kids(p.kidIds).copy()
	if not kids.any(p.nodes[it].text2(p.kidIds) != ""): return
	for k, v in kids:
		line = p.nodes[v].line
		col = p.nodes[v].col
		name = p.nodes[v].text.copy()
		if p.nodes[v].text2(p.kidIds) == "":
			p.stopParsing(
				line,
				col,
				compileError("EnumValueMissing", [name.copy(), p.nodes[d].text.copy()])
			)
		elif not p.nodes[v].kids(p.kidIds).isEmpty:
			p.stopParsing(line, col, compileError("EnumValuePayload", [name.copy()]))
		else:
			for w in kids[..k]:
				if p.nodes[w].value(p.kidIds) == p.nodes[v].value(p.kidIds):
					p.stopParsing(
						line,
						col,
						compileError(
							"EnumValueDuplicate",
							[
								p.nodes[w].text.copy(),
								name.copy(),
								"{p.nodes[v].value(p.kidIds) ?? 0}"
							]
						)
					)

# The methods written in type d's block after its fields (or variants), its receiver implicit
# (spec 5.2): `fn put(k i32)`, `mut fn` to change it, which a block's method that is not `pub`
# need not write (check/receivers.zap infers it). Each is kept as an impl of its own, or a generic
# function taking self first when it has type parameters of its own. A field after them is an
# error.
fn blockMethodsOf(mut p Parser, d NodeId):
	if not p.methodAhead(): return
	while not p.at(tkDedent) and not p.at(tkEof):
		if not p.methodAhead():
			p.parseError(
				p.cur(),
				compileError("FieldAfterMethods", ["{p.nodes[d].text2(p.kidIds)}"])
			)
		p.blockMethods.push(p.blockMethod(d))
		p.skipNL()

fn methodAhead(p Parser):
	at = 1 if p.at(tkPub) else 0
	k = p.kindAt(at)
	k == tkFn or (k == tkMut or k == tkMove) and p.kindAt(at + 1) == tkFn

fn blockMethod(mut p Parser, d NodeId):
	isPub = p.accept(tkPub)
	if p.at(tkMove):
		p.parseError(p.cur(), compileError("SelfLent", []))
	isMut = p.accept(tkMut)
	f = p.parseFnDecl(isPub, isMut, false)
	p.nodes[f].ival = methodInBlock
	line = p.nodes[f].line
	col = p.nodes[f].col
	if not p.nodes[f].names(p.kidIds).isEmpty:
		# type parameters of its own: the type's go first, and self is its first parameter
		te = p.mk(nTyName, line, col)
		p.nodes[te].setText(p.nodes[d].text2(p.kidIds).copy())
		for nameAt in 0..p.nodes[d].names(p.kidIds).len:
			name = p.nodes[d].names(p.kidIds)[nameAt].copy()
			arg = p.mk(nTyName, line, col)
			p.nodes[arg].setText(name.copy())
			p.nodes[te].nodePart(p.kidIds).types.push(arg)
		prm = p.mk(nParam, line, col)
		p.nodes[prm].setText("self")
		p.nodes[prm].ival = modeMut if isMut else modeRead
		p.nodes[prm].nodePart(p.kidIds).types.push(te)
		p.nodes[f].insertKid(p.kidIds, 0, prm)
		p.nodes[f].flags &= ~flagMut
		names = p.nodes[d].names(p.kidIds).copy()
		names.extend(p.nodes[f].names(p.kidIds).copy())
		p.nodes[f].nodeMore(p.kidIds).names = names
		bounds = p.nodes[d].bounds(p.kidIds).copy()
		bounds.extend(p.nodes[f].bounds(p.kidIds).copy())
		p.nodes[f].nodeMore(p.kidIds).bounds = bounds
		return f
	impl = p.mk(nImplDecl, line, col)
	p.nodes[impl].setText2(p.kidIds, p.nodes[d].text2(p.kidIds).copy())
	p.nodes[impl].setText(p.nodes[d].text2(p.kidIds).copy())
	p.nodes[impl].nodeMore(p.kidIds).file = p.file.copy()
	p.nodes[impl].nodeMore(p.kidIds).names = p.nodes[d].names(p.kidIds).copy()
	p.nodes[impl].nodeMore(p.kidIds).bounds = p.nodes[d].bounds(p.kidIds).copy()
	p.nodes[impl].pushKid(p.kidIds, f)
	impl

# `bound Drawable:` then `fn draw(mut self Drawable, mut r Renderer)`, `fn bounds(self Drawable)
# Rect` on its lines: the functions taking a type first it must have to stand for a type
# parameter with this bound (`fn drawAll<T Drawable>(xs T[])`), and the only ones the generic
# may call on it. Each is a signature without a body, its value `self` of the bound's name; kept
# as a method's (flagMut for `mut self`, the rest its parameters). (`bound` is a word only here.)
fn parseBoundDecl(mut p Parser, isPub bool):
	start = p.adv()
	name = p.expectTok(tkUident)
	d = p.mkNamedDecl(nBoundDecl, start.line, start.col, name.text)
	if isPub:
		p.nodes[d].flags = flagPub
	p.expectTok(tkColon)
	p.openIndented()
	p.inBound = true
	while not p.at(tkDedent) and not p.at(tkEof):
		fnT = p.expectTok(tkFn)
		f = p.mk(nFnDecl, fnT.line, fnT.col)
		p.nodes[f].setText(p.expectTok(tkIdent).text)
		p.nodes[f].nodeMore(p.kidIds).file = p.file.copy()
		p.parseParamList(f)
		p.parseFnResult(f)
		p.boundSelf(f, p.nodes[d].text2(p.kidIds).copy())
		p.nodes[d].pushKid(p.kidIds, f)
		p.skipNL()
	p.inBound = false
	p.expectTok(tkDedent)
	d

# whether parameters ps start with `self B` or `mut self B`, B the bound
fn selfOfBound(p Parser, ps NodeId[], bound str):
	if ps.isEmpty: return false
	te = p.nodes[ps[0]].types(p.kidIds)[0]
	p.nodes[ps[0]].text == "self" and p.nodes[te].kind == nTyName and p.nodes[te].text == bound and
		p.nodes[te].types(p.kidIds).isEmpty and p.nodes[ps[0]].ival != modeMove

# a bound's function f takes `self B` or `mut self B` first, B the bound's name: kept as a method's
# signature (flagMut for mut self), without it
fn boundSelf(mut p Parser, f NodeId, bound str):
	ps = p.nodes[f].kids(p.kidIds).copy()
	if not p.selfOfBound(ps, bound):
		at = f if ps.isEmpty else ps[0]
		p.selfError(at, compileError("BoundSelfFirst", ["{p.nodes[f].text}", "{bound}"]))
		return
	if p.nodes[ps[0]].ival == modeMut:
		p.nodes[f].flags |= flagMut
	p.nodes[f].removeKid(p.kidIds, 0)

fn selfError(mut p Parser, prm NodeId, msg str):
	p.stopParsing(p.nodes[prm].line, p.nodes[prm].col, msg)

# `parts lex, check`: a top-level line naming the parts of the file's module
fn partsAhead(p Parser):
	p.at(tkIdent) and p.cur().text == "parts" and p.kindAt(1) == tkIdent

fn parseParts(mut p Parser):
	start = p.adv()
	d = p.mk(nPartsDecl, start.line, start.col)
	p.nodes[d].nodeMore(p.kidIds).file = p.file.copy()
	p.nodes[d].nodeMore(p.kidIds).names.push(p.expectTok(tkIdent).text.copy())
	while p.accept(tkComma):
		p.nodes[d].nodeMore(p.kidIds).names.push(p.expectTok(tkIdent).text.copy())
	d

# `import json`: the module, its names read through it (json.parse)
fn parseImport(mut p Parser):
	start = p.adv()
	d = p.mk(nImportDecl, start.line, start.col)
	p.nodes[d].nodeMore(p.kidIds).file = p.file.copy()
	p.importPath(d)
	p.modules.push(p.nodes[d].text2(p.kidIds).copy())
	d

# `from json import parse, encode as write`: those names of the module, read bare in this file
# (in parentheses over several lines); the module itself is not named (text2 "")
fn parseFromImport(mut p Parser):
	start = p.adv()
	d = p.mk(nImportDecl, start.line, start.col)
	p.nodes[d].nodeMore(p.kidIds).file = p.file.copy()
	p.importPath(d)
	p.nodes[d].setText2(p.kidIds, "")
	p.expectTok(tkImport)
	listed = p.accept(tkLparen)
	loop:
		name = p.importedName()
		local = p.importedName() if p.acceptWord(asWord) else name.copy()
		p.nodes[d].nodeMore(p.kidIds).names.push(name)
		p.nodes[d].nodeMore(p.kidIds).names2.push(local)
		if not p.accept(tkComma) or listed and p.at(tkRparen): break
	if listed:
		p.expectTok(tkRparen)
	d

fn importedName(mut p Parser):
	(p.adv() if p.at(tkUident) else p.expectTok(tkIdent)).text.copy()

# an import's dotted path, and its last segment on its own
fn importPath(mut p Parser, d NodeId):
	path = ""
	last = p.expectTok(tkIdent).text
	while p.accept(tkDot):
		path = "{path}{last}."
		last = p.expectTok(tkIdent).text
	p.nodes[d].setText(path + last)
	p.nodes[d].setText2(p.kidIds, last)

# `? E` with no value: a result type whose value side is ()
fn unitThrows(p Parser, t NodeId):
	p.nodes[t].kind == nTyResult and not p.nodes[t].types(p.kidIds).isEmpty and
		p.nodes[p.nodes[t].types(p.kidIds)[0]].kind == nTyName and
		p.nodes[p.nodes[t].types(p.kidIds)[0]].text == "()"

# a top-level binding: a constant (an expression evaluated where it is used), or with `mut`
# a module variable (storage initialised before main, shared by every function and thread)
fn parseConst(mut p Parser, isPub bool, isMut bool):
	n = p.adv()
	if n.text in circleWords:
		p.parseError(n, compileError("LanguageConstant", [n.text.copy()]))
	if p.aliasOf(n.text) >= 0:
		p.parseError(n, compileError("AliasRebound", ["{n.text}"]))   # `name = v` would set what it names
	d = p.mk(nConstDecl, n.line, n.col)
	p.nodes[d].setText2(p.kidIds, n.text.copy())   # the constant's name, kept as written
	p.nodes[d].setText(n.text.copy())
	p.nodes[d].nodeMore(p.kidIds).file = p.file.copy()
	if isPub:
		p.nodes[d].flags = flagPub
	if isMut:
		p.nodes[d].flags |= flagMut
	if not p.at(tkEq):
		p.nodes[d].nodePart(p.kidIds).types.push(p.parseType())
	if isMut and isGpuFile(p.file) and p.bareArrayDecl(d):
		return d   # `mut a T[N]` of a GPU file: a compute group's memory, given no value
	if p.bareArrayDecl(d):
		p.nodes[d].kind = nLet   # `a T[N]`: the elements come by assignment, in the program's statements
		return d
	p.expectTok(tkEq)
	madeKid = p.tupleValue(n)
	p.nodes[d].pushKid(p.kidIds, madeKid)
	d

fn parseDecl(mut p Parser):
	if p.at(tkIdent) and p.cur().text == testWord and p.kindAt(1) == tkStr: return p.parseTestDecl()
	isPub = p.accept(tkPub)
	if p.at(tkImport): return p.parseImport()
	if p.at(tkIdent) and p.cur().text == fromWord and p.kindAt(1) == tkIdent:
		return p.parseFromImport()
	if p.at(tkIdent) and p.cur().text == boundWord and p.kindAt(1) == tkUident:
		return p.parseBoundDecl(isPub)
	if p.at(tkShared) or p.at(tkType): return p.parseTypeDecl(isPub)
	if p.accept(tkExtern):
		if p.at(tkType):
			# `extern type Name { ... }`: a structure laid out as C has it, for a system call
			d = p.parseTypeDecl(isPub)
			p.nodes[d].flags |= flagExtern
			return d
		# `extern fn Name(params) Ret` is a function of the operating system, from kernel32
		# unless a DLL is named: `extern "ws2_32.dll" fn socket(...)`; `extern loaded fn` has
		# its address given while the program runs (bindExtern), the DLL left empty, and may
		# name the symbol it is found by when that differs from its own name (one function
		# declared twice over different lists: `extern loaded "RtlMoveMemory" fn ...`), as a
		# library's may (`extern "libc.so" "__system_property_get" fn systemProperty(...)`)
		dll = "kernel32.dll"
		symbol = ""
		if p.at(tkStr):
			dll = p.adv().text
			if p.at(tkStr): symbol = p.adv().text
		elif p.at(tkIdent) and p.cur().text == loadedWord:
			p.adv()
			dll = ""
			if p.at(tkStr):
				symbol = p.adv().text
		f = p.parseFnDecl(isPub, false, true)
		p.nodes[f].nodeMore(p.kidIds).names2.push(dll)
		if symbol != "":
			p.nodes[f].nodeMore(p.kidIds).names2.push(symbol)
		return f
	isMut = p.accept(tkMut)
	if p.at(tkFn) and not isMut: return p.parseFnDecl(isPub, false, false)
	if p.at(tkIdent): return p.parseConst(isPub, isMut)
	p.parseError(p.cur(), compileError("ExpectedDeclaration", ["{tokKindName(p.kind())}"]))
	0

# `name T`, `name T[N]`, `name ref T`, `name mut ref T`: a binding with its type written
fn typedLetAhead(p Parser):
	# a name, then a size in brackets and a type, the fixed array's old form: a binding, so that
	# its type names the new one
	oldArray = p.kindAt(1) == tkLbracket and p.kindAt(2) == tkInt and
		p.kindAt(3) == tkRbracket and (p.kindAt(4) == tkIdent or p.kindAt(4) == tkUident)
	p.at(tkIdent) and
		(
			p.kindAt(1) == tkIdent or p.kindAt(1) == tkUident or p.kindAt(1) == tkRef or
				(p.kindAt(1) == tkMut and p.kindAt(2) == tkRef) or oldArray or
				p.kindAt(1) == tkLbrace or p.parenTypeAhead()
		)

# `name (A, B)[]` or `name (fn(i64) i64)[]`: a type in parentheses with its brackets after,
# apart from the name (`f(x)[0]` is an index of a call)
fn parenTypeAhead(p Parser):
	if p.kindAt(1) != tkLparen or p.toks[p.pos + 1].col <= p.cur().col + p.cur().text.len:
		return false
	i = p.closerOf(p.pos + 1)
	i >= 0 and i + 1 < p.toks.len and p.toks[i + 1].kind == tkLbracket

# whether the top-level line ahead is a statement of the program: not a declaration, not a
# binding (`name = v` is an assignment when the file bound name before it)
fn stmtAhead(p Parser, items NodeId[]):
	k = p.kind()
	if k in [tkPub, tkImport, tkShared, tkType, tkExtern, tkMut, tkFn]: return false
	if k != tkIdent: return true
	word = p.cur().text
	if word == fromWord and p.kindAt(1) == tkIdent: return false
	if word == testWord and p.kindAt(1) == tkStr or
		(word == boundWord or word == "impl") and p.kindAt(1) == tkUident:
		return false
	if word == "_" or p.wordStatementAhead(expectWord): return true
	if p.kindAt(1) == tkEq:
		return items.any(p.nodes[it].kind == nConstDecl and p.nodes[it].text == word)
	not p.typedLetAhead()

# Parses one file into the shared arena; returns its declaration nodes, none when it said an
# error. A file's top-level statements are its program: the function main, in their order
# (programOf).
pub fn parseProgram(move toks Tok[], file str, mut nodes Node[], mut kidIds NodeLists) NodeId[]?:
	notes = ParseNotes()
	decls = parseNoted(toks, file, nodes, kidIds, notes)
	notes.report()
	notes.apply(0, file)
	decls

# parseProgram's parse with what it tells in notes (its errors included) and nothing printed or
# written outside the call, so a job may parse
pub fn parseNoted(
	move toks Tok[],
	file str,
	mut nodes Node[],
	mut kidIds NodeLists,
	mut notes ParseNotes
) NodeId[]?:
	# the parser owns the arena while it works and hands it back at the end
	# the parser keeps its own file name (every declaration node gets a copy)
	p = Parser(toks, pos = 0, file = file.copy(), nodes = move nodes, kidIds = move kidIds)
	items = []   # declarations and statements, in order
	stmts = 0
	p.skipNL()
	while not p.at(tkEof):
		if p.partsAhead():
			items.push(p.parseParts())
		elif p.useAhead():
			if items.any(p.nodes[it].kind != nImportDecl):
				p.parseError(p.cur(), compileError("UseNotFirst", []))
			flags = p.parseUse()
			p.fileOptions |= flags
		elif p.aliasAhead():
			p.parseAlias()   # to the file's end
		elif p.stmtAhead(items):
			items.push(p.parseStmt())
			stmts += 1
		else:
			d = p.parseDecl()
			items.push(d)
			items.extend(p.blockMethods)
			p.blockMethods.clear()
			if p.nodes[d].kind == nLet: stmts += 1   # a bare array: a statement of the program
		p.skipNL()
	if p.stopped:
		nodes = p.nodes
		kidIds = p.kidIds
		notes = p.notes
		return none
	p.importMarkup(items)
	decls = items if stmts == 0 else p.programOf(items)
	nodes = p.nodes
	kidIds = p.kidIds
	notes = p.notes
	decls

# the errors the notes hold said, in the order they were found
pub fn report(notes ParseNotes):
	for said in notes.said:
		errorAtFile(said.file, said.line, said.col, said.msg)

# what the notes tell written where the compiler keeps it: the calls of `shader` and `compute`,
# the bodies of number functions, the files embedded, their node ids moved on by start
pub fn apply(notes ParseNotes, start i64, file str):
	for call in notes.shaderCalls:
		noteShaderCall(NodeId(i64(call) + start), file)
	for i in 0..notes.numberBodies.len / 2:
		numberBodies[NodeId(i64(notes.numberBodies[2 * i]) + start)] =
			NodeId(i64(notes.numberBodies[2 * i + 1]) + start)
	for e in notes.embedded:
		noteSourceParsed(e.path, e.text)

# a file's text lexed and parsed: its declarations, none when it said an error
pub fn parseSource(text str, file str, mut nodes Node[], mut kidIds NodeLists) NodeId[]?:
	parseProgram(try lex(text, file), file, nodes, kidIds)

# source the compiler wrote parsed (lexInternal): an error in it is the compiler's own, which
# stops it
pub fn parseInternal(text str, file str, mut nodes Node[], mut kidIds NodeLists) NodeId[]:
	toks = lexInternal(text, file) ?? fail("zap: the compiler wrote {file} wrong")
	parseProgram(toks, file, nodes, kidIds) ?? fail("zap: the compiler wrote {file} wrong")

# A file with statements: they are the program, the function main, in their order with the
# bindings among them. A binding the module needs (moduleBindings) is the module's: a constant
# when its value is a literal, else assigned where it stands by a statement of main (flagOrdered:
# its storage is zero before), so its value may come from args or a file. The others are
# main's own.
fn programOf(mut p Parser, items NodeId[]):
	decls = []
	first = items.find(p.nodes[it].kind < nParam) ?? items[0]
	body = p.mk(nBlock, p.nodes[first].line, p.nodes[first].col)
	stmts = []
	module = p.moduleBindings(items)
	for i, item in items:
		k = p.nodes[item].kind
		if k == nConstDecl and not module[i]:
			p.nodes[item].kind = nLet   # main's own: a binding of its body
			p.nodes[item].flags &= flagMut
			p.addStmt(stmts, item)
		elif k == nConstDecl and not p.constantValue(p.nodes[item].kids(p.kidIds)[0]):
			p.nodes[item].flags |= flagOrdered
			value = p.nodes[item].kids(p.kidIds)[0]
			madeKid = cloneTree(p.nodes, p.kidIds, value)
			p.nodes[item].setKid(p.kidIds, 0, madeKid)   # the declaration keeps a copy for its type
			target = p.mk(nIdent, p.nodes[item].line, p.nodes[item].col)
			p.nodes[target].setText(p.nodes[item].text.copy(), p.nodes[item].name)
			a = p.mk(nAssign, p.nodes[item].line, p.nodes[item].col)
			p.nodes[a].flags = flagInit
			p.nodes[a].pushKid(p.kidIds, target)
			p.nodes[a].pushKid(p.kidIds, value)
			p.addStmt(stmts, a)
			decls.push(item)
		elif k >= nParam:
			decls.push(item)
		else:
			p.addStmt(stmts, item)
	p.nodes[body].setKids(p.kidIds, stmts)
	p.expandRegArrays(body, [])   # main's register arrays, as any function's after its parse
	main = p.mk(nFnDecl, p.nodes[first].line, p.nodes[first].col)
	p.nodes[main].setText("main")
	p.nodes[main].flags |= p.fileOptions   # the file's statements are in its scope too
	p.nodes[main].nodeMore(p.kidIds).file = p.file.copy()
	p.nodes[main].nodePart(p.kidIds).sub.push(body)
	decls.push(main)
	decls

# which of the items are bindings the module keeps: the public ones, those a function, a type or
# a test names, and those the value of such a binding names (what a module binding reads is the
# module's too, assigned before it)
fn moduleBindings(p Parser, items NodeId[]):
	module = items.map(p.nodes[it].kind == nConstDecl and p.nodes[it].hasFlag(flagPub))
	fields = []   # the fields the file's types declare: bare in their methods
	for item in items:
		if p.nodes[item].kind == nStructDecl:
			for f in p.nodes[item].kids(p.kidIds):
				if p.nodes[f].kind == nFieldDecl: fields.push(p.nodes[f].text.copy())
	grew = true
	while grew:
		grew = false
		for i, item in items:
			if p.nodes[item].kind != nConstDecl or module[i]: continue
			name = p.nodes[item].text
			for j, o in items:
				if j == i or p.nodes[o].kind < nParam or
					p.nodes[o].kind == nConstDecl and not module[j]:
					continue
				if p.mentionsIdent(o, name, fields, p.nodes[item].hasFlag(flagMut)):
					module[i] = true
					grew = true
					break
	module

# whether e names the name: reads it, or changes it with `name op= v` (a module variable's), or,
# when the name is a `mut` binding's (assigned), with a `name = v` the rest of its block never
# reads (as a local of its own it would be unused). Else a `name = v` binds a local of its own,
# the name's from there to the block's end; a function or a lambda whose parameter takes the
# name, and a loop whose variable does, shadow it too (the loop's range is still read).
fn mentionsIdent(p Parser, e NodeId, name str, fields str[], assigned bool) bool:
	k = p.nodes[e].kind
	if k == nIdent: return p.nodes[e].text == name
	if k == nImplDecl and name in fields: return false   # a method names its fields bare
	if k == nFnDecl and
		p.nodes[e].kids(p.kidIds).any(p.nodes[it].kind == nParam and p.nodes[it].text == name):
		return false
	if k == nLambda and name in p.nodes[e].names(p.kidIds): return false
	if k == nFor and p.nodes[e].text == name:
		return p.nodes[e].kids(p.kidIds).any(p.mentionsIdent(it, name, fields, assigned))
	kids = p.nodes[e].kids(p.kidIds).copy()
	for i, kid in kids:
		if p.nodes[kid].kind == nLet and p.nodes[kid].text == name:
			if p.nodes[kid].hasFlag(flagCompound) or
				assigned and not p.nodes[kid].hasFlag(flagMut) and
				p.nodes[kid].types(p.kidIds).isEmpty and
				not kids[i + 1..].any(p.mentionsIdent(it, name, fields, false)):
				return true
			return p.nodes[kid].kids(p.kidIds).any(p.mentionsIdent(it, name, fields, assigned))
		if p.mentionsIdent(kid, name, fields, assigned): return true
	p.nodes[e].sub(p.kidIds).any(p.mentionsIdent(it, name, fields, assigned))

# a value known when compiling: a literal, arithmetic of literals, a list or a map of them
fn constantValue(p Parser, v NodeId) bool:
	k = p.nodes[v].kind
	if k in [nInt, nFloat, nStr, nBool, nNone]: return true
	if k in [nUnary, nBinary, nArray, nMapLit, nStructLit, nInterp]:
		return p.nodes[v].kids(p.kidIds).all(p.constantValue(it))
	false
