# One block encoded: its texels read (clamped at the image's edges), the endpoint mode they need,
# the endpoints along each partition's principal axis, and for each choice of that mode the endpoints
# quantized, each texel's weight projected on them and laid on the choice's grid, the error measured
# as the decoder interpolates; the best choice refit to its weights, and its bits written as the
# decoder reads them.

import image

# What a choice gives a block: its endpoint values and weights as stored (the weights interleaved
# by plane), the weight each texel gets (plane 1's from 144), the squared error and, for two
# partitions, their seed.
type Fit:
	stored i64[96]
	grid i64[96]
	planes i64[288]
	err i64
	seed i64

# the texels of the block at col, row as r, g, b, a each, row after row
fn texelsAt(e Encoder, img image.Image, col i64, row i64, mut px i64[576]):
	for y in 0..e.by:
		sy = (row * e.by + y).min(img.height - 1)
		for x in 0..e.bx:
			p = img[(col * e.bx + x).min(img.width - 1), sy]
			i = (y * e.bx + x) * 4
			px[i] = i64(p.r)
			px[i + 1] = i64(p.g)
			px[i + 2] = i64(p.b)
			px[i + 3] = i64(p.a)

fn uniform(px i64[576], texels i64):
	for i in 4..texels * 4:
		if px[i] != px[i & 3]: return false
	true

# a void extent of the color of the block's first texel, its extent unbounded
fn voidExtent(px i64[576]) i64[4]:
	[0xFFFF_FDFC, 0xFFFF_FFFF, px[0] * 257 | (px[1] * 257) << 16, px[2] * 257 | (px[3] * 257) << 16]

# The block at col, row of the image into out[at..at + 16].
fn encodeBlock(e Encoder, img image.Image, col i64, row i64, mut out u8[], at i64):
	px i64[576]
	e.texelsAt(img, col, row, px)
	w = voidExtent(px) if uniform(px, e.bx * e.by) else e.bestBlock(px)
	for i in 0..16:
		out[at + i] = u8((w[i >> 2] >> ((i & 3) * 8)) & 0xFF)

# the endpoint mode of the texels: luminance when each is gray, with alpha when one is not opaque
fn cemOf(px i64[576], texels i64):
	gray = true
	opaque = true
	for i in 0..texels:
		at = i * 4
		if px[at] != px[at + 1] or px[at] != px[at + 2]: gray = false
		if px[at + 3] != 255: opaque = false
	(cemGray if gray else cemRgb) + (0 if opaque else cemGrayAlpha)

# the bits of the choice of least error for the texels, refit
fn bestBlock(e Encoder, px i64[576]) i64[4]:
	texels = e.bx * e.by
	cem = cemOf(px, texels)
	map i64[144]
	best = Fit(stored = zeros(96), grid = zeros(96), planes = zeros(288), err = -1, seed = 0)
	chosen = e.bestOf(px, cem, map, 1, best, 0)
	# two partitions where one leaves more than a level of error a channel
	if best.err > texels * 4 and not e.seeds.isEmpty:
		seed = e.seedFor(px)
		two i64[144]
		partitionMap(seed, 2, e.bx, e.by, two)
		split = best
		split.err = -1
		twoChosen = e.bestOf(px, cem, two, 2, split, seed)
		if twoChosen >= 0 and split.err < best.err:
			best = split
			chosen = twoChosen
			map = two
	c = e.choices[chosen]
	refit f64[16]
	trial = best
	loop 2:
		e.refitEnds(c, px, map, best.planes, refit)
		e.tryChoice(c, px, map, refit, trial)
		if trial.err >= best.err: break
		best = trial
	e.blockBits(c, best)

# The choice of `parts` partitions (the texels' partitions in map, of `seed`) of least error for
# the texels into best, its index: the endpoints along each partition's axis (for a plane of
# alpha's own, the color's axis apart and alpha's least and most).
fn bestOf(
	e Encoder,
	px i64[576],
	cem i64,
	map i64[144],
	parts i64,
	mut best Fit,
	seed i64
) i64:
	ends f64[16]
	split f64[16]
	for part in 0..parts:
		e.principalEnds(px, 4, map, part, ends)
		e.principalEnds(px, 3, map, part, split)
		split[part * 8 + 3] = 255.0
		split[part * 8 + 7] = 0.0
		for i in 0..e.bx * e.by:
			if map[i] == part:
				split[part * 8 + 3] = split[part * 8 + 3].min(f64(px[i * 4 + 3]))
				split[part * 8 + 7] = split[part * 8 + 7].max(f64(px[i * 4 + 3]))
	trial = best
	trial.seed = seed
	chosen = -1
	for k in 0..e.choices.len:
		c = e.choices[k]
		if c.cem != cem or c.parts != parts: continue
		e.tryChoice(c, px, map, split if c.dual else ends, trial)
		if best.err < 0 or trial.err < best.err:
			best = trial
			chosen = k
	chosen

