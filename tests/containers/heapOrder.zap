# A heap gives its values back smallest first whatever the order they came in (sizes that leave
# the last parent one, two, three or four children).

for n in [1, 2, 3, 4, 5, 6, 7, 20, 21, 22, 23, 1000]:
	h = Heap<i64>()
	x = 7
	loop n:
		x = (x * 1_103_515_245 + 12_345) % 1_000_003
		h.push(x % 97)
	last = -1
	ordered = true
	pops = 0
	while h.pop() is v:
		ordered = ordered and v >= last
		last = v
		pops += 1
		if pops % 3 == 0 and pops < n / 2:
			h.push(last + pops % 5)   # pushes between pops too, none below the last
	print("{n} {ordered}")

test "a heap gives its values back smallest first":
	main()
	prints """
		1 true
		2 true
		3 true
		4 true
		5 true
		6 true
		7 true
		20 true
		21 true
		22 true
		23 true
		1000 true
		"""
