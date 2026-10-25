# HLSL (shader model 6.0, HLSL 2021) of one stage of a program from its GPU functions in the
# intermediate form (irgpu.zap), for Direct3D 12, laid out as the SPIR-V is (irspirv.zap): the
# parameters one constant buffer at b0 with each one where the std140 block has it (packoffset),
# followed by the stage's y flip; a texture at binding n the texture t<n> and the sampler s<n>; a
# storage buffer at binding n a structured buffer at t<16 + n>. Each vreg is a local of its
# function (a texture the variable it names); a branch is an if and a loop a while, written from
# the form's structure (IrFn.merges): a jump to a loop's continue block is that block's code and
# `continue`, one to the block after it `break`.
#
# A texture array at binding n is an array of textures at t0 and one of samplers at s0 of space
# 1 + n (`Texture2D textures_t[] : register(t0, space1)`; an unbounded one takes every register
# of its space after it, so each array has a space of its own: a descriptor table's range in the
# root signature, shader model 5.1 and later), indexed through NonUniformResourceIndex as the
# SPIR-V's index is NonUniform. Shader model 6.6's ResourceDescriptorHeap would need the 6.6
# profiles and a root signature flag; the arrays keep the stages at 6.0 and the reflection the
# same for both backends.
#
# A matrix is written transposed (HLSL's row r is the shader's column r, as the constant buffer
# lays it out row_major), so m @ v is mul(v, m), v @ m is mul(m, v), a @ b is mul(b, a), m[i] is
# the same column and a matrix made of columns is made of the same values in the same order.
# A target's y is flipped by the vertex stage (zapFlipY, -1; 1 for the screen): Direct3D puts
# clip y = 1 at a target's first row, where Vulkan's viewport puts y = -1.
#
# This step stands until Direct3D 12 takes the SPIR-V itself (shader model 7): the rest of the
# compiler, and the binaries' reflection, does not depend on it.

import shader

type HlslWriter:
	structs GpuStructs
	stage i64
	out str[]
	reads {str: shader.Ty}   # what the stage's code reads, each name its whole value's type
	# the function being written
	tys shader.Ty[]
	texts str[]   # each texture vreg's texture (a variable, a parameter, an array's element)
	loops IrMerge[]   # the open loops
	f IrFn
	givesNothing bool = true   # the function returns no value
	model i64 = 0   # the least shader model 6.x its code needs

# the HLSL of the stage laid out by `s`, its entry the function named `entry`, and the least
# shader model 6.x it needs
fn hlslStage(
	prog GpuProgram,
	s shader.StageLayout,
	l shader.Lowering,
	entry str,
	vs shader.StageLayout,
	groupSize i64[]
):
	h = HlslWriter(
		structs = prog.structs.copy(),
		stage = s.stage,
		out = [],
		reads = {},
		tys = [],
		texts = [],
		loops = [],
		f = newIrFn()
	)
	fns = prog.reachedFns(entry)
	h.hLine("// Written by the Zap compiler from the shader's Zap source (the {stageName(s.stage)} stage).")
	h.hDeclareStructs()
	h.hDeclareReads(prog, fns, l, prog.stageWrites(fns))
	returned str[] = []
	for f in fns:
		t = prog.fns[f].ret
		if t.arr >= 0 and h.hReturnName(t) not in returned:
			# HLSL returns no array: a struct of one does
			returned.push(h.hReturnName(t))
			h.hLine("struct {h.hReturnName(t)} \{ {h.hDeclared(t, "items")}; };")
	for f in fns:
		h.hLine("{h.hSignature(prog.fns[f])};")
	for f in fns:
		h.hlslFunction(prog.fns[f])
	if s.stage == shader.stageCompute:
		h.hComputeEntry(entry, groupSize)
	else:
		h.hEntryPoint(prog, s, l, entry, vs)
	("{h.out.join("\n")}\n", h.model)

fn hLine(mut h HlslWriter, text str):
	h.out.push(text.copy())

# ---------- names and types ----------

