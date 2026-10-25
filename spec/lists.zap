# 7.1 Lists: `T[]`
#
# A list owns its elements in one contiguous block; its type is written `T[]` (*Fixed arrays* for
# the layers of one bracket). Changing it needs a `mut` binding; an empty literal needs a type
# (*Literals*).

type Item:
	name str
	qty i64

fn restock(mut items Item[]):
	items.push(Item(name = "potion", qty = 5))

# `push(v)` appends, and gives the new element's index where its value is used; `pop()` moves the
# last element out (`T?`); `xs[i]` and `xs[i] = v` read and change an element, bounds-checked;
# `first` and `last` are fields, a `ref T?`; `len` and `isEmpty` its size.
test "push, pop, index, first, last and the size":
	nums = []
	print(nums.isEmpty)
	expect nums.push(10) == 0
	nums.push(20)
	nums.push(30)
	nums[1] = 25
	print("{nums.len} {nums[1]} {nums.first ?? -1} {nums.last ?? -1}")
	print("{nums.pop() ?? -1} {nums.pop() ?? -1} {nums.pop() ?? -1} {nums.pop() ?? -1}")
	prints """
		true
		3 25 10 30
		30 25 10 -1
		"""

test "an index past the end stops the program" stops IndexOutOfBounds:
	xs = [1, 2]
	print(xs[args.len + 2])

# A list of structs changes in place through an index, and a `mut` parameter changes the caller's
# list; `copy()` is a deep copy, independent of the original.
test "elements change in place, copies are independent":
	bag = [Item(name = "sword", qty = 1)]
	bag[0].qty += 1
	restock(bag)
	print("{bag.len} {bag[0].qty} {bag[1].name}")
	other = bag.copy()
	other.push(Item(name = "shield", qty = 1))
	other[0].qty = 100
	print("{bag.len} {bag[0].qty} {other.len} {other[0].qty}")
	prints """
		2 2 potion
		2 2 3 100
		"""

# `insert(i, v)` moves `v` in at `i` and `remove(i)` moves the element at `i` out, the rest
# shifting; `clear()` empties the list, `truncate(n)` keeps the first `n`, `reserve(n)` makes room
# for `n` in all; `swap(i, j)` trades two elements.
test "insert, remove, clear, truncate, reserve and swap":
	xs = ["a".repeat(3), "b".repeat(3), "c".repeat(3)]
	expect xs.remove(1) == "bbb"
	xs.insert(0, "z".repeat(2))
	xs.insert(3, "y".repeat(2))
	xs.insert(2, "m".repeat(2))
	print(xs.join(","))
	xs.swap(0, 4)
	xs.truncate(3)
	print(xs.join(","))
	xs.clear()
	print(xs.len)
	ns i64[] = []
	ns.reserve(1000)
	for i in 0..1000:
		ns.push(i)
	print("{ns.len} {ns[999]}")
	prints """
		zz,aaa,mm,ccc,yy
		yy,aaa,mm
		0
		1000 999
		"""

test "remove past the end stops the program" stops IndexOutOfBounds:
	xs = [1, 2]
	_ = xs.remove(2)

# A verb changes the list where it is (`sort()`, `sortBy(key)`, `reverse()`); its participle makes a
# new one (`sorted()`, `reversed()`). `sort` takes numbers, strings, tuples and lists, `sortBy` a key
# (a tuple orders by several fields); every sort is stable. A key orders as if made once for each
# element, in order, before any moves: one that only reads (numbers, texts it borrows, the
# program's functions with no loop) is made again where two elements are compared instead of kept,
# a later field of a tuple only when the earlier ones tie, which no program can tell apart.
test "verbs change the list, participles make one":
	xs = ["pear", "fig", "apple", "kiwi"]
	ys = xs.sorted()
	print("{xs} {ys}")
	xs.sort()
	xs.reverse()
	print("{xs} {xs.reversed()}")
	ns = (0..40).map((it * 37) % 41)
	ns.sortBy(-it)
	print(ns[..5])
	words = ["pear", "fig", "banana", "kiwi", "apple"]
	idx = [0, 1, 2, 3, 4]
	idx.sortBy(words[it].len, words[it])
	print(idx.map(words[it].copy()))   # any turn may read any element: each a copy of its own
	byLength = ["pear", "fig", "kiwi", "yam"]
	byLength.sortBy(.len)
	print(byLength)
	pairs = [(2, "b"), (1, "z"), (2, "a")]
	pairs.sort()
	print(pairs)
	empty i64[] = []
	empty.sort()
	empty.reverse()
	print(empty)
	prints """
		["pear", "fig", "apple", "kiwi"] ["apple", "fig", "kiwi", "pear"]
		["pear", "kiwi", "fig", "apple"] ["apple", "fig", "kiwi", "pear"]
		[40, 39, 38, 37, 36]
		["fig", "kiwi", "pear", "apple", "banana"]
		["fig", "yam", "pear", "kiwi"]
		[(1, "z"), (2, "a"), (2, "b")]
		[]
		"""

