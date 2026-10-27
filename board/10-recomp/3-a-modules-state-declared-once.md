---
size: L
---
# A module's state is declared once and the compiler derives its save and reset

Each part of the SNES console lists its variables three times: declared, zeroed in
`<part>PowerOn()`, and written and read in `<part>Fields(f)` (29 such functions, 156 lines of
`x = f.int(x)`). A language feature should remove the repetition: a `state:` block of a module
holds module variables as `mut` declarations do (the names stay bare in the module's code), and the
compiler derives for it `reset()`, `toBytes()` and `fromBytes()` (spec 7.7's layout, nested values
and lists included), reached as the module's `state`: `console.state.reset()`,
`console.state = ConsoleState.fromBytes(r)`. What a load rebuilds (line buffers, fetched tiles)
stays outside the block. A save state in memory then is a copy of the value (rewind, netplay).

- [ ] add the `state:` block to the compiler and describe it in the spec (module variables,
  `reset()`, `toBytes()`, `fromBytes()`); a test in `tests/` saves, resets and restores a module
  with nested values and lists
- [ ] use it in the SNES console (`projects/recomp/snes/console`): remove the `PowerOn` and
  `Fields` functions and `saveState.zap`'s `StateFile`; `projects/recomp/snes/tests/saveStates.zap`
  passes and the frame checks stay equal
