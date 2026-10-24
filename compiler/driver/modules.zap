# Module loader: the entry file, the dirs it imports (depth first) and the runtime (runtime/)
# (module rt) are parsed into one Program whose declarations carry globally unique names.

import fs

# the dir part of path with its slash ("a/b/" for "a/b/c"), "" when it has none: what a
# name inside that dir is put after
fn dirPrefix(path str):
	dir = fs.dirOf(path)
	"" if dir == "" else "{dir}/"

fn moduleIndex(modules Module[], id str):
	modules.findIndex(.id == id) ?? -1

# a module's names are its id's, '.' written "_d" and '_' "_u", then "__" (a.b and a_b
# never share one: "a_db__", "a_ub__")
fn prefixFor(id str):
	"{id.replace("_", "_u").replace(".", "_d")}__"

# Tags one parsed file's declarations with their module (prog.modules[mi]) and renames them to
# global names. Every node keeps a file name and a module id of its own.
fn adoptDecls(mut prog Program, mi i64, parsed NodeId[], file str):
	for d in parsed:
		k = prog.nodes[d].kind
		if k == nImportDecl or k == nPartsDecl: continue
		if k == nTestDecl:
			prog.adoptTest(d, file)
			continue
		prog.nodes[d].declPart().mod = prog.modules[mi].id.copy()
		prog.nodes[d].declPart().file = file.copy()
		name = move prog.nodes[d].text   # the bare name moves to text2
		prog.nodes[d].text = prog.modules[mi].prefix + name
		prog.nodes[d].text2 = name
		if k == nImplDecl or k == nBoundDecl:
			for mm in prog.nodes[d].kids:
				prog.nodes[mm].declPart().mod = prog.modules[mi].id.copy()
				prog.nodes[mm].declPart().file = file.copy()
		prog.decls.push(d)

# a test and its cases (`refuses Name:` in its body) made tests of the file; only zap test makes
# them part of the program. A test whose body is only cases is not run itself.
fn adoptTest(mut prog Program, d NodeId, file str):
	for c in prog.nodes[d].kids.copy():
		prog.nodes[c].declPart().file = file.copy()
		prog.tests.push(c)
	if prog.nodes[d].ival < 2 and not prog.nodes[d].kids.isEmpty and
		prog.nodes[prog.nodes[d].sub[0]].kids.isEmpty:
		return
	prog.nodes[d].declPart().file = file.copy()
	prog.tests.push(d)

# The modules m imports loaded: false once one said an error (a lex, parse or import error, the
# loading's errors), the rest left
fn loadImports(mut prog Program, root str, mut loading str[], m Module) bool:
	for imp in m.imports:
		# the id is the module's own: loading it adds nodes, which may move this one's text
		if not prog.loadModule(root, loading, prog.nodes[imp].text.copy(), imp): return false
	true

