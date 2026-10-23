# Super Mario World recompiled into native Zap: the cartridge's 65816 code translated ahead of
# time (recomp.snes, projects/smw/prepare.zap), built into one executable with the SNES written in
# Zap (projects/recomp/snes/console). Needs the player's own dump at
# projects/recomp/snes/rom/smw.sfc only to prepare, which this does first when
# projects/smw/recomp/ is missing; it then builds build/smw.exe when it is missing and runs it.
# Run from the repository root:
#
#   zap run projects/smw/main.zap                      Enter is Start, the arrows move, Z is B
#   zap run projects/smw/main.zap --headless --wide --wide-width 486 --frames 3000 --shot wide.png
#   zap run projects/smw/main.zap --android <dir> [--target android-x64]   (smw.apk and smw-wide.apk)
#   needs: projects/recomp/snes/rom/smw.sfc (the player's dump, never committed)

import cartridge
import recomp.snes.snes

cartridge.game().playMain(cartridge.dump, "SMW Recomp")
