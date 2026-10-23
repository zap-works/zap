# The GPU's time per pass, opt-in: ZAP_RUN=gputime prints every 120 frames (`gputime=N`: every
# N) the mean milliseconds each pass of a frame took on the GPU, its targets named, and the
# frame's span from its first pass's start to its last one's end. Each backend writes a timestamp
# before a pass and after it (Vulkan's timestamp queries at the bottom of the pipe: a pass's start
# once the work before it is done; Direct3D 12's timestamp queries) into the frame's queries, and
# reads them once the frame's fence says the GPU is done with it.

pub mostTimedPasses = 64   # a frame's passes timed (two queries each)

# the passes' GPU times, summed between prints
pub type GpuTimer:
	every i64   # frames between prints, 0: off
	frames i64   # frames summed since the last print
	labels str[]   # the passes of the frames summed, by their order in a frame
	ms f64[]   # their milliseconds, summed
	span f64   # the frames' spans, summed

fn gpuTimeWord():
	TraceWord("gputime", "prints each pass's GPU milliseconds every 120 frames, gputime=N every N")

# the timer `gputime` asks for (off when the word is not in ZAP_RUN)
pub fn newGpuTimer() GpuTimer:
	word = gpuTimeWord()
	GpuTimer(
		every = (i64.parse(word.value() ?? "") ?? 120).max(1) if word.on() else 0,
		frames = 0,
		labels = [],
		ms = [],
		span = 0.0
	)

pub fn gpuTimerOff() GpuTimer:
	GpuTimer(every = 0, frames = 0, labels = [], ms = [], span = 0.0)

# a pass's name: its targets (the screen, a color texture's id, a depth texture's) and size
pub fn passLabel(color i64, depth i64, width i64, height i64) str:
	target = "screen" if color == screenTarget else "color {color}" if color >= 0 else ""
	withDepth = ("depth {depth}" if target == "" else " + depth {depth}") if depth >= 0 else ""
	"{target}{withDepth} {width}x{height}"

# A frame's timestamps (ticks: each pass's start and end, in the order of `labels`), `nsPerTick`
# nanoseconds each: summed with the frames before, the means printed when they are due.
pub fn addGpuFrame(mut t GpuTimer, labels str[], ticks i64[], nsPerTick f64):
	n = labels.len.min(ticks.len / 2)
	if n == 0: return
	for i in 0..n:
		ms = (ticks[i * 2 + 1] - ticks[i * 2]) * nsPerTick / 1000000.0
		if i < t.labels.len:
			if t.labels[i] != labels[i]:
				t.labels[i] = labels[i].copy()
			t.ms[i] += ms
		else:
			t.labels.push(labels[i].copy())
			t.ms.push(ms)
	t.span += (ticks[n * 2 - 1] - ticks[0]) * nsPerTick / 1000000.0
	t.frames += 1
	if t.frames < t.every: return
	f = f64(t.frames)
	total = 0.0
	text = "gpu time over {t.frames} frames (ms a frame):"
	for i, label in t.labels:
		total += t.ms[i]
		text += "\n  pass {i} {label}: {(t.ms[i] / f):.3}"
	text += "\n  passes {(total / f):.3}, frame span {(t.span / f):.3}"
	eprint(text)
	t.frames = 0
	t.labels.clear()
	t.ms.clear()
	t.span = 0.0
