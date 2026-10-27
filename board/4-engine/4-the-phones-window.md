---
size: XL
priority: P1
branch: engine-4
by: 76e2e166-89bc-415b-aaa9-a83df0879b58
---
# The engine's GPU runs in a phone's window on every Vulkan level

An app runs on the Android emulator (`zap run --target android-x64`, spec 13.1) with the engine's
GPU in its window, also on Vulkan 1.2 (render passes and pipelines holding their states where the
extensions are missing; the `swiftshader_indirect` emulator is 1.2 without dynamic rendering,
extended dynamic state, push descriptors, descriptor indexing or drawIndirectCount).
`engine/tests/examples.zap` runs the examples there and with `vulkan=1.2` on the PC. This is what
skyrim's milestone 15 (Android) stands on, together with engine-5; the tile steps then decide its
frame rate. Left:

- [ ] run the examples under `-gpu host` (Vulkan 1.3 on the emulator); they have not run since the
  1.2 paths landed. `engine/tests/examplesAndroid.zap` passes
- [ ] support Vulkan 1.1: the compiler writes SPIR-V 1.5 (`compiler/shader/spirv.zap`), which needs
  1.2; a 1.1 device needs SPIR-V 1.3 (the entry points' interfaces only inputs and outputs). A
  shader test builds SPIR-V 1.3 and validates
- [ ] texture arrays without descriptor indexing: the sprite batch draws one texture per batch
  there, but recomp.switch's translated shaders read `Texture[]` and stop at `newProgram`; make
  them run, and a test draws two textures through a `Texture[]` on the 1.2 emulator
- [ ] pre-rotation: the swapchain is made IDENTITY and the compositor turns it (`turned` in
  `rhi/core/device.zap`). Set `currentTransform` in the swapchain and turn the projection instead
  (the screen's passes, their viewport and scissor), saving the compositor's pass; a rotated
  emulator shows the picture upright
- [ ] end the activity with `ANativeActivity_finish` instead of ending the process; the app closes
  to the launcher
