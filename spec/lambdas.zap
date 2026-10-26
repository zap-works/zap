# 5.3 Function values and lambdas
#
# A function type is `fn(A, B) R` (`fn(A)` without a result). A top-level function is a value by
# its name; a lambda is `(x i64): x * 2`, `x: ...` (types from the expected `fn` type), or
# `(a, b):` followed by an indented block whose trailing expression is its result, written
# wherever a value is given: an argument, a binding's value, a returned value, a list's element,
# a map's value, a line of its own. A statement's header (`if
# ready:`) and a match's arm (`m: ...`) end in `:` too, so no lambda starts one. Function values
# go in lists, fields and parameters, and are returned.

type Button:
	label str
	onClick fn(str) str

type Person:
	name str
	age i64
	alive bool

type Line:
	price f64
	qty f64

fn apply(f fn(i64) i64, x i64):
	f(x)

fn twice(x i64):
	x * 2

fn each(xs i64[], f fn(i64)):
	for x in xs:
		f(x)

fn makeAdder(n i64) fn(i64) i64:
	x: x + n

fn compose(move f fn(i64) i64, move g fn(i64) i64) fn(i64) i64:
	x: g(f(x))

fn describe(people Person[], pick fn(Person) bool):
	people.filter(pick).map(.name).join(" ")

fn tagged(name str, tag str):
	"{tag}:{name}"

test "functions are values":
	double = (x i64): x * 2
	expect apply == {(double, 21): 42, (twice, 5): 10}
	add5 = makeAdder(5)
	both = compose(double.copy(), add5.copy())
	ops = [double, add5, both, twice]
	print(ops.map(op: op(1)))
	print("{ops[2](10)} {[1, 2, 3].map(ops[0])}")
	each([6], x:
		y = x + 1
		print(y)
	)
	b = Button(label = "ok", onClick = (s str): "clicked {s}")
	print(b.onClick(b.label))
	greet = (name str, excited bool):
		if excited: return "Hi, {name}!"
		"Hi, {name}."
	expect greet == {("Ana", true): "Hi, Ana!", ("Bia", false): "Hi, Bia."}
	prints """
		[2, 6, 7, 2]
		25 [2, 4, 6]
		7
		clicked ok
		"""

test "a lambda's parameter types come from its place" refuses CannotInferLambdaParameter:
	f = x: x + 1
	print(f(1))

# Functions with `mut` or `move` parameters and generic functions are not values: a function
# value lends its arguments.
test "a function with a mut parameter is no value" refuses MutParameterAsValue:
	fn bump(mut n i64):
		n += 1
	fns = [bump]
	print(fns.len)

test "a function with a move parameter is no value" refuses MoveParameterAsValue:
	fn eaten(move xs i64[]) i64:
		xs.len
	fns = [eaten]
	print(fns.len)

test "a generic function is no value" refuses GenericAsValue:
	fn same<T>(x T) T:
		x
	fns = [same]
	print(fns.len)

# In a call's argument where a function of one parameter is expected, `it` stands for that
# parameter and `.name` for its field (a leading dot): the whole argument is then the function, as
# pandas reads `df[df.age > 30]`. `it` given on to a call that takes a value stays the outer
# argument's. It stops at the argument: `f(.a + .b, 1)` is `f(x: x.a + x.b, 1)`.
people = [
	Person(name = "ann", age = 34, alive = true),
	Person(name = "bob", age = 25, alive = false),
	Person(name = "cid", age = 41, alive = true)
]
lines = [Line(price = 2.0, qty = 3.0), Line(price = 1.5, qty = 2.0)]

test "a field read makes the argument a function of the value":
	expect (people.filter(.age > 30).map(.name).join(" ")) == "ann cid"
	expect (describe(people, .age > 30 and .alive)) == "ann cid"
	expect people.any(.age <= 30 and not .alive)
	expect lines.sortedBy(.price * .qty).map(i64(.price * .qty)) == [3, 6]

test "it is the value itself":
	print(apply(it + 1, 1))
	print(people.map("w{.age}-{.name}").join(" "))
	r = 0
	print([1, 2, 3, 4].filter(it % 2 == r % 2).map(it + r))
	print(["a", "b"].map(tagged("x", it)).join(" "))
	each([4, 5], print(it * 10))
	prints """
		2
		w34-ann w25-bob w41-cid
		[2, 4]
		a:x b:x
		40
		50
		"""

