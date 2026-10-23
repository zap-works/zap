# The typed pieces of printing, JSON and binary encoding. The compiler writes, for every type
# a program prints or encodes, Zap functions that walk its values (compiler/collections/derive.zap);
# they call these. Writing appends to a u8[]; reading walks a text or a byte list with a
# cursor (`mut at`) that the caller owns, so decoding keeps no state of its own.

# ---------- writing ----------

fn outStr(mut out u8[], s str):
	strBuildAdd(out, s)

fn outInt(mut out u8[], v i64):
	pushInt(out, v)

fn outUint(mut out u8[], v u64):
	pushUint(out, v)

fn outBool(mut out u8[], b bool):
	outStr(out, fmtBool(b))

# the shortest digits that read back to the same value
fn outFloat(mut out u8[], x f64):
	pushFloat(out, i64(x.toBits()), 64)

# JSON has no NaN or infinity: they are null
fn outJsonFloat(mut out u8[], x f64):
	if x != x or x > 1.7976931348623157e308 or x < -1.7976931348623157e308:
		outStr(out, "null")
		return
	if x == 0.0 and x.toBits() >> 63 != 0:   # -0, which reads back as itself
		outStr(out, "-0")
		return
	outFloat(out, x)

# s as a quoted string: " \ and the control characters escaped (JSON's rules), the runs between
# them copied whole (with no escape, the quotes and the bytes written in one go)
fn outQuoted(mut out u8[], s str):
	n = sLen(s)
	i = jsonEscapeAt(s, 0)
	l = __addr(out)
	at = __ld64(l + 8)
	textGrow(l, at + n + 2)
	if i == n:
		p = __ld64(l) + at
		__st8(p, '"')
		__memcpy(p + 1, sPtr(s), n)
		__st8(p + n + 1, '"')
		__st64(l + 8, at + n + 2)
		return
	out.push('"')
	start = 0
	while i < s.len:
		c = s[i]
		out.extend(s[start..i].bytes())
		out.push('\\')
		if c == '"' or c == '\\':
			out.push(c)
		elif c == '\n':
			out.push('n')
		elif c == '\r':
			out.push('r')
		elif c == '\t':
			out.push('t')
		else:
			outStr(out, "u00")
			out.push(hexDigit(i64(c) / 16, false))
			out.push(hexDigit(i64(c) % 16, false))
		start = i + 1
		i = jsonEscapeAt(s, start)
	out.extend(s[start..].bytes())
	out.push('"')

# the first byte of s at or after from that a JSON string escapes (" \ or a control character),
# or s.len: sixteen bytes at a time, the last few too when sixteen from them lie in their page
fn jsonEscapeAt(s str, from i64) i64:
	bytes = s.bytes()
	i = from
	quote = Simd<16>('"')
	slash = Simd<16>('\\')
	high = Simd<16>(224)   # a control character has none of the top three bits
	zero = Simd<16>(0)
	while i + 16 <= bytes.len:
		v = bytes.load16(i)
		m = v.eqMask(quote) | v.eqMask(slash) | (v & high).eqMask(zero)
		if m != 0: return i + m.trailingZeros()
		i += 16
	at = sPtr(s) + i
	if i < bytes.len and (at & 4095) <= 4080:
		v = __strof(at, 16, 0).bytes().load16(0)   # the bytes past the end masked off
		found = v.eqMask(quote) | v.eqMask(slash) | (v & high).eqMask(zero)
		m = found & ((1 << (bytes.len - i)) - 1)
		return i + m.trailingZeros() if m != 0 else bytes.len
	while i < bytes.len and bytes[i] != '"' and bytes[i] != '\\' and bytes[i] >= ' ':
		i += 1
	i

# s as a JSON string literal
pub fn jsonQuote(s str) str:
	out u8[] = []
	outQuoted(out, s)
	str(move out)

# ---------- reading: a text or a byte list and a cursor into it ----------

