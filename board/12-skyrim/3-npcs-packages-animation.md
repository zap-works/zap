---
size: L
---
# NPCs follow the game's packages and animation rules (milestone 7)

Three rules of the NPCs are approximated. The tests are `actorTests.zap`, `graphTests.zap` and
`townfolkTests.zap` in `projects/skyrim`.

- [ ] the sync points of the behavior graph (`iSyncIdleLocomotion`, `iSyncTurnState`,
  `iSyncForwardState`, `iSyncStrafeState`, `iSyncSprintState`) are set by hand: read the writers of
  the sync integers in the executable and set them as it does (`game/graph.zap`); the graph test
  passes without the hand-set values
- [ ] the stagger's mass terms (`fStaggerMassOffsetBase` and the player's mass multiplier) are not
  read: read them in the executable and use them in the fight code (`game/combat`); `fightTests.zap`
  covers a stagger
- [ ] the AI's own movement over a 900-second time-skip step: the port takes it as reaching the
  place; read how the game walks an actor during a skip and port it; `townfolkTests.zap` shows the
  actor where the game puts it
