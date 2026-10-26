---
size: M
priority: P1
---
# A real Vulkan run on Linux

no machine here has libvulkan (the container and the arm64 host
lack it); the loaded libraries' calls and callbacks are tested with libc (tests/io/libThreads.zap).
