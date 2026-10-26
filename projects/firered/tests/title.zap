# The game from the player's dump to its title screen: prepared, built, and run without a window
# to frame 2400, where the title (Charizard, the flames, PRESS START) is on the screen; the
# frame's hash is the picture. Without the dump the file is skipped, with a line.
#   needs: projects/firered/rom/firered.gba (the player's dump, never committed)

titleHash = "54214c87c972bf44e515467370da937e85e24795"

# a zap command run as from the checkout, its builds in its build/ (not the test's own dir), so an
# unchanged game is the executable kept there (spec 13.1)
fn inCheckout(words str):
	Process.output("{zapPath()} {words}", vars = ["{buildsVariable().name}=build"]).code

test "the recompiled game reaches its title screen":
	expect inCheckout("run projects/firered/prepare.zap") == 0
	expect inCheckout("build projects/firered/recomp/firered.zap") == 0
	said = Process.output("build/firered{exeSuffix()} --headless --frames 2400 --hash").out
	expect said.trimmed() == "frame 2400: {titleHash}"
