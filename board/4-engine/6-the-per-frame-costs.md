---
size: L
---
# The engine's per-frame costs fall

Each item is measured by frame time with `projects/examples/stress` (`--bench N`,
`--case boxes|sprites|crowd`, `--unsorted`), or on the phone where the fragment shader is the
bottleneck.

- [ ] `readBuffer` and `readStorage` call `waitIdle`; read back through a ring one frame late once a
  program reads back each frame; the stress case with a readback shows the stall gone
- [ ] HDR and MSAA targets in RGBA16F: try R11G11B10F, a transient MSAA target and reverse-Z; frame
  time or memory falls, and the shots stay the same or are looked at and updated
- [ ] lights by cluster: skyrim's `paramsOf` sends every light and each fragment walks `lightCount`;
  walk only the cluster's lights
- [ ] shadows of lights that do not move are made once (the inn's, when skyrim's milestone 5 adds
  them)
- [ ] an `f16` type in the shaders' language for colours, normals and uvs (Mali's `mediump` doubles
  the throughput): add it to `compiler/shader` and use it in the engine's shaders
- [ ] `Frames` takes a target rate and paces (vsync, `VK_GOOGLE_display_timing`) so a phone does not
  heat and lose its clock
