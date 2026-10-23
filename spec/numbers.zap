# 3.1 Primitive types and numbers
#
# `i8 i16 i32 i64 u8 u16 u32 u64 n32 n64 f32 f64 bool str ()`. User types are PascalCase.
#
# Two roles, never mixed: `u8`..`u64` are bits, their arithmetic modulo 2^n on purpose (a hash, a
# mask, a checksum, a file's bytes); signed integers, naturals and ranges are quantities, which
# never wrap: a sum, difference, product, negation, `abs()`, `**` or `sum()` that leaves the type
# stops the program (`integer-overflow`, 6.6). The check is a jump after the operation, left out
# where the operands' widths prove the result inside.

fn nothing() ():
	print("nothing")

test "the primitive types":
	nothing()
	a i8 = 1
	b i16 = 2
	c i32 = 3
	d = 4
	e u8 = 5
	f u16 = 6
	g u32 = 7
	h u64 = 8
	i n32 = 9
	j n64 = 10
	k f32 = 1.5
	l = 2.5
	m = true
	n = "s"
	print("{a} {b} {c} {d} {e} {f} {g} {h} {i} {j} {k} {l} {m} {n}")
	prints """
		nothing
		1 2 3 4 5 6 7 8 9 10 1.5 2.5 true s
		"""

test "a type's name is PascalCase" refuses Expected:
	type point:
		x i64
	print(point(x = 1).x)

test "unsigned integers wrap":
	c u8 = 250
	c += 10
	h u64 = 14_695_981_039_346_656_037
	for byte in [104, 105]:
		h = (h ^ u64(byte)) * 1_099_511_628_211
	w u64 = 3
	print("{c} {h} {h >> 60} {w ** 40}")
	prints "4 628919584683901914 0 12157665459056928801"

test "an i64 sum past its largest value" stops IntegerOverflow:
	b i64 = 9_223_372_036_854_775_807
	b += (args.len + 1)
	print(b)

test "an i32 sum past its largest value" stops IntegerOverflow:
	a i32 = 2_147_483_647
	print(a + i32((args.len + 1)))

test "an i64 negation of its smallest value" stops IntegerOverflow:
	d i64 = -9_223_372_036_854_775_807 - (args.len + 1)
	print(-d)

test "the smallest value's abs" stops IntegerOverflow:
	d i64 = -9_223_372_036_854_775_807 - (args.len + 1)
	print(d.abs())

test "the smallest value divided by -1" stops IntegerOverflow:
	d i64 = -9_223_372_036_854_775_807 - (args.len + 1)
	print(d / -(args.len + 1))

test "a power past the type" stops IntegerOverflow:
	print(3 ** (39 + (args.len + 1)))

test "a sum of a list past the type" stops IntegerOverflow:
	print([9_223_372_036_854_775_807, (args.len + 1)].sum())

test "a constant sum past the type stops when it runs" stops IntegerOverflow:
	print(9_223_372_036_854_775_807 + 1)

# `MIN % -1` is 0. Division truncates toward zero, `%` takes the sign of the dividend, and `x ** n`
# with a negative `n` is 0. Shifts and `& | ^ ~` are bits and never stop; division by zero and a
# shift by a negative or too large count do.

test "what stays inside its type":
	n = (args.len + 1) - 1
	d = -9_223_372_036_854_775_807 - 1 + n
	print("{d} {d % -1} {d % (n - 1)}")
	a i32 = -2_147_483_647
	print("{a - i32((args.len + 1))} {-a + i32(n)} {i16(-32_768 + n)} {i8(127 + n)}")
	print("{7 / -2} {-7 / 2} {-7 % 2} {7 % -2} {2 ** -1}")
	print("{1 << 3} {-1 >> 1} {~0} {5 & 3} {5 | 3} {5 ^ 3} {d & 1}")
	prints """
		-9223372036854775808 0 0
		-2147483648 2147483647 -32768 127
		-3 -3 -1 1 0
		8 -1 -1 1 7 6 0
		"""

