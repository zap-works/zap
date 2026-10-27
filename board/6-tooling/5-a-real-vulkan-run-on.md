---
size: M
priority: P2
blocked: ask the user which machine with a Linux Vulkan driver (libvulkan) may be used for the run
---
# The Vulkan code is run for real on Linux

No machine available here has `libvulkan`: neither the container nor the arm64 host has it. The
loaded libraries' calls and callbacks are tested with libc instead (`tests/io/libThreads.zap`), so
the Linux path of the Vulkan backend (`rhi/vulkan`, `rhi/core/linux`) has never run against a real
driver.

- [ ] install or find a Linux machine with `libvulkan` (a software driver such as lavapipe is
  enough) and record in this card how it is reached
- [ ] run an engine example there (`engine/tests/examples.zap`); it draws and its shot equals the
  PC's, or the differences are listed
