# The wide picture must disturb nothing: jungle.txt played with `--wide --wide-native-logic` (drawn
# wide, the cartridge's windows not widened) matches Mesen 2 in every frame's work RAM and native
# picture, as the same route played native does (routes.zap).
#   needs: projects/dkc/rom/dkc1.sfc (the player's dump, never committed)

import playing

test "jungle.txt played wide with the cartridge's windows native plays as Mesen 2 does":
	playing.preparedAndBuilt()
	playing.playsAsMesenWith("jungle", 3300, "--wide --wide-native-logic")
