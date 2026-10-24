# What A64's vector structure loads and stores do (arm64/structure.zap decodes them): elements
# walked structure by structure, each structure's elements in consecutive registers (wrapping
# at v31), the address moving on by an element each.

import recomp.switch.arm64
import recomp.switch.cpu.core

# lane `index` of register r, of 1 << size bytes
pub fn lane(c core.Cpu, r i64, index i64, size i64) u64:
	at = index << size
	word = c.q[2 * r + at / 8]
	if size == 3: return word
	(word >> ((at % 8) * 8)) & ((u64(1) << (8 << size)) - 1)

pub fn setLane(mut c core.Cpu, r i64, index i64, size i64, v u64):
	at = index << size
	w = 2 * r + at / 8
	if size == 3:
		c.q[w] = v
		return
	shift = (at % 8) * 8
	m = ((u64(1) << (8 << size)) - 1) << shift
	c.q[w] = (c.q[w] & ~m) | ((v << shift) & m)

pub fn vectorStructure(mut c core.Cpu, i arm64.Instr):
	at = i64(c.x[i.rn])
	start = at
	ebytes = 1 << i.size
	lanes = (16 if i.q else 8) / ebytes
	if i.opc == 2:
		for s in 0..i.amount:
			r = (i.rd + s) % 32
			v = core.memory.load(at, i.size)
			for e in 0..lanes:
				c.setLane(r, e, i.size, v)
			if not i.q: c.q[2 * r + 1] = 0
			at += ebytes
	elif i.index >= 0:
		for s in 0..i.amount:
			r = (i.rd + s) % 32
			if i.opc == 1: c.setLane(r, i.index, i.size, core.memory.load(at, i.size))
			else: core.memory.store(at, i.size, c.lane(r, i.index, i.size))
			at += ebytes
	else:
		for k in 0..i.imm2:
			for e in 0..lanes:
				for s in 0..i.amount:
					r = (i.rd + k + s) % 32
					if i.opc == 1: c.setLane(r, e, i.size, core.memory.load(at, i.size))
					else: core.memory.store(at, i.size, c.lane(r, e, i.size))
					at += ebytes
		if i.opc == 1 and not i.q:
			for k in 0..i.imm2 * i.amount:
				c.q[2 * ((i.rd + k) % 32) + 1] = 0
	if i.mode == .PostIndex:
		c.x[i.rn] = u64(start) + (u64(at - start) if i.rm == arm64.zr else c.x[i.rm])
