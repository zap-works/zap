# ASTC's integer sequence encoding: a run of values of one range stored as plain bits, or, for
# ranges of 3 * 2^n or 5 * 2^n levels, with the high part packed as trits (5 in 8 bits) or quints
# (3 in 7 bits) among the low bits. Weights and color endpoints are such runs; the unquantizers
# turn a stored value into a 0..64 weight or a 0..255 endpoint value.

# the 21 ranges in order (2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 24, 32, 40, 48, 64, 80, 96, 128,
# 160, 192, 256 levels): the plain low bits of each and whether the rest is a trit (1) or quint (2)
quantBits = [1, 0, 2, 0, 1, 3, 1, 2, 4, 2, 3, 5, 3, 4, 6, 4, 5, 7, 5, 6, 8]
quantKind = [0, 1, 0, 2, 1, 0, 2, 1, 0, 2, 1, 0, 2, 1, 0, 2, 1, 0, 2, 1, 0]

# the bits that follow each of a group's low-bit fields: a trit group is five values with the
# 8 bits of T cut 2, 2, 1, 2, 1; a quint group three values with the 7 bits of Q cut 3, 2, 2
tritChunks = [2, 2, 1, 2, 1]
quintChunks = [3, 2, 2]

# n bits of the block from bit `at`, low bit first; bits past the block read as 0
fn bitsAt(w i64[4], at i64, n i64):
	if n == 0 or at >= 128: return 0
	word = at >> 5
	shift = at & 31
	v = w[word] >> shift
	if shift + n > 32 and word < 3: v |= w[word + 1] << (32 - shift)
	v & ((1 << n) - 1)

# the bits taken by `count` values of range `q`
pub fn sequenceBits(count i64, q i64) i64:
	extra = match quantKind[q]:
		1: (8 * count + 4) / 5
		2: (7 * count + 2) / 3
		_: 0
	count * quantBits[q] + extra

# `count` values of range `q` read from bit `start`; value = (trit or quint) * 2^bits + low bits
pub fn readSequence(w i64[4], start i64, count i64, q i64, mut out i64[96]):
	n = quantBits[q]
	kind = quantKind[q]
	at = start
	if kind == 0:
		for i in 0..count:
			out[i] = bitsAt(w, at, n)
			at += n
		return
	size = 5 if kind == 1 else 3
	chunks = tritChunks if kind == 1 else quintChunks
	first = 0
	while first < count:
		low i64[5]
		packed = 0
		packedBits = 0
		taken = (count - first).min(size)
		for j in 0..taken:
			low[j] = bitsAt(w, at, n)
			at += n
			packed |= bitsAt(w, at, chunks[j]) << packedBits
			at += chunks[j]
			packedBits += chunks[j]
		high i64[5]
		if kind == 1: unpackTrits(packed, high)
		else: unpackQuints(packed, high)
		for j in 0..taken:
			out[first + j] = (high[j] << n) | low[j]
		first += taken

# the five trits in the 8 bits T
fn unpackTrits(t i64, mut out i64[5]):
	c = 0
	if (t >> 2) & 7 == 7:
		c = ((t >> 5) << 2) | (t & 3)
		out[4] = 2
		out[3] = 2
	else:
		c = t & 31
		if (t >> 5) & 3 == 3:
			out[4] = 2
			out[3] = t >> 7
		else:
			out[4] = t >> 7
			out[3] = (t >> 5) & 3
	if c & 3 == 3:
		out[2] = 2
		out[1] = c >> 4
		out[0] = (((c >> 3) & 1) << 1) | (((c >> 2) & 1) & ((~(c >> 3)) & 1))
	elif (c >> 2) & 3 == 3:
		out[2] = 2
		out[1] = 2
		out[0] = c & 3
	else:
		out[2] = c >> 4
		out[1] = (c >> 2) & 3
		out[0] = c & 3

# the three quints in the 7 bits Q
fn unpackQuints(q i64, mut out i64[5]):
	if (q >> 1) & 3 == 3 and (q >> 5) & 3 == 0:
		out[2] = ((q & 1) << 2) | ((((q >> 4) & 1) & (~q & 1)) << 1) | (((q >> 3) & 1) & (~q & 1))
		out[1] = 4
		out[0] = 4
		return
	c = 0
	if (q >> 1) & 3 == 3:
		out[2] = 4
		c = (((q >> 3) & 3) << 3) | (((~(q >> 5)) & 3) << 1) | (q & 1)
	else:
		out[2] = (q >> 5) & 3
		c = q & 31
	if c & 7 == 5:
		out[1] = 4
		out[0] = c >> 3
	else:
		out[1] = c >> 3
		out[0] = c & 7

# What each trit or quint range adds to the unquantized value, from the spec's table: C scales the
# trit or quint, and a low-bit field (b to f, the bits above the lowest) lands in B at the places
# its mask has set. Indexed like quantBits; the weights have their own scales and masks, of which
# only the ranges up to 32 levels are used.
colorScale = [0, 0, 0, 0, 204, 0, 113, 93, 0, 54, 44, 0, 26, 22, 0, 13, 11, 0, 6, 5, 0]
weightScale = [0, 0, 0, 0, 50, 0, 28, 23, 0, 13, 11, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0]
fieldMasks = [
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	278, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	268, 0, 0, 0, 0,
	133, 266, 0, 0, 0,
	0, 0, 0, 0, 0,
	130, 261, 0, 0, 0,
	65, 130, 260, 0, 0,
	0, 0, 0, 0, 0,
	64, 129, 258, 0, 0,
	32, 64, 129, 258, 0,
	0, 0, 0, 0, 0,
	32, 64, 128, 257, 0,
	16, 32, 64, 128, 257
]

weightMasks = [
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	69, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	66, 0, 0, 0, 0,
	33, 66, 0, 0, 0
]

# the values of a range that is only a trit (1) or a quint (2)
weightLevels = [[0], [0, 32, 63], [0, 16, 32, 47, 63]]
colorLevels = [[0], [0, 128, 255], [0, 64, 128, 191, 255]]

# the value of `v` bits `n` repeated down to `width` bits
fn replicate(v i64, n i64, width i64):
	r = 0
	shift = width - n
	while shift > -n:
		r |= (v << shift) if shift >= 0 else (v >> -shift)
		shift -= n
	r

# A stored value of range `q` as an endpoint value 0..255, or with `weight` as a weight 0..64.
pub fn unquantize(v i64, q i64, weight bool) i64:
	n = quantBits[q]
	kind = quantKind[q]
	width = 6 if weight else 8
	if kind == 0: return fixWeight(replicate(v, n, width), weight)
	d = v >> n
	if n == 0:
		if weight: return fixWeight(weightLevels[kind][d], true)
		return colorLevels[kind][d]
	low = v & ((1 << n) - 1)
	b = 0
	masks = weightMasks if weight else fieldMasks
	for k in 1..n:
		b += ((low >> k) & 1) * masks[q * 5 + k - 1]
	a = low & 1
	if weight:
		t = (d * weightScale[q] + b) ^ (a * 127)
		return fixWeight((a * 32) | (t >> 2), true)
	t = (d * colorScale[q] + b) ^ (a * 511)
	(a * 128) | (t >> 2)

fn fixWeight(w i64, weight bool):
	w + 1 if weight and w > 32 else w
