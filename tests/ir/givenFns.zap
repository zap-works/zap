# A function taking a function made for each one given (spec 14.3): lambdas with captures,
# functions by name, recursion passing the function on, generic callees, block bodies with
# early returns, owned results, and parameters kept as values; the function given on to another
# callee, a pipeline's step or a lambda of the callee's own; lambdas changing a capture or written
# in a generic's body; methods; environments in the caller's frame; nothing left behind.
limit = 5

fn sumWith(xs i64[], f fn(i64) i64):
	total = 0
	for x in xs:
		total += f(x)
	total

fn insertionSort(mut xs i64[], before fn(i64, i64) bool):
	for i in 1..xs.len:
		v = xs[i]
		j = i
		while j > 0 and before(v, xs[j - 1]):
			xs[j] = xs[j - 1]
			j -= 1
		xs[j] = v

fn descending(a i64, b i64):
	a > b

# a depth-first count: the function given to itself
fn countDown(n i64, keep fn(i64) bool) i64:
	if n == 0: return 0
	(1 if keep(n) else 0) + countDown(n - 1, keep)

fn mapAll<T>(xs T[], f fn(T) T) T[]:
	out T[] = []
	for x in xs:
		out.push(f(x))
	out

fn apply(f fn(i64) i64, x i64):
	f(x)

fn applyTo(x i64, f fn(i64) i64):
	f(x)

type Bag:
	items i64[]

	fn countWhere(f fn(i64) bool):
		n = 0
		for x in self.items:
			if f(x):
				n += 1
		n

	fn sumBy(f fn(i64) i64):
		total = 0
		for x in self.items:
			total += f(x)
		total

# a local named as the global the lambda reads
fn shadowing(f fn() i64):
	limit = 100
	f() + limit

# used as a value: called through its pointer
fn mapped(xs i64[], f fn(i64) i64):
	xs.map(f)

fn named(prefix str, f fn(str) str):
	"{f(prefix)}|{f("{prefix}2")}"

fn churn(n i64):
	before = liveBlocks()
	total = 0
	for i in 0..n:
		tag = "t{i}"
		total += named("p", "{tag}:{it}").len
		total += mapAll(["a", "bb"], "{it}{tag}").len
	total > 0 and liveBlocks() == before

test "a lambda with captures, a function by name":
	k = 3
	words = ["a", "bcd"]
	print(sumWith([1, 2, 3], it * k + words.len))
	print(sumWith([1, 2, 3], it + words[1].len))
	xs = [5, 1, 4, 2, 3]
	insertionSort(xs, (a, b): a < b)
	print(xs)
	insertionSort(xs, descending)
	print(xs)
	prints "24\n15\n[1, 2, 3, 4, 5]\n[5, 4, 3, 2, 1]"

test "recursion, generics, inlined callees, methods":
	m = 3
	print(countDown(10, it % m == 0))
	print(mapAll([1, 2, 3], it * 10))
	print(mapAll(["a", "b"], "{it}!"))
	print(apply(it + m, 4))
	print(Bag(items = [1, 2, 3, 4]).countWhere(it > 2))
	prints "3\n[10, 20, 30]\n[\"a!\", \"b!\"]\n7\n2"

test "a block body with an early return, the lambda's names its own":
	print(sumWith([1, -2, 3], x:
		if x < 0: return 0
		x * 2
	))
	print(shadowing((): limit))
	print(mapped([1, 2], it + 1))
	prints "8\n105\n[2, 3]"

test "owned results and captures freed":
	print(named("p", "<{it}>"))
	print(churn(50))
	prints "<p>|<p2>\ntrue"

# given on to another callee, to a pipeline's steps and to a lambda of its own
fn sumOuter(xs i64[], f fn(i64) i64):
	sumWith(xs, f) + 1

fn sumMapped(xs i64[], f fn(i64) i64):
	xs.map(f).sum()

fn countKept(xs i64[], keep fn(i64) bool):
	xs.count(keep) + xs.filter(keep).len

fn sumNested(xs i64[], f fn(i64) i64):
	sumWith(xs, f(it) + 1)

# a lambda of its own that is no given one: its closure made, the function called in its body
fn sumKept(xs i64[], f fn(i64) i64):
	g = (x i64): f(x) * 2
	total = 0
	for x in xs:
		total += g(x)
	total

fn sumParallel(n i64, f fn(i64) i64):
	(0..n).parallel().map(t: f(t)).sum()

# called and kept as a value: the closure made whole where it is copied
fn callAndKeep(xs i64[], f fn(i64) i64):
	kept = [f.copy()]
	total = 0
	for x in xs:
		total += f(x) + kept[0](x)
	total

fn countIf<T>(xs T[], f fn(T) bool) i64:
	n = 0
	for x in xs:
		if f(x):
			n += 1
	n

# a lambda written in a generic's body, each instance's own
fn countAbove<T Num>(xs T[], lim T) i64:
	countIf(xs, it > lim)

fn sumLens<T>(xs T[]) i64:
	sumWith([1, 2], it * xs.len)

type Holder<T>:
	items T[]

	fn countWhere(f fn(T) bool) i64:
		n = 0
		for x in self.items:
			if f(x):
				n += 1
		n

test "a lambda changing a capture":
	seen = 0
	print(sumWith([1, 2, 3], x:
		seen += x
		x
	))
	print(seen)
	calls = 0
	print(applyTo(5, x:
		calls += 1
		x * 2
	))
	print(sumOuter([4, 5], x:
		calls += 1
		if x > 4: return 0
		x
	))
	print(calls)
	prints "6\n6\n10\n5\n3"

test "given on to another callee, a pipeline's steps, a lambda of its own":
	k = 2
	xs = [1, 2, 3, 4]
	print(sumOuter(xs, it * k))
	print(sumMapped(xs, it * k))
	print(countKept(xs, it > k))
	print(sumNested(xs, it * k))
	print(sumKept(xs, it * k))
	print(sumParallel(5, it * k))
	print(callAndKeep(xs, it * k))
	prints "21\n20\n4\n24\n40\n20\n40"

test "a lambda in a generic's body, a method, a generic impl's method":
	print(countAbove([1, 5, 9], 4))
	print(countAbove([1.5, 2.5], 2.0))
	print(sumLens(["a", "b", "c"]))
	print(sumLens([1.0]))
	m = 10
	print(Bag(items = [1, 2, 3]).sumBy(it * m))
	print(Holder<str>(items = ["a", "bb", "ccc"]).countWhere(.len > 1))
	print(Holder<i64>(items = [1, 2, 3]).countWhere(it > 1))
	prints "2\n1\n9\n3\n60\n2\n2"

test "a lambda given to a function made for it allocates nothing":
	xs = [1, 2, 3]
	k = 4
	words = ["ab"]
	before = allocations()
	total = sumWith(xs, it * k + words[0].len) + sumOuter(xs, it + k) + sumNested(xs, it * k)
	expect allocations() == before
	expect total == 76