hlslWords = [
	"AppendStructuredBuffer",
	"BlendState",
	"Buffer",
	"ByteAddressBuffer",
	"CompileShader",
	"ComputeShader",
	"ConsumeStructuredBuffer",
	"DepthStencilState",
	"DepthStencilView",
	"DomainShader",
	"GeometryShader",
	"Hullshader",
	"InputPatch",
	"LineStream",
	"NULL",
	"OutputPatch",
	"PixelShader",
	"PointStream",
	"RasterizerState",
	"RenderTargetView",
	"SamplerComparisonState",
	"SamplerState",
	"StructuredBuffer",
	"Texture1D",
	"Texture2D",
	"Texture2DArray",
	"Texture3D",
	"TextureCube",
	"TriangleStream",
	"VertexShader",
	"asm",
	"auto",
	"case",
	"cbuffer",
	"centroid",
	"class",
	"column_major",
	"compile",
	"const",
	"default",
	"do",
	"double",
	"dword",
	"enum",
	"export",
	"extern",
	"float",
	"groupshared",
	"half",
	"in",
	"inline",
	"inout",
	"int",
	"interface",
	"line",
	"lineadj",
	"linear",
	"matrix",
	"namespace",
	"nointerpolation",
	"noperspective",
	"out",
	"packoffset",
	"pass",
	"point",
	"precise",
	"register",
	"row_major",
	"sample",
	"sampler",
	"shared",
	"snorm",
	"static",
	"string",
	"struct",
	"switch",
	"tbuffer",
	"technique",
	"template",
	"texture",
	"this",
	"triangle",
	"triangleadj",
	"typedef",
	"uniform",
	"unorm",
	"unsigned",
	"vector",
	"volatile",
	"uint",
	"mul",
	"lerp",
	"frac", "rsqrt", "saturate", "atan2", "mad", "ddx", "ddy", "select", "asfloat", "asint", "asuint", "main"]

# a name as HLSL may have it: its letters, digits and underscores (any other byte an underscore),
# a keyword or an intrinsic the writer calls taken a trailing underscore
fn hname(n str) str:
	if n in hlslWords: return "{n}_"
	out = []
	for c in n.bytes():
		out.push(c if c.isAlnum() or c == '_' else '_')
	str(move out)

fn hBaseWord(base i64):
	shader.baseWords[base].glsl.copy() if base < shader.baseWords.len else ""

# a struct's name in the code: its declaration's, and its place (tuples share a declaration)
fn hStructName(h HlslWriter, sid i64):
	"{hname(h.structs.names[sid])}_{sid}"

# the HLSL type of t, its array length aside
fn hHtype(h HlslWriter, t shader.Ty):
	if t.base == shader.bStruct: return h.hStructName(t.sid)
	if t.cols > 1: return "float{t.cols}x{t.rows}"
	if t.rows > 1: return "{hBaseWord(t.base)}{t.rows}"
	hBaseWord(t.base)

# `name[n]` for an array
fn hArraySuffix(t shader.Ty):
	"[{t.arr}]" if t.arr > 0 else "[]" if t.arr == 0 else ""

fn hElemTy(t shader.Ty):
	shader.Ty(..t, arr = -1)

# a declaration of a value of type t named n
fn hDeclared(h HlslWriter, t shader.Ty, n str):
	"{h.hHtype(t.hElemTy())} {n}{t.hArraySuffix()}"

# ---------- declarations ----------

# the structs, each after those its fields hold, and the function making one of each of its
# values (HLSL has no constructor)
fn hDeclareStructs(mut h HlslWriter):
	done = []
	for sid in 0..h.structs.names.len:
		h.hDeclareStruct(sid, done)

fn hDeclareStruct(mut h HlslWriter, sid i64, mut done i64[]):
	if sid in done: return
	done.push(sid)
	members = h.structs.members[sid].copy()
	for m in members:
		if m.base == shader.bStruct:
			h.hDeclareStruct(m.sid, done)
	name = h.hStructName(sid)
	fields = h.structs.fields[sid].map(hname(it))
	h.hLine("struct {name} \{")
	for i, field in fields:
		h.hLine("\t{h.hDeclared(members[i], field)};")
	h.hLine("};")
	params = (0..fields.len).map(h.hDeclared(members[it], fields[it]))
	h.hLine("{name} zapMake_{name}({params.join(", ")}) \{")
	h.hLine("\t{name} made;")
	for field in fields:
		h.hLine("\tmade.{field} = {field};")
	h.hLine("\treturn made;")
	h.hLine("}")

