# The Tegra's block-linear layout, how the Switch's GPU keeps most surfaces: the image cut into
# GOBs of 64 bytes by 8 rows (512 bytes, its bytes in a fixed order of 16-byte pieces), GOBs stacked
# 2^blockHeight high (and 2^blockDepth deep) into blocks, blocks laid left to right, then down, then
# back. A compressed format's rows are rows of its 4x4 blocks. The order is yuzu's and Ryujinx's
# (textures/decoders), as the hardware documents it.

gobWidth = 64
gobHeight = 8
gobBytes = 512

# the byte at (x, y) of one GOB: its place among the GOB's 512
fn inGob(x i64, y i64):
	(x % 64) / 32 * 256 + (y % 8) / 2 * 64 + (x % 32) / 16 * 32 + (y % 2) * 16 + x % 16

# The shape of a block-linear surface: its row of bytes, its rows and slices, and its blocks' GOBs
# up and deep as log2.
pub type Surface:
	rowBytes i64
	rows i64
	slices i64 = 1
	blockHeight i64 = 0
	blockDepth i64 = 0

	# the bytes the surface takes in its layout: whole blocks, every way
	fn layoutBytes():
		up = gobHeight << blockHeight
		deep = 1 << blockDepth
		blocksAcross = (rowBytes + gobWidth - 1) / gobWidth
		blocksDown = (rows + up - 1) / up
		blocksBack = (slices + deep - 1) / deep
		blocksAcross * blocksDown * blocksBack * (gobBytes << (blockHeight + blockDepth))

	# where the byte at (x, y, z) of the plain image lies in the layout
	fn offset(x i64, y i64, z i64):
		up = gobHeight << blockHeight
		deep = 1 << blockDepth
		block = gobBytes << (blockHeight + blockDepth)
		blocksAcross = (rowBytes + gobWidth - 1) / gobWidth
		blocksDown = (rows + up - 1) / up
		blockAt = ((z / deep) * blocksDown + y / up) * blocksAcross + x / gobWidth
		gobAt = ((z % deep) << blockHeight) + (y % up) / gobHeight
		blockAt * block + gobAt * gobBytes + inGob(x, y)

# The surface's plain bytes (rows of rowBytes, rows by slices) from its block-linear bytes at `at`.
pub fn unswizzle(s Surface, src u8[], at i64) u8[]:
	out u8[] = zeros(s.rowBytes * s.rows * s.slices)
	for z in 0..s.slices:
		for y in 0..s.rows:
			base = (z * s.rows + y) * s.rowBytes
			for x in 0..s.rowBytes:
				from = at + s.offset(x, y, z)
				if from < src.len: out[base + x] = src[from]
	out

# The block-linear bytes of the surface from its plain bytes (unswizzle's inverse, for tests and
# for what the CPU writes back).
pub fn swizzle(s Surface, plain u8[]) u8[]:
	out u8[] = zeros(s.layoutBytes())
	for z in 0..s.slices:
		for y in 0..s.rows:
			for x in 0..s.rowBytes:
				out[s.offset(x, y, z)] = plain[(z * s.rows + y) * s.rowBytes + x]
	out

test "a GOB's bytes go in 16-byte pieces, two rows a pair, the halves of 32 apart":
	s = Surface(rowBytes = 64, rows = 8)
	expect s.offset(0, 0, 0) == 0
	expect s.offset(16, 0, 0) == 32
	expect s.offset(0, 1, 0) == 16
	expect s.offset(0, 2, 0) == 64
	expect s.offset(32, 0, 0) == 256
	expect s.offset(63, 7, 0) == 511

test "GOBs stack in a block, blocks go across then down":
	s = Surface(rowBytes = 128, rows = 32, blockHeight = 1)
	expect s.offset(0, 8, 0) == 512   # the block's second GOB
	expect s.offset(64, 0, 0) == 1024   # the next block across
	expect s.offset(0, 16, 0) == 2048   # the next row of blocks
	expect s.layoutBytes() == 4096

test "swizzle and unswizzle are inverses":
	s = Surface(rowBytes = 200, rows = 37, slices = 3, blockHeight = 2, blockDepth = 1)
	plain u8[] = (0..s.rowBytes * s.rows * s.slices).map(u8((it * 7 + it / 13) & 0xFF))
	expect s.unswizzle(s.swizzle(plain), 0) == plain
