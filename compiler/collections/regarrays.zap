# Register arrays: `mut zr Simd<4, f64>[4] = [a, b, c, d]` is four locals, zr[0] .. zr[3], each kept
# where the compiler keeps any local (a register in a loop that makes no call). An array
# declared without values (`r Simd<4, f64>[10]`) gets each element at its first assignment, which
# is where that local begins. The indices must be known when the program is compiled: a
# literal, or an expression of literals, of the variables of `for` loops over literal ranges
# (unrolled for it: the copies take the loop's place, each copy's own locals renamed s#1,
# s#2...) and of the lets of such a copy whose value is then known (k = i * (i - 1) / 2 + j).
# An immutable array of integer literals is a table: a read with a known index is the literal
# (pairI i64[10] = [1, 2, 2, ...], then p[pairI[k]]). The pass runs on a function body right
# after it is parsed. It first tries the body on a copy: an array that cannot be taken apart
# this way (an index known only when the program runs, the array used whole, a loop that cannot
# be unrolled) stays a T[N] value in memory, which the checker and the backend handle as any
# other type; the arrays that can are then expanded for real. A function with number parameters
# keeps its body as parsed: each instance expands a copy of its own with the numbers known
# (numberInstance), so an array sized by one, and the loops over 0..N that index it, are taken
# apart as a literal length's are.

# what the pass knows at a point of the body
type ArrayScope:
	names str[]   # the arrays ...
	sizes i64[]   # ... their lengths ...
	flags i64[]   # ... and declarations (mut or not) for elements born by assignment
	known str[]   # the names visible here (parameters, earlier lets, elements)
	copies i64   # the copies made so far: a copy's locals are numbered by it
	tables i64[,]   # per array: its values when it is an immutable array of integer
# literals (a table: a[k] is the literal), else []
	fixed str[]   # the immutable locals visible here
	aliasFrom str[]   # elements of immutable arrays given an immutable local (s[3] = one) ...
	aliasTo str[]   # ... read as that local: no copy
	inCopy i64   # inside an unrolled copy: an if whose condition folds keeps one branch
	trial bool   # the trial on a copy: a failure is recorded, not reported
	failed str[]   # the arrays the trial could not take apart
	numbers str[] = []   # an instance's number parameters ...
	numberValues i64[] = []   # ... and their values, read where the pass needs a literal

pub fn expandRegArrays(mut p Parser, body NodeId, params str[]):
	p.expandArrays(body, params, [], [])

fn expandArrays(mut p Parser, body NodeId, params str[], numbers str[], values i64[]):
	if not p.declaresArray(body): return
	markMayChange(p.nodes, body)   # (a let without mut may still change: spec 2.4)
	markZeroedArrays(p.nodes, body)
	# the pass follows names, not scopes: an array whose name a loop variable, a pattern or a
	# lambda's parameter binds again stays in memory, where the checker tells the names apart
	rebound = []
	p.reboundNames(body, rebound)
	p.sizedByParameter(body, rebound)
	p.keepInMemory(body, rebound)
	if not p.declaresArray(body): return
	# trials on copies until every array left can be taken apart (one that cannot may have kept
	# a loop from unrolling for another)
	rounds = 0
	going = true
	while going and rounds < 8:
		trial = ArrayScope(
			names = [],
			sizes = [],
			flags = [],
			known = params.copy(),
			copies = 0,
			tables = [],
			fixed = [],
			aliasFrom = [],
			aliasTo = [],
			inCopy = 0,
			trial = true,
			failed = [],
			numbers = numbers.copy(),
			numberValues = values.copy()
		)
		p.expandBlock(cloneTree(p.nodes, body), trial)
		going = not trial.failed.isEmpty
		if going:
			p.keepInMemory(body, trial.failed)
		rounds += 1
	if not p.declaresArray(body): return
	sc = ArrayScope(
		names = [],
		sizes = [],
		flags = [],
		known = params.copy(),
		copies = 0,
		tables = [],
		fixed = [],
		aliasFrom = [],
		aliasTo = [],
		inCopy = 0,
		trial = false,
		failed = [],
		numbers = numbers.copy(),
		numberValues = values.copy()
	)
	p.expandBlock(body, sc)

