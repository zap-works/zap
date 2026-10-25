# A check of the SPIR-V the compiler writes, for the rules a driver relies on and the compiler
# could break: every id defined once and before it is used (labels and functions may come
# later), the types of the instructions it emits (loads, stores, access chains, arithmetic,
# composites, comparisons, conversions, calls, returns), blocks that end in one terminator with
# their merges right before it, function variables first, and descriptor indexing: a texture
# array without a length needs RuntimeDescriptorArray, a NonUniform decoration
# ShaderNonUniform, an index computed into a texture array a NonUniform pointer (with
# SampledImageArrayNonUniformIndexing) or SampledImageArrayDynamicIndexing, and a texture loaded
# through a NonUniform pointer is NonUniform itself. The problems found, as text.

type Inst:
	op i64
	words i64[]   # the operands, after the opcode word
	at i64   # its index among the instructions

type Checker:
	insts Inst[]
	types {i64: i64}   # a type's id: its instruction
	valueTy {i64: i64}   # a value's id: its type's id
	defined {i64: i64}   # an id: the instruction defining it
	problems str[]

pub fn validate(words u32[]) str[]:
	c = Checker(insts = [], types = {}, valueTy = {}, defined = {}, problems = [])
	if words.len < 5 or words[0] != 0x0723_0203:
		c.problems.push("not a SPIR-V module")
		return move c.problems
	bound = i64(words[3])
	i = 5
	while i < words.len:
		w = i64(words[i])
		count = w >> 16
		op = w & 0xFFFF
		if count < 1 or i + count > words.len:
			c.problems.push("instruction {c.insts.len} has a bad word count {count}")
			return move c.problems
		operands = (1..count).map(i64(words[i + it]))
		c.insts.push(Inst(op, words = operands, at = c.insts.len))
		i += count
	for k in 0..c.insts.len:
		c.record(k, bound)
	for k in 0..c.insts.len:
		c.checkInst(k)
	c.checkBlocks()
	c.checkDescriptorIndexing()
	c.problems

# ---------- what each instruction defines ----------

# the result id and the result type of an instruction (-1 when it has none)
fn resultOf(op i64, words i64[]):
	if op in [opExtInstImport, opLabel, opString()]: return (words[0], -1)
	if op >= opTypeVoid and op <= opTypeFunction: return (words[0], -1)
	if hasTypeAndResult(op): return (words[1], words[0])
	(-1, -1)

fn opString():
	7

# the instructions written as result type, result id, operands
fn hasTypeAndResult(op i64):
	op in [
		opExtInst,
		opConstantTrue,
		opConstantFalse,
		opConstant,
		opConstantComposite,
		opConstantNull,
		opFunction
	] or
		op == opFunctionParameter or op == opFunctionCall or op == opVariable or op == opLoad or
		op == opAccessChain or op >= opVectorExtractDynamic and op <= opTranspose or
		op >= opImageSampleImplicitLod and op <= opImageQueryLevels or
		op >= opConvertFToU and op <= opBitcast or op >= opSNegate and op <= opFwidth or
		op == opPhi or
		op == opCopyLogical or op >= opGroupNonUniformElect and op <= opGroupNonUniformFMax

fn record(mut c Checker, k i64, bound i64):
	inst = c.insts[k].copy()
	id, ty = resultOf(inst.op, inst.words)
	if id < 0: return
	if id <= 0 or id >= bound:
		c.problems.push("{opText(inst.op)} at {k} defines id {id} outside the bound {bound}")
		return
	if id in c.defined:
		c.problems.push("id {id} defined twice ({opText(inst.op)} at {k})")
	c.defined[id] = k
	if inst.op >= opTypeVoid and inst.op <= opTypeFunction:
		c.types[id] = k
	elif ty >= 0:
		c.valueTy[id] = ty

# ---------- types ----------

fn typeInst(c Checker, t i64) Inst?:
	match c.types.get(t):
		k: c.insts[k].copy()
		none: none

# the type a pointer type points to, and its storage class (-1, -1 when t is not a pointer)
fn pointee(c Checker, t i64):
	match c.typeInst(t):
		i: (i.words[2], i.words[1]) if i.op == opTypePointer else (-1, -1)
		none: (-1, -1)

fn tyOfValue(c Checker, id i64):
	c.valueTy.get(id) ?? -1

