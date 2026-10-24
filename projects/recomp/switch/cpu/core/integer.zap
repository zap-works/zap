# What A64's integer instructions do (the Arm ARM's pseudocode, shared functions in J1), on a
# thread's registers: the interpreter calls these with a decoded instruction's fields, and the
# translation writes the same calls with them as constants.

import recomp.switch.arm64

pub mask32 u64 = 0xFFFF_FFFF

fn widthMask(sf bool):
	u64(-1) if sf else mask32

# whether v is negative as a number of its width
pub fn isNegative(v u64, sf bool) bool:
	(v >> (63 if sf else 31)) & 1 != 0

# x + y + carry and its flags (AddWithCarry)
pub fn addWithCarry(x u64, y u64, carry bool, sf bool) (u64, u64):
	m = widthMask(sf)
	a = x & m
	b = y & m
	cin = flagBit(carry)
	sum = (a + b + cin) & m
	carryOut = false
	if sf:
		carryOut = sum < a or (sum == a and (b != 0 or carry))
	else:
		carryOut = a + b + cin > m
	overflow = isNegative(a, sf) == isNegative(b, sf) and isNegative(sum, sf) != isNegative(a, sf)
	n = isNegative(sum, sf)
	flags = flagBit(n) << 3 | flagBit(sum == 0) << 2 | flagBit(carryOut) << 1 | flagBit(overflow)
	(sum, flags)

# the flags of x + y + carry alone
pub fn addFlags(x u64, y u64, carry bool, sf bool) u64:
	_, flags = addWithCarry(x, y, carry, sf)
	flags

# v shifted: lsl, lsr, asr, ror (ShiftReg)
pub fn shifted(v u64, kind i64, amount i64, sf bool) u64:
	m = widthMask(sf)
	x = v & m
	if amount == 0: return x
	match kind:
		0: (x << amount) & m
		1: x >> amount
		2:
			if sf: return u64(i64(x) >> amount)
			u64(i64(i32(u32(x))) >> amount) & m
		_: rotated(x, amount, sf)

# v extended (uxtb, uxth, uxtw, uxtx, sxtb, sxth, sxtw, sxtx) then shifted left (ExtendReg)
pub fn extended(v u64, kind i64, shift i64, sf bool) u64:
	width = 8 << (kind & 3)
	x = v
	if width < 64:
		x = v & ((u64(1) << width) - 1)
		if kind >= 4 and (x >> (width - 1)) & 1 != 0: x = x | ~((u64(1) << width) - 1)
	(x << shift) & widthMask(sf)

# v's width rotated right by r
fn rotated(v u64, r i64, sf bool) u64:
	if sf: return v.rotateRight(r)
	u32(v & mask32).rotateRight(r)

# sbfm, bfm, ubfm: src rotated right by r, kept where wmask says over dst (bfm's) or zero, then
# the bits tmask leaves out taken from the top bit of src at s (sbfm's) or from dst; the masks
# are arm64.bitMasks's, the translation's known ahead
pub fn bitfieldOf(src u64, dst u64, r i64, s i64, wmask u64, tmask u64, opc i64, sf bool) u64:
	m = widthMask(sf)
	base = dst if opc == 1 else u64(0)
	bot = (base & ~wmask) | (rotated(src, r, sf) & wmask)
	top = base
	if opc == 0: top = m if (src >> s) & 1 != 0 else u64(0)
	((top & ~tmask) | (bot & tmask)) & m

# a bitfield's wmask and tmask, for its width
pub fn bitfieldMasks(r i64, s i64, sf bool) (u64, u64):
	w, t = arm64.bitMasks(sf, r, s, sf, false) ?? (0, 0)
	(u64(w) & widthMask(sf), u64(t) & widthMask(sf))

# extr: the width's bits of hi:lo from bit `at` of lo
pub fn extractOf(lo u64, hi u64, at i64, sf bool) u64:
	if at == 0: return lo
	left = (64 if sf else 32) - at
	((lo >> at) | (hi << left)) & widthMask(sf)

pub fn reverseBits(v u64, width i64) u64:
	r = u64(0)
	for b in 0..width:
		if (v >> b) & 1 != 0: r = r | (u64(1) << (width - 1 - b))
	r

