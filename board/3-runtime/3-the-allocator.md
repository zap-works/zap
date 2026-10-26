---
size: L
priority: P1
---
# The allocator

(runtime/core/coreAlloc.zap), each measured by `peak` and the allocation
benchmarks (binaryTrees, wordFreq, httpJson): big blocks rounded to a power of two (up to half
the commit idle) rounded to steps of 1.25x instead; the 2..4 KB classes losing 7 to 25% of a
16 KB page's tail given 64 KB pages; the 4 MB chunk committed whole at a thread's first
allocation reserved and committed 64 KB at a time, an emptied chunk decommitted; a cached big
block memset whole on reuse and `readFile`'s buffer zeroed before the read overwrites it, both
raw for callers that write the bytes; the map's table one block (header, marks, cells) instead
of three. Peaks are data still in use (the compiler's 154 MB loaded, 262 MB checked, 312 MB
generating code).
