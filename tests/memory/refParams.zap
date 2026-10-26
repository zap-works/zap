# References through generics, loops and mutable parameters: no copies, no aliasing bugs.
type Pair:
	a i64
	b str

fn sum(xs ref i64[]):
	t = 0
	for x in xs:
		t += x
	t

fn show<T Show>(x T) str:
	"{x}"

fn firstOf(ps Pair[]) ref Pair?:
	if ps.isEmpty: return none
	ps[0]

fn bump(mut p Pair):
	p.a += 1
	p.b += "!"

xs = [1, 2, 3]
r = xs
print(sum(r))
print(sum(xs))
print(show(r.len))
h = xs[2]
print(show(h))
mut ps = [Pair(a = 1, b = "x")]
match firstOf(ps):
	p: print("{p.a} {p.b}")
	none: print("none")
bump(mut ref ps[0])
print(ps[0].b)
q = mut ref ps[0]
q.a = 10
bump(q)
print("{ps[0].a} {ps[0].b}")
names = ps.map(.b)
print(names)
rp = ps
print(rp.map(.a).len)

test "references through generics, loops and mut parameters neither copy nor alias":
	main()
	prints """
	    6
	    6
	    3
	    3
	    1 x
	    x!
	    11 x!!
	    ["x!!"]
	    1
	    """
