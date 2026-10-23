# Super Mario World (USA) as recomp.snes prepares it: the player's dump checked, the flow seeded
# by the jumps through memory Mesen 2 saw it take (tables/played.cfg; the interpreter runs what the
# flow still cannot see), the program's name and the widescreen's patches (patches.zap).

import recomp.snes.snes

pub romPath = "projects/recomp/snes/rom/smw.sfc"
pub recompDir = "projects/smw/recomp"
pub dump = snes.Dump(
	title = "Super Mario World (USA)",
	bytes = 0x8_0000,
	sha256 = "0838e531fe22c077528febe14cb3ff7c492f1f5fa8de354192bdff7137c27f5b"
)

pub fn game(rom str = romPath) snes.Game:
	snes.Game(
		name = "smw",
		romPath = rom.copy(),
		recompDir = recompDir,
		tablesDir = "projects/smw/tables",
		imports = ["wide"],
		setup = ["wide.install()"],
		patches = widePatches()
	)

# Prepares from the dump at `rom`; stops the program with the reason when it is not the game's.
pub fn prepare(rom str = romPath):
	game(rom).prepareDump(dump)
