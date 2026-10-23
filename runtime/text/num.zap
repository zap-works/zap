# Numbers: checked integer power, float helpers, conversions, formatting and parsing.
# Floats travel as their 64-bit bit patterns (i64) between the generated code and here. The
# digit machinery works on ASCII digits in a u8[]; the public entry points convert to and
# from `str`.

fn shl1(n i64) i64:
	1 << n

fn bitsNeg(b i64) i64:
	b ^ (-9_223_372_036_854_775_807 - 1)

# base ** e for integers: wrapping multiplication (the caller truncates to the width of the
# type), a negative exponent gives 0
# base ** e of bits, wrapping
fn upow(base u64, e u64) u64:
	r u64 = 1
	b = base
	n = e
	while n > 0:
		if n & 1 == 1:
			r *= b
		n >>= 1
		b *= b
	r

fn ipow(base i64, e i64) i64:
	if e < 0: return 0
	r i64 = 1
	b = base
	n = e
	while n > 0:
		if n % 2 == 1:
			r *= b
		n /= 2
		if n > 0:
			b *= b
	r

# float -> integer: truncate toward zero, saturate, NaN -> 0
fn f2i(bits64 i64, bits i64, signed bool) i64:
	x = f64.fromBits(u64(bits64))
	if x != x: return 0
	lo i64 = 0
	hi i64 = 0
	if bits == 64:
		if signed:
			if x >= 9223372036854775807.0: return 9_223_372_036_854_775_807
			if x <= -9223372036854775808.0: return -9_223_372_036_854_775_808
			return __ftoi(x)
		if x <= 0.0: return 0
		if x >= 18446744073709551615.0: return -1
		if x >= 9223372036854775808.0:
			return __ftoi(x - 9223372036854775808.0) + -9_223_372_036_854_775_808
		return __ftoi(x)
	if signed:
		hi = shl1(bits - 1) - 1
		lo = -(shl1(bits - 1))
	else:
		hi = shl1(bits) - 1
	if x >= f64(hi): return hi
	if x <= f64(lo): return lo
	__ftoi(x)

# round half away from zero (C's round)
fn fround(bits64 i64) i64:
	x = f64.fromBits(u64(bits64))
	r = x.floor()
	if x - r >= 0.5:
		r += 1.0
	if x < 0.0:
		c = x.ceil()
		r = c
		if c - x >= 0.5:
			r = c - 1.0
	i64(r.toBits())

# the remainder of a / b for floats (the sign of a), as f64 bits: a float's % (the compiler
# calls it)
fn remBits(a64 i64, b64 i64) i64:
	a = f64.fromBits(u64(a64))
	b = f64.fromBits(u64(b64))
	if b == 0.0 or a != a or b != b: return i64((0.0 / 0.0).toBits())
	q = (a / b).trunc()
	i64((a - q * b).toBits())

# base ** n for n >= 0 by repeated squaring
fn powi(base f64, n i64) f64:
	r = 1.0
	b = base
	k = n
	while k > 0:
		if k % 2 == 1:
			r *= b
		b *= b
		k /= 2
	r

# a ** b for floats, as f64 bits
fn fpow(a64 i64, b64 i64) i64:
	a = f64.fromBits(u64(a64))
	b = f64.fromBits(u64(b64))
	if b == 0.0: return i64(1.0.toBits())
	if a == 1.0: return i64(1.0.toBits())
	if a != a or b != b: return i64((0.0 / 0.0).toBits())
	# integer exponents by repeated squaring (exact for small cases)
	if b == b.floor() and b > -1024.0 and b < 1024.0:
		n = __ftoi(b)
		if n < 0: return i64((1.0 / powi(a, -n)).toBits())
		return i64(powi(a, n).toBits())
	if b == 0.5 and a >= 0.0: return i64(a.sqrt().toBits())
	if a < 0.0: return i64((0.0 / 0.0).toBits())
	i64(f64Exp(b * f64Ln(a)).toBits())

# ---------- exact decimal expansions ----------
# A decimal number as its significant digits (ASCII, no leading zeros) and the position of
# the decimal point: the number of integer digits, which may be negative (leading zeros
# after the point) or beyond the digits (trailing zeros before the point).
type Decimal:
	digits u8[]
	point i64

