# 3.5 Fixed arrays: `T[N]`
#
# `T[N]` is `N` values stored inline, in the variable, field or parameter that holds it, with no
# heap block. It is a value: it copies, moves, is passed (read, `mut` or `move`, as a struct is) and
# returned, prints as a list, and its elements may own things. `a.len` is `N`.

type Hero:
	name str
	stats i32[6]

fn total(s i32[6]):
	t i32 = 0
	for x in s:
		t += x
	t

fn bump(mut h Hero, i i64):
	h.stats[i] += 10

fn squares() i64[4]:
	[0, 1, 4, 9]

test "an array in a struct":
	h = Hero(name = "ana", stats = [1, 2, 3, 4, 5, 6])
	h.bump(2)
	print(h)
	expect total(h.stats) == 31
	expect h.stats.len == 6
	prints """
		Hero(name = "ana", stats = [1, 2, 13, 4, 5, 6])
		"""

test "arrays are values":
	names str[3] = ["a", "b", "c"]
	copy = names.copy()
	copy[1] = "z"
	print("{names} {copy}")
	q = squares()
	n = 3
	print(q[n])
	prints """
		["a", "b", "c"] ["a", "z", "c"]
		9
		"""

fn changedCopy(a i64[3]):
	b = a
	b[1] = 50
	a[1] + b[1]

type Grid3:
	cells i64[3]

test "an array of plain values copies when it is bound to another name":
	grid i64[3] = [1, 2, 3]
	g = grid
	g[0] = 9
	kept = grid
	grid[2] = 7
	h = Grid3(cells = grid)
	cells = h.cells
	cells[0] = 4
	print("{grid} {g} {kept} {h.cells} {cells} {changedCopy(grid)}")
	prints "[1, 2, 7] [9, 2, 3] [1, 2, 3] [1, 2, 7] [4, 2, 7] 52"

type Body:
	pos f64[3]
	tags str[2]

fn scale(mut a f64[3], k f64):
	for i in 0..3:
		a[i] *= k

fn twice(mut a f64[3]):
	scale(a, 2.0)
	scale(a, 2.0)

fn rename(mut t str[2], move name str):
	t[1] = name

fn countUp(mut c i64[3]):
	c[0] += 1

fn sum3(a f64[3]):
	a[0] + a[1] + a[2]

fn keep3(move a f64[3]):
	a

test "an array passed whole: read, mut and move":
	c i64[3]
	countUp(c)
	countUp(c)
	print(c)
	b = Body(pos = [1.0, 2.0, 3.0], tags = ["a", "b"])
	scale(b.pos, 10.0)
	rename(b.tags, "z")
	print(b)
	grid f64[2, 3]
	grid[1][2] = 1.0
	twice(grid[1])
	print(grid)
	r f64[3]
	r[0] = 1.0
	r[1] = 2.0
	r[2] = 3.0
	scale(r, 3.0)
	kept = keep3(r)
	print("{sum3(r)} {sum3(kept)}")
	bodies = [Body(pos = [1.0, 1.0, 1.0], tags = ["x", "y"])]
	scale(bodies[0].pos, 5.0)
	print(bodies[0].pos)
	prints """
		[2, 0, 0]
		Body(pos = [10, 20, 30], tags = ["a", "z"])
		[[0, 0, 0], [0, 0, 4]]
		18 18
		[5, 5, 5]
		"""

# An index is any integer: a literal one is checked when compiling (`N` an integer literal or a
# number parameter, 3.6), any other at run time. The literal must give all `N` values.

test "a known index outside" refuses IndexOutside:
	xs i64[3] = [1, 2, 3]
	print(xs[3])

test "an index outside when the program runs" stops IndexOutOfBounds:
	xs i64[3] = [1, 2, 3]
	i = xs.len
	print(xs[i])

# Arrays have no other methods: a collection that grows is a list (*Lists*).

test "an array has no list methods" refuses FixedArrayLacksMethod:
	mut xs i64[2] = [1, 2]
	xs.push(3)
	print(xs)

# An array declared without values starts from each element's empty value (`0`, `0.0`, `false`,
# `""`, `[]`, `none`, a zero vector), unless the first statement after it that names it only binds
# its elements (`a[i] = v`): each is then bound once, and reading an element before its value is
# an error.

test "an array declared without values starts from zeros":
	a i64[2]
	s str[2]
	v Simd<4, f64>[4]
	l i64[2, ]
	print("{a[0]} {s[1].len} {v[3].lane(0)} {l[1]}")
	o i64?[2]
	print(o[0] ?? 7)
	for k in 0..4:
		v[k] += Simd<4>(1.0)
	print(v.len + i64(v[3].lane(0)) - 1)
	prints """
		0 0 0 []
		7
		4
		"""

test "an array whose first use binds its elements binds each once" refuses ReadBeforeSet:
	c i64[2]
	c[1] = 5
	print(c[0])

# `fill(N, x)` evaluates `x` once and copies it into every element of a `T[N]`; `zeros(N)` is N
# zeros (*Lists*).

mut made = 0

fn nextMade():
	made += 1
	made

fn madeName():
	made += 1
	"n{made}"

