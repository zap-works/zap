# Integers of any size: `BigInt`, a sign and a magnitude in limbs of 64 bits, the lowest first,
# with no zero limb at the top (zero has none, and no sign). `BigInt.of(n)`, `BigInt.parse(text)`
# (base 10), `x.toI64()`, `x.decimal()`. The methods that give a new value (`plus`, `minus`,
# `times`, `div`, `rem`, `divRem`, `shiftLeft`, `shiftRight`, `negated`) leave their operands as
# they are; those that change a value in place (`add`, `sub`, `mulSmall`, `addMul`, `setMulAdd`,
# `set`) reuse its limbs, so a loop over them allocates nothing. Division truncates toward zero
# as an i64's does, the remainder taking the dividend's sign; `==` compares values.

pub type BigInt:
	limbs u64[]
	negative bool = false

	# the value as an i64, none when it does not fit
	pub fn toI64() i64?:
		if limbs.isEmpty: return 0
		if limbs.len > 1: return none
		m = limbs[0]
		if negative:
			if m >> 63 != 0 and m << 1 != 0: return none   # past 2^63
			return i64.wrap(0 - m)
		if m >> 63 != 0: return none
		i64(m)

	# the base-10 text, a minus first when negative
	pub fn decimal() str:
		if limbs.isEmpty: return "0"
		rest = limbs.copy()
		chunks = []
		while not rest.isEmpty:
			chunks.push(magDivSmall(rest, decimalChunk))
		out = "-" if negative else ""
		out += "{chunks[chunks.len - 1]}"
		i = chunks.len - 2
		while i >= 0:
			out += "{chunks[i]:019}"
			i -= 1
		out

	# whether the value is 0
	pub fn isZero() bool:
		limbs.isEmpty

	# -1, 0 or 1 as the value is below, equal to or above other
	pub fn compare(other BigInt) i64:
		if negative != other.negative: return -1 if negative else 1
		c = magCompare(limbs, other.limbs)
		-c if negative else c

	# the value becomes other's, in the limbs it has
	pub mut fn set(other BigInt):
		limbs.clear()
		for w in other.limbs:
			limbs.push(w)
		negative = other.negative

	# no zero limb at the top, and zero not negative
	fn normalize():
		trim(limbs)
		if limbs.isEmpty: negative = false

	# the value plus other
	pub mut fn add(other BigInt):
		self.addSigned(other.limbs, other.negative)

	# the value minus other
	pub mut fn sub(other BigInt):
		self.addSigned(other.limbs, not other.negative)

	fn addSigned(b u64[], bNegative bool):
		if b.isEmpty: return
		if limbs.isEmpty or negative == bNegative:
			negative = bNegative
			magAdd(limbs, b)
		elif magCompare(limbs, b) >= 0:
			magSub(limbs, b)
		else:
			magSubFrom(limbs, b)
			negative = bNegative
		self.normalize()

	# the value times k
	pub mut fn mulSmall(k i64):
		if k == 0 or limbs.isEmpty:
			limbs.clear()
			negative = false
			return
		carry = magMulSmall(limbs, magnitudeOf(k))
		if carry != 0:
			limbs.push(carry)
		if k < 0: negative = not negative

	# the value plus b times k
	pub mut fn addMul(b BigInt, k i64):
		if k == 0 or b.limbs.isEmpty: return
		productNegative = b.negative != (k < 0)
		if limbs.isEmpty or negative == productNegative:
			negative = productNegative
			magAddMul(limbs, b.limbs, magnitudeOf(k))
		elif magSubMul(limbs, b.limbs, magnitudeOf(k)):
			negative = not negative   # the product was the larger
		self.normalize()

	# the value becomes b times k plus c, in one pass when the signs agree
	pub mut fn setMulAdd(b BigInt, k i64, c BigInt):
		productNegative = b.negative != (k < 0)
		if k == 0 or b.limbs.isEmpty or not c.limbs.isEmpty and c.negative != productNegative:
			self.set(c)
			self.addMul(b, k)
			return
		magSetMulAdd(limbs, b.limbs, magnitudeOf(k), c.limbs)
		negative = productNegative
		self.normalize()

	# the value becomes itself times x plus b times y, in one pass
	pub mut fn combine(x i64, b BigInt, y i64):
		if x == 0 or y == 0 or limbs.isEmpty or b.limbs.isEmpty:
			self.mulSmall(x)
			self.addMul(b, y)
			return
		ownNegative = negative != (x < 0)
		if ownNegative == (b.negative != (y < 0)):
			magCombine(limbs, magnitudeOf(x), b.limbs, magnitudeOf(y))
			negative = ownNegative
		else:
			negative = ownNegative !=
				magCombineApart(limbs, magnitudeOf(x), b.limbs, magnitudeOf(y))
		self.normalize()

	# the value plus other
	pub fn plus(other BigInt) BigInt:
		r = self.copy()
		r.add(other)
		r

	# the value minus other
	pub fn minus(other BigInt) BigInt:
		r = self.copy()
		r.sub(other)
		r

	# -value
	pub fn negated() BigInt:
		BigInt(limbs = limbs.copy(), negative = not negative and not limbs.isEmpty)

	# the value times other
	pub fn times(other BigInt) BigInt:
		r = BigInt(limbs = magMul(limbs, other.limbs), negative = negative != other.negative)
		r.normalize()
		r

	# the quotient by d, truncated toward zero
	pub fn div(d BigInt) BigInt:
		if d.limbs.isEmpty: fail("a BigInt divided by zero")
		q = BigInt(limbs = magDiv(limbs, d.limbs), negative = negative != d.negative)
		q.normalize()
		q

	# the remainder by d, of the value's sign
	pub fn rem(d BigInt) BigInt:
		_, r = self.divRem(d)
		r

	# the quotient (truncated toward zero) and the remainder (of the value's sign) by d
	pub fn divRem(d BigInt) (BigInt, BigInt):
		if d.limbs.isEmpty: fail("a BigInt divided by zero")
		qs, rs = magDivRem(limbs, d.limbs)
		q = BigInt(limbs = qs, negative = negative != d.negative)
		r = BigInt(limbs = rs, negative)
		q.normalize()
		r.normalize()
		(q, r)

	# the value times 2^n
	pub fn shiftLeft(n i64) BigInt:
		if limbs.isEmpty or n == 0: return self.copy()
		if n < 0: return self.shiftRight(-n)
		words = n / 64
		bits = n % 64
		r u64[] = zeros(words)
		carry = 0
		for w in limbs:
			r.push(w << bits | carry)
			carry = w >> (64 - bits) if bits > 0 else 0
		if carry != 0:
			r.push(carry)
		BigInt(limbs = r, negative)

	# the value divided by 2^n, rounded down (toward minus infinity, as an arithmetic shift)
	pub fn shiftRight(n i64) BigInt:
		if limbs.isEmpty or n == 0: return self.copy()
		if n < 0: return self.shiftLeft(-n)
		words = n / 64
		bits = n % 64
		if words >= limbs.len: return BigInt.of(-1 if negative else 0)
		lost = limbs[..words].any(it != 0) or bits > 0 and limbs[words] << (64 - bits) != 0
		r = []
		for i in words..limbs.len:
			high = limbs[i + 1] << (64 - bits) if bits > 0 and i + 1 < limbs.len else 0
			r.push(limbs[i] >> bits | high)
		q = BigInt(limbs = r, negative)
		q.normalize()
		if negative and lost:
			magAddWord(q.limbs, 1)
		q

	# the value modulo m (m > 0), in 0..m
	pub fn mod(m BigInt) BigInt:
		r = self.rem(m)
		if r.negative: r.add(m)
		r

	# the value to the power e (e >= 0) modulo m (m > 0), in 0..m
	pub fn powMod(e BigInt, m BigInt) BigInt:
		base = self.mod(m)
		r = BigInt.of(1).mod(m)
		i = 64 * e.limbs.len - 1
		while i >= 0:
			r = r.times(r).rem(m)
			if (e.limbs[i / 64] >> (i % 64)) & 1 == 1:
				r = r.times(base).rem(m)
			i -= 1
		r

	# the x in 0..m with the value times x 1 modulo m, none when the two share a factor
	pub fn inverseMod(m BigInt) BigInt?:
		a = self.mod(m)
		b = m.copy()
		x = BigInt.of(1)
		y = BigInt.of(0)
		while not b.isZero():
			q, r = a.divRem(b)
			a = move b
			b = move r
			next = x.minus(q.times(y))
			x = move y
			y = move next
		if a != BigInt.of(1): return none
		x.mod(m)

	# the magnitude as big-endian bytes, n of them (its low bytes when it needs more)
	pub fn bytes(n i64) u8[]:
		out u8[] = zeros(n)
		for i in 0..n.min(8 * limbs.len):
			out[n - 1 - i] = u8.wrap(limbs[i / 8] >> (8 * (i % 8)))
		out

	# how many bits the magnitude takes
	pub fn bitLength() i64:
		if limbs.isEmpty: return 0
		64 * limbs.len - limbs[len - 1].leadingZeros()

