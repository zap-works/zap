# The checker's numeric widening, coercions, references, origins and mutability rules (check.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# Wraps a plain value in nSome when it is stored where T? (or T ? E) is expected, so the
# backend builds the box. Returns the expression to store (possibly the original).
# Widening between numbers happens on its own: an integer where a wider integer of the same
# `f64(x)`; a narrowing only where proven (narrowProven). Returns the node to use.
# `f64(x)`. A narrowing or a sign change is made only where proven (narrowProven). Returns the node.
fn numWiden(mut c Checker, e NodeId, maybeTarget TypeId?) NodeId:
	target = maybeTarget ?? return e
	src = nodes[e].ty ?? return e
	if c.tKind(src) == tRef:
		src = innerOf(tys, src)
	if c.tKind(src) != tInt: return e
	m = ""
	if c.floatHolds(src, target):
		m = "toF64" if tys[target].bits == 64 else "toF32"
	elif c.tKind(target) == tFloat and nodes[e].kind == nInt and c.exactFloatLiteral(e, target):
		m = "toF32"   # a generic's literal where its f32 instance wants a float: f32 holds it exactly
	elif c.intWidens(src, target):
		m = intConversionTo(tys, target)
	if m == "": return e
	c.widenedCall(e, m, target)

# whether the float type dst holds every value of the integer type src: an f64 any integer, an
# f32 one of 16 bits or fewer (spec 3.1)
fn floatHolds(c Checker, src TypeId, dst TypeId):
	c.tKind(src) == tInt and c.tKind(dst) == tFloat and
		(tys[dst].bits == 64 or tys[src].bits <= 16 and not isDefined(tys, src))

# the conversion method into integer type t: toI64, toU8...
fn intConversionTo(ts Ty[], t TypeId):
	"to{"I" if ts[t].isSigned else "U"}{ts[t].bits}"

# e, an integer where an integer type it does not widen to is expected (a narrower one, or one of
# another sign): converted to it, as `u8(e)` converts, when its values are proven inside it
# (spanOf), else e. Only where a value lands (fitValue), never an operand: `small + r % 9` is
# computed in the wider type.
fn narrowProven(mut c Checker, e NodeId, target TypeId) NodeId:
	if not c.narrowsProven(e, target): return e
	c.widenedCall(e, intConversionTo(tys, target), target)

# whether narrowProven converts e to target
fn narrowsProven(mut c Checker, e NodeId, target TypeId):
	src = nodes[e].ty ?? return false
	c.tKind(src) == tInt and c.tKind(target) == tInt and not tys[target].ranged and
		not isDefined(tys, src) and not isDefined(tys, target) and tys[src].param == "" and
		tys[target].param == "" and not isAssignable(tys, src, target) and
		c.provenInside(e, target)

# e given to a place of type target (a typed binding, an assignment, an argument, a return, a
# field, an element): widened to it, or narrowed when proven inside (narrowProven)
fn fitValue(mut c Checker, e NodeId, maybeTarget TypeId?) NodeId:
	widened = c.numWiden(e, maybeTarget)
	if widened != e: return widened
	target = maybeTarget ?? return e
	c.narrowProven(e, target)

# e converted by the conversion method m to target, a call the checker wrote (flagAutoWiden)
fn widenedCall(mut c Checker, e NodeId, m str, target TypeId):
	callee = newNode(nodes, kidIds, nField, nodes[e].line, nodes[e].col)
	nodes[callee].pushKid(kidIds, e)
	nodes[callee].setText(m.copy())
	nodes[callee].flags |= flagInternal   # the checker's: never a needless conversion
	call = newNode(nodes, kidIds, nCall, nodes[e].line, nodes[e].col)
	nodes[call].pushKid(kidIds, callee)
	c.checkExpr(call, target)
	nodes[call].flags |= flagAutoWiden
	if tys[target].ranged:
		nodes[call].ty = target   # a range into one that holds it: no check
	call

# the common type two numeric operands widen to, or none when they must match as written
fn numCommon(mut c Checker, lt TypeId, rt TypeId) TypeId?:
	if isDefined(tys, lt) or isDefined(tys, rt): return none   # never widened: converted
	lk = c.tKind(lt)
	rk = c.tKind(rt)
	if c.floatHolds(rt, lt): return lt
	if c.floatHolds(lt, rt): return rt
	if lk == tInt and rk == tInt and tys[lt].isSigned == tys[rt].isSigned:
		if tys[lt].bits > tys[rt].bits: return rangeBase(tys, lt)
		return rangeBase(tys, rt)
	if lk == tInt and rk == tInt:
		# an unsigned integer fits a wider signed one without loss (u8 and i64, u32 and i64)
		if tys[lt].isSigned and tys[lt].bits > tys[rt].bits: return rangeBase(tys, lt)
		if tys[rt].isSigned and tys[rt].bits > tys[lt].bits: return rangeBase(tys, rt)
	none

