---
size: S
check: zap test engine --only tests, then zap test engine --only check passes
priority: P0
---
# The lint's stale findings

A `zap test engine --only tests` (or `--only build,check,tests`) run in a warm checkout writes
findings into build/cache/lint that a later `--only check` reports: "`import rhi` is ``" on
engine/window.zap, render/indirect.zap, render/target.zap, scene/mesh.zap and "`import image` is
``" on engine/app.zap, imports those files need (window.zap reaches rhi through gpu.waitIdle(),
app.zap image through .savePng). It failed a land once. The likely path is
compiler/tools/fmt/imports.zap: a removal note for a method-only import that verifyNotes accepts
because another file of the module imports the same module, written by a run that does not
evaluate the lint. Workaround: delete those files' entries in build/cache/lint.
