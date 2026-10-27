---
needs: [switch-5]
size: L
priority: P1
---
# The player controls Link in the Shrine, to the Sheikah Slate and out of the door

After the waking (switch-5), the player moves Link by touch and by pad in the Shrine, picks up the
Sheikah Slate and leaves through the door, which ends slice 1. Each is made right on Windows
headless first (shots against the oracle, Eden), then on the zap37 Android emulator.

- [ ] on Windows headless, a scripted pad run walks Link to the Sheikah Slate, takes it and goes
  out of the door; shots at the steps equal Eden's
- [ ] the same by touch controls (`controls/pad.zap`, the overlay in `projects/recomp/touch`)
- [ ] the same run on the zap37 emulator (`main.zap --target android-x64 --android <dir>`) reaches
  the door
