# The lint (spec 13.1.3): the forms only types tell (canon.zap), noted by the checks zap test's
# check and tests kinds make. Those whose rewrite still checks (verifyNotes, a check again) are
# kept by file under the hash of the text they were noted in: zap fmt applies a file's while its
# text is that one, and never checks; zap test says them as lint. (zap build and run keep none:
# the check again would cost a build as much again each time a file changed.) Windows is the
# repository's reference host: a module with system dirs reads differently on each system (an
# import one system's functions need and another's do not), so the findings are noted there
# alone, and fmt elsewhere is the layout (but a test's own request for the lint, explicit, is noted
# on any host).

import fs

# where a file's findings are kept: in build/cache/lint/ by its path, or, for a file under build/
# (a test's own, gone with its dir), beside it
fn lintFileOf(file str):
	if notePath(file).startsWith("{notePath("build")}/"): return "{file}.lint"
	"build/cache/lint/{testSlug(fullPath(file))}.txt"

fn hashWord(text str):
	"{u64.wrap(text.hash()):x}"

# the findings kept for a file while its text is the one they were noted in
fn keptFindings(file str, text str):
	kept = fs.readFile(lintFileOf(file)) ?? return []
	head = kept[..(kept.indexOf("\n") ?? len)]
	if head.split(" ")[0] != hashWord(text): return []
	readNotes(kept[head.len..])

# the words of a file's kept head: the hash of the text, then the notes sets verified for it
fn keptWords(file str):
	kept = fs.readFile(lintFileOf(file)) ?? return []
	kept[..(kept.indexOf("\n") ?? len)].split(" ")

# A check of the program target names (notedProgram's) made with the notes on (checkNoted), the
# files it read (lintedFiles, taken before the backend, which takes the program's declarations):
# for each file, the notes that change its text (changing), those whose rewrite still checks
# (verifyNotes; with own, the ownership too, as the program's lowering passed it), kept with what
# other programs' checks kept of it (what a program notes depends on the functions it reaches).
# A file's kept line first holds the hash of its text, then each notes set verified for it (the
# hash of the notes, how they were checked): while a program's set stands nothing is done again.
# A program that notes nothing in a file leaves what was kept of its text.
fn keepFindings(files str[], target str, own bool, explicit bool = false):
	if not onWindows() and not explicit:
		formNotes.clear()
		return
	noting = false
	noted = formNotes.copy()
	formNotes.clear()
	stale = []   # the files whose notes are verified, and their heads
	heads = []
	for f in files:
		mine = notesFor(noted, f)
		if notePath(f) != notePath(target):
			# whether a copy may go rests on what the whole program's calls change: the
			# program's own file's alone
			mine = mine.filter(.old != copyCall)
		text = fs.readFile(f) ?? ""
		words = keptWords(f)
		current = not words.isEmpty and words[0] == hashWord(text)
		if mine.isEmpty:
			if not current: _ = fs.deleteFile(lintFileOf(f))
			continue
		head = "{hashWord(text)} {hashWord(noteLines(mine))}/{"own" if own else "types"}"
		if current and head.split(" ")[1] in words: continue
		stale.push(f.copy())
		heads.push(head)
		formNotes.extend(changing(f, text, mine))
	if stale.isEmpty: return
	_ = fs.createDir("build/cache/lint")
	if not formNotes.isEmpty and not verifyNotes(target, stale, own):
		formNotes.clear()
	for i, f in stale:
		keepVerified(f, heads[i], notesFor(formNotes, f))
	formNotes.clear()

# the notes verified for a file, kept under their set's head with those kept for the same text
fn keepVerified(file str, newHead str, found Note[]):
	kept = fs.readFile(lintFileOf(file)) ?? ""
	line = kept[..(kept.indexOf("\n") ?? len)]
	same = line.startsWith("{newHead.split(" ")[0]} ")
	head = "{line} {newHead.split(" ")[1]}" if same else newHead
	merged = readNotes(kept[line.len..]).filter(o:
		same and not found.any(.line == o.line and .col == o.col)
	)
	merged.extend(found.copy())
	_ = fs.writeFile(lintFileOf(file), "{head}\n{noteLines(merged)}")

# whether the program checks, the lint's notes made when noted
fn checkNoted(mut prog Program, noted bool):
	noting = noted
	checked = prog.checkProgram()
	noting = false
	checked

# the notes of a file that change its text (fmt's layout with them, against without), or none
fn changing(file str, text str, mine Note[]):
	markup = isMarkupFile(file)
	if formatFile(text, false, mine, markup) == formatFile(text, false, [], markup): return []
	mine.copy()

# the files whose findings a program's check gives: those it read, but the runtime's and a GPU
# file's (fmt leaves its forms); their imports noted first
fn lintedFiles(prog Program):
	prog.noteImports()
	files str[] = []
	for d in prog.decls:
		f = prog.nodes[d].file()
		if not isLinted(f) or files.any(notePath(it) == notePath(f)): continue
		files.push(f.copy())
	files

# whether a file's findings are the lint's: not the runtime's, a GPU file's or a made name's
fn isLinted(file str):
	not file.startsWith("<") and not isGpuFile(file) and
		not notePath(file).startsWith("{notePath(runtimeDir())}/")

# the files a path covers for the lint: those under it, and for an entry file those of the
# repository its check read
fn lintPathFiles(path str):
	files = fs.walk(path, sources = true)
	if not fs.isSourceFile(path) or not isEntryText(fs.readFile(path) ?? ""): return files
	for f in entryReads(path):
		if fs.isSourceFile(f) and isLinted(f) and not files.any(notePath(it) == notePath(f)):
			files.push(f.copy())
	files

# ZAP_RUN's word that makes zap test's lint write the findings (zap fmt on their files) instead of
# failing; a land asks it of the merge's suite, whose checkout holds forms the branch's alone lacked
fn fixLintWord():
	TraceWord(
		"fixlint",
		"zap test: the lint's findings written to their files (zap fmt) instead of failing the run"
	)

# zap test's lint: the findings kept for the files under the paths, said a line each; whether
# there are none (with fixlint they are written, and the run passes with the files changed)
fn lintCheck(paths str[]):
	found = 0
	said str[] = []
	written str[] = []
	for path in paths:
		for f in lintPathFiles(path):
			if said.any(notePath(it) == notePath(f)): continue
			said.push(f.copy())
			for n in keptFindings(f, fs.readFile(f) ?? ""):
				found += 1
				print("{f}:{n.line}:{n.col}: {n.findingText()} (zap fmt applies it)")
				if not (f in written): written.push(f.copy())
	if found > 0 and fixLintWord().on():
		for f in written:
			formatPath(f, false)
		print("lint: {found} forms written to {written.len} files")
		return true
	if found > 0:
		print("lint: {found} forms only types tell to write")
	found == 0

# what a host that does not note the lint says of it, "" on Windows, where it is noted
fn lintNotRun():
	if onWindows(): return ""
	"lint: not run on {hostTarget()}; run zap test --only check on Windows before landing"

# what a finding changes, on one line
fn findingText(n Note):
	if n.kind == noteCoalesce: return "the match is written with ??"
	old = n.old.lines()
	"`{old[0] if not old.isEmpty else ""}{"..." if old.len > 1 else ""}` is `{n.text.replace("\n", " ")}`"
