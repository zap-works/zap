# `.copy()` is a deep copy for every type: a map (one word owning a table), an enum payload,
# a struct with lists, maps, an option and a closure capturing an owned list. Every copy is
# freed on its own (zap test poisons freed blocks).
type Shape:
	Dot
	Line(pts i64[], label str)
type Bag:
	names str[]
	tags {str: i64}
	shape Shape
	extra i64[]?
mut m {i64: i64} = {}
m.add(1, 2)
m.add(5, 3)
c = m.copy()
m.add(1, 10)
print("{c.get(1) ?? 0} {m.get(1) ?? 0}")
mut tables = []
tables.push(c)
tables.push(tables[0].copy())
print(tables[1].get(5) ?? 0)
mut t {str: i64} = {}
t.add("ab", 1)
pts i64[] = [1, 2]
extra i64[] = [7]
b = Bag(names = ["x", "yz"], tags = t, shape = .Line(pts, "l"), extra)
d = b.copy()
print(d.names[1])
print(d.tags.get("ab") ?? 0)
match d.shape:
	Line(ps, label): print("{ps.len} {label}")
	Dot: print("dot")
print(d.extra ?? [])
owned str[] = ["p", "q"]
f = (k i64): owned.len + k
g = f.copy()
print(g(1))
print(f(2))

test "copy() copies every part, and each copy is freed on its own":
	main()
	prints """
	    2 12
	    3
	    yz
	    1
	    2 l
	    [7]
	    3
	    4
	    """
