# Lists: { ptr, length, cap } over a contiguous block of T. Generic over the element type; the
# backend instantiates each function for the element types a program uses, so a body may
# compare, add or copy its elements with the ordinary operators: each instance is checked
# with its own T. The raw part is the list core (the header, growth, push, extend, windows);
# everything above it is written over xs[i], move and copy().

fn hdr<T>(xs T[]) i64:
	__addr(xs)

# xs.len: the number of elements
pub fn listLen<T>(xs T[]) i64:
	__ld64(hdr(xs) + 8)

# xs.isEmpty: whether the list has no elements
pub fn listIsEmpty<T>(xs T[]) bool:
	__ld64(hdr(xs) + 8) == 0

# a == b for lists of integers or bools: the lengths, then the bytes a word at a time (the
# derived equality of such lists calls it)
fn listSameBytes<T>(a T[], b T[]) bool:
	if __ld64(hdr(a) + 8) != __ld64(hdr(b) + 8): return false
	bytesEq(__ld64(hdr(a)), __ld64(hdr(b)), listByteSize(a))

# xs.sum(b => i64(b)) of bytes: sixteen at a time, two words' bytes added pairwise into four
# 16-bit lanes (each takes 64 steps before it could overflow), then the lanes added up; in u64,
# which wraps where no sum of bytes reaches
fn bytesSum(xs u8[]) i64:
	n = xs.len
	p = __ld64(hdr(xs))
	m u64 = 0x00FF_00FF_00FF_00FF
	total u64 = 0
	i = 0
	while i + 16 <= n:
		end = (i + 1024).min(n & -16)
		lanes u64 = 0
		while i < end:
			w = u64.wrap(__ld64(p + i))
			x = u64.wrap(__ld64(p + i + 8))
			lanes += (w & m) + (w >> 8 & m) + (x & m) + (x >> 8 & m)
			i += 16
		pairs = (lanes & 0x0000_FFFF_0000_FFFF) + (lanes >> 16 & 0x0000_FFFF_0000_FFFF)
		total += (pairs & 0xFFFF_FFFF) + (pairs >> 32)
	while i < n:
		total += u64(__ld8(p + i))
		i += 1
	i64.wrap(total)

# xs.byteSize: the bytes the elements take, side by side (a list of plain values handed to
# the system or the GPU: vertices, pixels)
pub fn listByteSize<T>(xs T[]) i64:
	__ld64(hdr(xs) + 8) * __stride(__zeroElem(xs))

# xs.copyBytesTo(out): out holds xs's bytes, in the room it has (a buffer refilled every frame
# allocates nothing once it has grown)
pub fn listCopyBytesTo<T>(xs T[], mut out u8[]):
	n = listByteSize(xs)
	listGrowRaw(hdr(out), n, 1)
	if n > 0:
		__memcpy(__ld64(hdr(out)), __ld64(hdr(xs)), n)
	__st64(hdr(out) + 8, n)

# xs.bytes(): the elements' bytes as memory holds them, a window into the list (no copy): a
# Grid<Rgba8>'s cells as a texture's bytes
pub fn listBytes<T Copy>(xs T[]) ref u8[]:
	w u8[] = []
	__st64(__addr(w), __ld64(__addr(xs)))
	__st64(__addr(w) + 8, listByteSize(xs))
	w

# xs.rawBytes(): the elements' bytes side by side, as memory holds them (a list of plain values
# for the system or the GPU: vertices, records)
pub fn listRawBytes<T>(xs T[]) u8[]:
	n = listByteSize(xs)
	out u8[] = []
	if n > 0:
		listGrowRaw(hdr(out), n, 1)
		__memcpy(__ld64(hdr(out)), __ld64(hdr(xs)), n)
		__st64(hdr(out) + 8, n)
	out

# xs.set(ys): the list's elements become ys's (args.set(["x"]) gives a test a command line)
pub fn listSet<T>(mut xs T[], move ys T[]):
	xs = ys

# xs.clear(): removes every element (each is destroyed), keeping the room
pub fn listClear<T>(mut xs T[]):
	listTruncate(xs, 0)

# A list a loop's turn made, at the turn's end: its elements dropped and its block kept in the
# loop's slot at `kept` (24 bytes, a list's header), which the binding that made it takes again
# next turn, its room the largest turn's (TODO.md 54); freed instead when the slot holds one.
fn listRecycle<T>(mut xs T[], kept i64):
	listTruncate(xs, 0)
	h = hdr(xs)
	if __ld64(kept + 16) == 0:
		__memcpy(kept, h, 24)
	elif __ld64(h + 16) > 0:
		rtFree(__ld64(h))
	__st64(h, 0)
	__st64(h + 16, 0)

# room for n elements in all, allocated once (a list that will be filled to a known size)
pub fn listReserve<T>(mut xs T[], n i64):
	listGrowExact(hdr(xs), n, __stride(__zeroElem(xs)))

