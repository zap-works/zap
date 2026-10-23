# A function written as Zap: a loop over a match of its labels, entered at the label the thread's
# pc names. Each arm runs its instructions as their forms write them (forms.zap), or else through
# cpu's execute, the decoded instruction written as a literal; branches are the loop's own jumps when they stay inside, a return to the
# dispatcher when they leave (which enters the next function, or the interpreter). A call to a
# translated function is a direct call, after which the caller goes on only if the callee came
# back to the call's next instruction and the thread did not halt. A backward jump pays the
# arm's instructions from the thread's budget and yields when it is spent.

import recomp.switch.arm64
import recomp.switch.forms

# a translated function's name
pub fn functionName(at i64) str:
	"f{at:x}"

# the lines of a jump to target from inside f at `depth`
fn jump(f Function, target i64, from i64, depth i64):
	tab = "\t".repeat(depth)
	if target < f.at or target >= f.end: return ["{tab}c.pc = 0x{target:x}", "{tab}return"]
	if target <= from:
		return [
			"{tab}if c.budget <= 0:",
			"{tab}\tc.pc = 0x{target:x}",
			"{tab}\treturn",
			"{tab}label = 0x{target:x}",
			"{tab}continue"
		]
	["{tab}label = 0x{target:x}", "{tab}continue"]

# the lines of one instruction at pc (in an arm, at depth 4); whether it ended the arm
fn instrLines(f Function, i arm64.Instr, pc i64, starts {i64: bool}, mut out str[]):
	tab = "\t\t\t\t"
	run = "{tab}c.execute({i.literal()}, 0x{pc:x})"
	match i.op:
		Branch:
			out.extend(f.jump(i.imm, pc, 4))
			return true
		BranchCond, CompareBranch, TestBranch:
			out.push("{tab}if {i.branchTaken(i.knownFields(pc)) ?? "false"}:")
			out.extend(f.jump(i.imm, pc, 5))
		BranchLink:
			ret = pc + 4
			out.push("{tab}c.x[30] = 0x{ret:x}")
			out.push("{tab}c.pc = 0x{i.imm:x}")
			if i.imm in starts:
				out.push("{tab}{functionName(i.imm)}(c)")
				out.push("{tab}if c.pc != 0x{ret:x} or c.isHalted: return")
				out.push("{tab}label = 0x{ret:x}")
				out.push("{tab}continue")
			else:
				out.push("{tab}return")
			return true
		BranchReg, BranchLinkReg, Return, Svc, Brk, Unknown:
			out.push(run)
			out.push("{tab}return")
			return true
		_:
			match i.formLines(i.knownFields(pc)):
				lines: out.extend(lines.map("{tab}{it}"))
				none: out.push(run)
	false

# The function's lines; `starts` the translated functions' starts.
pub fn emitFunction(f Function, starts {i64: bool}) str[]:
	out = [
		"fn {functionName(f.at)}(c mut ref cpu.Cpu):",
		"\tlabel = c.pc",
		"\twhile true:",
		"\t\tmatch label:"
	]
	for k, l in f.labels:
		next = f.labels[k + 1] if k + 1 < f.labels.len else f.end
		out.push("\t\t\t0x{l:x}:")
		out.push("\t\t\t\tc.budget -= {(next - l) / 4}")
		ended = false
		for pc in (0..(next - l) / 4).map(l + it * 4):
			ended = f.instrLines(instrAt(pc), pc, starts, out)
			if ended: break
		if not ended:
			out.extend(f.jump(next, next - 4, 4))
	out.push("\t\t\t_:")
	out.push("\t\t\t\tc.pc = label")
	out.push("\t\t\t\treturn")
	out
