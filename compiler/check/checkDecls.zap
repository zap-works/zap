# The checker's lookup of declarations, runtime methods and impls (check.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# an error found in a round of a body, not reported yet
type PendingError:
	file str
	line i64
	col i64
	message str

# the round's errors reported
# whether an error was found in the file: reported, or still held
fn hasErrorsIn(c Checker, file str):
	file in filesWithErrors or c.pending.any(.file == file)

pub fn reportPending(mut c Checker):
	for e in c.pending:
		errorAtFile(e.file, e.line, e.col, e.message)
	c.pending.clear()

# ---------- declarations ----------

fn isTypeDeclKind(k i64):
	k == nStructDecl or k == nEnumDecl

fn declIsPub(c Checker, d NodeId):
	k = nodes[d].kind
	if k in [nFnDecl, nStructDecl, nEnumDecl, nConstDecl]: return nodes[d].hasFlag(flagPub)
	true

fn kindMatches(dk i64, kind i64):
	if kind == nStructDecl or kind == nEnumDecl: return isTypeDeclKind(dk)
	dk == kind

# The module alias of a name the compiler wrote: a global name, found as such from any module
# (the main module's names carry no prefix, so `Point` there is not another module's `Point`),
# and a name of the runtime (a tuple is the runtime's Tuple2 whatever the program declares).
globalAlias = "$global"
runtimeAlias = "$rt"

# global lookups (by globally unique name, as the backend sees them)
fn findTypeDecl(c Checker, name str):
	c.findDeclByGlobalName(nStructDecl, name)

fn findFunc(c Checker, name str):
	c.findDeclByGlobalName(nFnDecl, name)

# every function's and method's declaration
fn functionDecls(c Checker):
	out = []
	for d in c.decls:
		k = nodes[d].kind
		if k == nFnDecl:
			out.push(d)
		elif k == nImplDecl:
			out.extend(nodes[d].kids(kidIds))
	out

# the methods of str with a rule of their own, and their runtime functions
strMethodRuntime = [
	("len", "strLen"),
	("isEmpty", "strIsEmpty"),
	("slice", "strWindow")]

fn strMethodRt(m str):
	pairedName(strMethodRuntime, m)

# the receivers of the runtime's methods, by the prefix of their functions (listPush is xs.push)
runtimeReceivers = [
	("list", "T[]"),
	("str", "str"),
	("map", r"{K: V}"),
	("f64", "f64"),
	("f32", "f32")
]

fn capital(m str):
	m[..1].upper() + m[1..]

# the names the runtime's function of method m may have, one per receiver (listM, strM...; a str
# method of strMethodRuntime's its own)
fn rtMethodNames(m str):
	renamed = strMethodRt(m)
	names = []
	for (prefix, _) in runtimeReceivers:
		names.push(renamed.copy() if prefix == "str" and renamed != "" else prefix + capital(m))
	names

# the runtime's functions of the method m of a list, a map, a str or a float, those that exist
fn rtMethodDecls(c Checker, m str):
	out = []
	for name in rtMethodNames(m):
		if c.findDeclInModule("rt", nFnDecl, name) is d: out.push(d)
	out

# whether the method m of a list, a map or a str changes its receiver: its runtime function takes the
# receiver mut (take and intoStr move the value out of it). The one list of such methods, read
# from the runtime's declarations.
fn methodIsMutating(c Checker, m str):
	if m == "take" or m == "intoStr" or m.startsWith("store") and i64.parse(m[5..]) != none:
		return true   # (xs.store4(i, v): an intrinsic of lists)
	c.rtMethodDecls(m).any(c.takesMutFirst(it))

# whether the function fd takes its first parameter mut
fn takesMutFirst(c Checker, fd NodeId):
	not nodes[fd].kids(kidIds).isEmpty and nodes[nodes[fd].kids(kidIds)[0]].ival == modeMut

# the runtime's function of method m of a list, a map or a str (the receiver's kind otk), or none
fn rtMethodDecl(c Checker, otk i64, m str) NodeId?:
	name = ""
	if otk == tList:
		name = "list{capital(m)}"
	elif otk == tMap:
		name = "map{capital(m)}"
	elif otk == tStr:
		name = strMethodRt(m) if strMethodRt(m) != "" else "str{capital(m)}"
	none if name == "" else c.findDeclInModule("rt", nFnDecl, name)

