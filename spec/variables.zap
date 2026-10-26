# 2.4 Variables and constants
#
# A binding needs no keyword: `x = 10` binds x, and a word between the name and `=` is its type
# (`total f64 = 0.0`). A binding that what follows it in its block changes is mutable, found when
# it is checked: it is assigned again (`x = 2`, `x += 1`, a field or an element of it), a method
# that changes it is called on it or a part of it, it is lent to a `mut` parameter, `mut ref` or
# `out`, a part is moved out of it, or a loop's or a match's `mut` name is bound to a part of it.
# Any other binding is immutable, which the compiler relies on (an immutable number is read as its
# value, an immutable list keeps its length). `found = none` is an optional whose type the first
# real assignment fixes. There is no `let`, `var` or `const`.
#
# A binding's type is its value's. One of number literals alone that changes takes, from the
# start, the type of the first value or place of another it meets (mixed, compared, passed,
# stored, pushed or assigned where it is wanted): an `f32` for a float (3.1), any other integer
# type for an integer, as `[]` and `none` take theirs from their first use. zap fmt drops a written
# type the uses give alike (`n i64 = 0` is `n = 0`), and keeps one they do not or that claims what
# the compiler proves (a range, a defined type: 3.1.1).
#
# `mut` stays only where it is a contract: on a parameter and a receiver (`fn grow(mut xs i64[])`,
# spec 4.2), on a module variable (below), and on a name bound to an element that changes the
# element: `for mut x in xs` (spec 6.1) and a `match`'s or an `is`'s `mut` name (spec 6.2). Without
# it such a name is immutable: a loop or a match never changes a list or a value in place unless it
# says so. A local is never written `mut`: one moved whole (`move x`, spec 4.1) that what follows
# changes stays usable, empty, after the move, and an array declared without values starts from
# zeros unless the first statement that names it binds its elements (spec 3.5). A name reused by
# mistake is assigned again rather than refused; a value of another type still stops it.

import fs

test "a binding that changes is mutable":
	x = 10
	count = 0
	count += 1
	total = 0.0
	found = none
	for k in [4, 7, 9]:
		if k > 5:
			found = k
			break
	xs = [3, 1]
	xs.push(2)
	xs.sort()
	print("{x} {count} {total} {found ?? 0} {xs}")
	prints "10 1 0 7 [1, 2, 3]"

fn halved(x i32):
	x / 2

test "a changing binding of number literals takes the type its uses want":
	n = 10
	n -= 2
	k = 0
	k += 1
	bytes u8[] = []
	bytes.push(k)
	print("{halved(n)} {bytes}")
	prints "4 [1]"

type Route:
	stops str[]

	mut fn normalize():
		stops.clear()

test "a call of a module's function changes what its own parameters say":
	names = ["maps/town"]
	path = names.first ?? "none"
	print(fs.normalize(path))
	route = Route(stops = [path.copy()])
	route.normalize()
	print(route.stops)
	prints r"""
		maps/town
		[]
		"""

# An assignment gives no value: Python's `a = b = 0` is two lines, or `a, b = 0, 0`.
test "an assignment is not chained" refuses ChainedAssignment:
	a = b = 0
	print(a + b)

test "a name assigned a value of another type is refused" refuses AssignType:
	name = "Ana"
	name = 7
	print(name)

test "a parameter without mut is not changed" refuses AssignImmutable:
	fn f(n i64) i64:
		n = 2
		n
	print(f(1))

# Compound assignment (`+= -= *= /= %= &= |= ^= <<= >>=`) is `x = x op v`, on a local, a field or an
# element.

type Acc:
	total i64

test "compound assignment on locals, fields and elements":
	x = 10
	x += 5
	x -= 3
	x *= 4
	x /= 6
	x %= 5
	b u8 = 12
	b |= 3
	b &= 14
	b ^= 1
	b <<= 2
	b >>= 1
	f = 1.5
	f *= 2.0
	f -= 0.5
	xs = [1, 2, 3]
	i = 1
	xs[i] += 10
	xs[0] *= 7
	a = Acc(total = 1)
	for k in 0..4:
		a.total += k
	s = "ab"
	s += "cd"
	print("{x} {b} {f} {xs} {a.total} {s}")
	prints "3 30 2.5 [7, 12, 3] 7 abcd"

# An index that calls a function is computed once; an assignment runs as written: the target's
# indexes, outermost first, then the value.

mut kindCalls = 0
mut order str[] = []

fn kindOf(b i64):
	kindCalls += 1
	b % 3

fn logged(move word str, v i64):
	order.push(word)
	v

test "an index that calls a function is computed once, in order":
	counts = [0, 0, 0]
	for b in [0, 1, 3, 4, 2]:
		counts[kindOf(b)] += 1
	print("{counts} {kindCalls}")
	rows = [[0, 0], [0, 0]]
	rows[logged("row", 0)][logged("col", 1)] += logged("value", 7)
	print("{rows} {order}")
	prints """
		[2, 2, 1] 5
		[[0, 7], [0, 0]] ["row", "col", "value"]
		"""

