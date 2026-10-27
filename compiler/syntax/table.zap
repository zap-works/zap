# Table<T>, a list kept as columns (spec 7): a struct the checker makes for T, one List per
# field of T under the field's name (the column `t.f` is that field), and functions written as
# source into the `derive` module for what goes through whole elements. The checker writes a
# table's uses over as uses of its columns, so the backend sees lists and calls only:
#   t.len, t.isEmpty           the first column's
#   t[i].f, r.f (r a row)      t.f[i]
#   t[i], r                    $tget: the element, a copy (`move t[i]`: $ttake)
#   t[i] = v                   $tset
#   t.push(v), t.pop()...      $tpush, $tpop...: the list's method on every column
#   t.map(f), t.filter(f)...   (0..t.len).map(f) with f's element a row of t (stepInPlace);
#                              a table not named: $trows(t).map(f)
#   [a, b] where a table goes  $tfrom([a, b])
#   r = mut ref t[i]           r a row: i under a hidden name, each r.f a column's element
#   for r in t                 for $i in 0..t.len with r = mut ref t[$i]
#   f(t[i]), f(r), r.f()       f's row instance f$row(t, i), its parameter a row (rowCall)

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# what a row names: the table (written again at each use) and its index's hidden name
type TableRow:
	table NodeId
	index str

# a function's row instance (rowFunction) and the function, whose body it takes once that is
# checked (fillRowFunction)
type RowFunction:
	decl NodeId
	origin NodeId
	fields TypeId? = none   # a method's: the struct whose fields its body names bare

# the steps of a pipeline a table takes, through copies of its elements
tableSteps = [
	"map",
	"filter",
	"sum",
	"count",
	"any",
	"all",
	"find",
	"findIndex",
	"reduce",
	"minBy",
	"maxBy",
	"sortedBy",
	"flatMap"]

# the methods a table has of its own, each the derived function $t<name> (a `$` name is the
# checker's: the forms it writes for t[i] and the steps)
tableMethods = [
	"push",
	"pop",
	"insert",
	"remove",
	"swap",
	"clear",
	"truncate",
	"reserve",
	"$get",
	"$set",
	"$take",
	"$rows",
	"$at"]

fn isTable(c Checker, maybeT TypeId?):
	t = maybeT ?? return false
	tys[t].kind == tStruct and nodes[declOf(tys, t)].hasFlag(flagTable)

# the element type of the table type t
fn tableElement(c Checker, t TypeId?):
	nodes[declOf(tys, t)].ints()[0]

# the derived function of the table declared by d that does `method`
fn tableFunction(c Checker, d NodeId, method str):
	name = method[1..].copy() if method.startsWith("$") else method.copy()
	c.findDeclInModule("derive", nFnDecl, "$t{name}{d}") ?? fail("table {d} has no {name}")

# The type Table<elem>, made on first use with its functions; tyError when elem cannot be one
# (reported).
fn tableType(mut c Checker, elem TypeId, line i64, col i64):
	if c.tKind(elem) == tError: return tyError
	if c.tKind(elem) != tStruct or tys[elem].param != "" or
		nodes[declOf(tys, elem)].kids(kidIds).isEmpty:
		errorAt(
			c,
			line,
			col,
			compileError("TableElement", ["{c.showTy(elem)}"])
		)
		return tyError
	name = "Table_{identChars(typeMangled(tys, elem))}"
	found = c.findTypeDecl(name)
	if found is found: return tyOfDecl(tys, nodes, found)
	sd = declOf(tys, elem)
	for f in nodes[sd].kids(kidIds):
		if readsAsField(nodes[f].text):
			c.errorAt(
				line,
				col,
				compileError("TableFieldName", ["{c.showTy(elem)}", "{nodes[f].text}"])
			)
			return tyError
	# the fields' types are resolved where the struct is declared
	savedMod = c.curMod
	savedFile = c.curFile.copy()
	c.enterModuleOf(sd)
	fts = c.fieldTypes(sd)
	c.curMod = savedMod
	c.curFile = savedFile
	d = newNode(nodes, kidIds, nStructDecl, line, col, text = name)
	nodes[d].setText2("Table<{c.showTy(elem)}>")
	nodes[d].nodeMore().mod = "derive"
	nodes[d].nodeMore().file = "<derived>"
	nodes[d].flags = flagTable
	nodes[d].nodeMore().ints = [elem]
	for i, ft in fts:
		inner = newNode(nodes, kidIds, nTyName, line, col, text = "$param{ft}")
		list = newNode(nodes, kidIds, nTyName, line, col, text = "List")
		nodes[list].nodePart().types = [inner]
		empty = newNode(nodes, kidIds, nArray, line, col)
		f = newNode(
			nodes,
			kidIds,
			nFieldDecl,
			line,
			col,
			text = nodes[nodes[sd].kids(kidIds)[i]].text.copy()
		)
		nodes[f].nodePart().types = [list]
		nodes[f].setKids(kidIds, [empty])
		nodes[d].pushKid(kidIds, f)
	c.deriveModule()
	c.addDecl(d)
	t = tyOfDecl(tys, nodes, d)
	c.addDerivedText(c.tableSource(d, t, elem, fts))
	t

