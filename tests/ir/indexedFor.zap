# for i, x in xs over structs of numbers: x is a reference to the element, read through its address.
type Ball:
	x f64
	r f64
	hits i64

fn nearest(balls Ball[]):
	best = 1e300
	for i, b in balls:
		d = b.x - i
		if d < best:
			best = d
	best

fn weighed(balls Ball[]):
	total = 0
	for i, b in balls:
		total += b.hits * 10 + i
	total

test "indexed for over structs":
	balls = [Ball(x = 5.0, r = 1.0, hits = 0), Ball(x = 3.0, r = 1.0, hits = 1)]
	expect nearest(balls) == 2
	expect weighed(balls) == 11

# x of `i, x` is a number read through its reference wherever a value is wanted: a choice's arm
fn picked(values i64[]):
	out = []
	for i, v in values:
		out.push(v if i == 2 else v * 3)
		out.push(v if i == 1 else 7)
	out

test "indexed for: the element a choice gives":
	expect picked([4, 5, 6]) == [12, 7, 15, 5, 6, 7]