test "an i32's sum, difference and product, negative or at its ends":
	n = i32(args.len)
	print(
		"{n - 5 + 3} {n - 5 - 3} {(n - 5) * 3} {2_147_483_646 + (n + 1)} {-2_147_483_647 - (n + 1)}"
	)
	prints "-2 -8 -15 2147483647 -2147483648"

test "an i32's division and remainder, by -1 too":
	n = i32(args.len)
	lo = i32(-2_147_483_647) - 1 + n
	expect (-7 + n) / 2 == -3
	expect (7 + n) / -2 == -3
	expect (-7 + n) % 2 == -1
	expect (7 + n) % -2 == 1
	expect (5 + n) / -1 == -5
	expect lo % -1 == 0
	expect lo / 7 == -306_783_378

test "division by zero" stops DivisionByZero:
	print(5 / args.len)

test "a shift past the width" stops ShiftOutOfRange:
	print(1 << (args.len + 70))

# `T in a..b` (`..=` and an open end `a..` too) is the integer type `T` whose values lie in the
# range, stored as `T`. The naturals `n32` and `n64` are `i32 in 0..` and `i64 in 0..`, written so.
# A bound is an integer literal or a constant. A range's value goes wherever its base goes; a value
# goes into a range when the compiler proves it inside (a literal, a range inside it), else through
# the range's checked conversion, its name called (`Percent(x)`, `n64(i)`).

type Percent = i64 in 0..=100
type Digit = u8 in 0..=9
type Positive = i64 in 1..

type Hero:
	name str
	hp i64 in 0..=500

fn half(p Percent) Percent:
	Percent(p / 2)

# `+ * / %` of naturals (or of a natural and a literal not negative) give a natural, so
# `count += 1` keeps an `n64`; a difference of naturals is a plain integer
fn odd(n n64) n64:
	n * 2 + 1

fn pair(m n32) (n64, i64):
	(m + n64(1), m - 7)

test "a range type's arithmetic and conversions stay within its range":
	p Percent = 40
	q = half(p)
	print("{p} {q} {p + q}")
	k n64 = 3
	k += 4
	k *= 2
	print("{k} {odd(k)}")
	h = Hero(name = "a", hp = 120)
	d Digit = 7
	one Positive = 1
	print("{h.hp} {d} {Positive(args.len + 3)} {one}")
	x = args.len + 51
	m n32 = 5
	print("{Percent(x)} {n64(i64(m) - 3)}")
	z = m   # a mut binding holds the range's base
	z -= 9
	print("{pair(m)} {z}")
	print([p, q])
	prints """
		40 20 60
		14 29
		120 7 3 1
		51 2
		(6, -2) -4
		[40, 20]
		"""

test "a literal outside the range" refuses LiteralOutsideRange:
	type Percent = i64 in 0..=100
	p Percent = 150
	print(p)

test "an integer into a range asks for the conversion" refuses InitializerType:
	type Percent = i64 in 0..=100
	x = args.len
	q Percent = x
	print(q)

test "a natural's difference is no natural" refuses AssignType:
	mut k n64 = 3
	k -= 1
	print(k)

# A natural, or an unsigned integer, compared with 0 as if it could be below it (`n < 0`, `n >= 0`)
# decides nothing: an error (a "none" that was a value below 0 is an optional, `n64?`).

test "a natural is never below 0" refuses ComparisonDecided:
	fn found(at n64) bool:
		at >= 0

	print(found(3))

# An optional of a range keeps none in a value its range leaves unused: `n32?` is 4 bytes, -1
# for none, and `(u8 in 0..=9)?` one byte, 10 for none; written, read, matched and compared as any
# optional.

type Tree:
	left n32?
	right n32?

fn leaves(t Tree[], at n32) i64:
	n = t[at]
	match n.left:
		l: leaves(t, l) + leaves(t, n.right ?? l)
		none: 1

fn firstOdd(xs n64[]) n64?:
	for x in xs:
		if x % 2 == 1: return x
	none

