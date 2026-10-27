# The control flow rebuilt as Zap's if, else and loop. Each flow instruction becomes a jump to an
# instruction (BRA, its guard the predicate and the condition code test; SYNC to its SSY's target,
# BRK to its PBK's, CONT to its PCNT's: the innermost such region around it, as the compiler nests
# them), a return (EXIT) or a discard (KIL). Then a range of the code is written in order: a
# backward jump makes a loop of its target up to it, a forward conditional jump an if of what it
# skips (an if-else when what it skips ends with a jump past its target), a jump to the innermost
# loop's end or start `break` or `continue`, a jump to where the block ends nothing. An if whose
# part jumps past its end to a common exit is wrapped in a block run once (`loop:` ending in
# `break`), so those jumps break out of it. Any other jump (or an indirect one, a call) makes the
# whole code a machine of blocks instead (machine.zap).

import recomp.switch.arm64

pub type Flow:
	Plain
	Jump
	Return
	Discard
	Unknown   # a jump no nesting of ifs and loops holds (indirect, a call): machine.zap's

pub type Step:
	flow Flow = .Plain
	target i64 = -1   # a jump's instruction index

# The flow of each instruction of the code.
pub fn stepsOf(code Instr[]) Step[]:
	steps = []
	for k, i in code:
		steps.push(
			match i.op:
				Bra: braStep(i)
				Sync: regionJump(code, k, .Ssy)
				Brk: regionJump(code, k, .Pbk)
				Cont: regionJump(code, k, .Pcnt)
				Exit: Step(flow = .Return)
				Kil: Step(flow = .Discard)
				Brx, Jmp, Jmx, Cal, Jcal, Ret, Pret, Longjmp, Plongjmp, Pexit: Step(flow = .Unknown)
				_: Step()
		)
	steps

# BRA when its target is no constant's (its condition code test is part of its guard)
fn braStep(i Instr):
	if arm64.hasBit(i.word, 5): return Step(flow = .Unknown)
	Step(flow = .Jump, target = indexOf(i.branchTarget()))

pub alwaysTest = 15

# a flow instruction's condition code test (bits 0-4), alwaysTest for any other
pub fn flowTest(i Instr) i64:
	if i.op in [.Bra, .Brk, .Cont, .Sync, .Exit, .Kil, .Ret, .Brx, .Jmx]:
		return arm64.bits(i.word, 0, 5)
	alwaysTest

# The condition under which i runs (with `negated`, does not): its guard predicate and its
# condition code test.
pub fn guard(mut e Emitter, i Instr, negated bool) str:
	test = i.flowTest()
	if test == alwaysTest: return e.pred(i.pred, i.predNot != negated)
	p = e.pred(i.pred, i.predNot)
	t = e.flowTestOf(test)
	both = t if p == "true" else "{p} and {t}"
	"not ({both})" if negated else both

# Condition code test t (yuzu's GetFlowTest; the CSM tests never hold, as its FCSM_TR stub)
fn flowTestOf(mut e Emitter, t i64):
	z, s, c, o = "zf", "sf", "cf", "of"
	test = [
		"false",
		"(({s} and not {z}) != {o})",
		"(not {s} and {z})",
		"({s} != ({z} or {o}))",
		"((not {s} != {o}) and not {z})",
		"not {z}",
		"({s} == {o})",
		"(not {s} or not {z})",
		"({s} and {z})",
		"({s} != {o})",
		"{z}",
		"(({s} != {o}) or {z})",
		"(not {s} != ({z} or {o}))",
		"({s} or not {z})",
		"((not {s} or {z}) != {o})",
		"true",
		"not {o}",
		"not {c}",
		"not {s}",
		"({z} or not {c})",
		"({c} and not {z})",
		"{s}",
		"{c}",
		"{o}",
		"false",
		"false",
		"false",
		"false",
		"false",
		"false",
		"({s} or {z})",
		"(not {s} and not {z})"
	][t]
	for k, name in flagNames:
		if name in test: e.cc(k)
	test

# the jump to the target of the innermost `push` (SSY, PBK, PCNT) whose region holds instruction k
fn regionJump(code Instr[], k i64, push Op):
	j = k
	while j > 0:
		j -= 1
		if code[j].op == push and indexOf(code[j].branchTarget()) > k:
			return Step(flow = .Jump, target = indexOf(code[j].branchTarget()))
	Step(flow = .Unknown)

# A loop or an if being written: where a jump means `continue` (a loop's head), `break` (its end)
# or nothing (the end of an if's part, from its last instruction).
type Frame:
	isLoop bool
	head i64
	end i64

