# A program's stages laid out from their entry functions: what the GPU hands a stage (its vertex
# and instance attributes, the values the vertex stage passed on, the parameters) and what it
# gives back (the clip position and those values, the pixel's colors) are the entry's
# parameters and results, so the compiler declares them as the stage's variables and writes the
# stage's `main`, which reads them, calls the entry and writes what it gives (StageLayout):
#   vertex(v Vertex[, i Instance][, p Params]) Vec4 | (Vec4, Between)
#   pixel([b Between][, p Params]) Vec4 | Targets | nothing
# `v` and `i` are structs of attributes (an attribute per field, at locations in their order:
# the vertex's, then the instance's), or an i32: the vertex's (the instance's) number, for a
# draw without buffers. A second struct of the vertex stage is its parameters, a third its
# instance between them. The pixel stage receives what the vertex stage gives after the
# position (a struct, a field a value passed on; or one value), then its parameters.
#
# A parameter struct is the program's: its numbers, vectors, matrices, bools, enums, fixed
# arrays and nested structs are a part of the one parameter block (std140, at binding 32), its
# textures (Texture, TextureArray, ShadowMap, ShadowMapArray, Texture[] unbounded, TextureArray[N]) and its
# storage buffers (T[]) bindings of their own, numbered in the order of the fields. A
# function's parameter of that type is not passed: every `p.field` reads the block's member or
# the texture itself (`zapP<part>_<field>`, mc/irgpu.zap), so a stage's functions take the
# struct as the entry does and nothing is copied.

pub stageVertex = 0
pub stageFragment = 1
pub stageCompute = 2

pub type Part:
	module str   # the module of its struct (the program's CPU code sets it by this name)
	name str   # its struct's name
	offset i64   # where its numbers start in the block (bytes, a multiple of 16)
	size i64   # the bytes they take
	firstParam i64   # its numbers among the lowering's params, in the order of its fields
	params i64
	firstTexture i64
	textures i64
	firstBuffer i64
	buffers i64
	firstArray i64
	arrays i64

# a texture, a texture array or a storage buffer of a part, as the stages read it: its name
# (zapP<part>_<field>), its kind (resTexture...), its binding (a texture's, an array's in set 1, a
# buffer's before bufferBase is added) and its textures' kind (sampler2D...)
pub type Resource:
	name str
	kind i64
	binding i64
	sampler i64

pub resTexture = 0
pub resArray = 1
pub resBuffer = 2

# what a stage reads of its entry, and the program's numbering as it grows
pub type Lowering:
	parts Part[]
	params Param[]   # every part's numbers, by name
	resources Resource[]
	samplers SamplerSlot[]
	arrays TextureArray[]
	buffers i64[]
	inputs VertexInput[]
	vertexStride i64
	instanceStride i64
	between Field[]   # what the vertex stage passes on (one unnamed field: a single value)
	betweenStruct str   # its struct's name, "" for a single value or none
	targets str[]   # the pixel stage's outputs' types (none: it writes no color)
	paramBytes i64

# a field of a struct as the lowering reads it
pub type Field:
	name str
	tname str
	zname str
	arr i64
	pos i64

# a variable of a stage's interface: an input (an attribute, a value passed on) or an output (a
# value passed on, a target), its type in the tree's words, its location (-1: the program's
# link gives it) and whether it is passed on without interpolation
pub type StageVar:
	name str
	tname str
	qual i64
	location i64
	flat bool

# how main makes an argument of the entry: a part's (not passed: `part` its number), one
# variable's value (an input, or zapVertexIndex, zapInstanceIndex), or a struct of variables (a
# field each)
pub argPart = 0
pub argValue = 1
pub argStruct = 2

pub type StageArg:
	kind i64
	vars str[]
	part i64 = -1

# what main does with the entry's result: nothing (none), writes it to one variable (value: the
# vertex stage's zapPosition, the pixel's zapColor), each field to one (fields: the pixel's
# targets), or its first to zapPosition and its second to one or to each field's (tuple)
pub resultNone = 0
pub resultValue = 1
pub resultFields = 2
pub resultTuple = 3

pub type StageResult:
	kind i64
	vars str[]   # the variables written, in the fields' order (a tuple's second's)
	second i64   # a tuple's second: resultValue or resultFields

# a stage of a program: its entry, how main calls it, and the variables of its interface
pub type StageLayout:
	stage i64
	module str
	entry str
	args StageArg[]
	result StageResult
	vars StageVar[]

