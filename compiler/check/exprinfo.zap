# What the backend asks of an expression or a type: its kind and size, whether it may call,
# owns its result or is a place, and which derived function it runs.

alias nodes = g.c.nodes
alias tys = g.c.types

fn isF64(g Gen, t TypeId):
	g.tyK(t) == tFloat and tys[t].bits == 64

# Whether evaluating e may run a call (which clobbers every xmm register): only literals,
# places and arithmetic over them are known not to, plus the float methods genFloat inlines.
fn exprMayCall(mut g Gen, e NodeId) bool:
	k = nodes[e].kind
	if k in [nInt, nFloat, nBool]: return false
	if k == nIdent:
		cd = g.isConstName(nodes[e].text) ?? return false
		return g.constantOwns(cd)   # a list constant is made at each use
	if k in [nField, nDeref, nUnary]: return g.exprMayCall(nodes[e].kids[0])
	if k == nStructLit:
		for kid in nodes[e].kids:
			if g.exprMayCall(kid): return true
		return false
	if k == nIndex or k == nBinary:
		op = nodes[e].ival
		# a float % calls remBits; an integer one is emitted in place (division by zero jumps out)
		if k == nBinary and
			(
				op == binPow or (op == binMod and g.tyK(g.ty(e)) == tFloat) or op == binMatmul or
					g.derivedOpCalls(e)
			):
			return true
		if k == nBinary and isCompareOp(op) and g.tyK(g.ty(nodes[e].kids[0])) == tStr:
			return true   # strEq / strCmp
		return g.exprMayCall(nodes[e].kids[0]) or g.exprMayCall(nodes[e].kids[1])
	if k == nCall and (nodes[e].hasFlag(flagVecLit) or g.isLiteralSplat(e) or g.isSimdCall(e)):
		# vector literals and the f64x4 / u8x16 methods are emitted in place: they call only
		# when an operand does
		for kid in nodes[e].kids:
			part = kid
			if nodes[kid].kind == nField:
				part = nodes[kid].kids[0]   # the receiver of the method
			elif nodes[kid].kind == nIdent and nodes[e].kids[0] == kid:
				continue   # the name of a vector literal's type
			if g.exprMayCall(part): return true
		return false   # emitted in place
	if k == nCall and nodes[nodes[e].kids[0]].kind == nField and g.callArgs(e).isEmpty and
		g.inPlaceMethod(g.ty(nodes[nodes[e].kids[0]].kids[0]), nodes[nodes[e].kids[0]].text):
		return g.exprMayCall(nodes[nodes[e].kids[0]].kids[0])   # emitted in place
	if k == nCall and nodes[nodes[e].kids[0]].kind == nField and
		g.tyK(g.ty(nodes[nodes[e].kids[0]].kids[0])) == tStruct:
		# a struct's method whose body is emitted in place: it calls when its receiver, its
		# arguments or its statements do
		callee = nodes[e].kids[0]
		recv = nodes[callee].kids[0]
		rt = g.ty(recv)
		md = g.c.findMethod(tys[rt].name, nodes[callee].text)
		if md is md and not g.c.implIsGeneric(tys[rt].name, md) and
			g.canInlineBody(md) and (g.genIsPlace(recv) or g.smallPlain(rt)):
			if g.exprMayCall(recv): return true
			if (1..g.c.nodes[e].kids.len).any(g.exprMayCall(nodes[e].kids[it])): return true
			g.inlineDepth += 1
			r = g.bodyMayCall(nodes[md].sub[0])
			g.inlineDepth -= 1
			return r
	if k == nCall and nodes[nodes[e].kids[0]].kind == nIdent:
		nm = nodes[nodes[e].kids[0]].text
		# a runtime intrinsic other than __drop is emitted in place (read before g changes)
		inPlaceIntrinsic = nm.startsWith("__") and nm != "__drop"
		if not nm.startsWith("__") and g.findVar(nm) < 0:
			fnd = g.c.findFunc(nm)
			if fnd is fnd and nodes[fnd].names.isEmpty and g.canInline(fnd):
				if (1..g.c.nodes[e].kids.len).any(g.exprMayCall(nodes[e].kids[it])): return true
				body = nodes[nodes[fnd].sub[0]].kids[0]
				g.inlineDepth += 1   # bounds the analysis of recursive bodies too
				r = g.exprMayCall(nodes[body].kids[0])
				g.inlineDepth -= 1
				return r
			if fnd is fnd and nodes[fnd].names.isEmpty and g.inlineDepth == 0 and
				g.canInlineBody(fnd):
				# emitted in place too (genInlineBody): it calls when its arguments or statements do
				if (1..g.c.nodes[e].kids.len).any(g.exprMayCall(nodes[e].kids[it])): return true
				g.inlineDepth += 1
				r = g.bodyMayCall(nodes[fnd].sub[0])
				g.inlineDepth -= 1
				return r
		if inPlaceIntrinsic:
			# a runtime intrinsic is emitted in place (rax, rcx, rdx, xmm0 and xmm1 at most)
			return (1..g.c.nodes[e].kids.len).any(g.exprMayCall(nodes[e].kids[it]))
	true

