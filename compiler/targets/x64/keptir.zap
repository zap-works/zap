# The functions of the kept stages kept lowered (spec 14.2): a function of the runtime or of std
# whose form names only the kept stages' types and nodes, and whose lowering made nothing the
# program shares but what it asked for by name (its strings, the drops and copies of types, the
# closures' stubs, the runtime's instances, the module variables it names), is kept as its passes
# made it, beside the stages in build/cache/, under the chain's key and what the program
# decides of those stages' functions (their effects, which of them are taken as values). The next
# build with the same takes the form instead of lowering it, asking for the same in the same
# order, so what the program shares grows as the lowering grew it and the executable is the same
# byte for byte.

import fs

keptIrMagic = "ZKIR"
keptIrVersion = 1

# the kept forms a build may take and those it adds
type KeptIr:
	name str = ""   # the last kept stage's
	key i64 = 0   # 0: none taken nor kept
	nodes i64 = 0   # the kept stages' nodes and types: a kept function is one of those nodes, and
	types i64 = 0   #   its form names no other
	forms {str: KeptForm} = {}
	changed bool = false

# what a lowering asked for by name, in order: a string (keptString, its offset then), a type's
# drop or copy, a closures' stub, a runtime's instance (its function's name, its types)
type KeptAsk:
	kind i64
	text str = ""
	types i64[] = []
	off i64 = 0
	made bool = false   # it made what it asked for: a label and a plan of its own, or a string

keptString = 0
keptDrop = 1
keptCopy = 2
keptStub = 3
keptInstance = 4

# a function's form as its passes made it, its numbers (irNumbersOf) by their places: the types
# and nodes as they are, each data offset a ref; what its lowering asked for and the module
# variables it names
type KeptForm:
	types i64[]
	refs i64[]   # each data number: -1 - k the offset the k-th ask gives (a string), else that offset (a fixed one)
	nodes i64[]
	asks KeptAsk[]
	globals str[]
	form u8[]

# what a function's record keeps until its passes write its form (IrMade.kept)
type KeptPlan:
	numbers i64[,]
	refs i64[]
	asks KeptAsk[]
	globals str[]

# the kept forms of this program's kept stages read, when the build may take them: the last
# stage of the runtime or std it checked or read, keyed with the facts the program decides of the
# stages' functions
fn openKeptIr(mut g Gen, stages CheckStage[]):
	g.keptIr = KeptIr()
	if not keepsStages() or noting or checksShared or lowersPatchedOnly or irTraced(): return
	keptAt = -1
	for i, s in stages:
		if s.key != 0 and s.done: keptAt = i
	if keptAt < 0: return
	stage = stages[keptAt]
	g.keptIr = KeptIr(
		name = stage.name.copy(),
		key = "{stage.key} {g.keptFacts(stage.nodes)}".hash(),
		nodes = stage.nodes,
		types = stage.types
	)
	d = fs.readBytes(g.keptIr.keptIrPath()) ?? return
	parts = d.unpack(keptIrMagic, keptIrVersion) ?? return
	if not d.keptFor(parts, g.keptIr.key): return
	r = Reader(d, at = parts.bodyAt)
	forms = r.readKeptForms()
	if not r.short and r.at == parts.end: g.keptIr.forms = forms

# the forms beside the last kept stage's file: those of the last chain and facts written
fn keptIrPath(k KeptIr):
	"{stagePath(k.name)}.ir"

# whether a word of ZAP_RUN asks to see what the lowering does: every function is lowered then
fn irTraced():
	irWord().on() or irDumpWord().on() or irLoweredWord().on() or irOwnWord().on() or
		irMaxWord().on() or irInlineWord().on() or irBlocksWord().on() or irDropsWord().on() or
		lowerSharedWord().on()

# a hash of what the program decides of the functions below node bound: which are taken as
# values (their calls keep the stack convention), what each changes (effects.zap) and does
# (purity.zap)
fn keptFacts(g Gen, bound i64):
	lines = []
	for name in g.fnValueNames.keys():
		if g.c.findFunc(name) is d and i64(d) < bound: lines.push("value {name}")
	for key, paths in g.c.effects:
		if (i64.parse(key[..key.indexOf(":") ?? 0]) ?? bound) < bound:
			lines.push("{key} {paths.join(" ")}")
	for d, bits in g.c.fnEffects:
		if i64(d) < bound: lines.push("does {d} {bits}")
	lines.sorted().join("\n").hash()

