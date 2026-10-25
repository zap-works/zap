# Grid<T> (runtime/grid/grid.zap, spec 7.10): the forms the checker writes as calls of its
# functions, so the backend sees calls and lists only:
#   Grid(w, h)                   $rt.gridZeros(w, h): every cell its type's zero
#   Grid(w, h, fill = v)         $rt.gridFilled(w, h, v)
#   Grid(w, h, cells = xs)       $rt.gridOfCells(w, h, xs): the list's cells, row after row
#   g[x, y]                      the cell g.index(x, y) lends (indexMut where it changes); in
#                                loops over 0..g.width and 0..g.height, g.cells[y * g.width + x]
#                                unchecked
#   g[a..b, y]                   g.gridRow(a, b, y): a window into the cells
#   g[x, a..b], g[a..b, c..d]    g.gridColumn(x, a, b), g.gridBlock(a, b, c, d): a GridView
#   for (x, y), v in g           a loop over the cells' count, x and y counted along

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

gridWhole = 1
gridView = 2

# Outside the runtime a grid's width, height and cells (as a whole) are never changed, so its
# cells always fill width x height: the error at a change of one (mutBlocker)
fn gridSizeChange(mut c Checker, target NodeId, line i64, col i64):
	at = target
	while nodes[at].kind == nDeref:
		at = nodes[at].kids(kidIds)[0]
	if nodes[at].kind != nField or nodes[at].kids(kidIds).len != 1 or c.walkingRuntime(): return
	if not (nodes[at].text in ["width", "height", "cells"]): return
	owner = nodes[at].kids(kidIds)[0]
	if c.gridKind(c.derefType(typeOf(nodes, owner))) == gridWhole:
		c.errorAt(line, col, compileError("GridSizeFixed", [nodes[at].text.copy()]))

# whether t is a Grid (gridWhole), a GridView (gridView) or neither (0)
fn gridKind(c Checker, maybeT TypeId?):
	t = maybeT ?? return 0
	if c.tKind(t) != tStruct: return 0
	d = declOf(tys, t)
	if nodes[d].mod() != "rt": return 0
	name = nodes[nodes[d].origin() ?? return 0].text2()
	if name == "Grid": return gridWhole
	if name == "GridView": return gridView
	0

# the cells' type of the grid type t
fn gridCell(c Checker, t TypeId):
	nodes[declOf(tys, t)].ints()[0]

# `Grid(width, height)`, `Grid(width, height, fill = v)` or `Grid(width, height, cells = xs)`
# (d the struct its callee names) made the call of the runtime's maker; a number literal as fill
# takes the cell type written (`Grid<f32>`) or expected: whether e was
fn gridMaker(mut c Checker, e NodeId, d NodeId, expected TypeId?):
	gd = nodes[d].origin() ?? d   # an instance: a defined type's (Image)
	if nodes[gd].mod() != "rt" or nodes[gd].text2() != "Grid" or c.walkingRuntime(): return false
	callee = nodes[e].kids(kidIds)[0]
	args = nodes[e].kidsFrom(kidIds, 1).copy()
	line = nodes[e].line
	col = nodes[e].col
	made = "?"   # the third argument's name: "" for none
	if args.len == 2:
		made = ""
	elif args.len == 3 and nodes[args[2]].kind == nNamedArg:
		made = nodes[args[2]].text.copy()
	if args[..2.min(len)].any(nodes[it].kind == nNamedArg) or made not in ["", "fill", "cells"]:
		c.errorAt(line, col, compileError("GridLiteral", []))
		return false
	rt = newNode(nodes, kidIds, nIdent, line, col, text = "$rt")
	if made == "":
		# the runtime's own, its cell type the one written (Grid<f32>(w, h)) or expected
		zeros = newNode(nodes, kidIds, nIdent, line, col, text = "gridZeros")
		nodes[zeros].nodePart().types = nodes[callee].types().copy()
		nodes[zeros].flags |= flagInternal
		nodes[e].setKid(kidIds, 0, zeros)
		return true
	nodes[e].setKid(kidIds, 3, nodes[args[2]].kids(kidIds)[0])   # the value named
	if made == "cells":
		madeKid = newNode(nodes, kidIds, nField, line, col, text = "gridOfCells", kids = [rt])
		nodes[e].setKid(kidIds, 0, madeKid)
		return true
	want TypeId? = none
	if not nodes[callee].types().isEmpty:
		want = c.resolveType(nodes[callee].types()[0])
	elif c.gridKind(expected) == gridWhole and expected is grid:
		want = c.gridCell(grid)
	elif gd != d:
		want = c.gridCell(tyOfDecl(tys, nodes, d))
	fill = nodes[e].kids(kidIds)[3]
	floating = nodes[fill].kind == nFloat or nodes[fill].kids(kidIds).any(nodes[it].kind == nFloat)
	literal = "f64" if floating else "i64"
	if (c.tKind(want) == tInt or c.tKind(want) == tFloat) and c.isNumLit(fill) and
		c.showTy(want) != literal:
		convert = newNode(
			nodes,
			kidIds,
			nField,
			line,
			col,
			text = conversionMethod(c.showTy(want)),
			kids = [fill]
		)
		madeKid = newNode(nodes, kidIds, nCall, line, col, kids = [convert])
		nodes[e].setKid(kidIds, 3, madeKid)
	madeKid = newNode(nodes, kidIds, nField, line, col, text = "gridFilled", kids = [rt])
	nodes[e].setKid(kidIds, 0, madeKid)
	true

