# Prepares a cell of Skyrim Special Edition from the player's own install: nothing of the game is
# in the repository, each player prepares it from the copy they have. Reads the cell, its
# references, their models and textures out of Skyrim.esm and the BSA archives once and writes
# them ready to draw into projects/skyrim/assets/prepared/<cell>/ (game/prepare.zap): the game
# then reads only those files and opens at once (it runs this itself, once, when they are missing
# or of an older format). Run from the repository root:
#
#   zap run projects/skyrim/prepare.zap [--install <Data dir>] [--cell <editor id>] [--textures astc]
#
# The install defaults to the copy fetch.zap made (projects/skyrim/assets/game/Data), the cell to the Sleeping
# Giant Inn (RiverwoodSleepingGiantInn). `--textures astc` lays the game's BC textures as ASTC, for
# Android's GPUs, which read no BC.

import game
import skyrim

dir = args.option("--install") ?? skyrim.defaultInstall
if args.option("--textures") == "astc": game.prepareTexturesAs(.Astc)
game.prepareCell(dir, args.option("--cell") ?? game.defaultCell)