# 10^19, the largest power of ten in a limb: the base of the decimal text's chunks
decimalChunk u64 = 10_000_000_000_000_000_000
# the operand length (limbs) from which a product splits in halves (Karatsuba)
karatsubaLimbs = 40

# ---------- making and reading ----------

# n as a BigInt
pub fn of(n i64) BigInt:
	if n == 0: return BigInt(limbs = [])
	BigInt(limbs = [magnitudeOf(n)], negative = n < 0)

# n's absolute value as a word (the smallest i64's too)
fn magnitudeOf(n i64):
	u64(n) if n >= 0 else 0 - u64.wrap(n)

# the integer a decimal text writes (a sign, then digits), none for any other text
pub fn parse(text str) BigInt?:
	neg = text.startsWith("-")
	digits = text[1..] if neg or text.startsWith("+") else text
	if digits.isEmpty: return none
	for c in digits.bytes():
		if not c.isDigit(): return none
	r = BigInt(limbs = [])
	at = digits.len % 19
	if at > 0:
		r.limbs.push(try u64.parse(digits[..at]))
	while at < digits.len:
		carry = magMulSmall(r.limbs, decimalChunk)
		if carry != 0:
			r.limbs.push(carry)
		magAddWord(r.limbs, try u64.parse(digits[at..at + 19]))
		at += 19
	r.negative = neg
	r.normalize()
	r

