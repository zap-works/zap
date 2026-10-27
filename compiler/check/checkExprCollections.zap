# The checking of calls on maps and of pipelines with their lambdas (checkExpr.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# the call when e is `x.get(k)` on a map or a pool (whose value an arm may change), else none
fn lookupCall(c Checker, e NodeId) NodeId?:
	if nodes[e].kind != nCall or nodes[c.writtenCallee(e)].kind != nField or
		nodes[c.writtenCallee(e)].text not in ["get", "getLive"]:
		return none
	obj = nodes[c.writtenCallee(e)].kids(kidIds)[0]
	t = typeOf(nodes, obj)
	inner = innerOf(tys, t) if c.tKind(t) == tRef else t
	if c.tKind(inner) == tMap or c.isIndexable(inner): return e
	none

# whether t is a type indexed by its methods: x[k] reads index, a change through it indexMut
# (Pool<T>), and x[k] = v is its set when it has one (env)
fn isIndexable(c Checker, t TypeId):
	c.tKind(t) == tStruct and c.findMethod(tys[t].name, "index") != none

# ---------- built-in methods ----------

fn calleeObj(c Checker, e NodeId):
	nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0]

# The method's name as a value of its own: the method checks compare it and report it while
# they check the arguments, which changes c.
fn calleeName(c Checker, e NodeId):
	nodes[nodes[e].kids(kidIds)[0]].text.copy()

# Methods on {K: V}: get/has/length/isEmpty/keys/values, and set/remove/clear (receiver must be mut).
fn checkMapMethod(mut c Checker, e NodeId, mapT TypeId) TypeId:
	obj = c.calleeObj(e)
	m = c.calleeName(e)
	line = nodes[e].line
	col = nodes[e].col
	keyT = c.innerOrError(mapT)
	valT = tys[mapT].val ?? tyError
	if m == "len":
		c.expectArgs(e, m, 0)
		return tyN64
	if m == "isEmpty":
		c.expectArgs(e, m, 0)
		return tyBool
	if m == "add":
		# counts: the value at the key grows by delta, from zero when the key is new; the key is
		# only copied when it is inserted
		if not c.expectArgs(e, m, 2): return tyError
		c.requireMutRoot(obj, line, col, "add")
		kt = c.checkExpr(c.argAt(e, 0), keyT)
		if not c.rangeArg(e, 0, kt, keyT) and not isRefAssignable(tys, kt, keyT):
			c.errorAt(line, col, compileError("MapAddKey", ["{c.showTy(keyT)}", "{c.showTy(kt)}"]))
		elif not isSameType(tys, kt, keyT):
			c.setArg(e, 0, c.coerceTo(c.argAt(e, 0), keyT))
		if c.tKind(valT) != tInt:
			errorAt(
				c,
				line,
				col,
				compileError("MapAddValueType", ["{c.showTy(valT)}"])
			)
		vt = c.checkExpr(c.argAt(e, 1), valT)
		if not c.rangeArg(e, 1, vt, valT):
			c.errorAt(
				line,
				col,
				compileError("MapAddDelta", ["{c.showTy(valT)}", "{c.showTy(vt)}"])
			)
		return tyUnit
	if m in ["has", "set"] and not nodes[e].hasFlag(flagInternal):
		c.errorAt(line, col, compileError("NoMethod", ["{m}", c.showTy(mapT)]))
		return tyError
	if m in ["get", "has", "remove"]:
		if not c.expectArgs(e, m, 1): return tyError
		if m == "remove":
			c.requireMutRoot(obj, line, col, "remove")
		kt = c.checkExpr(c.argAt(e, 0), keyT)
		c.keepConversion(c.argAt(e, 0))   # a map's key is never widened
		if not c.rangeArg(e, 0, kt, keyT):
			c.errorAt(
				line,
				col,
				compileError("MapKeyArgument", ["{m}", "{c.showTy(keyT)}", "{c.showTy(kt)}"])
			)
		if m == "has": return tyBool
		if m == "get":
			# a reference to the stored value: no copy
			return tyOption(tys, tyRef(tys, valT, false))
		return tyOption(tys, valT)
	if m == "set":
		if not c.expectArgs(e, m, 2): return tyError
		c.requireMutRoot(obj, line, col, "set")
		kt = c.checkExpr(c.argAt(e, 0), keyT)
		c.keepConversion(c.argAt(e, 0))   # a map's key is never widened
		if not c.rangeArg(e, 0, kt, keyT):
			c.errorAt(line, col, compileError("MapSetKey", ["{c.showTy(keyT)}", "{c.showTy(kt)}"]))
		vt = c.checkExpr(c.argAt(e, 1), valT)
		if not isAssignable(tys, vt, valT):
			c.errorAt(
				line,
				col,
				compileError("MapSetValue", ["{c.showTy(valT)}", "{c.showTy(vt)}"])
			)
		c.setArg(e, 1, c.coerceTo(c.argAt(e, 1), valT))
		return tyUnit
	c.checkRuntimeMethod(e, "map", c.showTy(mapT), none)

