# A sequence of random numbers that repeats for its seed (xorshift64*): `rng = Random(seed)`,
# then `rng.next(0..10)`, `rng.next(1..=6)`, `rng.next(0.0..1.0)`. `random(range)` draws from
# the program's own sequence.
pub type Random:
	state i64

	# the next 64 random bits
	mut fn nextBits() u64:
		x = u64(randomStart if state == 0 else state)
		x ^= x >> 12
		x ^= x << 25
		x ^= x >> 27
		state = i64(x)
		x * 2_685_821_657_736_338_717

	# rng.next(lo..hi) of integers: one of [lo, hi); the program stops when the range is empty
	mut fn nextInt(lo i64, hi i64) i64:
		if hi <= lo:
			fail("random from an empty range {lo}..{hi}")
		lo + i64((nextBits() >> 1) % u64(hi - lo))

	# rng.next(lo..hi) of floats: one of [lo, hi)
	mut fn nextFloat(lo f64, hi f64) f64:
		lo + (hi - lo) * (f64(i64(nextBits() >> 11)) / 9007199254740992.0)

# the state a seed of 0 starts from (xorshift never leaves 0)
randomStart i64 = -7_046_029_254_386_353_131

mut programRandom = Random(state = randomStart)

# random(lo..hi) of integers, from the program's sequence
fn randomIn(lo i64, hi i64) i64:
	programRandom.nextInt(lo, hi)

# random(lo..hi) of floats, from the program's sequence
fn randomFloatIn(lo f64, hi f64) f64:
	programRandom.nextFloat(lo, hi)

# xs.pick(): an element drawn at random from the program's sequence (random); the program stops
# on an empty list
pub fn listPick<T>(xs T[]) ref T:
	if xs.len == 0:
		fail("pick from an empty list")
	xs[randomIn(0, len)]
