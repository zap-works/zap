---
size: L
---
# SNES: Memory: narrow arrays and 2D tables

Memory: lineMain, mainColor, subColor, mainPrio, subPrio, tileEntry, tileChr, dspRegs, necRam
and the like are `i64[]` holding bytes and 15-bit colours (eight times their size): `u8[]` and
`u16[]` now that fmt drops the redundant casts. Flat tables indexed by hand
(`windowMask[layer * 256 + x]`, `tileChr[4 * columns * 4]`, x64's `xmm[2 * r]`) as fixed
arrays of two dimensions (`bool[6, 256]`, `a[layer, x]`, spec 3.5), or `Grid<T>` where the
size is the picture's.