# where the reading is: the next byte's index (one outside the text reads as nothing there: no
# read stops the program)
pub type Cursor:
	at i64

# ---------- JSON reading ----------

# past the white space at the cursor: sixteen bytes at a time once there is some
fn jsonSpace(s str, mut cur Cursor):
	if cur.at < 0 or cur.at >= s.len or not s[cur.at].isSpace(): return
	bytes = s.bytes()
	i = cur.at + 1
	while i + 16 <= bytes.len:
		v = bytes.load16(i)
		spaces = v.eqMask(Simd<16>(' ')) | v.eqMask(Simd<16>('\n')) |
			v.eqMask(Simd<16>('\r')) | v.eqMask(Simd<16>('\t'))
		if spaces != 65_535:
			cur.at = i + (spaces ^ 65_535).trailingZeros()
			return
		i += 16
	while i < bytes.len and bytes[i].isSpace():
		i += 1
	cur.at = i

# the byte c next (after white space): consumed when it is
fn jsonChar(s str, mut cur Cursor, c i64) bool:
	p = cur.at
	if p >= 0 and p < sLen(s) and __ld8(sPtr(s) + p) == c:
		cur.at = p + 1   # the usual case, no white space first
		return true
	jsonCharSpaced(s, cur, c)

# the same past white space
fn jsonCharSpaced(s str, mut cur Cursor, c i64) bool:
	n = s.len
	p = cur.at
	if p < 0: return false
	while p < n and s[p].isSpace():
		p += 1
	found = p < n and i64(s[p]) == c
	cur.at = p + 1 if found else p
	found

# consumed when it is next
fn jsonLiteral(s str, mut cur Cursor, lit str) bool:
	if cur.at >= 0 and cur.at < sLen(s) and __ld8(sPtr(s) + cur.at) <= ' ':
		jsonSpace(s, cur)
	p = cur.at
	if p < 0 or lit.len > sLen(s) - p or not sameBytes(sPtr(s) + p, sPtr(lit), lit.len):
		return false
	cur.at = p + lit.len
	true

fn jsonNull(s str, mut cur Cursor) bool:
	jsonLiteral(s, cur, "null")

fn jsonBool(s str, mut cur Cursor) bool?:
	if jsonLiteral(s, cur, "true"): return true
	if jsonLiteral(s, cur, "false"): return false
	none

# -1 for a byte that is no hexadecimal digit
pub fn hexValue(c u8) i64:
	if c.isDigit(): return i64(c) - '0'
	if c >= 'a' and c <= 'f': return i64(c) - 87
	if c >= 'A' and c <= 'F': return i64(c) - 55
	-1

# four hex digits at i, or -1
fn fourHexDigits(s str, i i64) i64:
	if i + 4 > s.len: return -1
	v i64 = 0
	for k in 0..4:
		h = hexValue(s[i + k])
		if h < 0: return -1
		v = v * 16 + h
	v

# where a JSON string's text ends when it has no escape (its closing quote), else -1; cur at its
# first byte
fn plainStrEnd(s str, cur Cursor) i64:
	if cur.at < 0: return -1
	bytes = s.bytes()
	p = cur.at
	quote = Simd<16>('"')
	slash = Simd<16>('\\')
	while p + 16 <= bytes.len:
		v = bytes.load16(p)
		m = v.eqMask(quote) | v.eqMask(slash)
		if m != 0:
			p += m.trailingZeros()
			return p if bytes[p] == '"' else -1
		p += 16
	while p < bytes.len and bytes[p] != '"' and bytes[p] != '\\':
		p += 1
	p if p < bytes.len and bytes[p] == '"' else -1

