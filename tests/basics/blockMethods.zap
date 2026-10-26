# Methods written in their type's block (spec 5.2): the receiver implicit, borrowed to change it
# when the body changes it, checked before the other bodies and in any order, their calls of one
# another solved together; the errors that ask for `mut fn`.

type Cache:
	keys i32[]
	vals i32[]
	hits i64

	fn put(k i32, v i32):
		keys.push(k)
		vals.push(v)

	fn find(k i32) i32?:
		for i, x in keys:
			if x == k: return vals[i]
		none

	fn get(k i32):
		r = find(k)
		if r != none: hits += 1
		r ?? -1

	fn twice(k i32, v i32):
		put(k, v)   # a call of a method that changes it
		self.put(k + 1, v)

	fn count():
		keys.len

fn fill(mut c Cache, n i32):
	for i in 0..n:
		c.put(i, i * 10)

test "a method changes its receiver when its body does, and reads it otherwise":
	c = Cache(keys = [], vals = [], hits = 0)
	c.twice(1, 10)
	c.fill(2)
	expect c.get == {1: 10, 7: -1}
	expect c.hits == 1
	expect c.count() == 4

type Walk:
	n i64
	log i64[]

	fn a(k i64):   # calls b, which changes the receiver only after it calls a back
		if k > 0: b(k - 1)

	fn b(k i64):
		if k > 0: a(k - 1)
		n += 1

	fn ping(k i64):
		if k > 0: pong(k - 1)

	fn pong(k i64):   # neither changes it
		if k > 0: ping(k - 1)

	fn note(k i64):
		mark(k)

	fn mark(k i64):
		lend(log, k)

	fn newest():
		log.last ?? 0

fn lend(mut xs i64[], k i64):
	xs.push(k)

test "methods that call one another are solved together":
	w = Walk(n = 0, log = [])
	w.a(3)
	w.ping(3)
	w.note(7)
	expect w.n == 2
	expect w.newest() == 7

type Pile<T Show>:
	items T[]
	count i64

	fn add(x T):
		print(x)
		bump()

	fn bump():
		count += 1

	fn shown<U Show>(tag U) str:
		"{tag}: {items.len} {count}"

	fn reset<U Show>(tag U):
		items = []
		print(tag)

type Color:
	Red
	Green

	fn next():
		match self:
			Red: Color.Green
			Green: Color.Red

	fn flip():
		self = next()

bound Sized:
	fn area(self Sized) i64
	fn widen(mut self Sized, by i64)

type Box2:
	w i64
	h i64

	fn area():
		w * h

	fn widen(by i64):
		w += by

fn grow<T Sized>(mut x T):
	x.widen(2)

test "a generic type's, an enum's and a bound's methods":
	p = Pile<str>(items = [], count = 0)
	p.add("a")
	print(p.shown(1))
	p.reset("gone")
	k = Color.Red
	k.flip()
	b = Box2(w = 1, h = 2)
	grow(b)
	print("{k} {b.area()} {p.count}")
	prints """
		a
		1: 0 1
		gone
		Green 6 1
		"""

type Slot:
	v i64
	xs i64[]
	name str

	fn written():
		v = 4

	fn refd():
		r = mut ref xs
		r.push(9)

	fn twiceAll():
		for mut x in xs:
			x *= 2

	fn takeName():
		print(move name)

	fn reads():
		xs.len + name.len

test "a mut ref, a mut loop name and a move out of a field change it":
	s = Slot(v = 1, xs = [], name = "nm")
	s.written()
	s.refd()
	s.twiceAll()
	s.takeName()
	print("{s.v} {s.xs} '{s.name}' {s.reads()}")
	prints """
		nm
		4 [18] '' 1
		"""

test "a change inside a lambda asks for mut fn" refuses ReceiverUntold("'put' changes its receiver inside a lambda: write `mut fn put`"):
	type W:
		xs i64[]

		fn put(v i64):
			f = (x i64): xs.push(x)
			f(v)
	w = W(xs = [])
	w.put(1)

test "a generic's method found changing after another read it asks for mut fn" refuses ReceiverUntold:
	type Walk<T>:
		n i64
		tag T

		fn a(k i64):
			if k > 0: b(k - 1)

		fn b(k i64):
			if k > 0: a(k - 1)
			n += 1
	w = Walk<str>(n = 0, tag = "x")
	w.b(4)

test "the fields come before the methods" refuses FieldAfterMethods:
	type W:
		n i64

		fn get():
			n
		m i64
