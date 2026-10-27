# The functions grad.zap's asks need, written as Zap source (derive.zap's way). A body is read
# in order as values, each a name of the written function (`$vN`); the backward pass then walks
# them in reverse, each value's gradient the sum of what its uses gave it (`$dN`), a use's share
# `$cN`. What a value of a parameter given no gradient feeds is a constant: only the values the
# active parameters reach are differentiated (an activity analysis). A tail `if` or `match`
# writes each arm's forward and backward pass in the arm; a `for` over a list or a range keeps
# the values its loop changes at each step's start and goes over the steps backward, each step's
# values computed again (a checkpoint per step). What it cannot differentiate is an error at the
# place it is written (GradUnsupported).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# a value of the function being written
type GVal:
	name str   # what the written code calls it: a name, or a literal's text
	t TypeId
	kind i64   # gradNone..gradList
	active bool
	contribs str[] = []   # the names of the shares of its gradient, in the order given
	fieldContribs {str: str[]} = {}   # a struct's: per field, its shares
	elemList str = ""   # a list's: the mutable list of its elements' gradients, once made
	text str = ""   # what its binding is bound to
	lent bool = false   # a part of another value (a field, an element) or a name: read again, not kept

# an operation the forward pass made, walked back by the backward one
type GOp:
	kind i64   # opRule..opLoop
	result i64
	args i64[]   # values
	text str = ""   # the function a rule or pull calls; a scalar operation's name; a field's name
	node NodeId   # the expression
	extra str = ""   # a rule's or pull's slots of gradients, comma-joined indexes of args

opRule = 0   # a hand derivative (fGrad): the gradients of its tensor parameters
opPull = 1   # a function the compiler differentiates ($pullN)
opScalar = 2   # a number's operation: text "+", "-", "*", "/", "neg", or a method's name
opField = 3   # a struct's field read: text the field
opIndex = 4   # a list's element: args [list, index]
opCopy = 5   # the same value under another name (a conversion of a number: text the type)
opLoop = 6   # a loop: GLoop[extra]

# A loop over steps: the values it changes (each its value before the loop, the mutable name it
# lives in through the loop, the list that keeps it at each step's start, and its value after),
# what it walks, the body's statements.
type GLoop:
	carried str[]   # the source names of the values the loop changes
	before i64[]   # their values before
	after i64[]   # their values after (the mutable names)
	tapes str[]
	over i64   # the list walked, -1 a range
	rangeText str   # a range's text (its bounds' values)
	element str   # the loop variable's source name
	elementT TypeId
	body NodeId
	steps str   # the name of the count of steps
	index str   # the step's index
	outer i64   # the values made before the loop
	starts i64[]   # the values the body starts from, the loop's changed ones
	ends i64[]   # the values the body ends with
	kept i64[]   # the body's values its backward pass reads, kept a list each
	elementValue i64   # the element's value, -1 for a range's
	values GVal[]   # the writer's values after the body
	ops GOp[]   # the body's operations

type GradWriter:
	values GVal[] = []
	ops GOp[] = []
	loops GLoop[] = []
	names {str: i64} = {}   # a source name: its current value
	inLoop bool = false
	inlining NodeId[] = []   # the functions read in place, innermost last
	lines str[] = []
	indent i64 = 1
	counter i64 = 0
	fd NodeId
	selfFields str[] = []   # a method's bare field names, read through its first parameter
	failed bool = false

fn gLine(mut w GradWriter, text str):
	w.lines.push("\t".repeat(w.indent) + text)

fn gFresh(mut w GradWriter, prefix str):
	w.counter += 1
	"${prefix}{w.counter}"

fn gAdd(mut w GradWriter, name str, t TypeId, kind i64, active bool):
	w.values.push(GVal(name = name.copy(), t, kind, active))
	w.values.len - 1

# the error at node e: grad cannot differentiate what it is
fn gradUnsupported(mut c Checker, mut w GradWriter, e NodeId, what str):
	if w.failed: return
	w.failed = true
	c.errorAt(
		nodes[e].line,
		nodes[e].col,
		compileError("GradUnsupported", ["{nodes[w.fd].text2(kidIds)}", "{what}"])
	)

