# Donkey Kong Country (USA, v1.0) as recomp.snes prepares it: the player's dump checked, the
# community's tables (tables/), the program's name and the widescreen's patches (patches.zap).

import recomp.snes.snes

pub romPath = "projects/dkc/rom/dkc1.sfc"
pub recompDir = "projects/dkc/recomp"
pub dump = snes.Dump(
	title = "Donkey Kong Country (USA, v1.0)",
	bytes = 0x40_0000,
	sha256 = "fa8cacf5bbfc39ee6bbaa557adf89133d60d42f6cf9e1db30d5a36a469f74d15"
)

pub fn game(rom str = romPath) snes.Game:
	snes.Game(
		name = "dkc",
		romPath = rom.copy(),
		recompDir = recompDir,
		tablesDir = "projects/dkc/tables",
		imports = ["wide"],
		setup = ["wide.install()"],
		patches = widePatches()
	)

# Prepares from the dump at `rom`; stops the program with the reason when it is not the game's.
pub fn prepare(rom str = romPath):
	game(rom).prepareDump(dump)
