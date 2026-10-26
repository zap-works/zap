# A small aggregate of numbers (up to four leaves) a function reads comes in registers, its leaves
# spread over them, and one it gives back (two to four leaves) goes back in registers (spec 14.2):
# their values are the same as through memory, in any order and mix of integers and floats.

type P3:
	x f64
	y f64
	z f64

	fn dot(o P3):
		x * o.x + y * o.y + z * o.z

	fn plus(o P3):
		P3(x = x + o.x, y = y + o.y, z = z + o.z)

type Mixed:
	n i64
	f f64
	m i32
	g f32

# each argument where the other's register was: the moves in a cycle
fn swapped(a P3, b P3) (P3, P3):
	if a.x > 1e9: return a.swapped(b)
	(b, a)

fn rotated(a f64, b f64, c f64, d f64) (f64, f64, f64, f64):
	if a > 1e9: return rotated(a, b, c, d)
	(d, a, b, c)

fn cross(a Vec3, b Vec3) Vec3:
	if a.x > 1e9: return cross(b, a)
	a.cross(b)

fn mixedNext(m Mixed, k i64) Mixed:
	if k > 1_000_000: return m.mixedNext(k - 1)
	Mixed(n = m.n + k, f = m.f * 2.0, m = m.m - 1, g = m.g + 0.5)

fn divmod(a i64, b i64):
	if b == 0: return (0, 0)
	(a / b, a % b)

# past the registers: a, b spread, c by its address
fn many(a P3, b P3, c P3) f64:
	if a.x > 1e9: return b.many(c, a)
	a.dot(b) + c.z

# one value given twice: its registers go to two places each
fn gap(a P3, b P3) f64:
	if a.x > 1e9: return b.gap(a)
	d = P3(x = a.x - b.x, y = a.y - b.y, z = a.z - b.z)
	d.dot(d)

# a recursion that keeps leaves across its calls
fn sumTo(n i64, acc P3) P3:
	if n == 0: return acc
	sumTo(n - 1, acc.plus(P3(x = 1.0, y = n.toF64(), z = 0.5)))

test "small aggregates go and come back in registers":
	a = P3(x = 1.0, y = 2.0, z = 3.0)
	b = P3(x = 4.0, y = 5.0, z = 6.0)
	p, q = a.swapped(b)
	print("{p.x} {p.y} {p.z} {q.x} {q.y} {q.z} {a.dot(b)}")
	print("{rotated(1.0, 2.0, 3.0, 4.0)}")
	print("{cross(Vec3(1, 0, 0), Vec3(0, 1, 0))}")
	m = mixedNext(Mixed(n = 5, f = 1.5, m = 7, g = 2.0), 3)
	print("{m.n} {m.f} {m.m} {m.g}")
	print("{divmod(17, 5)}")
	print("{a.many(b, P3(x = 0.0, y = 0.0, z = 0.25))}")
	s = sumTo(100, P3(x = 0.0, y = 0.0, z = 0.0))
	print("{s.x} {s.y} {s.z}")
	print("{a.gap(b)} {Vec3(3, 0, 4).distance(Vec3(0, 1, 0))}")
	prints """
		4 5 6 1 2 3 32
		(4, 1, 2, 3)
		Vec3(x = 0, y = 0, z = 1)
		8 3 6 2.5
		(3, 2)
		32.25
		100 5050 50
		27 5.0990195
		"""

# one leaf of a result read alone: the unread leaves' registers are no place it goes
fn thirds(a f32):
	Vec3(a, a * 2.0, a * 3.0)

test "a result's leaf read alone is that leaf":
	print(thirds(1.0).z)
	print(thirds(2.0).y)
	prints """
		3
		4
		"""

# past a class's registers the words go on the stack, in order: those before them stay in
# registers, and a small aggregate that does not fit in what is left goes by its address
fn quatSum(a Quat, b Quat) Quat:
	if a.x > 1e9: return b.quatSum(a)
	Quat(a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w)

fn floats(a f64, b f64, c f64, d f64, e f64, f f64, g f64, h f64, k i64) f64:
	if k > 0: return floats(b, c, d, e, f, g, h, a, k - 1)
	a + 2.0 * b + 3.0 * c + 4.0 * d + 5.0 * e + 6.0 * f + 7.0 * g + 8.0 * h

fn ints(a i64, b i64, c i64, d i64, e i64, f i64, x f32, k i64) i64:
	if k > 0: return ints(b, c, d, e, f, a, x * 2.0, k - 1)
	a + 10 * b + 100 * c + 1000 * d + 10_000 * e + 100_000 * f + i64(x)

fn lerped(a Vec3, b Vec3, t f32, s f32) Vec3:
	if t > 1e9: return b.lerped(a, s, t)
	a + (b - a) * t * s

test "arguments past the registers go on the stack":
	print("{quatSum(Quat(1, 2, 3, 4), Quat(10, 20, 30, 40))}")
	print("{floats(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 0)} {floats(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 3)}")
	print("{ints(1, 2, 3, 4, 5, 6, 0.5, 0)} {ints(1, 2, 3, 4, 5, 6, 0.5, 2)}")
	print("{lerped(Vec3(0, 0, 0), Vec3(2, 4, 8), 0.5, 0.5)}")
	prints """
		Quat(x = 11, y = 22, z = 33, w = 44)
		204 144
		654321 216545
		Vec3(x = 0.5, y = 1, z = 2)
		"""