# the source of a type in the written code
fn gTypeText(mut c Checker, t TypeId):
	k = c.tKind(t)
	if k in [tFloat, tInt, tBool]: return c.showTy(t)
	tyName(c.noteDerive(t, 0))

# ---------- the asked functions ----------

# Writes the function the ask i names: its parameters as the function's (the active ones' first
# taking its gradient), the forward pass of the body, then the backward one.
fn writeGrad(mut c Checker, i i64, mut src str[]):
	ask = c.gradAsks[i].copy()
	fd = ask.fd
	savedMod = c.curMod
	savedFile = c.curFile.copy()
	c.enterModuleOf(fd)
	w = GradWriter(fd)
	params = []
	names, types = c.gParams(fd)
	for k, pt in types:
		name = "$a{k}"
		params.push("{name} {c.gTypeText(pt)}")
		kind = c.gradKind(pt)
		v = w.gAdd(name, pt, kind, ask.active[k] and kind != gradNone)
		w.names[names[k].copy()] = v
		if k == 0 and names[k] == "self":
			w.selfFields = c.fieldNamesOf(pt)
	ret = c.fnRetType(fd)
	retText = c.gTypeText(ret)
	grads = []
	for k in 0..ask.active.len:
		if ask.active[k]:
			grads.push(c.gTypeText(types[k]))
	if not ask.top:
		params.push("$dy {retText}")
	results = [retText] if ask.top else []
	results.extend(grads)
	resultText = results[0] if results.len == 1 else "({results.join(", ")})"
	c.readBody(fd)
	body = nodes[fd].sub(kidIds)[0]
	c.gWriteBlock(w, nodes[body].kids(kidIds).copy(), ask)
	if not w.failed:
		src.push("fn {c.gradFnName(i)}({params.join(", ")}) {resultText}:")
		src.extend(unreadDropped(w.lines))
	c.curMod = savedMod
	c.curFile = savedFile

# the lines without the forward values no other line reads (every binding is read; a value is
# computed again backward only for what its derivative needs)
fn unreadDropped(lines str[]):
	kept = lines.copy()
	going = true
	while going:
		going = false
		uses {str: i64} = {}
		for line in kept:
			for name in valueNames(line):
				uses.add(name, 1)
		next = []
		for line in kept:
			tabs = 0
			while tabs < line.len and line[tabs] == '\t':
				tabs += 1
			at = line.indexOf(" = ") ?? -1
			if at > tabs and line[tabs..].startsWith("$v") and (uses.get(line[tabs..at]) ?? 0) == 1:
				going = true   # a value nothing reads: not computed (what it read may go in turn)
			else:
				next.push(line.copy())
		kept = next
	kept

# the $vN names a line holds
fn valueNames(line str):
	out = []
	i = 0
	while i + 1 < line.len:
		if line[i] == '$' and line[i + 1] == 'v':
			j = i + 2
			while j < line.len and line[j] >= '0' and line[j] <= '9':
				j += 1
			if j > i + 2:
				out.push(line[i..j].copy())
			i = j
		else:
			i += 1
	out

# The names and the types of fd's parameters, a method's self first (the parser keeps it apart:
# a function taking self is a method of its type's impl).
fn gParams(mut c Checker, fd NodeId):
	names = []
	types = []
	if c.implOfMethod(fd) is impl:
		names.push("self")
		types.push(c.implTypeOf(impl) ?? tyError)
	kids = nodes[fd].kids(kidIds).copy()
	for p in kids:
		names.push(nodes[p].text.copy())
		types.push(c.resolveType(nodes[p].types(kidIds)[0]))
	(names, types)

# the impl a method is of, none for a function
fn implOfMethod(c Checker, fd NodeId) NodeId?:
	if not nodes[fd].text2(kidIds).isEmpty: return none
	c.decls.find(nodes[it].kind == nImplDecl and fd in nodes[it].kids(kidIds))

fn fieldNamesOf(mut c Checker, t TypeId):
	st = c.derefType(t)
	if c.tKind(st) != tStruct: return []
	d = declOf(tys, st)
	(0..nodes[d].kids(kidIds).len).map(c.fieldName(d, it).copy())

