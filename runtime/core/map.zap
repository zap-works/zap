# Maps: a {K: V} value is the address of a heap-allocated MapTable<K, V>: an open-addressing
# table of cells, each a key next to its value, with a byte a cell beside them (as Swiss tables
# do): 0 empty, 1 removed, else 128 and the hash's top seven bits. A probe reads the bytes, which
# stay in the cache, and a cell only when its byte matches. A removed cell is left marked until
# the next rehash. Keys are integers or strings: anything with hash() and ==. An empty cell is
# zero, which owns nothing: the cells drop as a list. A map keeps no order: it is walked in the
# order of its cells, the same for the same keys added the same way.

pub type MapCell<K, V>:
	key K
	val V

# what a {K: V} points to
pub type MapTable<K, V>:
	cells MapCell<K, V>[]
	marks u8[]   # each cell's byte
	used i64   # cells marked: live and removed
	live i64

# an empty map
pub fn mapNew<K Hash, V>() {K: V}:
	probe K[] = []
	if __window(__zeroElem(probe)) == 1:
		tt = TextTable<V>(   # keys of text windows: textmap.zap
			cells = [],
			marks = [],
			used = 0,
			live = 0,
			base = 0,
			near = [],
			far = [],
			wide = false
		)
		q = rtAlloc(__sizeof(tt))
		__poke(q, tt)
		return __cast(q)
	t = MapTable<K, V>(cells = [], marks = [], used = 0, live = 0)
	p = rtAlloc(__sizeof(t))
	__poke(p, t)
	__cast(p)

# the table a map points to: the one place a map's word is read as an address
fn table<K Hash, V>(m {K: V}) mut ref MapTable<K, V>:
	__cast(__ld64(__addr(m)))

# a cell's byte for a key of hash h: 128 and the low seven bits (the probe starts from the high
# ones: homeOf)
fn markOf(h i64) i64:
	128 | (h & 127)

# The table's size is any number of cells from 16 up, not only a power of two: it is rebuilt past
# 7/8 use, half again as large, so it holds its keys in less memory (a large one's misses are
# fewer). A probe starts at the cell the hash's high 32 bits scale to the size, and goes on in
# order, round past the last cell to the first.

# the cell a probe for hash h starts at, among n cells (below n: the scaled bits' product wraps
# past 2^64 only for a table of over 2^32 cells, and stays below 2^32 then)
fn homeOf(h i64, n i64) i64:
	i64(((u64(h) >> 32) * u64(n)) >> 32)

# the cell after s of n, round past the last
fn nextCell(s i64, n i64) i64:
	0 if s + 1 == n else s + 1

# the size a table of n cells, used of them marked and live of them holding keys, is rebuilt at
# to take one key more: the same when removals left it at most 3/4 live (a map that churns keys
# stays its size), half again as large otherwise (and as many times as it takes); 0 when it
# takes one more as it is
fn grownSize(n i64, used i64, live i64) i64:
	if (used + 1) * 8 <= n * 7: return 0
	ns = n if (live + 1) * 4 <= n * 3 else n + n / 2
	ns = ns.max(16)
	while (live + 1) * 8 > ns * 7:
		ns += ns / 2
	ns

# n empty cells, and their bytes
fn emptyCells<K Hash, V>(mut t MapTable<K, V>, n i64):
	growZeroed(t.cells, n)
	t.marks = emptyMarks(n)

groupWidth = 16   # the bytes a probe reads at once

# n cells' bytes, all empty, then for a group read over the end the first groupWidth bytes
# again, which setMark keeps (a table has at least that many cells): elements of the list, so
# that a copy of the map keeps them
fn emptyMarks(n i64) u8[]:
	zeros(n + groupWidth)

# the cells a table's bytes stand for (the copy of the first group's after them)
fn cellsOf(marks u8[]) i64:
	(marks.len - groupWidth).max(0)

# cell s's byte made b, and its copy past the end
fn setMark(mut marks u8[], s i64, b i64):
	marks[s] = u8(b)
	if s < groupWidth:
		marks[cellsOf(marks) + s] = u8(b)

# A probe reads the bytes sixteen at a time (as Swiss tables do), from the key's cell on: the
# cells whose byte is the key's are compared, lowest first, and a group with an empty byte ends
# it (the table is at most 7/8 used, so one always does). The branches a probe takes are then the
# same for most keys, so the misses of one lookup overlap the next one's. A group read over the
# end reads the copy of the first bytes there.