# `g[x, y]` and its slices (e an index the parser marked flagComma): checked as the runtime's
# call it stands for; none when the indexed value is no grid (a list's layers)
fn checkCommaIndex(mut c Checker, e NodeId, expected TypeId?) TypeId?:
	line = nodes[e].line
	col = nodes[e].col
	coords NodeId[] = []
	at = e
	while nodes[at].kind == nIndex and nodes[at].hasFlag(flagComma):
		coords.insert(0, nodes[at].kids(kidIds)[1])
		at = nodes[at].kids(kidIds)[0]
	if nodes[at].kind != nIndex: return none
	coords.insert(0, nodes[at].kids(kidIds)[1])
	base = nodes[at].kids(kidIds)[0]
	place = exprText(nodes, kidIds, base) if c.fieldChain(base) else ""
	bt = c.derefIfRef(base, c.checkExpr(base, none))
	kind = c.gridKind(bt)
	ranged = coords.any(nodes[it].kind == nRange)
	if kind == 0:
		if c.tKind(bt) == tError: return c.typed(e, tyError)
		if ranged:
			c.errorAt(line, col, compileError("GridSliceInList", []))
			return c.typed(e, tyError)
		return none
	if coords.len != 2:
		c.errorAt(line, col, compileError("GridCellCoordinates", ["{coords.len}"]))
		return c.typed(e, tyError)
	x = coords[0]
	y = coords[1]
	if not ranged and kind == gridWhole and c.gridLoopsHold(place, x, "width") and
		c.gridLoopsHold(place, y, "height"):
		width = newNode(
			nodes,
			kidIds,
			nField,
			line,
			col,
			text = "width",
			kids = [cloneTree(nodes, kidIds, base)]
		)
		row = c.binaryNode(binMul, y, width, line, col)
		cell = c.binaryNode(binAdd, row, x, line, col)
		nodes[row].flags |= flagWrap
		nodes[cell].flags |= flagWrap
		cells = newNode(nodes, kidIds, nField, line, col, text = "cells", kids = [base])
		nodes[e].setKids(kidIds, [cells, cell])
		nodes[e].flags = (nodes[e].flags & ~flagComma) | flagInternal | flagInBounds
		return c.checkExpr(e, expected)
	if not ranged:
		callee = newNode(nodes, kidIds, nField, line, col, text = "index", kids = [base])
		call = newNode(nodes, kidIds, nCall, line, col, kids = [callee, x, y])
		nodes[e].kind = nDeref
		nodes[e].setKids(kidIds, [call])
		nodes[e].flags = (nodes[e].flags & ~flagComma) | flagInternal
		return c.checkExpr(e, expected)
	if kind == gridView:
		c.errorAt(line, col, compileError("GridViewSliced", []))
		return c.typed(e, tyError)
	args = []
	method = ""
	if nodes[x].kind == nRange and nodes[y].kind == nRange:
		method = "gridBlock"
		args = c.gridSpanOf(x, base, "width") ?? return c.typed(e, tyError)
		args.extend(c.gridSpanOf(y, base, "height") ?? return c.typed(e, tyError))
	elif nodes[x].kind == nRange:
		method = "gridRow"
		args = c.gridSpanOf(x, base, "width") ?? return c.typed(e, tyError)
		args.push(y)
	else:
		method = "gridColumn"
		args = [x]
		args.extend(c.gridSpanOf(y, base, "height") ?? return c.typed(e, tyError))
	callee = newNode(nodes, kidIds, nField, line, col, text = method, kids = [base])
	args.insert(0, callee)
	nodes[e].kind = nCall
	nodes[e].setKids(kidIds, args)
	nodes[e].flags = (nodes[e].flags & ~flagComma) | flagInternal
	c.checkExpr(e, expected)

