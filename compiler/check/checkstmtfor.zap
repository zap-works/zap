# The checking of for loops: ranges, element changes, loop uses and notes (checkstmt.zap).

alias nodes = c.nodes
alias tys = c.types

# `x.lines()` with no arguments: only meaningful as the sequence of a for loop
pub fn isLinesCall(c Checker, e NodeId) bool:
	if nodes[e].kind != nCall or nodes[e].kids.len != 1: return false
	callee = nodes[e].kids[0]
	nodes[callee].kind == nField and nodes[callee].text == "lines"

# whether e is `if c { a } else { b }` used as a value (a match on the condition with a true arm
# and a wildcard, see ifValueNode)
pub fn isIfValue(c Checker, e NodeId) bool:
	if nodes[e].kind != nMatch or nodes[e].kids.len != 3: return false
	pat = nodes[nodes[e].kids[1]].kids[0]
	nodes[pat].ival == patLit and nodes[pat].kids.len == 1 and
		nodes[nodes[pat].kids[0]].kind == nBool and
		nodes[nodes[nodes[e].kids[2]].kids[0]].ival == patWildcard

# the branches of an if used as a value, nested ifs flattened, in order (else [])
pub fn ifValueBranches(c Checker, e NodeId) NodeId[]:
	out = []
	if not c.isIfValue(e): return out
	for k in 1..3:
		body = nodes[nodes[e].kids[k]].kids[1]
		if c.isIfValue(body):
			out.extend(c.ifValueBranches(body))
		else:
			out.push(body)
	out

# `x.split(sep)` as the sequence of a for loop: the parts of a text between the separators, as
# windows (the checker marks the call's type str; a list's split, or a split elsewhere, is a call)
pub fn isSplitLoop(c Checker, e NodeId) bool:
	if nodes[e].kind != nCall or nodes[e].kids.len != 2 or typeOf(nodes, e) != tyStr: return false
	callee = nodes[e].kids[0]
	nodes[callee].kind == nField and nodes[callee].text == "split"

# whether a for loop's sequence is `text.split(sep)` with a text receiver (decided by its type)
fn splitOverText(mut c Checker, e NodeId):
	if nodes[e].kind != nCall or nodes[e].kids.len != 2: return false
	callee = nodes[e].kids[0]
	if nodes[callee].kind != nField or nodes[callee].text != "split": return false
	recv = nodes[callee].kids[0]
	rt = c.derefIfRef(recv, c.checkExpr(recv, none))
	c.tKind(rt) == tStr

# the bounds (and step) of a range, which share one integer type: the type, the error type
# when they do not
# `lo..x + 1` noted for zap fmt as `lo..=x`
fn noteInclusiveRange(mut c Checker, iter NodeId, hiE NodeId):
	if not noting or nodes[hiE].kind != nBinary or nodes[hiE].ival != binAdd: return
	one = nodes[hiE].kids[1]
	if nodes[one].kind != nInt or nodes[one].text != "1": return
	src = c.file if c.curFile == "" else c.curFile
	text = sourceLineOf(src, nodes[iter].line)
	dd = nodes[iter].col - 1
	plus = nodes[hiE].col - 1
	if nodes[hiE].line != nodes[iter].line or dd < 0 or plus < 2 or plus + 3 > text.len or
		text[dd..dd + 2] != ".." or text[plus - 1..plus + 3] != " + 1":
		return
	if dd + 2 < text.len and text[dd + 2] == '=': return
	if plus + 3 < text.len and text[plus + 3].isWordByte(): return
	c.canonNote(noteReplace, nodes[iter].line, dd + 1, 2, "..=")
	c.canonNote(noteReplace, nodes[iter].line, plus, 4, "")

