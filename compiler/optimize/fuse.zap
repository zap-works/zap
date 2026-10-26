# `use fusedMultiplyAdd`: in a function or block under it (flagFusedMath), each a * b + c, c + a * b, a * b - c
# and c - a * b of f64, f32 or Simd<4, f64> is computed with one rounding (the processor's fused
# multiply-add). The rule reads the source, so the scalar, inlined and vectorized code agree: a
# product given a name stays rounded (`p = a * b` then `p + c`), a sum of two products
# (`a * b - c * d`, the cancellation geometric tests rely on) is never fused, and neither is one
# whose operands call a function (the backend evaluates the three in its own order). The
# checked tree is rewritten to the fused calls the backend emits: x.mulAdd(y, z) (a * b - c is
# a.mulAdd(b, -c), c - a * b is (-a).mulAdd(b, c)), and for Simd<4, f64> x.mulSub(y, z), z.subMul(x, y).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

pub fn fuseMath(mut c Checker, fnd NodeId):
	c.fuseIn(nodes[fnd].sub()[0], nodes[fnd].hasFlag(flagFusedMath))

# the operands first, so a fused sum is an operand like any other value; `on` from the function
# or a block with the option, to its end
fn fuseIn(mut c Checker, e NodeId, on bool):
	here = on or (nodes[e].kind == nBlock and nodes[e].hasFlag(flagFusedMath))
	if here and nodes[e].kind == nFor:
		nodes[e].flags |= flagFusedMath   # its sums may keep lane sums (loopVec.zap)
	for k in nodes[e].kids(kidIds).copy():
		c.fuseIn(k, here)
	for k in nodes[e].sub().copy():
		c.fuseIn(k, here)
	if here and nodes[e].kind == nBinary and
		(nodes[e].ival == binAdd or nodes[e].ival == binSub) and
		c.fusesIn(typeOf(nodes, e)):
		c.fuseSum(e)

fn fusesIn(c Checker, maybeT TypeId?):
	t = maybeT ?? return false
	c.tKind(t) == tFloat or c.tKind(t) == tSimd

# a product of the sum's own type, written in place (not a name for one)
fn isProduct(c Checker, e NodeId, t TypeId):
	nodes[e].kind == nBinary and nodes[e].ival == binMul and isSameType(tys, nodes[e].ty, t)

# whether e calls nothing that could have an effect: its calls are methods of numbers
fn callsNothing(c Checker, e NodeId) bool:
	if nodes[e].kind == nLambda: return false
	if nodes[e].kind == nCall:
		callee = nodes[e].kids(kidIds)[0]
		if nodes[callee].kind != nField: return false
		rk = c.tKind(typeOf(nodes, nodes[callee].kids(kidIds)[0]))
		if rk != tInt and rk != tFloat and rk != tSimd: return false
	nodes[e].kids(kidIds).all(c.callsNothing(it)) and nodes[e].sub().all(c.callsNothing(it))

fn fuseSum(mut c Checker, e NodeId):
	t = typeOf(nodes, e)
	l = nodes[e].kids(kidIds)[0]
	r = nodes[e].kids(kidIds)[1]
	lp = c.isProduct(l, t)
	rp = c.isProduct(r, t)
	if lp == rp or not c.callsNothing(e): return
	p, other = (l, r) if lp else (r, l)
	a = nodes[p].kids(kidIds)[0]
	b = nodes[p].kids(kidIds)[1]
	adds = nodes[e].ival == binAdd
	if c.tKind(t) == tSimd:
		if adds:
			c.fusedCall(e, "mulAdd", a, b, other)
		elif lp:
			c.fusedCall(e, "mulSub", a, b, other)
		else:
			c.fusedCall(e, "subMul", other, a, b)
	elif adds:
		c.fusedCall(e, "mulAdd", a, b, other)
	elif lp:
		c.fusedCall(e, "mulAdd", a, b, c.negated(other))
	else:
		c.fusedCall(e, "mulAdd", c.negated(a), b, other)

# e made the call recv.m(x, y), keeping its place in the tree and its type
fn fusedCall(mut c Checker, e NodeId, move m str, recv NodeId, x NodeId, y NodeId):
	callee = newNode(nodes, kidIds, nField, nodes[e].line, nodes[e].col, text = m, kids = [recv])
	nodes[e].kind = nCall
	nodes[e].ival = 0
	nodes[e].flags = flagInternal
	nodes[e].setKids(kidIds, [callee, x, y])

fn negated(mut c Checker, x NodeId):
	n = newNode(nodes, kidIds, nUnary, nodes[x].line, nodes[x].col, kids = [x])
	nodes[n].ival = unNeg
	nodes[n].ty = typeOf(nodes, x)
	n