# a GPU function's arrays declared without values (`mut acc f32[16]`) start as zeros
fn zeroBareArrays(mut p Parser, e NodeId):
	if p.isArrayDecl(e) and p.nodes[e].kids.isEmpty:
		zeros = p.mk(nArray, p.nodes[e].line, p.nodes[e].col)
		p.nodes[zeros].flags = flagInternal
		p.nodes[e].kids.push(zeros)
	for k in p.nodes[e].kids:
		p.zeroBareArrays(k)
	for kAt in 0..p.nodes[e].sub().len:
		k = p.nodes[e].sub()[kAt]
		p.zeroBareArrays(k)

# the declarations of the named arrays become T[N] values in memory: no longer arrays of this
# pass, and one without values starts as N zeros
fn keepInMemory(mut p Parser, e NodeId, names str[]):
	if p.isArrayDecl(e) and p.nodes[e].text in names:
		p.nodes[e].ival = 1
		if p.nodes[e].kids.isEmpty:
			zeros = p.mk(nArray, p.nodes[e].line, p.nodes[e].col)
			p.nodes[zeros].flags = flagInternal
			p.nodes[e].kids.push(zeros)
	for k in p.nodes[e].kids:
		p.keepInMemory(k, names)
	for kAt in 0..p.nodes[e].sub().len:
		k = p.nodes[e].sub()[kAt]
		p.keepInMemory(k, names)

# the names under e bound by a for loop, a match arm's pattern or a lambda's parameters
fn reboundNames(p Parser, e NodeId, mut out str[]):
	k = p.nodes[e].kind
	if k == nFor or (k == nPattern and p.nodes[e].ival in [patBind, patRest]):
		out.push(p.nodes[e].text.copy())
	if k == nLambda:
		for nm in p.nodes[e].names():
			out.push(nm.copy())
	for kid in p.nodes[e].kids:
		p.reboundNames(kid, out)
	for sb in p.nodes[e].sub():
		p.reboundNames(sb, out)

# the arrays whose length is a number parameter (T[N]), known only per instance: kept in memory
fn sizedByParameter(p Parser, e NodeId, mut out str[]):
	if p.isArrayDecl(e) and p.nodes[p.nodes[e].types()[0]].text != "":
		out.push(p.nodes[e].text.copy())
	for kid in p.nodes[e].kids:
		p.sizedByParameter(kid, out)
	for sb in p.nodes[e].sub():
		p.sizedByParameter(sb, out)

fn isArrayDecl(p Parser, e NodeId):
	p.nodes[e].kind == nLet and p.nodes[e].ival != 1 and not p.nodes[e].types().isEmpty and
		p.nodes[p.nodes[e].types()[0]].kind == nTyArray

fn declaresArray(p Parser, e NodeId) bool:
	p.isArrayDecl(e) or p.nodes[e].kids.any(p.declaresArray(it)) or
		p.nodes[e].sub().any(p.declaresArray(it))

# an array that cannot be taken apart: recorded in a trial (it stays in memory), reported otherwise
fn arrayError(mut p Parser, mut sc ArrayScope, e NodeId, move arrays str[], msg str):
	if sc.trial:
		names = move arrays
		for k in 0..names.len:
			if names[k] not in sc.failed:
				sc.failed.push(move names[k])
		return
	p.parseError(Tok(kind = 0, text = "", line = p.nodes[e].line, col = p.nodes[e].col), msg)

# the arrays of the scope indexed under e
fn arraysIndexedIn(p Parser, e NodeId, names str[], mut out str[]):
	if p.isArrayElem(e, names) and p.nodes[p.nodes[e].kids[0]].text not in out:
		out.push(p.nodes[p.nodes[e].kids[0]].text.copy())
	for k in p.nodes[e].kids:
		p.arraysIndexedIn(k, names, out)
	for k in p.nodes[e].sub():
		p.arraysIndexedIn(k, names, out)

