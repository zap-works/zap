fn pick(i i64):
	i * 7 % 5
mut total = 0
mut seen = []
for i in 0..12:
	a = pick(i)
	if a > 2:
		d = a * 10 + i
		seen.push(d)
		total += d
	elif a == 2:
		d = pick(i + 1)
		total += d * 100
	else:
		t = i + 1
		total -= t
	d = a + 1
	k = pick(d)
	total += k
print("{total} {seen}")

test "a let in a branch is its own variable, another after the branch":
	main()
	prints """
	    1354 [42, 34, 47, 39]
	    """
