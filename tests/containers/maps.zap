# a map of text windows ({ref str: V}) keeps each key in one word: every operation, keys of
# any length (one of 70000 bytes), owned values, copies, removals, growth and the first k of a
# sort walking the cells
#
# hash() on the key types, and maps over owning values: removal, reinsertion after growth,
# clearing and a table decoded from JSON, with freed blocks poisoned (as zap test runs them).
#
# Maps returned from functions: a map is one pointer in the backend, so moving it out of a
# local, out of an explicit `move`, or through a temporary must hand the entries over intact.
#
# f32 values handed to the runtime's generic functions (a map literal's mapSet, groupBy, zip) as
# the single's bits, as any call passes them.

test "a map that churns keys keeps its entries right as it compacts":
	m {str: i64} = {}
	mirror = fill(150, -1)   # the value at each key, -1 when absent
	for r in 0..40:
		for i in 0..200:
			k = (i * 7 + r) % 150
			m["k{k}"] = i * 1000 + r
			mirror[k] = i * 1000 + r
			if i % 3 == 0:
				m.remove("k{i % 150}")
				mirror[i % 150] = -1
	same = m.len == mirror.filter(it >= 0).len
	for k in 0..150:
		same = same and (m.get("k{k}") ?? -1) == mirror[k]
	expect same
	print("k150" in m)
	prints """
		false
		"""

text = "the quick brown fox jumps over the lazy dog the end {"x".repeat(70_000)}"
words = text.split(" ")
mut counts {ref str: i64} = {}
for w in words:
	counts.add(w, 1)
print("{counts.len} {counts["the"]} {counts.get("fox")} {counts.get("cat")} {"dog" in counts}")
long = words[len - 1]
print("{long.len} {counts[long]}")
counts["fox"] = 10
counts["dog"] += 5
print(counts.keys().filter(.len < 10).sorted())
print(counts.values().sum())
counts.remove("the")
print("{counts.remove("the")} {counts.len} {"the" in counts}")
mut groups {ref str: i64[]} = {}
for i, w in words:
	if groups.get(w) is mut xs:
		xs.push(i)
	else:
		groups[w] = [i]
copy = groups.copy()
groups.clear()
print("{groups.len} {copy.len} {copy["the"]} {copy.get("zzz")}")
mut many {ref str: i64} = {}
all = (0..5000).map("w{it}").join(" ")
for w in all.split(" "):
	many.add(w, 2)
for w in all.split(" "):
	if w.len == 3:
		many.remove(w)
print("{many.len} {many.values().sum()} {many.get("w999")} {many.get("w1000")}")
small {ref str: i64} = {}
mut s2 = small
s2.add("b", 2)
s2.add("a", 1)
print(s2)
print(s2.entries().sorted())
print(counts.keys().sortedBy(-(counts.get(it) ?? 0), it)[..3])
print(counts.keys().count(it < "f"))
print(counts.keys().sortedBy(-.len)[..2].map(.len))
print(counts.values().sortedBy(-it)[..2])
mut mixed {ref str: i64} = {}   # keys of a literal and of the heap: addresses far apart
mixed.add("ab", 1)
for w in words[..4]:
	mixed.add(w, 2)
mixed.add("cd", 3)
print(mixed.keys().sorted())

type Named:
	id i32
	names str[] = []

test "a value taken out of a map whose keys are narrower than a word is whole":
	m {i32: Named} = {}
	for i in 0..20:
		m[i32(i)] = Named(id = i32(i), names = ["a{i}", "b{i}"])
	out = []
	for i in 18..22:
		out.push(m.remove(i32(i)) ?? Named(id = -1))
	print(out.map("{.id}:{.names.join(",")}").join(" "))
	prints """
		18:a18,b18 19:a19,b19 -1: -1:
		"""

test "a map of text windows":
	main()
	prints r"""
		10 3 some(1) none true
		70000 1
		["brown", "dog", "end", "fox", "jumps", "lazy", "over", "quick", "the"]
		26
		none 9 false
		0 10 [0, 6, 9] none
		4910 9820 some(2) some(2)
		{"b": 2, "a": 1}
		[("a", 1), ("b", 2)]
		["fox", "dog", "brown"]
		3
		[70000, 5]
		[10, 6]
		["ab", "brown", "cd", "fox", "quick", "the"]
		"""

type Inventory:
	items {str: str[]}

test "keys hash alike when equal, and a map grows, shrinks and clears through its hashes":
	print(7.hash() == 7.hash())
	print(7.hash() == 8.hash())
	print("abc".hash() == "ab".hash())
	print("a longer key of many bytes".hash() == "a longer key of many bytes".hash())
	print((-1).hash() == i32(-1).hash())   # the same integer at any width
	bags {str: str[]} = {}
	for i in 0..40:
		bags["bag{i}"] = ["x{i}", "y{i}"]
	for i in 0..40:
		if i % 3 == 0:
			bags.remove("bag{i}")
	print(bags.len)
	print(bags.get("bag4") ?? [])
	print("bag3" in bags)
	bags["bag3"] = ["back"]
	print(bags.get("bag3") ?? [])
	print(bags.keys().len)
	counts {i64: i64} = {}
	for i in 0..1000:
		counts.add(i % 17, 1)
	print(counts.get(5) ?? 0)
	print(counts.len)
	counts.clear()
	print(counts.isEmpty)
	counts.add(-3, 2)
	print(counts)
	inv = Inventory.fromJson(
		"\{\"items\":\{\"sword\":[\"iron\"],\"potion\":[\"red\",\"blue\"]\}\}"
	) ??
		Inventory(items = {})
	print(inv.items.get("potion") ?? [])
	print("shield" in inv.items)
	prints r"""
	    true
	    false
	    false
	    true
	    true
	    26
	    ["x4", "y4"]
	    false
	    ["back"]
	    27
	    59
	    17
	    true
	    {-3: 2}
	    ["red", "blue"]
	    false
	    """

