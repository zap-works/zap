# Jumps made short: a jmp or jcc whose label lies within a byte's reach of its end takes the
# two-byte form (EB or 7x and rel8) instead of five or six bytes. Every jump starts short, one that
# does not reach is made long, and the layout is worked out again (each loop top's padding to 32
# bytes too) until none changes. Then the code is written anew and every position in it moved.
# The layout is one scan in order; what is checked against it, written and moved is per item or per
# position and runs on every processor at once.

# the pieces the code is written in, one a job
relaxPieces = 64

# The items of the code whose size may change, in code order: the jumps (their fixup) and the
# paddings.
type RelaxItems:
	start i64[]
	size i64[]   # as emitted
	fix i64[]   # a jump's fixup, -1 for a padding
	long bool[]   # a jump that does not reach short
	target i64[]   # a jump's label's item: the first one starting at or after it
	now i64[]   # each padding's size in the layout being tried
	shift i64[]   # the bytes the items before each one gave up, then all of them
	pads i64[]   # the paddings' items
	seg i64[]   # per item, and one past the last: the paddings before it (its segment)
	local i64[]   # the bytes the jumps before each item in its segment gave up, then all of them
	give i64[]   # per segment (the jumps between two paddings): the bytes its jumps gave up
	base i64[]   # per segment: the bytes the items before it gave up

# a code's jumps and paddings: the jumps' items made at once, the paddings put between them
fn relaxItems(a Asm):
	jumps = (0..a.fixAt.len).parallel().filter(a.fixJump[it] != 0)
	jumpAt = (0..jumps.len).parallel().map(j: i64(a.fixAt[jumps[j]]) - i64(a.fixJump[jumps[j]]))   # the opcode's first byte
	jumpSize = (0..jumps.len).parallel().map(j: 4 + i64(a.fixJump[jumps[j]]))
	before = (0..a.padAt.len).parallel().map(p: jumpAt.countUpTo(a.padAt[p]))
	start i64[] = []
	size i64[] = []
	fix i64[] = []
	pads = []
	start.reserve(jumps.len + a.padAt.len)
	size.reserve(jumps.len + a.padAt.len)
	fix.reserve(jumps.len + a.padAt.len)
	j = 0
	for p in 0..a.padAt.len:
		start.extend(jumpAt[j..before[p]])
		size.extend(jumpSize[j..before[p]])
		fix.extend(jumps[j..before[p]])
		j = before[p]
		pads.push(start.len)
		start.push(a.padAt[p])
		size.push(a.padLen[p])
		fix.push(-1)
	start.extend(jumpAt[j..])
	size.extend(jumpSize[j..])
	fix.extend(jumps[j..])
	n = start.len
	seg = (0..n + 1).parallel().map(i: pads.countBefore(i))
	RelaxItems(
		start,
		size = size.copy(),
		fix,
		long = fill(n, false),
		target = zeros(n),
		now = size,
		shift = zeros(n + 1),
		pads,
		seg,
		local = zeros(n + 1),
		give = zeros(pads.len + 1),
		base = zeros(pads.len + 1)
	)

# how many of the ascending xs are at or before at
fn countUpTo(xs i64[], at i64):
	lo = 0
	hi = xs.len
	while lo < hi:
		mid = (lo + hi) / 2
		if xs[mid] <= at:
			lo = mid + 1
		else:
			hi = mid
	lo

# how many of the ascending xs are before at
fn countBefore(xs i64[], at i64):
	xs.countUpTo(at - 1)

# Jumps made short, the code written again and every position in it moved: the labels, the
# fixups, the regions and the code positions given in moved (each `every`th).
pub fn asmRelax(mut a Asm, mut moved i32[], every i64):
	items = a.relaxItems()
	items.target = (0..items.start.len).parallel().map(i: items.targetItem(a, i))
	items.settle(a)
	a.code = a.relaxedCode(items)
	a.relaxMoved(items, moved, every)

# the jumps that do not reach made long, and the layout worked out again, until none changes
fn settle(mut items RelaxItems, a Asm):
	n = items.start.len
	for k in 0..=items.pads.len:
		items.countGiven(k)
	again = true
	while again:
		items.layOut()
		far = (0..n).parallel().filter(i: items.fix[i] >= 0 and not items.long[i] and
				a.jumpTooFar(items, i))
		again = not far.isEmpty
		for i in far:
			items.long[i] = true
		seen = -1
		for i in far:
			if items.seg[i] != seen:
				seen = items.seg[i]
				items.countGiven(seen)

# the bytes the jumps of segment k give up, and what the jumps before each item gave up in it
fn countGiven(mut items RelaxItems, k i64):
	lo = 0 if k == 0 else items.pads[k - 1] + 1
	hi = items.start.len if k == items.pads.len else items.pads[k]
	given = 0
	for i in lo..hi:
		items.local[i] = given
		if not items.long[i]:
			given += items.size[i] - 2
	items.local[hi] = given
	items.give[k] = given

