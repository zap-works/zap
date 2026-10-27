# The GPU's functions lowered to the intermediate form (ir.zap): a shader's entry functions and
# every function they call, a GPU file's or any other (std/math's), from the tree mc checked. A
# vreg holds any value of the GPU's in one (a number, a vector, a matrix, a struct, a tuple, an
# array, a texture), typed in the shader compiler's terms (shader.Ty: the language's vectors and
# matrices are the GPU's, i64 its 32-bit number, f64 a GPU file's double and any other code's
# 32-bit float, as the GPU ran the CPU's code before it had doubles); a branch and a loop keep their
# structure (IrFn.merges), and && and || are branches too. A function's parameter of a part's
# struct (the program's parameters) has no vreg: `p.field` reads the stage's parameter, texture
# or storage buffer where it is (irStageIn), and the argument is not passed. The language's
# operations on numbers and vectors are the GPU's own (irBuiltin, irMatMul), whether the checker
# kept them as operators (a GPU file's code) or made them calls of the runtime's functions (a CPU
# function's: $fw..., mat4TimesVec, f64Sin); what is left of the runtime is lowered as any other
# function (quatTimesQuat). irSpirv.zap writes SPIR-V from the result, irHlsl.zap HLSL.

import shader

alias nodes = w.c.nodes
alias kidIds = w.c.kidIds
alias tys = w.c.types

# the structs of a program's GPU code, a sid each: the checker's type, the name the stage's code
# gives it, its fields' names and types
pub type GpuStructs:
	types TypeId[]
	names str[]
	fields str[,]
	members shader.Ty[,]

# a GPU function in the form: its declaration, the stage code's name of it, its vregs' types,
# its parameters' vregs in order (a part's parameter has none) and its result's type
type GpuFn:
	decl NodeId
	name str
	f IrFn
	tys shader.Ty[]
	params i64[]
	ret shader.Ty

# a program's GPU code in the form: the functions its entries reach, the entries first, and the
# type of each group memory a compute stage keeps (zapW_<name>)
type GpuProgram:
	fns GpuFn[]
	structs GpuStructs
	groupMemory {str: shader.Ty} = {}

type GpuLower:
	c Checker
	structs GpuStructs
	parts {NodeId: i64}   # the part each parameters struct is (its declaration)
	groupMemory {str: shader.Ty} = {}
	fns GpuFn[]
	todo NodeId[]   # the functions called, lowered after the one being lowered
	# the function being lowered
	fnd NodeId?
	f IrFn
	tys shader.Ty[]
	names str[]   # the names in scope, innermost last
	vals i64[]   # their vregs; partName(k) for a part's parameter
	breaks i64[]   # per open loop: the block after it
	conts i64[]   # per open loop: the block continue goes to
	doubles bool = false   # the code being lowered is a GPU file's: its f64 a double

# The GPU code the entries reach, in the form; `parts` the part of each parameters struct.
fn lowerGpuProgram(
	mut c Checker,
	entries NodeId[],
	parts {NodeId: i64}
) GpuProgram ? shader.GpuError:
	w = GpuLower(
		c = move c,
		structs = GpuStructs(types = [], names = [], fields = [], members = []),
		parts = parts.copy(),
		fns = [],
		todo = entries.copy(),
		fnd = none,
		f = newIrFn(),
		tys = [],
		names = [],
		vals = [],
		breaks = [],
		conts = []
	)
	stopped = w.glReached()
	c = move w.c   # (given back whether the lowering ended at an error or not)
	if stopped is error: return error
	GpuProgram(fns = w.fns, structs = w.structs, groupMemory = w.groupMemory)

# the functions to lower and those they call lowered: none, or the error that stopped them
fn glReached(mut w GpuLower) shader.GpuError?:
	while not w.todo.isEmpty:
		fnd = w.todo[0]
		w.todo = w.todo[1..].copy()
		if not w.fns.any(.decl == fnd):
			match w.glFunction(fnd):
				error: return error
				_: continue
	none

# the vreg value standing for part k's parameter (no vreg: its fields are read where they are)
fn partName(k i64):
	-2 - k

