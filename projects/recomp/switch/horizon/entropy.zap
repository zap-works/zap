# svcGetInfo's random entropy (InfoType 11), as Eden draws it: four u64 from std::mt19937 seeded 0
# (its rng_seed setting) through uniform_int_distribution, each the first 32-bit draw above the second.

entropyWords = 4
mtSeed = 0
mtShift = 397
mask32 = 0xFFFF_FFFF

# the first n outputs of a 32-bit Mersenne Twister, tempered
fn twister(seed i64, n i64):
	state = [seed & mask32]
	for i in 1..=n + mtShift:
		previous = state[i - 1]
		state.push((1_812_433_253 * (previous ^ (previous >> 30)) + i) & mask32)
	out = []
	for i in 0..n:
		mixed = (state[i] & 0x8000_0000) | (state[i + 1] & 0x7FFF_FFFF)
		twisted = state[i + mtShift] ^ (mixed >> 1) ^ (0x9908_B0DF if mixed & 1 != 0 else 0)
		y = twisted ^ (twisted >> 11)
		y ^= (y << 7) & 0x9D2C_5680
		y ^= (y << 15) & 0xEFC6_0000
		out.push((y ^ (y >> 18)) & mask32)
	out

# entropy word i of the process
pub fn processEntropy(index i64) u64?:
	if index < 0 or index >= entropyWords: return none
	draws = twister(mtSeed, entropyWords * 2)
	u64((draws[index * 2] << 32) | draws[index * 2 + 1])
