# The checking of fixed arrays and parallel pipelines (checkExpr.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# [a, b, c] where a T[N] is expected: exactly N values of T; the empty literal the compiler
# writes for a declaration without values is N zeros (each element's empty value)
fn checkFixedArrayLit(mut c Checker, e NodeId, at TypeId) TypeId:
	n = tys[at].bits
	elem = innerOf(tys, at)
	# the elements are read from e at each use: checking changes c (element i is read before
	# it is replaced by its coerced form)
	nelems = nodes[e].kids(kidIds).len
	if nelems == 0 and nodes[e].hasFlag(flagInternal): return c.typed(e, at)
	if nelems == 1 and (nodes[e].ival == n or nodes[e].ival == -1):
		nelems = n   # fill(n, x): one value for every element (-1: the number parameter's)
	if nelems != n:
		errorAt(
			c,
			nodes[e].line,
			nodes[e].col,
			compileError("FixedArrayCount", ["{c.showTy(at)}", "{n}", "{nelems}"])
		)
		return c.typed(e, tyError)
	for i in 0..c.nodes[e].kids(c.kidIds).len:
		v = nodes[e].kids(kidIds)[i]
		vt = c.checkExpr(v, elem)
		if not isAssignable(tys, vt, elem) and c.tKind(vt) != tError:
			errorAt(
				c,
				nodes[v].line,
				nodes[v].col,
				compileError(
					"FixedArrayElement",
					["{c.showTy(at)}", "{c.showTy(elem)}", "{c.showTy(vt)}"]
				)
			)
		madeKid = c.coerceTo(v, elem)
		nodes[e].setKid(kidIds, i, madeKid)
	c.typed(e, at)

# fill(N, x) where a T[N] is expected: an array literal of the one value x (ival N), evaluated
# once and copied into the other elements, as a list's repeat copies its element
fn checkFixedRepeat(mut c Checker, e NodeId, at TypeId) TypeId:
	n = tys[at].bits
	callee = nodes[e].kids(kidIds)[0]
	x = nodes[nodes[callee].kids(kidIds)[0]].kids(kidIds)[0]
	count = c.argAt(e, 0)
	np = c.numberParam(nodes[count].text) if nodes[count].kind == nIdent else none
	if np is np and (tys[np].bits == n if n >= 0 else isSameType(tys, np, tys[at].val)):
		# fill(N, x) for a T[N]: as long as each instance's array
		nodes[e].kind = nArray
		nodes[e].setKids(kidIds, [x])
		nodes[e].ival = -1
		return c.checkFixedArrayLit(e, at)
	if nodes[count].kind != nInt or (i64.parse(nodes[count].text) ?? -1) != n:
		errorAt(
			c,
			nodes[e].line,
			nodes[e].col,
			compileError("FixedArrayRepeat", ["{c.showTy(at)}", "{n}"])
		)
		return c.typed(e, tyError)
	nodes[e].kind = nArray
	nodes[e].setKids(kidIds, [x])
	nodes[e].ival = i32(n)
	c.checkFixedArrayLit(e, at)

# ---------- parallel pipelines ----------

# The `.parallel()` the source chain of the pipeline call e starts from (`xs.parallel().map(f)`,
# `xs.parallel().filter(p).sum(f)`: maps and filters between), or -1.
fn parallelStep(c Checker, e NodeId) NodeId?:
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind != nField or nodes[callee].kids(kidIds).len != 1 or
		nodes[callee].text not in pipelineSteps:
		return none   # xs.parallel().map(f).len: length reads the list made
	at = nodes[callee].kids(kidIds)[0]
	while nodes[at].kind == nCall and not c.isParallelStep(at):
		f = nodes[at].kids(kidIds)[0]
		if nodes[f].kind != nField or nodes[f].kids(kidIds).len != 1 or
			nodes[f].text != "map" and nodes[f].text != "filter":
			return none
		at = nodes[f].kids(kidIds)[0]
	at if c.isParallelStep(at) else none

# the methods of a pipeline (those a parallel step may lead to, or refuse with a reason)

# `xs.parallel()`: the step a parallel pipeline starts from
fn isParallelStep(c Checker, e NodeId):
	if nodes[e].kind != nCall or nodes[e].kids(kidIds).len != 1: return false
	f = nodes[e].kids(kidIds)[0]
	nodes[f].kind == nField and nodes[f].text == "parallel" and nodes[f].kids(kidIds).len == 1