fn expandBlock(mut p Parser, blk NodeId, mut sc ArrayScope):
	mark = sc.known.len
	fixedMark = sc.fixed.len
	out = []
	p.expandStmts(p.nodes[blk].kids.copy(), sc, out)
	p.nodes[blk].kids = out
	sc.known.truncate(mark)
	sc.fixed.truncate(fixedMark)

fn expandStmts(mut p Parser, stmts NodeId[], mut sc ArrayScope, mut out NodeId[]):
	for st in stmts:
		k = p.nodes[st].kind
		if k == nIf and sc.inCopy > 0 and foldBool(p.nodes, p.nodes[st].kids[0]):
			# decided when compiling: the chosen branch takes the if's place
			if p.nodes[p.nodes[st].kids[0]].ival == 1:
				p.expandStmts(p.nodes[p.nodes[st].sub()[0]].kids.copy(), sc, out)
			elif p.nodes[st].sub().len > 1:
				p.expandStmts(p.nodes[p.nodes[st].sub()[1]].kids.copy(), sc, out)
		elif p.aliasesElement(st, sc):
			# s[3] = one: s[3] reads one
			pass
		elif p.isArrayDecl(st):
			p.declareArray(st, sc, out)
		elif k == nFor and p.loopFeedsIndex(p.nodes[st].sub()[0], sc.names, p.nodes[st].text):
			p.unrollFor(st, sc, out)
		else:
			if k == nFor:
				sc.known.push(p.nodes[st].text.copy())   # the loop variable, while its body is rewritten
			p.rewriteArrays(st, sc)
			if k == nFor:
				sc.known.pop()
			if p.nodes[st].kind == nLet and p.nodes[st].text not in sc.known:
				sc.known.push(p.nodes[st].text.copy())   # the scope's lists keep names of their own
				if p.nodes[st].flags & (flagMut | flagMayChange) == 0:
					sc.fixed.push(p.nodes[st].text.copy())
			out.push(st)

# The first assignment of an element of an immutable array from an immutable local: the
# element is that local (recorded, no statement).
fn aliasesElement(mut p Parser, st NodeId, mut sc ArrayScope):
	if p.nodes[st].kind != nAssign or not p.isArrayElem(p.nodes[st].kids[0], sc.names): return false
	target = p.nodes[st].kids[0]
	value = p.nodes[st].kids[1]
	a = sc.names.indexOf(p.nodes[p.nodes[target].kids[0]].text) ?? -1
	if sc.flags[a] & (flagMut | flagMayChange) != 0 or p.nodes[value].kind != nIdent or
		p.nodes[value].text not in sc.fixed or not p.foldKnown(p.nodes[target].kids[1], sc):
		return false
	elem = "{sc.names[a]}[{p.litOf(p.nodes[target].kids[1])}]"
	if elem in sc.known: return false
	sc.known.push(elem.copy())   # known and aliasFrom each keep the name
	sc.aliasFrom.push(elem)
	sc.aliasTo.push(p.nodes[value].text.copy())
	true

