---
size: M
priority: P2
---
# Storage images run on the emulator's SwiftShader

`projects/examples/images` (storage images read, written and changed by atomics in compute
stages) crashes the Android emulator itself when its GPU is SwiftShader's Vulkan 1.2
(`-gpu swiftshader_indirect`): the app hangs, the emulator's log says `bad color buffer handle`
and qemu ends. It runs on the host GPU (`-gpu host`) and on the PC, also with `vulkan=1.2`. It
happens with the compiler's SPIR-V 1.5 and 1.3 alike, so it is the program's use of storage
images (formatless reads and writes, image atomics, `rhi/vulkan/` descriptors of kind storage
image) that SwiftShader through gfxstream cannot take. Until then `engine/tests/examplesAndroid.zap`
cannot pass on that emulator, which also kills every test after it.

- [ ] find the call that crashes it (cut `projects/examples/images/main.zap` down step by step on
  `-gpu swiftshader_indirect`; the emulator started outside the agent's process tree) and avoid it
  in `rhi/vulkan/` where the device lacks what it needs, or make the RHI refuse it with a message
  (then the example says it is skipped there). `zap test engine/tests/examplesAndroid.zap` passes
  on `-gpu swiftshader_indirect`
- [ ] the file runs within the test's limit (180 s on the clock) on SwiftShader, where each example
  takes 3 to 25 s: split the list into two files if it does not

check: `zap test engine/tests/examplesAndroid.zap` on both emulator GPUs