# whether an integer of type src widens to dst without loss: wider and the same sign, or
# wider and signed when src is unsigned
fn intWidens(c Checker, src TypeId, dst TypeId):
	intWidensTy(tys, src, dst)

# e's child i coerced to the type (coerceTo), or widened to it (numWiden)
fn coerceKid(mut c Checker, e NodeId, i i64, maybeTarget TypeId?):
	made = c.coerceTo(nodes[e].kids(kidIds)[i], maybeTarget)
	nodes[e].setKid(kidIds, i, made)

fn widenKid(mut c Checker, e NodeId, i i64, maybeTarget TypeId?):
	made = c.numWiden(nodes[e].kids(kidIds)[i], maybeTarget)
	nodes[e].setKid(kidIds, i, made)

fn coerceTo(mut c Checker, e NodeId, maybeTarget TypeId?) NodeId:
	target = maybeTarget ?? return e
	if isRangeIntoWrapped(tys, nodes[e].ty, target):
		return c.coerceTo(c.numWiden(e, tys[target].inner), target)   # the range widened, then wrapped
	c.noteWidenedAt(e, target)
	et = typeOf(nodes, e)
	if c.tKind(et) == tRef and c.tKind(target) != tRef and
		not isSameType(tys, et, target) and
		not (c.isOptionOfRef(target) and isSameType(tys, tys[target].inner, et)):
		# a reference where its value is expected (not an optional reference): the value it points to
		c.derefNode(e)
		et = typeOf(nodes, e)
	if c.intWidens(et, target) or c.floatHolds(et, target):
		return c.numWiden(e, target)   # a narrower integer widens without loss
	if c.tKind(et) == tBox and not c.boxExpected(target) and
		not isSameType(tys, et, target):
		# a box where its value is expected: the value it holds
		c.derefNode(e)
		et = typeOf(nodes, e)
	if c.isOptionOfRef(et) and c.tKind(target) == tOption and not c.isOptionOfRef(target) and
		not isSameType(tys, et, target):
		# an optional reference where an optional value is expected
		c.derefNode(e)
		et = typeOf(nodes, e)
	if typeNeedsResWrap(tys, et, target):
		s = newNode(nodes, kidIds, nSome, nodes[e].line, nodes[e].col)
		nodes[s].pushKid(kidIds, e)
		rk = 2
		if isSameType(tys, et, tys[target].inner):
			rk = 1
		nodes[s].ival = rk
		nodes[s].ty = target
		return s
	if not typeNeedsOptWrap(tys, et, target): return e
	s = newNode(nodes, kidIds, nSome, nodes[e].line, nodes[e].col)
	nodes[s].pushKid(kidIds, e)
	nodes[s].ty = target
	s

# whether a Box fits the target as it is: a Box, an optional Box, a result with a Box side, or a
# reference
fn boxExpected(c Checker, target TypeId):
	k = c.tKind(target)
	if k == tBox or k == tRef: return true
	if k == tResult and tys[errOf(tys, target)].kind == tBox: return true
	(k == tOption or k == tResult) and tys[target].inner != none and
		tys[innerOf(tys, target)].kind == tBox

# whether e is a shared value seen as its struct (the receiver of one of its own methods)
fn isSharedDeref(c Checker, e NodeId):
	if nodes[e].kind != nDeref: return false
	rt = nodes[nodes[e].kids(kidIds)[0]].ty ?? return false
	tys[rt].kind == tBox and tys[rt].counted

# Rewrites a reference-typed expression in place into the value it points to (nDeref), so the
# parents keep their child ids. Returns the node.
fn isOptionOfRef(c Checker, t TypeId):
	c.tKind(t) == tOption and tys[t].inner != none and tys[innerOf(tys, t)].kind == tRef

# the type a dereference produces: T for ref T, T? for (ref T)?
fn derefType(mut c Checker, t TypeId):
	if c.tKind(t) == tRef or c.tKind(t) == tBox: return innerOf(tys, t)
	if c.isOptionOfRef(t): return tyOption(tys, tys[innerOf(tys, t)].inner)
	t

# the callee of a method call as written (`x.get`), also once the checker made the call one of
# its runtime function
fn writtenCallee(c Checker, call NodeId):
	first = nodes[call].kids(kidIds)[0]
	c.undoneCallee(first) if nodes[call].hasFlag(flagMethod) else first

