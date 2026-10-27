---
size: L
blocked: ask the user how the real game is to be played scripted for the comparison (the repository's rules forbid driving the real game's window), or whether a recorded run of the game exists
---
# A scripted run is compared by state between the game and ours

Today the project (`projects/skyrim`) compares pictures only. The aim is one scripted run of
inputs played in the real game and in our port and compared by game state (positions, stats,
inventory), not by frames. The unclear part is how to play the real game scripted without driving
its window.

- [ ] choose a short sequence in the inn (walk, take an item, talk to Orgnar) and record the real
  game's state at its steps from a source the user names; save it under `projects/skyrim/reference`
  (versioned, without game data)
- [ ] play the same inputs in `main.zap` headless and compare the state step by step; a test
  (`walkTests.zap` style) fails on any difference
