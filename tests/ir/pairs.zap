# The f64 fields of structs in a loop: two lanes made by one operation (irPairs.zap), a load read
# by the operation that uses it (irFoldedUse), each lane what the scalar code computes, exactly.
type V3:
	x f64
	y f64
	z f64

	fn dot(b V3):
		x * b.x + y * b.y + z * b.z

type Ball:
	center V3
	radius f64

fn balls():
	[
		Ball(center = V3(1.5, -2.25, 3.0), radius = 0.5),
		Ball(center = V3(0.0, -0.0, 7.0), radius = 2.0),
		Ball(center = V3(-3.0, 4.0, 1e-300), radius = 1e300),
		Ball(center = V3(0.1, 0.2, 0.3), radius = 0.7)
	]

# what hit computes in raytrace: the eye's zeros less a center, dotted
fn reach(eye V3, dir V3):
	out = []
	for b in balls():
		oc = eye - b.center
		r = oc @ dir
		out.push(r * r - (oc @ oc - b.radius * b.radius))
	out

test "a vector less each center, its dot products":
	print(reach(V3(0.0, 0.0, 0.0), V3(0.6, 0.0, 0.8)))
	print(reach(V3(0.25, -0.5, 1.0), V3(-1.0, 2.0, 0.5)))
	prints """
		[-5.172499999999998, -13.639999999999993, Infinity, 0.43999999999999995]
		[5.6875, -14.25, Infinity, 0.9274999999999993]
		"""

test "zeros less each center: the zeros' signs kept":
	out = []
	for b in balls():
		oc = V3(0.0, 0.0, 0.0) - b.center
		sq = oc * oc - oc
		out.push(1.0 / oc.x)
		out.push(1.0 / oc.y)
		out.push(sq.x + sq.y)
	print(out)
	prints "[-0.6666666666666666, 0.4444444444444444, 6.5625, Infinity, Infinity, 0, 0.3333333333333333, -0.25, 26, -10, -5, 0.35000000000000003]"

test "lanes scaled by a constant, less a vector, by a value that changes, divided":
	from = V3(0.25, -0.5, 1.0)
	k = 0.5
	out = []
	for b in balls():
		s = (b.center * 2.5 - from) * k
		u = V3(s.x / k, s.y / k, 0.0)
		w = V3(2.0 * u.x, 2.0 * u.y, 0.0)
		out.push(w.x)
		out.push(1.0 / w.y)   # a zero's sign
		k *= -3.0
	print(out)
	prints "[7, -0.0975609756097561, -0.5, 1, -15.5, 0.047619047619047616, 0, 0.5]"

test "lanes read in another order, squared, stored and compared":
	xs = []
	far = 0
	for b in balls():
		y = b.center.y
		x = b.center.x
		d = V3(x - 1.0, y - 1.0, 0.0)
		e = V3(d.x * d.x, d.y * d.y, 0.0)
		f = V3(e.x + 0.5, e.y + 0.5, 0.0)
		xs.push(f.y)
		if f.y > f.x: far += 1
	print("{xs} {far}")
	prints "[11.0625, 1.5, 9.5, 1.1400000000000001] 1"

test "a store between two loads keeps them apart":
	bs = balls()
	out = []
	for mut b in bs:
		x = b.center.x
		b.center.y = x * 4.0
		y = b.center.y
		out.push((x - 1.0) * (y - 1.0))
	expect out == [2.5, 1, 52, 0.54]