# the cell holding key (whose hash is h), or -1 (the probe's numbers unsigned: they wrap, unchecked)
fn findCell<K Hash, V>(t MapTable<K, V>, key K, h i64) i64:
	n = cellsOf(t.marks)
	if n == 0: return -1
	marks = u64(__ld64(__addr(t.marks)))
	size = u64(n)
	pat = Simd<16>(u8(markOf(h)))
	s = u64(homeOf(h, n))
	# the first cell the key may be in fetched while its bytes are read: in a large table the two
	# misses overlap
	__prefetch(i64(u64(__ld64(__addr(t.cells))) + s * u64(__stride(__zeroElem(t.cells)))))
	while true:
		group = __peek(i64(marks + s), pat)
		hits = u64(group.eqMask(pat))
		while hits != 0:
			c = s + u64(hits.trailingZeros())
			if c >= size: c -= size
			if __at(t.cells, i64(c)).key == key: return i64(c)
			hits &= hits - 1
		if group.eqMask(Simd<16>(u8(0))) != 0: return -1
		s += u64(groupWidth)
		if s >= size: s -= size
	-1

# the first empty cell of the probe of hash h among a table's marks (a text table's too)
fn freeCell(marks u8[], h i64) i64:
	p = u64(__ld64(__addr(marks)))
	size = u64(cellsOf(marks))
	zero = Simd<16>(u8(0))
	s = u64(homeOf(h, cellsOf(marks)))
	while true:
		empty = u64(__peek(i64(p + s), zero).eqMask(zero))
		if empty != 0:
			c = s + u64(empty.trailingZeros())
			return i64(c - size if c >= size else c)
		s += u64(groupWidth)
		if s >= size: s -= size
	-1

# the first cell of the probe of hash h among a table's marks that holds no key: empty, or removed
# (a key put there is found as well, as the probes that met it went on past it), so a map that
# removes and adds keys takes its removed cells again (as Swiss tables do)
fn openCell(marks u8[], h i64) i64:
	p = u64(__ld64(__addr(marks)))
	size = u64(cellsOf(marks))
	zero = Simd<16>(u8(0))
	one = Simd<16>(u8(1))
	s = u64(homeOf(h, cellsOf(marks)))
	while true:
		group = __peek(i64(p + s), zero)
		open = u64(group.eqMask(zero) | group.eqMask(one))
		if open != 0:
			c = s + u64(open.trailingZeros())
			return i64(c - size if c >= size else c)
		s += u64(groupWidth)
		if s >= size: s -= size
	-1

# The live cells placed again in a table of n cells (each key's hash made again), in the cells'
# own list grown in place, so the old table and the new are never both held. A cell still to
# place is one marked live in the old bytes and not yet in the new: a key that meets one on its
# probe takes its place, and that one is placed next.
fn rehash<K Hash, V>(mut t MapTable<K, V>, n i64):
	pending = move t.marks   # the old bytes
	was = cellsOf(pending)
	growZeroed(t.cells, n)
	t.marks = emptyMarks(n)
	for i in 0..was:
		if pending[i] < 128 or t.marks[i] != 0: continue
		pending[i] = 0
		cur = move t.cells[i]
		placing = true
		while placing:
			h = cur.key.hash()
			s = freeCell(t.marks, h)
			setMark(t.marks, s, markOf(h))
			if s < was and pending[s] >= 128:
				pending[s] = 0   # its key is placed next
				next = move t.cells[s]
				t.cells[s] = move cur
				cur = move next
			else:
				t.cells[s] = move cur
				placing = false
	t.used = t.live

# a new cell for a key that is not in the table, the table rebuilt first when it is full
# (grownSize)
fn addCell<K Hash, V>(mut t MapTable<K, V>, move key K, move val V, h i64) i64:
	ns = grownSize(cellsOf(t.marks), t.used, t.live)
	if ns > 0:
		rehash(t, ns)
	s = openCell(t.marks, h)
	if t.marks[s] == 0:
		t.used += 1   # (a removed cell taken again was counted)
	setMark(t.marks, s, markOf(h))
	t.cells[s] = MapCell<K, V>(key = key, val = val)
	t.live += 1
	s

