# The lanes of the 128-bit FP/SIMD registers and the arithmetic the Advanced SIMD instructions
# share: signed and unsigned views of a lane, saturation (which sets FPSR.QC), shifts by a
# count with rounding. A lane's value is its bits, zero-extended in a u64.

import recomp.switch.arm64
import recomp.switch.cpu.core

# a vector register's 128 bits, worked on apart from the register (a destination may be a source)
pub type Vec:
	lo u64 = 0
	hi u64 = 0

	# lane k of `bits` bits
	fn lane(bits i64, k i64):
		at = k * bits
		w = hi if at >= 64 else lo
		(w >> (at & 63)) & core.laneMask(bits)

	fn setLane(bits i64, k i64, v u64):
		at = k * bits
		m = core.laneMask(bits) << (at & 63)
		x = (v << (at & 63)) & m
		if at >= 64:
			hi = (hi & ~m) | x
		else:
			lo = (lo & ~m) | x

# a lane's bits as a signed number
pub fn signedOf(v u64, bits i64) i64:
	s = 64 - bits
	i64(v << s) >> s

pub fn vecRead(c core.Cpu, r i64) Vec:
	Vec(lo = c.q[2 * r], hi = c.q[2 * r + 1])

# register r set to v, the high half cleared unless `full` (a 64-bit or scalar result)
pub fn vecWrite(mut c core.Cpu, r i64, v Vec, full bool):
	c.q[2 * r] = v.lo
	c.q[2 * r + 1] = v.hi if full else 0

# the lanes an instruction works on: one for a scalar, else the register's 64 or 128 bits
pub fn laneCount(i arm64.Instr, bits i64) i64:
	1 if i.scalar else (128 if i.q else 64) / bits

# v with every lane of `bits` bits set to x
pub fn replicated(x u64, bits i64) Vec:
	out = Vec()
	for k in 0..128 / bits:
		out.setLane(bits, k, x)
	out

# FPSR.QC: a saturation happened
pub fn setQc(mut c core.Cpu):
	c.fpsr |= u64(1) << 27

fn extremeSigned(bits i64, negative bool):
	if negative: return u64(1) << (bits - 1)
	core.laneMask(bits - 1)

# the exact signed value v cut to a signed lane, saturated
pub fn clampSigned(mut c core.Cpu, v i64, bits i64) u64:
	if bits == 64: return u64(v)
	hi = (1 << (bits - 1)) - 1
	if v > hi:
		c.setQc()
		return u64(hi)
	if v < -hi - 1:
		c.setQc()
		return extremeSigned(bits, true)
	u64(v) & core.laneMask(bits)

# the exact unsigned value v cut to an unsigned lane, saturated
pub fn clampUnsigned(mut c core.Cpu, v u64, bits i64) u64:
	if v > core.laneMask(bits):
		c.setQc()
		return core.laneMask(bits)
	v

# the exact signed value v cut to an unsigned lane, saturated
pub fn clampSignedToUnsigned(mut c core.Cpu, v i64, bits i64) u64:
	if v < 0:
		c.setQc()
		return 0
	c.clampUnsigned(v, bits)

pub fn addSaturating(mut c core.Cpu, a u64, b u64, bits i64, unsigned bool) u64:
	s = a + b
	if unsigned:
		if bits == 64 and s < a:
			c.setQc()
			return u64(-1)
		return c.clampUnsigned(s, bits)
	if bits < 64: return c.clampSigned(signedOf(a, bits) + signedOf(b, bits), bits)
	if ((a ^ s) & (b ^ s)) >> 63 != 0:
		c.setQc()
		return extremeSigned(64, i64(a) < 0)
	s

pub fn subSaturating(mut c core.Cpu, a u64, b u64, bits i64, unsigned bool) u64:
	if unsigned:
		if b > a:
			c.setQc()
			return 0
		return a - b
	if bits < 64: return c.clampSigned(signedOf(a, bits) - signedOf(b, bits), bits)
	s = a - b
	if ((a ^ b) & (a ^ s)) >> 63 != 0:
		c.setQc()
		return extremeSigned(64, i64(a) < 0)
	s

# -a, saturated at the signed lane's largest value
pub fn negSaturating(mut c core.Cpu, a u64, bits i64) u64:
	if a == u64(1) << (bits - 1):
		c.setQc()
		return core.laneMask(bits - 1)
	(0 - a) & core.laneMask(bits)

# a signed lane's absolute value, saturated
pub fn absSaturating(mut c core.Cpu, a u64, bits i64) u64:
	if signedOf(a, bits) < 0: return c.negSaturating(a, bits)
	a

# x shifted right by n (1 to 128) with the bits shifted out rounded in when `round`
pub fn rightShifted(x u64, n i64, bits i64, unsigned bool, round bool) u64:
	if unsigned:
		r = x >> n if n < 64 else u64(0)
		bit = (x >> (n - 1)) & 1 if round and n <= 64 else u64(0)
		return r + bit
	s = signedOf(x, bits)
	r = s >> n.min(63)
	bit = (s >> (n - 1).min(63)) & 1 if round else 0
	u64(r + bit) & core.laneMask(bits)

# x shifted left by n (0 or more) with the result saturated to the lane
pub fn leftSaturating(mut c core.Cpu, x u64, n i64, bits i64, unsigned bool) u64:
	if unsigned:
		if x == 0: return 0
		if n >= bits: return c.unsignedMax(bits)
		r = x << n
		if r >> n != x: return c.unsignedMax(bits)
		return c.clampUnsigned(r, bits)
	s = signedOf(x, bits)
	if s == 0: return 0
	if n >= bits: return c.signedExtreme(s < 0, bits)
	r = s << n
	if r >> n != s: return c.signedExtreme(s < 0, bits)
	c.clampSigned(r, bits)

# the largest unsigned lane, QC set
fn unsignedMax(mut c core.Cpu, bits i64):
	c.setQc()
	core.laneMask(bits)

# the largest or smallest signed lane, QC set
pub fn signedExtreme(mut c core.Cpu, negative bool, bits i64) u64:
	c.setQc()
	extremeSigned(bits, negative)

# SSHL, USHL and their saturating and rounding forms: y's low byte is a signed count, a
# negative one shifting right
pub fn shiftedBy(
	mut c core.Cpu,
	x u64,
	y u64,
	bits i64,
	unsigned bool,
	round bool,
	saturate bool
) u64:
	n = signedOf(y, 8)
	if n < 0: return rightShifted(x, -n, bits, unsigned, round)
	if saturate: return c.leftSaturating(x, n, bits, unsigned)
	if n >= bits: return 0
	(x << n) & core.laneMask(bits)
