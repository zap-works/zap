---
size: L
---
# The NPCs, their packages and animation (milestone 7)

- [ ] The sync points of the behavior graph (`iSyncIdleLocomotion`, `iSyncTurnState`,
  `iSyncForwardState`, `iSyncStrafeState`, `iSyncSprintState`) are still set by hand; the writers of
  the sync integers in the executable are unread.
- [ ] The stagger's mass terms: fStaggerMassOffsetBase and the player's mass multiplier.
- [ ] The AI's own movement over a 900-second time-skip step: the port takes it as reaching the place.