pub fn newLowering() Lowering:
	Lowering(
		parts = [],
		params = [],
		resources = [],
		samplers = [],
		arrays = [],
		buffers = [],
		inputs = [],
		vertexStride = 0,
		instanceStride = 0,
		between = [],
		betweenStruct = "",
		targets = [], paramBytes = 0)

# ---------- finding things ----------

pub fn findTop(u Unit, kind i64, nm str) LayoutId?:
	u.tops.find(u.nodes[it].kind == kind and u.nodes[it].text == nm)

pub fn fieldsOf(u Unit, sname str) Field[]:
	s = u.findTop(kStruct, sname) ?? return []
	u.nodes[s].kids.map(m:
		Field(
			name = u.nodes[m].text.copy(),
			tname = u.nodes[m].tname.copy(),
			zname = u.nodes[m].zname.copy(),
			arr = u.nodes[m].arr,
			pos = u.nodes[m].pos
		)
	)

fn isStructName(u Unit, t str):
	t in u.structs

fn isTextureType(t str):
	samplerKinds.any(.glsl == t)

# whether a field of a parameter struct is a texture or a storage buffer (not in the block)
fn isResource(f Field):
	isTextureType(f.tname) or f.arr == 0

# ---------- types ----------

# the type a field of the unit's structs names, its array length applied (unitMembers knew each)
pub fn unitTy(u Unit, tname str, arr i64) Ty:
	t = tyOfName(tname, u.structs) ?? fail("shader: no type {tname} past unitMembers")
	t.arrayOf(arr) if arr >= 0 else t

# each struct's member types, by its place among the unit's structs, for layoutOf; the error at
# the first field whose type the shader does not know
pub fn unitMembers(u Unit) Ty[,] ? GpuError:
	members = []
	for s in u.structs:
		types = []
		for f in u.fieldsOf(s):
			if tyOfName(f.tname, u.structs) == none:
				return stop(f.pos, compileError("ShaderUnknownType", ["{f.tname}"]))
			types.push(u.unitTy(f.tname, f.arr))
		members.push(types)
	members

# ---------- the parts ----------

# The part of struct `sname` (of module `module`, declared in u): found among the parts so
# far, else laid out after them. Its numbers are named zapP<k>_<field>.
pub fn partOf(mut l Lowering, u Unit, module str, sname str, pos i64) i64 ? GpuError:
	if l.parts.findIndex(.module == module and .name == sname) is k: return k
	k = l.parts.len
	fields = u.fieldsOf(sname)
	if fields.isEmpty and u.findTop(kStruct, sname) == none:
		return stop(pos, compileError("ShaderParameterType", ["{sname}"]))
	members = try u.unitMembers()
	start = l.paramBytes.alignUp(16)
	offset = 0
	part = Part(
		module = module.copy(),
		name = sname.copy(),
		offset = start,
		size = 0,
		firstParam = l.params.len,
		params = 0,
		firstTexture = l.samplers.len,
		textures = 0, firstBuffer = l.buffers.len, buffers = 0, firstArray = l.arrays.len, arrays = 0)
	for f in fields:
		name = "zapP{k}_{f.name}"
		if isTextureType(f.tname):
			kind = (tyOfName(f.tname, []) ?? scalar(bVoid)).sid
			if f.arr >= 0:
				binding = l.arrays.len
				l.arrays.push(TextureArray(binding, kind, count = f.arr))
				l.resources.push(
					Resource(name = name.copy(), kind = resArray, binding, sampler = kind)
				)
				part.arrays += 1
			else:
				binding = l.samplers.len
				l.samplers.push((binding, kind))
				l.resources.push(
					Resource(name = name.copy(), kind = resTexture, binding, sampler = kind)
				)
				part.textures += 1
			continue
		if f.arr == 0:
			try u.checkRecord(sname, f, pos)
			l.resources.push(
				Resource(name = name.copy(), kind = resBuffer, binding = l.buffers.len, sampler = 0)
			)
			l.buffers.push(bufferBase + l.buffers.len)
			part.buffers += 1
			continue
		if f.tname == "bool" and f.arr >= 0:
			return stop(pos, compileError("ShaderBoolArray", ["{sname}", "{f.name}"]))
		try u.checkParamField(sname, f, pos)
		a, size = u.unitTy(f.tname, f.arr).layoutOf(true, members)
		offset = offset.alignUp(a)
		l.params.push(
			Param(
				name,
				tname = "uint" if f.tname == "bool" else f.tname.copy(),
				arr = f.arr,
				offset = start + offset,
				pos = f.pos
			)
		)
		part.params += 1
		offset += size
	part.size = offset.alignUp(16)
	l.paramBytes = start + part.size
	l.parts.push(part)
	k

