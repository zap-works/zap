# matMul: the product of two n by n f64 matrices, loops in i, k, j order so each element sums in
# k order and every language prints the same digits.
import problems

fn matrix(n i64):
	scale = 1.0 / n / n
	(0..n * n).map(scale * (it / n - it % n) * (it / n + it % n))   # row x / n, column x % n

fn product(a f64[], b f64[], n i64):
	use fusedMultiplyAdd
	c f64[] = zeros(n * n)
	for i in 0..n:
		for k in 0..n:
			aik = a[i * n + k]
			for j in 0..n:
				c[i * n + j] += aik * b[k * n + j]
	c

n = arg(0, 30)
a = matrix(n)
b = matrix(n)
c = product(a, b, n)
print("{c[n / 2 * n + n / 2]:.9}")
print("{(0..n).sum(c[it * n + it]):.9}")

test "the product of the matrices has the reference's digits":
	main()
	prints """
		-2.633332099
		-149.955419753
		"""

test "the C, Rust and Python programs print the same bytes":
	expect problems.agree("matMul")