test "fill(N, x) evaluates x once and copies it":
	a i64[3] = fill(3, nextMade())
	print(a)
	r f64[4] = fill(4, f64(nextMade()))
	for i in 0..4:
		r[i] += i
	print(r)
	s = "x"
	b str[2] = fill(2, move s)
	print(b)
	d str[2] = fill(2, madeName())
	print(d)
	bodies Body[2] = fill(2, Body(pos = [0.0, 0.0, 0.0], tags = ["a", ""]))
	bodies[1].tags[1] = "b"
	print(bodies)
	grid i64[2, 2] = fill(2, 2, nextMade())
	grid[0][0] = 9
	print(grid)
	print(made)
	prints """
		[1, 1, 1]
		[2, 3, 4, 5]
		["x", "x"]
		["n3", "n3"]
		[Body(pos = [0, 0, 0], tags = ["a", ""]), Body(pos = [0, 0, 0], tags = ["a", "b"])]
		[[9, 4], [4, 4]]
		4
		"""

# A type is written as its literal looks: `T[]` a list, `T[N]` a fixed array, `{K: V}` a map.
# Only these collections have a short form; every other generic type keeps `<>` (`Pool<T>`,
# `Table<T>`, `Grid<T>`, `Channel<T>`, `Seq<T>`, `Simd<4, f64>`).

type Gem:
	id i64

test "a list or map type is written as its literal looks":
	ops (fn(i64) i64)[] = [x: x + 2, x: x + 3]
	scores = {"ana": 3}
	print("{ops.map(it(1))} {scores}")
	print(Gem[].fromJson("[\{\"id\": 1}]"))
	print({str: i64}.fromJson("\{\"axe\": 3}"))
	prints r"""
		[3, 4] {"ana": 3}
		some([Gem(id = 1)])
		some({"axe": 3})
		"""

# One bracket holds a type's layers, outer first, separated by commas, an empty place a list:
# `i32[3, 4]` is three arrays of four, `Vec3[, 4]` a list of arrays of four, `str[2, ]` two lists,
# `f64[,]` a list of lists. An index takes the same commas (`rows[r, c]` is `rows[r][c]`);
# `rows[r]` is the layer. A `?` binds before the brackets after it: `T?[]` is a list of optionals,
# `T[]?` an optional list. A function, a reference or a result as an element is put in parentheses.

test "one bracket holds a type's layers, outer first, and an index takes the same commas":
	rows = [[1, 2], [3]]
	print("{rows} {rows[1, 0]} {rows[1]}")
	cells i32[2, 4]
	for r in 0..2:
		for c in 0..4:
			cells[r, c] = r * 4 + c
	print("{cells} {cells[1, 2]} {cells[1][2]}")
	pairs i64[, 2] = [[1, 2], [3, 4], [5, 6]]
	print(pairs)
	words str[2, ] = [["x"], ["y", "w"]]
	for i, w in words:
		print("{i} {w}")
	maybe i64?[] = [1, none]
	whole i64[]? = [2]
	print("{maybe} {whole}")
	prints """
		[[1, 2], [3]] 3 [3]
		[[0, 1, 2, 3], [4, 5, 6, 7]] 6 6
		[[1, 2], [3, 4], [5, 6]]
		0 ["x"]
		1 ["y", "w"]
		[some(1), none] some([2])
		"""

test "a second bracket pair after a type is no list of lists" refuses TypeBracketsTwice:
	rows str[][] = []
	print(rows.len)

# A `for` walks a layer as any array (`for c in cells[r]:`), at an index the loop does not change.

test "a for walks a layer of an array":
	cells i32[3, 2]
	for r in 0..3:
		cells[r, 0] = r
		cells[r, 1] = r * 10
	total = 0
	for r in 0..3:
		for x in cells[r]:
			total += x
	expect total == 33

test "a for over a layer whose index the loop changes needs a name" refuses ForNeedsPlace:
	cells i32[3, 2] = [[1, 2], [3, 4], [5, 6]]
	mut r = 0
	for x in cells[r]:
		r = 1
		print(x)

# Brackets after brackets are an error, so no type has two spellings; a defined type stays one
# piece (`type Row = f32[4]` makes `Row[]` a list of rows, indexed as `f32[, 4]` is).

type Row = f32[4]

test "a defined type stays one piece":
	rs Row[] = [[1.0, 2.0, 3.0, 4.0]]
	expect rs[0, 3] == 4
	expect rs[0][3] == 4
	expect rs[0].len == 4

# When every index of a local array is known when compiling (a literal, literals combined, the
# variable of a `for` over a literal range, an immutable binding of those), its elements become
# separate locals kept in registers, and the loops that index it are unrolled; the program reads the
# same either way (`compiler/collections/regArrays.zap` decides). An immutable array of integer literals is a
# table: `pairI[k]` is the literal.

test "an array indexed only by known indices reads the same":
	acc i64[4]
	for i in 0..4:
		acc[i] = i * i
	pairI i64[3] = [7, 8, 9]
	print("{acc} {pairI[1] + acc[3]}")
	prints "[0, 1, 4, 9] 17"