# A storage buffer's element as the CPU's list holds it, so its bytes go as they are: a number
# (f32, i32, u32), a Vec2 or a Vec4, or a struct of those.
fn checkRecord(u Unit, sname str, f Field, pos i64) ? GpuError:
	parts = [
		Field(
			name = f.name.copy(),
			tname = f.tname.copy(),
			zname = f.zname.copy(),
			arr = -1,
			pos = f.pos
		)
	]
	if u.isStructName(f.tname):
		parts = u.fieldsOf(f.tname)
	for g in parts:
		t = tyOfName(g.tname, u.structs) ?? scalar(bVoid)
		ok = g.arr < 0 and g.zname not in u.enums and (t.base in [bFloat, bInt, bUint]) and
			t.cols == 1 and t.rows != 3
		if not ok:
			return stop(
				pos,
				compileError("StorageBufferElement", ["{sname}", "{f.name}", "{g.zname}"])
			)
	if u.isStructName(f.tname):
		try checkRecordOrder(
			f.tname,
			parts.map(.name.copy()),
			parts.map(u.unitTy(.tname, -1)),
			pos
		)

# A struct a storage buffer holds is read at the offsets Vulkan's std430 gives its members, and
# Direct3D's structured buffer packs them (each at the next 4 bytes, the struct as long as its
# members): both must agree. Scalars, Vec2s and Vec4s in an order that leaves no gap, the size a
# multiple of the widest member's alignment, do.
fn checkRecordOrder(sname str, names str[], types Ty[], pos i64) ? GpuError:
	packed = 0
	laid = 0
	widest = 4
	for i in 0..types.len:
		a, size = types[i].layoutOf(false, [])
		laid = laid.alignUp(a)
		if laid != packed:
			return stop(
				pos,
				compileError("ShaderMemberOffset", ["{sname}", "{names[i]}", "{laid}", "{packed}"])
			)
		widest = widest.max(a)
		laid += size
		packed += size
	if laid.alignUp(widest) != packed:
		return stop(
			pos,
			compileError(
				"ShaderBlockSize",
				["{sname}", "{packed}", "{laid.alignUp(widest)}", "{widest}"]
			)
		)

# a number of a parameter struct, as the block can hold it: a bool only at the struct's top
# (stored as a uint), no texture or buffer in a nested struct
fn checkParamField(u Unit, sname str, f Field, pos i64) ? GpuError:
	if not u.isStructName(f.tname): return
	for g in u.fieldsOf(f.tname):
		if g.tname == "bool" or g.isResource():
			return stop(
				pos,
				compileError(
					"ShaderParameterField",
					["{sname}", "{f.name}", "{f.tname}", "{g.name}", "{g.zname}"]
				)
			)
		try u.checkParamField(f.tname, g, pos)

# ---------- a stage ----------

# The layout of the stage whose entry is `entry` (a function u declares): its variables, the
# parts its parameters struct is, how main calls the entry and writes what it gives.
pub fn layoutStage(
	u Unit,
	entry str,
	module str,
	stage i64,
	mut l Lowering
) StageLayout ? GpuError:
	e = u.findTop(kFunction, entry) ?? fail("shader {sourceNames.join(", ")}: no fn {entry}")
	pos = u.nodes[e].pos
	params = u.nodes[e].kids.copy()
	s = StageLayout(
		stage,
		module = module.copy(),
		entry = entry.copy(),
		args = [],
		result = StageResult(kind = resultNone, vars = [], second = resultNone),
		vars = []
	)
	if stage == stageVertex:
		try u.vertexParams(params, module, pos, l, s)
		try u.vertexResult(u.nodes[e].tname, pos, l, s)
	elif stage == stageCompute:
		# a compute stage takes its parameters (or nothing) and gives nothing: it writes buffers
		if params.len > 1 or u.nodes[e].tname != "void":
			return stop(pos, compileError("ComputeStage", []))
		if params.len == 1:
			try u.partParam(params[0], module, l, s)
	else:
		try u.pixelParams(params, module, pos, l, s)
		try u.pixelResult(u.nodes[e].tname, pos, l, s)
	s