# xs grown to n elements whose bytes are all zero (a table's empty cells), its room made once
fn growZeroed<T>(mut xs T[], n i64):
	was = listLen(xs)
	if n <= was: return
	stride = __stride(__zeroElem(xs))
	listReserve(xs, n)
	__memset(__ld64(hdr(xs)) + was * stride, 0, (n - was) * stride)
	__st64(hdr(xs) + 8, n)

# keeps the first n elements (nothing when n is not shorter), dropping the rest
pub fn listTruncate<T>(mut xs T[], n i64):
	length = listLen(xs)
	if n < 0 or n >= length: return
	if __owning(__zeroElem(xs)) != 0:
		dropFrom(xs, n, length)
	__st64(hdr(xs) + 8, n)

# drops the elements n..length of xs
fn dropFrom<T>(mut xs T[], n i64, length i64):
	i = n
	while i < length:
		__drop(__at(xs, i))
		i += 1

# xs.push(v): adds v at the end (v moves in), growing the room when full
pub fn listPush<T>(mut xs T[], move v T):
	listPushRaw(hdr(xs), __addr(v), __stride(v))
	__forget(v)

# xs.extend(ys): the elements of ys appended to xs in one copy (plain elements only)
pub fn listExtend<T>(mut xs T[], ys T[]):
	n = listLen(xs)
	m = listLen(ys)
	if m == 0: return
	stride = __stride(__zeroElem(xs))
	src = __ld64(hdr(ys))
	oldItems = __ld64(hdr(xs))
	if n + m > __ld64(hdr(xs) + 16):
		listGrowRaw(hdr(xs), n + m, stride)
	if src >= oldItems and src < oldItems + n * stride:
		src = __ld64(hdr(xs)) + (src - oldItems)   # ys was a window into xs: follow the move
	__memcpy(__ld64(hdr(xs)) + n * stride, src, m * stride)
	__st64(hdr(xs) + 8, n + m)

# the last element moved out (none when empty); the slot it leaves is empty, which truncate would drop
# for nothing
pub fn listPop<T>(mut xs T[]) T?:
	if xs.isEmpty: return none
	listTake(xs)

# the last element of a list that has one, moved out
fn listTake<T>(mut xs T[]) T:
	n = __ld64(__addr(xs) + 8) - 1
	v = move xs[n]
	__st64(__addr(xs) + 8, n)
	v

# xs.first: the first element, borrowed; none when empty
pub fn listFirst<T>(xs T[]) ref T?:
	if xs.len == 0: return none
	xs[0]

# xs.last: the last element, borrowed; none when empty
pub fn listLast<T>(xs T[]) ref T?:
	n = xs.len
	if n == 0: return none
	xs[n - 1]

# xs.remove(i): the element at i moves out, the ones after it move down one place
pub fn listRemove<T>(mut xs T[], i i64) T:
	if i < 0 or i >= xs.len:
		boundsFail()
	removeAt(xs, i)

# the element at i (inside xs: the runtime's own index) moved out, the ones after it down one
fn removeAt<T>(mut xs T[], i i64) T:
	n = xs.len
	# raw: a forward copy is safe moving down, the moved last slot not dropped
	stride = __stride(__zeroElem(xs))
	items = __ld64(hdr(xs))
	v = __at(xs, i)
	__memcpy(items + i * stride, items + (i + 1) * stride, (n - 1 - i) * stride)
	__st64(hdr(xs) + 8, n - 1)
	v

# xs.insert(i, v): v moves in at i, the elements from i move up one place
pub fn listInsert<T>(mut xs T[], i i64, move v T):
	n = xs.len
	if i < 0 or i > n:
		boundsFail()
	# raw after the check above; one by one from the end, as __memcpy only copies forward
	xs.push(v)
	last = __at(xs, n)
	k = n
	while k > i:
		__setAt(xs, k, __at(xs, k - 1))
		k -= 1
	__setAt(xs, i, last)

# xs.reversed(): a copy in the opposite order
pub fn listReversed<T>(xs T[]) T[]:
	n = xs.len
	r T[] = []
	r.reserve(n)
	i = n - 1
	while i >= 0:
		r.push(xs[i].copy())
		i -= 1
	r

# xs.reverse(): the elements change places, the first with the last (no copies)
pub fn listReverse<T>(mut xs T[]):
	i = 0
	j = xs.len - 1
	while i < j:
		a = move xs[i]
		xs[i] = move xs[j]
		xs[j] = a
		i += 1
		j -= 1

# xs[start..to], a window over the elements of xs: no copy; the backend makes it in place, its
# bounds checked (irSlice)
fn listSlice<T>(xs T[], start i64, to i64) ref T[]:
	w T[] = []
	__st64(__addr(w), __ld64(__addr(xs)) + start * __stride(__zeroElem(xs)))
	__st64(__addr(w) + 8, to - start)
	w

# the byte the n bytes at p (n > 0) all are, or -1 when they differ
fn oneByte(p i64, n i64) i64:
	first = __ld8(p)
	for i in 1..n:
		if __ld8(p + i) != first: return -1
	first

