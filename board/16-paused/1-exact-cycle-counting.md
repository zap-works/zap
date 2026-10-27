---
size: L
blocked: set aside
priority: P3
---
# FireRed: cycle counting is exact

The FireRed port (`projects/firered`, a recompilation of the GBA game) counts the CPU's cycles, but
the IWRAM's sound buffer and the frame counters still differ from mGBA's, so cycle-sensitive code
diverges.

- [ ] find which instructions or memory accesses the port times differently from mGBA (wait states
  of the bus, DMA, prefetch) by comparing the IWRAM sound buffer and the frame counters over the
  same inputs
- [ ] fix the timing in `projects/firered/cpu` and `gba/timing.zap` until those IWRAM regions equal
  mGBA's at every frame of the test route (`zap test projects/firered`)
