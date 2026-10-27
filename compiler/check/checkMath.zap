# The checking of struct, matrix and array math, defaults and name qualifying (checkExpr.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# The methods of a vector a struct of numbers has, with no method of the name: dot (what
# `a @ b` calls; written, it is an error), and on floats length, distance, normalized (zero
# stays zero) and reflect (by a normal of length 1), written once for every such struct
# (derive.zap).
vectorMethods = ["dot", "length", "distance", "normalized", "reflect"]

# the $fw function of method m on t asked for, and those it calls
fn noteFieldwise(mut c Checker, t TypeId, m str, shape str):
	i = c.noteDerive(t, 0)
	if c.fieldwise.any(.derived == i and .method == m and .shape == shape): return
	c.fieldwise.push(FieldwiseAsk(i, m.copy(), shape.copy()))
	if m == "length" or m == "reflect":
		c.noteFieldwise(t, "dot", "S")
	if m == "distance" or m == "normalized":
		c.noteFieldwise(t, "length", "")
	if m in ["distance", "normalized", "reflect"]:
		c.noteDerive(t, deriveArith)

# How many arguments a number's method that works field by field takes, -1 for any other name:
# the compiler's own (abs, floor, min, clamp...) and the runtime's that give a number of the
# receiver's type (f64Sin, f64Lerp...).
fn fieldwiseArity(mut c Checker, m str):
	if c.gpuCode and gpuDerivative(m): return 0
	if c.gpuCode and gpuLaneArity(m) >= 0 and m not in laneBoolMethods: return gpuLaneArity(m)
	if m in vectorMethods: return 0 if m == "length" or m == "normalized" else 1
	if m in ["abs", "floor", "ceil", "round", "trunc", "sqrt"]: return 0
	if m in ["min", "max"]: return 1
	if m == "clamp": return 2
	fd = c.findDeclInModule("rt", nFnDecl, "f64{capital(m)}") ?? return -1
	if not c.declIsPub(fd) or nodes[fd].kids(kidIds).isEmpty: return -1
	nodes[fd].kids(kidIds).len - 1 if isSameType(tys, c.fnRetType(fd), tyFloat(64)) else -1

# f64(x), a new node
fn widened(mut c Checker, x NodeId) NodeId:
	newNode(
		nodes,
		kidIds,
		nCall,
		nodes[x].line,
		nodes[x].col,
		kids = [
			newNode(nodes, kidIds, nField, nodes[x].line, nodes[x].col, text = "toF64", kids = [x])
		]
	)

# whether t is one of the language's matrices (Mat2..Mat4)
fn isLanguageMatrix(c Checker, t TypeId):
	c.tKind(t) == tStruct and nodes[declOf(tys, t)].mod() == "rt" and
		nodes[declOf(tys, t)].text2() in ["Mat2", "Mat3", "Mat4"]

# the one number type of every field of struct t, or none (no fields, or fields of other kinds)
fn uniformNumberField(mut c Checker, t TypeId) TypeId?:
	c.numberFieldOf(t, false)

# the one number type of every field of struct t, a field of [N] of it counting when `arrays`
# (a matrix: its arithmetic is on each element), or none
fn numberFieldOf(mut c Checker, t TypeId, arrays bool):
	if c.tKind(t) != tStruct: return none
	d = declOf(tys, t)
	found TypeId? = none
	for k in 0..c.nodes[d].kids(c.kidIds).len:
		ft = c.resolveType(nodes[nodes[d].kids(kidIds)[k]].types()[0])
		if arrays and c.tKind(ft) == tArray:
			ft = innerOf(tys, ft)
		if c.tKind(ft) != tInt and c.tKind(ft) != tFloat: return none
		if found != none and not isSameType(tys, found, ft): return none
		found = ft
	found