# `xs.parallel()` of a list or a range with no step after it: an error that says how one goes
# on; whether it is that (a struct may have a method of its own by that name)
fn parallelAlone(mut c Checker, e NodeId):
	src = c.parallelSource(e)
	if nodes[src].kind != nRange:
		k = c.tKind(c.derefIfRef(src, c.checkExpr(src, none)))
		if k != tList and k != tArray: return false
	c.errorAt(nodes[e].line, nodes[e].col, compileError("ParallelStartsPipeline", []))
	true

# the source a parallel step reads (`xs` of `xs.parallel()`)
fn parallelSource(c Checker, par NodeId):
	nodes[nodes[par].kids(kidIds)[0]].kids(kidIds)[0]

fn binaryNode(mut c Checker, op i64, l NodeId, r NodeId, line i64, col i64):
	b = newNode(nodes, kidIds, nBinary, line, col, kids = [l, r])
	nodes[b].ival = i32(op)
	b

# parallelChunks(), $c, and the bounds of part $c of n things: $c * n / chunks, ($c + 1) * n / chunks
# a name the compiler writes for one of them
fn internalName(mut c Checker, name str, line i64, col i64):
	n = newNode(nodes, kidIds, nIdent, line, col, text = name.copy())
	nodes[n].flags |= flagInternal
	n

fn chunksCall(mut c Checker, line i64, col i64) NodeId:
	newNode(nodes, kidIds, nCall, line, col, kids = [c.internalName("parallelChunks", line, col)])

fn partBound(mut c Checker, n NodeId, after bool, line i64, col i64) NodeId:
	at = newNode(nodes, kidIds, nIdent, line, col, text = "$c")
	if after:
		at = c.binaryNode(
			binAdd,
			at,
			newNode(nodes, kidIds, nInt, line, col, text = "1"),
			line,
			col
		)
	binaryNode(
		c,
		binDiv,
		c.binaryNode(binMul, at, n, line, col),
		c.chunksCall(line, col),
		line,
		col
	)

# the methods a bound of a parallel range may call: they compute, with no effect (and the
# integer conversions)
readOnlyMethods = ["len", "min", "max", "abs", "clamp"]

# whether e can be evaluated again for each part with the same value and no effect: literals,
# names, fields, operators over them and the read-only methods (`n.min(m)`, `xs.len`)
fn readsAgain(c Checker, e NodeId) bool:
	k = nodes[e].kind
	if k in [nInt, nFloat, nBool, nIdent]: return true
	if k == nField or k == nBinary or k == nUnary and nodes[e].ival != unMove:
		return nodes[e].kids(kidIds).all(c.readsAgain(it))
	if k == nCall:
		callee = nodes[e].kids(kidIds)[0]
		return nodes[callee].kind == nField and
			(nodes[callee].text in readOnlyMethods or nodes[callee].text in intConversions) and
			nodes[e].kids(kidIds).all(it == callee or c.readsAgain(it)) and
			c.readsAgain(nodes[callee].kids(kidIds)[0])
	false

# Part $c of the source of the parallel step par, of parallelChunks() parts: a range's share
# of its values, a list's slice (`xs.slice(a, b)`); none after an error (the source must be a
# name, a field or a range: it is read once for each part).
fn parallelPart(mut c Checker, par NodeId) NodeId?:
	line = nodes[par].line
	col = nodes[par].col
	src = c.parallelSource(par)
	k = nodes[src].kind
	if k == nRange and nodes[src].kids(kidIds).len == 2:
		lo = nodes[src].kids(kidIds)[0]
		hi = nodes[src].kids(kidIds)[1]
		if not c.readsAgain(lo) or not c.readsAgain(hi):
			c.errorAt(line, col, compileError("ParallelRangeBounds", []))
			return none
		span1 = c.binaryNode(
			binSub,
			cloneTree(nodes, kidIds, hi),
			cloneTree(nodes, kidIds, lo),
			line,
			col
		)
		a = binaryNode(
			c,
			binAdd,
			cloneTree(nodes, kidIds, lo),
			c.partBound(span1, false, line, col),
			line,
			col
		)
		span2 = c.binaryNode(
			binSub,
			cloneTree(nodes, kidIds, hi),
			cloneTree(nodes, kidIds, lo),
			line,
			col
		)
		b = binaryNode(
			c,
			binAdd,
			cloneTree(nodes, kidIds, lo),
			c.partBound(span2, true, line, col),
			line,
			col
		)
		return newNode(nodes, kidIds, nRange, line, col, kids = [a, b])
	if k != nIdent and k != nField:
		c.errorAt(line, col, compileError("ParallelSourceUnbound", []))
		return none
	a = c.partBound(
		lenOf(nodes, kidIds, line, col, cloneTree(nodes, kidIds, src)),
		false,
		line,
		col
	)
	b = c.partBound(lenOf(nodes, kidIds, line, col, cloneTree(nodes, kidIds, src)), true, line, col)
	slice = newNode(
		nodes,
		kidIds,
		nField,
		line,
		col,
		text = "slice",
		kids = [cloneTree(nodes, kidIds, src)]
	)
	part = newNode(nodes, kidIds, nCall, line, col, kids = [slice, a, b])
	nodes[part].flags |= flagInternal
	part