fn trim(mut a u64[]):
	while not a.isEmpty and a[len - 1] == 0:
		a.pop()

# ---------- in place ----------

# ---------- new values ----------

# ---------- modular arithmetic and bytes (RSA's) ----------

# the non-negative integer of the big-endian bytes
pub fn ofBytes(bytes u8[]) BigInt:
	r = BigInt(limbs = zeros((bytes.len + 7) / 8))
	for i, b in bytes:
		at = bytes.len - 1 - i
		r.limbs[at / 8] |= u64(b) << (8 * (at % 8))
	r.normalize()
	r

# ---------- magnitudes: words, lowest first ----------

fn magCompare(a u64[], b u64[]):
	if a.len != b.len: return 1 if a.len > b.len else -1
	i = a.len - 1
	while i >= 0:
		if a[i] != b[i]: return 1 if a[i] > b[i] else -1
		i -= 1
	0

# a + w (a carry rippling up)
fn magAddWord(mut a u64[], w u64):
	carry = w
	i = 0
	while carry != 0 and i < a.len:
		s = a[i] + carry
		carry = 1 if s < carry else 0
		a[i] = s
		i += 1
	if carry != 0:
		a.push(carry)

# a + b; each carry tested right after its sum and added next, as the compiler takes it into adc
fn magAdd(mut a u64[], b u64[]):
	while a.len < b.len:
		a.push(0)
	carry = 0
	for i, y in b:
		x = a[i]
		s = x + y
		c1 u64 = 1 if s < x else 0
		t = s + carry
		carry = c1 + (1 if t < s else 0)
		a[i] = t
	if carry != 0:
		i = b.len
		while i < a.len and a[i] == ~u64(0):
			a[i] = 0
			i += 1
		if i < a.len:
			a[i] += 1
		else:
			a.push(1)

# a - b, a at least b
fn magSub(mut a u64[], b u64[]):
	borrow = 0
	for i, y in b:
		x = a[i]
		d = x - y
		b1 u64 = 1 if x < y else 0
		r = d - borrow
		borrow = b1 + (1 if d < borrow else 0)
		a[i] = r
	i = b.len
	while borrow != 0:
		x = a[i]
		a[i] = x - 1
		borrow = 1 if x == 0 else 0
		i += 1
	trim(a)