fn partOfName(v i64):
	-2 - v if v <= -2 else -1

# the error that stops the GPU compile at a node of the function being lowered
fn glStop(w GpuLower, e NodeId, msg str):
	n = nodes[e]
	stopAt(nodes[w.fnd ?? e].file(kidIds), n.line, n.col, msg)

# the function being lowered
fn lowered(w GpuLower):
	w.fnd ?? fail("no GPU function is being lowered")

# ---------- types ----------

# the GPU's type of the checker's type t (an error at e when it has none)
fn glTy(mut w GpuLower, maybeT TypeId?, e NodeId) shader.Ty ? shader.GpuError:
	t = w.glSeenThrough(maybeT ?? return shader.scalar(shader.bVoid))
	if tys[t].kind == tUnit: return shader.scalar(shader.bVoid)
	k = tys[t].kind
	if k == tBool: return shader.scalar(shader.bBool)
	if k == tInt:
		return shader.scalar(shader.bInt if tys[t].isSigned or tys[t].ranged else shader.bUint)
	if k == tFloat:
		return shader.Ty(..shader.scalar(shader.bFloat), wide = tys[t].bits == 64 and w.doubles)
	if k == tEnum:
		d = declOf(tys, t)
		if nodes[d].kids(kidIds).any(not nodes[it].kids(kidIds).isEmpty):
			return w.glStop(e, compileError("GpuVariantWithValues", ["{nodes[d].text2(kidIds)}", "..."]))
		return shader.scalar(shader.bInt)
	if k == tArray: return (try w.glTy(innerOf(tys, t), e)).arrayOf(tys[t].bits)
	if k == tList: return (try w.glTy(innerOf(tys, t), e)).arrayOf(0)
	if k != tStruct: return w.glStop(e, compileError("GpuType", []))
	d = declOf(tys, t)
	name = nodes[d].text2(kidIds)
	if nodes[d].mod(kidIds) == "rt":
		for n in 2..5:
			if name == "Vec{n}": return shader.vector(shader.bFloat, n)
			if name == "IVec{n}": return shader.vector(shader.bInt, n)
			if name == "UVec{n}": return shader.vector(shader.bUint, n)
			if name == "Mat{n}": return shader.matrix(n)
		if name == "Quat": return shader.vector(shader.bFloat, 4)
	if shader.samplerKinds.findIndex(.zap == name) is kind:
		return shader.Ty(base = shader.bSampler, rows = 1, cols = 1, arr = -1, sid = kind + 1)
	if w.doubles and w.glFieldTypes(t).any(holdsDouble(tys, it)):
		return w.glStop(e, compileError("GpuDoubleStored", []))
	shader.Ty(base = shader.bStruct, rows = 1, cols = 1, arr = -1, sid = try w.glStruct(t, e))

# whether t is an f64 or an array or a list of them
fn holdsDouble(ts Ty[], t TypeId) bool:
	k = ts[t].kind
	if k == tArray or k == tList: return holdsDouble(ts, innerOf(ts, t))
	k == tFloat and ts[t].bits == 64

# the sid of struct t, its fields typed when it is first met
fn glStruct(mut w GpuLower, t TypeId, e NodeId) i64 ? shader.GpuError:
	key = typeKey(tys, t)
	if w.structs.types.findIndex(typeKey(tys, it) == key) is sid: return sid
	sid = w.structs.types.len
	d = declOf(tys, t)
	w.structs.types.push(t)
	w.structs.names.push(nodes[d].text.copy())
	w.structs.fields.push(nodes[d].kids(kidIds).map(nodes[it].text.copy()))
	w.structs.members.push([])
	members = []
	# (typed as any code's, whoever meets the struct first: a GPU file's refuses one of f64s)
	doubles = w.doubles
	w.doubles = false
	for ft in w.glFieldTypes(t):
		members.push(try w.glTy(ft, e))
	w.doubles = doubles
	w.structs.members[sid] = members
	sid