# whether the runtime's function of method m of a list or a map (otk) takes its parameter k `move`
fn rtTakesMove(c Checker, otk i64, m str, k i64):
	if otk != tList and otk != tMap: return false
	fd = c.rtMethodDecl(otk, m) ?? return false
	k < nodes[fd].kids(kidIds).len and nodes[nodes[fd].kids(kidIds)[k]].ival == modeMove

# whether the method m of a List, Map or str only makes a value: a step of a pipeline but each
# and sortBy, one of the checker's own (slice, window, bytes, copy, length, lines), or the
# runtime's function that reads its receiver and gives a result
fn methodMakesValue(c Checker, m str):
	if m in pipelineSteps: return m != "sortBy"
	if m in ["slice", "window", "bytes", "copy", "len", "lines"]: return true
	c.rtMethodDecls(m).any(fd:
		not nodes[fd].kids(kidIds).isEmpty and nodes[nodes[fd].kids(kidIds)[0]].ival != modeMut and
			not nodes[fd].types().isEmpty
	)

# whether the method m of a List, Map or str lends into its receiver: its runtime function
# returns a reference (first, get, trim...), or it is one of the checker's own forms that do
# (slice, window, bytes)
fn methodLends(c Checker, m str):
	if m in ["slice", "window", "bytes"]: return true
	# the result as written (ref T, ref T?): resolving it would need the call's T
	c
		.rtMethodDecls(m)
		.any(fd: not nodes[fd].types().isEmpty and (nodes[nodes[fd].types()[0]].kind == nTyRef or
				nodes[nodes[fd].types()[0]].kind == nTyOpt and
				nodes[nodes[nodes[fd].types()[0]].types()[0]].kind == nTyRef))

fn findDeclInModule(c Checker, moduleId str, kind i64, localName str):
	c.firstIndexed(c.declsByLocal, kind, moduleId, localName, true)

fn findDeclByGlobalName(c Checker, kind i64, name str):
	c.firstIndexed(c.declsByName, kind, "", name, false)

# The `import a.b` (qualified) declaration of module m whose alias is `alias` (a together
# check's source's, else its program's: ownModules).
fn findImportByAlias(c Checker, m i64, alias str) NodeId?:
	if m < 0: return none
	if c.modules[m].imports.find(nodes[it].text2() == alias) is imp:
		c.noteImportUse(alias)   # the file reads the module: zap fmt keeps or writes its line
		return imp
	if c.modules[m].unit: return c.findImportByAlias(moduleIndex(c.modules, ""), alias)
	none

# The modules whose declarations the module being checked sees as its own, private ones too:
# itself, and for a together check's source (loadUnits) then the test file's, whose
# declarations go before it (spec 13.1)
fn ownModules(c Checker):
	if c.curMod < 0: return [""]
	m = c.modules[c.curMod]
	[m.id.copy(), ""] if m.unit else [m.id.copy()]

# whether the error of that name is said where it is found: an unused value or binding is no
# error in a together check's source, unless its test expects that very error
fn reportsUnused(c Checker, name str):
	c.curMod < 0 or not c.modules[c.curMod].unit or c.modules[c.curMod].expects == kebabCase(name)

# (a, b) as written: the checker's struct literal of fields _0, _1... in order
fn isTupleLiteral(c Checker, maybeE NodeId?):
	e = maybeE ?? return false
	nodes[e].kind == nStructLit and not nodes[e].names().isEmpty and nodes[e].names()[0] == "_0"

fn kindWord(kind i64):
	if kind == nFnDecl: return "function"
	if kind == nConstDecl: return "constant"
	if kind == nBoundDecl: return "bound"
	"type"

# Resolves a name written in the source: qualified (alias.Name, alias != "") or bare (this
# module, then the file's from-imports). A hit in another module must be `pub`. Also accepts an
# already-resolved global name, so re-checking a generic instance works. Reports nothing when not found.
fn lookupDecl(mut c Checker, kind i64, alias str, name str, line i64, col i64):
	c.declOfAlias(c.lookupDeclAsWritten(kind, alias, name, line, col))

# the declaration d, or for `type Name = T` of a struct or an enum that of T (a literal's)
fn declOfAlias(c Checker, maybeD NodeId?) NodeId?:
	d = try maybeD
	if not nodes[d].hasFlag(flagTypeAlias): return d
	# resolveTypeAliases resolved every one before
	t = nodes[d].ty
	k = kindOf(tys, t)
	declOf(tys, t) if k == tStruct or k == tEnum else d

