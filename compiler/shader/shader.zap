# The shader compiler's own part: a program's stages, functions of its modules' GPU files,
# compiled when the program that names them is built (`shader(lit.vertex, lit.pixel)` in Zap code
# is the bytes made here, a string literal), so the running program hands the GPU binaries it
# already has. mc lowers the stages' code to its intermediate form (mc/irgpu.zap) and writes it
# (mc/irspirv.zap, mc/irhlsl.zap); this module keeps what both backends lay their bindings out
# from and the bytes:
#   - the program's layout (lower.zap): the parameter block's parts, the textures, the storage
#     buffers, the vertex inputs, the values passed on, the texture arrays (the reflection);
#   - for each parameter struct, the Zap source of its packer (packer.zap), which the compiler
#     adds to the struct's module;
#   - the stages' SPIR-V, for Vulkan, checked by check.zap, and their DXIL, for Direct3D 12: the
#     HLSL compiled by DXC, Microsoft's compiler, run here (dxc.exe from its official release,
#     one for the machine outside every checkout, findDxc). Without it the DXIL is left empty.
# The bytes (little-endian 32-bit words): "ZSH2", the parameter block's size, the parts (each
# its name as a string: its length and its bytes padded to a word; its offset in bytes; its
# first texture and their count, its first storage buffer and their count, its first texture
# array and their count), the textures (binding, kind), the storage buffers (binding), the
# vertex inputs (location, component type, size, stream, offset), the vertex's and the
# instance's strides, then the vertex SPIR-V, the pixel SPIR-V, the vertex DXIL and the pixel
# DXIL, each its length in bytes and its bytes padded to a word, then the texture arrays
# (binding, kind, length; 0 unbounded).

import fs

mut warnedNoDxc = false

# a stage's declarations: its module (its id, "" the program's own), those of the module's GPU
# files (mc/gpu.zap) and the entry function
pub type GpuStage:
	module str
	unit Unit
	entry str

# the Zap source of a parameter struct's packer, for its module
pub type Packer:
	module str
	name str
	source str

# A program laid out: a vertex stage and a pixel stage, or a compute stage and the size of its
# groups. Its parameters' packers are known (the program checks the code that calls them), its
# stages are written once the program is checked.
pub type Prepared:
	names str[]
	stages StageLayout[]
	groupSize i64[] = []   # a compute stage's groups: invocations along x, y and z
	l Lowering
	packers Packer[]

# The program of a vertex stage and a pixel stage (`screen`: a pass over a whole target, whose
# vertex stage, screenVertex, the compiler writes) laid out and its packers written. `names` are
# the files their declarations' places number (posOf), for messages.
pub fn prepareShader(
	names str[],
	vertex GpuStage,
	pixel GpuStage,
	screen bool
) Prepared ? GpuError:
	sourceNames = names.copy()
	l = newLowering()
	vs = try vertex.unit.layoutStage(vertex.entry, vertex.module, stageVertex, l)
	ps = try pixel.unit.layoutStage(pixel.entry, pixel.module, stageFragment, l)
	units = [pixel.unit.copy()] if screen else [vertex.unit.copy(), pixel.unit.copy()]
	Prepared(
		names = names.copy(),
		stages = [vs, ps],
		l = l.copy(),
		packers = try l.packersOf(units, vertex.module)
	)

# The program of a compute stage, its groups of `size` invocations (x, y, z), laid out and its
# packers written.
pub fn prepareCompute(names str[], kernel GpuStage, size i64[]) Prepared ? GpuError:
	sourceNames = names.copy()
	l = newLowering()
	ks = try kernel.unit.layoutStage(kernel.entry, kernel.module, stageCompute, l)
	Prepared(
		names = names.copy(),
		stages = [ks],
		groupSize = size.copy(),
		l = l.copy(),
		packers = try l.packersOf([kernel.unit.copy()], kernel.module)
	)

