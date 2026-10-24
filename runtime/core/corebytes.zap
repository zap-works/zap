# The runtime's own bytes (core.zap): the little-endian numbers at an offset of a u8[] that the
# system's structures and the binary encoding are read and written with, a tag compared and the
# bytes seen as text. A u8[]'s other methods are bytes/bytes.zap's, which these keep their names
# beside.

# The number of the 2, 4 or 8 bytes at `at`, little-endian, as the type its name says (bytes.zap
# has the rest); bytes past the end stop the program.
pub fn listU16le(b u8[], at i64) u16:
	u16.wrap(__ld16(__bytesAt(b, at, 2)))

pub fn listU32le(b u8[], at i64) u32:
	u32.wrap(__ld32(__bytesAt(b, at, 4)))

pub fn listU64le(b u8[], at i64) u64:
	u64.wrap(__ld64(__bytesAt(b, at, 8)))

pub fn listI64le(b u8[], at i64) i64:
	i64.wrap(b.u64le(at))

# v as the 2, 4 or 8 bytes at `at`, little-endian: one store. Bytes past the end stop the program.
pub fn listSetU16le(mut b u8[], at i64, v u16):
	__st16(__bytesAt(b, at, 2), i64(v))

pub fn listSetU32le(mut b u8[], at i64, v u32):
	__st32(__bytesAt(b, at, 4), i64(v))

pub fn listSetU64le(mut b u8[], at i64, v u64):
	__st64(__bytesAt(b, at, 8), i64.wrap(v))

# The low 2, 4 or 8 bytes of v at the end of out, little-endian (the binary encoding's, derive.zap)
fn pushLe(mut out u8[], v u64, n i64):
	for k in 0..n:
		out.push(u8((v >> u64(8 * k)) & 255))

pub fn listPushU16le(mut out u8[], v i64):
	pushLe(out, u64.wrap(v), 2)

pub fn listPushU32le(mut out u8[], v i64):
	pushLe(out, u64.wrap(v), 4)

# whether the bytes at `at` spell `tag` ("RIFF", "OggS"); false when they run past the end
pub fn listMatchesAt(b u8[], at i64, tag str) bool:
	if at < 0 or at > b.len - tag.len: return false
	b[at..at + tag.len] == tag.bytes()

# whether the bytes begin with `tag`, a file's magic
pub fn listStartsWith(b u8[], tag str) bool:
	listMatchesAt(b, 0, tag)

# the bytes read as a text, a window over them: no copy, and it lives as long as they do
pub fn listText(b u8[]) ref str:
	w = __strof(__ld64(__addr(b)), b.len, 0)
	w
