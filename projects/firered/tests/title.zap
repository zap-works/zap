# The game from the player's dump to its title screen: prepared, built, and run without a window
# to frame 2400, where the title (Charizard, the flames, PRESS START) is on the screen; the
# frame's hash is the picture. Without the dump the file is skipped, with a line.
#   needs: projects/firered/rom/firered.gba (the player's dump, never committed)
#   limit: 900 s (the game's build, 100 s and 3.1 GB committed at most, then 2400 frames, on a loaded machine)

titleHash = "54214c87c972bf44e515467370da937e85e24795"

test "the recompiled game reaches its title screen":
	expect Process.output("{zapPath()} run projects/firered/prepare.zap").code == 0
	expect Process.output("{zapPath()} build projects/firered/recomp/firered.zap").code == 0
	said = Process.output("{builtExe("firered")} --headless --frames 2400 --hash").out
	expect said.trimmed() == "frame 2400: {titleHash}"
