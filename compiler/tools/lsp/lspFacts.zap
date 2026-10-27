# What the checker tells the language server of a file: the program the file belongs to (its
# parts' owner, its module, or itself) checked in this process with the editor's texts in place of
# the files', as zap fmt checks (canon.zap); then each binding's type as its scope ended, the type
# of each name and field read, and the errors, every place 0-based as the protocol counts.

# a name the checker typed: a binding (a let, a parameter, a loop's or an arm's name) or a use
import fs

type NameFact:
	line i64
	col i64
	name str
	ty str
	binding bool

type ErrorFact:
	file str   # as the check named it
	line i64
	col i64
	message str

# one check's facts, by notePath of each file
type CheckFacts:
	target str   # what was checked (checkTarget)
	names {str: NameFact[]}
	errors {str: ErrorFact[]}

type NotedBinding:
	file str
	line i64
	col i64
	name str
	ty TypeId

# while the server checks: every binding as its scope ends (exitScope)
mut bindingsNoted = false
mut notedBindings NotedBinding[] = []

fn noteBinding(c Checker, v Var):
	if v.name == "_" or not v.name[0].isWordByte() or "$" in v.name or "#" in v.name or
		"[" in v.name:
		return
	file = c.file if c.curFile == "" else c.curFile
	notedBindings.push(NotedBinding(file.copy(), v.line, v.col, v.name.copy(), v.ty))

# What the program holding `file` tells of the files `wanted` (notePath keys): its errors in every
# file, the names of the wanted ones. `texts` are the editor's texts by path, read in place of the
# files' (the program it belongs to too).
fn checkFacts(root str, file str, texts {str: str}, wanted {str: bool}):
	said = "{root}/build/lsp-said-{processId()}.txt"
	_ = fs.createDir("{root}/build")
	outputTo(said)   # stdout is the protocol's: what the check prints goes apart
	for path, text in texts:
		if text != (fs.readFile(path) ?? ""): sourceOverrides[notePath(path)] = text.copy()
	notedBindings = []
	bindingsNoted = true
	target = checkTarget(root.replace("\\", "/"), file.replace("\\", "/"))
	facts = CheckFacts(target.copy(), names = {}, errors = {})
	facts.names = checkedNames(target, wanted)
	bindingsNoted = false
	notedBindings = []
	sourceOverrides = {}
	outputBack()
	_ = fs.deleteFile(said)
	for line in errorLines:
		noteError(facts.errors, line)
	facts

# the names of the wanted files, the target's program checked
fn checkedNames(target str, wanted {str: bool}):
	prog = notedProgram(target) ?? return {}
	refusalEnds = false
	prog.checkProgram()
	refusalEnds = true
	names = prog.usedNames(wanted)
	for b in notedBindings:
		key = notePath(b.file)
		if key not in wanted: continue
		names.noteUnder(
			key,
			NameFact(b.line - 1, b.col - 1, b.name.copy(), typeStr(prog.types, b.ty), true)
		)
	names

# the target a file is checked as: the program whose parts hold it, else the file when it is a
# program (statements or tests), else its dir, a module
fn checkTarget(root str, file str) str:
	if partOwner(file, root) is owner: return checkTarget(root, owner)
	if isEntryText(readSource(file)): return file.copy()
	dir = dirPrefix(file)
	dir[..dir.len - 1].copy()

# the names read in the wanted files' declarations, with their types: a variable, a constant, a
# field (not a function, a type nor a module)
fn usedNames(prog Program, wanted {str: bool}):
	out {str: NameFact[]} = {}
	seen = fill(prog.nodes.len, false)
	for d in prog.decls:
		key = notePath(prog.nodes[d].file(prog.kidIds))
		if key not in wanted: continue
		open = [d]
		while open.pop() is e:
			if seen[e]: continue
			seen[e] = true
			n = prog.nodes[e]
			if (n.kind == nIdent or n.kind == nField) and n.ty is t and n.line > 0 and
				typedName(n.text) and prog.types[t].kind != tFn and prog.types[t].kind != tError:
				out.noteUnder(
					key,
					NameFact(n.line - 1, n.col - 1, n.text.copy(), typeStr(prog.types, t), false)
				)
			open.extend(n.kids(prog.kidIds))
			open.extend(n.sub(prog.kidIds))
			open.extend(n.types(prog.kidIds))
	out

# whether a node's text is a name a program writes in lowercase (not one the compiler made)
fn typedName(text str):
	not text.isEmpty and text[0] >= 'a' and text[0] <= 'z' and
		(0..text.len).all(text[it].isWordByte())

# an error line the check said (`file:line:col: error[code]: message`) noted under its file
fn noteError(mut errors {str: ErrorFact[]}, line str):
	at = line.indexOf(": error") ?? return
	after = line.indexOf(": ", at + 7) ?? return
	place = line[..at].split(":")
	if place.len < 3: return
	key = notePath(place[..len - 2].join(":"))
	fact = ErrorFact(
		place[..len - 2].join(":"),
		(i64.parse(place[len - 2]) ?? 1) - 1,
		(i64.parse(place[len - 1]) ?? 1) - 1,
		line[after + 2..].copy()
	)
	errors.noteUnder(key, fact)

fn noteUnder<T>(mut facts {str: T[]}, key str, move fact T):
	if facts.get(key) is mut at:
		at.push(fact)
	else:
		facts[key.copy()] = [fact]