# What the stage's code reads: the parameters, in the constant buffer where the std140 block
# has them (then the stage's y flip), the textures and their samplers, the texture arrays, the
# storage buffers; the pixel's position; the size of a texture's level.
fn hDeclareReads(mut h HlslWriter, prog GpuProgram, fns i64[], l shader.Lowering, written str[]):
	h.reads = prog.stageReads(fns, l)
	h.hLine(r"cbuffer ZapParams : register(b0) {")
	for p in l.params:
		t = shader.storedTy(h.reads.get(p.name) ?? continue)
		place = "c{p.offset / 16}"
		if t.arr < 0 and not t.isMatrix():
			place = "{place}.{shader.swizzleSets[0][(p.offset % 16) / 4..(p.offset % 16) / 4 + 1]}"
		major = "row_major " if t.hElemTy().isMatrix() else ""
		h.hLine("\t{major}{h.hDeclared(t, hname(p.name))} : packoffset({place});")
	if h.stage != shader.stageCompute:
		h.hLine("\tfloat zapFlipY : packoffset(c{l.paramBytes.alignUp(16) / 16});")
	h.hLine("};")
	h.hDeclareSizes()
	for name in h.reads.keys().sorted():
		t = h.reads[name]
		if gpuValues.any(.name == name) and name != "lane" and name != "laneCount":
			h.hLine("static {h.hHtype(t)} {name};")   # set by main
		if name.startsWith("zapW_"):
			h.hLine("groupshared {h.hDeclared(t, name)};")
	for r in l.resources:
		t = h.reads.get(r.name) ?? continue
		name = hname(r.name)
		if r.kind == shader.resBuffer:
			# a buffer the stage writes is an unordered access view (u), one it reads a view (t)
			rw = "RW" if r.name in written else ""
			kind = "u" if r.name in written else "t"
			h.hLine("{rw}StructuredBuffer<{h.hHtype(t.hElemTy())}> {name} : register({kind}{shader.bufferBase + r.binding});")
			continue
		kind = shader.samplerKinds[r.sampler - 1]
		if kind.storage:
			# a storage image: an unordered access view at u<binding> (a storage buffer's start past 16)
			h.hLine("{kind.hlslTexture} {name}_t : register(u{r.binding});")
			continue
		if r.kind == shader.resArray:
			space = shader.textureArraySet + r.binding
			h.hLine("{kind.hlslTexture} {name}_t{t.hArraySuffix()} : register(t0, space{space});")
			h.hLine("{kind.hlslSampler} {name}_s{t.hArraySuffix()} : register(s0, space{space});")
		else:
			h.hLine("{kind.hlslTexture} {name}_t : register(t{r.binding});")
			h.hLine("{kind.hlslSampler} {name}_s : register(s{r.binding});")

# ---------- functions ----------

fn hFnName(name str):
	"zap_{hname(name)}"

fn hVregName(v i64):
	"v{v}"

fn hSignature(h HlslWriter, g GpuFn):
	ps = []
	for v in g.params:
		t = g.tys[v]
		if t.base == shader.bSampler:
			kind = shader.samplerKinds[t.sid - 1]
			sampler = ", {kind.hlslSampler} {hVregName(v)}_s" if not kind.storage else ""
			ps.push("{kind.hlslTexture} {hVregName(v)}_t{sampler}")
		else:
			ps.push(h.hDeclared(t, hVregName(v)))
	"{h.hReturnType(g.ret)} {hFnName(g.name)}({ps.join(", ")})"

# the type a function returning t returns: t, or for an array the struct of one holding it
fn hReturnType(h HlslWriter, t shader.Ty):
	h.hReturnName(t) if t.arr >= 0 else h.hHtype(t)

fn hReturnName(h HlslWriter, t shader.Ty):
	"ZapArray_{hname(h.hHtype(t.hElemTy()))}_{t.arr}"

# A function: its vregs its locals (a texture's the texture it reads), its code written from
# its first block.
fn hlslFunction(mut h HlslWriter, g GpuFn):
	h.tys = g.tys.copy()
	h.texts = (0..h.tys.len).map(hVregName(it))
	h.loops = []
	h.f = g.f.copy()
	h.givesNothing = h.hReturnType(g.ret) == "void"
	h.hLine("{h.hSignature(g)} \{")
	for v, t in h.tys:
		if v in g.params or t.base == shader.bVoid or t.base == shader.bSampler: continue
		h.hLine("\t{h.hDeclared(t, hVregName(v))};")
	h.hWalk(0, -1, "\t")
	h.hLine("}")

