# MIO0, the compression of the game's data on the cartridge: a header ("MIO0", the size made,
# where the copies' words start, where the literal bytes start), then a stream of flag bits read
# 32 at a time from offset 16, most significant first. A 1 takes the next literal byte; a 0 takes
# the next 16-bit word: its top 4 bits plus 3 bytes copied from its low 12 bits plus 1 back.

# the bytes a MIO0 block makes, or why it cannot
pub fn decodeMio0(b u8[]) u8[] ? str:
	if b.len < 16 or not b.startsWith("MIO0"): return "not a MIO0 block"
	size = i64(b.u32be(4))
	copies = i64(b.u32be(8))
	literals = i64(b.u32be(12))
	# a flag bit and a 2-byte word make at most 18 bytes: no block makes 9 times its own size
	if size > b.len * 9: return "a MIO0 block of {b.len} bytes cannot make {size}"
	out u8[] = []
	out.reserve(size)
	flags = 16
	word = 0
	bitsLeft = 0
	while out.len < size:
		if bitsLeft == 0:
			if flags + 4 > b.len: return "the MIO0 flags run past the end"
			word = b.u32be(flags)
			flags += 4
			bitsLeft = 32
		bitsLeft -= 1
		if word.bits(bitsLeft, 1) == 1:
			if literals >= b.len: return "the MIO0 literals run past the end"
			out.push(b[literals])
			literals += 1
		else:
			if copies + 2 > b.len: return "the MIO0 copies run past the end"
			if copies + 2 > b.len: return "the MIO0 copies run past the end"
			if copies + 2 > b.len: return "the MIO0 copies run past the end"
			if copies + 2 > b.len: return "the MIO0 copies run past the end"
			v = i64(b.u16be(copies))
			copies += 2
			n = (v >> 12) + 3
			back = (v & 0xFFF) + 1
			if back > out.len: return "a MIO0 copy reaches before the start"
			start = out.len - back
			for k in 0..n:
				out.push(out[start + k])
	out.truncate(size)
	out
