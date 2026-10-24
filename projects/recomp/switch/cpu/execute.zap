# One decoded instruction run on a thread: its effect, then the next pc (a branch's target, else
# the next word). A supervisor call or an instruction the decoder does not know leaves the thread
# halted with the reason, its pc at the instruction, for the kernel or the caller to see.

import recomp.switch.arm64
import recomp.switch.cpu.core

# dc zva's operation (op1:CRn:CRm:op2); the system registers below are matched by mrs's and msr's
# 15 bits (op0's low bit:op1:CRn:CRm:op2, op0's high bit always set)
dcZva = 0x1BA1

# the counter's frequency, as the Switch's (19.2 MHz)
pub counterHz = 19_200_000

# the guest's counter (CNTPCT_EL0), kept by whoever runs the threads (the kernel's clock)
pub mut counter u64 = 0

fn readSystem(c core.Cpu, reg i64) u64?:
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

fn writeSystem(mut c core.Cpu, reg i64, v u64):
	match reg:
		0x5A10: c.setNzcv(v >> 28)
		0x5A20: c.fpcr = v
		0x5A21: c.fpsr = v
		0x5E82: c.tpidr = v
		_: return false
	true

pub fn execute(mut c core.Cpu, i arm64.Instr, pc i64):
	c.pc = pc + 4
	match i.op:
		AddImm: c.formAddImm(i)
		AddShifted: c.formAddShifted(i)
		AddExtended: c.formAddExtended(i)
		AddCarry: c.formAddCarry(i)
		LogicImm: c.formLogicImm(i)
		LogicShifted: c.formLogicShifted(i)
		MoveWide: c.formMoveWide(i)
		Bitfield: c.formBitfield(i)
		Extract: c.formExtract(i)
		CondCompare: c.formCondCompare(i)
		CondSelect: c.formCondSelect(i)
		OneSource: c.oneSource(i)
		TwoSource: c.twoSource(i)
		ThreeSource: c.formThreeSource(i)
		Adr: c.formAdr(i)
		Load: c.formLoad(i)
		Store: c.formStore(i)
		LoadLiteral: c.loadLiteral(i)
		LoadPair: c.formLoadPair(i)
		StorePair: c.formStorePair(i)
		LoadExclusive: c.loadExclusive(i)
		StoreExclusive: c.storeExclusive(i)
		LoadAcquire: c.loadAcquire(i)
		StoreRelease: c.storeRelease(i)
		Branch: c.pc = i.imm
		BranchLink:
			c.x[30] = u64(pc + 4)
			c.pc = i.imm
		BranchCond: c.formBranchCond(i)
		CompareBranch: c.formCompareBranch(i)
		TestBranch: c.formTestBranch(i)
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
					core.memory.store(at + k * 8, 3, 0)
		ClearExclusive: c.exclusiveAt = -1
		Hint, Barrier, Prefetch, WriteState: pass
		Float: c.formFloat(i)
		Vector: c.vector(i)
		VectorStructure: c.vectorStructure(i)
		Svc: c.stop(pc + 4, "svc {i.imm:x}")
		Brk: c.stop(pc, "brk {i.imm:x}")
		Unknown: c.stop(pc, "unknown")

# the translated code's way to the interpreter: the program that runs it calls this once
pub fn install():
	core.interpreter = executeOn

fn executeOn(c mut ref core.Cpu, i arm64.Instr, pc i64):
	c.execute(i, pc)
