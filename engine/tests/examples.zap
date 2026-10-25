# The engine's examples that check themselves (they end with 1 when what they drew is wrong), each
# run on both backends, headless, on Vulkan also as a device of 1.2 without extensions draws
# (vulkan=1.2), and as an app on Android's emulator (whose GPU is the host's, `-gpu host`, or
# SwiftShader's of Vulkan 1.2, `-gpu swiftshader_indirect`; skipped when none answers); and a
# scripted run, which shows no window. They need the repository's root as the working dir: from
# elsewhere the test says so and passes.

import fs

# the exit code of an example on a backend, headless
fn exitCodeOn(example str, gpu str):
	run = "zap run projects/examples/{example}/main.zap"
	Process.output(run, vars = [runAssignment("gpu={gpu}")]).code

checking = [
	"indirect",
	"compressed",
	"compute",
	"post",
	"targets",
	"staged",
	"texels",
	"volumes",
	"images"
]

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
	("staged", "d3d12"),
	("texels", "vulkan"),
	("texels", "d3d12"),
	("volumes", "vulkan"),
	("volumes", "d3d12"),
	("images", "vulkan"),
	("images", "d3d12")
]:
	if not fs.exists("projects/examples/post/main.zap"):
		print("skipped: run from the repository's root")
	else:
		expect exitCodeOn(example, gpu) == 0

test "an example draws what it must as a device of Vulkan 1.2 without extensions" for example in checking:
	if not fs.exists("projects/examples/post/main.zap"):
		print("skipped: run from the repository's root")
	else:
		expect exitCodeOn(example, "vulkan,vulkan=1.2") == 0

test "an example draws what it must on Android's emulator" for example in checking:
	if not fs.exists("projects/examples/post/main.zap"):
		print("skipped: run from the repository's root")
	else:
		run = Process.output(
			"zap run --target android-x64 projects/examples/{example}/main.zap",
			vars = [runAssignment("headless")]
		)
		if run.code == 2 and "no Android emulator" in run.out:
			print("skipped: no Android emulator")
		else:
			expect run.code == 0

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

# frames opened and never drawn into nor shown: each next one begins on either backend
emptyFrames = """
	import engine

	mut frames = engine.newFrames()
	mut win = engine.openWindow("Empty", 64, 64)
	loop 3:
		if not win.nextFrame(frames): exit(1)
	"""

test "frames that record nothing follow one another" for gpu in ["vulkan", "d3d12"]:
	program = "{testDir()}emptyframes.zap"
	_ = fs.writeFile(program, emptyFrames)
	run = Process.output("zap run {program}", vars = [runAssignment("gpu={gpu}")])
	expect run.code == 0