fn checkRangeBounds(mut c Checker, iter NodeId) TypeId:
	line = nodes[iter].line
	col = nodes[iter].col
	if nodes[iter].kids.len < 2 or nodes[iter].hasFlag(flagOpenEnd):
		c.errorAt(line, col, compileError("OpenRange", []))
		return tyError
	# a literal bound adopts the type of the other bound (0..count with count i64)
	loE = nodes[iter].kids[0]
	hiE = nodes[iter].kids[1]
	c.noteInclusiveRange(iter, hiE)
	lo TypeId = tyError
	hi TypeId = tyError
	# a bound read through a reference (a loop's element, a parameter) is its value
	if nodes[loE].kind == nInt and nodes[hiE].kind != nInt:
		hi = c.derefIfRef(hiE, c.checkExpr(hiE, none))
		lo = c.derefIfRef(loE, c.checkExpr(loE, c.numOrNone(hi)))
	else:
		lo = c.derefIfRef(loE, c.checkExpr(loE, none))
		hi = c.derefIfRef(hiE, c.checkExpr(hiE, c.numOrNone(lo)))
	if c.tKind(lo) != tInt and c.tKind(lo) != tError:
		c.errorAt(line, col, compileError("RangeNotInteger", ["{c.showTy(lo)}"]))
		return tyError
	elif not isSameType(tys, lo, hi) and c.joinedInts([loE, hiE], none) == none:
		c.errorAt(
			line,
			col,
			compileError("RangeBoundsDiffer", ["{c.showTy(lo)}", "{c.showTy(hi)}"])
		)
		return tyError
	base = rangeBase(tys, lo) if c.tKind(lo) == tInt and not isDefined(tys, lo) else lo
	if nodes[iter].kids.len > 2:
		stepE = nodes[iter].kids[2]
		st = c.checkExpr(stepE, base)
		if not isSameType(tys, rangeBase(tys, st), base):
			c.errorAt(
				line,
				col,
				compileError("RangeStepType", ["{c.showTy(base)}", "{c.showTy(st)}"])
			)
		elif nodes[stepE].kind == nInt and nodes[stepE].text == "0":
			errorAt(
				c,
				line,
				col,
				compileError("RangeStepZero", [])
			)
	nodes[iter].ty = base
	c.loopVarType(iter, base)

# for x in a over a T[N]: for $i in 0..N { x = ref a[$i] ... }, checked as written so; the array
# is a variable or a field of one, so naming it each time evaluates nothing again. A number the
# body does not change is x = a[$i]: read once, where a reference is read at each use (a store
# between two may change it, as far as the code can tell).
fn forArray(mut c Checker, s NodeId, at TypeId):
	# a length a number parameter gives is its name: each instance's own value
	sized = tys[at].bits >= 0
	text = str(tys[at].bits) if sized else tys[valOf(tys, at)].param.copy()
	hi = newNode(nodes, nInt if sized else nIdent, nodes[s].line, nodes[s].col, text = text)
	inner = innerOf(tys, at)
	k = c.tKind(inner)
	borrow = unRef
	if nodes[s].hasFlag(flagMut):
		borrow = unMutRef
	elif k in [tInt, tFloat, tBool]:
		borrow = -1
	c.forByIndex(s, hi, borrow, "a {c.showTy(at)}")

# `for mut x in` a range, a text, a sequence, a table, a grid or a pool: no element to change
fn noMutName(mut c Checker, s NodeId):
	if nodes[s].hasFlag(flagMut):
		c.errorAt(
			nodes[s].line,
			nodes[s].col,
			compileError("MutLoopNoElement", ["{nodes[s].text}"])
		)

# for b in s over a str: for $i in 0..s.len { b = s[$i] }, each byte a u8 (as s[i] is); the
# str is a variable or a field of one
fn forBytes(mut c Checker, s NodeId):
	line = nodes[s].line
	col = nodes[s].col
	c.forByIndex(s, lenOf(nodes, line, col, cloneTree(nodes, nodes[s].kids[0])), -1, "a str")