# imp: the import node, whose file and position an error names (read from it when reported:
# loading adds nodes); false once the loading said an error
fn loadModule(mut prog Program, root str, mut loading str[], move id str, imp NodeId) bool:
	if moduleIndex(prog.modules, id) >= 0: return true
	if id in loading:
		errorAtFile(
			prog.nodes[imp].file(),
			prog.nodes[imp].line,
			prog.nodes[imp].col,
			compileError("ImportCycle", ["{id}"])
		)
		return false
	loading.push(id.copy())   # the stack of modules being loaded, for cycles
	dir = root + id.replace(".", "/")
	files = moduleSources(dir, "." not in id)
	if files.isEmpty and id.split(".")[0] in rootLibraries():
		dir = zapRoot() + id.replace(".", "/")   # a library of the compiler's repository (engine)
		files = moduleSources(dir, false)
	if files.isEmpty:
		dir = stdDir() + id.replace(".", "/")   # a module of the standard library
		files = moduleSources(dir, false)
	# a dir above the program's: programs side by side share a library beside them, after std, so
	# a stray dir around a script never hides a standard module
	up = 1
	while files.isEmpty and up <= climbDirs:
		dir = root + "../".repeat(up) + id.replace(".", "/")
		files = moduleSources(dir, false)
		up += 1
	if files.isEmpty:
		errorAtFile(
			prog.nodes[imp].file(),
			prog.nodes[imp].line,
			prog.nodes[imp].col,
			compileError("ModuleNotFound", ["{id}", "{root}", "{id.replace(".", "/")}"])
		)
		return false
	indexed = prog.loadIndexed(root, loading, id, dir, files, imp) if isUnder(dir, stdDir())
		else indexNone
	if indexed != indexNone:
		loading.pop()
		return indexed == indexLoaded
	parsed = prog.parsedFiles(files, "") ?? return false
	if not prog.addParts(parsed): return false
	parsed = prog.forTarget(parsed, "{dir}/", "") ?? return false
	m = Module(
		id,
		prefixFor(id),
		file = files[0].copy(),
		imports = [],
		std = isUnder(dir, stdDir())
	)
	prog.takeImports(m, parsed)
	prog.takePrefixImports(m, parsed, root)
	if m.std and keepsStages() and not noting: prog.keepStdIndex(dir, m, parsed)
	if not prog.loadImports(root, loading, m): return false
	prog.modules.push(m)
	mi = prog.modules.len - 1
	for f in parsed:
		prog.adoptDecls(mi, f.decls, f.path)
	loading.pop()
	true

# how many dirs above a program's an import or an embedded file is looked for
climbDirs = 6

# a file of a module and its declarations as parsed
type ParsedFile:
	path str
	decls NodeId[]

# The files at base + each path parsed, each named by its path: none once one said an error.
fn parsedFiles(mut prog Program, paths str[], base str) ParsedFile[]?:
	out = []
	for path in paths:
		at = "{base}{path}"
		out.push(
			ParsedFile(
				path.copy(),
				try parseCached(readSource(at), path, at, prog.nodes)
			)
		)
	out

# the parts each file's `parts` lines name, parsed and added after the files, each once (a part's
# own parts too): false once one said an error
fn addParts(mut prog Program, mut files ParsedFile[]):
	i = 0
	while i < files.len:
		from = files[i].path.copy()
		for d in files[i].decls.copy():
			if prog.nodes[d].kind != nPartsDecl: continue
			for name in prog.nodes[d].names.copy():
				paths = prog.partFiles(from, d, name) ?? return false
				for path in paths:
					if not files.any(.path == path):
						files.extend(prog.parsedFiles([path], "") ?? return false)
		i += 1
	true

# the files with the declarations of their system's dir (dir/linux/, target.zap) in place of
# theirs, when building for it; a system file named by its path below base; none once one said an
# error
fn forTarget(mut prog Program, move files ParsedFile[], dir str, base str) ParsedFile[]?:
	out = move files
	for sys in systemDirsOf(dir):
		paths = moduleFiles(sys).sorted().map("{sys[base.len..]}{it}")
		if paths.isEmpty: continue
		more = try prog.parsedFiles(paths, base)
		names = out.map(.path.copy())
		names.extend(paths.map(.copy()))
		kept = replaceForTarget(prog.nodes, out.map(.decls.copy()), more.map(.decls.copy()))
		out = (0..kept.len).map(ParsedFile(names[it].copy(), kept[it].copy()))
	out

# whether a source below a module's dir is a system's (linux/: read for its target alone)
fn isSystemFile(path str):
	"/linux/" in "/{path}"

# the files the part name of a `parts` line (d, in file from) stands for: name.zap beside from,
# or every source under the dir name beside it; none when it said that neither or both are there
fn partFiles(prog Program, from str, d NodeId, name str) str[]?:
	at = "{dirPrefix(from)}{name}"
	file = fs.exists("{at}.zap")
	tree = fs.zapFiles(at, false).filter(it != "{at}.zap" and not isSystemFile(it))
	if file != tree.isEmpty:
		code = "PartTwice" if file else "PartNotFound"
		errorAtFile(
			from,
			prog.nodes[d].line,
			prog.nodes[d].col,
			compileError(code, ["{name}", "{at}"])
		)
		return none
	["{at}.zap"] if file else tree