# the types of struct t's fields (a tuple's parts), in their order
fn glFieldTypes(mut w GpuLower, t TypeId) TypeId[]:
	d = declOf(tys, t)
	if nodes[d].origin(kidIds) is origin and nodes[d].mod(kidIds) == "rt" and not nodes[d].ints(kidIds).isEmpty and
		nodes[origin].text2(kidIds).startsWith("Tuple"):
		return nodes[d].ints(kidIds).copy()
	w.c.enterModuleOf(d)
	w.c.fieldTypes(d)

# the field index of `name` in struct t (a vector's letter of any set)
fn glFieldIndex(mut w GpuLower, t TypeId?, move name str, e NodeId) i64 ? shader.GpuError:
	d = w.glDeclOf(t)
	if nodes[d].kids(kidIds).findIndex(nodes[it].text == name) is i: return i
	if (try w.glTy(t, e)).isVector() and name.len == 1 and shader.componentOf(name) is k: return k
	w.glStop(e, compileError("ShaderNoField", ["{nodes[d].text2(kidIds)}", "{name}"]))

fn glDeclOf(w GpuLower, t TypeId?):
	declOf(tys, w.glSeenThrough(t ?? tyError))

# t seen through its references and defined types
fn glSeenThrough(w GpuLower, t0 TypeId):
	t = t0
	while tys[t].kind == tRef or tys[t].under != none:
		t = innerOf(tys, t) if tys[t].kind == tRef else underOf(tys, t)
	t

fn glTyOfNode(mut w GpuLower, e NodeId) shader.Ty ? shader.GpuError:
	try w.glTy(nodes[e].ty, e)

# ---------- vregs and instructions ----------

fn glV(mut w GpuLower, t shader.Ty) i64:
	class = irFloat if t.base == shader.bFloat and t.isScalar()
		else irInt if t.isScalar()
		else irVec
	w.tys.push(t)
	w.f.irVreg(class)

fn glPut(mut w GpuLower, move inst IrInst):
	if not w.f.irEnded():
		w.f.irAppend(inst)

# dst = op(a, b) of type t
fn glOp(mut w GpuLower, op i64, t shader.Ty, a i64, b i64):
	v = w.glV(t)
	w.glPut(IrInst(op = u16(op), dst = v, a, b))
	v

fn glConst(mut w GpuLower, t shader.Ty, imm i64):
	v = w.glV(t)
	w.glPut(IrInst(op = irConst, dst = v, imm))
	v

fn glInt(mut w GpuLower, value i64) i64:
	w.glConst(shader.scalar(shader.bInt), value)

fn glFloat(mut w GpuLower, value f64) i64:
	w.glConst(shader.scalar(shader.bFloat), i64(value.toBits()))

fn glBool(mut w GpuLower, value bool) i64:
	w.glConst(shader.scalar(shader.bBool), 1 if value else 0)

# v as type t (the same vreg when it is already)
fn glAs(mut w GpuLower, v i64, t shader.Ty) i64:
	if v < 0 or w.tys[v].isSameTy(t): return v
	from = w.tys[v]
	if from.isScalar() and t.isScalar() and from.base == shader.bFloat and
		t.base == shader.bFloat and
		w.glConstOf(v) is imm:
		# a literal of one width as the other's (no conversion an f32's code would need f64 for)
		value = f64.fromBits(u64.wrap(imm))
		return w.glConst(t, i64(f64(f32(value)).toBits()) if t.wide and not from.wide else imm)
	w.glOp(irConvert, t, v, -1)

# the value of the constant v holds, when the block being filled set it last
fn glConstOf(w GpuLower, v i64) i64?:
	insts = w.f.blocks[w.f.cur].insts
	i = insts.len - 1
	while i >= 0:
		if insts[i].dst == v: return insts[i].imm if insts[i].op == irConst else none
		i -= 1
	none

# a part of a value: its component, column, field or element (the one taken already in this
# block, when v has not changed since)
fn glPart(mut w GpuLower, v i64, part i64, t shader.Ty):
	if w.glTakenBefore(.op == irPart and .a == v and .imm == part and .b < 0, v) is r: return r
	r = w.glV(t)
	w.glPut(IrInst(op = irPart, dst = r, a = v, imm = part))
	r