# b - a, b at least a
fn magSubFrom(mut a u64[], b u64[]):
	while a.len < b.len:
		a.push(0)
	borrow = 0
	for i, x in b:
		y = a[i]
		d = x - y
		b1 u64 = 1 if x < y else 0
		r = d - borrow
		borrow = b1 + (1 if d < borrow else 0)
		a[i] = r
	trim(a)

# a * m, the carry out of the top limb given back
fn magMulSmall(mut a u64[], m u64):
	carry = 0
	for i in 0..a.len:
		x = a[i]
		low = x * m
		high = x.mulHigh(m)
		s = low + carry
		carry = high + (1 if s < low else 0)
		a[i] = s
	carry

# a + b * m
fn magAddMul(mut a u64[], b u64[], m u64):
	while a.len < b.len:
		a.push(0)
	carry = magAddMulAt(a, 0, b, m)
	if carry != 0:
		rest = a[b.len..].copy()
		magAddWord(rest, carry)
		a.truncate(b.len)
		for w in rest:
			a.push(w)

# a + b * m at limb `at` of a (b.len limbs there), the carry out of the last given back
fn magAddMulAt(mut a u64[], at i64, b u64[], m u64):
	carry = 0
	for i, y in b:
		x = a[at + i]
		low = y * m
		high = y.mulHigh(m)
		s = x + low
		h1 = high + (1 if s < x else 0)
		t = s + carry
		carry = h1 + (1 if t < s else 0)
		a[at + i] = t
	carry

# a = |a - b * m|; whether b * m was the larger
fn magSubMul(mut a u64[], b u64[], m u64):
	while a.len <= b.len:
		a.push(0)
	borrow = subMulAt(a, 0, b, m)
	for i in b.len..a.len:
		x = a[i]
		a[i] = x - borrow
		borrow = 1 if x < borrow else 0
	if borrow == 0:
		trim(a)
		return false
	# a holds 2^(64 a.len) less the difference: its two's complement is the difference
	negateWords(a)
	trim(a)
	true

# a = b * m + c
fn magSetMulAdd(mut a u64[], b u64[], m u64, c u64[]):
	n = b.len.max(c.len)
	while a.len < n:
		a.push(0)
	a.truncate(n)
	both = b.len.min(c.len)
	carry = 0
	for i in 0..both:
		y = b[i]
		x = c[i]
		low = y * m
		high = y.mulHigh(m)
		s = x + low
		h1 = high + (1 if s < x else 0)
		t = s + carry
		carry = h1 + (1 if t < s else 0)
		a[i] = t
	for i in both..b.len:
		y = b[i]
		low = y * m
		high = y.mulHigh(m)
		s = low + carry
		carry = high + (1 if s < low else 0)
		a[i] = s
	for i in both..c.len:
		x = c[i]
		s = x + carry
		carry = 1 if s < x else 0
		a[i] = s
	if carry != 0:
		a.push(carry)

# a = a * x + b * y
fn magCombine(mut a u64[], x u64, b u64[], y u64):
	own = a.len
	while a.len < b.len:
		a.push(0)
	both = own.min(b.len)
	carry = 0
	for i in 0..both:
		v = a[i]
		low = v * x
		high = v.mulHigh(x)
		w = b[i]
		otherLow = w * y
		otherHigh = w.mulHigh(y)
		s = low + otherLow
		h1 = otherHigh + (1 if s < otherLow else 0)
		h2 = h1 + high
		t = s + carry
		carry = h2 + (1 if t < s else 0)
		a[i] = t
	for i in both..own:
		v = a[i]
		low = v * x
		high = v.mulHigh(x)
		s = low + carry
		carry = high + (1 if s < low else 0)
		a[i] = s
	for i in both..b.len:
		w = b[i]
		low = w * y
		high = w.mulHigh(y)
		s = low + carry
		carry = high + (1 if s < low else 0)
		a[i] = s
	if carry != 0:
		a.push(carry)

