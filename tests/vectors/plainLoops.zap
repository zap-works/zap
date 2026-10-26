# Plain loops vectorized (spec 14.3): element-wise loops over f64 and f32 lists run four or eight
# lanes a step, the rest one by one; each result is compared with the same loop written so it
# stays scalar (a `while`), at every length up to past two vector steps.

fn ramp(n i64, k f64):
	(0..n).map(it * k - 3.25)

fn ramp32(n i64, k f32):
	(0..n).map(f32(it) * k - f32(3.25))

fn axpy(a f64, x f64[], mut y f64[]):
	for i in 0..x.len:
		y[i] = a * x[i] + y[i]

fn axpyScalar(a f64, x f64[], mut y f64[]):
	i = 0
	while i < x.len:
		y[i] = a * x[i] + y[i]
		i += 1

test "a * x + y at every length":
	same = true
	for n in 0..20:
		x = ramp(n, 0.75)
		y = ramp(n, -1.5)
		z = y.copy()
		axpy(1.125, x, y)
		axpyScalar(1.125, x, z)
		same = same and y == z
	expect same

fn mixed(a f64[], b f64[], mut c f64[], lo i64, hi i64, k f64):
	for i in lo..hi:
		t = a[i + 1] - b[i] / k
		c[i] = -t * t + (a[i + 1] * a[i + 1] + 2.0).sqrt()
		c[i] += k

fn mixedScalar(a f64[], b f64[], mut c f64[], lo i64, hi i64, k f64):
	i = lo
	while i < hi:
		t = a[i + 1] - b[i] / k
		c[i] = -t * t + (a[i + 1] * a[i + 1] + 2.0).sqrt()
		c[i] += k
		i += 1

test "temporaries, negation, sqrt and a compound assignment, from any start":
	same = true
	for lo in 0..5:
		for hi in lo..17:
			a = ramp(18, 0.5)
			b = ramp(18, 0.25)
			c = fill(18, 0.0)
			d = fill(18, 0.0)
			mixed(a, b, c, lo, hi, 1.5)
			mixedScalar(a, b, d, lo, hi, 1.5)
			same = same and c == d
	expect same

fn scale32(mut xs f32[], ys f32[], k f32):
	for i in 0..xs.len:
		xs[i] = xs[i] * k + ys[i] / k

test "f32 lists, eight lanes, the same as f32 one by one":
	same = true
	for n in 0..20:
		xs = ramp32(n, f32(0.3))
		ys = ramp32(n, f32(1.7))
		zs = xs.copy()
		scale32(xs, ys, f32(0.7))
		i = 0
		while i < n:
			zs[i] = zs[i] * f32(0.7) + ys[i] / f32(0.7)
			i += 1
		same = same and xs == zs
	expect same

fn shiftUp(mut xs f64[]):
	for i in 0..xs.len - 1:
		xs[i + 1] = xs[i] + 1.0

test "a list read at another index than it is written at stays one by one":
	xs = fill(10, 0.0)
	shiftUp(xs)
	expect xs == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

fn dot(a f64[], b f64[]):
	use fusedMultiplyAdd
	s = 0.0
	for i in 0..a.len:
		s += a[i] * b[i]
	s

fn total(a f64[]):
	s = 0.0
	for i in 0..a.len:
		s += a[i]
	s

test "sums keep lane sums only under fusedMultiplyAdd":
	a = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0]
	expect dot(a, a) == 506
	expect total == {a: 66, [1e16, 1.0, -1e16, 1.0, 1.0]: 2}

fn mixInts(mut a i64[], b i64[], mut c u8[], d u8[], mut e i32[], f u32[], mut g u32[], k i64):
	for i in 0..a.len:
		a[i] = (a[i] + b[i] - k) ^ (b[i] & 255)
	for i in 0..c.len:
		c[i] = c[i] + d[i] - 3
	for i in 0..e.len:
		e[i] = (e[i] | 1) - i32(k)
	for i in 0..g.len:
		g[i] = g[i] * f[i] + 7

fn mixIntsScalar(
	mut a i64[],
	b i64[],
	mut c u8[],
	d u8[],
	mut e i32[],
	f u32[],
	mut g u32[],
	k i64
):
	i = 0
	while i < a.len:
		a[i] = (a[i] + b[i] - k) ^ (b[i] & 255)
		c[i] = c[i] + d[i] - 3
		e[i] = (e[i] | 1) - i32(k)
		g[i] = g[i] * f[i] + 7
		i += 1

test "integers lane by lane: u8 and u32 wrap, i32 and i64 checked":
	same = true
	for n in 0..40:
		a = (0..n).map(it * 1_000_003 - 17)
		b = (0..n).map(it * it * 31)
		c = (0..n).map(u8(it * 37 % 256))
		d = (0..n).map(u8(it * 101 % 256))
		e = (0..n).map(i32(it * 7 - 50))
		f = (0..n).map(u32(it * 2_654_435_761 % 4_294_967_296))
		g = (0..n).map(u32(it + 3_000_000_000))
		a2 = a.copy()
		c2 = c.copy()
		e2 = e.copy()
		g2 = g.copy()
		mixInts(a, b, c, d, e, f, g, 5)
		mixIntsScalar(a2, b, c2, d, e2, f, g2, 5)
		same = same and a == a2 and c == c2 and e == e2 and g == g2
	expect same

fn bits(xs u64[], ys u8[]):
	s = 0
	o u64 = 0
	b u8 = 0
	x u64 = 0
	for i in 0..xs.len:
		s += xs[i]
		o |= xs[i]
	for y in ys:
		b += y
	for i in 0..xs.len:
		x ^= xs[i] * 3
	(s, o, b, x)

test "unsigned sums wrap and bitwise sums keep lane sums in any order":
	xs = (0..37).map(u64(it) * 0x1234_5678_9ABC_DEF1)
	ys = (0..70).map(u8(it * 7 % 256))
	s = 0
	o = 0
	b = 0
	x = 0
	i = 0
	while i < ys.len:
		if i < xs.len:
			s += xs[i]
			o |= xs[i]
			x ^= xs[i] * 3
		b += ys[i]
		i += 1
	expect bits(xs, ys) == (s, o, b, x)

test "a signed lane that overflows stops the program" stops IntegerOverflow:
	fn bump(mut xs i64[]):
		for i in 0..xs.len:
			xs[i] = xs[i] + 9_000_000_000_000_000_000

	xs = [1, 2, 3, 4, 5, 6, 7, 300_000_000_000_000_000]
	bump(xs)
	print(xs)

test "every element is checked before the vector steps" stops IndexOutOfBounds:
	fn copyInto(mut out f64[], xs f64[], at i64):
		for i in 0..xs.len:
			out[at + i] = xs[i]

	out = fill(8, 0.0)
	copyInto(out, [1.0, 2.0, 3.0, 4.0, 5.0], 4)
	print(out)

test "the vector steps are AVX instructions on ymm registers":
	code = disassembly(
		"n = args.len + 9\nx = (0..n).map(f64(it))\nmut y = x.copy()\nfor i in 0..x.len:\n\ty[i] = 2.0 * x[i] + y[i]\nprint(y)\n",
		"main"
	)
	expect "vmulpd   ymm" in code and "vaddpd   ymm" in code
