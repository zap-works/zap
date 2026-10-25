# The encoder: each block to one or two partitions of two endpoints each along their texels'
# principal axis, a block of one color to a void extent. The endpoint mode follows the texels:
# luminance (0) or RGB (8) direct when every texel is opaque, with alpha (4, 12) when not, and then
# a second weight plane for alpha too. A block tries every weight grid and range of `choicesFor`
# with one partition and, when that leaves an error, with two (the seed whose partitions are
# nearest two clusters of its texels), keeps the choice of least squared error, measured by the
# decoder's own rules (partitionMap, unquantize, spread, the 16-bit interpolation) so the error is
# the one a GPU shows, and refits that one's endpoints to its weights by least squares.

import image

cemGray = 0
cemGrayAlpha = 4
cemRgb = 8
cemRgba = 12

# the least endpoint range a choice may leave (32 levels): fewer gives banded gradients
colorQuantLeast = 11

# a way to store a block: its block mode, the weight grid and range it names and whether alpha has
# a plane of its own, its partitions, their endpoint mode and the endpoint range left by them
type Choice:
	mode i64
	parts i64
	gridX i64
	gridY i64
	weightQuant i64
	dual bool
	cem i64
	colorQuant i64

# What an encode reads for every block: the choices of its footprint, the nearest stored value of
# each 0..255 for every endpoint range at nearColor[q * 256 + v] (of each 0..64 for every weight
# range at nearWeight[q * 65 + v]; 0 for a range no choice uses) and the packed trits and quints of
# every group of values; the seeds of two partitions, one of each different split of the
# footprint, with the split as a mask of the texels of partition 1.
type Encoder:
	bx i64
	by i64
	srgb bool
	choices Choice[]
	nearColor i64[]
	nearWeight i64[]
	trits i64[]
	quints i64[]
	seeds i64[]
	masks i64[]

# the grids a footprint tries: itself and, past 4x4, the grids a texel and two texels smaller
fn gridsFor(bx i64, by i64):
	grids = [(bx, by)]
	for less in 1..3:
		if bx - less >= 4 and by - less >= 4: grids.push((bx - less, by - less))
	grids

# the block mode of a grid, weight range and plane count; none when the format has none
fn modeOf(gx i64, gy i64, q i64, dual bool) i64?:
	for mode in 0..2048:
		if gridMode(mode) is g:
			if g.gridX == gx and g.gridY == gy and g.quant == q and g.dual == dual: return mode
	none

# Every valid choice of the footprint for every endpoint mode: each grid at each weight range the
# format allows, with a plane for alpha where the mode has alpha, its endpoint range the one the
# decoder derives (readBlock), kept when it is fine enough.
fn choicesFor(bx i64, by i64):
	out = []
	for parts in 1..3:
		for (gx, gy) in gridsFor(bx, by):
			for q in 0..12:
				for dual in [false, true]:
					mode = modeOf(gx, gy, q, dual) ?? continue
					for cem in [cemGray, cemGrayAlpha, cemRgb, cemRgba]:
						if dual and cem in [cemGray, cemRgb]: continue
						w i64[4]
						w[0] = mode | (cem << 13) if parts == 1 else mode | (1 << 11) | (cem << 25)
						b = readBlock(w, bx, by) ?? continue
						if b.colorQuant >= colorQuantLeast:
							out.push(Choice(mode, parts, gx, gy, q, dual, cem, b.colorQuant))
	out

# the seeds of two partitions that split the footprint, one of each split, and the splits (none
# for a footprint past a mask's 63 texels)
fn splitsOf(bx i64, by i64):
	seeds = []
	masks = []
	if bx * by > 63: return (seeds, masks)
	seen {i64: bool} = {}
	full = (1 << (bx * by)) - 1
	for seed in 0..1024:
		map i64[144]
		partitionMap(seed, 2, bx, by, map)
		mask = 0
		for i in 0..bx * by:
			mask |= map[i] << i
		if mask == 0 or mask == full or mask in seen or (full ^ mask) in seen: continue
		seen[mask] = true
		seeds.push(seed)
		masks.push(mask)
	(seeds, masks)

# the stored value of range q nearest each value 0..top, `weight` for the weight unquantizer
fn nearestOf(q i64, top i64, weight bool):
	levels = [1, 3, 5][quantKind[q]] << quantBits[q]
	values = (0..levels).map(unquantize(it, q, weight))
	out = []
	for v in 0..=top:
		best = 0
		for s in 1..levels:
			if (values[s] - v).abs() < (values[best] - v).abs(): best = s
		out.push(best)
	out

# for each group of trits (quints) as a number in base 3 (5), the least packed bits that unpack to
# it (written from the most down, so the least stays): least, so a group cut short by the
# sequence's end has its missing values' bits 0
fn packedGroups(kind i64):
	size = 5 if kind == 1 else 3
	base = 3 if kind == 1 else 5
	out i64[] = zeros(243 if kind == 1 else 125)
	top = 255 if kind == 1 else 127
	for down in 0..=top:
		packed = top - down
		got i64[5]
		if kind == 1: unpackTrits(packed, got)
		else: unpackQuints(packed, got)
		index = 0
		scale = 1
		for j in 0..size:
			index += got[j] * scale
			scale *= base
		out[index] = packed
	out

fn newEncoder(bx i64, by i64, srgb bool):
	choices = choicesFor(bx, by)
	nearColor i64[] = zeros(21 * 256)
	nearWeight i64[] = zeros(12 * 65)
	for c in choices:
		for v, s in nearestOf(c.colorQuant, 255, false):
			nearColor[c.colorQuant * 256 + v] = s
		for v, s in nearestOf(c.weightQuant, 64, true):
			nearWeight[c.weightQuant * 65 + v] = s
	seeds, masks = splitsOf(bx, by)
	Encoder(
		bx,
		by,
		srgb,
		choices,
		nearColor,
		nearWeight,
		packedGroups(1),
		packedGroups(2),
		seeds,
		masks
	)

# The image as ASTC blocks of bx by by texels; `srgb` measures the error as an sRGB texture of
# them decodes (its endpoints widen otherwise).
pub fn encodeAstc(img image.Image, bx i64, by i64, srgb bool = false) Astc:
	if bx < footprintMin or by < footprintMin or bx > footprintMax or by > footprintMax:
		fail("a {bx}x{by} ASTC footprint is not encoded")
	e = newEncoder(bx, by, srgb)
	across = blocksFor(img.width, bx)
	rows = blocksFor(img.height, by)
	parts = (0..rows).parallel().map(e.rowOf(img, it, across))
	blocks u8[] = []
	blocks.reserve(across * rows * blockBytes)
	for part in parts:
		blocks.extend(part)
	Astc(bx, by, img.width, img.height, blocks)

# the blocks of a row of them
fn rowOf(e Encoder, img image.Image, row i64, across i64):
	out u8[] = zeros(across * blockBytes)
	for col in 0..across:
		e.encodeBlock(img, col, row, out, col * blockBytes)
	out

# the .astc file of a texture, as the reference encoder writes it
pub fn writeAstc(a Astc) u8[]:
	out u8[] = [0x13, 0xAB, 0xA1, 0x5C, u8(a.blockX), u8(a.blockY), 1]
	for v in [a.width, a.height, 1]:
		out.extend([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF])
	out.extend(a.blocks)
	out