# a range coordinate's start and end, an end left out the grid's `size` (width or height);
# -1 for each when it cannot be one (reported)
fn gridSpanOf(mut c Checker, r NodeId, base NodeId, size str) NodeId[]?:
	line = nodes[r].line
	col = nodes[r].col
	if nodes[r].kids(kidIds).len > 2:
		c.errorAt(line, col, compileError("GridSliceStep", []))
		return none
	if nodes[r].kids(kidIds).len == 2: return [nodes[r].kids(kidIds)[0], nodes[r].kids(kidIds)[1]]
	if nodeCalls(nodes, kidIds, base):
		c.errorAt(
			line,
			col,
			compileError("GridSliceNeedsPlace", [])
		)
		return none
	[
		nodes[r].kids(kidIds)[0],
		newNode(
			nodes,
			kidIds,
			nField,
			line,
			col,
			text = size.copy(),
			kids = [cloneTree(nodes, kidIds, base)]
		)
	]

# the cell a step of a grid loop lends (kind gridWhole), or reads of a view as v[x, y] does
fn gridLoopCell(mut c Checker, s NodeId, kind i64, iter NodeId, gx str, gy str) NodeId:
	line = nodes[s].line
	col = nodes[s].col
	if kind != gridWhole:
		column = newNode(
			nodes,
			kidIds,
			nIndex,
			line,
			col,
			kids = [cloneTree(nodes, kidIds, iter), c.gridName(gx, s)]
		)
		cell = newNode(nodes, kidIds, nIndex, line, col, kids = [column, c.gridName(gy, s)])
		nodes[cell].flags = flagComma
		return cell
	place = c.binaryNode(
		binAdd,
		c.binaryNode(binMul, c.gridName(gy, s), c.gridField(iter, "width", s), line, col),
		c.gridName(gx, s),
		line,
		col
	)
	cell = newNode(nodes, kidIds, nIndex, line, col, kids = [c.gridField(iter, "cells", s), place])
	lend = newNode(nodes, kidIds, nUnary, line, col, kids = [cell])
	nodes[lend].ival = unRef
	lend

