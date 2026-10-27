# A thread run from its pc on translated code where there is some and the interpreter elsewhere.
# A translated function may be entered at its start or at any of its labels (a branch target, a
# return site, a place it yields at); it returns once the guest leaves it, its pc set to where.
# The host's stack is only a short cut: a function that yields returns at once, every caller
# under it too, and the thread later goes on from its pc, the guest's own stack holding the
# return addresses.

import fs
import recomp.switch.cpu.core

# when recording, the address of every block the threads entered (a profile for the
# translation: tools/run.zap --profile)
pub mut recording = false

# A breakpoint for the oracle (tools/run.zap --at): the thread stops before the breakHit-th time
# the interpreter reaches breakAt (-1: none).
pub mut breakAt = -1
pub mut breakHit = 1
mut breakSeen = 0
pub mut entered {i64: bool} = {}

# The blocks entered so far written to a file, an address a line (main.zap's --profile reads it),
# with those it already holds: the dispatcher sees only the entries the translated code did not
# make itself, so the runs of a partition's build add to the profile of the one before. The line
# that says so.
pub fn writeProfile(path str) str:
	for line in (fs.readFile(path) ?? "").lines():
		if i64.parse("0x{line}") is address: entered[address] = true
	blocks = entered.keys().sorted().map("{it:x}").join("\n")
	fs.writeFile(path, "{blocks}\n") ?? fail("cannot write {path}: {error}")
	"{entered.len} blocks into {path}"

# instructions run by the interpreter until one leaves the straight line (a branch taken, a
# call, a halt); how many
fn interpretBlock(mut c core.Cpu, mut code Decoded):
	n = 0
	while true:
		pc = c.pc
		if pc == breakAt and not c.isHalted:
			breakSeen += 1
			if breakSeen == breakHit:
				c.stop(pc, "breakpoint")
				break
		code.runAt(c, pc)
		n += 1
		if core.memory.faultAt >= 0:
			c.stop(pc, "memory fault at {pc:x}: {core.memory.takeFault()}")
		if c.isHalted or c.pc != pc + 4 or n >= 64: break
	n

# Runs the thread for about `budget` instructions, or until it halts (c.halted says why); how
# many ran, counting a translated function's entry as one.
pub fn runThread(mut c core.Cpu, mut code Decoded, budget i64) i64:
	c.budget = budget
	ran = 0
	while not c.isHalted and c.budget > 0:
		pc = c.pc
		c.trail[c.trailAt % len] = pc
		c.trailAt += 1
		if recording: entered[pc] = true
		if core.functionAt(pc) is f:
			before = c.budget
			if lockstep: c.lockstepRun(f, code) else: core.functions[f].run(mut ref c)
			if c.pc != pc or c.isHalted or c.budget != before:
				ran += before - c.budget + 1
				c.budget -= 1
				continue
		k = c.interpretBlock(code)
		ran += k
		c.budget -= k
	ran
