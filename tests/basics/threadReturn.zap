# `t = f(...)` then `if <test of t> { ... }`: a literal f returns that fails the test goes past the
# if at once; one that passes it, a t read later, or an argument that calls keep the long way
fn hit(x f64):
	if x < 0.0: return -1.0
	if x > 100.0: return 50.0
	x * 2.0

fn half(x f64):
	x / 2.0

mut sum = 0.0
mut best = 1e300
for x in [-5.0, 3.0, 200.0, 7.0, -1.0]:
	t = hit(x)
	if t > 1e-9 and t < best:
		best = t
		sum += t
print("{sum} {best}")
mut seen = 0.0
for x in [-5.0, 4.0]:
	t = hit(x)
	if t > 1e-9:
		seen += 1.0
	seen += t
print(seen)
mut calls = 0.0
for x in [-6.0, 10.0]:
	t = hit(half(x))
	if t > 0.0:
		calls += t
print(calls)

test "returns past the if they decide":
	main()
	prints """
		6 6
		8
		10
		"""
