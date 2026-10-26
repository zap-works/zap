# `ZAP_RUN=phases`: where a build's time goes on the main thread, which the build waits on: each
# phase's processor cycles there (the thread's own, which other processes move little) and its
# wall milliseconds, printed as it ends; the code phase also says what of it the lowering and the
# ownership check took, and how long its rounds' ends waited for their passes. The memory: the process's committed bytes at the phase's end and the
# most it committed so far.

fn phasesWord():
	TraceWord("phases", "a build's phases on the main thread: each one's millions of cycles there, its wall milliseconds, and the memory held at its end and at most so far")

mut phaseCycles = 0
mut phaseClock = 0.0
mut loweringCycles = 0   # of the code phase: the functions lowered
mut owningCycles = 0   # and their ownership checked
mut roundsMade = 0   # and its rounds, and how long their ends waited for the passes
mut roundsWaited = 0.0

# the phase that ended now, named; the first call starts the count
fn phaseEnded(name str):
	if not phasesWord().on(): return
	cycles = threadCycles()
	now = clockSeconds()
	if phaseClock > 0.0:
		ms = i64((now - phaseClock) * 1000.0)
		eprint("phase {name}: {(cycles - phaseCycles) / 1_000_000} M cycles, {ms} ms, {memoryCommitted() / 1048576} MB held, peak {peakCommitted() / 1048576} MB")
	phaseCycles = cycles
	phaseClock = now

fn phaseLoweringSaid():
	if not phasesWord().on(): return
	eprint("phase code's lowering: {loweringCycles / 1_000_000} M cycles, ownership {owningCycles / 1_000_000} M")
	eprint("phase code's rounds: {roundsMade}, their ends waited {i64(roundsWaited * 1000.0)} ms")

# a round's end waited that long for its passes; alone is its one function's key ("" for more), a
# function the build waits on alone over 50 ms named
fn phaseRoundWaited(seconds f64, alone str):
	if not phasesWord().on(): return
	roundsMade += 1
	roundsWaited += seconds
	if alone != "" and seconds > 0.05:
		eprint(
			"phase code's round {roundsMade} waited {i64(seconds * 1000.0)} ms for {alone} alone"
		)
