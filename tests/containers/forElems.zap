# `for x in L` with a body that cannot move L: the element's address is stepped in a register.
# Nested loops over lists of lists, break and continue, temporaries as the source, elements
# handed to inlined functions and captured by lambdas, structs read by field, an empty list.
type P:
	x f32
	y f32
	tag i64

fn half(p P):
	p.x * 0.5 + p.y

fn nested(rows i64[,]):
	s = 0
	for row in rows:
		for v in row:
			s = s * 3 + v
		s += row.len
	s

fn firstBig(xs i64[], limit i64):
	skipped = 0
	for x in xs:
		if x % 2 == 0:
			skipped += 1
			continue
		if x > limit: return x * 100 + skipped
	-1

fn sumFields(ps P[]):
	s = 0.0
	for p in ps:
		s += p.half() + f32(p.tag)
	s

fn captured(ps P[]):
	n = 0
	for p in ps:
		check = (k i64): p.tag > k
		if check(1):
			n += p.tag
	n

fn updates(mut xs i64[]):
	i = 0
	s = 0
	for x in xs:
		s += x
		i += 1
	for k in 0..xs.len:
		xs[k] *= 2
	s * 1000 + i

test "a loop over lists of lists steps each level's element":
	expect nested([[1, 2], [], [3], [4, 5, 6]]) == 735
	expect nested([]) == 0

test "break and continue":
	expect firstBig([2, 4, 5, 6, 9, 11], 6) == 903
	expect firstBig([2, 4], 6) == -1

test "structs and inlined calls":
	ps = [P(x = 2.0, y = 1.0, tag = 1), P(x = 4.0, y = 0.5, tag = 2), P(x = 0.0, y = 0.0, tag = 3)]
	expect sumFields(ps) == 10.5
	expect captured(ps) == 5

test "a loop over a temporary list keeps it to the loop's end":
	n = 0
	for w in "a bb ccc".split(" "):
		n = n * 10 + w.len
	expect n == 123
	m = 0
	for v in [[1], [2, 3]].map(.len):
		m = m * 10 + v
	expect m == 12

test "writes by index after":
	xs = [1, 2, 3]
	expect updates(xs) == 6003
	expect xs[2] == 6
