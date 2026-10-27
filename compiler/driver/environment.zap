# The environment variables (ZAP_SETUP and ZAP_RUN) and their words as their declarations say them
# (`EnvVariable("NAME", "what it does")`, `SetupWord("word", "what it does")`, `RunWord(...)`,
# `TraceWord(...)`, runtime/core/env.zap), read from the sources: `zap doc environment` lists
# those of the compiler, the runtime, std and the dependencies, and a build refuses a word of
# ZAP_SETUP or ZAP_RUN that nothing declares.

import fs

type DeclaredSetting:
	kind str   # EnvVariable, SetupWord, RunWord or TraceWord
	name str
	about str

settingKinds = ["EnvVariable", "SetupWord", "RunWord", "TraceWord"]

# the declarations in a file, in its order
fn settingsIn(file str):
	text = fs.readFile(file) ?? ""
	if not settingKinds.any("{it}(" in text): return []
	toks = (lex(text, file) ?? []).filter(.kind != tkNewline)
	out = []
	for i in 0..toks.len - 5:
		t = toks[i]
		if t.kind == tkUident and t.text in settingKinds and toks[i + 1].kind == tkLparen and
			toks[i + 2].kind == tkStr and toks[i + 3].kind == tkComma and
			toks[i + 4].kind == tkStr:
			out.push(
				DeclaredSetting(
					kind = t.text.copy(),
					name = toks[i + 2].text.copy(),
					about = toks[i + 4].text.copy()
				)
			)
	out

# the declarations in the files
fn settingsInAll(files str[]):
	out = []
	for f in files:
		out.extend(settingsIn(f))
	out

# the dir of the compiler's sources, beside the runtime's
fn compilerDir():
	rt = runtimeDir()
	"{dirPrefix(rt[..rt.len - 1])}compiler"

# the compiler's sources and the runtime's: their declarations hold for every build
fn compilerAndRuntimeFiles():
	rt = runtimeDir()
	files = fs.walk(compilerDir(), sources = true)
	files.extend(runtimeFiles(rt).map(rt + it))
	files

# The words in a variable's list that no declaration of the kinds names end the build, the words
# listed: a misspelt word would otherwise say nothing. They are looked for in the compiler, the
# runtime and the program's own modules, then in everything `zap doc environment` lists (a word of
# an engine program set for a run of another). A zap with no copy of these compiler sources beside its runtime
# (build/base's, which reads build/runtime, or a test's) cannot tell its own words, and checks none.
fn checkWords(prog Program, variable EnvVariable, kinds str[]):
	given = variable.value() ?? return
	if not fs.exists("{compilerDir()}/driver/environment.zap"): return
	own = ownSettings().filter(.kind in kinds).map(.name.copy())
	if given.split(",").all(it == "" or it[..it.indexOf("=") ?? len] in own): return
	files = compilerAndRuntimeFiles()
	addDeclFiles(prog.nodes, prog.kidIds, prog.decls, files)
	if prog.kept is kept: addDeclFiles(kept.nodes, kept.kidIds, kept.decls, files)   # (the kept stages')
	words = wordsDeclared(files, kinds)
	for item in given.split(","):
		word = item[..item.indexOf("=") ?? len]
		if word != "" and word not in words and word not in wordsDeclared(repositoryFiles(), kinds):
			exit(
				2,
				"zap: {variable.name} names no word '{word}': {words.sorted().join(", ")} (zap doc environment says what each does)"
			)

# the files of the declarations outside the runtime added to files, each once
fn addDeclFiles(nodes Node[], kidIds NodeLists, decls NodeId[], mut files str[]):
	for d in decls:
		f = nodes[d].file(kidIds)
		if nodes[d].mod(kidIds) != "rt" and f != "" and not f.startsWith("<") and f not in files:
			files.push(f.copy())

# The declarations of the compiler's sources and the runtime's (compilerAndRuntimeFiles), kept
# in the caches under the compiler's key: lexing them is a fifth of a small program's build. A word
# they lack is looked for in the sources themselves.
fn ownSettings():
	path = "{cachesDir}/settings.txt"
	lines = (fs.readFile(path) ?? "").lines()
	if not lines.isEmpty and lines[0] == "{compilerKey()}":
		return lines[1..].map(.split("\t")).filter(.len == 2).map(
			DeclaredSetting(kind = it[0].copy(), name = it[1].copy(), about = "")
		)
	found = settingsInAll(compilerAndRuntimeFiles())
	_ = fs.createDir(cachesDir)
	placeFile(path, "{compilerKey()}\n{found.map("{.kind}\t{.name}\n").join("")}")
	found

fn wordsDeclared(files str[], kinds str[]):
	settingsInAll(files).filter(.kind in kinds).map(.name.copy())

# ZAP_RUN's words are the diagnostics and the behaviours, ZAP_SETUP's the machine's
fn checkWordLists(prog Program):
	prog.checkWords(runVariable(), ["TraceWord", "RunWord"])
	prog.checkWords(setupVariable(), ["SetupWord"])

# the sources whose declarations `zap doc environment` lists: the working dir's repository (its
# spec and tests aside), its dependencies, std, the runtime and the compiler
fn repositoryFiles():
	files = fs.walk(".", sources = true).filter("/spec/" not in it and "/tests/" not in it)
	for m in apiModules():
		if m.origin != "runtime":
			files.extend(m.files.copy())
	files.extend(compilerAndRuntimeFiles())
	files

fn settingTitle(kind str):
	if kind == "EnvVariable": return "environment variables:"
	if kind == "SetupWord": return "words of ZAP_SETUP (set once on a machine):"
	if kind == "RunWord": return "words of ZAP_RUN (how a run behaves):"
	"words of ZAP_RUN (the diagnostics):"

# `zap doc environment`'s table: the variables, then the words of ZAP_SETUP, the behaviours and the
# diagnostics of ZAP_RUN, each with what it does, as the repositoryFiles declare them; a name
# declared twice is shown as the first declares it
fn environmentTable():
	found DeclaredSetting[] = []
	for s in settingsInAll(repositoryFiles()):
		if not found.any(.kind == s.kind and .name == s.name):
			found.push(s)
	lines = []
	for kind in settingKinds:
		mine = found.filter(.kind == kind).sortedBy(.name)
		lines.push(settingTitle(kind))
		width = mine.map(.name.len).max() ?? 0
		for s in mine:
			lines.push("  {s.name}{" ".repeat(width - s.name.len)}   {s.about}")
	lines.join("\n")
