# Advanced SIMD three different: the operations whose results are twice as wide as their
# sources (long), whose first source is already wide (wide), or half as wide (narrow); and the
# vector by element forms, whose second source is one lane repeated.

import recomp.switch.arm64
import recomp.switch.cpu.core

# the doubled product of two signed lanes, saturated to twice their width (SQDMULL)
fn doubledProduct(mut c core.Cpu, x u64, y u64, bits i64) u64:
	p = signedOf(x, bits) * signedOf(y, bits)
	if p == 1 << 62: return c.signedExtreme(false, 64)
	c.clampSigned(2 * p, bits * 2)

# a lane widened to 64 bits by its signedness
fn extendedLane(v u64, bits i64, unsigned bool):
	v if unsigned else u64(signedOf(v, bits))

# one lane of the long and wide forms: x and y the narrow sources, wide the first source's wide
# lane (opcodes 1 and 3), acc the destination's wide lane
fn longLane(mut c core.Cpu, i arm64.Instr, x u64, y u64, wide u64, acc u64, bits i64) u64:
	dst = bits * 2
	m = core.laneMask(dst)
	u = i.unsigned
	ex = extendedLane(x, bits, u)
	ey = extendedLane(y, bits, u)
	match i.opc:
		0: (ex + ey) & m
		1: (wide + ey) & m
		2: (ex - ey) & m
		3: (wide - ey) & m
		5: (acc + absDifference(x, y, bits, u)) & m
		7: absDifference(x, y, bits, u)
		8: (acc + ex * ey) & m
		9: c.addSaturating(acc, c.doubledProduct(x, y, bits), dst, false)
		10: (acc - ex * ey) & m
		11: c.subSaturating(acc, c.doubledProduct(x, y, bits), dst, false)
		12: (ex * ey) & m
		_: c.doubledProduct(x, y, bits)

# ADDHN, SUBHN and their rounding forms: the high half of the wide sum or difference, written
# to the low half of rd (the high half when q, the low half kept)
fn narrowingLanes(mut c core.Cpu, i arm64.Instr, a Vec, b Vec):
	bits = 8 << i.size
	wide = bits * 2
	out = Vec()
	for k in 0..64 / bits:
		x = a.lane(wide, k)
		y = b.lane(wide, k)
		r = x + y if i.opc == 4 else x - y
		if i.unsigned: r += u64(1) << (bits - 1)
		out.setLane(bits, k, (r & core.laneMask(wide)) >> bits)
	c.writeNarrow(i, out)

# out's low half written to the destination's low half, or its high half when q
pub fn writeNarrow(mut c core.Cpu, i arm64.Instr, out Vec):
	if not i.q: return c.vecWrite(i.rd, Vec(lo = out.lo), false)
	c.vecWrite(i.rd, Vec(lo = c.q[2 * i.rd], hi = out.lo), true)

# PMULL: the carry-less products of 8-bit lanes, or of the two 64-bit halves
fn polynomialLong(mut c core.Cpu, i arm64.Instr, a Vec, b Vec):
	out = Vec()
	if i.size == 3:
		x = a.hi if i.q else a.lo
		y = b.hi if i.q else b.lo
		lo, hi = carrylessMultiply(x, y)
		return c.vecWrite(i.rd, Vec(lo, hi), true)
	offset = 8 if i.q else 0
	for k in 0..8:
		lo, _ = carrylessMultiply(a.lane(8, k + offset), b.lane(8, k + offset))
		out.setLane(16, k, lo & 0xFFFF)
	c.vecWrite(i.rd, out, true)

# the lanes of a and b operated on as the instruction says, written to rd
pub fn differentLanes(mut c core.Cpu, i arm64.Instr, a Vec, b Vec):
	if i.opc == 4 or i.opc == 6: return c.narrowingLanes(i, a, b)
	if i.opc == 14: return c.polynomialLong(i, a, b)
	bits = 8 << i.size
	n = 1 if i.scalar else 64 / bits
	offset = n if i.q else 0
	d = c.vecRead(i.rd)
	out = Vec()
	for k in 0..n:
		x = a.lane(bits, k + offset)
		y = b.lane(bits, k + offset)
		out.setLane(
			bits * 2,
			k,
			c.longLane(i, x, y, a.lane(bits * 2, k), d.lane(bits * 2, k), bits)
		)
	c.vecWrite(i.rd, out, true)

pub fn threeDifferent(mut c core.Cpu, i arm64.Instr):
	c.differentLanes(i, c.vecRead(i.rn), c.vecRead(i.rm))

# the vector by element forms: b is the lane repeated over a register
pub fn indexed(mut c core.Cpu, i arm64.Instr):
	bits = 8 << i.size
	b = replicated(c.vecRead(i.rm).lane(bits, i.index), bits)
	a = c.vecRead(i.rn)
	if i.opc >= 8 and i.opc <= 13: return c.differentLanes(i, a, b)
	c.sameLanes(i, a, b)
