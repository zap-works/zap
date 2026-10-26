# Prints the player's worn models (slot, model, parts, triangles, bones, bone names the skeleton
# lacks, each part's textures and material) and the body posed on the CPU: in the skeleton's
# reference pose, or at a frame of a male animation; written as OBJ, or drawn from the front and
# the side as a PNG.
#
#   zap run projects/skyrim/actorInfo.zap [--install dir] [--anim mt_idle [--frame 0]]
#       [--obj out.obj] [--png out.png [--head]]

import skyrim
import skyrim.esm
import skyrim.actor
import game

install = skyrim.openInstall(args.option("--install") ?? skyrim.defaultInstall) ?? fail
plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
skeleton = install.readCharacterSkeleton() ?? fail
body = install.playerParts(plugin) ?? fail
request = actor.figureRequest(args) ?? fail
install.showFigure(body, skeleton, request, none, none) ?? fail
