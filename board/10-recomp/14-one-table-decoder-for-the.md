---
size: M
blocked: set aside until a project or a measure asks for it
---
# One table decoder for the recompilers

Excel's 68000 (`excel1/m68k`) and FireRed's ARM and
Thumb (`firered`) are each a text table of bits and templates read by a decoder of their own:
one decoder, in the engine or the std, reads all three tables.
