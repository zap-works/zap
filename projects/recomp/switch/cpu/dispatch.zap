# A thread run from its pc on translated code where there is some and the interpreter elsewhere.
# A translated function may be entered at its start or at any of its labels (a branch target, a
# return site, a place it yields at); it returns once the guest leaves it, its pc set to where.
# The host's stack is only a short cut: a function that yields returns at once, every caller
# under it too, and the thread later goes on from its pc, the guest's own stack holding the
# return addresses.

pub type Translated:
	at i64
	end i64
	run fn(mut ref Cpu)

# the program's translated functions, sorted by address (the written program registers them)
pub mut functions Translated[] = []

# the translated function whose span holds pc, by its index
fn functionAt(pc i64) i64?:
	lo = 0
	hi = functions.len
	while lo < hi:
		mid = (lo + hi) / 2
		if functions[mid].end <= pc: lo = mid + 1
		elif functions[mid].at > pc: hi = mid
		else: return mid
	none

# instructions run by the interpreter until one leaves the straight line (a branch taken, a
# call, a halt); how many
fn interpretBlock(mut c Cpu, mut code Decoded) i64:
	n = 0
	while true:
		pc = c.pc
		c.execute(code.at(pc), pc)
		n += 1
		if memory.fault != "":
			c.halted = "memory fault at {pc:x}: {memory.fault}"
			memory.fault = ""
		if c.halted != "" or c.pc != pc + 4 or n >= 64: break
	n

# Runs the thread for about `budget` instructions, or until it halts (c.halted says why); how
# many ran, counting a translated function's entry as one.
pub fn runThread(mut c Cpu, mut code Decoded, budget i64) i64:
	c.budget = budget
	ran = 0
	while c.halted == "" and c.budget > 0:
		pc = c.pc
		c.trail[c.trailAt % len] = pc
		c.trailAt += 1
		if functionAt(pc) is f:
			before = c.budget
			functions[f].run(mut ref c)
			if c.pc != pc or c.halted != "" or c.budget != before:
				ran += before - c.budget + 1
				c.budget -= 1
				continue
		k = c.interpretBlock(code)
		ran += k
		c.budget -= k
	ran
