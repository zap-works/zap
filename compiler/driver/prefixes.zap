# Imports from the prefixes a file names (spec 8): a name read as `x.y` or a type written `x.T`
# that nothing of the file binds, no import of its module names and no built-in type is
# (`f64.parse`) is the module of that name, imported as if the file wrote `import x`: a module
# found as an import's is (under the program's root, a library beside std, std, a dir above),
# else the one module whose dir is named x under the root, the libraries or std (`esm` is
# skyrim.esm). zap fmt writes the import lines so (canon.zap); a prefix no module has is an error
# naming the modules that come close.

import fs

# the modules by the last name of their ids, found once under the program's root, the libraries
# beside std and std
mut modulesByName {str: str[]} = {}
mut indexedRoot = "-"

# the implicit imports of the files of module m: an import node (flagInternal) each
fn takePrefixImports(mut prog Program, mut m Module, files ParsedFile[], root str):
	declared {str: bool} = {}   # the module's own names, any file's
	fields {str: str[]} = {}   # each type's fields, by its name: its methods name them bare
	for f in files:
		for d in f.decls:
			if prog.nodes[d].text != "": declared[prog.nodes[d].text.copy()] = true
			if prog.nodes[d].kind == nStructDecl:
				fields[prog.nodes[d].text.copy()] = prog.nodes[d]
					.kids(prog.kidIds)
					.filter(prog.nodes[it].kind == nFieldDecl)
					.map(prog.nodes[it].text.copy())
	for f in files:
		bound = declared.copy()
		for d in f.decls:
			boundNamesIn(prog.nodes, prog.kidIds, d, bound)
		for d in f.decls:
			own str[] = (fields.get(prog.nodes[d].text) ?? []) if prog.nodes[d].kind == nImplDecl
				else []
			for p in prefixesOf(prog.nodes, prog.kidIds, [d]):
				if bound.get(p.name) != none or p.name in own or
					m.imports.any(prog.nodes[it].text2(prog.kidIds) == p.name):
					continue
				prog.takePrefixImport(m, f, p, root)

# the import of the module prefix p names, made for file f of module m when one is found
fn takePrefixImport(mut prog Program, mut m Module, f ParsedFile, p Prefix, root str):
	id = moduleNamed(root, p.name) ?? return
	d = newNode(
		prog.nodes,
		prog.kidIds,
		nImportDecl,
		prog.nodes[p.at].line,
		prog.nodes[p.at].col,
		text = id
	)
	prog.nodes[d].setText2(prog.kidIds, p.name.copy())
	prog.nodes[d].flags = flagInternal   # not written: zap fmt writes it
	prog.nodes[d].nodeMore(prog.kidIds).file = f.path.copy()
	prog.nodes[d].nodeMore(prog.kidIds).mod = m.id.copy()
	m.imports.push(d)

# a prefix a file reads and a node that names it
type Prefix:
	name str
	at NodeId

# each prefix the declarations read (`x` of `x.y`, of a type `x.T`), once
fn prefixesOf(nodes Node[], kidIds NodeLists, decls NodeId[]):
	out = []
	for d in decls:
		prefixesUnder(nodes, kidIds, d, out)
	out

fn prefixesUnder(nodes Node[], kidIds NodeLists, e NodeId, mut out Prefix[]):
	name = prefixAt(nodes, kidIds, e)
	if name != "" and name[0] >= 'a' and name[0] <= 'z' and not out.any(.name == name) and
		name != "rt" and name != "self" and not primTypes.any(.name == name):
		out.push(Prefix(name.copy(), e))
	for kid in nodes[e].kids(kidIds):
		prefixesUnder(nodes, kidIds, kid, out)
	for s in nodes[e].sub(kidIds):
		prefixesUnder(nodes, kidIds, s, out)
	for t in nodes[e].types(kidIds):
		prefixesUnder(nodes, kidIds, t, out)

# the prefix node e reads (`x` of `x.y`, of a type `x.T`), else ""
fn prefixAt(nodes Node[], kidIds NodeLists, e NodeId) ref str:
	k = nodes[e].kind
	if k == nField and nodes[e].kids(kidIds).len == 1 and
		nodes[nodes[e].kids(kidIds)[0]].kind == nIdent:
		return nodes[nodes[e].kids(kidIds)[0]].text
	if k == nTyName: return nodes[e].text2(kidIds)
	""

