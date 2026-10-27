# Sets of code points as sorted ranges [lo0, hi0, lo1, hi1, ...] that do not touch, and the UTF-8
# that writes them: a text is matched byte by byte, so a character set becomes the byte ranges of
# its encodings (utf8Sequences).

maxCode = 0x10_FFFF

# whether the code point is in the ranges
fn hasCode(ranges i64[], code i64):
	lo = 0
	hi = ranges.len / 2 - 1
	while lo <= hi:
		mid = (lo + hi) / 2
		if code < ranges[2 * mid]:
			hi = mid - 1
		elif code > ranges[2 * mid + 1]:
			lo = mid + 1
		else:
			return true
	false

# the two sets of ranges as one
fn unionRanges(a i64[], b i64[]):
	out i64[] = []
	i = 0
	j = 0
	while i < a.len or j < b.len:
		fromA = j >= b.len or (i < a.len and a[i] <= b[j])
		lo = a[i] if fromA else b[j]
		hi = a[i + 1] if fromA else b[j + 1]
		if fromA:
			i += 2
		else:
			j += 2
		if not out.isEmpty and lo <= out[len - 1] + 1:
			if hi > out[len - 1]: out[len - 1] = hi
		else:
			out.push(lo)
			out.push(hi)
	out

# every code point that is not in the ranges and is not a surrogate (which no UTF-8 writes)
fn invertRanges(ranges i64[]):
	surrogates = [0xD800, 0xDFFF]
	all = unionRanges(ranges, surrogates)
	out = []
	next = 0
	for k in 0..all.len / 2:
		if all[2 * k] > next:
			out.push(next)
			out.push(all[2 * k] - 1)
		next = all[2 * k + 1] + 1
	if next <= maxCode:
		out.push(next)
		out.push(maxCode)
	out

# the ranges without their surrogates
fn withoutSurrogates(ranges i64[]):
	invertRanges(invertRanges(ranges))

# the ranges cut at the code point `limit`
fn clippedRanges(ranges i64[], limit i64):
	out = []
	for k in 0..ranges.len / 2:
		if ranges[2 * k] <= limit:
			out.push(ranges[2 * k])
			out.push(ranges[2 * k + 1].min(limit))
	out

# The ranges with, for each character, the other characters that `(?i)` takes for it (only the
# ASCII ones for each other under the flag `a`).
fn foldedRanges(ranges i64[], asciiOnly bool):
	out = ranges.copy()
	at = 0
	while at < foldGroups.len:
		size = foldGroups[at]
		hit = false
		for k in at + 1..at + 1 + size:
			if (not asciiOnly or foldGroups[k] < 0x80) and hasCode(ranges, foldGroups[k]):
				hit = true
		if hit:
			for k in at + 1..at + 1 + size:
				if not asciiOnly or foldGroups[k] < 0x80:
					out = unionRanges(out, [foldGroups[k], foldGroups[k]])
		at += size + 1
	out

# the UTF-8 sequence of a code point
fn utf8Of(code i64):
	if code < 0x80: return [u8(code)]
	if code < 0x800: return [0xC0 | (code >> 6), 0x80 | (code & 63)]
	if code < 0x1_0000: return [0xE0 | (code >> 12), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63)]
	[
		u8(0xF0 | (code >> 18)),
		0x80 | ((code >> 12) & 63),
		0x80 | ((code >> 6) & 63),
		0x80 | (code & 63)
	]

# The code point the UTF-8 character at `at` stands for, with its length in bytes above bit 24; a byte
# that does not begin a well-formed character stands for itself.
fn utf8At(bytes u8[], at i64):
	b = i64(bytes[at])
	n = 1
	code = b
	if b >= 0xF0 and b < 0xF8:
		n = 4
		code = b & 7
	elif b >= 0xE0:
		n = 3
		code = b & 15
	elif b >= 0xC0:
		n = 2
		code = b & 31
	if n == 1 or at + n > bytes.len: return (1 << 24) | b
	for k in 1..n:
		c = i64(bytes[at + k])
		if (c & 0xC0) != 0x80: return (1 << 24) | b
		code = (code << 6) | (c & 63)
	(n << 24) | code

# The byte ranges that write the code points between lo and hi, appended to `out` as
# sequences of (length, then a low and a high byte for each position); lo and hi are not surrogates.
fn utf8Sequences(lo i64, hi i64, mut out i64[]):
	for bound in [0x7F, 0x7FF, 0xFFFF]:
		if lo <= bound and hi > bound:
			utf8Sequences(lo, bound, out)
			utf8Sequences(bound + 1, hi, out)
			return
	n = 1 if hi < 0x80 else 2 if hi < 0x800 else 3 if hi < 0x1_0000 else 4
	for i in 1..n:
		shift = 6 * i
		mask = (1 << shift) - 1
		if (lo >> shift) != (hi >> shift):
			if (lo & mask) != 0:
				utf8Sequences(lo, lo | mask, out)
				utf8Sequences((lo | mask) + 1, hi, out)
				return
			if (hi & mask) != mask:
				utf8Sequences(lo, ((hi >> shift) << shift) - 1, out)
				utf8Sequences((hi >> shift) << shift, hi, out)
				return
	first = utf8Of(lo)
	last = utf8Of(hi)
	out.push(n)
	for k in 0..n:
		out.push(first[k])
		out.push(last[k])

# whether the code point is one a word's edge is judged by: `\w`'s, or ASCII's alone under the flag `a`
fn isWordCode(code i64, asciiOnly bool):
	if code < 0x80: return isWordByte(code)
	not asciiOnly and hasCode(wordRanges, code)

# whether the character that begins at `pos` is a word character
fn wordAt(bytes u8[], pos i64, asciiOnly bool):
	packed = utf8At(bytes, pos)
	if (packed >> 24) == 1 and bytes[pos] >= 0x80: return false
	isWordCode(packed & 0xFF_FFFF, asciiOnly)

# whether the character that ends at `pos` is a word character
fn wordBefore(bytes u8[], pos i64, asciiOnly bool):
	start = pos - 1
	while start > 0 and pos - start < 4 and (bytes[start] & 0xC0) == 0x80:
		start -= 1
	packed = utf8At(bytes, start)
	if start + (packed >> 24) != pos: return false
	isWordCode(packed & 0xFF_FFFF, asciiOnly)