# xs repeated `times` times: the buffer sized once; plain elements are copied as bytes, the
# filled part doubling each step (one byte throughout is a fill); owning elements are copied
# one by one. Only the checker calls it, with the one element of zeros and fill.
pub fn listRepeat<T>(xs T[], times i64) T[]:
	r T[] = []
	n = xs.len
	total = n * times
	if total <= 0: return r
	stride = __stride(__zeroElem(r))
	plain = __owning(__zeroElem(r)) == 0 and stride > 0
	byte = oneByte(__ld64(__addr(xs)), n * stride) if plain else -1
	if byte == 0:
		# `zeros(n)`: a zeroed block, which a block fresh from the system is untouched
		__st64(__addr(r), rtAlloc(total * stride))
		__st64(__addr(r) + 8, total)
		__st64(__addr(r) + 16, total)
		return r
	r.reserve(total)
	if byte > 0:
		__memset(__ld64(__addr(r)), byte, total * stride)
		__st64(__addr(r) + 8, total)
		return r
	if __owning(__zeroElem(r)) == 0:
		items = __ld64(__addr(r))
		__memcpy(items, __ld64(__addr(xs)), n * stride)
		have = n
		while have * 2 <= total:
			__memcpy(items + have * stride, items, have * stride)
			have *= 2
		if have < total:
			__memcpy(items + have * stride, items, (total - have) * stride)
		__st64(__addr(r) + 8, total)
		return r
	kk i64 = 0
	while kk < times:
		for i in 0..n:
			r.push(xs[i].copy())
		kk += 1
	r

# xs.join(sep): the strings of the list with sep between them
pub fn listJoin<T>(xs T[], sep str) str:
	total = 0
	for i in 0..xs.len:
		total += textAt(xs, i).len + sep.len
	out = strBuildStart(total)   # one block, its size known
	for i in 0..xs.len:
		if i > 0:
			strBuildAdd(out, sep)
		strBuildAdd(out, textAt(xs, i))
	strBuildEnd(move out)

# element i of a list of str or of ref str, lent: a window's two words, a str's read as a str's are
fn textAt<T>(xs T[], i i64) str:
	at = __addr(xs[i])
	if __window(__zeroElem(xs)) == 1: return __strof(__ld64(at), __ld64(at + 8), 0)
	__strof(textPtrAt(at), textLenAt(at), 0)

# xs.pick(): an element drawn at random from the program's sequence (random); the program stops
# on an empty list
pub fn listPick<T>(xs T[]) ref T:
	if xs.len == 0:
		fail("pick from an empty list")
	xs[randomIn(0, len)]

# xs.contains(v): whether an element equals v
pub fn listContains<T Eq>(xs T[], v T) bool:
	firstIndex(xs, v) >= 0

# xs.indexOf(v): the index of the first element equal to v; none when there is none
pub fn listIndexOf<T Eq>(xs T[], v T) n64?:
	foundIndex(firstIndex(xs, v))

# the index of the first element equal to v, or -1 (bytes: sixteen at a time)
fn firstIndex<T Eq>(xs T[], v T) i64:
	k = __tykind(__zeroElem(xs))
	if (k == 1 or k == 2) and __stride(__zeroElem(xs)) == 1:
		return byteIndex(__strof(__ld64(__addr(xs)), xs.len, 0), __ld8(__addr(v)), 0)
	for i in 0..xs.len:
		if xs[i] == v: return i
	-1

# the order of a and b: -1, 0 or 1 (the written $cmpN of tuples and lists build on it)
pub fn ordCompare<T Ord>(a T, b T) i64:
	if __tykind(a) == 4: return textOrderAt(__addr(a), __addr(b))   # a str: its bytes walked once
	if a < b: return -1
	if b < a: return 1
	0

# the index of the first largest element (wantMax) or the first smallest; xs is not empty
fn extremeIndex<T Ord>(xs T[], wantMax bool) i64:
	best i64 = 0
	for i in 1..xs.len:
		if (xs[i] > xs[best] if wantMax else xs[i] < xs[best]):
			best = i
	best

# xs.max(): the largest element, borrowed; none when empty
pub fn listMax<T Ord>(xs T[]) ref T?:
	if xs.len == 0: return none
	xs[extremeIndex(xs, true)]

# xs.min(): the smallest element, borrowed; none when empty
pub fn listMin<T Ord>(xs T[]) ref T?:
	if xs.len == 0: return none
	xs[extremeIndex(xs, false)]

# the sum in the element type (it wraps like every integer operation)
pub fn listSum<T Num>(xs T[]) T:
	n = xs.len
	if n == 0: return __zeroElem(xs)
	acc T = xs[0]
	for i in 1..n:
		acc += xs[i]
	acc