# each padding's size and the shift before every item, in the layout of the jumps now long: a
# padding depends on every byte before it, so the segments go in order, the items' shifts after
fn layOut(mut items RelaxItems):
	given = 0
	for k in 0..items.pads.len:
		items.base[k] = given
		at = items.start[items.pads[k]] - given - items.give[k]
		now = (32 - at % 32) % 32
		items.now[items.pads[k]] = now
		given += items.give[k] + items.size[items.pads[k]] - now
	items.base[items.pads.len] = given
	items.shift = (0..items.start.len + 1)
		.parallel()
		.map(i: items.base[items.seg[i]] + items.local[i])

# whether the short jump i does not reach its label in the layout
fn jumpTooFar(a Asm, items RelaxItems, i i64):
	d = items.shortDistance(a, i)
	d < -128 or d > 127

# the distance the short jump i spans in the layout, from its end to its label
fn shortDistance(items RelaxItems, a Asm, i i64):
	to = a.labelPos[a.fixTarget[items.fix[i]]] - items.shift[items.target[i]]
	to - (items.start[i] - items.shift[i] + 2)

# the code written again, in pieces of items made at once
fn relaxedCode(a Asm, items RelaxItems):
	n = items.start.len
	parts = n.min(relaxPieces).max(1)
	pieces = (0..parts).parallel().map(k: a.relaxedPiece(items, k * n / parts, (k + 1) * n / parts))
	code u8[] = []
	code.reserve(a.code.len - items.shift[n])
	for piece in pieces:
		code.extend(piece)
	code

# the code of the items from i0 up to i1 and of the bytes before each (the last piece's too, after
# its last item)
fn relaxedPiece(a Asm, items RelaxItems, i0 i64, i1 i64):
	code = []
	from = 0 if i0 == 0 else items.start[i0 - 1] + items.size[i0 - 1]
	for i in i0..i1:
		start = items.start[i]
		code.extend(a.code[from..start])
		from = start + items.size[i]
		if items.fix[i] < 0:
			nopsInto(code, items.now[i])
		elif items.long[i]:
			code.extend(a.code[start..from])
		else:
			code.push(0xEB if a.fixJump[items.fix[i]] == 1 else 0x70 | (a.code[start + 1] & 15))
			code.push(u8.wrap(items.shortDistance(a, i)))
	if i1 == items.start.len:
		code.extend(a.code[from..])
	code

# every position moved; the short jumps' fixups gone
fn relaxMoved(mut a Asm, items RelaxItems, mut moved i32[], every i64):
	a.labelPos = items.movedAll(a.labelPos)
	fixesAt = items.movedAll(a.fixAt)
	short = fill(a.fixAt.len, false)
	for i in (0..items.start.len).parallel().filter(items.fix[it] >= 0 and not items.long[it]):
		short[items.fix[i]] = true
	a.keepFixups((0..a.fixAt.len).parallel().filter(not short[it]), fixesAt)
	unwindAt = (0..a.unwindAt.len).parallel().map(r: items.movedTo(a.unwindAt[r]))
	a.unwindAt = unwindAt
	movedAt = (0..(moved.len + every - 1) / every)
		.parallel()
		.map(k: items.movedTo(moved[k * every]))
	for k in 0..movedAt.len:
		moved[k * every] = i32(movedAt[k])
	a.padAt.clear()
	a.padLen.clear()

# where code position at went: past the bytes the items before it gave up (an item starting at
# it is after it)
fn movedTo(items RelaxItems, at i64):
	at - items.shift[items.firstAtOrAfter(at)]

# the code positions moved (the unknown ones, negative, as they are), in pieces on every processor
fn movedAll(items RelaxItems, at i32[]):
	parts = (at.len / 4096).min(relaxPieces).max(1)
	pieces = (0..parts)
		.parallel()
		.map(k: items.movedPiece(at, k * at.len / parts, (k + 1) * at.len / parts))
	out i32[] = []
	out.reserve(at.len)
	for piece in pieces:
		out.extend(piece)
	out

# the positions from i0 up to i1 moved: the item each lies before found from the last one's when it
# is near (the positions mostly rise), else by search
fn movedPiece(items RelaxItems, at i32[], i0 i64, i1 i64):
	out i32[] = []
	out.reserve(i1 - i0)
	lo = 0
	for i in i0..i1:
		x = at[i]
		if x < 0:
			out.push(x)
			continue
		steps = 0
		if lo > 0 and items.start[lo - 1] >= x:
			lo = items.firstAtOrAfter(x)
		while lo < items.start.len and items.start[lo] < x and steps < 8:
			lo += 1
			steps += 1
		if lo < items.start.len and items.start[lo] < x:
			lo = items.firstAtOrAfter(x)
		out.push(i32(x - items.shift[lo]))
	out

# the first item starting at or after the code position at (binary search)
fn firstAtOrAfter(items RelaxItems, at i64):
	lo = 0
	hi = items.start.len
	while lo < hi:
		mid = (lo + hi) / 2
		if items.start[mid] < at:
			lo = mid + 1
		else:
			hi = mid
	lo

# the item a jump's label lies at (0 for a padding, which has none)
fn targetItem(items RelaxItems, a Asm, i i64):
	if items.fix[i] < 0: return 0
	items.firstAtOrAfter(a.labelPos[a.fixTarget[items.fix[i]]])
