# Strings: UTF-8 bytes; positions seen by programs count code points. Bytes are read with
# byteAt and loadWord (bounds-checked), windows are made with window, and new strings are
# built in a u8[] that becomes the str without a copy (str(move bytes)). The three words of a str
# themselves are handled in core.zap.

# the code points among the bytes [from, to) of s
fn utf8Count(s str, start i64, to i64) i64:
	n i64 = 0
	i = start
	while i < to:
		if (s[i] & 192) != 128:
			n += 1
		i += 1
	n

# byte offset of code point idx counted from byte `start`, clamped to the end
fn utf8At(s str, start i64, idx i64) i64:
	length = sLen(s)
	i = start
	n i64 = 0
	while i < length:
		if (s[i] & 192) != 128:
			if n == idx: return i
			n += 1
		i += 1
	length

# str(bytes) of a list's place or a lent list: a str with its own copy of the bytes
fn strFromU8(l u8[]) str:
	s = strNew(l.len)
	__memcpy(sPtr(s), __ld64(__addr(l)), l.len)
	s

# the number of Unicode characters of s (s.len counts bytes)
fn strLenCp(s str) i64:
	utf8Count(s, 0, sLen(s))

# s.isEmpty: whether the string has no bytes
pub fn strIsEmpty(s str) bool:
	sLen(s) == 0

# the first place of sub in s at or after start, or -1 (the search of split and of the patterns
# the compiler writes)
fn findBytes(s str, start i64, sub str) i64:
	findIn(sPtr(s), sLen(s), start, sPtr(sub), sLen(sub))

# the first place of the m bytes at psub among the n at ps, at or after start, or -1: the next
# occurrence of its first byte is looked for in the next sixteen bytes, then sixteen at a time
# (byteIndexIn), the rest compared
# there (a split loop calls it with the words it read once)
fn findIn(ps i64, n i64, start i64, psub i64, m i64) i64:
	if m == 0: return start if start <= n else -1
	first = __ld8(psub)
	i = start.max(0)
	while i + m <= n:
		near = (i + 16).min(n)
		while i < near and __ld8(ps + i) != first:   # the next sixteen byte by byte, no call
			i += 1
		if i == near and near < n:
			i = byteIndexIn(ps, n, first, i)
		if i < 0 or i + m > n: return -1
		# raw: the loop bounds both indexes
		j i64 = 1
		while j < m and __ld8(ps + i + j) == __ld8(psub + j):
			j += 1
		if j == m: return i
		i += 1
	-1

# s.contains(part): whether part occurs in s
pub fn strContains(s str, sub str) bool:
	findBytes(s, 0, sub) >= 0

# s.startsWith(prefix): whether s begins with prefix
pub fn strStartsWith(s str, p str) bool:
	lp = sLen(p)
	lp <= sLen(s) and bytesEq(sPtr(s), sPtr(p), lp)

# s.endsWith(suffix): whether s ends with suffix
pub fn strEndsWith(s str, p str) bool:
	ls = sLen(s)
	lp = sLen(p)
	lp <= ls and bytesEq(sPtr(s) + ls - lp, sPtr(p), lp)

# i, or none for -1: what a search gives
fn foundIndex(i i64) n64?:
	if i >= 0: return i
	none

# s.indexOf(part, from = 0): the byte index of the first place part occurs at or after from;
# none when it does not
pub fn strIndexOf(s str, sub str, start i64 = 0) n64?:
	foundIndex(findBytes(s, start.max(0), sub))

# s.indexOf(b, from = 0) of a byte: the index of the first byte b at or after from; none when
# there is none
fn strIndexOfByte(s str, b u8, start i64 = 0) n64?:
	foundIndex(byteIndex(s, i64(b), start))

# s.lastIndexOf(part): the byte index of the last place part occurs in s; none when it does not
pub fn strLastIndexOf(s str, part str) n64?:
	foundIndex(lastIndex(s, part))

# ASCII white space: a space, a tab or a line break
pub fn isSpace(c u8) bool:
	c == ' ' or c == '\t' or c == '\n' or c == '\r'

# ASCII classes of a byte (or the i64 of one): the one set the runtime, the lexer and the tools
# that read sources as text share
pub fn isDigit(c u8) bool:
	c >= '0' and c <= '9'

