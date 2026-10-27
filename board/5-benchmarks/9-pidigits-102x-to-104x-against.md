---
size: M
priority: P3
---
# pidigits runs under 1.00x of C over GMP

`tests/benchmarks/pidigits.zap` is at 1.02x to 1.04x against C using GMP, whose limb loops are
hand-written assembly.

- [ ] keep a scratch limb buffer between steps instead of making one each time; the benchmark's
  ratio falls
- [ ] make the 64x64-to-128-bit product a single `mul`. Commit 7c1d8ce7 of the bench1 branch, not in
  main, measures 0.87x with a multiword product's factor loaded into `rax` and the carries chained;
  once that commit lands, measure again and finish what it did not
