---
size: L
blocked: set aside
priority: P3
---
# Excel: code copied into RAM at run time is recompiled

In the Excel 1 port (`projects/excel1`), the p-code dispatcher and the code Excel copies into RAM
before running it stay interpreted: 56% of the instructions of the About run. The aim is to
recompile code copied at run time, identified by the bytes it was copied from, and to compare the
recompiled run with the interpreted one.

- [ ] recognize a block of code copied into RAM by the bytes it came from (a hash of the source
  bytes), and translate it ahead of time as the other code is (`recomp.zap`, `m68k`)
- [ ] run the About scenario both ways; the screen and the registers are equal and the
  interpreted share of instructions falls below 56% (measure and write the new share)
