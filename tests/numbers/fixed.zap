# "{x:.n}" is the exact binary value rounded half to even at n decimals (runtime/core/num.zap's
# fmtFixed): a wide multiply for up to 17 decimals while the integer fits 64 bits, the exact
# decimal beyond. The texts below are Python's format of the same doubles.

# a value and its text at 0, 2 and 17 decimals
type Fixed:
	x f64
	zero str
	two str
	many str

fixed Fixed[] = [
	Fixed(0.125, "0", "0.12", "0.12500000000000000"),
	Fixed(0.375, "0", "0.38", "0.37500000000000000"),
	Fixed(2.5, "2", "2.50", "2.50000000000000000"),
	Fixed(3.5, "4", "3.50", "3.50000000000000000"),
	Fixed(9.995, "10", "9.99", "9.99499999999999922"),
	Fixed(99.97, "100", "99.97", "99.96999999999999886"),
	Fixed(0.999, "1", "1.00", "0.99900000000000000"),
	Fixed(1_000_000_000_000_000.2, "1000000000000000", "1000000000000000.25", "1000000000000000.25000000000000000"),
	Fixed(123_456_789.98765433, "123456790", "123456789.99", "123456789.98765432834625244"),
	Fixed(1.0e19, "10000000000000000000", "10000000000000000000.00", "10000000000000000000.00000000000000000"),
	Fixed(1.8446744073709552e19, "18446744073709551616", "18446744073709551616.00", "18446744073709551616.00000000000000000"),
	Fixed(1.0e22, "10000000000000000000000", "10000000000000000000000.00", "10000000000000000000000.00000000000000000"),
	Fixed(5.0e-324, "0", "0.00", "0.00000000000000000"),
	Fixed(0.1, "0", "0.10", "0.10000000000000001"),
	Fixed(2.675, "3", "2.67", "2.67499999999999982"),
	Fixed(1.0e-7, "0", "0.00", "0.00000010000000000")
]

test "fixed decimals round the exact value half to even":
	for c in fixed:
		expect "{c.x:.0}" == c.zero
		expect "{c.x:.2}" == c.two
		expect "{c.x:.17}" == c.many

test "a negative keeps its sign unless it rounds to zero":
	expect "{-2.5:.0}" == "-2"
	expect "{-99.97:.1}" == "-100.0"
	expect "{-0.001:.2}" == "0.00"
	expect "{-0.0:.3}" == "0.000"
	expect "{-123_456_789.98765433:.2}" == "-123456789.99"
