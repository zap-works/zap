# zeros(n) and fill(n, v): n of a type's zero, or n copies of v. More sizes make lists of lists,
# the outer size first and the value last (`zeros(n, m)`, `fill(n, m, -1)`), each row its own.
# The checker writes them as the internal `repeat` of a one-element list literal (only the checker
# writes it: in a program it is no method) and checks that, so they are lowered as it is.

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

fn checkZerosFill(mut c Checker, e NodeId, cname str, expected TypeId?) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	given = c.argCount(e)
	isZeros = cname == "zeros"
	if given < (1 if isZeros else 2):
		form = "sizes, outermost first: zeros(n), zeros(n, m)"
		if not isZeros:
			form = "sizes, outermost first, and the value last: fill(n, v), fill(n, m, v)"
		c.errorAt(line, col, compileError("ZerosFillArguments", [cname.copy(), form]))
		c.checkArgsAlone(e)
		return tyError
	sizes = nodes[e].kids(kidIds)[1..(given + 1 if isZeros else given)].copy()
	value = nodes[e].kids(kidIds)[given]
	if isZeros:
		want = c.zeroElement(expected, sizes.len)
		made = c.zeroNode(want, line, col)
		if made is zero:
			value = zero
		else:
			c.errorAt(line, col, compileError("ZerosElement", ["{c.showTy(want)}"]))
			c.checkArgsAlone(e)
			return tyError
	# fill(first, last, value), e being the outermost call
	inner = value
	for i in 0..sizes.len:
		size = sizes[len - 1 - i]
		list = newNode(nodes, kidIds, nArray, line, col, kids = [inner])
		repeat = newNode(nodes, kidIds, nField, line, col, text = "repeat", kids = [list])
		nodes[repeat].flags |= flagInternal
		if i == sizes.len - 1:
			nodes[e].setKids(kidIds, [repeat, size])
		else:
			inner = newNode(nodes, kidIds, nCall, line, col, kids = [repeat, size])
	c.checkExpr(e, expected)

# whether the type has a zero zeros(n) can make
fn hasZero(c Checker, t TypeId):
	c.tKind(t) in [tInt, tFloat, tBool, tOption]

# the element zeros makes `depth` lists deep: the expected type's, else an i64
fn zeroElement(c Checker, expected TypeId?, depth i64):
	t = expected
	loop depth:
		if c.tKind(t) != tList and c.tKind(t) != tArray: return tyInt(64, true)
		t = innerOf(tys, t)
	t ?? tyInt(64, true)

# the literal zero of a number, a bool or an optional type; none for another
fn zeroNode(mut c Checker, t TypeId, line i64, col i64) NodeId?:
	k = c.tKind(t)
	if k == tInt: return newNode(nodes, kidIds, nInt, line, col, text = "0")
	if k == tFloat: return newNode(nodes, kidIds, nFloat, line, col, text = "0.0")
	if k == tBool: return newNode(nodes, kidIds, nBool, line, col)
	if k == tOption: return newNode(nodes, kidIds, nNone, line, col)
	none