pub fn isUpper(c u8) bool:
	c >= 'A' and c <= 'Z'

pub fn isLower(c u8) bool:
	c >= 'a' and c <= 'z'

pub fn isAlpha(c u8) bool:
	c.isLower() or c.isUpper()

pub fn isAlnum(c u8) bool:
	c.isAlpha() or c.isDigit()

# a byte of a name: a letter, a digit or '_'
pub fn isWordByte(c u8) bool:
	c.isAlnum() or c == '_'

# a byte a name starts with
pub fn isWordStart(c u8) bool:
	c.isAlpha() or c == '_'

# whether the byte is trimmed: a space, or one of `chars` when some are given
fn trimsByte(c u8, chars str) bool:
	c.isSpace() if chars.isEmpty else chars.indexOf(c) != none

# s.trimmed(): s without its leading and trailing spaces, or the bytes of `chars` when given
# (Python's `s.strip(chars)`): a window, no copy, lives as long as s
pub fn strTrimmed(s str, chars str = "") ref str:
	strTrimmedEnd(strTrimmedStart(s, chars), chars)

# s.trimmedStart(): s without its leading spaces, or the bytes of `chars` when given (Python's
# `s.lstrip(chars)`): a window, no copy
pub fn strTrimmedStart(s str, chars str = "") ref str:
	n = sLen(s)
	a i64 = 0
	while a < n and trimsByte(s[a], chars):
		a += 1
	s[a..n]

# s.trimmedEnd(): s without its trailing spaces, or the bytes of `chars` when given (Python's
# `s.rstrip(chars)`): a window, no copy
pub fn strTrimmedEnd(s str, chars str = "") ref str:
	b = sLen(s)
	while b > 0 and trimsByte(s[b - 1], chars):
		b -= 1
	s[..b]

# the byte index of the last place part occurs in s, or -1
fn lastIndex(s str, part str) i64:
	n = sLen(s)
	m = sLen(part)
	if m > n: return -1
	i = n - m
	while i >= 0:
		k = 0
		while k < m and s[i + k] == part[k]:
			k += 1
		if k == m: return i
		i -= 1
	-1

# the first index at or after start holding the byte b, or -1; 64 bytes at a time, then 16 (the
# lanes equal to b as a bit mask, the lowest set bit the position)
fn byteIndex(s str, b i64, start i64) i64:
	byteIndexIn(sPtr(s), sLen(s), b, start)

# byteIndex of the n bytes at p
fn byteIndexIn(p i64, n i64, b i64, start i64) i64:
	i = start.max(0)
	bytes = bytesAt(p, n)
	wide = Simd<32>(u8(b & 255))
	while i + 64 <= bytes.len:   # (the window's own length: its checks proven)
		m = bytes.load32(i).eqMask(wide) | bytes.load32(i + 32).eqMask(wide) << 32
		if m != 0: return i + m.trailingZeros()
		i += 64
	pat = Simd<16>(u8(b & 255))
	while i + 16 <= bytes.len:
		m = bytes.load16(i).eqMask(pat)
		if m != 0: return i + m.trailingZeros()
		i += 16
	while i < bytes.len:
		if bytes[i] == (b & 255): return i
		i += 1
	-1

# a window over the n bytes at p
fn bytesAt(p i64, n i64) ref u8[]:
	w u8[] = []
	__st64(__addr(w), p)
	__st64(__addr(w) + 8, n)
	w

# s.count(b): how many bytes of s equal b (of a part: s[from..to].count(b)), 64 bytes at a time,
# then 16 (the bits of the mask of equal lanes counted)
pub fn strCount(s str, b u8) i64:
	i i64 = 0
	end = sLen(s)
	bytes = s.bytes()
	wide = Simd<32>(b)
	count i64 = 0
	while i + 64 <= end:
		count += (bytes.load32(i).eqMask(wide) | bytes.load32(i + 32).eqMask(wide) << 32).bitCount()
		i += 64
	pat = Simd<16>(b)
	while i + 16 <= end:
		count += bytes.load16(i).eqMask(pat).bitCount()
		i += 16
	while i < end:
		if s[i] == b:
			count += 1
		i += 1
	count

