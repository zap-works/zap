# The forms of the program's own functions (those past the kept stages, its entry's module) kept as
# the stages' are (keptIr.zap), in build/cache/ir/ beside the program's IR cache, each under a key
# of its own: the stages' key; the function's own nodes, places included, and those of each
# function whose body its lowering read (inlined, looked into) or that it calls by name, each tree
# with what it reads of the program's declarations (keptEntryKeys.zap); and what it asked of other
# functions that a body read further decides (what a call reads of a parameter, whether a given
# function is only called), asked again when the form is taken. Its nodes are named by their place
# in its own tree, its types past the stages' by their parts or their declaration's name. An edit
# of one body makes again the forms of that function and of those that read it or its declaration.

import fs

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

keptEntryMagic = "ZKEF"

# a node's ref -1 - (k << 32 | at) with k from here (keptNodeRef): the at-th node of the tree of
# the (k - keptTreeBase)-th of KeptForm.trees
keptTreeBase = 1 << 20

# a keptType ask's first part when the type is a list or an optional made for one node where it
# was checked (never found by its parts): found again as that node's type
keptFreshType = -1

type KeptEntry:
	path str = ""
	global i64 = 0   # the key every form's begins with; 0: none kept nor taken
	bytes u8[] = []
	waiting {str: i64} = {}   # the forms kept, where each one's record is in bytes
	sizes {str: i64} = {}   #   and its length
	fns {str: NodeId} = {}   # the program's own functions a form may be kept of, by key
	names {NodeId: str} = {}
	types {str: i64} = {}   # its type declarations by name (-1: two of one name)
	digests {NodeId: i64} = {}   # each one's tree (entryDigest)
	planning bool = false   # the plan of one being made: its types named by name (keptTypes.zap)
	own {i64: i64} = {}   #   and its nodes by their place in its tree
	taking i64[,] = []   # the trees of the form being taken (entryTrees)
	checked {str: u8[]} = {}   # the functions nothing called lowered and checked without an error,
	# by key: their keys and what those name (pushChecked)
	changed bool = false
	taken i64 = 0
	made i64 = 0

# while a function of the program's own being kept is lowered: the bodies the lowering read, and
# what it asked of a function that reads further than its body ("r fnd param", "w fnd i")
mut bodiesNoting = false
mut bodiesNoted NodeId[] = []
mut askedNoting = false
mut askedNoted str[] = []
mut treesNamed str[] = []   # the functions whose trees' nodes its form names (keptTreeBase)

fn noteBodyRead(fnd NodeId):
	if bodiesNoting: bodiesNoted.push(fnd)

fn noteAsked(kind str, fnd NodeId, what str):
	if askedNoting: askedNoted.push("{kind}\t{fnd}\t{what}")

# the program's own functions and types named, the key of its forms found and their file read
fn openKeptEntry(mut g Gen):
	if g.keptIr.key == 0 or irCache.entry == "" or loadableBuild: return
	e = KeptEntry(path = "{cachesDir}/ir/{testSlug(fullPath(irCache.entry))}{targetTag()}.forms")
	for d in g.c.decls:
		if i64(d) < g.keptIr.nodes or nodes[d].mod(kidIds) == "derive": continue
		k = nodes[d].kind
		if k == nFnDecl:
			if nodes[d].names(kidIds).isEmpty: e.noteOwnFn(nodes[d].text, d)
		elif k == nImplDecl:
			if not nodes[d].names2(kidIds).isEmpty: continue
			sd = g.c.findTypeDecl(nodes[d].text, nameOf(nodes, d)) ?? continue
			for m in nodes[d].kids(kidIds):
				e.noteOwnFn("{nodes[sd].text}_{nodes[m].text}", m)
		elif k != nConstDecl:
			e.types[nodes[d].text.copy()] = -1 if nodes[d].text in e.types else i64(d)
	g.keptIr.entry = move e
	said = "{g.keptIr.key} {buildTarget} {appBuild} {loadableBuild}"
	g.keptIr.entry.global = said.hash() & hashMask | 1
	values = g.entryNameValues()
	closures {i64: i64[]} = {}
	for d in g.keptIr.entry.names.keys():
		tree = mixIn(g.nodeDigest(d, true, i64(d)), nodes[d].file(kidIds).hash())
		g.keptIr.entry.digests[d] = mixIn(tree, g.treeReads(d, values, closures))
	g.readKeptEntry()

