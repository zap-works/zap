# Grid<T>: a rectangle of values in one block, row after row from the top (spec 7.10).
# `Grid(width, height, fill = v)` makes one, `g[x, y]` reads or changes a cell (each coordinate
# checked on its own), `g[.., y]`, `g[x, ..]` and `g[a..b, c..d]` lend a row, a column and a
# block without a copy, and `for (x, y), v in g` visits the cells in order. The block is
# contiguous: `g.cells.bytes()` of a `Grid<Rgba8>` is a texture's bytes as they are.

pub type Grid<T>:
	width i64
	height i64
	cells T[]

	# g[x, y]
	fn index(x i64, y i64) ref T:
		cells[gridPlace(width, height, x, y)]

	# g[x, y] where it changes
	mut fn indexMut(x i64, y i64) mut ref T:
		found = mut ref cells[gridPlace(width, height, x, y)]
		found

	# g[left..right, y]: a part of row y, a window into the cells
	fn gridRow(left i64, right i64, y i64) ref T[]:
		gridSpan(left, right, width, "x")
		at = gridPlace(width.max(1), height, 0, y)
		cells[at + left..at + right]

	# g[left..right, top..bottom] (a column: right is left + 1)
	fn gridBlock(left i64, right i64, top i64, bottom i64) GridView<T>:
		gridSpan(left, right, width, "x")
		gridSpan(top, bottom, height, "y")
		GridView<T>(grid = self, left, top, width = right - left, height = bottom - top)

	# g[x, top..bottom]
	fn gridColumn(x i64, top i64, bottom i64) GridView<T>:
		gridBlock(x, x + 1, top, bottom)

	# the cells of `from` copied into the grid, its top left corner at (x, y); a cell past the edge
	# stops the program
	pub mut fn paste(from Grid<T>, x i64, y i64):
		gridSpan(x, x + from.width, width, "x")
		gridSpan(y, y + from.height, height, "y")
		for j in 0..from.height:
			for i in 0..from.width:
				cells[(y + j) * width + x + i] = from.cells[j * from.width + i].copy()

# A part of a grid, lent: a column (`g[x, ..]`) or a block (`g[a..b, c..d]`). Its cell (x, y)
# is the grid's (left + x, top + y).
pub type GridView<T>:
	grid ref Grid<T>
	left i64
	top i64
	width i64
	height i64

	# v[x, y]
	fn index(x i64, y i64) ref T:
		gridCheck(width, height, x, y)
		grid.cells[viewPlace(x, y)]

	# where the view's cell (x, y) is among its grid's cells
	fn viewPlace(x i64, y i64) i64:
		(top + y) * grid.width + left + x

	# the view's cells, row after row, copied into a grid of their own
	fn grid() Grid<T>:
		out T[] = []
		out.reserve(width * height)
		for y in 0..height:
			for x in 0..width:
				out.push(grid.cells[viewPlace(x, y)].copy())
		Grid<T>(width = width, height = height, cells = out)

# Grid(width, height): every cell its type's zero
fn gridZeros<T>(width i64, height i64) Grid<T>:
	sample T[] = []
	gridFilled(width, height, __zeroElem(sample))

# Grid(width, height, fill = v): every cell a copy of v
fn gridFilled<T>(width i64, height i64, cell T) Grid<T>:
	if width < 0 or height < 0:
		fail("a grid's size is never negative: {width}x{height}")
	Grid<T>(width = width, height = height, cells = fill(width * height, cell))

# Grid(width, height, cells = xs): the cells, row after row, as a grid; their count must fill it
fn gridOfCells<T>(width i64, height i64, move cells T[]) Grid<T>:
	n = cells.len
	gridMade(width, height, move cells) ??
		fail("a {width}x{height} grid holds {width * height} cells, given {n}")

# the cells as a grid, none when their count does not fill it (std's decoders, which stop on
# nothing)
fn gridMade<T>(width i64, height i64, move cells T[]) Grid<T>?:
	if width < 0 or height < 0 or height > 0 and width > cells.len / height or
		width * height != cells.len:
		return none
	Grid<T>(width = width, height = height, cells = cells)