# a = |a * x - b * y|; whether b * y was the larger: the sum's carry and the difference's borrow
# each a chain of its own
fn magCombineApart(mut a u64[], x u64, b u64[], y u64):
	own = a.len
	while a.len < b.len:
		a.push(0)
	carry = 0
	borrow = 0
	for i, w in b:
		v = a[i]
		low = v * x
		high = v.mulHigh(x)
		s = low + carry
		carry = high + (1 if s < low else 0)
		otherLow = w * y
		otherHigh = w.mulHigh(y)
		d = s - otherLow
		h = otherHigh + (1 if s < otherLow else 0)
		r = d - borrow
		borrow = h + (1 if d < borrow else 0)
		a[i] = r
	for i in b.len..own:
		v = a[i]
		low = v * x
		high = v.mulHigh(x)
		s = low + carry
		carry = high + (1 if s < low else 0)
		r = s - borrow
		borrow = 1 if s < borrow else 0
		a[i] = r
	if carry >= borrow:
		if carry > borrow:
			a.push(carry - borrow)
		return false
	# a holds the difference plus (borrow - carry) words above it: negated, the magnitude
	top = borrow - carry - (0 if negateWords(a) else 1)
	if top != 0:
		a.push(top)
	true

# a = 2^(64 a.len) - a (0 for 0); whether a was 0
fn negateWords(mut a u64[]):
	zeros = 0
	while zeros < a.len and a[zeros] == 0:
		zeros += 1
	if zeros == a.len: return true
	a[zeros] = 0 - a[zeros]
	for i in zeros + 1..a.len:
		a[i] = ~a[i]
	false

# a / d in place, the remainder given back
fn magDivSmall(mut a u64[], d u64):
	r = 0
	i = a.len - 1
	while i >= 0:
		q, rest = divWide(r, a[i], d)
		a[i] = q
		r = rest
		i -= 1
	trim(a)
	r

# (hi * 2^64 + lo) / d and its remainder, hi below d (Hacker's Delight's divlu: the divisor
# shifted to its top bit, two digits of 32 bits each estimated and corrected)
fn divWide(hi u64, lo u64, d u64):
	s = d.leadingZeros()
	dn = d << s
	top = hi << s | (lo >> (64 - s) if s > 0 else 0)
	low = lo << s
	dHigh = dn >> 32
	dLow = dn & 0xFFFF_FFFF
	q1, mid = divDigit(top, low >> 32, dHigh, dLow)
	q0, rest = divDigit(mid, low & 0xFFFF_FFFF, dHigh, dLow)
	(q1 << 32 | q0, rest >> s)

# one 32-bit digit of the quotient of (n * 2^32 + next) by the divisor dHigh:dLow (its top bit
# set), and the remainder
fn divDigit(n u64, next u64, dHigh u64, dLow u64):
	q = n / dHigh
	rhat = n - q * dHigh
	while q >> 32 != 0 or q * dLow > (rhat << 32 | next):
		q -= 1
		rhat += dHigh
		if rhat >> 32 != 0: break
	(q, (n << 32 | next) - q * (dHigh << 32 | dLow))

# ---------- products ----------

# a * b
fn magMul(a u64[], b u64[]) u64[]:
	if a.isEmpty or b.isEmpty: return []
	if a.len.min(b.len) < karatsubaLimbs: return schoolbook(a, b)
	karatsuba(a, b)

# a * b by rows: each limb of a times b added at its place
fn schoolbook(a u64[], b u64[]):
	r u64[] = zeros(a.len + b.len)
	for i in 0..a.len:
		r[i + b.len] = magAddMulAt(r, i, b, a[i])
	trim(r)
	r

# a * b by halves: (a1 B + a0)(b1 B + b0) = z2 B^2 + ((a0 + a1)(b0 + b1) - z0 - z2) B + z0, the
# shorter split as the longer is when it reaches past the half, else its product with each half
fn karatsuba(a u64[], b u64[]) u64[]:
	h = (a.len.max(b.len) + 1) / 2
	a0 = lowHalf(a, h)
	a1 = highHalf(a, h)
	b0 = lowHalf(b, h)
	b1 = highHalf(b, h)
	if a1.isEmpty or b1.isEmpty:
		r = magMul(a0, b0)
		magAddAt(r, h, magMul(a1, b) if b1.isEmpty else magMul(a, b1))
		return r
	z0 = magMul(a0, b0)
	z2 = magMul(a1, b1)
	sa = a0.copy()
	magAdd(sa, a1)
	sb = b0.copy()
	magAdd(sb, b1)
	z1 = magMul(sa, sb)
	magSub(z1, z0)
	magSub(z1, z2)
	r = z0.copy()
	magAddAt(r, h, z1)
	magAddAt(r, 2 * h, z2)
	r