# the callee a runtime function's name node stands for (checkRuntimeMethod keeps it in origin)
fn undoneCallee(c Checker, name NodeId):
	nodes[name].origin(kidIds) ?? fail("a runtime method's name keeps its callee")

# The place target is about to change: `m[k]` along it lends the value to be changed (index
# becomes indexMut), and a match arm's name for what `x.get(k)` found makes that call getMut,
# the body checked again.
fn lendForChange(mut c Checker, target NodeId):
	e = target
	while nodes[e].kind in [nDeref, nField, nIndex]:
		inner = nodes[e].kids(kidIds)[0]
		if nodes[e].kind == nDeref and nodes[e].hasFlag(flagInternal) and
			nodes[inner].kind == nCall:
			callee = c.writtenCallee(inner)
			if nodes[callee].text in ["index", "indexLive"]:
				nodes[callee].setText("{nodes[callee].text}Mut")
				nodes[e].ty = c.derefType(c.checkExpr(inner, none))
			return
		if nodes[e].kind == nDeref and nodes[inner].kind == nIdent:
			v = c.lookupVarNo(nameOf(nodes, inner))
			from = c.vars[v].lentFrom if v >= 0 else none
			if from is from and nodes[c.writtenCallee(from)].text in ["get", "getLive"]:
				nodes[c.writtenCallee(from)].setText("{nodes[c.writtenCallee(from)].text}Mut")
				c.relend = true
			return
		e = inner

# The expression e moved whole into a new node, which is returned; e keeps its position and
# origin (an expression node has no file, module or bounds) and is rebuilt by the caller.
fn moveIntoInner(mut c Checker, e NodeId):
	inner = newNode(nodes, kidIds, nIdent, nodes[e].line, nodes[e].col)
	nodes[inner] = move nodes[e]
	nodes[e].line = nodes[inner].line
	nodes[e].col = nodes[inner].col
	nodes[e].part = 0
	nodes[e].setOrigin(kidIds, nodes[inner].origin(kidIds))
	inner

# Rewrites an expression in place into `ref expr` (nUnary): the parents keep their child ids.
fn refNode(mut c Checker, e NodeId):
	inner = c.moveIntoInner(e)
	vt = typeOf(nodes, inner)
	nodes[e].kind = nUnary
	nodes[e].setKids(kidIds, [inner])
	nodes[e].setText("")
	nodes[e].flags = flagAlias | flagAutoRef   # made by the compiler: may reference a temporary
	nodes[e].ival = unRef
	nodes[e].ty = tyRef(tys, vt, false)
	e

fn derefNode(mut c Checker, e NodeId):
	inner = c.moveIntoInner(e)
	nodes[inner].flags &= ~flagAutoCopy
	rt = typeOf(nodes, inner)
	nodes[e].kind = nDeref
	nodes[e].setKids(kidIds, [inner])
	nodes[e].setText("")
	nodes[e].flags = flagAutoRef
	nodes[e].ival = 0
	nodes[e].ty = c.derefType(rt)
	e

# dereferences the expression when it has a reference type; returns the resulting type
fn derefIfRef(mut c Checker, e NodeId, t TypeId):
	if c.tKind(t) != tRef and c.tKind(t) != tBox: return t
	c.derefNode(e)
	typeOf(nodes, e)

fn rejectRef(mut c Checker, t TypeId, line i64, col i64, what str):
	if c.tKind(t) == tRef:
		c.errorAt(line, col, compileError("NotAReference", ["{what}"]))
	elif c.tKind(t) == tSeq:
		c.rejectSeq(line, col, what)
	elif c.isViewType(t):
		c.errorAt(line, col, compileError("NotAView", ["{what}"]))
	elif c.holdsRefs(t):
		c.errorAt(line, col, compileError("ListOfReferences", ["{what}", "{c.showTy(t)}"]))

# a Seq is written only as a generator's result: it is walked where it is made
fn rejectSeq(mut c Checker, line i64, col i64, what str):
	errorAt(
		c,
		line,
		col,
		compileError("SeqNotStored", ["{what}"])
	)

# what a list element or a map value may be: a value, or a read reference (the list then
# borrows what its elements point to)
fn rejectHeldRef(mut c Checker, t TypeId, line i64, col i64, what str):
	if c.tKind(t) == tRef and tys[t].bits == 1:
		c.errorAt(line, col, compileError("MutRefNotAllowed", ["{what}"]))
	elif c.tKind(t) != tRef and not c.isExternView(t):
		c.rejectRef(t, line, col, what)

# an extern type holding C pointers: a list of them is a C array, and borrows as a list of
# references does
pub fn isExternView(mut c Checker, t TypeId) bool:
	c.tKind(t) == tStruct and nodes[declOf(tys, t)].hasFlag(flagExtern) and c.isViewType(t)

