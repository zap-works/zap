---
size: L
---
# SMW: Mode 7 boss rooms and the title's demo level are widescreen

The widescreen judge (`projects/smw/wide/scene.zap`) draws only normal levels wide: it centres
anything in Mode 7 (the boss rooms) and the demo level the title plays, as the native frame on
black.

- [ ] widen a Mode 7 boss room: decode the Mode 7 floor beyond the native edge (the generic
  `console/mode7.zap` of `projects/recomp/snes`) and let the judge accept it; a wide shot of a
  boss room shows the margins
- [ ] widen the title's demo level, which scrolls like a level but is a different game mode; a wide
  shot of it shows the margins
- [ ] the native-logic route tests still match Mesen 2
