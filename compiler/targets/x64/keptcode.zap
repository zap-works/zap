# The machine code of the kept stages' functions kept beside their forms (keptir.zap, spec 14.2):
# a function whose form is kept has its code, as its emission wrote it before the jumps are made
# short, kept with the form, every place its code names outside its bytes named by what it is (a
# label of its own, a function's label by its key, a check's stub, a data number of its form, a
# float, an import) and what it added to the assembler's lists (paddings, regions, source lines,
# its peephole state at its end) by its places. The code depends on the form alone, the chain's
# key and the program's facts the form is kept under, and the target; its emission reads one
# thing more, the source line it begins at, which a build
# taking it checks (else the form is made again). A build placing it at another position of
# another program's code gets the code the emission there writes: the executable is the same byte
# for byte.

# A function's code kept: its bytes and what they name, each place an offset into them.
type KeptCode:
	bytes u8[]
	fixes i64[]   # per fixup: kind, place, jump (fixJump), what it names (refOf, dataRefOf, an
# import's place in imports) and a table's label or the bytes into a module variable
	names str[]   # the labels it names but does not make: a function's key, "#k" the k-th
# stub, "%dT" ("%cT") the drop (copy) of type T, "%d@k" of the k-th of its form's types
	imports str[]   # the imports it names, "dll\tname"
	globals str[]   # the module variables it names
	floats i64[]   # the floats it asked for, in order (floatConst), and for each how many of the
	floatsAfter i64[]   #   drops' and copies' names it names were asked before it (their data first)
	labels i64[]   # the labels it made: each one's place, -1 unplaced
	pads i64[]   # per loop top's padding: place, length
	regions i64[]   # per region asked for: place, kind (-1 a leaf, 0 the frame on rbp, k infos[k - 1])
	infos i64[,]
	lines i64[]   # per source line noted: place, line, column, file (in files)
	files str[]
	line i64   # the line, column and file its emission began at (curLine, curCol, curFile: those
	col i64   #   of its fail sites and source lines when no node of its sets them, as a module
	file str   #   variable's initializer), and the line and column it ended at
	endLine i64
	endCol i64
	tail i64[]   # the assembler's peephole state at its end (asmTailOf)

# the lists' lengths an emission being kept began at
type KeptCodeMark:
	at i64
	fixes i64
	labels i64
	pads i64
	placed i64
	strings i64
	addresses i64
	libc i64
	types i64
	descriptors i64
	planned i64
	line i64
	col i64
	file str
	stable i64 = -1   # a held code's (irheld.zap): the labels and the data's bytes made before
	stableData i64 = -1   #   it, which it names by their numbers

# the checks' stubs, by their place in the list: the same labels in every program
fn checkStubs(g Gen):
	[g.failDivZero, g.failShift, g.failStep, g.failBounds, g.failOverflow, g.failConversion,
		g.failCpu]

# the emission of a function to be kept begins: what it asks for noted
fn keptCodeBegin(mut g Gen) KeptCodeMark:
	g.codeNoting = true
	g.floatsNoted = []
	g.linesNoted = []
	g.labelsNoted = []
	g.a.regionsNoting = true
	g.a.regionsNoted = []
	KeptCodeMark(
		at = g.a.code.len,
		fixes = g.a.fixAt.len,
		labels = g.a.labelPos.len,
		pads = g.a.padAt.len,
		placed = g.a.placedBelow.len,
		strings = g.strOffs.len,
		addresses = g.a.addresses.len,
		libc = g.a.libcNames.len,
		types = g.c.types.len,
		descriptors = g.tdOffs.len,
		planned = g.planned.len,
		line = g.curLine,
		col = g.curCol,
		file = g.curFileName()
	)

# m's code emitted since mark kept with its form, unless it names what it cannot name again
fn keepCode(mut g Gen, m IrMade, mark KeptCodeMark):
	data = m.keptData.copy()
	code = g.keptCodeEnd(mark, data, m.keptTypes) ?? return
	g.readKeptForm(m.key)
	form = g.keptIr.forms.get(m.key) ?? return
	if g.codeLayer(code) > form.layer: return
	kept = form.copy()
	kept.code = code
	g.keptIr.touch(kept.layer)
	g.keptIr.forms[m.key.copy()] = kept
	g.keptIr.codes += 1