test "an optional of a range is its range's word":
	xs n32?[] = [none, n32(3)]
	xs.push(none)
	xs.push(n32(7))
	print("{xs} {xs.rawBytes().len} {xs.rawBytes()[0..4]}")
	ds Digit?[] = [none, Digit(4)]
	print("{ds} {ds.rawBytes()}")
	prints """
		[none, some(3), none, some(7)] 16 [255, 255, 255, 255]
		[none, some(4)] [10, 4]
		"""

test "a tree of natural indexes, none for a leaf":
	t = [
		Tree(left = n32(1), right = n32(2)),
		Tree(left = none, right = none),
		Tree(left = none, right = none)
	]
	print("{leaves(t, 0)} {t.rawBytes().len}")
	prints """
		2 24
		"""

test "try, fallback, presence and a pattern on an optional of a range":
	print("{firstOdd([n64(4), n64(9)]) ?? 0} {firstOdd([n64(2)]) == none} {firstOdd([]) ?? 5}")
	ys n32?[] = [none, n32(3), none, n32(7)]
	ys[0] = n32(0)
	ys.sortBy(it ?? n32(100))
	print("{ys} {ys.pop()} {none in ys} {ys.filter(it != none).len}")
	prints """
		9 true 5
		[some(0), some(3), some(7), none] some(none) false 3
		"""

test "a conversion outside the range stops the program" stops IntegerOverflow:
	type Percent = i64 in 0..=100
	print(Percent(args.len + 101))

test "a negative value is no natural" stops IntegerOverflow:
	print(n64(-1 - args.len))

test "a sum of naturals past the type stops the program" stops IntegerOverflow:
	big n64 = 9_223_372_036_854_775_807
	print(big + n64(args.len + 1))

# Widening is implicit where nothing is lost, in bindings, assignments, arguments, a struct's
# fields, pushes, returns, arithmetic and comparisons: an integer becomes a wider integer of the same signedness or a wider
# signed one (a `u32` an `i64`, which holds every `u32`), any integer next to an `f64` an `f64`,
# and one of 16 bits or fewer (`u8`, `i8`, `u16`, `i16`) next to an `f32` an `f32`, which holds
# each exactly. `& | ^` widen the same way, and a shift count may be any integer. Narrowing and sign
# changes to a type that does not hold every value (`i64` to `u64`, `u32` to `i32`) are written,
# `u8(x)`, unless the compiler proves the value inside the type (3.1.1) where it lands: a typed
# binding, an assignment, an argument, a return, a field or an element. A literal, `x % c`,
# `x & mask`, `x >> s`, a range type, a loop's variable over a range of constants, and sums and
# products of those are proven: `1 + r % 9` of a `u64` is a `u8` there. An operand is never
# narrowed (`small + r % 9` is computed in the wider type), nor a float (`f32(x)` loses
# precision); the rest needs `T(x)`, and the error says so. zap fmt drops a conversion the
# compiler proves, and a widening one where the place (an index, a shift count, an argument, a
# typed binding, a return, an operand beside its own type or a wider one) gives the same type.

fn halved(x f64):
	x / 2.0

fn wider(n i32) i64:
	n

test "widening where nothing is lost":
	i i32 = 7
	print("{i * 0.5} {halved(i)} {wider(i) + 1}")
	total = 0
	total += i
	w i64 = i
	print("{total} {w == i} {i < 7.5} {i * 2.0 == i * 2.0}")
	y f32 = 7
	print("{halved(3)} {y / 2.0}")
	bytes u8[] = [2, 1]
	wide u32 = 256
	print("{bytes[0] | wide} {wide | bytes[0]} {bytes[0] ^ u32(bytes[1])} {wide >> bytes[1]}")
	count i64 = wide
	print("{wider(bytes[0]) + count} {count - 300}")
	shade f32 = bytes[0]
	tint = Vec3(bytes[0], bytes[1], 0.5)
	print("{shade * y} {bytes[1] + shade} {tint.x + tint.y}")
	prints """
		3.5 3.5 8
		7 true true true
		1.5 3.5
		258 258 3 128
		258 -44
		14 3 3
		"""

fn die(r u64) u8:
	1 + r % 6

type Pixel:
	shade u8
	low i8

