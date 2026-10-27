---
size: M
---
# Skyrim's sound follows the game's rules (milestone 5)

Two sound rules are approximated and one visual part of speech is missing. Sound code is in
`projects/skyrim/game/sound`; its tests are `soundTests.zap`.

- [ ] the attenuation curve's points are read as linear volume between min and max, ducking pauses
  instead of lowering, and the knock threshold is approximated: read the executable's curve,
  ducking and knock code and port them; `soundTests.zap` checks the volumes against the game's
- [ ] the lip track is not drawn, because the GPU heads have no morph targets yet: add morphs to
  the actor heads (`world/actorHead.zap`) and drive them from `skyrim/lip.zap`; a talking actor's
  mouth moves in a headless shot