# big integers as base-1e9 limbs, little endian
fn bigFromU64(v i64) i64[]:
	b i64[] = []
	x = v
	while x != 0:
		b.push(i64(u64(x) % 1_000_000_000))
		x = i64(u64(x) / 1_000_000_000)
	b

fn bigMulSmall(mut b i64[], m i64):
	carry i64 = 0
	for i in 0..b.len:
		v = b[i] * m + carry
		b[i] = v % 1_000_000_000
		carry = v / 1_000_000_000
	while carry != 0:
		b.push(carry % 1_000_000_000)
		carry /= 1_000_000_000

# the decimal digits of the big integer
fn bigDigits(b i64[]) u8[]:
	s u8[] = []
	n = b.len
	if n == 0:
		s.push(48)
		return s
	pushInt(s, b[n - 1])
	i = n - 2
	while i >= 0:
		limb = b[i]
		p i64 = 100_000_000   # nine digits, zero-padded
		while p > 0:
			s.push(u8(48 + (limb / p) % 10))
			p /= 10
		i -= 1
	s

# the exact decimal of m * 2^e (m < 2^53)
fn exactDecimal(m i64, e i64) Decimal:
	b = bigFromU64(m)
	if e >= 0:
		k = e
		while k > 0:
			step = k.min(29)
			bigMulSmall(b, shl1(step))
			k -= step
		digits = bigDigits(b)
		return Decimal(digits = digits, point = digits.len)
	# m / 2^-e = m * 5^-e / 10^-e
	k = -e
	while k > 0:
		step = k.min(13)
		bigMulSmall(b, ipow(5, step))
		k -= step
	digits = bigDigits(b)
	Decimal(digits = digits, point = digits.len + e)

# a double's magnitude as m * 2^e, m an integer below 2^53
type BinaryParts:
	m i64
	e i64

# the m and e of the double with the given bits (the sign ignored)
fn binaryParts(bits i64) BinaryParts:
	exp = (bits >> 52) & 2047
	mant = bits & 4_503_599_627_370_495
	if exp == 0:
		return BinaryParts(m = mant, e = -1074)   # subnormal
	BinaryParts(m = mant + 4_503_599_627_370_496, e = exp - 1075)

# the exact decimal of the double with the given bits
fn exactDigitsOf(bits i64) Decimal:
	p = binaryParts(bits)
	exactDecimal(p.m, p.e)

# digit i of a decimal, counted from its first significant digit (zeros beyond the digits)
fn digitAt(d Decimal, i i64) i64:
	if i < 0 or i >= d.digits.len: return 0
	i64(d.digits[i]) - 48

fn trailingZeros(d Decimal, start i64) bool:
	i = start
	while i < d.digits.len:
		if d.digits[i] != 48: return false
		i += 1
	true

# compares the number (digits a, point pa) with b; both without leading zeros
fn compareDigits(a u8[], pa i64, b Decimal) i64:
	if pa != b.point:
		if pa > b.point: return 1
		return -1
	an = a.len
	bn = b.digits.len
	n = an
	if bn > n:
		n = bn
	i i64 = 0
	while i < n:
		x i64 = 0
		y i64 = 0
		if i < an:
			x = i64(a[i]) - 48
		if i < bn:
			y = i64(b.digits[i]) - 48
		if x != y:
			if x > y: return 1
			return -1
		i += 1
	0

# adds one to the decimal digit string; true when it carried out (the digits are then
# 1 followed by zeros and the caller moves the point)
fn incrementDigits(mut d u8[]) bool:
	j = d.len - 1
	while j >= 0:
		c = i64(d[j]) + 1
		if c > 57:
			d[j] = 48
			j -= 1
		else:
			d[j] = u8(c)
			return false
	if d.len > 0:
		d[0] = 49
	true

fn stripTrailingZeros(mut d u8[]):
	while d.len > 1 and d[len - 1] == 48:
		_ = d.pop()