fn noteOwnFn(mut e KeptEntry, key str, d NodeId):
	e.fns[key.copy()] = d
	e.names[d] = key.copy()

fn readKeptEntry(mut g Gen):
	d = fs.readBytes(g.keptIr.entry.path) ?? return
	parts = d.unpack(keptEntryMagic, keptIrVersion) ?? return
	if not d.keptFor(parts, g.keptIr.entry.global): return
	r = Reader(d, at = parts.bodyAt)
	loop r.count():
		key = r.readText()
		n = r.count()
		g.keptIr.entry.waiting[key.copy()] = r.at
		g.keptIr.entry.sizes[key] = n
		r.at += n
	loop r.count():
		key = r.readText()
		g.keptIr.entry.checked[key] = r.bytes(r.count())
	if r.short or r.at != parts.end:
		g.keptIr.entry.waiting = {}
		g.keptIr.entry.checked = {}
		return
	g.keptIr.entry.bytes = move d

# a hash of e's tree: what each node says (its kind, text, flags and names), with its place when
# places; a function's body only with places (the declarations' hash leaves them out), and the
# result a function's declaration was found to give
fn nodeDigest(g Gen, e NodeId, places bool, root i64) i64:
	n = nodes[e]
	id = 0 if n.kind == nLambda else n.ival   # (a lambda's: the check's count of them)
	h = mixIn(mixIn(mixIn(i64(n.kind) + 1, n.flags), id), nameHash(n.text, root))
	if places: h = mixIn(mixIn(h, n.line), n.col)
	h = mixIn(h, nameHash(n.text2(kidIds), root))   # (a part with nothing in it or none: alike)
	for s in n.names(kidIds):
		h = mixIn(h, nameHash(s, root))
	for s in n.names2(kidIds):
		h = mixIn(h, nameHash(s, root))
	for k in n.kids(kidIds):
		h = mixIn(h, g.nodeDigest(k, places, root))
	for t in n.types(kidIds):
		h = mixIn(h, g.nodeDigest(t, places, root))
		if n.kind == nFnDecl and nodes[t].ty is ty: h = mixIn(h, typeStr(tys, ty).hash())
	for i, s in n.sub(kidIds):
		if places or n.kind != nFnDecl or i > 0: h = mixIn(h, g.nodeDigest(s, places, root))
	h

# the hash of a name, one the parser or the check made of a node's number (`$it1234`,
# `$elem1234`) with the number counted from root (which moves when a file before it grows)
fn nameHash(s str, root i64):
	if not s.startsWith("$"): return s.hash()
	at = s.len
	while at > 1 and s[at - 1] >= '0' and s[at - 1] <= '9':
		at -= 1
	n = i64.parse(s[at..]) ?? return s.hash()
	"{s[..at]}{n - root}".hash() if n >= root else s.hash()

# the nodes of fnd's tree in the order nodeDigest walks them
fn ownTree(g Gen, fnd NodeId):
	out = []
	g.pushTree(fnd, out)
	out

fn pushTree(g Gen, e NodeId, mut out i64[]):
	out.push(i64(e))
	for k in nodes[e].kids(kidIds):
		g.pushTree(k, out)
	for t in nodes[e].types(kidIds):
		g.pushTree(t, out)
	for s in nodes[e].sub(kidIds):
		g.pushTree(s, out)

# fnd's tree with its places and its file and what it reads of the program's declarations
# (keptEntryKeys.zap), hashed before any lowering (which writes what it decided into the nodes:
# irNodeMarks.zap)
fn entryDigest(g Gen, fnd NodeId):
	g.keptIr.entry.digests.get(fnd) ?? -1

# the key of fnd's form when its lowering read the functions deps (by key): -1 when one is gone
fn entryKeyOf(mut g Gen, fnd NodeId, deps str[]):
	h = mixIn(g.keptIr.entry.global, g.entryDigest(fnd))
	for name in deps:
		d = g.keptIr.entry.fns.get(name) ?? return -1
		h = mixIn(mixIn(h, name.hash()), g.entryDigest(d))
	h

# n, a node past the stages' a form of the program's own names, in the tree of a function its
# lowering read or the declaration of one: none when in neither
fn entryNodeRef(g Gen, n i64) i64?:
	if g.keptIr.entry.names.get(NodeId(n)) is name: return treeRef(name, 0)
	seen {NodeId: bool} = {}
	for d in bodiesNoted:
		if d in seen: continue
		seen[d] = true
		name = g.keptIr.entry.names.get(d) ?? continue
		if g.ownTree(d).findIndex(it == n) is at: return treeRef(name, at)
	none

