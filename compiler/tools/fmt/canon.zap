# What only the checker can tell zap fmt (lint): the forms of a file that say a thing more shortly once
# its types are known. A program checked with the notes on (noting) notes them:
#   - `Shape.Circle` where the place expects a Shape (or an optional of one) is `.Circle`;
#   - a struct's literal that names every field, some `f = b.f` of one local b of its type, and
#     whose fields are all plain data, is `Type(..b, g = v)` (b's fields are copied either way);
#   - a match giving its value whose first arm gives what it binds and whose other gives a value
#     of that type, or leaves, may be written with ?? (rewrite.zap writes it);
#   - `f(x, a)`, f a function taking x's type first that `x.f(a)` calls, is `x.f(a)`;
# None is noted in the runtime's and the derived code, or in a generic's body (its instances'
# types vary) unless it reads alike for every type. What a check notes is kept for zap fmt
# (lint.zap), which never checks.

import fs

noteReplace = 0   # the cut bytes at line:col (old) replaced by text
noteCoalesce = 1   # the match at line:col may be written with ??

pub type Note:
	kind i64
	file str   # the file's full path, normalized (notePath)
	line i64
	col i64
	cut i64
	old str
	text str

# whether the checker notes the forms, and the notes made
mut noting = false
mut formNotes Note[] = []

# whether the code being checked is the runtime's or the derived functions', which keep the forms
# a program is told to change
fn inRuntimeOrDerived(c Checker):
	c.curMod >= 0 and (c.modules[c.curMod].id == "rt" or c.modules[c.curMod].id == "derive")

# a note at line:col of the file being checked (cut bytes there replaced by text); once per place.
# Written alike for every type (syntax): noted in a generic's body as well.
fn canonNote(
	mut c Checker,
	kind i64,
	line i64,
	col i64,
	cut i64,
	text str,
	syntax bool = false
):
	if not noting or not syntax and not c.subst.names.isEmpty or c.inRuntimeOrDerived(): return
	pushNote(c.file if c.curFile == "" else c.curFile, kind, line, col, cut, text)

# whether the file being checked has a note at line:col (a `try ` put there would share its place)
fn notedAt(c Checker, line i64, col i64):
	file = notePath(c.noteSource())
	formNotes.any(.file == file and .line == line and .col == col)

# the note itself, once per place
fn pushNote(src str, kind i64, line i64, col i64, cut i64, text str):
	file = notePath(src)
	if formNotes.any(.file == file and .line == line and .col == col): return
	formNotes.push(
		Note(kind, file, line, col, cut, old = sourceSpan(src, line, col, cut), text = text.copy())
	)

# the n bytes of the file being checked at line:col (fewer at the line's end)
fn sourceAt(c Checker, line i64, col i64, n i64):
	text = sourceLineOf(c.file if c.curFile == "" else c.curFile, line)
	if col < 1 or col - 1 >= text.len: return ""
	text[col - 1..(col - 1 + n).min(len)].copy()

# the cut bytes of a file from line:col, over the lines below when they go past its end ("" when
# the file ends first)
fn sourceSpan(src str, line i64, col i64, cut i64):
	text = sourceLineOf(src, line).copy()
	next = line + 1
	while col - 1 + cut > text.len and next <= line + 50:
		text += "\n{sourceLineOf(src, next)}"
		next += 1
	text[col - 1..col - 1 + cut].copy() if col >= 1 and col - 1 + cut <= text.len else ""

# a path as notes name files: full, with `/` between its parts, its `.` and `..` dirs taken
# out, in lower case (a file reached two ways is one file)
fn notePath(path str):
	fullPath(path).lower()

# `Type.Variant` (or `module.Type.Variant`) whose variant name is at line:col: where its type
# starts on that line, or -1 when it is not written so (a generic's arguments, another layout)
fn qualifiedStart(file str, line i64, col i64):
	text = sourceLineOf(file, line)
	k = col - 2   # the dot before the variant's name
	if k < 1 or k >= text.len or text[k] != '.': return -1
	start = k
	while start > 0 and text[start - 1].isWordByte():
		start -= 1
	if start == k or not (text[start] >= 'A' and text[start] <= 'Z'): return -1
	if start > 1 and text[start - 1] == '.' and text[start - 2].isWordByte():
		start -= 1   # module.Type
		while start > 0 and text[start - 1].isWordByte():
			start -= 1
	start

# the notes as lint.zap keeps them (readNotes reads them back), a line each
fn noteLines(notes Note[]):
	notes
		.map("{.kind}\t{.file}\t{.line}\t{.col}\t{.cut}\t{noteField(.old)}\t{noteField(.text)}\n")
		.join("")

