---
size: L
priority: P3
---
# havlak runs under 1.00x of C's time

`tests/benchmarks/havlak.zap` measures 1.11x to 1.25x C's (1.21x at `--full`), varying with its
large lists made on each run. The causes found: loop invariants hoisted and then spilled in
`predecessors`, bounds checks, list headers read through memory, a growth call that reloads every
held header, values split at loop boundaries, and arm64's allocation across calls (compiler-7).

- [ ] apply `irSplitLoop` (`compiler/optimize/irLoopSplit.zap`, which handles vectors only) to
  integers that live across calls; havlak's ratio falls and the executable stays correct
  (`zap test tests/benchmarks`)
- [ ] write `listPushRaw` with the growth in a cold call that returns the header, so the caller
  does not reload every held header after it; same measure