test "narrowing where the value is proven inside":
	r = u64(args.len) * 1_000_003 + 7
	n = args.len + 300
	bytes u8[] = [r % 256, n & 15]
	bytes[0] = r >> 60
	bytes.push(n % 7 + n % 3)
	for i in 0..4:
		bytes.push(i * 50)
	p = Pixel(n & 255, n >> 60)
	print("{die(r)} {bytes} {p.shade} {p.low}")
	prints """
		2 [0, 12, 6, 0, 50, 100, 150] 44 0
		"""

test "narrowing is written" refuses InitializerType:
	a = args.len
	b i32 = a
	print(b)

test "an operand is never narrowed" refuses ReturnMismatch:
	fn roll(small u8, r u64) u8:
		small + r % 9

	print(roll(1, 2))

# A conversion is written with the type's name: `i8(x)`..`i64(x)`, `u8(x)`..`u64(x)`, `f32(x)`,
# `f64(x)`. Integer to integer keeps the value: one that does not fit the narrower type stops the
# program, and a sign change to the same width or a wider one keeps the bits. `T.wrap(x)` wraps an
# integer to `T` where the wrap is meant; float to integer truncates toward zero and saturates
# (NaN is 0).

# a reader's function: a call of no value is no conversion
fn u16():
	7

test "a conversion is written with the type's name":
	big = 300
	print("{u8.wrap(big)} {i8.wrap(200)} {u16.wrap(-1)} {i32.wrap(9_223_372_036_854_775_807)}")
	print("{u64(-1)} {i64(u64.wrap(-1))} {i64.wrap(u64(-1))}")
	print("{i64(3.9)} {i32(-3.9)} {i32(1e20)} {i64(0.0 / 0.0)}")
	i i32 = 7
	x = 0.1
	print("{f32(i) * 0.5} {f64(f32(x)) == x} {f64(f32(x))}")
	print("{[1, 2, 3].map(it / 2.0)} {[1, 2, 3, 4].map(u8(it)).sum(b: i64(b))} {u16()}")
	n = args.len
	print("{u8(255 + n)} {i8(-128 + n)} {u32(4_294_967_295 + n)}")
	prints """
		44 -56 65535 -1
		18446744073709551615 -1 -1
		3 -3 2147483647 0
		3.5 false 0.10000000149011612
		[0.5, 1, 1.5] 10 7
		255 -128 4294967295
		"""

test "a conversion that loses the value" stops IntegerOverflow:
	big i64 = 299 + (args.len + 1)
	print(u8(big))

# A conversion to the type the value already has is an error, and so is one there and back only to
# call a method the type has (an `f32`'s method only the `f64` has is computed in `f64` and rounded
# once); a conversion the method needs stays.

test "a conversion to the type the value has" refuses NeedlessConversion:
	x = 1.5
	print(f64(x))

test "a conversion there and back for a method the type has" refuses ConversionRoundTrip:
	x f32 = 2.0
	print(f32(f64(x).sqrt()))

test "a conversion the method needs stays":
	n = 9
	x f32 = 2.0
	y = 0.5
	expect i64(f64(n).sqrt()) == 3
	expect f32(f64(x).pow(y)) == 1.4142135
	expect x.sqrt() == 1.4142135
	expect x.pow(2.0) == 4

# Parsing is not a conversion: `T.parse(s)` of a number type is a `T?`, since bad text is no bug:
# an optional sign and decimal digits (`.` and an exponent for floats; `0x` and hexadecimal digits
# for integers), nothing else, in the type's range. A value's text is `str(x)` (7.5).

parses = [
	("42", "some(42)", "some(42)"),
	("-7", "some(-7)", "none"),
	("+5", "some(5)", "some(5)"),
	("0xff", "some(255)", "some(255)"),
	("300", "some(300)", "none"),
	("4x2", "none", "none"),
	("4_2", "none", "none"),
	("2147483648", "some(2147483648)", "none"),
	(" 1", "none", "none"),
	("", "none", "none")
]

test "parse a number" for (text, asI64, asU8) in parses:
	expect str(i64.parse(text)) == asI64
	expect str(u8.parse(text)) == asU8