# which of names (each closed by a quote: "id\"name\"") an object's next key is, as the offset
# in names where it starts, its colon consumed: -1 for a key none of them is, -2 when no key and
# colon are next. The key at offset next, the one expected, is tried first where it lies.
fn jsonField(s str, mut cur Cursor, names str, next i64) i64:
	p = cur.at
	n = s.len
	if p >= 0 and next < names.len and p + 2 < n:
		text = sPtr(s) + p
		name = sPtr(names) + next
		k = nameEnd(name, 0)   # its length: its closing quote compared with the key's
		if __ld8(text) == '"' and k + 2 < n - p and __ld8(text + k + 2) == ':' and
			sameBytes(text + 1, name, k + 1):
			cur.at = p + k + 3
			return next
	anyField(s, cur, names)

# jsonField's general way: past white space, a key elsewhere in names or none of them, escapes
fn anyField(s str, mut cur Cursor, names str) i64:
	if not jsonChar(s, cur, '"'): return -2
	p = cur.at
	found = -1
	end = plainStrEnd(s, cur)
	if end >= 0:
		found = fieldAt(names, sPtr(s) + p, end - p)
		cur.at = end + 1
	else:
		cur.at -= 1   # back to the quote: decoded the general way
		found = escapedField(s, cur, names) ?? -2
		if found == -2: return -2
	if not jsonChar(s, cur, ':'): return -2
	found

fn escapedField(s str, mut cur Cursor, names str) i64?:
	key = try jsonText(s, cur)
	fieldAt(names, sPtr(key), key.len)

# the offset of the quote closing the name at offset i of the names at `at`
fn nameEnd(at i64, i i64) i64:
	j = i
	while __ld8(at + j) != '"':
		j += 1
	j

# the offset in names (as jsonField takes them) of the n bytes at p, or -1
fn fieldAt(names str, p i64, n i64) i64:
	at = sPtr(names)
	i = 0
	while i < names.len:
		j = nameEnd(at, i)
		if j - i == n and bytesEq(at + i, p, n): return i
		i = j + 1
	-1

# a JSON string: the text between the quotes with its escapes resolved
fn jsonText(s str, mut cur Cursor) str?:
	if not jsonChar(s, cur, '"'): return none
	end = plainStrEnd(s, cur)
	if end < 0: return jsonUnescaped(s, cur)
	out = strNew(end - cur.at)   # no escape: one block, one copy
	__memcpy(sPtr(out), sPtr(s) + cur.at, end - cur.at)
	cur.at = end + 1
	out

# the rest of a JSON string that has an escape, cur at its first byte (apart: its frame is
# the plain string's no more)
fn jsonUnescaped(s str, mut cur Cursor) str?:
	out u8[] = []
	p = cur.at
	start = cur.at
	while p < s.len:
		c = s[p]
		if c == '"':
			out.extend(s[start..p].bytes())
			cur.at = p + 1
			return str(move out)
		if c == '\\':
			out.extend(s[start..p].bytes())
			p += 1
			if p >= s.len: return none
			e = s[p]
			if e == '"' or e == '\\' or e == '/':
				out.push(e)
			elif e == 'n':
				out.push('\n')
			elif e == 'r':
				out.push('\r')
			elif e == 't':
				out.push('\t')
			elif e == 'b':
				out.push(8)
			elif e == 'f':
				out.push(12)
			elif e == 'u':
				cp = fourHexDigits(s, p + 1)
				if cp < 0: return none
				p += 4
				if cp >= 55_296 and cp < 56_320 and p + 2 < s.len and s[p + 1] == '\\' and
					s[p + 2] == 'u':
					lo = fourHexDigits(s, p + 3)
					if lo >= 56_320 and lo < 57_344:
						cp = 65_536 + ((cp - 55_296) << 10) + (lo - 56_320)
						p += 6
				out.extend(strFromCode(cp).bytes())
			else:
				return none
			start = p + 1
		p += 1
	none

