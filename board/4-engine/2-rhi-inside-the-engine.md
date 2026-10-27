---
size: M
---
# The GPU layer lives inside the engine

`rhi/` is the engine's GPU layer (one device over Vulkan and Direct3D 12) and nothing outside
`engine/` imports it. The root should hold only the language, the engine and the projects, and the
two GPU names should be told apart: `std/gpu` (compute without a window) and the engine's layer.
This is a layout change that ships with its migration.

- [ ] move `rhi/` to `engine/gpu/` (`import engine.gpu`) and `std/gpu` to `std/compute`, updating
  every import
- [ ] update the places that name the dirs: the land's dir rules, spec 13's words for them, the note
  in `compiler/driver/modules.zap`, `AGENTS.md` and `engine/README.md`
- [ ] `zap test engine` passes and the projects' shots (`zap test --only shots`) are unchanged,
  which shows nothing else moved