# The functions of the table declared by d (type t, of elements elem with fields of types fts).
fn tableSource(mut c Checker, d NodeId, t TypeId, elem TypeId, fts TypeId[]):
	tab = tyName(c.noteDerive(t, 0))
	el = tyName(c.noteDerive(elem, 0))
	names = nodes[d].kids(kidIds).map(nodes[it].text.copy())
	# a part that owns memory moves out of the element given, and is copied out of a column
	given = (0..fts.len).map("v.{names[it]}" if c.isPlainType(fts[it]) else "move v.{names[it]}")
	read = (0..fts.len).map(
		"t.{names[it]}[i]" if c.isPlainType(fts[it]) else "t.{names[it]}[i].copy()"
	)
	moved = "xs[i]" if c.isPlainType(elem) else "move xs[i]"
	src = []
	# the list's method on every column: its name, parameters and arguments
	each = [
		("push", ", move v {el}", "V"),
		("insert", ", i i64, move v {el}", "i, V"),
		("swap", ", i i64, j i64", "i, j"),
		("clear", "", ""),
		("truncate", ", n i64", "n"),
		("reserve", ", n i64", "n")]
	for (m, params, args) in each:
		src.push("fn $t{m}{d}(mut t {tab}{params}):")
		for i in 0..fts.len:
			src.push("\tt.{names[i]}.{m}({args.replace("V", given[i])})")
	src.push("fn $tset{d}(mut t {tab}, i i64, move v {el}):")
	for i in 0..fts.len:
		src.push("\tt.{names[i]}[i] = {given[i]}")
	src.push("fn $tget{d}(t {tab}, i i64) {el}:")
	src.push("\t{el}({(0..fts.len).map("{names[it]} = {read[it]}").join(", ")})")
	src.push("fn $ttake{d}(mut t {tab}, i i64) {el}:")
	src.push("\t{el}({names.map("{it} = move t.{it}[i]").join(", ")})")
	src.push("fn $tremove{d}(mut t {tab}, i i64) {el}:")
	src.push("\t{el}({names.map("{it} = t.{it}.remove(i)").join(", ")})")
	src.push("fn $tpop{d}(mut t {tab}) {el}?:")
	src.push("\tif t.{names[0]}.isEmpty: return none")
	src.push("\tv = $tremove{d}(t, t.{names[0]}.len - 1)")
	src.push("\tv")
	src.push("fn $tat{d}(t {tab}, i i64?) {el}?:")
	src.push("\tat = i ?? return none")
	src.push("\t$tget{d}(t, at)")
	src.push("fn $trows{d}(t {tab}) {el}[]:")
	src.push("\tout {el}[] = []")
	src.push("\tout.reserve(t.{names[0]}.len)")
	src.push("\tfor i in 0..t.{names[0]}.len:")
	src.push("\t\tout.push($tget{d}(t, i))")
	src.push("\tout")
	src.push("fn $tfrom{d}(move xs {el}[]) {tab}:")
	src.push("\tt = {tab}()")
	src.push("\tfor i in 0..xs.len:")
	src.push("\t\t$tpush{d}(t, {moved})")
	src.push("\tt")
	"{src.join("\n")}\n"

