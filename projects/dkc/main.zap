# Donkey Kong Country recompiled into native Zap: the cartridge's 65816 code translated ahead of
# time (recomp.snes, projects/dkc/prepare.zap), built into one executable with the SNES written in Zap
# (projects/recomp/snes/console). Needs the player's own dump at projects/dkc/rom/dkc1.sfc only to
# prepare, which this does first when projects/dkc/recomp/ is missing; it then builds
# build/dkc.exe when it is missing and runs it. Run from the repository root:
#
#   zap run projects/dkc/main.zap                      Enter is Start, the arrows move, Z is B
#   zap run projects/dkc/main.zap --frames 700 --shot intro.png   (the frame saved)
#   zap run projects/dkc/main.zap --headless --frames 900 --route projects/dkc/assets/route-title.txt --hashes projects/dkc/assets/zap.txt
#   zap run projects/dkc/main.zap --android <dir> [--target android-x64]   (dkc.apk and dkc-wide.apk)
#   needs: projects/dkc/rom/dkc1.sfc (the player's dump, never committed)

import cartridge
import recomp.snes.snes

cartridge.game().playMain(cartridge.dump, "DKC Recomp")
