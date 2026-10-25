# What the lowering tells the ownership check (irNote, taken out after it): where a name borrows
# a place and until when (its vreg's last use), where a place changes, and where a loop or a
# pipeline reads a place in place. Places are named as the program names them ("x", "x.f",
# "x[]"), a borrow by the place it borrows; a reference's places come from where its value was
# made (a call's from the callee's origins).

alias nodes = g.c.nodes
alias tys = g.c.types

fn irNoted(
	mut lw IrLower,
	kind i64,
	target i64,
	key str,
	other i64 = -1,
	cond i64 = 0,
	owns bool = false
):
	if lw.irInRuntimeCode(): return
	scale = 2 if owns else 1   # a noteBorrow's name owns its value, target its slot
	lw.irPut(IrInst(op = irNote, imm = kind, target, key = key.copy(), other, cond, scale))

# the place e names: its root's name, or the place the root borrows ("self.f" for a field of the
# receiver named alone); "" for none
fn irPathOf(mut g Gen, lw IrLower, e NodeId):
	found, below = g.c.placePath(e)
	r = found ?? return ""
	name = nodes[r].text.copy()
	i = lw.irLookupAt(name)
	if i >= 0:
		if lw.borrowOf.get(i) is root and root != "": return root + below
		return name + below
	if g.irFieldOfThis(lw, name): return "self.{name}{below}"
	name + below

# the borrow the place e goes through: its root's name when that name borrows, else ""
fn irViaOf(mut g Gen, lw IrLower, e NodeId):
	found, _ = g.c.placePath(e)
	r = found ?? return ""
	i = lw.irLookupAt(nodes[r].text)
	if i >= 0 and lw.borrowOf.get(i) != none: return nodes[r].text.copy()
	""

# the further places the name e is bound to holds borrows of (a list of references, a view)
fn irHeldPlaces(mut g Gen, lw IrLower, e NodeId):
	if nodes[e].kind != nIdent: return []
	i = lw.irLookupAt(nodes[e].text)
	if i < 0: return []
	(lw.held.get(i) ?? []).copy()

# a change of the place e (param: the callee's parameter it is given to, "self" the receiver)
fn irNoteChange(mut g Gen, mut lw IrLower, e NodeId, param str = "", callee NodeId? = none):
	path = g.irPathOf(lw, e)
	if path == "": return
	found, _ = g.c.placePath(e)
	if found is r:
		lw.irArenaStore(lw.irLookupAt(nodes[r].text))
	via = g.irViaOf(lw, e)
	other = i64(callee ?? NodeId(0)) if callee != none else -1
	lw.irNoted(noteChanged, -1, "{path}\t{via}\t{param}", other)

# the name just declared borrows roots (its first the place it is another name for, when
# borrows) while vreg v is used; cond 1: it copies freely (a copy instead, other the value's node),
# 2: a lambda that points at its captures
fn irNoteBorrow(
	mut lw IrLower,
	v i64,
	borrows bool,
	move roots str[],
	cond i64 = 0,
	other i64 = -1
):
	i = lw.names.len - 1
	if i < 0 or roots.isEmpty: return
	if borrows:
		lw.borrowOf[i] = roots[0].copy()
	lw.held[i] = roots.copy()
	if v < 0 or roots.all(it == ""): return
	lw.borrowsNoted = true
	lw.irNoted(noteBorrow, v, "{lw.names[i]}\t{roots.join("\t")}", other, cond, not borrows)

# The places a value bound by the let s points into (none: it owns its value), and whether the
# binding is another name for a place.
fn irBindingRoots(mut g Gen, lw IrLower, s NodeId, value NodeId):
	vt = typeOf(nodes, value)
	if g.c.givesRefLike(vt): return (g.irRootsOf(lw, value), true)
	if g.c.isPlainType(vt): return ([], false)
	if g.c.holdsRefs(vt) and not g.irNamesPlace(lw, value):
		roots = g.irRootsOf(lw, value)
		if "" in roots and g.c.isLentMap(value):
			# strs lent by the elements of a temporary list, gone after the statement
			g.irOwnError(
				g.irFileNow,
				nodes[s].line,
				nodes[s].col,
				compileError("RefToTemporaryElements", ["{nodes[s].text}"])
			)
		return (roots.filter(it != ""), false)
	if nodes[s].hasFlag(flagMut):
		if g.irNamesOwnedLocal(lw, value): return (g.irHeldPlaces(lw, value), false)
		return ([], false)
	k = nodes[value].kind
	if k == nBinary and nodes[value].ival == binCoalesce and
		g.irCoalesceLends(lw, nodes[value].kids[0]):
		left = nodes[value].kids[0]
		while nodes[left].kind == nBinary and nodes[left].ival == binCoalesce:
			left = nodes[left].kids[0]
		return ([g.irPathOf(lw, left)], true)
	if k == nMatch and g.irMatchLentWhole(lw, value):
		return ([g.irPathOf(lw, nodes[value].kids[0])], true)
	if g.irPlaceChoice(lw, value) and not g.c.copiesFreely(vt):
		return (g.c.ifValueBranches(value).map(g.irPathOf(lw, it)), true)
	if k == nTry and g.irNamesPlace(lw, nodes[value].kids[0]) and
		not g.irNamesOwnedLocal(lw, nodes[value].kids[0]) and not g.c.copiesFreely(vt):
		return ([g.irPathOf(lw, nodes[value].kids[0])], true)
	if g.irNamesPlace(lw, value):
		if k == nDeref and nodes[nodes[value].kids[0]].kind == nCall:
			return (g.irRootsOf(lw, value), true)
		out = [g.irPathOf(lw, value)]
		out.extend(g.irHeldPlaces(lw, value))
		return (out, true)
	([], false)

