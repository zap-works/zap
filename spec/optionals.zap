# 6.4 Optionals: `T?`
#
# `T?` is a `T` or `none`, the one spelling of an optional. It composes with generics, nests (`T??`)
# and works in `match`. A `T` stored where a `T?` is expected is wrapped automatically (returns,
# assignments, arguments, fields, `push`, `m[k] = v`).

type User:
	id u32
	name str

type Account:
	owner User?

fn findUser(id n32) User?:
	if id == 1: return User(id = 1, name = "Ana")
	none

fn described(u User?):
	u?.name ?? "missing"

fn firstOf<T Copy>(xs T[]) T?:
	xs[0] if xs.len > 0 else none

test "a value goes where its optional is wanted":
	found User? = none
	found = User(id = 2, name = "Bo")
	acct = Account(owner = User(id = 3, name = "Cy"))
	xs User?[] = []
	xs.push(User(id = 4, name = "Di"))
	m {str: str?} = {}
	m["a"] = "x"
	print("{described(found)} {described(User(id = 5, name = "Ed"))} {acct.owner?.name} {xs[0]?.id} {m["a"]}")
	empty i64[] = []
	print("{firstOf([3, 4])} {firstOf(empty)}")
	# T = i64? nests: a T? holds none, or a value that may itself be none
	holes i64?[] = [none]
	noHoles i64?[] = []
	inner = firstOf(holes)
	print("{inner} {firstOf(noHoles)} {inner != none}")
	match inner:
		none: print("empty")
		v: print("holds {v}")
	prints """
		Bo Ed some("Cy") some(4) some("x")
		some(3) none
		some(none) none true
		holds none
		"""

# `x ?? fallback` is the value or the fallback (on a result, the ok side with the error dropped; its
# right side reads the error as `error`, 6.5); `?.` is safe access, none propagating. A list
# literal takes the optional element type its place asks for.

test "a default, safe access and match":
	a = findUser(1)
	b = findUser(2)
	print("{a?.name ?? "missing"} {b?.name ?? "missing"}")
	label = match a:
		u: "found {u.name}"
		none: "nobody"
	fallback = b ?? User(id = 0, name = "guest")
	print("{label} {fallback.name}")
	xs i64?[] = [1, none, 3]
	zs str?[] = ["a".repeat(2), none]
	print("{xs[0] ?? -1} {xs[1] ?? -1} {xs[2] ?? -1} {zs[0] ?? "-"} {zs[1] ?? "-"}")
	prints """
		Ana missing
		found Ana guest
		1 -1 3 aa -
		"""

# A `?.` call of a method that gives nothing is a statement: the method runs when there is a value,
# and nothing happens on none. The method changes the optional's value in place when the optional
# is a place that may change (a local, a `mut` parameter, a field or an element of one), so an
# optional that outlives a loop is set, called through and cleared as a plain local is.

type Duel:
	hits i64 = 0

	fn strike(n i64):
		hits += n

	fn left():
		10 - hits

test "a ?. call changes the value in place, and does nothing on none":
	duel Duel? = none
	seen = []
	for round in 0..5:
		if round == 1: duel = Duel()
		duel?.strike(round)
		seen.push(duel?.left())
		if round == 3: duel = none
	print(seen)
	prints "[none, some(9), some(7), some(4), none]"

test "a local bound once is changed by a ?. call as by a plain one":
	duel Duel? = Duel()
	duel?.strike(4)
	print(duel?.left())
	prints "some(6)"

test "a ?. call that changes the value needs a place that may change" refuses NeedsMut("strike needs 'd' to be mut (declare it 'mut' to mutate)"):
	fn hit(d Duel?):
		d?.strike(1)
	hit(Duel())

fn doubled(n i64) i64?:
	n * 2 if n > 0 else none

fn firstUpper(names str[]):
	first = names.first ?? return "nobody"
	first.upper()

fn sumFound(xs i64[]):
	sum = 0
	for x in xs:
		v = doubled(x) ?? continue
		if v > 10: break
		sum += v
	sum

test "the right side of ?? may stop or leave instead of giving a value":
	expect (doubled(3) ?? fail("no value")) == 6
	print("{firstUpper(["ana"])} {firstUpper([])} {sumFound([1, -2, 3, 9, 4])}")
	prints """
		ANA nobody 8
		"""

test "?? fail stops the program on none" stops Failure("bad port"):
	port i64? = none
	print(port ?? fail("bad port"))

