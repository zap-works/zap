# `zap doc`: what the runtime, the standard library and the libraries beside it (engine, rhi)
# offer, and what the spec (spec/) says, read from their sources each time, so it is never out
# of step with them. With no argument it lists the modules with the first line of each one's
# header comment; with a module's name, that module's public declarations with the first line of
# their comments; with a type's name, its fields and then every function taking it first, by
# module and file; with `spec`, the spec's sections; with a section's number (`6.5`) or name
# (`errors`), that section; with `find` and words, every public declaration whose name,
# signature or comment holds all of the words, then every section that does. An empty answer to
# `find` means the API is missing: it is added where it belongs, not copied.

import fs

type ApiModule:
	name str
	origin str   # "runtime", "std", or the dependency it comes from
	files str[]

type ApiEntry:
	module str
	signature str   # as a caller writes it: `T[].push(move x T)`, `bytes.u32le(b u8[], at i64) i64`
	name str   # as declared (listPush): find matches it too
	doc str   # the first line of its comment (or of the comment over its group)

# a section of the spec: a file of spec/ whose first line is its number and title
# (`# 6.5 Errors: ...`); a chapter's file is its first section's too, whose heading follows in the
# file's opening comment (`# 6. Control flow, optionals and errors`, then `# 6.1 Conditions and loops`)
type SpecSection:
	number str   # without a final dot: `6`, `6.5`
	title str
	name str   # the file's name without `.zap`: `errors`
	file str

pub fn docCommand(line CommandLine):
	words = line.operands
	modules = apiModules()
	if words.isEmpty:
		for m in modules:
			print("{m.name:<12} {m.moduleSummary()}")
		print("spec         the language's specification: its sections, one by its number or name (zap doc 6.5, zap doc errors)")
		print("{docTables.join(", ")}: the compiler's tables, each after its section")
		return
	if words[0] == "find":
		wanted = words[1..].map(.lower())
		if wanted.isEmpty:
			exit(1, "usage: zap doc find <words>")
		for m in modules:
			for e in m.moduleEntries():
				hay = "{e.module} {e.name} {e.signature} {e.doc}".lower()
				if wanted.all(it in hay):
					print(e.entryLine(true))
		findSections(wanted)
		return
	if words[0] == "spec" or words[0][0].isDigit():
		specCommand(words[0])
		return
	if explainError(words[0]): return
	at = -1
	for i, m in modules:
		if m.name == words[0]:
			at = i
	if at < 0 and docTable(words[0]) is table and
		specSections().findIndex(.name == words[0]) == none:
		print(table)
		return
	if at < 0 and not typeEntries(modules, words[0]) and not specByName(words[0]):
		exit(1, "zap doc: no module, type, error or section '{words[0]}' (zap doc lists the modules, zap doc errors the errors, zap doc spec the sections)")
	if at < 0: return
	for e in modules[at].moduleEntries():
		print(e.entryLine(false))

# zap test's doc: the public declarations with no comment line saying what they do, in the module
# the name text names (every module when none), each one listed; whether there is none, so a check
# keeps `zap doc` able to answer.
fn undocumentedCheck(request TestRequest):
	missing = 0
	for m in apiModules():
		if request.name != "" and m.name != request.name: continue
		for e in m.moduleEntries():
			if e.doc == "":
				print(e.signature)
				missing += 1
	if missing > 0:
		print("doc: {missing} public declarations have no comment: write one line above each saying what it does")
	else:
		print("doc: every public declaration has a comment")
	missing == 0

fn entryLine(e ApiEntry, named bool):
	head = "{e.module}: {e.signature}" if named else e.signature.copy()
	head if e.doc == "" else "{head}    # {e.doc}"

# the runtime, every module of std, and every module of the libraries beside it
fn apiModules():
	out = []
	rt = runtimeDir()
	out.push(
		ApiModule(
			name = "runtime",
			origin = "runtime",
			files = runtimeFiles(rt).map(rt + it)
		)
	)
	addDirModules(out, stdDir(), "std")
	for name in rootLibraries():
		addDirModule(out, zapRoot(), name, "library")
	out

