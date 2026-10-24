# SPIR-V of one stage of a program from its GPU functions in the intermediate form (irgpu.zap):
# the functions its entry reaches, each vreg given one id when one instruction gives it its
# value and a Function variable otherwise (a value a loop, a branch or an in-place change
# changes), its blocks in an order where each comes after those that lead to it, and each branch
# and loop given its merge (IrFn.merges). The stage's variables are those of its layout (the
# inputs and outputs, shader.StageLayout) and of what its code reads (irStageIn: the parameter
# block's members at their std140 offsets, the textures and texture arrays at their bindings, the
# storage buffers at bufferBase + theirs); its entry point, `main`, reads the inputs, calls the
# entry, writes what it gives, and a vertex stage's then maps its depth from the engine's -1..1
# (its projection matrices') to Vulkan's 0..1.

import shader

# a variable of the stage: its pointer, its value's type, its storage class, its member of the
# parameter block (-1 none)
type SpvVar:
	ptr i64
	ty shader.Ty
	storage i64
	member i64 = -1

type SpvWriter:
	m shader.Module
	structs shader.Ty[,]
	stage i64
	vars {str: SpvVar}   # the stage's variables, by name
	interface i64[]
	fnIds {str: i64}
	imageQuery bool = false
	runtimeArrays bool = false
	capabilities i64[] = []   # the lane operations' (GroupNonUniform...)
	nonUniform i64[] = []   # the pointers and images reached through an index the stage computes
	# the function being written
	tys shader.Ty[]
	ids i64[]   # each vreg's value, when one instruction gives it
	ptrs i64[]   # each other vreg's variable
	consts bool[] = []   # whether irConst gives each vreg its value (one every invocation shares)
	body u32[]
	locals u32[]

# the SPIR-V words of the stage laid out by `s`, its entry the function named `entry`
fn spirvStage(
	prog GpuProgram,
	s shader.StageLayout,
	l shader.Lowering,
	entry str,
	groupSize i64[]
):
	w = SpvWriter(
		m = shader.newModule(),
		structs = prog.structs.members.copy(),
		stage = s.stage,
		vars = {},
		interface = [],
		fnIds = {},
		tys = [],
		ids = [],
		ptrs = [],
		body = [],
		locals = []
	)
	fns = prog.reachedFns(entry)
	w.spvDeclareInterface(s, l)
	w.spvDeclareReads(prog, fns, l)
	for f in fns:
		w.fnIds[prog.fns[f].name.copy()] = w.m.newId()
	for f in fns:
		w.spvFunction(prog.fns[f])
	main = w.spvMain(prog, s, entry)
	emit(w.m.capabilities, shader.opCapability, [1])   # Shader
	if w.imageQuery:
		emit(w.m.capabilities, shader.opCapability, [shader.capImageQuery])
	# descriptor indexing (core in SPIR-V 1.5: no extension to name)
	if w.runtimeArrays:
		emit(w.m.capabilities, shader.opCapability, [shader.capRuntimeDescriptorArray])
	if not w.nonUniform.isEmpty:
		emit(w.m.capabilities, shader.opCapability, [shader.capShaderNonUniform])
		emit(w.m.capabilities, shader.opCapability, [shader.capSampledImageArrayNonUniformIndexing])
	for capability in w.capabilities:
		emit(w.m.capabilities, shader.opCapability, [capability])
	# Vertex, Fragment, GLCompute
	model = [0, 4, 5][s.stage]
	shader.emitWithString(w.m.entries, shader.opEntryPoint, [model, main], "main", w.interface)
	if s.stage == shader.stageFragment:
		emit(w.m.modes, shader.opExecutionMode, [main, 7])   # OriginUpperLeft
		if s.vars.any(.name == shader.depthOutput):
			emit(w.m.modes, shader.opExecutionMode, [main, 12])   # DepthReplacing
	if s.stage == shader.stageCompute:
		emit(   # LocalSize
			w.m.modes,
			shader.opExecutionMode,
			[main, 17, groupSize[0], groupSize[1], groupSize[2]]
		)
	w.m.moduleWords()

fn emit(mut out u32[], op i64, operands i64[]):
	shader.emit(out, op, operands)

# ---------- types ----------

# the SPIR-V type of t (laid: as in a block, with its strides and offsets; 1 std140 for the
# parameter block, 2 std430 for a storage buffer)
fn spvType(mut w SpvWriter, t shader.Ty, laid i64 = 0) i64:
	if t.arr >= 0:
		e = w.spvType(t.elemOf(), laid)
		key = "a{t.arr}:{e}:{laid}"
		if w.m.made.get(key) is id: return id
		id = 0
		if t.arr == 0:
			id = w.m.typeOf(key, shader.opTypeRuntimeArray, [e])
		else:
			id = w.m.typeOf(key, shader.opTypeArray, [e, w.spvInt(t.arr)])
		if laid > 0:
			w.m.decorate(id, [shader.decArrayStride, t.strideOf(laid == 1, w.structs)])
		return id
	if t.base == shader.bVoid: return w.m.typeOf("void", shader.opTypeVoid, [])
	if t.base == shader.bStruct: return w.spvStructType(t.sid, laid)
	if t.base == shader.bSampler:
		return w.m.typeOf("si:{t.sid}", shader.opTypeSampledImage, [w.spvImageType(t.sid)])
	if t.cols > 1:
		column = w.spvType(shader.vector(shader.bFloat, t.rows))
		return w.m.typeOf("m{t.cols}x{t.rows}", shader.opTypeMatrix, [column, t.cols])
	if t.rows > 1:
		c = w.spvType(shader.scalar(t.base))
		return w.m.typeOf("v{t.rows}:{t.base}", shader.opTypeVector, [c, t.rows])
	if t.base == shader.bBool: return w.m.typeOf("bool", shader.opTypeBool, [])
	if t.base == shader.bInt: return w.m.typeOf("i32", shader.opTypeInt, [32, 1])
	if t.base == shader.bUint: return w.m.typeOf("u32", shader.opTypeInt, [32, 0])
	w.m.typeOf("f32", shader.opTypeFloat, [32])

