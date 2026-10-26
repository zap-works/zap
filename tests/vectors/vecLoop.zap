# Vector loads inside loops whose list header lives in registers: the element size of every
# lane type scales the index (8 lanes of 4 bytes, 4 of 8, 32 of 1).
n = 64
mut ints = []
mut floats = []
mut longs i64[] = []
mut bytes = []
for i in 0..n:
	ints.push(i32(i * 3))
	floats.push(f32(f64(i)) * f32(0.5))
	longs.push(i * 1000)
	bytes.push(u8(i % 7))
mut si = 0
mut sf = 0.0
mut sl = 0
for k in 0..(n / 8):
	si += ints.load8(k * 8).sum()
	sf += f64(floats.load8(k * 8).sum())
for k in 0..(n / 4):
	sl += longs.load4(k * 4).sum()
mut sb = 0
for k in 0..(n / 32):
	sb += bytes.load32(k * 32).sum()
print("{si} {sf} {sl} {sb}")

test "vector loads in a loop scale the index by the lane's size":
	main()
	prints """
	    6048 1008 2016000 189
	    """