# ---------- the shortest digits (Ryu) ----------
# Ulf Adams's Ryu (2018): the shortest decimal that reads back as the double, found from the
# double's interval scaled by 128-bit approximations of 5^i (and 2^k / 5^i) with ryuBits bits.
# Those of every ryuStep-th power are kept; the rest are made from them times 5^offset, the error
# of each made one corrected by its 2 bits in the offsets (16 powers a word).

ryuBits = 125
ryuStep = 26

# 5^0 .. 5^25, exact
pow5Small u64[] = [
	1,
	5,
	25,
	125,
	625,
	3_125,
	15_625,
	78_125,
	390_625,
	1_953_125,
	9_765_625,
	48_828_125,
	244_140_625,
	1_220_703_125,
	6_103_515_625,
	30_517_578_125,
	152_587_890_625,
	762_939_453_125,
	3_814_697_265_625,
	19_073_486_328_125,
	95_367_431_640_625,
	476_837_158_203_125,
	2_384_185_791_015_625,
	11_920_928_955_078_125,
	59_604_644_775_390_625,
	298_023_223_876_953_125]

# 5^i for i = 0, 26, 52 ..., ryuBits bits: the low word, then the high
pow5Split u64[] = [
	0,
	1_152_921_504_606_846_976,
	0,
	1_490_116_119_384_765_625,
	1_032_610_780_636_961_552,
	1_925_929_944_387_235_853,
	7_910_200_175_544_436_838,
	1_244_603_055_572_228_341,
	16_941_905_809_032_713_930,
	1_608_611_746_708_759_036,
	13_024_893_955_298_202_172,
	2_079_081_953_128_979_843,
	6_607_496_772_837_067_824,
	1_343_575_221_513_417_750,
	17_332_926_989_895_652_603,
	1_736_530_273_035_216_783,
	13_037_379_183_483_547_984,
	2_244_412_773_384_604_712,
	1_605_989_338_741_628_675,
	1_450_417_759_929_778_918,
	9_630_225_068_416_591_280,
	1_874_621_017_369_538_693,
	665_883_850_346_957_067,
	1_211_445_438_634_777_304,
	14_931_890_668_723_713_708,
	1_565_756_531_257_009_982]

# 2^(ryuBits - 1 + bits of 5^i) / 5^i + 1 for i = 0, 26, 52 ..., low then high
pow5InvSplit u64[] = [
	1,
	2_305_843_009_213_693_952,
	5_955_668_970_331_000_884,
	1_784_059_615_882_449_851,
	8_982_663_654_677_661_702,
	1_380_349_269_358_112_757,
	7_286_864_317_269_821_294,
	2_135_987_035_920_910_082,
	7_005_857_020_398_200_553,
	1_652_639_921_975_621_497,
	17_965_325_103_354_776_697,
	1_278_668_206_209_430_417,
	8_928_596_168_509_315_048,
	1_978_643_211_784_836_272,
	10_075_671_573_058_298_858,
	1_530_901_034_580_419_511,
	597_001_226_353_042_382,
	1_184_477_304_306_571_148,
	1_527_430_471_115_325_346,
	1_832_889_850_782_397_517,
	12_533_209_867_169_019_542,
	1_418_129_833_677_084_982,
	5_577_825_024_675_947_042,
	2_194_449_627_517_475_473,
	11_006_974_540_203_867_551,
	1_697_873_161_311_732_311,
	10_313_493_231_639_821_582,
	1_313_665_730_009_899_186,
	12_701_016_819_766_672_773,
	2_032_799_256_770_390_445]

# what each 5^i made from pow5Split lacks, 2 bits a power
pow5Corrections u64[] = [
	0,
	0,
	0,
	0,
	1_073_741_824,
	1_500_076_437,
	1_431_590_229,
	1_448_432_917,
	1_091_896_580,
	1_079_333_904,
	1_146_442_053,
	1_146_111_296,
	1_163_220_304,
	1_073_758_208,
	2_521_039_936,
	1_431_721_317,
	1_413_824_581,
	1_075_134_801,
	1_431_671_125,
	1_363_170_645,
	261]

