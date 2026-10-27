# The math operators on std/tensor's Tensor (spec 7.8): the checker writes each as the call of
# the tensor's method, so the backend and grad (grad.zap) see calls only:
#   a + b, a - b, a * b, a / b   a.add(b), a.sub(b), a.mul(b), a.div(b)
#   a @ b                        a.matmul(b)
#   a * k, k * a                 a.scaled(k)       a / k   a.divided(k)    k / a   a.dividing(k)
#   a + k, k + a                 a.shifted(k)      a - k   a.subtracted(k) k - a   a.subtractedFrom(k)
#   -a                           a.neg()
# k is any number, an f32 to the method.

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# whether t is std/tensor's Tensor
fn isTensorType(c Checker, maybeT TypeId?):
	t = maybeT ?? return false
	if c.tKind(t) != tStruct: return false
	d = declOf(tys, t)
	nodes[d].mod(kidIds) == "tensor" and nodes[d].text2(kidIds) == "Tensor"

fn checkTensorMath(mut c Checker, e NodeId, op i64, lt TypeId, rt TypeId, expected TypeId?) TypeId:
	l = nodes[e].kids(kidIds)[0]
	r = nodes[e].kids(kidIds)[1]
	both = c.isTensorType(lt) and c.isTensorType(rt)
	left = c.isTensorType(lt)
	name = ""
	if both:
		if op == binAdd: name = "add"
		elif op == binSub: name = "sub"
		elif op == binMul: name = "mul"
		elif op == binDiv: name = "div"
		elif op == binMatmul: name = "matmul"
	elif left and typeIsNumeric(tys, rt):
		if op == binAdd: name = "shifted"
		elif op == binSub: name = "subtracted"
		elif op == binMul: name = "scaled"
		elif op == binDiv: name = "divided"
	elif not left and typeIsNumeric(tys, lt):
		if op == binAdd: name = "shifted"
		elif op == binSub: name = "subtractedFrom"
		elif op == binMul: name = "scaled"
		elif op == binDiv: name = "dividing"
	if name.isEmpty:
		errorAt(
			c,
			nodes[e].line,
			nodes[e].col,
			compileError("OperatorUndefined", ["{binName(op)}", "{c.showTy(lt)}", "{c.showTy(rt)}"])
		)
		return tyError
	receiver = l if left else r
	other = r if left else l
	if not both:
		c.checkExpr(other, tyFloat(32))
	c.tensorMethodCall(e, name, receiver, [other], expected)

# e made the call receiver.name(args) and checked
fn tensorMethodCall(
	mut c Checker,
	e NodeId,
	name str,
	receiver NodeId,
	args NodeId[],
	expected TypeId?
) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	kids = [newNode(nodes, kidIds, nField, line, col, text = name.copy(), kids = [receiver])]
	kids.extend(args)
	nodes[e].kind = nCall
	nodes[e].ival = 0
	nodes[e].setKids(kidIds, kids)
	c.checkExpr(e, expected)

# -a of a tensor: a.neg()
fn checkTensorNeg(mut c Checker, e NodeId, operand NodeId, expected TypeId?) TypeId:
	c.tensorMethodCall(e, "neg", operand, [], expected)
