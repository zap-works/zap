# A translated function's dispatcher (irdispatch.zap): a loop over a match on a variable, each arm
# setting the next key. An arm that sets a constant goes straight to that key's arm, the match
# skipped (a key no arm has goes to the default); entered at a key known only at run time, the
# match still decides the first arm. Each run's arms are recorded, so a wrong arm shows.

mut visited i64[] = []

# entered at a constant: every way in knows its key
fn fixed(n0 i64) i64:
	pc u32 = 0x0100_8000
	n = n0
	loop:
		match pc:
			0x0100_8000:
				visited.push(1)
				n += 1
				if n > 50: return n
				pc = 0x0100_8010
				continue
			0x0100_8010:
				visited.push(2)
				n += 2
				pc = 0x0100_9000   # falls out of the match: the loop goes on
			0x0100_9000:
				visited.push(3)
				n *= 3
				if n & 1 == 0:
					pc = 0x0100_8000
					continue
				pc = 0x0200_8000
			0x0200_8000:
				visited.push(4)
				return n + 7
			_: return -1

# entered at a run time key, a jump through a register (a key read from memory) on the way, and
# a constant no arm has
fn entered(start i64, jumps i64[]) i64:
	label = start
	n = 0
	turns = 0
	while true:
		turns += 1
		if turns > 20: return n
		match label:
			0x7100_0000_0010:
				visited.push(10)
				n += 1
				label = 0x7100_0000_0020
				continue
			0x7100_0000_0020:
				visited.push(20)
				n += 10
				label = jumps[n % len]
				continue
			0x7100_0000_0040:
				visited.push(40)
				label = 0x7100_0000_0010
				continue
			0x7100_0000_0044:
				visited.push(44)
				label = 0x7100_0000_0050   # no arm: the default
				continue
			_:
				visited.push(0)
				return -n
	0

test "a dispatcher entered at a constant takes every arm in order":
	visited.clear()
	expect fixed(0) == 16
	expect visited == [1, 2, 3, 4]
	visited.clear()
	expect fixed(1) == 52
	expect visited == [1, 2, 3, 1, 2, 3, 4]
	visited.clear()
	expect fixed(60) == 61
	expect visited == [1]

test "a dispatcher entered at a run time key, a key no arm has going to the default":
	for start in [0x7100_0000_0010, 0x7100_0000_0040, 0x7100_0000_0044, 0x7100_0000_0030]:
		visited.clear()
		entered(start, [0x7100_0000_0044])
		seen = visited.copy()
		match start:
			0x7100_0000_0010: expect seen == [10, 20, 44, 0]
			0x7100_0000_0040: expect seen == [40, 10, 20, 44, 0]
			0x7100_0000_0044: expect seen == [44, 0]
			_: expect seen == [0]
	visited.clear()
	jumps = [0x7100_0000_0040, 0x7100_0000_0010, 0x7100_0000_0020]
	expect entered(0x7100_0000_0010, jumps) == 105
	expect visited == (0..5).flatMap(_: [10, 20, 20, 40])
