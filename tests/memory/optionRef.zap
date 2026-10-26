# An optional reference has no tag: one word, the target's address, 0 for none. Lookups, finds,
# fields, lists and returns of them read like any optional.
type Item:
	name str
	weight i64

type Pick:
	best ref Item?
	count i64

type Point:
	x i64
	y i64

fn heaviest(items Item[]) ref Item?:
	if items.isEmpty: return none
	best = 0
	for i in 1..items.len:
		if items[i].weight > items[best].weight:
			best = i
	items[best]

fn nameOf(item ref Item?):
	match item:
		found: found.name
		none: "-"

fn firstWeight(items Item[]) i64?:
	w = try items.first
	w.weight

fn weightOf(item ref Item?):
	item?.weight ?? -1

items = [Item(name = "a", weight = 3), Item(name = "b", weight = 9), Item(name = "c", weight = 5)]

test "an optional reference as a result, a parameter and a match":
	print(
		"{nameOf(heaviest(items))} {nameOf(heaviest([]))} {weightOf(items.first)} {weightOf(none)}"
	)
	e = []
	print("{firstWeight(items) ?? -1} {firstWeight(e) ?? -1}")
	prints """
		b - 3 -1
		3 -1
		"""

test "lookups and finds give one":
	m = {"x": 4, "y": 7}
	scores = [2, 8, 5]
	print("{m.get("y") ?? 0} {m.get("z") ?? 0} {scores.first ?? 0} {scores.last ?? 0} {scores.max() ?? 0}")
	print("{nameOf(items.find(.weight > 4))} {nameOf(items.find(.weight > 9))}")
	e Item[] = []
	print(
		"{nameOf(items.minBy(.weight))} {nameOf(items.maxBy(.weight))} {nameOf(e.maxBy(.weight))}"
	)
	prints """
		7 0 2 5 8
		b -
		a b -
		"""

test "a field through one, a presence test and a struct of numbers read through":
	e Item[] = []
	print("{items.first?.weight} {e.first?.weight} {items.first != none} {e.first == none}")
	pts = [Point(x = 1, y = 2)]
	none0 Point[] = []
	p = pts.first ?? Point(x = 0, y = 0)
	q = none0.first ?? Point(x = -1, y = -1)
	print("{p.x} {p.y} {q.x} {q.y}")
	prints """
		some(3) none true true
		1 2 -1 -1
		"""

test "a view's field and a list of them":
	v = Pick(best = heaviest(items), count = items.len)
	w = Pick(best = none, count = 0)
	print("{nameOf(v.best)} {v.count} {nameOf(w.best)}")
	refs = []
	refs.push(items.first)
	refs.push(none)
	refs.push(items.last)
	print(refs.map(nameOf(it)))
	prints """
		b 3 -
		["a", "-", "c"]
		"""

test "a pool's lookup":
	pool = Pool<Item>()
	h = pool.add(Item(name = "p", weight = 1))
	print(nameOf(pool.get(h)))
	pool.remove(h)
	print(nameOf(pool.get(h)))
	prints """
		p
		-
		"""

fn handleAt(m {i64: Handle<i64>}, k i64) Handle<i64>?:
	m.get(k)

test "get of a map of handles gives an optional handle":
	pool = Pool<i64>()
	pool.add(1)
	h = pool.add(2)
	m {i64: Handle<i64>} = {}
	m[3] = h
	print((handleAt(m, 3) ?? fail("none")).index)
	print(handleAt(m, 4) == none)
	prints """
		1
		true
		"""