# the image a sampler of the kind reads (2D, an array of 2D layers, depth for comparisons)
fn spvImageType(mut w SpvWriter, kind i64) i64:
	f = w.spvType(shader.scalar(shader.bFloat))
	depth = 1 if shader.isShadow(kind) else 0
	arrayed = 1 if shader.isLayered(kind) else 0
	w.m.typeOf("img:{kind}", shader.opTypeImage, [f, 1, depth, arrayed, 0, 1, 0])

fn spvStructType(mut w SpvWriter, sid i64, laid i64):
	key = "s:{sid}:{laid}"
	if w.m.made.get(key) is id: return id
	types = w.structs[sid].copy()
	members = types.map(w.spvType(it, laid))
	id = w.m.typeOf(key, shader.opTypeStruct, members)
	if laid > 0:
		for i, offset in shader.offsetsOf(types, laid == 1, w.structs):
			w.m.decorateMember(id, i, [shader.decOffset, offset])
			if types[i].elemOf().isMatrix() or types[i].isMatrix():
				w.m.decorateMember(id, i, [shader.decColMajor])
				w.m.decorateMember(id, i, [shader.decMatrixStride, 16])
	id

fn spvPtrType(mut w SpvWriter, t shader.Ty, storage i64) i64:
	laid = 1 if storage == shader.scUniform else 2 if storage == shader.scStorageBuffer else 0
	w.spvPtrToId(w.spvType(t, laid), storage)

fn spvPtrToId(mut w SpvWriter, inner i64, storage i64) i64:
	w.m.typeOf("p{storage}:{inner}", shader.opTypePointer, [storage, inner])

# ---------- constants ----------

fn spvInt(mut w SpvWriter, v i64) i64:
	w.m.constantOf(w.spvType(shader.scalar(shader.bInt)), [v & 0xFFFF_FFFF])

fn spvUint(mut w SpvWriter, v i64) i64:
	w.m.constantOf(w.spvType(shader.scalar(shader.bUint)), [v & 0xFFFF_FFFF])

fn spvFloat(mut w SpvWriter, v f64) i64:
	w.m.constantOf(w.spvType(shader.scalar(shader.bFloat)), [shader.f32Bits(v)])

fn spvBool(mut w SpvWriter, v bool):
	t = w.spvType(shader.scalar(shader.bBool))
	key = "true" if v else "false"
	if w.m.made.get(key) is id: return id
	id = w.m.newId()
	emit(w.m.globals, shader.opConstantTrue if v else shader.opConstantFalse, [t, id])
	w.m.made[key] = id
	id

# irConst's value of type t: a number (a float's imm its f64's bits), a bool, an aggregate's zero
fn spvConstOf(mut w SpvWriter, t shader.Ty, imm i64):
	if t.isScalar():
		if t.base == shader.bFloat: return w.spvFloat(f64.fromBits(u64.wrap(imm)))
		if t.base == shader.bBool: return w.spvBool(imm != 0)
		if t.base == shader.bUint: return w.spvUint(imm)
		return w.spvInt(imm)
	tid = w.spvType(t)
	key = "null:{tid}"
	if w.m.made.get(key) is id: return id
	id = w.m.newId()
	emit(w.m.globals, shader.opConstantNull, [tid, id])
	w.m.made[key] = id
	id

# ---------- instructions ----------

# an instruction with a result of type t: its new id
fn spvVal(mut w SpvWriter, op i64, t shader.Ty, operands i64[]) i64:
	tid = w.spvType(t)
	w.spvValId(op, tid, operands)

fn spvValId(mut w SpvWriter, op i64, tid i64, operands i64[]):
	id = w.m.newId()
	ops = [tid, id]
	ops.extend(operands)
	emit(w.body, op, ops)
	id

fn spvIns(mut w SpvWriter, op i64, operands i64[]):
	emit(w.body, op, operands)

# an instruction of the extended set every SPIR-V shader imports (std450)
fn spvExt(mut w SpvWriter, t shader.Ty, instr i64, args i64[]) i64:
	ops = [w.m.std450, instr]
	ops.extend(args)
	w.spvVal(shader.opExtInst, t, ops)

# a variable of the function being written
fn spvLocalVar(mut w SpvWriter, t shader.Ty):
	id = w.m.newId()
	emit(w.locals, shader.opVariable, [w.spvPtrType(t, shader.scFunction), id, shader.scFunction])
	id

# a variable of the module, of the storage class, one of the entry point's interface
fn spvGlobalVar(mut w SpvWriter, t shader.Ty, storage i64):
	id = w.m.newId()
	emit(w.m.globals, shader.opVariable, [w.spvPtrType(t, storage), id, storage])
	w.interface.push(id)
	id

# ---------- the stage's variables ----------