# a vector's component type and size; a scalar is itself with size 1
fn shapeOf(c Checker, t i64):
	match c.typeInst(t):
		i: (i.words[1], i.words[2]) if i.op == opTypeVector else (t, 1)
		none: (t, 1)

fn isFloatTy(c Checker, t i64):
	comp, _ = c.shapeOf(t)
	match c.typeInst(comp):
		i: i.op == opTypeFloat
		none: false

fn isIntTy(c Checker, t i64):
	comp, _ = c.shapeOf(t)
	match c.typeInst(comp):
		i: i.op == opTypeInt
		none: false

fn isBoolTy(c Checker, t i64):
	comp, _ = c.shapeOf(t)
	match c.typeInst(comp):
		i: i.op == opTypeBool
		none: false

# the type reached from t by one index (a constant's value for a struct member)
fn stepInto(c Checker, t i64, index i64, constant bool):
	match c.typeInst(t):
		i:
			if i.op == opTypeStruct:
				if not constant: return -2
				return i.words[index + 1] if index >= 0 and index + 1 < i.words.len else -2
			if i.op in [opTypeArray, opTypeRuntimeArray, opTypeVector, opTypeMatrix]:
				return i.words[1]
			-2
		none: -2

# the value of an integer constant, or -1
fn constValue(c Checker, id i64):
	match c.defined.get(id):
		k: c.insts[k].words[2] if c.insts[k].op == opConstant else -1
		none: -1

# ---------- each instruction ----------

fn problem(mut c Checker, k i64, msg str):
	c.problems.push("{opText(c.insts[k].op)} at {k}: {msg}")

fn checkInst(mut c Checker, k i64):
	inst = c.insts[k].copy()
	op = inst.op
	w = inst.words
	# every id operand defined (the forward references the format allows aside)
	for id in idOperands(op, w):
		if id not in c.defined:
			c.problem(k, "uses id {id}, never defined")
	if not hasTypeAndResult(op) and op != opStore and op != opReturnValue and
		op != opBranchConditional:
		return
	if op == opLoad:
		t, _ = c.pointee(c.tyOfValue(w[2]))
		if t != w[0]:
			c.problem(k, "loads a {c.typeText(t)} as a {c.typeText(w[0])}")
	elif op == opStore:
		t, _ = c.pointee(c.tyOfValue(w[0]))
		if t != c.tyOfValue(w[1]):
			problem(
				c,
				k,
				"stores a {c.typeText(c.tyOfValue(w[1]))} where a {c.typeText(t)} goes"
			)
	elif op == opAccessChain:
		c.checkInstAccessChain(k, w)
	elif op == opVariable:
		_, sc = c.pointee(w[0])
		if sc != w[2]:
			c.problem(k, "a variable of class {w[2]} typed for class {sc}")
	elif op == opCompositeExtract:
		t = c.tyOfValue(w[2])
		for j in 3..w.len:
			t = c.stepInto(t, w[j], true)
		if t != w[0]:
			c.problem(k, "extracts a {c.typeText(t)} as a {c.typeText(w[0])}")
	elif op == opCompositeConstruct:
		c.checkConstruct(k)
	elif op == opVectorShuffle:
		c.checkInstShuffle(k, w)
	elif op in [
		opFAdd,
		opFSub,
		opFMul,
		opFDiv,
		opFMod,
		opFRem,
		opIAdd,
		opISub,
		opIMul,
		opSDiv,
		opUDiv,
		opSRem,
		opUMod,
		opBitwiseAnd,
		opBitwiseOr,
		opBitwiseXor
	]:
		c.checkInstArithmetic(k, op, w)
	elif op in [opFNegate, opSNegate, opNot, opLogicalNot, opDPdx, opDPdy, opFwidth]:
		if c.tyOfValue(w[2]) != w[0]:
			c.problem(k, "operand {c.typeText(c.tyOfValue(w[2]))} for a {c.typeText(w[0])}")
	elif op == opVectorTimesScalar:
		comp, _ = c.shapeOf(w[0])
		if c.tyOfValue(w[2]) != w[0] or c.tyOfValue(w[3]) != comp:
			c.problem(k, "bad operands")
	elif op >= opLogicalEqual and op <= opFOrdGreaterThanEqual and op != opSelect:
		c.checkInstCompare(k, op, w)
	elif op == opSelect:
		if not c.isBoolTy(c.tyOfValue(w[2])) or c.tyOfValue(w[3]) != w[0] or
			c.tyOfValue(w[4]) != w[0]:
			c.problem(k, "selects {c.typeText(c.tyOfValue(w[3]))} / {c.typeText(c.tyOfValue(w[4]))} as {c.typeText(w[0])}")
	elif op >= opConvertFToU and op <= opBitcast:
		c.checkInstConvert(k, op, w)
	elif op == opFunctionCall:
		c.checkCall(k)
	elif op == opBranchConditional:
		if not c.isBoolTy(c.tyOfValue(w[0])):
			c.problem(k, "a condition of {c.typeText(c.tyOfValue(w[0]))}")
	elif op == opPhi:
		for j in 0..(w.len - 2) / 2:
			if c.tyOfValue(w[2 + j * 2]) != w[0]:
				c.problem(
					k,
					"a phi value of {c.typeText(c.tyOfValue(w[2 + j * 2]))} for {c.typeText(w[0])}"
				)
	elif op == opDot:
		if not c.isFloatTy(w[0]) or c.tyOfValue(w[2]) != c.tyOfValue(w[3]):
			c.problem(k, "bad operands")