# the paths a references-typed expression may point into ("" when not known: a temporary)
fn irRootsOf(mut g Gen, lw IrLower, e NodeId) str[]:
	k = nodes[e].kind
	out = []
	if k == nUnary and (nodes[e].ival == unRef or nodes[e].ival == unMutRef):
		inner = nodes[e].kids[0]
		if g.c.tKind(typeOf(nodes, inner)) == tRef or nodes[inner].kind == nDeref or
			not g.irNamesPlace(lw, inner):
			return g.irRootsOf(lw, inner)
		out.push(g.irPathOf(lw, inner))
		out.extend(g.irHeldPlaces(lw, inner))
		return out
	if k in [nSome, nTry, nDeref]: return g.irRootsOf(lw, nodes[e].kids[0])
	if k == nArray and g.c.holdsRefs(typeOf(nodes, e)):
		for kid in nodes[e].kids.copy():
			out.extend(g.irRootsOf(lw, kid))
		return out
	if k == nIdent:
		if not (g.c.holdsRefs(typeOf(nodes, e)) and g.irNamesOwnedLocal(lw, e)):
			out.push(g.irPathOf(lw, e))
		out.extend(g.irHeldPlaces(lw, e))
		return out
	if k == nStructLit:
		st = nodes[e].ty
		fields = nodes[declOf(tys, st)].kids.copy() if st != none and g.c.tKind(st) == tStruct
			else []
		for i, kid in nodes[e].kids.copy():
			declaredRef = i < fields.len and not nodes[fields[i]].types().isEmpty and
				g.c.isRefLike(g.c.resolveType(nodes[fields[i]].types()[0]))
			if declaredRef or g.c.isRefLike(typeOf(nodes, kid)):
				out.extend(g.irRootsOf(lw, kid))
		return out
	if k == nStr:
		out.push(moduleOrigin)   # a lent literal: the program's data
		return out
	if k == nField and g.c.isViewType(typeOf(nodes, nodes[e].kids[0])):
		return g.irRootsOf(lw, nodes[e].kids[0])   # a reference field of a view: the view's places
	if k == nField or k == nIndex:
		head = g.irPathOf(lw, e)
		if g.c.tKind(typeOf(nodes, e)) == tRef:
			found, _ = g.c.placePath(e)
			if found is r and g.irNamesOwnedLocal(lw, r):
				return g.irHeldPlaces(lw, r)   # a reference kept in a list of references: where it points
		out.push(head)
		return out
	if k == nBinary and nodes[e].ival == binCoalesce:
		out.extend(g.irRootsOf(lw, nodes[e].kids[0]))
		out.extend(g.irRootsOf(lw, nodes[e].kids[1]))
		return out
	if k == nCall: return g.irCallRoots(lw, e)
	if k == nMatch:
		# where the matched value points (a name an arm's pattern binds points there too), and
		# where each arm's other value points
		scrut = nodes[e].kids[0]
		if g.c.givesRefLike(typeOf(nodes, scrut)):
			out.extend(g.irRootsOf(lw, scrut))
		for arm in g.c.matchArms(e):
			v = g.c.armValue(arm) ?? continue
			if nodes[v].kind != nIdent or lw.irLookupAt(nodes[v].text) >= 0:
				out.extend(g.irRootsOf(lw, v))
	out

# where a reference into x's elements or bytes points: where x points, and "" (a temporary, gone
# after the statement unless kept) when x owns them
fn irLentRoots(mut g Gen, lw IrLower, x NodeId):
	out = g.irRootsOf(lw, x)
	if not g.irNamesPlace(lw, x) and not g.c.isRefLike(typeOf(nodes, x)) and
		not g.c.isPlainType(typeOf(nodes, x)) and nodes[x].kind != nIdent:
		out.push("")
	out

