# 7.10 Grids: `Grid<T>`
#
#
# A `Grid<T>` is a rectangle of values in one block, row after row from the top
# (`runtime/grid/grid.zap`): a picture, a height map, a level's tiles.

type Px:
	r u8
	g u8
	b u8
	a u8

# A grid is made by calling its type, what it is made from named: `Grid(width, height)` every cell
# its type's zero, `Grid(width, height, fill = v)` every cell a copy of `v`, `Grid(width, height,
# cells = xs)` the list's cells (below). `g[x, y]` reads a cell and
# `g[x, y] = v` changes it in place; `g.width` and `g.height` are its size and `g.cells` its list.
test "made, read and changed by its coordinates":
	g = Grid(4, 3, fill = 0.0)
	g[1, 2] = 5.0
	g[3, 0] += 2.0
	expect g.width == 4
	expect g.height == 3
	expect g[1, 2] == 5
	expect g[3, 0] == 2
	expect g.cells == [0, 0, 0, 2, 0, 0, 0, 0, 0, 5, 0, 0]

# A number literal as the fill takes the cell type written (`Grid<f32>(...)`) or expected.
test "the cell type from the place or the type written":
	h Grid<f32> = Grid(2, 1, fill = 1.5)
	print(h.cells)
	k = Grid<u8>(1, 2, fill = 3)
	print(k.cells)
	prints """
		[1.5, 1.5]
		[3, 3]
		"""

test "cells that own memory, changed in place":
	names = Grid(2, 2, fill = "a")
	names[1, 0] = "b"
	print(names.cells)
	empty i64[] = []
	lists = Grid(2, 2, fill = empty)
	lists[1, 0].push(7)
	print(lists.cells)
	prints """
		["a", "b", "a", "a"]
		[[], [7], [], []]
		"""

# Being one block, a `Grid<Rgba8>`'s `g.cells.bytes()` is a texture's bytes as they are.
test "a struct's fields in a cell":
	g = Grid(2, 2, fill = Px(1, 2, 3, 4))
	g[1, 1].r = 9
	g[0, 1] = Px(5, 6, 7, 8)
	expect g.cells.bytes() == [1, 2, 3, 4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 2, 3, 4]
	expect g[1, 1].r == 9

# A cell that is a fixed array, or has one in a field, is bound to a name like any value.
type Corners:
	heights f32[4]
	kind u8

test "a fixed array of a cell bound to a name":
	g = Grid<Corners>(2, 1)
	g[1, 0].heights = [1.0, 2.0, 3.0, 4.0]
	h = g[1, 0].heights
	rows = Grid(2, 1, fill = [5, 6])
	r = rows[0, 0]
	expect h[2] == 3
	expect h[3] == 4
	expect r[1] == 6

# `g[a..b, y]` and `g[.., y]` are part of row `y` or all of it: a window `ref T[]` into the cells,
# no copy. `g[x, a..b]`, `g[x, ..]` and `g[a..b, c..d]` are a column or a block: a `GridView<T>`,
# lent, read by `v[x, y]` (from its own corner), `v.width`, `v.height`, `for` and `v.grid()` (a
# copy). A range's end left out is the grid's edge (`g[2.., 0..]`).
test "a row, a part of one, a column and a block, lent":
	g = Grid(4, 3, fill = 0)
	for i in 0..12:
		g.cells[i] = i
	print(g[.., 1])
	print(g[1..3, 1])
	column = g[1, ..]
	print("{column.width}x{column.height} {column.grid().cells}")
	block = g[2.., 1..3]
	print("{block.width}x{block.height} {block.grid().cells}")
	print(block[1, 0])
	prints """
		[4, 5, 6, 7]
		[5, 6]
		1x3 [1, 5, 9]
		2x2 [6, 7, 10, 11]
		7
		"""