# `for v in g` and `for (x, y), v in g` over a grid (kind) or a view: a loop over the cells'
# count, the coordinates counted at the start of each step (so `continue` keeps them) and the
# cell lent; a Grid's cells alone are its list's
fn forGridCells(mut c Checker, s NodeId, kind i64, iterT TypeId):
	line = nodes[s].line
	col = nodes[s].col
	iter = nodes[s].kids(kidIds)[0]
	if kind == 0:
		if c.tKind(iterT) != tError:
			c.errorAt(line, col, compileError("GridForNotGrid", ["{c.showTy(iterT)}"]))
		return
	if kind == gridWhole and nodes[s].names().isEmpty:
		madeKid = newNode(nodes, kidIds, nField, line, col, text = "cells", kids = [iter])
		nodes[s].setKid(kidIds, 0, madeKid)
		c.checkFor(s)
		return
	if not c.fieldChain(iter):
		c.errorAt(line, col, compileError("GridForNeedsPlace", []))
		return
	gx = "$gx{s}"
	gy = "$gy{s}"
	first = [
		c.gridAssign(gx, c.binaryNode(binAdd, c.gridName(gx, s), c.gridInt("1", s), line, col), s)
	]
	wrapped = c.binaryNode(binEq, c.gridName(gx, s), c.gridField(iter, "width", s), line, col)
	nextRow = newNode(
		nodes,
		kidIds,
		nBlock,
		line,
		col,
		kids = [
			c.gridAssign(gx, c.gridInt("0", s), s),
			c.gridAssign(
				gy,
				c.binaryNode(binAdd, c.gridName(gy, s), c.gridInt("1", s), line, col),
				s
		)]
	)
	atEdge = newNode(nodes, kidIds, nIf, line, col, kids = [wrapped])
	nodes[atEdge].nodePart().sub = [nextRow]
	first.push(atEdge)
	for i, name in nodes[s].names().copy():
		if name != "_":
			first.push(c.gridLet(name, c.gridName(gx if i == 0 else gy, s), false, s))
	cell = c.gridLoopCell(s, kind, iter, gx, gy)
	first.push(c.gridLet(nodes[s].text.copy(), cell, false, s))
	body = nodes[s].sub()[0]
	first.extend(nodes[body].kids(kidIds))
	nodes[body].setKids(kidIds, first)
	count = c.binaryNode(
		binMul,
		c.gridField(iter, "width", s),
		c.gridField(iter, "height", s),
		line,
		col
	)
	r = newNode(nodes, kidIds, nRange, line, col, kids = [c.gridInt("0", s), count])
	cellLoop = newNode(nodes, kidIds, nFor, line, col, text = "_", kids = [r])
	nodes[cellLoop].nodePart().sub = [body]
	scope = newNode(
		nodes,
		kidIds,
		nBlock,
		line,
		col,
		kids = [
			c.gridLet(gx, c.gridInt("-1", s), true, s),
			c.gridLet(gy, c.gridInt("0", s), true, s),
			cellLoop]
	)
	nodes[s].kind = nIf
	nodes[s].text = ""
	nodes[s].nodePart().names = []
	madeKids = [newNode(nodes, kidIds, nBool, line, col)]
	nodes[s].setKids(kidIds, madeKids)
	nodes[nodes[s].kids(kidIds)[0]].ival = 1
	nodes[s].nodePart().sub = [scope]
	c.checkStmt(s)

# A for over lo..g.width or lo..g.height (lo a literal not below 0, g a local's place) whose
# body leaves g's size alone: its variable is a coordinate inside g along that axis, and g[x, y]
# with both coordinates so proven is read unchecked (checkCommaIndex). A lambda inside the body
# may run after the loop: lambdas counts those open at the loop.
type GridLoop:
	index str   # the loop's variable
	place str   # g's text
	axis str   # "width" or "height"
	lambdas i64

# the loop s noted in gridLoops when it goes over a grid's width or height and its body (read
# before it is checked) leaves the grid's size alone
fn enterGridLoop(mut c Checker, s NodeId):
	iter = nodes[s].kids(kidIds)[0]
	if nodes[iter].kids(kidIds).len != 2 or not nodes[s].names().isEmpty or nodes[s].text == "_":
		return
	lo = nodes[iter].kids(kidIds)[0]
	hi = nodes[iter].kids(kidIds)[1]
	if nodes[lo].kind != nInt or nodes[lo].text.startsWith("-"): return
	if nodes[hi].kind != nField or nodes[hi].kids(kidIds).len != 1 or
		not (nodes[hi].text in ["width", "height"]):
		return
	grid = nodes[hi].kids(kidIds)[0]
	if not c.fieldChain(grid): return
	root = nodes[c.chainRoot(grid)].text.copy()
	if not c.lookupVarQuiet(root): return   # a module's variable: a call may resize it
	place = exprText(nodes, kidIds, grid)
	index = nodes[s].text.copy()
	if not c.gridSizeKept(nodes[s].sub()[0], place, root, index): return
	c.gridLoops.push(
		GridLoop(index, place, axis = nodes[hi].text.copy(), lambdas = c.lamStack.len)
	)