# A step of groupBy, in the loop the compiler makes of it and the steps before it (countBy's is
# mapAdd, mean's an addition): a copy of x onto the end of its key's group, a new key copied in
pub fn mapGroupAdd<K Hash, T>(mut groups {K: T[]}, key K, x T):
	if groups.get(key) is group:
		group.push(x.copy())
	else:
		groups[key.copy()] = [x.copy()]

# a step of zip: copies of x and ys[i] paired onto the end of pairs
pub fn listZipPush<T, U>(mut pairs (T, U)[], x T, ys U[], i i64):
	pairs.push((x.copy(), ys[i].copy()))

# the indices of keys in ascending order, equal keys in their original order: a stable merge
# sort of the indices (the keys themselves never move)
fn sortedOrder<K Ord>(keys K[]) i64[]:
	n = keys.len
	order = (0..n).map(i: i)
	spare = zeros(n)
	sortSpan(keys, __ld64(__addr(order)), __ld64(__addr(spare)), 0, n)
	order

# the same on every processor: parts sorted at once, then merged pairwise level by level, each
# merge cut into as many pieces as the level has fewer merges than parts, every piece at once
# (a short list is sorted on this thread)
fn sortedOrderParallel<K Ord>(keys K[]) i64[]:
	n = keys.len
	parts = parallelChunks()
	if n < 4096 or parts < 2: return sortedOrder(keys)
	order = (0..n).map(i: i)
	spare = zeros(n)
	a = __ld64(__addr(order))
	b = __ld64(__addr(spare))
	size = (n + parts - 1) / parts
	parallelDo(parts, p:
		sortSpan(keys, a, b, (p * size).min(n), ((p + 1) * size).min(n))
	)
	src = a
	dst = b
	width = size
	while width < n:
		from = src
		to = dst
		w = width
		merges = (n + 2 * w - 1) / (2 * w)
		pieces = (parts / merges).max(1)
		parallelDo(merges * pieces, t:
			lo = t / pieces * 2 * w
			mid = (lo + w).min(n)
			hi = (lo + 2 * w).min(n)
			piece = t % pieces
			k0 = (hi - lo) * piece / pieces
			k1 = (hi - lo) * (piece + 1) / pieces
			i0 = coRank(keys, from, k0, lo, mid, hi)
			i1 = coRank(keys, from, k1, lo, mid, hi)
			mergeFrom(keys, from, to, lo + i0, lo + i1, mid + k0 - i0, mid + k1 - i1, lo + k0)
		)
		src = to
		dst = from
		width *= 2
	if src != a:
		__memcpy(a, src, n * 8)
	order

# the indices at a[lo..hi) sorted by their keys, stably, with b's same span as room: runs of 16
# by insertion, then merged in rounds of doubling width; the result ends in a
fn sortSpan<K Ord>(keys K[], a i64, b i64, lo i64, hi i64):
	s = lo
	while s < hi:
		e = (s + 16).min(hi)
		for i in s + 1..e:
			v = __ld64(a + i * 8)
			j = i
			while j > s and keys[__ld64(a + (j - 1) * 8)] > keys[v]:
				__st64(a + j * 8, __ld64(a + (j - 1) * 8))
				j -= 1
			__st64(a + j * 8, v)
		s = e
	src = a
	dst = b
	width = 16
	while width < hi - lo:
		at = lo
		while at < hi:
			mergeRuns(keys, src, dst, at, (at + width).min(hi), (at + 2 * width).min(hi))
			at += 2 * width
		t = src
		src = dst
		dst = t
		width *= 2
	if src != a and hi > lo:
		__memcpy(a + lo * 8, src + lo * 8, (hi - lo) * 8)

# the sorted runs src[lo..mid) and src[mid..hi) merged into dst[lo..hi), the left one first
# among equal keys
fn mergeRuns<K Ord>(keys K[], src i64, dst i64, lo i64, mid i64, hi i64):
	mergeFrom(keys, src, dst, lo, mid, mid, hi, lo)

# how many of the first k indices of the merge of src[lo..mid) and src[mid..hi) come from the
# left run (the left first among equal keys): where a piece of the merge starts
fn coRank<K Ord>(keys K[], src i64, k i64, lo i64, mid i64, hi i64) i64:
	nl = mid - lo
	nr = hi - mid
	a = (k - nr).max(0)
	b = k.min(nl)
	while a < b:
		i = (a + b) / 2
		j = k - i
		if i < nl and j > 0 and
			not (keys[__ld64(src + (lo + i) * 8)] > keys[__ld64(src + (mid + j - 1) * 8)]):
			a = i + 1   # the left's next goes before the right's last taken
		else:
			b = i
	a

# src[i..mid) and src[j..hi), both sorted, merged into dst from k, the left first among equal keys
fn mergeFrom<K Ord>(keys K[], src i64, dst i64, i0 i64, mid i64, j0 i64, hi i64, k0 i64):
	i = i0
	j = j0
	k = k0
	while i < mid and j < hi:
		x = __ld64(src + i * 8)
		y = __ld64(src + j * 8)
		if keys[y] < keys[x]:
			__st64(dst + k * 8, y)
			j += 1
		else:
			__st64(dst + k * 8, x)
			i += 1
		k += 1
	if i < mid:
		__memcpy(dst + k * 8, src + i * 8, (mid - i) * 8)
	if j < hi:
		__memcpy(dst + k * 8, src + j * 8, (hi - j) * 8)

