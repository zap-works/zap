# The functions of the kept stages kept lowered (spec 14.2): a function of the runtime or of std
# (or an instance of their generic for their types) whose form names only the kept stages' types
# and nodes, and whose lowering made nothing the program shares but what it asked for by name
# (its strings, the drops and copies of types, the closures' stubs, the runtime's instances and
# their checks, the instances for the functions a call gives, the optionals' tags and ranges it
# types, the module variables it names), is kept as its passes
# made it, beside the stages in build/cache/, under the chain's key and what the program
# decides of those stages' functions (their effects, which of them are taken as values). The next
# build with the same takes the form instead of lowering it, asking for the same in the same
# order, so what the program shares grows as the lowering grew it and the executable is the same
# byte for byte.

import fs

keptIrMagic = "ZKIR"
keptIrVersion = 7

# the kept forms a build may take and those it adds
type KeptIr:
	path str = ""   # the last kept stage's (stagePath)
	key i64 = 0   # 0: none taken nor kept
	nodes i64 = 0   # the kept stages' nodes and types: a kept function is one of those nodes, and
	types i64 = 0   #   its form names no other
	forms {str: KeptForm} = {}   # those read (keptFormOf) or made
	waiting {str: i64} = {}   #   and the others of the file, where each one's record is in bytes
	bytes u8[] = []
	checked {str: bool} = {}   # the functions of the stages lowered and checked without an error
	inits NodeId[] = []   # the stages' module variables $init gives a value, in the order it does
	changed bool = false
	placed i64 = 0   # the functions whose code was placed, made from their forms, and kept, and
	made i64 = 0
	codes i64 = 0
	lowered i64 = 0   #   those of the stages lowered, no form of theirs taken

# what a lowering asked for by name, in order: a string (keptString, its offset then), a type's
# drop or copy, a closures' stub, a runtime's instance (its function's name, its types), an
# instance made for the functions a call gave (its label; the function, then each given's
# parameter, node and part), a type past the kept stages' its lowering made or met: an optional's
# tag (the optional), an arithmetic's range (its base and bounds), off then the type; an
# instance checked (its mangle, its generic); off of an instance's: its declaration
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
keptGiven = 5
keptNiche = 6
keptSpan = 7
keptCheck = 8
keptType = 9

# a function's form as its passes made it, its numbers (irNumbersOf) by their places: the types
# and nodes as they are, each data offset a ref; what its lowering asked for and the module
# variables it names
type KeptForm:
	types i64[]   # -1 - k: the type the k-th ask gives
	refs i64[]   # each data number: -1 - k the offset the k-th ask gives (a string), else that offset (a fixed one)
	nodes i64[]   # below 0: a node of an instance's copy (keptNodeRef)
	asks KeptAsk[]
	globals str[]
	spans i64   # the places read in place it numbered (irReadFrom): numbered on when it is taken
	form u8[]
	code KeptCode? = none   # its machine code (keptcode.zap)

# what a function's record keeps until its passes write its form (IrMade.kept)
type KeptPlan:
	numbers i64[,]
	types i64[]   # numbers' types as the form keeps them (KeptForm.types)
	nodes i64[]   # numbers' nodes as the form keeps them (KeptForm.nodes)
	refs i64[]
	asks KeptAsk[]
	globals str[]
	spans i64

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
		path = stage.stagePath(),
		key = "{stage.key} {g.keptFacts(stage.nodes)}".hash(),
		nodes = stage.nodes,
		types = stage.types
	)
	d = fs.readBytes(g.keptIr.keptIrPath()) ?? return
	parts = d.unpack(keptIrMagic, keptIrVersion) ?? return
	if not d.keptFor(parts, g.keptIr.key): return
	r = Reader(d, at = parts.bodyAt)
	waiting = r.keptFormPlaces()
	checked = r.readTexts()
	inits = r.readIds(0)
	if r.short or r.at != parts.end: return
	g.keptIr.inits = inits
	g.keptIr.waiting = waiting
	g.keptIr.bytes = move d
	for key in checked:
		g.keptIr.checked[key] = true