test "a map whose lambda gives none makes optional elements, written over and dropped as any":
	ring Box<i64>?[] = (0..4).map(_: none)
	for i in 0..10:
		ring[i & 3] = Box(i)
	for b in ring:
		print(b != none)
	prints """
		true
		true
		true
		true
		"""

test "a map of owned keys rebuilt in place many times keeps every key that stays":
	m {str: i64} = {}
	for i in 0..20000:
		m["k{i * 7919 % 20011}"] = i
		if i % 3 == 0:
			m.remove("k{(i / 2) * 7919 % 20011}")
	sum = 0
	wrong = 0
	for i in 0..20000:
		if m.get("k{i * 7919 % 20011}") is v:
			sum += v
			if v != i:
				wrong += 1
	print("{m.len} {m.keys().len} {wrong} {sum}")
	prints """
		13333 13333 0 166660000
		"""

fn letterCounts(text str):
	m {str: i64} = {}
	for i in 0..text.len:
		m.add(text[i..i + 1], 1)
	m
fn literal():
	m = { "x": 1, "y": 2 }
	m
fn moved() {i64: i64}:
	m {i64: i64} = {}
	m[7] = 70
	move m

test "a map made in a function is returned whole":
	print(letterCounts("ACGTACGA").len)
	c = letterCounts("ACGTACGA")
	print(c.get("A") ?? 0)
	print(literal().get("y") ?? 0)
	print(moved().get(7) ?? 0)
	print(letterCounts("zz").len + literal().len)
	prints """
	    4
	    3
	    2
	    70
	    3
	    """

fn ones(k i64):
	m {i64: i64} = {}
	for i in 0..k:
		m.add(i, 1)
	m

test "maps a list's map makes are the list's":
	tables = [1, 2, 3].map(ones(it))
	again = tables[1]
	print("{tables.map(.len)} {again.len} {again[1]}")
	prints "[1, 2, 3] 2 1"

test "a block lambda's local map is the list's":
	tables = [1, 2, 3].map(k:
		total = ones(k)
		total.add(10, 1)
		total
	)
	expect tables.map(.len) == [2, 3, 4]

test "pipelines over a map's keys and values walk its cells in place, past removed keys":
	m {str: i64} = {}
	for i in 0..50:
		m["w{i}"] = i * 3 % 17
	for i in 0..50:
		if i % 4 == 0:
			m.remove("w{i}")
	print(m.keys().count(.len == 2))
	print(m.values().sum())
	print(m.values().filter(it > 10).count(v: true))
	print(m.keys().map(.len).sum())
	print(m.keys().any(it == "w7"))
	print(m.keys().all(.startsWith("w")))
	print(m.values().reduce(0, (a, v): a.max(v)))
	print(m.keys().sortedBy(-(m.get(it) ?? 0), it)[..5])
	print(m.values().sortedBy(it)[..4])
	print(m.keys().map("{it}!").filter(.len < 4).sortedBy(it)[..3])
	total = 0
	for k in m.keys():
		total += k.len
	print(total)
	prints """
		7
		291
		12
		104
		true
		true
		16
		["w11", "w45", "w22", "w39", "w5"]
		[0, 0, 1, 1]
		["w1!", "w2!", "w3!"]
		104
		"""

fn speeds() {str: f32}:
	{"a": 2.0}

test "a map literal, groupBy and zip keep f32 values":
	x f32 = 7.5
	m {str: f32} = {"speed": 7.0, "x": x}
	print("{m["speed"]} {m["x"]} {speeds()["a"]}")
	k {i32: f32} = {1: 9.5}
	print(k[1])
	xs f32[] = [1.5, 2.5, 3.5]
	print(xs.groupBy(1 if it > 2.0 else 0))
	print(xs.zip([1, 2, 3]))
	prints r"""
		7 7.5 2
		9.5
		{0: [1.5], 1: [2.5, 3.5]}
		[(1.5, 1), (2.5, 2), (3.5, 3)]
		"""

test "an integer map that removes and adds many keys in small tables finds exactly its keys":
	for span in [20, 37, 90, 300]:
		m {i64: i64} = {}
		present bool[] = zeros(span)
		state u64 = 12_345
		for step in 0..4000:
			state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407
			k = i64((state >> 33) % u64(span))
			if (state >> 20) % 3 == 0:
				m.remove(k)
				present[k] = false
			else:
				m[k] = step
				present[k] = true
			if step % 97 == 0:
				for j in 0..span:
					expect (j in m) == present[j]
		expect m.len == present.count(it)