# The statements of a body whose last gives the function's value: each read forward, then, at
# the value (an if or a match there writes each arm's rest), the seed and the backward pass, and
# the return of the value and the gradients.
fn gWriteBlock(mut c Checker, mut w GradWriter, stmts NodeId[], ask GradAsk):
	for k, s in stmts:
		last = k == stmts.len - 1
		value = s
		if nodes[s].kind == nReturn and last and not nodes[s].kids(kidIds).isEmpty:
			value = nodes[s].kids(kidIds)[0]
		elif nodes[s].kind == nExprStmt and last:
			value = nodes[s].kids(kidIds)[0]
		if last:
			if nodes[value].kind == nMatch or nodes[value].kind == nIf:
				c.gWriteTailBranch(w, value, ask)
				return
			v = c.gExpr(w, value)
			c.gFinish(w, v, ask)
			return
		c.gStmt(w, s)
		if w.failed: return

# a tail `match` (or `if`): each arm the rest of the function
fn gWriteTailBranch(mut c Checker, mut w GradWriter, e NodeId, ask GradAsk):
	if nodes[e].kind == nIf:
		cond = c.gExpr(w, nodes[e].kids(kidIds)[0])
		if w.values[cond].active:
			return c.gradUnsupported(w, e, "a condition on a value it differentiates")
		w.gLine("if {w.values[cond].name}:")
		c.gArm(w, nodes[nodes[e].sub(kidIds)[0]].kids(kidIds).copy(), ask)
		w.gLine("else:")
		if nodes[e].sub(kidIds).len < 2: return c.gradUnsupported(w, e, "an if without else as the value")
		elseBody = nodes[e].sub(kidIds)[1]
		c.gArm(
			w,
			nodes[elseBody].kids(kidIds) if nodes[elseBody].kind == nBlock else [elseBody],
			ask
		)
		return
	subject = c.gExpr(w, nodes[e].kids(kidIds)[0])
	if w.values[subject].active:
		return c.gradUnsupported(w, e, "a match on a value it differentiates")
	w.gLine("match {w.values[subject].name}:")
	for arm in nodes[e].kidsFrom(kidIds, 1).copy():
		pat = c.gPatternText(w, nodes[arm].kids(kidIds)[0])
		if w.failed: return
		w.gLine("\t{pat}:")
		w.indent += 1
		body = nodes[arm].kids(kidIds)[1]
		c.gArm(w, nodes[body].kids(kidIds) if nodes[body].kind == nBlock else [body], ask)
		w.indent -= 1

# one arm: the writer's state copied, the arm's statements the rest of the function
fn gArm(mut c Checker, mut w GradWriter, stmts NodeId[], ask GradAsk):
	arm = w.copy()
	arm.indent += 1
	arm.lines = []
	c.gWriteBlock(arm, stmts, ask)
	w.lines.extend(arm.lines)
	w.counter = arm.counter
	w.failed = w.failed or arm.failed

# a pattern of an arm, as written: a literal, `_`, a variant without values
fn gPatternText(mut c Checker, mut w GradWriter, p NodeId):
	k = nodes[p].ival
	if k == patWildcard: return "_"
	if k == patLit:
		lit = nodes[p].kids(kidIds)[0]
		return c.gLiteralText(w, lit)
	if k == patCtor and nodes[p].kids(kidIds).isEmpty: return ".{nodes[p].text}"
	c.gradUnsupported(w, p, "an arm's pattern of values")
	""

# the seed, the backward pass and the return
fn gFinish(mut c Checker, mut w GradWriter, v i64, ask GradAsk):
	if w.failed: return
	value = w.values[v].name.copy()
	if ask.top:
		seed = "1.0" if w.values[v].kind == gradNum else "{value}.onesLike()"
		if w.values[v].kind == gradNum:
			w.gLine("$dseed {c.gTypeText(w.values[v].t)} = {seed}")
		else:
			w.gLine("$dseed = {seed}")
	if w.values[v].active:
		w.values[v].contribs.push("$dseed" if ask.top else "$dy")
	c.gBackward(w, 0)
	out = [value] if ask.top else []
	for k in 0..ask.active.len:
		if ask.active[k]:
			out.push(c.gGradientOf(w, k))
	if w.failed: return
	w.gLine(out[0] if out.len == 1 else "({out.join(", ")})")

