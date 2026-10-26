# Small struct temporaries through inlined methods and operators: a temporary receiver, a
# temporary argument, results written straight into a local, a list element or the value
# they are computed from, inside loops that keep element addresses in registers.
type V3:
	x f32
	y f32
	z f32

	fn dot(o V3):
		x * o.x + y * o.y + z * o.z

	fn cross(o V3):
		V3(x = y * o.z - z * o.y, y = z * o.x - x * o.z, z = x * o.y - y * o.x)

	fn scaled(k f32):
		V3(x = x * k, y = y * k, z = z * k)

	fn sum():
		x + y + z

fn mid(a V3, b V3):
	V3(x = (a.x + b.x) * 0.5, y = (a.y + b.y) * 0.5, z = (a.z + b.z) * 0.5)

fn v(x f32, y f32, z f32):
	V3(x, y, z)

test "temporary receivers and arguments":
	a = v(1.0, 2.0, 3.0)
	b = v(4.0, 5.0, 6.0)
	c = v(1.0, 0.0, 2.0)
	expect a.cross(b) @ c == -9.0
	expect a.scaled(2.0).cross(b.scaled(0.5)).sum() == 0.0
	expect a.scaled(2.0).mid(b).sum() == 13.5
	expect mid(a + b, b - a).sum() == 15.0

test "results into their own operands":
	a = v(1.0, 2.0, 3.0)
	b = v(4.0, 5.0, 6.0)
	a = a.cross(b)
	expect a.x == -3.0 and a.y == 6.0 and a.z == -3.0
	a = b.mid(a)
	expect a.x == 0.5 and a.y == 5.5 and a.z == 1.5
	a += a.scaled(2.0)
	expect a.sum() == 22.5

test "lists in loops":
	pos = []
	vel = []
	for i in 0..10:
		f = f32(i)
		pos.push(v(f, f * 2.0, 1.0))
		vel.push(v(1.0, -1.0, f))
	loop 4:
		for i in 0..pos.len:
			pos[i] += vel[i] * 0.5
	s = 0.0
	for i in 0..pos.len:
		s += pos[i].cross(vel[i]) @ pos[i].scaled(0.5) + pos[i].mid(vel[i]).sum()
	expect pos[3].x == 5.0 and pos[3].y == 4.0 and pos[3].z == 7.0
	expect s == 140.0
	t = 0.0
	for p in pos:
		t += p.scaled(2.0).sum()
	expect t == 470.0
