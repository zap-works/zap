# The exact result of a floating-point operation on numbers (nonzero, finite), before its
# rounding: sums, products, quotients and roots as an Exact (fround.zap) whose bits below the 128
# kept are only known to be there (`sticky`).

# a number as the value it stands for; a zero has no bits
pub fn exactOf(u Unpacked) Exact:
	Exact(sign = u.sign, e = u.e, w = Wide(lo = u.m))

pub fn mulExact(a Unpacked, b Unpacked) Exact:
	Exact(sign = a.sign != b.sign, e = a.e + b.e, w = mulWide(a.m, b.m))

# x shifted so its leading bit is bit 126, which leaves room for a carry
fn leadingAt126(x Exact):
	shift = x.w.leadingZeros() - 1
	Exact(..x, e = x.e - shift, w = x.w.shl(shift))

# w shifted right by n (any n from 0), and whether a set bit was lost
fn shiftedOut(w Wide, n i64):
	if n == 0: return (w, false)
	q, guard, rest = w.splitAt(n)
	(q, guard or rest)

# a + b, with no bits and no sticky when they cancel
pub fn addExact(a Exact, b Exact) Exact:
	if a.w.isZero(): return b
	if b.w.isZero(): return a
	x = a.leadingAt126()
	y = b.leadingAt126()
	if x.e < y.e:
		swapped = x
		x = y
		y = swapped
	small, lost = y.w.shiftedOut(x.e - y.e)
	if x.sign == y.sign: return Exact(..x, w = x.w.add(small), sticky = lost)
	if x.w.less(small): return Exact(..y, e = x.e, w = small.sub(x.w), sticky = lost)
	diff = x.w.sub(small)
	if lost: diff = diff.sub(Wide(lo = 1))
	Exact(..x, w = diff, sticky = lost)

# a / b: 64 bits of quotient by long division, and whether the remainder is not zero
pub fn divExact(a Unpacked, b Unpacked) Exact:
	sa = a.m.leadingZeros()
	sb = b.m.leadingZeros()
	n = a.m << sa
	d = b.m << sb
	quotient = 0
	carry = false
	loop 64:
		fits = carry or n >= d
		if fits: n -= d
		quotient = quotient << 1 | (1 if fits else 0)
		carry = n >> 63 != 0
		n <<= 1
	Exact(
		sign = a.sign != b.sign,
		e = (a.e - sa) - (b.e - sb) - 63,
		w = Wide(lo = quotient),
		sticky = n != 0 or carry
	)

# the square root of a number
pub fn sqrtExact(a Unpacked) Exact:
	s = a.m.leadingZeros()
	m = a.m << s
	e = a.e - s
	k = 64 if e & 1 == 0 else 63
	radicand = Wide(hi = m, lo = 0) if k == 64 else Wide(hi = m >> 1, lo = m << 63)
	root, inexact = radicand.rootWide()
	Exact(sign = false, e = (e - k) >> 1, w = Wide(lo = root), sticky = inexact)
