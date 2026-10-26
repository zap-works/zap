# Names the compiler writes for the program stay the program's: a generic of another module
# instantiated with a type named like one of that module's, types named like the runtime's
# tuples and the Cursor its derived decoders use, instances whose type arguments print alike,
# modules whose names differ by '.' and '_', defaults of another module naming its own types, a
# pub function named like a built-in (stock's fill) that a module not importing it never sees.
import fs
import geo
import shape.flat
import shapeFlat
import stock

type Point:
	x i64
	y i64
	z i64

type Tuple2:
	mine i64

type Cursor:
	mine str

type Hidden:
	v str

type Mode:
	Other

type Holder<T>:
	v T

fn show<T Show>(x T) str:
	"{x}"

w = geo.wrap(Point(7, 8, 9))
print(w.top())
print(geo.here())
print(Tuple2(mine = 1))
pair = 1, "x"
_, x = pair
print(x)
mut some i64?[] = []
some.push(1)
some.push(none)
nothing i64[]? = none
print(show(some))
print(show(nothing))
a Holder<i64?[]> = Holder(v = some)
b Holder<i64[]?> = Holder(v = nothing)
print(a)
print(b)
print(flat.who())
print(shapeFlat.who())
print(Point.fromJson(Point(1, 2, 3).toJson()))
print(Point.fromBytes(Point(4, 5, 6).toBytes()))
print(Cursor(mine = "c"))
print(geo.Cfg())
print(geo.ask("q "))
mut shelf = stock.Shelf(counts = [])
mut extra = []
shelf.fill(extra, 2)
print(geo.coded(shelf.counts[0] + extra.len))

test "the compiler's names for the program's types and modules do not meet":
	main()
	prints fs.readFile("tests/programs/sameNames/main.expected") ?? ""
