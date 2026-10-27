---
size: L
priority: P2
---
# A map lookup touches memory once and less of it

The `lru` benchmark runs at 1.6 times Rust's time and spends 46% of it in `findCell`; it is
memory-bound. Zap's table holds 266k cells for 100k keys (a third full) where Rust's hashbrown
holds 131k (three quarters full), and `put` probes for the miss, then for the set, then for the
open cell. There are no perf counters on Windows, so each idea is measured by A/B on the
benchmark. The code is `runtime/core/map.zap`. The rest of lru's gap is benchmarks-3.

- [ ] make `put` probe once, not three times (miss, set, open cell); `lru`'s time falls
- [ ] probe like hashbrown (grouped control bytes), so a table of 100k keys holds near 131k cells
  instead of 266k; `lru`'s memory falls
- [ ] use a power-of-two size with a mask instead of `homeOf`'s multiply-high, then triangular
  probing; `lru`'s time falls
- [ ] make the integer hash one multiply; `lru`'s time falls
- [ ] make the rebuilds that clean removed marks cheaper (3% of lru); `lru`'s time falls