# The seed of two partitions nearest two clusters of the texels (k-means from the two ends of the
# block's axis): the split of the fewest texels on the other side.
fn seedFor(e Encoder, px i64[576]) i64:
	texels = e.bx * e.by
	zero i64[144]
	ends f64[16]
	e.principalEnds(px, 4, zero, 0, ends)
	mask = 0
	loop 3:
		mask = 0
		for i in 0..texels:
			d0 = 0.0
			d1 = 0.0
			for ch in 0..4:
				v = f64(px[i * 4 + ch])
				d0 += (v - ends[ch]) * (v - ends[ch])
				d1 += (v - ends[4 + ch]) * (v - ends[4 + ch])
			if d1 < d0: mask |= 1 << i
		sums f64[8]
		counts f64[2]
		for i in 0..texels:
			side = (mask >> i) & 1
			counts[side] += 1.0
			for ch in 0..4:
				sums[side * 4 + ch] += f64(px[i * 4 + ch])
		for side in 0..2:
			if counts[side] > 0.0:
				for ch in 0..4:
					ends[side * 4 + ch] = sums[side * 4 + ch] / counts[side]
	best = 0
	fewest = texels + 1
	for k in 0..e.masks.len:
		d = (e.masks[k] ^ mask).bitCount()
		d = d.min(texels - d)
		if d < fewest:
			fewest = d
			best = k
	e.seeds[best]

# The two endpoints of the first `channels` channels (r, g, b, a) of the texels of partition
# `part` into ends[part * 8..]: their mean moved along their principal axis (by power iteration on
# the covariance) to the least and the most of their projections.
fn principalEnds(e Encoder, px i64[576], channels i64, map i64[144], part i64, mut ends f64[16]):
	texels = e.bx * e.by
	count = 0.0
	mean f64[4]
	for i in 0..texels:
		if map[i] == part:
			count += 1.0
			for ch in 0..channels:
				mean[ch] += f64(px[i * 4 + ch])
	if count == 0.0: return
	for ch in 0..channels:
		mean[ch] /= count
	cov f64[16]
	for i in 0..texels:
		if map[i] == part:
			for a in 0..channels:
				da = f64(px[i * 4 + a]) - mean[a]
				for b in 0..channels:
					cov[a * 4 + b] += da * (f64(px[i * 4 + b]) - mean[b])
	# from the covariance's row of the most varied channel, which the axis cannot be normal to
	most = 0
	for a in 1..channels:
		if cov[a * 5] > cov[most * 5]: most = a
	axis f64[4] = [cov[most * 4], cov[most * 4 + 1], cov[most * 4 + 2], cov[most * 4 + 3]]
	loop 8:
		next f64[4]
		norm = 0.0
		for a in 0..channels:
			for b in 0..channels:
				next[a] += cov[a * 4 + b] * axis[b]
			norm += next[a] * next[a]
		if norm < 1e-12: break
		norm = norm.sqrt()
		for a in 0..channels:
			axis[a] = next[a] / norm
	lo = 1e30
	hi = -1e30
	for i in 0..texels:
		if map[i] == part:
			t = 0.0
			for ch in 0..channels:
				t += (f64(px[i * 4 + ch]) - mean[ch]) * axis[ch]
			lo = lo.min(t)
			hi = hi.max(t)
	for ch in 0..channels:
		ends[part * 8 + ch] = mean[ch] + lo * axis[ch]
		ends[part * 8 + 4 + ch] = mean[ch] + hi * axis[ch]

