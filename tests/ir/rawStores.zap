# A list's length written by the runtime's raw store (truncate, pop) inside a loop: the loop reads
# it again each turn (the form once kept the first read for the whole loop).
type Stacks:
	a i64[]
	b i64[]

fn drain(mut s Stacks, n i64):
	loop n:
		s.a.pop()
		s.b.pop()
	s.a.len * 100 + s.b.len

test "pops in a loop":
	s = Stacks(a = [1, 2, 3, 4, 5], b = [1, 2, 3, 4, 5, 6, 7, 8])
	expect s.drain == {3: 205, 9: 0}
