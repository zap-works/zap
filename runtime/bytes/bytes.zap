# Raw bytes, as methods of a u8[]: numbers read at an offset in either byte order
# (d.u32le(at), d.i16be(at)...), written in place (d.setU32le(at, v)), appended to a buffer (out.pushU32le(v), out.pushF64be(x)...), a
# tag compared (d.startsWith("RIFF"), d.matchesAt(at, "WAVE")), a NUL-ended name read (d.cStringAt(at)), every byte
# mapped through a table (xs.translate(table)), a packed file's parts (PackedParts.pack,
# d.unpack), a cursor that walks a buffer (Reader(d = data)) and one that walks its bits
# (BitReader(d = data)). The little-endian unsigned numbers of a u8[] (and i64le), pushU16le,
# pushU32le, matchesAt, startsWith and text are the core's (core/coreBytes.zap).

# ---------- numbers at an offset ----------

# The number of the 2, 4 or 8 bytes at `at`, little-endian (le) or big-endian (be), as the type
# its name says: u16le gives a u16, i32be an i32 (f16le the f32 of a half float). One load, its
# bytes swapped for big-endian. Bytes past the end stop the program (a Reader gives 0 instead).
# The unsigned ones are a u8[N]'s too.
pub fn listU16be(b u8[], at i64) u16:
	b.u16le(at).byteSwap()

pub fn listU32be(b u8[], at i64) u32:
	b.u32le(at).byteSwap()

pub fn listU64be(b u8[], at i64) u64:
	b.u64le(at).byteSwap()

pub fn arrayU16le<N n64>(b u8[N], at i64) u16:
	u16.wrap(__ld16(__bytesAt(b, at, 2)))

pub fn arrayU16be<N n64>(b u8[N], at i64) u16:
	b.u16le(at).byteSwap()

pub fn arrayU32le<N n64>(b u8[N], at i64) u32:
	u32.wrap(__ld32(__bytesAt(b, at, 4)))

pub fn arrayU32be<N n64>(b u8[N], at i64) u32:
	b.u32le(at).byteSwap()

pub fn arrayU64le<N n64>(b u8[N], at i64) u64:
	u64.wrap(__ld64(__bytesAt(b, at, 8)))

pub fn arrayU64be<N n64>(b u8[N], at i64) u64:
	b.u64le(at).byteSwap()

# ---------- numbers written in place ----------

# v as the 2, 4 or 8 bytes at `at`, little-endian (le) or big-endian (be): one store. Bytes past
# the end stop the program. A u8[N]'s too.
pub fn listSetU16be(mut b u8[], at i64, v u16):
	b.setU16le(at, v.byteSwap())

pub fn listSetU32be(mut b u8[], at i64, v u32):
	b.setU32le(at, v.byteSwap())

pub fn listSetU64be(mut b u8[], at i64, v u64):
	b.setU64le(at, v.byteSwap())

pub fn arraySetU16le<N n64>(mut b u8[N], at i64, v u16):
	__st16(__bytesAt(b, at, 2), i64(v))

pub fn arraySetU16be<N n64>(mut b u8[N], at i64, v u16):
	b.setU16le(at, v.byteSwap())

pub fn arraySetU32le<N n64>(mut b u8[N], at i64, v u32):
	__st32(__bytesAt(b, at, 4), i64(v))

pub fn arraySetU32be<N n64>(mut b u8[N], at i64, v u32):
	b.setU32le(at, v.byteSwap())

pub fn arraySetU64le<N n64>(mut b u8[N], at i64, v u64):
	__st64(__bytesAt(b, at, 8), i64.wrap(v))

pub fn arraySetU64be<N n64>(mut b u8[N], at i64, v u64):
	b.setU64le(at, v.byteSwap())

pub fn listI16le(b u8[], at i64) i16:
	i16.wrap(b.u16le(at))

pub fn listI16be(b u8[], at i64) i16:
	i16.wrap(b.u16be(at))

pub fn listI32le(b u8[], at i64) i32:
	i32.wrap(b.u32le(at))

pub fn listI32be(b u8[], at i64) i32:
	i32.wrap(b.u32be(at))

pub fn listI64be(b u8[], at i64) i64:
	i64.wrap(b.u64be(at))

# the f32 of the half float (IEEE binary16) of the 2 bytes at `at`, as a file stores one
pub fn listF16le(b u8[], at i64) f32:
	halfValue(u32(b.u16le(at)))