# the first layer of the kept forms (keptir.zap) that holds what a code names by name: the types
# of its drops and copies, its functions (an instance's by its generic and types) and its module
# variables; its form's names the rest
fn codeLayer(g Gen, code KeptCode):
	k = g.keptIr
	layer = 0
	for name in code.names:
		if name.startsWith("%"):   # (one of its form's types, "%d@k", its form's layer holds)
			if name[2] != '@': layer = layer.max(k.typeLayer(i64.parse(name[2..]) ?? 0))
		elif name.startsWith("$init:"):
			layer = layer.max(k.nodeLayer(g.globalNode(name[6..])))
		elif g.c.findFunc(name) is d:
			layer = layer.max(k.nodeLayer(i64(d)))
		elif g.c.instances.find(.mangle == name) is gi:
			layer = layer.max(k.nodeLayer(i64(gi.fnDecl)))
			for t in gi.sub.types:
				layer = layer.max(g.partsLayer(t))
	for name in code.globals:
		layer = layer.max(k.nodeLayer(g.globalNode(name)))
	layer

# the code emitted since mark, the noting ended; none when it added to what a kept code cannot
# add to (strings, data addresses, the C library's names, types; descriptors and functions planned
# but by the drops and copies it named, asked again first, when it asked for no float), placed a
# label made before it, or names a label, a data offset or a region it cannot name again
fn keptCodeEnd(mut g Gen, mark KeptCodeMark, mut data i64[], types i64[]) KeptCode?:
	g.codeNoting = false
	g.a.regionsNoting = false
	noted = move g.floatsNoted
	g.floatsNoted = []
	floats = (0..noted.len / 3).map(noted[3 * it])
	lines = move g.linesNoted
	g.linesNoted = []
	asked = move g.a.regionsNoted
	g.a.regionsNoted = []
	typed = move g.labelsNoted
	g.labelsNoted = []
	if g.strOffs.len != mark.strings or g.a.addresses.len != mark.addresses or
		g.a.libcNames.len != mark.libc or g.a.placedBelow.len != mark.placed or
		g.c.types.len != mark.types:
		return none
	tail = g.a.asmTailOf(mark.at)
	labels = g.keptLabelsOf(mark, tail, typed, types) ?? return none
	fixes = []
	imports = []
	globals str[] = []
	for f in mark.fixes..g.a.fixAt.len:
		kind = g.a.fixKind[f]
		target = g.a.fixTarget[f]
		a = 0
		b = 0
		if kind == fxTable:
			a = labels.refOf(target >> 32) ?? return none
			b = labels.refOf(target & 0xFFFF_FFFF) ?? return none
		elif kind == fxImport:
			imports.push("{g.a.importDlls[target]}\t{g.a.imports[target]}")
			a = imports.len - 1
		elif namesData(kind):
			a, b = g.dataRefOf(target, data, floats, globals, mark.stableData) ?? return none
		else:
			a = labels.refOf(target) ?? return none
		fixes.extend([kind, g.a.fixAt[f] - mark.at, g.a.fixJump[f], a, b])
	pads = []
	for p in mark.pads..g.a.padAt.len:
		pads.extend([g.a.padAt[p] - mark.at, g.a.padLen[p]])
	regions = []
	infos = []
	k = 0
	while k < asked.len:
		if asked[k] < mark.at: return none
		kind = asked[k + 1]
		if kind > 0:
			infos.push(g.a.unwindInfos[kind].copy())
			kind = infos.len
		regions.extend([asked[k] - mark.at, kind])
		k += 2
	placedLines = []
	files str[] = []
	fileOf {i64: i64} = {}   # a file of debugFiles -> its place in files
	k = 0
	while k < lines.len:
		at = fileOf.get(lines[k + 3]) ?? -1
		if at < 0:
			files.push(g.debugFiles[lines[k + 3]].copy())
			at = files.len - 1
			fileOf[lines[k + 3]] = at
		placedLines.extend([lines[k] - mark.at, lines[k + 1], lines[k + 2], at])
		k += 4
	tail = labels.tailRefs(tail) ?? return none
	KeptCode(
		bytes = g.a.code[mark.at..].copy(),
		fixes,
		names = labels.names.copy(),
		imports,
		globals,
		floats,
		floatsAfter = (0..floats.len).map(
			labels.madeBefore(noted[3 * it + 2]) if mark.stable >= 0
			else typedBefore(typed, noted[3 * it + 1])
		),
		labels = labels.places.copy(),
		pads,
		regions,
		infos,
		lines = placedLines,
		files,
		line = mark.line,
		col = mark.col,
		file = mark.file.copy(),
		endLine = g.curLine,
		endCol = g.curCol,
		tail
	)

