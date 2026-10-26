# move on scalar places: the value moves out and the place is left zero, at its own width

fn removeAt<T>(mut xs T[], i i64) T:
	n = xs.len
	v = move xs[i]
	k = i
	while k < n - 1:
		xs[k] = move xs[k + 1]
		k += 1
	xs.truncate(n - 1)
	v

type Pair:
	a i64
	b f64

mut xs i64[] = [5, 6, 7]
v = move xs[0]
print(v)
print(xs)
mut bytes u8[] = [1, 2, 3, 4]
print(move bytes[1])
print(bytes)   # the neighbours of a byte survive
mut whole = 9
m = move whole
print(m)
print(whole)
mut p = Pair(a = 3, b = 2.5)
print(move p.b)
print(p)
mut fs f32[] = [f32(1.5), f32(2.5)]
print(move fs[0])
print(fs)
mut words str[] = ["a", "b", "c"]
print(removeAt(words, 1))
print(words)
mut nums i64[] = [1, 2, 3]
print(removeAt(nums, 0))
print(nums)
mut counts {str: i64} = {"x": 1}
taken = move counts
print(taken)
print(counts)

test "a scalar moved out of its place leaves zero there at its width":
	main()
	prints r"""
		5
		[0, 6, 7]
		2
		[1, 0, 3, 4]
		9
		0
		2.5
		Pair(a = 3, b = 0)
		1.5
		[0, 2.5]
		b
		["a", "c"]
		1
		[2, 3]
		{"x": 1}
		{}
		"""