# ---------- the forward pass ----------

fn gStmt(mut c Checker, mut w GradWriter, s NodeId):
	k = nodes[s].kind
	if k == nLet and not nodes[s].kids(kidIds).isEmpty and nodes[s].names(kidIds).isEmpty:
		v = c.gExpr(w, nodes[s].kids(kidIds)[0])
		w.names[nodes[s].text.copy()] = v
		return
	if k == nAssign and nodes[nodes[s].kids(kidIds)[0]].kind == nIdent and nodes[s].ival == 0:
		target = nodes[nodes[s].kids(kidIds)[0]].text.copy()
		v = c.gExpr(w, nodes[s].kids(kidIds)[1])
		w.names[target.copy()] = v
		return
	if k == nFor:
		c.gFor(w, s)
		return
	c.gradUnsupported(w, s, "this statement")

# The value of expression e: its parts' values, then its own (a new name, or the literal).
fn gExpr(mut c Checker, mut w GradWriter, e NodeId) i64:
	if w.failed: return 0
	k = nodes[e].kind
	t = typeOf(nodes, e)
	if k in [nInt, nFloat, nBool, nStr]:
		return w.gAdd(c.gLiteralText(w, e), t, c.gradKind(t), false)
	if k == nDeref: return c.gExpr(w, nodes[e].kids(kidIds)[0])
	if k == nIdent:
		if w.names.get(nodes[e].text) is v: return v
		if nodes[e].text in w.selfFields:
			return c.gField(w, e, w.names["self"], nodes[e].text.copy())
		return w.gAdd(c.gGlobalText(w, e), t, gradNone, false)
	if k == nField:
		obj = nodes[e].kids(kidIds)[0]
		if c.isModuleName(obj): return w.gAdd(c.gGlobalText(w, e), t, gradNone, false)
		r = c.gExpr(w, obj)
		return c.gField(w, e, r, nodes[e].text.copy())
	if k == nIndex:
		list = c.gExpr(w, nodes[e].kids(kidIds)[0])
		at = c.gExpr(w, nodes[e].kids(kidIds)[1])
		return c.gValueOp(
			w,
			e,
			opIndex,
			[list, at],
			"",
			"{w.values[list].name}[{w.values[at].name}]"
		)
	if k == nUnary and nodes[e].ival == unNeg:
		a = c.gExpr(w, nodes[e].kids(kidIds)[0])
		return c.gValueOp(w, e, opScalar, [a], "neg", "-{w.values[a].name}")
	if k == nBinary: return c.gBinary(w, e)
	if k == nCall: return c.gCall(w, e)
	if k == nArray:
		elements = nodes[e].kids(kidIds).copy()
		parts = []
		for el in elements:
			parts.push(c.gExpr(w, el))
		if parts.any(w.values[it].active):
			c.gradUnsupported(w, e, "a list of values it differentiates")
		text = "[{parts.map(w.values[it].name.copy()).join(", ")}]"
		return c.gBind(w, e, text, false)
	c.gradUnsupported(w, e, "this expression")
	0

# a literal's text
fn gLiteralText(mut c Checker, mut w GradWriter, e NodeId):
	k = nodes[e].kind
	if k == nBool: return "true" if nodes[e].ival != 0 else "false"
	if k == nStr:
		escaped = nodes[e].text
			.replace("\\", "\\\\")
			.replace("\"", "\\\"")
			.replace(r"{", r"\{")
			.replace("\n", "\\n")
		return "\"{escaped}\""
	text = nodes[e].text.copy()
	if k == nFloat and c.tKind(typeOf(nodes, e)) == tFloat: return text
	text

