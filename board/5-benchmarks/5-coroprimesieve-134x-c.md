---
size: M
priority: P3
---
# coroPrimeSieve runs under 1.00x of C++'s time

`tests/benchmarks/coroPrimeSieve.zap` is at 1.34x C++'s. The cost is its division loop, about 14
instructions per prime against C++'s 5, and two hyperthreads sharing one core's divider.

- [ ] use `u32` in the Zap program (C++'s `int` is never negative), which drops the `-1` check;
  the instruction count per prime falls
- [ ] measure with each thread on a core of its own, so the shared divider does not decide;
  `zap test --only bench tests/benchmarks/coroPrimeSieve.zap` shows the ratio
