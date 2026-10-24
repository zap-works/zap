# What translated code reaches of the dispatcher: the functions the written program registers,
# and the way one calls another build's (a part's) function. Kept apart from the interpreter and
# the thread's loop (cpu/dispatch.zap), so a change there keeps every part.

import recomp.switch.arm64

pub type Translated:
	at i64
	end i64
	run fn(mut ref Cpu)

# the program's translated functions, sorted by address (the written program registers them)
pub mut functions Translated[] = []

# the translated function whose span holds pc, by its index
pub fn functionAt(pc i64) i64?:
	lo = 0
	hi = functions.len
	while lo < hi:
		mid = (lo + hi) / 2
		if functions[mid].end <= pc: lo = mid + 1
		elif functions[mid].at > pc: hi = mid
		else: return mid
	none

# A call from translated code to a function another build translated: the one whose span holds
# the thread's pc run, nothing when none does (the caller then returns to the dispatcher).
pub fn enter(mut c Cpu):
	if functionAt(c.pc) is f: functions[f].run(mut ref c)

# The interpreter's execute, set by the program that runs translated code (cpu's install): the
# instructions the translation does not write out are run through it, so a part does not hold the
# interpreter.
pub mut interpreter fn(mut ref Cpu, arm64.Instr, i64) = (c, _, pc): c.stop(
	pc,
	"no interpreter installed"
)

# one instruction the translation did not write out, run by the interpreter
pub fn emulate(mut c Cpu, i arm64.Instr, pc i64):
	run = interpreter
	run(mut ref c, i, pc)
