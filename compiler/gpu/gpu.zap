# The GPU's code in a program: files whose names end in `.gpu.zap` hold it. Their types (the
# vertex, the values passed on, the parameters) are the program's like any module's, while their
# functions and constants are the GPU's: the CPU's code never calls them. `shader(lit.vertex,
# lit.pixel)` names a program's stages, functions of a module's GPU files (a single function: a
# pass over a whole target). Once every module is loaded, each call's program is laid out by the
# shader compiler (compiler/shader) from the declarations of its modules' GPU files as the parser
# read them (their layout's units, below), and each parameter struct gets the packer the shader
# compiler writes for it (`gpuName`, `gpuWrite`), added to its module. Once the program is
# checked, the stages' code is lowered to the intermediate form (irgpu.zap) and written as
# SPIR-V (irspirv.zap) and HLSL (irhlsl.zap): the call is the string literal of its binaries and
# reflection.

import shader
import fs

fn packersWord():
	TraceWord("packers", "the packers written for the shaders' parameter structs")

fn shadersWord():
	TraceWord(
		"shaders",
		"each stage's HLSL and SPIR-V (shaders=dir: written there as .hlsl and .spv files)"
	)

# the shader(...) calls the parser met (their nodes) and the file of each
mut shaderCalls (NodeId, str)[] = []
# the programs of the calls prepared before the check, finished after it (their nodes)
mut preparedShaders (NodeId, shader.Prepared)[] = []

# a call of shader(...) parsed in `file`
pub fn noteShaderCall(call NodeId, file str):
	shaderCalls.push((call, file.copy()))

pub fn forgetShaderCalls():
	shaderCalls = []
	preparedShaders = []

# whether a file holds GPU code
pub fn isGpuFile(path str) bool:
	path.endsWith(".gpu.zap")

# a stage named in a call: its module and its function
type Entry:
	module str
	name str
	line i64
	col i64
	file str

# Each call's program laid out and its packers added (false when a call's or a GPU file's error
# was reported: each call is laid out still, so one's error hides none of another's)
pub fn linkShaders(mut prog Program) bool:
	shader.nameError = compileError
	calls = shaderCalls.copy()
	shaderCalls = []
	packed str[] = []
	helped str[] = []
	linked = true
	for (call, file) in calls:
		laid = prog.prepareCall(call, file)
		prog.nodes[call].kind = nStr   # its bytes once the program is checked
		prog.nodes[call].text = ""
		prog.nodes[call].setKids(prog.kidIds, [])
		match laid:
			prepared:
				for p in prepared.packers:
					if "{p.module}:{p.name}" in packed: continue
					packed.push("{p.module}:{p.name}")
					source = methodsSource(p.name, p.source)
					if p.module not in helped:
						helped.push(p.module.copy())
						source += shader.packerHelpers
					adoptGenerated(
						prog,
						p.module,
						source,
						"<packers of {"the program" if p.module == "" else p.module.copy()}>"
					)
				preparedShaders.push((call, prepared))
			error:
				error.reportGpuError()
				linked = false
	match prog.leaveToGpu():
		error:
			error.reportGpuError()
			false
		_: linked

# a call's program laid out: compute(...)'s kernel, or shader(...)'s stages
fn prepareCall(mut prog Program, call NodeId, file str) shader.Prepared ? shader.GpuError:
	n = prog.nodes[call].copy()
	if prog.nodes[n.kids(prog.kidIds)[0]].text == "compute": return prog.compileKernel(call, file)
	prog.compileStages(try prog.entriesOf(call, file, n.kidsFrom(prog.kidIds, 1).copy()))

# an error of the GPU compile told as every other compile error
fn reportGpuError(e shader.GpuError):
	errorAtFile(e.file, e.line, e.col, e.message)

# the shader(...) calls made the bytes of their programs, the program checked (false when a
# call's error was reported: each call is made still)
pub fn finishShaders(mut prog Program) bool:
	if preparedShaders.isEmpty: return true
	c = prog.newChecker()
	finished = true
	for (call, prepared) in preparedShaders:
		match c.shaderBytes(prepared):
			bytes:
				c.nodes[call].text = bytes
			error:
				error.reportGpuError()
				finished = false
	c.giveBack(prog)
	preparedShaders = []
	finished