fn lowHalf(a u64[], h i64):
	r = a[..h.min(len)].copy()
	trim(r)
	r

fn highHalf(a u64[], h i64) u64[]:
	a[h..].copy() if a.len > h else []

# a + b * 2^(64 at)
fn magAddAt(mut a u64[], at i64, b u64[]):
	if b.isEmpty: return
	while a.len < at:
		a.push(0)
	high = a[at..].copy()
	magAdd(high, b)
	a.truncate(at)
	for w in high:
		a.push(w)

# ---------- quotients ----------

# a / b
fn magDiv(a u64[], b u64[]):
	if b.len == 1:
		q = a.copy()
		magDivSmall(q, b[0])
		return q
	if magCompare(a, b) < 0: return []
	if quotientWord(a, b) is q: return [q] if q != 0 else []
	q, _ = magDivRem(a, b)
	q

# a / b when the quotient is one word that the top 128 bits of a over the top 64 of b tell for
# certain: a's bits from b's 64th highest on, `at`, against b's top 64, `bt`, bound the quotient
# between at / (bt + 1) and (at + 1) / bt; none when those differ (or a reaches too high)
fn quotientWord(a u64[], b u64[]) u64?:
	s = b[len - 1].leadingZeros()
	e = 64 * b.len - s - 64   # b's bits below its top 64
	if 64 * a.len - a[len - 1].leadingZeros() > e + 128: return none
	bt = bitsAt(b, e)
	atHigh = bitsAt(a, e + 64)
	atLow = bitsAt(a, e)
	if bt == ~u64(0) or atHigh >= bt: return none
	low, _ = divWide(atHigh, atLow, bt + 1)
	nextLow = atLow + 1
	high, _ = divWide(atHigh + (1 if nextLow == 0 else 0), nextLow, bt)
	low if low == high else none

# the 64 bits of a from bit e (0 past its top)
fn bitsAt(a u64[], e i64):
	w = e / 64
	o = e % 64
	low = a[w] >> o if w < a.len else 0
	if o == 0 or w + 1 >= a.len: return low
	low | a[w + 1] << (64 - o)

# a / b and a % b, b of two limbs or more (Knuth's algorithm D: both shifted so b's top bit is
# set, each quotient word estimated from the top two words over b's top one, corrected by b's
# next, the product taken off and added back the rare time the estimate was one too high)
fn magDivRem(a u64[], b u64[]):
	if b.len == 1:
		q = a.copy()
		r = magDivSmall(q, b[0])
		return (q, [r] if r != 0 else [])
	if magCompare(a, b) < 0: return ([], a.copy())
	s = b[len - 1].leadingZeros()
	bn = shiftedWords(b, s, b.len)
	an = shiftedWords(a, s, a.len + 1)
	n = b.len
	q u64[] = zeros(a.len - n + 1)
	j = a.len - n
	while j >= 0:
		qhat = estimateWord(an, j, bn)
		borrow = subMulAt(an, j, bn, qhat)
		if borrow > an[j + n]:
			an[j + n] -= borrow
			q[j] = qhat - 1
			an[j + n] += magAddAt0(an, j, bn)
		else:
			an[j + n] -= borrow
			q[j] = qhat
		j -= 1
	an.truncate(n)
	r = shiftedDown(an, s)
	trim(q)
	trim(r)
	(q, r)

# the words of a shifted left by s bits (below 64), n of them
fn shiftedWords(a u64[], s i64, n i64):
	r = []
	carry = 0
	for w in a:
		r.push(w << s | carry)
		carry = w >> (64 - s) if s > 0 else 0
	if r.len < n:
		r.push(carry)
	r

# the words of a shifted right by s bits (below 64)
fn shiftedDown(a u64[], s i64):
	if s == 0: return a.copy()
	r = []
	for i in 0..a.len:
		high = a[i + 1] << (64 - s) if i + 1 < a.len else 0
		r.push(a[i] >> s | high)
	r

