# One decoded instruction run on a thread: its effect, then the next pc (a branch's target, else
# the next word). A supervisor call or an instruction the decoder does not know leaves the thread
# halted with the reason, its pc at the instruction, for the kernel or the caller to see.

import recomp.switch.arm64

# dc zva's operation (op1:CRn:CRm:op2); the system registers below are matched by mrs's and msr's
# 15 bits (op0's low bit:op1:CRn:CRm:op2, op0's high bit always set)
dcZva = 0x1BA1

# the counter's frequency, as the Switch's (19.2 MHz)
pub counterHz = 19_200_000

# the guest's counter (CNTPCT_EL0), kept by whoever runs the threads (the kernel's clock)
pub mut counter u64 = 0

fn readSystem(c Cpu, reg i64) u64?:
	match reg:
		0x5A10: c.nzcv() << 28
		0x5A20: c.fpcr
		0x5A21: c.fpsr
		0x5E82: c.tpidr
		0x5E83: c.tpidrro
		0x5F00: u64(counterHz)
		0x5F01, 0x5F02: counter
		0x5807: 4   # dc zva clears 64 bytes
		0x5801: 0x8444_C004   # the Cortex-A57's cache types
		_: none

fn writeSystem(mut c Cpu, reg i64, v u64):
	match reg:
		0x5A10: c.setNzcv(v >> 28)
		0x5A20: c.fpcr = v
		0x5A21: c.fpsr = v
		0x5E82: c.tpidr = v
		_: return false
	true

pub fn execute(mut c Cpu, i arm64.Instr, pc i64):
	c.pc = pc + 4
	match i.op:
		AddImm: c.addImm(i)
		AddShifted: c.addShifted(i)
		AddExtended: c.addExtended(i)
		AddCarry: c.addCarry(i)
		LogicImm: c.logicImm(i)
		LogicShifted: c.logicShifted(i)
		MoveWide: c.moveWide(i)
		Bitfield: c.bitfield(i)
		Extract: c.extract(i)
		CondCompare: c.condCompare(i)
		CondSelect: c.condSelect(i)
		OneSource: c.oneSource(i)
		TwoSource: c.twoSource(i)
		ThreeSource: c.threeSource(i)
		Adr: c.set(i.rd, u64(i.imm), true)
		Load: c.load(i)
		Store: c.store(i)
		LoadLiteral: c.loadLiteral(i)
		LoadPair: c.loadPair(i)
		StorePair: c.storePair(i)
		LoadExclusive: c.loadExclusive(i)
		StoreExclusive: c.storeExclusive(i)
		LoadAcquire: c.loadAcquire(i)
		StoreRelease: c.storeRelease(i)
		Branch: c.pc = i.imm
		BranchLink:
			c.x[30] = u64(pc + 4)
			c.pc = i.imm
		BranchCond:
			if c.holds(i.cond): c.pc = i.imm
		CompareBranch:
			if (c.get(i.rd, i.sf) == 0) == (i.opc == 0): c.pc = i.imm
		TestBranch:
			if ((c.x[i.rd] >> i.imm2) & 1 == 1) == (i.opc == 1): c.pc = i.imm
		BranchReg: c.pc = i64(c.x[i.rn])
		BranchLinkReg:
			target = i64(c.x[i.rn])
			c.x[30] = u64(pc + 4)
			c.pc = target
		Return: c.pc = i64(c.x[i.rn])
		ReadSystem:
			v = c.readSystem(i.imm) ?? return c.stop(pc, "mrs of {i.imm:x}")
			c.set(i.rd, v, true)
		WriteSystem:
			if not c.writeSystem(i.imm, c.x[i.rd]): c.stop(pc, "msr of {i.imm:x}")
		System:
			if i.imm == dcZva:
				at = i64(c.x[i.rd]) & ~63
				for k in 0..8:
					memory.store(at + k * 8, 3, 0)
		ClearExclusive: c.exclusiveAt = -1
		Hint, Barrier, Prefetch, WriteState: pass
		Float: c.float(i)
		Vector: c.vector(i)
		VectorStructure: c.vectorStructure(i)
		Svc: c.stop(pc + 4, "svc {i.imm:x}")
		Brk: c.stop(pc, "brk {i.imm:x}")
		Unknown: c.stop(pc, "unknown")

# the thread halted at pc with the reason
pub fn stop(mut c Cpu, pc i64, move why str):
	c.pc = pc
	c.halted = why