# The bytes of a prepared program: its entries and what they call lowered (each part's
# parameter left out of the functions), each stage written as SPIR-V and HLSL.
fn shaderBytes(mut c Checker, p shader.Prepared) str ? shader.GpuError:
	stages = p.stages.copy()
	entries = []
	parts {NodeId: i64} = {}
	for s in stages:
		fnd = c.findDeclInModule(s.module, nFnDecl, s.entry) ?? fail("no stage function {s.entry}")
		entries.push(fnd)
		c.enterModuleOf(fnd)
		for i, arg in s.args:
			if arg.kind == shader.argPart:
				t = c.resolveType(c.nodes[c.nodes[fnd].kids(c.kidIds)[i]].types()[0])
				parts[declOf(c.types, t)] = arg.part
	program = try c.lowerGpuProgram(entries, parts)
	spirv = []
	hlsl = []
	models = []
	written = []
	for i, s in stages:
		name = c.nodes[entries[i]].text.copy()
		try c.checkStageValues(program, s.stage, name)
		spirv.push(program.spirvStage(s, p.l, name, p.groupSize))
		text, model = program.hlslStage(s, p.l, name, stages[0], p.groupSize)
		hlsl.push(text)
		models.push(model)
		written.extend(program.stageWrites(program.reachedFns(name)))
	if shadersWord().value() is dir:
		name = stages.map("{.module}.{.entry}").join("-")
		traceShader(dir, name.replace(".", "_"), spirv, hlsl)
	p.programOf(spirv, hlsl, models, written)

# A program's stages shown (ZAP_RUN=shaders): each stage's HLSL and its SPIR-V's instructions,
# or with a dir, each written there as `name.vs.hlsl`, `name.vs.spv`...
fn traceShader(dir str, name str, spirv u32[,], hlsl str[]):
	stages = ["cs"] if spirv.len == 1 else ["vs", "ps"]
	for i, stage in stages:
		if dir == "":
			eprint("// {name} ({stage})\n{hlsl[i]}{shader.disassemble(spirv[i])}")
			continue
		_ = fs.createDir(dir)
		_ = fs.writeFile("{dir}/{name}.{stage}.hlsl", hlsl[i])
		bytes = []
		for word in spirv[i]:
			bytes.pushU32le(word)
		_ = fs.writeBytes("{dir}/{name}.{stage}.spv", bytes)

# The program of a call's stages, laid out from the declarations of the GPU files of their
# modules; a single stage is a pass over a whole target, whose vertex stage the shader compiler
# writes (shader.screenVertex, a function of the runtime's).
fn compileStages(mut prog Program, es Entry[]):
	pixel = es[len - 1]
	pixelFiles = prog.gpuFilesSeen(pixel.module)
	names = pixelFiles.map(.file.copy())
	pixelUnit = try prog.gpuUnit(pixelFiles, 0, pixel.module)
	screen = es.len == 1
	vertex = shader.GpuStage(module = "rt", unit = pixelUnit.copy(), entry = "zapScreenVertex")
	if screen:
		name = "(a screen pass's vertex stage)"
		vertex.unit = try prog.screenUnit(name, names.len)
		names.push(name)
	elif es[0].module == pixel.module:
		vertex.module = es[0].module.copy()
		vertex.entry = es[0].name.copy()
	else:
		vertexFiles = prog.gpuFilesSeen(es[0].module)
		vertex = shader.GpuStage(
			module = es[0].module.copy(),
			unit = try prog.gpuUnit(vertexFiles, names.len, es[0].module),
			entry = es[0].name.copy()
		)
		names.extend(vertexFiles.map(.file.copy()))
	shader.prepareShader(
		names,
		vertex,
		shader.GpuStage(module = pixel.module.copy(), unit = pixelUnit, entry = pixel.name.copy()),
		screen
	)

