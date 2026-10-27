---
size: M
blocked: set aside until a project or a measure asks for it
priority: P3
---
# Pure top-level constants are computed by the compiler

A top-level constant whose value calls only pure functions (no I/O, no `args`, no module variable)
would be computed by the compiler and stored in the executable's data, with no new syntax and no
macros. It was set aside: the tables that qualify cost well under a millisecond at start (mario's
`sineTable` and `arctanTable`, `std/digest`'s `crcTable`, excel1's opcode `matchers`, ragnarok's
JPEG `idctTable`), and storing them makes the executable larger (mario's by about 28 KB), against
the spec's goal of the smallest executable. It comes back when a table costs time worth measuring.

- [ ] evaluate a constant of pure calls at compile time (`compiler/fold`) and store it in the data
  section; a table that costs time at start (measured, not the five above) starts faster, and
  `zap test --only size` shows the executable growth stays within what the time saved is worth
