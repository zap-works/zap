# What a std module imports and reads, kept under the stamp of its files (build/cache/), so a
# build whose kept stages hold the module (keptstages.zap) never parses it: its imports are
# loaded from the index, the runtime's dirs it reaches told by the names it reads, and the module
# parsed only when no kept stage holds it.

import fs

# a std module's index: the modules it imports (by id, in its order) and what it reads
type StdIndex:
	imports str[]
	reads str[]
	needs str[]

fn stdIndexPath(id str):
	"{keptPath(stageFile(id))}.index"

# the index of the std module at dir while its files are as it says, none else
fn stdIndexOf(id str) StdIndex?:
	text = fs.readFile(stdIndexPath(id)) ?? return none
	kept = try keptWhileSame(text)
	lines = kept.lines()
	if lines.len != 3: return none
	StdIndex(spacedWords(lines[0][2..]), spacedWords(lines[1][2..]), spacedWords(lines[2][2..]))

# the index of the std module m at dir, parsed from its files, kept (stamped by every source
# below dir, a system's too); none for a module with GPU code or a shader's call, which the
# shaders' link reads before the stages kept are
fn keepStdIndex(prog Program, dir str, m Module, parsed ParsedFile[]):
	for f in parsed:
		if isGpuFile(f.path): return
		for (_, file) in shaderCalls:
			if file == f.path: return
	names {str: bool} = {}
	needs = []
	for f in parsed:
		decls = f.decls.filter(prog.nodes[it].kind not in [nTestDecl, nImportDecl, nPartsDecl])
		readsUnder(prog.nodes, prog.kidIds, decls, names, needs)   # (the declarations the module adopts)
	imports = m.imports.map(prog.nodes[it].text.copy())
	text = "i {imports.join(" ")}\nr {names.keys().join(" ")}\nn {needs.join(" ")}"   # (a line each, none empty)
	_ = fs.createDir(cachesDir)
	_ = fs.writeFile(stdIndexPath(m.id), stamped(fs.walk(dir, sources = true), text))

# The std module id at dir loaded from its index, when it has one and the build reads kept stages:
# its imports loaded, then the module put in unparsed, what it reads set aside for the runtime's
# reach. Whether it was (indexLoaded), was not, or an import said an error.
fn loadIndexed(
	mut prog Program,
	root str,
	mut loading str[],
	id str,
	dir str,
	files str[],
	imp NodeId
) i64:
	if not keepsStages() or noting: return indexNone
	index = stdIndexOf(id) ?? return indexNone
	for other in index.imports:
		if not prog.loadModule(root, loading, other.copy(), imp): return indexFailed
	prog.modules.push(
		Module(
			id.copy(),
			prefixFor(id),
			file = files[0].copy(),
			imports = [],
			std = true,
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

# the std modules loaded from their index that no kept stage holds parsed into their places;
# false once one said an error
fn parseUnparsed(mut prog Program, root str):
	for mi in 0..prog.modules.len:
		if not prog.modules[mi].unparsed: continue
		id = prog.modules[mi].id.copy()
		dir = stdDir() + id.replace(".", "/")
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
