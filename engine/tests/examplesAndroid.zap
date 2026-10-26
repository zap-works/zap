# The engine's examples that check themselves (examples.zap) run as an app on Android's emulator
# (whose GPU is the host's, `-gpu host`, or SwiftShader's of Vulkan 1.2, `-gpu
# swiftshader_indirect`; skipped when none answers). They need the repository's root as the
# working dir: from elsewhere the test says so and passes.

import fs

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
