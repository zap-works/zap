---
size: L
priority: P3
---
# havlak 1.11x to 1.25x C's

(1.21x at `--full`), varying with its large lists made each run:
the invariants hoisted and then spilled in `predecessors`, bounds checks, list headers read
through memory, a growth call reloading every held header, values split at loop boundaries,
arm64's allocation across calls (compiler-7). Ideas: `irSplitLoop` (irLoopSplit.zap, vectors
only) for integers live across calls; `listPushRaw` with the growth in a cold call returning the
header.