# a number token's text
fn jsonNumber(s str, mut cur Cursor) str?:
	jsonSpace(s, cur)
	start = cur.at
	p = cur.at
	if p < 0: return none
	if p < s.len and s[p] == '-':
		p += 1
	digits = 0
	while p < s.len and s[p].isDigit():
		p += 1
		digits += 1
	if p < s.len and s[p] == '.':
		p += 1
		while p < s.len and s[p].isDigit():
			p += 1
			digits += 1
	if digits == 0: return none
	if p < s.len and (s[p] == 'e' or s[p] == 'E'):
		p += 1
		if p < s.len and (s[p] == '+' or s[p] == '-'):
			p += 1
		while p < s.len and s[p].isDigit():
			p += 1
	cur.at = p
	s[start..p].copy()

# none when the number has a fraction or an exponent
fn jsonInt(s str, mut cur Cursor) i64?:
	# up to 18 digits read in place (the text's bytes and length read once); anything else (a
	# fraction, more digits) the general way
	at = sPtr(s)
	n = s.len
	p = cur.at
	if p < 0: return none
	if p < n and __ld8(at + p) <= 32:
		jsonSpace(s, cur)
		p = cur.at
	neg = p < n and __ld8(at + p) == '-'
	first = p + 1 if neg else p
	p = first
	last = (first + 18).min(n)
	v i64 = 0
	while p < last:
		d = __ld8(at + p) - '0'
		if d < 0 or d > 9: break
		v = v * 10 + d
		p += 1
	if p > first and (p >= n or not jsonNumberGoesOn(__ld8(at + p))):
		cur.at = p
		return -v if neg else v
	tok = try jsonNumber(s, cur)
	if tok.contains(".") or tok.contains("e") or tok.contains("E"): return none
	i64.parse(tok)

# whether byte c continues a number's digits (a digit, a fraction or an exponent)
fn jsonNumberGoesOn(c i64) bool:
	(c >= '0' and c <= '9') or c == '.' or c == 'e' or c == 'E'

# a JSON integer as a u64: none for a fraction, an exponent or a sign before a value above 0
# (-0 is 0, as for every other integer type)
fn jsonU64(s str, mut cur Cursor) u64?:
	tok = try jsonNumber(s, cur)
	if not tok.startsWith("-"): return u64.parse(tok)
	0 if u64.parse(tok[1..]) == 0 else none

fn jsonFloat(s str, mut cur Cursor) f64?:
	tok = try jsonNumber(s, cur)
	f64.parse(tok)

# passes over one value of any shape
fn jsonSkip(s str, mut cur Cursor) bool:
	jsonSpace(s, cur)
	if cur.at < 0 or cur.at >= s.len: return false
	c = s[cur.at]
	if c == '{' or c == '[':
		close = i64(c) + 2   # } or ]
		cur.at += 1
		if jsonChar(s, cur, close): return true
		more = true
		while more:
			if c == '{':
				if jsonText(s, cur) == none or not jsonChar(s, cur, ':'): return false
			if not jsonSkip(s, cur): return false
			more = jsonChar(s, cur, ',')
		return jsonChar(s, cur, close)
	if c == '"': return jsonText(s, cur) != none
	if c == 't': return jsonLiteral(s, cur, "true")
	if c == 'f': return jsonLiteral(s, cur, "false")
	if c == 'n': return jsonLiteral(s, cur, "null")
	jsonNumber(s, cur) != none

# whether only white space is left
fn jsonEnd(s str, mut cur Cursor) bool:
	jsonSpace(s, cur)
	cur.at == s.len

# ---------- binary reading: the bytes and a cursor into them ----------

# n bytes as a little-endian unsigned number
fn bytesLittleEndian(b u8[], mut cur Cursor, n i64) u64?:
	if cur.at < 0 or n < 0 or n > b.len - cur.at: return none
	v u64 = 0
	for k in 0..n:
		v |= u64(b[cur.at + k]) << u64(8 * k)
	cur.at += n
	v

fn bytesText(b u8[], mut cur Cursor, n i64) str?:
	if cur.at < 0 or n < 0 or n > b.len - cur.at: return none
	s = str(b[cur.at..cur.at + n])
	cur.at += n
	s