# `for v in g` and `for (x, y), v in g` visit the cells in order, lent, with their coordinates (`_`
# for one not read); a view's too.
test "for visits the cells in order with their coordinates":
	g = Grid(2, 3, fill = 0)
	for i in 0..6:
		g.cells[i] = i
	for (x, y), v in g:
		print("({x}, {y}) {v}")
	sum = 0
	for v in g:
		sum += v
	print(sum)
	rows = []
	column = g[1, 1..]
	for (_, y), v in column:
		if v % 2 == 1:
			rows.push(str(y))
	print("rows {rows.join(" ")}")
	prints """
		(0, 0) 0
		(1, 0) 1
		(0, 1) 2
		(1, 1) 3
		(0, 2) 4
		(1, 2) 5
		15
		rows 0 1
		"""

test "continue and break keep the coordinates":
	g = Grid(3, 3, fill = 1)
	seen = []
	for (x, y), v in g:
		if y == 0 or x == 1: continue
		if y == 2: break
		seen.push((x, y + v - 1))
	expect seen == [(0, 1), (2, 1)]

# Each coordinate is checked on its own, so an `x` past the width stops the program instead of
# reading the next row; a slice past the edge stops it too.
test "an x past the width stops instead of reading the next row" stops Failure("x 4 is outside the grid's width 4"):
	g = Grid(4, 3, fill = 0)
	print(g[4, 0])

test "a slice past the edge stops" stops Failure("y 1..4 is outside the grid's 0..3"):
	g = Grid(4, 3, fill = 0)
	print(g[0, 1..4].height)

# A list of lists keeps its own commas (`rows[i, j]` is `rows[i][j]`); a range among them is an
# error. A slice has no step, a view is not sliced again, and its cells are read only.
test "one coordinate is not a cell" refuses GridCellSpelling:
	g = Grid(4, 3, fill = 0)
	print(g[1])

test "a list of lists is not sliced across its layers" refuses GridSliceInList:
	rows = [[1, 2], [3, 4]]
	print(rows[0.., 1])

test "a slice has no step" refuses GridSliceStep:
	g = Grid(4, 3, fill = 0)
	print(g[(0..4 step 2), 0])

test "a view is not sliced again" refuses GridViewSliced:
	g = Grid(4, 3, fill = 0)
	v = g[1.., 1..]
	print(v[0.., 0].width)

test "a view's cells are read only" refuses NoMethod:
	mut g = Grid(4, 3, fill = 0)
	v = g[1.., 1..]
	v[0, 0] = 1

test "the coordinates' loop goes over a grid" refuses GridForNotGrid:
	for (x, y), v in [1, 2]:
		print(v)

# In a loop `for x in 0..g.width` (or `0..g.height` for y) whose body does not bind `x` or `g`
# again, nor hand `g` (or what holds it) to a call or an assignment, a `g[x, y]` whose coordinates
# are two such loops' variables is read and written unchecked: the loops prove it inside, and a
# grid's size never changes. `use noStops` (2.6) sees it so.
fn brightened(mut g Grid<f64>, by f64):
	use noStops
	for y in 0..g.height:
		for x in 0..g.width:
			g[x, y] += by * g[x, y]

test "a loop over the width and the height reads and writes cells unchecked":
	g = Grid(3, 2, fill = 1.0)
	g[2, 1] = 4.0
	brightened(g, 0.5)
	print(g.cells)
	steps = Grid(4, 2, fill = 0)
	for x in 0..steps.width:
		for y in 0..steps.height:
			steps[x, y] = y * 10 + x
	print(steps.cells)
	prints """
		[1.5, 1.5, 1.5, 1.5, 1.5, 6]
		[0, 1, 2, 3, 10, 11, 12, 13]
		"""

test "a loop that resizes its grid keeps the checks" stops Failure("x 1 is outside the grid's width 1"):
	g = Grid(4, 1, fill = 0)
	for x in 0..g.width:
		g = Grid(1, 1, fill = 0)
		print(g[x, 0])

# `Grid(width, height, cells = xs)` makes the list's cells, row after row, a grid; a count that does
# not fill it stops the program. A grid is never written field by field. Its cells change in place
# (`g.cells[i] = v`), but `width`, `height` and `cells` never change themselves, so the cells always
# fill width x height.
test "a grid from its cells":
	g = Grid(2, 2, cells = [1, 2, 3, 4])
	expect g[1, 1] == 4

