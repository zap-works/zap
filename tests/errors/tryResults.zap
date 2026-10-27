# `try` on a result in forms the lowering took apart: a struct too big for registers, and a
# statement in a match arm that is the tail of a function without a value.

type Big:
	a u64
	b bool = false
	c i64 = 0
	d i64 = 0
	e i64 = 0
	f i64 = 0
	g i64 = 0
	h i64 = 0
	i i64 = 0
	j i64 = 0
	k i64 = 0
	l i64 = 0
	n1 i64 = 0
	n2 i64 = 0
	n3 i64 = 0
	n4 i64 = 0
	n5 i64 = 0
	n6 i64 = 0
	n7 i64 = 0
	n8 i64 = 0

fn bigOf(n u64) Big ? str:
	if n > 100: return "past"
	Big(a = n)

fn bigField(n u64) i64 ? str:
	d = try bigOf(n)
	i64(d.a)

test "try binds a struct of twenty fields":
	print(bigField(5) ?? -1)
	print(bigField(500) ?? -1)
	prints """
		5
		-1
		"""

fn checked(n i64) ? str:
	if n > 1: return "big"

fn inArm(n i64) ? str:
	match n:
		0: print("zero")
		_: try checked(n)

test "try is a statement in a match arm that ends a function without a value":
	for n in [0, 5]:
		match inArm(n):
			error: print(error)
			_: print("ok")
	prints """
		zero
		ok
		big
		"""

type Stepper:
	n i64

fn stepA(mut s Stepper) ? str:
	s.n += 1
	if s.n > 5: return "big"

fn stepB(mut s Stepper) ? str:
	s.n += 2
	if s.n < 0: return "neg"

fn stepEither(mut s Stepper, first bool):
	if first: return s.stepA()
	s.stepB()

fn stepLoop(mut s Stepper, first bool) i64 ? str:
	loop 3:
		try s.stepEither(first)
	s.n

test "an inferred result returned and ended by calls of a result without a value":
	s = Stepper(n = 0)
	print(s.stepLoop(true) ?? -1)
	t = Stepper(n = 0)
	print(t.stepLoop(false) ?? -1)
	u = Stepper(n = 3)
	print(u.stepLoop(true) ?? -1)
	prints """
		3
		6
		-1
		"""

type Tally:
	total i64

	fn add(e i64) i64 ? str:
		if e > 100: return "too big"
		total += e
		total

	fn pick(k i64, t i64) i64 ? str:
		q = k * 2
		if q > 0:
			try add(q)
		if q > 5: return q
		t

test "a value returned after a try of a method in an if is the ok side, though a condition narrowed it":
	w = Tally(total = 0)
	print(w.pick(1, 7) ?? -1)
	print(w.pick(4, 7) ?? -1)
	print(w.pick(500, 7) ?? -1)
	prints """
		7
		8
		-1
		"""