# the packer of each part, its struct declared in the first unit that has it (of `module`, the
# first stage's)
fn packersOf(l Lowering, units Unit[], module str) Packer[] ? GpuError:
	packers = []
	for part in l.parts:
		u = units[len - 1].copy()
		if part.module == module:
			if units.find(.findTop(kStruct, part.name) != none) is first:
				u = first.copy()
		params = l.params[part.firstParam..part.firstParam + part.params]
		packers.push(
			Packer(
				module = part.module.copy(),
				name = part.name.copy(),
				source = try u.packerSource(part, params, part.partName())
			)
		)
	packers

# The bytes of a prepared program from its stages' SPIR-V (checked) and HLSL (compiled to DXIL
# when DXC is at hand, by the profile of shader model 6.x its `models` say), in the stages'
# order; `written` the storage buffers a compute stage writes.
pub fn programOf(p Prepared, spirv u32[,], hlsl str[], models i64[], written str[]) str:
	sourceNames = p.names.copy()
	kinds = ["vs", "ps"] if p.groupSize.isEmpty else ["cs"]
	profiles = (0..kinds.len).map("{kinds[it]}_6_{models[it]}")
	for i, words in spirv:
		checkSpirv(p.names, ["vertex", "pixel", "compute"][p.stages[i].stage], words)
	dxc = findDxc()
	dxil = []
	for i, code in hlsl:
		dxil.push(dxilOf(dxc, code, profiles[i], p.names) if dxc != "" else "")
	if dxc == "" and not warnedNoDxc:
		eprint("note: no DXC ({dxcDir()}/dxc.exe could not be fetched, or dxc in ZAP_SETUP): the shaders are built without DXIL, so Direct3D 12 cannot draw them")
		warnedNoDxc = true
	binaries = spirv.map(wordBytes(it))
	binaries.extend(dxil)
	p.l.programBytes(binaries) if p.groupSize.isEmpty
		else p.l.computeBytes(binaries, p.groupSize, written)

# the name a part goes by in the reflection: its struct's, qualified by its module
pub fn partName(p Part) str:
	p.name.copy() if p.module == "" else "{p.module}.{p.name}"

fn checkSpirv(names str[], stage str, words u32[]):
	problems = validate(words)
	if not problems.isEmpty:
		fail("shader {names.join(", ")}: the {stage} stage's SPIR-V is wrong: {problems[..problems.len.min(4)].join("; ")}")

# ---------- the bytes ----------

fn putWord(mut out u8[], v i64):
	out.pushU32le(v)

fn putBytes(mut out u8[], bytes str):
	putWord(out, bytes.len)
	out.extend(bytes.bytes())
	while out.len % 4 != 0:
		out.push(0)

fn wordBytes(words u32[]) str:
	out = []
	for w in words:
		putWord(out, w)
	str(move out)

# binaries: the vertex and pixel SPIR-V, then the vertex and pixel DXIL
fn programBytes(l Lowering, binaries str[]) str:
	out = []
	out.extend("ZSH2".bytes())
	putParts(out, l)
	putWord(out, l.buffers.len)
	for b in l.buffers:
		putWord(out, b)
	putWord(out, l.inputs.len)
	for i in l.inputs:
		putWord(out, i.location)
		putWord(out, i.base)
		putWord(out, i.rows)
		putWord(out, i.stream)
		putWord(out, i.offset)
	putWord(out, l.vertexStride)
	putWord(out, l.instanceStride)
	for b in binaries:
		putBytes(out, b)
	putArrays(out, l)
	str(move out)

# A compute program's bytes: "ZSC1", the parameter block and its parts, the textures as a
# program's, the storage buffers (binding, and 1 when the stage writes it), the groups' size (x,
# y, z), its SPIR-V and its DXIL, the texture arrays. binaries: the SPIR-V, then the DXIL
fn computeBytes(l Lowering, binaries str[], size i64[], written str[]) str:
	out = []
	out.extend("ZSC1".bytes())
	putParts(out, l)
	putWord(out, l.buffers.len)
	for b in l.buffers:
		putWord(out, b)
		name = l.resources.find(.kind == resBuffer and bufferBase + .binding == b) ??
			fail("shader: a buffer without its field")
		putWord(out, 1 if name.name in written else 0)
	for k in size:
		putWord(out, k)
	for b in binaries:
		putBytes(out, b)
	putArrays(out, l)
	str(move out)

