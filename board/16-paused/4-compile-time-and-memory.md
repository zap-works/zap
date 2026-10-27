---
size: L
blocked: set aside
priority: P3
---
# FireRed: the generated code builds in less time and memory

The FireRed port's generated code (`projects/firered/recomp/firered.zap`, translated from the GBA
ROM) takes about 100 s and 2.3 GB to build cold.

- [ ] find with the compiler's phase timings and `ZAP_RUN=memstats` what dominates (a few huge
  functions, or the number of functions), and write it here
- [ ] change the translator's output or the compiler (see compiler-1 and compiler-2) so the cold
  build takes well under 100 s and under 2.3 GB; `zap test --only size` shows the numbers