# copies of the elements of xs in the given order
fn picked<T>(xs T[], order i64[]) T[]:
	r T[] = []
	r.reserve(order.len)   # not a map: the room taken once
	for i in order:
		r.push(xs[i].copy())
	r

# xs.sorted(): a sorted copy (stable)
pub fn listSorted<T Ord>(xs T[]) T[]:
	picked(xs, sortedOrder(xs))

# xs.sort(): the elements put in order where they are (stable; they move, none is copied). Equal
# bools, integers, strs and windows of text are the same value, so their order cannot show: they
# are sorted in place, with no room besides the list
pub fn listSort<T Ord>(mut xs T[]):
	k = __tykind(__zeroElem(xs))
	if k == 1 or k == 2 or k == 4 or __window(__zeroElem(xs)) == 1:
		introSort(xs, 0, xs.len, introDepth(xs.len))
		return
	placeInOrder(xs, sortedOrder(xs))

# how deep introsort's quicksort goes before heapsort takes over: twice log2 n
fn introDepth(n i64) i64:
	depth = 0
	k = n
	while k > 1:
		depth += 2
		k /= 2
	depth

# xs[lo..hi) sorted where it lies: quicksort around the median of three, insertion sort for
# short spans, heapsort once the depth runs out (no quadratic input)
fn introSort<T Ord>(mut xs T[], lo i64, hi i64, depth i64):
	l = lo
	h = hi
	d = depth
	while h - l > 16:
		if d == 0:
			heapSort(xs, l, h)
			return
		d -= 1
		m = l + (h - l) / 2
		if __at(xs, m) < __at(xs, l):
			swapAt(xs, m, l)
		if __at(xs, h - 1) < __at(xs, l):
			swapAt(xs, h - 1, l)
		if __at(xs, h - 1) < __at(xs, m):
			swapAt(xs, h - 1, m)
		# the pivot at l; xs[h - 1] is not below it, so the scan up stops inside the span
		swapAt(xs, l, m)
		i = l
		j = h
		crossing = true
		while crossing:
			i += 1
			while __at(xs, i) < __at(xs, l):
				i += 1
			j -= 1
			while __at(xs, l) < __at(xs, j):
				j -= 1
			if i >= j:
				crossing = false
			else:
				swapAt(xs, i, j)
		swapAt(xs, l, j)
		# the shorter side by recursion, the longer by the loop: the stack stays logarithmic
		if j - l < h - j - 1:
			introSort(xs, l, j, d)
			l = j + 1
		else:
			introSort(xs, j + 1, h, d)
			h = j
	for i in l + 1..h:
		j = i
		while j > l and __at(xs, j) < __at(xs, j - 1):
			swapAt(xs, j, j - 1)
			j -= 1

fn heapSort<T Ord>(mut xs T[], lo i64, hi i64):
	n = hi - lo
	start = n / 2
	while start > 0:
		start -= 1
		siftDown(xs, lo, start, n)
	end = n
	while end > 1:
		end -= 1
		swapAt(xs, lo, lo + end)
		siftDown(xs, lo, 0, end)

# the heap xs[lo..lo + n) made whole again below its node at
fn siftDown<T Ord>(mut xs T[], lo i64, at i64, n i64):
	root = at
	while 2 * root + 1 < n:
		child = 2 * root + 1
		if child + 1 < n and __at(xs, lo + child) < __at(xs, lo + child + 1):
			child += 1
		if not (__at(xs, lo + root) < __at(xs, lo + child)): return
		swapAt(xs, lo + root, lo + child)
		root = child

# xs.swap(i, j): the elements at i and j trade places (they move, none is copied)
pub fn listSwap<T>(mut xs T[], i i64, j i64):
	n = xs.len
	if i < 0 or i >= n or j < 0 or j >= n:
		fail("swap({i}, {j}) on a list of {n}")
	swapAt(xs, i, j)

# The heaps are 4-ary (children of i at 4i+1..4i+4): half the levels of a binary heap, each a
# tournament of four children; values move as bytes, unchecked (the indexes lie inside the list,
# u64s: their arithmetic has no overflow check).

