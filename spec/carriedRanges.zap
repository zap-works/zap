# 3.1.1 Ranges carried and proven
#
# Arithmetic, min, max, clamp and conversions carry their
# operands' ranges into their types; a for's variable lies in its range; a check just made proves
# an immutable variable inside (in the if's block, its else, after an if that leaves, and in the
# arms of an if value: `0 if x < 0 else x` reads x as never negative after else); a derived
# decoder checks a range; an unsigned value only compared, indexed with or converted is a quantity:
# a parameter, a local, or a struct's field that every read in the program reads so (a struct laid
# out for the system, `extern type`, holds bits).

type Percent = i64 in 0..=100

# a check just made proves the value inside: before the end, x lies in 0..=100
fn percentOf(x i64) Percent:
	if x < 0: return 0
	if x > 100: return 100
	x

# the same as one if value: each arm knows what its condition left
fn percentIn(x i64) Percent:
	0 if x < 0 else 100 if x > 100 else x

test "arithmetic carries ranges, a loop's variable and a check just made prove them":
	p Percent = 40
	q Percent = 90
	half Percent = p / 2   # 0..=50 lies inside 0..=100
	low i64 in 0..=15 = (p + q) % 16
	mixed i64 in -100..=100 = p - q
	most i64 in 0..=100 = p.clamp(q, 100)
	sum = 0
	for i in 0..101:
		r Percent = i   # i lies in 0..=100
		sum += r
	x = args.len + 60
	if x >= 0 and x <= 100:
		r Percent = x
		print(r)
	print("{half} {low} {mixed} {most} {sum}")
	expect percentOf == {-5: 0, 250: 100, x: 60}
	expect percentIn == {-5: 0, 250: 100, x: 60}
	prints """
		60
		20 2 -50 90 5050
		"""

type Score:
	name str
	points Percent

test "a conversion keeps its operand's range, and a derived decoder checks a range":
	b u8 = 200
	wide = i64(b) * 4   # 0..=1020: no overflow check
	low i64 in 0..=1020 = wide
	print("{low} {Score.fromJson("\{\"name\": \"a\", \"points\": 70}")?.points} {Score.fromJson("\{\"name\": \"a\", \"points\": 170}") == none}")
	prints """
		800 some(70) true
		"""

test "an unsigned value only compared and indexed with is a quantity" refuses UnsignedQuantity:
	fn show(n u32, xs i64[]):
		if n < xs.len:
			print(xs[n])
	show(1, [1, 2])

test "a quantity is said in a body checked first for a caller that needs its result" refuses UnsignedQuantity:
	fn twice() i64:
		count([1]) * 2
	fn count(xs u8[]):
		w u16 = 3
		if w > 1:
			return xs.len
		0
	print(twice())

test "a check made on a mut binding proves nothing" refuses InitializerType:
	type Percent = i64 in 0..=100
	mut x = args.len
	if x < 100:
		p Percent = x
		print(p)

# the same proofs under `use noStops`: a loop's variable lies below its end, a check just made
# bounds a value, and arithmetic carries both
fn lastCount(n i64):
	use noStops
	last = 0
	for i in 0..n:
		last = i + 1
	last

fn picked(t u8[8], i i64):
	use noStops
	if i < 0 or i >= 8: return 0
	i64(t[i]) + i64(t[(i + 3) % 8])

test "a loop's variable and a check just made prove arithmetic and indexes under noStops":
	t u8[8] = [1, 2, 3, 4, 5, 6, 7, 8]
	expect lastCount(5) == 5
	expect picked == {(t, 6): 9, (t, 9): 0}