test "parse a float":
	expect f64.parse == {
		"3.5": 3.5,
		"-1e3": -1000.0,
		"1.5x": none,
		".5": 0.5,
		"5.": 5.0,
		"inf": none,
		"nan": none,
		"": none
	}
	expect f32.parse("2.5e-1") == 0.25

test "i64.parse reads decimal, and hexadecimal after 0x":
	expect (i64.parse("0x11C58") ?? -1) == 72_792
	expect (i64.parse("-0xff") ?? -1) == -255
	expect (i64.parse("0x7FFFFFFFFFFFFFFF") ?? -1) == 9_223_372_036_854_775_807
	expect (i64.parse("-0x8000000000000000") ?? -1) == -9_223_372_036_854_775_808
	expect i64.parse == {"0x": none, "0x8000000000000000": none, "0xg1": none, "0x1 ": none}
	expect (i32.parse("0x0C") ?? -1) == 12
	expect i32.parse == {"2147483648": none, "-0": 0}

# A number constant without a written type is its literal: at the top level, or an immutable local
# bound to numbers alone (a choice whose condition cannot change, an element of a list of numbers
# included), it takes the type its place asks for (a float's only a float type: beside an integer
# it stays a float), and one that does not fit is an error there. A constant with a written type
# keeps it.

fn halfF32(x f32):
	x / 2.0

fn twice(v f32):
	v * 2.0

test "a local of numbers alone takes the type of its use":
	t f32 = 0.5
	steps = 2400.0
	limit = 3 * 1000
	n u32 = 7
	low = -(1 + 1)
	small i8 = 0
	print("{t * steps} {steps} {n + limit} {halfF32(steps)} {small + low}")
	flag = args.len > 5
	a = 1.5
	b = 24.0 if flag else 17.0
	print("{twice(a)} {twice(b)} {twice(1.0 if flag else 0.45)}")
	x f32 = 0.3
	c = [0.34, 0.42][args.len]
	print(x < c)
	prints """
		1200 2400 3007 1200 -2
		3 34 0.9
		true
		"""

fn spaced(n i64, xs str[]):
	gap = 2.0
	h = 12.0 if n == 1 else 7.0
	out = []
	for j, x in xs:
		out.push("{x} {j * (h + gap):.1}")
	out.join(",")

test "a local of float numbers stays a float where it meets an integer":
	print(spaced(1, ["a", "b"]))
	prints "a 0.0,b 14.0"

test "a constant that does not fit its use" refuses LiteralDoesNotFit:
	k = 300
	x u8 = k
	print(x)

test "a constant with a written type keeps it" refuses InitializerType:
	limit u32 = 4096
	y u16 = limit
	print(y)

# Float bindings follow `f32`: a `mut` binding of float literals alone, and any binding of a choice
# between such numbers, is an `f64` until it meets an `f32` (mixed, compared, passed, stored or
# pushed where one is wanted): then it is an `f32` from the start. A tree of `f32` operations is
# computed in single precision.

type Point32:
	x f32

test "a float binding meeting an f32 is one":
	x f32 = 0.3
	m = 0.5
	m *= x
	v f32 = 0.3
	vein = 0.9 if v < 0.5 else 1.0
	acc = 0.0
	acc += v * vein
	p = Point32(x = vein)
	xs f32[] = []
	xs.push(vein)
	print("{m} {twice(vein) * 0.5 * 2.0 + acc + p.x + xs[0]}")
	big f32 = 16_777_216.0
	print(big + 1.0)
	prints """
		0.15 3.87
		16777216
		"""

test "a mut float meeting an f64 stays an f64":
	m = 0.5
	y = 0.5
	m *= y
	expect m == 0.25

# Floats are exact unless asked: each operation is rounded on its own, as written. The option
# `use fusedMultiplyAdd` (2.6) rounds each `a * b + c`, `c + a * b`, `a * b - c` and `c - a * b` in
# its scope once, in `f64`, `f32` and `Simd<4, f64>` (tests/vectors/fma.zap), lambdas included. The
# rule reads the source, so every way the code is compiled agrees: a product given a name stays
# rounded, and a sum of two products, or one whose operands call a function, is never fused.
# `x += a * b` is `x = x + a * b`. Under it a vectorized loop's sum `s += x` (14.3) also keeps one
# sum per lane, added to `s` at the loop's end: its additions run in another order.

