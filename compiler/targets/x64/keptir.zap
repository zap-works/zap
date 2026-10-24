# The functions of the kept stages kept lowered (spec 14.2): a function of the runtime, std or
# the program's imported modules (or an instance of their generic for their types) whose form
# names only the kept stages' types and nodes, and whose lowering made nothing the program shares
# but what it asked for by name (its strings, the drops and copies of types, the closures' stubs,
# the runtime's instances and their checks, the instances for the functions a call gives, the
# optionals' tags and ranges it types, the module variables it names), is kept as its passes made
# it, beside the first stage in build/cache/ that holds what it names (KeptLayer), under that
# stage's key and what the program decides of the functions up to it (their effects, which of
# them are taken as values). The next build with the same takes the form instead of lowering it,
# asking for the same in the same order, so what the program shares grows as the lowering grew it
# and the executable is the same byte for byte.

import fs

keptIrMagic = "ZKIR"
keptIrVersion = 12

# the kept forms a build may take and those it adds
type KeptIr:
	layers KeptLayer[] = []
	key i64 = 0   # the last layer's; 0: none taken nor kept
	nodes i64 = 0   # the kept stages' nodes and types: a kept function is one of those nodes, and
	types i64 = 0   #   its form names no other
	forms {str: KeptForm} = {}   # those read (keptFormOf) or made
	waiting {str: i64} = {}   #   and the others of the files, where each one's record is in its
	waitingIn {str: i64} = {}   #   layer's bytes
	checked {str: i64} = {}   # the stages' functions lowered and checked without an error: their layer
	inits NodeId[] = []   # the stages' module variables $init gives a value, in the order it does
	placed i64 = 0   # the functions whose code was placed, made from their forms, and kept, and
	made i64 = 0
	codes i64 = 0
	lowered i64 = 0   #   those of the stages lowered, no form of theirs taken

# The forms kept beside one stage of the chain (a layer): those of the functions whose forms and
# code name nothing past it, under its key and what the program decides of the functions up to
# it. A form is the first layer's that holds what it names, so an edit of a module past it
# leaves it kept, and programs whose stages begin alike share it.
type KeptLayer:
	path str   # the stage's (stagePath)
	key i64
	nodes i64   # the nodes, types and instances up to the stage
	types i64
	instances i64
	bytes u8[] = []
	changed bool = false

# what a lowering asked for by name, in order: a string (keptString, its offset then), a type's
# drop or copy, a closures' stub, a runtime's instance (its function's name, its types), an
# instance made for the functions a call gave (its label; the function, then each given's
# parameter, node and part), a type past the kept stages' its lowering made or met: an optional's
# tag (the optional), an arithmetic's range (its base and bounds), off then the type; an
# instance checked (its mangle, its generic); one its check recorded (its generic, its types); a
# type of the kept stages' parts (kepttypes.zap); off of an instance's: its declaration
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
keptRecord = 10
keptDerived = 11   # a function the program's check derived, named alike in every program (derivedName)

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
	layer i64 = 0   # the layer it is kept in (KeptLayer)

# what a function's record keeps until its passes write its form (IrMade.kept)
type KeptPlan:
	numbers i64[,]
	types i64[]   # numbers' types as the form keeps them (KeptForm.types)
	nodes i64[]   # numbers' nodes as the form keeps them (KeptForm.nodes)
	refs i64[]
	asks KeptAsk[]
	globals str[]
	spans i64
	layer i64   # the first layer that holds what it names

# the kept forms of this program's kept stages read, when the build may take them: a layer per
# stage of the runtime, std or the program's modules it checked or read, each keyed with the facts
# the program decides of the functions up to it
fn openKeptIr(mut g Gen, stages CheckStage[]):
	g.keptIr = KeptIr()
	if not keepsStages() or noting or checksShared or lowersPatchedOnly or irTraced(): return
	kept = stages.filter(.key != 0 and .done)
	if kept.isEmpty: return
	facts = g.layerFacts(kept.map(.nodes))
	for i, s in kept:
		key = "{s.key} {facts[..i + 1].map("{it}").join(" ")}".hash()
		g.keptIr.layers.push(KeptLayer(
			path = s.stagePath(),
			key,
			nodes = s.nodes,
			types = s.types,
			instances = s.instances
		))
	last = kept[len - 1]
	g.keptIr.key = g.keptIr.layers[kept.len - 1].key
	g.keptIr.nodes = last.nodes
	g.keptIr.types = last.types
	for i in 0..kept.len:
		g.readKeptLayer(i)

