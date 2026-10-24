# Vectors and matrices: a vector is a list of numbers, a matrix a list of those. The math
# operators on them (+ - * / element by element or by a number, @) compile to these functions,
# one instance per number type. Shape mismatches stop the program.

fn apply<T Num>(x T, y T, op i64) T:
	if op == 43: return x + y
	if op == 45: return x - y
	if op == 42: return x * y
	x / y

fn vecEw<T Num>(a T[], b T[], op i64) T[]:
	n = a.len
	if n != b.len:
		fail("vector shape mismatch")
	r T[] = []
	r.reserve(n)
	for i in 0..n:
		r.push(apply(a[i], b[i], op))
	r

fn vecScalar<T Num>(a T[], s T, op i64) T[]:
	r T[] = []
	r.reserve(a.len)
	for i in 0..a.len:
		r.push(apply(a[i], s, op))
	r

fn vecDot<T Num>(a T[], b T[]) T:
	n = a.len
	if n != b.len or n == 0:
		fail("vector dot shape mismatch")
	s = a[0] * b[0]
	for i in 1..n:
		s += a[i] * b[i]
	s

fn matEw<T Num>(a T[,], b T[,], op i64) T[,]:
	rows = a.len
	if rows != b.len:
		fail("matrix shape mismatch")
	r T[,] = []
	for i in 0..rows:
		r.push(vecEw(a[i], b[i], op))
	r

fn matScalar<T Num>(a T[,], s T, op i64) T[,]:
	r T[,] = []
	for i in 0..a.len:
		r.push(vecScalar(a[i], s, op))
	r

fn matMul<T Num>(a T[,], b T[,]) T[,]:
	rows = a.len
	inner = b.len
	if rows == 0 or inner == 0 or a[0].len != inner:
		fail("matrix multiply shape mismatch")
	cols = b[0].len
	r T[,] = []
	for i in 0..rows:
		row T[] = []
		row.reserve(cols)
		for j in 0..cols:
			s = a[i][0] * b[0][j]
			for k in 1..inner:
				s += a[i][k] * b[k][j]
			row.push(s)
		r.push(row)
	r

fn matVec<T Num>(a T[,], v T[]) T[]:
	rows = a.len
	if rows == 0 or a[0].len != v.len:
		fail("matrix-vector shape mismatch")
	r T[] = []
	r.reserve(rows)
	for i in 0..rows:
		r.push(vecDot(a[i], v))
	r
