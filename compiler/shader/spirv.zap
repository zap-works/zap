# A SPIR-V module being written: its sections in the order the format wants them, ids handed
# out in turn, types and constants made once each (by a key that describes them).

# the opcodes used
pub opName = 5
pub opMemberName = 6
pub opExtInstImport = 11
pub opExtInst = 12
pub opMemoryModel = 14
pub opEntryPoint = 15
pub opExecutionMode = 16
pub opCapability = 17
pub opTypeVoid = 19
pub opTypeBool = 20
pub opTypeInt = 21
pub opTypeFloat = 22
pub opTypeVector = 23
pub opTypeMatrix = 24
pub opTypeImage = 25
pub opTypeSampledImage = 27
pub opTypeArray = 28
pub opTypeRuntimeArray = 29
pub opTypeStruct = 30
pub opTypePointer = 32
pub opTypeFunction = 33
pub opConstantTrue = 41
pub opConstantFalse = 42
pub opConstant = 43
pub opConstantComposite = 44
pub opConstantNull = 46
pub opFunction = 54
pub opFunctionParameter = 55
pub opFunctionEnd = 56
pub opFunctionCall = 57
pub opVariable = 59
pub opLoad = 61
pub opStore = 62
pub opAccessChain = 65
pub opDecorate = 71
pub opMemberDecorate = 72
pub opVectorExtractDynamic = 77
pub opVectorInsertDynamic = 78
pub opVectorShuffle = 79
pub opCompositeConstruct = 80
pub opCompositeExtract = 81
pub opCompositeInsert = 82
pub opTranspose = 84
pub opImageSampleImplicitLod = 87
pub opImageSampleExplicitLod = 88
pub opImageSampleDrefImplicitLod = 89
pub opImageSampleDrefExplicitLod = 90
pub opImageFetch = 95
pub opImageGather = 96
pub opImageRead = 98
pub opImageWrite = 99
pub opImageDrefGather = 97
pub opImage = 100
pub opImageQuerySizeLod = 103
pub opImageQuerySize = 104
pub opImageQueryLod = 105
pub opImageQueryLevels = 106
pub opConvertFToU = 109
pub opConvertFToS = 110
pub opConvertSToF = 111
pub opConvertUToF = 112
pub opFConvert = 115
pub opBitcast = 124
pub opSNegate = 126
pub opFNegate = 127
pub opIAdd = 128
pub opFAdd = 129
pub opISub = 130
pub opFSub = 131
pub opIMul = 132
pub opFMul = 133
pub opUDiv = 134
pub opSDiv = 135
pub opFDiv = 136
pub opUMod = 137
pub opSRem = 138
pub opFRem = 140
pub opFMod = 141
pub opVectorTimesScalar = 142
pub opMatrixTimesScalar = 143
pub opVectorTimesMatrix = 144
pub opMatrixTimesVector = 145
pub opMatrixTimesMatrix = 146
pub opDot = 148
pub opAll = 155
pub opLogicalEqual = 164
pub opLogicalNotEqual = 165
pub opLogicalOr = 166
pub opLogicalAnd = 167
pub opLogicalNot = 168
pub opSelect = 169
pub opIEqual = 170
pub opINotEqual = 171
pub opUGreaterThan = 172
pub opSGreaterThan = 173
pub opUGreaterThanEqual = 174
pub opSGreaterThanEqual = 175
pub opULessThan = 176
pub opSLessThan = 177
pub opULessThanEqual = 178
pub opSLessThanEqual = 179
pub opFOrdEqual = 180
pub opFOrdNotEqual = 182
pub opFOrdLessThan = 184
pub opFOrdGreaterThan = 186
pub opFOrdLessThanEqual = 188
pub opFOrdGreaterThanEqual = 190
pub opShiftRightLogical = 194
pub opShiftRightArithmetic = 195
pub opShiftLeftLogical = 196
pub opBitwiseOr = 197
pub opBitwiseXor = 198
pub opBitwiseAnd = 199
pub opNot = 200
pub opDPdx = 207
pub opDPdy = 208
pub opFwidth = 209
pub opPhi = 245
pub opLoopMerge = 246
pub opSelectionMerge = 247
pub opLabel = 248
pub opBranch = 249
pub opBranchConditional = 250
pub opKill = 252
pub opReturn = 253
pub opReturnValue = 254
pub opUnreachable = 255
pub opControlBarrier = 224
pub opImageTexelPointer = 60
pub opAtomicExchange = 229
pub opAtomicCompareExchange = 230
pub opAtomicIAdd = 234
pub opAtomicSMin = 236
pub opAtomicUMin = 237
pub opAtomicSMax = 238
pub opAtomicUMax = 239
pub opAtomicAnd = 240
pub opAtomicOr = 241
pub opAtomicXor = 242
pub opGroupNonUniformElect = 333
pub opGroupNonUniformIAdd = 349
pub opGroupNonUniformFMax = 358
pub opCopyLogical = 400

# storage classes
pub scUniformConstant = 0
pub scInput = 1
pub scUniform = 2
pub scOutput = 3
pub scWorkgroup = 4
pub scPrivate = 6
pub scFunction = 7
pub scImage = 11
pub scStorageBuffer = 12

