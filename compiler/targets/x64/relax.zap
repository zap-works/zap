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
	now i64[]   # each item's size in the layout being tried
	shift i64[]   # the bytes the items before each one gave up, then all of them

# a code's jumps and paddings
fn relaxItems(a Asm):
	start = []
	size = []
	fix = []
	p = 0
	for f in 0..a.fixAt.len:
		if a.fixJump[f] == 0: continue
		at = a.fixAt[f] - a.fixJump[f]   # the opcode's first byte
		while p < a.padAt.len and a.padAt[p] < at:
			start.push(a.padAt[p])
			size.push(a.padLen[p])
			fix.push(-1)
			p += 1
		start.push(at)
		size.push(4 + a.fixJump[f])
		fix.push(f)
	while p < a.padAt.len:
		start.push(a.padAt[p])
		size.push(a.padLen[p])
		fix.push(-1)
		p += 1
	n = start.len
	RelaxItems(
		start,
		size = size.copy(),
		fix,
		long = fill(n, false),
		now = size,
		shift = zeros(n + 1)
	)

# Jumps made short, the code written again and every position in it moved: the labels, the
# fixups, the regions and the code positions given in moved (each `every`th).
pub fn asmRelax(mut a Asm, mut moved i32[], every i64):
	items = a.relaxItems()
	items.settle(a)
	a.code = a.relaxedCode(items)
	a.relaxMoved(items, moved, every)

# the jumps that do not reach made long, and the layout worked out again, until none changes
fn settle(mut items RelaxItems, a Asm):
	n = items.start.len
	again = true
	while again:
		again = false
		items.layOut()
		far = (0..n).parallel().map(i: items.fix[i] >= 0 and not items.long[i] and
				a.jumpTooFar(items, i))
		for i in 0..n:
			if far[i]:
				items.long[i] = true
				again = true

# each item's size and the shift before it, in the layout of the jumps now long
fn layOut(mut items RelaxItems):
	for i in 0..items.start.len:
		if items.fix[i] < 0:
			at = items.start[i] - items.shift[i]
			items.now[i] = (32 - at % 32) % 32
		else:
			items.now[i] = items.size[i] if items.long[i] else 2
		items.shift[i + 1] = items.shift[i] + items.size[i] - items.now[i]

# whether the short jump i does not reach its label in the layout
fn jumpTooFar(a Asm, items RelaxItems, i i64):
	d = items.shortDistance(a, i)
	d < -128 or d > 127

# the distance the short jump i spans in the layout, from its end to its label
fn shortDistance(items RelaxItems, a Asm, i i64):
	to = items.movedTo(a.labelPos[a.fixTarget[items.fix[i]]])
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
	labelsAt = (0..a.labelPos.len).parallel().map(l: i32(
		items.movedTo(a.labelPos[l]) if a.labelPos[l] >= 0 else a.labelPos[l]
	))
	a.labelPos = labelsAt
	fixesAt = (0..a.fixAt.len).parallel().map(f: items.movedTo(a.fixAt[f]))
	kept = 0
	item = 0
	for f in 0..a.fixAt.len:
		if a.fixJump[f] != 0:
			while items.fix[item] != f:
				item += 1
			if not items.long[item]: continue
		a.fixKind[kept] = a.fixKind[f]
		a.fixAt[kept] = i32(fixesAt[f])
		a.fixTarget[kept] = a.fixTarget[f]
		a.fixJump[kept] = a.fixJump[f]
		kept += 1
	a.fixKind.truncate(kept)
	a.fixAt.truncate(kept)
	a.fixTarget.truncate(kept)
	a.fixJump.truncate(kept)
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
	# the items starting before at: binary search
	lo = 0
	hi = items.start.len
	while lo < hi:
		mid = (lo + hi) / 2
		if items.start[mid] < at:
			lo = mid + 1
		else:
			hi = mid
	at - items.shift[lo]