# `a T[N] = [e0, ..., eN-1]` or `= fill(N, e)`: N lets a[0] .. a[N-1]; without values, the
# elements are born at their first assignments
fn declareArray(mut p Parser, st NodeId, mut sc ArrayScope, mut out NodeId[]):
	# the array's name is read from st where needed: making nodes moves p.nodes, never st's text
	te = p.nodes[st].types()[0]
	n = p.nodes[te].ival
	sc.names.push(p.nodes[st].text.copy())
	sc.sizes.push(n)
	sc.flags.push(p.nodes[st].flags)
	sc.tables.push([])
	if p.nodes[st].kids.isEmpty:
		if p.nodes[st].flags & flagMut == 0:
			return   # immutable: each element is bound once, as a let
		# mutable: every element starts from the zero of its type
		elemTE = p.nodes[te].types()[0]
		zero = p.zeroOf(elemTE)
		if zero == none:
			arrayError(
				p,
				sc,
				st,
				[p.nodes[st].text.copy()],
				compileError("RegisterArrayZeros", ["{n}"])
			)
			return
		for i in 0..n:
			l = p.mk(nLet, p.nodes[st].line, p.nodes[st].col)
			p.nodes[l].text = "{p.nodes[st].text}[{i}]"
			p.nodes[l].flags = p.nodes[st].flags
			p.nodes[l].nodePart().types.push(elemTE)
			p.nodes[l].kids.push(p.zeroOf(elemTE) ?? fail("no zero"))
			out.push(l)
			sc.known.push("{p.nodes[st].text}[{i}]")
		return
	values = p.initialValues(st, n, sc)
	if values.len != n:
		arrayError(
			p,
			sc,
			st,
			[p.nodes[st].text.copy()],
			compileError("RegisterArrayValues", ["{n}"])
		)
		return
	table = values.filter(foldInt(p.nodes, it)).map(p.litOf(it))
	if p.nodes[st].flags & (flagMut | flagMayChange) == 0 and table.len == n:
		sc.tables[len - 1] = table   # no locals: every read is a literal
		return
	for i in 0..n:
		v = values[i]
		p.rewriteArrays(v, sc)
		l = p.mk(nLet, p.nodes[st].line, p.nodes[st].col)
		p.nodes[l].text = "{p.nodes[st].text}[{i}]"
		p.nodes[l].flags = p.nodes[st].flags
		p.nodes[l].nodePart().types.push(p.nodes[te].types()[0])
		p.nodes[l].kids.push(v)
		out.push(l)
		sc.known.push("{p.nodes[st].text}[{i}]")

# the n values of the initializer of the array declared by st: a list literal of n, or
# fill(n, e): e written n times, or, when it calls or moves (it is evaluated once), e for the
# first element and that element read for the others (only for numbers and vectors: other
# elements would be moved; such an array stays in memory)
fn initialValues(mut p Parser, st NodeId, n i64, sc ArrayScope):
	init = p.nodes[st].kids[0]
	if p.nodes[init].kind == nArray: return p.nodes[init].kids.copy()
	out = []
	if p.nodes[init].kind != nCall or p.nodes[init].kids.len < 2: return out
	callee = p.nodes[init].kids[0]
	count = p.nodes[init].kids[1]
	e NodeId? = none
	if p.nodes[callee].kind == nIdent and p.nodes[callee].text == "fill" and
		p.nodes[init].kids.len == 3:
		e = p.nodes[init].kids[2]   # fill(N, e)
	elif p.nodes[callee].kind == nIdent and p.nodes[callee].text == "zeros" and
		p.nodes[init].kids.len == 2:
		e = p.zeroOf(p.nodes[p.nodes[st].types()[0]].types()[0])   # zeros(N)
		if e is zero and p.nodes[zero].kind == nArray:
			e = none   # only numbers, bools and optionals have a zero here
	value = e ?? return out
	if not p.foldKnown(count, sc) or p.litOf(count) != n: return out
	if not p.callsOrMoves(value): return (0..n).map(_: cloneTree(p.nodes, value))
	if not p.copiesAsBits(p.nodes[p.nodes[st].types()[0]].types()[0]): return out
	out.push(value)
	for _ in 1..n:
		first = p.mk(nIdent, p.nodes[value].line, p.nodes[value].col)
		p.nodes[first].text = "{p.nodes[st].text}[0]"
		out.push(first)
	out

# whether the type written te is a number, a bool or a vector: a value read twice is a copy
fn copiesAsBits(p Parser, te NodeId):
	if p.nodes[te].kind != nTyName: return false
	name = p.nodes[te].text
	prim = primType(name)
	scalar = prim != none and prim != tyStr and prim != tyUnit
	scalar or isSimdName(name) or isVecLitName(name)

# whether the loop variable v reaches an index of one of the arrays in the body, directly or
# through immutable lets of the body (k = i + j, then a[k])
fn loopFeedsIndex(p Parser, body NodeId, names str[], v str):
	if names.isEmpty: return false
	vars = [v.copy()]   # the names that carry v, a working list of its own
	for st in p.nodes[body].kids:
		if p.nodes[st].kind == nLet and p.nodes[st].flags & (flagMut | flagMayChange) == 0 and
			not p.nodes[st].kids.isEmpty and mentionsAny(p.nodes, p.nodes[st].kids[0], vars):
			vars.push(p.nodes[st].text.copy())
	p.indexesWith(body, names, vars)

