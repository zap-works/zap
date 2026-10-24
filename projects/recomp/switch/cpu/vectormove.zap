# What the Advanced SIMD groups that move lanes and constants do: copy (dup, ins, smov, umov),
# modified immediate, extract, table lookup and permute.

import recomp.switch.arm64
import recomp.switch.cpu.core

pub fn elementCopy(mut c core.Cpu, i arm64.Instr):
	bits = 8 << i.size
	src = c.vecRead(i.rn)
	match i.opc:
		0:
			out = replicated(src.lane(bits, i.index), bits)
			c.vecWrite(i.rd, out if not i.scalar else Vec(lo = out.lo & core.laneMask(bits)), i.q)
		1: c.vecWrite(i.rd, replicated(c.x[i.rn] & core.laneMask(bits), bits), i.q)
		3:
			d = c.vecRead(i.rd)
			d.setLane(bits, i.index, c.x[i.rn])
			c.vecWrite(i.rd, d, true)
		5: c.set(i.rd, u64(signedOf(src.lane(bits, i.index), bits)), i.q)
		7: c.set(i.rd, src.lane(bits, i.index), i.q)
		_:
			d = c.vecRead(i.rd)
			d.setLane(bits, i.index, src.lane(bits, i.imm))
			c.vecWrite(i.rd, d, true)

pub fn modifiedImmediate(mut c core.Cpu, i arm64.Instr):
	x = u64(i.imm)
	if i.amount == 1:   # fmov's 8 bits: a double (op, held in sf), or a single in each half
		x = core.fmtDouble.expandImm(i.imm) if i.sf
			else core.fmtSingle.expandImm(i.imm) * 0x1_0000_0001
	d = c.vecRead(i.rd)
	out = match i.opc:
		2: Vec(lo = d.lo | x, hi = d.hi | x)
		3: Vec(lo = d.lo & x, hi = d.hi & x)
		_: Vec(lo = x, hi = x)
	c.vecWrite(i.rd, out, i.q)

# EXT: the bytes of Vm:Vn from byte imm
pub fn extractBytes(mut c core.Cpu, i arm64.Instr):
	a = c.vecRead(i.rn)
	b = c.vecRead(i.rm)
	n = 16 if i.q else 8
	out = Vec()
	for k in 0..n:
		j = k + i.imm
		out.setLane(8, k, a.lane(8, j) if j < n else b.lane(8, j - n))
	c.vecWrite(i.rd, out, i.q)

# TBL and TBX: each byte of Vm indexes the bytes of the imm registers from Vn on
pub fn tableLookup(mut c core.Cpu, i arm64.Instr):
	idx = c.vecRead(i.rm)
	d = c.vecRead(i.rd)
	out = Vec()
	for k in 0..(16 if i.q else 8):
		at = i64(idx.lane(8, k))
		r = d.lane(8, k) if i.opc == 1 else u64(0)
		if at < 16 * i.imm:
			r = c.vecRead((i.rn + at / 16) % 32).lane(8, at % 16)
		out.setLane(8, k, r)
	c.vecWrite(i.rd, out, i.q)

# the lane of ZIP, UZP and TRN number k, from a or from b
fn permuted(opc i64, k i64, n i64, a Vec, b Vec, bits i64):
	half = n / 2
	second = opc >= 4
	match opc & 3:
		1:
			j = 2 * (k % half) + (1 if second else 0)
			(a if k < half else b).lane(bits, j)
		2:
			j = k / 2 * 2 + (1 if second else 0)
			(a if k % 2 == 0 else b).lane(bits, j)
		_:
			j = k / 2 + (half if second else 0)
			(a if k % 2 == 0 else b).lane(bits, j)

pub fn permute(mut c core.Cpu, i arm64.Instr):
	a = c.vecRead(i.rn)
	b = c.vecRead(i.rm)
	bits = 8 << i.size
	n = i.laneCount(bits)
	out = Vec()
	for k in 0..n:
		out.setLane(bits, k, permuted(i.opc, k, n, a, b, bits))
	c.vecWrite(i.rd, out, i.q)