# the same for pow5InvSplit
pow5InvCorrections u64[] = [
	1_414_808_916,
	67_458_373,
	268_701_696,
	4_195_348,
	1_073_807_360,
	1_091_917_141,
	1_108,
	65_604,
	1_073_741_824,
	1_140_850_753,
	1_346_716_752,
	1_431_634_004,
	1_365_595_476,
	1_073_758_208,
	16_777_217,
	66_816,
	1_364_284_433,
	89_478_484,
	1_346_442_496,
	1_074_003_968,
	84_148_496,
	0]

# a 128-bit number: its high and low words
type Wide:
	hi u64
	lo u64

# a * b, all 128 bits
fn wideMul(a u64, b u64) Wide:
	aLo = a & 4_294_967_295
	aHi = a >> 32
	bLo = b & 4_294_967_295
	bHi = b >> 32
	mid1 = aHi * bLo
	mid2 = aLo * bHi
	carry = ((aLo * bLo) >> 32) + (mid1 & 4_294_967_295) + (mid2 & 4_294_967_295)
	Wide(hi = aHi * bHi + (mid1 >> 32) + (mid2 >> 32) + (carry >> 32), lo = a * b)

# the 64 bits of hi:lo from bit dist (0 < dist < 64)
fn wideShift(hi u64, lo u64, dist i64) u64:
	(hi << u64(64 - dist)) | (lo >> u64(dist))

# m times the 128-bit scale (its low word less dropLow), the 192 bits shifted right by dist and
# cut to 128, the correction added: a power of five made from a kept one
fn scaleWords(m u64, scale Wide, dropLow u64, dist i64, correction u64) Wide:
	high = wideMul(m, scale.hi)
	low = wideMul(m, scale.lo - dropLow)
	sum = low.hi + high.lo
	top = high.hi + (1 if sum < low.hi else 0)
	Wide(hi = wideShift(top, sum, dist), lo = wideShift(sum, low.lo, dist) + correction)

# 5^i as Ryu scales by it (ryuBits bits)
fn pow5Scale(i i64) Wide:
	base = i / ryuStep
	offset = i - base * ryuStep
	kept = Wide(hi = pow5Split[2 * base + 1], lo = pow5Split[2 * base])
	if offset == 0: return kept
	delta = pow5Bits(i) - pow5Bits(base * ryuStep)
	scaleWords(pow5Small[offset], kept, 0, delta, ryuCorrection(pow5Corrections, i))

# 2^(ryuBits - 1 + the bits of 5^i) / 5^i, rounded up, as Ryu scales by it
fn pow5InvScale(i i64) Wide:
	base = (i + ryuStep - 1) / ryuStep
	offset = base * ryuStep - i
	kept = Wide(hi = pow5InvSplit[2 * base + 1], lo = pow5InvSplit[2 * base])
	if offset == 0: return kept
	delta = pow5Bits(base * ryuStep) - pow5Bits(i)
	scaleWords(pow5Small[offset], kept, 1, delta, 1 + ryuCorrection(pow5InvCorrections, i))

fn ryuCorrection(words u64[], i i64) u64:
	(words[i / 16] >> u64((i % 16) * 2)) & 3

# the bits of 5^e (1 for e = 0), for 0 <= e <= 3528
fn pow5Bits(e i64) i64:
	((e * 1_217_359) >> 19) + 1

# floor(log10(2^e)), for 0 <= e <= 1650
fn log10Pow2(e i64) i64:
	(e * 78_913) >> 18

# floor(log10(5^e)), for 0 <= e <= 2620
fn log10Pow5(e i64) i64:
	(e * 732_923) >> 20

# how many times 5 divides v (v > 0)
fn pow5Factor(v u64) i64:
	x = v
	n = 0
	while x % 5 == 0:
		x /= 5
		n += 1
	n

# (m * scale) >> j, for 64 < j < 128
fn mulShift(m u64, scale Wide, j i64) u64:
	high = wideMul(m, scale.hi)
	sum = wideMul(m, scale.lo).hi + high.lo
	top = high.hi + (1 if sum < high.lo else 0)
	wideShift(top, sum, j - 64)

# A decimal number: digits (an integer, no trailing zero) times 10^exp
type ShortDecimal:
	digits u64
	exp i64