# Whether the program, checked again with the noted replacements applied to its files, still
# checks: quickly, the bodies of the patched files alone and no lowering, until it does or its
# errors name no note's file, then whole. While it does not, in each file its errors name the
# notes on their lines go, or when they name none, or the file failed before, its dropped copies
# (their error may be at a later use), else all its notes, and it is checked again.
fn verifyNotes(target str, linted str[], own bool):
	erred str[] = []
	quick = true
	loop 12:
		found = checkWithNotes(target, linted, own, quick)
		if found == none:
			if not quick: return true
			quick = false
			continue
		failed = found ?? []
		files = failed.map(.split("\t")[0].copy())
		before = formNotes.len
		lined = formNotes
			.filter("{.file}\t{.line}" in failed and .file not in erred)
			.map(.file.copy())
		whole = files.filter(it not in lined)
		copies = formNotes
			.filter(.file in whole and .old == copyCall and .file not in erred)
			.map(.file.copy())
		formNotes = formNotes.filter(n:
			"{n.file}\t{n.line}" not in failed and
				not (n.file in whole and (n.old == copyCall or n.file not in copies))
		)
		if formNotes.len == before:
			if not quick: return false
			quick = false   # (its errors are in files no note patched)
			continue
		if formNotes.isEmpty: return true
		erred.extend(files)
	false

# whether what the check again says goes to a file of its own already (a zap answering a test's
# request, answers.zap): else it is sent apart here
mut sayingApart = false

# the places (`file\tline`, errorPlace) of the errors of the program checked with the notes
# applied to the files, none when it checks: in this zap's process, the texts patched in place of
# the files' own (checkedHere); the ownership is checked too with own, or when a copy is dropped
fn checkWithNotes(target str, files str[], own bool, quick bool):
	lines = []
	for f in files:
		mine = notesFor(formNotes, f)
		if mine.isEmpty: continue
		text = (fs.readFile(f) ?? "").replace("\r", "").lines()
		applyNotes(text, mine)
		lines.push("{notePath(f)}\t{noteField(text.join("\n"))}")
	if lines.isEmpty: return none
	lowersPatchedOnly = own
	bodiesPatchedOnly = quick
	failed = checkedHere(target, lines, not quick and (own or formNotes.any(.old == copyCall)))
	bodiesPatchedOnly = false
	lowersPatchedOnly = false
	failed

# the places (`file\tline`) an error's first line names: its own (`path:line:col: error[...]`)
# and the lines of that file its message names (`... given away at line 8`)
fn errorPlaces(line str):
	at = line.indexOf(": error[") ?? return []
	parts = line[..at].split(":")
	if parts.len < 3: return []
	n = i64.parse(parts[len - 2]) ?? return []
	file = notePath(parts[..parts.len - 2].join(":"))
	out = ["{file}\t{n}"]
	words = line[at..].split(" ")
	for i in 1..words.len:
		if words[i - 1] != "line": continue
		k = 0
		while k < words[i].len and words[i][k].isDigit():
			k += 1
		if k > 0 and i64.parse(words[i][..k]) is named: out.push("{file}\t{named}")
	out

# The places of the errors of the program of target with the patched texts (lines, `path\ttext`),
# the lowering and its ownership too with lowers, none when it checks. What it says goes apart,
# and the functions of the modules the group of checks already checked clean (checksShared) are
# not checked again unless a text of theirs or of their imports is patched.
fn checkedHere(target str, lines str[], lowers bool) str[]?:
	notes = formNotes.copy()   # (a program loaded forgets them)
	said = "build/cache/lint/said-{processId()}"
	if not sayingApart: outputTo(said)
	overridden(lines)
	overridesRead = {}
	checks = checksPatched(target, lowers) and allOverridesRead()
	sourceOverrides = {}
	if not sayingApart:
		outputBack()
		_ = fs.deleteFile(said)
	formNotes = notes
	if checks: return none
	places = []
	for line in errorLines:
		places.extend(errorPlaces(line))
	places

fn checksPatched(target str, lowers bool):
	prog = notedProgram(target) ?? return false
	refusalEnds = false
	ok = prog.checkProgram() and (not lowers or prog.genX64(""))
	refusalEnds = true
	ok

# Whether the program checked again read every patched text: one it did not read (a note took
# away the import that reached it) is not checked, an error at its first line said for it (not
# the table's: the lint's checks alone read it)
fn allOverridesRead():
	unread = sourceOverrides.keys().filter(overridesRead.get(it) == none)
	for key in unread:
		said = "{key}:1:1: error[unread]: the program checked again did not read it"
		errorLines.push(said.copy())
		eprint(said)
	unread.isEmpty

# the patched texts (`path\ttext` lines) read in place of their files'
fn overridden(lines str[]):
	for line in lines:
		f = line.split("\t")
		if f.len == 2: sourceOverrides[f[0].copy()] = unnoteField(f[1])

# the program a target stands for: a file's own, its tests made functions of it; a module
# dir's, a program beside the dir that imports it; none when it does not load
fn notedProgram(target str) Program?:
	if fs.isSourceFile(target):
		prog = try loadProgram(target)
		prog.addTestFunctions(target)
		return prog
	parent = dirPrefix(target).copy()
	id = target[parent.len..].copy()
	loadProgramText("{parent}$fmt.zap", "import {id}\n\npass\n")

