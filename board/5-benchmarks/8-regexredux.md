---
needs: [runtime-2]
size: L
priority: P3
---
# regexRedux runs under 1.00x of Rust on cycles

This needs runtime-2. `tests/benchmarks/regexRedux.zap` is at 0.89x Rust's time, 1.02x its memory
and 1.66x its cycles. The counts scan at 1.4 ns a byte on every core, where Rust's Teddy (a SIMD
literal matcher) takes 0.6. The substitutions are the critical path and run on one core: about 55
ns a match, spent in the call chain of a locate (skip, anchored scan, two builder appends). The
code is `std/regex`.

- [ ] scan for the pattern's first bytes or longest literal with a vector scan before running the
  automaton; the counts' ns per byte falls toward 0.6
- [ ] add a byte shift on `Simd<32, u8>` for a nibble-table prefilter (the Teddy method)
- [ ] do the five substitutions in one pass; the substitution phase's time falls
- [ ] after these, the benchmark's cycles ratio is under 1.00x