# the vreg an instruction of the block being filled that `same` picks gave its value, when the
# vreg `source` (-1 none) has not changed since, nor any memory (no write, call or barrier came
# between): a value read again is not computed again
fn glTakenBefore(w GpuLower, same fn(IrInst) bool, source i64) i64?:
	insts = w.f.blocks[w.f.cur].insts
	i = insts.len - 1
	while i >= 0:
		if same(insts[i]): return insts[i].dst
		if source >= 0 and insts[i].dst == source or
			(insts[i].op in [irStageOut, irCall, irBarrier]):
			return none
		i -= 1
	none

fn glMake(mut w GpuLower, t shader.Ty, parts i64[]):
	r = w.glV(t)
	w.glPut(IrInst(op = irMake, dst = r, part = instPartOf(parts.copy())))
	r

# a branch to yes when the bool c holds, else to no
fn glBranch(mut w GpuLower, c i64, yes i64, no i64):
	w.glPut(IrInst(op = irBranch, a = c, target = yes, other = no))

# ---------- names ----------

fn glDeclare(mut w GpuLower, name str, v i64):
	w.names.push(name.copy())
	w.vals.push(v)

fn glLookup(w GpuLower, name str) i64?:
	i = w.names.len - 1
	while i >= 0:
		if w.names[i] == name: return w.vals[i]
		i -= 1
	none

fn glScopeEnd(mut w GpuLower, mark i64):
	w.names.truncate(mark)
	w.vals.truncate(mark)

# ---------- functions ----------

# the stage code's name of a function: its global name
fn glFnName(w GpuLower, fnd NodeId):
	nodes[fnd].text.copy()

# the part a parameter of type t is (a parameters struct's), -1 for any other
fn glPartOf(w GpuLower, t TypeId):
	if tys[t].kind != tStruct: return -1
	w.parts.get(declOf(tys, t)) ?? -1

fn glParamTypes(mut w GpuLower, fnd NodeId):
	w.c.enterModuleOf(fnd)
	decls = nodes[fnd].kids(kidIds).copy()
	decls.map(w.c.resolveType(nodes[it].types(kidIds)[0]))

fn glFunction(mut w GpuLower, fnd NodeId) ? shader.GpuError:
	if not nodes[fnd].names(kidIds).isEmpty or nodes[fnd].sub(kidIds).isEmpty or nodes[fnd].hasFlag(flagExtern):
		return w.glStop(fnd, compileError("GpuCall", []))
	w.fnd = fnd
	w.doubles = nodes[fnd].hasFlag(flagGpu)
	w.f = newIrFn()
	w.tys = []
	w.names = []
	w.vals = []
	w.breaks = []
	w.conts = []
	types = w.glParamTypes(fnd)
	params = []
	decls = nodes[fnd].kids(kidIds).copy()
	for i, p in decls:
		k = w.glPartOf(types[i])
		if nodes[p].ival == modeMut and k < 0:
			return w.glStop(p, compileError("GpuMutParameter", ["{nodes[p].text}"]))
		if k >= 0:
			w.glDeclare(nodes[p].text, partName(k))
			continue
		v = w.glV(try w.glTy(types[i], p))
		w.glPut(IrInst(op = irParam, dst = v, imm = params.len))
		params.push(v)
		w.glDeclare(nodes[p].text, v)
	w.c.enterModuleOf(fnd)
	rt = w.c.fnRetType(fnd)
	ret = try w.glTy(rt, fnd)
	w.c.readBody(fnd)
	value = try w.glBlock(nodes[fnd].sub(kidIds)[0])
	if not w.f.irEnded():
		w.glPut(IrInst(op = irRet, a = -1 if ret.base == shader.bVoid else w.glAs(value, ret)))
	w.f.irPrune()
	w.fns.push(
		GpuFn(
			decl = fnd,
			name = w.glFnName(fnd),
			f = move w.f,
			tys = move w.tys,
			params,
			ret
		)
	)
	w.f = newIrFn()

# ---------- statements ----------
