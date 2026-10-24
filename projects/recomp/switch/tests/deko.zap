# A deko3d homebrew (a triangle) run interpreted on the HLE kernel: its libnx start, the display and
# GPU services it opens, and its frame loop presenting frame after frame through the binder, each
# frame's draw made by its macros.
#   needs: projects/recomp/switch/rom/homebrew/deko_basic.nro
#   needs: projects/recomp/switch/rom/homebrew/deko_examples.nro

import recomp.switch.horizon

# whether a line of the log has this text
fn mentions(log str[], text str):
	for line in log:
		if (line.indexOf(text) ?? -1) >= 0: return true
	false

test "deko_basic presents its tenth frame without an error from the services":
	k = horizon.launchNro("projects/recomp/switch/rom/homebrew/deko_basic.nro", 0x1000_0000) ?? fail
	k.runProcess(30_000_000)
	expect k.display.presented >= 10
	expect k.gpu.stats.semaphores > 0
	expect k.gpu.stats.draws >= k.display.presented   # the triangle, through deko3d's Draw macro
	expect k.gpu.notes.isEmpty
	expect not mentions(k.log, "not written")
	expect not mentions(k.log, "cannot open")
	shown = k.display.queue[len - 1]
	expect shown.width == 1280 and shown.height == 720 and shown.address > 0

test "deko_examples shows its menu: the console's text read from the presented RGB565 block-linear buffer":
	k = horizon.launchNro("projects/recomp/switch/rom/homebrew/deko_examples.nro", 0x1000_0000) ??
		fail
	k.runProcess(150_000_000)
	picture = k.screenPicture() ?? fail("nothing presented")
	bytes = picture.cells.bytes()
	lit = (0..bytes.len / 4).filter(bytes[4 * it] > 128).len
	expect picture.width == 1280 and picture.height == 720
	expect lit > 10_000 and lit < 100_000   # the menu's white text on black