fn chainRoot(c Checker, e NodeId) NodeId:
	e if nodes[e].kind == nIdent else c.chainRoot(nodes[e].kids(kidIds)[0])

# whether coordinate v of a cell of the grid at place is a loop's variable proven along axis
fn gridLoopsHold(c Checker, place str, v NodeId, axis str):
	place != "" and nodes[v].kind == nIdent and
		c.gridLoops.any(
			.index == nodes[v].text and .place == place and .axis == axis and
			.lambdas == c.lamStack.len
		)

# whether e (unchecked) leaves the size of the grid at place alone and binds neither the
# loop's variable nor the grid's root again: the grid is read only through its cells
# (g[x, y], read or written), g.width and g.height; a place holding it or inside it reaching a
# call, an assignment or anything else may resize it, as may a local function value's call
fn gridSizeKept(mut c Checker, e NodeId, place str, root str, index str) bool:
	k = nodes[e].kind
	if k in [nLet, nFor, nPattern, nArm, nLambda] and
		(nodes[e].text == index or nodes[e].text == root or
				nodes[e].names().any(it == index or it == root)):
		return false
	coords = c.gridCellAt(e, place)
	if not coords.isEmpty: return coords.all(c.gridSizeKept(it, place, root, index))
	if c.fieldChain(e):
		t = exprText(nodes, kidIds, e)
		if nodes[c.chainRoot(e)].text != root or c.gridPlaceApart(t, place): return true
		return t == "{place}.width" or t == "{place}.height"
	if k == nCall or k == nAssign:
		callee = nodes[e].kids(kidIds)[0]
		if k == nCall and nodes[callee].kind == nIdent and c.lookupVarQuiet(nodes[callee].text):
			return false
		given = nodes[e].kidsFrom(kidIds, 1).copy()
		if k == nAssign or nodes[callee].kind == nField:
			given.push(nodes[callee].kids(kidIds)[0] if k == nCall else callee)
		for g in given:
			if k == nAssign and not c.gridCellAt(g, place).isEmpty: continue
			if c.fieldChain(g) and nodes[c.chainRoot(g)].text == root and
				not c.gridPlaceApart(exprText(nodes, kidIds, g), place):
				return false
	nodes[e].kids(kidIds).all(c.gridSizeKept(it, place, root, index)) and
		nodes[e].sub().all(c.gridSizeKept(it, place, root, index))

# whether the places a and b are apart: neither holds the other
fn gridPlaceApart(c Checker, a str, b str):
	a != b and not a.startsWith("{b}.") and not b.startsWith("{a}.")

# g[x, y] (unchecked) of the grid at place: its coordinates x and y, none when e is no such cell
fn gridCellAt(mut c Checker, e NodeId, place str):
	if nodes[e].kind != nIndex or not nodes[e].hasFlag(flagComma): return []
	inner = nodes[e].kids(kidIds)[0]
	if nodes[inner].kind != nIndex or nodes[inner].hasFlag(flagComma): return []
	base = nodes[inner].kids(kidIds)[0]
	if not c.fieldChain(base) or exprText(nodes, kidIds, base) != place: return []
	[nodes[inner].kids(kidIds)[1], nodes[e].kids(kidIds)[1]]

fn gridName(mut c Checker, name str, s NodeId) NodeId:
	newNode(nodes, kidIds, nIdent, nodes[s].line, nodes[s].col, text = name.copy())

fn gridInt(mut c Checker, text str, s NodeId) NodeId:
	newNode(nodes, kidIds, nInt, nodes[s].line, nodes[s].col, text = text.copy())

