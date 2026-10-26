# 7.2 Pipelines
#
# Collections are processed by method chains (there is no `|` operator), over a list, a fixed
# array or a range (`lo..hi`, `(lo..hi step s)`). Each step compiles to a loop in line, the
# lambda's body inside it with no call per element. `f` and `p` are lambdas, functions by name or
# expressions of `it` and `.hp` (6.3). `map(f)`, `filter(p)` and `flatMap(f)` give a new list;
# `all(p)` and `any(p)` a `bool`, stopping at the first answer; `count(p)` an `i64`; `find(p)` the
# first match and `minBy(key)`, `maxBy(key)` the first element with the smallest or largest key
# (`ref T?` of a list, `T?` of a range: `(0..n).minBy(d[it])` the index); `findIndex(p)` the index
# of the first match in a list, `i64?`; `reduce(start, (acc, x): next)` the accumulator, a
# number or a bool; `sum()` and `sum(f)` the sum of the elements or of `f` over them. A range has
# only these methods.

import fs

type Item:
	name str
	price i64

fn isEven(x i64):
	x % 2 == 0

test "ranges as sources":
	print((0..5).map(it * it))
	print((0..10).filter(it % 3 == 0))
	print((0..5).sum())
	print((1..5).reduce(1, (acc, i): acc * i))
	print((0..10 step 4).map(it))
	print((0..0).sum())
	n = 6
	print((n - 2..n).map(it))
	prints """
		[0, 1, 4, 9, 16]
		[0, 3, 6, 9]
		10
		24
		[0, 4, 8]
		0
		[4, 5]
		"""

test "terminals on lists":
	xs = [3, 8, 1, 6]
	expect xs.all(it > 0)
	expect not xs.all(it > 1)
	expect xs.any(it == 6)
	expect not xs.any(it > 8)
	expect xs.count(it > 2) == 3
	expect (xs.find(it > 5) ?? 0) == 8
	expect (xs.find(it > 9) ?? -1) == -1
	expect xs.reduce(0, (acc, x): acc + x) == 18
	expect (xs.minBy(it) ?? 0) == 1
	expect (xs.maxBy(-it) ?? 0) == 1
	empty i64[] = []
	expect empty.all(it > 100)
	expect not empty.any(it > 100)
	expect (empty.minBy(it) ?? 7) == 7

test "terminals on ranges":
	expect (1..10).all(it > 0)
	expect (1..10).any(it * it == 49)
	expect (0..100).count(it % 10 == 0) == 10
	expect ((1..100).find(it * it > 50) ?? 0) == 8
	expect ((1..5).find(it > 50) ?? -1) == -1
	ks = [5, 3, 9, 1, 7]
	expect ((0..ks.len).minBy(ks[it]) ?? -1) == 3 and ((0..ks.len).maxBy(ks[it]) ?? -1) == 2
	expect (0..0).minBy(ks[it]) == none and ((1..10 step 3).maxBy(-it) ?? 0) == 1
	expect (0..ks.len).sortedBy(ks[it]) == [3, 1, 0, 4, 2]

test "flatMap joins the lists its lambda gives, in order":
	print([1, 2].flatMap([it, it * 10]))
	print((0..3).flatMap((0..it).map(it)))
	words = ["ab", "c"]
	print(words.flatMap([.copy(), .copy()]))
	prints """
		[1, 10, 2, 20]
		[0, 0, 1]
		["ab", "ab", "c", "c"]
		"""

test "structs and strings":
	items = [
		Item(name = "pen", price = 3),
		Item(name = "book", price = 20),
		Item(name = "cup", price = 7)
	]
	expect items.map(.price).sum() == 30
	expect (items.maxBy(.price)?.name ?? "") == "book"
	expect (items.minBy(.name)?.name ?? "") == "book"
	expect (items.find(.name.startsWith("c"))?.price ?? 0) == 7
	expect items.count(.price > 5) == 2
	expect items.any(.name == "pen")

test "a named function stands where a lambda would":
	xs = [1, 2, 3, 4]
	expect xs.count(isEven) == 2
	expect xs.all(isEven) == false
	expect (xs.find(isEven) ?? 0) == 2
	expect (0..9).count(isEven) == 5

type Slot:
	name str
	hp i64

