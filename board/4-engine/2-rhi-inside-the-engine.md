---
size: M
---
# rhi inside the engine

`rhi/` is the engine's GPU layer (one device over Vulkan and Direct3D
12) and nothing outside engine/ imports it. It moves to `engine/gpu/` (`import engine.gpu`), so
the root holds the language, the engine and the projects; `std/gpu`, compute without a window,
becomes `std/compute` so the two names tell them apart. A layout change with its migration in
one: the imports, the land's dir rules and spec 13's words for them, compiler/driver/modules.zap's
note, AGENTS.md and the engine's README; `zap test engine` and the projects' shots prove nothing
else moved.
