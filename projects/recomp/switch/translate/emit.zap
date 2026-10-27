# A function written as Zap: a loop over a match of its labels, entered at the label the thread's
# pc names. Each arm runs its instructions as their forms write them (forms.zap), or else through
# cpu's execute, the decoded instruction written as a literal; branches are the loop's own jumps when they stay inside, a return to the
# dispatcher when they leave (which enters the next function, or the interpreter); a br (a jump
# table's) jumps to the label its register names when it stays inside. A call to a function of the
# same build is a direct call, to any other one through cpu's enter (another build's, found by its
# address, or none); the caller goes on only if the callee came back to the call's next
# instruction and the thread did not halt. A backward jump pays the arm's instructions from the
# thread's budget and yields when it is spent.

import codegen
import recomp.switch.arm64
import recomp.switch.forms

# a translated function's name
pub fn functionName(at i64) str:
	"f{at:x}"

# a jump to target from inside f; the arm's last statement when `tail`, where the loop goes on by itself
fn jump(mut s codegen.Source, f Function, target i64, from i64, tail bool):
	if target < f.at or target >= f.end:
		s.line("c.pc = {target:#x}")
		s.line("return")
		return
	if target <= from:
		s.block("if c.budget <= 0:")
		s.line("c.pc = {target:#x}")
		s.line("return")
		s.end()
	s.line("label = {target:#x}")
	if not tail: s.line("continue")

# one instruction at pc, in an arm; whether it ended the arm. `fused` is the condition of the b.cond
# when the compare before it was fused into it, "" otherwise.
fn instrLines(
	mut s codegen.Source,
	f Function,
	i arm64.Instr,
	pc i64,
	starts {i64: bool},
	numbers {i64: i64},
	fused str
):
	run = "c.emulate({i.literal()}, {pc:#x})"
	match i.op:
		Branch:
			s.jump(f, i.imm, pc, true)
			return true
		BranchCond, CompareBranch, TestBranch:
			s.block("if {fused if fused != "" else i.branchTaken(i.knownFields(pc)) ?? "false"}:")
			s.jump(f, i.imm, pc, false)
			s.end()
		BranchLink:
			ret = pc + 4
			if i.imm in starts:
				s.line("c.link({ret:#x}, {i.imm:#x})")
				s.line("{functionName(i.imm)}(c)")
				s.line("if c.leftAfter({ret:#x}): return")
			else:
				s.line(
					"if core.callOut(c, {ret:#x}, {i.imm:#x}, {numbers.get(i.imm) ?? -1}): return"
				)
		BranchReg:
			s.line("c.pc = i64(c.x[{i.rn}])")
			s.block("if c.pc >= {f.at:#x} and c.pc < {f.end:#x} and c.budget > 0:")
			s.line("label = c.pc")
			s.line("continue")
			s.end()
			s.line("return")
			return true
		BranchLinkReg, Return, Svc, Brk, Unknown:
			s.line(run)
			s.line("return")
			return true
		_:
			match i.flagsKept(f, pc).formLines(i.knownFields(pc)):
				lines:
					for line in lines:
						s.line(line)
				none: s.line(run)
	false

# the lines of the arm of label l, up to next; how many instructions it holds. `starts` and
# `numbers` as in emitFunction.
fn armLines(
	mut body codegen.Source,
	f Function,
	l i64,
	next i64,
	starts {i64: bool},
	numbers {i64: i64}
):
	ran = 0
	fused = ""
	for pc in (0..(next - l) / 4).map(l + it * 4):
		ran += 1
		i = instrAt(pc)
		if f.fusedCondition(i, pc, next) is condition:
			fused = condition
			continue
		if body.instrLines(f, i, pc, starts, numbers, fused): return ran
		fused = ""
	body.jump(f, next, next - 4, true)
	ran

# The function's lines; `starts` the starts of the functions translated into the same build (called
# directly), `numbers` the place of each function of the program in the dispatcher's table, by address.
pub fn emitFunction(f Function, starts {i64: bool}, numbers {i64: i64}) str[]:
	s = codegen.Source()
	s.block("fn {functionName(f.at)}(c mut ref core.Cpu):")
	s.line("label = c.pc")
	s.block("while true:")
	s.block("match label:")
	for k, l in f.labels:
		next = f.labels[k + 1] if k + 1 < f.labels.len else f.end
		body = codegen.Source(level = s.level + 1)
		ran = body.armLines(f, l, next, starts, numbers)
		s.block("{l:#x}:")
		s.line("c.budget -= {ran}")
		s.lines.extend(body.lines)
		s.end()
	s.block("_:")
	s.line("c.pc = label")
	s.line("return")
	s.end()
	s.end()
	s.end()
	s.end()
	s.lines
