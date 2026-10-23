# The interpreter: a thread's instructions fetched from guest memory, decoded once per address
# (kept while the code is not written over) and executed until the thread halts at a supervisor
# call, a breakpoint or a word the decoder does not know, or the steps run out.

import recomp.switch.arm64

pub type Decoded:
	cache {i64: arm64.Instr} = {}

	# the instruction at pc run on the thread, decoded the first time (lent, never copied)
	mut fn runAt(mut c Cpu, pc i64):
		if not (pc in cache): cache[pc] = arm64.decode(i64(memory.load(pc, 2)), pc)
		c.execute(cache[pc], pc)

	# what was decoded in [at, at + size) forgotten, after the code there was written
	mut fn forget(at i64, size i64):
		for k in (0..size / 4).map(at + it * 4):
			_ = cache.remove(k)

# Runs the thread from its pc for at most `steps` instructions; how many ran. The thread stops
# early when it halts (c.halted says why).
pub fn run(mut c Cpu, mut code Decoded, steps i64) i64:
	n = 0
	while n < steps:
		pc = c.pc
		code.runAt(c, pc)
		n += 1
		if c.isHalted: break
	n