# the shortest decimal that reads back as the positive finite double of these bits (Ryu)
fn shortestDecimal(bits u64) ShortDecimal:
	mantissa = bits & 4_503_599_627_370_495
	biased = i64((bits >> 52) & 2047)
	e2 = (1 if biased == 0 else biased) - 1077
	m2 = mantissa if biased == 0 else mantissa | 4_503_599_627_370_496
	even = m2 & 1 == 0
	mv = 4 * m2
	mmShift u64 = 1 if mantissa != 0 or biased <= 1 else 0
	vr u64 = 0
	vp u64 = 0
	vm u64 = 0
	e10 = 0
	vmZeros = false   # whether the dropped digits of vm (vr) are all zeros
	vrZeros = false
	if e2 >= 0:
		q = log10Pow2(e2) - (1 if e2 > 3 else 0)
		e10 = q
		j = -e2 + q + ryuBits + pow5Bits(q) - 1
		scale = pow5InvScale(q)
		vr = mulShift(mv, scale, j)
		vp = mulShift(mv + 2, scale, j)
		vm = mulShift(mv - 1 - mmShift, scale, j)
		if q <= 21:
			if mv % 5 == 0:
				vrZeros = pow5Factor(mv) >= q
			elif even:
				vmZeros = pow5Factor(mv - 1 - mmShift) >= q
			elif pow5Factor(mv + 2) >= q:
				vp -= 1
	else:
		q = log10Pow5(-e2) - (1 if -e2 > 1 else 0)
		e10 = q + e2
		i = -e2 - q
		j = q - (pow5Bits(i) - ryuBits)
		scale = pow5Scale(i)
		vr = mulShift(mv, scale, j)
		vp = mulShift(mv + 2, scale, j)
		vm = mulShift(mv - 1 - mmShift, scale, j)
		if q <= 1:
			vrZeros = true
			if even:
				vmZeros = mmShift == 1
			else:
				vp -= 1
		elif q < 63:
			vrZeros = mv & ((u64(1) << u64(q)) - 1) == 0
	removed = 0
	out u64 = 0
	if vmZeros or vrZeros:
		last u64 = 0   # the last digit of vr dropped
		while vp / 10 > vm / 10:
			vmZeros = vmZeros and vm % 10 == 0
			vrZeros = vrZeros and last == 0
			last = vr % 10
			vr /= 10
			vp /= 10
			vm /= 10
			removed += 1
		if vmZeros:
			while vm % 10 == 0:
				vrZeros = vrZeros and last == 0
				last = vr % 10
				vr /= 10
				vp /= 10
				vm /= 10
				removed += 1
		if vrZeros and last == 5 and vr % 2 == 0:
			last = 4   # exactly half: to even
		out = vr + (1 if vr == vm and (not even or not vmZeros) or last >= 5 else 0)
	else:
		up = false
		if vp / 100 > vm / 100:
			up = vr % 100 >= 50
			vr /= 100
			vp /= 100
			vm /= 100
			removed = 2
		while vp / 10 > vm / 10:
			up = vr % 10 >= 5
			vr /= 10
			vp /= 10
			vm /= 10
			removed += 1
		out = vr + (1 if vr == vm or up else 0)
	trimmed(out, e10 + removed)

# digits * 10^exp with the digits' trailing zeros moved into the exponent
fn trimmed(digits u64, exp i64) ShortDecimal:
	d = digits
	e = exp
	while d % 10 == 0 and d != 0:
		d /= 10
		e += 1
	ShortDecimal(digits = d, exp = e)

# whether the digits of d kept before index i round up, half to even (lastKept: the last kept
# digit, ASCII)
fn roundsUpAt(d Decimal, i i64, lastKept u8) bool:
	next = digitAt(d, i)
	next > 5 or (next == 5 and (not trailingZeros(d, i + 1) or (lastKept - '0') % 2 == 1))

# the exact decimal of the double rounded to p significant digits (half to even)
fn roundedDigits(bits64 i64, p i64) Decimal:
	dv = exactDigitsOf(bits64)
	n = dv.digits.len
	if n <= p: return dv
	out u8[] = []
	out.extend(dv.digits[..p])
	point = dv.point
	if roundsUpAt(dv, p, out[p - 1]) and incrementDigits(out):
		point += 1
	stripTrailingZeros(out)
	Decimal(digits = out, point = point)

