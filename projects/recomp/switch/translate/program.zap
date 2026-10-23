# A module's code as functions, found as SavageWindRecomp finds them (tools/analyze.py, gen.py):
# where each starts (its unwind tables' FDEs, the code its relocations and symbols name, every
# bl's target, an adr or adrp+add that makes an address of code outside the function it is in),
# where it ends (its FDE's range, else the next start) and its labels: the places it may be
# entered at besides its start (a branch's target, an address of code made inside its own FDE, a
# jump table's targets, the place after a call, a supervisor call or a branch that does not come
# back). A branch into another function makes a label there (a tail call to its middle).

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

# the span of the sorted spans that holds pc, if any
fn spanHolding(spans Span[], pc i64) Span?:
	lo = 0
	hi = spans.len
	while lo < hi:
		mid = (lo + hi) / 2
		if spans[mid].at + spans[mid].size <= pc: lo = mid + 1
		elif spans[mid].at > pc: hi = mid
		else: return spans[mid]
	none

# whether `made` lies inside the span that holds pc, past its start
fn inOwnSpan(spans Span[], pc i64, made i64):
	own = spanHolding(spans, pc) ?? return false
	made > own.at and made < own.at + own.size

# the code address an adr makes, or an adrp with an add of the same register after it
fn madeAddress(i arm64.Instr, pc i64) i64?:
	if cpu.memory.load(pc, 2) >> 31 == 0: return i.imm   # adr
	for next in (1..=8).map(pc + it * 4):
		a = instrAt(next)
		if a.op == .AddImm and not a.setFlags and a.rn == i.rd and a.rd == i.rd:
			return i.imm + a.imm
		if a.rd == i.rd or ends(a): return none
	none

# The functions of the code in [at, textEnd).
pub fn findFunctions(at i64, textEnd i64) Function[]:
	inText = (a i64): a >= at and a < textEnd
	spans = frameSpans(at).filter(inText(it.at)).sortedBy(.at)
	starts {i64: bool} = {at: true}
	for s in spans:
		starts[s.at] = true
	for s in dynamicStarts(at, textEnd):
		starts[s] = true
	labels {i64: bool} = {}
	for pc in (0..(textEnd - at) / 4).map(at + it * 4):
		i = instrAt(pc)
		match i.op:
			BranchLink:
				if inText(i.imm): starts[i.imm] = true
			Branch, BranchCond, CompareBranch, TestBranch:
				if inText(i.imm): labels[i.imm] = true
			Adr:
				if madeAddress(i, pc) is made and inText(made):
					if spans.inOwnSpan(pc, made): labels[made] = true else: starts[made] = true
			BranchReg:
				if spanHolding(spans, pc) is own:
					for t in tableTargets(pc, own.at, own.at + own.size) ?? []:
						labels[t] = true
			_: pass
		if i.op in [.BranchLink, .BranchLinkReg, .Svc] or ends(i): labels[pc + 4] = true
	spanEnd {i64: i64} = {}
	for s in spans:
		spanEnd[s.at] = s.at + s.size
	sorted = starts.keys().sorted()
	held = labels.keys().sorted()
	out = []
	k = 0
	for n, s in sorted:
		next = sorted[n + 1] if n + 1 < sorted.len else textEnd
		end = (spanEnd.get(s) ?? next).min(next)
		own = [s]
		while k < held.len and held[k] < end:
			if held[k] > s: own.push(held[k])
			k += 1
		out.push(Function(at = s, end, labels = own))
	out

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