# the code from block b on until the block `stop` (the merge of the branch it is in): each block's
# instructions, its branch an if (else), a loop's header a while, a jump out of a loop a break or
# the continue block's code and a continue
fn hWalk(mut h HlslWriter, b0 i64, stop i64, indent str):
	b = b0
	while b >= 0 and b != stop:
		if h.f.merges.find(.header == b and .cont >= 0) is m:
			if h.loops.isEmpty or h.loops[len - 1].header != b:
				h.hLine("{indent}[loop] while (true) \{")
				h.loops.push(m.copy())
				h.hWalk(b, m.merge, "{indent}\t")
				h.loops.pop()
				h.hLine("{indent}}")
				b = m.merge
				continue
		b = h.hWalkBlock(b, indent)
		if b == -2: return

# block b's code and its end: the block the walk goes on with (-2 when it ends here)
fn hWalkBlock(mut h HlslWriter, b i64, indent str) i64:
	insts = h.f.blocks[b].insts.copy()
	if insts.isEmpty: return -2
	for inst in insts[..len - 1]:
		h.hInstruction(inst, indent)
	last = insts[len - 1].copy()
	if not isTerminator(last.op):
		h.hInstruction(last, indent)
		return -2
	if last.op == irJmp: return h.hJump(last.target, indent)
	if last.op == irBranch:
		c = h.texts[last.a]
		if h.f.merges.find(.header == b and .cont < 0) is m:
			if last.target == m.merge:
				h.hLine("{indent}if (!({c})) \{")
				h.hWalk(last.other, m.merge, "{indent}\t")
			else:
				h.hLine("{indent}if ({c}) \{")
				h.hWalk(last.target, m.merge, "{indent}\t")
				if last.other != m.merge:
					h.hLine("{indent}\} else \{")
					h.hWalk(last.other, m.merge, "{indent}\t")
			h.hLine("{indent}}")
			return m.merge
		# a loop's test: one way leaves it
		if h.hExits(last.other):
			h.hLine("{indent}if (!({c})) \{")
			h.hJump(last.other, "{indent}\t")
			h.hLine("{indent}}")
			return last.target
		h.hLine("{indent}if ({c}) \{")
		h.hJump(last.target, "{indent}\t")
		h.hLine("{indent}}")
		return last.other
	if last.op == irDiscard:
		h.hLine("{indent}discard;")
	elif last.a >= 0:
		t = h.tys[last.a]
		if t.arr >= 0:
			h.hLine("{indent}\{ {h.hReturnName(t)} zapReturned; zapReturned.items = {h.texts[last.a]}; return zapReturned; }")
		else:
			h.hLine("{indent}return {h.texts[last.a]};")
	elif h.givesNothing:
		h.hLine("{indent}return;")
	-2

# whether a jump to b leaves the loop it is in (a break or a continue)
fn hExits(h HlslWriter, b i64):
	if h.loops.isEmpty: return false
	b == h.loops[len - 1].cont or b == h.loops[len - 1].merge

# a jump to block b: a break, the continue block's code and a continue, or the walk going on at b
fn hJump(mut h HlslWriter, b i64, indent str):
	if not h.loops.isEmpty:
		cont = h.loops[len - 1].cont
		if b == h.loops[len - 1].merge:
			h.hLine("{indent}break;")
			return -2
		if b == cont:
			for inst in h.f.blocks[cont].insts.copy():
				if not isTerminator(inst.op):
					h.hInstruction(inst, indent)
			h.hLine("{indent}continue;")
			return -2
	b

# ---------- instructions ----------

# a value's literal: a float with its point, an unsigned with its u
fn hLiteral(t shader.Ty, imm i64):
	if t.base == shader.bBool: return "true" if imm != 0 else "false"
	if t.base == shader.bUint: return "{imm}u"
	if t.base != shader.bFloat: return "{imm}"
	text = str(f64.fromBits(u64.wrap(imm)))
	"({text})" if "." in text or "e" in text or "n" in text else "({text}.0)"

