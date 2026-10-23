# The partition of each texel of a block, from the partition count and the 10-bit seed, by the
# format's hash: no table, so a footprint of any size has it.

smallBlockTexels = 32

# the format's 32-bit hash of the seed
fn hash52(seed u32):
	p = seed
	p ^= p >> 15
	p *= 0xEEDE_0891
	p ^= p >> 5
	p += p << 16
	p ^= p >> 7
	p ^= p >> 3
	p ^= p << 6
	p ^= p >> 17
	p

# the partition (0..parts-1) of every texel of a bx by by block, row after row
pub fn partitionMap(seed i64, parts i64, bx i64, by i64, mut map i64[144]):
	if parts == 1:
		for i in 0..bx * by:
			map[i] = 0
		return
	rnum = i64(hash52(u32.wrap(seed + (parts - 1) * 1024)))
	s i64[12]
	for k in 0..8:
		s[k] = (rnum >> (4 * k)) & 15
	s[8] = (rnum >> 18) & 15
	s[9] = (rnum >> 22) & 15
	s[10] = (rnum >> 26) & 15
	s[11] = ((rnum >> 30) | (rnum << 2)) & 15
	sh1 = 0
	sh2 = 0
	if seed & 1 != 0:
		sh1 = 4 if seed & 2 != 0 else 5
		sh2 = 6 if parts == 3 else 5
	else:
		sh1 = 6 if parts == 3 else 5
		sh2 = 4 if seed & 2 != 0 else 5
	sh3 = sh1 if seed & 16 != 0 else sh2
	shifts = [sh1, sh2, sh1, sh2, sh1, sh2, sh1, sh2, sh3, sh3, sh3, sh3]
	for k in 0..12:
		s[k] = (s[k] * s[k]) >> shifts[k]
	small = bx * by < smallBlockTexels
	for y in 0..by:
		for x in 0..bx:
			px = x * 2 if small else x
			py = y * 2 if small else y
			a = (s[0] * px + s[1] * py + (rnum >> 14)) & 63
			b = (s[2] * px + s[3] * py + (rnum >> 10)) & 63
			c = (s[4] * px + s[5] * py + (rnum >> 6)) & 63
			d = (s[6] * px + s[7] * py + (rnum >> 2)) & 63
			if parts < 4: d = 0
			if parts < 3: c = 0
			map[y * bx + x] = pick(a, b, c, d)

fn pick(a i64, b i64, c i64, d i64):
	if a >= b and a >= c and a >= d: return 0
	if b >= c and b >= d: return 1
	if c >= d: return 2
	3
