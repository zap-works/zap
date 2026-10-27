---
size: M
priority: P3
---
# brainfudge runs under 1.00x C++

`tests/benchmarks/brainfudge.zap` was 1.06x C++'s time before `pc < ops.len` and `ops[pc]` became
one comparison (now 0.952x on arm64, 0.92x in bench1). What is left are the bounds checks of
`tape[head]` and `head += arg`, which C++'s program does not make and no range or guard proves.
mandelbrot at 0.97x is at the multiply ports' limit, like its rivals, and needs nothing.

- [ ] let the compiler prove or hoist the `tape[head]` and `head += arg` checks (or find a form of
  the program that makes them provable without changing what it computes); brainfudge's ratio in
  `zap test --only bench tests/benchmarks/brainfudge.zap` falls below 0.952x on arm64