# m[k] = v: stores v under k (both move in), replacing what was there
fn mapSet<K Hash, V>(mut m {K: V}, move key K, move val V):
	if __window(key) == 1:
		tt = textTable(m)
		p = __ld64(__addr(key))
		length = __ld64(__addr(key) + 8)
		kw = textWord(p, length)
		hh = textHash(p, length, kw)
		at = textFind(tt, p, length, kw, hh)
		if at >= 0:
			tt.cells[at].val = val
		else:
			_ = textAdd(tt, p, length, kw, val, hh)
		return
	t = table(m)
	h = key.hash()
	s = findCell(t, key, h)
	if s >= 0:
		t.cells[s].val = val
		return
	_ = addCell(t, key, val, h)

# the number in cell s (one a probe found: it lies in the table) grows by delta, read and written
# where it is: past the key, at a multiple of its size (a number's size is its alignment); the
# address's numbers unsigned (they wrap, unchecked)
fn addInCell<K Hash, V Num>(mut t MapTable<K, V>, s i64, key K, delta V):
	at = i64(
		u64(__ld64(__addr(t.cells))) + u64(s) * u64(__stride(__zeroElem(t.cells))) +
			u64(valueOffset(key, delta))
	)
	__poke(at, __peek(at, delta) + delta)

# where a cell's value lies in it: past the key, at a multiple of its size (a number's size is
# its alignment)
fn valueOffset<K, V>(key K, val V) i64:
	(__sizeof(key) + __sizeof(val) - 1) / __sizeof(val) * __sizeof(val)

# m.add(key, delta): the number at the key grows by delta, from zero when the key is new
# (the key is only read: it is copied when it enters the table)
pub fn mapAdd<K Hash, V Num>(mut m {K: V}, key K, delta V):
	if __window(key) == 1:
		mapAddText(m, key, delta)
		return
	t = table(m)
	h = key.hash()
	s = findCell(t, key, h)
	if s >= 0:
		addInCell(t, s, key, delta)
		return
	_ = addCell(t, key.copy(), delta, h)

# m.add(key, delta) of a text key (str or a window): the hash, the probe and the comparison of
# the key's bytes all here, with no call on the way to an existing key
pub fn mapAddText<K Hash, V Num>(mut m {K: V}, key K, delta V):
	if __window(key) == 1:
		# a window key (textmap.zap): one word compared per cell for a key of up to 6 bytes
		t = textTable(m)
		p = __ld64(__addr(key))
		length = __ld64(__addr(key) + 8)
		kw = textWord(p, length)
		h = textHash(p, length, kw)
		s = textFind(t, p, length, kw, h)
		if s >= 0:
			t.cells[s].val += delta
		else:
			_ = textAdd(t, p, length, kw, delta, h)
		return
	t = table(m)
	p = textPtrAt(__addr(key))
	length = textLenAt(__addr(key))
	h u64 = u64(bytesHash(p, length))
	n = cellsOf(t.marks)
	if n > 0:
		marks = __ld64(__addr(t.marks))
		cells = __ld64(__addr(t.cells))
		stride = __stride(__zeroElem(t.cells))
		mk = markOf(i64(h))
		s = homeOf(i64(h), n)
		cm = __ld8(marks + s)
		while cm != 0:
			c = cells + s * stride   # the cell: its key's header first
			if cm == mk and textLenAt(c) == length:
				if sameBytes(textPtrAt(c), p, length):
					t.cells[s].val += delta
					return
			s = nextCell(s, n)
			cm = __ld8(marks + s)
	_ = addCell(t, key.copy(), delta, i64(h))

# the cell of key in m (in its text table when key is a text window), or -1
fn cellOf<K Hash, V>(m {K: V}, key K) i64:
	if __window(key) == 1: return textCell(m, key)
	findCell(table(m), key, key.hash())

# the value of cell s (cellOf's; text when the key is a window)
fn valueAt<K Hash, V>(m {K: V}, text bool, s i64) ref V:
	if text:
		tt = textTable(m)
		return tt.cells[s].val
	t = table(m)
	t.cells[s].val

# the value of cell s to change in place
fn placeAt<K Hash, V>(mut m {K: V}, text bool, s i64) mut ref V:
	if text:
		tt = textTable(m)
		place = mut ref tt.cells[s].val
		return place
	t = table(m)
	found = mut ref t.cells[s].val
	found