# each dir under dir holding .zap files is a module named by the dir, with its parts (tests,
# examples and build dirs aside, and the dirs that are a module's parts)
fn addDirModules(mut out ApiModule[], dir str, origin str):
	for name in (fs.list(dir) ?? []).sorted():
		if "." in name or name == "tests" or name == "examples" or name == "build": continue
		addDirModule(out, dir, name, origin)

# the module of the dir name under dir, unless a part of a module above it, and the ones under it
fn addDirModule(mut out ApiModule[], dir str, name str, origin str):
	sub = "{dir}{name}/"
	files = moduleFiles(sub)
	inPart = out.any(.files.any(.startsWith(sub)))
	if not files.isEmpty and not inPart:
		out.push(
			ApiModule(
				name = name.copy(),
				origin = origin.copy(),
				files = withParts(files.sorted().map(sub + it))
			)
		)
	addDirModules(out, sub, origin)

# the first line of the module's header comment: its file named as the module, else its first
fn moduleSummary(m ApiModule):
	if m.origin == "runtime":
		return "the built-ins every program has without an import: methods of lists, str, maps and numbers, files, time"
	main = 0
	for i, f in m.files:
		if f.endsWith("/{m.name}.zap"):
			main = i
	text = fs.readFile(m.files[main]) ?? ""
	header = ""
	for line in text.replace("\r", "").lines():
		t = line.trimmed()
		if not t.startsWith("#"):
			break
		part = t[1..]
		header += "{part.trimmed()}\n"
	firstSentence(header.trimmed())

# the public declarations of a module, in the order of its files
fn moduleEntries(m ApiModule):
	out = []
	for file in m.files:
		text = fs.readFile(file) ?? ""
		decls = scanDecls(text)
		publicTypes = decls
			.filter(d:
				d.detail.startsWith("pub type ") or d.detail.startsWith("pub shared type ")
			)
			.map(.name.copy())
		for d in decls:
			visible = d.detail.startsWith("pub ") if d.container == ""
				else d.container in publicTypes
			if not visible or (m.origin == "runtime" and runtimeInternal(d.name)): continue
			out.push(
				ApiEntry(
					module = m.name.copy(),
					signature = m.callerSignature(d),
					name = d.name.copy(),
					doc = firstSentence(d.doc)
				)
			)
	out

# a comment's first sentence, on one line and at most about a hundred characters
fn firstSentence(doc str):
	text = doc.replace("\n", " ")
	end = text.len
	for i in 0..text.len:
		if sentenceEndsAt(text, i):
			end = i
			break
	if end <= 100: return text[..end].copy()
	cut = text[..100]
	at = cut.lastIndexOf(" ") ?? 100
	"{cut[..at]}..."

# the runtime's plumbing: what the compiler's generated code calls, not a program
fn runtimeInternal(name str):
	name.startsWith("rt") or name.endsWith("Raw") or name == "testRun" or name == "testExit"

# the declaration as a caller writes it: a runtime method on its receiver (`T[].push(...)`), a
# module's function after the module's name, a method after its type
fn callerSignature(m ApiModule, d Decl):
	unmarked = d.detail.replace("pub ", "")
	sig = unmarked.trimmed()
	if d.container != "": return "{d.container}.{afterFirstParam(d.name, sig)}"
	if m.origin == "runtime" and sig.startsWith("fn "):
		receiver = runtimeReceiver(d.name, sig)
		if receiver != "":
			return "{receiver}.{methodForm(d.name[receiverPrefix(receiver).len..], sig)}"
		return sig[3..].copy()
	if m.origin == "runtime": return sig.copy()
	"{m.name}.{sig[3..]}" if sig.startsWith("fn ") else "{m.name}: {sig}"