fn indexesWith(p Parser, e NodeId, names str[], vars str[]) bool:
	p.isArrayElem(e, names) and mentionsAny(p.nodes, p.nodes[e].kids[1], vars) or
		p.nodes[e].kids.any(p.indexesWith(it, names, vars)) or
		p.nodes[e].sub().any(p.indexesWith(it, names, vars))

# for v in lo..hi (by s) over literals: one copy of the body per value, v written as the value
fn unrollFor(mut p Parser, st NodeId, mut sc ArrayScope, mut out NodeId[]):
	iter = p.nodes[st].kids[0]
	body = p.nodes[st].sub()[0]
	indexed = []
	p.arraysIndexedIn(body, sc.names, indexed)
	if p.nodes[iter].kind != nRange:
		p.arrayError(sc, st, indexed, compileError("RegisterLoopRange", []))
		return
	for b in p.nodes[iter].kids:
		if not p.foldKnown(b, sc):
			arrayError(
				p,
				sc,
				st,
				indexed,
				compileError("RegisterLoopConstant", [])
			)
			return
	lo = p.litOf(p.nodes[iter].kids[0])
	hi = p.litOf(p.nodes[iter].kids[1])
	step = 1
	if p.nodes[iter].kids.len > 2:
		step = p.litOf(p.nodes[iter].kids[2])
	if step <= 0 or (hi - lo) / step > 64:
		arrayError(
			p,
			sc,
			st,
			indexed,
			compileError("RegisterLoopSteps", [])
		)
		return
	if breaksOut(p.nodes, body, true):
		arrayError(
			p,
			sc,
			st,
			indexed,
			compileError("RegisterLoopBreak", [])
		)
		return
	v = p.nodes[st].text.copy()   # its own: every copy of the body adds nodes
	locals = []   # the lets of the body that declare
	p.declaredIn(body, sc.known, locals)
	at = lo
	while at < hi:
		copy = cloneTree(p.nodes, body)
		p.substitute(copy, v, at)
		p.foldConstLets(copy, sc, locals)
		sc.copies += 1
		for nm in locals:
			p.rename(copy, nm, "{nm}#{sc.copies}")   # a local of this copy
		sc.inCopy += 1
		p.expandBlock(copy, sc)
		sc.inCopy -= 1
		for l in p.nodes[copy].kids:
			out.push(l)
			if p.nodes[l].kind == nLet and p.nodes[l].text not in sc.known:
				sc.known.push(p.nodes[l].text.copy())   # visible to the copies after it, as in the loop
		at += step

# the names lets under e declare (not visible before), lambdas left out
fn declaredIn(p Parser, e NodeId, known str[], mut out str[]):
	k = p.nodes[e].kind
	if k == nLambda: return
	if k == nLet and p.nodes[e].text not in known and p.nodes[e].text not in out:
		out.push(p.nodes[e].text.copy())
	for kid in p.nodes[e].kids:
		p.declaredIn(kid, known, out)
	for sb in p.nodes[e].sub():
		p.declaredIn(sb, known, out)

# In a copy, an immutable let of the copy's own whose value is known (k = 2 * 3 + 1) is replaced by its value
# where it is read, and every expression of literals is folded (spread(k % 4) gets a literal).
fn foldConstLets(mut p Parser, blk NodeId, sc ArrayScope, locals str[]):
	kept = []
	stmts = p.nodes[blk].kids.copy()
	for i in 0..stmts.len:
		st = stmts[i]
		p.readTables(st, sc)
		if p.nodes[st].kind == nLet and p.nodes[st].text in locals and
			p.nodes[st].flags & (flagMut | flagMayChange) == 0 and p.nodes[st].types().isEmpty and
			not p.nodes[st].kids.isEmpty:
			p.foldKnown(p.nodes[st].kids[0], sc)
		p.foldLiterals(st)
		if p.nodes[st].kind == nLet and p.nodes[st].text in locals and
			p.nodes[st].flags & (flagMut | flagMayChange) == 0 and p.nodes[st].types().isEmpty and
			not p.nodes[st].kids.isEmpty and p.nodes[p.nodes[st].kids[0]].kind == nInt:
			value = p.litOf(p.nodes[st].kids[0])
			for j in (i + 1)..stmts.len:
				p.substituteLet(stmts[j], st, value)
			# the let stays (a literal, read nowhere now) so the checker still sees what the
			# name meant: a field or a module variable of that name is an error there
		kept.push(st)
	p.nodes[blk].kids = kept

