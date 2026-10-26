# grad(f): the derivative of a function, written by the compiler (spec 5.4). `grad(f)` is a
# function taking f's parameters and giving f's value and its gradient with respect to the first
# parameter (a number, a std/tensor Tensor, or a struct or list of those): `loss, g =
# grad(lossOf)(model, batch)`. The checker notes each ask; once the program is checked,
# gradWrite.zap writes Zap functions for it, in reverse mode, parsed into the `derive` module and
# checked like any program code:
#   $gradN(params) (R, P1)       f's value, and the gradient of its first parameter
#   $pullN(params, dy R) G...    the gradients of the parameters a caller differentiates (mask)
#   $gzeroN(a) $TyN, $gaddN(a, b) $TyN   a struct of gradients: its zero, a sum field by field
# A function with a hand derivative (`fGrad` in its module, taking f's parameters and the
# result's gradient, giving those of its tensor parameters) is not differentiated: its derivative
# is called. ZAP_RUN=derived prints what is written.

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# what a gradient is of: nothing, a number, a tensor, a struct of gradients, a list of them
gradNone = 0
gradNum = 1
gradTensor = 2
gradRecord = 3
gradList = 4

# a derivative asked: of function fd, of its parameters marked active; `top`: grad(fd) itself
type GradAsk:
	fd NodeId
	active bool[]
	top bool

# what a value's gradient is, given its type
fn gradKind(mut c Checker, t0 TypeId) i64:
	t = c.derefType(t0)
	k = c.tKind(t)
	if k == tFloat: return gradNum
	if c.isTensorType(t): return gradTensor
	if k == tList:
		inner = c.gradKind(innerOf(tys, t))
		return gradList if inner in [gradTensor, gradRecord, gradNum] else gradNone
	if k == tStruct and not c.isTupleType(t) and c.gridKind(t) == 0 and c.isGradRecord(t):
		return gradRecord
	gradNone

# a struct some of whose fields have a gradient (the others carried along)
fn isGradRecord(mut c Checker, t TypeId):
	d = declOf(tys, t)
	if nodes[d].kind != nStructDecl or not nodes[d].names().isEmpty: return false
	c.fieldTypes(d).any(c.gradKind(it) != gradNone)

# the index of the derivative asked (asked now when new)
fn noteGrad(mut c Checker, fd NodeId, active bool[], top bool):
	for i, ask in c.gradAsks:
		if ask.fd == fd and ask.active == active and ask.top == top: return i
	c.gradAsks.push(GradAsk(fd, active = active.copy(), top))
	c.gradAsks.len - 1

# the name derive.zap's module gives an asked derivative
fn gradFnName(c Checker, i i64):
	"${"grad" if c.gradAsks[i].top else "pull"}{i}"

# `grad(f)`: f's derivative as a function value, its type f's parameters to (f's result, the
# first parameter's type)
fn checkGradRef(mut c Checker, e NodeId) TypeId:
	line = nodes[e].line
	col = nodes[e].col
	if c.argCount(e) != 1:
		c.errorAt(line, col, compileError("GradTakesFunction", []))
		return tyError
	arg = c.argAt(e, 0)
	ft = c.checkExpr(arg, none)
	if c.tKind(ft) != tFn or not nodes[arg].hasFlag(flagFnRef):
		c.errorAt(line, col, compileError("GradTakesFunction", []))
		return tyError
	fd = c.findFunc(nodes[arg].text) ?? return tyError
	params = tys[ft].params.copy()
	ret = tys[ft].ret ?? tyUnit
	if params.isEmpty or c.gradKind(params[0]) == gradNone:
		c.errorAt(
			line,
			col,
			compileError(
				"GradParameter",
				["{nodes[fd].text2()}", "{c.showTy(params[0] if not params.isEmpty else tyUnit)}"]
			)
		)
		return tyError
	rk = c.gradKind(ret)
	if rk != gradNum and rk != gradTensor:
		c.errorAt(line, col, compileError("GradResult", ["{nodes[fd].text2()}", "{c.showTy(ret)}"]))
		return tyError
	active = fill(params.len, false)
	active[0] = true
	i = c.noteGrad(fd, active, true)
	if c.implOfMethod(fd) != none:
		c.errorAt(line, col, compileError("GradTakesFunction", []))   # a method's self is its type's
		return tyError
	result = c.tupleTypeOf(fd, [nodes[fd].types()[0], nodes[nodes[fd].kids(kidIds)[0]].types()[0]])
	nodes[e].kind = nIdent
	nodes[e].setText("derive__{c.gradFnName(i)}")
	nodes[e].setKids(kidIds, [])
	nodes[e].flags |= flagFnRef
	c.typed(e, tyFn(tys, params, result))

# the tuple of the types the type expressions of fd's module write
fn tupleTypeOf(mut c Checker, fd NodeId, parts NodeId[]):
	savedMod = c.curMod
	savedFile = c.curFile.copy()
	c.enterModuleOf(fd)
	te = newNode(nodes, kidIds, nTyName, nodes[fd].line, nodes[fd].col, text = "Tuple{parts.len}")
	nodes[te].setText2("$rt")
	nodes[te].nodePart().types = parts.copy()
	t = c.resolveType(te)
	c.curMod = savedMod
	c.curFile = savedFile
	t

# whether the code being checked is what the compiler wrote (derive.zap's module)
fn inDerived(c Checker):
	c.curMod >= 0 and c.modules[c.curMod].id == "derive"

# whether call e is `grad(f)`, the name not taken by the program
fn isGradCall(mut c Checker, e NodeId):
	callee = nodes[e].kids(kidIds)[0]
	nodes[callee].kind == nIdent and nodes[callee].text == "grad" and
		not c.lookupVarQuiet("grad") and
		c.lookupDecl(nFnDecl, "", "grad", nodes[e].line, nodes[e].col) == none