# a name the body reads that is not its own: a constant or a function of a module, by its
# global name
fn gGlobalText(mut c Checker, mut w GradWriter, e NodeId):
	if nodes[e].kind == nIdent:
		if c.lookupDecl(nConstDecl, "", nodes[e].text, nodes[e].line, nodes[e].col) is d:
			return "$global.{nodes[d].text}"
		if c.findDeclByGlobalName(nConstDecl, nodes[e].text, nameOf(nodes, e)) is d:
			return "$global.{nodes[d].text}"
	if nodes[e].kind == nField and c.isModuleName(nodes[e].kids(kidIds)[0]):
		alias = nodes[nodes[e].kids(kidIds)[0]].text
		if c.lookupDecl(nConstDecl, alias, nodes[e].text, nodes[e].line, nodes[e].col) is d:
			return "$global.{nodes[d].text}"
	c.gradUnsupported(w, e, "the name '{nodes[e].text}'")
	""

# whether e names a module (`tensor` of `tensor.zeros`)
fn isModuleName(mut c Checker, e NodeId):
	nodes[e].kind == nIdent and nodes[e].ty == none and
		c.findImportByAlias(c.curMod, nodes[e].text) != none

# a field of value r
fn gField(mut c Checker, mut w GradWriter, e NodeId, r i64, field str) i64:
	c.gValueOp(w, e, opField, [r], field, "{w.values[r].name}.{field}")

# a value bound to a new name: `$vN = text`
fn gBind(mut c Checker, mut w GradWriter, e NodeId, text str, active bool):
	t = typeOf(nodes, e)
	name = w.gFresh("v")
	w.gLine("{name} = {text}")
	v = w.gAdd(name, t, c.gradKind(t), active)
	w.values[v].text = text.copy()
	w.values[v].lent = nodes[e].kind in [nField, nIndex, nIdent, nDeref]
	v

# a value made by an operation of the args: bound, and its op kept when it is differentiated
fn gValueOp(
	mut c Checker,
	mut w GradWriter,
	e NodeId,
	kind i64,
	args i64[],
	what str,
	text str
):
	# a value without a gradient (a size, a shape, a count) is a constant whatever it is made of
	active = args.any(w.values[it].active) and c.gradKind(typeOf(nodes, e)) != gradNone
	v = c.gBind(w, e, text, active)
	if active:
		w.ops.push(GOp(kind, result = v, args = args.copy(), text = what.copy(), node = e))
	v

scalarOps = ["+", "-", "*", "/"]

fn gBinary(mut c Checker, mut w GradWriter, e NodeId) i64:
	op = nodes[e].ival
	a = c.gExpr(w, nodes[e].kids(kidIds)[0])
	b = c.gExpr(w, nodes[e].kids(kidIds)[1])
	symbol = binName(op)
	text = "{w.values[a].name} {symbol} {w.values[b].name}"
	if not w.values[a].active and not w.values[b].active: return c.gBind(w, e, "({text})", false)
	if not (op in [binAdd, binSub, binMul, binDiv]) or c.gradKind(typeOf(nodes, e)) != gradNum:
		c.gradUnsupported(w, e, "the operator '{symbol}' on a value it differentiates")
		return 0
	c.gValueOp(w, e, opScalar, [a, b], symbol, text)

# The functions of one number grad knows (their derivatives in gScalarBack).
scalarMethods = ["exp", "ln", "sqrt", "tanh", "sin", "cos", "abs", "max", "min"]

