# A module's code as functions: where each starts (its unwind tables' FDEs, the module's entry,
# every bl's target in its .text), where it ends (its FDE's length, else the next start) and its
# labels: the places it may be entered at besides its start (a branch's target inside it, the
# place after a call, a supervisor call or a branch that does not come back).

import recomp.switch.arm64
import recomp.switch.cpu

pub type Function:
	at i64
	end i64
	labels i64[]   # sorted, the start first

# the decoded instruction at pc
pub fn instrAt(pc i64) arm64.Instr:
	arm64.decode(i64(cpu.memory.load(pc, 2)), pc)

# whether an instruction leaves the straight line for good (b, br, ret, an unknown word)
fn ends(i arm64.Instr):
	i.op in [.Branch, .BranchReg, .Return, .Unknown, .Brk]

# The functions of the code in [at, textEnd).
pub fn findFunctions(at i64, textEnd i64) Function[]:
	spanEnd {i64: i64} = {}
	for s in frameSpans(at):
		if s.at >= at and s.at < textEnd: spanEnd[s.at] = s.at + s.size
	starts {i64: bool} = {at: true}
	for s, _ in spanEnd:
		starts[s] = true
	for pc in (0..(textEnd - at) / 4).map(at + it * 4):
		i = instrAt(pc)
		if i.op == .BranchLink and i.imm >= at and i.imm < textEnd: starts[i.imm] = true
	sorted = starts.keys().sorted()
	out = []
	for k, s in sorted:
		next = sorted[k + 1] if k + 1 < sorted.len else textEnd
		end = (spanEnd.get(s) ?? next).min(next)
		out.push(Function(at = s, end, labels = labelsOf(s, end)))
	out

# the labels of the function in [at, end)
fn labelsOf(at i64, end i64):
	labels {i64: bool} = {at: true}
	for pc in (0..(end - at) / 4).map(at + it * 4):
		i = instrAt(pc)
		match i.op:
			Branch, BranchCond, CompareBranch, TestBranch:
				if i.imm >= at and i.imm < end: labels[i.imm] = true
			_: pass
		after = i.op in [.BranchLink, .BranchLinkReg, .Svc] or i.ends()
		if after and pc + 4 < end: labels[pc + 4] = true
	labels.keys().sorted()

# The functions that hold one of the addresses a run entered (a profile), those addresses among
# their labels.
pub fn ranIn(functions Function[], addresses i64[]) Function[]:
	held {i64: bool} = {}
	for a in addresses:
		held[a] = true
	out = []
	for f in functions:
		ran = (0..(f.end - f.at) / 4).map(f.at + it * 4).filter(it in held)
		if ran.isEmpty: continue
		# a block the run entered is a label too: a jump table's targets, which no direct branch names
		labels {i64: bool} = {}
		for l in f.labels:
			labels[l] = true
		for a in ran:
			labels[a] = true
		out.push(Function(at = f.at, end = f.end, labels = labels.keys().sorted()))
	out
