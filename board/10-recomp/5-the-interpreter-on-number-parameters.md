---
size: L
priority: P1
---
# The SNES interpreter's opcodes are written once with number parameters

`projects/recomp/snes/snes/interpret.zap` writes 1,280 functions, one per opcode for each widths
combination (`i{op}{widths}`), from the same translation as the games' code. A number parameter
(spec 3.6) can carry the widths as the bits e, m, x, so each opcode's body is written once, with no
new syntax: `fn lda<W u8>(at u32) u32`, each instance folded as literals would be, and the step's
match names the instances (`0x0A9 | 3 << 8: lda<3>(at)`). The translated code calls the same bodies
(`cpu.adc<W>(operand)`) where today it copies their text. The compiler is only checked: instances
of one body merge and `W & 2 != 0` folds in each instance. The Switch recompiler's forms
(`projects/recomp/switch/cpu/forms.zap`) follow.

- [ ] write each opcode's body once as a function with a number parameter for the widths (by hand
  or from the translator), and have the interpreter's step call the instances; the interpreter's
  function count falls well below 1,280 and `zap test --only size` shows the executable smaller
- [ ] have the translated code call the same bodies instead of copying their text; the SNES frame
  checks against Mesen 2 stay equal
- [ ] check the compiler merges the instances of one body and folds `W & 2 != 0` in each; a test
  in `tests/generics` shows it
- [ ] do the same for the Switch recompiler's forms