# the same, its value expected to be of type `want` (-1: any)
fn checkPipelineLambdaFor(mut c Checker, lam NodeId, paramType TypeId, want TypeId?) TypeId:
	line = nodes[lam].line
	col = nodes[lam].col
	if nodes[lam].kind != nLambda:
		# a function value: fn(T) R
		ft = c.checkExpr(lam, none)
		if c.tKind(ft) == tError: return tyError
		if c.tKind(ft) != tFn or tys[ft].params.len != 1 or
			not isSameType(tys, tys[ft].params[0], paramType):
			c.errorAt(
				line,
				col,
				compileError("LambdaExpected", ["{c.showTy(paramType)}", "{c.showTy(ft)}"])
			)
			return tyError
		return retOf(tys, ft)
	if not c.takesOneParam(lam): return tyError
	if not nodes[lam].sub(kidIds).isEmpty:
		# a block body is only meaningful for each; map/filter/sortedBy need a value
		c.enterScope()
		c.addVar(nodes[lam].names(kidIds)[0], paramType, false, true, line, col)
		saveRet = c.currentRet
		saveLoop = c.loopDepth
		c.currentRet = tyUnit
		c.loopDepth = 0
		c.checkBlock(nodes[lam].sub(kidIds)[0])
		c.currentRet = saveRet
		c.loopDepth = saveLoop
		c.exitScope()
		return c.typed(lam, tyUnit)
	c.enterScope()
	c.addVar(nodes[lam].names(kidIds)[0], paramType, false, true, line, col)
	bt = c.checkExpr(nodes[lam].kids(kidIds)[0], want)
	if c.tKind(bt) == tRef:
		# the value each element gives is a value: a reference is copied out
		bt = innerOf(tys, bt)
		c.coerceKid(lam, 0, bt)
	c.exitScope()
	c.typed(lam, c.heldType(bt) if want == none else bt)   # a range's values held as its base's

# print(value) and its kin (eprint, stream.print): one printable value, formatted by code the
# compiler derives for its type
fn checkPrintCall(mut c Checker, e NodeId, name str) TypeId:
	if c.argCount(e) != 1:
		c.errorAt(nodes[e].line, nodes[e].col, compileError("OneArgument", ["{name}"]))
	else:
		at = c.derefIfRef(c.argAt(e, 0), c.checkExpr(c.argAt(e, 0), none))
		c.requireBound(at, "Show", "printing", nodes[e].line, nodes[e].col)
		if not c.isPrintable(at) and c.tKind(at) != tError:
			c.errorAt(nodes[e].line, nodes[e].col, compileError("CannotPrint", ["{c.showTy(at)}"]))
		c.noteFormat(at)
	c.typed(e, tyUnit)

# The enum declaration the identifier obj names in `Enum.Variant` (its text becomes the enum's
# qualified name), -1 when obj is a variable or names no enum, enumFailed when it names an enum
# that could not be made (already reported).
fn enumNamedBy(mut c Checker, obj NodeId) EnumNamed:
	if nodes[obj].kind != nIdent or c.lookupVarNo(nameOf(nodes, obj)) >= 0: return .NoEnum
	named, made = c.namedTypeOf(obj)
	if named is named and nodes[named].kind == nEnumDecl and made == none: return .EnumUnmade
	if named is named and made is enumd and nodes[enumd].kind == nEnumDecl:
		nodes[obj].setText(nodes[named].text.copy(), nodes[named].name)
		return .NamedEnum(enumd)
	.NoEnum