# The loop `for x in v` made `for $i in 0..upper { x = v[$i] }` (the element lent with
# `borrow`, unRef or unMutRef, when it is not -1) and checked; v must be a variable, or a field
# or an element of one at an index the body does not change, as it is named twice.
fn forByIndex(mut c Checker, s NodeId, upper NodeId, borrow i64, what str):
	line = nodes[s].line
	col = nodes[s].col
	iter = nodes[s].kids[0]
	root = iter
	while nodes[root].kind == nField or nodes[root].kind == nDeref or
		nodes[root].kind == nIndex and c.steadyIndex(root, nodes[s].sub()[0]):
		root = nodes[root].kids[0]
	if nodes[root].kind != nIdent:
		errorAt(
			c,
			line,
			col,
			compileError("ForNeedsPlace", ["{what}"])
		)
		return
	idxName = "$i{s}"
	zero = newNode(nodes, nInt, line, col, text = "0")
	r = newNode(nodes, nRange, line, col, kids = [zero, upper])
	idx = newNode(nodes, nIdent, line, col)
	nodes[idx].text = idxName.copy()   # the index variable is named in two nodes
	elem = newNode(nodes, nIndex, line, col)
	nodes[elem].kids = [iter, idx]
	if borrow >= 0:
		lend = newNode(nodes, nUnary, line, col)
		nodes[lend].ival = i32(borrow)
		nodes[lend].kids = [elem]
		elem = lend
	bind = newNode(nodes, nLet, line, col)
	nodes[bind].text = move nodes[s].text   # the loop's name moves to the binding
	nodes[bind].flags = flagInternal
	nodes[bind].kids = [elem]
	body = nodes[s].sub()[0]
	nodes[body].kids.insert(0, bind)
	nodes[s].text = idxName
	nodes[s].kids = [r]
	nodes[s].flags &= ~flagMut   # (the element's binding says it)
	c.checkFor(s)

# whether the index of the element e (`rows[r]`) is the same on each turn of the loop body: a
# number, or a name the body does not change (an outer loop's element read through its reference)
fn steadyIndex(mut c Checker, e NodeId, body NodeId):
	if nodes[e].kids.len != 2: return false
	at = nodes[e].kids[1]
	if nodes[at].kind == nDeref: at = nodes[at].kids[0]
	if nodes[at].kind == nInt: return true
	nodes[at].kind == nIdent and not c.changesName(body, nodes[at].text.copy(), tyN64)

# `for k, v in m` over a map m (the parser wrote it as a list's: `v = ref m[k]` first in the body)
# made `for $cell in 0..mapEntryCount(m)`, its body under `if mapEntryAlive(m, $cell)` with `k`
# the cell's key and `v` a reference to its value, and checked; false when m is no map
fn forMapCells(mut c Checker, s NodeId) bool:
	body = nodes[s].sub()[0]
	bind = nodes[body].kids[0]
	m = nodes[nodes[nodes[bind].kids[0]].kids[0]].kids[0]   # ref m[k]
	probe = cloneTree(nodes, m)
	mt = c.derefIfRef(probe, c.checkExpr(probe, none))
	if c.tKind(mt) != tMap: return false
	line = nodes[s].line
	col = nodes[s].col
	cell = "$cell{s}"
	count = newNode(
		nodes,
		nCall,
		line,
		col,
		kids = [c.internalName("mapEntryCount", line, col), cloneTree(nodes, m)]
	)
	zero = newNode(nodes, nInt, line, col, text = "0")
	key = newNode(
		nodes,
		nLet,
		line,
		col,
		text = move nodes[s].text,
		kids = [c.cellCall(c.mapKeyReader(mt), m, cell, line, col)]
	)
	nodes[key].flags = flagInternal
	nodes[bind].kids = [c.cellCall("mapValAt", m, cell, line, col)]
	nodes[body].kids.insert(0, key)
	alive = newNode(nodes, nIf, line, col, kids = [c.cellCall("mapEntryAlive", m, cell, line, col)])
	nodes[alive].nodePart().sub = [body]
	nodes[s].text = cell
	nodes[s].kids = [newNode(nodes, nRange, line, col, kids = [zero, count])]
	nodes[s].nodePart().sub = [newNode(nodes, nBlock, line, col, kids = [alive])]
	nodes[s].flags &= ~flagInternal
	c.checkFor(s)
	true