fn addVar(mut s StageLayout, name str, tname str, qual i64, location i64):
	s.vars.push(
		StageVar(
			name = name.copy(),
			tname = tname.copy(),
			qual,
			location,
			flat = isIntegerType(tname)
		)
	)

# v (a struct of attributes or the vertex's number), i likewise, p the parameters
fn vertexParams(
	u Unit,
	params LayoutId[],
	module str,
	pos i64,
	mut l Lowering,
	mut s StageLayout
) ? GpuError:
	n = params.len
	if n == 0 or n > 3: return stop(pos, compileError("VertexStageParameters", []))
	streams = [params[0]]
	paramsNode LayoutId? = none
	if n == 3:
		streams.push(params[1])
		paramsNode = params[2]
	elif n == 2:
		t = u.nodes[params[1]].tname
		if t == "int" or t == "uint":
			streams.push(params[1])
		else:
			paramsNode = params[1]
	location = 0
	for k in 0..n:
		p = u.nodes[params[k]].copy()
		if params[k] == paramsNode:
			try u.partParam(params[k], module, l, s)
			continue
		stream = streams.indexOf(params[k]) ?? 0
		if p.tname == "int" or p.tname == "uint":
			s.args.push(
				StageArg(
					kind = argValue,
					vars = ["zapVertexIndex" if stream == 0 else "zapInstanceIndex"]
				)
			)
			continue
		if not u.isStructName(p.tname) or p.arr >= 0:
			return stop(
				p.pos,
				compileError(
					"VertexStageInput",
					["{"vertex" if stream == 0 else "instance"}", "{p.zname}"]
				)
			)
		names = []
		offset = 0
		for f in u.fieldsOf(p.tname):
			t = tyOfName(f.tname, u.structs) ?? scalar(bVoid)
			if f.arr >= 0 or not t.isNumeric() or t.isMatrix():
				return stop(
					p.pos,
					compileError("VertexAttribute", ["{p.tname}", "{f.name}", "{f.zname}"])
				)
			name = "zapIn{stream}_{f.name}"
			s.addVar(name, f.tname, qIn, location)
			l.inputs.push(VertexInput(location, base = t.base, rows = t.rows, stream, offset))
			location += 1
			offset += t.rows * 4
			names.push(name)
		if stream == 0:
			l.vertexStride = offset
		else:
			l.instanceStride = offset
		s.args.push(StageArg(kind = argStruct, vars = names))

# b what the vertex stage passed on (when it passes something), p the parameters
fn pixelParams(
	u Unit,
	params LayoutId[],
	module str,
	pos i64,
	mut l Lowering,
	mut s StageLayout
) ? GpuError:
	first = 0
	if not l.between.isEmpty:
		if params.isEmpty: return stop(pos, compileError("PixelStageInputFirst", []))
		b = u.nodes[params[0]].copy()
		if l.betweenStruct == "":
			if b.tname != l.between[0].tname or b.arr >= 0:
				return stop(
					b.pos,
					compileError("PixelStageInput", ["{l.between[0].zname}", "{b.zname}"])
				)
			s.addVar("zapB", b.tname, qIn, -1)
			s.args.push(StageArg(kind = argValue, vars = ["zapB"]))
		else:
			fields = u.fieldsOf(b.tname)
			if not sameFields(fields, l.between):
				return stop(
					b.pos,
					compileError("PixelStageInputDiffers", ["{b.zname}", "{l.betweenStruct}"])
				)
			for f in fields:
				s.addVar("zapB_{f.name}", f.tname, qIn, -1)
			s.args.push(StageArg(kind = argStruct, vars = fields.map("zapB_{.name}")))
		first = 1
	if params.len > first + 1: return stop(pos, compileError("PixelStageParameters", []))
	if params.len == first + 1:
		try u.partParam(params[first], module, l, s)

fn isIntegerType(t str):
	match tyOfName(t, []):
		ty: ty.base == bInt or ty.base == bUint
		none: false

# whether two structs have the same fields in the same order (names and types)
fn sameFields(a Field[], b Field[]):
	if a.len != b.len: return false
	(0..a.len).all(i:
		a[i].name == b[i].name and a[i].tname == b[i].tname and a[i].arr == b[i].arr
	)

