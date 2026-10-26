# a vector assigned from an expression that reads it: the result register is the variable's
# own, so it is written only after every read of the old value
use fusedMultiplyAdd
mut x = Simd<4>(1.0)
b = Simd<4>(2.0)
c = Simd<4>(3.0)
mut y = Simd<4>(1.0)
mut z = Simd<4>(1.0)
xs u8[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
k = xs.load16(0)
mut u = xs.load16(0)
loop 3:
	x = x * b + c   # a factor is the target
	y = (y - b) * (c * c)   # the left side reads the target
	z = c * z + b   # the other factor is the target
	u = (u + k) - (k + k)
print("{x.lane(0)} {y.lane(0)} {z.lane(0)} {u.lane(0)} {u.lane(15)}")

test "a vector assigned from an expression of itself is written after every read":
	main()
	prints """
	    29 -909 53 254 224
	    """