# whether t is a list or map that holds references ((ref str)[], {i64: ref Node}, and
# lists of them): an owned value that also borrows what its references point to
pub fn holdsRefs(mut c Checker, t TypeId) bool:
	k = c.tKind(t)
	if k == tList:
		inner = innerOf(tys, t)
		return c.tKind(inner) == tRef or c.holdsRefs(inner) or c.isViewType(inner) or
			c.isExternView(inner)
	if k == tMap:
		key = innerOf(tys, t)
		val = valOf(tys, t)
		return c.tKind(key) == tRef or c.tKind(val) == tRef or c.holdsRefs(val) or
			c.isViewType(val)
	false

# A view is a struct with a reference (or a view) among its fields; it borrows like a reference.
# Its other fields may own memory: then it moves and drops them as any struct, and is plain data
# (copying it copies only pointers) only when they are.
pub fn isViewType(mut c Checker, t TypeId) bool:
	if c.tKind(t) != tStruct or c.viewDepth > 8:
		return false   # recursive types (a Dir holding a Dir[]) end here
	sd = declOf(tys, t)
	# a container's storage (a map's entries of a {str: ref T}): what it holds is the container's;
	# a GridView, and a runtime type of its own with a field written `ref` (a Reader), is a view
	if nodes[sd].mod(kidIds) == "rt":
		return c.gridKind(t) == gridView or
			"<" not in tys[t].display and
			nodes[sd].kids(kidIds).any(nodes[nodes[it].types(kidIds)[0]].kind == nTyRef)
	top = c.viewDepth == 0
	if top:
		if c.views.get(sd) is known: return known
	c.viewDepth += 1
	found = false
	for f in nodes[declOf(tys, t)].kids(kidIds).copy():
		ft = c.resolveType(nodes[f].types(kidIds)[0])
		if c.tKind(ft) == tRef or c.isViewType(ft):
			found = true
	c.viewDepth -= 1
	if top and nodes[sd].names(kidIds).isEmpty:
		c.views[sd] = found   # a declaration with no type parameter: the same at every use
	found

# whether t is a `mut ref`
fn isMutRef(c Checker, t TypeId?):
	c.tKind(t) == tRef and tys[t ?? return false].bits == 1

# ref str (read): what a string literal may be lent as
pub fn isReadRefStr(c Checker, t TypeId?) bool:
	c.tKind(t) == tRef and not c.isMutRef(t) and isSameType(tys, innerOf(tys, t), tyStr)

# reference-like: a reference, an optional reference or a view
pub fn isRefLike(mut c Checker, t TypeId) bool:
	c.tKind(t) == tRef or c.isOptionOfRef(t) or c.isViewType(t)

# whether t is reference-like, or an optional or a result whose value is (a view a call may fail
# to give)
pub fn givesRefLike(mut c Checker, t TypeId) bool:
	k = c.tKind(t)
	if (k == tOption or k == tResult) and tys[t].inner != none: return c.isRefLike(innerOf(tys, t))
	c.isRefLike(t)

# 0 = no reference on the path, 1 = through a mut ref, 2 = through a read ref
fn derefKind(c Checker, e0 NodeId):
	e = e0
	going = true
	while going:
		k = nodes[e].kind
		if k == nDeref:
			rt = nodes[nodes[e].kids(kidIds)[0]].ty
			if rt is rt and tys[rt].kind == tRef:
				if tys[rt].bits == 1: return 1
				return 2
			if rt is rt and tys[rt].kind == tBox and tys[rt].counted: return 3
			e = nodes[e].kids(kidIds)[0]
		elif k == nField or k == nIndex:
			e = nodes[e].kids(kidIds)[0]
		else:
			going = false
	0

# A function returning a reference must have one evident origin among its borrowed parameters;
# with no borrowed parameter at all it points into the module's own data (a constant list's
# element), which lives as long as the program: the origin "$module".
# The origins are recorded in names2 for the ownership analysis, the receiver's as "self.f"
# when every result comes from its field f.
fn checkRefOrigins(mut c Checker, fnd NodeId, implType TypeId?):
	ret = c.writtenResult(fnd)   # (one found is a value)
	if c.tKind(ret) != tRef and not c.isViewType(ret) and not c.holdsRefs(ret): return
	origins = c.refOrigins(fnd, implType, ret)
	field = c.selfFieldReturned(fnd, implType ?? tyError) if "self" in origins else ""
	nodes[fnd].nodeMore(kidIds).names2 = origins.map(
		"self.{field}" if it == "self" and field != "" else it
	)