# the forms beside the last kept stage's file: those of the last chain and facts written
fn keptIrPath(k KeptIr):
	"{k.path}.ir"

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
	g.readKeptForm(key)
	kept = g.keptIr.forms.get(key) ?? return false
	found = g.keptTypesFound(kept.asks) ?? return false
	offsets = []
	for k, ask in kept.asks:
		offsets.push(found[k] if ask.kind == keptType else g.askedAgain(ask, found))
	for name in kept.globals:
		g.globalsNamed[name.copy()] = true
	g.irSpans += kept.spans
	data = kept.refs.map(offsets[-1 - it] if it < 0 else it)
	types = kept.types.map(offsets[-1 - it] if it < 0 else it)
	nodes = kept.nodes.map(keptNodeOf(it, fnd, offsets))
	g.irFileNow = g.c.nodes[fnd].file().copy()
	ret = g.c.fnRetType(fnd)
	if kept.code is code:
		g.made.push(
			IrMade(
				key = key.copy(),
				node = fnd,
				ret,
				f = newIrFn(),
				passed = true,
				code = code.copy(),
				keptData = data,
				keptTypes = types,
				keptNodes = nodes
			)
		)
	else:
		g.keptIr.made += 1
		f = g.keptFormRead(key, [types.copy(), data.copy(), nodes.copy()]) ?? return false
		g.made.push(
			IrMade(
				key = key.copy(),
				node = fnd,
				ret,
				f = move f,
				passed = true,
				keepsCode = true,
				keptData = data,
				keptTypes = types,
				keptNodes = nodes
			)
		)
	g.irShip()
	true

# the kept form under key read, numbers its types, data and nodes in this program
fn keptFormRead(g Gen, key str, numbers i64[,]) IrFn?:
	kept = try g.keptIr.forms.get(key)   # (readKeptForm read it)
	r = Reader(kept.form)
	r.irRead(irRenamingOf(numbers, true))

# A node past the kept stages' a form names, of an instance's copy (made alike, though where
# depends on the program): -1 - (k << 32 | at), its at-th node; k 0 the copy fnd is, else the copy
# the k-th ask's instance is (askedAgain gives its declaration)
fn keptNodeRef(g Gen, n i64, fnd NodeId, asks KeptAsk[]) i64?:
	if n < g.keptIr.nodes: return n
	if n >= i64(fnd) and n < g.keptCopyEnd(fnd): return -1 - (n - i64(fnd))
	for k, ask in asks:
		if (ask.kind == keptInstance or ask.kind == keptCheck) and n >= ask.off and
			n < g.keptCopyEnd(NodeId(ask.off)):
			return -1 - ((k + 1) << 32 | (n - ask.off))
	none

fn keptNodeOf(n i64, fnd NodeId, asked i64[]):
	if n >= 0: return n
	k = (-1 - n) >> 32
	at = (-1 - n) & 4_294_967_295
	at + (i64(fnd) if k == 0 else asked[k - 1])

# what the ask asks for asked for again: a string's offset, a type, else 0
fn askedAgain(mut g Gen, ask KeptAsk, found i64[]):
	if ask.kind == keptString: return g.strLit(ask.text)
	if ask.kind == keptNiche: return i64(g.irNicheTag(keptAskType(ask.types[0], found)))
	if ask.kind == keptSpan:
		base = keptAskType(ask.types[0], found)
		return i64(spanType(g.c.types, g.c.rangeTypes, base, Span(ask.types[1], ask.types[2])))
	if ask.kind == keptDrop or ask.kind == keptCopy:
		g.typeFnLabel(keptAskType(ask.types[0], found), ask.kind == keptDrop)
	elif ask.kind == keptStub:
		g.closureStubLabel(ask.text.copy())
	elif ask.kind == keptGiven:
		g.irGivenAgain(ask)
	elif ask.kind == keptCheck:
		ii = g.c.findInstance(NodeId(ask.types[0]), ask.text) ?? fail("no instance {ask.text}")
		g.askChecked(ii)
		return i64(g.c.instances[ii].decl)
	else:
		fnd = g.rtDecl(ask.text)
		mangle = g.rtMangle(ask.text, ask.types.map(keptAskType(it, found)))
		ii = g.c.findInstance(fnd, mangle) ?? return 0
		return i64(g.c.instances[ii].decl)
	0

# whether fnd, a function of the kept stages, was lowered and checked without an error by a build
# with the same: not checked again when nothing calls it
fn keptChecked(g Gen, fnd NodeId, key str):
	g.keepable(fnd) and (key in g.keptIr.checked or g.keptIr.hasForm(key))

# fnd lowered and checked without an error, noted when it is a kept stages' function
fn noteKeptChecked(mut g Gen, fnd NodeId, key str):
	if not g.keepable(fnd) or key in g.keptIr.checked: return
	g.keptIr.checked[key.copy()] = true
	g.keptIr.changed = true