# the stage's interface: the clip position (a vertex stage's), the vertex's and the instance's
# numbers, a pixel stage's depth, and the layout's inputs and outputs at their locations (a value passed on at its
# place among them, an integer not interpolated)
fn spvDeclareInterface(mut w SpvWriter, s shader.StageLayout, l shader.Lowering):
	int = shader.scalar(shader.bInt)
	if s.stage == shader.stageVertex:
		w.spvBuiltinVar("zapPosition", shader.vector(shader.bFloat, 4), shader.scOutput, 0)   # Position
		w.spvBuiltinVar("zapVertexIndex", int, shader.scInput, 42)   # VertexIndex
		w.spvBuiltinVar("zapInstanceIndex", int, shader.scInput, 43)   # InstanceIndex
	for v in s.vars:
		t = shader.tyOfName(v.tname, []) ?? fail("shader: a variable of type {v.tname}")
		if v.name == shader.depthOutput:
			w.spvBuiltinVar(v.name, t, shader.scOutput, 22)   # FragDepth
			continue
		storage = shader.scInput if v.qual == shader.qIn else shader.scOutput
		ptr = w.spvGlobalVar(t, storage)
		passed = v.name.startsWith("zapB")
		location = (l.between.findIndex(passedName(.name) == v.name) ?? 0) if passed else v.location
		if passed and v.flat:
			w.m.decorate(ptr, [shader.decFlat])
		w.m.decorate(ptr, [shader.decLocation, location])
		w.m.debugName(ptr, v.name)
		w.vars[v.name.copy()] = SpvVar(ptr, ty = t, storage)

# the values the GPU gives a stage's code (gpucheck.zap's gpuValues) and their SPIR-V BuiltIns
spvValues = [
	("pixelPosition", 15),   # FragCoord
	("globalId", 28),   # GlobalInvocationId
	("localId", 27),   # LocalInvocationId
	("groupId", 26),   # WorkgroupId
	("localIndex", 29),   # LocalInvocationIndex
	("lane", 41),   # SubgroupLocalInvocationId
	("laneCount", 36)   # SubgroupSize
]

# a capability the stage declares (once)
fn spvNeed(mut w SpvWriter, capability i64):
	if capability not in w.capabilities:
		w.capabilities.push(capability)

# a value the GPU gives or takes (its SPIR-V BuiltIn)
fn spvBuiltinVar(mut w SpvWriter, name str, t shader.Ty, storage i64, builtin i64):
	ptr = w.spvGlobalVar(t, storage)
	w.m.decorate(ptr, [shader.decBuiltIn, builtin])
	w.vars[name.copy()] = SpvVar(ptr, ty = t, storage)

# What the stage's code reads (irStageIn): the pixel's position, the parameters it reads as the
# members of the std140 block at binding paramsBinding (each at its offset, in the parameters'
# order), the textures and texture arrays (set textureArraySet) at their bindings, the storage
# buffers at bufferBase + theirs.
fn spvDeclareReads(mut w SpvWriter, prog GpuProgram, fns i64[], l shader.Lowering):
	read = prog.stageReads(fns, l)
	for (name, builtin) in spvValues:
		if read.get(name) is t:
			w.spvBuiltinVar(name, t, shader.scInput, builtin)
			if name == "lane" or name == "laneCount":
				w.spvNeed(shader.capGroupNonUniform)
	for name in read.keys().sorted():
		t = read[name]
		if name.startsWith("zapW_"):
			ptr = w.spvGlobalVar(t, shader.scWorkgroup)
			w.m.debugName(ptr, name)
			w.vars[name.copy()] = SpvVar(ptr, ty = t, storage = shader.scWorkgroup)
	params = l.params.filter(.name in read)
	if not params.isEmpty:
		types = params.map(shader.storedTy(read[.name]))
		members = types.map(w.spvType(it, 1))
		sid = w.m.typeOf("params", shader.opTypeStruct, members)
		w.m.decorate(sid, [shader.decBlock])
		for i, p in params:
			w.m.decorateMember(sid, i, [shader.decOffset, p.offset])
			if types[i].elemOf().isMatrix() or types[i].isMatrix():
				w.m.decorateMember(sid, i, [shader.decColMajor])
				w.m.decorateMember(sid, i, [shader.decMatrixStride, 16])
			shader.emitWithString(w.m.names, shader.opMemberName, [sid, i], p.name, [])
		v = w.m.newId()
		emit(
			w.m.globals,
			shader.opVariable,
			[w.spvPtrToId(sid, shader.scUniform), v, shader.scUniform]
		)
		w.interface.push(v)
		w.m.decorate(v, [shader.decDescriptorSet, 0])
		w.m.decorate(v, [shader.decBinding, shader.paramsBinding])
		for i, p in params:
			w.vars[p.name.copy()] = SpvVar(
				ptr = v,
				ty = types[i],
				storage = shader.scUniform,
				member = i
			)
	for r in l.resources:
		t = read.get(r.name) ?? continue
		if r.kind == shader.resBuffer:
			# a block of one member: the runtime array of the elements (std430)
			sid = w.m.typeOf("buffer:{r.name}", shader.opTypeStruct, [w.spvType(t, 2)])
			w.m.decorate(sid, [shader.decBlock])
			w.m.decorateMember(sid, 0, [shader.decOffset, 0])
			v = w.m.newId()
			emit(
				w.m.globals,
				shader.opVariable,
				[w.spvPtrToId(sid, shader.scStorageBuffer), v, shader.scStorageBuffer]
			)
			w.interface.push(v)
			w.m.decorate(v, [shader.decDescriptorSet, 0])
			w.m.decorate(v, [shader.decBinding, shader.bufferBase + r.binding])
			w.vars[r.name.copy()] = SpvVar(
				ptr = v,
				ty = t,
				storage = shader.scStorageBuffer,
				member = 0
			)
			continue
		v = w.spvGlobalVar(t, shader.scUniformConstant)
		# a texture array is a table of descriptors of its own: set 1 (bound once, updated while
		# in use), the other bindings set 0
		w.m.decorate(
			v,
			[shader.decDescriptorSet, shader.textureArraySet if r.kind == shader.resArray else 0]
		)
		w.m.decorate(v, [shader.decBinding, r.binding])
		if t.arr == 0:
			w.runtimeArrays = true
		w.m.debugName(v, r.name)
		w.vars[r.name.copy()] = SpvVar(ptr = v, ty = t, storage = shader.scUniformConstant)