# The shortest decimal of a value held as a float of fbits (as narrowedTo takes them): Ryu's for a
# double; for a narrower float an integer's own digits (65504, not the 65500 that rounds to it),
# else the candidate with the fewest digits that rounds back to the same float, precisions 1..9
# tried through the exact decimal of the double.
fn shortestDecimalAs(bits64 i64, fbits i64) ShortDecimal:
	if fbits >= 64: return shortestDecimal(u64(bits64))
	x = f64.fromBits(u64(bits64))
	if x < 9_007_199_254_740_992.0 and x == x.round(): return trimmed(u64(x), 0)
	p i64 = 1
	while p <= 9:
		d = roundedDigits(bits64, p)
		back = decimalToF64(d.digits, 0, d.digits.len, d.point - d.digits.len)
		if i64(narrowedTo(back, fbits).toBits()) == bits64:
			digits u64 = 0
			for c in d.digits:
				digits = digits * 10 + u64(c - '0')
			return ShortDecimal(digits, exp = d.point - d.digits.len)
		p += 1
	shortestDecimal(u64(bits64))

# x rounded to the float of fbits: 64 itself, 32 an f32
fn narrowedTo(x f64, fbits i64) f64:
	x if fbits == 64 else f64(f32(x))

# ---------- formatting ----------

fn pushZeros(mut s u8[], n i64):
	z = n
	while z > 0:
		s.push(48)
		z -= 1

# the powers of ten a double holds exactly
exactPowers f64[] = [
	1.0,
	10.0,
	100.0,
	1000.0,
	10000.0,
	100000.0,
	1000000.0,
	10000000.0,
	100000000.0,
	1000000000.0,
	10000000000.0,
	100000000000.0,
	1000000000000.0,
	10000000000000.0,
	100000000000000.0,
	1000000000000000.0,
	10000000000000000.0,
	100000000000000000.0,
	1000000000000000000.0,
	10000000000000000000.0,
	100000000000000000000.0,
	1000000000000000000000.0,
	10000000000000000000000.0]

# the shortest text that reads back as the same float (fbits 32 or 64)
fn fmtFloat(bits64 i64, fbits i64) str:
	out u8[] = []
	pushFloat(out, bits64, fbits)
	str(move out)

# appends the shortest text that reads back as the same float (fbits 64, 32, 16 or 8 as
# narrowedTo takes it): plain digits up to 21 integer digits, a leading `0.` down to 1e-6,
# scientific beyond
fn pushFloat(mut out u8[], bits64 i64, fbits i64):
	x = f64.fromBits(u64(bits64))
	if x != x:
		out.extend("NaN".bytes())
	elif x == 0.0:
		out.push('0')
	elif x > 1.7976931348623157e308 or x < -1.7976931348623157e308:
		out.extend(("Infinity" if x > 0.0 else "-Infinity").bytes())
	else:
		if x < 0.0:
			out.push('-')
		absBits = bits64 & 9_223_372_036_854_775_807
		dec = shortestDecimalAs(absBits, fbits)
		pushDecimal(out, i64(dec.digits), dec.exp)

# digits * 10^exp as pushFloat writes it
fn pushDecimal(mut out u8[], digits i64, exp i64):
	n = intWidth(digits)
	pos = n + exp   # where the point goes, from the first digit
	if n <= pos and pos <= 21:
		pushInt(out, digits)
		pushZeros(out, pos - n)
	elif 0 < pos and pos <= 21:
		start = out.len
		pushInt(out, digits)
		out.insert(start + pos, '.')
	elif -6 < pos and pos <= 0:
		out.extend("0.".bytes())
		pushZeros(out, -pos)
		pushInt(out, digits)
	else:
		start = out.len
		pushInt(out, digits)
		if n > 1:
			out.insert(start + 1, '.')
		out.push('e')
		out.push('+' if pos > 0 else '-')
		pushInt(out, (pos - 1).abs())