# whether fnd's form may be kept or taken: a function of the kept stages, made for no function
# a call gives it but the kept stages' own (irgiven.zap: the program's are named as the program
# names them)
fn keepable(g Gen, fnd NodeId):
	g.keptIr.key != 0 and (i64(fnd) < g.keptIr.nodes or g.keptCopyEnd(fnd) > 0) and
		g.irGivenNow.all(i64(.node) < g.keptIr.nodes and .site.names.isEmpty and .held.isEmpty)

# past the nodes of fnd's tree when fnd is an instance's copy of a kept stages' generic for kept
# types: the instance's form names them by their place from fnd (the copy is made alike, though
# where depends on the program); else 0
fn keptCopyEnd(g Gen, fnd NodeId):
	i = g.c.instances.findIndex(.decl == fnd) ?? return 0
	gi = g.c.instances[i]
	if i64(gi.fnDecl) >= g.keptIr.nodes or not g.keptTypesOfParts(gi.sub.types): return 0
	gi.end

# the ask of an instance made for the functions given to fnd (its label made): none when one is
# not the kept stages' or a substitution is in force (keepable)
fn givenAsk(
	g Gen,
	made str,
	fnd NodeId,
	givens IrGiven[],
	implType TypeId?,
	implDecl NodeId?,
	new bool
) KeptAsk?:
	if implType != none or implDecl != none or not g.c.subst.names.isEmpty: return none
	ints = [i64(fnd)]
	for given in givens:
		if i64(given.node) >= g.keptIr.nodes or not given.site.names.isEmpty or
			not given.held.isEmpty:
			return none
		ints.extend([given.at, i64(given.node), given.part])
	KeptAsk(keptGiven, made.copy(), types = ints, made = new)

# whether the lowering of fnd may be kept: a function of the kept stages none is kept for yet;
# what it asks for is noted while it is lowered
fn mayKeep(mut g Gen, fnd NodeId, key str):
	staged = g.keepable(fnd)
	if staged: g.keptIr.lowered += 1
	keeps = staged and not g.keptIr.hasForm(key)
	g.asksNoted = []
	g.asksNoting = keeps
	g.asksSpoiled = false
	g.asksGrew = []
	typesPast = g.keptIr.types if keeps else -1
	typesMet = []
	keeps

# the runtime's instance fnd of sub recorded: while a function being kept is lowered, what
# making it grew of the shared state counted as its ask's, which the form taken makes again
fn askInstance(mut g Gen, fnd NodeId, sub Subst):
	if not g.asksNoting: return g.c.recordInstance(fnd, sub, fnd)
	before = g.askBegun()
	mangle = g.c.recordInstance(fnd, sub, fnd)
	g.askEnded(before)
	mangle

# the instance ii checked: while a function being kept is lowered, asked for again (another
# program may not have checked it yet, nor made the instances its check makes) and what the
# check grew of the shared state counted as the ask's
fn askChecked(mut g Gen, ii i64):
	if not g.asksNoting: return g.c.checkInstance(ii)
	gi = g.c.instances[ii]
	g.noteAsk(KeptAsk(keptCheck, gi.mangle.copy(), types = [i64(gi.fnDecl)], off = i64(gi.decl)))
	before = g.askBegun()
	g.c.checkInstance(ii)
	g.askEnded(before)

# the declaration of the instance mangle of fnd an instance's ask noted last made
fn noteInstanceAsked(mut g Gen, fnd NodeId, mangle str):
	if not g.asksNoting: return
	ii = g.c.findInstance(fnd, mangle) ?? return
	g.asksNoted[len - 1].off = i64(g.c.instances[ii].decl)

# the shared state's sizes before an ask makes what it asks for, the types it meets not counted
fn askBegun(mut g Gen):
	typesPast = -1
	[g.lowerSharedSizes(), g.lowerMemoSizes()]

# what the ask made since before counted as its own
fn askEnded(mut g Gen, before i64[,]):
	typesPast = g.keptIr.types
	after = [g.lowerSharedSizes(), g.lowerMemoSizes()]
	if g.asksGrew.isEmpty: g.asksGrew = [zeros(before[0].len), zeros(before[1].len)]
	for row in 0..2:
		for i in 0..before[row].len:
			g.asksGrew[row][i] += after[row][i] - before[row][i]

