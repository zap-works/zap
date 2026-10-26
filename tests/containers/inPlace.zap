# sortedBy beside sortBy, a tuple key, a list field grown while indexed, the first k of a sort.

test "a tuple key lends the element's str":
	words = ["d", "a", "c", "b"]
	counts = {"a": 3, "b": 1, "c": 2, "d": 1}
	expect words.sortedBy(-counts[it], it) == ["a", "c", "b", "d"]
	print(words.minBy(-counts[it], it))
	prints """
		some("a")
		"""

# sortBy's cheap keys are made again at each comparison (listSortByParts): the order, ties and
# stops those of a key made once for each element
type Entry:
	name str
	age i64
	score f64

fn entries(n i64):
	(0..n).map(i:
		Entry(name = "e{(i * 37) % 11}{i % 3}", age = (i * 7) % 5, score = ((i * 13) % 4) / 2.0)
	)

test "a key's parts sort as the key does, ties in their order":
	xs = (0..100).map((it * 37) % 23)
	expected = xs.sortedBy(it % 7, -it)
	xs.sortBy(it % 7, -it)
	expect xs == expected
	ys = (0..100).map(it)
	ys.sortBy(ys[it] % 7)   # read while it moves: a key made once for each element, kept
	expect ys.filter(it % 7 == 3) == (0..100).filter(it % 7 == 3)   # stable
	expect ys[..5] == [0, 7, 14, 21, 28]

test "runs longer than the merge's room split, ties in their order" for n in [70_000, 200_001]:
	xs = (0..n).map((it * 7_919) % 1_009 * n + it)
	expected = xs.sortedBy(it / n % 61)
	xs.sortBy(it / n % 61)
	expect xs == expected
	ys = (0..n).map(n - it)
	reversed = ys.sortedBy(it / 3)
	ys.sortBy(it / 3)   # every merge's runs out of order
	expect ys == reversed

test "three parts of an element's fields, its str lent" for n in [0, 1, 2, 15, 16, 17, 33, 200]:
	es = entries(n)
	expected = es.sortedBy(.age, .score, .name).map(.name.copy())
	es.sortBy(.age, .score, .name)
	expect es.map(.name.copy()) == expected
	tied = entries(n)
	stable = tied.sortedBy(.score, .age).map(.name.copy())
	tied.sortBy(.score, .age)   # equal keys, other names: in their order
	expect tied.map(.name.copy()) == stable

test "a str field sorts by its text":
	es = entries(6)
	es.sortBy(.name)
	expect es.map(.name) == ["e00", "e10", "e41", "e51", "e82", "e92"]

fn wordAt(words str[], i i64) ref str:
	words[i][0..2]

test "a part borrowing a capture through a function":
	words = ["pear", "apple", "fig", "plum", "kiwi", "apricot", "peach"]
	idx = (0..words.len).map(it)
	idx.sortBy(wordAt(words, it), words[it].len)
	expect idx.map(words[it].copy()) == ["apple", "apricot", "fig", "kiwi", "pear", "peach", "plum"]

test "a part that stops stops the sort before any element moves" stops IndexOutOfBounds:
	words = ["a", "b"]
	idx = [1, 0, 2]
	idx.sortBy(0, words[it])

test "a single element's key is made too" stops IndexOutOfBounds:
	words = ["a"]
	idx = [3]
	idx.sortBy(words[it], 0)

type Ranked:
	items i64[]
	scale i64

	fn rank():
		items.sortBy(it % scale, it)   # a field of self named bare: the keys kept

fn byDistance(mut xs i64[], pivot i64):
	xs.sortBy((it - pivot) * (it - pivot), it)

test "a key reading a field of self, and one lowered at two calls":
	r = Ranked(items = [5, 3, 8, 6], scale = 3)
	r.rank()
	xs = [1, 9, 4, 6, 2]
	byDistance(xs, 5)
	ys = xs.copy()
	byDistance(ys, 1)
	print("{r.items} {xs} {ys}")
	prints "[3, 6, 5, 8] [4, 6, 2, 1, 9] [1, 2, 4, 6, 9]"

type Bag:
	items i64[]

	fn grow():
		loop 100:
			items.push(0)

	# a loop over a list field whose header it holds, while a method moves the list's items
	fn fill():
		s = 0
		for i in 0..10:
			items[i] = i
			if i == 3:
				grow()
			if i == 5:
				items.push(7)
			s += items[i]
		s + items.len

	fn bump():
		s = 0
		for i in 0..items.len:
			items[i] += 1
			s += items[i]
		s

test "a list field indexed in a loop while methods grow it":
	b = Bag(items = zeros(10))
	expect b.fill() == 156
	expect b.bump() == 163

type Shelf:
	names str[]
	sizes i64[]

mut kept str[] = []

# `xs = xs.filter(p)`, `.map(f)` and `.sortedBy(k)` of a list the lambda does not read work in
# the list itself: no block made, the elements a filter leaves out dropped where they are
test "a step assigned back to its own list works in place":
	words = (0..12).map("the word numbered {it}")
	shelf = Shelf(names = words.copy(), sizes = (0..6).map(it * 3))
	kept = ["a long one kept elsewhere", "b"].map(.copy())
	before = allocations()
	words = words.filter(.len % 2 == 0)
	shelf.sizes = shelf.sizes.map(it + 1)
	shelf.names = shelf.names.filter(.endsWith("1"))
	kept = kept.filter(.len > 1)
	made = allocations() - before
	words = words.sortedBy(it[.len - 1])
	words = words.map(.upper())
	print("{words} {shelf.sizes} {shelf.names} {kept} {made}")
	prints "[\"THE WORD NUMBERED 10\", \"THE WORD NUMBERED 11\"] [1, 4, 7, 10, 13, 16] [\"the word numbered 1\", \"the word numbered 11\"] [\"a long one kept elsewhere\"] 0"

test "a step that reads its list makes a new one":
	xs = [3, 1, 2]
	xs = xs.map(it + xs.len)
	ys = [5, 6]
	ys = ys.filter(it > ys[0])
	print("{xs} {ys}")
	prints "[6, 4, 5] [6]"

test "a text replaced into itself keeps its block when it does not grow":
	s = "one, two, three, four and five".copy()
	before = allocations()
	s = s.replace(", ", ";")
	same = allocations() - before
	s = s.replace(";", " then ")
	short = "a-b".copy()
	t = short.copy()
	t = t.replace("-", "+")
	print("{s} {same} {t} {short}")
	prints "one then two then three then four and five 0 a+b a-b"
