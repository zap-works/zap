# The targets of a `br` that reads a bounds-checked jump table (SavageWindRecomp's gen.py
# jump_table): the index compared with an immediate (cmp), a branch past the table when it is
# above (b.hi/b.hs, the table after it) or into the table when it is not (b.ls/b.lo), then the
# address computed and the br. The window from the compare to the br is run once per index on a
# scratch thread (cpu's execute), the table base made first by replaying the function's adr, adrp
# and add from its start, and each target must lie in the function.

import recomp.switch.arm64
import recomp.switch.cpu

condHs = 2
condLo = 3
condHi = 8
condLs = 9

fn isControl(i arm64.Instr):
	i.op in [
		.Branch,
		.BranchLink,
		.BranchCond,
		.CompareBranch,
		.TestBranch,
		.BranchReg,
		.BranchLinkReg,
		.Return,
		.Svc,
		.Brk,
		.Unknown
	]

fn setsFlags(i arm64.Instr):
	i.setFlags or i.op in [.CondCompare, .Float, .WriteSystem, .WriteState] or
		(i.op in [.LogicImm, .LogicShifted] and i.opc == 3)

# a `cmp rn, #imm` (subs to zr)
fn isCompareImm(i arm64.Instr):
	i.op == .AddImm and i.setFlags and i.subtract and i.rd == arm64.zr

# The targets of the br at brPc in the function [lo, hi), none when it reads no table found so.
pub fn tableTargets(brPc i64, lo i64, hi i64) i64[]?:
	fallThrough(brPc, lo, hi) ?? taken(brPc, lo, hi)

# the compare whose flags the conditional branch at guard tests: straight code with no other
# flag write between, at most 12 instructions back
fn guardCompare(guard i64, lo i64) i64?:
	a = guard - 4
	while a >= lo and guard - a <= 48:
		i = instrAt(a)
		if isCompareImm(i): return a
		if i.isControl() and i.op != .BranchCond or i.setsFlags(): return none
		a -= 4
	none

# how many entries a compare of limit and a guard of cond allow, none past 4096
fn entries(limit i64, cond i64) i64?:
	count = limit + 1 if cond in [condHi, condLs] else limit
	none if count <= 0 or count > 4096 else count

# where the straight code that ends before `at` begins, at most 12 instructions back
fn straightFrom(at i64, lo i64) i64:
	s = at
	while s - 4 >= lo and at - (s - 4) <= 48 and not instrAt(s - 4).isControl():
		s -= 4
	s

# cmp idx, #n; b.hi/b.hs default; the address made; br
fn fallThrough(brPc i64, lo i64, hi i64) i64[]?:
	a = brPc - 4
	while true:
		if a < lo or brPc - a > 128: return none
		i = instrAt(a)
		if i.op == .BranchCond and i.cond in [condHi, condHs]: break
		if i.isControl() and i.op != .BranchCond: return none
		a -= 4
	compare = guardCompare(a, lo) ?? return none
	count = entries(instrAt(compare).imm, instrAt(a).cond) ?? return none
	start = straightFrom(compare, lo)
	run(brPc, lo, hi, start, compare, copiesOf(start, compare, instrAt(compare).rn), count)

# cmp idx, #n; b.ls/b.lo table; ... table: the address made; br
fn taken(brPc i64, lo i64, hi i64) i64[]?:
	s = straightFrom(brPc, lo)
	for g in (0..(hi - lo) / 4).map(lo + it * 4):
		i = instrAt(g)
		if i.op != .BranchCond or i.cond not in [condLs, condLo] or i.imm != s: continue
		compare = guardCompare(g, lo) ?? continue
		count = entries(instrAt(compare).imm, i.cond) ?? continue
		return run(brPc, lo, hi, s, s, [instrAt(compare).rn], count)
	none

# the register an instruction copies into its rd unchanged in value (and, mov, uxtb...), if any
fn copiedFrom(i arm64.Instr) i64?:
	match i.op:
		LogicImm: i.rn if i.opc == 0 else none
		LogicShifted: i.rm if i.opc == 1 and i.rn == arm64.zr and not i.subtract and i.amount == 0
			else none
		Bitfield: i.rn if i.opc != 1 else none
		_: none

# the index register and those holding its value in [start, at): what it was copied from and the
# copies of those (the table is sometimes read through another copy after the check)
fn copiesOf(start i64, at i64, index i64) i64[]:
	regs = [index]
	changed = true
	while changed:
		changed = false
		for pc in (0..(at - start) / 4).map(start + it * 4):
			i = instrAt(pc)
			src = i.copiedFrom() ?? continue
			if src >= 31 or i.rd >= 31: continue
			for (x, y) in [(i.rd, src), (src, i.rd)]:
				if x in regs and y not in regs:
					regs.push(y)
					changed = true
	regs

# [start, brPc) run once per index (set in the index registers on reaching setAt), the br's
# register read after each; the targets, none when one leaves [lo, hi) or the run cannot be
fn run(brPc i64, lo i64, hi i64, start i64, setAt i64, index i64[], count i64) i64[]?:
	base = cpu.Cpu()
	for r in 0..=arm64.sp:
		base.x[r] = u64(lo)   # a readable place for what the window does not make
	for pc in (0..(start - lo) / 4).map(lo + it * 4):
		i = instrAt(pc)
		if i.op == .Adr or (i.op == .AddImm and not i.setFlags): base.execute(i, pc)
	rn = instrAt(brPc).rn
	targets {i64: bool} = {}
	for k in 0..count:
		c = base.copy()
		for pc in (0..(brPc - start) / 4).map(start + it * 4):
			if pc == setAt:
				for r in index:
					c.x[r] = u64(k)
			i = instrAt(pc)
			if i.op in [.BranchCond, .Store, .StorePair, .StoreExclusive, .StoreRelease, .VectorStructure]:
				continue   # (a store would write over the code the translation reads)
			if i.isControl(): return none
			c.execute(i, pc)
		t = i64(c.x[rn])
		if cpu.memory.takeFault() != "" or t < lo or t >= hi or t % 4 != 0: return none
		targets[t] = true
	if count > 1 and targets.len == 1: return none   # the index was not the one the table reads
	targets.keys().sorted()
