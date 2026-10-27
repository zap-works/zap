# 7.4 Maps: `{K: V}`
#
# `m[k] = v` inserts or replaces, `m[k]` reads the value and stops the program when `k` is not a
# key, `get(k)` gives a `ref V?`; `k in m` asks whether `k` is a key and `remove(k)` moves its
# value out (`V?`); `len`, `isEmpty` and `clear()` as a list's. A map is written by its index alone.
# `for k, v in m:` goes over its keys with their values (v a reference to the value), in the map's
# own order.

type Player:
	name str
	hp i64

type Tile:
	kind i64
	edits i64

type PipeKey:
	layout i64
	blend i64
	lines bool
	name str

type Nested:
	key PipeKey
	n u32

test "index, get, in, remove and the size":
	scores {str: i64} = {}
	print(scores.isEmpty)
	scores["ana"] = 10
	scores["bia"] = 20
	scores["ana"] = 15
	print("{scores.len} {scores["ana"]} {scores.get("ana")} {scores.get("zed")} {"bia" in scores}")
	print("{scores.remove("ana")} {scores.remove("ana")} {scores.len}")
	players = {
		1: Player(name = "Ana", hp = 30),
		2: Player(name = "Bia", hp = 25),
	}
	players[3] = Player(name = "Caio", hp = 40)
	print(players.values().map(.hp).sum())
	big {i64: i64} = {}
	for i in 0..1000:
		big[i] = i * 2
	for i in 0..500:
		big.remove(i)
	print("{big.len} {big[777]} {big.keys().sorted().first}")
	big.clear()
	print(big.len)
	prints """
		true
		2 15 some(15) none true
		some(15) none 1
		95
		500 1554 some(500)
		0
		"""

# `m.reserve(n)` makes room for n keys at once: a map that is to hold that many is not rebuilt on
# the way.
test "a map takes room for its keys at once":
	m {i64: i64} = {}
	m.reserve(1000)
	for i in 0..1000:
		m[i] = i * 2
	names {str: i64} = {}
	names.reserve(3)
	names["a"] = 1
	expect m.len == 1000
	expect m[999] == 1998
	expect names["a"] == 1

test "a copy of a map finds every key, those whose probe runs past its last cell too":
	m {i64: i64} = {}
	for i in 0..2000:
		m[i * 7919] = i
	texts {str: i64} = {}
	for i in 0..2000:
		texts["k{i}"] = i
	copied = m
	copiedTexts = texts
	expect (0..2000).all((copied.get(it * 7919) ?? -1) == it)
	expect (0..2000).all((copiedTexts.get("k{it}") ?? -1) == it)

test "a map of optional values":
	seen {str: i64?} = {}
	seen["a"] = none
	seen["b"] = 3
	given {str: i64?} = {"b": 2, "c": none}
	print("{seen} {given} {given["b"]}")
	prints r"""
		{"a": none, "b": some(3)} {"b": some(2), "c": none} some(2)
		"""

test "m[k] stops the program when k is not a key" stops Failure("the key is not in the map"):
	m {str: i64} = {}
	m["a"] = 1
	print(m["b"])

# A map keeps no order: `keys()`, `values()` and `entries()` (each key with its value, a `(K, V)[]`)
# follow its cells, the same for the same keys added the same way; a map is printed, and written as
# JSON, with its integer or text keys sorted.
test "a map walks in its own order and prints sorted":
	m {str: i64} = {}
	m["b"] = 2
	m["a"] = 1
	m["c"] = 3
	m.remove("c")
	print(m.entries().sorted())
	print(m)
	print(m.keys().sorted())
	prints r"""
		[("a", 1), ("b", 2)]
		{"a": 1, "b": 2}
		["a", "b"]
		"""

# `m[k]` and an arm of `m.get(k)` change a value in place, a number or a str too (`t = v` and
# `t += v` of `is mut t` write through it); `m[k] += 5` stops the program when
# `k` is absent (`add` and `setDefault`, below, give a missing key its start).
test "values change in place":
	world {i64: Tile} = {}
	world[7] = Tile(kind = 1, edits = 0)
	if world.get(7) is mut t:
		t.kind = 4
		t.edits += 1
	print(world.get(7))
	byParity {str: i64[]} = {}
	for i in 0..6:
		parity = "even" if i % 2 == 0 else "odd"
		if byParity.get(parity) is mut xs:
			xs.push(i)
		else:
			byParity[parity] = [i]
	print(byParity)
	world[7].edits += 2
	world[7].kind += 1
	print("{world[7].edits} {world[7].kind}")
	totals {str: f64} = {}
	totals["a"] = 1.5
	if totals.get("a") is mut total:
		total += 2.0
	print(totals["a"])
	prints r"""
		some(Tile(kind = 4, edits = 1))
		{"even": [0, 2, 4], "odd": [1, 3, 5]}
		3 5
		3.5
		"""

