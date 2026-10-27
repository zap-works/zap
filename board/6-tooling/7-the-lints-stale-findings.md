---
size: S
check: zap test engine --only tests, then zap test engine --only check passes
priority: P0
---
# The lint no longer keeps stale findings from earlier runs

A `zap test engine --only tests` (or `--only build,check,tests`) run in a warm checkout writes
findings into `build/cache/lint` that a later `--only check` reports: "`import rhi` is ``" on
`engine/window.zap`, `render/indirect.zap`, `render/target.zap` and `scene/mesh.zap`, and "`import
image` is ``" on `engine/app.zap`. Those imports are needed (`window.zap` reaches rhi through
`gpu.waitIdle()`, `app.zap` reaches image through `.savePng`). It failed a land once. The likely
path is `compiler/tools/fmt/imports.zap`: a removal note for a method-only import that
`verifyNotes` accepts because another file of the module imports the same module, written by a run
that does not evaluate the lint. The workaround is to delete those files' entries in
`build/cache/lint`.

- [ ] reproduce: run `zap test engine --only tests`, then `zap test engine --only check`, in a warm
  checkout, and see the false notes
- [ ] fix the path that writes the false removal note (or stop `--only check` from trusting it);
  the same two commands now pass with no manual cache deletion