# A pipeline from a parallel step, written over as parts that run on every processor at once:
# `xs.parallel().filter(p).sum(f)` is parallelMap(parallelChunks(), $c => part($c).filter(p).sum(f))
# summed; map, filter and flatMap join the parts' lists in order (listJoinParts), sum and count
# add theirs, any and all ask theirs. The lambdas run on several threads: they read what they
# capture.
# xs.parallel()...sortedBy(f): the steps before it run in parallel (a pipeline of their own) and
# the sort on every processor (listSortByKeysParallel); xs.parallel().minBy(f) and maxBy(f): the
# keys made on every processor, the element picked by them (listPickByKeys)
fn checkParallelPick(mut c Checker, e NodeId, par NodeId, expected TypeId?) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	callee = nodes[e].kids(kidIds)[0]
	m = nodes[callee].text.copy()
	recv = nodes[callee].kids(kidIds)[0]
	if m == "sortedBy":
		if recv == par:
			madeKid = c.parallelSource(par)
			nodes[callee].setKid(kidIds, 0, madeKid)
		nodes[e].flags |= flagParallelSort
		return c.checkExpr(e, expected)
	src = c.parallelSource(par)
	sk = nodes[src].kind
	if recv != par or sk != nIdent and sk != nField:
		errorAt(
			c,
			line,
			col,
			compileError("ParallelNeedsName", ["{m}"])
		)
		return tyError
	keys = newNode(
		nodes,
		kidIds,
		nCall,
		line,
		col,
		kids = [
			newNode(nodes, kidIds, nField, line, col, text = "map", kids = [cloneTree(nodes, kidIds, par)]),
			c.argAt(e, 0)
		]
	)
	wantMax = newNode(nodes, kidIds, nBool, line, col)
	nodes[wantMax].ival = 1 if m == "maxBy" else 0
	pick = newNode(
		nodes,
		kidIds,
		nCall,
		line,
		col,
		kids = [
			c.internalName("listPickByKeys", line, col),
			cloneTree(nodes, kidIds, src),
			keys,
			wantMax
		]
	)
	nodes[e] = nodes[pick].copy()
	c.checkExpr(e, expected)

fn checkParallelPipeline(mut c Checker, e NodeId, par NodeId, expected TypeId?) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	m = nodes[nodes[e].kids(kidIds)[0]].text.copy()
	if c.argCount(e) == 1:
		c.itLambda(c.argAt(e, 0))
		c.noteItForm(c.argAt(e, 0), none)   # the steps below write the lambda over before checking it
	if m in ["sortedBy", "minBy", "maxBy"]: return c.checkParallelPick(e, par, expected)
	if not isStepParallel(m):
		steps = pipelineSteps.filter(s: isStepParallel(s)).join(", ")
		c.errorAt(line, col, compileError("NotParallel", ["{m}", "{steps}"]))
		return tyError
	if m == "map" and nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0] == par:
		return c.checkParallelMap(e, par, expected)
	inner = cloneTree(nodes, kidIds, e)
	parIn = c.parallelStep(inner) ?? return tyError
	part = c.parallelPart(parIn) ?? return tyError
	nodes[parIn] = nodes[part].copy()
	lam = newNode(nodes, kidIds, nLambda, line, col, kids = [inner])
	nodes[lam].nodeMore().names = ["$c"]
	nodes[lam].nodePart().types = [newNode(nodes, kidIds, nTyAbsent, line, col)]
	parts = newNode(
		nodes,
		kidIds,
		nCall,
		line,
		col,
		kids = [c.internalName("parallelMap", line, col), c.chunksCall(line, col), lam]
	)
	outer = parts
	if m in ["map", "filter", "flatMap"]:
		outer = newNode(
			nodes,
			kidIds,
			nCall,
			line,
			col,
			kids = [c.internalName("listJoinParts", line, col), parts]
		)
	elif m == "groupBy" or m == "countBy":
		merge = "mapMergeGroups" if m == "groupBy" else "mapMergeCounts"
		outer = newNode(
			nodes,
			kidIds,
			nCall,
			line,
			col,
			kids = [c.internalName(merge, line, col), parts]
		)
	elif m == "sum" or m == "count":
		outer = newNode(
			nodes,
			kidIds,
			nCall,
			line,
			col,
			kids = [newNode(nodes, kidIds, nField, line, col, text = "sum", kids = [parts])]
		)
	else:
		same = newNode(
			nodes,
			kidIds,
			nLambda,
			line,
			col,
			kids = [newNode(nodes, kidIds, nIdent, line, col, text = "$b")]
		)
		nodes[same].nodeMore().names = ["$b"]
		nodes[same].nodePart().types = [newNode(nodes, kidIds, nTyAbsent, line, col)]
		outer = newNode(
			nodes,
			kidIds,
			nCall,
			line,
			col,
			kids = [
				newNode(nodes, kidIds, nField, line, col, text = m.copy(), kids = [parts]),
				same
			]
		)
	nodes[e] = nodes[outer].copy()
	c.checkExpr(e, expected)