fn checkInstAccessChain(mut c Checker, k i64, w i64[]):
	base, sc = c.pointee(c.tyOfValue(w[2]))
	t = base
	for j in 3..w.len:
		v = c.constValue(w[j])
		t = c.stepInto(t, v, v >= 0)
		if t < 0:
			c.problem(k, "an index that leads nowhere")
			return
	rt, rsc = c.pointee(w[0])
	if rt != t or rsc != sc:
		problem(
			c,
			k,
			"points to a {c.typeText(t)} (class {sc}), typed {c.typeText(rt)} (class {rsc})"
		)

fn checkInstShuffle(mut c Checker, k i64, w i64[]):
	_, n = c.shapeOf(w[0])
	ca, na = c.shapeOf(c.tyOfValue(w[2]))
	cb, nb = c.shapeOf(c.tyOfValue(w[3]))
	cr, _ = c.shapeOf(w[0])
	if n != w.len - 4 or ca != cr or cb != cr:
		c.problem(k, "shuffles into {c.typeText(w[0])} from {c.typeText(c.tyOfValue(w[2]))} and {c.typeText(c.tyOfValue(w[3]))}")
	for j in 4..w.len:
		if w[j] >= na + nb:
			c.problem(k, "component {w[j]} out of {na + nb}")

fn checkInstArithmetic(mut c Checker, k i64, op i64, w i64[]):
	if c.tyOfValue(w[2]) != w[0] or c.tyOfValue(w[3]) != w[0]:
		c.problem(k, "operands {c.typeText(c.tyOfValue(w[2]))} and {c.typeText(c.tyOfValue(w[3]))} for a {c.typeText(w[0])}")
	isF = op in [opFAdd, opFSub, opFMul, opFDiv, opFMod, opFRem]
	if isF != c.isFloatTy(w[0]):
		c.problem(k, "a {"float" if isF else "integer"} operation on {c.typeText(w[0])}")

fn checkInstCompare(mut c Checker, k i64, op i64, w i64[]):
	if not c.isBoolTy(w[0]):
		c.problem(k, "a comparison giving {c.typeText(w[0])}")
	if op >= opIEqual and c.tyOfValue(w[2]) != c.tyOfValue(w[3]):
		problem(
			c,
			k,
			"compares {c.typeText(c.tyOfValue(w[2]))} with {c.typeText(c.tyOfValue(w[3]))}"
		)

fn checkInstConvert(mut c Checker, k i64, op i64, w i64[]):
	_, n = c.shapeOf(w[0])
	_, m = c.shapeOf(c.tyOfValue(w[2]))
	if n != m:
		c.problem(k, "converts {c.typeText(c.tyOfValue(w[2]))} to {c.typeText(w[0])}")
	if (op == opConvertSToF or op == opConvertUToF) and
		(not c.isFloatTy(w[0]) or not c.isIntTy(c.tyOfValue(w[2]))):
		c.problem(
			k,
			"an int to float conversion from {c.typeText(c.tyOfValue(w[2]))} to {c.typeText(w[0])}"
		)
	if (op == opConvertFToS or op == opConvertFToU) and
		(not c.isIntTy(w[0]) or not c.isFloatTy(c.tyOfValue(w[2]))):
		c.problem(
			k,
			"a float to int conversion from {c.typeText(c.tyOfValue(w[2]))} to {c.typeText(w[0])}"
		)