# each coordinate checked on its own: an x past the width stops instead of reading the next row
fn gridCheck(width i64, height i64, x i64, y i64):
	if x < 0 or x >= width:
		fail("x {x} is outside the grid's width {width}")
	if y < 0 or y >= height:
		fail("y {y} is outside the grid's height {height}")

fn gridPlace(width i64, height i64, x i64, y i64) i64:
	gridCheck(width, height, x, y)
	y * width + x

fn gridSpan(lo i64, hi i64, size i64, axis str):
	if lo < 0 or hi > size or lo > hi:
		fail("{axis} {lo}..{hi} is outside the grid's 0..{size}")

# ---------- math on grids of numbers ----------
# The checker writes `a @ b`, `a @ b + c`, `a + b` (- * / alike) and `a * k` (/ alike, k a number)
# of grids of numbers as these calls (grid.zap of the compiler). A shape that does not fit stops the
# program.

# a op b cell by cell (op as vec.zap's apply takes it)
fn gridEw<T Num>(a Grid<T>, b Grid<T>, op i64) Grid<T>:
	if a.width != b.width or a.height != b.height:
		fail("a {a.width}x{a.height} grid and a {b.width}x{b.height} one do not match")
	Grid<T>(width = a.width, height = a.height, cells = vecEw(a.cells, b.cells, op))

# a op s on every cell
fn gridScalar<T Num>(a Grid<T>, s T, op i64) Grid<T>:
	Grid<T>(width = a.width, height = a.height, cells = vecScalar(a.cells, s, op))

# a @ b: a's height rows of b's width, each cell the sum over k of a[k, y] * b[x, k] in the order of
# k; with c (a grid of that shape, else none), c added to each cell after its sum (`a @ b + c` in
# one pass). Bands of rows run on every processor; within a band, b's rows are taken a block that
# fits the cache at a time, and each row of the band is updated by each of them (plain loops, so
# vectorized, 14.3).
fn gridProduct<T Num>(a Grid<T>, b Grid<T>, c Grid<T>?) Grid<T>:
	if a.width != b.height:
		fail("a {a.width}x{a.height} grid @ a {b.width}x{b.height} one: the first's width is not the second's height")
	rows = a.height
	cols = b.width
	if c is d and (d.width != cols or d.height != rows):
		fail("a {cols}x{rows} product + a {d.width}x{d.height} grid do not match")
	band = 16
	parts = parallelMap((rows + band - 1) / band, p:
		top = p * band
		out T[] = []
		count = ((top + band).min(rows) - top) * cols
		out.reserve(count)
		gridBand(a.cells, b.cells, out, a.width, cols, top, (top + band).min(rows))
		if c is d:
			gridAddRows(out, d.cells, top * cols)
		out
	)
	Grid<T>(width = cols, height = rows, cells = listJoinParts(parts))

# rows [top, bottom) of the product of ac (inner wide) and bc (cols wide) pushed onto out: each
# row's cells start at zero and add a[k] * b's row k for k in order, b's rows a cache's block at
# a time
fn gridBand<T Num>(ac T[], bc T[], mut out T[], inner i64, cols i64, top i64, bottom i64):
	zero = __zeroElem(out)
	loop (bottom - top) * cols:
		out.push(zero)
	block = (32_768 / cols.max(1)).max(8)
	for k0 in 0..inner step block:
		k1 = (k0 + block).min(inner)
		for i in top..bottom:
			o = (i - top) * cols
			for k in k0..k1:
				aik = ac[i * inner + k]
				bo = k * cols
				for j in 0..cols:
					out[o + j] += aik * bc[bo + j]

# out[j] += cs[at + j] for every cell of out
fn gridAddRows<T Num>(mut out T[], cs T[], at i64):
	for j in 0..out.len:
		out[j] += cs[at + j]