# what an identifier names as an enum
type EnumNamed:
	NoEnum   # a variable, or no enum
	EnumUnmade   # an enum that could not be made (reported)
	NamedEnum(decl NodeId)

# whether the pipeline lambda lam takes the one parameter an element binds (reported when not)
fn takesOneParam(mut c Checker, lam NodeId):
	if nodes[lam].names(kidIds).len != 1:
		c.errorAt(nodes[lam].line, nodes[lam].col, compileError("PipelineLambdaArity", []))
		return false
	true

# whether count's argument is a value to compare the elements with, not what holds for them: a
# literal, or a local that is no function
fn isCountedValue(mut c Checker, e NodeId) bool:
	k = nodes[e].kind
	if k in [nInt, nFloat, nStr, nBool]: return true
	if k == nUnary: return c.isCountedValue(nodes[e].kids(kidIds)[0])
	if k != nIdent or nodes[e].hasFlag(flagPlaceholder): return false
	v = c.lookupVarNo(nameOf(nodes, e))
	v >= 0 and c.tKind(c.vars[v].ty) != tFn

fn isBlockLambda(c Checker, e NodeId):
	nodes[e].kind == nLambda and not nodes[e].sub(kidIds).isEmpty

# The pipeline methods, compiled in line over a list or a range (lo..hi, (lo..hi).by(s)): map,
# filter, flatMap, each and sortedBy make a list or run a body for each element; all, any,
# count, find, reduce, minBy, maxBy and sum (of a range: a list's is the runtime's) reduce it to
# one value (a range's find, minBy and maxBy the value itself). The type of the call, or -2 when m is none of them.
# whether lambda lam is `x => x` or `x => i64(x)` / `u64(x)` (its value the element's,
# widened)
fn widensParam(c Checker, lam NodeId):
	if nodes[lam].kind != nLambda or not nodes[lam].sub(kidIds).isEmpty or nodes[lam].names(kidIds).len != 1:
		return false
	body = nodes[lam].kids(kidIds)[0]
	x = body
	if nodes[body].kind == nCall and nodes[body].kids(kidIds).len == 1 and
		nodes[nodes[body].kids(kidIds)[0]].kind == nField:
		m = nodes[nodes[body].kids(kidIds)[0]].text
		if m != "toI64" and m != "toU64": return false
		x = nodes[nodes[body].kids(kidIds)[0]].kids(kidIds)[0]
	nodes[x].kind == nIdent and nodes[x].text == nodes[lam].names(kidIds)[0]