# ---------- functions ----------

fn spvFnType(mut w SpvWriter, ret shader.Ty, params shader.Ty[]) i64:
	r = w.spvType(ret)
	ops = [r]
	key = "fn:{r}"
	for p in params:
		pid = w.spvParamType(p)
		ops.push(pid)
		key += ":{pid}"
	w.m.typeOf(key, shader.opTypeFunction, ops)

# a parameter's SPIR-V type: its value's, or for a texture a pointer to its variable (an image is
# never copied: it is reached where it is declared)
fn spvParamType(mut w SpvWriter, t shader.Ty) i64:
	w.spvPtrType(t, shader.scUniformConstant) if t.base == shader.bSampler else w.spvType(t)

# A function: each vreg one instruction gives its value to an id, each other a variable; its
# blocks each led by its label, its merges before its branches.
fn spvFunction(mut w SpvWriter, g GpuFn):
	f = g.f
	w.tys = g.tys.copy()
	w.ids = fill(w.tys.len, -1)
	w.ptrs = fill(w.tys.len, -1)
	w.body = []
	w.locals = []
	defs = f.spvVregDefs(w.tys.len)
	w.consts = zeros(w.tys.len)
	for b in f.blocks:
		for inst in b.insts:
			if inst.op == irConst:
				w.consts[inst.dst] = defs[inst.dst] == 1
	for v in 0..w.tys.len:
		if defs[v] > 1:
			if w.tys[v].base == shader.bSampler:
				fail("shader: a texture is given in one place ({g.name})")
			w.ptrs[v] = w.spvLocalVar(w.tys[v])
	id = w.fnIds[g.name]
	params = g.params.map(w.tys[it])
	emit(w.m.functions, shader.opFunction, [w.spvType(g.ret), id, 0, w.spvFnType(g.ret, params)])
	w.m.debugName(id, g.name)
	for v in g.params:
		pid = w.m.newId()
		emit(w.m.functions, shader.opFunctionParameter, [w.spvParamType(w.tys[v]), pid])
		if w.ptrs[v] >= 0:
			w.spvIns(shader.opStore, [w.ptrs[v], pid])
		else:
			w.ids[v] = pid
	labels = []
	loop f.blocks.len:
		labels.push(w.m.newId())
	order = f.spvBlockOrder()
	first = labels[order[0]]
	for bi, b in order:
		if bi > 0:
			w.spvIns(shader.opLabel, [labels[b]])
		w.spvBlock(f, b, labels, g.ret)
	w.spvFinishFunction(first)

# how many instructions give each vreg its value (a parameter's counted)
fn spvVregDefs(f IrFn, count i64):
	defs = zeros(count)
	for b in f.blocks:
		for inst in b.insts:
			if inst.dst >= 0:
				defs[inst.dst] += 1
	defs

# the blocks reached from the first, each after every block leading to it but those of a back
# edge (reverse postorder), then those never reached
fn spvBlockOrder(f IrFn):
	seen = fill(f.blocks.len, false)
	post = []
	stack = [(0, 0)]
	seen[0] = true
	while not stack.isEmpty:
		b, next = stack[len - 1]
		succ = f.spvBlockSuccessors(b)
		if next < succ.len:
			stack[len - 1] = b, next + 1
			s = succ[next]
			if not seen[s]:
				seen[s] = true
				stack.push((s, 0))
		else:
			post.push(b)
			stack.pop()
	out = post.reversed()
	for b in 0..f.blocks.len:
		if not seen[b]:
			out.push(b)
	out

fn spvBlockSuccessors(f IrFn, b i64):
	insts = f.blocks[b].insts
	if insts.isEmpty: return []
	insts[len - 1].irSuccessors()

# the function's first block (its variables first), then the rest of its code
fn spvFinishFunction(mut w SpvWriter, first i64):
	emit(w.m.functions, shader.opLabel, [first])
	w.m.functions.extend(w.locals)
	w.m.functions.extend(w.body)
	emit(w.m.functions, shader.opFunctionEnd, [])

# a vreg's value: its id, or its variable's value now
fn spvGet(mut w SpvWriter, v i64):
	if w.ptrs[v] >= 0: return w.spvVal(shader.opLoad, w.tys[v], [w.ptrs[v]])
	if w.ids[v] < 0:
		fail("shader: a value read before it is given (vreg {v})")
	w.ids[v]

# vreg v given the value id
fn spvPut(mut w SpvWriter, v i64, id i64):
	if w.ptrs[v] >= 0:
		w.spvIns(shader.opStore, [w.ptrs[v], id])
	else:
		w.ids[v] = id

