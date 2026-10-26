# What an imported module imports and reads, kept under the stamp of its files (build/cache/), so
# a build whose kept stages hold the module (keptstages.zap) never parses it: its imports are
# loaded from the index, the runtime's dirs it reaches told by the names it reads, and the module
# parsed only when no kept stage holds it. A std module has one, and a module of the program's
# that is a dir of its own (its sources all below it, no `parts` naming files elsewhere).

import fs

# a module's index: the modules it imports (by id, in its order) and what it reads
type ModuleIndex:
	imports str[]
	reads str[]
	needs str[]

# where the index of module id at dir is kept: a std module's by its id, a program's module's by
# its dir too (two programs may each have a module of that name)
fn moduleIndexPath(id str, dir str, std bool):
	if std: return "{keptPath(stageFile(id))}.index"
	"{keptPath("mod-{id}-{fullPath(dir).hash() & 4_294_967_295:x}")}.index"

# the index of module id at dir while its files are as it says, none else
fn moduleIndexOf(id str, dir str, std bool) ModuleIndex?:
	text = fs.readFile(moduleIndexPath(id, dir, std)) ?? return none
	kept = try keptWhileSame(text)
	lines = kept.lines()
	if lines.len != 3: return none
	ModuleIndex(spacedWords(lines[0][2..]), spacedWords(lines[1][2..]), spacedWords(lines[2][2..]))

# whether module id's files (from moduleSources) are those of its dir, which an index's stamp walks
fn indexableFiles(dir str, files str[]):
	files.all(.startsWith("{dir}/"))

# the index of module m at dir, parsed from its files, kept (stamped by every source below dir, a
# system's too); none for a module with GPU code or a shader's call, which the shaders' link reads
# before the stages kept are, nor for one whose `parts` may name files outside dir
fn keepModuleIndex(prog Program, dir str, m Module, parsed ParsedFile[]):
	for f in parsed:
		if isGpuFile(f.path): return
		for (_, file) in shaderCalls:
			if file == f.path: return
		if not m.std and f.decls.any(prog.nodes[it].kind == nPartsDecl): return
	names {str: bool} = {}
	needs = []
	for f in parsed:
		decls = f.decls.filter(prog.nodes[it].kind not in [nTestDecl, nImportDecl, nPartsDecl])
		readsUnder(prog.nodes, prog.kidIds, decls, names, needs)   # (the declarations the module adopts)
	imports = m.imports.map(prog.nodes[it].text.copy())
	text = "i {imports.join(" ")}\nr {names.keys().join(" ")}\nn {needs.join(" ")}"   # (a line each, none empty)
	_ = fs.createDir(cachesDir)
	_ = fs.writeFile(moduleIndexPath(m.id, dir, m.std), stamped(fs.walk(dir, sources = true), text))

# The module id at dir loaded from its index, when it has one and the build reads kept stages: its
# imports loaded, then the module put in unparsed, what it reads set aside for the runtime's reach.
# Whether it was (indexLoaded), was not, or an import said an error.
fn loadIndexed(
	mut prog Program,
	root str,
	mut loading str[],
	id str,
	dir str,
	files str[],
	imp NodeId
) i64:
	if not keepsStages() or noting or not indexableFiles(dir, files): return indexNone
	std = isUnder(dir, stdDir())
	index = moduleIndexOf(id, dir, std) ?? return indexNone
	for other in index.imports:
		if not prog.loadModule(root, loading, other.copy(), imp): return indexFailed
	prog.modules.push(
		Module(
			id.copy(),
			prefixFor(id),
			file = files[0].copy(),
			imports = [],
			std,
			unparsed = true
		)
	)
	for n in index.reads:
		prog.readsAside[n.copy()] = true
	for n in index.needs:
		if n not in prog.needsAside: prog.needsAside.push(n.copy())
	indexLoaded

indexNone = 0
indexLoaded = 1
indexFailed = 2

# the modules loaded from their index that no kept stage holds parsed into their places; false
# once one said an error
fn parseUnparsed(mut prog Program, root str):
	for mi in 0..prog.modules.len:
		if not prog.modules[mi].unparsed: continue
		dir = fs.dirOf(prog.modules[mi].file)
		files = moduleSources(dir, false)
		parsed = prog.parsedFiles(files, "") ?? return false
		if not prog.addParts(parsed): return false
		parsed = prog.forTarget(parsed, "{dir}/", "") ?? return false
		m = prog.modules[mi].copy()
		m.unparsed = false
		prog.takeImports(m, parsed)
		prog.takePrefixImports(m, parsed, root)
		prog.modules[mi] = m
		for f in parsed:
			prog.adoptDecls(mi, f.decls, f.path)
	true
