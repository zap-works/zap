---
size: L
priority: P2
---
# `zap fmt` and the lint

(each written by hand where met):
- [ ] `zap fmt <dir>` does not reach a fixed point in one run: `zap test --only check` still listed
  lint notes (`fixed(c, ` is `c.fixed(`, a type dropped) that a second and third run applied
  (projects/recomp/switch, a dir of several modules importing each other).
- [ ] It does not apply: `addExact(x.exactOf(), y.exactOf())` noted as `x.exactOf().addExact(`; the
  forms only types tell to write ("zap fmt applies it"); `x = f() ?? return none` noted as
  `x = try f()`, left by three runs.
- [ ] The lint notes `.copy()` as droppable in a lambda's result, `romFiles((at, n): rom[at..at +
  n].copy())` with `read fn(i64, i64) u8[]`, and `zap fmt` drops it; the program then fails in
  the callee (`head = read(0, 0x50)`: move-of-part), so verifyNotes does not take the note back.
- [ ] The lint's import form flips with the set of entry files checked together: `zap test
  engine/audio --only check` says `import engine.audio.mdct` in engine/audio/xwma/window.zap is
  to be dropped, a land's `check engine projects/recomp` on the file without it says it is to be
  added. The file uses `mdct.`; a judgment of an import must not depend on the other entries.
- [ ] About 56 `?? return none` and 6 `?? fail(error)` stay in files the lint never sees, since no
  check reaches them on Windows (engine/post, scene, render and swf, rhi/d3d12, std/gpu, the
  Linux dirs, tests/programs/parts): each reached by a check, then `zap fmt .` again.
