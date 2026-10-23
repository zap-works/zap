# A row of a constant list is borrowed in place (spec/variables.zap states constants).
#
# == on lists of integers or bools compares their bytes: every length (whole words and the bytes
# after), every width, and lists of floats or structs still element by element.

type Pair2:
	x f32
	y f32

test "a list literal of plain values walked by a for lives in the frame":
	a = 3
	b = 5
	sum = 0
	for i in 0..1000:
		for v in [a, b, i % 3, 7]:
			sum += v
	t = 0.0
	for p in [Pair2(x = 1.0, y = 2.0), Pair2(x = 3.0, y = 4.5)]:
		t += p.x * p.y
	expect sum == 15_999
	expect t == 15.5

test "a list made with its length that nothing resizes keeps every index within it":
	counts = zeros(256)
	for b in "hello, world".bytes():
		counts[i64(b)] += 1
	v = u32('a') << 16 | u32('b') << 8 | 'c'
	digits = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/"
	print("{counts['l']} {counts['o']} {digits[v >> 18]} {digits[v & 63]}")
	prints """
		3 2 111 122
		"""

nested = [[0, 1, 2], [8, 9], [5, 6]]

test "a row of a constant list of lists is borrowed, not given away, in nested loops":
	out = []
	for r in 0..3:
		for k in 0..2:
			row = nested[r]
			out.push(row[k % 1])
	expect out == [0, 0, 8, 8, 5, 5]
	expect nested == [[0, 1, 2], [8, 9], [5, 6]]

type P:
	x i32
	y i64

test "lists of integers and bools are equal when their elements are":
	a u8[] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
	b = a.copy()
	empty = []
	print("{a == b} {a == empty} {a == b[..8].copy()} {empty == []}")
	b[8] = 0
	c i32[] = [1, -2, 3]
	print("{a != b} {c == [1, -2, 4]} {c == [1, -2, 3]}")
	print("{[true, false] == [true, false]} {[true] == [false]}")
	print("{[0.0] == [-0.0]} {[P(x = 1, y = 2)] == [P(x = 1, y = 3)]}")
	prints """
		true false false true
		true false true
		true false
		true false
		"""

test "byte lists copied in pieces of every size keep their bytes":
	# the copy goes 8, 4, 2 and 1 bytes at a time: extend, remove (which moves the rest down over
	# itself) and slices
	sums = []
	for n in 0..40:
		src = (0..n).map(u8.wrap(it * 7 + 1))
		xs = []
		xs.extend(src)
		xs.extend(src[n / 3..n])
		if not xs.isEmpty:
			xs.remove(0)
		if xs.len > 5:
			xs.remove(3)
		sums.push(xs.reduce(0, (h, b): h * 31 % 1_000_003 + i64(b)))
	print(sums.reduce(0, (h, s): (h * 131 + s) % 1_000_000_007))
	prints """
		47337716
		"""

byteCounts = [0, 1, 7, 8, 9, 15, 16, 17, 1023, 1024, 1025, 1040, 5000, 100_003]

test "bytes added sixteen at a time give the sum of one at a time" for n in byteCounts:
	full u8[] = fill(n, 255)
	mixed = (0..n).map(u8(it * 7 % 256))
	one = 0
	for b in mixed:
		one += b
	expect full.sum(b: i64(b)) == 255 * n
	expect mixed.sum(b: i64(b)) == one
	expect mixed.sum(b: u64(b)) == u64(one)