# m.get(k): the value under k, borrowed; none when absent
pub fn mapGet<K Hash, V>(m {K: V}, key K) ref V?:
	s = cellOf(m, key)
	if s < 0: return none
	valueAt(m, __window(key) == 1, s)

# m.get(k) where the program changes what it gives (`match m.get(k) { v => v.n += 1 }`): the
# value under k to change in place; none when absent. While it is held the map gains and loses
# no keys (the table may move its values)
pub fn mapGetMut<K Hash, V>(mut m {K: V}, key K) mut ref V?:
	s = cellOf(m, key)
	if s < 0: return none
	placeAt(m, __window(key) == 1, s)

# m[k]: the value under k; the program stops when k is not a key
pub fn mapIndex<K Hash, V>(m {K: V}, key K) ref V:
	s = cellOf(m, key)
	if s < 0:
		fail("the key is not in the map")
	valueAt(m, __window(key) == 1, s)

# m[k] where it changes (`m[k].hits += 1`): the value under k, changed in place; the program
# stops when k is not a key
pub fn mapIndexMut<K Hash, V>(mut m {K: V}, key K) mut ref V:
	s = cellOf(m, key)
	if s < 0:
		fail("the key is not in the map")
	placeAt(m, __window(key) == 1, s)

# k in m: whether k is a key
fn mapHas<K Hash, V>(m {K: V}, key K) bool:
	if __window(key) == 1: return textCell(m, key) >= 0
	findCell(table(m), key, key.hash()) >= 0

# m.remove(k): takes the value under k out of the map; none when absent
pub fn mapRemove<K Hash, V>(mut m {K: V}, key K) V?:
	if __window(key) == 1:
		at = textCell(m, key)
		if at < 0: return none
		tt = textTable(m)
		setMark(tt.marks, at, 1)
		tt.live -= 1
		return move tt.cells[at].val
	t = table(m)
	s = findCell(t, key, key.hash())
	if s < 0: return none
	__drop(t.cells[s].key)   # the key goes, its bytes zero (a dead cell owns nothing)
	__memset(__addr(t.cells[s]), 0, __sizeof(t.cells[s].key))
	setMark(t.marks, s, 1)
	t.live -= 1
	move t.cells[s].val

# the cells a table made to hold n keys takes, from its size now: them at 3/4 use at most (one half
# again as large each time, as grownSize), the room the removed marks of a map that churns keys
# take before it is rebuilt
fn sizeFor(now i64, n i64) i64:
	ns = now.max(16)
	while n * 4 > ns * 3:
		ns += ns / 2
	ns

# m.reserve(n): room for n keys made at once, so a map that is to hold that many is not rebuilt on
# the way (Rust's with_capacity)
pub fn mapReserve<K Hash, V>(mut m {K: V}, n i64):
	probe K[] = []
	if __window(__zeroElem(probe)) == 1:
		tt = textTable(m)
		ns = sizeFor(cellsOf(tt.marks), n)
		if ns > cellsOf(tt.marks): textRehash(tt, ns)
		return
	t = table(m)
	ns = sizeFor(cellsOf(t.marks), n)
	if ns > cellsOf(t.marks): rehash(t, ns)

# m.clear(): removes every entry
pub fn mapClear<K Hash, V>(mut m {K: V}):
	probe K[] = []
	if __window(__zeroElem(probe)) == 1:
		tt = textTable(m)
		n = cellsOf(tt.marks)
		tt.cells.clear()
		tt.near.clear()
		tt.far.clear()
		textEmpty(tt, n)
		tt.used = 0
		tt.live = 0
		return
	t = table(m)
	n = cellsOf(t.marks)
	t.cells.clear()
	emptyCells(t, n)
	t.used = 0
	t.live = 0

# m.len: the number of keys
pub fn mapLen<K Hash, V>(m {K: V}) i64:
	table(m).live

# m.isEmpty: whether the map has no keys
pub fn mapIsEmpty<K Hash, V>(m {K: V}) bool:
	table(m).live == 0

# m.keys(): the keys in the map's order, a new list
pub fn mapKeys<K Hash, V>(m {K: V}) K[]:
	ks K[] = []
	if __window(__zeroElem(ks)) == 1:
		tt = textTable(m)
		ks.reserve(tt.live)
		for c in 0..cellsOf(tt.marks):
			if tt.marks[c] >= 128:
				ks.push(textKeyAt(m, c))
		return ks
	t = table(m)
	r K[] = []
	r.reserve(t.live)
	for c in 0..cellsOf(t.marks):
		if t.marks[c] >= 128:
			r.push(t.cells[c].key.copy())
	r