# `src.parallel().map(f)` with nothing between: parallelMap(n, $k => { x = element $k; f's body })
# (the source's count, a range's lo + $k or a list's xs[$k]), each element a task of its own as
# the pool hands them out, so uneven work balances; f's block, if it has one, runs as written.
fn checkParallelMap(mut c Checker, e NodeId, par NodeId, expected TypeId?) TypeId:
	call = c.parallelMapCall(e, par, "parallelMap") ?? return tyError
	nodes[e] = nodes[call].copy()
	c.checkExpr(e, expected)

# the call of the runtime's function name (parallelMap, parallelStream) that makes e =
# `src.parallel().map(f)`: name(n, $k => { x = element $k; f's body }), none after an error
fn parallelMapCall(mut c Checker, e NodeId, par NodeId, name str) NodeId?:
	line = nodes[e].line
	col = nodes[e].col
	src = c.parallelSource(par)
	f = c.argAt(e, 0)
	k = newNode(nodes, kidIds, nIdent, line, col, text = "$k")
	count, elem = try c.parallelCounted(src, k, line, col)
	lam = newNode(nodes, kidIds, nLambda, line, col)
	nodes[lam].nodeMore().names = ["$k"]
	nodes[lam].nodePart().types = [newNode(nodes, kidIds, nTyAbsent, line, col)]
	if nodes[f].kind == nLambda and nodes[f].names().len == 1:
		bind = newNode(
			nodes,
			kidIds,
			nLet,
			line,
			col,
			text = nodes[f].names()[0].copy(),
			kids = [elem]
		)
		stmts = [bind]
		if not nodes[f].sub().isEmpty:
			stmts.extend(nodes[nodes[f].sub()[0]].kids(kidIds))
		else:
			stmts.push(
				newNode(nodes, kidIds, nExprStmt, line, col, kids = [nodes[f].kids(kidIds)[0]])
			)
		nodes[lam].nodePart().sub = [newNode(nodes, kidIds, nBlock, line, col, kids = stmts)]
	else:
		madeKids = [newNode(nodes, kidIds, nCall, line, col, kids = [f, elem])]
		nodes[lam].setKids(kidIds, madeKids)
	newNode(nodes, kidIds, nCall, line, col, kids = [c.internalName(name, line, col), count, lam])

# Whether an extern's u8[] parameter (pt) takes the argument of type at as its bytes: a list
# of plain values (numbers, structs of them: vertices, pixels), whose buffer the system receives
# as it would a u8[]'s.
fn listOfBytes(mut c Checker, at TypeId, pt TypeId):
	if c.tKind(pt) != tList or not isSameType(tys, tys[pt].inner, tyInt(8, false)): return false
	t = at
	if c.tKind(t) == tRef:
		t = innerOf(tys, t)
	c.tKind(t) == tList and tys[t].inner != none and c.isPlainType(innerOf(tys, t))

# ---------- vectors and matrices: lists of numbers ----------

# the number type of a list of numbers (a vector), or none
fn numListElem(c Checker, t TypeId) TypeId?:
	if c.tKind(t) == tList and tys[t].inner != none and typeIsNumeric(tys, tys[t].inner):
		return innerOf(tys, t)
	none

# the number type of a list of lists of numbers (a matrix), or none
fn numMatrixElem(c Checker, t TypeId):
	if c.tKind(t) == tList and tys[t].inner != none: return c.numListElem(innerOf(tys, t))
	none