fn checkPipeline(mut c Checker, e NodeId, m str, elem TypeId, onRange bool) TypeId?:
	line = nodes[e].line
	col = nodes[e].col
	nargs = c.argCount(e)
	if m == "count" and nargs == 1 and c.isCountedValue(c.argAt(e, 0)):
		# xs.count(v): the elements equal to v, counted as xs.count(it == v)
		element = newNode(nodes, kidIds, nIdent, line, col, text = "$it")
		nodes[element].flags |= flagPlaceholder
		eq = newNode(nodes, kidIds, nBinary, line, col, kids = [element, c.argAt(e, 0)])
		nodes[eq].ival = binEq
		c.setArg(e, 0, eq)
	if nargs == 1 and m in pipelineSteps and m != "zip":
		c.itLambda(c.argAt(e, 0))
	if m == "sum" and nargs == 1 and not onRange and c.tKind(elem) == tInt and
		tys[elem].bits == 8 and not tys[elem].isSigned and c.widensParam(c.argAt(e, 0)):
		# bytes widened and added: eight at a time in the runtime
		body = nodes[c.argAt(e, 0)].kids(kidIds)[0]
		unsigned = nodes[body].kind == nCall and nodes[nodes[body].kids(kidIds)[0]].text == "toU64"
		nodes[e].setKids(kidIds, [nodes[e].kids(kidIds)[0]])   # the lambda goes: nothing runs it
		nodes[e].flags |= flagBytesSum
		return tyInt(64, false) if unsigned else tyInt(64, true)
	if m == "mean" and (nargs == 1 or
			nargs == 0 and c.tKind(elem) != tError and
			not (c.tKind(elem) == tFloat and tys[elem].bits == 64)):
		# xs.mean(f): the mean of f over the elements, written over as xs.map(f).mean(); the
		# mean of numbers other than f64s is their f64s' (xs.map(f64(it)).mean())
		if nargs == 0:
			element = newNode(nodes, kidIds, nIdent, line, col, text = "$it")
			nodes[element].flags |= flagPlaceholder
			wide = newNode(nodes, kidIds, nField, line, col, text = "toF64", kids = [element])
			madeKid = newNode(nodes, kidIds, nCall, line, col, kids = [wide])
			nodes[e].pushKid(kidIds, madeKid)
	if (m == "sum" or m == "mean") and nodes[e].kids(kidIds).len == 2:
		# xs.sum(f): the sum of f over the elements, written over as xs.map(f).sum()
		callee = nodes[e].kids(kidIds)[0]
		mapField = newNode(nodes, kidIds, nField, line, col, text = "map")
		nodes[mapField].setKids(kidIds, [nodes[callee].kids(kidIds)[0]])
		mapped = newNode(nodes, kidIds, nCall, line, col)
		madeKids = [mapField, c.argAt(e, 0)]
		nodes[mapped].setKids(kidIds, madeKids)
		nodes[callee].setKids(kidIds, [mapped])
		nodes[e].setKids(kidIds, [callee])
		return c.checkExpr(e, none)
	if m == "sum" and onRange:
		c.expectArgs(e, m, 0)
		return elem
	if m == "reduce": return c.checkReduce(e, elem, none)
	if m in ["mean", "groupBy", "countBy", "zip"]: return c.checkCollectStep(e, m, elem)
	if m not in pipelineSteps or m == "sum": return none
	if onRange and not isStepOnRange(m):
		c.errorAt(line, col, compileError("RangeNotList", ["{m}"]))
		return tyError
	if nargs != 1:
		c.errorAt(line, col, compileError("OneLambda", ["{m}"]))
		return tyError
	c.checkPipelineStep(e, m, elem, onRange)

fn checkPipelineStep(mut c Checker, e NodeId, m str, elem TypeId, onRange bool) TypeId?:
	line = nodes[e].line
	col = nodes[e].col
	lam = c.argAt(e, 0)
	bt TypeId = tyError
	bodyExpected = c.mapExpected if m == "map" and c.tKind(c.mapExpected) == tOption else none   # (a bare none takes its type)
	c.mapExpected = none   # not for the pipelines inside
	if c.isBlockLambda(lam):
		bt = c.checkBlockPipelineLambda(lam, elem)   # its last expression is the value
	else:
		bt = c.checkPipelineLambdaFor(lam, elem, bodyExpected)
		c.noteItForm(lam, elem)
	bk = c.tKind(bt)
	if m == "map" and bk == tStr and c.isPartOfParameter(lam):
		# a str of the element: lent, not copied (`ms.map(.name)` is a (ref str)[] into ms)
		nodes[lam].flags |= flagKeyLambda
		return tyList(tys, tyRef(tys, bt, false))
	if m == "map": return tyList(tys, c.heldType(bt))
	if m == "flatMap":
		if bk != tList and bk != tError:
			c.errorAt(line, col, compileError("FlatMapNotList", ["{c.showTy(bt)}"]))
			return tyError
		if nodes[lam].kind == nLambda and c.lambdaValueOf(lam) is value:
			bodyK = nodes[value].kind
			if bodyK in [nIdent, nField, nIndex]:
				errorAt(
					c,
					line,
					col,
					compileError("FlatMapBorrows", [])
				)
				return tyError
		return bt
	if m in ["sortedBy", "sortBy", "minBy", "maxBy"]:
		keyed = bk == tStr or c.isTupleLiteral(c.lambdaValueOf(lam))
		if nodes[lam].kind == nLambda and keyed:
			nodes[lam].flags |= flagKeyLambda   # a key compared while the elements stand: lent
		if not c.typeHasOrd(bt):
			c.errorAt(line, col, compileError("SortKeyNotOrdered", ["{m}", "{c.showTy(bt)}"]))
		elif not typeIsNumeric(tys, bt) and bk != tStr and bk != tError:
			c.noteDerive(bt, deriveCmp | deriveEq)
		if m == "sortedBy": return tyList(tys, elem)
		if m == "sortBy":
			c.requireMutRoot(c.calleeObj(e), line, col, m)
			return tyUnit
		if onRange: return tyOption(tys, elem)   # the value itself
		return tyOption(tys, tyRef(tys, elem, false))
	if bk != tBool and bk != tError:
		c.errorAt(line, col, compileError("PredicateNotBool", ["{m}", "{c.showTy(bt)}"]))
	if m == "filter": return tyList(tys, elem)
	if m == "all" or m == "any": return tyBool
	if m == "count": return tyN64
	if m == "findIndex":
		return tyOption(tys, tyN64)   # the index of the first element it holds for
	if onRange:
		return tyOption(tys, elem)   # find: the value itself
	tyOption(tys, tyRef(tys, elem, false))   # find: the element borrowed

