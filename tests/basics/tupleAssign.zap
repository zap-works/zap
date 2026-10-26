# `(a, b) = (x, y)` of plain scalars: every value reads the names as they were before the
# statement (swaps, Fibonacci steps, rotations), new names and existing ones, f32 and f64,
# inside loops whose locals live in registers.
fn fib(n i64):
	a = 0
	b = 1
	loop n:
		a, b = b, a + b
	a

fn rotate(n i64):
	x = 1
	y = 2
	z = 3
	loop n:
		x, y, z = y, z, x * 10
	(x, y, z)

fn spin(steps i64):
	c = 1.0
	s = 0.0
	ca f32 = 0.99500417
	sa f32 = 0.09983342
	loop steps:
		c, s = c * ca - s * sa, c * sa + s * ca
	c * c + s * s

test "values read the names as they were":
	expect fib(10) == 55
	expect fib(90) == 2_880_067_194_370_816_120
	p, q, r = rotate(4)
	expect p == 20 and q == 30 and r == 100
	a = 1.5
	b = 2.5
	a, b = b, a
	expect a == 2.5 and b == 1.5
	n, half = 7, 3.5
	expect n == 7 and half == 3.5
	expect (spin(1000) - 1.0).abs() < 0.001
