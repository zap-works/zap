# A map whose keys are text windows ({ref str: V}, a word of a text counted in place) keeps
# each key in one word, so a cell is 16 bytes for an 8-byte value where a window and a value
# take 24: its length in the high 16 bits and, below, a key of up to 6 bytes its bytes (a probe
# compares one word and never reads the key's text, the miss a lookup paid), a longer one its
# address (a program's addresses fit in 48 bits), one of 65535 bytes or more its length (65535
# above it). The address of a key of up to 6 bytes or of 65535 or more is kept beside the cells,
# for the walks of the keys: in `near`, 4 bytes a cell, its distance from `base` (the first such
# key's) while every such key lies within 2 GB of it, else whole in `far` (`wide`). The table is a MapTable in all but its cells (the same fields in the
# same places), so the code that reads the bytes, the counts and the cells' number serves both;
# map.zap's functions turn here when K is a window (__window).

pub type TextCell<V>:
	key i64
	val V

pub type TextTable<V>:
	cells TextCell<V>[]
	marks u8[]
	used i64
	live i64
	base i64
	near i32[]   # each cell's key's address less base
	far i64[]   # each cell's key's address, when wide
	wide bool

textShort = 6   # the longest key kept as its bytes
textLong = 65_535
textLow = 281_474_976_710_655   # the low 48 bits

fn textTable<K Hash, V>(m {K: V}) mut ref TextTable<V>:
	__cast(__ld64(__addr(m)))

# the word the key of p and length is kept as
fn textWord(p i64, length i64) i64:
	if length <= textShort: return 0 if length == 0 else i64(shortWord(p, length)) | (length << 48)
	if length < textLong: return p | (length << 48)
	length | (textLong << 48)

# the key of p and length's hash (its word kw): bytesHash's, from the word when it holds the bytes
fn textHash(p i64, length i64, kw i64) i64:
	shortHash(u64(kw & textLow)) if length > 0 and length <= textShort else bytesHash(p, length)

# the length of the key kept as w
fn textLen(w i64) i64:
	hi = i64(u64(w) >> 48)
	hi if hi != textLong else w & textLow

# whether the key kept as w in cell s is the key of p and length whose word is kw
fn textSame<V>(t TextTable<V>, s i64, w i64, p i64, length i64, kw i64) bool:
	if length <= textShort: return w == kw
	if length < textLong: return u64(w ^ kw) >> 48 == 0 and sameBytes(w & textLow, p, length)
	w == kw and bytesEq(textKept(t, s), p, length)

# the cell holding the key p, length (word kw, hash h), or -1
fn textFind<V>(t TextTable<V>, p i64, length i64, kw i64, h i64) i64:
	n = cellsOf(t.marks)
	if n == 0: return -1
	marks = __ld64(__addr(t.marks))
	cells = __ld64(__addr(t.cells))
	stride = __stride(__zeroElem(t.cells))
	mk = markOf(h)
	s = homeOf(h, n)
	cm = __ld8(marks + s)
	while cm != 0:
		if cm == mk and textSame(t, s, __ld64(cells + s * stride), p, length, kw): return s
		s = nextCell(s, n)
		cm = __ld8(marks + s)
	-1

# n empty cells, and their bytes and addresses
fn textEmpty<V>(mut t TextTable<V>, n i64):
	growZeroed(t.cells, n)
	textGrowAt(t, n)
	t.marks = emptyMarks(n)

# the address kept for cell s's key
fn textKept<V>(t TextTable<V>, s i64) i64:
	t.far[s] if t.wide else t.base + i64(t.near[s])

# p kept as cell s's key's address: as its distance from base while that fits in 4 bytes, else
# every address whole from now on
fn textKeep<V>(mut t TextTable<V>, s i64, p i64):
	if not t.wide:
		if t.base == 0:
			t.base = p
		d = p - t.base
		if d >= -2_147_483_648 and d < 2_147_483_648:
			t.near[s] = i32(d)
			return
		t.far = t.near.map(t.base + i64(it))
		t.near = []
		t.wide = true
	t.far[s] = p

# room for the addresses of n cells
fn textGrowAt<V>(mut t TextTable<V>, n i64):
	if t.wide:
		growZeroed(t.far, n)
	else:
		growZeroed(t.near, n)

# the address of cell s's key: the word's, else the one kept beside it
fn textAddrOf<V>(t TextTable<V>, s i64) i64:
	w = t.cells[s].key
	length = textLen(w)
	w & textLow if length > textShort and length < textLong else textKept(t, s)

# the hash of the key in cell s
fn textHashAt<V>(t TextTable<V>, s i64) i64:
	w = t.cells[s].key
	length = textLen(w)
	textHash(textAddrOf(t, s), length, w)

# the live cells placed again in n cells, in place (map.zap's rehash), each key's address with it
fn textRehash<V>(mut t TextTable<V>, n i64):
	pending = move t.marks
	was = cellsOf(pending)
	growZeroed(t.cells, n)
	textGrowAt(t, n)
	t.marks = emptyMarks(n)
	for i in 0..was:
		if pending[i] < 128 or t.marks[i] != 0: continue
		pending[i] = 0
		h = textHashAt(t, i)
		cur = move t.cells[i]
		curAt = textKept(t, i)
		placing = true
		while placing:
			s = freeCell(t.marks, h)
			setMark(t.marks, s, markOf(h))
			if s < was and pending[s] >= 128:
				pending[s] = 0
				nextH = textHashAt(t, s)
				next = move t.cells[s]
				nextAt = textKept(t, s)
				t.cells[s] = move cur
				textKeep(t, s, curAt)
				cur = move next
				curAt = nextAt
				h = nextH
			else:
				t.cells[s] = move cur
				textKeep(t, s, curAt)
				placing = false
	t.used = t.live

# a new cell for the key p, length (word kw, hash h), the table rebuilt first when it is full
# (grownSize)
fn textAdd<V>(mut t TextTable<V>, p i64, length i64, kw i64, move val V, h i64) i64:
	ns = grownSize(cellsOf(t.marks), t.used, t.live)
	if ns > 0:
		textRehash(t, ns)
	s = openCell(t.marks, h)
	if t.marks[s] == 0:
		t.used += 1   # (a removed cell taken again was counted)
	setMark(t.marks, s, markOf(h))
	t.cells[s] = TextCell<V>(key = kw, val = val)
	if length <= textShort or length >= textLong:
		textKeep(t, s, p)
	t.live += 1
	s

# the cell of key (a window), made with make() when absent
fn textCellOf<K Hash, V>(m {K: V}, key K, make fn() V) i64:
	t = textTable(m)
	p = __ld64(__addr(key))
	length = __ld64(__addr(key) + 8)
	kw = textWord(p, length)
	h = textHash(p, length, kw)
	s = textFind(t, p, length, kw, h)
	s if s >= 0 else textAdd(t, p, length, kw, make(), h)

# the cell of key (a window), or -1
fn textCell<K Hash, V>(m {K: V}, key K) i64:
	p = __ld64(__addr(key))
	length = __ld64(__addr(key) + 8)
	kw = textWord(p, length)
	textFind(textTable(m), p, length, kw, textHash(p, length, kw))

# the window cell i's key is, as a K
pub fn textKeyAt<K Hash, V>(m {K: V}, i i64) K:
	t = textTable(m)
	pair = textAddrOf(t, i), textLen(t.cells[i].key)   # a window's two words
	ks K[] = []
	__peek(__addr(pair), __zeroElem(ks))