# the kept form of the function fnd under key made (taken instead of lowered), what its lowering
# asked for asked again and its module variables named; false when there is none
fn irKeptForm(mut g Gen, fnd NodeId, key str):
	if not g.keepable(fnd): return false
	kept = g.keptIr.forms.get(key) ?? return false
	offsets = []
	for ask in kept.asks:
		offsets.push(g.askedAgain(ask))
	for name in kept.globals:
		g.globalsNamed[name.copy()] = true
	data = kept.refs.map(offsets[-1 - it] if it < 0 else it)
	r = Reader(kept.form)
	f = r.irRead(irRenamingOf([kept.types.copy(), data, kept.nodes.copy()], true)) ?? return false
	g.irFileNow = g.c.nodes[fnd].file().copy()
	g.made.push(
		IrMade(key = key.copy(), node = fnd, ret = g.c.fnRetType(fnd), f = move f, passed = true)
	)
	g.irShip()
	true

# what the ask asks for asked for again: a string's offset, else 0
fn askedAgain(mut g Gen, ask KeptAsk):
	if ask.kind == keptString: return g.strLit(ask.text)
	if ask.kind == keptDrop or ask.kind == keptCopy:
		g.typeFnLabel(TypeId(ask.types[0]), ask.kind == keptDrop)
	elif ask.kind == keptStub:
		g.closureStubLabel(ask.text.copy())
	else:
		g.rtMangle(ask.text, ask.types.map(TypeId(it)))
	0

# whether fnd's form may be kept or taken: a function of the kept stages, not made for the
# functions a call gives it (irgiven.zap: those are the program's, named as the program names them)
fn keepable(g Gen, fnd NodeId):
	g.keptIr.key != 0 and i64(fnd) < g.keptIr.nodes and g.irGivenNow.isEmpty

# whether the lowering of fnd may be kept: a function of the kept stages none is kept for yet;
# what it asks for is noted while it is lowered
fn mayKeep(mut g Gen, fnd NodeId, key str):
	keeps = g.keepable(fnd) and key not in g.keptIr.forms
	g.asksNoted = []
	g.asksNoting = keeps
	g.asksSpoiled = false
	g.asksGrew = []
	typesPast = g.keptIr.types if keeps else -1
	typesMet = false
	keeps

# the runtime's instance fnd of sub recorded: while a function being kept is lowered, what
# making it grew of the shared state counted as its ask's, which the form taken makes again
fn askInstance(mut g Gen, fnd NodeId, sub Subst):
	if not g.asksNoting: return g.c.recordInstance(fnd, sub, fnd)
	before = [g.lowerSharedSizes(), g.lowerMemoSizes()]
	past = typesPast
	typesPast = -1
	mangle = g.c.recordInstance(fnd, sub, fnd)
	typesPast = past
	after = [g.lowerSharedSizes(), g.lowerMemoSizes()]
	if g.asksGrew.isEmpty: g.asksGrew = [zeros(before[0].len), zeros(before[1].len)]
	for row in 0..2:
		for i in 0..before[row].len:
			g.asksGrew[row][i] += after[row][i] - before[row][i]
	mangle

# a lowering's ask noted, while a function being kept is lowered
fn noteAsk(mut g Gen, move ask KeptAsk):
	if g.asksNoting: g.asksNoted.push(ask)