# A call giving a reference points into the arguments bound to the callee's origins
# (names2, checkRefOrigins); a list's, a map's or a str's lending method into its receiver.
fn irCallRoots(mut g Gen, lw IrLower, e NodeId):
	out = []
	callee = g.c.writtenCallee(e)
	nargs = g.c.argCount(e)
	found NodeId? = none
	recv NodeId? = none
	if nodes[callee].kind == nIdent:
		found = g.c.findFunc(nodes[callee].text)
	elif nodes[callee].kind == nField:
		obj = nodes[callee].kids[0]
		ot = typeOf(nodes, obj)
		if g.c.tKind(ot) == tRef:
			ot = innerOf(tys, ot)
		ok = g.c.tKind(ot)
		if ok == tStruct or ok == tEnum:
			found = g.c.findMethod(tys[ot].name, nodes[callee].text)
			recv = obj
		if g.c.standInIndex(ot) >= 0:
			found = g.c.boundMethodOf(g.c.standInIndex(ot), nodes[callee].text)
			recv = obj
		if ok in [tList, tMap, tStr]:
			if g.c.lendsElement(e) or g.c.methodLends(nodes[callee].text):
				if not g.irNamesPlace(lw, obj) or g.irPathOf(lw, obj) == "":
					return g.irLentRoots(lw, obj)
				# into the container itself; on into what its references point to only when what
				# it lends is one (a map's value of a {ref str: V} is the map's own)
				lent = [g.irPathOf(lw, obj)]
				given = g.c.derefType(typeOf(nodes, e))
				if g.c.isRefLike(given) or g.c.holdsRefs(given):
					lent.extend(g.irHeldPlaces(lw, obj))
				return lent
			m = nodes[callee].text
			if m in pipelineSteps and g.c.holdsRefs(typeOf(nodes, e)):
				src = g.c.fusedSource(obj)
				if g.irNamesPlace(lw, src) or g.c.holdsRefs(g.c.derefType(typeOf(nodes, src))):
					out.extend(g.irRootsOf(lw, src))
				else:
					out.push("")   # into a temporary's elements: gone after the statement
				return out
			return out
	fnd = found ?? return out
	if nodes[fnd].hasFlag(flagExtern): return out
	origins = nodes[fnd].names2().copy()
	if origins.isEmpty:
		# not recorded (a runtime function): the receiver, and each borrowed argument that is not
		# plain data
		if recv is r:
			out.extend(g.irRootsOf(lw, r))
		for i in 0..g.c.nodes[fnd].kids.len:
			if i >= nargs or nodes[nodes[fnd].kids[i]].ival == modeMove: continue
			at = nodes[g.c.argAt(e, i)].ty
			if at is t and (g.c.tKind(t) == tRef or not g.c.isPlainType(t)):
				out.extend(g.irRootsOf(lw, g.c.argAt(e, i)))
		return out
	for o in origins:
		if o == moduleOrigin:
			out.push(moduleOrigin)
		elif o == "self":
			if recv is r:
				out.extend(g.irRootsOf(lw, r))
		else:
			for i in 0..g.c.nodes[fnd].kids.len:
				if nodes[nodes[fnd].kids[i]].text == o and i < nargs:
					out.extend(g.irRootsOf(lw, g.c.argAt(e, i)))
	out

# the paths of the captures lambda lam points at (a local lambda: not those that copy freely,
# not the scalars it changes, which it reaches through a pointer of its own)
fn irPointedCaptures(mut g Gen, lw IrLower, lam NodeId):
	out = []
	caps = nodes[lam].names2().copy()
	types = nodes[lam].ints().copy()
	changed = nodes[lam].bounds().copy()
	for i, nm in caps:
		if i >= types.len: break
		free = g.c.copiesFreely(types[i]) and not g.c.isShared(types[i])
		if not free and nm not in changed:
			out.push(g.irNamePath(lw, nm))
	out

# the place a name is: its own, or the place it borrows
fn irNamePath(mut g Gen, lw IrLower, name str):
	i = lw.irLookupAt(name)
	if i >= 0 and lw.borrowOf.get(i) is root and root != "": return root.copy()
	if i < 0 and g.irFieldOfThis(lw, name): return "self.{name}"
	name.copy()

# `x = v` of a name already bound: its place changed; a name that borrows is not bound again
# (AssignBorrowing, AssignBorrow for a written reference), a value that copies freely copied
fn irReassigned(mut g Gen, mut lw IrLower, s NodeId, name str, at i64, value NodeId):
	if lw.irInRuntimeCode() or lw.floor > 0: return
	lw.irArenaStore(at)
	lw.irNoted(noteChanged, -1, "{g.irNamePath(lw, name)}\t\t")
	vt = typeOf(nodes, value)
	if g.c.isRefLike(vt):
		roots = g.irRootsOf(lw, value)
		lw.borrowOf.remove(at)
		lw.held.remove(at)
		if not roots.isEmpty:
			lw.borrowOf[at] = roots[0].copy()
			lw.held[at] = roots
		return
	root = lw.borrowOf.get(at) ?? return
	line = nodes[s].line
	col = nodes[s].col
	file = g.irFileNow.copy()
	msg = compileError("AssignBorrowing", ["{name}", "{root}"])
	g.irOwnError(file, line, col, msg)