# `zap doc Orbit`: the fields of each public type of that name, then every public function taking
# it first, by module and file, each with the first line of its comment; whether there was one
fn typeEntries(modules ApiModule[], name str):
	found = false
	for m in modules:
		for file in m.files:
			text = fs.readFile(file) ?? ""
			for d in scanDecls(text):
				if (d.kind == symStruct or d.kind == symEnum) and d.name == name and
					d.detail.startsWith("pub "):
					found = true
					print("{m.name}.{name}    # {firstSentence(d.doc)}")
					for f in fieldNames(text, d):
						print("\t{f}")
	if not found: return false
	for m in modules:
		for file in m.files:
			taking = scanDecls(fs.readFile(file) ?? "").filter(d:
				(d.kind == symMethod or d.kind == symFunction and d.detail.startsWith("pub ")) and
					firstParamType(d.detail) == name
			)
			if taking.isEmpty: continue
			print("{m.name} ({fs.fileName(file)}):")
			for d in taking:
				e = ApiEntry(
					module = m.name.copy(),
					signature = m.callerSignature(d),
					name = d.name.copy(),
					doc = firstSentence(d.doc)
				)
				print("\t{e.entryLine(false)}")
	true

# the receiver a runtime function is a method of: its name starts with the receiver's prefix and
# a capital (listPush), and its first parameter is of the receiver's type; "" for a function
fn runtimeReceiver(name str, sig str):
	open = sig.indexOf("(") ?? -1
	if open < 0: return ""
	params = sig[open + 1..]
	firstEnd = params.indexOf(",") ?? (params.indexOf(")") ?? params.len)
	first = params[..firstEnd]
	for (prefix, receiver) in runtimeReceivers:
		named = name.startsWith(prefix) and name.len > prefix.len and
			name[prefix.len] >= 'A' and name[prefix.len] <= 'Z'
		if named and takesReceiver(first, receiver): return receiver.copy()
	""

# whether a first parameter's text is of the receiver as runtimeReceivers names it
fn takesReceiver(first str, receiver str):
	if receiver == "T[]": return first.endsWith("]")
	if receiver.startsWith(r"{"): return first.endsWith("}")
	first.endsWith(" {receiver}")

fn receiverPrefix(receiver str):
	for (prefix, r) in runtimeReceivers:
		if r == receiver: return prefix.copy()
	""

# listPush<T>(mut xs T[], move x T) as push(move x T): the method's name in lower case, and
# its parameters after the receiver
fn methodForm(rest str, sig str):
	afterFirstParam(rest[..1].lower() + rest[1..], sig)

# `zap doc spec`: the spec's sections, a subsection two spaces in; `zap doc 6.5`: that section,
# a chapter's (`zap doc 6`) with its subsections, each file once
fn specCommand(word str):
	sections = specSections()
	if word == "spec":
		for s in sections:
			indent = "  " if "." in s.number else ""
			print("{indent}{s.number} {s.title}")
		return
	if sections.findIndex(.number == word) == none:
		exit(1, "zap doc: no section {word} (zap doc spec lists them)")
	shown = ""
	for s in sections:
		if (s.number == word or s.number.startsWith("{word}.")) and s.file != shown:
			s.printSection()
			shown = s.file.copy()

# `zap doc errors`: the section of that name, as its file holds it; whether there is one
fn specByName(name str):
	for s in specSections():
		if s.name == name:
			s.printSection()
			return true
	false

# a section as its file holds it, then the compiler's table of its name
fn printSection(s SpecSection):
	print((fs.readFile(s.file) ?? "").replace("\r", "").trimmedEnd())
	if docTable(s.name) is table:
		print("\n{table}")

# every section of the spec whose file holds all the words, a file by its last heading
fn findSections(wanted str[]):
	sections = specSections()
	for i, s in sections:
		if i + 1 < sections.len and sections[i + 1].file == s.file: continue
		hay = (fs.readFile(s.file) ?? "").lower()
		if wanted.all(it in hay):
			print("spec {s.number}: {s.title}")

# the sections of the spec in the order of their numbers (6.2 before 6.10, 3.1 before 3.1.1)
fn specSections():
	dir = specDir()
	found = []
	for name in fs.list(dir) ?? []:
		if fs.isSourceFile(name):
			found.extend(specHeadings(dir + name, name))
	keys = found.map(sectionKey(.number))
	order = (0..found.len).map(it)
	order.sortBy(keys[it])
	order.map(found[it].copy())

