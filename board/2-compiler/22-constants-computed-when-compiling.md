---
size: M
blocked: set aside until a project or a measure asks for it
priority: P3
---
# Constants computed when compiling

A top-level constant whose value calls only pure functions
(no I/O, no `args`, no module variable) computed by the compiler and stored in the executable's
data; no new syntax, no macros. The tables that qualify cost well under a millisecond at start
(mario's `sineTable` and `arctanTable`, std/digest's `crcTable`, excel1's opcode `matchers`,
ragnarok's JPEG `idctTable`) and stored in the executable make it larger (mario by about 28 KB),
against the spec's smallest executable: it comes back when a table costs time worth measuring.
