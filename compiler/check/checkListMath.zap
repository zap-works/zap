# The checking of list math, extern binds, argument filling and fieldwise math (checkExpr.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# The math operators on lists of numbers: + - * / element by element between two of one type,
# * and / by a number of the element type (a literal takes it), and @: matrix times matrix,
# matrix times vector, vector dot vector. A shape mismatch stops the program.
fn checkListMath(mut c Checker, e NodeId, op i64, lt TypeId, rt TypeId) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	lm = c.numMatrixElem(lt)
	rm = c.numMatrixElem(rt)
	lv = c.numListElem(lt)
	rv = c.numListElem(rt)
	res TypeId? = none
	if op == binMatmul:
		if lm != none and isSameType(tys, lt, rt):
			res = lt
		elif lm != none and rv != none and isSameType(tys, lm, rv):
			res = rt
		elif lv != none and isSameType(tys, lt, rt):
			res = lv
	elif (op in [binAdd, binSub, binMul, binDiv]) and isSameType(tys, lt, rt):
		res = lt
	elif op == binMul or op == binDiv:
		# a list and a number: the number scales every element
		elem = lm
		if elem == none:
			elem = lv
		side = 1
		if elem == none and op == binMul:
			elem = rm
			if elem == none:
				elem = rv
			side = 0
		if elem is elem:
			x = nodes[e].kids(kidIds)[side]
			xt = typeOf(nodes, x)
			if nodes[x].kind == nInt or nodes[x].kind == nFloat:
				xt = c.checkExpr(x, elem)
			if not isSameType(tys, xt, elem) and isSameType(tys, c.heldType(xt), elem):
				madeKid = c.coerceTo(x, elem)
				nodes[e].setKid(kidIds, side, madeKid)   # a range: its base
				xt = elem
			if isSameType(tys, xt, elem):
				res = lt if side == 1 else rt
	defined = res ??
		return c.errorTyped(
			line,
			col,
			compileError("OperatorUndefined", ["{binName(op)}", "{c.showTy(lt)}", "{c.showTy(rt)}"])
		)
	c.typed(e, defined)

# bindExtern(name, address): the `extern loaded fn` name calls the code at address from now on
# (an address the system gives, such as vkGetDeviceProcAddr's)
fn checkBindExtern(mut c Checker, e NodeId) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	if c.argCount(e) != 2:
		c.errorAt(line, col, compileError("BindExternArguments", []))
		return tyError
	f = c.argAt(e, 0)
	found = c.lookupDecl(
		nFnDecl,
		"",
		nodes[f].text,
		nodes[f].line,
		nodes[f].col
	) if nodes[f].kind ==
		nIdent
		else none
	fd = found ?? return c.errorTyped(line, col, compileError("BindExternTarget", []))
	if not nodes[fd].hasFlag(flagExtern) or nodes[fd].names2().isEmpty or
		nodes[fd].names2()[0] != "":
		return c.errorTyped(line, col, compileError("BindExternTarget", []))
	nodes[f].text = nodes[fd].text.copy()   # the argument names the declaration
	nodes[f].ty = tyUnit
	at = c.checkExpr(c.argAt(e, 1), tyInt(64, true))
	if c.tKind(at) != tInt and c.tKind(at) != tError:
		errorAt(
			c,
			line,
			col,
			compileError("BindExternAddress", ["{c.showTy(at)}"])
		)
	c.typed(e, tyUnit)