pub type Writer:
	e Emitter
	steps Step[]
	frames Frame[] = []
	result str   # what EXIT returns: `return` and the stage's outputs
	failure str = ""   # the first unstructured jump met, "" for none

	fn unstructured(i Instr):
		if failure == "": failure = "an unstructured jump: {i.op} at {i.at:x}"

	# the instructions [from, to): `loopAt` the loop or block being written, which starts at `from`
	fn region(from i64, to i64, loopAt i64):
		k = from
		while k < to and failure == "":
			end = loopEnd(k, to)
			if k != loopAt and end > k:
				writeLoop(k, end)
				k = end
				continue
			block = blockEnd(k, to)
			if k != loopAt and block > k:
				writeBlock(k, block)
				k = block
				continue
			k = step(k, to)

	# An if at k (a guarded jump forward) whose part jumps past its own end, to T within the
	# region (the exit of a chain of cases): a block of the code from k to the farthest such T, so
	# those jumps break out of it; -1 for none.
	fn blockEnd(k i64, to i64):
		if steps[k].flow != .Jump or not e.code[k].isGuarded(): return -1
		ifEnd = steps[k].target
		if ifEnd <= k + 1: return -1
		end = -1
		for j in k + 1..ifEnd:
			t = steps[j].target
			elsePart = j == ifEnd - 1 and not e.code[j].isGuarded()   # an if-else's own jump
			if steps[j].flow == .Jump and not elsePart and t > ifEnd and t <= to and t > end:
				end = t
		end

	# a block run once: a loop with no head to continue to, whose end is where its jumps break to
	fn writeBlock(start i64, end i64):
		e.openBlock("loop:")
		frames.push(Frame(isLoop = true, head = -2, end))
		region(start, end, start)
		e.line("break")
		frames.pop()
		e.closeBlock()

	fn writeLoop(head i64, end i64):
		e.openBlock("loop:")
		frames.push(Frame(isLoop = true, head, end))
		region(head, end, head)
		if fallsThrough(end - 1): e.line("break")
		frames.pop()
		e.closeBlock()

	# the end of the loop whose head is k: past its last jump back to k, -1 for none
	fn loopEnd(k i64, to i64):
		end = -1
		for j in k..to:
			if steps[j].flow == .Jump and steps[j].target == k: end = j + 1
		end

	fn fallsThrough(k i64):
		s = steps[k]
		not ((s.flow == .Jump or s.flow == .Return) and not e.code[k].isGuarded())

	# instruction k written: the next instruction to write
	fn step(k i64, to i64) i64:
		i = e.code[k]
		match steps[k].flow:
			Plain:
				e.emitInstr(i)
			Return:
				# a void stage's last EXIT ends it without a word
				if result == "return" and k == e.code.len - 1 and frames.isEmpty and
					not i.isGuarded():
					return k + 1
				e.openGuard(i)
				e.line(result)
				e.closeGuard(i)
			Discard:
				e.openGuard(i)
				e.line("discard()")
				e.line(result)
				e.closeGuard(i)
			Unknown:
				unstructured(i)
			Jump:
				return jump(k, to)
		k + 1

	# the jump at k: an if or an if-else of what it skips, or break, continue, nothing
	fn jump(k i64, to i64) i64:
		i = e.code[k]
		t = steps[k].target
		said = meaning(t, k == to - 1)
		if said is text:
			if text != "":
				e.openGuard(i)
				e.line(text)
				e.closeGuard(i)
			return k + 1
		if t <= k or t > to:
			unstructured(i)
			return to
		if not i.isGuarded(): return t
		last = steps[t - 1]
		elseEnd = last.target if last.flow == .Jump and not e.code[t - 1].isGuarded() and
			last.target > t and last.target <= to
			else -1
		e.openBlock("if {e.guard(i, true)}:")
		frames.push(Frame(isLoop = false, head = -1, end = elseEnd if elseEnd > 0 else t))
		region(k + 1, t, -1)
		e.closeBlock()
		if elseEnd > 0:
			e.openBlock("else:")
			region(t, elseEnd, -1)
			e.closeBlock()
		frames.pop()
		elseEnd if elseEnd > 0 else t

	# what a jump to t means where it is: "break", "continue", "" (nothing: from the last
	# instruction to the end of the innermost if's part or its loop's head), none when it is no
	# such jump
	fn meaning(t i64, isLast bool) str?:
		if frames.last is f and isLast and t == (f.head if f.isLoop else f.end): return ""
		if frames.isEmpty and t == e.code.len and isLast: return ""
		for j in 0..frames.len:
			f = frames[len - 1 - j]
			if f.isLoop:
				if t == f.end: return "break"
				if t == f.head: return "continue"
				return none
		none
