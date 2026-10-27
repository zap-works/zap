---
size: M
priority: P2
---
# A map's table lives in one memory block

A map's table is three blocks today (the header, the marks and the cells; `runtime/core/map.zap`
and `textMap.zap`). Laying the three out in one block saves two allocations per map and one big
block fewer per large table. A related waste from the allocator's card: a byte list grown past 4096
bytes (`listGrowTo`) zeroes its whole cached block before the copy overwrites its first part, and
only the part past the copy needs zeroing.

- [ ] lay out a map's header, marks and cells in one block in `runtime/core/map.zap` and
  `textMap.zap`; the `peak` and `wordFreq` benchmarks (`zap test --only bench`) show less memory
  or time, and `zap test runtime` passes
- [ ] in `listGrowTo`, zero only the part of the cached block past the copied bytes; a byte-list
  growth benchmark shows the saved zeroing
