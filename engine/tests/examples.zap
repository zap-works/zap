# The engine's examples that check themselves (they end with 1 when what they drew is wrong), each
# run on both backends, headless; and a scripted run, which shows no window. They need the
# repository's root as the working dir: from elsewhere the test says so and passes.

import fs

# the exit code of an example on a backend, headless
fn exitCodeOn(example str, gpu str):
	run = "zap run projects/examples/{example}/main.zap"
	Process.output(run, vars = [runAssignment("gpu={gpu}")]).code

test "an example draws what it must" for (example, gpu) in [
	("indirect", "vulkan"),
	("indirect", "d3d12"),
	("compressed", "vulkan"),
	("compressed", "d3d12"),
	("compute", "vulkan"),
	("compute", "d3d12"),
	("post", "vulkan"),
	("post", "d3d12"),
	("targets", "vulkan"),
	("targets", "d3d12"),
	("staged", "vulkan"),
	("staged", "d3d12")
]:
	if not fs.exists("projects/examples/post/main.zap"):
		print("skipped: run from the repository's root")
	else:
		expect exitCodeOn(example, gpu) == 0

extern "user32.dll" fn FindWindowA(className str, title str) i64
extern "user32.dll" fn IsWindowVisible(window i64) bool

# whether an engine window titled `title` is on the screen now
fn engineWindowShown(title str):
	handle = FindWindowA("ZapEngineWindow\0", "{title}\0")
	handle != 0 and IsWindowVisible(handle)

test "a scripted run shows no window":
	if not fs.exists("projects/examples/compute/main.zap"):
		print("skipped: run from the repository's root")
	else:
		run = Process.start(
			"zap run projects/examples/compute/main.zap --frames 2 --shot build/headless.png"
		)
		shown = false
		while not run.isDone:
			shown = shown or engineWindowShown("Compute")
			sleepMs(2)
		expect run.wait() == 0
		expect not shown