fn lookupDeclAsWritten(mut c Checker, kind i64, alias str, name str, line i64, col i64) NodeId?:
	if alias == globalAlias: return c.findDeclByGlobalName(kind, name)
	if alias == runtimeAlias: return c.findDeclInModule("rt", kind, name)
	if kind == nStructDecl and name.startsWith("$Ty"):
		t = c.derivedTypeNamed(name)
		if t is mut t and tys[t].kind == tBox:
			t = innerOf(tys, t)
		if t is t and (tys[t].kind == tStruct or tys[t].kind == tEnum): return declOf(tys, t)
		if t is t and tys[t].kind == tInt and tys[t].defined is d: return d   # $Ty3(n)
	if alias != "":
		imp = c.findImportByAlias(c.curMod, alias) ??
			return c.noneReported(line, col, unknownModule(alias))
		d = c.findDeclInModule(nodes[imp].text, kind, name) ??
			return c.noneReported(
				line,
				col,
				compileError("NotInModule", ["{alias}", "{kindWord(kind)}", "{name}"])
			)
		if not c.declIsPub(d):
			c.errorAt(line, col, compileError("PrivateName", ["{name}", "{alias}"]))
		return d
	for own in c.ownModules():
		if c.findDeclInModule(own, kind, name) is d: return d
	if c.importedBare(kind, name) is imported: return imported
	d2 = c.findDeclByGlobalName(kind, name)
	if d2 is d2 and c.seesByGlobalName(kind, d2): return d2
	# public declarations of the runtime (types such as TcpConn) are visible everywhere; the
	# builtins keep their own typing
	if kind == nFnDecl and builtinAt(name) >= 0: return none
	r = c.findDeclInModule("rt", kind, name)
	# the code the compiler derives (printing, encoding) calls the runtime's private helpers
	if r is r and (c.declIsPub(r) or c.curMod >= 0 and c.modules[c.curMod].id == "derive"): return r
	none

# Whether a bare name that matched declaration d only by its global name means d: a name
# already resolved (a generic instance checked again). A declaration of the main module, whose
# global names carry no prefix, is not seen from another module: the runtime's `total = n` binds
# a local of its own even when the program has a module variable `total`, and the derived code's
# Cursor is the runtime's even when the program declares one (a type the compiler names for
# another module carries globalAlias).
fn seesByGlobalName(c Checker, kind i64, d NodeId):
	if c.curMod < 0 or nodes[d].text != nodes[d].text2(): return true
	nodes[d].mod() in c.ownModules()

fn lookupTypeDecl(mut c Checker, alias str, name str, line i64, col i64) NodeId?:
	c.lookupDecl(nStructDecl, alias, name, line, col)

# `alias.Name` where alias is an imported module: rewrites the node into an identifier
# carrying the global name. Returns 1 when rewritten, 0 when not a module reference,
# -1 when it was a module reference that failed to resolve (already reported).
fn normalizeQualified(mut c Checker, e NodeId):
	if nodes[e].kind != nField or nodes[e].hasFlag(flagSafe): return 0
	obj = nodes[e].kids(kidIds)[0]
	if nodes[obj].kind != nIdent or c.lookupVar(nodes[obj].text) >= 0: return 0
	alias = nodes[obj].text
	if alias == globalAlias:
		# the code the compiler writes names any module's function by its global name
		gd = c.findDeclByGlobalName(nFnDecl, nodes[e].text) ?? return 0
		nodes[e].kind = nIdent
		nodes[e].text = nodes[gd].text.copy()
		nodes[e].setText2(globalAlias)
		nodes[e].setKids(kidIds, [])
		nodes[e].flags = 0
		return 1
	imp = c.findImportByAlias(c.curMod, alias)
	# `rt.name` is the runtime's, which a declaration of the module named the same may hide;
	# `$rt.name`, which only the compiler writes, reaches its private ones too
	compilers = alias == runtimeAlias
	if imp == none and alias != "rt" and not compilers: return 0
	name = nodes[e].text
	path = "rt"
	if imp is imp:
		path = nodes[imp].text.copy()
	found = c.findDeclInModule(path, nFnDecl, name) ??
		c.findDeclInModule(path, nStructDecl, name) ??
		c.findDeclInModule(path, nConstDecl, name)
	# both messages first: alias and name borrow the nodes changed below
	d = found ?? return c.notInModuleBare(e, alias, name, path)
	if not c.declIsPub(d) and not compilers and
		not (path == "rt" and c.curMod >= 0 and c.modules[c.curMod].std):
		errorAt(
			c,
			nodes[e].line,
			nodes[e].col,
			compileError("PrivateName", ["{name}", "{alias}"])
		)
	nodes[e].kind = nIdent
	nodes[e].text = nodes[d].text.copy()
	nodes[e].setKids(kidIds, [])
	nodes[e].flags = 0
	1