# The program of a call of compute(kernels.sum, x[, y[, z]]): the kernel, a function of a GPU
# file, run by groups of x * y * z invocations (literals, 1024 at most in all).
fn compileKernel(mut prog Program, call NodeId, file str) shader.Prepared ? shader.GpuError:
	n = prog.nodes[call].copy()
	if n.kids(prog.kidIds).len < 3 or n.kids(prog.kidIds).len > 5:
		return stopAt(file, n.line, n.col, compileError("ComputeSize", []))
	size = []
	for a in n.kidsFrom(prog.kidIds, 2):
		an = prog.nodes[a]
		v = (i64.parse(an.text) ?? 0) if an.kind == nInt else 0
		if v < 1: return stopAt(file, an.line, an.col, compileError("ComputeSize", []))
		size.push(v)
	if size.reduce(1, (acc, x): acc * x) > 1024:
		return stopAt(file, n.line, n.col, compileError("ComputeSize", []))
	while size.len < 3:
		size.push(1)
	kernel = (try prog.entriesOf(call, file, [n.kids(prog.kidIds)[1]]))[0]
	files = prog.gpuFilesSeen(kernel.module)
	shader.prepareCompute(
		files.map(.file.copy()),
		shader.GpuStage(
			module = kernel.module.copy(),
			unit = try prog.gpuUnit(files, 0, kernel.module),
			entry = kernel.name.copy()
		),
		size
	)

# the stages a call names (its arguments `args`): alias.function (a module the calling file's
# module imports) or function (one of that module's), each a function of a GPU file
fn entriesOf(prog Program, call NodeId, file str, args NodeId[]) Entry[] ? shader.GpuError:
	n = prog.nodes[call]
	if args.len < 1 or args.len > 2:
		return stopAt(file, n.line, n.col, compileError("ShaderStages", []))
	callerModule = prog.moduleOfFile(file)
	out = []
	for a in args:
		an = prog.nodes[a]
		e = Entry(
			module = callerModule.copy(),
			name = an.text.copy(),
			line = an.line,
			col = an.col,
			file = file.copy()
		)
		if an.kind == nField and prog.nodes[an.kids(prog.kidIds)[0]].kind == nIdent:
			alias = prog.nodes[an.kids(prog.kidIds)[0]].text
			e.module = prog.importedModule(callerModule, alias) ??
				return stopAt(file, an.line, an.col, compileError("ShaderModule", ["{alias}"]))
		elif an.kind != nIdent:
			return stopAt(
				file,
				an.line,
				an.col,
				compileError("ShaderTakesFunctions", [])
			)
		if not prog.hasGpuFunction(e.module, e.name):
			where = "this module" if e.module == "" else "module {e.module}"
			return stopAt(
				file,
				an.line,
				an.col,
				compileError("ShaderNoFunction", ["{e.name}", "{where}"])
			)
		out.push(e)
	out

# the error that stops the GPU compile at a place of a file
fn stopAt(file str, line i64, col i64, msg str):
	shader.GpuError(file = file.copy(), line, col, message = msg.copy())

# the module a file belongs to (its declarations say; the program's own when none does)
fn moduleOfFile(prog Program, file str):
	if prog.decls.find(prog.nodes[it].file() == file) is d: return prog.nodes[d].mod().copy()
	""

# the module the alias names among those `module` imports
fn importedModule(prog Program, module str, alias str) str?:
	for m in prog.modules:
		if m.id == module:
			for imp in m.imports:
				if prog.nodes[imp].text2() == alias: return prog.nodes[imp].text.copy()
	none

fn hasGpuFunction(prog Program, module str, name str):
	for d in prog.decls:
		n = prog.nodes[d]
		if n.kind == nFnDecl and n.mod() == module and n.text2() == name and isGpuFile(n.file()):
			return true
	false

# the GPU files a stage of `module` sees, each with its module: its own, then those of the
# modules it imports (their functions and constants callable as module.name)
fn gpuFilesSeen(prog Program, module str):
	seen = prog.gpuFilesOf(module).map(GpuFile(.copy(), module.copy()))
	for m in prog.modules:
		if m.id != module: continue
		for imp in m.imports:
			imported = prog.nodes[imp].text
			for file in prog.gpuFilesOf(imported):
				if not seen.any(.file == file):
					seen.push((file.copy(), imported.copy()))
	seen

# the GPU files of a module, in their order
fn gpuFilesOf(prog Program, module str):
	files str[] = []
	for d in prog.decls:
		n = prog.nodes[d]
		if n.mod() == module and isGpuFile(n.file()) and n.file() not in files:
			files.push(n.file().copy())
	files

