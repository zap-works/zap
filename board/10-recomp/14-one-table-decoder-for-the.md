---
size: M
blocked: set aside until a project or a measure asks for it
priority: P3
---
# One table decoder serves the recompilers

Three CPU decoders each read a text table of bits and templates with a decoder of their own:
Excel's 68000 (`projects/excel1/m68k`), and FireRed's ARM and Thumb (`projects/firered`). One
decoder, placed in the engine or the std, should read all three tables.

- [ ] write the shared table decoder (in `std` or `engine`) and have the three tables use it; each
  project's tests pass with the same results (`zap test projects/excel1 projects/firered`)
- [ ] delete the three private decoders; `rg` finds no second decoder of a bit table