# The arithmetic of a struct whose fields are all one number type (a point, a color, a size)
# or arrays of it (a matrix): + - * / between two of them work element by element, and with a
# number of the fields' type (on either side) between the number and every element; @ is
# the product (checkStructProduct). The meaning is fixed, as for lists of numbers: no program
# defines it. The checker asks for the functions that do it ($addN...), which the backend
# calls.
fn checkStructMath(mut c Checker, e NodeId, op i64, lt TypeId, rt TypeId) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	if op == binMatmul: return c.checkStructProduct(e, lt, rt)
	if op != binAdd and op != binSub and op != binMul and op != binDiv:
		errorAt(
			c,
			line,
			col,
			compileError(
				"OperatorNotDefined",
				["{binName(op)}", "{c.showTy(lt if c.tKind(lt) == tStruct else rt)}"]
			)
		)
		return tyError
	if c.tKind(lt) == tStruct and isSameType(tys, lt, rt):
		if c.numberFieldOf(lt, true) == none:
			c.errorAt(line, col, compileError("NoArithmetic", ["{c.showTy(lt)}"]))
			return tyError
		c.noteDerive(lt, deriveArith)
		return c.typed(e, lt)
	if c.tKind(lt) == tStruct and c.tKind(rt) == tStruct:
		c.errorAt(
			line,
			col,
			compileError("ShapesDiffer", ["{binName(op)}", "{c.showTy(lt)}", "{c.showTy(rt)}"])
		)
		return tyError
	structLeft = c.tKind(lt) == tStruct
	st = lt if structLeft else rt
	field = c.numberFieldOf(st, true) ??
		return c.errorTyped(line, col, compileError("NoArithmetic", ["{c.showTy(st)}"]))
	numAt = 1 if structLeft else 0
	n = nodes[e].kids(kidIds)[numAt]
	nt = c.derefIfRef(n, c.checkExpr(n, field))   # a literal takes the fields' type
	if not isSameType(tys, nt, field) and isSameType(tys, c.heldType(nt), field):
		madeKid = c.coerceTo(n, field)
		nodes[e].setKid(kidIds, numAt, madeKid)   # a range: its base
		nt = field
	if not isSameType(tys, nt, field):
		c.errorAt(
			line,
			col,
			compileError(
				"StructScalarType",
				["{c.showTy(st)}", "{c.showTy(field)}", "{c.showTy(nt)}"]
			)
		)
		return tyError
	c.noteDerive(st, deriveArith)
	c.typed(e, st)

# a @ b on structs: matrix @ matrix, matrix @ vector and quaternion @ quaternion (the language's,
# vectors.zap) call the runtime's products, vector @ vector is the dot product (the fieldwise
# `dot`), a number; a GPU function keeps the operator but for a quaternion's (the GPU's own
# product, irGpu.zap)
fn checkStructProduct(mut c Checker, e NodeId, lt TypeId, rt TypeId):
	line = nodes[e].line
	col = nodes[e].col
	if c.isLanguageMatrix(lt):
		n = nodes[declOf(tys, lt)].text2()[3..4]
		if isSameType(tys, lt, rt): return c.runtimeProduct(e, "mat{n}TimesMat", lt)
		if c.tKind(rt) == tStruct and nodes[declOf(tys, rt)].mod() == "rt" and
			nodes[declOf(tys, rt)].text2() == "Vec{n}":
			return c.runtimeProduct(e, "mat{n}TimesVec", rt)
	elif c.isRuntimeType(lt, "Quat"):
		# the runtime's product on the GPU too (a Quat is its vec4 there, with no product of its own)
		if isSameType(tys, lt, rt): return c.runtimeProduct(e, "quatTimesQuat", lt, true)
	elif c.tKind(lt) == tStruct and isSameType(tys, lt, rt) and c.uniformNumberField(lt) != none:
		if c.gpuCode: return c.typed(e, c.uniformNumberField(lt) ?? tyError)
		callee = newNode(
			nodes,
			kidIds,
			nField,
			line,
			col,
			text = "dot",
			kids = [nodes[e].kids(kidIds)[0]]
		)
		nodes[e].kind = nCall
		nodes[e].ival = 0
		nodes[e].setKids(kidIds, [callee, nodes[e].kids(kidIds)[1]])
		nodes[e].flags |= flagInternal
		return c.checkExpr(e, none)
	elif c.matrixField(lt) != none and c.sameTemplate(lt, rt):
		return c.matrixStructProduct(e, lt, rt)
	c.errorAt(line, col, compileError("ProductOperands", ["{c.showTy(lt)}", "{c.showTy(rt)}"]))
	tyError

# the one field of struct t when it is a fixed array of numbers (a program's matrix:
# `type Mat<R n64, C n64>: cells f32[R, C]`), else none
fn matrixField(mut c Checker, t TypeId) NodeId?:
	if c.tKind(t) != tStruct: return none
	d = declOf(tys, t)
	if nodes[d].kids(kidIds).len != 1: return none
	f = nodes[d].kids(kidIds)[0]
	none if c.numberArrayLayers(c.resolveType(nodes[f].types()[0])).isEmpty else f

# whether structs a and b are one declaration's, or instances of one generic's
fn sameTemplate(c Checker, a TypeId, b TypeId):
	if c.tKind(a) != tStruct or c.tKind(b) != tStruct: return false
	da = declOf(tys, a)
	db = declOf(tys, b)
	da == db or (nodes[da].origin() != none and nodes[da].origin() == nodes[db].origin())