# a lowering's ask noted, while a function being kept is lowered, after the ranges its
# arithmetic made or met since the last
fn noteAsk(mut g Gen, move ask KeptAsk):
	g.noteSpansAsked()
	if g.asksNoting: g.asksNoted.push(ask)

fn noteSpansAsked(mut g Gen):
	if spansAsked.isEmpty: return
	if g.asksNoting:
		for s in spansAsked:
			g.asksNoted.push(KeptAsk(keptSpan, types = s[..3].copy(), off = s[3], made = s[4] == 1))
	spansAsked = []

# a type past the kept stages' the lowering made or met, noted as an ask of kind
fn noteTypeAsk(mut g Gen, kind i64, types i64[], t TypeId, made bool):
	if i64(t) >= g.keptIr.types or made:
		g.noteAsk(KeptAsk(kind, types = types.copy(), off = i64(t), made))

# the plan of keeping f, lowered with the program's shared state at sizes before: none when its
# lowering met a type past the kept stages' not made of their parts alone (kepttypes.zap), added
# to the shared state what its asks do not make again (types, nodes, instances, lambdas, data but
# strings), or its form names a node past the kept stages', a type neither theirs nor of their
# parts, or data that is neither a string it asked for nor a module variable's
fn keptPlanOf(mut g Gen, fnd NodeId, f IrFn, before i64[,], clean bool) KeptPlan?:
	g.noteSpansAsked()
	g.asksNoting = false
	typesPast = -1
	met = move typesMet
	typesMet = []
	if not clean or g.asksSpoiled: return none
	after = [g.lowerSharedSizes(), g.lowerMemoSizes()]
	grew = move g.asksGrew
	g.asksGrew = []
	if grew.isEmpty: grew = [zeros(before[0].len), zeros(before[1].len)]
	asks = move g.asksNoted
	g.asksNoted = []
	made = asks.count(.made and .kind in [keptDrop, keptCopy, keptStub])
	strings = asks.count(.made and .kind == keptString)
	givens = asks.count(.made and .kind == keptGiven)
	madeTypes = asks.count(.made and (.kind == keptNiche or .kind == keptSpan))
	for i in 0..before[0].len:
		grown = after[0][i] - before[0][i] - grew[0][i]
		# drops planned, labels, strings, given instances
		allowed = made if i in [6, 8] else strings if i == 7 else givens if i == 3
			else madeTypes if i == 4 else 0
		if grown != allowed and i not in [2, 9, 11, 13]:
			return none   # (spans numbered again, globals named, call stores, data)
	for i in [4, 5, 6, 18]:   # type descriptors, loaded slots, function values, typeIndex
		if after[1][i] - before[1][i] != grew[1][i]: return none
	noted = asks.len
	for t in met:
		_ = try g.keptTypeRef(t, asks)
	for k in 0..noted:
		ts = asks[k].types.copy()
		if asks[k].kind in [keptDrop, keptCopy, keptNiche, keptInstance]:
			asks[k].types = try g.keptAskTypes(ts, asks)
		elif asks[k].kind == keptSpan:
			asks[k].types[0] = try g.keptTypeRef(TypeId(ts[0]), asks)
	for ask in asks:
		if ask.kind == keptType: continue
		bound = g.keptIr.nodes if ask.kind in [keptGiven, keptCheck] else g.keptIr.types
		if ask.types[..1 if ask.kind == keptSpan else len].any(it >= bound): return none
	if g.namesLaterFunction(f): return none
	numbers = f.irNumbersOf()
	types = []
	for t in numbers[0]:
		if t < g.keptIr.types:
			types.push(t)
		elif asks.findIndex(.kind in [keptNiche, keptSpan, keptType] and .off == t) is k:
			types.push(-1 - k)
		else:
			types.push(try g.keptTypeRef(TypeId(t), asks))
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
	nodes = []
	for n in numbers[2]:
		nodes.push(try g.keptNodeRef(n, fnd, asks))
	spans = after[0][2] - before[0][2] - grew[0][2]
	KeptPlan(numbers, types, nodes, refs, asks, globals, spans)

# whether f calls, or takes the address of, a function declared past the kept stages by its name
# (one the program's check derived, as a comparison: named by count)
fn namesLaterFunction(g Gen, f IrFn):
	for b in f.blocks:
		for inst in b.insts:
			if (inst.op == irCall or inst.op == irFnAddr) and inst.key != "" and
				g.c.findFunc(inst.key) is d and i64(d) >= g.keptIr.nodes:
				return true
	false

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
		types = plan.types.copy(),
		refs = plan.refs.copy(),
		nodes = plan.nodes.copy(),
		asks = plan.asks.copy(),
		globals = plan.globals.copy(),
		spans = plan.spans,
		form = move m.keptForm
	)
	m.keptForm = []
	g.keptIr.changed = true
	m.keepsCode = true
	m.keptData = plan.numbers[1].copy()
	m.keptTypes = plan.numbers[0].copy()

