# Save states (console/saveState.zap): a run saving at frames' ends plays as Mesen 2 does, and each
# state loaded in a run of its own plays on as the saving run did, frame for frame (picture and
# work RAM). DKC and SMW at their title and in a level, translated and interpreted whole.
#   needs: projects/recomp/snes/rom/dkcg.sfc, projects/recomp/snes/rom/smw.sfc (the player's dumps, never committed; tools/gather.zap)

import recomp.snes.mesen

after = 120   # the frames compared after each load

type Game:
	name str
	route str
	mesenHashes str
	savedAt i64[]

dkc = Game(
	name = "dkcg",
	route = "projects/dkc/tests/routes/jungle.txt",
	mesenHashes = "projects/dkc/tests/routes/jungle-mesen.txt",
	savedAt = [600, 2500]
)
smw = Game(
	name = "smw",
	route = "projects/recomp/snes/tests/routes/smw.txt",
	mesenHashes = "projects/recomp/snes/tests/routes/smw-mesen.txt",
	savedAt = [300, 2000]
)

# compare.zap's verdict on two runs' hash files
fn verdict(expected str, got str):
	said = Process.output("{zapPath()} run projects/recomp/snes/compare.zap {expected} {got}")
	(said.out.lines().first ?? "compare.zap said nothing").copy()

fn ranWell(command str):
	expect Process.output(command).code == 0

# The game built, played along its route saving at each frame of savedAt, then each state loaded
# and played for `after` frames.
fn savesAndLoads(game Game, options str):
	prepared = Process.output(
		"{zapPath()} run projects/recomp/snes/main.zap projects/recomp/snes/rom/{game.name}.sfc --out projects/recomp/snes/out/tests/{game.name} --build"
	)
	expect prepared.code == 0
	exe = builtExe(game.name)
	run = "{exe} --headless {options} --route {game.route}"
	stem = "build/states-{game.name}"
	frames = (game.savedAt.last ?? 0) + after   # savedAt in order
	saves = game.savedAt.map("--save-at {it} {stem}-{it}.state").join(" ")
	ranWell("{run} --frames {frames} {saves} --hashes {stem}.txt")
	expect verdict(game.mesenHashes, "{stem}.txt") == mesen.allEqual(frames)
	for at in game.savedAt:
		ranWell("{run} --load {stem}-{at}.state --frames {after} --hashes {stem}-{at}.txt")
		expect verdict("{stem}.txt", "{stem}-{at}.txt") == mesen.allEqual(after)

test "DKC saved and loaded plays on as it did":
	dkc.savesAndLoads("")

test "Super Mario World saved and loaded plays on as it did":
	smw.savesAndLoads("")

test "DKC interpreted whole, saved and loaded, plays on as it did":
	dkc.savesAndLoads("--interpret")

test "Super Mario World interpreted whole, saved and loaded, plays on as it did":
	smw.savesAndLoads("--interpret")