# bindExterns(loader): every `extern loaded fn` of the calling module given the address
# loader(name) finds for it (its name as written), as if bindExtern were called for each. The
# calls of the loader are kept in sub, their functions in ints.
fn checkBindExterns(mut c Checker, e NodeId) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	if c.argCount(e) != 1:
		errorAt(
			c,
			line,
			col,
			compileError("BindExternsArgument", [])
		)
		return tyError
	module = c.modules[c.curMod].id.copy() if c.curMod >= 0 else ""
	externs = c.decls.filter(d:
		nodes[d].kind == nFnDecl and nodes[d].hasFlag(flagExtern) and
			not nodes[d].names2().isEmpty and nodes[d].names2()[0] == "" and
			nodes[d].mod() == module
	)
	nodes[e].nodePart().types.extend(externs)   # the functions it binds
	if nodes[e].types().isEmpty:
		c.errorAt(line, col, compileError("BindExternsNone", []))
		return tyError
	for i in 0..c.nodes[e].types().len:
		fd = nodes[e].types()[i]
		call = newNode(nodes, kidIds, nCall, line, col)
		madeKid = cloneTree(nodes, kidIds, c.argAt(e, 0))
		nodes[call].pushKid(kidIds, madeKid)
		name = newNode(nodes, kidIds, nStr, line, col)
		nodes[name].text = nodes[fd].names2()[1].copy() if nodes[fd].names2().len > 1
			else nodes[fd].text2().copy()
		nodes[call].pushKid(kidIds, name)
		nodes[e].nodePart().sub.push(call)
		at = c.checkExpr(call, tyInt(64, true))
		if c.tKind(at) != tInt and c.tKind(at) != tError:
			c.errorAt(
				line,
				col,
				compileError("BindExternsLoader", ["{c.showTy(at)}"])
			)
			return tyError
	c.typed(e, tyUnit)

# whether constant cd is a number literal with no type written (`k = 7`, `half = 0.5`, `low = -3`)
fn numericLiteralConstant(c Checker, cd NodeId):
	nodes[cd].types().isEmpty and not nodes[cd].hasFlag(flagMut) and
		not nodes[cd].kids(kidIds).isEmpty and c.isNumLit(nodes[cd].kids(kidIds)[0])

# whether an expression names a variable in scope (a field's default may not: it is written
# where the type is declared, and checked where the literal is)
fn readsVariable(mut c Checker, e NodeId) bool:
	if nodes[e].kind == nIdent and c.lookupVarQuiet(nodes[e].text): return true
	nodes[e].kids(kidIds).any(c.readsVariable(it))

# whether a variable of this name is in scope (without recording a capture)
fn lookupVarQuiet(c Checker, name str):
	c.vars.any(.name == name)

# The arguments of call e to fd in the order of its parameters (from parameter `first` on, the
# ones before it given already, as a receiver is): the named ones (`tint = red`) moved to their
# parameter's place, the ones left out given the parameter's default (a copy of its expression,
# as if written there). A name that is not a parameter, given twice or after its place was
# filled, and a parameter left out with no default are reported; the call's kids are then the
# arguments in order, as any other call's.
fn fillArguments(mut c Checker, e NodeId, fd NodeId, first i64):
	line = nodes[e].line
	col = nodes[e].col
	named = nodes[e].kidsFrom(kidIds, 1).any(nodes[it].kind == nNamedArg)
	nparams = nodes[fd].kids(kidIds).len - first
	hasDefault = nodes[fd].kids(kidIds)[first..nodes[fd].kids(kidIds).len]
		.any(not nodes[it].kids(kidIds).isEmpty)
	if not named and (not hasDefault or c.argCount(e) >= nparams):
		return   # an ordinary call: nothing to place
	# the slot of each parameter: the argument given for it, or -1
	slots NodeId?[] = zeros(nparams)
	positional = 0
	ok = true
	sawNamed = false
	for i in 1..c.nodes[e].kids(c.kidIds).len:
		a = nodes[e].kids(kidIds)[i]
		if nodes[a].kind != nNamedArg and sawNamed:
			c.errorAt(nodes[a].line, nodes[a].col, compileError("ValueAfterNamed", []))
			ok = false
			break
		if nodes[a].kind != nNamedArg:
			if positional >= nparams:
				ok = false
				break
			slots[positional] = a
			positional += 1
			continue
		sawNamed = true
		at = -1
		for k in 0..nparams:
			if nodes[nodes[fd].kids(kidIds)[first + k]].text == nodes[a].text:
				at = k
		if at < 0 and nodes[a].text == "..":
			c.errorAt(
				nodes[a].line,
				nodes[a].col,
				compileError("BaseOfFunction", ["{nodes[fd].text2()}"])
			)
			ok = false
		elif at < 0:
			errorAt(
				c,
				nodes[a].line,
				nodes[a].col,
				compileError("NoParameter", ["{nodes[fd].text2()}", "{nodes[a].text}"])
			)
			ok = false
		elif slots[at] != none:
			errorAt(
				c,
				nodes[a].line,
				nodes[a].col,
				compileError("ArgumentGivenTwice", ["{nodes[a].text}"])
			)
			ok = false
		else:
			slots[at] = nodes[a].kids(kidIds)[0]
	if not ok:
		# reported: the named arguments count as their values, for the arity check's word
		for i in 1..c.nodes[e].kids(c.kidIds).len:
			a = nodes[e].kids(kidIds)[i]
			if nodes[a].kind == nNamedArg: nodes[e].setKid(kidIds, i, nodes[a].kids(kidIds)[0])
		return
	missing = []
	for k in 0..nparams:
		if slots[k] != none: continue
		p = nodes[fd].kids(kidIds)[first + k]
		if nodes[p].kids(kidIds).isEmpty:
			missing.push(nodes[p].text.copy())
			continue
		val = c.defaultOf(p, fd, "parameter")
		nodes[val].line = line
		nodes[val].col = col
		slots[k] = val
	if not missing.isEmpty:
		c.errorAt(
			line,
			col,
			compileError(
				"MissingArgument",
				[
					"{nodes[fd].text2()}",
					"{"an argument" if missing.len == 1 else "arguments"}",
					"{missing.join(", ")}"
				]
			)
		)
		return
	kids = [nodes[e].kids(kidIds)[0]]
	for slot in slots:
		if slot is given: kids.push(given)   # (each one given by now)
	nodes[e].setKids(kidIds, kids)