# how many labels the first n drops and copies of typed (label, type, drop) name, each once: the
# code's typed names asked before a float asked after them
fn typedBefore(typed i64[], n i64):
	seen {i64: bool} = {}
	for k in 0..n:
		seen[typed[3 * k]] = true
	seen.len

# a data offset as a kept code names it, by the kind in its two low bits: its form's k-th data
# number (4k; a held code's offsets below stable, added to data as met), the k-th byte of the
# runtime's slots (4k + 1), a float it asked for (4k + 2, the k-th of floats), or bytes into a
# module variable (4k + 3, the k-th of globals; and how many)
fn dataRefOf(
	g Gen,
	off i64,
	mut data i64[],
	floats i64[],
	mut globals str[],
	stable i64
) (i64, i64)?:
	if data.indexOf(off) is k: return (4 * k, 0)
	if off < stable:
		data.push(off)
		return (4 * (data.len - 1), 0)
	if off >= g.globalsOff and off < g.globalsOff + runtimeSlotsBytes:
		return (4 * (off - g.globalsOff) + 1, 0)
	for k, bits in floats:
		if g.floatOffs.get(bits) is at and at == off: return (4 * k + 2, 0)
	if off < bssBase: return none
	name = ""
	start = -1
	for global, at in g.globalOffs:
		if at <= off and at > start:
			name = global.copy()
			start = at
	if start < 0: return none
	k = globals.indexOf(name) ?? -1
	if k < 0:
		globals.push(name.copy())
		k = globals.len - 1
	(4 * k + 3, off - start)

# what a data ref of a kept code names in this program (dataRefOf)
fn dataOfRef(mut g Gen, code KeptCode, at i64, bytes i64, data i64[]):
	k = at >> 2
	kind = at & 3
	if kind == 0: return data[k]
	if kind == 1: return g.globalsOff + k
	if kind == 2: return g.floatConst(code.floats[k])
	return (g.globalOffs.get(code.globals[k]) ?? fail("a kept code's module variable missing")) +
		bytes

# The labels a kept code names: those it made (by their place among them) and the others (by
# name: a function's key, a stub's place).
type KeptLabels:
	floor i64   # the labels made before the code
	own i64[]   # a label past floor: its place among the code's own, -1 one named
	places i64[]   # the code's own labels' places in it, -1 unplaced
	named {i64: i64}   # a label named -> its place in names
	names str[]
	made i64[] = []   # a held code's: the labels it made that names name, in the order made (first)

# the labels the code since mark names, by what they are: those made past mark's and not a
# function's or a stub's, its own; none when it names a function the compiler makes by a name that
# is not the same in every program (a drop, a copy, an environment's) but a drop or copy it asked
# for by type (typed: label, type, drop) of a kept stages' type or of one of its form's types
fn keptLabelsOf(g Gen, mark KeptCodeMark, tail i64[], typed i64[], types i64[]) KeptLabels?:
	wanted {i64: bool} = {}   # (those made before it: its own are named or its own anyway)
	for f in mark.fixes..g.a.fixAt.len:
		target = g.a.fixTarget[f]
		if g.a.fixKind[f] == fxTable:
			if target >> 32 < mark.labels: wanted[target >> 32] = true
			if target & 0xFFFF_FFFF < mark.labels: wanted[target & 0xFFFF_FFFF] = true
		elif not namesData(g.a.fixKind[f]) and target < mark.labels:
			wanted[target] = true
	for l in tailLabels(tail):
		wanted[l] = true
	names = []
	named {i64: i64} = {}
	made = []
	if mark.stable >= 0:
		g.heldNames(mark, typed, wanted, names, named, made)
		return g.ownLabels(mark, move names, move named, move made)
	k = 0
	while k < typed.len:
		if named.get(typed[k]) == none:
			t = typed[k + 1]
			# a type past the kept stages' by its place among its form's (kepttypes.zap)
			shown = "{t}" if t < g.keptIr.types else "@{try types.indexOf(t)}"
			named[typed[k]] = names.len
			names.push("%{"d" if typed[k + 2] == 1 else "c"}{shown}")
		k += 3
	for key, l in g.fnLabels:
		if named.get(l) == none and (wanted.get(l) != none or l >= mark.labels):
			if not stableName(key): return none
			named[l] = names.len
			names.push(key.copy())
	for k, l in g.checkStubs():
		if named.get(l) == none:
			named[l] = names.len
			names.push("#{k}")
	g.ownLabels(mark, move names, move named, move made)