# a call of the runtime's function name on map m and its cell
fn cellCall(mut c Checker, name str, m NodeId, cell str, line i64, col i64) NodeId:
	at = newNode(nodes, nIdent, line, col, text = cell.copy())
	newNode(
		nodes,
		nCall,
		line,
		col,
		kids = [c.internalName(name, line, col), cloneTree(nodes, m), at]
	)

fn checkFor(mut c Checker, s NodeId):
	line = nodes[s].line
	col = nodes[s].col
	iter = nodes[s].kids[0]
	if nodes[s].hasFlag(flagInternal) and c.forMapCells(s): return
	if c.isParallelStep(iter):
		c.noMutName(s)
		c.checkParallelFor(s)
		return
	if c.isParallelMap(iter) and nodes[s].text != "":
		c.noMutName(s)
		c.checkParallelStream(s)
		return
	varT = tyError
	gridMark = c.gridLoops.len
	if nodes[iter].kind == nRange:
		c.enterGridLoop(s)
		varT = c.checkRangeBounds(iter)
	elif c.splitOverText(iter):
		# for part in text.split(sep): windows over the text, one per part, no copies
		sep = nodes[iter].kids[1]
		st = c.derefIfRef(sep, c.checkExpr(sep, tyStr))
		if c.tKind(st) != tStr and c.tKind(st) != tError:
			c.errorAt(line, col, compileError("SplitSeparator", ["{c.showTy(st)}"]))
		nodes[iter].ty = tyStr
		varT = tyStr
	elif c.isLinesCall(iter):
		# for line in text.lines(): windows over the text, one per line, no copies
		recv = nodes[nodes[iter].kids[0]].kids[0]
		rt = c.derefIfRef(recv, c.checkExpr(recv, none))
		if c.tKind(rt) != tStr and c.tKind(rt) != tError:
			c.errorAt(line, col, compileError("LinesNeedsStr", ["{c.showTy(rt)}"]))
		nodes[iter].ty = tyStr
		varT = tyStr
	else:
		walked = c.walkedPool(s)
		c.seqOk = iter
		iterT = c.derefIfRef(iter, c.checkExpr(iter, none))
		if walked is walked and c.tKind(iterT) == tList:
			c.noMutName(s)
			c.checkPoolWalk(s, walked, innerOf(tys, iterT))
			return
		if c.tKind(iterT) == tArray:
			c.forArray(s, iterT)
			return
		if c.tKind(iterT) == tStr:
			c.noMutName(s)
			c.forBytes(s)
			return
		if c.isTable(iterT):
			c.noMutName(s)
			c.forTable(s)
			return
		if c.gridKind(iterT) > 0 or not nodes[s].names().isEmpty:
			c.noMutName(s)
			c.forGridCells(s, c.gridKind(iterT), iterT)
			return
		if c.tKind(iterT) == tList and nodes[s].hasFlag(flagMut):
			c.forByIndex(s, lenOf(nodes, line, col, cloneTree(nodes, iter)), unMutRef, "a list")
			return
		if c.tKind(iterT) == tList:
			c.giveUpEmptyList(iter)
			varT = tys[iterT].inner ?? c.untoldList(iter, line, col)
		elif c.tKind(iterT) == tSeq:
			varT = innerOf(tys, iterT)
		elif c.tKind(iterT) != tError:
			errorAt(
				c,
				line,
				col,
				compileError("ForNotIterable", ["{c.showTy(iterT)}"])
			)
	c.noMutName(s)
	c.noteElementLoop(s)
	c.enterScope()
	v = c.addVar(nodes[s].text, varT, false, false, line, col)
	c.noteLoopLength(iter, v)
	c.checkLoopBody(nodes[s].sub()[0])
	c.exitScope()
	c.gridLoops.truncate(gridMark)
	c.proveLoopIndexes(s)
	c.proveLoopSums(s)