# `alias.name` that names nothing of the module: reported, the node of the error type; -1
fn notInModuleBare(mut c Checker, e NodeId, alias str, name str, path str):
	c.errorAt(
		nodes[e].line,
		nodes[e].col,
		compileError("NotInModuleBare", ["{alias}", "{name}"])
	)
	nodes[e].ty = tyError
	-1

# the error reported at line:col, and the error type (`t = find() ?? return c.errorTyped(...)`)
fn errorTyped(mut c Checker, line i64, col i64, message str):
	c.errorAt(line, col, message)
	tyError

# the error reported at line:col, and none (`x = find() ?? return c.noneReported(...)`)
fn noneReported(mut c Checker, line i64, col i64, message str) NodeId?:
	c.errorAt(line, col, message)
	none

# The (non-template) impl of a type that holds its method m, if any: a type's methods may sit in
# several, each with its own type parameters.
# whether the impl block holding method m of typeName takes type parameters of its own
fn implIsGeneric(c Checker, typeName str, m NodeId):
	c.implIsGenericOf(c.findImplDecl(typeName, m))

# whether the impl block d, if any, takes type parameters of its own
fn implIsGenericOf(c Checker, maybeD NodeId?):
	d = maybeD ?? return false
	not nodes[d].names2().isEmpty

# the impl holding method m of typeName, when there is m
fn findImplDeclOf(c Checker, typeName str, maybeM NodeId?):
	c.findImplDecl(typeName, try maybeM)

fn findImplDecl(c Checker, typeName str, m NodeId) NodeId?:
	if typeName == "": return none
	for d in c.implsOf(typeName):
		if nodes[d].names().isEmpty and m in nodes[d].kids(kidIds): return d
	none

fn findMethod(c Checker, typeName str, methodName str) NodeId?:
	for d in c.implsOf(typeName):
		for m in nodes[d].kids(kidIds):
			if nodes[m].text == methodName: return m
	none

# the impls of the type named typeName, in the order of decls (found by the index by name)
fn implsOf(c Checker, typeName str) Seq<NodeId>:
	at = c.declsByName.get(typeName) ?? return
	for pos in at:
		d = c.decls[pos]
		if nodes[d].kind == nImplDecl and nodes[d].text == typeName: yield d

# the child of a declaration with that name: a variant of an enum, a field of a struct
fn kidNamed(c Checker, d NodeId, name str) NodeId?:
	nodes[d].kids(kidIds).find(nodes[it].text == name)

# whether the enum d gives its variants integers (`Add = 1`: all of them or none, see the parser)
fn enumHasValues(c Checker, d NodeId):
	not nodes[d].kids(kidIds).isEmpty and nodes[nodes[d].kids(kidIds)[0]].text2() != ""

fn fieldIndexOf(c Checker, structd NodeId, name str):
	fields = nodes[structd].kids(kidIds)
	fields.findIndex(nodes[it].text == name) ?? -1

# A `mut` parameter is passed by reference: a struct, a fixed array, a list or a map.
fn isMutPassable(c Checker, t TypeId):
	k = c.tKind(t)
	si = c.standInIndex(t)
	if si >= 0: return not c.declaredBounds(si).isEmpty   # a type with methods
	k in [tStruct, tArray, tList, tMap, tError]

# Switches the resolution context to the module (and file) that owns a declaration.
fn enterModuleOf(mut c Checker, d NodeId):
	c.curMod = moduleIndex(c.modules, nodes[d].mod())
	c.curFile = nodes[d].file().copy()

# The result type of a function node: as written, or as its body gives it (results.zap), else
# unit.
fn fnRetType(mut c Checker, fnd NodeId) TypeId:
	if noting: c.noteResultCall(fnd)
	if c.resultState.get(fnd) is state and not c.askResult(fnd, state): return tyError
	c.writtenResult(fnd)

fn writtenResult(mut c Checker, fnd NodeId):
	if not nodes[fnd].types().isEmpty: return c.resolveType(nodes[fnd].types()[0])
	tyUnit

# ---------- type resolution ----------

fn primType(n str) TypeId?:
	if n.len < 2 or n.len > 4:
		return none   # every built-in name has 2 to 4 bytes
	c0 = n[0]
	if c0 != 'i' and c0 != 'u' and c0 != 'f' and c0 != 'b' and c0 != 's' and c0 != '(' and
		c0 != 'n':
		return none   # nor starts otherwise
	if primTypes.find(.name == n) is p: return p.id
	none
