# Which functions are expanded at their call sites instead of called.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# A function whose body is one `return expr` over plain scalar parameters, with no call inside,
# is expanded at the call site: the arguments go to frame slots named as the parameters and
# the expression is generated in place.
fn canInline(mut g Gen, fnd NodeId):
	if nodes[fnd].sub(kidIds).isEmpty or nodes[fnd].kids(kidIds).len > 6: return false
	g.c.readBody(fnd)
	body = nodes[fnd].sub(kidIds)[0]
	if nodes[body].kids(kidIds).len != 1: return false
	st = nodes[body].kids(kidIds)[0]
	expr = st
	if nodes[st].kind == nReturn and nodes[st].kids(kidIds).len == 1:
		expr = nodes[st].kids(kidIds)[0]
		rt = g.c.resolveType(nodes[fnd].types(kidIds)[0])
		if not g.c.refIsWindow(rt) and
			(not g.c.isScalar(rt) or g.isOwningType(rt) or g.tyK(rt) == tRef):
			return false   # (a window into a parameter is made in place)
		if not isSameType(tys, g.ty(expr), rt):
			return false   # a boxing return (T into T?) is not an expression
	elif nodes[st].kind == nExprStmt and nodes[fnd].types(kidIds).isEmpty:
		expr = nodes[st].kids(kidIds)[0]
		if nodes[expr].kind == nMatch: return false
	else:
		return false
	if g.holdsReturn(expr):
		return false   # a return inside (a match arm's): only a body inlined whole has where to go
	for p in nodes[fnd].kids(kidIds).copy():
		pt = g.c.resolveType(nodes[p].types(kidIds)[0])
		if nodes[p].ival != modeRead or g.tyK(pt) == tRef or g.c.isViewType(pt): return false
		if g.c.isScalar(pt) and g.isOwningType(pt):
			return false   # a map by value would need its drop flag
	_ = expr
	g.inlineDepth < 3

# whether a return statement lies anywhere inside e (its blocks, its arms)
fn holdsReturn(g Gen, e NodeId) bool:
	if nodes[e].kind == nReturn: return true
	nodes[e].kids(kidIds).any(g.holdsReturn(it)) or nodes[e].sub(kidIds).any(g.holdsReturn(it))

# Whether a free function's whole body may be generated in place of a call: read parameters
# of plain or aggregate type, no loop, lambda in the body, a small body, no
# generics, bounded nesting. (canInline covers the one-expression case without a scope.)
fn canInlineBody(mut g Gen, fnd NodeId):
	nodes[fnd].names(kidIds).isEmpty and g.canInlineBodyOf(fnd)

# the same for a generic function's instance too
fn canInlineBodyOf(mut g Gen, fnd NodeId):
	if nodes[fnd].sub(kidIds).isEmpty or g.inlineDepth >= 2 or nodes[fnd].hasFlag(flagExtern):
		return false
	if nodes[fnd].kids(kidIds).len > 6: return false
	for p in nodes[fnd].kids(kidIds).copy():
		pt = g.c.resolveType(nodes[p].types(kidIds)[0])
		mode = nodes[p].ival
		if (mode == modeMut and g.c.isScalar(pt)) or (mode == modeMove and g.isOwningType(pt)) or
			g.tyK(pt) == tRef or g.c.isViewType(pt) or
			(g.c.isScalar(pt) and g.isOwningType(pt)):
			# (a plain aggregate moved in is used through its address; an owning one is the
			# callee's to keep or drop, which only a real call gives it)
			return false
	rt = g.c.fnRetType(fnd)
	if g.tyK(rt) == tRef or g.c.isViewType(rt): return false
	g.c.readBody(fnd)
	body = nodes[fnd].sub(kidIds)[0]
	g.inlineFn = fnd
	g.bodyInlineable(body, 0) <= 40

# whether fnd is the function being generated, called from its own body (no inlined body in
# between): one level of its recursion is inlined, the calls in that copy stay calls
fn selfInline(g Gen, fnd NodeId):
	g.inlineDepth == 0 and not nodes[fnd].sub(kidIds).isEmpty and nodes[fnd].sub(kidIds)[0] == g.f.body

# the node count of a body fit for inlining, or a large number when it holds a loop, a
# lambda or a call to the function being inlined into
fn bodyInlineable(g Gen, e NodeId, depth i64) i64:
	k = nodes[e].kind
	if k in [nWhile, nFor, nLambda] or depth > 12 or nodes[e].hasFlag(flagClosure): return 1000
	if k == nCall:
		callee = nodes[e].kids(kidIds)[0]
		if nodes[callee].kind == nField:
			m = nodes[callee].text
			if isPipelineMethod(m) or
				m == "sum" and nodes[nodes[callee].kids(kidIds)[0]].kind == nRange:
				return 1000   # a pipeline carries a lambda or a loop
		elif nodes[callee].kind == nIdent and g.inlineFn is f and
			nodes[callee].text == nodes[f].text and not g.selfInline(f):
			return 1000   # recursion
	n = 1
	for kid in nodes[e].kids(kidIds):
		n += g.bodyInlineable(kid, depth + 1)
	for sb in nodes[e].sub(kidIds):
		n += g.bodyInlineable(sb, depth + 1)
	n

# the list methods genPipeline compiles in line (a list's sum is the runtime's)
fn isPipelineMethod(m str):
	m in pipelineSteps and m != "sum"
