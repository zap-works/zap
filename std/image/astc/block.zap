# One block to its texels: the constant (void-extent) blocks, and for the others the weights
# unquantized and spread over the texel grid, the endpoints of each partition, and the texel's
# color between its partition's two endpoints. Anything that is not decodable (a reserved
# pattern) gives the error color; an HDR endpoint mode gives it to its partition's texels.

import image

errorColor = image.Rgba8(255, 0, 255, 255)

fn byteReverse(b i64):
	((b * 0x02_0202_0202) & 0x0108_8442_2010) % 1023

# the 16 bytes at `at` as four 32-bit words
fn wordsAt(src u8[], at i64) i64[4]:
	[src.u32le(at), src.u32le(at + 4), src.u32le(at + 8), src.u32le(at + 12)]

# the block's 128 bits in reverse order, where the weights' sequence reads from
fn reversedWords(src u8[], at i64):
	out i64[4]
	for i in 0..16:
		out[i >> 2] |= byteReverse(src[at + 15 - i]) << ((i & 3) * 8)
	out

fn fill(color image.Rgba8, texels i64, mut px image.Rgba8[144]):
	for i in 0..texels:
		px[i] = color

# Decodes the block at `at` of src into the `bx` by `by` texels of px, row after row; `srgb` picks
# how the endpoints widen (the result is the stored value either way).
pub fn decodeBlock(src u8[], at i64, bx i64, by i64, srgb bool, mut px image.Rgba8[144]):
	w = wordsAt(src, at)
	texels = bx * by
	if bitsAt(w, 0, 9) == 0x1FC:
		constantColor(w, src, at).fill(texels, px)
		return
	found = readBlock(w, bx, by)
	if found == none or not shade(src, at, w, found ?? emptyBlock, bx, by, srgb, px):
		errorColor.fill(texels, px)

emptyBlock = Block(0, 0, 0, false, 0, 0, 0, [0, 0, 0, 0], 0, 0, 0)

# a void-extent block: one 16-bit color a channel, of which the top bytes are kept; the error color
# for a half-float one (HDR) or reserved bits
fn constantColor(w i64[4], src u8[], at i64):
	hdr = bitsAt(w, 9, 1) == 1
	if hdr or bitsAt(w, 10, 2) != 3: return errorColor
	sMin = bitsAt(w, 12, 13)
	sMax = bitsAt(w, 25, 13)
	tMin = bitsAt(w, 38, 13)
	tMax = bitsAt(w, 51, 13)
	unbounded = sMin == 0x1FFF and sMax == 0x1FFF and tMin == 0x1FFF and tMax == 0x1FFF
	if (sMin >= sMax or tMin >= tMax) and not unbounded: return errorColor
	image.Rgba8(src[at + 9], src[at + 11], src[at + 13], src[at + 15])

# Fills px with the block's texels; false when the block is an error.
fn shade(
	src u8[],
	at i64,
	w i64[4],
	block Block,
	bx i64,
	by i64,
	srgb bool,
	mut px image.Rgba8[144]
):
	map i64[144]
	partitionMap(block.seed, block.parts, bx, by, map)
	ends i64[32]
	readColors(w, block, srgb, ends)
	planes i64[288]
	readWeights(src, at, block, bx, by, planes)
	ccs = block.plane2Channel if block.dual else -1
	for i in 0..bx * by:
		e = map[i] * 8
		c i64[4]
		for ch in 0..4:
			weight = planes[144 + i] if ch == ccs else planes[i]
			c[ch] = ((ends[e + ch] * (64 - weight) + ends[e + 4 + ch] * weight + 32) >> 6) >> 8
		px[i] = image.Rgba8(u8.wrap(c[0]), u8.wrap(c[1]), u8.wrap(c[2]), u8.wrap(c[3]))
	true

# The endpoints of every partition, 8 values each, in 16 bits a channel: the stored 8-bit value
# repeated into the low byte, or for sRGB with 0x80 there.
fn readColors(w i64[4], block Block, srgb bool, mut ends i64[32]):
	values i64[96]
	readSequence(w, block.colorStart, block.colorCount, block.colorQuant, values)
	for i in 0..block.colorCount:
		values[i] = unquantize(values[i], block.colorQuant, false)
	at = 0
	for p in 0..block.parts:
		mode = block.modes[p]
		e i64[8]
		if not readEndpoints(mode, values, at, e):
			setEndpoints(e, 255, 0, 255, 255, 255, 0, 255, 255)
		at += ((mode >> 2) + 1) * 2
		for k in 0..8:
			ends[p * 8 + k] = (e[k] << 8) | (0x80 if srgb else e[k])

# The weights of plane 0 into planes[0..] and of plane 1 into planes[144..], one for each texel.
fn readWeights(src u8[], at i64, block Block, bx i64, by i64, mut planes i64[288]):
	rev = reversedWords(src, at)
	count = block.gridX * block.gridY
	planeCount = 2 if block.dual else 1
	raw i64[96]
	readSequence(rev, 0, count * planeCount, block.weightQuant, raw)
	grid i64[96]
	for plane in 0..planeCount:
		for i in 0..count:
			grid[i] = unquantize(raw[i * planeCount + plane], block.weightQuant, true)
		spread(grid, block.gridX, block.gridY, bx, by, plane * 144, planes)

# The weight grid laid over the block's texels: each texel takes the four grid weights around its
# position (in 1/16 steps, the four shares adding to 16), the grid stretched to fit the block.
fn spread(grid i64[96], gx i64, gy i64, bx i64, by i64, base i64, mut planes i64[288]):
	ds = (1024 + bx / 2) / (bx - 1)
	dt = (1024 + by / 2) / (by - 1)
	for t in 0..by:
		gt = (dt * t * (gy - 1) + 32) >> 6
		jt = gt >> 4
		ft = gt & 15
		for s in 0..bx:
			gs = (ds * s * (gx - 1) + 32) >> 6
			js = gs >> 4
			fs = gs & 15
			v = jt * gx + js
			p11 = (fs * ft + 8) >> 4
			p10 = ft - p11
			p01 = fs - p11
			p00 = 16 - fs - ft + p11
			planes[base + t * bx + s] = (
				grid[v] * p00 + grid[v + 1] * p01 + grid[v + gx] * p10 + grid[v + gx + 1] * p11 + 8
			) >> 4
