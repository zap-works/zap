# Identical functions merged, as LLVM's MergeFunctions does: the instances of a generic that the
# types do not change, the drops and copies of types laid out alike. Two functions are the same
# when their bytes are, the labels, data and imports they name outside themselves are, and so are
# their jump tables, loop paddings, unwind regions and source lines, each at the same place (the
# paddings' bytes left out: asmRelax pads every loop top again). A caller is emitted before what
# it calls, so the functions are compared once all are emitted, in rounds (a merge makes their
# callers the same) until none is merged; each merged one's code is then taken out, its label
# made the one it became's.

# The code of one function in the assembler's lists: where each of them stood when it began and
# where it ended.
type CodeRange:
	label i64 = -1   # its own label
	floor i64   # the labels made before it: one it places past that is its own (but its label)
	at i64   # its first byte
	end i64 = -1
	fixes i64
	fixEnd i64 = -1
	pads i64
	padEnd i64 = -1
	regions i64   # (a region at its first byte from before it, empty, is its)
	regionEnd i64 = -1
	lines i64   # (the same of a source line note)
	lineEnd i64 = -1

# a function's code begins here (before its label is placed)
fn beginFunction(mut g Gen):
	if g.emitting > 0:
		g.nested = true
	g.emitting += 1
	at = g.a.code.len
	lines = g.debugLines.len
	if lines >= 4 and g.debugLines[lines - 4] == at:
		lines -= 4
	regions = g.a.unwindAt.len
	if regions > 0 and g.a.unwindAt[regions - 1] == at:
		regions -= 1
	g.a.labelFloor = g.a.labelPos.len
	g.a.placedBelow = []
	CodeRange(
		floor = g.a.labelPos.len,
		at,
		fixes = g.a.fixAt.len,
		pads = g.a.padAt.len,
		regions,
		lines
	)

# The function key's code ends here: kept to be compared when nothing outside it may name a place
# in it and nothing falls into it. Code that falls into it is no longer whole.
fn endFunction(mut g Gen, key str, mut r CodeRange):
	g.emitting -= 1
	nested = g.nested
	if g.emitting == 0:
		g.nested = false
	g.a.labelFloor = 0
	if nested: return
	r.label = g.fnLabels.get(key) ?? return
	placed = g.a.labelPos[r.label]
	while placed < r.at and (g.emitted.last ?? return).end > placed:
		g.emitted.pop()   # the jump at its end dropped: it falls into this one
	if placed != r.at or g.a.placedBelow.len != (1 if r.label < r.floor else 0): return
	r.end = g.a.code.len
	r.fixEnd = g.a.fixAt.len
	r.padEnd = g.a.padAt.len
	r.regionEnd = g.a.unwindAt.len
	r.lineEnd = g.debugLines.len
	g.emitted.push(r)

# the functions emitted merged in rounds, then the merged ones' code taken out. A function's
# signature is made again only when a label it names merged since it was made (seen through the
# labels each merge passes), so it is the one the round would make of it then.
fn mergeSameCode(mut g Gen):
	n = g.emitted.len
	signatures = fill(n, "")
	hashes = fill(n, 0)
	names i64[,] = fill(n, [])
	madeAt = fill(n, -1)   # the merges made before each signature was
	mergedAt {i64: i64} = {}   # a merged label -> the merges made before it
	merged = true
	while merged:
		merged = false
		firstBy {i64: i64} = {}   # a signature's hash -> the first function with it
		for i in 0..n:
			if g.emitted[i].label in g.mergedInto: continue
			g.signatureNow(i, mergedAt, signatures, hashes, names, madeAt)
			match firstBy.get(hashes[i]):
				first:
					g.signatureNow(first, mergedAt, signatures, hashes, names, madeAt)
					if signatures[first] == signatures[i]:
						g.mergedInto[g.emitted[i].label] = g.emitted[first].label
						mergedAt[g.emitted[i].label] = mergedAt.len
						merged = true
				none:
					firstBy[hashes[i]] = i
	if g.mergedInto.isEmpty: return
	g.removeCode(g.emitted.filter(.label in g.mergedInto))
	for label in g.mergedInto.keys():
		g.a.labelPos[label] = g.a.labelPos[g.survivor(label)]

# function i's signature made again when it has none or a label it names (or one that label
# became) merged since it was made
fn signatureNow(
	g Gen,
	i i64,
	mergedAt {i64: i64},
	mut signatures str[],
	mut hashes i64[],
	mut names i64[,],
	mut madeAt i64[]
):
	if madeAt[i] >= 0 and not names[i].any(g.mergedSince(it, mergedAt, madeAt[i])): return
	named = []
	signatures[i] = g.codeSignature(g.emitted[i], named)
	hashes[i] = signatures[i].hash()
	names[i] = named
	madeAt[i] = mergedAt.len

# whether label, or one it became, merged after the first `since` merges
fn mergedSince(g Gen, label i64, mergedAt {i64: i64}, since i64):
	at = label
	while mergedAt.get(at) is k:
		if k >= since: return true
		at = g.mergedInto[at]
	false

# the function a merged one's label became (through the rounds), or the label itself
fn survivor(g Gen, label i64):
	at = label
	while g.mergedInto.get(at) is into:
		at = into
	at

