---
size: L
priority: P2
---
# arm64 code as good as x64 code

benchmarks-2 lists the ratios this moves. Four gaps are left in the arm64 backend
(`compiler/targets/a64`); each is seen in the benchmark's arm64 ratio (`zap test --only bench`,
measured on the arm64 host):

- [ ] havlak's `numbering` and `predecessors` still spill with AArch64's own register set: `x0` to
  `x7` are used only for virtual registers no call or scratch-using instruction meets, so what lives
  across a call has `x19` to `x28` alone; widen that use, and havlak's ratio improves
- [ ] loops around an inner loop are not split in the register allocator; split them, same measure
- [ ] fasta's `drawRounds` loop makes its constants at each turn: its multiplier and addend (a
  `mov` each, since AArch64's `mul` and `add` take no such immediate) and `% im`'s magic number and
  divisor (a `mov` and a `movk` each, `a64DivByConstant` in `compiler/targets/a64/a64Divide.zap`);
  hoist them out of the loop, and fasta's ratio improves
- [ ] `writeRandom`'s `draws[at..]` window is written to its frame slot and read back each round;
  keep it in a register, same measure