# While a value lent by `m[k]` or `get` is used, the map gains and loses no keys.
test "a value read by m[k] keeps the map's keys as they are" refuses ChangeWhileBorrowed:
	mut m {str: i64[]} = {}
	m["a"] = [1]
	xs = m["a"]
	m["b"] = [2]
	print(xs)

test "a value of a map of windows changed through get: the keys' text is not what it changes":
	words = "the a the b".split(" ")
	groups {ref str: i64[]} = {}
	for i, w in words:
		if groups.get(w) is mut xs:
			xs.push(i)
		else:
			groups[w] = [i]
	print(groups)
	prints "\{\"b\": [3], \"the\": [0, 2], \"a\": [1]}"

# `add(k, n)` adds `n` to an integer value, from 0 for a new key; a window key is copied only when
# it is inserted, so counting the windows of a text allocates no string per window.
test "add counts from 0 for a new key and copies a window key only when it inserts it":
	text = "abcabcabd"
	counts {str: i64} = {}
	for i in 0..text.len - 1:
		counts.add(text[i..i + 2], 1)
	print(counts)
	big {i64: i64} = {}
	big.add(7, 100)
	big.add(7, -1)
	print(big[7])
	prints r"""
		{"ab": 3, "bc": 2, "bd": 1, "ca": 2}
		99
		"""

# `setDefault(k, v)` puts v under k unless k is a key already (Python's `setdefault`, and
# `defaultdict`): the value read after it is there, so it is changed in place by `m[k]`; the key
# is only read, copied when it enters the map.
test "setDefault gives a missing key its value, and leaves a present one":
	words = "to be or not to be".split(" ")
	positions {str: i64[]} = {}
	seen {ref str: i64[]} = {}
	for i, w in words:
		positions.setDefault(w, [])
		positions[w].push(i)
		seen.setDefault(w, [])
		seen[w].push(i)
	print(positions)
	print("{seen["to"]} {seen.len}")
	names {i64: str} = {}
	names.setDefault(1, "first")
	names.setDefault(1, "second")
	print(names)
	prints r"""
		{"be": [1, 5], "not": [3], "or": [2], "to": [0, 4]}
		[0, 4] 4
		{1: "first"}
		"""

# Keys are integers, strings, `ref str` (the map borrows its keys), or structs of those and bools,
# compared with `==` and hashed field by field; not floats.
test "a struct of integers, strings and bools is a map key, hashed field by field":
	m {PipeKey: i64} = {}
	for i in 0..1000:
		m[PipeKey(layout = i % 10, blend = i / 10, lines = i % 3 == 0, name = "p{i % 7}")] = i
	print(m.len)
	print(m.get(PipeKey(layout = 3, blend = 51, lines = true, name = "p2")) ?? -1)
	print(m.get(PipeKey(layout = 3, blend = 51, lines = false, name = "p2")) == none)
	nested {Nested: str} = {}
	nested[Nested(key = PipeKey(layout = 1, blend = 2, lines = true, name = "a"), n = 4)] = "four"
	print(nested.get(Nested(key = PipeKey(layout = 1, blend = 2, lines = true, name = "a"), n = 4)))
	words = "to be or not to be".split(" ")
	seen {ref str: i64} = {}
	for w in words:
		seen.add(w, 1)
	print("{seen["to"]} {seen.len}")
	prints """
		1000
		513
		true
		some("four")
		2 4
		"""

test "for k, v goes over a map's keys and values, its text keys borrowed too":
	scores {str: i64} = {}
	scores["ana"] = 3
	scores["bia"] = 5
	scores["caio"] = 7
	scores.remove("bia")
	lines = []
	for name, score in scores:
		lines.push("{name} {score}")
	print(lines.sorted())
	words = "to be or not to be".split(" ")
	seen {ref str: i64} = {}
	for w in words:
		seen.add(w, 1)
	total = 0
	for word, n in seen:
		if word == "or": continue
		total += n
	print(total)
	prints """
		["ana 3", "caio 7"]
		5
		"""

test "a float is not a map key" refuses MapKeyType:
	type Point:
		x f32

	mut m {Point: i64} = {}
	print(m.len)

# A type of a program or a library is indexed the same way when it declares `index` (`x[k]`),
# `indexMut` (a change through `x[k]`) and `set` (`x[k] = v`), as `env` and `Pool<T>` do.
type Board:
	cells i64[]

	fn index(at i64) ref i64:
		cells[at]

	fn indexMut(at i64) mut ref i64:
		found = mut ref cells[at]
		found

	fn set(at i64, v i64):
		cells[at] = v

test "a type with index, indexMut and set is indexed as a map":
	b = Board(cells = [0, 0, 0])
	b[1] = 5
	b[1] += 2
	print("{b[1]} {b.cells}")
	prints "7 [0, 7, 0]"