# a @ b on structs holding one fixed array of numbers: the struct of the arrays' product,
# Mat<R, K> @ Mat<K, C> a Mat<R, C> (S(field = a.field @ b.field), its type arguments taken from
# the product's shape)
fn matrixStructProduct(mut c Checker, e NodeId, lt TypeId, rt TypeId) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	f = c.matrixField(lt) ?? return tyError   # (asked of matrix structs)
	g = c.matrixField(rt) ?? return tyError
	shape, _ = c.arrayProduct(
		c.resolveType(nodes[f].types()[0]),
		c.resolveType(nodes[g].types()[0])
	)
	if shape == none:
		return c.errorTyped(
			line,
			col,
			compileError("ProductShapes", ["{c.showTy(lt)}", "{c.showTy(rt)}"])
		)
	d = declOf(tys, lt)
	tmpl = nodes[d].origin() ?? d
	name = nodes[f].text.copy()
	lf = newNode(
		nodes,
		kidIds,
		nField,
		line,
		col,
		text = name.copy(),
		kids = [nodes[e].kids(kidIds)[0]]
	)
	rf = newNode(
		nodes,
		kidIds,
		nField,
		line,
		col,
		text = name.copy(),
		kids = [nodes[e].kids(kidIds)[1]]
	)
	product = newNode(nodes, kidIds, nBinary, line, col, kids = [lf, rf])
	nodes[product].ival = binMatmul
	nodes[e].kind = nStructLit
	nodes[e].ival = 0
	nodes[e].setText(nodes[tmpl].text.copy(), nodes[tmpl].name)
	nodes[e].setText2(globalAlias)
	nodes[e].nodeMore().names = [name]
	nodes[e].setKids(kidIds, [product])
	nodes[e].nodePart().types = []
	c.checkExpr(e, none)

# the layers of a fixed array of numbers of one or two dimensions, the outer first; [] for any
# other type
fn numberArrayLayers(c Checker, t TypeId):
	if c.tKind(t) != tArray: return []
	inner = innerOf(tys, t)
	if typeIsNumeric(tys, inner): return [t]
	if c.tKind(inner) == tArray and typeIsNumeric(tys, tys[inner].inner): return [t, inner]
	[]

# whether fixed arrays a and b have one length (a number parameter's at a generic's definition)
fn sameLength(c Checker, a TypeId, b TypeId):
	tys[a].bits == tys[b].bits and (tys[a].bits >= 0 or isSameType(tys, tys[a].val, tys[b].val))

# The type of lt @ rt on fixed arrays of numbers and the runtime's function that makes it:
# T[R, K] @ T[K, C] a T[R, C], T[R, K] @ T[K] a T[R], T[N] @ T[N] a T; (none, "") when the shapes or
# the number types do not meet.
fn arrayProduct(mut c Checker, lt TypeId, rt TypeId) (TypeId?, str):
	l = c.numberArrayLayers(lt)
	r = c.numberArrayLayers(rt)
	if l.isEmpty or r.isEmpty: return (none, "")
	ll = l[len - 1]
	rl = r[len - 1]
	if not isSameType(tys, tys[ll].inner, tys[rl].inner) or not c.sameLength(ll, r[0]):
		return (none, "")
	if l.len == 2 and r.len == 2: return (c.arrayHolding(lt, innerOf(tys, rt)), "arrayTimesArray")
	if l.len == 2: return (c.arrayHolding(lt, innerOf(tys, ll)), "arrayTimesVector")
	if r.len == 1: return (innerOf(tys, ll), "arrayDot")
	(none, "")

# the fixed array of a's length holding inner
fn arrayHolding(mut c Checker, a TypeId, inner TypeId) TypeId:
	t = tys[a].copy()
	t.inner = inner
	tyOnce(tys, t)

# a @ b with a fixed array on a side: the runtime's product of the shapes (arrayProduct)
fn checkArrayProduct(mut c Checker, e NodeId, lt TypeId, rt TypeId) TypeId:
	shape, product = c.arrayProduct(lt, rt)
	t = shape ??
		return c.errorTyped(
			nodes[e].line,
			nodes[e].col,
			compileError("ProductShapes", ["{c.showTy(lt)}", "{c.showTy(rt)}"])
		)
	c.runtimeProduct(e, product, t)

# the binary e made the call of the runtime's `product` on its operands, giving t (in a GPU
# function only when `gpu`: the GPU has its own product otherwise)
fn runtimeProduct(mut c Checker, e NodeId, move product str, t TypeId, gpu bool = false) TypeId:
	if c.gpuCode and not gpu: return c.typed(e, t)
	line = nodes[e].line
	col = nodes[e].col
	l = nodes[e].kids(kidIds)[0]
	r = nodes[e].kids(kidIds)[1]
	rtMod = newNode(nodes, kidIds, nIdent, line, col, text = "$rt")
	callee = newNode(nodes, kidIds, nField, line, col, text = product, kids = [rtMod])
	nodes[e].kind = nCall
	nodes[e].ival = 0
	nodes[e].setKids(kidIds, [callee, l, r])
	c.checkExpr(e, none)