# a block's instructions, its merge right before its branch; a block that does not end,
# unreachable
fn spvBlock(mut w SpvWriter, f IrFn, b i64, labels i64[], ret shader.Ty):
	insts = f.blocks[b].insts.copy()
	for inst in insts:
		if not isTerminator(inst.op):
			w.spvInst(inst)
			continue
		value = w.spvGet(inst.a) if inst.a >= 0 else -1   # the branch's condition, the result
		if f.merges.find(.header == b) is merge:
			if merge.cont >= 0:
				w.spvIns(shader.opLoopMerge, [labels[merge.merge], labels[merge.cont], 0])
			else:
				w.spvIns(shader.opSelectionMerge, [labels[merge.merge], 0])
		if inst.op == irJmp:
			w.spvIns(shader.opBranch, [labels[inst.target]])
		elif inst.op == irBranch:
			w.spvIns(shader.opBranchConditional, [value, labels[inst.target], labels[inst.other]])
		elif inst.op == irDiscard:
			w.spvIns(shader.opKill, [])
		elif value >= 0:
			w.spvIns(shader.opReturnValue, [value])
		else:
			w.spvIns(shader.opReturn if ret.base == shader.bVoid else shader.opUnreachable, [])
		return
	w.spvIns(shader.opUnreachable, [])

fn spvInst(mut w SpvWriter, inst IrInst):
	op = inst.op
	if op == irParam: return
	t = w.tys[inst.dst] if inst.dst >= 0 else shader.scalar(shader.bVoid)
	if op == irConst:
		w.spvPut(inst.dst, w.spvConstOf(t, inst.imm))
	elif op == irCopy:
		w.spvPut(inst.dst, w.spvGet(inst.a))
	elif op == irSet:
		w.spvPut(inst.dst, w.spvCompare(inst.cond, inst.a, inst.b))
	elif op == irNot:
		code = shader.opLogicalNot if t.base == shader.bBool else shader.opNot
		w.spvPut(inst.dst, w.spvVal(code, t, [w.spvGet(inst.a)]))
	elif op == irNeg or op == irFNeg:
		code = shader.opFNegate if t.base == shader.bFloat else shader.opSNegate
		w.spvPut(inst.dst, w.spvVal(code, t, [w.spvGet(inst.a)]))
	elif op == irConvert:
		w.spvPut(inst.dst, w.spvConvert(w.spvGet(inst.a), w.tys[inst.a], t))
	elif op == irFloatBits or op == irBitsToFloat:
		w.spvPut(inst.dst, w.spvVal(shader.opBitcast, t, [w.spvGet(inst.a)]))
	elif op == irMake:
		w.spvPut(inst.dst, w.spvVal(shader.opCompositeConstruct, t, inst.args.map(w.spvGet(it))))
	elif op == irPart:
		w.spvPut(inst.dst, w.spvPart(inst, t))
	elif op == irSetPart:
		w.spvSetPart(inst)
	elif op == irSwizzle:
		w.spvPut(inst.dst, w.spvSwizzle(w.spvGet(inst.a), w.tys[inst.a], t, inst.key))
	elif op == irMatMul:
		w.spvPut(inst.dst, w.spvProduct(t, inst.a, inst.b))
	elif op == irBuiltin:
		w.spvPut(inst.dst, w.spvBuiltin(inst.key, t, inst.args))
	elif op == irTexture:
		w.spvPut(inst.dst, w.spvTexture(inst, t))
	elif op == irStageIn:
		w.spvPut(inst.dst, w.spvStageIn(inst, t))
	elif op == irStageOut:
		w.spvStageOut(inst)
	elif op == irBarrier:
		# the group's invocations meet, their group memory's writes seen (Workgroup scope,
		# AcquireRelease | WorkgroupMemory)
		scope = w.spvUint(2)
		w.spvIns(shader.opControlBarrier, [scope, scope, w.spvUint(0x108)])
	elif op == irCall:
		args = inst.args.map(w.spvGet(it))
		ops = [w.fnIds[inst.key]]
		ops.extend(args)
		id = w.spvVal(shader.opFunctionCall, t, ops)
		if inst.dst >= 0:
			w.spvPut(inst.dst, id)
	else:
		w.spvPut(inst.dst, w.spvArith(op, t, inst.a, inst.b, inst.uns))

# ---------- values ----------

# a comparison of vregs a and b (of one type), a bool: cond irEq..irGe
fn spvCompare(mut w SpvWriter, cond i64, a i64, b i64) i64:
	base = w.tys[a].base
	# ==, !=, <, <=, >, >= (the IR's conditions' order)
	codes = [shader.opLogicalEqual, shader.opLogicalNotEqual] if base == shader.bBool
		else [
			shader.opFOrdEqual,
			shader.opFOrdNotEqual,
			shader.opFOrdLessThan,
			shader.opFOrdLessThanEqual,
			shader.opFOrdGreaterThan,
			shader.opFOrdGreaterThanEqual
		] if base ==
			shader.bFloat
		else [
			shader.opIEqual,
			shader.opINotEqual,
			shader.opSLessThan,
			shader.opSLessThanEqual,
			shader.opSGreaterThan,
			shader.opSGreaterThanEqual
		] if base ==
			shader.bInt
		else [
			shader.opIEqual,
			shader.opINotEqual,
			shader.opULessThan,
			shader.opULessThanEqual,
			shader.opUGreaterThan,
			shader.opUGreaterThanEqual
		]
	w.spvVal(codes[cond], shader.scalar(shader.bBool), [w.spvGet(a), w.spvGet(b)])