# the forms of layer i read, when its file is of its key
fn readKeptLayer(mut g Gen, i i64):
	layer = g.keptIr.layers[i]
	d = fs.readBytes(layer.keptIrPath()) ?? return
	parts = d.unpack(keptIrMagic, keptIrVersion) ?? return
	if not d.keptFor(parts, layer.key): return
	r = Reader(d, at = parts.bodyAt)
	waiting = r.keptFormPlaces()
	checked = r.readTexts()
	inits = r.readIds(0)
	if r.short or r.at != parts.end: return
	if i == g.keptIr.layers.len - 1: g.keptIr.inits = inits
	for key, at in waiting:
		g.keptIr.waiting[key.copy()] = at
		g.keptIr.waitingIn[key.copy()] = i
	for key in checked:
		g.keptIr.checked[key] = i
	g.keptIr.layers[i].bytes = move d

# the forms beside a kept stage's file: those of the last chain and facts written
fn keptIrPath(k KeptLayer):
	"{k.path}.ir"

# the first layer whose nodes (types) hold n, the last when none does
fn nodeLayer(k KeptIr, n i64):
	k.layers.findIndex(.nodes > n) ?? k.layers.len - 1

fn typeLayer(k KeptIr, t i64):
	k.layers.findIndex(.types > t) ?? k.layers.len - 1

# a layer's form or what it checked changed: its file written again
fn touch(mut k KeptIr, layer i64):
	k.layers[layer].changed = true

# whether a word of ZAP_RUN asks to see what the lowering does: every function is lowered then
fn irTraced():
	irWord().on() or irDumpWord().on() or irLoweredWord().on() or irOwnWord().on() or
		irMaxWord().on() or irInlineWord().on() or irBlocksWord().on() or irDropsWord().on() or
		lowerSharedWord().on()

# a hash for each layer of what the program decides of its functions, those below its bound and
# not below the one before: which are taken as values (their calls keep the stack convention),
# what each changes (effects.zap) and does (purity.zap)
fn layerFacts(g Gen, bounds i64[]):
	lines str[,] = []
	for _ in bounds:
		lines.push([])
	for name in g.fnValueNames.keys():
		if g.c.findFunc(name) is d: lines.noteFact(bounds, i64(d), "value {name}")
	for key, paths in g.c.effects:
		if i64.parse(key[..key.indexOf(":") ?? 0]) is d:
			lines.noteFact(bounds, d, "{key} {paths.join(" ")}")
	for d, bits in g.c.fnEffects:
		lines.noteFact(bounds, i64(d), "does {d} {bits}")
	lines.map(.sorted().join("\n").hash())

fn noteFact(mut lines str[,], bounds i64[], d i64, move line str):
	if bounds.findIndex(it > d) is i: lines[i].push(line)

# the kept form of the function fnd under key made (taken instead of lowered), what its lowering
# asked for asked again and its module variables named; false when there is none. Plain: the
# initializer of the module variable fnd ($init:name, irglobals.zap), of no node of its own.
fn irKeptForm(mut g Gen, fnd NodeId, key str, plain bool = false):
	if not g.keepable(fnd): return false
	kept = g.keptFormOf(key) ?? return false
	if kept.asks.any(.kind == keptDerived and g.c.findFunc(.text) == none): return false
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
	if not plain: g.irFileNow = g.c.nodes[fnd].file().copy()
	ret = tyUnit if plain else g.c.fnRetType(fnd)
	node NodeId? = none if plain else fnd
	if kept.code != none:
		g.made.push(
			IrMade(
				key = key.copy(),
				node,
				ret,
				f = newIrFn(),
				passed = true,
				code = kept.code,
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
				node,
				ret,
				f = move f,
				passed = true,
				keepsCode = true,
				keptData = data,
				keptTypes = types,
				keptNodes = nodes
			)
		)
		g.irShip()   # (a kept code, which has no passes, goes with the next function shipped)
	true

# the kept form under key read, numbers its types, data and nodes in this program
fn keptFormRead(mut g Gen, key str, numbers i64[,]) IrFn?:
	g.readKeptForm(key)
	kept = try g.keptIr.forms.get(key)
	r = Reader(kept.form)
	r.irRead(irRenamingOf(numbers, true))

