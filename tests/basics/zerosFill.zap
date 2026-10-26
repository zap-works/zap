# zeros(n) and fill(n, v): the element type comes from the place, an i64 when nothing expects one;
# more sizes make lists of lists, each row its own.

type Cell:
	alive bool
	age i64

fn total(xs u8[]) i64:
	xs.sum()

fn weights() f64[]:
	zeros(3)

test "zeros takes the element type from the place":
	a = zeros(3)
	b u8[] = zeros(2)
	c f32[] = zeros(2)
	d bool[] = zeros(2)
	e i64?[] = zeros(2)
	print("{a} {b} {c} {d} {e} {total(zeros(4))} {weights()}")
	prints "[0, 0, 0] [0, 0] [0, 0] [false, false] [none, none] 0 [0, 0, 0]"

test "fill copies a value made once":
	xs = fill(3, testTick())
	words = fill(2, "ab")
	print("{xs} {testTick()} {words} {fill(2, u8(7))} {fill(2, Cell(alive = true, age = 3))}")
	prints "[1, 1, 1] 2 [\"ab\", \"ab\"] [7, 7] [Cell(alive = true, age = 3), Cell(alive = true, age = 3)]"

test "more sizes make lists of lists with a row of their own":
	g = zeros(2, 3)
	g[0][1] = 5
	h i32[,] = fill(2, 2, -1)
	h[1][0] = 4
	print("{g} {h} {zeros(0, 3).len}")
	prints "[[0, 5, 0], [0, 0, 0]] [[-1, -1], [4, -1]] 0"

test "zeros and fill make a fixed array":
	a u8[4] = zeros(4)
	b i64[3] = fill(3, 9)
	a[2] = 1
	print("{a} {b}")
	prints "[0, 0, 1, 0] [9, 9, 9]"

test "a variable or a function of the same name wins":
	fill = 3
	expect fill == 3

test "zeros of a struct asks for fill" refuses ZerosElement:
	xs Cell[] = zeros(2)
	print(xs.len)