# the names (parameters, "self", moduleOrigin) what fnd, giving ret, may return points into
fn refOrigins(mut c Checker, fnd NodeId, implType TypeId?, ret TypeId):
	# the candidates are names of their own: the chosen one is recorded in names2
	cands = []
	mutCands = []
	if implType != none:
		cands.push("self")
		if nodes[fnd].hasFlag(flagMut):
			mutCands.push("self")
	for p in nodes[fnd].kids(kidIds).copy():
		pt = c.resolveType(nodes[p].types(kidIds)[0])
		mode = nodes[p].ival
		isRef = c.tKind(pt) == tRef
		if isRef or (mode != modeMove and not c.isPlainType(pt)):
			cands.push(nodes[p].text.copy())
			if mode == modeMut or (isRef and tys[pt].bits == 1):
				mutCands.push(nodes[p].text.copy())
	noBorrows = cands.isEmpty
	pool = move cands
	if c.tKind(ret) == tRef and tys[ret].bits == 1:
		pool = mutCands
	if pool.len == 1: return pool
	if noBorrows and c.tKind(ret) == tRef and tys[ret].bits == 0: return [moduleOrigin]
	# several parameters could be the origin: the body says which, by what it returns
	found = c.bodyOrigins(fnd, pool)
	if found.isEmpty:
		if c.tKind(ret) == tRef and tys[ret].bits == 0:
			found.push(moduleOrigin)   # only literals and constants are returned
		else:
			found = pool.copy()
	found

# the parameters (of pool) what fnd's body returns may point into; all of them with no body (a
# function type)
fn bodyOrigins(mut c Checker, fnd NodeId, pool str[]):
	if nodes[fnd].sub(kidIds).isEmpty: return pool.copy()
	c.readBody(fnd)
	found = []
	body = nodes[fnd].sub(kidIds)[0]
	for e in c.returnedValues(body):
		c.originsOf(body, e, pool, found, 0)
	found

# The field of the receiver every reference method fnd of struct st returns points into
# (`self.part[0].sub` into part), "" when one may point at the receiver as a whole: what a
# borrow of its result keeps from changing. A value from elsewhere (a constant) takes none.
fn selfFieldReturned(mut c Checker, fnd NodeId, st TypeId):
	if nodes[fnd].sub(kidIds).isEmpty or c.tKind(st) != tStruct: return ""
	c.readBody(fnd)
	body = nodes[fnd].sub(kidIds)[0]
	fields = nodes[declOf(tys, st)].kids(kidIds).map(nodes[it].text.copy())
	field = ""
	for e in c.returnedValues(body):
		f = c.selfFieldOf(fnd, body, e, fields, 0) ?? continue
		if f == "" or field != "" and f != field: return ""
		field = f
	field

# the field of self e points into ("" self as a whole or not known), none when e is not from self
fn selfFieldOf(mut c Checker, fnd NodeId, body NodeId, e NodeId, fields str[], depth i64) str?:
	k = nodes[e].kind
	if depth > 12: return ""
	if k in [nStr, nInt, nFloat, nBool, nNone]: return none
	if k == nField and not nodes[e].kids(kidIds).isEmpty:
		obj = nodes[e].kids(kidIds)[0]
		if nodes[obj].kind == nIdent and nodes[obj].text == "self": return nodes[e].text.copy()
	if k in [nUnary, nField, nIndex, nDeref, nTry, nSome] and not nodes[e].kids(kidIds).isEmpty:
		return c.selfFieldOf(fnd, body, nodes[e].kids(kidIds)[0], fields, depth + 1)
	if k != nIdent: return ""
	nm = nodes[e].text.copy()
	if nm == "self": return ""
	at = c.letOf(body, nm)
	if at is at and not nodes[at].kids(kidIds).isEmpty:
		return c.selfFieldOf(fnd, body, nodes[at].kids(kidIds)[0], fields, depth + 1)
	if c.matchedBy(body, nm) is scrutinee:
		return c.selfFieldOf(fnd, body, scrutinee, fields, depth + 1)   # a part of what it matched
	if nodes[fnd].kids(kidIds).any(nodes[it].text == nm): return none   # a parameter's
	if nm in fields: return nm   # a field named bare
	if c.lookupDecl(nConstDecl, "", nm, 0, 0) != none: return none   # the module's data
	""

# the expressions a body gives back: its returns' values and its final expression (not those
# inside a lambda, which returns from itself)
fn returnedValues(c Checker, body NodeId):
	out = []
	c.collectReturns(body, out)
	n = nodes[body].kids(kidIds).len
	if n > 0 and nodes[nodes[body].kids(kidIds)[n - 1]].kind == nExprStmt:
		out.push(nodes[nodes[body].kids(kidIds)[n - 1]].kids(kidIds)[0])
	out