# m.values(): the values in the map's order, a new list
pub fn mapValues<K Hash, V>(m {K: V}) V[]:
	probe K[] = []
	if __window(__zeroElem(probe)) == 1:
		tt = textTable(m)
		vs V[] = []
		vs.reserve(tt.live)
		for c in 0..cellsOf(tt.marks):
			if tt.marks[c] >= 128:
				vs.push(tt.cells[c].val.copy())
		return vs
	t = table(m)
	r V[] = []
	r.reserve(t.live)
	for c in 0..cellsOf(t.marks):
		if t.marks[c] >= 128:
			r.push(t.cells[c].val.copy())
	r

# m.entries(): the keys and their values, side by side in the map's order, a new list
pub fn mapEntries<K Hash, V>(m {K: V}) (K, V)[]:
	probe K[] = []
	if __window(__zeroElem(probe)) == 1:
		tt = textTable(m)
		es (K, V)[] = []
		es.reserve(tt.live)
		for c in 0..cellsOf(tt.marks):
			if tt.marks[c] >= 128:
				es.push((textKeyAt(m, c), tt.cells[c].val.copy()))
		return es
	t = table(m)
	r (K, V)[] = []
	r.reserve(t.live)
	for c in 0..cellsOf(t.marks):
		if t.marks[c] >= 128:
			r.push((t.cells[c].key.copy(), t.cells[c].val.copy()))
	r

# The cells in the map's order, empty and removed ones included (alive says which): how the
# code the compiler writes for printing and encoding walks a map.
pub fn mapEntryCount<K Hash, V>(m {K: V}) i64:
	cellsOf(table(m).marks)

pub fn mapEntryAlive<K Hash, V>(m {K: V}, i i64) bool:
	table(m).marks[i] >= 128

pub fn mapKeyAt<K Hash, V>(m {K: V}, i i64) ref K:
	t = table(m)
	t.cells[i].key

# the address of cell i's key (a key not kept as a window) and of its value, where a walk of the
# cells reads them
pub fn mapKeyPlace<K Hash, V>(m {K: V}, i i64) i64:
	t = table(m)
	__addr(t.cells[i].key)

pub fn mapValPlace<K Hash, V>(m {K: V}, i i64) i64:
	probe K[] = []
	if __window(__zeroElem(probe)) == 1:
		tt = textTable(m)
		return __addr(tt.cells[i].val)
	t = table(m)
	__addr(t.cells[i].val)

pub fn mapValAt<K Hash, V>(m {K: V}, i i64) ref V:
	probe K[] = []
	if __window(__zeroElem(probe)) == 1:
		tt = textTable(m)
		return tt.cells[i].val
	t = table(m)
	t.cells[i].val

# the live cells of m in their keys' order: how a map of integer or text keys is printed and
# encoded
pub fn mapSortedCells<K Hash + Ord, V>(m {K: V}) i64[]:
	probe K[] = []
	if __window(__zeroElem(probe)) == 1:
		tt = textTable(m)
		live = (0..cellsOf(tt.marks)).filter(i: tt.marks[i] >= 128)
		return live.sortedBy(i: textKeyAt(m, i))
	t = table(m)
	cells i64[] = []
	for i in 0..cellsOf(t.marks):
		if t.marks[i] >= 128:
			cells.push(i)
	cells.sortedBy(i: t.cells[i].key)

# the keys of the cells at, in that order (`m.keys().sortedBy(f)[0..k]` walked the cells in
# place and kept these: firstKeysKeep)
pub fn mapKeysPicked<K Hash, V, S>(m {K: V}, move keys S[], move at i64[], k i64) K[]:
	firstKeysCheck(at, k)
	r K[] = []
	window = __window(__zeroElem(r)) == 1
	t = table(m)
	for i in at:
		if window:
			r.push(textKeyAt(m, i))
		else:
			r.push(t.cells[i].key.copy())
	r

# the same for `m.values()`
pub fn mapValuesPicked<K Hash, V, S>(m {K: V}, move keys S[], move at i64[], k i64) V[]:
	firstKeysCheck(at, k)
	at.map(i: mapValAt(m, i).copy())