# Each partition's endpoints refit to the weights its texels got: the least squares of the
# interpolation against the texels, channel by channel (alpha against the second plane when the
# choice has one).
fn refitEnds(e Encoder, c Choice, px i64[576], map i64[144], planes i64[288], mut ends f64[16]):
	for part in 0..c.parts:
		for ch in 0..4:
			base = 144 if c.dual and ch == 3 else 0
			aa = 0.0
			ab = 0.0
			bb = 0.0
			ap = 0.0
			bp = 0.0
			for i in 0..e.bx * e.by:
				if map[i] == part:
					t = f64(planes[base + i]) / 64.0
					p = f64(px[i * 4 + ch])
					aa += (1.0 - t) * (1.0 - t)
					ab += t * (1.0 - t)
					bb += t * t
					ap += (1.0 - t) * p
					bp += t * p
			det = aa * bb - ab * ab
			at = part * 8 + ch
			if det.abs() < 1e-9:
				ends[at] = (ap + bp) / (aa + 2.0 * ab + bb).max(1.0)
				ends[at + 4] = ends[at]
			else:
				ends[at] = (ap * bb - ab * bp) / det
				ends[at + 4] = (aa * bp - ab * ap) / det

fn byteOf(v f64):
	i64(v.round()).clamp(0, 255)

# a channel's endpoint widened to 16 bits as the decoder interpolates it
fn widened(e Encoder, v i64):
	(v << 8) | (0x80 if e.srgb else v)

# the channel the endpoint values of pair p (of the mode's 1 to 4) come from: luminance from red
fn sourceOf(cem i64, p i64):
	[0, 3][p] if cem < cemRgb else p

# the pair of endpoint values of a channel, -1 for alpha in a mode without it (255 then)
fn pairOf(cem i64, ch i64):
	if ch == 3: return [-1, 1, -1, 3][cem >> 2]
	0 if cem < cemRgb else ch

# Choice c of the texels (of the partitions in map) from the endpoints `ends` (r, g, b, a each,
# 8 a partition) into f: each partition's endpoints quantized, the weights projected on them, and
# the error.
fn tryChoice(e Encoder, c Choice, px i64[576], map i64[144], ends f64[16], mut f Fit):
	pairs = (c.cem >> 2) + 1
	near = c.colorQuant * 256
	lo i64[8]
	hi i64[8]
	for part in 0..c.parts:
		at = part * pairs * 2
		un i64[8]
		for p in 0..pairs:
			ch = part * 8 + sourceOf(c.cem, p)
			f.stored[at + p * 2] = e.nearColor[near + byteOf(ends[ch])]
			f.stored[at + p * 2 + 1] = e.nearColor[near + byteOf(ends[4 + ch])]
			un[p * 2] = unquantize(f.stored[at + p * 2], c.colorQuant, false)
			un[p * 2 + 1] = unquantize(f.stored[at + p * 2 + 1], c.colorQuant, false)
		# a lower second sum would make the decoder contract blue: the endpoints swap instead
		if c.cem >= cemRgb and un[1] + un[3] + un[5] < un[0] + un[2] + un[4]:
			for k in 0..pairs:
				s = f.stored[at + k * 2]
				f.stored[at + k * 2] = f.stored[at + k * 2 + 1]
				f.stored[at + k * 2 + 1] = s
				u = un[k * 2]
				un[k * 2] = un[k * 2 + 1]
				un[k * 2 + 1] = u
		for ch in 0..4:
			p = pairOf(c.cem, ch)
			lo[part * 4 + ch] = un[p * 2] if p >= 0 else 255
			hi[part * 4 + ch] = un[p * 2 + 1] if p >= 0 else 255
	ideal f64[288]
	e.projected(px, map, lo, hi, 0, 3 if c.dual else 4, 0, ideal)
	if c.dual: e.projected(px, map, lo, hi, 3, 4, 144, ideal)
	e.laidOnGrid(c, ideal, f)
	f.err = 0
	for i in 0..e.bx * e.by:
		at = map[i] * 4
		for ch in 0..4:
			w = f.planes[144 + i] if c.dual and ch == 3 else f.planes[i]
			got = ((e.widened(lo[at + ch]) * (64 - w) + e.widened(hi[at + ch]) * w + 32) >> 6) >> 8
			d = got - px[i * 4 + ch]
			f.err += d * d

