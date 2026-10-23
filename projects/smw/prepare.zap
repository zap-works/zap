# Prepares Super Mario World from the player's own dump (projects/recomp/snes/rom/smw.sfc, USA;
# nothing of the game is in the repository): checks it and writes its code recompiled by
# recomp.snes into projects/smw/recomp/ (a Zap program, projects/smw/recomp/smw.zap, built with
# `zap build projects/smw/recomp/smw.zap`). Run from the repository root:
#
#   zap run projects/smw/prepare.zap [--rom <file>]

import cartridge

cartridge.prepare(args.option("--rom") ?? cartridge.romPath)
