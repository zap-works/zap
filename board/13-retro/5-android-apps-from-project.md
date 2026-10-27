---
size: M
---
# DKC: the Android apps built from the project run on a phone

`zap run projects/dkc/main.zap --android dir` builds DKC's own apps, with DKC's widescreen in place
of the generic one that the earlier dkcg apps had. They have been built but never run on a phone.

- [ ] build the apps and run them on the zap37 emulator (`--target android-x64`) and on the user's
  S26 on a hidden display; the title and the first level draw and answer the touch controls
- [ ] the widescreen shows in the level (a shot wider than 256 pixels), and the frame time is
  below 16.6 ms
