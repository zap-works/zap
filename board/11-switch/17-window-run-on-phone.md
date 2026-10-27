---
size: S
priority: P0
branch: switch-17
by: 79ab913f-3608-4a1a-967c-5a7876badbd2
---
# The window run on a phone

The touch controls, the finger ids and the controls menu of `projects/recomp/switch/frontend/screen.zap`
are tested without a window only (`zap test projects/recomp/touch projects/recomp/switch/controls`).
The window run itself is not tried on a phone: the overlay is drawn on the CPU image
(`projects/recomp/touch/touch.zap`'s `compose`), not on the GPU picture the renderer makes.

- [x] Build the program for the emulator (`zap build --target android-x64 projects/recomp/switch/main.zap`),
  run it on zap37 and see the controls over the picture; the two fingers (stick and a button) held
  at once show both.
- [ ] Draw the controls over the renderer's GPU picture when that is what the window shows, so the
  frame the phone presents carries them (a shot with `ZAP_RUN` `headless` shows them).