# decorations
pub decBlock = 2
pub decColMajor = 5
pub decArrayStride = 6
pub decMatrixStride = 7
pub decBuiltIn = 11
pub decFlat = 14
pub decNonWritable = 24
pub decLocation = 30
pub decBinding = 33
pub decDescriptorSet = 34
pub decOffset = 35
pub decNonUniform = 5300

# capabilities past Shader
pub capFloat64 = 10
pub capSampledCubeArray = 45
pub capImageQuery = 50
pub capStorageImageReadWithoutFormat = 55
pub capStorageImageWriteWithoutFormat = 56
pub capGroupNonUniform = 61
pub capShaderNonUniform = 5301
pub capRuntimeDescriptorArray = 5302
pub capSampledImageArrayNonUniformIndexing = 5307

pub type Module:
	bound i64
	capabilities u32[]
	imports u32[]
	entries u32[]
	modes u32[]
	names u32[]
	decorations u32[]
	globals u32[]   # types, constants and module variables, in the order made
	functions u32[]
	made {str: i64}   # a type's or a constant's key and its id
	std450 i64   # the import of the standard extended instructions

pub fn newModule() Module:
	m = Module(
		bound = 1,
		capabilities = [],
		imports = [],
		entries = [],
		modes = [],
		names = [],
		decorations = [],
		globals = [],
		functions = [],
		made = {},
		std450 = 0
	)
	m.std450 = m.newId()
	# the set's name is fixed by the SPIR-V specification (Khronos' extended instruction set 450)
	emitWithString(m.imports, opExtInstImport, [m.std450], "GLSL.std.450", [])
	m

pub fn newId(mut m Module) i64:
	id = m.bound
	m.bound += 1
	id

# an instruction: its word count and opcode, then its operands
pub fn emit(mut out u32[], op i64, operands i64[]):
	out.push(u32((operands.len + 1) << 16 | op))
	out.extend(operands.map(u32(it & 0xFFFF_FFFF)))

# an instruction with a literal string among its operands: before it `head`, after it `tail`
pub fn emitWithString(mut out u32[], op i64, head i64[], s str, tail i64[]):
	words = stringWords(s)
	out.push(u32((head.len + words.len + tail.len + 1) << 16 | op))
	out.extend(head.map(u32(it & 0xFFFF_FFFF)))
	out.extend(words)
	out.extend(tail.map(u32(it & 0xFFFF_FFFF)))

# a string's UTF-8 bytes, NUL-terminated, four to a word (low byte first)
fn stringWords(s str):
	out = []
	i = 0
	while i <= s.len:
		w = 0
		for k in 0..4:
			b = i64(s[i + k]) if i + k < s.len else 0
			w |= b << (k * 8)
		out.push(u32(w))
		i += 4
	out

# the id made for `key`, or a new one made by `op` with the operands (the id first)
pub fn typeOf(mut m Module, key str, op i64, operands i64[]) i64:
	if m.made.get(key) is id: return id
	id = m.newId()
	words = [id]
	words.extend(operands)
	emit(m.globals, op, words)
	m.made[key.copy()] = id
	id

# a constant of the type t with the literal words (made once per type and value)
pub fn constantOf(mut m Module, t i64, words i64[]) i64:
	key = "c{t}{words.map(":{it}").join("")}"
	if m.made.get(key) is id: return id
	id = m.newId()
	ops = [t, id]
	ops.extend(words)
	emit(m.globals, opConstant, ops)
	m.made[key] = id
	id

pub fn debugName(mut m Module, id i64, s str):
	emitWithString(m.names, opName, [id], s, [])

pub fn decorate(mut m Module, id i64, operands i64[]):
	ops = [id]
	ops.extend(operands)
	emit(m.decorations, opDecorate, ops)

pub fn decorateMember(mut m Module, id i64, member i64, operands i64[]):
	ops = [id, member]
	ops.extend(operands)
	emit(m.decorations, opMemberDecorate, ops)

# the module's words: the header (SPIR-V 1.5), then each section in its place
pub fn moduleWords(m Module) u32[]:
	out u32[] = [0x0723_0203, 0x0001_0500, 0, u32(m.bound), 0]
	out.extend(m.capabilities)
	out.extend(m.imports)
	emit(out, opMemoryModel, [0, 1])   # Logical, the 450 memory model
	out.extend(m.entries)
	out.extend(m.modes)
	out.extend(m.names)
	out.extend(m.decorations)
	out.extend(m.globals)
	out.extend(m.functions)
	out

# the bits of an f32 with value v (normal numbers and zero; the shaders' constants)
pub fn f32Bits(v f64) i64:
	b = i64(v.toBits())
	sign = (b >> 63) & 1
	e64 = (b >> 52) & 0x7FF
	if e64 == 0: return sign << 31
	e32 = e64 - 1023 + 127
	if e32 <= 0: return sign << 31
	if e32 >= 255: return sign << 31 | 0x7F80_0000
	# round to nearest even: the 29 bits dropped decide
	mantissa = b & 0xF_FFFF_FFFF_FFFF
	m32 = mantissa >> 29
	rest = mantissa & 0x1FFF_FFFF
	if rest > 0x1000_0000 or rest == 0x1000_0000 and (m32 & 1) == 1:
		m32 += 1
	bits = sign << 31 | e32 << 23
	bits += m32   # a mantissa carry moves into the exponent
	bits