# `[a, b]` where a table is expected: e made the table of those elements
fn tableOfList(mut c Checker, e NodeId, t TypeId) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	list = newNode(nodes, kidIds, nArray, line, col, kids = nodes[e].kids(kidIds).copy())
	from = newNode(
		nodes,
		kidIds,
		nIdent,
		line,
		col,
		text = nodes[c.tableFunction(declOf(tys, t), "from")].text.copy()
	)
	nodes[e].kind = nCall
	nodes[e].setKids(kidIds, [from, list])
	c.checkExpr(e, t)

# `Table<T>()` or `[]` where a table is expected: e made the struct literal of the empty table
fn emptyTable(mut c Checker, e NodeId, t TypeId, expected TypeId?) TypeId:
	if nodes[e].kind == nCall and nodes[e].kids(kidIds).len > 1:
		errorAt(
			c,
			nodes[e].line,
			nodes[e].col,
			compileError("TableEmpty", ["{c.showTy(t)}"])
		)
		return tyError
	nodes[e].kind = nStructLit
	nodes[e].setText(nodes[declOf(tys, t)].text.copy(), nodes[declOf(tys, t)].name)
	nodes[e].setText2(globalAlias)
	nodes[e].setKids(kidIds, [])
	nodes[e].nodeMore().names = []
	nodes[e].nodePart().types = []
	c.checkExpr(e, expected)

# `Table<T>()`: the call e, an empty table
fn checkNewTable(mut c Checker, e NodeId, expected TypeId?) TypeId:
	callee = nodes[e].kids(kidIds)[0]
	te = newNode(nodes, kidIds, nTyName, nodes[callee].line, nodes[callee].col, text = "Table")
	nodes[te].nodePart().types = nodes[callee].types().copy()
	t = c.resolveType(te)
	if t == tyError: return tyError
	c.emptyTable(e, t, expected)

# The variable named `name` in the scopes, innermost first, without noting it captured: -1 when none
fn innermostVar(c Checker, name str):
	i = c.vars.len - 1
	while i >= 0:
		if c.vars[i].name == name: return i
		i -= 1
	-1

# The type of e when it is a named place (a variable, a module variable, fields of one, and with
# `elements` an element of a list or an array), read without checking e (nothing noted);
# references and boxes seen through; none when it is no such place
fn placeType(mut c Checker, e NodeId, elements bool = false) TypeId?:
	k = nodes[e].kind
	t TypeId? = none
	if k == nIdent:
		v = c.innermostVar(nodes[e].text)
		if v >= 0:
			t = c.vars[v].ty
		else:
			cd = c.lookupDecl(
				nConstDecl,
				"",
				nodes[e].text,
				nodes[e].line,
				nodes[e].col,
				nameOf(nodes, e)
			) ??
				return none
			t = c.constTypeOf(cd)
	elif k == nDeref:
		t = c.placeType(nodes[e].kids(kidIds)[0], elements)
	elif k == nIndex and elements and nodes[nodes[e].kids(kidIds)[1]].kind != nRange:
		lt = c.placeType(nodes[e].kids(kidIds)[0], elements)
		if c.tKind(lt) != tList and c.tKind(lt) != tArray: return none
		t = innerOf(tys, lt)
	elif k == nField and nodes[e].kids(kidIds).len == 1 and nodes[e].text2() == "":
		ot = c.placeType(nodes[e].kids(kidIds)[0], elements)
		if c.tKind(ot) != tStruct: return none
		f = try c.kidNamed(declOf(tys, ot), nodes[e].text)
		t = c.resolveType(nodes[f].types()[0])
	while t is mut t and (c.tKind(t) == tRef or c.tKind(t) == tBox):
		t = innerOf(tys, t)
	t

# whether e reads a table's element (t[i], not a slice) of a table named as a place
fn isTableIndex(mut c Checker, e NodeId):
	nodes[e].kind == nIndex and nodes[nodes[e].kids(kidIds)[1]].kind != nRange and
		c.isTable(c.placeType(nodes[e].kids(kidIds)[0]))