# the reads of tables with literal indices under e become the literals
fn readTables(mut p Parser, e NodeId, sc ArrayScope):
	for kid in p.nodes[e].kids:
		p.readTables(kid, sc)
	if not p.isArrayElem(e, sc.names) or not p.foldKnown(p.nodes[e].kids[1], sc): return
	a = sc.names.indexOf(p.nodes[p.nodes[e].kids[0]].text) ?? -1
	i = p.litOf(p.nodes[e].kids[1])
	if not sc.tables[a].isEmpty and i >= 0 and i < sc.tables[a].len:
		p.nodes[e].kind = nInt
		p.nodes[e].text = str(sc.tables[a][i])
		p.nodes[e].kids = []

fn foldLiterals(mut p Parser, e NodeId):
	for kid in p.nodes[e].kids:
		p.foldLiterals(kid)
	for sbAt in 0..p.nodes[e].sub().len:
		sb = p.nodes[e].sub()[sbAt]
		p.foldLiterals(sb)
	if p.nodes[e].kind == nBinary or p.nodes[e].kind == nUnary:
		foldInt(p.nodes, e)

fn substitute(mut p Parser, e NodeId, v str, value i64):
	if p.nodes[e].kind == nIdent and p.nodes[e].text == v:
		p.nodes[e].kind = nInt
		p.nodes[e].text = "{value}"
		return
	for kid in p.nodes[e].kids:
		p.substitute(kid, v, value)
	for sbAt in 0..p.nodes[e].sub().len:
		sb = p.nodes[e].sub()[sbAt]
		p.substitute(sb, v, value)

# substitute for the name the let `named` binds, read from that let at each node (the rewrite
# changes p, so the name is not held across it)
fn substituteLet(mut p Parser, e NodeId, named NodeId, value i64):
	if p.nodes[e].kind == nIdent and p.nodes[e].text == p.nodes[named].text:
		p.nodes[e].kind = nInt
		p.nodes[e].text = "{value}"
		return
	for k in 0..p.nodes[e].kids.len:
		p.substituteLet(p.nodes[e].kids[k], named, value)
	for k in 0..p.nodes[e].sub().len:
		p.substituteLet(p.nodes[e].sub()[k], named, value)

# every use and let of the name `old` under e becomes `to`
fn rename(mut p Parser, e NodeId, old str, to str):
	k = p.nodes[e].kind
	if (k == nIdent or k == nLet) and p.nodes[e].text == old:
		p.nodes[e].text = to.copy()   # each node renamed keeps its own
	for kid in p.nodes[e].kids:
		p.rename(kid, old, to)
	for sbAt in 0..p.nodes[e].sub().len:
		sb = p.nodes[e].sub()[sbAt]
		p.rename(sb, old, to)

# whether e folds to an integer literal, an instance's number parameters read as their values
fn foldKnown(mut p Parser, e NodeId, sc ArrayScope) bool:
	for i, number in sc.numbers:
		p.substitute(e, number, sc.numberValues[i])
	foldInt(p.nodes, e)

fn litOf(p Parser, e NodeId):
	i64.parse(p.nodes[e].text) ?? 0