# the smallest value of the heap xs (not empty) taken out: the last value v fills the hole it
# leaves, moving down past the smallest children, each of which moves up once (moved as bytes)
fn heapTake<T Ord>(mut xs T[]) T:
	n = __ld64(__addr(xs) + 8) - 1
	top = __at(xs, 0)
	__st64(__addr(xs) + 8, n)
	if n == 0: return top
	v = __at(xs, n)
	end = u64.wrap(n)
	i u64 = 0
	c u64 = 1
	while c + 3 < end:
		# two pairs, then their winners, chosen by value: no branch (which child is smallest cannot
		# be guessed) and no load waiting on a choice
		x0 = __at(xs, c)
		x1 = __at(xs, c + 1)
		x2 = __at(xs, c + 2)
		x3 = __at(xs, c + 3)
		a = x1 if x1 < x0 else x0
		ai = c + 1 if x1 < x0 else c
		b = x3 if x3 < x2 else x2
		bi = c + 3 if x3 < x2 else c + 2
		m = bi if b < a else ai
		least = b if b < a else a
		if not (least < v):
			c = end   # v stays here: nothing below
			break
		__setAt(xs, i, least)
		i = m
		c = 4 * i + 1
	if c < end:
		# the last parent, with fewer than four children
		m = c
		k = c + 1
		while k < end:
			m = k if __at(xs, k) < __at(xs, m) else m
			k += 1
		least = __at(xs, m)
		if least < v:
			__setAt(xs, i, least)
			i = m
	__setAt(xs, i, v)
	top

# v added to the heap xs, whose last element is room for it (written over): each larger parent
# moves down into the hole v leaves, and v goes where the moving stops (no swaps). It allocates
# nothing, so a program's loop gets it inlined.
fn heapSiftUp<T Ord>(mut xs T[], move v T):
	i = u64.wrap(xs.len - 1)
	while i > 0:
		parent = (i - 1) >> 2
		above = __at(xs, parent)
		if not (above > v): break
		__setAt(xs, i, above)
		i = parent
	__setAt(xs, i, v)

# the elements at i and j exchanged as bytes (a value moves wherever it lies)
fn swapAt<T>(mut xs T[], i i64, j i64):
	stride = __stride(__zeroElem(xs))
	p = __ld64(__addr(xs))
	a = p + i * stride
	b = p + j * stride
	if stride == 8:
		t = __ld64(a)
		__st64(a, __ld64(b))
		__st64(b, t)
		return
	if stride == 4:
		t = __ld32(a)
		__st32(a, __ld32(b))
		__st32(b, t)
		return
	k = 0
	while k + 8 <= stride:
		t = __ld64(a + k)
		__st64(a + k, __ld64(b + k))
		__st64(b + k, t)
		k += 8
	while k < stride:
		t = __ld8(a + k)
		__st8(a + k, __ld8(b + k))
		__st8(b + k, t)
		k += 1

# xs.sortBy(key): the elements put in the order of their keys where they are (stable; they move,
# none is copied), the order applied cycle by cycle; the keys, built for the call, end here
fn listSortBy<T, K Ord>(mut xs T[], move keys K[]):
	placeInOrder(xs, sortedOrder(keys))

# xs's elements moved to the order given (order[i]: the index of the one that goes at i), cycle
# by cycle
fn placeInOrder<T>(mut xs T[], order i64[]):
	placed = fill(order.len, false)
	for start in 0..order.len:
		if placed[start]: continue
		placed[start] = true
		i = start
		while order[i] != start:
			j = order[i]
			swapAt(xs, i, j)   # i takes its element; the one it held waits at j
			placed[j] = true
			i = j

# xs.sortBy(f) for a key of one to three parts the compiler found cheap to make again (pure,
# borrowing only what outlives the sort: irKeyParts; a key of fewer parts gives its first again
# for the rest): no keys kept, a stable merge sort of the elements where a comparison makes the
# first parts of the two, a later part only when those tie. When a part may stop the program,
# every key is made once first, in order, as a list of keys would be (made). Short runs are
# sorted by insertion where they are, then merged pairwise in rounds (mergeParts) through a room
# (sortRoom bytes, or an eighth of the list), the elements moved as bytes
fn listSortByParts<T, K0 Ord, K1 Ord, K2 Ord>(
	mut xs T[],
	first fn(T) K0,
	second fn(T) K1,
	third fn(T) K2,
	parts i64,
	made bool
):
	n = xs.len
	if made:
		for i in 0..n:
			_ = first(__at(xs, i))
			if parts > 1: _ = second(__at(xs, i))
			if parts > 2: _ = third(__at(xs, i))
	# as many runs as a power of two, each of at most 16 sorted by insertion
	runs = 1
	while n > 16 * runs:
		runs *= 2
	for r in 0..runs:
		s = r * n / runs
		for i in s + 1..(r + 1) * n / runs:
			j = i
			while j > s:
				# (partsBefore in line, as in mergeParts)
				c = ordCompare(first(__at(xs, j)), first(__at(xs, j - 1)))
				if c > 0 or c == 0 and
					(
						parts == 1 or
							not laterBefore(__at(xs, j), __at(xs, j - 1), second, third, parts)
					):
					break
				swapAt(xs, j - 1, j)
				j -= 1
	if runs == 1: return
	stride = __stride(__zeroElem(xs))
	room T[] = []   # what a merge moves out of the way (its length stays 0)
	roomLen = ((n + 1) / 2).min((sortRoom / stride).max(n / 8).max(16))
	listGrowTo(hdr(room), roomLen, stride)
	m = runs
	while m > 1:
		for t in 0..m / 2:
			mergeParts(
				xs,
				room,
				2 * t * n / m,
				(2 * t + 1) * n / m,
				(2 * t + 2) * n / m,
				first,
				second,
				third,
				parts
			)
		m /= 2