pub fn listF16be(b u8[], at i64) f32:
	halfValue(u32(b.u16be(at)))

pub fn listF32le(b u8[], at i64) f32:
	f32.fromBits(b.u32le(at))

pub fn listF32be(b u8[], at i64) f32:
	f32.fromBits(b.u32be(at))

pub fn listF64le(b u8[], at i64) f64:
	f64.fromBits(b.u64le(at))

pub fn listF64be(b u8[], at i64) f64:
	f64.fromBits(b.u64be(at))

# ---------- numbers appended to a buffer ----------

# The low 2, 4 or 8 bytes of v at the end of out, little-endian (le) or big-endian (be); a
# signed and an unsigned number of one width push the same bytes.
fn pushBe(mut out u8[], v i64, n i64):
	for k in 0..n:
		out.push(u8(v >> (8 * (n - 1 - k)) & 255))

pub fn listPushU16be(mut out u8[], v i64):
	pushBe(out, v, 2)

pub fn listPushU32be(mut out u8[], v i64):
	pushBe(out, v, 4)

pub fn listPushU64le(mut out u8[], v i64):
	pushLe(out, u64.wrap(v), 8)

pub fn listPushU64be(mut out u8[], v i64):
	pushBe(out, v, 8)

pub fn listPushI16le(mut out u8[], v i64):
	pushLe(out, u64.wrap(v), 2)

pub fn listPushI16be(mut out u8[], v i64):
	pushBe(out, v, 2)

pub fn listPushI32le(mut out u8[], v i64):
	pushLe(out, u64.wrap(v), 4)

pub fn listPushI32be(mut out u8[], v i64):
	pushBe(out, v, 4)

pub fn listPushI64le(mut out u8[], v i64):
	pushLe(out, u64.wrap(v), 8)

pub fn listPushI64be(mut out u8[], v i64):
	pushBe(out, v, 8)

# the IEEE bits of x at the end of out
pub fn listPushF32le(mut out u8[], x f32):
	pushLe(out, u64(x.toBits()), 4)

pub fn listPushF32be(mut out u8[], x f32):
	pushBe(out, x.toBits(), 4)

pub fn listPushF64le(mut out u8[], x f64):
	pushLe(out, x.toBits(), 8)

pub fn listPushF64be(mut out u8[], x f64):
	pushBe(out, i64.wrap(x.toBits()), 8)

# v at the end of out in as few bytes as it needs (a varint): seven bits a byte, the low ones
# first, its sign folded into the lowest bit, so a small number, negative or not, takes one byte
pub fn listPushVarint(mut out u8[], v i64):
	z = u64((v << 1) ^ (v >> 63))
	while z >= 128:
		out.push(u8(z & 127 | 128))
		z >>= 7
	out.push(u8(z))

# ---------- tags and names ----------

# the text at `at` up to its NUL, the end of the bytes or `limit` bytes, whichever comes first
pub fn listCStringAt(b u8[], at i64, limit i64 = 4096) str:
	if at < 0 or at >= b.len: return ""
	end = b.len.min(at + limit.clamp(0, b.len))
	out = []
	i = at
	while i < end and b[i] != 0:
		out.push(b[i])
		i += 1
	str(move out)

# ---------- packed files ----------

# A buffer a program writes for itself (a prepared level, a cache): a 4-byte magic, a version,
# the head's length, then the head and the body. Reading it back gives where the head and the
# body lie, none when the magic or the version is another program's or an older one's.

# where a packed buffer's head and body lie: slice the buffer with them (nothing is copied)
pub type PackedParts:
	headAt i64
	bodyAt i64
	end i64

# PackedParts.pack(magic, version, head, body): head and body behind a magic (4 bytes:
# "ZNRK"), a version and the head's length
pub fn packedPartsPack(magic str, version i64, head u8[], body u8[]) u8[]:
	out u8[] = []
	out.reserve(16 + head.len + body.len)
	out.extend(magic.bytes())
	out.pushU32le(version)
	out.pushU64le(head.len)
	out.extend(head)
	out.extend(body)
	out

# where the head and the body of a packed buffer lie, none when it is not one of this magic and
# version (or is cut short)
pub fn listUnpack(d u8[], magic str, version i64) PackedParts?:
	if d.len < 16 or not d.startsWith(magic) or d.u32le(4) != version: return none
	n = d.i64le(8)
	if n < 0 or 16 + n > d.len: return none
	PackedParts(headAt = 16, bodyAt = 16 + n, end = d.len)

