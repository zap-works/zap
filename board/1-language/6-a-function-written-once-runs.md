---
size: L
blocked: set aside until a project or a measure asks for it
---
# A function written once runs on the CPU and the GPU

Found by FireRed: its layers are drawn
on the CPU because a shader's function cannot take a storage buffer as an argument and CPU code
cannot call a `.gpu.zap` function. A plain function over buffers (`u32[]`, a `Grid`) callable
from CPU code and from a kernel alike, its buffers passed as storage on the GPU; then FireRed's
PPU draws its layers on the GPU with the same code its CPU path runs (frame hashes the same).
