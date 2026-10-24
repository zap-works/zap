# The translated program written into a dir: its functions a few hundred to a file, with the table
# that registers them with cpu's dispatcher, and the program, which loads the executable (its
# data, and code the translation did not see) and runs it on the HLE kernel. A translation of more
# instructions than a build takes (`each`) is written as parts, a module and an entry file each
# (<name>-part<k>.zap), built with `zap build --loadable` and loaded by the program as it starts
# (loadBuild), in the order of their addresses; one that fits is the program's module game.

import fs

functionsEach = 300
registeredEach = 500

header = "# Written by recomp.switch from the game's code: never committed.\n\nimport recomp.switch.arm64\nimport recomp.switch.cpu\n"

# the table's functions: register0... each adding a part, register calling them in order
fn tableTexts(fs Function[]):
	texts = []
	parts = (fs.len + registeredEach - 1) / registeredEach
	for p in 0..parts:
		lines = ["\nfn register{p}():"]
		for f in fs[p * registeredEach..((p + 1) * registeredEach).min(len)]:
			lines.push("\tcpu.functions.push(cpu.Translated(at = 0x{f.at:x}, end = 0x{f.end:x}, run = {functionName(f.at)}))")
		texts.push(lines.join("\n"))
	calls = (0..parts).map("\tregister{it}()").join("\n")
	texts.push("\n# the translated functions given to the dispatcher, by address\npub fn register():\n{calls}")
	texts

# the functions as module `dir`: their files and the table
fn writeModule(dir str, functions Function[]):
	fs.createDir(dir) ?? fail("cannot make {dir}: {error}")
	starts {i64: bool} = {}
	for f in functions:
		starts[f.at] = true
	texts = functions.map("\n{.emitFunction(starts).join("\n")}\n")
	_ = fs.writeNumbered("{dir}/functions", ".zap", header, texts, functionsEach) ??
		fail("cannot write {dir}: {error}")
	_ = fs.writeNumbered("{dir}/table", ".zap", header, tableTexts(functions), 1_000_000) ??
		fail("cannot write {dir}: {error}")

# the functions cut into parts of at most `each` instructions, in order (a function larger than
# that a part alone)
fn partsOf(functions Function[], each i64):
	out = []
	part = []
	held = 0
	for f in functions:
		n = (f.end - f.at) / 4
		if held > 0 and held + n > each:
			out.push(move part)
			part = []
			held = 0
		part.push(f.copy())
		held += n
	if not part.isEmpty: out.push(move part)
	out

# The program for `executable` written into dir, its parts' entry files too: the files to build,
# the parts first and the program last.
pub fn writeProgram(dir str, name str, executable str, functions Function[], each i64) str[]:
	parts = partsOf(functions, each)
	imports = programImports(dir)
	files = []
	if parts.len == 1:
		writeModule("{dir}/game", parts[0])
	else:
		for k, part in parts:
			writeModule("{dir}/part{k}", part)
			file = "{dir}/{name}-part{k}.zap"
			text = "# Part {k} of {name}'s translation: built with zap build --loadable, loaded by {name}.zap.\n\n{imports}import part{k}\n\npart{k}.register()\n"
			fs.writeChanged(file, text.bytes()) ?? fail("cannot write {file}: {error}")
			files.push(file)
	program = "{dir}/{name}.zap"
	text = [
		"# {name} recompiled by recomp.switch: run it from the repository root.",
		"",
		"{imports}{"import game\n" if parts.len == 1 else ""}",
		"# the program's statements are a function's: a part laid out as the program has no binding",
		"fn play():",
		"\tcpu.functions.clear()",
		"\tgame.register()" if parts.len == 1 else loadLines(name, parts.len),
		"\t# the executable where it was translated from, else beside the program (an app's files)",
		"\tpath = \"{executable}\"",
		"\tif not fs.exists(path): path = fs.join(fs.dirOf(exePath()), \"{fs.fileName(executable)}\")",
		"\tk = horizon.launch(path) ?? fail(error)",
		"\tk.traceCalls = \"--calls\" in args",
		"\tk.gpu.recordDir = args.option(\"--record-shaders\") ?? \"\"",
		"\t{playLine(dir)}",
		"\tfor line in k.log:",
		"\t\tprint(line)",
		"\tprint(\"-- \{why}\")",
		"\tfor line in k.gpuReport():",
		"\t\tprint(line)",
		"",
		"play()",
		""
	]
	fs.writeChanged(program, text.join("\n").bytes()) ?? fail("cannot write {program}: {error}")
	files.push(program)
	files

# the parts loaded from beside the program's executable, in order
fn loadLines(name str, count i64):
	at = "fs.join(fs.dirOf(exePath()), \"{name}-part\{k}.exe\")"
	"\tfor k in 0..{count}:\n\t\tloadBuild({at}) ?? fail(error)"

# the modules the program imports, a line each: a part imports the same, so both lay out the
# state alike
fn programImports(dir str):
	names = [
		"fs",
		"recomp.switch.cpu",
		"recomp.switch.frontend",
		"recomp.switch.horizon",
		"recomp.switch.render"
	]
	if rendersWith(dir): names.push("programs")
	names.map("import {it}\n").join("")

# the frontend's call: with the program table the shaders tool wrote beside the program
# (<dir>/programs/, `tools/shaders.zap ... --out <dir>`), the frames are drawn by the renderer
fn playLine(dir str):
	if not rendersWith(dir): return "why = frontend.play(k)"
	fields = [
		"code = programs.programCode",
		"textures = programs.programTextures",
		"attributes = programs.programAttributes",
		"setParams = programs.setProgramParams"
	]
	"why = frontend.play(k, render.ShaderTable({fields.join(", ")}))"

fn rendersWith(dir str):
	fs.isDir(fs.join(dir, "programs"))