# the row variable e names (an identifier), or -1
fn rowVar(c Checker, e NodeId):
	if nodes[e].kind != nIdent: return -1
	v = c.innermostVar(nodes[e].text)
	v if v >= 0 and c.vars[v].row >= 0 else -1

# the row variable v's index, a new identifier
fn rowIndex(mut c Checker, v i64, line i64, col i64) NodeId:
	newNode(nodes, kidIds, nIdent, line, col, text = c.rows[c.vars[v].row].index.copy())

# the row variable v's table, written again
fn rowTable(mut c Checker, v i64) NodeId:
	cloneTree(nodes, kidIds, c.rows[c.vars[v].row].table)

# The table and the index of the element `at` names, a row or t[i] (the row's written again,
# t[i]'s its own nodes); none when it names none.
fn elementPlace(mut c Checker, at NodeId) (NodeId, NodeId)?:
	v = c.rowVar(at)
	if v >= 0:
		c.vars[v].used = true
		return (c.rowTable(v), c.rowIndex(v, nodes[at].line, nodes[at].col))
	if c.isTableIndex(at): return (nodes[at].kids(kidIds)[0], nodes[at].kids(kidIds)[1])
	none

# A field read through a table's element: t[i].f or r.f (r a row), e made t.f[i]. Whether it was.
fn tableField(mut c Checker, e NodeId):
	table, index = c.elementPlace(nodes[e].kids(kidIds)[0]) ?? return false
	column = newNode(
		nodes,
		kidIds,
		nField,
		nodes[e].line,
		nodes[e].col,
		text = nodes[e].text.copy(),
		kids = [table]
	)
	nodes[e].kind = nIndex
	nodes[e].setText("")
	nodes[e].flags = 0
	nodes[e].setKids(kidIds, [column, index])
	true

# A table's whole element, t[i] or a row r, read (`$get`, a copy) or moved out (`$take`, the
# element `at` of the `move` e): e made the call of that method. Whether it was.
fn tableElementCall(mut c Checker, e NodeId, at NodeId, method str):
	table, index = c.elementPlace(at) ?? return false
	call = newNode(
		nodes,
		kidIds,
		nField,
		nodes[e].line,
		nodes[e].col,
		text = method.copy(),
		kids = [table]
	)
	nodes[e].kind = nCall
	nodes[e].setText("")
	nodes[e].ival = 0
	nodes[e].setKids(kidIds, [call, index])
	true

# A method called on a table (its receiver checked, of type t).
fn checkTableMethod(mut c Checker, e NodeId, t TypeId, expected TypeId?):
	line = nodes[e].line
	col = nodes[e].col
	m = c.calleeName(e)
	callee = nodes[e].kids(kidIds)[0]
	d = declOf(tys, t)
	if m == "copy" and c.argCount(e) == 0: return c.typed(e, t)
	if m in sizeWords:
		# the first column's size
		first = newNode(
			nodes,
			kidIds,
			nField,
			line,
			col,
			text = nodes[nodes[d].kids(kidIds)[0]].text.copy(),
			kids = [nodes[callee].kids(kidIds)[0]]
		)
		nodes[callee].setKid(kidIds, 0, first)
		return c.checkCall(e, expected)
	if m in tableSteps and c.stepInPlace(e, m): return c.checkCall(e, expected)
	if m in tableSteps:
		rows = newNode(
			nodes,
			kidIds,
			nField,
			line,
			col,
			text = "$rows",
			kids = [nodes[callee].kids(kidIds)[0]]
		)
		madeKid = newNode(nodes, kidIds, nCall, line, col, kids = [rows])
		nodes[callee].setKid(kidIds, 0, madeKid)
		return c.checkCall(e, expected)
	if m in tableMethods: return c.callAsMethod(e, c.tableFunction(d, m), m, expected)
	c.errorAt(
		line,
		col,
		compileError(
			"TableNoMethod",
			[
				"{m}",
				"{c.showTy(t)}",
				"{tableMethods.filter(not .startsWith("$")).join(", ")}",
				"{tableSteps.join(", ")}"
			]
		)
	)
	c.checkArgsAlone(e)
	tyError

