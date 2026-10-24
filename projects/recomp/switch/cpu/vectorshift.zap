# What the Advanced SIMD shifts by immediate do.

import recomp.switch.arm64
import recomp.switch.cpu.core

# x shifted right by n (1 to the lane's width), 0 for a count past 63
fn shiftedRight(x u64, n i64):
	x >> n if n < 64 else u64(0)

# one lane of the shifts that keep their size: x the source lane, acc the destination's
fn shiftLane(mut c core.Cpu, i arm64.Instr, x u64, acc u64, bits i64) u64:
	u = i.unsigned
	m = core.laneMask(bits)
	n = i.amount
	match i.opc:
		0: rightShifted(x, n, bits, u, false)
		2: (acc + rightShifted(x, n, bits, u, false)) & m
		4: rightShifted(x, n, bits, u, true)
		6: (acc + rightShifted(x, n, bits, u, true)) & m
		8: shiftedRight(x, n) | acc & ~shiftedRight(m, n) & m
		10: insertedLeft(x, acc, n, m, u)
		12:
			if signedOf(x, bits) < 0:
				c.setQc()
				return 0
			c.leftSaturating(x, n, bits, true)
		_: c.leftSaturating(x, n, bits, u)

# SHL, or SLI which keeps the destination's low n bits
fn insertedLeft(x u64, acc u64, n i64, m u64, keep bool):
	r = (x << n) & m
	if keep: r |= acc & ((u64(1) << n) - 1)
	r

# SHRN, SQSHRN, UQSHRN, SQSHRUN and the rounding forms: lanes shifted right then narrowed
fn narrowingShift(mut c core.Cpu, i arm64.Instr, a Vec):
	bits = 8 << i.size
	wide = bits * 2
	out = Vec()
	round = i.opc & 1 == 1
	for k in 0..1 if i.scalar else 64 / bits:
		x = a.lane(wide, k)
		r = rightShifted(x, i.amount, wide, i.unsigned and i.opc >= 0x12, round)
		v = match i.opc:
			0x10, 0x11: c.narrowedUnsigned(r, wide, bits, i.unsigned)
			_: c.clampUnsigned(r, bits) if i.unsigned else c.clampSigned(signedOf(r, wide), bits)
		out.setLane(bits, k, v)
	c.writeNarrow(i, out)

# the shifted lane r cut to `bits`: saturated from signed to unsigned (SQSHRUN) or just cut (SHRN)
fn narrowedUnsigned(mut c core.Cpu, r u64, wide i64, bits i64, saturate bool):
	if saturate: return c.clampSignedToUnsigned(signedOf(r, wide), bits)
	r & core.laneMask(bits)

# SSHLL and USHLL: the lanes of one half widened then shifted left
fn lengtheningShift(mut c core.Cpu, i arm64.Instr, a Vec):
	bits = 8 << i.size
	n = 64 / bits
	out = Vec()
	for k in 0..n:
		x = extendedLane(a.lane(bits, k + (n if i.q else 0)), bits, i.unsigned)
		out.setLane(bits * 2, k, (x << i.amount) & core.laneMask(bits * 2))
	c.vecWrite(i.rd, out, true)

pub fn shiftImmediate(mut c core.Cpu, i arm64.Instr):
	a = c.vecRead(i.rn)
	if i.opc >= 0x14: return c.lengtheningShift(i, a)
	if i.opc >= 0x10: return c.narrowingShift(i, a)
	d = c.vecRead(i.rd)
	bits = 8 << i.size
	out = Vec()
	for k in 0..laneCount(i, bits):
		out.setLane(bits, k, c.shiftLane(i, a.lane(bits, k), d.lane(bits, k), bits))
	c.vecWrite(i.rd, out, i.q)