# s.upper(): a new string with ASCII letters in upper case
pub fn strUpper(s str) str:
	strCased(s, 97, 122)   # a..z

# s.lower(): a new string with ASCII letters in lower case
pub fn strLower(s str) str:
	strCased(s, 65, 90)   # A..Z

# s with the letters lo..hi turned to the other case
fn strCased(s str, lo i64, hi i64) str:
	n = sLen(s)
	r = strNew(n)
	from = sPtr(s)
	to = sPtr(r)
	for i in 0..n:
		c = __ld8(from + i)
		__st8(to + i, c ^ 32 if c >= lo and c <= hi else c)
	r

# s.replace(old, new): a new string with every old replaced by new
pub fn strReplace(s str, start str, to str) str:
	lf = sLen(start)
	if lf == 0: return s.copy()
	n = sLen(s)
	out u8[] = []
	out.reserve(n + replacedGrowth(s, start, to))
	p i64 = 0
	going = true
	while going:
		q = findBytes(s, p, start)
		if q < 0:
			out.extend(s[p..n].bytes())
			going = false
		else:
			out.extend(s[p..q].bytes())
			out.extend(to.bytes())
			p = q + lf
	str(move out)

# how many bytes replacing every start in s by to adds (0 when to is no longer: room enough)
fn replacedGrowth(s str, start str, to str) i64:
	grows = sLen(to) - sLen(start)
	if grows <= 0: return 0
	count = 0
	p = findBytes(s, 0, start)
	while p >= 0:
		count += 1
		p = findBytes(s, p + sLen(start), start)
	count * grows

# `s = s.replace(old, new)` of the str at `at`, which the assignment drops after: a text that owns
# its block and does not grow is written over it, its parts moved down (each before where it was
# read), and the block given to the result (the str at `at` left owning nothing); otherwise a new one
fn strReplaceOwn(at i64, start str, to str) str:
	lf = sLen(start)
	lt = sLen(to)
	room = __ld64(at + 16)
	if lf == 0 or room <= 0 or lt > lf:
		return strReplace(__strof(textPtrAt(at), textLenAt(at), 0), start, to)
	p = __ld64(at)
	n = __ld64(at + 8)
	pf = sPtr(start)
	pt = sPtr(to)
	r i64 = 0
	w i64 = 0
	q = findIn(p, n, 0, pf, lf)
	while q >= 0:
		__memcpy(p + w, p + r, q - r)   # down, never past where it reads (forward)
		w += q - r
		__memcpy(p + w, pt, lt)
		w += lt
		r = q + lf
		q = findIn(p, n, r, pf, lf)
	__memcpy(p + w, p + r, n - r)
	w += n - r
	if w < room:
		__st8(p + w, 0)   # (a block made a str from a list may have no room for its NUL)
	__st64(at + 16, 0)
	__strof(p, w, room)

# s.split(sep): the parts between the separators, a new list
# s.words(): the runs of s between spaces, tabs and line breaks, none of them empty
pub fn strWords(s str) str[]:
	r str[] = []
	n = sLen(s)
	p i64 = 0
	while p < n:
		while p < n and s[p].isSpace():
			p += 1
		q = p
		while q < n and not s[q].isSpace():
			q += 1
		if q > p:
			r.push(s[p..q].copy())
		p = q
	r

# s.lines(): its lines, a new list, as a for over them goes (split at newlines, a carriage
# return before one left out, nothing after a final newline)
pub fn strLines(s str) str[]:
	r str[] = []
	for line in s.lines():
		r.push(line.copy())
	r

# s.wrapLines(width): its words in lines of at most width bytes (a longer word alone on its
# line), joined by line breaks
pub fn strWrapLines(s str, width i64) str:
	out = ""
	line = 0
	for w in strWords(s):
		if line > 0 and line + 1 + w.len > width:
			out += "\n"
			line = 0
		elif line > 0:
			out += " "
			line += 1
		out += w
		line += w.len
	out