# The code of r as two functions compare: its bytes but the paddings', then each fixup, padding,
# region and source line by its place in those bytes. A label is named by its place when r placed
# it, else by its own number (a merged function's by the one it became's).
fn codeSignature(g Gen, r CodeRange, mut named i64[]) str:
	out = []
	from = r.at
	for p in r.pads..r.padEnd:
		out.extend(g.a.code[from..g.a.padAt[p]])
		from = g.a.padAt[p] + g.a.padLen[p]
	out.extend(g.a.code[from..r.end])
	bytesPut64(out, r.fixEnd - r.fixes)
	for f in r.fixes..r.fixEnd:
		kind = g.a.fixKind[f]
		target = g.a.fixTarget[f]
		bytesPut64(out, kind)
		bytesPut64(out, g.placeIn(r, g.a.fixAt[f]))
		if kind == fxTable:
			bytesPut64(out, g.labelIn(r, named, target >> 32))
			bytesPut64(out, g.labelIn(r, named, target & 0xFFFF_FFFF))
		elif namesData(kind):
			bytesPut64(out, target)
		else:
			bytesPut64(out, g.labelIn(r, named, target))
	bytesPut64(out, r.padEnd - r.pads)
	for p in r.pads..r.padEnd:
		bytesPut64(out, g.placeIn(r, g.a.padAt[p]))
	bytesPut64(out, r.regionEnd - r.regions)
	for k in r.regions..r.regionEnd:
		bytesPut64(out, g.placeIn(r, g.a.unwindAt[k]))
		bytesPut64(out, g.a.unwindKind[k])
	k = r.lines
	while k < r.lineEnd:
		bytesPut64(out, g.placeIn(r, g.debugLines[k]))
		for i in 1..4:
			bytesPut64(out, g.debugLines[k + i])
		k += 4
	str(move out)

# the code position at as an offset into r's bytes without its paddings
fn placeIn(g Gen, r CodeRange, at i64):
	before = 0
	for p in r.pads..r.padEnd:
		if g.a.padAt[p] < at:
			before += g.a.padLen[p]
	at - r.at - before

# a label r names: its place in r (negative) when r placed it, else its number (noted in named)
fn labelIn(g Gen, r CodeRange, mut named i64[], label i64):
	at = g.a.labelPos[label]
	if label == r.label or label >= r.floor and at >= r.at and at < r.end:
		return -1 - g.placeIn(r, at)
	named.push(label)
	g.survivor(label)

# The code of the functions gone (in code order) taken out: the bytes, and the fixups, paddings,
# regions and source lines in it; every position after moved back by the bytes before it gone
# (one in a gone function's code to where it was).
fn removeCode(mut g Gen, gone CodeRange[]):
	cut = [0]   # the bytes of the gone functions before each one, then of all
	for r in gone:
		cut.push((cut.last ?? 0) + r.end - r.at)
	code u8[] = []
	code.reserve(g.a.code.len - (cut.last ?? 0))
	from = 0
	for r in gone:
		code.extend(g.a.code[from..r.at])
		from = r.end
	code.extend(g.a.code[from..])
	g.a.code = move code
	kept = 0
	for f in 0..g.a.fixAt.len:
		if removedAt(gone, g.a.fixAt[f]):
			kind = g.a.fixKind[f]
			if kind == fxTable:
				g.a.labelJumps[g.a.fixTarget[f] >> 32] -= 1
			elif kind == fxLabel:
				g.a.labelJumps[g.a.fixTarget[f]] -= 1
			continue
		g.a.fixKind[kept] = g.a.fixKind[f]
		g.a.fixAt[kept] = i32(movedBack(gone, cut, g.a.fixAt[f]))
		g.a.fixTarget[kept] = g.a.fixTarget[f]
		g.a.fixJump[kept] = g.a.fixJump[f]
		kept += 1
	g.a.fixKind.truncate(kept)
	g.a.fixAt.truncate(kept)
	g.a.fixTarget.truncate(kept)
	g.a.fixJump.truncate(kept)
	for l in 0..g.a.labelPos.len:
		if g.a.labelPos[l] >= 0:
			g.a.labelPos[l] = i32(movedBack(gone, cut, g.a.labelPos[l]))
	kept = 0
	for p in 0..g.a.padAt.len:
		if not removedAt(gone, g.a.padAt[p]):
			g.a.padAt[kept] = movedBack(gone, cut, g.a.padAt[p])
			g.a.padLen[kept] = g.a.padLen[p]
			kept += 1
	g.a.padAt.truncate(kept)
	g.a.padLen.truncate(kept)
	kept = 0
	for k in 0..g.a.unwindAt.len:
		if not removedAt(gone, g.a.unwindAt[k]):
			g.a.unwindAt[kept] = movedBack(gone, cut, g.a.unwindAt[k])
			g.a.unwindKind[kept] = g.a.unwindKind[k]
			kept += 1
	g.a.unwindAt.truncate(kept)
	g.a.unwindKind.truncate(kept)
	kept = 0
	k = 0
	while k < g.debugLines.len:
		if not removedAt(gone, g.debugLines[k]):
			g.debugLines[kept] = i32(movedBack(gone, cut, g.debugLines[k]))
			for i in 1..4:
				g.debugLines[kept + i] = g.debugLines[k + i]
			kept += 4
		k += 4
	g.debugLines.truncate(kept)

# the last gone function that starts at or before the code position at, or -1
fn goneBefore(gone CodeRange[], at i64):
	lo = 0
	hi = gone.len
	while lo < hi:
		mid = (lo + hi) / 2
		if gone[mid].at <= at:
			lo = mid + 1
		else:
			hi = mid
	lo - 1

# whether the code position at is in a gone function's code
fn removedAt(gone CodeRange[], at i64):
	k = goneBefore(gone, at)
	k >= 0 and at < gone[k].end

# where the code position at goes once the gone functions are taken out
fn movedBack(gone CodeRange[], cut i64[], at i64):
	k = goneBefore(gone, at)
	if k < 0: return at
	if at < gone[k].end: return gone[k].at - cut[k]
	at - cut[k + 1]

# whether a fixup of the kind names a place in the data (or an import), not a label
fn namesData(kind i64):
	kind in [fxData, fxImport, fxA64Page, fxA64Low] or
		kind == fxA64LowLoad