fn hInstruction(mut h HlslWriter, inst IrInst, indent str):
	op = inst.op
	if op == irParam: return
	d = hVregName(inst.dst) if inst.dst >= 0 else ""
	t = h.tys[inst.dst] if inst.dst >= 0 else shader.scalar(shader.bVoid)
	if t.base == shader.bSampler:
		h.texts[inst.dst] = h.hTextureOf(inst)
		return
	text = h.hValueOf(inst, t)
	if text == "": return
	if inst.dst < 0 or op == irSetPart:
		h.hLine("{indent}{text};")
	elif t.arr >= 0 and op == irMake:
		for i, part in inst.args:
			h.hLine("{indent}{d}[{i}] = {h.texts[part]};")
	else:
		h.hLine("{indent}{d} = {text};")

# the texture a texture vreg reads: a texture of the stage (an array's element), a parameter's,
# the one another names
fn hTextureOf(h HlslWriter, inst IrInst):
	if inst.op == irCopy: return h.texts[inst.a].copy()
	if inst.op == irParam: return hVregName(inst.dst)
	if inst.op == irStageIn:
		name = hname(inst.key)
		if inst.b < 0: return name
		return "{name}[NonUniformResourceIndex({h.texts[inst.b]})]"
	fail("shader: a texture of operation {inst.op}")
	""

# an instruction's value as HLSL (an in-place change or a call giving nothing: its statement)
fn hValueOf(mut h HlslWriter, inst IrInst, t shader.Ty):
	op = inst.op
	a = h.texts[inst.a].copy() if inst.a >= 0 else ""
	b = h.texts[inst.b].copy() if inst.b >= 0 else ""
	if op == irConst:
		if not t.isScalar(): return "({h.hHtype(t.hElemTy())}{t.hArraySuffix()})0"
		return t.hLiteral(inst.imm)
	if op == irCopy: return a
	if op == irSet: return "({a} {["==", "!=", "<", "<=", ">", ">="][inst.cond]} {b})"
	if op == irNot: return "(!{a})" if t.base == shader.bBool else "(~{a})"
	if op == irNeg or op == irFNeg: return "(-{a})"
	if op == irConvert: return h.hConvert(a, h.tys[inst.a], t)
	if op == irFloatBits: return "asuint({a})"
	if op == irBitsToFloat: return "asfloat({a})"
	if op == irMake:
		parts = inst.args.map(h.texts[it].copy())
		if t.base == shader.bStruct: return "zapMake_{h.hStructName(t.sid)}({parts.join(", ")})"
		return "{h.hHtype(t)}({parts.join(", ")})"
	if op == irPart: return h.hPartOf(a, h.tys[inst.a], inst.imm, b)
	if op == irSetPart: return "{h.hPartOf(a, h.tys[inst.a], inst.imm, b)} = {h.texts[inst.c]}"
	if op == irSwizzle:
		if h.tys[inst.a].isScalar(): return "(({h.hHtype(t)})({a}))"
		return "{a}.{inst.key}"
	if op == irMatMul:
		if h.tys[inst.a].isMatrix() or h.tys[inst.b].isMatrix(): return "mul({b}, {a})"
		if h.tys[inst.a].isScalar(): return "({a} * {b})"
		return "dot({a}, {b})"
	if op == irBuiltin: return h.hBuiltin(inst, t)
	if op == irTexture: return h.hTexture(inst, t)
	if op == irStageOut:
		name = hname(inst.key)
		place = "{name}[{b}]" if inst.b >= 0 else name
		return "{place} = {a}"
	if op == irBarrier: return "GroupMemoryBarrierWithGroupSync()"
	if op == irStageIn:
		name = hname(inst.key)
		if inst.key == "lane": return "int(WaveGetLaneIndex())"
		if inst.key == "laneCount": return "int(WaveGetLaneCount())"
		if gpuValues.any(.name == inst.key): return name
		value = "{name}[{b}]" if inst.b >= 0 else name
		stored = h.reads[inst.key]
		if stored.base == shader.bBool and inst.b < 0: return "({value} != 0)"   # its word
		return value
	if op == irCall:
		args = []
		for v in inst.args:
			if h.tys[v].base == shader.bSampler and shader.isStorage(h.tys[v].sid):
				args.push(h.hTexturePart(h.texts[v], "_t"))
			elif h.tys[v].base == shader.bSampler:
				args.push("{h.hTexturePart(h.texts[v], "_t")}, {h.hTexturePart(h.texts[v], "_s")}")
			else:
				args.push(h.texts[v].copy())
		items = ".items" if t.arr >= 0 else ""
		return "{hFnName(inst.key)}({args.join(", ")}){items}"
	h.hArith(op, t, a, b, inst)

