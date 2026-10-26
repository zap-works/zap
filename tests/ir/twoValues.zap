# Two lambdas made in one function are two values (the optimizer once merged their code
# addresses, which differ only by the function they name).
#
# Two choices on one condition with different values are two values (the optimizer once merged
# them as a common computation): the second is not the first's.

fn pair(n i64):
	add = (x i64): x + n
	mul = (x i64): x * n
	(add(3), mul(3))

test "two lambdas in one function":
	print("{pair(4)}")
	prints "(7, 12)"

fn codes(eq bool):
	cc = 0x95 if eq else 0x94
	init = 0 if eq else 1
	(cc, init)

fn pick(x i64):
	a = 10 if x > 3 else 20
	b = 1 if x > 3 else 2
	c = 10 if x > 3 else 20
	a * 100 + b * 10 + c / 10

test "selects on one condition":
	print("{codes(true)} {codes(false)} {pick(5)} {pick(1)}")
	prints "(149, 0) (148, 1) 1011 2022"
