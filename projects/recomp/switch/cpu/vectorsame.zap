# Advanced SIMD "three registers of the same type" (and the vector by element forms, whose
# second operand is one lane repeated): the integer operations on each lane of two sources.

import recomp.switch.arm64

# the carry-less product of x and y: its low and high 64 bits
pub fn carrylessMultiply(x u64, y u64) (u64, u64):
	lo = u64(0)
	hi = u64(0)
	for b in 0..64:
		if (y >> b) & 1 == 0: continue
		lo ^= x << b
		if b > 0: hi ^= x >> (64 - b)
	(lo, hi)

fn polynomialLow(x u64, y u64):
	lo, _ = carrylessMultiply(x, y)
	lo

fn allOnes(cond bool, bits i64):
	laneMask(bits) if cond else 0

fn halving(x u64, y u64, bits i64, unsigned bool, round bool):
	r = 1 if round else 0
	if unsigned: return (x + y + u64(r)) >> 1
	u64((signedOf(x, bits) + signedOf(y, bits) + r) >> 1) & laneMask(bits)

fn halvingSub(x u64, y u64, bits i64, unsigned bool):
	if unsigned: return u64((i64(x) - i64(y)) >> 1) & laneMask(bits)
	u64((signedOf(x, bits) - signedOf(y, bits)) >> 1) & laneMask(bits)

# x greater than y (or equal), by the signedness
fn greater(x u64, y u64, bits i64, unsigned bool, orEqual bool):
	if unsigned: return x >= y if orEqual else x > y
	a = signedOf(x, bits)
	b = signedOf(y, bits)
	a >= b if orEqual else a > b

fn absDifference(x u64, y u64, bits i64, unsigned bool):
	if unsigned: return x - y if x > y else y - x
	u64((signedOf(x, bits) - signedOf(y, bits)).abs()) & laneMask(bits)

# SQDMULH and SQRDMULH: the doubled product's high half, saturated
fn doublingHigh(mut c Cpu, x u64, y u64, bits i64, round bool) u64:
	p = signedOf(x, bits) * signedOf(y, bits)
	if round: p += 1 << (bits - 2)
	c.clampSigned(p >> (bits - 1), bits)

# the logical operation `op` (the size field) of three-same's opcode 3 on 64 bits
fn logicWord(op i64, unsigned bool, x u64, y u64, d u64):
	if not unsigned:
		return match op:
			0: x & y
			1: x & ~y
			2: x | y
			_: x | ~y
	match op:
		0: x ^ y
		1: (d & x) | (~d & y)
		2: (d & ~y) | (x & y)
		_: (d & y) | (x & ~y)

# long: one arm a line, the opcodes of the Arm ARM's three-same table
fn sameLane(mut c Cpu, i arm64.Instr, x u64, y u64, acc u64, bits i64) u64:
	u = i.unsigned
	m = laneMask(bits)
	match i.opc:
		0: halving(x, y, bits, u, false)
		1: c.addSaturating(x, y, bits, u)
		2: halving(x, y, bits, u, true)
		4: halvingSub(x, y, bits, u)
		5: c.subSaturating(x, y, bits, u)
		6: allOnes(greater(x, y, bits, u, false), bits)
		7: allOnes(greater(x, y, bits, u, true), bits)
		8: c.shiftedBy(x, y, bits, u, false, false)
		9: c.shiftedBy(x, y, bits, u, false, true)
		10: c.shiftedBy(x, y, bits, u, true, false)
		11: c.shiftedBy(x, y, bits, u, true, true)
		12: x if greater(x, y, bits, u, true) else y
		13: x if greater(y, x, bits, u, true) else y
		14: absDifference(x, y, bits, u)
		15: (acc + absDifference(x, y, bits, u)) & m
		16: (x - y) & m if u else (x + y) & m
		17: allOnes(x == y, bits) if u else allOnes(x & y != 0, bits)
		18: (acc - x * y) & m if u else (acc + x * y) & m
		19: polynomialLow(x, y) & m if u else (x * y) & m
		_: c.doublingHigh(x, y, bits, u)

# the lanes of a and b operated on as the instruction says, written to rd
pub fn sameLanes(mut c Cpu, i arm64.Instr, a Vec, b Vec):
	d = c.vecRead(i.rd)
	out = Vec()
	if i.opc == 3 and not i.scalar:
		out.lo = logicWord(i.size, i.unsigned, a.lo, b.lo, d.lo)
		out.hi = logicWord(i.size, i.unsigned, a.hi, b.hi, d.hi)
		return c.vecWrite(i.rd, out, i.q)
	bits = 8 << i.size
	n = i.laneCount(bits)
	for k in 0..n:
		x, y = operandsAt(i.pair, a, b, bits, n, k)
		out.setLane(bits, k, c.sameLane(i, x, y, d.lane(bits, k), bits))
	c.vecWrite(i.rd, out, i.q)

pub fn threeSame(mut c Cpu, i arm64.Instr):
	c.sameLanes(i, c.vecRead(i.rn), c.vecRead(i.rm))
