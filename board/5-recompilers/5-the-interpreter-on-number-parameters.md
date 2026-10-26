---
size: L
---
# The interpreter on number parameters, not texts

(project change). interpret.zap
writes 1,280 functions, one an opcode in each widths (`i{op}{widths}`), from the same translation
as the games' code. No new syntax: a number parameter (spec 3.6) carries the widths as the bits
e, m, x, `fn lda<W u8>(at u32) u32`, each instance folded as literals would be, and the step's
match names the instances (`0x0A9 | 3 << 8: lda<3>(at)`); each opcode's body is written once, by
hand or by the translator, and the translated code calls the same bodies (`cpu.adc<W>(operand)`)
where today it copies their text. The compiler is only checked: instances of one body merge and
`W & 2 != 0` folds in each instance. The Switch recompiler's forms (cpu/forms.zap) follow.
Measured by the interpreter's function count and the exe size.