# "{n:x}" ("{n:X}" upper): the hexadecimal digits of n, a negative number's those of its
# magnitude after a minus (the compiler calls it for the format)
fn i64ToHex(n i64, upper bool) str:
	if n < 0:
		return "-" + u64ToHex(u64(0 - n), upper)   # the most negative too: its bits are its magnitude
	u64ToHex(u64(n), upper)

fn u64ToHex(n u64, upper bool) str:
	if n == 0: return "0"
	out u8[] = []
	v = n
	while v > 0:
		out.push(hexDigit(i64(v & 15), upper))
		v >>= 4
	out.reverse()
	str(move out)

# the hexadecimal digit of v (0..15)
fn hexDigit(v i64, upper bool) u8:
	("0123456789ABCDEF" if upper else "0123456789abcdef")[v]

# the float with exactly `decimals` digits after the point (0..20), rounded half to even
fn fmtFixed(bits64 i64, decimals i64) str:
	x = f64.fromBits(u64(bits64))
	if x != x: return "NaN"
	dec = decimals.clamp(0, 20)
	neg = x < 0.0
	absBits = bits64
	if neg:
		absBits = bitsNeg(bits64)
	if x > 1.7976931348623157e308: return "Infinity"
	if x < -1.7976931348623157e308: return "-Infinity"
	digits = Decimal(digits = [48], point = 1)
	if (u64(absBits) << 1) != 0:
		digits = exactDigitsOf(absBits)
	pos = digits.point
	# the digit sequence of the integer part and `dec` fraction digits, then the rounding digit
	buf u8[] = []
	if pos <= 0:
		buf.push(48)   # 0.ddd: leading zeros before the digits
		z = -pos
		k i64 = 0
		while k < dec:
			c i64 = 48
			if k >= z:
				c = 48 + digitAt(digits, k - z)
			buf.push(u8(c))
			k += 1
		nextIdx = dec - z
		if nextIdx >= 0 and roundsUpAt(digits, nextIdx, buf[len - 1]):
			_ = incrementDigits(buf)   # cannot carry out: the first digit is 0
	else:
		k i64 = 0
		while k < pos + dec:
			buf.push(u8(48 + digitAt(digits, k)))
			k += 1
		if roundsUpAt(digits, pos + dec, buf[len - 1]):
			if incrementDigits(buf):
				buf.push(48)   # carried out (99.97 is 100.0): 1 then one zero more
	intLen = buf.len - dec
	s u8[] = []
	if neg:
		# -0.00 prints as 0.00
		if not buf.all(b: b == 48):
			s.push(45)
	s.extend(buf[..intLen])
	if dec > 0:
		s.push(46)
		s.extend(buf[intLen..])
	str(move s)

# ---------- parsing ----------

# w * 10^exp10 when it is exact in floating arithmetic (Clinger): w below 2^53 and the power
# within 10^22 (more of a larger one moved into w while w stays below 2^53); none otherwise
fn exactScaled(w i64, exp10 i64) f64?:
	if w >= 9_007_199_254_740_992: return none
	m = w
	e = exp10
	while e > 22 and m < 900_719_925_474_099:
		m *= 10
		e -= 1
	if e > 22 or e < -22: return none
	f64(m) * exactPowers[e] if e >= 0 else f64(m) / exactPowers[-e]

