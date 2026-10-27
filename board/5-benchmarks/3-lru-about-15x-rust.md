---
needs: [runtime-5]
size: M
priority: P3
---
# lru runs under 1.00x of Rust's time

This needs runtime-5. `tests/benchmarks/lru.zap` runs at about 1.5x Rust. Its `findCell` takes 56
instructions on a miss against Rust's 20, the list headers and locals are spilled (compiler-7), and
the map's probes are the other cost (runtime-5).

- [ ] after runtime-5 and compiler-7, look at `findCell`'s instructions again and cut what is left
  (the spills, the header reloads); `zap test --only bench tests/benchmarks/lru.zap` shows the
  ratio under 1.00x