# A list of windows of text sorts as its texts do, the windows moved, the text left where it is.
test "a list of windows sorts by their texts":
	text = "pear fig apple fig"
	words = []
	for (at, to) in [(0, 4), (5, 8), (9, 14), (15, 18)]:
		words.push(text[at..to])
	words.sort()
	expect words == ["apple", "fig", "fig", "pear"]

# `indexOf(v)` gives an `i64?` (membership is `v in xs`), `count(v)` how many equal `v` (`count(p)`
# with a function: those it holds for); `max()` and `min()` a `ref T?` of numbers or strings.
test "searching and counting":
	xs = [3, 1, 4, 1, 5]
	expect xs.indexOf == {4: 2, 9: none}
	expect 1 in xs
	expect not (9 in xs)
	print("{xs.count(1)} {xs.count(it > 2)} {xs.max()} {["b", "a"].min()}")
	prints """
		2 3 some(5) some("a")
		"""

# `zeros(n)` is `n` zeros of the expected element type (a number, a `bool` as `false`, an optional as
# `none`; a list or a `T[n]` is expected, an `i64` when nothing is), and `fill(n, v)` is `n` copies
# of `v`, evaluated once. More sizes make lists of lists, the outer size first and the value of
# `fill` last: `zeros(n, m)`, `fill(n, m, -1)`, each row its own list. A struct has no zero:
# `zeros` of one is an error that asks for `fill(n, T())`. `extend(ys)` appends `ys` and
# `place(at, ys)` writes it over the elements from `at` (plain elements: one copy of the block,
# the program stopping where `ys` would run past the end), `join(sep)` joins a `str[]` or
# `(ref str)[]`, `sum()` adds numbers.
test "zeros, fill, extend, place, join and sum":
	empty f32[] = zeros(3)
	fixed i32[4] = zeros(4)
	rows = fill(2, 2, -1)
	xs = [1, 2]
	xs.extend([3, 4])
	xs.place(1, [7, 8])
	print("{empty} {fixed} {rows} {xs} {xs.sum()} {["a", "b"].join("-")}")
	prints "[0, 0, 0] [0, 0, 0, 0] [[-1, -1], [-1, -1]] [1, 7, 8, 4] 20 a-b"

# `xs.extend(ys.map(f))` (or a filter) of elements that own memory pushes each value onto `xs` as
# it is made, with no list between, unless the steps name `xs` (they then see it before it grows).
test "an extend of a map pushes the values as they are made":
	src = ["b", "c"]
	out = ["a"]
	out.extend(src.map("{it}!"))
	out.extend(out.map("{it}{out.len}"))
	expect out == ["a", "b!", "c!", "a3", "b!3", "c!3"]

# `xs[a..b]` is a window `ref T[]` with no copy (*Slices*); `pick()` an element drawn at random
# (`random`, *Modules*), a `ref T` that stops the program on an empty list.
test "a window and a drawn element":
	xs = [10, 20, 30, 40]
	print(xs[1..3])
	expect xs.pick() in xs
	prints "[20, 30]"

test "pick on an empty list stops the program" stops Failure("pick from an empty list"):
	xs i64[] = []
	print(xs.pick())

# A list of plain values (numbers, structs of them) has `byteSize`, its size in bytes; `bytes()`,
# its bytes lent as a window `ref u8[]`; and `rawBytes()`, a copy of them as a `u8[]`.
type Pair:
	a f32
	b u32

test "a list of plain values as its bytes":
	pairs = [Pair(a = 1.0, b = 7), Pair(a = 2.0, b = 9)]
	print(pairs.byteSize)
	print(pairs.rawBytes())
	print(pairs.bytes().len)
	empty Pair[] = []
	print(empty.rawBytes().len)
	prints """
		16
		[0, 0, 128, 63, 7, 0, 0, 0, 0, 0, 0, 64, 9, 0, 0, 0]
		16
		0
		"""
