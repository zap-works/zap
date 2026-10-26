# Register arrays: T[N] is N locals with indices known when compiling. Loops over literal
# ranges that index them are unrolled (with lets of known value and branches decided by
# literals), tables of integer literals read as literals, and an element of an immutable
# array given an immutable local reads that local.
mut acc i64[4] = [0, 0, 0, 0]
for round in 0..3:
	for k in 0..4:
		acc[k] += k * 10 + round
print("{acc[0]} {acc[1]} {acc[2]} {acc[3]}")
squares i64[5]
for i in 0..5:
	squares[i] = i * i
print(squares[4] + squares[3])
pairI i64[6] = [1, 2, 2, 3, 3, 3]
pairJ i64[6] = [0, 0, 1, 0, 1, 2]
pos f64[4] = [0.0, 1.5, 4.0, 10.0]
mut total = 0.0
for k in 0..6:
	i = pairI[k]
	j = pairJ[k]
	d = pos[i] - pos[j]
	total += d * d
print(total)
zero = 0
padded i64[4]
for g in 0..4:
	if g < 3:
		padded[g] = g + 7
	else:
		padded[g] = zero
print("{padded[0]} {padded[2]} {padded[3]}")
mut v Simd<4, f64>[2] = fill(2, Simd<4>(1.0, 2.0, 3.0, 4.0))
loop 3:
	for k in 0..2:
		v[k] = v[k] * 2 + k
print("{v[0].lane(3)} {v[1].lane(0)}")
n = 10
mut evens = 0
for i in 0..n:
	evens += 1 if i % 2 == 0 else 0
print(evens)

test "a register array's elements are locals its unrolled loops index":
	main()
	prints """
	    3 33 63 93
	    25
	    232.75
	    7 9 0
	    32 15
	    5
	    """

fn shadowedByLoop(rows i64[, 3]):
	a i64[3]
	a[0] = 1
	a[1] = 2
	a[2] = 3
	s = 0
	for a in rows:
		s += a[0] * 100
	s + a[0] + a[1] + a[2]

fn shadowedByArm(o (i64[3])?):
	a i64[3]
	a[0] = 1
	r = match o:
		a: a[0] * 1000
		none: 0
	r + a[0]

fn shadowedByLambda():
	a i64[3]
	a[0] = 1
	f = (a i64[3]): a[0] * 10
	f([7, 8, 9]) + a[0]

test "a loop variable, a pattern or a lambda's parameter named like a register array is its own":
	expect shadowedByLoop([[5, 0, 0], [6, 0, 0]]) == 1106
	expect shadowedByArm([9, 9, 9]) == 9001
	expect shadowedByLambda() == 71