# the imports of the files, the module's
fn takeImports(mut prog Program, mut m Module, files ParsedFile[]):
	for f in files:
		for d in f.decls:
			if prog.nodes[d].kind == nImportDecl:
				prog.nodes[d].declPart().file = f.path.copy()
				prog.nodes[d].declPart().mod = m.id.copy()
				m.imports.push(d)

# the part names a text's `parts` lines list, read from its text (for the tools; the loader reads
# the parsed lines)
pub fn partsOf(text str) str[]:
	out = []
	for line in text.lines():
		if line.startsWith("parts "):
			for name in codeOf(line[6..]).split(","):
				if name.trimmed() != "": out.push(name.trimmed().copy())
	out

# the files with the parts their `parts` lines name, the parts' own too, each once (a part not
# found left out)
pub fn withParts(files str[]) str[]:
	out = files.copy()
	i = 0
	while i < out.len:
		at = dirPrefix(out[i])
		for name in partsOf(readSource(out[i])):
			part = "{at}{name}"
			for f in (["{part}.zap"] if fs.exists("{part}.zap") else fs.zapFiles(part, false)):
				if f not in out: out.push(f.copy())
		i += 1
	out

# the file whose `parts` line names the part that holds file ('/' between its dirs): one beside
# it or in a dir above it, up to root; none when file is no part
pub fn partOwner(file str, root str) str?:
	up = dirPrefix(file)
	while up.len >= root.len:
		first = file[up.len..].split("/")[0]
		name = first[..len - 4].copy() if first.endsWith(".zap") else first.copy()
		for f in moduleFiles("." if up == "" else up):
			if up + f != file and name in partsOf(readSource(up + f)): return up + f
		if up == "": return none
		up = dirPrefix(up[..len - 1])
	none

# the Zap sources of one dir
fn moduleFiles(dir str):
	(fs.list(dir) ?? []).filter(fs.isSourceFile(it))

# a module's first files, as paths: the dir's sources, else, where alone may be (beside the
# program, not nested: a nested one's dir.zap is its parent's file), the file dir.zap, but a
# program (with statements or tests), else none
fn moduleSources(dir str, alone bool):
	files = moduleFiles(dir)
	if not files.isEmpty: return files.sorted().map("{dir}/{it}")
	["{dir}.zap"] if alone and isModuleFile("{dir}.zap") else []

fn isModuleFile(path str):
	fs.exists(path) and not isEntryText(readSource(path))

# whether the file lies in the dir (an entry file of std: its tests see what std's modules see)
fn isUnder(file str, dir str):
	fullPath(file).lower().startsWith("{fullPath(dir).lower()}/")

# the path from the root of its drive, '/' between parts, "." and "x/.." taken out
fn fullPath(path str):
	fs.normalize(fs.join(currentDir(), path))

# A source file as an executable names it (its debug table): an absolute path or one through
# "..", from the zap repository's root when it lies there (std/fs/fs.zap), else from the working
# dir, so no build holds a path, or the spelling of a path, of the machine that built it.
fn portablePath(file str):
	if not file.startsWith("/") and ":" not in file and ".." not in file: return file.copy()
	full = fullPath(file)
	for dir in [zapRoot(), currentDir()]:
		base = fullPath(dir)
		if full.lower().startsWith("{base.lower()}/"): return full[base.len + 1..].copy()
	full

# the standard library's modules, imported by name (import net): std/ beside runtime/
fn stdDir():
	"{zapRoot()}std/"

# the root of the compiler's repository: the dir holding runtime/, std/ and the libraries beside
# them (engine/, rhi/)
fn zapRoot():
	rt = runtimeDir()
	dirPrefix(rt[..len - 1])