# A node past the kept stages' a form names, of an instance's copy (made alike, though where
# depends on the program): -1 - (k << 32 | at), its at-th node; k 0 the copy fnd is, else the copy
# the k-th ask's instance is (askedAgain gives its declaration)
fn keptNodeRef(g Gen, n i64, fnd NodeId, asks KeptAsk[]) i64?:
	if n < g.keptIr.nodes: return n
	if n >= i64(fnd) and n < g.keptCopyEnd(fnd): return -1 - (n - i64(fnd))
	for k, ask in asks:
		if ask.kind in [keptInstance, keptCheck, keptRecord] and n >= ask.off and
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
	if ask.kind == keptDerived: return 0
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
	elif ask.kind == keptRecord:
		fnd = NodeId(ask.types[0])
		sub = Subst(g.c.nodes[fnd].names.copy(), ask.types[1..].map(keptAskType(it, found)))
		mangle = g.c.recordInstance(fnd, sub, fnd)
		ii = g.c.findInstance(fnd, mangle) ?? fail("no instance {mangle}")
		return i64(g.c.instances[ii].decl)
	elif ask.kind == keptCheck:   # (what its check asked for follows it: keptRecord)
		ii = g.c.findInstance(NodeId(ask.types[0]), ask.text) ?? fail("no instance {ask.text}")
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
	layer = g.fnLayer(fnd)
	g.keptIr.checked[key.copy()] = layer
	g.keptIr.touch(layer)

# the first layer that holds fnd, a kept function (keepable): its node's, else, an instance's
# copy, its generic's and its types', and the functions given to it
fn fnLayer(g Gen, fnd NodeId):
	k = g.keptIr
	layer = k.nodeLayer(i64(fnd))
	if i64(fnd) >= k.nodes:
		gi = g.c.instances.find(.decl == fnd) ?? return k.layers.len - 1
		layer = k.nodeLayer(i64(gi.fnDecl))
		for t in gi.sub.types:
			layer = layer.max(g.partsLayer(t))
	for given in g.irGivenNow:
		layer = layer.max(k.nodeLayer(i64(given.node)))
	layer

# whether fnd's form may be kept or taken: a function of the kept stages, made for no function
# a call gives it but the kept stages' own (irgiven.zap: the program's are named as the program
# names them)
fn keepable(g Gen, fnd NodeId):
	g.keptIr.key != 0 and (i64(fnd) < g.keptIr.nodes or g.keptCopyEnd(fnd) > 0) and
		g.irGivenNow.all(i64(.node) < g.keptIr.nodes and .site.names.isEmpty and .held.isEmpty)

# whether fnd is an instance's copy of a kept stages' generic, whatever its types
fn ofKeptGeneric(g Gen, fnd NodeId):
	i = g.c.instances.findIndex(.decl == fnd) ?? return false
	i64(g.c.instances[i].fnDecl) < g.keptIr.nodes

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
	if staged or g.keptIr.key != 0 and g.ofKeptGeneric(fnd): g.keptIr.lowered += 1
	keeps = staged and not g.keptIr.hasForm(key)
	g.asksNoted = move g.checkRecorded if keeps else []
	g.checkRecorded = []
	g.asksNoting = keeps
	g.asksSpoiled = false
	g.asksGrew = []
	typesPast = g.keptIr.types if keeps else -1
	typesMet = []
	typesMetTop = -1
	keeps

# the runtime's instance fnd of sub recorded: while a function being kept is lowered, what
# making it grew of the shared state counted as its ask's, which the form taken makes again
fn askInstance(mut g Gen, fnd NodeId, sub Subst):
	if not g.asksNoting: return g.c.recordInstance(fnd, sub, fnd)
	before = g.askBegun()
	mangle = g.c.recordInstance(fnd, sub, fnd)
	g.askEnded(before)
	mangle

# the instance ii checked before it is lowered (or earlier), the instances its check asked for
# noted as asks of its form (checkRecorded), which the build that takes the form records again,
# unchecked
fn checkKeptInstance(mut g Gen, ii i64):
	g.c.checkInstance(ii)
	g.checkRecorded = g.c.instances[ii].recorded.map(g.recordAsk(it))

# the ask of instance k recorded again
fn recordAsk(g Gen, k i64):
	gi = g.c.instances[k]
	ask = KeptAsk(keptRecord, gi.mangle.copy(), types = [i64(gi.fnDecl)], off = i64(gi.decl))
	ask.types.extend(gi.sub.types.map(i64(it)))
	ask

