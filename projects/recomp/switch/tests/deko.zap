# A deko3d homebrew (a triangle) run interpreted on the HLE kernel: its libnx start, the display and
# GPU services it opens, and its frame loop presenting frame after frame through the binder.
#   needs: projects/recomp/switch/rom/homebrew/deko_basic.nro

import recomp.switch.horizon

# whether a line of the log has this text
fn mentions(log str[], text str):
	for line in log:
		if (line.indexOf(text) ?? -1) >= 0: return true
	false

test "deko_basic presents its tenth frame without an error from the services":
	k = horizon.launchNro("projects/recomp/switch/rom/homebrew/deko_basic.nro", 0x1000_0000) ?? fail
	_ = k.runProcess(30_000_000)
	expect k.display.presented >= 10
	expect k.gpu.stats.semaphores > 0
	expect k.gpu.notes.isEmpty
	expect not mentions(k.log, "not written")
	expect not mentions(k.log, "cannot open")
	shown = k.display.queue[len - 1]
	expect shown.width == 1280 and shown.height == 720 and shown.address > 0