# what call e changes, noted after it: its receiver and its mut arguments that are places (with
# the callee and its parameter, judged by what the callee changes), the module variables it may
# change ("@"), the captures its lent lambdas change; a list's or a map's changing method its
# receiver; a local lambda's call what the lambda changes of its captures
fn irNoteCall(mut g Gen, mut lw IrLower, e NodeId):
	if nodes[e].kind != nCall or nodes[e].kids.isEmpty: return
	callee = nodes[e].kids[0]
	n = g.c.argCount(e)
	if nodes[callee].kind == nIdent:
		i = lw.irLookupAt(nodes[callee].text)
		if i >= 0 and lw.localLambdas.get(i) is lam:
			for path in g.irLambdaChanges(lw, lam):
				lw.irNoted(noteChanged, -1, "{path}\t{nodes[callee].text}\t")
			return
	decl NodeId? = none
	if nodes[callee].kind == nIdent:
		decl = g.c.findFunc(nodes[callee].text)
	elif nodes[callee].kind == nField and not nodes[callee].kids.isEmpty:
		obj = nodes[callee].kids[0]
		ot = nodes[obj].ty
		otk = g.c.tKind(ot)
		m = nodes[callee].text.copy()
		if (otk == tStruct or otk == tEnum) and ot is t:
			decl = g.c.findMethod(tys[t].name, m)
			if decl is md and nodes[md].hasFlag(flagMut) and g.irNamesPlace(lw, obj):
				g.irNoteChange(lw, obj, "self", md)
		elif g.irNamesPlace(lw, obj) and (nodes[e].hasFlag(flagTaken) or
				g.c.methodIsMutating(m) and
				(otk == tList or otk == tMap or m == "take" or m == "intoStr")):
			g.irNoteChange(lw, obj)
			g.irArgsIntoChanged(lw, e, obj)
	if decl == none and nodes[callee].kind == nField and not nodes[callee].kids.isEmpty:
		obj = nodes[callee].kids[0]
		if g.c.holdsRefs(g.c.derefType(typeOf(nodes, obj))) and g.irNamesPlace(lw, obj):
			for i in 0..n:
				g.irKeepsRefs(lw, obj, g.c.argAt(e, i))   # push, set, add: the container keeps them
	fnd = decl ?? return
	g.irLentChecks(lw, e, fnd)
	g.irNoteCallReads(lw, e, fnd)
	for i in 0..n:
		a = g.c.argAt(e, i)
		if i < nodes[fnd].kids.len and nodes[nodes[fnd].kids[i]].ival == modeMut and
			g.irNamesPlace(lw, a) and g.c.holdsRefs(g.c.derefType(typeOf(nodes, a))):
			for j in 0..n:
				if j != i and
					(j >= nodes[fnd].kids.len or nodes[nodes[fnd].kids[j]].ival != modeMut):
					g.irKeepsRefs(lw, a, g.c.argAt(e, j))
		if i < nodes[fnd].kids.len and nodes[nodes[fnd].kids[i]].ival == modeMut and
			g.irNamesPlace(lw, a):
			g.irNoteChange(lw, a, nodes[nodes[fnd].kids[i]].text.copy(), fnd)
		if nodes[a].kind == nLambda and g.irFlagged(a, flagBorrowLambda):
			for path in g.irLambdaChanges(lw, a):
				lw.irNoted(noteChanged, -1, "{path}\t\t")
	if not nodes[fnd].hasFlag(flagExtern) and not g.c.opaqueFunction(fnd):
		lw.irNoted(noteChanged, -1, "@\t\t", i64(fnd))

# what the call e of fnd reads of each name given to it that borrows (noteCallRead), so that the
# check finds the call using those parts only
fn irNoteCallReads(mut g Gen, mut lw IrLower, e NodeId, fnd NodeId):
	if not lw.borrowsNoted: return
	callee = nodes[e].kids[0]
	if nodes[callee].kind == nField and not nodes[callee].kids.isEmpty and
		not nodes[fnd].hasFlag(flagMut):
		g.irNoteReadOf(lw, nodes[callee].kids[0], fnd, "self")
	for i in 0..g.c.argCount(e):
		if i < nodes[fnd].kids.len and nodes[nodes[fnd].kids[i]].ival == modeRead:
			g.irNoteReadOf(lw, g.c.argAt(e, i), fnd, nodes[nodes[fnd].kids[i]].text.copy())

fn irNoteReadOf(mut g Gen, mut lw IrLower, a NodeId, fnd NodeId, param str):
	if nodes[a].kind != nIdent or g.c.isPlainType(typeOf(nodes, a)): return
	i = lw.irLookupAt(nodes[a].text)
	if i < 0 or lw.vals[i].isEmpty: return
	parts = g.c.readsThrough(fnd, param).map(it[2..].copy() if .len > 2 else "$")
	lw.irNoted(noteCallRead, lw.vals[i][0], parts.join("\t"))

# the function or the method of a struct or an enum the call e names, none for another (a
# built-in method, a function value)
fn irCalledFn(mut g Gen, lw IrLower, e NodeId):
	callee = nodes[e].kids[0]
	if nodes[callee].kind == nIdent:
		if lw.irLookupAt(nodes[callee].text) >= 0: return none
		return g.c.findFunc(nodes[callee].text)
	if nodes[callee].kind != nField or nodes[callee].kids.isEmpty: return none
	t = try nodes[nodes[callee].kids[0]].ty
	if g.c.tKind(t) != tStruct and g.c.tKind(t) != tEnum: return none
	g.c.findMethod(tys[t].name, nodes[callee].text)

