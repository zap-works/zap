---
size: L
priority: P2
---
# `zap fmt` and the lint agree and fix everything in one run

The formatter (`zap fmt`) and the lint (`zap test --only check`) are in `compiler/tools/fmt`. Five
mismatches were met, each worked around by hand where it showed.

- [ ] `zap fmt <dir>` does not reach a fixed point in one run: `zap test --only check` still listed
  lint notes (`fixed(c, ` should be `c.fixed(`, a type dropped) that a second and third run
  applied, on `projects/recomp/switch` (a dir of several modules importing each other). Make one
  run apply them all; a second `zap fmt` changes nothing
- [ ] it does not apply some notes: `addExact(x.exactOf(), y.exactOf())` noted as
  `x.exactOf().addExact(`; the forms only types tell to write ("zap fmt applies it"); and
  `x = f() ?? return none` noted as `x = try f()`, left in place by three runs. Apply them
- [ ] the lint notes `.copy()` as droppable in a lambda's result, e.g.
  `romFiles((at, n): rom[at..at + n].copy())` with `read fn(i64, i64) u8[]`, and `zap fmt` drops
  it; the program then fails in the callee (`head = read(0, 0x50)`: move-of-part), so `verifyNotes`
  (`compiler/tools/fmt/canon.zap`) does not take the note back. Stop noting it, or take the note
  back when the program fails
- [ ] the lint's import note flips with the set of entry files checked together: `zap test
  engine/audio --only check` says `import engine.audio.mdct` in `engine/audio/xwma/window.zap` is
  to be dropped, while a land's `check engine projects/recomp` on the file without it says it is to
  be added. The file uses `mdct.`; a judgment of an import must not depend on the other entries
  (`compiler/tools/fmt/imports.zap`). Both runs give the same answer
- [ ] about 56 `?? return none` and 6 `?? fail(error)` stay in files the lint never sees, since no
  check reaches them on Windows (`engine/post`, `engine/scene`, `engine/render`, `engine/swf`,
  `rhi/d3d12`, `std/gpu`, the Linux dirs, `tests/programs/parts`): make a check reach each, then
  `zap fmt .` again; `rg "\?\? (return none|fail)"` finds none
