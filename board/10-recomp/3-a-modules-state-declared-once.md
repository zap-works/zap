---
size: L
---
# A module's state declared once

(compiler). Each part of the console lists its variables three
times: declared, zeroed in `<part>PowerOn()` and written and read in `<part>Fields(f)` (29 such
functions, 156 lines of `x = f.int(x)`). A `state:` block of a module holds module variables as
`mut` declarations do (the names stay bare in the module's code), and the compiler derives for it
`reset()`, `toBytes()` and `fromBytes()` (spec 7.7's layout, nested values and lists included),
reached as the module's `state`: `console.state.reset()`, `console.state =
ConsoleState.fromBytes(r)`. What a load rebuilds (line buffers, fetched tiles) stays outside the
block. saveState.zap's StateFile goes; a save state in memory is a copy of the value (rewind,
netplay).