# The names of a held code's labels: those it made that a function's key names, by that key (a
# drop's or a copy's by its type, asked again as typeFnLabel asks), in the order made, then those
# made before it that it names, by their numbers.
fn heldNames(
	g Gen,
	mark KeptCodeMark,
	typed i64[],
	wanted {i64: bool},
	mut names str[],
	mut named {i64: i64},
	mut made i64[]
):
	typedNames {i64: str} = {}
	k = 0
	while k < typed.len:
		typedNames[typed[k]] = "%{"d" if typed[k + 2] == 1 else "c"}{typed[k + 1]}"
		k += 3
	first = g.a.fnMade.len
	while first > 0 and g.a.fnMade[first - 1] >= mark.stable:
		first -= 1
	for k in first..g.a.fnMade.len:
		l = g.a.fnMade[k]
		named[l] = names.len
		names.push((typedNames.get(l) ?? g.a.fnMadeKeys[k]).copy())
		made.push(l)
	for l in wanted.keys().sorted():
		if l >= 0 and l < mark.stable and named.get(l) == none:
			named[l] = names.len
			names.push("@{l}")

# the code's own labels: those made past mark's that no name names
fn ownLabels(
	g Gen,
	mark KeptCodeMark,
	move names str[],
	move named {i64: i64},
	move made i64[]
) KeptLabels:
	own = []
	places = []
	namedOwn = named.keys().filter(it >= mark.labels).sorted()
	next = 0
	for l in mark.labels..g.a.labelPos.len:
		if next < namedOwn.len and namedOwn[next] == l:
			next += 1
			own.push(-1)
			continue
		own.push(places.len)
		at = g.a.labelPos[l]
		places.push(at - mark.at if at >= 0 else -1)
	KeptLabels(floor = mark.labels, own, places, named, names, made)

# how many of the names a held code made were made before the n-th label
fn madeBefore(k KeptLabels, n i64):
	k.made.count(it < n)

# whether a function the compiler makes is named alike in every program that makes it
fn stableName(key str):
	not key.startsWith("$") or key.startsWith("$init:") or
		key in ["$init", "$fini", "$osThreadEntry", "$sigreturn", "$copyClosure", "$dropClosure"]

# label as a kept code names it: -1 none, its own label's place, else -2 - its place in names
fn refOf(k KeptLabels, label i64) i64?:
	if label < 0: return -1
	if label >= k.floor and k.own[label - k.floor] >= 0: return k.own[label - k.floor]
	if k.named.get(label) is n: return -2 - n
	none

# the label a kept code's ref names, its own labels made at first and those it names by name
fn labelOfRef(at i64, own i64[], named i64[]):
	if at == -1: return -1
	own[at] if at >= 0 else named[-2 - at]

# what the label a kept code names by name is in this program
fn namedLabel(mut g Gen, name str, types i64[]):
	if name.startsWith("#"): return g.checkStubs()[i64.parse(name[1..]) ?? 0]
	if name.startsWith("@"): return i64.parse(name[1..]) ?? -1
	if name.startsWith("%"):
		t = types[i64.parse(name[3..]) ?? 0] if name[2] == '@' else i64.parse(name[2..]) ?? 0
		return g.typeFnLabel(TypeId(t), name[1] == 'd')
	return fnLabel(g.fnLabels, g.a, name)