# `it` belongs to the innermost argument that takes a function: in `rows.map(it.filter(it > 1).len)`
# the first `it` is a row and the second one of its elements. One level only: a lambda written
# inside another names its parameter, and `it` in it is an error, as is `it` outside a call's
# argument or a binding named `it`.
test "it belongs to the innermost call that takes a function":
	rows = [[1, 2], [3], [4, 5]]
	expect (rows.map(.filter(it > 1).len + 1)) == [2, 2, 3]
	expect people.filter(.alive).map(p: rows.map(.len * p.age).sum() / 10) == [17, 20]

test "a lambda inside another names its parameter" refuses NoCallArgument:
	rows = [[1, 2], [3]]
	print(rows.map(r: r.filter(v: v > it.len)))

test "it outside a call's argument" refuses NoCallArgument:
	x = it + 1
	print(x)

# Captures. A lambda that runs inline (a pipeline step, a callback the call consumes), or one bound
# to a name that the function only calls by that name, borrows what it uses: it may use borrowed
# parameters and change the captured variables, the caller's own.
fn weighted(xs i64[], scale i64):
	sum = 0
	add = (x i64):
		sum += x * scale
	for x in xs:
		add(x)
	sum

fn labels(prefix ref str):
	tag = (n i64): "{prefix}{n}"
	[tag(1), tag(2)]

test "a lambda only called by its name borrows what it captures and may change it":
	print(weighted([1, 2, 3], 2))
	print(labels("a"))
	count = 0
	seen = []
	see = (x i64):
		count += 1
		seen.push(x)
	see(5)
	see(1)
	count += 1
	print("{count} {seen}")
	counter = [0]
	inc = ():
		counter[0] += 1
		counter[0]
	inc()
	print(inc())
	total = 0
	print([1, 2, 3].map(x:
		total += x
		total
	))
	prints """
		12
		["a1", "a2"]
		3 [5, 1]
		2
		[1, 3, 6]
		"""

# While the lambda is still called, the variables it reads cannot change or be given away outside
# it; after its last call they can, and each call changes what its body changes.
test "a capture changed while the lambda is still called" refuses ChangeWhileCaptured:
	mut xs = [1]
	size = (): xs.len
	print(size())
	xs.push(2)
	print(size())

test "a borrow taken after a local lambda's last change is fine":
	xs = ["a".repeat(1)]
	grow = ():
		xs.push("b")
	grow()
	grow()
	r ref str = xs[0]
	expect r == "a"
	expect xs.len == 3

# A lambda that is stored, returned or sent to a thread owns its captures: they are moved in (the
# compiler asks for `.copy()` when the variable is used afterwards), a parameter a returned lambda
# captures is declared `move`, and assigning a capture in such a lambda is an error. A closure value
# owns its environment: it moves, `copy()` duplicates it with its captures.
test "a kept closure owns its captures, and copy duplicates them":
	prefix = "pre"
	mk = (): "{prefix}!"
	other = mk
	expect mk() == "pre!"
	expect other() == "pre!"

test "a stored closure takes what it captures" refuses UseAfterCapture:
	prefix = "pre"
	makers = [(): "{prefix}!"]
	print(prefix)
	print(makers[0]())

test "a returned closure captures a parameter given to it" refuses ClosureKeepsBorrow:
	fn later(s str) fn() i64:
		(): s.len
	print(later("abc".repeat(2))())

# A lambda that only a `for` over a parallel map holds ends with the loop: it borrows what it captures.
fn doubledSum(n i64, f fn(i64) i64):
	sum = 0
	for v in (0..n).parallel().map(t: f(t) * 2):
		sum += v
	sum

test "a parallel map in a for borrows a function parameter":
	expect doubledSum(4, it + 1) == 20

test "a kept lambda that changes a capture" refuses CapturedChangeLost:
	mut n = 0
	bumps = [():
		n += 1
	]
	bumps[0]()
	print(n)

# A system callback is a top-level function, never a lambda (*Foreign functions*).
