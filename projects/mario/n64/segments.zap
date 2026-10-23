# The game's memory as its data sees it: 32 segments, each a block of bytes loaded from the
# cartridge (as they are, or decompressed from MIO0), named by addresses whose top byte is the
# segment and whose low 24 bits are the offset in it. Scripts and geo layouts may name any of the
# 32; display lists only 0..15 (the graphics chip sees 16), so their top byte is masked.

pub type Segments:
	banks u8[,]

pub fn newSegments() Segments:
	Segments(banks = fill(32, []))

# the segment of an address and its offset there
pub fn segmentOf(addr i64) i64:
	addr.bits(24, 5)

pub fn offsetOf(addr i64) i64:
	addr & 0xFF_FFFF

# the cartridge's bytes start..end put in segment `seg`, decompressed when they are MIO0
pub fn loadSegment(mut s Segments, rom Rom, seg i64, start i64, end i64, compressed bool):
	raw = rom.romSlice(start, end)
	if not compressed:
		s.banks[seg] = raw.copy()   # kept after the cartridge's bytes are let go
		return
	match decodeMio0(raw):
		made: s.banks[seg] = made
		error: fail("segment {seg} from {start}: {error}")

# whether n bytes at the address are loaded
pub fn holds(s Segments, addr i64, n i64) bool:
	seg = segmentOf(addr)
	off = offsetOf(addr)
	off + n <= s.banks[seg].len

fn bankAt(s Segments, addr i64, n i64) ref u8[]:
	if not s.holds(addr, n):
		fail("segment {segmentOf(addr)} holds {s.banks[segmentOf(addr)].len} bytes: {n} at {offsetOf(addr)} are past them")
	s.banks[segmentOf(addr)]

pub fn u8At(s Segments, addr i64) i64:
	s.bankAt(addr, 1)[offsetOf(addr)]

pub fn u16At(s Segments, addr i64) i64:
	s.bankAt(addr, 2).u16be(offsetOf(addr))

pub fn s16At(s Segments, addr i64) i64:
	s.bankAt(addr, 2).i16be(offsetOf(addr))

pub fn u32At(s Segments, addr i64) i64:
	s.bankAt(addr, 4).u32be(offsetOf(addr))

pub fn s32At(s Segments, addr i64) i64:
	s.bankAt(addr, 4).i32be(offsetOf(addr))