# The code placed at the end of the assembler's code as its emission would write it there: its
# floats and the drops and copies it names asked for again in the order it asked (each may add
# data), its labels made, its fixups, paddings, regions and source lines added at their places,
# the source line and the peephole state left as it left them.
fn placeKeptCode(mut g Gen, code KeptCode, data i64[], types i64[]):
	base = g.a.code.len
	g.a.code.extend(code.bytes)
	named = []
	for k, bits in code.floats:
		while named.len < code.floatsAfter[k]:
			named.push(g.namedLabel(code.names[named.len], types))
		_ = g.floatConst(bits)
	own = []
	for at in code.labels:
		l = g.a.asmNewLabel()
		if at >= 0: g.a.labelPos[l] = base + at
		own.push(l)
	named.extend(code.names[named.len..].map(g.namedLabel(it, types)))
	k = 0
	while k < code.fixes.len:
		kind = code.fixes[k]
		a = code.fixes[k + 3]
		target = 0
		if kind == fxTable:
			label = labelOfRef(a, own, named)
			target = label << 32 | labelOfRef(code.fixes[k + 4], own, named)
			g.a.labelJumps[label] += 1
		elif kind == fxImport:
			words = code.imports[a].split("\t")
			target = g.a.asmImport(words[0], words[1])
		elif namesData(kind):
			target = g.dataOfRef(code, a, code.fixes[k + 4], data)
		else:
			target = labelOfRef(a, own, named)
			if kind == fxLabel: g.a.labelJumps[target] += 1   # (x64's relaxation counts them)
		g.a.fixKind.push(kind)
		g.a.fixAt.push(base + code.fixes[k + 1])
		g.a.fixTarget.push(target)
		g.a.fixJump.push(code.fixes[k + 2])
		k += 5
	k = 0
	while k < code.pads.len:
		g.a.padAt.push(base + code.pads[k])
		g.a.padLen.push(code.pads[k + 1])
		k += 2
	k = 0
	while k < code.regions.len:
		kind = code.regions[k + 1]
		g.a.asmUnwindRegionAt(
			base + code.regions[k],
			g.a.asmUnwindInfo(code.infos[kind - 1]) if kind > 0 else kind
		)
		k += 2
	files = code.files.map(g.debugFile(it))
	k = 0
	while k < code.lines.len:
		g.noteDebugLineAt(
			base + code.lines[k],
			code.lines[k + 1],
			code.lines[k + 2],
			files[code.lines[k + 3]]
		)
		k += 4
	g.curLine = code.endLine
	g.curCol = code.endCol
	g.a.asmTailSet(base, code.tail, own, named)

# ---------- the peephole state at a code's end ----------
# The assembler's fields a peephole reads at the next instruction, by place: the code positions
# (an instruction's end, -1 none, -2 one before the code: left as the code found it), the values
# that go with them, the labels (a jump's target, and those placed at the last jump's end).

tailPlaces = 11
tailValues = 7

fn asmTailOf(a Asm, at i64) i64[]:
	ends = [a.lastStoreEnd, a.lastJmpEnd, a.endJmpEnd, a.lastWidenStart, a.lastWidenEnd,
		a.lastLabelEnd, a.lastRaxFromEnd, a.lastRaxToEnd, a.lastQmovEnd, a.lastXStoreEnd,
		a.lastAddRcxEnd]
	out = ends.map(it - at if it > at else -1 if it == -1 else -2)
	if a.lastLabelEnd == at: out[5] = 0   # its own label's (placed as it is placed again)
	if out[4] >= 0: out[3] = a.lastWidenStart - at
	out.extend([a.lastStoreDisp, a.lastRaxFromReg, a.lastRaxToReg, 1 if a.lastQmovToRax else 0,
		a.lastXStoreDisp, a.lastXStoreReg, a.lastXStorePfx])
	out.extend([a.lastJmpTarget, a.endJmpTarget])
	out.extend(a.endJmpLabels)
	out

# the labels a tail names
fn tailLabels(tail i64[]):
	out = []
	if tail[1] >= 0: out.push(tail[tailPlaces + tailValues])
	if tail[2] >= 0:
		out.push(tail[tailPlaces + tailValues + 1])
		out.extend(tail[tailPlaces + tailValues + 2..])
	out

