---
size: L
blocked: set aside until a project or a measure asks for it
priority: P3
---
# One function runs on the CPU and on the GPU

Found by FireRed (`projects/firered`): its PPU layers are drawn on the CPU because a shader function
(`.gpu.zap`) cannot take a storage buffer as an argument, and CPU code cannot call a `.gpu.zap`
function. The same drawing code therefore has to be written twice, once per side.

- [ ] let a plain function take buffers (`u32[]`, a `Grid`) and be called from CPU code and from a
  kernel alike, the buffers passed as storage on the GPU (checker in `compiler/gpu/gpuCheck.zap`,
  shader lowering in `compiler/shader/lower.zap`); a test in `tests/` calls one such function from
  both sides and compares the results
- [ ] draw FireRed's PPU layers (`projects/firered/gba/ppu.zap`) on the GPU with the same function
  its CPU path runs; the frame hashes of `zap test projects/firered` stay the same