# a call: a number's method, a function with a hand derivative, or one grad differentiates
fn gCall(mut c Checker, mut w GradWriter, e NodeId):
	callee = nodes[e].kids(kidIds)[0]
	argNodes = nodes[e].kidsFrom(kidIds, 1).copy()
	method = ""
	if nodes[e].hasFlag(flagMethod) and not nodes[callee].names(kidIds).isEmpty:
		method = nodes[callee].names(kidIds)[0].copy()
	elif nodes[callee].kind == nField and not c.isModuleName(nodes[callee].kids(kidIds)[0]):
		method = nodes[callee].text.copy()
		argNodes.insert(0, nodes[callee].kids(kidIds)[0])
	fd = c.calleeDecl(e)
	args = argNodes.map(c.gExpr(w, it))
	if w.failed: return 0
	names = args.map(w.values[it].name.copy())
	text = c.gCallText(w, e, fd, method, names)
	active = args.any(w.values[it].active)
	if not active or c.gradKind(typeOf(nodes, e)) == gradNone: return c.gBind(w, e, text, false)
	if method == "copy" and args.len == 1: return c.gValueOp(w, e, opCopy, args, "", text)
	number = c.tKind(typeOf(nodes, e)) == tFloat and
		c.tKind(c.derefType(w.values[args[0]].t)) == tFloat
	if number and method in scalarMethods: return c.gValueOp(w, e, opScalar, args, method, text)
	if fd == none or c.isConversionCall(e) or method in floatConversions:
		if number and args.len == 1 and (method.isEmpty or method in floatConversions):
			return c.gValueOp(w, e, opCopy, args, c.showTy(typeOf(nodes, e)), text)
		c.gradUnsupported(
			w,
			e,
			"the call of '{method if not method.isEmpty else nodes[callee].text}'"
		)
		return 0
	f = fd ?? 0
	if c.ruleOf(f) is rule:
		v = c.gValueOp(
			w,
			e,
			opRule,
			args,
			(nodes[rule].text2(kidIds) if not nodes[rule].text2(kidIds).isEmpty else nodes[rule].text).copy(),
			text
		)
		w.ops[len - 1].extra = c.gRuleSlots(w, e, f, rule, args)
		return v
	if nodes[f].sub(kidIds).isEmpty or nodes[f].hasFlag(flagExtern):
		c.gradUnsupported(
			w,
			e,
			"the call of '{nodes[f].text2(kidIds)}', which has no body nor derivative"
		)
		return 0
	if c.inlinable(w, f) is stmts: return c.gInline(w, f, stmts, args)
	mask = []
	for k, a in args:
		mask.push(w.values[a].active and c.gradKind(w.values[a].t) != gradNone)
	pull = c.noteGrad(f, mask, false)
	v = c.gValueOp(w, e, opPull, args, c.gradFnName(pull), text)
	w.ops[len - 1].extra = (0..args.len).filter(mask[it]).map(str(it)).join(",")
	v

# the hand derivative of function f: `fGrad` of its module
fn ruleOf(mut c Checker, f NodeId):
	if not nodes[f].text2(kidIds).isEmpty:
		return c.findDeclInModule(nodes[f].mod(kidIds).copy(), nFnDecl, "{nodes[f].text2(kidIds)}Grad")
	# a method (its first parameter self): its type's
	impl = try c.implOfMethod(f)
	c.findMethod(nodes[impl].text, "{nodes[f].text}Grad")

# whether call e converts a number (f32(x))
fn isConversionCall(c Checker, e NodeId):
	callee = nodes[e].kids(kidIds)[0]
	nodes[callee].kind == nIdent and primType(nodes[callee].text) != none

# the call's text: a method on its first argument, else the function by its global name
fn gCallText(mut c Checker, mut w GradWriter, e NodeId, fd NodeId?, method str, names str[]):
	if not method.isEmpty: return "{names[0]}.{method}({names[1..].join(", ")})"
	callee = nodes[e].kids(kidIds)[0]
	if c.isConversionCall(e): return "{nodes[callee].text}({names.join(", ")})"
	f = fd ?? return ""
	"$global.{nodes[f].text}({names.join(", ")})"

# The arguments a hand derivative gives gradients of: its function's first tensor parameters, as
# many as it gives (one, or a tuple's); an active argument for another parameter is an error.
fn gRuleSlots(mut c Checker, mut w GradWriter, e NodeId, fd NodeId, rule NodeId, args i64[]):
	rt = c.fnRetType(rule)
	given = nodes[declOf(tys, rt)].kids(kidIds).len if c.isTupleType(rt) else 1
	slots = []
	for k, a in args:
		pt = w.values[a].t
		if c.isTensorType(c.derefType(pt)) and slots.len < given:
			slots.push(str(k))
		elif w.values[a].active:
			c.gradUnsupported(w, e, "an argument of {nodes[fd].text2(kidIds)} it differentiates, which {nodes[fd].text2(kidIds)}Grad takes as a constant")
	slots.join(",")
