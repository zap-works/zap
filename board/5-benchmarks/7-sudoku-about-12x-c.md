---
size: M
priority: P3
---
# sudoku runs under 1.00x of C's time

`tests/benchmarks/sudoku.zap` is at about 1.2x C's. Two code-generation costs are known: the outer
counters of `choose` are spilled (compiler-7), and in `sr[rr] += 1; if sr[rr] != 1` the panic stub
sits inline and the store-to-load forwarding is missed.

- [ ] move the panic stub out of line and keep the loaded value of `sr[rr]` in a register after the
  store; `zap test --only bench tests/benchmarks/sudoku.zap` shows the ratio fall