# A step over a table named as a place, `t.step(f)` (e), its lambda written out: made the step
# over 0..t.len with the lambda's element a row of t at that index, so it reads the columns in
# place; filter, sortedBy, find, minBy and maxBy then copy out the elements they give. Whether
# it was.
fn stepInPlace(mut c Checker, e NodeId, m str):
	callee = nodes[e].kids(kidIds)[0]
	recv = nodes[callee].kids(kidIds)[0]
	if not c.isNamedPlace(recv) or nodes[recv].kind == nIndex: return false
	at = 1 if m == "reduce" else 0
	if c.argCount(e) != at + 1: return false
	lam = c.argAt(e, at)
	c.itLambda(lam)
	if nodes[lam].kind != nLambda or nodes[lam].names().len != at + 1 or
		nodes[nodes[lam].types()[at]].kind != nTyAbsent:
		return false
	line = nodes[e].line
	col = nodes[e].col
	index = "$ix{lam}"
	c.rows.push(TableRow(table = cloneTree(nodes, kidIds, recv), index = index.copy()))
	elem = c.tableElement(c.placeType(recv))
	c.rowParams.push(RowParam(index.copy(), nodes[lam].takeName(at), c.rows.len - 1, elem))
	nodes[lam].nodeMore().names[at] = index
	zero = newNode(nodes, kidIds, nInt, line, col, text = "0")
	madeKid = newNode(
		nodes,
		kidIds,
		nRange,
		line,
		col,
		kids = [zero, lenOf(nodes, kidIds, line, col, recv)]
	)
	nodes[callee].setKid(kidIds, 0, madeKid)
	if m == "findIndex":
		nodes[callee].setText("find")   # a range's find gives the index
	if m not in ["filter", "sortedBy", "find", "minBy", "maxBy"]: return true
	# the indexes the step gives, their elements copied out
	inner = newNode(nodes, kidIds, nCall, line, col)
	nodes[inner] = nodes[e].copy()
	table = cloneTree(nodes, kidIds, c.rows[len - 1].table)
	if m == "filter" or m == "sortedBy":
		pick = "$jx{e}"
		element = newNode(
			nodes,
			kidIds,
			nIndex,
			line,
			col,
			kids = [table, newNode(nodes, kidIds, nIdent, line, col, text = pick.copy())]
		)
		get = newNode(nodes, kidIds, nLambda, line, col, kids = [element])
		nodes[get].nodeMore().names.push(pick)
		nodes[get].nodePart().types.push(newNode(nodes, kidIds, nTyAbsent, line, col))
		map = newNode(nodes, kidIds, nField, line, col, text = "map", kids = [inner])
		nodes[e].setKids(kidIds, [map, get])
		return true
	madeKids = [newNode(nodes, kidIds, nField, line, col, text = "$at", kids = [table]), inner]
	nodes[e].setKids(kidIds, madeKids)
	true

# the table type of the element e names, a row or t[i] of a named table, if any
fn elementTable(mut c Checker, e NodeId):
	v = c.rowVar(e)
	if v >= 0: return c.placeType(c.rows[c.vars[v].row].table)
	if c.isTableIndex(e): return c.placeType(nodes[e].kids(kidIds)[0])
	none

# the table expression of the element e names (elementTable's), not written again
fn elementPlaceTable(c Checker, e NodeId):
	v = c.rowVar(e)
	c.rows[c.vars[v].row].table if v >= 0 else nodes[e].kids(kidIds)[0]

# the names that reach the table whose root variable is `root`: it and the rows of it in scope
fn tableNames(c Checker, root str):
	out = [root.copy()]
	for v in c.vars:
		if v.row >= 0 and c.rootName(c.rows[v.row].table) == root:
			out.push(v.name.copy())
	out