# `for i in 0..xs.len:` whose body reads xs[i] and nothing else of xs or i: noted for zap fmt as
# `for x in xs:` with each xs[i] as x (`for i, x in xs:` when i is read on its own too). The
# element's name is the list's without its final s (items: item), or `each`.
fn noteElementLoop(mut c Checker, s NodeId):
	if not noting: return
	iter = nodes[s].kids[0]
	if nodes[iter].kind != nRange or nodes[iter].kids.len != 2: return
	lo = nodes[iter].kids[0]
	hi = nodes[iter].kids[1]
	if nodes[lo].kind != nInt or nodes[lo].text != "0": return
	placeNode = c.lenReceiver(hi) ?? return
	if not c.fieldChain(placeNode) or
		c.tKind(c.derefType(typeOf(nodes, placeNode))) not in [tList, tArray, tStr]:
		return   # a map's m[i] reads the key i, not the i-th cell
	place = exprText(nodes, placeNode)
	index = nodes[s].text
	if index == "_" or index == place: return
	body = nodes[s].sub()[0]
	firstLet = c.elementLet(body, place, index)
	uses = LoopUses(reads = 0, other = false, blocked = false, writes = false, letOf = firstLet)
	for st in nodes[body].kids.copy():
		if st != firstLet:
			c.loopUses(st, place, index, false, uses)
	if uses.blocked or uses.reads == 0 and firstLet == none or uses.writes and firstLet != none:
		return
	if uses.writes and c.bindsElementPart(body, place, index) or
		c.lendsIndexedElement(body, place, index):
		return   # the rewrite would not check (read while lent, or an element lent by `for x in xs`)
	each = ""
	if firstLet is firstLet:
		each = nodes[firstLet].text.copy()   # `l = xs[i]` as the first statement: l is the element
	else:
		dot = place.lastIndexOf(".") ?? -1
		last = place[dot + 1..]
		each = singularOf(last)
		if each == "": return   # no singular to name the element (pos, status, axis)
		if each in keywords or c.lookupVar(each) >= 0 or each == index or
			c.mentionsName(body, each):
			return
	name = "mut {each}" if uses.writes else each   # a loop that changes its element says so
	src = c.file if c.curFile == "" else c.curFile
	text = sourceLineOf(src, nodes[s].line)
	head = "{index} in 0..{place}.len"
	at = nodes[s].col - 1 + 4
	if at + head.len > text.len or text[at..at + head.len] != head: return
	canonNote(
		c,
		noteReplace,
		nodes[s].line,
		at + 1,
		head.len,
		"{index}, {name} in {place}" if uses.other else "{name} in {place}"
	)
	if firstLet is firstLet:
		letText = sourceLineOf(src, nodes[firstLet].line)
		letAt = nodes[firstLet].col - 1
		canonNote(   # the binding goes: the loop binds it
			c,
			noteReplace,
			nodes[firstLet].line,
			letAt + 1,
			codeOf(letText).trimmedEnd().len - letAt,
			""
		)
	for st in nodes[body].kids.copy():
		if st != firstLet:
			c.loopReadNotes(st, place, index, each)

# whether e matches a part of place[index] with a pattern that binds (the part is lent while the
# loop's element is changed: `mut each` would read it while lent)
fn bindsElementPart(mut c Checker, e NodeId, place str, index str) bool:
	if nodes[e].kind == nMatch and "{place}[{index}]" in exprText(nodes, nodes[e].kids[0]) and
		nodes[e].kids[1..].any(
			nodes[nodes[it].kids[0]].ival == patCtor and not nodes[nodes[it].kids[0]].kids.isEmpty
		):
		return true
	nodes[e].kids.any(c.bindsElementPart(it, place, index)) or
		nodes[e].sub().any(c.bindsElementPart(it, place, index))