# OpCompositeConstruct: a vector's parts add up to its components; others, one part per member,
# as many as it has
fn checkConstruct(mut c Checker, k i64):
	w = c.insts[k].words.copy()
	t = w[0]
	match c.typeInst(t):
		ti:
			if ti.op == opTypeVector:
				n = 0
				for j in 2..w.len:
					comp, m = c.shapeOf(c.tyOfValue(w[j]))
					if comp != ti.words[1]:
						problem(
							c,
							k,
							"a part of {c.typeText(c.tyOfValue(w[j]))} in a {c.typeText(t)}"
						)
					n += m
				if n != ti.words[2]:
					c.problem(k, "{n} components for a {c.typeText(t)}")
			elif ti.op == opTypeMatrix or ti.op == opTypeArray:
				count = ti.words[2] if ti.op == opTypeMatrix else c.constValue(ti.words[2])
				if w.len - 2 != count:
					c.problem(k, "{w.len - 2} parts for a {c.typeText(t)} of {count}")
				for j in 2..w.len:
					if c.tyOfValue(w[j]) != ti.words[1]:
						problem(
							c,
							k,
							"a part of {c.typeText(c.tyOfValue(w[j]))} in a {c.typeText(t)}"
						)
			elif ti.op == opTypeStruct:
				if w.len - 2 != ti.words.len - 1:
					c.problem(k, "{w.len - 2} parts for a struct of {ti.words.len - 1}")
				for j in 2..w.len:
					if j - 1 >= ti.words.len or c.tyOfValue(w[j]) != ti.words[j - 1]:
						c.problem(k, "member {j - 2} of a {c.typeText(t)}")
		none: c.problem(k, "builds an unknown type")

fn checkCall(mut c Checker, k i64):
	w = c.insts[k].words.copy()
	if c.defined.get(w[2]) is fk:
		fnTy = c.insts[fk].words[3]
		match c.typeInst(fnTy):
			ft:
				if ft.words[1] != w[0]:
					c.problem(k, "returns {c.typeText(ft.words[1])}, used as {c.typeText(w[0])}")
				if ft.words.len - 2 != w.len - 3:
					c.problem(k, "{w.len - 3} arguments for {ft.words.len - 2} parameters")
					return
				for j in 3..w.len:
					if c.tyOfValue(w[j]) != ft.words[j - 1] and
						not c.isPointerTo(ft.words[j - 1], w[j]):
						c.problem(k, "argument {j - 3}: {c.typeText(c.tyOfValue(w[j]))} for {c.typeText(ft.words[j - 1])}")
			none: c.problem(k, "calls something without a function type")

# whether the argument is the variable a pointer parameter takes (its type is the pointer's)
fn isPointerTo(c Checker, paramTy i64, arg i64):
	match c.defined.get(arg):
		k: c.insts[k].op == opVariable and c.insts[k].words[0] == paramTy
		none: false

# the id operands of an instruction that must be defined somewhere in the module
fn idOperands(op i64, w i64[]):
	if op in [
		opLoad,
		opCompositeExtract,
		opConvertFToU,
		opConvertFToS,
		opConvertSToF,
		opConvertUToF,
		opBitcast
	] or
		op == opFNegate or op == opSNegate or op == opNot or op == opLogicalNot or
		op == opTranspose or op == opDPdx or op == opDPdy or op == opFwidth or op == opImage or
		op == opCopyLogical:
		return [w[0], w[2]]
	if op == opStore: return [w[0], w[1]]
	if op in [opAccessChain, opCompositeConstruct, opFunctionCall]:
		out = [w[0]]
		out.extend(w[2..])
		return out
	if op == opVectorShuffle: return [w[0], w[2], w[3]]
	if op >= opGroupNonUniformIAdd and op <= opGroupNonUniformFMax:
		out = [w[0], w[2]]   # the type, the scope; the group operation a literal
		out.extend(w[4..])
		return out
	if hasTypeAndResult(op) and op != opVariable and op != opPhi and op != opExtInst and
		op != opFunction and op != opConstant and op != opConstantTrue and op != opConstantFalse and
		op != opConstantComposite and op != opConstantNull and op != opFunctionParameter and
		not (op >= opImageSampleImplicitLod and op <= opImageQueryLod and op != opImage) and
		op != opCompositeInsert:
		out = [w[0]]
		out.extend(w[2..])
		return out
	[]