# the form of m as its passes made it, its numbers by their places, for keepMadeForm
fn writeKeptForm(mut m IrMade):
	plan = m.kept ?? return
	out = []
	if m.f.irWrite(out, irRenamingOf(plan.numbers, false)): m.keptForm = move out

# the kept forms written back with those another build wrote since, when this one added some
fn saveKeptIr(g Gen):
	if keptWord().on() and g.keptIr.key != 0:
		k = g.keptIr
		eprint("kept: code placed {k.placed}, made from the form {k.made}, kept {k.codes}, lowered {k.lowered}")
	if not g.keptIr.changed: return
	path = g.keptIr.keptIrPath()
	forms = g.keptIr.forms.copy()
	for key, at in g.keptIr.waiting:
		if key not in forms: forms[key.copy()] = keptFormAt(g.keptIr.bytes, at)
	checked = g.keptIr.checked.copy()
	inits = g.keptIr.inits.copy()
	if fs.readBytes(path) is d and d.unpack(keptIrMagic, keptIrVersion) is parts and
		d.keptFor(parts, g.keptIr.key):
		r = Reader(d, at = parts.bodyAt)
		for key, at in r.keptFormPlaces():
			form = keptFormAt(d, at)
			if forms.get(key) is mine and (mine.code != none or form.code == none): continue
			forms[key.copy()] = form
		for key in r.readTexts():
			checked[key] = true
		writtenInits = r.readIds(0)
		if inits.isEmpty: inits = writtenInits
	body = []
	body.pushVarint(forms.len)
	for key, form in forms:
		body.pushText(key)
		record u8[] = []
		record.pushKeptForm(form)
		body.pushVarint(record.len)
		body.extend(record)
	body.pushTexts(checked.keys())
	body.pushIds(inits, 0)
	head = []
	head.pushU64le(compilerKey())
	head.pushU64le(g.keptIr.key)
	_ = fs.createDir(cachesDir)
	placeFile(path, str(PackedParts.pack(keptIrMagic, keptIrVersion, head, body)))

# the kept forms of a file, by key: where each one's record (pushKeptForm's) is, read when a
# build takes it (most of a small one's take few)
fn keptFormPlaces(mut r Reader):
	places {str: i64} = {}
	loop r.count():
		key = r.readText()
		n = r.count()
		places[key] = r.at
		r.at += n
	places

# whether a form is kept under key
fn hasForm(k KeptIr, key str):
	key in k.forms or key in k.waiting

# the form kept under key read from the file into forms, the first time it is asked for
fn readKeptForm(mut g Gen, key str):
	if key in g.keptIr.forms: return
	at = g.keptIr.waiting.get(key) ?? return
	g.keptIr.forms[key.copy()] = keptFormAt(g.keptIr.bytes, at)

fn pushKeptForm(mut out u8[], form KeptForm):
	out.pushInts(form.types)
	out.pushInts(form.refs)
	out.pushInts(form.nodes)
	out.pushVarint(form.asks.len)
	for ask in form.asks:
		out.pushVarint(ask.kind)
		out.pushText(ask.text)
		out.pushInts(ask.types)
		out.pushVarint(ask.off)
	out.pushTexts(form.globals)
	out.pushVarint(form.spans)
	out.pushVarint(form.form.len)
	out.extend(form.form)
	if form.code is code:
		out.pushVarint(1)
		out.pushKeptCode(code)
	else:
		out.pushVarint(0)

# the form pushKeptForm wrote at at
fn keptFormAt(d u8[], at i64):
	r = Reader(d, at)
	types = r.readInts()
	refs = r.readInts()
	nodes = r.readInts()
	asks = []
	loop r.count():
		kind = r.varint()
		text = r.readText()
		asked = r.readInts()
		asks.push(KeptAsk(kind, text, types = asked, off = r.varint()))
	globals = r.readTexts()
	spans = r.varint()
	form = r.bytes(r.count())
	code KeptCode? = r.readKeptCode() if r.varint() == 1 else none
	KeptForm(types, refs, nodes, asks, globals, spans, form, code)