# whether e calls a function with place[index] for a `mut` parameter: `for x in xs` lends x
# immutably, so the rewrite would not check
fn lendsIndexedElement(mut c Checker, e NodeId, place str, index str) bool:
	if nodes[e].kind == nCall and c.callLendsIndexedElement(e, place, index): return true
	nodes[e].kids.any(c.lendsIndexedElement(it, place, index)) or
		nodes[e].sub().any(c.lendsIndexedElement(it, place, index))

# whether an argument of the call e is place[index] and stands for a parameter named mut
fn callLendsIndexedElement(mut c Checker, e NodeId, place str, index str):
	callee = nodes[e].kids[0]
	mask = 0
	first = 0
	fd NodeId? = none
	if nodes[callee].kind == nField and nodes[callee].kids.len == 1:
		recv = nodes[callee].kids[0]
		t = nodes[recv].text
		named = nodes[recv].kind == nIdent and t != "" and
			(
				t[0] >= 'A' and t[0] <= 'Z' or t == "rt" or
					c.lookupVar(t) < 0 and c.findImportByAlias(c.curMod, t) != none
			)
		mask = c.mutParamsOf(nodes[callee].text.copy())
		first = 0 if named else 1
	elif nodes[callee].kind == nIdent:
		fd = c.lookupDecl(nFnDecl, "", nodes[callee].text.copy(), nodes[e].line, nodes[e].col)
	for j in 1..nodes[e].kids.len:
		arg = nodes[e].kids[j]
		if nodes[arg].kind != nIndex or nodes[arg].kids.len != 2 or
			exprText(nodes, nodes[arg].kids[0]) != place or
			exprText(nodes, nodes[arg].kids[1]) != index:
			continue
		at = j - 1 + first
		if at < 63 and mask & (1 << at) != 0: return true
		if fd is f and j - 1 < nodes[f].kids.len and nodes[nodes[f].kids[j - 1]].ival == modeMut:
			return true
	false

# the singular of a list's name (items: item, bodies: body, batches: batch), or "" when it has none
fn singularOf(word str):
	if word.len < 2 or not word.endsWith("s") or ["ss", "us", "is", "os"].any(word.endsWith(it)):
		return ""
	if word.endsWith("ies"): return "{word[..len - 3]}y"
	if ["ches", "shes", "xes", "sses"].any(word.endsWith(it)): return word[..len - 2].copy()
	word[..len - 1].copy()

# the value whose `len` e reads (also once the checker made it its runtime function's call, the
# receiver its first argument), else none
fn lenReceiver(c Checker, e NodeId) NodeId?:
	if nodes[e].kind != nCall: return none
	callee = nodes[e].kids[0]
	if nodes[e].hasFlag(flagMethod):
		named = nodes[e].kids.len == 2 and not nodes[callee].names().isEmpty and
			nodes[callee].names()[0] == "len"
		return nodes[e].kids[1] if named else none
	if nodes[e].kids.len == 1 and nodes[callee].kind == nField and nodes[callee].text == "len" and
		nodes[callee].kids.len == 1:
		return nodes[callee].kids[0]
	none

# whether e is a name, or a field of one (a place `for i, x in` takes as its list)
fn fieldChain(mut c Checker, e NodeId) bool:
	if nodes[e].kind == nIdent: return true
	nodes[e].kind == nField and nodes[e].kids.len == 1 and c.fieldChain(nodes[e].kids[0])

type LoopUses:
	reads i64   # xs[i] read
	other bool   # i read on its own
	blocked bool   # xs or i used in a way `for x in xs` cannot say
	writes bool   # xs[i] changed (xs a `mut` place, whose loop's name changes the element)
	letOf NodeId?   # the first statement `l = xs[i]`, whose name is the element's