# value v of type from as type t: numbers converted component by component, a scalar spread
# over a vector, a bool from a number (whether it is not zero) and a number from a bool (1 or 0)
fn spvConvert(mut w SpvWriter, v i64, from shader.Ty, t shader.Ty) i64:
	if from.isSameTy(t): return v
	if t.base == shader.bBool and from.base != shader.bBool:
		zero = w.spvConvert(w.spvInt(0), shader.scalar(shader.bInt), from)
		code = shader.opFOrdNotEqual if from.base == shader.bFloat else shader.opINotEqual
		return w.spvVal(code, t, [v, zero])
	if from.base == shader.bBool and t.base != shader.bBool:
		one = w.spvConvert(w.spvInt(1), shader.scalar(shader.bInt), t)
		zero = w.spvConvert(w.spvInt(0), shader.scalar(shader.bInt), t)
		return w.spvVal(shader.opSelect, t, [v, one, zero])
	if from.isScalar() and t.isVector():
		return w.spvSplat(
			w.spvConvert(v, from, shader.scalar(t.base)),
			shader.scalar(t.base),
			t.rows
		)
	if not from.isNumeric() or not t.isNumeric() or from.rows != t.rows or from.cols != t.cols:
		fail("shader: cannot convert {from.tyText()} to {t.tyText()} (irgpu.zap lets no such conversion through)")
	op = shader.opBitcast
	if t.base == shader.bFloat:
		op = shader.opConvertSToF if from.base == shader.bInt else shader.opConvertUToF
	elif from.base == shader.bFloat:
		op = shader.opConvertFToS if t.base == shader.bInt else shader.opConvertFToU
	w.spvVal(op, t, [v])

fn spvSplat(mut w SpvWriter, v i64, t shader.Ty, n i64) i64:
	if n == 1: return v
	w.spvVal(shader.opCompositeConstruct, t.withRows(n), fill(n, v))

# part imm (or the part at index b) of vreg a: an index computed into an array or a matrix reads
# through a pointer (the vreg's variable, or one it is put in)
fn spvPart(mut w SpvWriter, inst IrInst, t shader.Ty) i64:
	at = w.tys[inst.a]
	if inst.b < 0: return w.spvVal(shader.opCompositeExtract, t, [w.spvGet(inst.a), inst.imm])
	i = w.spvGet(inst.b)
	if at.isVector(): return w.spvVal(shader.opVectorExtractDynamic, t, [w.spvGet(inst.a), i])
	ptr = w.ptrs[inst.a]
	if ptr < 0:
		ptr = w.spvLocalVar(at)
		w.spvIns(shader.opStore, [ptr, w.spvGet(inst.a)])
	p = w.spvValId(shader.opAccessChain, w.spvPtrType(t, shader.scFunction), [ptr, i])
	w.spvVal(shader.opLoad, t, [p])

# part imm (or the part at index b) of vreg a's variable given c's value
fn spvSetPart(mut w SpvWriter, inst IrInst):
	at = w.tys[inst.a]
	ct = w.tys[inst.c]
	index = w.spvGet(inst.b) if inst.b >= 0 else w.spvInt(inst.imm)
	p = w.spvValId(
		shader.opAccessChain,
		w.spvPtrType(ct, shader.scFunction),
		[w.ptrs[inst.a], index]
	)
	_ = at
	w.spvIns(shader.opStore, [p, w.spvGet(inst.c)])

# the components of vector v named by letters (x y z w), or scalar v repeated
fn spvSwizzle(mut w SpvWriter, v i64, from shader.Ty, t shader.Ty, letters str) i64:
	if from.isScalar(): return w.spvSplat(v, from, t.rows)
	comps = (0..letters.len).map(shader.componentOf(letters[it..it + 1]) ?? 0)
	if comps.len == 1: return w.spvVal(shader.opCompositeExtract, t, [v, comps[0]])
	ops = [v, v]
	ops.extend(comps)
	w.spvVal(shader.opVectorShuffle, t, ops)

# + - * / % and the bitwise operations of vregs a and b giving t: a matrix element by element
# (with a matrix or a number) or by a number, a float vector by a number, a number spread over
# the other's vector, a shift's count as an integer of the shifted value's shape
fn spvArith(mut w SpvWriter, op i64, t shader.Ty, a i64, b i64, uns bool) i64:
	ta = w.tys[a]
	tb = w.tys[b]
	if ta.isMatrix() or tb.isMatrix():
		if op == irFMul and (ta.isScalar() or tb.isScalar()):
			m = a if ta.isMatrix() else b
			k = b if ta.isMatrix() else a
			return w.spvVal(shader.opMatrixTimesScalar, t, [w.spvGet(m), w.spvGet(k)])
		return w.spvMatrixElementwise(op, t, a, b)
	if op == irShl or op == irShr:
		count = w.spvConvert(w.spvGet(b), tb, shader.scalar(tb.base).withRows(ta.rows))
		code = shader.opShiftLeftLogical if op == irShl
			else shader.opShiftRightLogical if ta.base == shader.bUint
			else shader.opShiftRightArithmetic
		return w.spvVal(code, t, [w.spvGet(a), count])
	if op == irFMul and t.isVector() and (ta.isScalar() or tb.isScalar()):
		vec = b if ta.isScalar() else a
		k = a if ta.isScalar() else b
		return w.spvVal(shader.opVectorTimesScalar, t, [w.spvGet(vec), w.spvGet(k)])
	ca = w.spvConvert(w.spvGet(a), ta, t)
	cb = w.spvConvert(w.spvGet(b), tb, t)
	w.spvVal(spvArithCode(op, t.base), t, [ca, cb])

