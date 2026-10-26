# A name `is` binds `mut` writes back to the place it was read from only when the whole condition
# held: the else branch (which may push to the list and move its items) leaves the place alone.
type Slot:
	Kept(from i64, to i64)
	Added(text str)

fn runs(from i64[]) Slot[]:
	out Slot[] = []
	for j, i in from:
		if i < 0:
			out.push(.Added("new{j}"))
		elif not out.isEmpty and out[len - 1] is Kept(_, mut to) and to + 1 == i:
			to = i
		else:
			out.push(.Kept(i, i))
	out

test "a run extended through an is test, the others pushed":
	for s in runs([0, 1, 2, 5, -1, 6, 7, 8, 10]):
		match s:
			Kept(a, b): print("{a}..{b}")
			Added(t): print(t)
	prints """
		0..2
		5..5
		new4
		6..8
		10..10
		"""