# the instance ii checked: while a function being kept is lowered, asked for again with what its
# check asked for (another program may not have recorded those yet; its form taken lowers nothing,
# so it is not checked) and what the check grew of the shared state counted as the ask's
fn askChecked(mut g Gen, ii i64):
	if not g.asksNoting: return g.c.checkInstance(ii)
	gi = g.c.instances[ii]
	g.noteAsk(KeptAsk(keptCheck, gi.mangle.copy(), types = [i64(gi.fnDecl)], off = i64(gi.decl)))
	before = g.askBegun()
	g.c.checkInstance(ii)
	g.askEnded(before)
	for k in g.c.instances[ii].recorded.copy():
		g.noteAsk(g.recordAsk(k))

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
		# (each made first: the asks grow as their types are named)
		if asks[k].kind in [keptDrop, keptCopy, keptNiche, keptInstance]:
			named = try g.keptAskTypes(ts, asks)
			asks[k].types = named
		elif asks[k].kind == keptRecord:
			named = [ts[0]]
			named.extend(try g.keptAskTypes(ts[1..], asks))
			asks[k].types = named
		elif asks[k].kind == keptSpan:
			named = ts.copy()
			named[0] = try g.keptTypeRef(TypeId(ts[0]), asks)
			asks[k].types = named
	for ask in asks:
		if ask.kind == keptType: continue
		bound = g.keptIr.nodes if ask.kind in [keptGiven, keptCheck, keptRecord] else g.keptIr.types
		if ask.types[..1 if ask.kind in [keptSpan, keptRecord] else len].any(it >= bound):
			return none
	named = g.lastNamedFunction(f)
	if named >= g.keptIr.nodes: return none
	for key in g.derivedNamed(f):
		asks.push(KeptAsk(keptDerived, key))
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
	layer = g.fnLayer(fnd).max(g.keptIr.typeLayer(typesMetTop)).max(g.keptIr.nodeLayer(named))
	for t in types:
		layer = layer.max(g.keptIr.typeLayer(t))   # (an ask's, below 0, in the first)
	for n in nodes:
		layer = layer.max(g.keptIr.nodeLayer(n))
	for ask in asks:
		layer = layer.max(g.askLayer(ask))
	for name in globals:
		layer = layer.max(g.keptIr.nodeLayer(g.globalNode(name)))
	KeptPlan(numbers, types, nodes, refs, asks, globals, spans, layer)

# the last of the functions f calls, or takes the address of, by their names, but those the
# program derived named alike in every program (derivedNamed): -1 none (another the program's
# check derived is named by count)
fn lastNamedFunction(g Gen, f IrFn):
	last = -1
	for b in f.blocks:
		for inst in b.insts:
			if (inst.op == irCall or inst.op == irFnAddr) and inst.key != "" and
				not stablyDerived(inst.key) and g.c.findFunc(inst.key) is d:
				last = last.max(i64(d))
	last

# the functions the program derived that f calls by their names, named alike in every program
# (derivedName): asked for again by name
fn derivedNamed(g Gen, f IrFn):
	keys str[] = []
	for b in f.blocks:
		for inst in b.insts:
			if (inst.op == irCall or inst.op == irFnAddr) and stablyDerived(inst.key) and
				inst.key not in keys and g.c.findFunc(inst.key) != none:
				keys.push(inst.key.copy())
	keys

# whether key names a derived equality or order of built-in types (derivedName)
fn stablyDerived(key str):
	key.startsWith("derive__$eq_") or key.startsWith("derive__$cmp_")

# the first layer that holds what an ask names: the types, nodes and generics it asks with
fn askLayer(g Gen, ask KeptAsk):
	k = g.keptIr
	if ask.kind == keptString or ask.kind == keptStub: return 0
	if ask.kind == keptDerived: return 0   # (of built-in types, whose templates are core's)
	if ask.kind == keptGiven: return ask.types.map(k.nodeLayer(it)).max() ?? 0
	if ask.kind == keptType: return g.partsLayer(TypeId(ask.off))
	if ask.kind == keptCheck:   # (and the stage that recorded the instance, which the form finds)
		ii = g.c.findInstance(NodeId(ask.types[0]), ask.text) ?? return k.layers.len - 1
		layer = k
			.nodeLayer(ask.types[0])
			.max(k.layers.findIndex(.instances > ii) ?? k.layers.len - 1)
		for t in g.c.instances[ii].sub.types:
			layer = layer.max(g.partsLayer(t))
		return layer
	if ask.kind == keptRecord:
		return k.nodeLayer(ask.types[0]).max(ask.types[1..].map(k.typeLayer(it)).max() ?? 0)
	if ask.kind == keptInstance:
		fnd = g.c.findFunc("rt__{ask.text}") ?? return k.layers.len - 1
		return k.nodeLayer(i64(fnd)).max(ask.types.map(k.typeLayer(it)).max() ?? 0)
	k.typeLayer(ask.types[0])   # (a drop, a copy, a niche's optional, a span's base; an ask's below 0)

