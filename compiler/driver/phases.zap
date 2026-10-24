# `ZAP_RUN=phases`: where a build's time goes on the main thread, which the build waits on: each
# phase's processor cycles there (the thread's own, which other processes move little) and its
# wall milliseconds, printed as it ends; the code phase also says what of it the lowering and the
# ownership check took. The memory: the process's committed bytes at the phase's end and its
# peak working set so far.

fn phasesWord():
	TraceWord("phases", "a build's phases on the main thread: each one's millions of cycles there, its wall milliseconds, and the memory held at its end and at most so far")

mut phaseCycles = 0
mut phaseClock = 0.0
mut loweringCycles = 0   # of the code phase: the functions lowered
mut owningCycles = 0   # and their ownership checked

# the phase that ended now, named; the first call starts the count
fn phaseEnded(name str):
	if not phasesWord().on(): return
	cycles = threadCycles()
	now = clockSeconds()
	if phaseClock > 0.0:
		ms = i64((now - phaseClock) * 1000.0)
		eprint("phase {name}: {(cycles - phaseCycles) / 1_000_000} M cycles, {ms} ms, {memoryCommitted() / 1048576} MB held, peak {peakMemory() / 1048576} MB")
	phaseCycles = cycles
	phaseClock = now

fn phaseLoweringSaid():
	if not phasesWord().on(): return
	eprint("phase code's lowering: {loweringCycles / 1_000_000} M cycles, ownership {owningCycles / 1_000_000} M")