# generated source (a packer, the screen's vertex stage) parsed into a module, as the file `path`
fn adoptGenerated(mut prog Program, module str, source str, path str):
	mi = -1
	for i in 0..prog.modules.len:
		if prog.modules[i].id == module:
			mi = i
	if mi < 0: return
	if packersWord().on():
		eprint("// {path}\n{source}")
	parsed = parseInternal(source, path, prog.nodes, prog.kidIds).filter(
		not standsIn(prog.nodes, prog.kidIds, it)
	)
	prog.adoptDecls(mi, parsed, path)

# Methods the compiler writes for a type declared elsewhere (a shader's packer, a learnable's
# functions), as a block of the type's name: the methods after a stand-in field (methodsField),
# a struct adoptGenerated drops for the methods it leaves
fn methodsSource(typeName str, methods str):
	lines = methods.lines().map("\t{it}" if it != "" else "")
	"type {typeName}:\n\t{methodsField} i64\n{lines.join("\n")}\n"

methodsField = "zapMethodsOf"

# whether d is the stand-in block of methodsSource
fn standsIn(nodes Node[], kidIds NodeId[], d NodeId):
	nodes[d].kind == nStructDecl and not nodes[d].kids(kidIds).isEmpty and
		nodes[nodes[d].kids(kidIds)[0]].text == methodsField

# The functions and constants of the GPU files marked the GPU's: the checker checks them in its
# terms (gpucheck.zap) and the CPU's code never calls them.
fn leaveToGpu(mut prog Program) ? shader.GpuError:
	kept = []
	for d in prog.decls:
		n = prog.nodes[d]
		if isGpuFile(n.file()):
			if n.kind == nImplDecl:
				return stopAt(n.file(), n.line, n.col, compileError("GpuMethod", []))
			if n.kind == nFnDecl or n.kind == nConstDecl:
				prog.nodes[d].flags |= flagGpu
		kept.push(d)
	prog.decls = kept

# ---------- the layout's units ----------

# The declarations of a module's GPU files as the layout reads them (shader.Unit), from the
# parser's tree: structs and enums, and the functions' signatures, each node at its file, line
# and column. The Zap words of the GPU's types become the shader's (f32 float, Vec3 vec3, Texture
# sampler2D: shader.typeName); a tuple type is a struct of its own (zapTuple<k>, its members _0,
# _1...); an enum is an i32 on the GPU, each declaration of an enum's type an int (its Zap name
# kept, for the CPU's side).
type GpuFront:
	unit shader.Unit
	files str[]   # the files lowered, numbered from `first` in the tree's places
	first i64
	file i64   # the one being lowered, by its place in `files`
	tuples str[]   # the tuple structs made, by their members' types ("vec4,Between")
	modules str[]   # the module of each file
	renamed {str: str}   # an imported module's declaration ("module\tname") -> its name here

# a written type: the tree's name of it, the Zap word it was written with, its array length
# (-1 none, 0 a List's)
type GpuType:
	tname str
	zname str
	arr i64

# a GPU file and the module it is of
type GpuFile:
	file str
	module str

# The unit of the declarations of `files`: the GPU files of module `home`, then those of the
# modules it imports (the first file numbered `first` in the tree's places). An imported
# module's declarations are taken under the name module_name, so they never meet the home
# module's names.
fn gpuUnit(prog Program, seen GpuFile[], first i64, home str) shader.Unit ? shader.GpuError:
	files = seen.map(.file.copy())
	f = newGpuFront(files, first)
	f.modules = seen.map(.module.copy())
	for i, file in files:
		if f.modules[i] != home:
			for d in prog.decls:
				n = prog.nodes[d]
				if n.file() == file and (n.kind in [nFnDecl, nConstDecl, nStructDecl, nEnumDecl]):
					f.renamed[
						"{f.modules[i]}\t{n.declaredName()}"
					] = "{f.modules[i]}_{n.declaredName()}"
	for i, file in files:
		f.file = i
		for d in prog.decls:
			if prog.nodes[d].file() == file:
				try prog.layoutDecl(f, d)
	f.enumsAsInts()
	f.unit

