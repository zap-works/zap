# The runtime's text: strings, comparison, building and number formatting (core.zap).

strShort i64 = 22

# the bytes of the str whose header is at a
fn textPtrAt(a i64) i64:
	a if __ld64(a + 16) < 0 else __ld64(a)

fn textLenAt(a i64) i64:
	room = __ld64(a + 16)
	(room >> 56) & 127 if room < 0 else __ld64(a + 8)

pub fn sPtr(s str) i64:
	textPtrAt(__addr(s))

fn sLen(s str) i64:
	textLenAt(__addr(s))

# the cap word of a short str of n bytes
fn shortRoom(n i64) i64:
	(n - 128) << 56

# a new string of n bytes (NUL-terminated for the system calls), owned: short when it fits
fn strNew(n i64) str:
	if n <= strShort: return __strof(0, 0, shortRoom(n))   # zero bytes, the NUL among them
	# the capacity is the allocated size, never 0: cap 0 means bytes that are not owned
	p = rtAllocRaw(n + 1)
	__st8(p + n, 0)
	__strof(p, n, n + 1)

pub fn strLen(s str) i64:
	sLen(s)

# a + b
pub fn strConcat(a str, b str) str:
	la = sLen(a)
	lb = sLen(b)
	r = strNew(la + lb)
	__memcpy(sPtr(r), sPtr(a), la)
	__memcpy(sPtr(r) + la, sPtr(b), lb)
	r

# a == b: two short ones by their three words (the bytes past a short one's length are zero),
# else lengths, then the first byte, then words
fn strEq(a str, b str) bool:
	ra = __ld64(__addr(a) + 16)
	rb = __ld64(__addr(b) + 16)
	if (ra & rb) < 0:
		return ra == rb and __ld64(__addr(a)) == __ld64(__addr(b)) and
			__ld64(__addr(a) + 8) == __ld64(__addr(b) + 8)
	la = sLen(a)
	if la != sLen(b): return false
	pa = sPtr(a)
	pb = sPtr(b)
	if la == 0 or pa == pb: return true
	if __ld8(pa) != __ld8(pb):
		return false   # names differ at the first byte most often
	bytesEq(pa, pb, la)

# whether the n bytes at pa and at pb agree, thirty-two at a time (the words' differences or'ed),
# then eight
fn bytesEq(pa i64, pb i64, n i64) bool:
	i i64 = 0
	while i + 32 <= n:
		a = pa + i
		b = pb + i
		if (__ld64(a) ^ __ld64(b)) | (__ld64(a + 8) ^ __ld64(b + 8)) |
			(__ld64(a + 16) ^ __ld64(b + 16)) | (__ld64(a + 24) ^ __ld64(b + 24)) != 0:
			return false
		i += 32
	while i + 8 <= n:
		if __ld64(pa + i) != __ld64(pb + i): return false
		i += 8
	while i < n:
		if __ld8(pa + i) != __ld8(pb + i): return false
		i += 1
	true

# whether the 8 bytes from p lie in p's page: reading them cannot fault, even past what p holds
fn wordInPage(p i64) bool:
	(p & 4095) <= 4088

# bytesEq with up to 8 bytes compared in one word when neither read leaves its page
fn sameBytes(p i64, q i64, length i64) bool:
	(u64(__ld64(q) ^ __ld64(p)) << ((8 - length) * 8)) == 0 if length > 0 and length <= 8 and
		wordInPage(q) and wordInPage(p)
		else bytesEq(q, p, length)

# -1, 0 or 1 by byte order
pub fn strCmp(a str, b str) i64:
	textOrderAt(__addr(a), __addr(b))

# strCmp of the strs at addresses a and b. Equal words are skipped eight bytes at a time and the
# first that differs decides, read with its first byte highest (unsigned); the last few bytes are
# one word too when neither read leaves its page, the bytes past them shifted away
fn textOrderAt(a i64, b i64) i64:
	la = textLenAt(a)
	lb = textLenAt(b)
	ua = u64.wrap(textPtrAt(a))
	ub = u64.wrap(textPtrAt(b))
	end = u64.wrap(la.min(lb))
	i u64 = 0
	while i + 8 <= end:
		x = u64.wrap(__bswap(__ld64(i64.wrap(ua + i))))
		y = u64.wrap(__bswap(__ld64(i64.wrap(ub + i))))
		if x != y: return -1 if x < y else 1
		i += 8
	if i < end:
		if wordInPage(i64.wrap(ua + i)) and wordInPage(i64.wrap(ub + i)):
			shift = (8 - (end - i)) * 8
			x = u64.wrap(__bswap(__ld64(i64.wrap(ua + i)))) >> shift
			y = u64.wrap(__bswap(__ld64(i64.wrap(ub + i)))) >> shift
			if x != y: return -1 if x < y else 1
		else:
			while i < end:
				x = __ld8(i64.wrap(ua + i))
				y = __ld8(i64.wrap(ub + i))
				if x != y: return -1 if x < y else 1
				i += 1
	-1 if la < lb else 1 if la > lb else 0

