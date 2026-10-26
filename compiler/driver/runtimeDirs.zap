# Which of the runtime's dirs a build loads (spec 8): runtime/core/ always, what any program uses
# without naming it; each other dir of runtime/ (threads/, grid/, bytes/...) only when the program,
# or a dir it loads, names one of the dir's declarations or holds a form the compiler lowers to
# the dir's functions (loweredForms), to a fixpoint; test/ too in a build of tests (zap test's,
# the lint's check). What each dir declares and reads is an index
# made once for this compiler and these runtime sources, kept in build/cache/ under their stamp
# (stamps.zap), so a build reads the dirs it loads and no other.

import fs

runtimeCore = "core"
testRunnerDir = "test"

# the forms the compiler lowers to the functions of a dir besides core: the kind of the node that
# asks for it, its text (an operator's name, a call's function; "" any), the dir
# long: a table
loweredForms = [
	(nField, "parallel", "threads"),   # xs.parallel(): parallelDo, parallelMap, the parallel sorts
	(nCall, "random", "random"),   # random(lo..hi): randomIn, randomFloatIn
	(nCall, "arg", "cli"),   # arg(i, default): argParsed, argTextOr
	(nField, "fromBytesAt", "bytes"),   # T.fromBytesAt(b, at): its derived reading with a Reader
	(nBinary, "@", "vectors"),   # a @ b of fixed arrays: arrayTimesArray, arrayTimesVector
	(nField, "fromCsv", "csv"),   # Row[].fromCsv(text): its derived reading with csvRecord
	(nField, "toCsv", "csv"),   # rows.toCsv(): its derived writing with csvOutField
	(nField, "toJson", "jsonIndent")   # v.toJson(2): jsonIndented
]

# a dir of the runtime: its top-level declarations' names, the names its sources read, the
# dirs their lowered forms need and the dirs it is checked after (those it reads or needs);
# alone when core reaches it with no program (the kept index's reading leaves its lists out:
# what a dir core does not reach declares is no name core's dirs read)
type RuntimeDir:
	name str
	declares str[]
	reads str[]
	needs str[]
	after str[] = []
	alone bool = false

fn runtimeIndexWord():
	TraceWord(
		"rtdirs",
		"the runtime's dirs a build loads, and for each the name or form that reached it"
	)

# the top dir of a runtime file's path below the runtime's dir ("threads" of "threads/linux/x.zap")
fn runtimeDirOf(path str):
	path.split("/")[0].copy()

# what the nodes under the roots read into names (a field's name also as the runtime's functions of
# that method, listPush for .push) and the dirs their lowered forms need into needs
fn readsUnder(
	nodes Node[],
	kidIds NodeId[],
	roots NodeId[],
	mut names {str: bool},
	mut needs str[]
):
	for r in roots:
		readsAt(nodes, kidIds, r, names, needs)

fn readsAt(nodes Node[], kidIds NodeId[], e NodeId, mut names {str: bool}, mut needs str[]):
	k = nodes[e].kind
	if k in [nIdent, nField, nStructLit, nTyName, nPattern, nCall] and nodes[e].text != "":
		names[nodes[e].text.copy()] = true
		if k == nField:
			for m in rtMethodNames(nodes[e].text):
				names[m] = true
	form = nodes[e].text.copy()
	if k == nBinary:
		form = binName(nodes[e].ival)
	elif k == nCall and not nodes[e].kids(kidIds).isEmpty and
		nodes[nodes[e].kids(kidIds)[0]].kind == nIdent:
		form = nodes[nodes[e].kids(kidIds)[0]].text.copy()
	for (kind, text, dir) in loweredForms:
		if k == kind and (text == "" or form == text) and dir not in needs:
			needs.push(dir.copy())
	for kid in nodes[e].kids(kidIds):
		readsAt(nodes, kidIds, kid, names, needs)
	for s in nodes[e].sub():
		readsAt(nodes, kidIds, s, names, needs)
	for t in nodes[e].types():
		readsAt(nodes, kidIds, t, names, needs)

# the runtime's dirs, their files below rtDir (every one, a system's too) parsed apart from any
# program; none when one does not parse
fn indexedRuntime(rtDir str, files str[]) RuntimeDir[]?:
	out RuntimeDir[] = []
	for path in files:
		name = runtimeDirOf(path)
		if not out.any(.name == name):
			out.push(RuntimeDir(name.copy(), [], [], []))
		nodes = []
		kidIds = []
		decls = try parseSource(readSource("{rtDir}{path}"), path, nodes, kidIds)
		reads {str: bool} = {}
		at = out.findIndex(.name == name) ?? 0
		for d in decls:
			if nodes[d].text != "" and nodes[d].kind != nTestDecl and nodes[d].kind != nImportDecl:
				out[at].declares.push(nodes[d].text.copy())
		readsUnder(nodes, kidIds, decls, reads, out[at].needs)
		out[at].reads.extend(reads.keys().map(.copy()))
	for i in 0..out.len:
		out[i].after = out.dirsBefore(out[i])
	out

