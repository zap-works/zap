# Prints every living lemming of this build at an iteration, to find the same records in the DOS
# game's memory dump (compare.zap --mem):
#   zap run projects/lemmings/lemmingsAt.zap --rating R --level L --iteration N [--route "..."]

import dos.lemmings
import game

dir = args.option("--install") ?? lemmings.defaultInstall
at = i64.parse(args.option("--iteration") ?? "100") ?? 100
g = game.chosenGame(dir)
r = game.parseRoute(args.option("--route") ?? "")
print(
	"screenStart {g.level.screenStart} skills {g.level.skills} rate {g.level.releaseRate} entrances"
)
while g.iteration < at:
	g.step()
	g.runRoute(r)
for i, l in g.lemmings:
	if not l.removed:
		print("{i}: x {l.x} y {l.y} dx {l.dx} {l.action} frame {l.frame}")