# mean() of f64s (other numbers and mean(f) were written over as a map of f64s), groupBy(key),
# countBy(key) and zip(ys): what each makes of the elements of a list, a range or a Seq, its steps
# before it run in its loop (irLower.zap)
fn checkCollectStep(mut c Checker, e NodeId, m str, elem TypeId) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	if m == "mean":
		c.expectArgs(e, m, 0)
		return tyFloat(64)
	if c.argCount(e) != 1:
		c.errorAt(line, col, compileError("ZipOfOneList" if m == "zip" else "OneLambda", ["{m}"]))
		return tyError
	arg = c.argAt(e, 0)
	if m == "zip":
		ys = c.derefIfRef(arg, c.checkExpr(arg, none))
		if c.tKind(ys) == tError: return tyError
		if c.tKind(ys) != tList:
			c.errorAt(line, col, compileError("ZipOfOneList", ["{m}"]))
			return tyError
		return tyList(tys, c.pairType(elem, innerOf(tys, ys), line, col))
	if nodes[arg].kind == nLambda:
		nodes[arg].flags |= flagKeyLambda   # read while the element stands, copied into the map
	key = c.heldType(c.derefType(c.checkPipelineLambdaFor(arg, elem, none)))
	if c.tKind(key) == tError: return tyError
	c.requireBound(key, "Hash", "{m}'s key", line, col)
	tyMap(tys, key, tyInt(64, true) if m == "countBy" else tyList(tys, elem))

# the tuple type (a, b), as the literal of two values of those types is checked
fn pairType(mut c Checker, a TypeId, b TypeId, line i64, col i64):
	c.enterScope()
	c.addVar("$pair0", a, false, false, line, col)
	c.addVar("$pair1", b, false, false, line, col)
	first = newNode(nodes, kidIds, nIdent, line, col, text = "$pair0")
	second = newNode(nodes, kidIds, nIdent, line, col, text = "$pair1")
	pair = newNode(nodes, kidIds, nStructLit, line, col, text = "Tuple2", kids = [first, second])
	nodes[pair].setText2(kidIds, "$rt")
	nodes[pair].nodeMore(kidIds).names = ["_0", "_1"]
	t = c.checkExpr(pair, none)
	c.exitScope()
	t

# a step over a Seq of elem: filter and map give a Seq (they run in the loop that walks it, so
# map's values own nothing), the rest a value as a list's do; toList() the elements in a list
fn checkSeqStep(mut c Checker, e NodeId, m str, elem TypeId):
	line = nodes[e].line
	col = nodes[e].col
	if m == "toList":
		c.expectArgs(e, m, 0)
		return tyList(tys, elem)
	if m == "sum" and c.argCount(e) == 0:
		if not typeIsNumeric(tys, elem) and c.tKind(elem) != tError:
			c.errorAt(line, col, compileError("SumNotNumbers", ["{c.showTy(elem)}"]))
		return elem
	if m == "count" and c.argCount(e) == 0: return tyInt(64, true)   # the elements
	if m not in seqSteps:
		c.checkArgsAlone(e)
		errorAt(
			c,
			line,
			col,
			compileError("SeqLacksMethod", ["{seqSteps.join(", ")}", "{m}"])
		)
		return tyError
	res = c.checkPipeline(e, m, elem, false) ?? tyError
	if m == "filter" and c.tKind(res) == tList: return tySeq(tys, elem)
	if m == "map" and c.tKind(res) == tList:
		if not c.isPlainType(innerOf(tys, res)):
			c.errorAt(line, col, compileError("SeqMapOwns", ["{c.showTy(tys[res].inner)}"]))
		return tySeq(tys, innerOf(tys, res))
	res

