# NSO0, an executable of the ExeFS: a 0x100-byte header (flags: segments compressed with LZ4;
# for .text, .rodata and .data their place in the file, in memory and size; the module's build
# id at 0x40; each segment's compressed size at 0x60), then the segments. switchbrew.org/wiki/NSO.

import lz4

pub type Segment:
	fileAt i64
	memoryAt i64
	size i64
	stored i64   # its size in the file

pub type Nso:
	buildId str   # the first 20 bytes of the module id, as hex
	segments Segment[]
	bss i64

# The NSO's header, or none when it is no NSO.
pub fn readNso(file u8[]) Nso?:
	if file.len < 0x100 or not file.startsWith("NSO0"): return none
	segments = []
	for i in 0..3:
		h = 0x10 + i * 0x10
		segments.push(
			Segment(
				fileAt = file.u32le(h),
				memoryAt = file.u32le(h + 4),
				size = file.u32le(h + 8),
				stored = file.u32le(0x60 + i * 4)
			)
		)
	id = file[0x40..0x54].map("{it:02x}").join("")
	Nso(buildId = id, segments, bss = file.u32le(0x3C))

# The same NSO with its segments stored whole: flags of compression cleared, each segment where
# it lies in memory past the header, its stored size its size. Why not, when a segment is damaged.
pub fn decompressNso(file u8[]) u8[] ? str:
	nso = readNso(file) ?? return "not an NSO"
	flags = i64(file.u32le(0x0C))
	out = file[..0x100].copy()
	out.setU32le(0x0C, flags & ~7)
	for i, s in nso.segments:
		raw = file[s.fileAt..s.fileAt + s.stored].copy()
		compressed = (flags >> i) & 1 != 0
		body = (lz4.decodeBlock(raw, s.size) ?? return "segment {i}: {error}") if compressed
			else raw
		at = 0x100 + s.memoryAt
		while out.len < at:
			out.push(0)
		out.setU32le(0x10 + i * 0x10, u32(at))
		out.setU32le(0x60 + i * 4, u32(s.size))
		out.extend(body)
	out
