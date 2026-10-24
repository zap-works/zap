# 128-bit unsigned arithmetic, for the floating-point results that need every bit below the
# rounded one: the product of two 64-bit mantissas, a quotient, a root. A shift count outside
# 0..127 stops the program (spec 3.1), so these take only counts inside it.

pub type Wide:
	hi u64 = 0
	lo u64 = 0

	fn isZero():
		hi == 0 and lo == 0

	# shifted left by n, 0 to 127
	fn shl(n i64):
		if n == 0: return Wide(hi, lo)
		if n >= 64: return Wide(hi = lo << (n - 64), lo = 0)
		Wide(hi = hi << n | lo >> (64 - n), lo = lo << n)

	# shifted right by n, 0 to 127
	fn shr(n i64):
		if n == 0: return Wide(hi, lo)
		if n >= 64: return Wide(hi = 0, lo = hi >> (n - 64))
		Wide(hi = hi >> n, lo = lo >> n | hi << (64 - n))

	fn add(o Wide):
		sum = lo + o.lo
		Wide(hi = hi + o.hi + (1 if sum < lo else 0), lo = sum)

	fn sub(o Wide):
		Wide(hi = hi - o.hi - (1 if lo < o.lo else 0), lo = lo - o.lo)

	fn less(o Wide):
		hi < o.hi or (hi == o.hi and lo < o.lo)

	# the zero bits above the highest one set (128 for zero)
	fn leadingZeros():
		if hi != 0: return hi.leadingZeros()
		64 + lo.leadingZeros()

	# whether any of the n lowest bits is set, n from 0 to 128
	fn lowBits(n i64):
		if n == 0: return false
		if n == 128: return not isZero()
		not shl(128 - n).isZero()

	# bit n, 0 to 127
	fn bit(n i64):
		shr(n).lo & 1 != 0

# a * b in full
pub fn mulWide(a u64, b u64) Wide:
	low32 u64 = 0xFFFF_FFFF
	p00 = (a & low32) * (b & low32)
	p01 = (a & low32) * (b >> 32)
	p10 = (a >> 32) * (b & low32)
	p11 = (a >> 32) * (b >> 32)
	mid = (p00 >> 32) + (p01 & low32) + (p10 & low32)
	Wide(hi = p11 + (p01 >> 32) + (p10 >> 32) + (mid >> 32), lo = (p00 & low32) | (mid << 32))

# w >> n for any n of 1 or more: the quotient, the bit just below it, and whether any lower bit
# is set. This is how every rounding to a coarser grid starts.
pub fn splitAt(w Wide, n i64) (Wide, bool, bool):
	if n > 128: return (Wide(), false, not w.isZero())
	quotient = Wide() if n == 128 else w.shr(n)
	(quotient, w.bit(n - 1), w.lowBits(n - 1))

# The floor of the square root of w (w at least 2^126, so the root has 64 bits) and whether it
# is not exact. Digit by digit: each step brings two more bits of w down.
pub fn rootWide(w Wide) (u64, bool):
	remainder = Wide()
	root = 0
	for step in 0..64:
		two = w.shr(126 - 2 * step).lo & 3
		remainder = remainder.shl(2).add(Wide(lo = two))
		trial = Wide(lo = root).shl(2).add(Wide(lo = 1))
		if trial.less(remainder) or not remainder.less(trial):
			remainder = remainder.sub(trial)
			root = root << 1 | 1
		else:
			root <<= 1
	(root, not remainder.isZero())

test "a product, a split and a root of 128 bits":
	p = mulWide(0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF)
	expect p.hi == u64(-2) and p.lo == 1
	q, guard, rest = splitAt(Wide(hi = 0, lo = 0b1010), 2)
	expect q.lo == 2 and guard and not rest
	r, inexact = rootWide(Wide(hi = 1 << 62, lo = 0))
	expect r == 1 << 63 and not inexact
	r2, inexact2 = rootWide(Wide(hi = 1 << 62, lo = 1))
	expect r2 == 1 << 63 and inexact2
