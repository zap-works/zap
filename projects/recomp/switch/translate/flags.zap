# Whether the flags (NZCV) are read after a point of a function, which lets the translation leave
# unset the flags an instruction writes: a path is dead where an instruction sets all four, live
# where one reads them, and dead where it leaves the function, calls, returns or jumps through a
# register (the calling convention carries no flags across them). A scan that grows past `reach`
# instructions is live, the safe answer.

import recomp.switch.arm64
import recomp.switch.forms

reach = 64

# whether i reads the flags (anything that might, including the instructions that halt)
fn readsFlags(i arm64.Instr):
	match i.op:
		BranchCond, CondSelect, CondCompare, AddCarry, ReadSystem, WriteSystem, WriteState, Unknown, Brk: true
		Float: i.fop in [.Select, .CondCompare]
		_: false

# whether i sets all four flags
fn writesFlags(i arm64.Instr):
	i.setsNzcv() or (i.op == .Float and i.fop == .Compare)

# Whether no instruction of f reads the flags as they stand entering pc.
fn flagsDeadAt(f Function, pc i64):
	pending = [pc]
	seen {i64: bool} = {}
	k = 0
	while k < pending.len:
		at = pending[k]
		k += 1
		if at < f.at or at >= f.end or at in seen: continue
		seen[at] = true
		if seen.len > reach: return false
		i = instrAt(at)
		if i.readsFlags(): return false
		if i.writesFlags(): continue
		match i.op:
			Branch: pending.push(i.imm)
			CompareBranch, TestBranch:
				pending.push(i.imm)
				pending.push(at + 4)
			BranchLink, BranchLinkReg, BranchReg, Return, Svc: pass
			_: pending.push(at + 4)
	true

# i without the flags it sets when nothing reads them
fn flagsKept(i arm64.Instr, f Function, pc i64):
	if not i.setsNzcv() or not f.flagsDeadAt(pc + 4): return i
	j = i.copy()
	j.setFlags = false
	if j.op in [.LogicImm, .LogicShifted]: j.opc = 0
	j

# The condition of the b.cond after a compare at pc (a flag-setting instruction that keeps no
# result) as an expression of the compare's operands, when no path reads the flags after the
# branch; none when the pair is not fused. `next` ends the compare's arm.
fn fusedCondition(f Function, i arm64.Instr, pc i64, next i64):
	if not i.setsNzcv() or i.rd != arm64.zr or pc + 4 >= next: return none
	b = instrAt(pc + 4)
	if b.op != .BranchCond or not f.flagsDeadAt(b.imm) or not f.flagsDeadAt(pc + 8): return none
	i.flagsCondition(i.knownFields(pc), b.cond)