fn collectReturns(c Checker, e NodeId, mut out NodeId[]):
	k = nodes[e].kind
	if k == nLambda: return
	if k == nReturn and not nodes[e].kids(kidIds).isEmpty:
		out.push(nodes[e].kids(kidIds)[0])
	for kid in nodes[e].kids(kidIds):
		c.collectReturns(kid, out)
	for sb in nodes[e].sub(kidIds):
		c.collectReturns(sb, out)

# The parameters (of `pool`) a returned expression may point into, added to found: followed
# through references, fields, elements, the receivers of method calls, the arguments of calls,
# both sides of a choice, and the locals bound on the way. What cannot be followed may point
# into any of them.
fn originsOf(mut c Checker, body NodeId, e NodeId, pool str[], mut found str[], depth i64):
	k = nodes[e].kind
	if depth > 12:
		addAll(pool, found)
		return
	if k in [nStr, nInt, nFloat, nBool, nNone]:
		return   # the program's data
	if k == nIdent:
		nm = nodes[e].text.copy()   # a name of its own: the lookups below change c
		if nm in pool:
			if nm not in found:
				found.push(nm)
			return
		at = c.letOf(body, nm)
		if at is at and not nodes[at].kids(kidIds).isEmpty:
			c.originsOf(body, nodes[at].kids(kidIds)[0], pool, found, depth + 1)
			return
		if c.lookupDecl(nConstDecl, "", nm, 0, 0) != none:
			return   # a constant: the module's data
		addAll(pool, found)
		return
	if k in [nUnary, nField, nIndex, nDeref, nTry, nSome]:
		if not nodes[e].kids(kidIds).isEmpty:
			c.originsOf(body, nodes[e].kids(kidIds)[0], pool, found, depth + 1)
		return
	if k == nCall:
		# a method's result comes from its receiver, a function's from its arguments
		callee = nodes[e].kids(kidIds)[0]
		if nodes[callee].kind == nField:
			c.originsOf(body, nodes[callee].kids(kidIds)[0], pool, found, depth + 1)
		fd NodeId? = none
		if nodes[callee].kind == nIdent:
			fd = c.lookupDecl(nFnDecl, "", nodes[callee].text.copy(), 0, 0)
		for i in 1..c.nodes[e].kids(c.kidIds).len:
			if fd is fd and c.writtenPlain(fd, nodes[e].kids(kidIds)[i], i - 1): continue
			c.originsOf(body, nodes[e].kids(kidIds)[i], pool, found, depth + 1)
		return
	if k == nMatch:
		for i in 1..c.nodes[e].kids(c.kidIds).len:
			arm = nodes[e].kids(kidIds)[i]
			if not nodes[arm].sub(kidIds).isEmpty:
				for v in c.returnedValues(nodes[arm].sub(kidIds)[0]):
					c.originsOf(body, v, pool, found, depth + 1)
			elif nodes[arm].kids(kidIds).len > 1:
				c.originsOf(body, nodes[arm].kids(kidIds)[1], pool, found, depth + 1)
		return
	if k == nBinary:
		if isCompareOp(nodes[e].ival): return   # a bool
		c.originsOf(body, nodes[e].kids(kidIds)[0], pool, found, depth + 1)
		c.originsOf(body, nodes[e].kids(kidIds)[1], pool, found, depth + 1)
		return
	if k == nStructLit:
		for kid in nodes[e].kids(kidIds):
			c.originsOf(body, kid, pool, found, depth + 1)
		return
	addAll(pool, found)

# whether the k-th argument arg of a call to fd passes a parameter written as a built-in type of
# plain data (an i64, a bool), which no reference comes from
fn writtenPlain(c Checker, fd NodeId, arg NodeId, k i64):
	if nodes[arg].kind == nNamedArg or k >= nodes[fd].kids(kidIds).len: return false
	p = nodes[fd].kids(kidIds)[k]
	if nodes[p].types(kidIds).isEmpty: return false
	te = nodes[p].types(kidIds)[0]
	nodes[te].kind == nTyName and nodes[te].types(kidIds).isEmpty and
		primTypes.any(.name == nodes[te].text and .name != "str" and .name != "()")

fn addAll(pool str[], mut found str[]):
	for nm in pool:
		if nm not in found:
			found.push(nm.copy())

# the let that binds `name` in the body (the first, at any depth), or none
fn letOf(c Checker, e NodeId, name str) NodeId?:
	if nodes[e].kind == nLet and nodes[e].text == name: return e
	if nodes[e].kind == nLambda: return none
	for kid in nodes[e].kids(kidIds):
		r = c.letOf(kid, name)
		if r != none: return r
	for sb in nodes[e].sub(kidIds):
		r = c.letOf(sb, name)
		if r != none: return r
	none

