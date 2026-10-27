---
size: M
priority: P2
---
# The map's table in one block

(runtime/core/map.zap, textMap.zap) a map's table is three blocks (the header, the marks, the
cells); one block with the three laid out in it saves two allocations per map and one big block
less per large table. Measured by `peak` and wordFreq.

Also from the allocator's card: a byte list grown past 4096 bytes (`listGrowTo`) zeroes its whole
cached block before the copy overwrites its first part; only the part past the copy needs it.