# the parameter block's size and parts, and the textures
fn putParts(mut out u8[], l Lowering):
	putWord(out, l.paramBytes.alignUp(16))
	putWord(out, l.parts.len)
	for p in l.parts:
		putBytes(out, p.partName())
		putWord(out, p.offset)
		putWord(out, p.firstTexture)
		putWord(out, p.textures)
		putWord(out, p.firstBuffer)
		putWord(out, p.buffers)
		putWord(out, p.firstArray)
		putWord(out, p.arrays)
	putWord(out, l.samplers.len)
	for s in l.samplers:
		putWord(out, s.binding)
		putWord(out, s.kind)

# the texture arrays
fn putArrays(mut out u8[], l Lowering):
	putWord(out, l.arrays.len)
	for a in l.arrays:
		putWord(out, a.binding)
		putWord(out, a.kind)
		putWord(out, a.count)

# ---------- DXC ----------

fn dxcWord():
	SetupWord("dxc", "dxc=<path>: where dxc.exe is (the program or its dir), for the shaders' DXIL")

# dxc.exe: dxc of ZAP_SETUP (the program or its dir), else the machine's (dxcDir), fetched there when it
# is missing (once a process: a fetch that failed says so once); "" none
fn findDxc():
	if dxcWord().value() is p:
		named = p.copy() if p.endsWith(".exe") else "{p}/dxc.exe"
		return named if fs.exists(named) else ""
	if not fs.isFetched(dxcDir()) and not warnedNoDxc:
		fetchDxc(dxcDir())
	"{dxcDir()}/dxc.exe" if fs.isFetched(dxcDir()) else ""

# the dir of this machine's DXC, one for every checkout and worktree
fn dxcDir():
	"{fs.cacheDir("zap")}/dxc"

dxcReleases = "https://api.github.com/repos/microsoft/DirectXShaderCompiler/releases/latest"

# DXC's latest release for Windows unpacked into dir (its x64 programs); nothing when it cannot be
# fetched
fn fetchDxc(dir str):
	if exeSuffix() != ".exe": return
	url = fs
		.fetchText(dxcReleases)
		.split("\"")
		.find(.startsWith("https://") and "/dxc_" in it and .endsWith(".zip")) ??
		return
	eprint("note: fetching DXC, Microsoft's shader compiler, into {dir} (once a machine)")
	fs.fetchUnpacked(url, "bin/x64", dir)

# the DXIL of a stage's HLSL, compiled by DXC (kept in build/shaders by the HLSL's hash: a
# shader built again is not compiled again). Written and compiled under names of this process,
# then moved into place whole: a build beside it making the same shader never reads half a file.
fn dxilOf(dxc str, hlsl str, profile str, names str[]):
	_ = fs.createDir("build/shaders")
	key = "build/shaders/{(hlsl.hash() & 0x7FFFFFFFFFFFFFFF)}-{profile}"
	source = "{key}.hlsl"
	object = "{key}.dxil"
	if fs.exists(object) and (fs.readFile(source) ?? "") == hlsl: return fs.readFile(object) ?? ""
	own = "{key}-{processId()}"
	_ = fs.writeFile("{own}.hlsl", hlsl)
	command = "\"{dxc}\" -nologo -T {profile} -E main -HV 2021 -Qstrip_reflect -Qstrip_debug -Wno-parentheses-equality -Fo \"{own}.dxil\" \"{own}.hlsl\""
	if Process.run(command) != 0 or not fs.exists("{own}.dxil"):
		fail("shader {names.join(", ")}: DXC did not compile the HLSL written for it ({own}.hlsl)")
	dxil = fs.readFile("{own}.dxil") ?? ""
	# (a move refused while another reads the cached file leaves that one, the same)
	_ = fs.moveFile("{own}.hlsl", source)
	_ = fs.moveFile("{own}.dxil", object)
	_ = fs.deleteFile("{own}.hlsl")
	_ = fs.deleteFile("{own}.dxil")
	dxil
