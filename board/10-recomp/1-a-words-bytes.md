---
size: M
---
# A word's bytes

(std, integer types). 44 `lo | (u16(hi) << 8)` and six functions of cpu.zap
that differ only by the wrap of the address (bank 0 or the 24 bits). On the integer types:
`u16.from(lo, hi)`, `u32.from(lo, hi)` (two u16), `u32.fromBytes(b0, b1, b2, b3)`; `w.low` and
`w.high` (each half as the half-width type, readable and assignable); `w.bytes()` a fixed array
of its bytes, little-endian. Lists already read a word at an offset (`u16.fromBytesAt`).