# a place read in place from here (cond 1: a for loop over its own list, 2: any change is one,
# 3: a pipeline that reads its header once): the span's number, -1 for none
fn irReadFrom(mut g Gen, mut lw IrLower, root str, what str, cond i64):
	if root == "" or lw.irInRuntimeCode() or lw.floor > 0: return -1
	g.irSpans += 1
	lw.irNoted(noteReadFrom, g.irSpans, "{root}\t{what}", -1, cond)
	g.irSpans

# the place a sequence e is read from while it is gone over: a place, or the one place a window
# points into; "" for a temporary
fn irSourcePlace(mut g Gen, lw IrLower, e NodeId):
	if nodes[e].kind == nRange: return ""
	if g.irNamesPlace(lw, e): return g.irPathOf(lw, e)
	if g.c.tKind(typeOf(nodes, e)) == tRef:
		roots = g.irRootsOf(lw, e)
		if roots.len == 1: return roots[0].copy()
	""

# the places a for loop s reads in place while its body runs, each a span opened here
fn irForSpans(mut g Gen, mut lw IrLower, s NodeId):
	out = []
	iter = nodes[s].kids[0]
	line = nodes[s].line
	if nodes[iter].kind == nRange: return out
	if g.c.tKind(typeOf(nodes, iter)) == tSeq:
		for place in g.irWalkedPlaces(lw, iter):
			out.push(
				g.irReadFrom(lw, place, "the loop at line {line} walks a generator given it", 2)
			)
		return out.filter(it >= 0)
	root = ""
	windowed = false
	if g.irNamesPlace(lw, iter) and not g.irFlagged(iter, flagAutoCopy):
		root = g.irPathOf(lw, iter)
		if root == "" and nodes[iter].kind == nDeref:
			root = g.irSourcePlace(lw, nodes[iter].kids[0])
			windowed = root != ""
	elif g.c.isLinesCall(iter) or g.c.isSplitLoop(iter):
		recv = nodes[nodes[iter].kids[0]].kids[0]
		if g.irNamesPlace(lw, recv):
			root = g.irPathOf(lw, recv)
			windowed = true
	else:
		root = g.irSourcePlace(lw, g.c.steppedSource(iter))
		windowed = root != ""
	span = g.irReadFrom(lw, root, "the loop at line {line} goes over it", 2 if windowed else 1)
	if span >= 0:
		out.push(span)
	out

# the places a walk over the Seq e reads while it runs: its generator's arguments and receiver
# that are places
fn irWalkedPlaces(mut g Gen, lw IrLower, e NodeId):
	at = e
	while g.c.generatorOf(at) == none and nodes[at].kind == nCall and
		nodes[nodes[at].kids[0]].kind == nField and
		g.c.tKind(typeOf(nodes, nodes[nodes[at].kids[0]].kids[0])) == tSeq:
		at = nodes[nodes[at].kids[0]].kids[0]
	out = []
	if nodes[at].kind != nCall: return out
	given = nodes[at].kids[1..nodes[at].kids.len].copy()
	callee = nodes[at].kids[0]
	if nodes[callee].kind == nField:
		given.push(nodes[callee].kids[0])
	for a in given:
		if g.irNamesPlace(lw, a):
			p = g.irPathOf(lw, a)
			if p != "":
				out.push(p)
	out

# a pipeline step over a list e (its lambdas run inline) reads its source in place: the span
# opened, -1 for none
fn irPipelineSpan(mut g Gen, mut lw IrLower, e NodeId) i64:
	callee = nodes[e].kids[0]
	if nodes[callee].kind != nField or nodes[callee].kids.isEmpty: return -1
	m = nodes[callee].text.copy()
	if m not in pipelineSteps: return -1
	obj = nodes[callee].kids[0]
	otk = g.c.tKind(nodes[obj].ty)
	if otk != tList and otk != tRef and otk != tArray: return -1
	line = nodes[e].line
	g.irReadFrom(lw,
		g.irSourcePlace(lw, g.c.steppedSource(obj)),
		"the pipeline at line {line} goes over it",
		3 if m in headerKeepingSteps else 2
	)

