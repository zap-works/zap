# The four timers: each counts up from its reload at 1, 1/64, 1/256 or 1/1024 of the clock, or
# once each overflow of the timer before it (cascade); an overflow reloads it, may ask for an
# interrupt and feeds the sound's FIFOs (timers 0 and 1). The counters are worked out when read.

prescalers = [1, 64, 256, 1024]

mut reloads u32[4] = [0, 0, 0, 0]
mut controls u32[4] = [0, 0, 0, 0]
mut counters i64[4] = [0, 0, 0, 0]   # the count at the cycle of `stamps`
mut stamps i64[4] = [0, 0, 0, 0]

fn isRunning(i i64):
	controls[i] & 0x80 != 0

fn isCascade(i i64):
	i > 0 and controls[i] & 4 != 0

fn prescaler(i i64):
	prescalers[controls[i] & 3]

# the counters brought up to cycle t, the overflows on the way acted on
pub fn runTimersTo(t i64):
	for i in 0..4:
		if not isRunning(i) or isCascade(i): continue
		p = prescaler(i)
		while stamps[i] + (0x1_0000 - counters[i]) * p <= t:
			stamps[i] += (0x1_0000 - counters[i]) * p
			counters[i] = reloads[i]
			overflow(i, stamps[i])
		ticks = (t - stamps[i]) / p
		if ticks <= 0: continue
		stamps[i] += ticks * p
		counters[i] += ticks

# timer i overflowed at cycle `at`
fn overflow(i i64, at i64):
	if controls[i] & 0x40 != 0: raise(irqTimer0 << u32(i))
	if i < 2: soundTimerOverflow(i, at)
	if i < 3 and isRunning(i + 1) and isCascade(i + 1):
		counters[i + 1] += 1
		if counters[i + 1] >= 0x1_0000:
			counters[i + 1] = reloads[i + 1]
			overflow(i + 1, at)

# the cycle of the next overflow of a timer counting the clock
pub fn nextTimerOverflow() i64:
	next = 9_223_372_036_854_775_807
	for i in 0..4:
		if not isRunning(i) or isCascade(i) or controls[i] & 0x40 == 0: continue
		next = next.min(stamps[i] + (0x1_0000 - counters[i]) * prescaler(i))
	next

pub fn timerCounter(i i64) u32:
	runTimersTo(cycles)
	u32(counters[i])

pub fn timerReload(i i64, v u16):
	reloads[i] = v

pub fn timerControl(i i64, v u16):
	runTimersTo(cycles)
	starts = not isRunning(i) and v & 0x80 != 0
	controls[i] = v
	if starts:
		counters[i] = reloads[i]
		stamps[i] = cycles
	scheduleEvents()