# an empty sep splits into the characters
pub fn strSplit(s str, sep str) str[]:
	r str[] = []
	ls = sLen(sep)
	n = sLen(s)
	if ls == 0:
		p i64 = 0
		while p < n:
			q = utf8At(s, p, 1)
			r.push(s[p..q].copy())
			p = q
		return r
	p i64 = 0
	going = true
	while going:
		q = findBytes(s, p, sep)
		if q < 0:
			r.push(s[p..n].copy())
			going = false
		else:
			r.push(s[p..q].copy())
			p = q + ls
	r

# s.chars(): the Unicode characters, each as a string
pub fn strChars(s str) str[]:
	strSplit(s, "")

# s.charCode(): the code point of the first character, -1 when s is empty
pub fn strCharCode(s str) i64:
	if sLen(s) == 0: return -1
	c0 = i64(s[0])
	if c0 < 128: return c0
	c1 = i64(s[1])
	if (c0 & 224) == 192: return ((c0 & 31) << 6) | (c1 & 63)
	c2 = i64(s[2])
	if (c0 & 240) == 224: return ((c0 & 15) << 12) | ((c1 & 63) << 6) | (c2 & 63)
	((c0 & 7) << 18) | ((c1 & 63) << 12) | ((c2 & 63) << 6) | (i64(s[3]) & 63)

# str.fromCode(cp): the character of a code point, as a string
pub fn strFromCode(cp0 i64) str:
	cp = cp0
	if cp < 0 or cp > 1_114_111:
		cp = 65_533
	s u8[] = []
	if cp < 128:
		s.push(u8(cp))
	elif cp < 2048:
		s.push(u8(192 | (cp >> 6)))
		s.push(u8(128 | (cp & 63)))
	elif cp < 65_536:
		s.push(u8(224 | (cp >> 12)))
		s.push(u8(128 | ((cp >> 6) & 63)))
		s.push(u8(128 | (cp & 63)))
	else:
		s.push(u8(240 | (cp >> 18)))
		s.push(u8(128 | ((cp >> 12) & 63)))
		s.push(u8(128 | ((cp >> 6) & 63)))
		s.push(u8(128 | (cp & 63)))
	str(move s)

# str.fromUtf16(bytes): the text of UTF-16 little-endian bytes (Windows' wide text), a byte order
# mark dropped, a lone surrogate as U+FFFD
pub fn strFromUtf16(b u8[]) str:
	at = 0
	if b.len >= 2 and b[0] == 255 and b[1] == 254:
		at = 2
	parts str[] = []
	while at + 1 < b.len:
		cp = i64(b[at]) | (i64(b[at + 1]) << 8)
		at += 2
		if cp >= 55_296 and cp < 56_320 and at + 1 < b.len:
			low = i64(b[at]) | (i64(b[at + 1]) << 8)
			if low >= 56_320 and low < 57_344:
				cp = 65_536 + ((cp - 55_296) << 10) + (low - 56_320)
				at += 2
		parts.push(strFromCode(cp))
	parts.join("")

# s.repeat(n): s written n times, a new string
pub fn strRepeat(s str, n i64) str:
	r u8[] = []
	if n <= 0: return str(move r)
	r.reserve(s.len * n)
	loop n:
		r.extend(s.bytes())
	str(move r)

# s widened to `width` characters with `pad`, before it or after it (formatAlign's)
fn strPad(s str, width i64, pad str, atStart bool) str:
	n = strLenCp(s)
	padLen = strLenCp(pad)
	if width <= n or padLen == 0: return s.copy()
	need = width - n
	part = utf8At(pad, 0, need % padLen)   # the bytes of the pad's first characters that end the fill
	out u8[] = []
	out.reserve(sLen(s) + need / padLen * sLen(pad) + part)
	if not atStart:
		out.extend(s.bytes())
	loop need / padLen:
		out.extend(pad.bytes())
	out.extend(pad[..part].bytes())
	if atStart:
		out.extend(s.bytes())
	str(move out)

# "{s:<8}", "{s:->8}": the text widened to `width` characters with `fill`, after it (left) or
# before it; the compiler calls it for a format (formatPlumbing in checkExpr.zap)
fn formatAlign(text str, width i64, fill str, left bool) str:
	strPad(text, width, fill, not left)