# The container at place target (a list or a map of references) now holds what value points to:
# the local owning it borrows that too, noted again from here; one the caller owns (a mut
# parameter) keeps no local's (CallerKeepsLocal), and none keeps a temporary's (RefToTemporary).
fn irKeepsRefs(mut g Gen, mut lw IrLower, target NodeId, value NodeId):
	if lw.irInRuntimeCode() or lw.floor > 0: return
	found, _ = g.c.placePath(target)
	r = found ?? return
	i = lw.irLookupAt(nodes[r].text)
	if i < 0: return
	roots = g.irRootsOf(lw, value)
	if roots.isEmpty: return
	file = g.irFileNow.copy()
	owned = lw.owned.any(.name == i)
	held = (lw.held.get(i) ?? []).copy()
	for root in roots:
		if root == "" and g.c.isRefLike(typeOf(nodes, value)):
			g.irOwnError(
				file,
				nodes[value].line,
				nodes[value].col,
				compileError("RefToTemporary", ["{nodes[r].text}"])
			)
			return
		if root == "" or root in held: continue
		if not owned and root != moduleOrigin and lw.irLookupAt(pathHead(root)) >= 0 and
			lw.irLookupAt(pathHead(root)) > i:
			g.irOwnError(
				file,
				nodes[value].line,
				nodes[value].col,
				compileError("CallerKeepsLocal", ["{nodes[r].text}", "{pathHead(root)}"])
			)
			return
		at = lw.irLookupAt(pathHead(root))
		if owned and at > i and g.irLocalKept(lw, at, value):
			lw.keptInner.push(
				IrKeptRef(holder = i, root = at, line = nodes[value].line, col = nodes[value].col)
			)
		held.push(root.copy())
	if held.isEmpty or lw.vals[i].isEmpty: return
	lw.held[i] = held.copy()
	lw.irNoted(noteBorrow, lw.vals[i][0], "{nodes[r].text}\t{held.join("\t")}", -1, 0, owned)

# whether a reference value into the local at name index at points at the local's own value: one
# it owns (dropped at its block's end) or one in registers, lent from a slot of its own (a view,
# such as a loop's element of a list or a text's word, points where the local points)
fn irLocalKept(mut g Gen, lw IrLower, at i64, value NodeId):
	t = g.c.derefType(typeOf(nodes, value))
	lw.owned.any(.name == at) or g.irTakes(t) and not g.irByAddress(t)

# a changing method's arguments are read while it changes its receiver (a push may move the
# elements first): one that borrows the receiver is refused
fn irArgsIntoChanged(mut g Gen, lw IrLower, e NodeId, obj NodeId):
	path = g.irPathOf(lw, obj)
	if path == "": return
	for i in 0..g.c.argCount(e):
		found, _ = g.c.placePath(g.c.argAt(e, i))
		a = found ?? continue
		at = lw.irLookupAt(nodes[a].text)
		if at < 0: continue
		root = lw.borrowOf.get(at) ?? continue
		if root != "" and pathsOverlap(root, path):
			g.irOwnError(
				g.irFileNow.copy(),
				nodes[e].line,
				0,
				compileError(
					"ChangeWhileBorrowed",
					["{path}", "{nodes[a].text}", "{nodes[e].line}", "{nodes[e].line}"]
				)
			)
			return

# the places a match's scrutinee is (a place) or points into (a lookup's reference): what the
# names its patterns bind borrow
fn irScrutRoots(mut g Gen, lw IrLower, scrut NodeId):
	if lw.irInRuntimeCode() or lw.floor > 0: return []
	if g.irNamesPlace(lw, scrut):
		out = [g.irPathOf(lw, scrut)]
		out.extend(g.irHeldPlaces(lw, scrut))
		return out
	if g.c.givesRefLike(typeOf(nodes, scrut)): return g.irRootsOf(lw, scrut).filter(it != "")
	[]

# a read of the place e while a name has it lent for changing (a mut ref, a for loop's element
# over a mut place), not through that name: noted for the check (ReadWhileLent)
fn irNoteRead(mut g Gen, mut lw IrLower, e NodeId):
	if lw.irInRuntimeCode() or lw.floor > 0: return
	k = nodes[e].kind
	if k != nIdent and k != nField and k != nIndex: return
	path = g.irPathOf(lw, e)
	if path == "": return
	via = g.irViaOf(lw, e)
	for i in 0..lw.names.len:
		root = lw.exclusive.get(i) ?? continue
		if lw.names[i] != via and pathsOverlap(root, path):
			lw.irNoted(noteRead, -1, "{path}\t{via}")
			return

# the parts of the places lent to fnd's read parameter param that its body reads (reads.zap)
fn irLentParts(mut g Gen, move lent str[], fnd NodeId, param str):
	reads = g.c.readsThrough(fnd, param)
	if "$" in reads: return lent
	out = []
	for l in lent:
		if l == "" or l == moduleOrigin:
			out.push(l.copy())
			continue
		for r in reads:
			out.push("{l}{r[1..]}")
	out