# the name here of a declaration `name` that the file being lowered names: bare, its own module's
# type; after an alias (`vecs.Texture`), the type of the module its module imports so
fn nameHere(prog Program, f GpuFront, name str, alias str):
	if f.file >= f.modules.len: return name.copy()
	own = f.modules[f.file]
	if alias != "" and prog.importedModule(own, alias) is from:
		return (f.renamed.get("{from}\t{name}") ?? name).copy()   # from the home module: as it is
	if f.renamed.get("{own}\t{name}") is here: return here.copy()
	name.copy()

# The unit of a pass over a whole target's vertex stage (shader.screenVertex), numbered `first`
# in the tree's places: a GPU function of the runtime's, parsed once and checked as a GPU file's.
fn screenUnit(mut prog Program, name str, first i64) shader.Unit ? shader.GpuError:
	decl = prog.screenDecl(name)
	f = newGpuFront([name.copy()], first)
	try prog.layoutDecl(f, decl)
	f.unit

# the runtime's GPU function of the file `name`, adopted on first use
fn screenDecl(mut prog Program, name str):
	if prog.decls.findIndex(prog.nodes[it].kind == nFnDecl and prog.nodes[it].file() == name) is i:
		return prog.decls[i]
	prog.adoptGenerated("rt", shader.screenVertex, name)
	i = prog.decls.findIndex(prog.nodes[it].kind == nFnDecl and prog.nodes[it].file() == name) ??
		fail("{name} not adopted")
	prog.nodes[prog.decls[i]].flags |= flagGpu
	prog.decls[i]

fn newGpuFront(files str[], first i64):
	GpuFront(
		unit = shader.Unit(nodes = [], tops = [], structs = [], enums = []),
		files = files.copy(),
		first,
		file = 0,
		tuples = [],
		modules = [],
		renamed = {}
	)

# the tree's place of a node of the file being lowered
fn gpuPos(f GpuFront, n Node):
	shader.posOf(f.first + f.file, n.line, n.col)

# the error that stops the GPU compile at a node of the file being lowered
fn gpuStop(f GpuFront, n Node, msg str):
	stopAt(f.files[f.file], n.line, n.col, msg)

# a declaration of a type the layout knows (a member, a parameter, a struct, a function)
fn typedNode(
	mut f GpuFront,
	kind i64,
	move text str,
	move kids shader.LayoutId[],
	t GpuType,
	pos i64
):
	f.unit.nodes.push(shader.newNode(kind, text, kids, pos))
	d = shader.LayoutId(f.unit.nodes.len - 1)
	f.unit.nodes[d].tname = t.tname.copy()
	f.unit.nodes[d].zname = t.zname.copy()
	f.unit.nodes[d].arr = t.arr
	d

fn plainType():
	GpuType(tname = "", zname = "", arr = -1)

# the declared name of a declaration (its text2 once its module adopted it)
fn declaredName(n Node):
	n.text2().copy() if n.text2() != "" else n.text.copy()

fn layoutType(prog Program, mut f GpuFront, t NodeId) GpuType ? shader.GpuError:
	n = prog.nodes[t].copy()
	if n.kind == nTyArray:
		if n.ival <= 0: return f.gpuStop(n, compileError("GpuArrayLength", []))
		inner = try prog.layoutType(f, n.types()[0])
		if inner.arr >= 0: return f.gpuStop(n, compileError("GpuArrayOfArrays", []))
		return GpuType(tname = inner.tname, zname = inner.zname, arr = n.ival)
	if n.kind == nTyRange: return prog.layoutType(f, n.types()[0])   # a range's values are its base's
	if n.kind != nTyName: return f.gpuStop(n, compileError("GpuType", []))
	if n.text == "n32": return GpuType(tname = "int", zname = "i32", arr = -1)
	if prog.rangeAliasOf(n.text) is written: return prog.layoutType(f, written)
	if n.text.startsWith("Tuple") and n.text2() == "$rt":
		parts = []
		for p in n.types():
			part = try prog.layoutType(f, p)
			if part.arr >= 0: return f.gpuStop(n, compileError("GpuTupleOfArray", []))
			parts.push(part.tname)
		s = f.tupleStruct(parts, f.gpuPos(n))
		return GpuType(tname = s.copy(), zname = s.copy(), arr = -1)
	if n.text == "List" and n.types().len == 1:
		inner = try prog.layoutType(f, n.types()[0])
		if inner.arr >= 0: return f.gpuStop(n, compileError("GpuListOfArrays", []))
		return GpuType(tname = inner.tname, zname = inner.zname, arr = 0)
	GpuType(
		tname = shader.typeName(prog.nameHere(f, n.text, n.text2())),
		zname = n.text.copy(),
		arr = -1
	)

