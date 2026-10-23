# The translated program written into a dir: its functions a few hundred to a file (module game),
# the table that registers them with cpu's dispatcher, and the program, which loads the
# executable (its data, and code the translation did not see) and runs it on the HLE kernel.

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
	texts.push("\n# the translated functions given to the dispatcher, by address\npub fn register():\n\tcpu.functions.clear()\n{calls}")
	texts

# Writes the program for `executable` into dir; the program's path.
pub fn writeProgram(dir str, name str, executable str, functions Function[]) str:
	game = "{dir}/game"
	fs.createDir(game) ?? fail("cannot make {game}: {error}")
	starts {i64: bool} = {}
	for f in functions:
		starts[f.at] = true
	texts = functions.map("\n{.emitFunction(starts).join("\n")}\n")
	_ = fs.writeNumbered("{game}/functions", ".zap", header, texts, functionsEach) ??
		fail("cannot write {game}: {error}")
	_ = fs.writeNumbered("{game}/table", ".zap", header, tableTexts(functions), 1_000_000) ??
		fail("cannot write {game}: {error}")
	program = "{dir}/{name}.zap"
	text = [
		"# {name} recompiled by recomp.switch: run it from the repository root.",
		"",
		"import fs",
		"import game",
		"import recomp.switch.frontend",
		"import recomp.switch.horizon",
		"",
		"game.register()",
		"# the executable where it was translated from, else beside the program (an app's files)",
		"path = \"{executable}\"",
		"if not fs.exists(path): path = fs.join(fs.dirOf(exePath()), \"{fs.fileName(executable)}\")",
		"k = horizon.launch(path) ?? fail(error)",
		"k.traceCalls = \"--calls\" in args",
		"k.gpu.recordDir = args.option(\"--record-shaders\") ?? \"\"",
		"why = frontend.play(k)",
		"for line in k.log:",
		"\tprint(line)",
		"print(\"-- \{why}\")",
		"for line in k.gpuReport():",
		"\tprint(line)",
		""
	]
	fs.writeChanged(program, text.join("\n").bytes()) ?? fail("cannot write {program}: {error}")
	program
