# What the Zap GPU code translated from Maxwell programs (recomp.switch.shaders) calls: the
# operations whose Maxwell meaning takes more than an expression (yuzu's and Ryujinx's
# translations of the same instructions).

# a * b with Maxwell's FMZ: zero when either is zero, whatever the other (an infinity, a NaN)
pub fn mulZero(a f32, b f32) f32:
	0.0 if a == 0.0 or b == 0.0 else a * b

# x rounded to the nearest integer, a tie to the even one
pub fn roundEven(x f32) f32:
	low = x.floor()
	d = x - low
	if d > 0.5: return low + 1.0
	if d < 0.5: return low
	low if (low * 0.5).fract() == 0.0 else low + 1.0

# F2I to 32 bits: rounded as asked, clamped to the integer's range, a NaN 0x80000000
pub fn floatToInt(x f32, signed bool) u32:
	if x != x: return 0x8000_0000
	if signed: return u32(i32(x.clamp(-2_147_483_648.0, 2_147_483_520.0)))
	u32(x.clamp(0.0, 4_294_967_040.0))

# the `count` bits of v from `offset` (BFE), the sign's copied above them when signed; a field
# past bit 31 ends there
pub fn extractBits(v u32, offset u32, count u32, signed bool) u32:
	ones u32 = 0xFFFF_FFFF
	if count == 0: return 0
	if offset >= 32: return ones if signed and v >> 31 != 0 else 0
	n = count.min(32 - offset)
	field = v >> offset
	if n < 32: field = field & ((u32(1) << n) - 1)
	if signed and n < 32 and (field >> (n - 1)) & 1 != 0: field = field | ~((u32(1) << n) - 1)
	field

# base with insert's low `count` bits put at `offset` (BFI)
pub fn insertBits(base u32, insert u32, offset u32, count u32) u32:
	if count == 0 or offset >= 32: return base
	n = count.min(32 - offset)
	ones u32 = 0xFFFF_FFFF
	mask = ones if n >= 32 else (u32(1) << n) - 1
	(base & ~(mask << offset)) | ((insert & mask) << offset)

# the number of bits set (POPC)
pub fn countBits(v u32) u32:
	n u32 = 0
	w = v
	while w != 0:
		n += w & 1
		w = w >> 1
	n

# the index of the highest bit set (FLO), 0xFFFFFFFF for none; signed: of the highest bit that
# differs from the sign
pub fn highestBit(v u32, signed bool) u32:
	w = ~v if signed and v >> 31 != 0 else v
	if w == 0: return 0xFFFF_FFFF
	n u32 = 31
	while (w >> n) & 1 == 0:
		n -= 1
	n

# the bits reversed (SHR.BREV, BFE.BREV)
pub fn reverseBits(v u32) u32:
	r u32 = 0
	for i in 0..32:
		r = r << 1 | (v >> u32(i)) & 1
	r

# LOP3: each bit of the result the bit of `table` its bits of a, b and c index
pub fn lop3(a u32, b u32, c u32, table u32) u32:
	r u32 = 0
	if table & 1 != 0: r = r | ~a & ~b & ~c
	if table & 2 != 0: r = r | ~a & ~b & c
	if table & 4 != 0: r = r | ~a & b & ~c
	if table & 8 != 0: r = r | ~a & b & c
	if table & 16 != 0: r = r | a & ~b & ~c
	if table & 32 != 0: r = r | a & ~b & c
	if table & 64 != 0: r = r | a & b & ~c
	if table & 128 != 0: r = r | a & b & c
	r

# a 16-bit half of v (high when `high`), sign-extended when signed (XMAD's operands)
pub fn half(v u32, high bool, signed bool) u32:
	h = v >> 16 if high else v & 0xFFFF
	if signed and h & 0x8000 != 0: return h | 0xFFFF_0000
	h

# SHF: the 64 bits high:low shifted by s (at most 63) right or left, the low word (right) or the
# high one (left) kept; arithmetic when signed
pub fn funnelShift(low u32, high u32, s u32, right bool, signed bool) u32:
	if s == 0: return low if right else high
	if right:
		if s >= 32:
			n = s - 32
			return u32(i32(high) >> n.min(31)) if signed else (0 if n >= 32 else high >> n)
		return low >> s | high << (32 - s)
	if s >= 32: return 0 if s - 32 >= 32 else low << (s - 32)
	high << s | low >> (32 - s)
