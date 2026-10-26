# `from m import a, b as c` (spec 8): the names a file reads bare from another module. The import
# names each one once and unknown to the file before it; a .zapx file's own import of zapx
# (parseMarkup.zap, flagInternal) names every public declaration of it, and the file's own module
# and its other imports win over those.

alias nodes = c.nodes

# the kinds of declaration a name can be imported as
importedKinds = [nFnDecl, nStructDecl, nConstDecl, nBoundDecl]

# checks every from-import at its line and fills in each internal one's names
fn checkFromImports(mut c Checker):
	for m in c.freshModules..c.modules.len:
		seen = []   # "file\tname": the names the files import so far
		for imp in c.modules[m].imports.copy():
			if nodes[imp].text2() != "": continue   # `import m`: the module, not its names
			c.enterModuleOf(imp)
			c.curMod = m
			if nodes[imp].hasFlag(flagInternal):
				c.importEveryName(imp)
				continue
			for i in 0..nodes[imp].names().len:
				local = nodes[imp].names2()[i].copy()
				c.checkImportedName(imp, nodes[imp].names()[i], local, seen)
				seen.push("{nodes[imp].file()}\t{local}")
	c.curMod = -1
	c.curFile = ""

fn checkImportedName(mut c Checker, imp NodeId, name str, local str, seen str[]):
	path = nodes[imp].text
	line = nodes[imp].line
	col = nodes[imp].col
	match c.declOfAnyKind(path, name):
		d:
			if not c.declIsPub(d):
				c.errorAt(line, col, compileError("PrivateName", ["{name}", "{path}"]))
		none:
			c.errorAt(line, col, compileError("NotInModuleBare", ["{path}", "{name}"]))
	if "{nodes[imp].file()}\t{local}" in seen or
		c.declOfAnyKind(c.modules[c.curMod].id, local) != none:
		c.errorAt(line, col, compileError("AmbiguousImport", ["{local}", "{path}"]))

# the declaration named `name` in module `path` of any kind a name can be imported as
fn declOfAnyKind(c Checker, path str, name str) NodeId?:
	for kind in importedKinds:
		if c.findDeclInModule(path, kind, name) is d: return d
	none

# an internal import's names: every public declaration of its module
fn importEveryName(mut c Checker, imp NodeId):
	path = nodes[imp].text.copy()
	for d in c.decls:
		if nodes[d].mod() != path or nodes[d].origin() != none or not c.declIsPub(d) or
			not importedKinds.any(kindMatches(nodes[d].kind, it)):
			continue
		name = nodes[d].text2().copy()
		if name == "" or name in nodes[imp].names(): continue
		nodes[imp].nodePart().names.push(name.copy())
		nodes[imp].nodePart().names2.push(name.copy())

# the declaration a bare name of kind `kind` reads through a from-import of the file being
# checked: one it names first, an internal one's after
fn importedBare(c Checker, kind i64, name str):
	if c.curMod < 0: return none
	found = c.importedBareIn(c.curMod, c.file if c.curFile == "" else c.curFile, kind, name)
	if found == none and c.modules[c.curMod].unit:
		main = moduleIndex(c.modules, "")
		return c.importedBareIn(main, c.modules[main].file, kind, name)   # (ownModules)
	found

fn importedBareIn(c Checker, m i64, file str, kind i64, name str) NodeId?:
	fallback NodeId? = none
	for imp in c.modules[m].imports:
		if nodes[imp].text2() != "" or nodes[imp].file() != file: continue
		at = nodes[imp].names2().indexOf(name) ?? continue
		d = c.findDeclInModule(nodes[imp].text, kind, nodes[imp].names()[at]) ?? continue
		if not nodes[imp].hasFlag(flagInternal): return d
		if fallback == none:
			fallback = d
	fallback
