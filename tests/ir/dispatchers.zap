# A translated function's dispatcher (irdispatch.zap): a loop over a match on a variable, each arm
# setting the next key. An arm that sets a constant goes straight to that key's arm, the match
# skipped (a key no arm has goes to the default); entered at a key known only at run time, the
# match still decides the first arm. Each run's arms are recorded, so a wrong arm shows. A sparse
# match whose keys fall in pages (key >> s) switches on the page, then on the low bits.

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

# A function's labels: five in each of six pages of 256 bytes, at 4-byte steps (a switch on a
# page of them, then one on the low bits)
fn labelled(at i64):
	match at:
		0x7100_0042_0018: 1
		0x7100_0042_0024: 2
		0x7100_0042_004C: 3
		0x7100_0042_00A4: 4
		0x7100_0042_00C8: 5
		0x7100_0042_0110: 6
		0x7100_0042_011C: 7
		0x7100_0042_0130: 8
		0x7100_0042_016C: 9
		0x7100_0042_01B8: 10
		0x7100_0042_0220: 11
		0x7100_0042_022C: 12
		0x7100_0042_0278: 13
		0x7100_0042_02D4: 14
		0x7100_0042_02DC: 15
		0x7100_0042_031C: 16
		0x7100_0042_032C: 17
		0x7100_0042_033C: 18
		0x7100_0042_0370: 19
		0x7100_0042_03D8: 20
		0x7100_0042_0414: 21
		0x7100_0042_0418: 22
		0x7100_0042_041C: 23
		0x7100_0042_0470: 24
		0x7100_0042_04C8: 25
		0x7100_0042_053C: 26
		0x7100_0042_0544: 27
		0x7100_0042_0548: 28
		0x7100_0042_0594: 29
		0x7100_0042_05D4: 30
		_: 0

labels = [
	0x7100_0042_0018,
	0x7100_0042_0024,
	0x7100_0042_004C,
	0x7100_0042_00A4,
	0x7100_0042_00C8,
	0x7100_0042_0110,
	0x7100_0042_011C,
	0x7100_0042_0130,
	0x7100_0042_016C,
	0x7100_0042_01B8,
	0x7100_0042_0220,
	0x7100_0042_022C,
	0x7100_0042_0278,
	0x7100_0042_02D4,
	0x7100_0042_02DC,
	0x7100_0042_031C,
	0x7100_0042_032C,
	0x7100_0042_033C,
	0x7100_0042_0370,
	0x7100_0042_03D8,
	0x7100_0042_0414,
	0x7100_0042_0418,
	0x7100_0042_041C,
	0x7100_0042_0470,
	0x7100_0042_04C8,
	0x7100_0042_053C,
	0x7100_0042_0544,
	0x7100_0042_0548,
	0x7100_0042_0594,
	0x7100_0042_05D4
]

# a bank's addresses in each of four widths (`widths << 24 | address`)
fn widened(key u32):
	match key:
		0x0000_8184: 1
		0x0000_839D: 2
		0x0000_839E: 3
		0x0000_83B9: 4
		0x0100_80C0: 5
		0x0100_817A: 6
		0x0100_817D: 7
		0x0100_83CE: 8
		0x0200_80B9: 9
		0x0200_8122: 10
		0x0200_826D: 11
		0x0200_8392: 12
		0x0300_8055: 13
		0x0300_8142: 14
		0x0300_832B: 15
		0x0300_839F: 16
		_: 0

widenedKeys u32[] = [
	0x0000_8184,
	0x0000_839D,
	0x0000_839E,
	0x0000_83B9,
	0x0100_80C0,
	0x0100_817A,
	0x0100_817D,
	0x0100_83CE,
	0x0200_80B9,
	0x0200_8122,
	0x0200_826D,
	0x0200_8392,
	0x0300_8055,
	0x0300_8142,
	0x0300_832B,
	0x0300_839F
]

test "a sparse switch of labels in pages, every value around each tried":
	for i, k in labels:
		expect [labelled(k - 1), labelled(k), labelled(k + 1)] == [0, i + 1, 0]
		expect labelled(k ^ 0x1_0000) == 0   # the same low bits in a page with no case
		expect labelled(k + 0x600) == 0
	expect labelled(0) == 0
	expect labelled(-1) == 0

test "a sparse switch of addresses in four widths, every value around each tried":
	for k in widenedKeys:
		for x in [k - 1, k, k + 1]:
			expect widened(x) == (widenedKeys.indexOf(x) ?? -1) + 1
		expect widened(k + (4 << 24)) == 0
		expect widened(k | 0x0080_0000) == 0
	expect widened(0) == 0
	expect widened(0xFFFF_FFFF) == 0