# "{n:04}": a number's text widened to `width` with zeros after its sign
fn formatZeroPad(text str, width i64) str:
	n = sLen(text)
	if n >= width: return text.copy()
	out u8[] = []
	out.reserve(width)
	from i64 = 0
	if n > 0 and (text[0] == '-' or text[0] == '+'):
		out.push(text[0])
		from = 1
	k = n
	while k < width:
		out.push('0')
		k += 1
	out.extend(text[from..n].bytes())
	str(move out)

# "{n:#08X}", "{n:#}": an integer's text (digits after an optional sign) as zap fmt writes its
# literal: 0x before hexadecimal digits, five digits or more grouped by `_` (four a group in
# hexadecimal, three in decimal)
fn formatLiteral(text str, hex bool) str:
	n = sLen(text)
	from i64 = 1 if n > 0 and text[0] == '-' else 0
	digits = n - from
	group = 4 if hex else 3
	out u8[] = []
	out.reserve(n + 2 + digits / group)
	if from == 1: out.push('-')
	if hex: out.extend("0x".bytes())
	k = from
	while k < n:
		if k > from and digits >= 5 and (n - k) % group == 0: out.push('_')
		out.push(text[k])
		k += 1
	str(move out)

# ---------- parsing ----------

# i64.parse(s): the integer written in s, an optional sign then decimal digits or 0x and
# hexadecimal ones; none when s is not one or it does not fit. Every number type has its parse:
# the integers' are this one's, checked against their range.
pub fn i64Parse(s str) i64?:
	n = sLen(s)
	i i64 = 0
	neg = false
	if n > 0 and (s[0] == '+' or s[0] == '-'):
		neg = s[0] == '-'
		i = 1
	if i >= n: return none
	if i + 2 < n and s[i] == '0' and (s[i + 1] == 'x' or s[i + 1] == 'X'):
		return parseHexDigits(s, i + 2, neg)
	v i64 = 0
	while i < n:
		c = s[i]
		if not c.isDigit(): return none
		d = c - '0'
		# accumulate negatively to reach the minimum value
		if v < -922_337_203_685_477_580 or (v == -922_337_203_685_477_580 and d > 8):
			if not (neg and v == -922_337_203_685_477_580 and d == 8): return none
		v = v * 10 - d
		i += 1
	if neg: return v
	if v == (-9_223_372_036_854_775_807 - 1): return none
	-v

# the hexadecimal digits of s from i to its end as an integer (negated when neg); none when one is
# not a digit or the value does not fit. Accumulated negatively, as decimal, to reach the minimum.
fn parseHexDigits(s str, from i64, neg bool) i64?:
	v i64 = 0
	for i in from..sLen(s):
		d = hexValue(s[i])
		if d < 0 or v < -576_460_752_303_423_488 or v * 16 < (-9_223_372_036_854_775_807 - 1) + d:
			return none
		v = v * 16 - d
	if neg: return v
	if v == (-9_223_372_036_854_775_807 - 1): return none
	-v

# the integer written in s when it lies in [lo, hi]; none otherwise
fn parseWithin(s str, lo i64, hi i64) i64?:
	v = i64Parse(s) ?? return none
	if v < lo or v > hi: return none
	v

# i32.parse(s), u8.parse(s), n32.parse(s)...: i64.parse's integer when it lies in T's range
pub fn intParse<T Num>(s str) T?:
	z T = 0
	v = parseWithin(s, __tylo(z), __tyhi(z)) ?? return none
	r T = __cast(v)
	r

# u64.parse(s): the whole range of u64, past i64's; an optional + then decimal digits or 0x and
# hexadecimal ones
pub fn u64Parse(s str) u64?:
	n = sLen(s)
	start = 1 if n > 0 and s[0] == '+' else 0
	if start >= n: return none
	hex = start + 2 < n and s[start] == '0' and (s[start + 1] == 'x' or s[start + 1] == 'X')
	v u64 = 0
	for i in (start + 2 if hex else start)..n:
		d = hexValue(s[i]) if hex else i64(s[i] - '0') if s[i].isDigit() else -1
		if d < 0: return none
		if hex:
			if v > 1_152_921_504_606_846_975: return none   # 2^60 - 1: a digit more would not fit
			v = (v << 4) | u64(d)
		else:
			if v > 1_844_674_407_370_955_161 or v == 1_844_674_407_370_955_161 and d > 5:
				return none
			v = v * 10 + u64(d)
	v