# a tail with its labels as the kept code names them (refOf); those of a position before the
# code left as they are
fn tailRefs(k KeptLabels, tail i64[]) i64[]?:
	out = tail[..tailPlaces + tailValues].copy()
	at = tailPlaces + tailValues
	if tail[1] >= 0:
		out.push(try k.refOf(tail[at]))
	else:
		out.push(-1)
	if tail[2] < 0:
		out.push(-1)
		return out
	for l in tail[at + 1..]:
		out.push(try k.refOf(l))
	out

# the tail of a code placed at base set in the assembler
fn asmTailSet(mut a Asm, base i64, tail i64[], own i64[], named i64[]):
	ends = (0..tailPlaces).map(tail[it] + base if tail[it] >= 0 else tail[it])
	if ends[0] != -2: a.lastStoreEnd = ends[0]
	if ends[1] != -2: a.lastJmpEnd = ends[1]
	if ends[2] != -2: a.endJmpEnd = ends[2]
	if ends[3] != -2: a.lastWidenStart = ends[3]
	if ends[4] != -2: a.lastWidenEnd = ends[4]
	if ends[5] != -2: a.lastLabelEnd = ends[5]
	if ends[6] != -2: a.lastRaxFromEnd = ends[6]
	if ends[7] != -2: a.lastRaxToEnd = ends[7]
	if ends[8] != -2: a.lastQmovEnd = ends[8]
	if ends[9] != -2: a.lastXStoreEnd = ends[9]
	if ends[10] != -2: a.lastAddRcxEnd = ends[10]
	v = tailPlaces
	a.lastStoreDisp = tail[v]
	a.lastRaxFromReg = tail[v + 1]
	a.lastRaxToReg = tail[v + 2]
	a.lastQmovToRax = tail[v + 3] == 1
	a.lastXStoreDisp = tail[v + 4]
	a.lastXStoreReg = tail[v + 5]
	a.lastXStorePfx = tail[v + 6]
	at = v + tailValues
	if tail[1] >= 0: a.lastJmpTarget = labelOfRef(tail[at], own, named)
	if tail[2] >= 0:
		a.endJmpTarget = labelOfRef(tail[at + 1], own, named)
		a.endJmpLabels = tail[at + 2..].map(labelOfRef(it, own, named))

# ---------- in the kept forms' file ----------

fn pushKeptCode(mut out u8[], code KeptCode):
	out.pushVarint(code.bytes.len)
	out.extend(code.bytes)
	out.pushInts(code.fixes)
	out.pushTexts(code.names)
	out.pushTexts(code.imports)
	out.pushTexts(code.globals)
	out.pushInts(code.floats)
	out.pushInts(code.floatsAfter)
	out.pushInts(code.labels)
	out.pushInts(code.pads)
	out.pushInts(code.regions)
	out.pushVarint(code.infos.len)
	for info in code.infos:
		out.pushInts(info)
	out.pushInts(code.lines)
	out.pushTexts(code.files)
	out.pushInts([code.line, code.col, code.endLine, code.endCol])
	out.pushText(code.file)
	out.pushInts(code.tail)

fn readKeptCode(mut r Reader) KeptCode:
	bytes = r.bytes(r.count())
	fixes = r.readInts()
	names = r.readTexts()
	imports = r.readTexts()
	globals = r.readTexts()
	floats = r.readInts()
	floatsAfter = r.readInts()
	labels = r.readInts()
	pads = r.readInts()
	regions = r.readInts()
	infos i64[,] = []
	loop r.count():
		infos.push(r.readInts())
	lines = r.readInts()
	files = r.readTexts()
	at = r.readInts()
	if at.len != 4: r.short = true
	file = r.readText()
	KeptCode(
		bytes,
		fixes,
		names,
		imports,
		globals,
		floats,
		floatsAfter,
		labels,
		pads,
		regions,
		infos,
		lines,
		files,
		line = at[0] if at.len == 4 else 0,
		col = at[1] if at.len == 4 else 0,
		file,
		endLine = at[2] if at.len == 4 else 0,
		endCol = at[3] if at.len == 4 else 0,
		tail = r.readInts()
	)
