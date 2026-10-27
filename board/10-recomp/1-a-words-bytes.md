---
size: M
---
# Integer types build and split words from bytes

The recompilers write `lo | (u16(hi) << 8)` 44 times, and `cpu.zap` of the SNES
(`projects/recomp/snes/cpu/cpu.zap`) has six functions that differ only by the wrap of the address
(bank 0 or the 24 bits). The std's integer types (`runtime/core`, `spec/numbers.zap`) should do it.
Lists already read a word at an offset (`u16.fromBytesAt`).

- [ ] add `u16.from(lo, hi)`, `u32.from(lo, hi)` (two `u16`) and `u32.fromBytes(b0, b1, b2, b3)`;
  a test in `tests/numbers` shows each result
- [ ] add `w.low` and `w.high` (each half as the half-width type, readable and assignable) and
  `w.bytes()` (a fixed array of its bytes, little-endian); a test shows each, and the assignment
- [ ] use them in the recompilers: the 44 `lo | (u16(hi) << 8)` are gone and the six address
  functions of `cpu.zap` become one taking the wrap as a parameter; the SNES frame checks stay equal
- [ ] describe them in `spec/numbers.zap`
