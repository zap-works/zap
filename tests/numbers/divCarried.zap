# a loop counter divided by a divisor the loop does not change: the quotient and the remainder
# carried from turn to turn (irDivCarry.zap), for every sign of the divisor and from any start
fn pairs(d i64, from i64):
	out = ""
	for i in from..from + 8:
		out += " {i / d}:{i % d}"
	out

fn mapped(d i64):
	(0..9).map(it / d * 100 + it % d)

for d in [1, 3, -3, -1, 7, 9_223_372_036_854_775_807, -9_223_372_036_854_775_808]:
	print("{d}:{pairs(d, 0)} |{pairs(d, 5)}")
	print(mapped(d))

test "a counter's quotient and remainder carried from turn to turn are the division's":
	main()
	prints """
		1: 0:0 1:0 2:0 3:0 4:0 5:0 6:0 7:0 | 5:0 6:0 7:0 8:0 9:0 10:0 11:0 12:0
		[0, 100, 200, 300, 400, 500, 600, 700, 800]
		3: 0:0 0:1 0:2 1:0 1:1 1:2 2:0 2:1 | 1:2 2:0 2:1 2:2 3:0 3:1 3:2 4:0
		[0, 1, 2, 100, 101, 102, 200, 201, 202]
		-3: 0:0 0:1 0:2 -1:0 -1:1 -1:2 -2:0 -2:1 | -1:2 -2:0 -2:1 -2:2 -3:0 -3:1 -3:2 -4:0
		[0, 1, 2, -100, -99, -98, -200, -199, -198]
		-1: 0:0 -1:0 -2:0 -3:0 -4:0 -5:0 -6:0 -7:0 | -5:0 -6:0 -7:0 -8:0 -9:0 -10:0 -11:0 -12:0
		[0, -100, -200, -300, -400, -500, -600, -700, -800]
		7: 0:0 0:1 0:2 0:3 0:4 0:5 0:6 1:0 | 0:5 0:6 1:0 1:1 1:2 1:3 1:4 1:5
		[0, 1, 2, 3, 4, 5, 6, 100, 101]
		9223372036854775807: 0:0 0:1 0:2 0:3 0:4 0:5 0:6 0:7 | 0:5 0:6 0:7 0:8 0:9 0:10 0:11 0:12
		[0, 1, 2, 3, 4, 5, 6, 7, 8]
		-9223372036854775808: 0:0 0:1 0:2 0:3 0:4 0:5 0:6 0:7 | 0:5 0:6 0:7 0:8 0:9 0:10 0:11 0:12
		[0, 1, 2, 3, 4, 5, 6, 7, 8]
		"""

test "a divisor of zero stops the loop before its first turn" stops DivisionByZero:
	d = args.len
	s = 0
	for i in 0..8:
		s += i / d
	print(s)