# a[i] with i known becomes the local a[i]; any other use of an array is an error
fn rewriteArrays(mut p Parser, e NodeId, mut sc ArrayScope):
	k = p.nodes[e].kind
	if k == nAssign and p.isArrayElem(p.nodes[e].kids[0], sc.names):
		value = p.nodes[e].kids[1]
		p.rewriteArrays(value, sc)
		target = p.nodes[e].kids[0]
		a = sc.names.indexOf(p.nodes[p.nodes[target].kids[0]].text) ?? -1   # names only grow: it stays
		p.rewriteArrays(target, sc)
		# the element's name moves from target, which leaves the tree here
		elem = move p.nodes[target].text
		p.nodes[e].kind = nLet   # a[2] = v assigns the local a[2] ...
		p.nodes[e].kids = [value]
		p.nodes[e].flags = 0
		if elem not in sc.known:
			p.nodes[e].flags = sc.flags[a]   # ... or makes it, the first time
			sc.known.push(elem.copy())
		p.nodes[e].text = elem
		return
	if p.isArrayElem(e, sc.names):
		# the array's name is read from its node where needed: rewriting the index changes p,
		# never that node
		arr = p.nodes[e].kids[0]
		a = sc.names.indexOf(p.nodes[arr].text) ?? -1
		idx = p.nodes[e].kids[1]
		p.rewriteArrays(idx, sc)
		if not p.foldKnown(idx, sc):
			p.arrayError(
				sc,
				e,
				[p.nodes[arr].text.copy()],
				compileError("RegisterIndexConstant", ["{p.nodes[arr].text}"])
			)
			return
		i = p.litOf(idx)
		n = sc.sizes[a]
		if i < 0 or i >= n:
			arrayError(
				p,
				sc,
				e,
				[p.nodes[arr].text.copy()],
				compileError("RegisterIndexOutside", ["{i}", "{p.nodes[arr].text}", "{n}"])
			)
			return
		elem = "{p.nodes[arr].text}[{i}]"
		ai = sc.aliasFrom.indexOf(elem) ?? -1
		if ai >= 0:
			p.nodes[e].kind = nIdent   # an element given an immutable local
			p.nodes[e].text = sc.aliasTo[ai].copy()   # read as often as the element is
			p.nodes[e].kids = []
			return
		table = sc.tables[a]
		if not table.isEmpty:
			p.nodes[e].kind = nInt   # a table's element is its literal
			p.nodes[e].text = str(table[i])
			p.nodes[e].kids = []
			return
		p.nodes[e].kind = nIdent
		p.nodes[e].text = elem
		p.nodes[e].kids = []
		return
	if (k == nIdent or k == nLet) and p.nodes[e].text in sc.names:
		p.arrayError(
			sc,
			e,
			[p.nodes[e].text.copy()],
			compileError("RegisterArrayWhole", ["{p.nodes[e].text}"])
		)
		return
	for kid in p.nodes[e].kids:
		p.rewriteArrays(kid, sc)
	for sbAt in 0..p.nodes[e].sub().len:
		sb = p.nodes[e].sub()[sbAt]
		if p.nodes[sb].kind == nBlock:
			p.expandBlock(sb, sc)
		else:
			p.rewriteArrays(sb, sc)

fn isArrayElem(p Parser, e NodeId, names str[]):
	p.nodes[e].kind == nIndex and p.nodes[p.nodes[e].kids[0]].kind == nIdent and
		p.nodes[p.nodes[e].kids[0]].text in names

fn paramNames(p Parser, f NodeId):
	p.nodes[f].kids.map(p.nodes[it].text.copy())