test "findIndex gives the index of the first element its lambda holds for":
	xs = [Slot(name = "a", hp = 3), Slot(name = "bb", hp = 0), Slot(name = "c", hp = 5)]
	print("{xs.findIndex(.hp == 0) ?? -1} {xs.findIndex(.name == "c") ?? -1} {xs.findIndex(.hp > 9) ?? -1}")
	ns = [4, 8, 15]
	print(ns.findIndex(it > 5) ?? -1)
	prints """
		1 2 -1
		1
		"""

test "a range has only the pipeline methods" refuses RangeLacksMethod:
	print((0..3).len)

# Python's `reversed(range(n))` counts down with a step: `n - 1..-1 step -1`.
test "a range has no reversed" refuses RangeLacksMethod:
	for i in (0..3).reversed():
		print(i)

test "reduce keeps a number" refuses ReduceAccumulator:
	print([1].reduce("", (acc, x): acc))

test "flatMap builds lists" refuses FlatMapBorrows:
	xs = [1]
	print([1].flatMap(x: xs))

test "an array as a source":
	stats i32[4] = [3, 1, 4, 1]
	print(stats.sum())
	fs f64[3] = [0.5, 1.5, 2.0]
	print(fs.sum())
	print(stats.map(it * 2))
	print("{stats.all(it > 0)} {stats.count(it == 1)}")
	print(fs.reduce(1.0, (acc, f): acc * f))
	names str[2] = ["ab", "c"]
	print(names.map(.len))
	prints """
		9
		4
		[6, 2, 8, 2]
		true 2
		1.5
		[2, 1]
		"""

test "an array keeps no references out" refuses FixedArrayLacksMethod:
	a i64[2] = [1, 2]
	print(a.find(x: x > 1))

type Mob:
	hp i64
	alive bool
	at Spot

type Spot:
	x f32

test "a field's function, sums of a function, and properties without parentheses":
	ms = [
		Mob(hp = 3, alive = true, at = Spot(x = 1.5)),
		Mob(hp = 5, alive = false, at = Spot(x = 2.5))
	]
	expect ms.sum(.hp) == 8
	expect ms.count(.alive) == 1
	expect ms.filter(.alive).len == 1
	expect ms.map(.at.x) == [1.5, 2.5]
	expect (ms.maxBy(.hp)?.hp ?? 0) == 5
	expect not ms.isEmpty
	expect "hello".len == 5

# `sortedBy(key)` is a stable sorted copy, its key one of a sort's (3.4); a `str` key that is part
# of the element is compared in place.

type User:
	name str
	age i64

test "sortedBy orders by the key it is given, ties in their order":
	us = [User(name = "bo", age = 20), User(name = "al", age = 10), User(name = "cy", age = 20)]
	expect (us.filter(.age > 18).map(.name).sortedBy(it)) == ["bo", "cy"]
	print("{us.sortedBy(.name).map(.age)} {[3, 1, 2].sortedBy(-it)}")
	prints """
		[10, 20, 20] [3, 2, 1]
		"""

# `mean()` and `mean(f)` give the mean of the elements or of `f` over them, an `f64` (NaN of none);
# `groupBy(key)` a `{K: T[]}`, each key with copies of the elements that have it, in order (a `str`
# part of the element as a key is copied into the map); `countBy(key)` a `{K: i64}`; `zip(ys)` a
# `(T, U)[]` of copies of the elements and of the list `ys`'s at each index, as long as the
# shorter. They take a list, a range or a `Seq`, and the `map` (of numbers) and `filter` steps
# before them run in their loop.

test "mean, groupBy, countBy and zip":
	words = ["fig", "apple", "kiwi", "plum", "banana"]
	print(words.groupBy(.len))
	print(words.filter(.len > 3).groupBy(.len))
	print("{(0..10).countBy(it % 3)} {words.countBy(.len)}")
	print([1, 2, 3].zip(["a", "b"]))
	print("{[1, 2, 3, 4].mean()} {[1.5, 2.5].mean()} {words.mean(.len)} {(0..0).mean()}")
	us = [User(name = "a", age = 20), User(name = "b", age = 10)]
	print(us.groupBy(.name))
	prints r"""
		{3: ["fig"], 4: ["kiwi", "plum"], 5: ["apple"], 6: ["banana"]}
		{4: ["kiwi", "plum"], 5: ["apple"], 6: ["banana"]}
		{0: 4, 1: 3, 2: 3} {3: 1, 4: 2, 5: 1, 6: 1}
		[(1, "a"), (2, "b")]
		2.5 2 4.4 NaN
		{"a": [User(name = "a", age = 20)], "b": [User(name = "b", age = 10)]}
		"""