# the body's first statement when it is `name = place[index]`, an immutable binding of the
# element read (the loop can bind the element itself), else none
fn elementLet(mut c Checker, body NodeId, place str, index str) NodeId?:
	if nodes[body].kids.isEmpty: return none
	st = nodes[body].kids[0]
	if nodes[st].kind != nLet or nodes[st].hasFlag(flagMut) or not nodes[st].types().isEmpty or
		nodes[st].text == "_" or nodes[st].kids.len != 1:
		return none
	v = nodes[st].kids[0]
	if nodes[v].kind != nIndex or nodes[v].kids.len != 2 or
		exprText(nodes, nodes[v].kids[0]) != place:
		return none
	idx = nodes[v].kids[1]
	if nodes[idx].kind != nIdent or nodes[idx].text != index or
		not c.readWrittenAs(v, place, index):
		return none
	if nodes[st].text in keywords or c.namesBound(nodes[st].text, nodes[st].line, nodes[st].col):
		return none   # an assignment of a name bound before the loop, which keeps the last element
	st

# the uses of the place and the index in e, writing when e is the target of an assignment
fn loopUses(mut c Checker, e NodeId, place str, index str, writing bool, mut uses LoopUses):
	k = nodes[e].kind
	if k == nIndex and nodes[e].kids.len == 2 and exprText(nodes, nodes[e].kids[0]) == place:
		idx = nodes[e].kids[1]
		# changed only when the list is a `mut` place: the loop's name changes it then
		if nodes[idx].kind == nIdent and nodes[idx].text == index and
			(not writing or c.mutRooted(nodes[e].kids[0])) and c.readWrittenAs(e, place, index):
			uses.reads += 1
			uses.writes = uses.writes or writing
			return
		uses.blocked = true   # changed, indexed otherwise, or written through an alias
		return
	if k == nAssign and nodes[nodes[e].kids[0]].kind == nIndex and
		exprText(nodes, nodes[nodes[e].kids[0]].kids[0]) == place:
		uses.blocked = true   # a whole element assigned: an index loop, as the vector loops are
		return
	if k == nIdent and nodes[e].text == index:
		uses.other = true
		return
	if k == nIdent and exprText(nodes, e) == place:
		uses.blocked = true   # the list itself, handed on or changed
		return
	if writing and k in [nIdent, nField] and place.startsWith("{exprText(nodes, e)}.") or
		k == nLet and (nodes[e].text == place or place.startsWith("{nodes[e].text}.")):
		uses.blocked = true   # the list, or its owner, assigned
		return
	if k == nField and exprText(nodes, e) == place:
		uses.blocked = true
		return
	if k == nUnary and nodes[e].ival in [unMove, unRef, unMutRef]:
		inner = nodes[e].kids[0]
		if nodes[inner].kind == nIndex and exprText(nodes, nodes[inner].kids[0]) == place or
			nodes[e].ival == unMutRef and "{place}[{index}]" in exprText(nodes, inner):
			uses.blocked = true   # the element (or a part of it, to change) lent or moved
			return
		c.loopUses(inner, place, index, true, uses)
		return
	for i in 0..nodes[e].kids.len:
		# a target, a binding, and an element indexed again or asked for a field or a method: not a
		# plain read
		loopUses(
			c,
			nodes[e].kids[i],
			place,
			index,
			writing or (k in [nAssign, nIndex, nField] and i == 0) or (k == nLet and nodes[nodes[e].kids[i]].kind == nIndex),
			uses
		)
	for b in nodes[e].sub().copy():
		c.loopUses(b, place, index, false, uses)

# whether the place e starts at a `mut` variable
fn mutRooted(mut c Checker, e NodeId):
	v = c.lookupVar(c.rootName(e).copy())
	v >= 0 and c.vars[v].isMut