# whether e assigns the variable `name` whole (a row is not bound again)
fn assignsWhole(c Checker, e NodeId, name str) bool:
	if nodes[e].kind == nAssign and nodes[nodes[e].kids(kidIds)[0]].kind == nIdent and
		nodes[nodes[e].kids(kidIds)[0]].text == name:
		return true
	nodes[e].kids(kidIds).any(c.assignsWhole(it, name)) or
		nodes[e].sub().any(c.assignsWhole(it, name))

# A call f(t[i]) or f(r) (r a row) of a function whose read or mut parameter takes the table's
# element (e, f declared by fd): made the call of f's row instance given the table and the
# index, so the body reads and changes the parameter's fields in the columns. Whether it was.
fn rowCall(mut c Checker, e NodeId, fd NodeId):
	if not nodes[fd].names().isEmpty or c.rowsRefused(fd) or
		nodes[e].kids(kidIds).any(nodes[it].kind == nNamedArg):
		return false
	c.readBody(fd)
	found = []
	foundTables = []
	for j in 0..c.argCount(e).min(nodes[fd].kids(kidIds).len):
		p = nodes[fd].kids(kidIds)[j]
		if nodes[p].ival != modeRead and nodes[p].ival != modeMut or
			c.assignsWhole(nodes[fd].sub()[0], nodes[p].text):
			continue
		t = c.elementTable(c.argAt(e, j))
		if t is t and isSameType(tys, c.resolveType(nodes[p].types()[0]), c.tableElement(t)):
			found.push(j)
			foundTables.push(t)
	# a table another argument reaches stays lent once (a copy of its element given), unless
	# both only read rows of it
	at = []
	tables = []
	name = "{nodes[fd].text}$row"
	for i, j in found:
		names = c.tableNames(c.rootName(c.elementPlaceTable(c.argAt(e, j))))
		reading = nodes[nodes[fd].kids(kidIds)[j]].ival == modeRead
		reached = false
		for k in 0..c.argCount(e):
			if k != j and mentionsAny(nodes, kidIds, c.argAt(e, k), names) and
				not (reading and k in found and nodes[nodes[fd].kids(kidIds)[k]].ival == modeRead):
				reached = true
		if not reached:
			at.push(j)
			tables.push(foundTables[i])
			name = "{name}{j}_{declOf(tys, foundTables[i])}"
	if at.isEmpty: return false
	if c.findFunc(name) == none: c.addRowFunction(c.rowFunction(fd, name, none, at, tables))
	k = at.len - 1
	while k >= 0:
		table, index = c.elementPlace(c.argAt(e, at[k])) ?? return false
		c.setArg(e, at[k], table)
		nodes[e].insertKid(kidIds, at[k] + 2, index)
		k -= 1
	nodes[nodes[e].kids(kidIds)[0]].setText(name)
	true

# x.f(a) with x a table's element (t[i] or a row) and f the element's method or the one
# function taking it first: e made the call of f's row instance (rowCall). Whether it was.
fn rowMethodCall(mut c Checker, e NodeId, obj NodeId, m str):
	t = c.elementTable(obj) ?? return false
	elem = c.tableElement(t)
	callee = nodes[e].kids(kidIds)[0]
	line = nodes[callee].line
	col = nodes[callee].col
	if c.findMethod(tys[elem].name, m) != none:
		impl, md = c.methodOf(tys[elem].name, m) ?? return false
		if not nodes[impl].names().isEmpty or c.rowsRefused(md): return false
		name = "$rowm{md}_{declOf(tys, t)}"
		if c.findFunc(name) == none:
			selfParam = newNode(nodes, kidIds, nParam, line, col, text = "self")
			nodes[selfParam].ival = modeMut if nodes[md].hasFlag(flagMut) else modeRead
			d = c.rowFunction(md, name, selfParam, [0], [t])
			nodes[d].flags &= ~flagMut
			nodes[d].nodeMore().mod = nodes[impl].mod().copy()
			nodes[d].nodeMore().file = nodes[impl].file().copy()
			c.rowFunctions[len - 1].fields = elem
			c.addRowFunction(d)
		table, index = c.elementPlace(obj) ?? return false
		kids = [newNode(nodes, kidIds, nIdent, line, col, text = name.copy()), table, index]
		kids.extend(nodes[e].kidsFrom(kidIds, 1))
		nodes[e].setKids(kidIds, kids)
		return true
	found = c.receiverFunctions(elem, m)
	if found.len != 1: return false
	kids = [newNode(nodes, kidIds, nIdent, line, col, text = nodes[found[0]].text.copy()), obj]
	kids.extend(nodes[e].kidsFrom(kidIds, 1))
	nodes[e].setKids(kidIds, kids)
	c.rowCall(e, found[0])
	true