# ---------- a cursor ----------

# A cursor over the window [at, end) of bytes (`end` past the bytes: up to their end),
# little-endian unless `big`: each read takes the next bytes. A read past the window's end (or
# before the start, `at` below 0) gives 0 and sets `short` instead of stopping, so a parser checks
# once per record: no read stops the program.
pub type Reader:
	d ref u8[]
	at i64 = 0
	end i64 = 9_223_372_036_854_775_807
	big bool = false
	short bool = false

	# whether n more bytes are in the window; when not, the cursor goes to its end and notes it
	mut fn has(n i64) bool:
		stop = end.min(d.len)
		if at < 0 or n < 0 or n > stop - at:
			short = true
			at = stop
			return false
		true

	# each read gives the type of its name
	mut fn u8() u8:
		if not has(1): return 0
		at += 1
		d[at - 1]

	mut fn u16() u16:
		u16.wrap(takeNumber(2))

	mut fn u32() u32:
		u32.wrap(takeNumber(4))

	mut fn u64() u64:
		takeNumber(8)

	# the next n bytes (2, 4 or 8) as a number in the reader's byte order, 0 past the end
	mut fn takeNumber(n i64) u64:
		if not has(n): return 0
		v u64 = 0
		for k in 0..n:
			b = u64(d[at + (k if big else n - 1 - k)])
			v = v << 8 | b
		at += n
		v

	mut fn i8() i8:
		i8.wrap(u8())

	mut fn i16() i16:
		i16.wrap(u16())

	mut fn i32() i32:
		i32.wrap(u32())

	mut fn i64() i64:
		i64.wrap(u64())

	mut fn f32() f32:
		f32.fromBits(u32())

	mut fn f64() f64:
		f64.fromBits(u64())

	# a number pushVarint wrote
	mut fn varint() i64:
		if at >= 0 and at < end and at < d.len and d[at] < 128:   # (one byte: most of them)
			b = i64(d[at])
			at += 1
			return (b >> 1) ^ -(b & 1)
		z u64 = 0
		shift = 0
		while shift < 64 and has(1):
			b = u64(d[at])
			at += 1
			z |= (b & 127) << shift
			if b < 128: return i64(z >> 1) ^ -i64(z & 1)
			shift += 7
		short = true
		0

	# the next n bytes, as a list of their own
	mut fn bytes(n i64) u8[]:
		if not has(n): return []
		at += n
		d[at - n..at].copy()

	# a field of n bytes holding text ended by a NUL: its bytes before the NUL (u8[].cStringAt gives
	# such a text as a str)
	mut fn cStringBytes(n i64) u8[]:
		if not has(n): return []
		out = []
		for i in at..at + n:
			if d[i] == 0: break
			out.push(d[i])
		at += n
		out

	# The next u32 as a count of records of at least bytesEach bytes (a count read from a file's
	# header, never trusted): 0, with `short` set and the cursor at the end, when that many records
	# would pass the bytes left. Loops and reservations by it stay within the bytes there.
	mut fn recordCount(bytesEach i64) i64:
		n = i64(u32())
		if short or n == 0: return 0
		if n > (end.min(d.len) - at) / bytesEach.max(1):
			short = true
			at = end.min(d.len)
			return 0
		n

	# The next n numbers of zero's type as one copy of their bytes, as the machine keeps them
	# (little-endian): what T.fromBytes(r) reads a list of numbers with
	mut fn numbers<T Num>(n i64, zero T) T[]:
		out = fill(n, zero)
		size = n * __stride(zero)
		if n <= 0 or not has(size): return []
		__memcpy(__ld64(__addr(out)), __ld64(hdr(d)) + at, size)
		at += size
		out

	# passes over n bytes: where they start
	mut fn skip(n i64) i64:
		from = at
		if has(n):
			at += n
		from

	# two, three or four f32 (T.fromBytes(r) of the vector type)
	mut fn vec2() Vec2:
		x = f32()
		Vec2(x, f32())

	mut fn vec3() Vec3:
		xy = vec2()
		Vec3(xy.x, xy.y, f32())

	mut fn vec4() Vec4:
		xyz = vec3()
		xyz.withW(f32())

	# a text of a u32 length then that many bytes, "" past the end
	mut fn sized() str:
		n = u32()
		if not has(n): return ""
		at += n
		str(d[at - n..at])