fn treeRef(name str, at i64):
	k = treesNamed.findIndex(it == name) ?? treesNamed.len
	if k == treesNamed.len: treesNamed.push(name.copy())
	-1 - ((keptTreeBase + k) << 32 | at)

# the trees a form of fnd names nodes of: fnd's, then those of the functions named
fn entryTrees(g Gen, fnd NodeId, names str[]):
	trees = [g.ownTree(fnd)]
	for name in names:
		trees.push(g.ownTree(g.keptIr.entry.fns.get(name) ?? fnd))   # (a name gone fails its key)
	trees

# t, a list or an optional made for one node of a tree the form names, as a keptType ask of it
fn freshTypeRef(g Gen, t TypeId, mut asks KeptAsk[]) i64?:
	n = try g.freshTypeNode(t)
	named = try g.keptNodeRef(n, NodeId(0), [])
	asks.push(KeptAsk(keptType, types = [keptFreshType, named], off = i64(t)))
	-1 - (asks.len - 1)

fn freshTypeNode(g Gen, t TypeId) i64?:
	for n, _ in g.keptIr.entry.own:
		if nodes[NodeId(n)].ty is ty and ty == t: return n
	seen {NodeId: bool} = {}
	for d in bodiesNoted:
		if d in seen or i64(d) < g.keptIr.nodes: continue
		seen[d] = true
		for n in g.ownTree(d):
			if nodes[NodeId(n)].ty is ty and ty == t: return n
	none

# whether fnd, under key, is a function of the program's own whose form may be kept or taken
fn entryKeepable(g Gen, fnd NodeId, key str):
	if g.keptIr.entry.global == 0 or g.isEntry(key) or not g.irGivenNow.isEmpty or
		not g.c.subst.names.isEmpty:
		return false
	if g.keptIr.entry.fns.get(key) is d: return d == fnd
	false

# the form kept for fnd under key, when its key is this build's and what it asked is answered
# alike
fn entryFormOf(mut g Gen, fnd NodeId, key str) KeptForm?:
	at = try g.keptIr.entry.waiting.get(key)
	form = keptFormAt(g.keptIr.entry.bytes, at, false)
	if not g.entryHolds(fnd, form.entryKey, form.deps, form.asked): return none
	form.layer = -1
	if form.code == none: g.keptIr.forms[key.copy()] = form.copy()   # (else read when its code
	# cannot be placed: readKeptForm)
	g.keptIr.entry.taken += 1
	form

# whether a key made of fnd and what it read (deps, asked) is this build's: the trees' hashes alike
# and what was asked answered alike
fn entryHolds(mut g Gen, fnd NodeId, key i64, deps str[], asked str[]):
	if key != g.entryKeyOf(fnd, deps): return false
	for line in asked:
		parts = line.split("\t")
		d = g.keptIr.entry.fns.get(parts[1]) ?? return false
		if g.askedOf(parts[0], d, parts[2]) != parts[3]: return false
	true

# what a lowering asked of d: what it reads of a parameter (r), whether its parameter i is only
# called (w)
fn askedOf(mut g Gen, kind str, d NodeId, what str):
	if kind == "r": return g.c.readsThrough(d, what).join(" ")
	"{g.irCallsOnly(d, i64.parse(what) ?? 0)}"

# the lowering of fnd, a function of the program's own, begins to be noted for its form
fn entryNotingBegin(mut g Gen, fnd NodeId):
	g.keptIr.entry.own = {}
	for i, n in g.ownTree(fnd):
		g.keptIr.entry.own[n] = i
	bodiesNoted = []
	bodiesNoting = true
	askedNoted = []
	askedNoting = true
	treesNamed = []

fn entryNotingEnd():
	bodiesNoting = false
	askedNoting = false

# plan, made of the lowering f of fnd, completed with what its key names; none when the lowering
# read a body or called a function past the stages that is not one of the program's own
fn entryPlanOf(mut g Gen, move plan KeptPlan, fnd NodeId, f IrFn) KeptPlan?:
	reads = try g.formReads(fnd, f)
	plan.trees = move treesNamed
	treesNamed = []
	plan.deps = reads.deps
	plan.asked = reads.asked
	plan.entryKey = g.entryKeyOf(fnd, plan.deps)
	plan.layer = -1
	g.keptIr.entry.made += 1
	plan