# the names the declaration e binds anywhere: its own, its parameters', its lets', its loops',
# its patterns', its lambdas', its from-imports'
fn boundNamesIn(nodes Node[], kidIds NodeLists, e NodeId, mut bound {str: bool}):
	k = nodes[e].kind
	if k in [nLet, nParam, nFor, nPattern, nFnDecl, nConstDecl, nStructDecl] and
		nodes[e].text != "":
		bound[nodes[e].text.copy()] = true
	if k == nLambda or k == nFor:
		for n in nodes[e].names(kidIds):
			bound[n.copy()] = true
	if k == nImportDecl:
		for n in nodes[e].names2(kidIds):
			bound[n.copy()] = true
	for kid in nodes[e].kids(kidIds):
		boundNamesIn(nodes, kidIds, kid, bound)
	for s in nodes[e].sub(kidIds):
		boundNamesIn(nodes, kidIds, s, bound)

# the id of the module a prefix x names, or none: looked for once a program's load (a name read
# in many files, or one no module has, asks again)
fn moduleNamed(root str, x str):
	key = "{root}\t{x}"
	if modulesNamed.get(key) is known: return known.copy()
	found = moduleNamedNow(root, x)
	modulesNamed[key] = found.copy()
	found

# what each prefix asked of moduleNamed in this program's load names
mut modulesNamed {str: str?} = {}

fn moduleNamedNow(root str, x str) str?:
	if not moduleSources(root + x, true).isEmpty or x in rootLibraries() or
		not moduleSources(stdDir() + x, false).isEmpty:
		return x.copy()
	for up in 1..=climbDirs:
		if not moduleSources(root + "../".repeat(up) + x, false).isEmpty: return x.copy()
	ids = modulesEndingIn(root, x)
	ids[0].copy() if ids.len == 1 else none

# the ids of the modules whose last name is x
pub fn modulesEndingIn(root str, x str) str[]:
	if indexedRoot != root:
		modulesByName = {}
		indexDirs("./" if root == "" else root, "")
		for lib in rootLibraries():
			indexDirs("{zapRoot()}{lib}/", "{lib}.")
		indexDirs(stdDir(), "")
		indexedRoot = root.copy()
	(modulesByName.get(x) ?? []).copy()

# the dirs holding sources under base, by their last names, as ids after prefix
fn indexDirs(written str, prefix str):
	base = written.replace("\\", "/")
	dirs str[] = []
	for f in fs.walk(written[..written.len - 1] if base.endsWith("/") else written, sources = true):
		path = f.replace("\\", "/")
		at = path.lastIndexOf("/") ?? continue
		dir = path[..at]
		start = base.len if path.startsWith(base) else 0 if base == "./" else -1
		if start < 0 or start > dir.len or "/linux/" in "{dir}/" or dir in dirs: continue
		dirs.push(dir.copy())
		rel = dir[start..]
		if rel == "": continue
		id = "{prefix}{rel.replace("/", ".")}"
		last = rel[(rel.lastIndexOf("/") ?? -1) + 1..]
		ids = (modulesByName.get(last) ?? []).copy()
		ids.push(id)
		modulesByName[last.copy()] = ids

# the error of a prefix no module has, naming the modules that come close
pub fn unknownModule(alias str) str:
	near = modulesNear(alias)
	compileError(
		"UnknownModule",
		["{alias}", "" if near.isEmpty else " (close: {near.join(", ")})"]
	)

# the ids of the modules found whose last names come close to x: two edits or fewer apart
pub fn modulesNear(x str) str[]:
	out = []
	for name in modulesByName.keys().sorted():
		if editsApart(x, name) <= 2:
			out.extend((modulesByName.get(name) ?? []).copy())
	out

# the fewest letters put in, taken out or changed that make a into b
fn editsApart(a str, b str):
	row = (0..=b.len).map(it)
	for i in 1..=a.len:
		next = [i]
		for j in 1..=b.len:
			change = row[j - 1] + (0 if a[i - 1] == b[j - 1] else 1)
			next.push(change.min(row[j] + 1).min(next[j - 1] + 1))
		row = next
	row[b.len]
