# grad's calls of functions it differentiates (gradWrite.zap): read in the caller's body, their
# parameters the arguments' values and their locals values of the caller's, so the forward pass
# computes each value once and the backward one reads it (a pull, $pullN, computes the callee's
# forward pass again: it stays for a callee whose value is a tail if or match, and for one that
# calls itself).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# how deep calls are read in their callers before one is pulled instead
inlineDepth = 8

# the statements of f's body when the caller may read them in place: its value the last one's
# (not a tail if or match), no return before it
fn inlinable(c Checker, w GradWriter, f NodeId) NodeId[]?:
	if f in w.inlining or w.inlining.len >= inlineDepth: return none
	bodyRead(f)
	body = nodes[f].sub(kidIds)[0]
	stmts = nodes[body].kids(kidIds)
	if stmts.isEmpty: return none
	last = stmts[len - 1]
	value = last
	if (nodes[last].kind == nReturn or nodes[last].kind == nExprStmt) and
		not nodes[last].kids(kidIds).isEmpty:
		value = nodes[last].kids(kidIds)[0]
	if nodes[value].kind == nMatch or nodes[value].kind == nIf: return none
	for s in stmts[..len - 1]:
		if nodes[s].kind == nReturn: return none
	stmts.copy()

# f's body read in place for a call of its args: the value of its last statement
fn gInline(mut c Checker, mut w GradWriter, f NodeId, stmts NodeId[], args i64[]):
	savedNames = w.names.copy()
	savedFields = w.selfFields.copy()
	savedMod = c.curMod
	savedFile = c.curFile.copy()
	c.enterModuleOf(f)
	names, types = c.gParams(f)
	w.names = {}
	for k, a in args:
		w.names[names[k].copy()] = a
	w.selfFields = c.fieldNamesOf(types[0]) if not names.isEmpty and names[0] == "self" else []
	w.inlining.push(f)
	for k, s in stmts:
		if k < stmts.len - 1:
			c.gStmt(w, s)
	last = stmts[len - 1]
	value = nodes[last].kids(kidIds)[0] if nodes[last].kind == nReturn or
		nodes[last].kind == nExprStmt
		else last
	v = c.gExpr(w, value)
	w.inlining.pop()
	w.names = savedNames
	w.selfFields = savedFields
	c.curMod = savedMod
	c.curFile = savedFile
	v