# the value a match in e takes apart whose pattern binds name (`if self.b is m`), or none
fn matchedBy(c Checker, e NodeId, name str) NodeId?:
	if nodes[e].kind == nLambda: return none
	if nodes[e].kind == nMatch:
		for arm in nodes[e].kidsFrom(kidIds, 1):
			if not nodes[arm].kids(kidIds).isEmpty and c.binds(nodes[arm].kids(kidIds)[0], name):
				return nodes[e].kids(kidIds)[0]
	for kid in nodes[e].kids(kidIds):
		if c.matchedBy(kid, name) is r: return r
	for sb in nodes[e].sub(kidIds):
		if c.matchedBy(sb, name) is r: return r
	none

# whether pattern pat binds name, in itself or a part
fn binds(c Checker, pat NodeId, name str) bool:
	if nodes[pat].kind == nPattern and nodes[pat].text == name: return true
	nodes[pat].kids(kidIds).any(c.binds(it, name))

fn isPrintable(c Checker, t TypeId?):
	k = c.tKind(t)
	t != none and k != tUnit and k != tFn and k != tError

fn argCount(c Checker, e NodeId):
	nodes[e].kids(kidIds).len - 1

fn argAt(c Checker, e NodeId, i i64):
	nodes[e].kids(kidIds)[i + 1]

fn setArg(mut c Checker, e NodeId, i i64, v NodeId):
	nodes[e].setKid(kidIds, i + 1, v)

fn expectArgs(mut c Checker, e NodeId, m str, n i64):
	got = c.argCount(e)
	if got != n:
		c.errorAt(
			nodes[e].line,
			nodes[e].col,
			compileError("ArgumentCount", ["{m}", "{n}", "{got}"])
		)
		return false
	true

# the node at the root of a place: below its fields, elements and dereferences
fn placeRootNode(c Checker, e NodeId):
	placeRootOf(nodes, kidIds, e)

# the identifier node at the root of a place and the path below it (".hp", "[]", ".items[]"); the
# root is none when e is not a place of a variable (a call's result, a type's member)
fn placePath(c Checker, e NodeId) (NodeId?, str):
	k = nodes[e].kind
	if k == nIdent: return (e, "")
	if k == nDeref: return c.placePath(nodes[e].kids(kidIds)[0])
	if (k == nField and not nodes[e].hasFlag(flagSafe)) or k == nIndex:
		root, base = c.placePath(nodes[e].kids(kidIds)[0])
		if root == none: return (none, "")
		if k == nField: return (root, "{base}.{nodes[e].text}")
		return (root, "{base}[]")
	(none, "")

# whether e, of type t, is a variable, field or element of the type a read reference expected
# (`ref T` or `ref T?`) points to
fn lendsPlace(mut c Checker, e NodeId, t TypeId?, expected TypeId?):
	if t == none or c.tKind(t) == tRef or c.tKind(t) == tError: return false
	expectedT = expected ?? return false
	want = innerOf(tys, expectedT) if c.tKind(expectedT) == tOption else expectedT
	if c.tKind(want) != tRef or tys[want].bits == 1 or not isSameType(tys, tys[want].inner, t):
		return false
	k = nodes[e].kind
	if k != nIdent and k != nField and k != nIndex and k != nDeref: return false
	c.lvalueRoot(e) >= 0 or c.storedConstRoot(e) or c.refCallBelow(e) != none

# the call whose reference the place e is reached through (`nodes[c].names(kidIds)` of
# `nodes[c].names(kidIds)[0]`), none for another place
pub fn refCallBelow(c Checker, e NodeId) NodeId?:
	at = e
	while nodes[at].kind in [nField, nIndex, nDeref] and not nodes[at].kids(kidIds).isEmpty:
		at = nodes[at].kids(kidIds)[0]
		if nodes[at].kind == nCall and c.tKind(typeOf(nodes, at)) == tRef: return at
	none

fn lvalueRoot(mut c Checker, e0 NodeId):
	e = c.placeRootNode(e0)
	if nodes[e].kind == nIdent: return c.lookupVarNo(nameOf(nodes, e))
	-1

# the top-level binding an expression's root identifier names (no variable hides it), or none
fn constRoot(mut c Checker, e0 NodeId):
	e = c.placeRootNode(e0)
	if nodes[e].kind != nIdent or c.lookupVarNo(nameOf(nodes, e)) >= 0: return none
	c.findDeclByGlobalName(nConstDecl, nodes[e].text, nameOf(nodes, e))