# f32.parse(s): f64.parse's number rounded to the nearest f32
pub fn f32Parse(s str) f32?:
	v = f64Parse(s) ?? return none
	f32(v)

# f64.parse(s): the number written in s, an optional sign, decimal digits with a point and an
# exponent; none when s is not one
pub fn f64Parse(s str) f64?:
	n = sLen(s)
	i i64 = 0
	neg = false
	if n > 0 and (s[0] == '+' or s[0] == '-'):
		neg = s[0] == '-'
		i = 1
	# the digits (without the point), and the exponent adjustment
	digits u8[] = []
	nd i64 = 0
	intDigits i64 = 0
	sawDot = false
	scanning = true
	while scanning and i < n:
		c = s[i]
		if c.isDigit():
			digits.push(c)
			nd += 1
			if not sawDot:
				intDigits += 1
			i += 1
		elif c == '.' and not sawDot:
			sawDot = true
			i += 1
		else:
			scanning = false
	if nd == 0: return none
	exp10 = intDigits - nd
	if i < n:
		c = s[i]
		if c != 'e' and c != 'E': return none
		i += 1
		eneg = false
		if i < n and (s[i] == '+' or s[i] == '-'):
			eneg = s[i] == '-'
			i += 1
		if i >= n: return none
		ev i64 = 0
		while i < n:
			c2 = s[i]
			if not c2.isDigit(): return none
			if ev < 100_000:
				ev = ev * 10 + (c2 - '0')
			i += 1
		if eneg:
			ev = -ev
		exp10 += ev
	v = decimalToF64(digits, 0, nd, exp10)
	if neg:
		v = -v
	v

# a copy of the str header at src into dst, with its own bytes (a window's bytes belong to
# someone else, so they are always duplicated), short when it fits; used by the generated copy
# functions
fn strCopyRaw(src i64, dst i64):
	n = textLenAt(src)
	from = textPtrAt(src)
	if n <= strShort:
		__st64(dst, 0)
		__st64(dst + 8, 0)
		__st64(dst + 16, shortRoom(n))
		__memcpy(dst, from, n)
		return
	p = rtAllocRaw(n + 1)
	__memcpy(p, from, n)
	__st8(p + n, 0)
	__st64(dst, p)
	__st64(dst + 8, n)
	__st64(dst + 16, n + 1)

# s.hash(): bytesHash of its bytes
pub fn strHash(s str) i64:
	bytesHash(sPtr(s), sLen(s))

# FNV's offset basis: the hash of no bytes
hashBasis u64 = 1_469_598_103_934_665_603

# FNV-style over eight bytes at a time; a tail shorter than a word is read as the last word
# (overlapping what came before) when there is one, else as one short word (shortHash)
fn bytesHash(p i64, length i64) i64:
	if length < 8: return i64(hashBasis) if length == 0 else shortHash(shortWord(p, length))
	h = hashBasis
	i i64 = 0
	while i + 8 <= length:
		h = hashWord(h, u64(__ld64(p + i)))
		i += 8
	if i < length:
		h = hashWord(h, u64(__ld64(p + length - 8)))
	i64(h)

fn hashWord(h u64, w u64) u64:
	x = (h ^ w) * 1_099_511_628_211
	x ^ (x >> 29)

# bytesHash of 1 to 7 bytes, read as one word (shortWord): a multiply whose high bytes reach the
# low bits too
fn shortHash(w u64) i64:
	h = (hashBasis ^ w) * 11_400_714_819_323_198_485
	i64(h ^ (h >> 32))

# the n bytes (1 to 7) at p as the low bytes of a word, the high ones zero: one load when the
# word stays within p's page (reading past the bytes there cannot fault)
pub fn shortWord(p i64, n i64) u64:
	if wordInPage(p): return u64(__ld64(p)) & ((1 << (n * 8)) - 1)
	shortWordByBytes(p, n)

fn shortWordByBytes(p i64, n i64) u64:
	w u64 = 0
	for i in 0..n:
		w |= u64(__ld8(p + i)) << (i * 8)
	w
