# A module with a Point of its own and generics the main module instantiates with its Point.

pub type Point:
	lat f64
	lon f64

pub type Stack<T>:
	items T[]

	pub fn top() ref T:
		items[len - 1]

pub fn wrap<T>(move x T) Stack<T>:
	Stack<T>(items = [x])

pub fn here() Point:
	Point(lat = 1.5, lon = 2.5)

type Hidden:
	v i64

type Mode:
	Fast
	Slow(level i64)

# defaults that name this module's private types: they mean these wherever the literal is
pub type Cfg:
	tag str = "{Hidden(7).v}"
	mode str = "{Mode.Slow(3)}"

pub fn ask(q str, m str = "{Mode.Slow(9)} {Hidden(v = 1)}") str:
	q + m

type Count = i64 in 0..=1000

type Book:
	entries Count = 0

fn entriesOf(n i64) Count:
	Count(n)

# the built-in fill, whatever another module's pub fill (stock's) changes
pub fn coded(n i64) i64:
	b = Book()
	entries = entriesOf(n)
	lengths u8[] = fill(entries, 3)
	b.entries = entries
	b.entries + lengths.len