# the impl declaring type `typeName`'s method m and the method
fn methodOf(c Checker, typeName str, m str) (NodeId, NodeId)?:
	for d in c.decls:
		if nodes[d].kind == nImplDecl and nodes[d].text == typeName:
			for f in nodes[d].kids(kidIds):
				if nodes[f].text == m: return (d, f)
	none

# whether the function fd has no row instance: its body changed after its check
fn rowsRefused(c Checker, fd NodeId):
	nodes[fd].sub().isEmpty or
		nodes[fd].hasFlag(flagExtern | flagGpu | flagFusedMath | flagOptionBlocks)

# The row instance `name` of the function or method fd, without its body yet (fillRowFunction):
# its parameter `selfParam` (a method's self, put first; -1 for a function) and the parameters at `at`
# each become the table of the type in `tables` (in the parameter's mode) and the index, the
# parameter's name a row of them in the body.
fn rowFunction(
	mut c Checker,
	fd NodeId,
	name str,
	selfParam NodeId?,
	at i64[],
	tables TypeId[]
):
	c.fnRetType(fd)   # a result its body gives, in the copy too
	d = cloneTree(nodes, kidIds, fd)
	nodes[d].nodePart().sub = []
	nodes[d].setText(name.copy())
	nodes[d].setText2(name.copy())
	if selfParam is selfParam:
		nodes[d].insertKid(kidIds, 0, selfParam)
	c.rowFunctions.push(RowFunction(decl = d, origin = fd))
	k = at.len - 1
	while k >= 0:
		p = nodes[d].kids(kidIds)[at[k]]
		line = nodes[p].line
		col = nodes[p].col
		hidden = "$t{d}p{at[k]}"
		index = "$ix{d}p{at[k]}"
		ip = newNode(nodes, kidIds, nParam, line, col, text = index.copy())
		nodes[ip].nodePart().types = [newNode(nodes, kidIds, nTyName, line, col, text = "i64")]
		nodes[d].insertKid(kidIds, at[k] + 1, ip)
		table = newNode(nodes, kidIds, nIdent, line, col, text = hidden.copy())
		c.rows.push(TableRow(table, index = index.copy()))
		elem = c.tableElement(tables[k])
		c.rowParams.push(RowParam(index, nodes[p].takeText(), c.rows.len - 1, elem))
		nodes[p].setText(hidden)
		nodes[p].nodePart().types = [
			newNode(nodes, kidIds, nTyName, line, col, text = "$param{tables[k]}")
		]
		nodes[p].setKids(kidIds, [])   # a default is the element's
		k -= 1
	d

# the row instance d made a declaration, its signature resolved where it is declared
fn addRowFunction(mut c Checker, d NodeId):
	savedMod = c.curMod
	savedFile = c.curFile.copy()
	c.enterModuleOf(d)
	c.resolveFnSignature(d)
	c.curMod = savedMod
	c.curFile = savedFile
	c.addDecl(d)

# d's body, when d is a row instance without one yet: its function's, checked by now (a
# method's bare names of its fields written self.f)
fn fillRowFunction(mut c Checker, d NodeId):
	if not nodes[d].sub().isEmpty: return
	for rf in c.rowFunctions:
		if rf.decl == d:
			body = cloneTree(nodes, kidIds, nodes[rf.origin].sub()[0])
			if rf.fields != none:
				c.selfFieldsIn(
					body,
					nodes[declOf(tys, rf.fields)].kids(kidIds).map(nodes[it].text.copy())
				)
			nodes[d].nodePart().sub = [body]
			return

