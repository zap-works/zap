# `zap run --live`: the program rebuilt when a source is saved, the new build swapped into the
# running program (spec 13.1). A build made for it enters each function through its slot
# (a jump through the slot at its entry, the slot leading to its body), inlines none of the program's
# functions into another, starts the runtime's watcher (runtime/core/live.zap) and writes beside the
# executable a `.live` file: where its data is, its slots, the references of its code into the
# state (the global slots and the module variables) and its layout, which must be the running
# build's for a swap. A build not made for it is unchanged.

import fs

# set by zap run --live for the build it starts: a build made for it (zap build reads it)
fn liveBuildVariable():
	InternalVariable("ZAP_BUILD_LIVE")

alias nodes = g.c.nodes
alias tys = g.c.types

# whether this build is for a live run
mut liveBuild = false
# the data offsets below it are the state: the global slots and the module variables
mut liveStateEnd = 0
mut liveSlots LiveEntry[] = []

# a function's body (past the jump at its entry) and its slot, by its key
type LiveEntry:
	key str
	body i64   # an offset in the code
	slot i64   # an offset in the data

# at a function's first byte, in a live build: the jump through its slot, which leads to the body
# right after it until a swap leads it elsewhere
fn liveEntry(mut g Gen, key str):
	if not liveBuild: return
	bytesAlign(g.a.data, 8)
	slot = g.a.asmDataZero(8)
	if onArm():
		g.a.a64AdrData(a64T0, slot)
		g.a.a64Ldr(a64T0, a64T0, 0)
		g.a.a64(0xD61F_0000 | a64T0 << 5)   # br x16
	else:
		g.a.em2(0xFF, 0x25)   # jmp [rip + slot]
		g.a.asmDisp32Data(slot)
		g.a.lastLabelEnd = g.a.code.len   # no peephole reaches across it
	liveSlots.push(LiveEntry(key = key.copy(), body = g.a.code.len, slot))

# the slots' first targets, each function's own body (the image is loaded at its base)
fn fillLiveSlots(mut g Gen):
	for s in liveSlots:
		g.a.patchAddress(s.slot, sectRva + s.body)

# The .live file beside a live build's executable: `data <rva>`, `slot <body> <slot> <key>` (RVAs),
# `fix <rva>` (a reference of the code into the state: x64's 32-bit displacement, AArch64's adrp,
# whose page the swap moves; the add after it keeps its offset), `source <file>` (the program's
# files, watched), and the layout a swap keeps: `var <name> <offset> <type>`, `type <name>
# <declaration>`, `fn <name> <header>`.
fn writeLiveFile(mut g Gen, exePath str):
	dataRva = dataRvaOf(g.a.code.len)
	lines = ["data {dataRva}"]
	for s in liveSlots:
		lines.push("slot {sectRva + s.body} {dataRva + s.slot} {s.key}")
	for i, kind in g.a.fixKind:
		if (kind == fxData or kind == fxA64Page) and g.a.fixTarget[i] < liveStateEnd:
			lines.push("fix {sectRva + g.a.fixAt[i]}")
	sources str[] = []
	for d in g.c.decls:
		file = nodes[d].file()
		if nodes[d].mod() != "rt" and file != "" and not file.startsWith("<") and
			file not in sources:
			sources.push(file.copy())
	lines.extend(sources.map("source {it}"))
	lines.extend(g.liveLayout())
	fs.writeFile("{exePath}.live", "{lines.join("\n")}\n") ??
		exit(1, "zap: cannot write {exePath}.live: {error}")

# what a swap must find the same in the running build: the module variables' places and types,
# the types' declarations and the functions' headers
fn liveLayout(mut g Gen):
	out = g.stateLayout()
	for d in g.c.decls:
		k = nodes[d].kind
		name = nodes[d].text.copy()
		if g.hasStorage(d):
			continue
		elif nodes[d].mod() == "rt" or nodes[d].file().startsWith("<") or name == "main":
			continue   # the runtime's and what the compiler wrote follow from the rest
		elif k == nStructDecl or k == nEnumDecl:
			out.push("type {name} {g.declText(d)}")
		elif k == nFnDecl:
			out.push("fn {name} {codeOf(sourceLineOf(nodes[d].file(), nodes[d].line).trimmed())}")
	out

# a declaration's lines, comments left out, on one line
fn declText(g Gen, d NodeId):
	last = lastLine(g.c.nodes, d)
	(nodes[d].line..=last)
		.map(codeOf(sourceLineOf(nodes[d].file(), it).trimmed()).trimmed().copy())
		.join(" ")

# the last line a node or what it holds stands on
fn lastLine(ns Node[], e NodeId) i64:
	last = ns[e].line
	for k in ns[e].kids:
		last = last.max(lastLine(ns, k))
	for k in ns[e].sub:
		last = last.max(lastLine(ns, k))
	last

# ---------- the live run ----------

# a build of the live run: its executable and .live file, copied where the run keeps them
type LiveRunBuild:
	exe str
	info str[]   # the .live file's lines

