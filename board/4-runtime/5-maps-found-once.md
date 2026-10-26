---
size: L
---
# Maps found once

lru is at Rust's 1.6x, findCell 46% of its time, memory-bound: Zap's table
holds 266k cells for 100k keys (a third full) where hashbrown's holds 131k (three quarters), and
`put` probes for the miss, then for the set, then the open cell. Each measured by A/B (no perf
counters on Windows): the probe set against hashbrown's; a power-of-two size with a mask instead
of `homeOf`'s multiply-high (then triangular probing); the integer hash one multiply; the removed
marks' rebuilds (3% of lru). lru's other half is benchmarks-3.