# Knuth's estimate of the quotient word at j: an's words j + n and j + n - 1 over bn's top,
# lowered while it times bn's next word passes what is left over the next of an
fn estimateWord(an u64[], j i64, bn u64[]):
	n = bn.len
	top = an[j + n]
	dHigh = bn[n - 1]
	qhat = ~u64(0)
	rhat = an[j + n - 1]
	if top < dHigh:
		qhat, rhat = divWide(top, an[j + n - 1], dHigh)
	else:
		rhat += dHigh
		if rhat < dHigh: return qhat   # past a word: the estimate stands
	dNext = bn[n - 2]
	while true:
		pHigh = qhat.mulHigh(dNext)
		pLow = qhat * dNext
		if pHigh < rhat or pHigh == rhat and pLow <= an[j + n - 2]: break
		qhat -= 1
		old = rhat
		rhat += dHigh
		if rhat < old: break
	qhat

# a's n words from j less b * m, the borrow out of the last given back
fn subMulAt(mut a u64[], j i64, b u64[], m u64):
	borrow = 0
	for i, y in b:
		x = a[j + i]
		low = y * m
		high = y.mulHigh(m)
		d = x - low
		h1 = high + (1 if x < low else 0)
		r = d - borrow
		borrow = h1 + (1 if d < borrow else 0)
		a[j + i] = r
	borrow

# a's words from j plus b, the carry out given back
fn magAddAt0(mut a u64[], j i64, b u64[]):
	carry = 0
	for i in 0..b.len:
		x = a[j + i]
		s = x + b[i]
		c1 u64 = 1 if s < x else 0
		t = s + carry
		carry = c1 + (1 if t < s else 0)
		a[j + i] = t
	carry

# ---------- tests ----------

fn big(text str):
	parse(text) ?? fail("not a number: {text}")

test "a BigInt made, read and written":
	print("{BigInt.of(0).decimal()} {BigInt.of(-42).decimal()} {BigInt.of(-9_223_372_036_854_775_807 - 1).decimal()}")
	x = big("-123456789012345678901234567890")
	print("{x.decimal()} {x.toI64()} {big("+77").toI64()} {big("-9223372036854775808").toI64()}")
	print("{parse("12a")} {parse("-")} {parse("")} {big("000").decimal()} {big("-0").negative}")
	print(big("18446744073709551616").limbs)
	prints """
		0 -42 -9223372036854775808
		-123456789012345678901234567890 none some(77) some(-9223372036854775808)
		none none none 0 false
		[0, 1]
		"""

test "sums and differences across signs and limbs":
	a = big("340282366920938463463374607431768211455")   # 2^128 - 1
	one = BigInt.of(1)
	print(a.plus(one).decimal())
	print(a.plus(one).minus(one).minus(a).decimal())
	print(one.minus(a).decimal())
	print(a.negated().plus(a.plus(a)).decimal())
	c = BigInt.of(5)
	c.sub(BigInt.of(8))
	c.add(BigInt.of(-2))
	print("{c.decimal()} {c.compare(BigInt.of(-6))} {c.compare(one)} {a.compare(one)} {c == BigInt.of(-5)}")
	prints """
		340282366920938463463374607431768211456
		0
		-340282366920938463463374607431768211454
		340282366920938463463374607431768211455
		-5 1 -1 1 true
		"""

test "products, small and large, agree with each other":
	f = BigInt.of(1)
	for k in 1..=30:
		f.mulSmall(k)
	print(f.decimal())
	p = BigInt.of(3)
	q = BigInt.of(1)
	loop 3000:
		q.mulSmall(3)
	loop 11:
		p = p.times(p)   # 3^2048
	print("{p.limbs.len} {q.div(p).times(p).plus(q.rem(p)) == q}")
	print(p.times(p).minus(BigInt.of(1)).rem(p.plus(BigInt.of(1))).isZero())
	big1 = q.times(p)
	print(schoolbook(q.limbs, p.limbs) == big1.limbs)
	f.mulSmall(-1)
	print("{f.times(f).decimal()} {f.times(BigInt.of(0)).decimal()}")
	g = q.copy()
	g.combine(-7, f, 1_000_000_007)
	h = q.copy()
	h.combine(7, f, -1_000_000_007)
	print(
		"{g == q.times(BigInt.of(-7)).plus(f.times(BigInt.of(1_000_000_007)))} {g == h.negated()}"
	)
	pairs = [(f.copy(), q.copy()), (q.copy(), f.copy()), (f.copy(), f.negated()),
		(p.copy(), BigInt.of(-1)), (BigInt.of(-1), p.copy())]
	for (x, y) in [(3, 2), (-3, 2), (3, -2), (-3, -2), (1, -1), (5, 0)]:
		for (u, v) in pairs:
			z = u.copy()
			z.combine(x, v, y)
			if z != u.times(BigInt.of(x)).plus(v.times(BigInt.of(y))): print("combine {x} {y}")
	prints """
		265252859812191058636308480000000
		51 true
		true
		true
		70359079638545882374689246780656119576032161719910400000000000000 0
		true true
		"""