# whether the expression's root is a module binding kept in the data area (a module variable, a
# constant list): a place a read reference may point into for as long as the program runs
fn storedConstRoot(mut c Checker, e NodeId):
	d = c.constRoot(e) ?? return false
	nodes[d].hasFlag(flagMut) or c.tKind(c.constTypeOf(d)) == tList

# What stops a change through the place target: blockNone (also when it is no variable's place),
# blockReadRef, blockShared, blockImmutable or blockConstant, with the variable's or constant's name
# for the last two. The place is lent for the change, and a change to a captured mut variable is
# noted for the closure. Each caller words the error for what it is doing.
fn mutBlocker(mut c Checker, target NodeId, line i64, col i64) (i64, str):
	c.gridSizeChange(target, line, col)
	c.lendForChange(target)
	through = c.derefKind(target)
	if through == 1: return (blockNone, "")
	if through == 2: return (blockReadRef, "")
	if through == 3: return (blockShared, "")
	root = c.lvalueRoot(target)
	if root < 0:
		if c.constRoot(target) is croot and not nodes[croot].hasFlag(flagMut):
			return (blockConstant, nodes[croot].text2(kidIds).copy())
		return (blockNone, "")
	if c.tKind(c.vars[root].ty) == tError:
		return (blockNone, "")   # a value of a type not known here: nothing to judge
	if c.receiverChange(root, line, col): return (blockNone, "")
	if not c.vars[root].isMut and c.vars[root].placeOf is place:
		return c.mutBlocker(place, line, col)   # a `?.` call's value: the optional decides
	if not c.vars[root].isMut: return (blockImmutable, c.vars[root].name.copy())
	rk = c.tKind(c.vars[root].ty)
	if c.isCapturedVar(root) and rk != tList and rk != tMap:
		c.noteCapturedChange(root, line, col)
	(blockNone, "")

blockNone = 0
blockReadRef = 1
blockShared = 2
blockImmutable = 3
blockConstant = 4

# Mutating through an expression requires its root variable to be `mut`.
fn requireMutRoot(mut c Checker, target NodeId, line i64, col i64, what str):
	if c.changesColumn(target, what): return
	block, name = c.mutBlocker(target, line, col)
	if block == blockReadRef:
		errorAt(
			c,
			line,
			col,
			compileError("MutateThroughReadRef", ["{what}"])
		)
	elif block == blockShared:
		c.errorAt(line, col, compileError("MutateShared", ["{what}"]))
	elif block == blockConstant:
		c.errorAt(line, col, compileError("MutateConstant", ["{what}", "{name}"]))
	elif block == blockImmutable:
		c.errorAt(line, col, compileError("NeedsMut", [what.copy(), name.copy()]))

# Arguments bound to `mut` parameters must be mutable places (the callee mutates them in place).
fn checkMutArgs(mut c Checker, e NodeId, fnd NodeId, first i64):
	params = nodes[fnd].kids(kidIds).copy()   # (reporting changes c.nodes)
	n = c.argCount(e)
	if params.len < n:
		n = params.len
	# the function's name is read from its node in each message: reporting changes c
	for i in first..n:
		if nodes[params[i]].ival != modeMut: continue
		a = c.argAt(e, i)
		ak = nodes[a].kind
		if ak != nIdent and ak != nField and ak != nIndex and ak != nDeref:
			c.errorAt(
				nodes[a].line,
				nodes[a].col,
				compileError("MutArgTemporary", ["{c.argumentOf(e, i, nodes[fnd].text)}"])
			)
			continue
		if c.changesColumn(a, c.argumentOf(e, i, nodes[fnd].text)): continue
		block, name = c.mutBlocker(a, nodes[a].line, nodes[a].col)
		if block == blockReadRef:
			c.errorAt(
				nodes[a].line,
				nodes[a].col,
				compileError("MutArgReadRef", ["{c.argumentOf(e, i, nodes[fnd].text)}"])
			)
		elif block == blockShared:
			c.errorAt(
				nodes[a].line,
				nodes[a].col,
				compileError("MutArgShared", ["{c.argumentOf(e, i, nodes[fnd].text)}"])
			)
		elif block == blockConstant:
			c.errorAt(
				nodes[a].line,
				nodes[a].col,
				compileError("MutArgConstant", ["{c.argumentOf(e, i, nodes[fnd].text)}", "{name}"])
			)
		elif block == blockImmutable:
			c.errorAt(
				nodes[a].line,
				nodes[a].col,
				compileError("MutArgImmutable", ["{c.argumentOf(e, i, nodes[fnd].text)}", "{name}"])
			)
