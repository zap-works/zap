---
size: L
---
# Doors in Skyrim behave as the game's do (milestone 8)

Door code is `projects/skyrim/game/doors.zap` and `game/movable.zap`; its tests are
`doorTests.zap` and `activateTests.zap`.

- [ ] doors: read in the executable the distance at which the follower sends
  `MovementMessageActivateDoor` and the lock rule (the cast's doors carry no lock), and port them;
  the follower opens a door at the game's distance in a test
- [ ] movable doors, four parts: the door's shadow (the shadow maps are of the baked buffer, so a
  moving door casts none); quaternion rotation keys (read, mixed linearly and normalized, as the
  game does or not); the door's Havok body moving (its collision leaves the physics world when it
  opens); and sounds on the sequences' text keys. Each is seen in a door test or a headless shot of
  a door opening