fn gridField(mut c Checker, base NodeId, field str, s NodeId) NodeId:
	newNode(
		nodes,
		kidIds,
		nField,
		nodes[s].line,
		nodes[s].col,
		text = field.copy(),
		kids = [cloneTree(nodes, kidIds, base)]
	)

fn gridLet(mut c Checker, name str, value NodeId, isMut bool, s NodeId):
	l = newNode(
		nodes,
		kidIds,
		nLet,
		nodes[s].line,
		nodes[s].col,
		text = name.copy(),
		kids = [value]
	)
	if isMut:
		nodes[l].flags = flagMut
	l

fn gridAssign(mut c Checker, name str, value NodeId, s NodeId) NodeId:
	newNode(
		nodes,
		kidIds,
		nAssign,
		nodes[s].line,
		nodes[s].col,
		kids = [c.gridName(name, s), value]
	)

# A math operator with a grid of numbers on a side (spec 7.10), written as the runtime's call it
# stands for and checked: `a @ b` (floats) gridProduct(a, b, none), `a @ b + c` and `c + a @ b`
# gridProduct(a, b, c) (c added in the same pass), `a + b` (- * /) gridEw(a, b, op), `a * k`,
# `k * a` and `a / k` gridScalar(a, k, op).
fn checkGridMath(mut c Checker, e NodeId, op i64, lt TypeId, rt TypeId, expected TypeId?) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	l = nodes[e].kids(kidIds)[0]
	r = nodes[e].kids(kidIds)[1]
	lg = c.gridKind(lt) == gridWhole
	rg = c.gridKind(rt) == gridWhole
	cell = c.gridCell(lt if lg else rt)
	both = lg and rg and isSameType(tys, lt, rt)
	name = ""
	args = []
	if op == binMatmul and both and c.tKind(cell) == tFloat:
		name = "gridProduct"
		args = [l, r, newNode(nodes, kidIds, nNone, line, col)]
	elif op == binAdd and both and c.gridSum(l) is product:
		name = "gridProduct"
		args = [nodes[product].kids(kidIds)[1], nodes[product].kids(kidIds)[2], r]
	elif op == binAdd and both and c.gridSum(r) is product:
		name = "gridProduct"
		args = [nodes[product].kids(kidIds)[1], nodes[product].kids(kidIds)[2], l]
	elif both and typeIsNumeric(tys, cell) and (op in [binAdd, binSub, binMul, binDiv]):
		name = "gridEw"
		args = [l, r, c.opCode(op, line, col)]
	elif lg and not rg and (op == binMul or op == binDiv) and typeIsNumeric(tys, cell):
		c.checkExpr(r, cell)
		name = "gridScalar"
		args = [l, r, c.opCode(op, line, col)]
	elif rg and not lg and op == binMul and typeIsNumeric(tys, cell):
		c.checkExpr(l, cell)
		name = "gridScalar"
		args = [r, l, c.opCode(op, line, col)]
	else:
		errorAt(
			c,
			line,
			col,
			compileError("OperatorUndefined", ["{binName(op)}", "{c.showTy(lt)}", "{c.showTy(rt)}"])
		)
		return tyError
	rtName = newNode(nodes, kidIds, nIdent, line, col, text = "$rt")
	kids = [newNode(nodes, kidIds, nField, line, col, text = name, kids = [rtName])]
	kids.extend(args)
	nodes[e].kind = nCall
	nodes[e].ival = 0
	nodes[e].setKids(kidIds, kids)
	nodes[e].flags = flagInternal
	c.checkExpr(e, expected)

# the product e is when it is `a @ b` with nothing added yet (gridProduct(a, b, none)), else none
fn gridSum(c Checker, e NodeId) NodeId?:
	if nodes[e].kind != nCall or nodes[e].kids(kidIds).len != 4: return none
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind != nField or nodes[callee].text != "gridProduct" or
		nodes[nodes[e].kids(kidIds)[3]].kind != nNone:
		return none
	e

# the operator's code as vec.zap's apply reads it
fn opCode(mut c Checker, op i64, line i64, col i64) NodeId:
	newNode(nodes, kidIds, nInt, line, col, text = "{opChar(op)}")