fn plain(a f64):
	a * 10.0 - 1.0

fn fused(a f64):
	use fusedMultiplyAdd
	a * 10.0 - 1.0

fn fusedFromLeft(a f64):
	use fusedMultiplyAdd
	1.0 - a * 10.0

fn fusedAdded(a f64):
	use fusedMultiplyAdd
	x = -1.0
	x += a * 10.0
	x

fn named(a f64):
	use fusedMultiplyAdd
	p = a * 10.0
	p - 1.0

fn twoProducts(a f64):
	use fusedMultiplyAdd
	a * 10.0 - a * 10.0

fn ten():
	10.0

fn called(a f64):
	use fusedMultiplyAdd
	a * ten() - 1.0

fn fusedF32(a f32):
	use fusedMultiplyAdd
	a * 10.0 - 1.0

fn plainF32(a f32):
	a * 10.0 - 1.0

fn lambdas():
	use fusedMultiplyAdd
	[0.1, 0.2].map(it * 10.0 - 1.0)

test "a multiply-add rounds once only where asked":
	expect plain(0.1).toBits() == 0
	expect fused(0.1).toBits() == 4_363_988_038_922_010_624
	expect fusedFromLeft(0.1) == -fused(0.1)
	expect fusedAdded(0.1) == fused(0.1)
	expect named(0.1).toBits() == 0
	expect twoProducts(0.1).toBits() == 0
	expect called(0.1).toBits() == 0
	expect plainF32(0.1).toBits() == 0
	expect fusedF32(0.1) != 0.0
	expect lambdas()[0] == fused(0.1)
	expect lambdas()[1] == fused(0.2)

test "a multiply-add is written as it reads" refuses MultiplyAdd:
	print(0.1.mulAdd(10.0, -1.0))

# Floats print with the shortest digits that round-trip, an exponent outside [1e-7, 1e21), and as
# `NaN`, `Infinity`, `-Infinity`.

test "floats print their shortest round trip":
	print("{0.1 + 0.2} {100000000.0} {1e21} {-0.0} {0.0 / 0.0} {1.0 / 0.0} {-1.0 / 0.0}")
	expect 0.000001 == 0.000001
	expect 0.0000001 == 1e-7
	expect 5e-324 == 5e-324
	expect f32(0.1) == 0.1
	expect f64(f32(0.1)) == 0.10000000149011612
	prints """
		0.30000000000000004 100000000 1e+21 0 NaN Infinity -Infinity
		"""

# The methods of numbers. An `f32`'s method is computed in `f64` and rounded once, by the one
# implementation of each function; the operators are single precision.

test "methods on any number":
	print("{(-3).abs()} {3.min(5)} {3.max(5)} {12.clamp(0, 10)} {(-1.5).abs()} {(-1).max(1)}")
	a u8 = 200
	b u8 = 100
	print("{a.max(b)} {a.min(b)}")
	prints """
		3 3 5 10 1.5 1
		200 100
		"""

test "methods on floats, in radians":
	print(
		"{2.5.floor()} {2.5.ceil()} {(-2.7).trunc()} {(-2.5).round()} {9.0.sqrt()} {2.0.pow(10.0)}"
	)
	print("{0.0.sin()} {0.0.cos()} {0.0.tan()} {1.0.atan() * 4.0} {1.0.atan2(1.0) * 4.0} {0.0.exp()} {1.0.ln()}")
	print("{1.0.asin() * 2.0} {1.0.acos()} {0.0.sinh()} {0.0.cosh()} {0.0.tanh()} {3.0.exp2()} {8.0.log2()} {4.0.inverseSqrt()}")
	# the part above the floor; -1, 0 or 1; 0 below the edge, else 1
	print("{2.75.fract()} {(-3.0).sign()} {0.5.step(1.0)} {180.0.radians()} {pi.degrees()}")
	# the remainder of x / d with the sign of x, x % d
	print("{7.5.rem(2.0)} {(-7.5).rem(2.0)}")
	# the point t of the way from a to b; 0 up to lo, 1 from hi, a smooth curve between
	print("{0.0.lerp(10.0, 0.25)} {0.5.smoothstep(0.0, 1.0)} {2.0.smoothstep(0.0, 1.0)}")
	x f32 = 2.0
	print("{x.sin() == f32(2.0.sin())} {x.sqrt()}")
	prints """
		2 3 -2 -3 3 1024
		0 1 0 3.141592653589793 3.141592653589793 1 0
		3.141592653589793 0 0 1 0 8 3 0.5
		0.75 -1 0 3.141592653589793 180
		1.5 -1.5
		2.5 0.5 1
		true 1.4142135
		"""

