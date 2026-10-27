---
size: M
---
# Skyrim runs at a frame rate above the game's on Windows (milestone 13)

`projects/skyrim` rebuilds the Sleeping Giant Inn in Zap; its aim after being frame-exact is to run
faster than the game does on this PC.

- [ ] measure the game's frame rate in the same cell on this PC (the unlocked rate, from a capture
  tool or the game's own counter) and write the number in `projects/skyrim/README.md`
- [ ] measure `projects/skyrim/main.zap` in the same cell and pose, unlocked (vsync off), and make
  it faster than the game's number: profile with `ZAP_RUN=gputime` and fix the costliest pass
  until the rate is above it
