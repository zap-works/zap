# Every subexpression runs once, in the order it is written, whatever the compiler makes of the
# form around it: compound and plain assignments by index, a map's value changed in place,
# arithmetic on lists and structs of numbers with a number, range bounds.

mut steps = 0

fn at(tag str, v i64):
	steps += 1
	print("{tag}")
	v

fn num(tag str, v f64):
	print("{tag}")
	v

fn key(tag str):
	print("{tag}")
	"k".repeat(1)

fn nums(tag str):
	print("{tag}")
	[1.0, 2.0]

type V2:
	x f64
	y f64

fn vec(tag str):
	print("{tag}")
	V2(1.0, 2.0)

test "the indexes of a place, outermost first, then the value":
	grid = [[0, 0], [0, 0]]
	grid[at("row", 1)][at("col", 0)] += at("add", 5)
	print(grid)
	xs = [0, 0, 0]
	xs[at("index", 2)] = at("value", 9)
	print(xs)
	prints """
		row
		col
		add
		[[0, 0], [5, 0]]
		index
		value
		[0, 0, 9]
		"""

test "a statement arm of a match assigns by a computed index":
	xs = [0, 0]
	o i64? = 4
	if o is n:
		xs[at("i", 1)] += at("v", n)
	print(xs)
	prints """
		i
		v
		[0, 4]
		"""

test "m[k] op= v changes the value in place and only reads the key":
	m {str: i64} = {}
	m["k"] = 3
	k = "k".repeat(1)
	m[k] *= 3
	print(k)
	print(m)
	m[key("m")] += 1
	print(m)
	s {str: str} = {}
	s["k"] = "a"
	s[k] += "b"
	print(s)
	prints r"""
		k
		{"k": 9}
		m
		{"k": 10}
		{"k": "ab"}
		"""

test "a number and a list or a struct of numbers: the left side first":
	print(nums("list") * num("scale", 2.0))
	print(num("scale", 3.0) * nums("list"))
	print(num("factor", 4.0) * vec("vec"))
	print(vec("vec") / num("divisor", 2.0))
	prints """
		list
		scale
		[2, 4]
		scale
		list
		[3, 6]
		factor
		vec
		V2(x = 4, y = 8)
		vec
		divisor
		V2(x = 0.5, y = 1)
		"""

test "a range's start, end and step in order":
	seen = []
	for i in at("start", 1)..at("end", 3):
		seen.push(i)
	print("{seen[0]} {seen[1]}")
	seen.clear()
	for i in at("start", 0)..at("end", 5) step at("step", 3):
		seen.push(i)
	print("{seen[0]} {seen[1]}")
	prints """
		start
		end
		1 2
		start
		end
		step
		0 3
		"""

type Inst:
	op i64
	words i64[]
	at i64

type Code:
	insts Inst[]

	fn add(op i64):
		insts.push(Inst(op, words = [op], at = insts.len))

fn emitInto(mut c Code, op i64):
	c.insts.push(Inst(op, words = [op], at = c.insts.len))

test "a literal pushed reads the list before the push":
	c = Code(insts = [])
	for i in 0..3:
		c.emitInto(i)
		c.add(i)
	print(c.insts.map(.at))
	prints """
		[0, 1, 2, 3, 4, 5]
		"""
