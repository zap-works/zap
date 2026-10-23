# Super Mario World as this project builds it (its tables and its widescreen's patches) plays as
# Mesen 2 does: the route of random buttons recomp.snes keeps and the route into Yoshi's Island 1
# (tests/routes/yi1.txt: a new game, the house, the map, the level run through) played from
# power-on, every frame's picture and work RAM the same as Mesen's; drawn wide with the cartridge's
# windows kept native (--wide-native-logic), the same again.
#   needs: projects/recomp/snes/rom/smw.sfc (the player's dump, never committed)

import recomp.snes.mesen

fn playsAsMesen(route str, mesenHashes str, frames i64, options str):
	expect Process.output("{zapPath()} run projects/smw/prepare.zap").code == 0
	expect Process.output("{zapPath()} build projects/smw/recomp/smw.zap").code == 0
	verdict = mesen.playedAgainst(
		builtExe("smw"),
		route,
		mesenHashes,
		"build/smw-route.txt",
		frames,
		options
	)
	expect verdict == mesen.allEqual(frames)

test "the random route plays as Mesen 2 does":
	routes = "projects/recomp/snes/tests/routes"
	playsAsMesen("{routes}/smw.txt", "{routes}/smw-mesen.txt", 3000, "")

test "the route into Yoshi's Island 1 plays as Mesen 2 does, drawn natively and wide":
	routes = "projects/smw/tests/routes"
	playsAsMesen("{routes}/yi1.txt", "{routes}/yi1-mesen.txt", 5000, "")
	playsAsMesen(
		"{routes}/yi1.txt",
		"{routes}/yi1-mesen.txt",
		5000,
		"--wide --wide-width 486 --wide-native-logic"
	)
