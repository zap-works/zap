---
size: L
---
# SNES: console memory uses narrow integer arrays and 2D tables

Many tables of the SNES recompiler's console (`projects/recomp/snes/console`) are `i64[]` holding
bytes or 15-bit colours, eight times the size they need: `lineMain`, `mainColor`, `subColor`,
`mainPrio`, `subPrio`, `tileEntry`, `tileChr`, `dspRegs`, `necRam` and the like. `u8[]` and `u16[]`
are possible now that `zap fmt` drops the redundant casts. Other tables are flat arrays indexed by
hand: `windowMask[layer * 256 + x]` (`console/compose.zap`), `tileChr[4 * columns * 4]`
(`console/fetch.zap`), and x64's `xmm[2 * r]` (`projects/recomp/x64/machine.zap`).

- [ ] change the byte and colour tables above to `u8[]` and `u16[]`; the frame checks against
  Mesen 2 (`zap test projects/recomp/snes`) stay unchanged and `zap test --only size` shows the
  recompiler's memory lower
- [ ] write the hand-indexed flat tables as fixed 2D arrays (`bool[6, 256]`, `a[layer, x]`, spec
  3.5), or `Grid<T>` where the size is the picture's; the same checks pass