# ---------- foreign memory ----------
# The copies, loads and stores behind std/win's MemoryView, which checks the bounds before each,
# and std/vmem's Window, which keeps each address inside its reservation.

fn copyToAddress<T>(to i64, values T[]):
	__memcpy(to, __ld64(hdr(values)), listByteSize(values))

fn copyFromAddress<T>(mut into T[], from i64):
	__memcpy(__ld64(hdr(into)), from, listByteSize(into))

fn copyBetweenAddresses(to i64, from i64, n i64):
	__memcpy(to, from, n)

fn wordAtAddress(at i64) i64:
	__ld64(at)

fn u8AtAddress(at i64) u8:
	u8.wrap(__ld8(at))

fn u16AtAddress(at i64) u16:
	u16.wrap(__ld16(at))

fn u32AtAddress(at i64) u32:
	u32.wrap(__ld32(at))

fn u64AtAddress(at i64) u64:
	u64.wrap(__ld64(at))

fn setU8AtAddress(at i64, v u8):
	__st8(at, i64(v))

fn setU16AtAddress(at i64, v u16):
	__st16(at, i64(v))

fn setU32AtAddress(at i64, v u32):
	__st32(at, i64(v))

fn setU64AtAddress(at i64, v u64):
	__st64(at, i64.wrap(v))

# ---------- tables ----------

# every byte b replaced by table[b], in place (a table of 256 entries: a complement, a case
# change, a classification)
pub fn listTranslate(mut xs u8[], table u8[]):
	if table.len < 256:
		fail("translate needs a table of 256 bytes, got {table.len}")
	for i in 0..xs.len:
		xs[i] = table[xs[i]]

# source.translationTable(target): the table that maps each byte of source to the byte at the
# same place in target, every other byte to itself
pub fn strTranslationTable(source str, target str) u8[]:
	table u8[] = (0..256).map(u8(it))
	for i in 0..source.len.min(target.len):
		table[source[i]] = target[i]
	table

# ---------- a cursor over bits ----------

# A cursor over the bits of bytes, a byte's lowest bit first (deflate, Vorbis) or its highest
# (`high`: MP3, JPEG), through a 64-bit buffer refilled a byte at a time. Past the data it is
# refilled with zeros, counted: reading them gives 0 and sets `short` instead of stopping, so a
# decoder under `use noStops` reads through it.
pub type BitReader:
	d ref u8[]
	at n64 = 0   # the next byte to put in the buffer
	high bool = false   # a byte's highest bit is its first
	short bool = false
	buffer u64 = 0   # the next bits: the first lowest, or highest when high
	count i64 in 0..=64 = 0   # bits in the buffer
	over i64 in 0..=8 = 0   # of its bytes those past the data's end, the last

	# the buffer filled to more than 56 bits
	mut fn refill():
		loop:
			c = count
			if c > 56: return
			a = at
			byte u64 = 0
			if a < d.len:
				byte = u64(d[a])
				at = a + 1
			else:
				over = (over + 1).min(8)
			buffer |= byte << u64(56 - c) if high else byte << u64(c)
			count = c + 8

	# the next n bits (up to 32) as take gives them, without taking them; past the data, zeros
	mut fn peek(n0 i64) Taken:
		n = n0.clamp(1, 32)
		if count < n: refill()
		next = buffer >> u64(64 - n) if high else buffer
		i64.wrap(next) & ((1 << n) - 1)

	# the next n bits (up to 32) as a number, the first its highest (high) or its lowest
	mut fn take(n0 i64) Taken:
		if n0 <= 0: return 0
		n = n0.min(32)
		v = peek(n)
		skip(n)
		0 if short else v

	# the next n bits (up to 32) passed over
	mut fn skip(n0 i64):
		n = n0.clamp(0, 32)
		if count < n: refill()
		c = count
		if n > c - over * 8:
			short = true
			return
		buffer = buffer << u64(n) if high else buffer >> u64(n)
		count = (c - n).max(0)

	# the bits left of the byte begun dropped and the buffer's whole bytes given back: the index of
	# the next byte to read whole, where at then is
	mut fn byteAligned() n64:
		skip(count & 7)
		back = count / 8 - over   # (none past the data's end)
		start = at - back if back > 0 else at
		buffer = 0
		count = 0
		over = 0
		if start < 0:
			short = true
			return at
		at = start
		at

# a value of up to 32 bits
pub type Taken = i64 in 0..=4_294_967_295
