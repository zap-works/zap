# The first 8,000 frames of the TAS walkthrough (3956M, tools/bk2Route.zap, retimed by Mesen), several levels in, played
# as Mesen 2 plays them; its other 136,000 frames were compared by hand and are too long to keep a test.
#   needs: projects/dkc/rom/dkc1.sfc (the player's dump, never committed)

import playing

test "the walkthrough's first 8,000 frames play as Mesen 2 does":
	playing.preparedAndBuilt()
	playing.playsAsMesen("tas8000", 8_000)
