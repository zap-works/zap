# The part of an ASTC block before its data: the block mode (the weight grid, its range, a second
# weight plane), the partition count and seed, and the color endpoint modes, with where the
# endpoint values start and which range they are stored in. Anything the format reserves is none.

# What a block says about itself. The weights fill the top of the block backwards, the endpoint
# values start at `colorStart` and run up to the extra bits below the weights.
type Block:
	gridX i64
	gridY i64
	weightQuant i64
	dual bool
	plane2Channel i64
	parts i64
	seed i64
	modes i64[4]
	colorStart i64
	colorQuant i64
	colorCount i64

# the weight grid a block mode names: its size, its range and whether there are two planes
type GridMode:
	gridX i64
	gridY i64
	quant i64
	dual bool

weightsMax = 64
weightBitsMin = 24
weightBitsMax = 96
colorQuantMin = 4
colorCountMax = 18

# The block mode (the low 11 bits) of a 2D block: bits 0-1 and 2-3 pick how bits 5-8 give the grid's
# size, bit 4 with bits 0-3 the range, bit 9 whether it is the high set of ranges, bit 10 the
# second plane.
fn gridMode(mode i64) GridMode?:
	low = mode & 3
	a = (mode >> 5) & 3
	h = (mode >> 9) & 1
	dual = (mode >> 10) & 1 == 1
	r = (mode >> 4) & 1
	gx = 0
	gy = 0
	if low != 0:
		r |= low << 1
		b = (mode >> 7) & 3
		match (mode >> 2) & 3:
			0:
				gx = b + 4
				gy = a + 2
			1:
				gx = b + 8
				gy = a + 2
			2:
				gx = a + 2
				gy = b + 8
			_:
				if mode & 0x100 != 0:
					gx = (b & 1) + 2
					gy = a + 2
				else:
					gx = a + 2
					gy = (b & 1) + 6
	else:
		middle = (mode >> 2) & 3
		if middle == 0: return none
		r |= middle << 1
		match (mode >> 7) & 3:
			0:
				gx = 12
				gy = a + 2
			1:
				gx = a + 2
				gy = 12
			2:
				gx = a + 6
				gy = ((mode >> 9) & 3) + 6
				h = 0
				dual = false
			_:
				if a > 1: return none
				gx = 6 + a * 4
				gy = 10 - a * 4
	GridMode(gx, gy, r - 2 + 6 * h, dual)

# The header of the block of w (as four 32-bit words) in a footprint of bx by by texels.
pub fn readBlock(w i64[4], bx i64, by i64) Block?:
	grid = gridMode(bitsAt(w, 0, 11)) ?? GridMode(0, 0, 0, false)
	if grid.gridX == 0 or grid.gridX > bx or grid.gridY > by: return none
	planes = 2 if grid.dual else 1
	count = grid.gridX * grid.gridY * planes
	weightBits = sequenceBits(count, grid.quant)
	if count > weightsMax or weightBits < weightBitsMin or weightBits > weightBitsMax: return none
	parts = bitsAt(w, 11, 2) + 1
	if grid.dual and parts == 4: return none
	b = Block(grid.gridX, grid.gridY, grid.quant, grid.dual, 0, parts, 0, [0, 0, 0, 0], 17, 0, 0)
	below = 128 - weightBits
	if parts == 1:
		b.modes[0] = bitsAt(w, 13, 4)
	else:
		b.seed = bitsAt(w, 13, 10)
		b.colorStart = 29
		below -= readModes(w, below, b)
	if grid.dual:
		below -= 2
		b.plane2Channel = bitsAt(w, below, 2)
	b.colorCount = 0
	for i in 0..parts:
		b.colorCount += ((b.modes[i] >> 2) + 1) * 2
	if b.colorCount > colorCountMax: return none
	available = below - b.colorStart
	q = 20
	while q >= colorQuantMin and sequenceBits(b.colorCount, q) > available:
		q -= 1
	if q < colorQuantMin: return none
	b.colorQuant = q
	b

# The modes of several partitions: bits 23-24 name the class (0: one mode for all, in bits 25-28),
# else a class per partition (one bit each) and a 2-bit mode each, the latter right below the
# weights (the second plane's channel is below those). The count of those extra bits.
fn readModes(w i64[4], below i64, mut b Block):
	sel = bitsAt(w, 23, 6)
	base = sel & 3
	if base == 0:
		for i in 0..b.parts:
			b.modes[i] = sel >> 2
		return 0
	extra = 3 * b.parts - 4
	sel |= bitsAt(w, below - extra, extra) << 6
	for i in 0..b.parts:
		cls = base - 1 + ((sel >> (2 + i)) & 1)
		b.modes[i] = (cls << 2) | ((sel >> (2 + b.parts + 2 * i)) & 3)
	extra