# the bytes a merge of sortBy's sets aside, or an eighth of the list when that is more: a room of
# half the list would be most of what sorting a long list adds to the program's memory, and a
# longer pair is split (mergeParts), each split moving the elements between once more
sortRoom = 32_768

# how many elements ahead a merge fetches the bytes of text keys
sortAhead = 8

# the sorted runs xs[lo..mid] and xs[mid..hi] merged where they are, the left first among equal
# keys: a left run that fits the room (its capacity) moves to it and the two merge back; a longer pair is split
# where the middle of the longer run goes in the other, the pieces between swap places and each
# side merges alone
fn mergeParts<T, K0 Ord, K1 Ord, K2 Ord>(
	mut xs T[],
	room T[],
	lo i64,
	mid i64,
	hi i64,
	first fn(T) K0,
	second fn(T) K1,
	third fn(T) K2,
	parts i64
):
	if lo == mid or mid == hi or
		not partsBefore(__at(xs, mid), __at(xs, mid - 1), first, second, third, parts):
		return   # in order already
	nl = mid - lo
	if nl > __ld64(hdr(room) + 16):
		long = nl >= hi - mid
		pivot = lo + nl / 2 if long else mid + (hi - mid) / 2
		i = pivot if long else partsBound(xs, lo, mid, pivot, true, first, second, third, parts)
		j = partsBound(xs, mid, hi, pivot, false, first, second, third, parts) if long else pivot
		swapRuns(xs, room, i, mid, j)
		k = i + j - mid
		mergeParts(xs, room, lo, i, k, first, second, third, parts)
		mergeParts(xs, room, k, j, hi, first, second, third, parts)
		return
	stride = __stride(__zeroElem(xs))
	at = __ld64(hdr(xs))
	left = __ld64(hdr(room))
	__memcpy(left, at + lo * stride, nl * stride)
	i = 0
	j = mid
	k = lo
	while i < nl and j < hi:
		if __tykind(first(__at(xs, j))) == 4:
			# text keys: the bytes of both runs' keys a few ahead fetched while these are compared
			# (a key that reads memory the caches lack would stall the merge at each step)
			ahead = first(__at(xs, (j + sortAhead).min(hi - 1)))
			__prefetch(textPtrAt(__addr(ahead)))
			aheadLeft = first(__at(room, (i + sortAhead).min(nl - 1)))
			__prefetch(textPtrAt(__addr(aheadLeft)))
		# (partsBefore in line: most comparisons end at the first parts, a call costs)
		c = ordCompare(first(__at(xs, j)), first(__at(room, i)))
		if c < 0 or c == 0 and parts > 1 and
			laterBefore(__at(xs, j), __at(room, i), second, third, parts):
			moveBytes(at + k * stride, at + j * stride, stride)
			j += 1
		else:
			moveBytes(at + k * stride, left + i * stride, stride)
			i += 1
		k += 1
	if i < nl:
		__memcpy(at + k * stride, left + i * stride, (nl - i) * stride)   # the right's rest is in place

# the first index of the sorted xs[a..b] whose element goes after the one at p (after), or does
# not go before it
fn partsBound<T, K0 Ord, K1 Ord, K2 Ord>(
	xs T[],
	a i64,
	b i64,
	p i64,
	after bool,
	first fn(T) K0,
	second fn(T) K1,
	third fn(T) K2,
	parts i64
) i64:
	lo = a
	hi = b
	while lo < hi:
		h = (lo + hi) / 2
		past = partsBefore(__at(xs, p), __at(xs, h), first, second, third, parts) if after
			else not partsBefore(__at(xs, h), __at(xs, p), first, second, third, parts)
		if past:
			hi = h
		else:
			lo = h + 1
	lo

# xs[a..m] and xs[m..b] swap places: through the room (its capacity) when the left fits it,
# else by three reversals
fn swapRuns<T>(mut xs T[], room T[], a i64, m i64, b i64):
	if a == m or m == b: return
	if m - a <= __ld64(hdr(room) + 16):
		stride = __stride(__zeroElem(xs))
		at = __ld64(hdr(xs))
		__memcpy(__ld64(hdr(room)), at + a * stride, (m - a) * stride)
		__memcpy(at + a * stride, at + m * stride, (b - m) * stride)   # (a forward copy, down)
		__memcpy(at + (a + b - m) * stride, __ld64(hdr(room)), (m - a) * stride)
		return
	reverseRun(xs, a, m)
	reverseRun(xs, m, b)
	reverseRun(xs, a, b)

