---
size: M
---
# Skyrim's dialogue follows the game's camera and choice rules (milestone 11)

Dialogue code is `projects/skyrim/game/dialogue` and `game/talk.zap`; its tests are
`dialogueTests.zap` and `talkTests.zap`.

- [ ] turning the third person camera to a speaker further aside than `fDialogueSoftStopAngle3P` is
  the settings' reading, not measured: measure it in a capture of the game and fix the code to
  match
- [ ] the dialogue's info choice (0x1403ef230: conditions, random, say once) and the `DialogueItem`
  builder (0x1405ed830); the manager's walk around them is read. `game/dialogue/choose.zap` does it
  from the records and `dialogueTests.zap` holds, which is why this waited; read both functions and
  check `choose.zap` against them, fixing any difference the test then shows
