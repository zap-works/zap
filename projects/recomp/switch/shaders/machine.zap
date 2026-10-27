# The code as a machine of blocks, when no nesting of ifs and loops holds its jumps (an indirect
# jump, a call, a jump to the end of an if or loop around the innermost: Zap has no labelled
# break): `at` the byte address of the block to run, each block an arm of a match in a loop that
# sets the next one. CAL and PRET push a return address on `returns`, RET takes the last one back;
# an indirect jump (BRX: a register plus its own offset; JMX, JMP, JCAL: from the code's start)
# reaches any block, an address that starts none ending the program.

import recomp.switch.arm64

# the return addresses a thread holds at most (Maxwell's call/return stack holds this many)
pub returnDepth = 16

pub fn writeMachine(mut w Writer):
	starts = w.blockStarts()
	w.e.usesMachine = true
	w.e.openBlock("loop:")
	w.e.openBlock("match at:")
	for n, k in starts:
		end = starts[n + 1] if n + 1 < starts.len else w.e.code.len
		w.e.openBlock("{addressOf(k)}:")
		for j in k..end - 1:
			w.e.emitInstr(w.e.code[j])
		w.ending(end - 1, addressOf(end))
		w.e.closeBlock()
	w.e.openBlock("_:")
	w.e.line("break")
	w.e.closeBlock()
	w.e.closeBlock()
	w.e.closeBlock()

# the first instruction of each block: the code's, a jump's target, a call's return, the one after
# any flow instruction
fn blockStarts(w Writer):
	n = w.e.code.len
	isStart = fill(n, false)
	isStart[0] = true
	for k, s in w.steps:
		i = w.e.code[k]
		if s.flow != .Plain and k + 1 < n: isStart[k + 1] = true
		target = s.target if s.flow == .Jump else -1
		if i.op in [.Cal, .Pret]: target = indexOf(i.branchTarget())
		if target >= 0 and target < n: isStart[target] = true
	(0..n).filter(isStart[it])

# the block's last instruction k written, then where it goes: `next` (the address after it) unless
# its flow goes elsewhere
fn ending(mut w Writer, k i64, next i64):
	i = w.e.code[k]
	s = w.steps[k]
	if s.flow == .Plain:
		w.e.emitInstr(i)
		w.e.line("at = {next}")
		return
	w.e.line("at = {next}")
	w.e.openGuard(i)
	match s.flow:
		Jump: w.e.line("at = {addressOf(s.target)}")
		Return: w.e.line(w.result)
		Discard:
			w.e.line("discard()")
			w.e.line(w.result)
		_: w.e.indirect(i)
	w.e.closeGuard(i)

# an indirect jump, a call or a return
fn indirect(mut e Emitter, i Instr):
	relative = i.at + 8 + arm64.signedBits(i.word, 20, 24)
	absolute = arm64.bits(i.word, 20, 32)
	match i.op:
		Brx: e.line("at = i32.wrap({e.x(i.ra)}) + {relative}")
		Jmx: e.line("at = i32.wrap({e.x(i.ra)}) + {absolute}")
		Jmp: e.line("at = {absolute}")
		Cal, Jcal:
			e.push("{addressOf(indexOf(i.at) + 1)}")
			e.line("at = {i.branchTarget() if i.op == .Cal else absolute}")
		Pret: e.push("{i.branchTarget()}")
		Ret:
			e.line("if called == 0: break")   # a return from the program's own code: its end
			e.line("called -= 1")
			e.line("at = returns[called]")
		_: e.lack(i, "{i.op}", [])

fn push(mut e Emitter, address str):
	e.calls = true
	e.line("returns[called] = {address}")
	e.line("called += 1")
