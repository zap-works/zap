# Methods on small structs of f64s are emitted in place: their parameters name the caller's
# locals, their f64 lets and immutable struct lets live in registers. The same sums written
# with plain f64s must give the same bits.

type V3:
	x f64
	y f64
	z f64

	fn dot(b V3):
		x * b.x + y * b.y + z * b.z

	fn len():
		dot(self).sqrt()

type Ball:
	center V3
	radius f64

	fn hit(origin V3, dir V3):
		oc = origin - center
		b = oc @ dir
		disc = b * b - (oc @ oc - radius * radius)
		if disc < 0.0: return -1.0
		-b - disc.sqrt()

# hit, with every value a plain f64
fn hitByHand(cx f64, cy f64, cz f64, r f64, ox f64, oy f64, oz f64, dx f64, dy f64, dz f64):
	px = ox - cx
	py = oy - cy
	pz = oz - cz
	b = px * dx + py * dy + pz * dz
	disc = b * b - ((px * px + py * py + pz * pz) - r * r)
	if disc < 0.0: return -1.0
	-b - disc.sqrt()

test "inlined struct methods give the bits of plain f64 code":
	balls = []
	for i in 0..20:
		f = f64(i)
		balls.push(Ball(center = V3(f * 0.7 - 5.0, 3.0 - f * 0.3, 8.0 + f), radius = 0.5 + f * 0.1))
	eye = V3(0.0, 0.0, 0.0)
	same = true
	misses = 0
	for k in 0..200:
		u = k / 100.0 - 1.0
		dir = V3(u, 0.5 - u * 0.25, 1.5)
		for ball in balls:
			t = ball.hit(eye, dir)
			c = ball.center
			byHand = hitByHand(c.x, c.y, c.z, ball.radius, eye.x, eye.y, eye.z, dir.x, dir.y, dir.z)
			if t.toBits() != byHand.toBits():
				same = false
		if dir.len <= 0.0:
			misses += 1
	expect same
	expect misses == 0