# the row a pipeline lambda's element is (stepInPlace), bound beside its index parameter `index`
fn addRowParam(mut c Checker, index str, line i64, col i64):
	iv = c.vars.len - 1
	for i in 0..c.rowParams.len:
		if c.rowParams[i].index == index:
			v = c.addVar(c.rowParams[i].name.copy(), c.rowParams[i].elem, false, true, line, col)
			c.vars[v].row = c.rowParams[i].row
			c.vars[iv].used = true   # the index is read by the row's uses, which may be none
			return

# A let that lends a table's element, `r = mut ref t[i]` (or the `ref` of a for's element): r
# becomes a row, the let binds its index under a hidden name. Whether s was one.
fn rowLet(mut c Checker, s NodeId) bool:
	value = nodes[s].kids(kidIds)[0]
	if nodes[value].kind != nUnary or nodes[value].ival != unRef and nodes[value].ival != unMutRef:
		return false
	at = nodes[value].kids(kidIds)[0]
	if not c.isTableIndex(at): return false
	line = nodes[s].line
	col = nodes[s].col
	table = nodes[at].kids(kidIds)[0]
	if not c.isNamedPlace(table) or nodes[table].kind == nIndex:
		errorAt(
			c,
			line,
			col,
			compileError("TableRowUnbound", [])
		)
		return true
	name = nodes[s].text.copy()
	index = "$row{s}"
	nodes[s].setText(index.copy())
	nodes[s].setKids(kidIds, [nodes[at].kids(kidIds)[1]])
	nodes[s].nodePart().types = []
	c.checkLet(s)
	iv = c.innermostVar(index)
	if iv >= 0:
		c.vars[iv].used = true   # read by the row's uses, which may be none
	elem = c.tableElement(c.placeType(table))
	v = c.addVar(name, elem, false, false, line, col)
	c.vars[v].row = c.rows.len
	c.rows.push(TableRow(table, index))
	true

# An assignment to a table's element or column (s): the element given whole
# is made the call that stores it; what a table does not take is reported. Whether s was one.
fn tableAssign(mut c Checker, s NodeId) bool:
	line = nodes[s].line
	col = nodes[s].col
	target = nodes[s].kids(kidIds)[0]
	if c.isTableIndex(target):
		if nodes[s].ival != 0:
			c.errorAt(line, col, compileError("TableElementChange", []))
			return true
		set = newNode(
			nodes,
			kidIds,
			nField,
			line,
			col,
			text = "$set",
			kids = [nodes[target].kids(kidIds)[0]]
		)
		call = newNode(
			nodes,
			kidIds,
			nCall,
			line,
			col,
			kids = [set, nodes[target].kids(kidIds)[1], nodes[s].kids(kidIds)[1]]
		)
		nodes[s].kind = nExprStmt
		nodes[s].setKids(kidIds, [call])
		c.checkStmt(s)
		return true
	if nodes[target].kind == nField and nodes[target].kids(kidIds).len == 1 and
		c.isTable(c.placeType(nodes[target].kids(kidIds)[0])):
		c.errorAt(line, col, compileError("TableColumnLength", ["{nodes[target].text}"]))
		return true
	false

# whether e is a table's column, changed by `what` (a method, a mut argument): reported, as a
# column keeps the table's length and order (the derived functions change them together)
fn changesColumn(mut c Checker, e NodeId, what str):
	if nodes[e].kind != nField or nodes[e].kids(kidIds).len != 1: return false
	if c.curMod >= 0 and c.modules[c.curMod].id == "derive": return false
	t = c.derefType(typeOf(nodes, nodes[e].kids(kidIds)[0]))
	if not c.isTable(t): return false
	c.errorAt(
		nodes[e].line,
		nodes[e].col,
		compileError("TableColumnChange", ["{what}", "{nodes[e].text}", "{c.showTy(t)}"])
	)
	true

# `for r in t` over a table: for $i in 0..t.len with r a row of t at $i
fn forTable(mut c Checker, s NodeId):
	line = nodes[s].line
	col = nodes[s].col
	forByIndex(
		c,
		s,
		lenOf(nodes, kidIds, line, col, cloneTree(nodes, kidIds, nodes[s].kids(kidIds)[0])),
		unMutRef,
		"a Table"
	)