test "zip pairs with one list" refuses ZipOfOneList:
	xs = [1]
	print(xs.zip([1], [2]))

# Steps feeding another step run in its loop, so `ms.filter(.alive).map(.hp).sum()` and
# `for h in ms.filter(.alive).map(.hp)` make no list between them; a list is made where the chain
# is bound to a name or returned (or where a `map` makes values that own memory). A chain of `map`
# and `filter` steps ending in `map`, `filter` or `sortedBy` is one loop too, the last step's list
# the only one made (`sortedBy` sorts the values gathered in place, keyed in the same loop). A
# pipeline makes a value; code that does something for each element is a `for` over it, or
# `each(f)` at the pipeline's end, the same loop written where the chain goes on: `xs.each(f)` as
# a statement is `for x in xs:` with f's body (a lambda of one parameter, or of `it` and `.hp`),
# and a lambda of two is `for a, b in xs:` (an index and an element, a map's key and value).
# `parallel()` runs the rest of the pipeline on every processor: `groupBy` and `countBy` group each
# processor's part and merge the parts by key in order; `.parallel().each(x: ...)` runs f on every
# processor, the elements in no order, and f may not change what it captures.

test "each ends a pipeline as a for loop does":
	ms = [
		Mob(hp = 3, alive = true, at = Spot(x = 1.5)),
		Mob(hp = 5, alive = false, at = Spot(x = 2.0)),
		Mob(hp = 7, alive = true, at = Spot(x = 0.5))
	]
	total = 0
	ms.filter(.alive).sortedBy(-.hp).each(print(.hp))
	ms.each(m:
		total += m.hp
	)
	(0..2).each(print(it))
	["a", "b"].each((i, w): print("{i} {w}"))
	ms.groupBy(.hp % 2).each((k, group): print("{k} {group.len}"))
	print(total)
	prints """
		7
		3
		0
		1
		0 a
		1 b
		1 3
		15
		"""

test "maps and filters run in the loop of what consumes them":
	ms = [
		Mob(hp = 3, alive = true, at = Spot(x = 1.5)),
		Mob(hp = 5, alive = false, at = Spot(x = 2.0)),
		Mob(hp = 7, alive = true, at = Spot(x = 0.5))
	]
	print("{ms.filter(.alive).sum(.hp)} {ms.filter(.alive).map(.at.x).sum()} {ms.map(.hp).filter(it > 4).count(it < 7)}")
	print(ms.filter(.alive).map(.hp).map(it * 10))
	print((0..10).filter(it % 2 == 0).map(it * it).sum())
	names = ["a", "bb", "ccc"]
	for n in names.filter(.len > 2): print(n)
	for h in ms.filter(.alive).map(.hp):
		if h > 5: break
		print(h)
	shown = []
	for v in (0..10).filter(it % 3 == 0).map(it * 10):
		if v == 30: continue
		shown.push("{v}")
	print(shown.join(" "))
	n = 0
	for x in [1, 2, 3, 4].map(it * it).filter(it > 3):
		n += x
	print(n)
	prints """
		10 2 1
		[30, 70]
		120
		ccc
		3
		0 60 90
		29
		"""

test "a chain of maps, filters and a sort makes only its result":
	xs = (0..50).map(it * 7 % 11)
	before = allocations()
	fused = xs.map(it + 1).filter(it % 2 == 0).map(it * 3).sortedBy(-it)
	made = allocations() - before
	start = allocations()
	a = xs.map(it + 1)
	b = a.filter(it % 2 == 0)
	c = b.map(it * 3)
	kept = c.sortedBy(-it)
	expect fused == kept and made < allocations() - start

# A chain, like a loop over windows (`lines()`, `split`, `slice`), reads its source in place while it
# runs: changing the source meanwhile, in a lambda or in the loop's body, is an error, and the
# elements a loop over `filter` steps gets are lent from the source. A `map` to a `str` part of the
# element lends it: a `(ref str)[]` into the elements, which cannot change while it is used
# (filters before it run in its loop and borrow too). A temporary list cannot be lent beyond its
# statement: `load().map(u: u.name.copy())`.

test "the source cannot change while a chain reads it" refuses ChangeWhileRead:
	mut xs = [1, 2, 3]
	for x in xs.filter(it > 1):
		xs.push(x)

