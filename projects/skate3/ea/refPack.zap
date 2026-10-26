# RefPack, EA's LZ77 compression (also called QFS): an optional header (a flags byte, 0xFB, the
# decoded size in 3 or 4 bytes, the packed size when flag 0x01 is set), then commands that copy
# literal bytes from the stream and runs from the output already written:
#
#   0ddrrrll dddddddd              ll literals, then a run of rrr+3 from distance ddd..+1
#   10rrrrrr lldddddd dddddddd     ll literals, a run of rrrrrr+4, distance (14 bits)+1
#   110drrll dd.. dd.. rrrrrrrr    ll literals, a run of rr..+5, distance (17 bits)+1
#   111lllll                       (lllll+1)*4 literals
#   111111ll                       ll literals and the end
#
# The output's size is known before (the header's, or the archive's).

# The bytes `packed` decodes to, `size` of them, or why it cannot. With `hasHeader` the
# stream starts with the RefPack header (its size must agree when `size` is not -1).
pub fn unpackRefPack(packed u8[], size i64, hasHeader bool = true) u8[] ? str:
	at = 0
	expected = size
	if hasHeader:
		if packed.len < 5 or packed[1] != 0xFB: return "not a RefPack stream"
		flags = i64(packed[0])
		wide = (flags & 0x80) != 0
		width = 4 if wide else 3
		declared = 0
		for i in 0..width:
			declared = declared << 8 | packed[2 + i]
		at = 2 + width
		if (flags & 0x01) != 0:
			at += width
		if expected < 0:
			expected = declared
		elif declared != expected:
			return "RefPack header says {declared} bytes, {expected} expected"
	zero u8 = 0
	out = fill(expected, zero)
	o = 0
	n = packed.len
	while at < n:
		b0 = i64(packed[at])
		literals = 0
		run = 0
		distance = 0
		last = false
		if b0 < 0x80:
			if at + 2 > n: return "RefPack stream cut short"
			b1 = i64(packed[at + 1])
			at += 2
			literals = b0 & 3
			run = b0.bits(2, 3) + 3
			distance = (b0 & 0x60) << 3 | b1
			distance += 1
		elif b0 < 0xC0:
			if at + 3 > n: return "RefPack stream cut short"
			b1 = i64(packed[at + 1])
			b2 = i64(packed[at + 2])
			at += 3
			literals = b1 >> 6
			run = (b0 & 0x3F) + 4
			distance = (b1 & 0x3F) << 8 | b2
			distance += 1
		elif b0 < 0xE0:
			if at + 4 > n: return "RefPack stream cut short"
			b1 = i64(packed[at + 1])
			b2 = i64(packed[at + 2])
			b3 = i64(packed[at + 3])
			at += 4
			literals = b0 & 3
			run = ((b0 & 0x0C) << 6) + b3 + 5
			distance = (b0 & 0x10) << 12 | b1 << 8 | b2
			distance += 1
		elif b0 < 0xFC:
			at += 1
			literals = ((b0 & 0x1F) << 2) + 4
		else:
			at += 1
			literals = b0 & 3
			last = true
		if at + literals > n or o + literals + run > expected:
			return "RefPack stream runs past its {expected} bytes"
		for i in 0..literals:
			out[o + i] = packed[at + i]
		at += literals
		o += literals
		if run > 0:
			if distance > o: return "RefPack run reaches before the output's start"
			from = o - distance
			loop run:
				out[o] = out[from]
				o += 1
				from += 1
		if last or o == expected: break
	if o != expected: return "RefPack stream gave {o} of {expected} bytes"
	out