# what the lowering f of fnd read that its key names: the functions whose trees it read or names
# (by key, sorted) and what it asked of other functions (askedOf's lines); none when it read a
# body or called a function past the stages that is not one of the program's own
type FormReads:
	deps str[]
	asked str[]

fn formReads(mut g Gen, fnd NodeId, f IrFn) FormReads?:
	deps {str: bool} = {}
	read = move bodiesNoted
	bodiesNoted = []
	for d in read:
		if i64(d) < g.keptIr.nodes or d == fnd or g.ofKeptGeneric(d): continue   # (a copy of
		# the stages' generic: its body theirs, its types the form's)
		name = try g.keptIr.entry.names.get(d)
		deps[name.copy()] = true
	for b in f.blocks:
		for inst in b.insts:
			if (inst.op == irCall or inst.op == irFnAddr) and inst.key() != "" and
				not stablyDerived(inst.key()):
				if g.keptIr.entry.fns.get(inst.key()) is d:
					if d != fnd: deps[inst.key().copy()] = true
				elif g.c.findFunc(inst.key()) is d and i64(d) >= g.keptIr.nodes:
					return none
	asked = []
	lines = move askedNoted
	askedNoted = []
	for line in lines:
		parts = line.split("\t")
		d = NodeId(try i64.parse(parts[1]))
		if i64(d) < g.keptIr.nodes: continue
		name = try g.keptIr.entry.names.get(d)
		asked.push("{parts[0]}\t{name}\t{parts[2]}\t{g.askedOf(parts[0], d, parts[2])}")
	for name in treesNamed:
		deps[name.copy()] = true
	FormReads(deps = deps.keys().sorted(), asked)

# whether fnd under key, a function of the program's own nothing calls, was lowered and checked
# without an error by a build that read the same
fn entryCheckedBefore(mut g Gen, fnd NodeId, key str):
	record = g.keptIr.entry.checked.get(key) ?? return false
	r = Reader(record)
	held = r.varint()
	return g.entryHolds(fnd, held, r.readTexts(), r.readTexts())

# fnd under key, a function of the program's own nothing calls, lowered (f) and checked: noted
# with what it read when without an error
fn noteEntryChecked(mut g Gen, fnd NodeId, key str, f IrFn, clean bool):
	entryNotingEnd()
	reads = (g.formReads(fnd, f) if clean else none) ?? return
	treesNamed = []
	record = []
	record.pushVarint(g.entryKeyOf(fnd, reads.deps))
	record.pushTexts(reads.deps)
	record.pushTexts(reads.asked)
	g.keptIr.entry.checked[key.copy()] = move record
	g.keptIr.entry.changed = true

# the forms of the program's own functions written back when one was made: those this build made
# or read whole, and the others of the file, as they are, of functions that are still the
# program's
fn saveKeptEntry(g Gen):
	if not g.keptIr.entry.changed: return
	body u8[] = []
	count = 0
	for key, form in g.keptIr.forms:
		if form.layer >= 0: continue
		body.pushText(key)
		record u8[] = []
		record.pushKeptForm(form)
		body.pushVarint(record.len)
		body.extend(record)
		count += 1
	for key, at in g.keptIr.entry.waiting:
		if key in g.keptIr.forms or key not in g.keptIr.entry.fns: continue
		n = g.keptIr.entry.sizes.get(key) ?? continue
		body.pushText(key)
		body.pushVarint(n)
		body.extend(g.keptIr.entry.bytes[at..at + n])
		count += 1
	counted = []
	counted.pushVarint(count)
	counted.extend(body)
	body = move counted
	checked = g.keptIr.entry.checked.keys().filter(it in g.keptIr.entry.fns)
	body.pushVarint(checked.len)
	for key in checked:
		body.pushText(key)
		record = g.keptIr.entry.checked.get(key) ?? []
		body.pushVarint(record.len)
		body.extend(record)
	head = []
	head.pushU64le(compilerKey())
	head.pushU64le(g.keptIr.entry.global)
	_ = fs.createDir("{cachesDir}/ir")
	_ = placeFile(
		g.keptIr.entry.path,
		str(PackedParts.pack(keptEntryMagic, keptIrVersion, head, body))
	)
