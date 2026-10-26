---
size: XL
---
# The phone's window

An app runs on the emulator (`zap run --target android-x64`, spec
13.1), the engine's GPU in its window, on Vulkan 1.2 too (render passes and pipelines holding
their states where the extensions are missing; `swiftshader_indirect` is 1.2 without dynamic
rendering, extended dynamic state, push descriptors, descriptor indexing or drawIndirectCount;
engine/tests/examples.zap runs the examples there and with `vulkan=1.2` on the PC). Left:
- [ ] the examples under `-gpu host` (1.3 on the emulator): not run since the 1.2 paths landed;
- [ ] Vulkan 1.1: the compiler writes SPIR-V 1.5 (compiler/shader/spirv.zap), which needs 1.2; a
  1.1 device needs SPIR-V 1.3 (the entry points' interfaces only inputs and outputs);
- [ ] texture arrays without descriptor indexing: the sprite batch draws one texture a batch there,
  but recomp.switch's translated shaders read `Texture[]` and stop at `newProgram`;
- [ ] pre-rotation: the swapchain is made IDENTITY and the compositor turns it (device.zap's
  `turned`); currentTransform in the swapchain with the projection turned (the screen's passes,
  their viewport and scissor) saves the compositor's pass;
- [ ] an end that closes the activity (ANativeActivity_finish) instead of ending the process.
With step 5 it is what skyrim's milestone 15 (Android) stands on; the tile steps then decide its
frame rate.
