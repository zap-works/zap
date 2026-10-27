---
size: L
---
# SNES: SMW runs faster on the arm64 host

Super Mario World, recompiled, takes 8.1 ms a frame natively on the arm64 host (Neoverse N1) and
9.2 ms wide at frame 486 in Yoshi's Island 1; the user's S26 is about 3.3 times faster. The cost is
in the console's picture code (`projects/recomp/snes/console`), measured on the arm64 host.

- [ ] draw a line whole when nothing changes mid-line (`console/ppu.zap`, `backgrounds.zap`); the
  frame time falls
- [ ] fetch a column at a time instead of a dot (`console/fetch.zap`); the frame time falls
- [ ] fill the margins' pixels (widescreen, `console/wideDraw.zap`) a tile row at a time instead of
  a hook call each
- [ ] compute the frame hash only when a test asks for it; the frame time falls
- [ ] after these, SMW's frame time on the arm64 host is below 8.1 ms and the frame checks against
  Mesen 2 are unchanged