# a texture's HLSL texture or sampler: name_t and name_s, an element of an array's name_t[i]
fn hTexturePart(h HlslWriter, text str, suffix str):
	match text.indexOf("["):
		i: text[..i] + suffix + text[i..]
		none: text + suffix

# a part of value a of type at: a component, a column, a field, an element (at index b)
fn hPartOf(h HlslWriter, a str, at shader.Ty, imm i64, b str):
	if b != "": return "{a}[{b}]"
	if at.base == shader.bStruct and at.arr < 0: return "{a}.{hname(h.structs.fields[at.sid][imm])}"
	if at.isVector(): return "{a}.{shader.swizzleSets[0][imm..imm + 1]}"
	"{a}[{imm}]"

# value v of type from as type t: numbers cast component by component, a number spread over a
# vector, a bool from a number (whether it is not zero) and a number from a bool
fn hConvert(h HlslWriter, v str, from shader.Ty, t shader.Ty):
	if from.isSameTy(t): return v.copy()
	if t.base == shader.bBool and from.base != shader.bBool: return "({v} != 0)"
	"(({h.hHtype(t)})({v}))"

# + - * / % and the bitwise operations (HLSL's * is element by element on matrices, as Zap's; a
# float's % is the truncated quotient's remainder, as Zap's on the CPU and SPIR-V's OpFRem)
fn hArith(h HlslWriter, op i64, t shader.Ty, a str, b str, inst IrInst):
	if op == irRem and t.base == shader.bFloat: return "fmod({a}, {b})"
	text = "+" if op == irFAdd or op == irAdd
		else "-" if op == irFSub or op == irSub
		else "*" if op == irFMul or op == irMul
		else "/" if op == irFDiv or op == irDiv
		else "%" if op == irRem
		else ("&&" if t.base == shader.bBool else "&") if op == irAnd
		else ("||" if t.base == shader.bBool else "|") if op == irOr
		else ("!=" if t.base == shader.bBool else "^") if op == irXor
		else "<<" if op == irShl
		else ">>" if op == irShr
		else ""
	if text == "":
		fail("shader: an operation {inst.op} HLSL has no form for")
	"({a} {text} {b})"

# a built-in function: its HLSL name, its arguments in its order (sign's result cast: HLSL's is an
# int), or an operation across the lanes (a wave's)
fn hBuiltin(h HlslWriter, inst IrInst, t shader.Ty):
	if shader.laneFunctions.find(.zap == inst.key) is lane:
		return "{lane.hlsl}({inst.args.map(h.texts[it].copy()).join(", ")})"
	f = shader.builtinFunctions.find(.zap == inst.key) ?? fail("shader: no built-in {inst.key}")
	parts = f.order.map(h.texts[inst.args[it]].copy())
	call = "{f.hlsl}({parts.join(", ")})"
	"(({h.hHtype(t)}){call})" if f.zap == "sign" else call

# ---------- the entry point ----------

# a compute stage's main: run by groups of groupSize invocations, the values the GPU gives it set
# (as int3, int), the entry called
fn hComputeEntry(mut h HlslWriter, entry str, groupSize i64[]):
	h.hLine("[numthreads({groupSize[0]}, {groupSize[1]}, {groupSize[2]})]")
	h.hLine(r"void main(uint3 zapGlobalId : SV_DispatchThreadID, uint3 zapLocalId : SV_GroupThreadID, uint3 zapGroupId : SV_GroupID, uint zapLocalIndex : SV_GroupIndex) {")
	for (name, given) in [
		("globalId", "int3(zapGlobalId)"),
		("localId", "int3(zapLocalId)"),
		("groupId", "int3(zapGroupId)"),
		("localIndex", "int(zapLocalIndex)")
	]:
		if h.reads.get(name) != none:
			h.hLine("\t{name} = {given};")
	h.hLine("\t{hFnName(entry)}();")
	h.hLine("}")

