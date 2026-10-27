---
size: XL
---
# SNES: the SA-1 and SuperFX coprocessors are modelled

The recompiler (`projects/recomp/snes`) models the DSP-1 in Zap for every command
(`console/dsp1.zap`, `dsp1Commands.zap`; the firmware only as the test's oracle). DSP-2 to DSP-4
and ST010/011 run from the player's firmware (`tools/gather.zap` brings it into `rom/`). The SA-1
(Super Mario RPG: a second 65816 with its own translation) and the SuperFX are not modelled, so
games that use them do not run.

- [ ] SA-1: translate its second 65816 as another CPU of the recompiler with its memory map and
  registers; Super Mario RPG matches Mesen 2's frames for 20k frames (the player's ROM, never
  committed)
- [ ] SuperFX: model its processor and registers; a SuperFX game (Star Fox) matches Mesen 2's
  frames for 20k frames