# zap run --live file [args...]: the program built and started; each time one of its files
# changes it is built again, then swapped in, or restarted when its layout changed, saying why
pub fn liveRun(file str, programArgs str[]):
	dir = "{buildsDir()}live.runs"   # (build/live is live.zap's executable on Linux)
	_ = fs.createDir(dir)
	for name in fs.list(dir) ?? []:
		_ = fs.deleteFile("{dir}/{name}")   # an earlier run's (one still running stays)
	request = "{dir}/{fs.stem(file)}.request"
	env[liveVariable().name] = request
	built = liveBuildOf(file, dir, 0) ?? exit(1)
	texts = readSources(built.sources()) ?? exit(1, "zap: cannot read the program's files")
	program = Process.start(built.commandLine(programArgs))
	generation = 0
	loop:
		if program.isDone:
			exit(i32(program.wait()))
		sleepMs(200)
		sources = built.sources()
		now = readSources(sources) ?? continue   # one being saved is read at the next look
		if now == texts: continue
		changed = liveChangedFunctions(texts, now)
		texts = now
		generation += 1
		next = liveBuildOf(file, dir, generation) ?? continue
		why = liveRestartWhy(built.info, next.info)
		built = next
		reason = why.copy()
		if reason == "":
			if not placeFile(request, built.exe): exit(1, "zap: cannot write {request}")
			answer = liveAnswer(request, built.exe, program)
			if answer == "": continue   # the program ended: the loop ends with it
			if answer == "swapped":
				eprint("zap: swapped {"the build" if changed.isEmpty else changed.join(", ")}")
				continue
			reason = "the running program could not load the new build"
		eprint("zap: restarting: {reason}")
		program.killTree()
		program.wait()
		program = Process.start(built.commandLine(programArgs))

# file built with --live, copied as build/live.runs/<name>-<generation> (an executable) with its
# .live file; none when it does not build (its errors printed)
fn liveBuildOf(file str, dir str, generation i64) LiveRunBuild?:
	code = Process.run(
		shellLine(
			withVariable(
				liveBuildVariable().name,
				"1",
				"{quoteArg(exePath())} build {quoteArg(file)} > {nullDevice()}"
			)
		)
	)
	if code != 0:
		if generation > 0:
			eprint("zap: the build failed; the program runs on as it was")
		return none
	stem = fs.stem(file)
	exe = "{dir}/{stem}-{generation}{exeExtension()}"
	for ext in [".live", ""]:
		bytes = fs.readFile("{exeFileOf(stem)}{ext}") ?? return none
		if not placeFile("{exe}{ext}", bytes): return none
	if not fs.canRun(exe): return none
	info = (fs.readFile("{exe}.live") ?? "").replace("\r", "").lines().map(.copy())
	LiveRunBuild(exe, info)

# the texts of the files; none when one cannot be read now (an editor's save replacing it)
fn readSources(files str[]) str[]?:
	texts = []
	for f in files:
		texts.push(fs.readFile(f) ?? return none)
	texts

fn sources(b LiveRunBuild):
	b.info.filter(.startsWith("source ")).map(it[7..].copy())

fn commandLine(b LiveRunBuild, programArgs str[]):
	line = quoteArg(hostPath(b.exe))
	for a in programArgs:
		line = "{line} {quoteArg(a)}"
	line

# why the next build cannot be swapped into the running one: the first part of the layout that
# differs; "" when none does
fn liveRestartWhy(running str[], next str[]):
	old = running.filter(isLayoutLine)
	new = next.filter(isLayoutLine)
	for line in new:
		if line in old: continue
		parts = line.split(" ")
		head = "{parts[0]} {parts[1]} "
		match parts[0]:
			"var":
				if old.any(.startsWith(head)):
					return "the module variable {parts[1]} changed its type"
				return "the module variable {parts[1]} is new"
			"type":
				if old.any(.startsWith(head)): return "the type {parts[1]} changed its layout"
			_:
				if old.any(.startsWith(head)):
					return "the function {parts[1]} changed its parameters or result"
	for line in old:
		parts = line.split(" ")
		if parts[0] == "var" and not new.any(.startsWith("var {parts[1]} ")):
			return "the module variable {parts[1]} went"
	""

fn isLayoutLine(line str):
	line.startsWith("var ") or line.startsWith("type ") or line.startsWith("fn ")

# the text at path whole: written beside it, then moved over it (the program reads the request
# and the builds, never part of one); the move waits while the system holds the path, as the
# program does reading the request
fn placeFile(path str, text str):
	part = "{path}.{processId()}.part"   # (one a zap: several may write the path)
	fs.writeFile(part, text) ?? return false
	loop:
		if fs.moveFile(part, path) is error:
			if error != .Denied: return false
			sleepMs(5)
			continue
		return true

# what the running program answered for the build: `swapped`, `failed`, or "" when the program
# ended without answering (it answers as soon as it runs, however long that takes)
fn liveAnswer(request str, exe str, program Process):
	loop:
		ended = program.isDone   # (before the read: an answer given before it ended is there)
		said = fs.readFile("{request}.done") ?? ""
		if said.endsWith(" {exe}"): return said[..said.indexOf(" ") ?? 0].copy()
		if ended: return ""
		sleepMs(20)

# the functions whose text changed between the files' texts before and now, by name
fn liveChangedFunctions(before str[], now str[]):
	names str[] = []
	for i in 0..now.len:
		if i >= before.len or before[i] == now[i]: continue
		was = declTexts(before[i], [symFunction, symMethod])
		texts = declTexts(now[i], [symFunction, symMethod])
		for name in texts.keys():
			if was.get(name) == texts.get(name) or name in names: continue
			names.push(name.copy())
	names

# the text of each declaration of those kinds (lsp.zap's sym kinds) in a source, by name
fn declTexts(text str, kinds i64[]):
	lines = text.replace("\r", "").lines()
	out {str: str} = {}
	for d in scanDecls(text):
		if d.kind in kinds:
			out[d.name.copy()] = lines[d.line..(d.endLine + 1).min(len)].join("\n")
	out
