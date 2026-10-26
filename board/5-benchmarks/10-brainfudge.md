---
size: M
priority: P3
---
# brainfudge

was 1.06x C++'s before `pc < ops.len` and `ops[pc]` became one comparison (0.952x
on arm64, 0.92x in bench1): left are the checks of `tape[head]` and `head += arg`, which C++'s
program does not make and no range or guard proves. mandelbrot 0.97x is at the multiply ports'
limit like its rivals.
