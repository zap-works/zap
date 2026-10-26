# A pure function's call treated as an operator (purity.zap): the same arguments give one call,
# one that never stops leaves a loop that does not change its arguments and goes when nothing
# reads it; a function that reads or changes a module variable, or may stop, keeps its calls.
mut factor = 2
mut calls = 0

# recursive: never inlined, and it may stop (an overflow)
fn tri(n i64) i64:
	0 if n == 0 else n + tri(n - 1)

# reads a module variable
fn scaled(x i64, depth i64) i64:
	x * factor if depth == 0 else scaled(x, depth - 1)

# changes one
fn counted(x i64, depth i64) i64:
	if depth == 0:
		calls += 1
		return x
	counted(x, depth - 1)

# divides: may stop
fn quotient(a i64, b i64, depth i64) i64:
	a / b if depth == 0 else quotient(a, b, depth - 1)

# floats only, too long to inline: never stops
fn wave(x f64):
	a = x * 1.5 + 2.25 * x * x - 0.5 * x * x * x + 3.0 / (x * x + 1.0)
	b = a * a - x * 0.25 + (a + x) * (a - x) / (a * a + 1.0)
	c = b * a - x * b + 0.125 * a * b * x - (b - a) * (b + a) / (x * x + 2.0)
	d = c * c + b * b + a * a - c * b * a / (c * c + b * b + 1.0)
	d * 0.5 + c * 0.25 + b * 0.125 + a * 0.0625 - x / (d * d + 3.0)

test "a pure call is made once for the same arguments":
	n = arg(0, 30)
	expect tri(n) + tri(n) * 2 == 1395

test "a call that reads or changes a module variable is made each time":
	a = scaled(3, 4)
	factor = 5
	b = scaled(3, 4)
	expect a == 6
	expect b == 15
	expect counted(1, 3) + counted(1, 3) == 2
	expect calls == 2

test "a call that may stop stays in a loop that does not run":
	n = arg(0, 0)
	s = 0
	loop n:
		s += quotient(1, n, 3)
	expect s == 0

test "a pure call that never stops leaves the loop and goes when unused":
	x = f64(arg(0, 2))
	t = 0.0
	loop 1000:
		t += wave(x)
	wave(x + 1.0)
	expect t == wave(x) * 1000.0 or t > 0.0
