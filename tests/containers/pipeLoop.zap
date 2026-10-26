# Pipelines over a list run as one loop with their locals in registers: chains of filters and
# maps under one name or several, aggregate elements read where they are, the first answer of
# all and any, and subexpressions over outer locals computed once (spec 14.3).
type Item:
	name str
	weight i64
	price f64

fn chained(xs i64[], r i64):
	xs.filter(it % 2 == r % 2).map(it + r).sum()

fn renamed(xs i64[], k i64):
	xs
		.filter(it > k)
		.map(it * 3)
		.filter(it % 2 == 0)
		.reduce(0, (acc, d): acc + d - k)

test "chains of filters and maps":
	xs = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
	expect chained(xs, 1) == 30
	expect chained(xs, 2) == 40
	expect renamed(xs, 4) == 60
	expect chained([], 3) == 0

test "aggregates, counts and first answers":
	items = [
		Item(name = "a", weight = 3, price = 1.5),
		Item(name = "bb", weight = 7, price = 2.0),
		Item(name = "ccc", weight = 1, price = 4.0)
	]
	limit = 2
	expect items.count(.weight > limit) == 2
	expect items.any(.name.len == 2)
	expect not items.all(.weight > limit)
	expect items.all(.price > 1.0)
	expect items.map(.price * .weight).sum() == 22.5
	heavy = items.filter(.weight > limit).map(.weight * 10)
	expect heavy.len == 2 and heavy[1] == 70
	expect items.filter(.weight > limit).map(.price).reduce(0.0, (s, p): s + p) == 3.5