# A call's places: two mut arguments (or one and a changing method's receiver) are never one
# place (LentTwice); a place lent to read is no part of what the same call changes through its mut
# arguments, its receiver or a module variable by its name (LentAndChanged, judged by what the
# callee changes, effects.zap).
fn irLentChecks(mut g Gen, lw IrLower, e NodeId, fnd NodeId):
	if lw.irInRuntimeCode() or lw.floor > 0: return
	n = g.c.argCount(e)
	callee = nodes[e].kids[0]
	params = nodes[fnd].kids.copy()
	file = g.irFileNow.copy()
	changed = []   # (path, parameter) of each place the call changes
	if nodes[callee].kind == nField and not nodes[callee].kids.isEmpty and
		nodes[fnd].hasFlag(flagMut) and g.irNamesPlace(lw, nodes[callee].kids[0]):
		changed.push((g.irPathOf(lw, nodes[callee].kids[0]), "self"))
	for i in 0..n:
		a = g.c.argAt(e, i)
		if i >= params.len or nodes[params[i]].ival != modeMut or not g.irNamesPlace(lw, a):
			continue
		path = g.irPathOf(lw, a)
		if path == "": continue
		for (other, _) in changed:
			if other != "" and pathsOverlap(path, other):
				g.irOwnError(
					file,
					nodes[a].line,
					nodes[a].col,
					compileError("LentTwice", ["{path}", "{other}"])
				)
				return
		changed.push((path, nodes[params[i]].text.copy()))
	for i in 0..n:
		a = g.c.argAt(e, i)
		mode = nodes[params[i]].ival if i < params.len else modeRead
		if mode == modeMove or mode == modeMut or nodes[a].kind == nLambda: continue
		at = typeOf(nodes, a)
		place = g.irNamesPlace(lw, a)
		lent = [g.irPathOf(lw, a)] if place and (not g.c.isPlainType(at) or g.c.passedByAddress(at))
			else g.irRootsOf(lw, a) if not place and g.c.isRefLike(at)
			else []
		if i < params.len and not lent.isEmpty:
			lent = g.irLentParts(move lent, fnd, nodes[params[i]].text.copy())
		for l in lent:
			if l == "" or l == moduleOrigin: continue
			for (path, param) in changed:
				if not pathsOverlap(path, l): continue
				for q in g.irCallChanges(fnd, param, path):
					if changeOverlaps(q, l, false):
						g.irOwnError(
							file,
							nodes[a].line,
							nodes[a].col,
							compileError("LentAndChanged", ["{l}", "{changedPlace(q)}"])
						)
						return
			head = pathHead(l).copy()
			if g.irModuleVariable(head):
				for q in g.c.changedThrough(fnd, "@{head}", head):
					if changeOverlaps(q, l, false):
						g.irOwnError(
							file,
							nodes[a].line,
							nodes[a].col,
							compileError("LentAndChanged", ["{l}", "{changedPlace(q)}"])
						)
						return

# what a call of fnd changes through param given path: the summary's, or the whole place for a
# function whose body works on raw memory
fn irCallChanges(mut g Gen, fnd NodeId, param str, path str):
	if nodes[fnd].mod() == "rt" or nodes[fnd].hasFlag(flagExtern) or g.c.opaqueFunction(fnd):
		return [path.copy()]
	g.c.changedThrough(fnd, param, path)

# the function's result value: a reference (a view, a list of references) points only into what
# outlives the call, its parameters and the program's data, never a local (ReturnLocalRef) or a
# temporary of the statement (ReturnTemporaryRef)
fn irReturnedRefs(mut g Gen, lw IrLower, value NodeId):
	if lw.irInRuntimeCode() or lw.floor > 0: return
	rt = lw.rt
	if not g.c.givesRefLike(rt) and not g.c.holdsRefs(rt): return
	file = g.irFileNow.copy()
	for r in g.irRootsOf(lw, value):
		if r == moduleOrigin: continue
		if r == "":
			g.irOwnError(
				file,
				nodes[value].line,
				nodes[value].col,
				compileError("ReturnTemporaryRef", [])
			)
			return
		head = pathHead(r).copy()
		i = lw.irLookupAt(head)
		if i >= lw.firstLocal:
			g.irOwnError(
				file,
				nodes[value].line,
				nodes[value].col,
				compileError("ReturnLocalRef", ["{head}"])
			)
			return

# the places of its captures lambda lam's body changes, as this code names them: assigned, given
# to a mut parameter, changed by a method
fn irLambdaChanges(mut g Gen, lw IrLower, lam NodeId):
	caps = nodes[lam].names2().copy()
	out = []
	g.irChangesIn(lw, lam, caps, out)
	out

fn irChangesIn(mut g Gen, lw IrLower, e NodeId, caps str[], mut out str[]):
	k = nodes[e].kind
	if k == nAssign:
		g.irCapturePath(lw, nodes[e].kids[0], caps, out)
	if k == nLet and nodes[e].canAssign() and nodes[e].text in caps:
		path = g.irNamePath(lw, nodes[e].text)
		if path not in out:
			out.push(path)
	if k == nUnary and nodes[e].ival == unMutRef:
		g.irCapturePath(lw, nodes[e].kids[0], caps, out)
	if k == nCall and not nodes[e].kids.isEmpty:
		callee = nodes[e].kids[0]
		if nodes[callee].kind == nField and not nodes[callee].kids.isEmpty:
			obj = nodes[callee].kids[0]
			if g.irMethodChanges(e):
				g.irCapturePath(lw, obj, caps, out)
		if nodes[callee].kind == nIdent and g.c.findFunc(nodes[callee].text) is fnd:
			for i in 0..g.c.argCount(e):
				if i < nodes[fnd].kids.len and nodes[nodes[fnd].kids[i]].ival == modeMut:
					g.irCapturePath(lw, g.c.argAt(e, i), caps, out)
	for kid in nodes[e].kids.copy():
		g.irChangesIn(lw, kid, caps, out)
	for b in nodes[e].sub().copy():
		g.irChangesIn(lw, b, caps, out)