# ---------- descriptor indexing ----------

capSampledImageArrayDynamicIndexing = 30

fn checkDescriptorIndexing(mut c Checker):
	caps = []
	nonUniform = []
	for inst in c.insts:
		if inst.op == opCapability:
			caps.push(inst.words[0])
		if inst.op == opDecorate and inst.words.len > 1 and inst.words[1] == decNonUniform:
			nonUniform.push(inst.words[0])
	if not nonUniform.isEmpty and capShaderNonUniform not in caps:
		c.problems.push("NonUniform decorations without the ShaderNonUniform capability")
	for k in 0..c.insts.len:
		inst = c.insts[k].copy()
		if inst.op == opTypeRuntimeArray and c.isTextureTy(inst.words[1]) and
			capRuntimeDescriptorArray not in caps:
			problem(
				c,
				k,
				"a texture array without a length needs the RuntimeDescriptorArray capability"
			)
		if inst.op == opAccessChain:
			base, sc = c.pointee(c.tyOfValue(inst.words[2]))
			if sc != scUniformConstant or inst.words.len < 4 or
				not c.isTextureTy(c.stepInto(base, 0, false)) or
				c.constValue(inst.words[3]) >= 0:
				continue
			if inst.words[1] in nonUniform:
				if capSampledImageArrayNonUniformIndexing not in caps:
					c.problem(k, "a NonUniform index into a texture array needs SampledImageArrayNonUniformIndexing")
			elif capSampledImageArrayDynamicIndexing not in caps:
				c.problem(k, "an index computed into a texture array is neither NonUniform nor allowed by SampledImageArrayDynamicIndexing")
		if inst.op == opLoad and inst.words[2] in nonUniform and inst.words[1] not in nonUniform:
			c.problem(k, "a texture loaded through a NonUniform pointer is not NonUniform itself")

# whether t is a texture: an image, or an image and its sampler
fn isTextureTy(c Checker, t i64):
	match c.typeInst(t):
		i: i.op == opTypeSampledImage or i.op == opTypeImage
		none: false

# ---------- blocks ----------

fn isTerminator(op i64):
	op in [opBranch, opBranchConditional, opReturn, opReturnValue, opKill, opUnreachable]

# inside functions: a label opens each block, one terminator closes it, a merge sits right
# before its block's terminator, and the variables come first in the first block
fn checkBlocks(mut c Checker):
	inFunction = false
	inBlock = false
	firstBlock = false
	seenCode = false
	for k in 0..c.insts.len:
		op = c.insts[k].op
		if op == opFunction:
			inFunction = true
			firstBlock = true
			seenCode = false
			continue
		if not inFunction or op == opFunctionParameter: continue
		if op == opFunctionEnd:
			if inBlock:
				c.problem(k, "a block without a terminator ends the function")
			inFunction = false
			inBlock = false
			continue
		if op == opLabel:
			if inBlock:
				c.problem(k, "a label inside a block that did not end")
			if not firstBlock or seenCode:
				firstBlock = false
			inBlock = true
			continue
		if not inBlock:
			c.problem(k, "code outside a block")
			continue
		if op == opVariable:
			if not firstBlock or seenCode:
				c.problem(k, "a function variable after the first block's code")
		else:
			seenCode = true
			firstBlock = false
		if op == opSelectionMerge or op == opLoopMerge:
			next = c.insts[k + 1].op if k + 1 < c.insts.len else -1
			if next != opBranch and next != opBranchConditional:
				c.problem(k, "a merge not right before its branch")
		if isTerminator(op):
			inBlock = false

# ---------- text ----------

