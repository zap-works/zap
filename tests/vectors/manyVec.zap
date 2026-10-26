base f64[] = [1.0, 2.0, 3.0, 4.0]
one = base.load4(0)
mut a0 = one
mut a1 = one * Simd<4>(2.0)
mut a2 = one * Simd<4>(3.0)
mut a3 = one * Simd<4>(4.0)
mut a4 = one * Simd<4>(5.0)
mut a5 = one * Simd<4>(6.0)
mut a6 = one * Simd<4>(7.0)
mut a7 = one * Simd<4>(8.0)
mut a8 = one * Simd<4>(9.0)
mut a9 = one * Simd<4>(10.0)
mut a10 = one * Simd<4>(11.0)
mut a11 = one * Simd<4>(12.0)
mut acc = Simd<4>(0.0)
loop 3:
	s = a0.sums4(a1, a2, a3)
	t = a4.sums4(a5, a6, a7)
	acc = acc + s + t
	a0 += one
	a1 += one
	a2 += one
	a3 += one
	a4 += one
	a5 += one
	a6 += one
	a7 += one
	a8 += one
	a9 += one
	a10 += one
	a11 += a0
mut out f64[] = zeros(12)
out.store4(0, acc)
out.store4(4, a11)
out.store4(8, a8 + a9 + a10)
print("{out}")

test "more vectors than registers keep their lanes through a loop":
	main()
	prints """
	    [240, 300, 360, 420, 21, 42, 63, 84, 39, 78, 117, 156]
	    """
