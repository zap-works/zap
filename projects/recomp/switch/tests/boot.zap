# BotW's boot on the interpreter, its heap of 3.26 GB mapped within zap test's memory cap (4096 MB
# committed): the guest's pages are committed only as the game touches them.
#   needs: projects/recomp/switch/rom/01007ef00011e000/exefs/main (the player's dump, never committed)

import recomp.switch.horizon

test "BotW's boot maps its heap of 3.26 GB and commits a fraction of it":
	k = horizon.launch("projects/recomp/switch/rom/01007ef00011e000/exefs") ?? fail
	why = k.runProcess(135_000_000)
	print("{k.space.heapSize:x} {why.startsWith("ran ")} {peakCommitted() < 1 << 30}")
	prints "c2600000 true true"