# whether the method call e changes its receiver: a mut method, a list's or a map's changing one
fn irMethodChanges(mut g Gen, e NodeId):
	callee = nodes[e].kids[0]
	obj = nodes[callee].kids[0]
	ot = nodes[obj].ty
	otk = g.c.tKind(ot)
	m = nodes[callee].text.copy()
	if (otk == tStruct or otk == tEnum) and ot is t:
		md = g.c.findMethod(tys[t].name, m) ?? return false
		return nodes[md].hasFlag(flagMut)
	g.c.methodIsMutating(m) and (otk == tList or otk == tMap or m == "take" or m == "intoStr")

# the place e changes, when rooted at one of the captures caps, added to out as this code names it
fn irCapturePath(mut g Gen, lw IrLower, e NodeId, caps str[], mut out str[]):
	found, below = g.c.placePath(e)
	r = found ?? return
	if nodes[r].text not in caps: return
	path = g.irNamePath(lw, nodes[r].text) + below
	if path not in out:
		out.push(path)

# a lambda that outlives the expression (kept, returned, stored) owns what it captures: never a
# borrow (ClosureKeepsBorrow), a list of references (ClosureKeepsReferences), and a change it makes
# of a capture is its copy's, lost (CapturedChangeLost)
fn irKeptLambda(mut g Gen, mut lw IrLower, lam NodeId):
	if lw.irInRuntimeCode() or lw.floor > 0: return
	lw.irArenaStore(-1)   # (a kept lambda may outlive any arena)
	file = g.irFileNow.copy()
	line = nodes[lam].line
	col = nodes[lam].col
	changed = nodes[lam].bounds().copy()
	if not changed.isEmpty:
		g.irOwnError(file, line, col, compileError("CapturedChangeLost", ["{changed[0]}"]))
		return
	caps = nodes[lam].names2().copy()
	types = nodes[lam].ints().copy()
	for i, nm in caps:
		if i >= types.len: break
		t = types[i]
		if g.c.isPlainType(t) or g.c.copiesFreely(t): continue
		at = lw.irLookupAt(nm)
		leaf = lw.vals[at][0] if at >= 0 and not lw.vals[at].isEmpty else -2
		owned = at >= 0 and lw.owned.any(.name == at or .slot == leaf or .word == leaf)
		if owned and g.c.holdsRefs(t):
			g.irOwnError(file, line, col, compileError("ClosureKeepsReferences", ["{nm}"]))
			return
		if not owned and (at >= 0 or g.irFieldOfThis(lw, nm)):
			g.irOwnError(file, line, col, compileError("ClosureKeepsBorrow", ["{nm}"]))
			return

# ---------- arenas: a value made in an `arena:` block never goes to a place outside it ----------

# what a statement in an arena block moves (each name, its type) and the fewest arena blocks
# open where a place it stores into was bound
type IrArenaStmt:
	moved i64[] = []   # name indices
	types TypeId[] = []   # each one's type (a shared value's copies are the same value)
	store i64 = 1_000_000

# the value of the local in slot given away by the statement being lowered
fn irArenaMoved(mut lw IrLower, slot i64):
	if lw.arenaWalk.isEmpty: return
	oi = lw.owned.findIndex(.slot == slot and .name >= 0) ?? return
	lw.irArenaMovedName(lw.owned[oi].name, lw.owned[oi].t)

fn irArenaMovedName(mut lw IrLower, i i64, t TypeId):
	if lw.arenaWalk.isEmpty or i < 0 or (lw.nameLevel.get(i) ?? 0) == 0: return
	n = lw.arenaWalk.len - 1
	lw.arenaWalk[n].moved.push(i)
	lw.arenaWalk[n].types.push(t)

# the statement being lowered stores into a place rooted at the name at index at (-1: returns,
# keeps a lambda: past every arena)
fn irArenaStore(mut lw IrLower, at i64):
	if lw.arenaWalk.isEmpty: return
	level = (lw.nameLevel.get(at) ?? 0) if at >= 0 else 0
	n = lw.arenaWalk.len - 1
	if level < lw.arenaWalk[n].store:
		lw.arenaWalk[n].store = level

# a statement's moves out of the arena blocks they were made in: errors
fn irArenaEscapes(mut g Gen, lw IrLower, st IrArenaStmt):
	for j, i in st.moved:
		level = lw.nameLevel.get(i) ?? 0
		if level <= st.store or i >= lw.names.len: continue
		line = lw.arenaLines[level - 1] if level - 1 < lw.arenaLines.len else 0
		name = lw.names[i].copy()
		way = "a shared value's copies are the same value: make it before the block" if g.c.isShared(
			st.types[j]
		)
			else "give a copy, {name}.copy(), which the heap holds"
		g.irOwnError(
			g.irFileNow,
			lw.line,
			lw.col,
			compileError("ArenaEscape", ["{name}", "{line}", "{way}"])
		)
		return