# each texel's weight 0..64 between its partition's endpoints lo and hi over the channels
# from..to: its projection on the segment, into ideal[base..]
fn projected(
	e Encoder,
	px i64[576],
	map i64[144],
	lo i64[8],
	hi i64[8],
	from i64,
	to i64,
	base i64,
	mut ideal f64[288]
):
	for i in 0..e.bx * e.by:
		at = map[i] * 4
		span = 0
		t = 0
		for ch in from..to:
			d = hi[at + ch] - lo[at + ch]
			span += d * d
			t += (px[i * 4 + ch] - lo[at + ch]) * d
		ideal[base + i] = 0.0 if span == 0 else (f64(t) * 64.0 / f64(span)).clamp(0.0, 64.0)

# Each plane's texel weights sampled at the grid's points (between the texels when the grid is
# smaller), quantized into f.grid, and spread back over the texels as the decoder does, into
# f.planes.
fn laidOnGrid(e Encoder, c Choice, ideal f64[288], mut f Fit):
	near = c.weightQuant * 65
	planeCount = 2 if c.dual else 1
	values i64[96]
	for plane in 0..planeCount:
		for gy in 0..c.gridY:
			fy = f64(gy * (e.by - 1)) / f64(c.gridY - 1)
			y0 = i64(fy).min(e.by - 2)
			ty = fy - f64(y0)
			for gx in 0..c.gridX:
				fx = f64(gx * (e.bx - 1)) / f64(c.gridX - 1)
				x0 = i64(fx).min(e.bx - 2)
				tx = fx - f64(x0)
				at = plane * 144 + y0 * e.bx + x0
				top = ideal[at] * (1.0 - tx) + ideal[at + 1] * tx
				bottom = ideal[at + e.bx] * (1.0 - tx) + ideal[at + e.bx + 1] * tx
				k = gy * c.gridX + gx
				stored = e.nearWeight[near + i64((top * (1.0 - ty) + bottom * ty).round())]
				f.grid[k * planeCount + plane] = stored
				values[k] = unquantize(stored, c.weightQuant, true)
		spread(values, c.gridX, c.gridY, e.bx, e.by, plane * 144, f.planes)

# n bits of v into the block from bit `at`
fn putBits(mut w i64[4], at i64, n i64, v i64):
	for k in 0..n:
		if (v >> k) & 1 == 1: w[(at + k) >> 5] |= 1 << ((at + k) & 31)

# `count` values of range q from bit `start`, as readSequence reads them
fn writeSequence(e Encoder, mut w i64[4], start i64, count i64, q i64, values i64[96]):
	n = quantBits[q]
	kind = quantKind[q]
	at = start
	if kind == 0:
		for i in 0..count:
			putBits(w, at, n, values[i])
			at += n
		return
	size = 5 if kind == 1 else 3
	base = 3 if kind == 1 else 5
	chunks = tritChunks if kind == 1 else quintChunks
	first = 0
	while first < count:
		taken = (count - first).min(size)
		index = 0
		scale = 1
		for j in 0..taken:
			index += (values[first + j] >> n) * scale
			scale *= base
		packed = e.trits[index] if kind == 1 else e.quints[index]
		for j in 0..taken:
			putBits(w, at, n, values[first + j])
			at += n
			putBits(w, at, chunks[j], packed)
			packed >>= chunks[j]
			at += chunks[j]
		first += taken

# the block's bits: the mode, the partitions (for two, their seed and one endpoint mode for both),
# the endpoint values from bit 17 (29 for two), the weights from the top bit down and, for two
# planes, alpha's as the second plane's channel below them
fn blockBits(e Encoder, c Choice, f Fit) i64[4]:
	w i64[4]
	putBits(w, 0, 11, c.mode)
	if c.parts == 1:
		putBits(w, 13, 4, c.cem)
	else:
		putBits(w, 11, 2, c.parts - 1)
		putBits(w, 13, 10, f.seed)
		putBits(w, 25, 4, c.cem)
	values = ((c.cem >> 2) + 1) * 2 * c.parts
	e.writeSequence(w, 17 if c.parts == 1 else 29, values, c.colorQuant, f.stored)
	rev i64[4]
	count = c.gridX * c.gridY * (2 if c.dual else 1)
	e.writeSequence(rev, 0, count, c.weightQuant, f.grid)
	bits = sequenceBits(count, c.weightQuant)
	for i in 0..bits:
		if bitsAt(rev, i, 1) == 1: w[(127 - i) >> 5] |= 1 << ((127 - i) & 31)
	if c.dual: putBits(w, 128 - bits - 2, 2, 3)
	w