# whether a block of lets, expression statements, returns, assignments of scalars and ifs over
# such blocks may call (anything else: yes)
fn bodyMayCall(mut g Gen, blk NodeId) bool:
	for st in nodes[blk].kids:
		k = nodes[st].kind
		if (k in [nLet, nReturn, nExprStmt]) and nodes[st].kids.len == 1:
			if g.exprMayCall(nodes[st].kids[0]): return true
		elif k == nAssign:
			if not g.c.isScalar(g.ty(nodes[st].kids[0])) or g.exprMayCall(nodes[st].kids[0]) or
				g.exprMayCall(nodes[st].kids[1]):
				return true
		elif k == nIf:
			if g.exprMayCall(nodes[st].kids[0]): return true
			for sb in nodes[st].sub:
				if g.bodyMayCall(sb): return true
		elif not (k == nReturn and nodes[st].kids.isEmpty):
			return true
	false

# x.splat4() of a float literal (a broadcast from the constant area)
fn isLiteralSplat(g Gen, e NodeId):
	callee = nodes[e].kids[0]
	if nodes[callee].kind != nField or nodes[callee].text != "splat4" or
		not g.callArgs(e).isEmpty:
		return false
	nodes[nodes[callee].kids[0]].kind == nFloat

# a struct owning nothing and copied through rdx alone (copyBytes: at most 128 bytes)
fn smallPlain(mut g Gen, maybeT TypeId?):
	t = maybeT ?? return false
	g.tyK(t) == tStruct and g.c.isPlainType(t) and g.sizeOf(t) <= 128

# the methods of numbers, lists and strs emitted in place, calling nothing
fn inPlaceMethod(g Gen, rt TypeId, m str):
	rk = g.tyK(rt)
	g.isF64(rt) and (m == "sqrt" or m == "abs") or
		rk == tInt and
		(
			m in ["toF64", "max", "min"] or m in intBitMethods or m in bitFieldMethods or
				m in intConversions
		) or
		(rk == tList or rk == tStr) and m == "len" or rk == tStr and m == "slice"

# f64x4 or u8x16: a 32-byte frame slot, a ymm register in a scratch-safe loop
fn isVec(g Gen, t TypeId):
	k = g.tyK(t)
	k == tSimd or k == tBytes

# a reference held as a value: one word (a window reference is wider)
# `ref str`: a window of 16 bytes on text (its address and length), the key a map of text
# windows packs into one word (map.zap's TextTable)
fn isTextWindow(mut g Gen, t TypeId):
	g.tyK(t) == tRef and g.tyK(tys[t].inner) == tStr and g.c.typeSize(t) == 16

# whether e holds a node of kind a or b (b = -1: only a); a lambda is a function of its own
# unless crossLambda
fn holdsKind(g Gen, e NodeId, a i64, b i64, crossLambda bool) bool:
	k = nodes[e].kind
	if k == a or k == b: return true
	if k == nLambda and not crossLambda: return false
	nodes[e].kids.any(g.holdsKind(it, a, b, crossLambda)) or
		nodes[e].sub.any(g.holdsKind(it, a, b, crossLambda))

fn exprHasCall(g Gen, e NodeId):
	g.holdsKind(e, nCall, -1, true)

fn ty(g Gen, e NodeId):
	typeOf(nodes, e)

fn tyK(g Gen, maybeT TypeId?):
	t = maybeT ?? return -1
	tys[t].kind

fn sizeOf(mut g Gen, t TypeId) i64:
	g.c.typeSize(t)

fn listElem(g Gen, t TypeId):
	k = g.tyK(t)
	if k == tList: return innerOf(tys, t)
	if k == tStr:
		return tyInt(8, false)   # a str indexes like a u8[] (same header)
	die("x64: not a list type")
	tyError

# a value-producing expression whose result the evaluator owns (not a place, not an alias)
fn producesOwned(mut g Gen, e NodeId):
	if not g.isOwningType(g.ty(e)): return false
	if nodes[e].hasFlag(flagAutoCopy): return true
	# a name, a literal or a reference never makes a value of its own; anything else does (a part
	# of a temporary moves out of it), but a choice whose arms borrow
	k = nodes[e].kind
	not (k in [nIdent, nStr, nNone, nDeref])

# a place expression: a variable, a field of a place, an element of a place
# whether a bare name is a field of the method's receiver
fn isReceiverField(g Gen, nm str):
	if not g.f.inMethod: return false
	fields = g.f.curFields ?? return false
	g.c.fieldIndexOf(fields, nm) >= 0

fn genIsPlace(g Gen, e NodeId) bool:
	k = nodes[e].kind
	if k == nDeref:
		kid = nodes[e].kids[0]
		if g.tyK(g.ty(kid)) == tOption: return false
		if g.tyK(g.ty(kid)) != tRef: return g.genIsPlace(kid)
		return true
	if k == nIdent:
		if nodes[e].hasFlag(flagFnRef): return false
		nm = nodes[e].text
		return g.findVar(nm) >= 0 or nm == "self" or
			g.isReceiverField(nm) or
			g.globalOf(nm) >= 0
	if k == nField:
		obj = nodes[e].kids[0]
		return not nodes[e].hasFlag(flagSafe) and nodes[obj].ty != none and
			g.tyK(g.ty(obj)) == tStruct and g.genIsPlace(obj)
	if k == nIndex: return g.genIsPlace(nodes[e].kids[0])
	false

