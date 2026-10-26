# two turns of a loop nest at once (irJam.zap): the rows of c two at a time, each element's sum in
# the order written; the guard runs the nest as written when an index could leave its list
fn product(a f64[], b f64[], n i64):
	c f64[] = zeros(n * n)
	for i in 0..n:
		for k in 0..n:
			aik = a[i * n + k]
			for j in 0..n:
				c[i * n + j] += aik * b[k * n + j]
	c

# the same sums in a local each: nothing jammed
fn bySums(a f64[], b f64[], n i64):
	c f64[] = zeros(n * n)
	for i in 0..n:
		for j in 0..n:
			t = 0.0
			for k in 0..n:
				t += a[i * n + k] * b[k * n + j]
			c[i * n + j] = t
	c

# an element the bounds of the counters would take past the end, read only when it is inside:
# the guard runs the nest as written
fn shifted(a f64[], n i64):
	c f64[] = zeros(n * n)
	for i in 0..n:
		for k in 0..n:
			x = a[i * n + k + 1] if i * n + k + 1 < n * n else 0.5
			for j in 0..n:
				c[i * n + j] += x * j
	c

fn shiftedBySums(a f64[], n i64):
	c f64[] = zeros(n * n)
	for i in 0..n:
		for j in 0..n:
			t = 0.0
			for k in 0..n:
				t += (a[i * n + k + 1] if i * n + k + 1 < n * n else 0.5) * j
			c[i * n + j] = t
	c

fn matrix(n i64, seed i64):
	(0..n * n).map(((it * 7 + seed) % 11) * 0.37 - 1.3)

for n in [1, 2, 3, 6, 9, 17]:
	a = matrix(n, 3)
	b = matrix(n, 5)
	print("{n} {product(a, b, n) == bySums(a, b, n)} {shifted(a, n) == shiftedBySums(a, n)}")

test "two turns of a loop nest at once sum each element in the order written":
	main()
	prints """
		1 true true
		2 true true
		3 true true
		6 true true
		9 true true
		17 true true
		"""

test "a list too short for the last row stops the nest as written" stops IndexOutOfBounds:
	n = 5 + args.len
	a f64[] = (0..n * n - 1).map(f64(it))
	c f64[] = zeros(n * n)
	for i in 0..n:
		for k in 0..n:
			x = a[i * n + k]
			for j in 0..n:
				c[i * n + j] = c[i * n + j] + x
	print(c[0])