# The error for a bare call inside an impl that names both a method of the type and the
# top-level function fd (-1: a built-in): the method is called through this, the function
# through its module.
fn ambiguousCallMessage(c Checker, name str, fd NodeId?):
	what = "a built-in function"
	fnWay = "rename the method"
	if fd != none:
		what = "a top-level function"
		fnWay = "rename one of them"
	if fd is fd and c.curMod >= 0 and nodes[fd].mod() != c.modules[c.curMod].id:
		for imp in c.modules[c.curMod].imports:
			if nodes[imp].text == nodes[fd].mod():
				fnWay = "write {nodes[imp].text2()}.{name}(...) for the function"
	compileError("AmbiguousCall", [name.copy(), c.showTy(c.implType), what, fnWay])

# a fixed array of numbers or bools (or of such arrays) whose every element is empty
# (`zeros(N)`): what an extern type's array field left out starts as; none for another type
fn emptyArray(mut c Checker, t TypeId, line i64, col i64) NodeId?:
	if tys[t].kind != tArray: return none
	et = innerOf(tys, t)
	k = tys[et].kind
	item NodeId? = none
	if k == tInt:
		item = newNode(nodes, kidIds, nInt, line, col, text = "0")
	elif k == tFloat:
		item = newNode(nodes, kidIds, nFloat, line, col, text = "0.0")
	elif k == tBool:
		item = newNode(nodes, kidIds, nBool, line, col)
	elif k == tArray:
		item = c.emptyArray(et, line, col)
	one = try item
	count = newNode(nodes, kidIds, nInt, line, col, text = str(tys[t].bits))
	items = newNode(nodes, kidIds, nArray, line, col, kids = [one])
	repeat = newNode(nodes, kidIds, nField, line, col, text = "repeat", kids = [items])
	nodes[repeat].flags |= flagInternal
	newNode(nodes, kidIds, nCall, line, col, kids = [repeat, count])

# the default a field or a parameter declares, written again where it is used (its names its
# owner's module's): a value of its own, reading no variable
fn defaultOf(mut c Checker, decl NodeId, owner NodeId, what str):
	val = cloneTree(nodes, kidIds, nodes[decl].kids(kidIds)[0])
	if c.readsVariable(val):
		c.errorAt(
			nodes[decl].line,
			nodes[decl].col,
			compileError("DefaultReadsVariable", ["{what}", "{nodes[decl].text}"])
		)
	c.qualifyInModuleOf(val, owner)
	val

# A default written in another module (a function's, a type's) used where a call or a literal
# is: its constants, functions and struct names given their global names as seen from the
# module of `owner`, so they mean there what they mean where the default was written.
fn qualifyInModuleOf(mut c Checker, e NodeId, owner NodeId):
	savedMod = c.curMod
	savedFile = move c.curFile
	c.enterModuleOf(owner)
	c.qualifyNames(e)
	c.curMod = savedMod
	c.curFile = savedFile

fn qualifyNames(mut c Checker, e NodeId):
	k = nodes[e].kind
	if k == nCall:
		# `Hidden(7)`: the struct of the default's module, made a literal that names it so (a
		# defined type's `Meters(0)` stays a conversion)
		callee = nodes[e].kids(kidIds)[0]
		if nodes[callee].kind == nIdent:
			d = c.constructedStruct(callee)
			if d is d and nodes[d].kind == nStructDecl and not nodes[d].hasFlag(flagTypeAlias) and
				c.asStructLiteral(e, d):
				nodes[e].setText2("")
				k = nStructLit
	if k == nIdent:
		d = c.lookupDecl(nConstDecl, "", nodes[e].text, nodes[e].line, nodes[e].col)
		if d == none:
			d = c.lookupDecl(nFnDecl, "", nodes[e].text, nodes[e].line, nodes[e].col)
		if d == none and not nodes[e].text.isEmpty and nodes[e].text[0] >= 'A' and
			nodes[e].text[0] <= 'Z':
			# a type: `Hidden(7)`, `Mode.Fast`
			d = c.lookupDecl(nStructDecl, "", nodes[e].text, nodes[e].line, nodes[e].col)
		if d is d:
			nodes[e].setText(nodes[d].text.copy(), nodes[d].name)
			if nodes[d].hasFlag(flagTypeAlias):
				nodes[e].setText2(globalAlias)   # a defined type's conversion (aliasCalled)
	elif k == nStructLit and nodes[e].text2() == "":
		d = c.lookupDecl(nStructDecl, "", nodes[e].text, nodes[e].line, nodes[e].col)
		if d is d:
			nodes[e].setText(nodes[d].text.copy(), nodes[d].name)
			nodes[e].setText2(globalAlias)
	for i in 0..c.nodes[e].kids(c.kidIds).len:
		c.qualifyNames(nodes[e].kids(kidIds)[i])