# the libraries beside std, each a dir holding a file of its name (engine/engine.zap), listed
# once a program's load (every prefix a module reads asks)
fn rootLibraries():
	if librariesListed is known: return known.copy()
	root = zapRoot()
	found = (fs.list(root) ?? []).sorted().filter(fs.exists("{root}{it}/{it}.zap"))
	librariesListed = found.copy()
	found

mut librariesListed str[]? = none

# The file a source names in embed(...): beside the source, else in a dir above it (climbDirs);
# the path beside it when none has it
fn sourcePath(source str, rel str):
	dir = dirPrefix(source)
	beside = dir + rel
	if fs.exists(beside): return beside
	for up in 1..=climbDirs:
		above = dir + "../".repeat(up) + rel
		if fs.exists(above): return above
	beside

fn runtimeWord():
	RunWord(
		"runtime",
		"runtime=<dir>: the runtime dir to compile with (default: runtime/ beside the compiler's dir)"
	)

fn tokensWord():
	TraceWord("tokens", "the entry file's tokens, one a line")

# the first dir, dir itself or above it, holding both runtime/ and std/ (and, with checkout, a .git:
# a checkout of the repository), as a path ending in "/"; none when no dir up to the root has them
fn rootAbove(start str, checkout bool) str?:
	dir = start if start.endsWith("/") else "{start}/"
	while dir != "":
		if fs.exists("{dir}runtime") and fs.exists("{dir}std") and
			(not checkout or fs.exists("{dir}.git")):
			return dir
		parent = dirPrefix(dir[..dir.len - 1])
		if parent == dir: return none
		dir = parent
	none

# where the runtime's sources are: runtime of ZAP_RUN, else the runtime/ of the checkout found from the
# compiler's executable (build/zap.exe, build/base/zap.exe, a copy kept anywhere under it: a copy
# of runtime/ beside one never shadows the checkout's), else of the first dir above the executable
# holding runtime/ and std/ (an install), else from the working dir upward
fn runtimeDir():
	if runtimeWord().value() is dir: return "{dir}/"
	exeDir = dirPrefix(exePath())
	root = rootAbove(exeDir, true) ?? rootAbove(exeDir, false) ?? rootAbove(fullPath("."), false) ??
		"{dirPrefix(exeDir[..exeDir.len - 1])}"
	"{root}runtime/"

# the runtime's sources, its subfolders' too, as paths below dir, in the order of their file
# names (a file moved to another subfolder keeps its place)
pub fn runtimeFiles(dir str) str[]:
	runtimeSources(dir).filter(not isSystemFile(it)).sortedBy(fs.fileName(it))

# every source of the runtime, a system's too, as a path below dir, listed once a process (the
# sources do not change while a zap checks them)
fn runtimeSources(dir str):
	if runtimeListed.get(dir) is known: return known.copy()
	files = fs.zapFiles(dir[..len - 1], false).map(it[dir.len..].copy())
	runtimeListed[dir.copy()] = files.copy()
	files

mut runtimeListed {str: str[]} = {}

# the runtime's sources at dir known from the paths of each (a stamp's, which a listing made)
fn listedRuntime(dir str, paths str[]):
	runtimeListed[dir.copy()] = paths.filter(.startsWith(dir)).map(it[dir.len..].copy())

# the runtime, module rt, put before the program's modules: the sources of the dirs the program
# reaches (runtimedirs.zap), the test runner's with tests, or of all with every, but for the stages
# kept checked (keptstages.zap), which also take the std modules they hold out of those loaded.
# False once one said an error.
fn addRuntime(mut prog Program, every bool, tests bool):
	dir = runtimeDir()
	index = runtimeIndex(dir) ?? return false
	if index.isEmpty:
		exit(1, "zap: no runtime in {dir} (set runtime=<dir> in ZAP_RUN)")
	dirs = checkOrder(index, index.map(.name.copy()))
	if not every:
		names = prog.readsAside.copy()   # (the std modules' an index told)
		needs = [testRunnerDir] if tests else []
		needs.extend(prog.needsAside.filter(it not in needs).map(.copy()))
		readsUnder(prog.nodes, prog.decls, names, needs)
		if tests:
			readsUnder(
				prog.nodes,
				prog.tests.filter(prog.nodes[it].file() == prog.file),
				names,
				needs
			)
		dirs = reachedDirs(index, names, needs)
	chain = stageChain(dir, dirs, prog.modules)
	for s in chain:
		prog.stageKeys[s.name.copy()] = s.key
		prog.stageFiles[s.name.copy()] = s.file.copy()
	kept = prog.keepFrom(chain)
	if not prog.parseUnparsed(dirPrefix(prog.file)): return false
	own = move prog.decls
	ownTests = move prog.tests
	prog.decls = []
	prog.tests = []
	loaded = prog.loadPrelude(dir, dirs.filter("rt/{it}" not in kept))
	prog.decls.extend(own)
	prog.tests.extend(ownTests)
	loaded

