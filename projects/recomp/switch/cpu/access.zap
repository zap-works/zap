# What A64's loads and stores do: the address of each mode, the general registers' loads
# (zero- or sign-extended) and stores, the FP/SIMD registers' (1 to 16 bytes, the rest of the
# register cleared on a load), pairs, and the exclusive monitor of one address.

import recomp.switch.arm64

# the address an access reads or writes, and the base's write-back when its mode has one
fn address(mut c Cpu, i arm64.Instr) i64:
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

# a loaded value of the size's bytes sign-extended to the register's width when signed
fn widened(v u64, i arm64.Instr) u64:
	if not i.signed or i.size == 3: return v
	bitsIn = 8 << i.size
	x = v
	if (v >> (bitsIn - 1)) & 1 != 0: x = v | ~((u64(1) << bitsIn) - 1)
	x if i.sf else x & 0xFFFF_FFFF

# register r of the FP/SIMD file loaded with `size` bytes at `at` (4: all 16), the rest zero
fn loadVector(mut c Cpu, r i64, at i64, size i64):
	if size == 4:
		c.q[2 * r] = memory.load(at, 3)
		c.q[2 * r + 1] = memory.load(at + 8, 3)
	else:
		c.q[2 * r] = memory.load(at, size)
		c.q[2 * r + 1] = 0

fn storeVector(c Cpu, r i64, at i64, size i64):
	if size == 4:
		memory.store(at, 3, c.q[2 * r])
		memory.store(at + 8, 3, c.q[2 * r + 1])
	else:
		memory.store(at, size, c.q[2 * r])

pub fn load(mut c Cpu, i arm64.Instr):
	at = c.address(i)
	if i.vector: return c.loadVector(i.rd, at, i.size)
	c.set(i.rd, widened(memory.load(at, i.size), i), true)

pub fn store(mut c Cpu, i arm64.Instr):
	value = c.x[i.rd]
	vecLow = c.q[2 * i.rd]
	at = c.address(i)
	if i.vector: return c.storeVector(i.rd, at, i.size)
	memory.store(at, i.size, value)
	_ = vecLow

pub fn loadLiteral(mut c Cpu, i arm64.Instr):
	if i.vector: return c.loadVector(i.rd, i.imm, i.size)
	c.set(i.rd, widened(memory.load(i.imm, i.size), i), true)

# a pair's address: its mode's, the second element `1 << size` bytes on
pub fn loadPair(mut c Cpu, i arm64.Instr):
	at = c.address(i)
	step = 1 << i.size
	if i.vector:
		c.loadVector(i.rd, at, i.size)
		return c.loadVector(i.ra, at + step, i.size)
	first = widened(memory.load(at, i.size), i)
	second = widened(memory.load(at + step, i.size), i)
	c.set(i.rd, first, true)
	c.set(i.ra, second, true)

pub fn storePair(mut c Cpu, i arm64.Instr):
	first = c.x[i.rd]
	second = c.x[i.ra]
	at = c.address(i)
	step = 1 << i.size
	if i.vector:
		c.storeVector(i.rd, at, i.size)
		return c.storeVector(i.ra, at + step, i.size)
	memory.store(at, i.size, first)
	memory.store(at + step, i.size, second)

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