opNames = [
	(opName, "OpName"),
	(opExtInst, "OpExtInst"),
	(opEntryPoint, "OpEntryPoint"),
	(opTypeVoid, "OpTypeVoid"),
	(opTypeBool, "OpTypeBool"),
	(opTypeInt, "OpTypeInt"),
	(opTypeFloat, "OpTypeFloat"),
	(opTypeVector, "OpTypeVector"),
	(opTypeMatrix, "OpTypeMatrix"),
	(opTypeImage, "OpTypeImage"),
	(opTypeSampledImage, "OpTypeSampledImage"),
	(opTypeArray, "OpTypeArray"),
	(opTypeRuntimeArray, "OpTypeRuntimeArray"),
	(opTypeStruct, "OpTypeStruct"),
	(opTypePointer, "OpTypePointer"),
	(opTypeFunction, "OpTypeFunction"),
	(opConstant, "OpConstant"),
	(opConstantComposite, "OpConstantComposite"),
	(opConstantNull, "OpConstantNull"),
	(opFunction, "OpFunction"),
	(opFunctionParameter, "OpFunctionParameter"),
	(opFunctionCall, "OpFunctionCall"),
	(opVariable, "OpVariable"),
	(opLoad, "OpLoad"),
	(opStore, "OpStore"),
	(opAccessChain, "OpAccessChain"),
	(opDecorate, "OpDecorate"),
	(opMemberDecorate, "OpMemberDecorate"),
	(opVectorExtractDynamic, "OpVectorExtractDynamic"),
	(opVectorShuffle, "OpVectorShuffle"),
	(opCompositeConstruct, "OpCompositeConstruct"),
	(opCompositeExtract, "OpCompositeExtract"),
	(opCompositeInsert, "OpCompositeInsert"),
	(opImageSampleImplicitLod, "OpImageSampleImplicitLod"),
	(opImageSampleExplicitLod, "OpImageSampleExplicitLod"),
	(opImageSampleDrefImplicitLod, "OpImageSampleDrefImplicitLod"),
	(opImageSampleDrefExplicitLod, "OpImageSampleDrefExplicitLod"),
	(opImageGather, "OpImageGather"),
	(opImageDrefGather, "OpImageDrefGather"),
	(opImageQueryLod, "OpImageQueryLod"),
	(opConvertSToF, "OpConvertSToF"),
	(opConvertUToF, "OpConvertUToF"),
	(opConvertFToS, "OpConvertFToS"),
	(opConvertFToU, "OpConvertFToU"),
	(opBitcast, "OpBitcast"),
	(opFAdd, "OpFAdd"),
	(opFSub, "OpFSub"),
	(opFMul, "OpFMul"),
	(opFDiv, "OpFDiv"),
	(opIAdd, "OpIAdd"),
	(opISub, "OpISub"),
	(opIMul, "OpIMul"),
	(opVectorTimesScalar, "OpVectorTimesScalar"),
	(opMatrixTimesVector, "OpMatrixTimesVector"),
	(opDot, "OpDot"),
	(opSelect, "OpSelect"),
	(opPhi, "OpPhi"),
	(opLoopMerge, "OpLoopMerge"),
	(opSelectionMerge, "OpSelectionMerge"),
	(opLabel, "OpLabel"),
	(opBranch, "OpBranch"),
	(opBranchConditional, "OpBranchConditional"),
	(opReturn, "OpReturn"),
	(opReturnValue, "OpReturnValue"),
	(opKill, "OpKill"),
	(opUnreachable, "OpUnreachable"),
	(opCopyLogical, "OpCopyLogical"),
	(opCapability, "OpCapability"), (opImage, "OpImage")]

fn opText(op i64):
	for (code, text) in opNames:
		if code == op: return text.copy()
	"Op{op}"

fn typeText(c Checker, t i64) str:
	match c.typeInst(t):
		i:
			if i.op == opTypeFloat: return "float"
			if i.op == opTypeInt: return "int" if i.words[2] == 1 else "uint"
			if i.op == opTypeBool: return "bool"
			if i.op == opTypeVoid: return "void"
			if i.op == opTypeVector: return "{c.typeText(i.words[1])}x{i.words[2]}"
			if i.op == opTypeMatrix: return "mat{i.words[2]}"
			if i.op == opTypePointer: return "ptr({c.typeText(i.words[2])})"
			if i.op == opTypeArray or i.op == opTypeRuntimeArray:
				return "{c.typeText(i.words[1])}[]"
			if i.op == opTypeSampledImage or i.op == opTypeImage: return "texture"
			"%{t}"
		none: "%{t}?"

# the module as text, one instruction a line: its index, its name, its operand words
pub fn disassemble(words u32[]) str:
	out = []
	i = 5
	k = 0
	while i < words.len:
		w = i64(words[i])
		count = (w >> 16).max(1)
		line = "{k}: {opText(w & 0xFFFF)}{(1..count).map(" {i64(words[i + it])}").join("")}"
		out.push(line)
		i += count
		k += 1
	out.join("\n")