test "in-place sums of products cross zero":
	a = BigInt.of(10)
	a.addMul(BigInt.of(3), -4)
	print(a.decimal())
	a.addMul(big("100000000000000000000000"), 1)
	a.addMul(big("100000000000000000000000"), -2)
	print(a.decimal())
	t = BigInt.of(0)
	t.setMulAdd(big("-18446744073709551615"), 3, BigInt.of(-7))
	print(t.decimal())
	t.setMulAdd(big("18446744073709551615"), 3, BigInt.of(-7))
	print(t.decimal())
	prints """
		-2
		-100000000000000000000002
		-55340232221128654852
		55340232221128654838
		"""

test "quotients and remainders truncate toward zero":
	a = big("1000000000000000000000000000000000000007")
	b = big("-12345678901234567890123")
	q, r = a.divRem(b)
	print("{q.decimal()} {r.decimal()} {q.times(b).plus(r) == a}")
	print("{a.negated().div(BigInt.of(7)).decimal()} {a.negated().rem(BigInt.of(10)).decimal()}")
	print("{BigInt.of(-7).div(BigInt.of(2)).decimal()} {BigInt.of(-7).rem(BigInt.of(2)).decimal()}")
	n = big("123456789123456789123456789123456789123456789")
	d = big("13717421013717421013717421")
	print("{n.div(d).decimal()} {n.times(d).div(d) == n} {n.div(n.plus(BigInt.of(1))).decimal()}")
	prints """
		-81000000729000006 7825963600692925659269 true
		-142857142857142857142857142857142857143 -7
		-3 -1
		9000000000000000000 true 0
		"""

test "every quotient of a long division checked by its product":
	x = BigInt.of(7)
	y = BigInt.of(3)
	for i in 0..400:
		x.mulSmall(1_000_003 + i)
		if i % 3 == 0:
			y.mulSmall(999_983 - i)
		x.add(BigInt.of(i))
		q, r = x.divRem(y)
		if q.times(y).plus(r) != x or r.compare(y) >= 0 or r.negative: print("wrong at {i}")
		if q != x.div(y): print("the quotient differs at {i}")
	print("checked")
	prints "checked"

test "shifts are by powers of two, rounding down":
	x = big("-1000000000000000000000000000001")
	print("{x.shiftLeft(70).decimal()} {x.shiftRight(70).decimal()} {x.negated().shiftRight(70).decimal()}")
	print("{BigInt.of(-1).shiftRight(1000).decimal()} {BigInt.of(5).shiftRight(-2).decimal()} {x.shiftLeft(64).shiftRight(64) == x}")
	prints """
		-1180591620717411303424000000001180591620717411303424 -847032948 847032947
		-1 20 true
		"""

test "powers and inverses modulo a number, and big-endian bytes":
	m = big("170141183460469231731687303715884105727")   # 2^127 - 1, a prime
	x = big("12345678901234567890")
	print(x.powMod(m.minus(BigInt.of(1)), m).decimal())   # Fermat: 1
	print(BigInt.of(3).powMod(BigInt.of(200), BigInt.of(1000)).decimal())
	inverse = x.inverseMod(m) ?? BigInt.of(0)
	print(x.times(inverse).mod(m).decimal())
	print("{BigInt.of(6).inverseMod(BigInt.of(9))} {BigInt.of(-7).mod(BigInt.of(5)).decimal()}")
	b = ofBytes([1, 2, 3, 4, 5, 6, 7, 8, 9])
	print("{b.decimal()} {b.bytes(10)} {b.bitLength()} {BigInt.of(0).bitLength()}")
	prints """
		1
		1
		1
		none 3
		18591708106338011145 [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] 65 0
		"""