# the plan of keeping f, lowered with the program's shared state at sizes before: none when its
# lowering met a type past the kept stages', added to the shared state what its asks do not make
# again (types, nodes, instances, lambdas, data but strings), or its form names a type or a node
# past the kept stages' or data that is neither a string it asked for nor a module variable's
fn keptPlanOf(mut g Gen, f IrFn, before i64[,], clean bool) KeptPlan?:
	g.asksNoting = false
	typesPast = -1
	if not clean or typesMet or g.asksSpoiled: return none
	after = [g.lowerSharedSizes(), g.lowerMemoSizes()]
	grew = move g.asksGrew
	g.asksGrew = []
	if grew.isEmpty: grew = [zeros(before[0].len), zeros(before[1].len)]
	asks = move g.asksNoted
	g.asksNoted = []
	made = asks.count(.made and .kind != keptString and .kind != keptInstance)
	strings = asks.count(.made and .kind == keptString)
	for i in 0..before[0].len:
		grown = after[0][i] - before[0][i] - grew[0][i]
		allowed = made if i in [6, 8] else strings if i == 7 else 0   # drops planned, labels, strings
		if grown != allowed and i not in [9, 11, 13]: return none   # (globals named, call stores, data)
	for i in [4, 5, 6, 18]:   # type descriptors, loaded slots, function values, typeIndex
		if after[1][i] - before[1][i] != grew[1][i]: return none
	if asks.any(.types.any(it >= g.keptIr.types)): return none
	numbers = f.irNumbersOf()
	if numbers[0].any(it >= g.keptIr.types) or numbers[2].any(it >= g.keptIr.nodes): return none
	refs = []
	globals = []
	for off in numbers[1]:
		if asks.findIndex(.kind == keptString and .off == off) is k:
			refs.push(-1 - k)
		elif off >= bssBase and g.globalNamedAt(off) is name:
			refs.push(off)
			globals.push(name)
		elif off == g.globalsOff:
			refs.push(off)
		else:
			return none
	KeptPlan(numbers, refs, asks, globals)

# the module variable at a data offset
fn globalNamedAt(g Gen, off i64) str?:
	for name, at in g.globalOffs:
		if at == off: return name.copy()
	none

# the form the passes wrote for m kept, for the next build
fn keepMadeForm(mut g Gen, mut m IrMade):
	if m.keptForm.isEmpty: return
	plan = m.kept ?? return
	g.keptIr.forms[m.key.copy()] = KeptForm(
		types = plan.numbers[0].copy(),
		refs = plan.refs.copy(),
		nodes = plan.numbers[2].copy(),
		asks = plan.asks.copy(),
		globals = plan.globals.copy(),
		form = move m.keptForm
	)
	m.keptForm = []
	g.keptIr.changed = true

# the form of m as its passes made it, its numbers by their places, for keepMadeForm
fn writeKeptForm(mut m IrMade):
	plan = m.kept ?? return
	out = []
	if m.f.irWrite(out, irRenamingOf(plan.numbers, false)): m.keptForm = move out

# the kept forms written back with those another build wrote since, when this one added some
fn saveKeptIr(g Gen):
	if not g.keptIr.changed: return
	path = g.keptIr.keptIrPath()
	forms = g.keptIr.forms.copy()
	if fs.readBytes(path) is d and d.unpack(keptIrMagic, keptIrVersion) is parts and
		d.keptFor(parts, g.keptIr.key):
		r = Reader(d, at = parts.bodyAt)
		written = r.readKeptForms()
		for key, form in written:
			if key not in forms: forms[key.copy()] = form.copy()
	body = []
	body.pushVarint(forms.len)
	for key, form in forms:
		body.pushText(key)
		body.pushInts(form.types)
		body.pushInts(form.refs)
		body.pushInts(form.nodes)
		body.pushVarint(form.asks.len)
		for ask in form.asks:
			body.pushVarint(ask.kind)
			body.pushText(ask.text)
			body.pushInts(ask.types)
		body.pushTexts(form.globals)
		body.pushVarint(form.form.len)
		body.extend(form.form)
	head = []
	head.pushU64le(compilerKey())
	head.pushU64le(g.keptIr.key)
	_ = fs.createDir(cachesDir)
	placeFile(path, str(PackedParts.pack(keptIrMagic, keptIrVersion, head, body)))

fn readKeptForms(mut r Reader):
	forms {str: KeptForm} = {}
	loop r.count():
		key = r.readText()
		types = r.readInts()
		refs = r.readInts()
		nodes = r.readInts()
		asks = []
		loop r.count():
			kind = r.varint()
			text = r.readText()
			asks.push(KeptAsk(kind, text, types = r.readInts()))
		globals = r.readTexts()
		form = r.bytes(r.count())
		forms[key] = KeptForm(types, refs, nodes, asks, globals, form)
	forms