# the first layer that holds type t: its own, or of one past the kept stages' made of their parts
# (kepttypes.zap), the parts'
fn partsLayer(g Gen, t TypeId) i64:
	k = g.keptIr
	if i64(t) < k.types: return k.typeLayer(i64(t))
	ty = g.c.types[t]
	layer = 0
	for part in [ty.inner, ty.err, ty.val, ty.ret, ty.under]:
		if part is p: layer = layer.max(g.partsLayer(p))
	for p in ty.params:
		layer = layer.max(g.partsLayer(p))
	if ty.defined is d: layer = layer.max(k.nodeLayer(i64(d)))
	if ty.decl is d:
		if i64(d) < k.nodes: return layer.max(k.nodeLayer(i64(d)))
		tmpl = g.c.nodes[d].origin ?? return k.layers.len - 1
		layer = layer.max(k.nodeLayer(i64(tmpl)))
		for a in g.c.nodes[d].ints():
			layer = layer.max(g.partsLayer(a))
	layer

# the declaration of the module variable name, as a node number
fn globalNode(g Gen, name str):
	i64(g.c.findDeclByGlobalName(nConstDecl, name) ?? NodeId(0))

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
		form = move m.keptForm,
		layer = plan.layer
	)
	m.keptForm = []
	g.keptIr.touch(plan.layer)
	m.keepsCode = true
	m.keptData = plan.numbers[1].copy()
	m.keptTypes = plan.numbers[0].copy()

# the form of m as its passes made it, its numbers by their places, for keepMadeForm
fn writeKeptForm(mut m IrMade):
	plan = m.kept ?? return
	out = []
	if m.f.irWrite(out, irRenamingOf(plan.numbers, false)): m.keptForm = move out

# the kept forms of each layer a form or what was checked of changed written back with those
# another build wrote since
fn saveKeptIr(g Gen):
	if keptWord().on() and g.keptIr.key != 0:
		k = g.keptIr
		eprint("kept: code placed {k.placed}, made from the form {k.made}, kept {k.codes}, lowered {k.lowered}")
	for i, layer in g.keptIr.layers:
		if layer.changed: g.saveKeptLayer(i)

fn saveKeptLayer(g Gen, i i64):
	layer = g.keptIr.layers[i]
	path = layer.keptIrPath()
	forms {str: KeptForm} = {}
	for key, form in g.keptIr.forms:
		if form.layer == i: forms[key.copy()] = form.copy()
	for key, at in g.keptIr.waiting:
		if key not in g.keptIr.forms and (g.keptIr.waitingIn.get(key) ?? -1) == i:
			forms[key.copy()] = keptFormAt(layer.bytes, at, true)
	checked {str: bool} = {}
	for key, at in g.keptIr.checked:
		if at == i: checked[key.copy()] = true
	last = i == g.keptIr.layers.len - 1
	inits = g.keptIr.inits.copy() if last else []
	if fs.readBytes(path) is d and d.unpack(keptIrMagic, keptIrVersion) is parts and
		d.keptFor(parts, layer.key):
		r = Reader(d, at = parts.bodyAt)
		for key, at in r.keptFormPlaces():
			form = keptFormAt(d, at, true)
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
	head.pushU64le(layer.key)
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
	layer = g.keptIr.waitingIn.get(key) ?? return
	form = keptFormAt(g.keptIr.layers[layer].bytes, at, true)
	form.layer = layer
	g.keptIr.forms[key.copy()] = form

# the form kept under key a build takes: one with its code read from the file without its form
# and left there (readKeptForm reads it whole when the code cannot be placed)
fn keptFormOf(mut g Gen, key str) KeptForm?:
	if g.keptIr.forms.get(key) is read: return read.copy()
	at = try g.keptIr.waiting.get(key)
	layer = try g.keptIr.waitingIn.get(key)
	kept = keptFormAt(g.keptIr.layers[layer].bytes, at, false)
	kept.layer = layer
	if kept.code == none: g.keptIr.forms[key.copy()] = kept.copy()
	kept

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

# the form pushKeptForm wrote at at, without the form's bytes when its code is kept and not whole
fn keptFormAt(d u8[], at i64, whole bool):
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
	n = r.count()
	formAt = r.at
	if r.has(n): r.at += n   # (else short: no form)
	code KeptCode? = r.readKeptCode() if r.varint() == 1 else none
	form = d[formAt..r.at].copy() if whole or code == none else []
	KeptForm(types, refs, nodes, asks, globals, spans, form, code)