# the runtime's sources of the dirs, module rt, the first module (there for what the linker writes
# into it when every dir is kept), a dir's after those before it in dirs; false once one said an
# error
fn loadPrelude(mut prog Program, dir str, dirs str[]):
	sources = runtimeFiles(dir)
	names = []
	for d in dirs:
		names.extend(sources.filter(runtimeDirOf(it) == d).map(.copy()))
	file = names[0].copy() if not names.isEmpty else ""
	prog.modules.insert(0, Module(id = "rt", prefix = "rt__", file, imports = [], std = false))
	if names.isEmpty: return true
	files = prog.parsedFiles(names, dir) ?? return false
	for d in dirs:
		files = prog.forTarget(files, "{dir}{d}/", dir) ?? return false
	replaced = prog.keptReplacements()
	for f in files:
		decls = f.decls.copy() if isSystemFile(f.path)
			else f.decls.filter(replacedKey(prog.nodes, it) not in replaced)
		prog.adoptDecls(0, decls, f.path)
	true

# what the kept stages' system files declare (replaceForTarget's keys): a dir loaded after them
# leaves out its own declarations of those, as it would loaded with them
fn keptReplacements(prog Program):
	out {str: bool} = {}
	kept = prog.kept ?? return out
	for d in kept.decls:
		n = kept.nodes[d]
		if n.mod() != "rt" or not isSystemFile(n.file()): continue
		if n.kind == nImplDecl and n.kids.len == 1:
			out["{n.text2}.{kept.nodes[n.kids[0]].text}"] = true
		else:
			out[n.text2.copy()] = true
	out

pub fn newProgram(entryFile str) Program:
	Program(
		nodes = [],
		decls = [],
		file = entryFile.copy(),
		modules = [],
		instances = [],
		types = newTypes(),
		derived = [],
		tests = [],
		entry = "main"
	)

# the program of an entry file; none when its loading said an error (a lex, parse or import
# error). With tests, the runtime's test runner is loaded for the tests' entry (addTestEntry).
pub fn loadProgram(entryFile str, tests bool = false) Program?:
	loadProgramText(entryFile, readSource(entryFile), tests)

# What a program loaded before in this process left in the compiler's tables, which hold one
# program's nodes and types (zap test checks its entries one after another, check.zap)
fn forgetEarlierProgram():
	forgetShaderCalls()
	forgetNumberBodies()
	librariesListed = none
	modulesNamed.clear()
	dropTypesSeen = false
	dropsHeld.clear()
	irOwnErrors = 0
	irOwnSaid = {}
	irMissing = 0
	filesWithErrors.clear()
	sourceTexts.clear()   # (a test's source is written again at its path)
	formNotes.clear()
	errorLines.clear()

# A together check's program (zap test's, spec 13.1): the test file's own (its declarations, its
# tests apart), then the sources (addUnits), each source's line (togetherLine with its index in
# the list) said before it is parsed and before its imports are loaded, so the source whose
# loading stops the check is the one named last. None when the loading said an error.
pub fn loadUnits(file str, units str[], expects str[], indexes i64[]) Program?:
	prog = try loadOwnModules(file, readSource(file))
	if not prog.addUnits(file, units, expects, indexes, true): return none
	if not prog.addRuntime(false, false): return none
	eprint(togetherLine("link"))   # (past the sources: a stop here is none's own)
	prog.entry = "{prefixFor(unitModuleId(indexes[0]))}main"
	if not prog.linkLoaded(): return none
	prog