# the zero of a type written as an expression (0, 0.0, false, "", [], {}, none, Simd<N, T>(0)), or none
# when the type has none to write (a struct): such an array stays in memory, which starts zeroed
fn zeroOf(mut p Parser, te NodeId) NodeId?:
	line = p.nodes[te].line
	col = p.nodes[te].col
	k = p.nodes[te].kind
	if k == nTyOpt: return p.mk(nNone, line, col)
	if k == nTyArray:
		zeros = p.mk(nArray, line, col)
		p.nodes[zeros].flags = flagInternal
		return zeros
	if k != nTyName: return none
	# what the name asks for, decided before a node is made (making one moves p.nodes)
	name = p.nodes[te].text
	zk = -1   # the kind of the zero's node
	prim = primType(name)
	if prim == tyFloat(32) or prim == tyFloat(64):
		zk = nFloat
	elif prim == tyBool:
		zk = nBool
	elif prim == tyStr:
		zk = nStr
	elif prim != none and prim != tyUnit:
		zk = nInt   # the rest are integers
	elif name == "List":
		zk = nArray
	elif name == "Map":
		zk = nMapLit
	simd = isSimdName(name) and p.nodes[te].types().len == 2
	if zk == nInt:
		z = p.mk(nInt, line, col)
		p.nodes[z].text = "0"
		return z
	if zk == nFloat:
		z = p.mk(nFloat, line, col)
		p.nodes[z].text = "0.0"
		return z
	if zk >= 0: return p.mk(zk, line, col)
	if simd:
		lane = p.nodes[p.nodes[te].types()[1]].text
		floatLane = lane == "f32" or lane == "f64"
		z = p.mk(nFloat if floatLane else nInt, line, col)
		p.nodes[z].text = "0.0" if floatLane else "0"
		callee = p.mk(nIdent, line, col)
		p.nodes[callee].text = p.nodes[te].text.copy()   # the call names the vector type
		p.nodes[callee].nodePart().types = p.nodes[te].types().copy()
		call = p.mk(nCall, line, col)
		p.nodes[call].kids = [callee, z]
		return call
	none

# the bodies of the functions with number parameters as parsed, before this pass
mut numberBodies {NodeId: NodeId} = {}

pub fn forgetNumberBodies():
	numberBodies.clear()

# f's body as parsed kept for its instances, when f has a number parameter
fn keepNumberBody(mut p Parser, f NodeId, body NodeId):
	if p.nodes[f].bounds().any(isNumberBound(it)):
		numberBodies[f] = cloneTree(p.nodes, body)

# whether a type parameter's bound declares it a number (<N n64>): an integer type's name
fn isNumberBound(bound str):
	primType(bound) != none and bound[0] in ['i', 'u', 'n']

# The declaration an instance of f checks and generates when f has number parameters: f with a
# copy of its body as parsed, the arrays it declares sized by the values and its passes run with
# them known; none when f kept no body.
pub fn numberInstance(mut nodes Node[], f NodeId, numbers str[], values i64[]) NodeId?:
	raw = try numberBodies.get(f)
	p = Parser(toks = [], pos = 0, file = nodes[f].file().copy(), nodes = move nodes)
	body = cloneTree(p.nodes, raw)
	p.sizeArrays(body, numbers, values)
	p.finishFnBody(f, body, numbers, values)
	params = []
	for i in 0..p.nodes[f].kids.len:
		params.push(cloneTree(p.nodes, p.nodes[f].kids[i]))
	d = p.nodes[f].copy()
	d.kids = params
	d.nodePart().sub = [body]
	p.nodes.push(d)
	nodes = p.nodes
	NodeId(nodes.len - 1)

# the arrays declared under e whose lengths name number parameters get the values as theirs
fn sizeArrays(mut p Parser, e NodeId, numbers str[], values i64[]):
	if p.nodes[e].kind == nLet and not p.nodes[e].types().isEmpty:
		p.nodes[e].nodePart().types[0] = p.sizedType(p.nodes[e].types()[0], numbers, values)
	for kid in p.nodes[e].kids:
		p.sizeArrays(kid, numbers, values)
	for sbAt in 0..p.nodes[e].sub().len:
		sb = p.nodes[e].sub()[sbAt]
		p.sizeArrays(sb, numbers, values)

# the array type te with the lengths that name number parameters written as their values (a
# new node where one changes: the written type is shared)
fn sizedType(mut p Parser, te NodeId, numbers str[], values i64[]) NodeId:
	if p.nodes[te].kind != nTyArray: return te
	elem = p.nodes[te].types()[0]
	inner = p.sizedType(elem, numbers, values)
	at = numbers.indexOf(p.nodes[te].text) ?? -1
	if at < 0 and inner == elem: return te
	n = p.nodes[te].copy()
	if at >= 0:
		n.text = ""
		n.ival = i32(values[at])
	n.nodePart().types = [inner]
	p.nodes.push(n)
	NodeId(p.nodes.len - 1)