# A number's method on a struct of numbers (`v.floor()`, `v.min(o)`, `v.clamp(0.0, 1.0)`), its
# type having no method of that name: the method field by field, each argument a struct of the
# same type (its field) or a number of the fields' type (spread over them). The checker asks for
# the function that does it ($fw<method><shape>N, derive.zap), which the backend calls.
fn checkFieldwise(mut c Checker, e NodeId, t TypeId, move m str):
	field = c.uniformNumberField(t) ?? return tyError   # (asked of a struct of one number type)
	if m == "dot" and not nodes[e].hasFlag(flagInternal):
		c.errorAt(nodes[e].line, nodes[e].col, compileError("NoMethod", ["dot", c.showTy(t)]))
		return tyError
	if c.tKind(field) != tFloat and m not in ["abs", "min", "max", "clamp", "dot"]:
		errorAt(
			c,
			nodes[e].line,
			nodes[e].col,
			compileError("FloatMethod", ["{m}", "{c.showTy(t)}", "{c.showTy(field)}"])
		)
		return tyError
	if not c.expectArgs(e, m, c.fieldwiseArity(m)): return tyError
	vector = m in vectorMethods
	shape = ""
	for i in 0..argCount(c, e):
		a = c.argAt(e, i)
		at = c.derefIfRef(a, c.checkExpr(a, field if c.isNumLit(a) else none))   # a literal takes the fields' type
		if isSameType(tys, at, t):
			shape += "S"
		elif isSameType(tys, at, field) and not vector:
			shape += "N"
		else:
			c.errorAt(
				nodes[a].line,
				nodes[a].col,
				compileError(
					"ArgumentKind",
					[
						"{m}",
						"{c.showTy(t)}",
						"{"" if vector else " or a {c.showTy(field)}"}",
						"{c.showTy(at)}"
					]
				)
			)
			return tyError
	result = field if m in ["dot", "length", "distance"] else t
	if c.gpuCode:
		return result   # the GPU's own (irGpu.zap); the CPU never runs it
	c.noteFieldwise(t, m, shape)
	nodes[e].flags |= flagFieldwise
	nodes[e].setText2("fw{m}{shape}")
	result
