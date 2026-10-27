# zap fmt's import lines (spec 8): each file imports the modules whose prefixes it reads, no other.
# The check notes the aliases each file's code resolves (an `alias.name`, a type `alias.T`, a
# function of an imported module called as a method); a file reading one it does not import gets
# the line after its imports, one importing a module it never names loses it. An import whose
# alias the file's text names elsewhere (a test's source, a string) stays. A module read from its
# kept stage was not checked again, so its files note no use and are left alone.

import fs

# with the notes on: `file\talias` of each alias a file's code resolved
mut importUses {str: bool} = {}

# the alias resolved by the code being checked
fn noteImportUse(c Checker, alias str):
	if not noting: return
	importUses["{notePath(c.file if c.curFile == "" else c.curFile)}\t{alias}"] = true

# the notes that add and remove the import lines of the program's files
fn noteImports(prog Program):
	for m in prog.modules:
		if m.id == "rt" or m.id == "derive" or m.id in prog.keptNames: continue
		files str[] = []
		for d in prog.decls:
			if prog.nodes[d].mod(prog.kidIds) == m.id and
				not prog.nodes[d].file(prog.kidIds).startsWith("<") and
				prog.nodes[d].file(prog.kidIds) not in files:
				files.push(prog.nodes[d].file(prog.kidIds).copy())
		for f in files:
			if not isGpuFile(f) and not isMarkupFile(f): prog.noteFileImports(m, f)

fn noteFileImports(prog Program, m Module, file str):
	key = notePath(file)
	own = m.imports.filter(notePath(prog.nodes[it].file(prog.kidIds)) == key and
			not prog.nodes[it].hasFlag(flagInternal))
	text = (fs.readFile(file) ?? "").replace("\r", "")
	added str[] = []
	for imp in m.imports:
		alias = prog.nodes[imp].text2(prog.kidIds)
		if alias == "" or importUses.get("{key}\t{alias}") == none: continue
		if own.any(prog.nodes[it].text2(prog.kidIds) == alias): continue
		id = prog.nodes[imp].text
		if (id.split(".").last ?? "") != alias or "import {id}" in added: continue
		added.push("import {id}")
	gone = own.filter(prog.nodes[it].text2(prog.kidIds) != "" and
			importUses.get("{key}\t{prog.nodes[it].text2(prog.kidIds)}") == none and
			"{prog.nodes[it].text2(prog.kidIds)}." not in text.replace(
				"import {prog.nodes[it].text}",
				""
	))
	kept = own.filter(it not in gone)
	block = added.sorted().join("\n")
	for i, imp in gone:
		line = prog.nodes[imp].line
		into = "{block}\n" if i == 0 and kept.isEmpty and not added.isEmpty else ""
		pushNote(file, noteReplace, line, 1, sourceLineOf(file, line).len + 1, into)
	if added.isEmpty or kept.isEmpty and not gone.isEmpty: return
	if kept.isEmpty:
		pushNote(file, noteReplace, firstCodeLine(text), 1, 0, "{block}\n\n")
	else:
		last = kept.map(prog.nodes[it].line).max() ?? 1
		pushNote(file, noteReplace, last, sourceLineOf(file, last).len + 1, 0, "\n{block}")

# the first line of a file's text past its leading comments and blank lines (1-based)
fn firstCodeLine(text str):
	for i, line in text.lines():
		t = line.trimmed()
		if t != "" and not t.startsWith("#"): return i + 1
	1
