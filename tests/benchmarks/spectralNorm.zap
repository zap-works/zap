# spectral-norm: the largest eigenvalue of the infinite matrix A(i,j) = 1/((i+j)(i+j+1)/2+i+1) by
# the power method, for n a multiple of 4. Every task computes four rows of a product four columns
# at a time (Simd<4, f64>); the denominators are exact in f64, and the next row's is the previous
# one plus i+j+2, i+j+3, i+j+4 (one less for the transposed: t is 1.0 for it, else 0.0).
import problems

fn rows4(i i64, v f64[], t f64):
	iv = Simd<4>(f64(i))
	jv = Simd<4>(0.0, 1.0, 2.0, 3.0)
	s Simd<4, f64>[4]
	for j in 0..v.len step 4:
		ipj = iv + jv
		d = ipj * (ipj + 1.0) * 0.5 + 1.0 + iv + (jv - iv) * t
		inc = ipj + (2.0 - t)
		vj = v.load4(j)
		for r in 0..4:
			s[r] += 1.0 / d * vj
			d += inc + r
		jv += 4.0
	s[0].sums4(s[1], s[2], s[3])

fn timesA(v f64[], t f64):
	rows = (0..v.len / 4).parallel().map(q: rows4(q * 4, v, t))
	out f64[] = zeros(v.len)
	for q, row in rows:
		out.store4(q * 4, row)
	out

n = arg(0, 100)
mut u = fill(n, 1.0)
mut v = []
loop 10:
	v = timesA(timesA(u, 0.0), 1.0)
	u = timesA(timesA(v, 0.0), 1.0)
vBv = (0..n).reduce(0.0, (acc, i): acc + u[i] * v[i])
vv = (0..n).reduce(0.0, (acc, i): acc + v[i] * v[i])
print("{(vBv / vv).sqrt():.9}")

test "the power method gives the spectral norm to nine digits":
	main()
	prints """
	    1.274219991
	    """

test "the C, Rust and Python programs print the same bytes":
	expect problems.agree("spectralNorm")
