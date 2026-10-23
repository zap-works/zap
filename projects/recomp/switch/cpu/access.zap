# What A64's loads and stores do: the address of each mode, the general registers' loads
# (zero- or sign-extended) and stores, the FP/SIMD registers' (1 to 16 bytes, the rest of the
# register cleared on a load), pairs, and the exclusive monitor of one address.

import recomp.switch.arm64

# the address an access reads or writes, and the base's write-back when its mode has one
fn address(mut c Cpu, i arm64.Instr):
	base = i64(c.x[i.rn])
	match i.mode:
		Offset: base + i.imm
		PreIndex:
			c.x[i.rn] = u64(base + i.imm)
			base + i.imm
		PostIndex:
			c.x[i.rn] = u64(base + i.imm)
			base
		RegisterOffset: base + i64(extended(c.x[i.rm], i.shift, i.amount, true))

# a loaded value of the size's bytes sign-extended to 64 bits, or to 32 when not sf
pub fn signExtend(v u64, size i64, sf bool) u64:
	if size == 3: return v
	bitsIn = 8 << size
	x = v
	if (v >> (bitsIn - 1)) & 1 != 0: x = v | ~((u64(1) << bitsIn) - 1)
	x if sf else x & 0xFFFF_FFFF

# a loaded value as the instruction keeps it: sign-extended when signed
fn widened(v u64, i arm64.Instr):
	signExtend(v, i.size, i.sf) if i.signed else v

# register r of the FP/SIMD file loaded with `size` bytes at `at` (4: all 16), the rest zero
pub fn loadVector(mut c Cpu, r i64, at i64, size i64):
	if size == 4:
		c.q[2 * r] = memory.load(at, 3)
		c.q[2 * r + 1] = memory.load(at + 8, 3)
	else:
		c.q[2 * r] = memory.load(at, size)
		c.q[2 * r + 1] = 0

pub fn storeVector(c Cpu, r i64, at i64, size i64):
	if size == 4:
		memory.store(at, 3, c.q[2 * r])
		memory.store(at + 8, 3, c.q[2 * r + 1])
	else:
		memory.store(at, size, c.q[2 * r])

pub fn loadLiteral(mut c Cpu, i arm64.Instr):
	if i.vector: return c.loadVector(i.rd, i.imm, i.size)
	c.set(i.rd, widened(memory.load(i.imm, i.size), i), true)

pub fn loadExclusive(mut c Cpu, i arm64.Instr):
	at = i64(c.x[i.rn])
	c.exclusiveAt = at
	if i.pair:
		size = i.size
		c.set(i.rd, memory.load(at, size), true)
		c.set(i.ra, memory.load(at + (1 << size), size), true)
	else:
		c.set(i.rd, memory.load(at, i.size), true)

# the store happens, and the status is 0, only while the monitor still marks the address
pub fn storeExclusive(mut c Cpu, i arm64.Instr):
	at = i64(c.x[i.rn])
	if c.exclusiveAt != at:
		c.exclusiveAt = -1
		return c.set(i.rm, 1, false)
	if i.pair:
		memory.store(at, i.size, c.x[i.rd])
		memory.store(at + (1 << i.size), i.size, c.x[i.ra])
	else:
		memory.store(at, i.size, c.x[i.rd])
	c.exclusiveAt = -1
	c.set(i.rm, 0, false)

pub fn loadAcquire(mut c Cpu, i arm64.Instr):
	c.set(i.rd, memory.load(i64(c.x[i.rn]), i.size), true)

pub fn storeRelease(mut c Cpu, i arm64.Instr):
	memory.store(i64(c.x[i.rn]), i.size, c.x[i.rd])