# a byte's ASCII class: a word byte is a letter, a digit or `_`
test "methods on a byte":
	b u8[] = [55, 32, 65, 95, 97, 49]
	expect b[0].isDigit()
	expect b[1].isSpace()
	expect b[2].isAlpha()
	expect not b[3].isAlnum()
	expect b[2].isUpper()
	expect b[4].isLower()
	expect b[3].isWordByte()
	expect not b[5].isWordStart()

# `toBits()` is the `u64` holding an `f64`'s bits (the `u32` of an `f32`); `f64.fromBits(u)` and
# `f32.fromBits(u)` its reverse, every bit kept (a NaN's payload too)
test "a float's bits and back":
	one = f32.fromBits(0x3F80_0000)
	print("{one} {f32.fromBits(0xC0200000)} {one.toBits()}")
	print("{f64.fromBits(4609434218613702656)} {1.5.toBits()}")
	nan = f32.fromBits(0x7FC0_0001)
	keep f32[1]
	keep[0] = f32.fromBits(0x7FC0_0001)
	print("{nan != nan} {keep[0].toBits()} {f32.fromBits(1)}")
	prints """
		1 -2.5 1065353216
		1.5 4609434218613702656
		true 2143289345 1e-45
		"""

# `x.bitsAt(at, width)` is the `width` bits of an integer from bit `at` (the lowest is 0), of x's
# type: `(x >> at) & mask` written once, for a foreign format's fields (a struct of the program's
# own packs with `toBits`, *Serialization*).
test "an integer's bits from a place":
	w u32 = 0xABCD_1234
	n = 8
	expect w.bitsAt == {(0, 4): 4, (28, 4): 10, (4, n): 35}
	expect i32(-1).bitsAt(3, 5) == 31

# set bits; zero bits below the lowest set one (the width for 0); the 64-bit hash maps use, a
# bijection on integers (also on `str`)
test "bit counts and the hash":
	expect u64(12).bitCount() == 2
	expect u64(8).trailingZeros() == 3
	expect u64(0).trailingZeros() == 64
	expect 1.hash() != 2.hash()
	expect "a".hash() == "a".hash()

# An unsigned integer's bits turned, swapped and counted: `x.rotateLeft(n)` and `x.rotateRight(n)`
# by `n` modulo the width (a negative count turns the other way), `x.byteSwap()` its bytes in the
# other order, `x.leadingZeros()` the zero bits above the highest one set (the width for 0), as
# `trailingZeros()` those below the lowest.
test "an unsigned integer turned, its bytes swapped, its zero bits counted":
	x u32 = 0x1234_5678
	print("{x.rotateLeft(8):x} {x.rotateRight(-8):x} {x.byteSwap():x} {x.leadingZeros()}")
	b u8 = 0x81
	print("{b.rotateLeft(1)} {u16(0x00F0).leadingZeros()} {u32(0).trailingZeros()}")
	prints """
		34567812 34567812 78563412 3
		3 8 32
		"""

# `v.alignUp(a)` is `v` rounded up to a multiple of `a`, as offsets and sizes are aligned (a range
# or a natural takes it as its `i64`).
test "a size aligned":
	n n64 = 13
	expect n.alignUp(8) == 16
	expect 16.alignUp(8) == 16
	expect 7.alignUp(3) == 9
	expect 5.alignUp(1) == 5
