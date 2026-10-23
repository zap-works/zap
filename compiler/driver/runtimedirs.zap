# Which of the runtime's dirs a build loads (spec 8): runtime/core/ always, what any program uses
# without naming it; each other dir of runtime/ (threads/, grid/, bytes/...) only when the program,
# or a dir it loads, names one of the dir's declarations or holds a form the compiler lowers to
# the dir's functions (loweredForms), to a fixpoint; test/ too in a build of tests (zap test's,
# the lint's check), live/ in a live one. What each dir declares and reads is an index
# made once for this compiler and these runtime sources, kept in build/cache/ under their stamp
# (stamps.zap), so a build reads the dirs it loads and no other.

import fs

runtimeCore = "core"
testRunnerDir = "test"
liveDir = "live"   # a build of zap run --live: liveStart, its first call

# the forms the compiler lowers to the functions of a dir besides core: the kind of the node that
# asks for it, its text (an operator's name; "" any), the dir
# long: a table
loweredForms = [
	(nField, "parallel", "threads"),   # xs.parallel(): parallelDo, parallelMap, the parallel sorts
	(nIdent, "random", "random"),   # random(lo..hi): randomIn, randomFloatIn
	(nIdent, "arg", "cli"),   # arg(i, default): argParsed, argTextOr
	(nField, "fromBytesAt", "bytes"),   # T.fromBytesAt(b, at): its derived reading with a Reader
	(nBinary, "@", "vectors")   # a @ b of fixed arrays: arrayTimesArray, arrayTimesVector
]

# a dir of the runtime: its top-level declarations' names, the names its sources read and the
# dirs their lowered forms need
type RuntimeDir:
	name str
	declares str[]
	reads str[]
	needs str[]

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
fn readsUnder(nodes Node[], roots NodeId[], mut names {str: bool}, mut needs str[]):
	for r in roots:
		readsAt(nodes, r, names, needs)

fn readsAt(nodes Node[], e NodeId, mut names {str: bool}, mut needs str[]):
	k = nodes[e].kind
	if k in [nIdent, nField, nStructLit, nTyName, nPattern, nCall] and nodes[e].text != "":
		names[nodes[e].text.copy()] = true
		if k == nField:
			for m in rtMethodNames(nodes[e].text):
				names[m] = true
	form = binName(nodes[e].ival) if k == nBinary else nodes[e].text.copy()
	for (kind, text, dir) in loweredForms:
		if k == kind and (text == "" or form == text) and dir not in needs:
			needs.push(dir.copy())
	for kid in nodes[e].kids:
		readsAt(nodes, kid, names, needs)
	for s in nodes[e].sub:
		readsAt(nodes, s, names, needs)
	for t in nodes[e].types:
		readsAt(nodes, t, names, needs)

# the runtime's dirs, their files below rtDir (every one, a system's too) parsed apart from any
# program; none when one does not parse
fn indexedRuntime(rtDir str, files str[]) RuntimeDir[]?:
	out RuntimeDir[] = []
	for path in files:
		name = runtimeDirOf(path)
		if not out.any(.name == name):
			out.push(RuntimeDir(name.copy(), [], [], []))
		nodes = []
		decls = try parseSource(readSource("{rtDir}{path}"), path, nodes)
		reads {str: bool} = {}
		at = out.findIndex(.name == name) ?? 0
		for d in decls:
			if nodes[d].text != "" and nodes[d].kind != nTestDecl and nodes[d].kind != nImportDecl:
				out[at].declares.push(nodes[d].text.copy())
		readsUnder(nodes, decls, reads, out[at].needs)
		out[at].reads.extend(reads.keys().map(.copy()))
	out

# the index as kept: a dir a line, its name, then its declarations, reads and needs, each a
# list of words after a tab
fn indexText(dirs RuntimeDir[]):
	dirs.map("{it.name}\t{it.declares.join(" ")}\t{it.reads.join(" ")}\t{it.needs.join(" ")}")
		.join("\n")

fn indexFromText(text str) RuntimeDir[]:
	out RuntimeDir[] = []
	for line in text.lines():
		f = line.split("\t")
		if f.len != 4: continue
		out.push(RuntimeDir(f[0].copy(), spacedWords(f[1]), spacedWords(f[2]), spacedWords(f[3])))
	out

fn spacedWords(s str) str[]:
	s.split(" ").filter(it != "").map(.copy())

# the index of the runtime's dirs: the kept one while this compiler and the runtime's sources are
# those it was made from, else made again and kept; none when a source does not parse (said)
fn runtimeIndex(rtDir str) RuntimeDir[]?:
	files = runtimeSources(rtDir)
	paths = files.map("{rtDir}{it}")
	kept = "{cachesDir}/runtime.index"
	if fs.readFile(kept) is text and keptWhileSame(text) is index: return indexFromText(index)
	dirs = try indexedRuntime(rtDir, files)
	_ = fs.createDir(cachesDir)
	_ = fs.writeFile(kept, stamped(paths, indexText(dirs)))
	dirs

# the dirs a program loads: core, then each dir one of whose declarations the names read or
# whose forms the needs ask for, its own reads and needs added, until no dir is left that they
# reach; in the index's order
fn reachedDirs(index RuntimeDir[], mut names {str: bool}, mut needs str[]) str[]:
	loaded str[] = []
	why {str: str} = {}
	grown = true
	while grown:
		grown = false
		for d in index:
			if d.name in loaded: continue
			reason = "always" if d.name == runtimeCore else "a form" if d.name in needs else ""
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
	order = index.map(.name.copy()).filter(it in loaded)
	if runtimeIndexWord().on():
		for name in order:
			eprint("rtdirs: {name} by {why.get(name) ?? ""}")
	order