# the SPIR-V operation of an arithmetic or bitwise operation on numbers (or bools) of `base`
fn spvArithCode(op i64, base i64):
	f = base == shader.bFloat
	u = base == shader.bUint
	if op == irFAdd or op == irAdd: return shader.opFAdd if f else shader.opIAdd
	if op == irFSub or op == irSub: return shader.opFSub if f else shader.opISub
	if op == irFMul or op == irMul: return shader.opFMul if f else shader.opIMul
	if op == irFDiv or
		op == irDiv: return shader.opFDiv if f else shader.opUDiv if u else shader.opSDiv
	if op == irRem: return shader.opFRem if f else shader.opUMod if u else shader.opSRem
	if op == irAnd: return shader.opLogicalAnd if base == shader.bBool else shader.opBitwiseAnd
	if op == irOr: return shader.opLogicalOr if base == shader.bBool else shader.opBitwiseOr
	shader.opLogicalNotEqual if base == shader.bBool else shader.opBitwiseXor

# + - * / of a matrix element by element with a matrix or a number: column by column
fn spvMatrixElementwise(mut w SpvWriter, op i64, t shader.Ty, a i64, b i64) i64:
	column = t.elemOf()
	code = spvArithCode(op, shader.bFloat)
	ida = w.spvGet(a)
	idb = w.spvGet(b)
	columns = (0..t.cols).map(i:
		w.spvVal(
			code,
			column,
			[w.spvColumnOf(ida, w.tys[a], column, i), w.spvColumnOf(idb, w.tys[b], column, i)]
		)
	)
	w.spvVal(shader.opCompositeConstruct, t, columns)

# column i of a matrix value, or a number spread over a column
fn spvColumnOf(mut w SpvWriter, v i64, vt shader.Ty, column shader.Ty, i i64) i64:
	w.spvVal(shader.opCompositeExtract, column, [v, i]) if vt.isMatrix()
		else w.spvConvert(v, vt, column)

# a @ b giving t: matrix by matrix, matrix by vector, vector by matrix, or two vectors' dot
# product (two numbers' product)
fn spvProduct(mut w SpvWriter, t shader.Ty, a i64, b i64) i64:
	ta = w.tys[a]
	tb = w.tys[b]
	ida = w.spvGet(a)
	idb = w.spvGet(b)
	if ta.isMatrix() and tb.isMatrix(): return w.spvVal(shader.opMatrixTimesMatrix, t, [ida, idb])
	if ta.isMatrix(): return w.spvVal(shader.opMatrixTimesVector, t, [ida, idb])
	if tb.isMatrix(): return w.spvVal(shader.opVectorTimesMatrix, t, [ida, idb])
	if ta.isScalar(): return w.spvVal(shader.opFMul, t, [ida, idb])
	w.spvVal(shader.opDot, t, [ida, idb])

# a built-in function (shader.builtinFunctions), its arguments in its order, or an operation
# across the lanes (shader.laneFunctions: GroupNonUniform, the Subgroup scope)
fn spvBuiltin(mut w SpvWriter, name str, t shader.Ty, args i64[]) i64:
	if shader.laneFunctions.find(.zap == name) is lane:
		w.spvNeed(shader.capGroupNonUniform)
		w.spvNeed(lane.capability)
		vt = w.tys[args[0]]
		code = lane.spirv[0 if vt.base == shader.bFloat else 2 if vt.base == shader.bUint else 1]
		ops = [w.spvUint(3)]   # Subgroup
		if lane.operation >= 0:
			ops.push(lane.operation)
		ops.extend(args.map(w.spvGet(it)))
		return w.spvVal(code, t, ops)
	f = shader.builtinFunctions.find(.zap == name) ?? fail("shader: no built-in {name}")
	ops = f.order.map(w.spvGet(args[it]))
	if name == "ddx": return w.spvVal(shader.opDPdx, t, ops)
	if name == "ddy": return w.spvVal(shader.opDPdy, t, ops)
	if name == "fwidth": return w.spvVal(shader.opFwidth, t, ops)
	if name == "transpose": return w.spvVal(shader.opTranspose, t, ops)
	w.spvExt(t, spvStd450Of(f, t), ops)

# a built-in's instruction of the extended set for a result of type t: min, max and clamp have
# one for floats, uints and ints, in that order; abs and sign one for floats, then one for ints
fn spvStd450Of(f shader.Builtin, t shader.Ty):
	if f.zap == "abs" or
		f.zap == "sign": return f.std450 if t.base == shader.bFloat else f.std450 + 1
	if f.zap in ["min", "max", "clamp"]:
		return f.std450 if t.base == shader.bFloat
			else f.std450 + 1 if t.base == shader.bUint
			else f.std450 + 2
	f.std450

# An index of a texture array may differ between the invocations drawn together: the pointer
# it gives, the texture loaded through it and what is taken from that are decorated NonUniform
# (the stage then declares ShaderNonUniform and SampledImageArrayNonUniformIndexing).
fn spvMarkNonUniform(mut w SpvWriter, id i64):
	w.m.decorate(id, [shader.decNonUniform])
	w.nonUniform.push(id)