# A function the lambda calls that only grows a list holding the one gone over (a push onto the
# nodes whose one node's kids `all` reads) moves the elements, not their own lists: the consumers
# that read their source's header once, before any lambda runs (all, any, count, find, findIndex,
# each), allow it. Growing the list gone over itself stays an error.

type Branch:
	kids i64[]

type Forest:
	nodes Branch[]

fn sprout(mut f Forest, k i64):
	f.nodes.push(Branch(kids = [k]))
	k > 0

test "a lambda may grow the list holding the one gone over":
	f = Forest(nodes = [Branch(kids = [1, 2, 3])])
	expect f.nodes[0].kids.all(f.sprout(it))
	expect not f.nodes[0].kids.any(f.sprout(it - 3))
	expect f.nodes.len == 7

test "a lambda may not grow the list gone over" refuses ChangeWhileRead:
	type Branch:
		kids i64[]
	type Forest:
		nodes Branch[]
	fn sproutHere(mut f Forest, k i64) bool:
		f.nodes[0].kids.push(k)
		k > 0
	mut f = Forest(nodes = [Branch(kids = [1, 2, 3])])
	print(f.nodes[0].kids.all(k: sproutHere(f, k)))

fn namesOf(items Item[]):
	items.map(.name)

test "a map to a str of the elements lends it":
	items = [Item(name = "pen", price = 2), Item(name = "ink", price = 5)]
	names = items.map(.name)
	print(names)
	print(namesOf(items).join("+"))
	dear = items.filter(.price > 3).map(.name)   # the filter runs in the map's loop: into items
	print(dear)
	for n in items.map(.name):
		print(n.len)
		break
	prints """
		["pen", "ink"]
		pen+ink
		["ink"]
		3
		"""

test "lent strs keep their list from changing" refuses ChangeWhileBorrowed:
	type Item:
		name str
		price i64

	mut items = [Item(name = "pen", price = 2)]
	names = items.map(.name)
	items.clear()
	print(names)

test "lent strs cannot outlive a temporary list" refuses RefToTemporaryElements:
	type Item:
		name str
		price i64

	fn made() Item[]:
		[Item(name = "pen", price = 2)]

	names = made().map(.name)
	print(names)

test "lent strs of a temporary cannot be returned" refuses ReturnTemporaryRef:
	type Item:
		name str
		price i64

	fn made() Item[]:
		[Item(name = "pen", price = 2)]

	fn names() (ref str)[]:
		made().map(.name)

	print(names())

# `zip` pairs two lists that come apart (a file's columns, two results); lists a program keeps side
# by side are one list of a struct of their fields: one allocation, one stream walked, and lengths
# that cannot part. Where a loop reads few fields of many rows, a `Table<T>` keeps the columns apart
# behind the same reads.

test "groupBy and countBy in parallel give what the serial ones give":
	ms = (0..5000).map(Mob(hp = (it * 7919) % 13, alive = it % 3 == 0, at = Spot(x = 1.0)))
	serial = ms.groupBy(.hp)
	par = ms.parallel().groupBy(.hp)
	same = serial.keys().all(serial[it].map(.alive) == par[it].map(.alive))
	print("{serial.len == par.len} {same}")
	a = ms.countBy(.hp)
	b = ms.parallel().countBy(.hp)
	print(a.len == b.len and a.keys().all(a[it] == b[it]))
	c = ms.filter(.alive).countBy(.hp)
	d = ms.parallel().filter(.alive).countBy(.hp)
	print(c.len == d.len and c.keys().all(c[it] == d[it]))
	e = (0..100).groupBy(it % 4)
	f = (0..100).parallel().groupBy(it % 4)
	print(e.len == f.len and e.keys().all(e[it] == f[it]))
	prints """
		true true
		true
		true
		true
		"""

test "parallel each runs f on every element, in no order":
	ms = [
		Mob(hp = 3, alive = true, at = Spot(x = 1.5)),
		Mob(hp = 5, alive = false, at = Spot(x = 2.0))
	]
	seen = zeros(2)
	(0..2).parallel().each(i:
		seen[i] = ms[i].hp * 2
	)
	expect seen == [6, 10]

test "each walks the map a parallel pipeline grouped into":
	xs = [5, 2, 4, 1]
	xs.parallel().filter(it > 1).sortedBy(it).groupBy(it % 2).each((k, group): print("{k} {group}"))
	prints """
		0 [2, 4]
		1 [5]
		"""
