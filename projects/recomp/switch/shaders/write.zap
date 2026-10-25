# Programs translated together into one module of Zap GPU code: <dir>/translated/, a file a
# program (<name>.gpu.zap) and types.gpu.zap, their shared `Varyings`; and a program naming each
# entry, which builds only when every translation compiles.

import fs

pub module = "translated"

# A program to translate, by the name its declarations end with.
pub type Source:
	name str
	program Program
	group i64[]   # a compute program's group size
	integers {i64: bool} = {}   # the handles of its textures of integers (true: signed), the TIC's

# A file as a program: deko3d's DKSH (.dksh, named after its dir and its file), else the bytes a
# game hands the GPU from the program's start (SPH and code), named P<the file's stem>, the hash
# its recording gave it.
pub fn readSource(path str) Source ? str:
	bytes = fs.readBytes(path) ?? return "cannot read {path}"
	if fs.extension(path) == ".dksh":
		d = try readDksh(bytes)
		parts = path.replace("\\", "/").split("/")
		dir = parts[len - 2] if parts.len > 1 else ""
		return Source(
			name = camelName("{dir}_{fs.stem(path)}"),
			program = d.program,
			group = d.group
		)
	if bytes.len < headerSize: return "{path}: shorter than an SPH"
	p = readProgram(bytes, 0, .Vertex)
	Source(name = "P{fs.stem(path)}", program = p, group = [])

# `deko_basic_color_fsh` as DekoBasicColorFsh
pub fn camelName(stem str) str:
	stem.split("_").filter(not .isEmpty).map("{it[..1].upper()}{it[1..]}").join("")

# Each source translated into <dir>/translated/: what was translated (a program whose stage
# or control flow could not be is left out, its reason in `skipped`).
pub type Translation:
	shaders Shader[]
	skipped str[]

pub fn writeModule(sources Source[], dir str) Translation ? str:
	t = newTable()
	at = fs.join(dir, module)
	fs.createDir(at) ?? return "cannot make {at}: {error}"
	interface = interfaceOf(sources.map(.program.copy()))
	shaders = []
	skipped = []
	for s in sources:
		got = t.translateProgram(s.program, s.name, interface, s.group, s.integers)
		if got is error:
			skipped.push("{s.name}: {error}")
			continue
		shader = got ?? continue
		fs.writeFile(fs.join(at, "{s.name}.gpu.zap"), shader.text) ?? return "cannot write: {error}"
		shaders.push(shader)
	fs.writeFile(fs.join(at, "types.gpu.zap"), typesFile(interface, shaders)) ??
		return "cannot write: {error}"
	Translation(shaders, skipped)

# The module of the sources written into dir with programs.zap, the program naming each entry,
# and that program built: the translation, and what the build said when it failed ("" when built)
pub fn writeBuilt(sources Source[], dir str) (Translation, str) ? str:
	done = try writeModule(sources, dir)
	fs.writeFile("{dir}/programs.zap", namingProgram(done.shaders, [])) ??
		return "cannot write {dir}/programs.zap: {error}"
	built = Process.output("{zapPath()} build {dir}/programs.zap")
	(done, "" if built.code == 0 else built.out)

# A program naming the entries: the module's recorded sets with `pairs` (programsModule), else
# each vertex stage with a pixel stage (in turn, each at least once); and each compute stage with
# its group's size.
pub fn namingProgram(shaders Shader[], pairs str[]) str:
	vertices = shaders.filter(.stage == .Vertex)
	pixels = shaders.filter(.stage == .Pixel)
	lines = ["import {module}", ""]
	if not pairs.isEmpty:
		lines.push("import {programsModule}")
		lines.push("")
		for key in pairs:
			lines.push("print(({programsModule}.programCode(\"{key}\") ?? \"\").len)")
	if pairs.isEmpty and not vertices.isEmpty and not pixels.isEmpty:
		for k in 0..vertices.len.max(pixels.len):
			lines.push("print(shader({module}.{vertices[k % vertices.len].entry}, {module}.{pixels[k % pixels.len].entry}).len)")
	for s in shaders:
		if s.stage == .Compute:
			lines.push("print(compute({module}.{s.entry}, {s.group.map("{it}").join(", ")}).len)")
	lines.push("")
	lines.join("\n")

# <dir>/programs.zap naming every entry and, with recorded sets, <dir>/programs/programs.zap
# (programsFile) beside it.
pub fn writePrograms(done Translation, sets TranslatedSet[], dir str) bool ? str:
	if not sets.isEmpty:
		at = fs.join(dir, programsModule)
		fs.createDir(at) ?? return "cannot make {at}: {error}"
		fs.writeFile(fs.join(at, "programs.zap"), programsFile(done.shaders, sets)) ??
			return "cannot write: {error}"
	fs.writeFile(
		fs.join(dir, "programs.zap"),
		namingProgram(done.shaders, sets.map(.key.copy()))
	) ??
		return "cannot write: {error}"
	true
