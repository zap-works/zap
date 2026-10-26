# an inlined method whose parameter has the name of the receiver: the receiver is still the
# caller's (a lambda's parameter, a local, a loop's element)
type V:
	x f64
	y f64

	fn hit(o V):
		x - o.x

xs = [V(x = 10.0, y = 0.0)]
from = V(x = 1.0, y = 0.5)
print(xs.map(.hit(from)))
o = V(x = 5.0, y = 0.0)
print(o.hit(from))
for o in xs:
	print(o.hit(from))

test "receiver named like a parameter":
	main()
	prints """
		[9]
		4
		9
		"""
