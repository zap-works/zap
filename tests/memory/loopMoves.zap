# A variable declared before a loop and given away inside it: the move stands when every
# iteration gives it a value again before reading it (cur = next); when a later iteration may
# read it first (keep, read on the lines that do not assign it) it is an error, and the program
# gives away a copy of its own.
#
# A return from inside a loop over a list made for the loop drops the list, and so does the loop
# that runs to its end: neither way leaves a block behind.
#
# A value bound by `is` in a condition and returned leaves intact, with no block left behind.

fn grow(xs i64[]):
	ys = xs.copy()
	ys.push(1)
	ys

test "moves inside loops":
	cur = []
	loop 3:
		next = grow(cur)
		cur = next
	print(cur)
	keep = ""
	seen = []
	for w in ["impl A", "  fn x", "impl B", "  fn y"]:
		if not w.startsWith(" "):
			keep = w[5..6].copy()
		seen.push(keep.copy())
	print(seen)
	prints """
	    [1, 1, 1]
	    ["A", "A", "B", "B"]
	    """

fn upTo(n i64):
	xs = []
	for i in 0..n:
		xs.push(i)
	xs

fn firstAbove(n i64, limit i64):
	for x in upTo(n):
		if x > limit: return x
	-1

fn nameAbove(names str[], n i64):
	for s in names.map("{it}!"):
		if s.len > n: return s
	"none"

test "a loop's own list is dropped whether the loop returns or ends":
	before = liveBlocks()
	found = 0
	missed = 0
	loop 1000:
		found = firstAbove(10, 5)
		missed = firstAbove(3, 5)
	names = ["ann", "bob", "charlie"]
	last = ""
	loop 100:
		last = nameAbove(names, 4)
		nameAbove(names, 20)
	print("{found} {missed}")
	print("{last} {nameAbove(names, 20)}")
	print(liveBlocks() - before <= 2)
	prints """
		6 -1
		charlie! none
		true
		"""

type M:
	A(xs str[])
	B(n i64)

fn decode(a bool) M:
	if a: .A(["x", "y"])
	else: .B(1)

fn kindOf(m M):
	match m:
		A: "A"
		B: "B"

fn first() M?:
	if decode(true) is m and m.kindOf() == "A": return m
	none

fn firstLocal() M?:
	d = decode(true)
	if d.kindOf() == "A": return d
	none

test "a value bound by is and returned keeps its lists":
	before = liveBlocks()
	loop 100:
		first()
		firstLocal()
	print(first())
	print(firstLocal())
	print(liveBlocks() - before <= 2)
	prints """
		some(A(["x", "y"]))
		some(A(["x", "y"]))
		true
		"""