# `??` takes the whole comparison on its right: `a ?? 0 < 3` is `a ?? (0 < 3)`.
test "?? binds looser than a comparison" refuses FallbackType("'??' needs a i64 on the right, found bool (`??` takes the whole comparison on its right: write (a ?? b) < c)"):
	a i64? = none
	print(a ?? 0 < 3)

test "?? takes an optional" refuses FallbackNotOptional:
	x = 3
	print(x ?? 4)

test "none takes its type from the first value assigned, for the reads before it too":
	found = none
	for i in 0..5:
		if found == none and i >= 3:
			found = i
	expect found == 3

test "none alone has no type" refuses UntypedNone("no use decides the type of 'x': write it, `x T? = none`"):
	x = none
	print(x)

# An optional is tested with `opt != none` (`opt == none` for none). `opt is x` tests and names the
# value, written only when `x` is read; the name changes the optional's value in place. An optional
# compared with a value of its type (`opt == 3`) is equal when it holds that value.

type Tally:
	n i64
	seen str[]

fn count(mut t Tally):
	t.n += 1
	t.seen.push("t{t.n}")

test "an optional is tested with != none, and with is x when x is read":
	xs = [1, 2]
	if xs.first != none: print("some")
	if xs.last is x: print("{x} is there")
	if doubled(-5) == none: print("none")
	maybe Tally? = Tally(n = 0, seen = [])
	loop 3:
		if maybe is mut t:
			t.count()
	y i64? = 5
	if y is mut v:
		v *= 3
	print("{maybe} {y}")
	prints """
		some
		2 is there
		none
		some(Tally(n = 3, seen = ["t1", "t2", "t3"])) some(15)
		"""

test "an optional equals a value it holds":
	xs = [4, 7]
	at = xs.indexOf(7)
	expect at == 1
	expect 1 == at
	expect at != 0
	expect not (xs.indexOf(5) == 0)

test "is _ binds nothing" refuses IsBlank:
	o i64? = 3
	if o is _:
		print("some")

test "a value is never tested with is x unread" refuses UnreadTest:
	o i64? = 3
	if o is x:
		print("some")

test "a test for none is == none" refuses IsNone:
	o i64? = 3
	if o is none:
		print("none")

test "only an optional is compared with none" refuses NoneComparison:
	o = 3
	if o != none:
		print("some")

type Big:
	f0 i64 = 0
	f1 i64 = 0
	f2 i64 = 0
	f3 i64 = 0
	f4 i64 = 0
	f5 i64 = 0
	f6 i64 = 0
	f7 i64 = 0
	f8 i64 = 0
	f9 i64 = 0
	f10 i64 = 0
	f11 i64 = 0
	f12 i64 = 0
	f13 i64 = 0
	f14 i64 = 0
	f15 i64 = 0
	f16 i64 = 0
	f17 i64 = 0
	f18 i64 = 0
	f19 i64 = 0

fn pick(o ref Big?, d ref Big):
	(o ?? d).f1
fn fresh(o ref Big?, d Big):
	o ?? d

# A reference to a struct too large to be passed in registers: `x ?? y` copies the struct x refers to
# when there is one.
test "x ?? y of an optional reference to a large struct":
	bs = [Big(f1 = 1)]
	d = Big(f1 = 2)
	none1 = bs.filter(.f1 > 5)
	expect pick == {(bs.first, d): 1, (none1.first, d): 2}
	expect fresh(bs.first, d).f1 == 1
	expect fresh(none1.first, d).f1 == 2

# `T??` and `T???` are written as types; a plain fallback of `x ?? y` on an optional of optional is
# wrapped into the inner optional.
fn nestedOrElse<T>(x T?, d T) T:
	x ?? d

# A value is wrapped in one optional layer, so a `T??` binding takes an optional (`inner`), not a plain
# value: `x bool?? = true` is refused and says to declare `bool?`.
test "a value is wrapped in one optional layer" refuses InitializerType("'x' declared bool?? but initializer is bool (a value is wrapped in one optional layer: declare bool?)"):
	x bool?? = true
	print(x)

test "an optional of an optional is written T??, and ?? takes one layer":
	inner i64? = 4
	some i64?? = inner
	nothing i64?? = none
	deep bool??? = none
	expect ((some ?? 7) ?? 0) == 4
	expect ((nothing ?? 7) ?? 0) == 7
	expect deep == none
	expect (nestedOrElse(some, none) ?? 0) == 4