# digits d[start..to) times 10^exp10, correctly rounded to the nearest double
fn decimalToF64(d u8[], start i64, end i64, exponent i64) f64:
	# strip leading zeros, and trailing ones into the exponent
	a = start
	while a < end and d[a] == 48:
		a += 1
	if a == end: return 0.0
	to = end
	exp10 = exponent
	while d[to - 1] == 48:
		to -= 1
		exp10 += 1
	ndig = to - a
	if ndig <= 15:
		w = 0
		for i in a..to:
			w = w * 10 + (i64(d[i]) - 48)
		if exactScaled(w, exp10) is x: return x
	if ndig > 800: return 1.0 / 0.0
	# first guess with floating arithmetic
	guess = 0.0
	i = a
	while i < to:
		guess = guess * 10.0 + f64(i64(d[i]) - 48)
		i += 1
	p = exp10
	if p > 0:
		while p > 0:
			guess *= 10.0
			p -= 1
	else:
		while p < 0:
			guess /= 10.0
			p += 1
	if guess > 1.7976931348623157e308: return 1.0 / 0.0
	if guess == 0.0: return 0.0
	# refine: compare the exact decimal of the guess with the input, move to neighbours
	cur = guess
	steps i64 = 0
	while steps < 64:
		c = compareExact(d, a, to, exp10, cur)
		if c == 0: return cur
		if c > 0:
			up = nextUp(cur)
			cu = compareExact(d, a, to, exp10, up)
			if cu < 0:
				# between cur and up: the nearer, by comparing with the midpoint
				return pickNearest(d, a, to, exp10, cur, up)
			cur = up
		else:
			down = nextDown(cur)
			cd = compareExact(d, a, to, exp10, down)
			if cd > 0: return pickNearest(d, a, to, exp10, down, cur)
			cur = down
		steps += 1
	cur

fn nextUp(x f64) f64:
	if x >= 1.7976931348623157e308: return 1.0 / 0.0
	f64.fromBits(x.toBits() + 1)

fn nextDown(x f64) f64:
	b = i64(x.toBits())
	if b == 0: return 0.0
	f64.fromBits(u64(b - 1))

# sign of (input - x) where input = digits d[a..to) * 10^exp10 and x > 0
fn compareExact(d u8[], a i64, to i64, exp10 i64, x f64) i64:
	compareDigits(d[a..to], to - a + exp10, exactDigitsOf(i64(x.toBits())))

# the nearer of two adjacent doubles lo < input < hi (ties to even mantissa)
fn pickNearest(d u8[], a i64, to i64, exp10 i64, lo f64, hi f64) f64:
	# the midpoint (lo + hi) / 2 exactly: 2m+1 at e-1
	p = binaryParts(i64(lo.toBits()))
	c = compareDigits(d[a..to], to - a + exp10, exactDecimal(2 * p.m + 1, p.e - 1))
	if c > 0: return hi
	if c < 0: return lo
	if p.m % 2 == 0: return lo
	hi

# the number the 16 bits of an IEEE half float (f16: 5 exponent bits, 10 of fraction) hold: the
# CPU's and the GPU's (std/tensor's kernels read halves with it)
pub fn halfValue(h u32) f32:
	sign = (h >> 15) & 1
	e = (h >> 10) & 31
	m = h & 1023
	if e == 0:
		v = f32(m) * 0.000000059604645   # 2^-24
		return -v if sign == 1 else v
	if e == 31: return f32.fromBits(sign << 31 | 0x7F80_0000 | m << 13)
	f32.fromBits(sign << 31 | (e + 112) << 23 | m << 13)

# the f16 nearest x (ties to even), as its 16 bits
pub fn halfBits(x f32) u32:
	b = x.toBits()
	sign = (b >> 16) & 0x8000
	exponent = i64((b >> 23) & 0xFF)
	m = b & 0x7F_FFFF
	if exponent == 0xFF: return sign | 0x7C00 | (0x200 if m != 0 else 0)
	e = exponent - 127 + 15
	if e >= 31: return sign | 0x7C00
	if e <= 0:
		if e < -10: return sign
		whole = m | 0x80_0000
		shift = 14 - e
		kept = whole >> u32(shift)
		rest = whole & ((u32(1) << u32(shift)) - 1)
		halfway = u32(1) << u32(shift - 1)
		up = rest > halfway or rest == halfway and (kept & 1) == 1
		return sign | (kept + 1 if up else kept)
	kept = u32(e) << 10 | m >> 13
	rest = m & 0x1FFF
	up = rest > 0x1000 or rest == 0x1000 and (kept & 1) == 1
	sign | (kept + 1 if up else kept)   # a carry into the exponent rounds up to it

# v.alignUp(a): v rounded up to a multiple of a, as offsets and sizes are aligned (a power of two
# by a mask)
pub fn alignUp(v i64, a i64) i64:
	if a <= 1: return v
	(v + a - 1) & -a if (a & (a - 1)) == 0 else (v + a - 1) / a * a
