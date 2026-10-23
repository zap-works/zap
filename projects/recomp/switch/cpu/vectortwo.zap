# Advanced SIMD two-register miscellaneous and across lanes: one source register, each lane
# (or the whole register) changed on its own.

import recomp.switch.arm64

# SUQADD (the destination lane signed plus the source lane unsigned) and USQADD (the reverse),
# saturated; 64-bit lanes by their carries
fn accumulateMixed(mut c Cpu, x u64, acc u64, bits i64, unsigned bool) u64:
	if bits < 64:
		if unsigned: return c.clampSignedToUnsigned(i64(acc) + signedOf(x, bits), bits)
		return c.clampSigned(signedOf(acc, bits) + i64(x), bits)
	if unsigned:
		if i64(x) >= 0:
			s = acc + x
			if s < acc:
				c.setQc()
				return u64(-1)
			return s
		return c.subSaturating(acc, 0 - x, 64, true)
	s = acc + x
	if i64(acc) >= 0:
		if s < x or s >> 63 != 0: return c.signedExtreme(false, 64)
		return s
	if s < x and s >> 63 != 0: return c.signedExtreme(false, 64)
	s

# the compare with zero (opcodes 8 to 10) as a lane
fn compareZero(opc i64, u bool, x u64, bits i64):
	s = signedOf(x, bits)
	hit = match opc:
		8: s >= 0 if u else s > 0
		9: s <= 0 if u else x == 0
		_: s < 0
	laneMask(bits) if hit else 0

fn miscLane(mut c Cpu, i arm64.Instr, x u64, acc u64, bits i64) u64:
	u = i.unsigned
	m = laneMask(bits)
	match i.opc:
		3: c.accumulateMixed(x, acc, bits, u)
		4: leadingZerosIn(x, bits) if u else leadingSigns(x, bits)
		5: reverseBits(x, 8) if u and i.size == 1 else (~x & m if u else u64(x.bitCount()))
		7: c.negSaturating(x, bits) if u else c.absSaturating(x, bits)
		0xF: x ^ (m ^ (m >> 1)) if u else x & (m >> 1)
		11: (0 - x) & m if u or signedOf(x, bits) < 0 else x
		_: compareZero(i.opc, u, x, bits)

# REV16, REV32, REV64: the lanes within each container in the opposite order
fn reversedLanes(mut c Cpu, i arm64.Instr, a Vec):
	container = 16 if i.opc == 1 else (32 if i.unsigned else 64)
	bits = 8 << i.size
	per = container / bits
	out = Vec()
	for k in 0..laneCount(i, bits):
		out.setLane(bits, k, a.lane(bits, k / per * per + per - 1 - k % per))
	c.vecWrite(i.rd, out, i.q)

# SADDLP, UADDLP, SADALP, UADALP: pairs of lanes added into lanes twice as wide
fn pairwiseLong(mut c Cpu, i arm64.Instr, a Vec):
	bits = 8 << i.size
	wide = bits * 2
	d = c.vecRead(i.rd)
	out = Vec()
	for k in 0..(128 if i.q else 64) / wide:
		s = extendedLane(a.lane(bits, 2 * k), bits, i.unsigned) +
			extendedLane(a.lane(bits, 2 * k + 1), bits, i.unsigned)
		if i.opc == 6: s += d.lane(wide, k)
		out.setLane(wide, k, s & laneMask(wide))
	c.vecWrite(i.rd, out, i.q)

# XTN, SQXTN, UQXTN, SQXTUN: lanes narrowed to half, saturated except for xtn
fn narrowedLanes(mut c Cpu, i arm64.Instr, a Vec):
	bits = 8 << i.size
	wide = bits * 2
	out = Vec()
	for k in 0..1 if i.scalar else 64 / bits:
		x = a.lane(wide, k)
		r = match i.opc:
			0x12: x & laneMask(bits) if not i.unsigned
				else c.clampSignedToUnsigned(signedOf(x, wide), bits)
			_: c.clampUnsigned(x, bits) if i.unsigned else c.clampSigned(signedOf(x, wide), bits)
		out.setLane(bits, k, r)
	c.writeNarrow(i, out)

# SHLL, SHLL2: the lanes of one half widened and shifted left by their width
fn shiftedLong(mut c Cpu, i arm64.Instr, a Vec):
	bits = 8 << i.size
	n = 64 / bits
	out = Vec()
	for k in 0..n:
		out.setLane(bits * 2, k, a.lane(bits, k + (n if i.q else 0)) << bits)
	c.vecWrite(i.rd, out, true)

pub fn twoMisc(mut c Cpu, i arm64.Instr):
	a = c.vecRead(i.rn)
	match i.opc:
		0, 1: c.reversedLanes(i, a)
		2, 6: c.pairwiseLong(i, a)
		0x12, 0x14: c.narrowedLanes(i, a)
		0x13: c.shiftedLong(i, a)
		_: c.miscLanes(i, a)

fn miscLanes(mut c Cpu, i arm64.Instr, a Vec):
	d = c.vecRead(i.rd)
	bits = 8 if i.opc == 5 else 8 << i.size
	out = Vec()
	for k in 0..laneCount(i, bits):
		out.setLane(bits, k, c.miscLane(i, a.lane(bits, k), d.lane(bits, k), bits))
	c.vecWrite(i.rd, out, i.q)

# SADDLV and UADDLV, SMAXV and UMAXV, SMINV and UMINV, ADDV, scalar ADDP: all lanes into one
pub fn acrossLanes(mut c Cpu, i arm64.Instr):
	a = c.vecRead(i.rn)
	bits = 8 << i.size
	n = (128 if i.q else 64) / bits
	r = a.lane(bits, 0)
	if i.opc == 3: r = extendedLane(r, bits, i.unsigned)
	for k in 1..n:
		x = a.lane(bits, k)
		r = match i.opc:
			3: r + extendedLane(x, bits, i.unsigned)
			0xA: x if greater(x, r, bits, i.unsigned, false) else r
			0x1A: x if greater(r, x, bits, i.unsigned, false) else r
			_: r + x
	width = bits * 2 if i.opc == 3 else bits
	c.vecWrite(i.rd, Vec(lo = r & laneMask(width)), false)