# whether lam is `x => x.a.b`: a lambda whose value is a field (of a field...) of its parameter
fn isPartOfParameter(c Checker, lam NodeId):
	if nodes[lam].kind != nLambda or not nodes[lam].sub(kidIds).isEmpty or nodes[lam].names(kidIds).len != 1:
		return false
	at = nodes[lam].kids(kidIds)[0]
	if nodes[at].kind != nField: return false
	while nodes[at].kind == nField and not nodes[at].hasFlag(flagSafe) and
		nodes[at].kids(kidIds).len == 1:
		at = nodes[at].kids(kidIds)[0]
	nodes[at].kind == nIdent and nodes[at].text == nodes[lam].names(kidIds)[0]

# whether e is a call of map or filter (a pipeline whose steps a consumer may run in its loop)
fn isMapOrFilter(c Checker, e NodeId):
	if nodes[e].kind != nCall: return false
	callee = nodes[e].kids(kidIds)[0]
	nodes[callee].kind == nField and (nodes[callee].text == "map" or nodes[callee].text == "filter")

# a.sum() of an array: written over as a.reduce(0, (acc, x) => acc + x), the zero of the element type
fn sumAsReduce(mut c Checker, e NodeId, elem TypeId):
	callee = nodes[e].kids(kidIds)[0]
	line = nodes[e].line
	col = nodes[e].col
	nodes[callee].setText("reduce")
	zero = newNode(nodes, kidIds, nInt, line, col, text = "0")
	if c.tKind(elem) == tFloat:
		nodes[zero].kind = nFloat
		nodes[zero].setText("0.0")
	acc = newNode(nodes, kidIds, nIdent, line, col, text = "$acc")
	x = newNode(nodes, kidIds, nIdent, line, col, text = "$x")
	add = newNode(nodes, kidIds, nBinary, line, col)
	nodes[add].ival = binAdd
	nodes[add].setKids(kidIds, [acc, x])
	lam = newNode(nodes, kidIds, nLambda, line, col)
	nodes[lam].nodeMore(kidIds).names = ["$acc", "$x"]
	nodes[lam].setKids(kidIds, [add])
	nodes[e].setKids(kidIds, [callee, zero, lam])

# x => { ...; value } in a pipeline: a closure of the element type, its result the block's last
# expression (the backend calls it for each element); the result type, or the error type
# two numbers of different types: both operands of e widened to their common type, which is
# given; none when they share a type already or have no common one
fn widenToCommon(mut c Checker, e NodeId, lt TypeId, rt TypeId) TypeId?:
	if not typeIsNumeric(tys, lt) or not typeIsNumeric(tys, rt) or isSameType(tys, lt, rt):
		return none
	common = try c.numCommon(lt, rt)
	c.widenKid(e, 0, common)
	c.widenKid(e, 1, common)
	common

# a lambda's value expression: its body, or a block's last expression (none when the block ends
# otherwise, or when lam is a function by name)
fn lambdaValueOf(c Checker, lam NodeId) NodeId?:
	if nodes[lam].kind != nLambda: return none
	if nodes[lam].sub(kidIds).isEmpty: return nodes[lam].kids(kidIds)[0]
	stmts = nodes[nodes[lam].sub(kidIds)[0]].kids(kidIds)
	if stmts.isEmpty: return none
	last = stmts[len - 1]
	nodes[last].kids(kidIds)[0] if (
		nodes[last].kind == nExprStmt or nodes[last].kind == nReturn
	) and
		nodes[last].kids(kidIds).len == 1
		else none

fn checkBlockPipelineLambda(mut c Checker, lam NodeId, elem TypeId):
	if not c.takesOneParam(lam): return tyError
	nodes[lam].nodePart(kidIds).types[0] = c.typeToTE(elem)
	ft = c.checkExpr(lam, none)
	if c.tKind(ft) != tFn: return tyError
	rt = tys[ft].ret ?? tyUnit
	if c.tKind(rt) == tUnit:
		errorAt(
			c,
			nodes[lam].line,
			nodes[lam].col,
			compileError("PipelineBlockValue", [])
		)
		return tyError
	rt