# What the stage is given (irStageIn): the pixel's position, a parameter (a member of the block;
# a bool read from its word), a texture (its variable: a pointer), an element of a texture array
# (NonUniform when its index is computed), of a storage buffer or of a parameter's array.
fn spvStageIn(mut w SpvWriter, inst IrInst, t shader.Ty) i64:
	v = w.vars[inst.key].copy()
	if v.storage == shader.scUniformConstant:
		if inst.b < 0: return v.ptr
		p = w.spvValId(
			shader.opAccessChain,
			w.spvPtrType(t, shader.scUniformConstant),
			[v.ptr, w.spvGet(inst.b)]
		)
		if not w.consts[inst.b]:
			w.spvMarkNonUniform(p)
		return p
	stored, ptr = w.spvPlace(v, inst.b)
	laid = 1 if v.storage == shader.scUniform else 2 if v.storage == shader.scStorageBuffer else 0
	if laid > 0 and (stored.arr >= 0 or stored.base == shader.bStruct):
		# an aggregate of a block is laid out (offsets, strides): loaded as such, then copied to
		# the same value without the layout
		raw = w.spvValId(shader.opLoad, w.spvType(stored, laid), [ptr])
		return w.spvVal(shader.opCopyLogical, stored, [raw])
	value = w.spvVal(shader.opLoad, stored, [ptr])
	w.spvConvert(value, stored, t)

# the type and the pointer of a stage's variable, its block member, or their element at the
# index vreg b (b >= 0)
fn spvPlace(mut w SpvWriter, v SpvVar, b i64):
	chain = [v.ptr]
	if v.member >= 0:
		chain.push(w.spvInt(v.member))
	if b >= 0:
		chain.push(w.spvGet(b))
	stored = v.ty.elemOf() if b >= 0 else v.ty
	if chain.len == 1: return (stored, v.ptr)
	(stored, w.spvValId(shader.opAccessChain, w.spvPtrType(stored, v.storage), chain))

# What the stage writes where it is (irStageOut: a compute stage's group memory, a storage
# buffer's element) given a's value.
fn spvStageOut(mut w SpvWriter, inst IrInst):
	v = w.vars[inst.key].copy()
	stored, ptr = w.spvPlace(v, inst.b)
	value = w.spvConvert(w.spvGet(inst.a), w.tys[inst.a], stored)
	laid = 2 if v.storage == shader.scStorageBuffer else 0
	if laid > 0 and (stored.arr >= 0 or stored.base == shader.bStruct):
		w.spvIns(
			shader.opStore,
			[ptr, w.spvValId(shader.opCopyLogical, w.spvType(stored, laid), [value])]
		)
		return
	w.spvIns(shader.opStore, [ptr, value])

# ---------- main ----------

# The entry point: the entry's arguments made of the stage's inputs (a struct's fields each an
# input), the entry called, what it gives written to the outputs; a vertex stage's depth moved
# into Vulkan's range (z' = (z + w) / 2).
fn spvMain(mut w SpvWriter, prog GpuProgram, s shader.StageLayout, entry str):
	g = prog.fns.find(.name == entry) ?? fail("shader: no entry {entry}")
	w.tys = g.tys.copy()
	w.ids = []
	w.ptrs = []
	w.body = []
	w.locals = []
	id = w.m.newId()
	void = shader.scalar(shader.bVoid)
	first = w.m.newId()
	emit(w.m.functions, shader.opFunction, [w.spvType(void), id, 0, w.spvFnType(void, [])])
	args = [w.fnIds[entry]]
	param = 0
	for arg in s.args:
		if arg.kind == shader.argPart: continue
		t = g.tys[g.params[param]]
		param += 1
		values = arg.vars.map(w.spvLoadVar(it))
		args.push(
			w.spvConvert(values[0], w.vars[arg.vars[0]].ty, t) if arg.kind == shader.argValue
			else w.spvVal(shader.opCompositeConstruct, t, values)
		)
	result = w.spvVal(shader.opFunctionCall, g.ret, args)
	r = s.result
	if r.kind == shader.resultValue:
		w.spvIns(shader.opStore, [w.vars[r.vars[0]].ptr, result])
	elif r.kind == shader.resultFields:
		w.spvStoreFields(result, r.vars)
	elif r.kind == shader.resultTuple:
		v4 = shader.vector(shader.bFloat, 4)
		w.spvIns(
			shader.opStore,
			[w.vars["zapPosition"].ptr, w.spvVal(shader.opCompositeExtract, v4, [result, 0])]
		)
		second = w.spvVal(shader.opCompositeExtract, w.structs[g.ret.sid][1], [result, 1])
		if r.second == shader.resultValue:
			w.spvIns(shader.opStore, [w.vars[r.vars[0]].ptr, second])
		else:
			w.spvStoreFields(second, r.vars)
	if s.stage == shader.stageVertex:
		v4 = shader.vector(shader.bFloat, 4)
		f = shader.scalar(shader.bFloat)
		position = w.vars["zapPosition"].ptr
		p = w.spvVal(shader.opLoad, v4, [position])
		z = w.spvVal(shader.opCompositeExtract, f, [p, 2])
		pw = w.spvVal(shader.opCompositeExtract, f, [p, 3])
		sum = w.spvVal(shader.opFAdd, f, [z, pw])
		half = w.spvVal(shader.opFMul, f, [sum, w.spvFloat(0.5)])
		w.spvIns(shader.opStore, [position, w.spvVal(shader.opCompositeInsert, v4, [half, p, 2])])
	w.spvIns(shader.opReturn, [])
	w.spvFinishFunction(first)
	id

fn spvLoadVar(mut w SpvWriter, name str) i64:
	v = w.vars[name].copy()
	w.spvVal(shader.opLoad, v.ty, [v.ptr])

# each field of struct value `value` stored to its variable
fn spvStoreFields(mut w SpvWriter, value i64, names str[]):
	for i, name in names:
		v = w.vars[name].copy()
		w.spvIns(shader.opStore, [v.ptr, w.spvVal(shader.opCompositeExtract, v.ty, [value, i])])