# main: the entry's arguments made of the stage's inputs (a vertex stage's attributes, the
# values passed on), the entry called, what it gives written out: a vertex stage's position
# with its depth from -1..1 to 0..1 and y flipped for a target, the values passed on, the pixel
# stage's targets and depth
fn hEntryPoint(
	mut h HlslWriter,
	prog GpuProgram,
	s shader.StageLayout,
	l shader.Lowering,
	entry str,
	vs shader.StageLayout
):
	g = prog.fns.find(.name == entry) ?? fail("shader: no entry {entry}")
	varyings = vs.vars.filter(.qual == shader.qOut)
	if s.stage == shader.stageVertex:
		h.hLine(r"struct ZapAttributes {")
		for v in s.vars:
			if v.qual == shader.qIn:
				h.hLine("\t{v.tname.hlslOfTree()} {v.name} : ATTR{v.location};")
		h.hLine("\tuint zapVertexId : SV_VertexID;")
		h.hLine("\tuint zapInstanceId : SV_InstanceID;")
		h.hLine("};")
	h.hLine(r"struct ZapVaryings {")
	h.hLine("\tfloat4 zapPosition : SV_Position;")
	for v in varyings:
		location = l.between.findIndex(passedName(.name) == v.name) ?? 0
		interpolation = "nointerpolation " if v.flat else ""
		h.hLine("\t{interpolation}{v.tname.hlslOfTree()} {v.name} : VARY{location};")
	h.hLine("};")
	args = []
	param = 0
	for arg in s.args:
		if arg.kind == shader.argPart: continue
		t = g.tys[g.params[param]]
		param += 1
		values = arg.vars.map(
			"int(zapIn.zapVertexId)" if it == "zapVertexIndex"
			else "int(zapIn.zapInstanceId)" if it == "zapInstanceIndex"
			else "zapIn.{it}"
		)
		args.push(
			values[0].copy() if arg.kind == shader.argValue
			else "zapMake_{h.hStructName(t.sid)}({values.join(", ")})"
		)
	call = "{hFnName(entry)}({args.join(", ")})"
	r = s.result
	if s.stage == shader.stageVertex:
		h.hLine(r"ZapVaryings main(ZapAttributes zapIn) {")
		h.hLine("\t{h.hHtype(g.ret)} zapResult = {call};")
		position = "zapResult._0" if r.kind == shader.resultTuple else "zapResult"
		h.hLine("\tZapVaryings zapOut;")
		h.hLine("\tzapOut.zapPosition = float4({position}.x, {position}.y * zapFlipY, ({position}.z + {position}.w) * 0.5, {position}.w);")
		if r.kind == shader.resultTuple:
			if r.second == shader.resultValue:
				h.hLine("\tzapOut.{r.vars[0]} = zapResult._1;")
			else:
				second = h.structs.members[g.ret.sid][1].sid
				for i, name in r.vars:
					h.hLine("\tzapOut.{name} = zapResult._1.{hname(h.structs.fields[second][i])};")
		h.hLine("\treturn zapOut;")
		h.hLine("}")
		return
	if r.kind == shader.resultFields:
		h.hLine(r"struct ZapTargets {")
		for v in s.vars.filter(.qual == shader.qOut):
			if v.name == shader.depthOutput:
				h.hLine("\tfloat {v.name} : SV_Depth;")
			else:
				h.hLine("\tfloat4 {v.name} : SV_Target{v.location};")
		h.hLine("};")
		h.hLine(r"ZapTargets main(ZapVaryings zapIn) {")
	elif r.kind == shader.resultValue:
		h.hLine(r"float4 main(ZapVaryings zapIn) : SV_Target0 {")
	else:
		h.hLine(r"void main(ZapVaryings zapIn) {")
	if h.reads.get("pixelPosition") != none:
		h.hLine("\tpixelPosition = float4(zapIn.zapPosition.xyz, 1.0 / zapIn.zapPosition.w);")
	if r.kind == shader.resultNone:
		h.hLine("\t{call};")
	elif r.kind == shader.resultValue:
		h.hLine("\treturn {call};")
	else:
		h.hLine("\t{h.hHtype(g.ret)} zapResult = {call};")
		h.hLine("\tZapTargets zapOut;")
		for i, name in r.vars:
			h.hLine("\tzapOut.{name} = zapResult.{hname(h.structs.fields[g.ret.sid][i])};")
		h.hLine("\treturn zapOut;")
	h.hLine("}")

# the HLSL type of a type in the tree's words (an input's, a value passed on)
fn hlslOfTree(tname str):
	t = shader.tyOfName(tname, []) ?? fail("shader: a variable of type {tname}")
	"{hBaseWord(t.base)}{t.rows}" if t.rows > 1 else hBaseWord(t.base)