# xs.reduce(start, (acc, x) => next): the accumulator is a number or a bool, the lambda gives the
# next one from it and an element
fn checkReduce(mut c Checker, e NodeId, elem TypeId, startT TypeId?):
	line = nodes[e].line
	col = nodes[e].col
	if c.argCount(e) != 2:
		c.errorAt(line, col, compileError("ReduceArguments", []))
		return tyError
	init = c.argAt(e, 0)
	accT = c.derefIfRef(init, c.checkExpr(init, startT))
	if c.tKind(accT) == tError: return tyError
	if not c.isScalar(accT) or c.tKind(accT) == tUnit:
		c.errorAt(line, col, compileError("ReduceAccumulator", ["{c.showTy(accT)}"]))
		return tyError
	lam = c.argAt(e, 1)
	# the block form of one expression (zap fmt's for a long lambda) is read as the expression
	if nodes[lam].kind == nLambda and not nodes[lam].sub(kidIds).isEmpty and
		nodes[nodes[lam].sub(kidIds)[0]].kids(kidIds).len == 1 and c.lambdaValueOf(lam) is value:
		nodes[lam].setKids(kidIds, [value])
		nodes[lam].nodePart(kidIds).sub = []
	if nodes[lam].kind != nLambda or nodes[lam].names(kidIds).len != 2 or not nodes[lam].sub(kidIds).isEmpty:
		c.errorAt(line, col, compileError("ReduceLambda", []))
		return tyError
	c.enterScope()
	c.addVar(nodes[lam].names(kidIds)[0], accT, false, true, line, col)
	c.addVar(nodes[lam].names(kidIds)[1], elem, false, true, line, col)
	body = nodes[lam].kids(kidIds)[0]
	bt = c.derefIfRef(body, c.checkExpr(body, accT))
	c.exitScope()
	if c.tKind(bt) != tError and not isAssignable(tys, bt, accT):
		errorAt(
			c,
			line,
			col,
			compileError("ReduceLambdaType", ["{c.showTy(bt)}", "{c.showTy(accT)}"])
		)
	c.typed(lam, accT)
	accT

# the range a method is called on, lo..hi; none when the receiver is not a range
fn rangeReceiver(mut c Checker, callee NodeId) NodeId?:
	obj = nodes[callee].kids(kidIds)[0]
	if nodes[obj].kind == nRange: obj else: none

fn checkIntArg(mut c Checker, e NodeId, i i64, what str):
	at = c.checkExpr(c.argAt(e, i), tyInt(64, true))
	if c.tKind(at) != tInt and c.tKind(at) != tError:
		c.errorAt(
			nodes[e].line,
			nodes[e].col,
			compileError("IntegerArgument", ["{what}", "{c.showTy(at)}"])
		)

# A place passed where the parameter is `ref T` (or `mut ref T`) borrows it without the
# caller writing `ref`: the argument becomes `ref place` here.
fn inferRefArg(mut c Checker, e NodeId, i i64, pt TypeId):
	if c.tKind(pt) != tRef: return
	a = c.argAt(e, i)
	k = nodes[a].kind
	if k == nUnary and (nodes[a].ival == unRef or nodes[a].ival == unMutRef): return
	if k != nIdent and k != nField and k != nIndex: return
	if c.lvalueRoot(a) < 0: return
	if k == nIdent:
		v = c.lookupVarNo(nameOf(nodes, a))
		if v >= 0 and c.tKind(c.vars[v].ty) == tRef:
			return   # already a reference: passed on as it is
	r = newNode(nodes, kidIds, nUnary, nodes[a].line, nodes[a].col)
	op = unRef
	if tys[pt].bits == 1:
		op = unMutRef
	nodes[r].ival = i32(op)
	nodes[r].pushKid(kidIds, a)
	c.setArg(e, i, r)

fn checkStrArg(mut c Checker, e NodeId, i i64, what str):
	at = c.checkExpr(c.argAt(e, i), tyStr)
	if c.tKind(at) != tStr and c.tKind(at) != tError:
		c.errorAt(
			nodes[e].line,
			nodes[e].col,
			compileError("StrArgument", ["{what}", "{c.showTy(at)}"])
		)
