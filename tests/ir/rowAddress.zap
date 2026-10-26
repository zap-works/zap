# a row of a table of 16 bits read at constant columns: its address is a base register plus a
# scaled index register, a displacement per column

type Rows:
	cells u16[100, 4]

fn columnSums(rows Rows, order u16[]):
	sums i64[4]
	for r in order:
		for j in 0..4:
			sums[j] += rows.cells[r, j]
	sums

fn firstOfEach(rows Rows, order u16[]):
	total = 0
	for r in order:
		total += i64(rows.cells[r, 0]) + 2 * i64(rows.cells[r, 3])
	total

test "a table's row at a register, its columns at constants":
	cells u16[100, 4]
	for r in 0..100:
		for j in 0..4:
			cells[r, j] = r * 4 + j
	rows = Rows(cells)
	order = [u16(3), 7, 99, 0]
	expect rows.columnSums(order) == [436, 440, 444, 448]
	expect rows.firstOfEach(order) == (12 + 28 + 396 + 0) + 2 * (15 + 31 + 399 + 3)