# the entry's parameter struct: its part, not passed
fn partParam(u Unit, p LayoutId, module str, mut l Lowering, mut s StageLayout) ? GpuError:
	t = u.nodes[p].tname.copy()
	if not u.isStructName(t) or u.nodes[p].arr >= 0:
		return stop(u.nodes[p].pos, compileError("StageParameters", ["{u.nodes[p].zname}"]))
	part = try l.partOf(u, module, t, u.nodes[p].pos)
	s.args.push(StageArg(kind = argPart, vars = [], part))

# ---------- results ----------

# the clip position, or the clip position and the values passed on
fn vertexResult(u Unit, result str, pos i64, mut l Lowering, mut s StageLayout) ? GpuError:
	if result == "vec4":
		s.result = StageResult(kind = resultValue, vars = ["zapPosition"], second = resultNone)
		return
	fields = u.fieldsOf(result)
	if not result.startsWith("zapTuple") or fields.len != 2 or fields[0].tname != "vec4":
		return stop(pos, compileError("VertexStageResult", []))
	b = fields[1].copy()
	if u.isStructName(b.tname):
		l.betweenStruct = b.tname.copy()
		names = []
		for f in u.fieldsOf(b.tname):
			t = tyOfName(f.tname, u.structs) ?? scalar(bVoid)
			if f.arr >= 0 or not t.isNumeric() or t.isMatrix():
				return stop(
					pos,
					compileError("VertexOutputField", ["{b.tname}", "{f.name}", "{f.zname}"])
				)
			s.addVar("zapB_{f.name}", f.tname, qOut, -1)
			l.between.push(f.copy())
			names.push("zapB_{f.name}")
		s.result = StageResult(kind = resultTuple, vars = names, second = resultFields)
		return
	t = tyOfName(b.tname, u.structs) ?? scalar(bVoid)
	if b.arr >= 0 or not t.isNumeric() or t.isMatrix():
		return stop(pos, compileError("VertexOutput", ["{b.zname}"]))
	s.addVar("zapB", b.tname, qOut, -1)
	l.between.push(
		Field(name = "", tname = b.tname.copy(), zname = b.zname.copy(), arr = -1, pos = b.pos)
	)
	s.result = StageResult(kind = resultTuple, vars = ["zapB"], second = resultValue)

# the pixel's color, or a struct of its outputs: each Vec4 field a target (`targetN`'s N, another's
# its place among the Vec4s), an f32 the depth (zapDepth); or nothing
fn pixelResult(u Unit, result str, pos i64, mut l Lowering, mut s StageLayout) ? GpuError:
	if result == "void": return
	if result == "vec4":
		s.addVar("zapColor", "vec4", qOut, 0)
		l.targets.push("vec4")
		s.result = StageResult(kind = resultValue, vars = ["zapColor"], second = resultNone)
		return
	if not u.isStructName(result) or result.startsWith("zapTuple"):
		return stop(pos, compileError("PixelStageResult", []))
	names = []
	place = 0
	for f in u.fieldsOf(result):
		if f.tname == "float" and f.arr < 0:
			if s.vars.any(.name == depthOutput):
				return stop(
					pos,
					compileError("PixelOutputTwice", ["{result}", "{f.name}", "the depth"])
				)
			s.addVar(depthOutput, "float", qOut, -1)
			names.push(depthOutput)
			continue
		if f.tname != "vec4" or f.arr >= 0:
			return stop(pos, compileError("PixelTargetType", ["{result}", "{f.name}", "{f.zname}"]))
		target = namedTarget(f.name) ?? place
		place += 1
		if s.vars.any(.qual == qOut and .location == target):
			return stop(
				pos,
				compileError("PixelOutputTwice", ["{result}", "{f.name}", "target {target}"])
			)
		s.addVar("zapT_{f.name}", "vec4", qOut, target)
		l.targets.push("vec4")
		names.push("zapT_{f.name}")
	s.result = StageResult(kind = resultFields, vars = names, second = resultNone)

# the pixel stage's depth output's variable
pub depthOutput = "zapDepth"

# the target a field named targetN writes (N 0 to 7), none for another name
fn namedTarget(name str) i64?:
	if not name.startsWith("target"): return none
	n = try i64.parse(name["target".len..])
	n if n >= 0 and n <= 7 and name == "target{n}" else none
