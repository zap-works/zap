# The float formatted at a fixed number of decimals ("{x:.2}"): fmtFixed in num.zap takes the
# wide multiply here up to 17 decimals, else the exact decimal digits.

# the largest power of ten a double's 53 bits can be multiplied by within 128 bits (10^17 < 2^57)
fixedWideDecimals = 17

# the magnitude of the double (its bits without the sign) times 10^dec rounded half to even to an
# integer, from one multiply of its mantissa by the power (m * 10^dec is below 2^110) and a shift
# by its exponent; none when that integer does not fit 64 bits
fn scaledRounded(absBits i64, dec i64) u64?:
	p = binaryParts(absBits)
	scale = u64(ipow(10, dec))
	m = u64(p.m)
	lo = m * scale
	hi = m.mulHigh(scale)
	if p.e >= 0:
		if hi != 0 or p.e >= 64 or (p.e > 0 and (lo >> (64 - p.e)) != 0): return none
		return lo << p.e
	s = -p.e
	if s >= 128: return 0   # below a quarter
	q u64 = 0
	remHi u64 = 0
	halfHi u64 = 0
	remLo = lo
	halfLo u64 = 0
	if s > 64:
		q = hi >> (s - 64)
		remHi = hi & ((1 << (s - 64)) - 1)
		halfHi = 1 << (s - 65)
	elif s == 64:
		q = hi
		halfLo = 1 << 63
	else:
		if (hi >> s) != 0: return none
		q = (hi << (64 - s)) | (lo >> s)
		remLo = lo & ((1 << s) - 1)
		halfLo = 1 << (s - 1)
	above = remHi > halfHi or (remHi == halfHi and remLo > halfLo)
	tie = remHi == halfHi and remLo == halfLo
	if above or (tie and q & 1 == 1):
		if q == 18_446_744_073_709_551_615: return none
		return q + 1
	q

# n as text with dec digits after the point (n is the number times 10^dec), a minus before it
# when neg
fn fixedText(n u64, neg bool, dec i64) str:
	digits i64 = 1
	v = n
	while v >= 10:
		v /= 10
		digits += 1
	width = digits.max(dec + 1)   # the integer part has a digit even when n is below 10^dec
	total = width + (1 if dec > 0 else 0) + (1 if neg else 0)
	s = strNew(total)
	p = sPtr(s)
	if neg:
		__st8(p, 45)
	at = total
	v = n
	for k in 0..width:
		if k == dec and dec > 0:
			at -= 1
			__st8(p + at, 46)
		at -= 1
		__st8(p + at, u8(48 + v % 10))
		v /= 10
	s