# whether e is a list literal lent to a read parameter whose elements own nothing: it is built
# in the caller's frame, with no heap block (the callee only reads it, and nothing is dropped)
fn stackListOk(mut g Gen, e NodeId):
	if nodes[e].kind != nArray or g.tyK(g.ty(e)) != tList: return false
	n = nodes[e].kids.len
	elem = g.listElem(g.ty(e))
	n > 0 and not g.isOwningType(elem) and g.tyK(elem) != tVec and g.tyK(elem) != tSimd and
		n * g.c.elemStride(elem) <= 4096

# An argument passed by address (the receiver, read and mut aggregates) could point into a list
# that a later argument reallocates (`xs[i].kids.push(parse(xs))`): when a later argument contains
# a call, the values are computed first and the addresses are taken just before the call.
fn needsValuesFirst(mut g Gen, fnd NodeId, recv NodeId?, args NodeId[]):
	addrSeen = recv != none
	for i, arg in args:
		p = nodes[fnd].kids[i]   # read at each step: resolveType changes g.c
		pt = g.c.resolveType(nodes[p].types[0])
		byAddr = not g.c.isScalar(pt) and nodes[p].ival != modeMove
		if byAddr:
			addrSeen = true
		elif addrSeen and g.exprHasCall(arg):
			return true
	false

# whether each use of the constant declared by d makes a value to drop (a list does, a text
# literal is a window into the data)
fn constantOwns(mut g Gen, d NodeId) bool:
	g.producesOwned(nodes[d].kids[0])

fn isSimdCall(g Gen, e NodeId):
	if nodes[e].kind != nCall or nodes[nodes[e].kids[0]].kind != nField: return false
	callee = nodes[e].kids[0]
	m = nodes[callee].text
	rk = g.tyK(g.ty(nodes[callee].kids[0]))
	if rk == tSimd:
		return m in [
			"sqrt",
			"rsqrtEstimate",
			"max",
			"min",
			"lane",
			"sum",
			"ltMask",
			"leMask",
			"gtMask",
			"geMask",
			"spread",
			"sums4",
			"mulAdd",
			"mulSub",
			"subMul"
		]
	if rk == tBytes: return m in ["shuffle", "blend", "eqBytes", "eqMask", "gtMask", "lane"]
	if rk == tFloat: return m == "splat4"
	if rk == tInt: return m == "splat16"
	if rk == tList: return m in ["load4", "store4", "load16", "store16"]
	false

# whether a binary e runs a written $..N function: == and orderings of composite values, and
# arithmetic on a struct of numbers unless its body is generated in place (genDerivedCall)
fn derivedOpCalls(mut g Gen, e NodeId):
	op = nodes[e].ival
	lt = g.ty(nodes[e].kids[0])
	if isCompareOp(op): return g.derivedCompare(lt)
	if g.tyK(g.ty(e)) != tStruct or not (op in [binAdd, binSub, binMul, binDiv]): return false
	fnd = g.derivedFn(g.arithFamily(e), g.ty(e)) ?? return true
	not g.canInlineBody(fnd)   # the same test genDerivedCall makes

# the function of `family` derive.zap wrote for type t, if any
fn derivedFn(g Gen, family str, t TypeId):
	g.c.derivedFunction(family, t)

# the written function a binary e on a struct of numbers runs: $addN.., $addRN.. with a number
# on the right, $addLN.. with one on the left
fn arithFamily(mut g Gen, e NodeId):
	op = nodes[e].ival
	family = "add" if op == binAdd else "sub" if op == binSub else "mul" if op == binMul else "div"
	if g.tyK(g.ty(nodes[e].kids[1])) != tStruct: return "{family}R"
	if g.tyK(g.ty(nodes[e].kids[0])) != tStruct: return "{family}L"
	family

# whether == or < on values of type t calls the written $eqN / $cmpN
fn derivedCompare(g Gen, t TypeId):
	k = g.tyK(t)
	k in [tStruct, tList, tArray, tOption] or (k == tEnum and not g.c.isEqNative(t))

# a list of its own: callers keep it while generating code (which changes g)
fn callArgs(g Gen, e NodeId):
	nodes[e].kids[1..nodes[e].kids.len].copy()

fn enumNamed(g Gen, obj NodeId, resultType TypeId) NodeId?:
	if nodes[obj].kind != nIdent: return none
	name = nodes[obj].text
	if g.tyK(resultType) == tEnum:
		dcl = declOf(tys, resultType)
		origin = nodes[dcl].origin
		if origin is origin and nodes[origin].text == name: return dcl
	if g.findVar(name) >= 0: return none
	g.c.decls.find(nodes[it].kind == nEnumDecl and nodes[it].text == name)