# a section's number as one integer that sorts as the numbers do, three levels deep
fn sectionKey(number str):
	parts = number.split(".")
	key = 0
	for i in 0..3:
		key = key * 1000 + ((i64.parse(parts[i]) ?? 0) if i < parts.len else 0)
	key

# a spec file's sections: its first line's, then those of its opening comment that the first one's
# number leads (`6.1` after `6.`); none when its first line is no heading
fn specHeadings(file str, name str):
	out = []
	lines = (fs.readFile(file) ?? "").replace("\r", "").lines()
	if lines.isEmpty: return out
	first = specHeading(lines[0], name, file) ?? return out
	for line in lines[1..]:
		if not line.startsWith("#"): break
		if specHeading(line, name, file) is s and s.number.startsWith("{first.number}."):
			out.push(s)
	out.insert(0, first)
	out

# a heading line's section (`# 6.5 Errors: ...`); none when the line is not one
fn specHeading(line str, name str, file str) SpecSection?:
	heading = line.trimmedEnd()
	if heading.len < 3 or not heading.startsWith("# ") or not heading[2].isDigit(): return none
	space = heading.indexOf(" ", 2) ?? -1
	if space < 0: return none
	cut = space - 1 if heading[space - 1] == '.' else space
	number = heading[2..cut]
	if not number.bytes().all(.isDigit() or it == '.'): return none
	SpecSection(
		number = number.copy(),
		title = heading[space + 1..].copy(),
		name = name[..len - 4].copy(),
		file = file.copy()
	)

# ---------- the tables zap doc prints ----------

# a row of the precedence table: a level's forms and what they are
type FormRow:
	forms str
	what str

# the forms looser than every binary operator, loosest first, and those tighter than them, around
# the levels of binaryOperators
looseForms = [FormRow("a..b  a..=b", "a range")]
choiceForm = FormRow("a if c else b", "the value a condition picks")
tightForms = [
	FormRow("-x  ~x  not x  move x  mut ref x  try x", "the unary operators"),
	FormRow("x?.f  x.f  x[i]  f(x)", "the postfix forms, tightest")
]

# the table of a name `zap doc` prints after the spec's section of that name (or alone, for a
# table with no section of its own); none for another name
pub fn docTable(name str) str?:
	match name:
		"keywords":
			"reserved: {keywords.join(" ")}\ncontextual: {contextualWords().join(" ")}"
		"operators": precedenceTable()
		"refused": refusedTable()
		"commands": zapUsage()
		"environment": environmentTable()
		_: none

# the names docTable knows, for `zap doc` to list
pub docTables = ["keywords", "operators", "refused", "commands", "environment"]

# the precedence levels, loosest first: the forms above the binary operators, their levels
# (binaryOperators) with the choice between `??` and `or`, the unary operators, `**` and the postfix forms
fn precedenceTable():
	rows = looseForms.copy()
	levels = binaryOperators.map(.level)
	level = levels.max() ?? 0
	while level >= (levels.min() ?? 0):
		if level == -1:
			rows.push(tightForms[0].copy())
		if level == 5:
			rows.push(choiceForm.copy())
		ops = binaryOperators.filter(.level == level).map(.text.copy())
		if not ops.isEmpty:
			forms = "{ops.join("  ")}  not in" if "in" in ops else ops.join("  ")
			rows.push(FormRow(forms, "right-associative" if level == -1 else ""))
		level -= 1
	rows.push(tightForms[1].copy())
	width = rows.map(.forms.len).max() ?? 0
	rows.map("{.forms}{" ".repeat(width - .forms.len)}   {.what}".trimmedEnd().copy()).join("\n")

# the forms the language refuses for the one it keeps: each error named ...Spelling, its code and
# its message (`zap doc <code>` explains one)
fn refusedTable():
	compileErrors
		.filter(.name.endsWith("Spelling"))
		.map("{kebabCase(.name)}: {.text}")
		.join("\n")
