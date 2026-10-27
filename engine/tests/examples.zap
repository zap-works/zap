# The engine's examples that check themselves (they end with 1 when what they drew is wrong), each
# built once and run on both backends, headless, and on Vulkan also as devices of 1.2 and 1.1
# without extensions draw (vulkan=1.2, vulkan=1.1); their run as an app on Android's emulator is
# examplesAndroid.zap; and a scripted run, which shows no window. They need the repository's root as
# the working dir: from elsewhere the test says so and passes.

import fs

# an example built once (`zap run` would build it again for each backend: the words of ZAP_RUN
# are in its stamp), then run headless on each of the backends `gpus` names; the runs that ended
# other than with 0, as "backend: code"
fn failedRuns(example str, gpus str[]):
	built = Process.output("zap build projects/examples/{example}/main.zap")
	if built.code != 0: return ["build: {built.out.trimmed()}"]
	failed = []
	for gpu in gpus:
		code = Process.output(builtExe("main"), vars = [runAssignment("gpu={gpu}")]).code
		if code != 0: failed.push("{gpu}: {code}")
	failed

checking = [
	"indirect",
	"compressed",
	"compute",
	"post",
	"targets",
	"staged",
	"texels",
	"volumes",
	"images",
	"arrays"
]

test "an example draws what it must on both backends and as devices of Vulkan 1.2 and 1.1" for example in checking:
	if not fs.exists("projects/examples/post/main.zap"):
		print("skipped: run from the repository's root")
	else:
		expect failedRuns(example, ["vulkan", "d3d12", "vulkan,vulkan=1.2", "vulkan,vulkan=1.1"]).isEmpty

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