test "a grid from too few cells stops" stops Failure("a 2x2 grid holds 4 cells, given 3"):
	g = Grid(2, 2, cells = [1, 2, 3])
	print(g.width)

test "a grid of zeros":
	g Grid<f32> = Grid(2, 1)
	k = Grid<u8>(1, 2)
	print("{g.cells} {k.cells}")
	prints "[0, 0] [0, 0]"

test "a grid's size is given, what it is made from named" refuses GridLiteral:
	g = Grid(width = 2, height = 2)
	print(g.width)

test "a grid's size is fixed" refuses GridSizeFixed:
	mut g = Grid(2, 2, fill = 0)
	g.width = 4
	print(g.width)

test "a grid's cells keep their count" refuses GridSizeFixed:
	mut g = Grid(2, 2, fill = 0)
	g.cells.push(1)
	print(g.width)

# `g.paste(from, x, y)` copies the cells of the grid `from` in, its top left corner at (x, y); past
# the edge stops the program.
test "a grid pasted into another":
	g = Grid(4, 3, fill = 0)
	g.paste(Grid(2, 2, fill = 7), 1, 1)
	expect g.cells == [0, 0, 0, 0, 0, 7, 7, 0, 0, 7, 7, 0]

test "a paste past the edge stops" stops Failure("x 3..5 is outside the grid's 0..4"):
	g = Grid(4, 3, fill = 0)
	g.paste(Grid(2, 2, fill = 7), 3, 0)

# The math operators take grids of numbers as they take lists (7.8), cell by
# cell: `a + b`, `a - b`, `a * b` and `a / b` of two grids of one shape, `a * k`, `k * a` and
# `a / k` with a number. `a @ b` of two `Grid<f32>` or two `Grid<f64>` is their product: the
# first's height rows of the second's width, each cell the sum over k of `a[k, y] * b[x, k]`,
# added in the order of k. It runs on every processor, in bands of rows and blocks of the
# second's rows that fit the cache, its inner loops vectorized (14.3); `a @ b + c` (and
# `c + a @ b`) adds `c` to each cell in the same pass, with the result `(a @ b) + c` gives. A
# shape that does not fit stops the program. A list of lists keeps its own `@`.
test "grid math, cell by cell and the product":
	a = Grid(3, 2, cells = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
	b = Grid(2, 3, cells = [1.0, 0.0, 0.0, 1.0, 2.0, 2.0])
	c = Grid<f64>(2, 2, fill = 0.5)
	p = a @ b
	print("{p.width}x{p.height} {p.cells} {(a @ b + c).cells} {(c + a @ b).cells}")
	print("{(c * 2.0).cells} {(2.0 * c - c).cells} {(c / 2.0).cells} {(c + c).cells}")
	f = Grid(2, 2, cells = [f32(1.5), f32(2.0), f32(0.5), f32(1.0)])
	print((f @ f).cells)
	prints """
		2x2 [7, 8, 16, 17] [7.5, 8.5, 16.5, 17.5] [7.5, 8.5, 16.5, 17.5]
		[1, 1, 1, 1] [0.5, 0.5, 0.5, 0.5] [0.25, 0.25, 0.25, 0.25] [1, 1, 1, 1]
		[3.25, 5, 1.25, 2]
		"""

test "a large product gives each cell's sum in the order of k":
	n = 70
	m = Grid(n, n, cells = (0..n * n).map((it % 7) * 0.37 - 1.1))
	mm = m @ m + m
	differ = 0
	for y in 0..n:
		for x in 0..n:
			t = 0.0
			for k in 0..n:
				t += m[k, y] * m[x, k]
			if t + m[x, y] != mm[x, y]:
				differ += 1
	expect differ == 0

test "a product of grids that do not fit stops" stops Failure("a 2x1 grid @ a 2x1 one: the first's width is not the second's height"):
	g = Grid<f64>(2, 1, fill = 1.0)
	print((g @ g).width)

test "a product of integer grids is refused" refuses OperatorUndefined:
	g = Grid(2, 2, fill = 1)
	print((g @ g).width)
