# arg(i, default): the i-th command-line argument parsed as the default's type (a number's or
# text), the default when it is missing. One given that does not parse stops the program (the
# runtime's argParsed), so a typo never runs with the default. The default is evaluated first.

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# arg(i, d) written as the runtime's functions over the text of argument i: argParsed(i,
# T.parse(argOrEmpty(i)), d) for a number T, argTextOr(i, d) for text. The type is the default's;
# a number literal there takes the type its place expects.
fn checkArg(mut c Checker, e NodeId, expected TypeId?) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	if not c.expectArgs(e, "arg", 2): return tyError
	index = c.argAt(e, 0)
	if c.tKind(c.checkExpr(index, tyInt(64, true))) != tInt:
		c.errorAt(line, col, compileError("ArgIndexNotInteger", []))
		return tyError
	d = c.argAt(e, 1)
	want TypeId? = expected if c.tKind(expected) == tInt or c.tKind(expected) == tFloat else none
	t = c.heldType(c.derefIfRef(d, c.checkExpr(d, want)))
	k = c.tKind(t)
	if k == tError: return tyError
	isText = k == tStr
	if not isText and k != tInt and k != tFloat or isDefined(tys, t) or tys[t].ranged:
		c.errorAt(line, col, compileError("ArgDefaultType", ["{c.showTy(t)}"]))
		return tyError
	if isText:
		madeKids = [c.internalName("argTextOr", line, col), index, d]
		nodes[e].setKids(kidIds, madeKids)
		return c.checkExpr(e, expected)
	text = newNode(
		nodes,
		kidIds,
		nCall,
		line,
		col,
		kids = [c.internalName("argOrEmpty", line, col), cloneTree(nodes, kidIds, index)]
	)
	parse = newNode(
		nodes,
		kidIds,
		nField,
		line,
		col,
		text = "parse",
		kids = [newNode(nodes, kidIds, nIdent, line, col, text = c.showTy(t))]
	)
	parsed = newNode(nodes, kidIds, nCall, line, col, kids = [parse, text])
	madeKids = [c.internalName("argParsed", line, col), index, parsed, d]
	nodes[e].setKids(kidIds, madeKids)
	c.checkExpr(e, expected)