# the other dirs d reads a declaration of or needs, in the index's order
fn dirsBefore(index RuntimeDir[], d RuntimeDir):
	reads {str: bool} = {}
	for n in d.reads:
		reads[n.copy()] = true
	index
		.filter(.name != d.name and (.name in d.needs or .declares.any(reads.get(it) != none)))
		.map(.name.copy())

# the index as kept: a dir a line, its name, then its declarations, reads, needs and the dirs it
# is checked after, each a list of words after a tab; then the dirs core reaches alone
fn indexText(dirs RuntimeDir[]):
	lines = dirs.map(
		"{.name}\t{.declares.join(" ")}\t{.reads.join(" ")}\t{.needs.join(" ")}\t{.after.join(" ")}"
	)
	names {str: bool} = {}
	noNeeds = []
	alone, _ = dirs.reachedWhy(names, noNeeds)
	lines.push("{aloneTag}{alone.join(" ")}")
	lines.join("\n")

aloneTag = "alone\t"

fn indexFromText(text str):
	lines = text.lines()
	last = lines[len - 1] if not lines.isEmpty else ""
	alone = spacedWords(last[aloneTag.len..]) if last.startsWith(aloneTag) else []
	out = []
	for line in lines:
		f = line.split("\t")
		if f.len != 5: continue
		if f[0] in alone:
			out.push(RuntimeDir(f[0].copy(), [], [], [], spacedWords(f[4]), alone = true))
			continue
		out.push(
			RuntimeDir(
				f[0].copy(),
				spacedWords(f[1]),
				spacedWords(f[2]),
				spacedWords(f[3]),
				spacedWords(f[4])
			)
		)
	out

fn spacedWords(s str):
	s.split(" ").filter(it != "").map(.copy())

# the index of the runtime's dirs: the kept one while this compiler and the runtime's sources are
# those it was made from, at rtDir (the user's cache is shared by every checkout), else made again
# and kept; none when a source does not parse (said)
fn runtimeIndex(rtDir str) RuntimeDir[]?:
	kept = "{cachesDir}/runtime.index"
	if fs.readFile(kept) is text and keptWhileSame(text) is index:
		files = stampedFiles(text)   # (its stamp names every source)
		if files.all(.startsWith(rtDir)):
			listedRuntime(rtDir, files)
			return indexFromText(index)
	files = runtimeSources(rtDir)
	paths = files.map("{rtDir}{it}")
	dirs = try indexedRuntime(rtDir, files)
	_ = fs.createDir(cachesDir)
	_ = fs.writeFile(kept, stamped(paths, indexText(dirs)))
	dirs

# the dirs a program loads: core, then each dir one of whose declarations the names read or
# whose forms the needs ask for, its own reads and needs added, until no dir is left that they
# reach; in the index's order
fn reachedDirs(index RuntimeDir[], mut names {str: bool}, mut needs str[]):
	loaded, why = index.reachedWhy(names, needs)
	order = checkOrder(index, loaded)
	if runtimeIndexWord().on():
		for name in order:
			eprint("rtdirs: {name} by {why.get(name) ?? ""}")
	order

# the dirs reachedDirs loads, in the order reached, each with what reached it
fn reachedWhy(index RuntimeDir[], mut names {str: bool}, mut needs str[]):
	loaded str[] = []
	why {str: str} = {}
	grown = true
	while grown:
		grown = false
		for d in index:
			if d.name in loaded: continue
			reason = "always" if d.name == runtimeCore else "core" if d.alone
				else "a form" if d.name in needs else ""
			if reason == "":
				for n in d.declares:
					if names.get(n) != none:
						reason = n.copy()
						break
			if reason == "": continue
			loaded.push(d.name.copy())
			why[d.name.copy()] = reason
			for n in d.reads:
				names[n.copy()] = true
			for n in d.needs:
				if n not in needs: needs.push(n.copy())
			grown = true
	(loaded, why)

# the loaded dirs in the order they are checked, each a stage of its own (spec 14.2): core, then
# each after the dirs it reads or needs, else in the index's order
fn checkOrder(index RuntimeDir[], loaded str[]):
	order = [runtimeCore.copy()] if runtimeCore in loaded else []
	open = []
	for d in index:
		index.placeAfter(d.name, loaded, order, open)
	order

fn placeAfter(index RuntimeDir[], name str, loaded str[], mut order str[], mut open str[]):
	if name in order or name in open or name not in loaded: return
	open.push(name.copy())
	d = index.find(.name == name) ?? return
	for before in d.after:
		index.placeAfter(before, loaded, order, open)
	open.pop()
	order.push(name.copy())