# s[start..to], a window over the bytes [start, to) of s: no copy, lives as long as s; the
# backend makes it in place, its bounds checked (irSlice)
fn strWindow(s str, start i64, to i64) ref str:
	w = __strof(sPtr(s) + start, to - start, 0)
	w

# the bytes of v's decimal digits, its sign's too
fn intWidth(v i64) i64:
	x = v if v < 0 else -v   # negative: the most negative number fits too
	digits = 1
	bound = -10   # -(10^digits)
	while x <= bound:
		digits += 1
		if digits == 19:
			break   # (10^19 is past the i64 range)
		bound *= 10
	digits + (1 if v < 0 else 0)

# v's decimal digits written in the size bytes at p (intWidth's), worked on as a negative number
fn writeInt(p i64, size i64, v i64):
	x = v if v < 0 else -v
	if v < 0:
		__st8(p, 45)
	first = p + 1 if v < 0 else p
	pairs = sPtr(digitPairs)
	at = p + size
	while at - first >= 2:
		q = x / 100
		pair = pairs + 2 * (q * 100 - x)   # written from the last two digits back
		at -= 2
		__st8(at, __ld8(pair))
		__st8(at + 1, __ld8(pair + 1))
		x = q
	if at > first:
		__st8(first, 48 - x)

# the two digits of each number below 100
digitPairs = "00010203040506070809101112131415161718192021222324252627282930313233343536373839404142434445464748495051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899"

# appends the decimal digits of v
fn pushInt(mut out u8[], v i64):
	l = __addr(out)
	n = __ld64(l + 8)
	size = intWidth(v)
	textGrow(l, n + size)
	writeInt(__ld64(l) + n, size, v)
	__st64(l + 8, n + size)

# A str built in one block (string interpolation): the bytes reserved for the expected length,
# the parts written in place (numbers formatted straight into it), then the block is the str.
fn strBuildStart(cap i64) u8[]:
	out u8[] = []
	listGrowRaw(__addr(out), cap, 1)
	out

# strBuildStart on the size bytes at buf, a buffer in the caller's frame: its room is -size (owned
# by no one), and the text moves to a block only when it outgrows it (textGrow)
fn strBuildIn(buf i64, size i64) u8[]:
	out u8[] = []
	__st64(__addr(out), buf)
	__st64(__addr(out) + 16, -size)
	out

# room for need bytes in the text being built at l
fn textGrow(l i64, need i64):
	room = __ld64(l + 16)
	if room < 0:
		if need <= -room: return
		__st64(l + 16, 0)   # out of the frame's buffer: the bytes copied to a block of their own
	listGrowRaw(l, need, 1)

# interpolation and join build strings through these
fn strBuildAdd(mut out u8[], s str):
	n = __ld64(__addr(out) + 8)
	m = sLen(s)
	if m == 0: return
	textGrow(__addr(out), n + m)
	__memcpy(__ld64(__addr(out)) + n, sPtr(s), m)
	__st64(__addr(out) + 8, n + m)

# the built text as a str: short, or the block it was built in with a NUL after the bytes (for
# the system calls), or copied to one of its size when it is still in the caller's buffer
fn strBuildEnd(move out u8[]) str:
	l = __addr(out)
	n = __ld64(l + 8)
	room = __ld64(l + 16)
	if n <= strShort:
		s = strNew(n)
		__memcpy(sPtr(s), __ld64(l), n)
		if room > 0:
			rtFree(__ld64(l))
		__st64(l + 16, 0)   # its block given back: out owns nothing now
		return s
	if room < 0:
		s = strNew(n)
		__memcpy(sPtr(s), __ld64(l), n)
		__st64(l + 16, 0)
		return s
	listGrowRaw(l, n + 1, 1)
	__st8(__ld64(l) + n, 0)   # a NUL after the bytes, as strNew's (for the system)
	str(move out)

# a number's text: short (20 bytes at most)
fn fmtInt(v i64) str:
	size = intWidth(v)
	s = strNew(size)
	writeInt(sPtr(s), size, v)
	s

# appends the decimal digits of an unsigned v
fn pushUint(mut out u8[], v u64):
	if i64(v) >= 0:
		pushInt(out, i64(v))
		return
	pushInt(out, i64(v / 10))   # above the largest i64: the last digit apart
	pushInt(out, i64(v % 10))

# v holds an unsigned 64-bit pattern
fn fmtUint(v i64) str:
	if v >= 0: return fmtInt(v)
	high = i64(u64(v) / 10)   # above the largest i64: the last digit apart
	size = intWidth(high)
	s = strNew(size + 1)
	writeInt(sPtr(s), size, high)
	__st8(sPtr(s) + size, 48 + i64(u64(v) % 10))
	s

fn fmtBool(v bool) str:
	if v: return "true"
	"false"

# ---------- console ----------
# Output to stdout is collected in a buffer and written in one call when it reaches 64 KB, at
# exit, before anything goes to stderr, before stdin is read and before a child process
# starts; on a console every line is written as it completes, so an interactive program
# behaves as before. Stdin is read 64 KB at a time. The state is one Console record.