# The sources after the test file's program (in the run's dir), each a module of its own that
# sees the file's declarations (unit) and a program alone (its statements its main, isUnitMain),
# with the error its test expects (expects[i], an error code: reportsUnused); each source is
# parsed, then its imports loaded, found from the test file's dir as the file's are. With staged,
# each source's line said before each (loadUnits). False once one said an error.
pub fn addUnits(
	mut prog Program,
	file str,
	units str[],
	expects str[],
	indexes i64[],
	staged bool
) bool:
	parsed = []
	for i, unit in units:
		if staged:
			eprint(togetherLine("unit {indexes[i]}"))
		# never cached: the sources are a run's own
		decls = parseSource(readSource(unit), unit, prog.nodes) ?? return false
		parsed.push([ParsedFile(unit.copy(), decls)])
	loading = []
	for i, unit in units:
		if staged:
			eprint(togetherLine("unit {indexes[i]}"))
		id = unitModuleId(indexes[i])
		m = Module(
			id,
			prefixFor(id),
			file = unit.copy(),
			imports = [],
			std = isUnder(file, stdDir()),
			unit = true,
			expects = expects[i].copy()
		)
		if not prog.addProgramModule(dirPrefix(file), loading, m, parsed[i].copy()): return false
	true

# loadProgram of an entry file's text (a program zap writes, as if the file held it)
pub fn loadProgramText(entryFile str, text str, tests bool = false) Program?:
	prog = try loadProgramModules(entryFile, text, tests)
	if not prog.linkLoaded(): return none
	prog

# the modules of the program of an entry file's text: the runtime (its test runner too with
# tests), the file's, what it imports; none when the loading said an error
pub fn loadProgramModules(entryFile str, text str, tests bool = false) Program?:
	prog = try loadOwnModules(entryFile, text)
	if not prog.addRuntime(false, tests): return none
	prog

# the modules of the program of an entry file's text but the runtime: the file's and what it
# imports; none when the loading said an error
fn loadOwnModules(entryFile str, text str) Program?:
	forgetEarlierProgram()
	prog = newProgram(entryFile)
	root = dirPrefix(entryFile)
	loading = []
	mainMod = Module(
		id = "",
		prefix = "",
		file = entryFile.copy(),
		imports = [],
		std = isUnder(entryFile, stdDir())
	)
	if tokensWord().on():
		traceTokens(lex(text, entryFile) ?? [])
	decls = try parseCached(text, entryFile, entryFile, prog.nodes)
	parsed = [ParsedFile(entryFile.copy(), decls)]
	if not prog.addParts(parsed): return none
	if not prog.addProgramModule(root, loading, mainMod, parsed): return none
	prog

# a program's own module (its entry file's, or a together check's source's) added with its files,
# the dir's system files in place of theirs, after the modules it imports: false once the
# loading said an error
fn addProgramModule(
	mut prog Program,
	root str,
	mut loading str[],
	mut m Module,
	move files ParsedFile[]
):
	parsed = move files
	if root != "":
		parsed = prog.forTarget(parsed, root, "") ?? return false
	prog.takeImports(m, parsed)
	prog.takePrefixImports(m, parsed, root)
	if not prog.loadImports(root, loading, m): return false
	prog.modules.push(m.copy())
	for f in parsed:
		prog.adoptDecls(prog.modules.len - 1, f.decls, f.path)
	true

# what a loaded program's modules link: the shaders, the learnables, the trace words checked,
# then what was loaded put in the stages that check it (stages.zap); false when a shader's error
# was said
fn linkLoaded(mut prog Program):
	linked = prog.linkShaders()
	prog.addLearnables()
	prog.checkWordLists()
	prog.orderStages()
	linked