# the written range of the range type named name (`type Band = i32 in 0..=3`), or none
fn rangeAliasOf(prog Program, name str) NodeId?:
	for d in prog.decls:
		n = prog.nodes[d]
		if n.kind == nStructDecl and n.hasFlag(flagTypeAlias) and n.declaredName() == name and
			not n.types().isEmpty and prog.nodes[n.types()[0]].kind == nTyRange:
			return n.types()[0]
	none

# The struct a tuple of these types is (made once): zapTuple<k> { _0 A  _1 B ... }.
fn tupleStruct(mut f GpuFront, parts str[], pos i64):
	signature = parts.join(",")
	if f.tuples.indexOf(signature) is k: return "zapTuple{k}"
	sname = "zapTuple{f.tuples.len}"
	f.tuples.push(signature.copy())
	members = (0..parts.len).map(i:
		typedNode(
			f,
			shader.kDecl,
			"_{i}",
			[],
			GpuType(tname = parts[i].copy(), zname = parts[i].copy(), arr = -1),
			pos
		)
	)
	s = f.typedNode(shader.kStruct, sname.copy(), members, plainType(), pos)
	f.unit.structs.push(sname.copy())
	f.unit.tops.push(s)
	sname

# a struct, an enum or a function's signature of a GPU file
fn layoutDecl(prog Program, mut f GpuFront, d NodeId) ? shader.GpuError:
	n = prog.nodes[d].copy()
	name = prog.nameHere(f, n.declaredName(), "")
	pos = f.gpuPos(n)
	if n.kind == nStructDecl:
		members = []
		for m in n.kids(prog.kidIds):
			fd = prog.nodes[m].copy()
			members.push(
				typedNode(
					f,
					shader.kDecl,
					fd.text.copy(),
					[],
					try prog.layoutType(f, fd.types()[0]),
					f.gpuPos(fd)
				)
			)
		s = f.typedNode(shader.kStruct, name.copy(), members, plainType(), pos)
		f.unit.structs.push(name.copy())
		f.unit.tops.push(s)
	elif n.kind == nEnumDecl:
		variants = []
		for v in n.kids(prog.kidIds):
			vn = prog.nodes[v].copy()
			if not vn.kids(prog.kidIds).isEmpty:
				return f.gpuStop(vn, compileError("GpuVariantWithValues", ["{name}", "{vn.text}"]))
			variants.push(f.typedNode(shader.kDecl, vn.text.copy(), [], plainType(), f.gpuPos(vn)))
		e = f.typedNode(shader.kEnum, name.copy(), variants, plainType(), pos)
		f.unit.enums.push(name.copy())
		f.unit.tops.push(e)
	elif n.kind == nFnDecl:
		params = []
		for p in n.kids(prog.kidIds):
			pn = prog.nodes[p].copy()
			params.push(
				typedNode(
					f,
					shader.kDecl,
					pn.text.copy(),
					[],
					try prog.layoutType(f, pn.types()[0]),
					f.gpuPos(pn)
				)
			)
		result = GpuType(tname = "void", zname = "", arr = -1) if n.types().isEmpty
			else try prog.layoutType(f, n.types()[0])
		f.unit.tops.push(f.typedNode(shader.kFunction, name.copy(), params, result, pos))

# each declaration of an enum's type an int
fn enumsAsInts(mut f GpuFront):
	for i in 0..f.unit.nodes.len:
		k = f.unit.nodes[i].kind
		if (k in [shader.kDecl, shader.kFunction]) and f.unit.nodes[i].tname in f.unit.enums:
			f.unit.nodes[i].tname = "int"