# A target that is a call's result would change a temporary.

test "a compound assignment to a call's result" refuses CompoundOnCall:
	fn items() i64[]:
		[1, 2]
	items()[0] += 1

# **Constants.** A top-level immutable binding is a constant. A constant list is made once, before
# the program; indexing it, looping over it or taking its length reads it in place, and taking it
# whole makes a list of one's own. A list literal of plain values that a `for` walks is built in
# the function's frame, with no heap block.

primes = [2, 3, 5, 7, 11]

fn sumOf(xs i64[]):
	s = 0
	for x in xs:
		s += x
	s

test "a constant list is read in place and taken whole as a list of one's own":
	print("{primes.len} {sumOf(primes)} {primes[4]}")
	mine = primes
	mine.push(13)
	print("{mine} {primes}")
	walked = 0
	for p in [primes[0], primes[1], 4]:
		walked += p
	print(walked)
	prints """
		5 28 11
		[2, 3, 5, 7, 11, 13] [2, 3, 5, 7, 11]
		9
		"""

# A constant of any other type that owns memory (a map, a struct holding one, an optional, an
# enum's variant, a box) is built where it is used: each use is a value of its own. A written type
# takes the value as a binding's does (`nick str? = "ana"` holds `some("ana")`).

type Shelf:
	counts {str: i64}
	tags str[]
	best i64?
	label str?
	cover Cover
	spare Box<Cover>

type Cover:
	Plain
	Printed(title str, colors str[])

shelf = Shelf(
	counts = { "a": 1 },
	tags = ["x", "y"],
	best = 3,
	label = none,
	cover = .Printed("t", ["red"]),
	spare = Box(Cover.Printed("s", [])),
)
byName = {
	"ana": Shelf(
		counts = {},
		tags = [],
		best = none,
		label = "l",
		cover = .Plain,
		spare = Box(Cover.Plain)
	)
}
nick str? = "ana"

fn shelfWords():
	"{shelf.counts} {shelf.tags} {shelf.best} {shelf.label} {shelf.cover} {shelf.spare} {byName["ana"].label} {nick}"

test "a constant that owns memory is a value of its own at each use":
	print(shelfWords())
	mine = shelf
	mine.counts["b"] = 2
	mine.tags.push("z")
	print("{mine.counts} {mine.tags} {shelf.counts} {shelf.tags}")
	if shelf.cover is Printed(title, colors):
		print("{title} {colors}")
	prints r"""
		{"a": 1} ["x", "y"] some(3) none Printed("t", ["red"]) Printed("s", []) some("l") some("ana")
		{"a": 1, "b": 2} ["x", "y", "z"] {"a": 1} ["x", "y"]
		t ["red"]
		"""

test "a constant cannot change" refuses MutArgConstant:
	limits = [1, 2]
	fn grow(mut xs i64[]):
		xs.push(3)
	fn count() i64:
		limits.len
	grow(limits)
	print(count())

# **Module variables.** A top-level `mut` binding is storage: initialised before the program (the
# runtime's first, then the program's, in order), shared by every function and every thread,
# dropped at exit. One that no code the program runs names, and whose initializer does nothing
# besides its value, is never initialised: it takes no time at the start and no room. A function assigns it by name (a local of the same name declared earlier in the
# function shadows it), and a lambda sees the variable itself, not a copy. Outside module variables,
# nothing holds state without a parameter.

type Stats:
	hits i64
	names str[]

mut counter = 0
mut log str[] = []
mut stats = Stats(hits = 0, names = [])
mut scores {str: i64} = {}
mut base = counter + 5
mut current = Cover.Plain
mut held Stats? = none
mut boxed = Box(Stats(hits = 0, names = []))
mut nested = { "a": Stats(hits = 0, names = []) }

fn bump():
	counter += 1
	log.push("bump {counter}")
	stats.hits += 1

fn record(move name str):
	scores.add(name, 1)
	stats.names.push(name)

fn keep(move name str):
	current = .Printed(name.copy(), [name.copy()])
	held = Stats(hits = 1, names = [name.copy()])
	boxed.hits += 1
	boxed.names.push(name.copy())
	nested["a"].names.push(move name)

test "module variables of every kind, changed by a function":
	keep("ana")
	keep("bia")
	print("{current} {held} {boxed} {nested}")
	prints r"""
		Printed("bia", ["bia"]) some(Stats(hits = 1, names = ["bia"])) Stats(hits = 2, names = ["ana", "bia"]) {"a": Stats(hits = 0, names = ["ana", "bia"])}
		"""

test "module variables are shared by every function":
	print(base)
	bump()
	bump()
	record("ana")
	record("bia")
	record("ana")
	f = ():
		bump()
	f()
	print("{counter} {log}")
	print(stats)
	print(scores)
	counter = 99
	print(counter)
	prints r"""
		5
		3 ["bump 1", "bump 2", "bump 3"]
		Stats(hits = 3, names = ["ana", "bia", "ana"])
		{"ana": 2, "bia": 1}
		99
		"""