# whether the index e is written `place[index]` in the source (not through an alias of the list)
fn readWrittenAs(mut c Checker, e NodeId, place str, index str):
	src = c.file if c.curFile == "" else c.curFile
	text = sourceLineOf(src, nodes[e].line)
	written = "{place}[{index}]"
	dot = place.lastIndexOf(".") ?? -1
	at = nodes[e].col - 1 - (dot + 1)
	at >= 0 and at + written.len <= text.len and text[at..at + written.len] == written

# whether a name is bound where a statement at line:col reads it: a local or a mut module variable
fn namesBound(mut c Checker, name str, line i64, col i64):
	c.lookupVar(name) >= 0 or c.mutModuleVar(name, line, col)

# whether a name read at line:col is a mut module variable's
fn mutModuleVar(mut c Checker, name str, line i64, col i64):
	isFlagged(nodes, c.lookupDecl(nConstDecl, "", name, line, col), flagMut)

# whether a name is mentioned in e (a binding of it, or a read)
fn mentionsName(mut c Checker, e NodeId, name str) bool:
	if nodes[e].text == name and nodes[e].kind in [nIdent, nLet, nFor]: return true
	nodes[e].kids.any(c.mentionsName(it, name)) or
		nodes[e].sub().any(c.mentionsName(it, name))

# each `place[index]` of e noted as the element's name
fn loopReadNotes(mut c Checker, e NodeId, place str, index str, each str):
	k = nodes[e].kind
	if k == nIndex and nodes[e].kids.len == 2 and exprText(nodes, nodes[e].kids[0]) == place and
		nodes[nodes[e].kids[1]].kind == nIdent and nodes[nodes[e].kids[1]].text == index:
		src = c.file if c.curFile == "" else c.curFile
		text = sourceLineOf(src, nodes[e].line)
		written = "{place}[{index}]"
		dot = place.lastIndexOf(".") ?? -1
		at = nodes[e].col - 1 - (dot + 1)   # an index's column is its base's: a field's is the field name's
		if at >= 0 and at + written.len <= text.len and
			text[at..at + written.len] == written:
			c.canonNote(noteReplace, nodes[e].line, at + 1, written.len, each)
		return
	for kid in nodes[e].kids.copy():
		c.loopReadNotes(kid, place, index, each)
	for b in nodes[e].sub().copy():
		c.loopReadNotes(b, place, index, each)

# Whether an expression only makes a value: arithmetic, a name, a literal, or a call of a method
# of a list, a map or a string that makes a value (methodMakesValue). As a statement its value is lost, which is a
# mistake (the sorted copy dropped), never a choice.
# `_ = f()` where f gives no result (T ? E): the call alone drops its value, noted for zap fmt
fn noteDroppedCall(mut c Checker, s NodeId):
	if not noting: return
	fd = c.curFn ?? return
	body = nodes[fd].sub()[0] if not nodes[fd].sub().isEmpty else s
	if not nodes[body].kids.isEmpty and nodes[body].kids[nodes[body].kids.len - 1] == s: return   # a body's last: the call alone would be its result
	src = c.file if c.curFile == "" else c.curFile
	text = sourceLineOf(src, nodes[s].line)
	at = nodes[s].col - 1
	if at < 0 or at + 4 > text.len or text[at..at + 4] != "_ = ": return
	c.canonNote(noteReplace, nodes[s].line, nodes[s].col, 4, "")

fn makesValueOnly(mut c Checker, e NodeId):
	k = nodes[e].kind
	if k in [nBinary, nIdent, nInt, nFloat, nStr, nBool, nField, nIndex]: return true
	if k != nCall or nodes[nodes[e].kids[0]].kind != nField: return false
	callee = nodes[e].kids[0]
	rt = nodes[nodes[callee].kids[0]].ty ?? return false
	rk = c.tKind(rt)
	if rk == tRef:
		rk = c.tKind(tys[rt].inner)
	(rk in [tList, tMap, tStr]) and c.methodMakesValue(nodes[callee].text)