# the bytes of each `chunk`-byte container of v reversed
fn reverseBytes(v u64, chunk i64, width i64):
	r = u64(0)
	for at in (0..width / 8 / chunk).map(it * chunk * 8):
		for k in 0..chunk:
			byte = (v >> (at + k * 8)) & 0xFF
			r |= byte << (at + (chunk - 1 - k) * 8)
	r

# the zero bits above the top set bit of the low `width` bits of v (CLZ)
pub fn leadingZerosIn(v u64, width i64) u64:
	u64(v.leadingZeros() - (64 - width))

# the bits after the top one that equal it, in the low `width` bits of v (CLS)
pub fn leadingSigns(v u64, width i64) u64:
	flipped = (v ^ (v >> 1)) & (laneMask(width) >> 1)
	u64(flipped.leadingZeros() - (64 - width) - 1)

pub fn oneSource(mut c Cpu, i arm64.Instr):
	width = 64 if i.sf else 32
	v = c.get(i.rn, i.sf)
	r = match i.opc:
		0: reverseBits(v, width)
		1: reverseBytes(v, 2, width)
		2: reverseBytes(v, 4, width) if i.sf else reverseBytes(v, 4, 32)
		3: reverseBytes(v, 8, 64)
		4: leadingZerosIn(v, width)
		_: leadingSigns(v, width)
	if i.opc == 2 and not i.sf: r = reverseBytes(v, 4, 32)
	c.set(i.rd, r, i.sf)

pub fn twoSource(mut c Cpu, i arm64.Instr):
	a = c.get(i.rn, i.sf)
	b = c.get(i.rm, i.sf)
	count = i64(b & (63 if i.sf else 31))
	r = match i.opc:
		2: u64(0) if b == 0 else a / b
		3: signedDivide(a, b, i.sf)
		8: shifted(a, 0, count, i.sf)
		9: shifted(a, 1, count, i.sf)
		10: shifted(a, 2, count, i.sf)
		11: shifted(a, 3, count, i.sf)
		_: c.crc(i, a, b)
	c.set(i.rd, r, i.sf)

fn signedDivide(a u64, b u64, sf bool) u64:
	if b == 0: return 0
	if sf:
		if a == u64(1) << 63 and b == u64(-1): return a
		return u64(i64(a) / i64(b))
	x = i64(i32(u32(a)))
	y = i64(i32(u32(b)))
	u64(x / y) & mask32

# crc32b/h/w/x (opc 16-19) and crc32cb/h/w/x (20-23): the accumulator in rn's 32 bits, the
# value's low bytes in rm, bit-reflected as the instruction defines
fn crc(c Cpu, i arm64.Instr, acc u64, value u64):
	poly = u64(0x82F6_3B78) if i.opc >= 20 else u64(0xEDB8_8320)
	n = 1 << (i.opc & 3)
	r = acc & mask32
	v = c.x[i.rm]
	for k in 0..n * 8:
		bitIn = (v >> k) & 1
		low = (r ^ bitIn) & 1
		r >>= 1
		if low != 0: r = r ^ poly
	r

# the high 64 bits of a's and b's 128-bit product, unsigned
pub fn mulHigh(a u64, b u64) u64:
	aLo = a & mask32
	aHi = a >> 32
	bLo = b & mask32
	bHi = b >> 32
	ll = aLo * bLo
	lh = aLo * bHi
	hl = aHi * bLo
	hh = aHi * bHi
	mid = (ll >> 32) + (lh & mask32) + (hl & mask32)
	hh + (lh >> 32) + (hl >> 32) + (mid >> 32)

# the high 64 bits of a's and b's 128-bit product, signed (smulh)
pub fn mulHighSigned(a u64, b u64) u64:
	hi = mulHigh(a, b)
	if i64(a) < 0: hi -= b
	if i64(b) < 0: hi -= a
	hi

# the 64-bit product of two 32-bit numbers' low words, signed (smull's)
pub fn mulSignedWords(a u64, b u64) u64:
	i64(i32(u32(a & mask32))) * i64(i32(u32(b & mask32)))

# a lane of `bits` bits as a mask
pub fn laneMask(bits i64) u64:
	u64(-1) if bits == 64 else (u64(1) << bits) - 1