# xs[a..b] in the opposite order (a word at once when an element is one)
fn reverseRun<T>(mut xs T[], a i64, b i64):
	i = a
	j = b - 1
	if __stride(__zeroElem(xs)) == 8:
		at = __ld64(hdr(xs))
		while i < j:
			t = __ld64(at + i * 8)
			__st64(at + i * 8, __ld64(at + j * 8))
			__st64(at + j * 8, t)
			i += 1
			j -= 1
		return
	while i < j:
		swapAt(xs, i, j)
		i += 1
		j -= 1

# whether x goes before y by their keys' parts, the later ones made only on a tie
fn partsBefore<T, K0 Ord, K1 Ord, K2 Ord>(
	x T,
	y T,
	first fn(T) K0,
	second fn(T) K1,
	third fn(T) K2,
	parts i64
) bool:
	c = ordCompare(first(x), first(y))
	c < 0 or c == 0 and parts > 1 and laterBefore(x, y, second, third, parts)

# the same for keys whose first parts tie
fn laterBefore<T, K1 Ord, K2 Ord>(x T, y T, second fn(T) K1, third fn(T) K2, parts i64) bool:
	if parts == 2: return second(x) < second(y)
	d = ordCompare(second(x), second(y))
	d < 0 or d == 0 and third(x) < third(y)

# stride bytes from `from` to `to` (one word at once when they are one)
fn moveBytes(to i64, from i64, stride i64):
	if stride == 8:
		__st64(to, __ld64(from))
	elif stride == 4:
		__st32(to, __ld32(from))
	else:
		__memcpy(to, from, stride)

# a copy of xs sorted by the parallel list of keys (stable); the keys, built for the call, end here
fn listSortByKeys<T, K Ord>(xs T[], move keys K[]) T[]:
	picked(xs, sortedOrder(keys))

# the key just pushed onto keys (element i's) moved to its place among the k first, kept in
# order (stable: it passes only strictly larger keys), the one past the k-th dropped; at holds
# the kept keys' indices
fn firstKeysKeep<K Ord>(mut keys K[], mut at i64[], i i64, k i64):
	p = keys.len - 1
	at.push(i)
	while p > 0 and keys[p] < keys[p - 1]:
		keys.swap(p, p - 1)
		at.swap(p, p - 1)
		p -= 1
	if keys.len > k:
		_ = keys.pop()
		_ = at.pop()

# the elements firstKeysKeep kept, in their keys' order (`xs.sortedBy(f)[0..k]` past the end
# stops the program)
fn firstKeysPicked<T, K>(xs T[], move keys K[], move at i64[], k i64) T[]:
	firstKeysCheck(at, k)
	picked(xs, at)

fn firstKeysCheck(at i64[], k i64):
	if k > at.len:
		boundsFail()   # xs.sortedBy(f)[0..k] past the end

# the same sorted on every processor (`xs.parallel().sortedBy(f)`)
fn listSortByKeysParallel<T, K Ord>(xs T[], move keys K[]) T[]:
	order = sortedOrderParallel(keys)
	(0..order.len).parallel().map(i: xs[order[i]].copy())

# the element of xs whose key is the first smallest (or largest), borrowed; none when xs is
# empty (`xs.parallel().minBy(f)`: the keys made on every processor)
fn listPickByKeys<T, K Ord>(xs T[], move keys K[], wantMax bool) ref T?:
	if keys.len == 0: return none
	xs[extremeIndex(keys, wantMax)]

# The helpers of the pipeline terminals the backend compiles in line (minBy, maxBy): each loop
# computes an index, these turn it into the result.

# the index of the first smallest (or largest) key, -1 when there is none; the keys, built for
# the call, end here
fn keysMinIndex<K Ord>(move keys K[]) i64:
	if keys.len == 0: return -1
	extremeIndex(keys, false)

fn keysMaxIndex<K Ord>(move keys K[]) i64:
	if keys.len == 0: return -1
	extremeIndex(keys, true)

# the elements of ys moved to the end of xs; the block that held them is freed here and ys left
# the empty list, so dropping it frees nothing more
fn listAppend<T>(mut xs T[], move ys T[]):
	n = listLen(xs)
	m = listLen(ys)
	if m > 0:
		stride = __stride(__zeroElem(xs))
		listGrowRaw(hdr(xs), n + m, stride)
		__memcpy(__ld64(hdr(xs)) + n * stride, __ld64(hdr(ys)), m * stride)
		__st64(hdr(xs) + 8, n + m)
	rtFree(__ld64(hdr(ys)))
	__st64(hdr(ys), 0)
	__st64(hdr(ys) + 8, 0)
	__st64(hdr(ys) + 16, 0)

# a copy of the list header at src into dst, its plain elements copied bitwise
fn listCopyRaw(src i64, dst i64, stride i64):
	n = __ld64(src + 8)
	__st64(dst, 0)
	__st64(dst + 8, 0)
	__st64(dst + 16, 0)
	if n == 0: return
	listGrowRaw(dst, n, stride)
	__memcpy(__ld64(dst), __ld64(src), n * stride)
	__st64(dst + 8, n)