# a test file's runnable tests made functions of the program (as zap test makes them), so their
# bodies are checked too; with no main of its own the first is the entry. How many there are.
fn addTestFunctions(mut prog Program, file str):
	n = 0
	for d in prog.tests.copy():
		if prog.nodes[d].file() != file or prog.nodes[d].ival >= 2: continue
		f = newNode(prog.nodes, prog.kidIds, nFnDecl, prog.nodes[d].line, prog.nodes[d].col)
		prog.nodes[f].text = "$fmt{n}"
		prog.nodes[f].setText2("$fmt{n}")
		prog.nodes[f].nodePart().file = file.copy()
		prog.nodes[f].nodePart().sub.push(prog.nodes[d].sub()[0])
		prog.decls.push(f)
		n += 1
	if n > 0 and not prog.hasMain():
		prog.entry = "$fmt0"
	n

# a note's text field: its backslashes, tabs and line breaks escaped
fn noteField(s str):
	s.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r")

fn unnoteField(s str) str:
	out u8[] = []
	k = 0
	while k < s.len:
		if s[k] == '\\' and k + 1 < s.len:
			b = s[k + 1]
			out.push(9 if b == 't' else 10 if b == 'n' else 13 if b == 'r' else b)
			k += 2
			continue
		out.push(s[k])
		k += 1
	str(move out)

# the notes noteLines wrote
fn readNotes(text str):
	found = []
	for line in text.lines():
		f = line.split("\t")
		if f.len != 7: continue
		found.push(
			Note(
				kind = i64.parse(f[0]) ?? -1,
				file = f[1].copy(),
				line = i64.parse(f[2]) ?? 0,
				col = i64.parse(f[3]) ?? 0,
				cut = i64.parse(f[4]) ?? 0,
				old = unnoteField(f[5]),
				text = unnoteField(f[6])
			)
		)
	found

# whether a file has top-level statements (its main) or tests: a program of its own
fn isEntryText(text str):
	hasTests(text) or hasTopStatement(text)

# whether a file declares a test
fn hasTests(text str):
	text.startsWith("test \"") or "\ntest \"" in text

# the notes of one file (its path as fs.walk gives it)
fn notesFor(all Note[], file str):
	full = notePath(file)
	all.filter(.file == full).map(.copy())

# The replacements noted for a file applied to its lines, the last first (each note's place
# stays where the text was); one whose text is not there any more is left out. One over several
# lines leaves the first: the lines it took are given (their numbers before).
fn applyNotes(mut lines str[], mine Note[]):
	taken = []
	ordered = mine.filter(.kind == noteReplace).sortedBy(-.line, -.col)
	for n in ordered:
		below = n.old.count('\n')   # the newlines it holds
		if n.line < 1 or n.line + below > lines.len: continue
		l = lines[n.line - 1].copy()
		for k in 0..below:
			l += "\n{lines[n.line + k]}"
		at = n.col - 1
		if at < 0 or at + n.cut > l.len or l[at..at + n.cut] != n.old: continue
		lines[n.line - 1] = l[..at] + n.text + l[at + n.cut..]
		for k in 0..below:
			lines.remove(n.line)
			taken.push(n.line + 1 + k)
	taken

# The written result of the function whose `fn` is at line:col (`fn f(a i64) i64:`): the line,
# the column just past its parameters' `)`, and the length from there up to the `:` that ends
# the signature (the space before the type with it); none when it is not written so
fn resultSpan(src str, line i64, col i64) (i64, i64, i64)?:
	ends = try paramsEnd(src, line, col)
	at, close = ends
	text = sourceLineOf(src, at)
	start = close + 1
	end = start
	depth = 0
	while end < text.len:
		b = text[end]
		if b in ['(', '[', '{', '<']:
			depth += 1
		elif b in [')', ']', '}', '>']:
			depth -= 1
		elif b == ':' and depth == 0:
			break
		end += 1
	if end >= text.len or end == start or text[start] != ' ': return none
	(at, start + 1, end - start)

# the line and the byte of the `)` that closes the parameters of the function at line:col (they
# may go over lines, a default's strings skipped), or none
fn paramsEnd(src str, line i64, col i64) (i64, i64)?:
	depth = 0
	quoted = false
	for at in line..line + 50:
		text = sourceLineOf(src, at)
		from = (try text.indexOf("(", col - 1)) if at == line else 0
		k = from
		while k < text.len:
			b = text[k]
			if quoted:
				if b == '\\':
					k += 1
				elif b == '"':
					quoted = false
			elif b == '"':
				quoted = true
			elif b == '(':
				depth += 1
			elif b == ')':
				depth -= 1
				if depth == 0: return (at, k)
			k += 1
	none
